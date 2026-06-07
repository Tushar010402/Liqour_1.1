package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

// v1.0.133-r10 — CV sidecar HTTP client.
//
// Calls the Python OpenCV sidecar (cv-sidecar service) to get a per-row
// blank/filled classification BEFORE the page-level Claude extraction.
// The result is converted into a prompt-hint so Claude is told exactly
// which serial numbers to skip — anti-hallucination cross-check.
//
// Best-effort: any failure (timeout, bad JSON, non-2xx) returns "" and the
// extraction proceeds without the hint. The sidecar must NEVER block the
// happy path.
//
// Env knobs:
//   CV_SIDECAR_URL                default http://cv-sidecar:8099
//   CV_SIDECAR_ENABLED            "1" (on) or "0" (off, default off)
//   CV_SIDECAR_TIMEOUT_MS         default 4000
//   CV_SIDECAR_MIN_BLANK_TO_HINT  default 2 (skip hint for sparse signals)

type cvSidecarRow struct {
	RowNumber int     `json:"row_number"`
	YTop      int     `json:"y_top"`
	YBottom   int     `json:"y_bottom"`
	IsBlank   bool    `json:"is_blank"`
	FillRatio float64 `json:"fill_ratio"`
}

type cvSidecarResponse struct {
	PageSizePx []int          `json:"page_size_px"`
	Rows       []cvSidecarRow `json:"rows"`
	Diag       map[string]any `json:"diag"`
}

// CVSidecarColumns is the per-page column-x layout returned by
// /detect-columns and /detect-grid. All x are absolute pixels left→right.
// Ok=false means detection failed and the caller should fall back to
// fixed-fraction crops (or skip cell-level entirely).
type CVSidecarColumns struct {
	Ok             bool  `json:"ok"`
	PageW          int   `json:"page_w"`
	XSnoStart      int   `json:"x_sno_start"`
	XBrandStart    int   `json:"x_brand_start"`
	XBrandEnd      int   `json:"x_brand_end"`
	XOpenStart     int   `json:"x_open_start"`
	XRecvStart     int   `json:"x_recv_start"`
	XTotalStart    int   `json:"x_total_start"`
	XSaleStart     int   `json:"x_sale_start"`
	XRateStart     int   `json:"x_rate_start"`
	XAmountStart   int   `json:"x_amount_start"`
	XClosingStart  int   `json:"x_closing_start"`
	XPageEnd       int   `json:"x_page_end"`
	DetectedLines  []int `json:"detected_lines"`
}

// CVSidecarGrid is the combined response of /detect-grid (rows + columns).
type CVSidecarGrid struct {
	PageSizePx []int            `json:"page_size_px"`
	DeskewDeg  float64          `json:"deskew_deg"`
	Rows       []cvSidecarRow   `json:"rows"`
	Columns    CVSidecarColumns `json:"columns"`
	Diag       map[string]any   `json:"diag"`
}

// SupplementalFallbackCtxKey is set on the context when the legacy
// extractFromImages is invoked as a SUPPLEMENTAL fallback after sheet-grid
// already produced its high-confidence rows. The supplemental call only
// needs to find the rows sheet-grid missed, so we skip self-consistency
// voting (single Sonnet pass) and skip Opus verifier — both are 30-60s
// each and unnecessary when sheet-grid covered the math-confirmed rows.
//
// v1.0.151 — drops the 30-Apr 375ml job runtime from 187s → ≤120s.
type supplementalFallbackCtxKeyT struct{}

var SupplementalFallbackCtxKey = supplementalFallbackCtxKeyT{}

// IsSupplementalFallback reads the flag set above.
func IsSupplementalFallback(ctx context.Context) bool {
	v := ctx.Value(SupplementalFallbackCtxKey)
	b, _ := v.(bool)
	return b
}

// SaleCVColsCtxKey carries CVSidecarColumns on the call context. Set by
// extractFromImages when /detect-grid succeeds.
type saleCVColsCtxKeyT struct{}

var SaleCVColsCtxKey = saleCVColsCtxKeyT{}

type CVSidecarClient struct {
	url     string
	enabled bool
	client  *http.Client
	logger  *logrus.Logger
}

func NewCVSidecarClient(logger *logrus.Logger) *CVSidecarClient {
	url := strings.TrimSpace(os.Getenv("CV_SIDECAR_URL"))
	if url == "" {
		url = "http://cv-sidecar:8099"
	}
	enabled := os.Getenv("CV_SIDECAR_ENABLED") == "1"
	timeoutMs := 4000
	if v := os.Getenv("CV_SIDECAR_TIMEOUT_MS"); v != "" {
		fmt.Sscanf(v, "%d", &timeoutMs)
	}
	if logger != nil {
		logger.Infof("CV sidecar client: enabled=%v url=%s timeout=%dms", enabled, url, timeoutMs)
	}
	return &CVSidecarClient{
		url:     url,
		enabled: enabled,
		logger:  logger,
		client:  &http.Client{Timeout: time.Duration(timeoutMs) * time.Millisecond},
	}
}

// DetectBlankRows posts an image to the sidecar and returns the row analysis.
// Returns nil on disabled / error / empty result. Logs but never panics.
func (c *CVSidecarClient) DetectBlankRows(ctx context.Context, imageBytes []byte) *cvSidecarResponse {
	if c == nil || !c.enabled {
		return nil
	}
	if len(imageBytes) == 0 {
		return nil
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "register.jpg")
	if err != nil {
		return nil
	}
	if _, err := part.Write(imageBytes); err != nil {
		return nil
	}
	w.Close()
	req, err := http.NewRequestWithContext(ctx, "POST", c.url+"/detect-blank-rows", body)
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		if c.logger != nil {
			c.logger.Warnf("CV sidecar request failed (treating as disabled): %v", err)
		}
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 400))
		if c.logger != nil {
			c.logger.Warnf("CV sidecar non-200 (%d): %s", resp.StatusCode, string(raw))
		}
		return nil
	}
	var out cvSidecarResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		if c.logger != nil {
			c.logger.Warnf("CV sidecar JSON decode failed: %v", err)
		}
		return nil
	}
	return &out
}

// DetectGrid posts an image to /detect-grid (Phase 1) and returns rows +
// columns in a single roundtrip. Best-effort — nil on disabled / error /
// empty result. The Go pipeline never blocks on CV failure.
func (c *CVSidecarClient) DetectGrid(ctx context.Context, imageBytes []byte) *CVSidecarGrid {
	if c == nil || !c.enabled || len(imageBytes) == 0 {
		return nil
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "register.jpg")
	if err != nil {
		return nil
	}
	if _, err := part.Write(imageBytes); err != nil {
		return nil
	}
	w.Close()
	req, err := http.NewRequestWithContext(ctx, "POST", c.url+"/detect-grid", body)
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		if c.logger != nil {
			c.logger.Warnf("CV sidecar /detect-grid failed: %v", err)
		}
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 400))
		if c.logger != nil {
			c.logger.Warnf("CV sidecar /detect-grid non-200 (%d): %s", resp.StatusCode, string(raw))
		}
		return nil
	}
	var out CVSidecarGrid
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		if c.logger != nil {
			c.logger.Warnf("CV sidecar /detect-grid decode failed: %v", err)
		}
		return nil
	}
	return &out
}

// CVSidecarPageQuality is /quality-check's response shape.
// v1.0.178 added severe_issues / severe / score fields. Older sidecars omit
// them — the zero values keep the advisory-only path working.
type CVSidecarPageQuality struct {
	OK            bool     `json:"ok"`
	PageSizePx    []int    `json:"page_size_px"`
	Blur          float64  `json:"blur"`
	Contrast      float64  `json:"contrast"`
	Brightness    float64  `json:"brightness"`
	SkewDeg       float64  `json:"skew_deg"`
	Issues        []string `json:"issues"`
	SevereIssues  []string `json:"severe_issues"`
	Advisory      bool     `json:"advisory"`
	Severe        bool     `json:"severe"`
	Score         float64  `json:"score"`
}

// QualityCheck posts an image to /quality-check (v1.0.177) and returns
// blur/contrast/brightness/skew telemetry. Passive — never blocks the
// pipeline. Caller logs the result so we can correlate accuracy with
// quality on real-traffic samples before flipping any hard gate.
func (c *CVSidecarClient) QualityCheck(ctx context.Context, imageBytes []byte) *CVSidecarPageQuality {
	if c == nil || !c.enabled || len(imageBytes) == 0 {
		return nil
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "register.jpg")
	if err != nil {
		return nil
	}
	if _, err := part.Write(imageBytes); err != nil {
		return nil
	}
	w.Close()
	req, err := http.NewRequestWithContext(ctx, "POST", c.url+"/quality-check", body)
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		if c.logger != nil {
			c.logger.Warnf("CV sidecar /quality-check failed: %v", err)
		}
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	var out CVSidecarPageQuality
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil
	}
	return &out
}

// BuildBlankRowHint converts a CV sidecar response into a prompt fragment
// that Claude will see at the top of the system prompt. Returns "" when
// the signal is too weak to be useful (no blanks found, or detection
// failed). The hint is conservative — it lists blank serial numbers so
// Claude returns null for those, but doesn't override Claude's own
// classification on filled rows.
func BuildBlankRowHint(r *cvSidecarResponse) string {
	if r == nil || len(r.Rows) == 0 {
		return ""
	}
	minBlanks := 2
	if v := os.Getenv("CV_SIDECAR_MIN_BLANK_TO_HINT"); v != "" {
		fmt.Sscanf(v, "%d", &minBlanks)
	}
	var blanks []int
	for _, row := range r.Rows {
		if row.IsBlank {
			blanks = append(blanks, row.RowNumber)
		}
	}
	if len(blanks) < minBlanks {
		return ""
	}
	var sb strings.Builder
	sb.WriteString("CV-CROSS-CHECK SIGNAL — A computer vision pre-pass detected the following register rows are BLANK (no handwriting). DO NOT extract any item for these rows; return null instead. Rows: ")
	for i, n := range blanks {
		if i > 0 {
			sb.WriteString(", ")
		}
		fmt.Fprintf(&sb, "%d", n)
	}
	sb.WriteString(".\n")
	sb.WriteString(fmt.Sprintf("(CV detected %d filled rows total, %d blank.)\n\n",
		len(r.Rows)-len(blanks), len(blanks)))
	return sb.String()
}
