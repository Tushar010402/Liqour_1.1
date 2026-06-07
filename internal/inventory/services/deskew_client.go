package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"
)

// deskewClient wraps cv-sidecar's POST /deskew endpoint. Used by the
// Textract pipeline to auto-correct tilted phone-shot bills BEFORE the
// AnalyzeDocument call — Textract's table-detection model is intolerant
// of even small (3-5°) tilts which collapse 41-row dense pages to 7
// usable rows on chhotu's real submissions.
//
// Best-effort: when the sidecar is unavailable / times out / returns an
// error, the original image bytes pass through unchanged. We never fail
// extraction because deskew failed.
type deskewClient struct {
	url     string
	client  *http.Client
	enabled bool
}

func newDeskewClient() *deskewClient {
	url := strings.TrimSpace(os.Getenv("CV_SIDECAR_URL"))
	if url == "" {
		url = "http://cv-sidecar:8000"
	}
	timeoutMs := 3000
	if v := os.Getenv("DESKEW_TIMEOUT_MS"); v != "" {
		fmt.Sscanf(v, "%d", &timeoutMs)
	}
	// Default ON for v1.0.193+. Set TEXTRACT_DESKEW=0 to disable per-tenant
	// or globally if a regression appears.
	enabled := true
	if v := os.Getenv("TEXTRACT_DESKEW"); v == "0" || strings.EqualFold(v, "false") || strings.EqualFold(v, "off") {
		enabled = false
	}
	return &deskewClient{
		url:     url,
		client:  &http.Client{Timeout: time.Duration(timeoutMs) * time.Millisecond},
		enabled: enabled,
	}
}

type deskewResponse struct {
	ImageBase64      string  `json:"image_base64"`
	RotationAngleDeg float64 `json:"rotation_angle_deg"`
	Applied          bool    `json:"applied"`
	Reason           string  `json:"reason,omitempty"`
}

// Deskew posts the image to cv-sidecar and returns either the rotated
// bytes (when the sidecar applied a rotation > 0.5°) or the original
// bytes unchanged (no-op cases). Errors are swallowed and the original
// bytes returned — caller is opaque to deskew failures.
func (c *deskewClient) Deskew(ctx context.Context, raw []byte) []byte {
	if c == nil || !c.enabled || len(raw) == 0 {
		return raw
	}

	body := &bytes.Buffer{}
	mw := multipart.NewWriter(body)
	fw, err := mw.CreateFormFile("file", "page.jpg")
	if err != nil {
		return raw
	}
	if _, err := fw.Write(raw); err != nil {
		return raw
	}
	mw.Close()

	url := strings.TrimRight(c.url, "/") + "/deskew"
	req, err := http.NewRequestWithContext(ctx, "POST", url, body)
	if err != nil {
		return raw
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		return raw
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return raw
	}
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return raw
	}
	var dr deskewResponse
	if err := json.Unmarshal(respBody, &dr); err != nil {
		return raw
	}
	if !dr.Applied || dr.ImageBase64 == "" {
		return raw
	}
	// Decode the base64 payload. cv-sidecar returns plain base64 (no data
	// URL prefix) per its endpoint spec.
	deskewed, err := base64DecodeString(dr.ImageBase64)
	if err != nil || len(deskewed) == 0 {
		return raw
	}
	return deskewed
}

// base64DecodeString accepts both standard and url-safe base64 (cv-sidecar
// uses standard padding). Returns ([], err) on any decode error so the
// Deskew caller falls back to the raw bytes.
func base64DecodeString(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(strings.TrimSpace(s))
}
