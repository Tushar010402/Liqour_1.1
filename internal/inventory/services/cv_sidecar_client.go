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

// v1.0.134 — CV sidecar HTTP client for Stock Setup. Mirrors the Sales-side
// implementation at internal/sales/services/cv_sidecar_client.go but lives
// in the inventory package so the two services can be deployed
// independently without coupling. Same env knobs (CV_SIDECAR_URL etc.) are
// shared since the sidecar is a single shared process.
//
// Best-effort: any failure (timeout, bad JSON, non-2xx) returns nil and the
// extraction proceeds without the hint. The sidecar must NEVER block the
// happy path.

type stockSetupCVRow struct {
	RowNumber int     `json:"row_number"`
	YTop      int     `json:"y_top"`
	YBottom   int     `json:"y_bottom"`
	IsBlank   bool    `json:"is_blank"`
	FillRatio float64 `json:"fill_ratio"`
}

type stockSetupCVResponse struct {
	PageSizePx []int             `json:"page_size_px"`
	Rows       []stockSetupCVRow `json:"rows"`
	Diag       map[string]any    `json:"diag"`
}

type StockSetupCVClient struct {
	url     string
	enabled bool
	client  *http.Client
	logger  *logrus.Logger
}

// logrusLogger returns a singleton logrus logger so service code can pass it
// to helpers that take *logrus.Logger without each caller wiring up a fresh
// instance. Stock Setup's own logging predates logrus (uses log.Printf), so
// this lives here to avoid imposing logrus on the rest of the package.
func logrusLogger() *logrus.Logger {
	return logrus.StandardLogger()
}

func NewStockSetupCVClient(logger *logrus.Logger) *StockSetupCVClient {
	url := strings.TrimSpace(os.Getenv("CV_SIDECAR_URL"))
	if url == "" {
		url = "http://cv-sidecar:8000"
	}
	enabled := os.Getenv("CV_SIDECAR_ENABLED") == "1"
	timeoutMs := 4000
	if v := os.Getenv("CV_SIDECAR_TIMEOUT_MS"); v != "" {
		fmt.Sscanf(v, "%d", &timeoutMs)
	}
	if logger != nil {
		logger.Infof("Stock Setup CV sidecar client: enabled=%v url=%s timeout=%dms", enabled, url, timeoutMs)
	}
	return &StockSetupCVClient{
		url:     url,
		enabled: enabled,
		logger:  logger,
		client:  &http.Client{Timeout: time.Duration(timeoutMs) * time.Millisecond},
	}
}

// DetectBlankRows posts an image to the sidecar and returns the row analysis.
func (c *StockSetupCVClient) DetectBlankRows(ctx context.Context, imageBytes []byte) *stockSetupCVResponse {
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
	req, err := http.NewRequestWithContext(ctx, "POST", c.url+"/detect-blank-rows", body)
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		if c.logger != nil {
			c.logger.Warnf("Stock Setup CV sidecar request failed: %v", err)
		}
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 400))
		if c.logger != nil {
			c.logger.Warnf("Stock Setup CV sidecar non-200 (%d): %s", resp.StatusCode, string(raw))
		}
		return nil
	}
	var out stockSetupCVResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		if c.logger != nil {
			c.logger.Warnf("Stock Setup CV sidecar JSON decode failed: %v", err)
		}
		return nil
	}
	return &out
}

// StockSetupPageQuality mirrors /quality-check's response (v1.0.178).
type StockSetupPageQuality struct {
	OK           bool     `json:"ok"`
	PageSizePx   []int    `json:"page_size_px"`
	Blur         float64  `json:"blur"`
	Contrast     float64  `json:"contrast"`
	Brightness   float64  `json:"brightness"`
	SkewDeg      float64  `json:"skew_deg"`
	Issues       []string `json:"issues"`
	SevereIssues []string `json:"severe_issues"`
	Advisory     bool     `json:"advisory"`
	Severe       bool     `json:"severe"`
	Score        float64  `json:"score"`
}

// QualityCheck posts to /quality-check. Returns nil when sidecar is disabled
// / unreachable so callers fail open. v1.0.178 — Stock Setup defense-in-depth.
func (c *StockSetupCVClient) QualityCheck(ctx context.Context, imageBytes []byte) *StockSetupPageQuality {
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
			c.logger.Warnf("Stock Setup CV /quality-check failed: %v", err)
		}
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	var out StockSetupPageQuality
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil
	}
	return &out
}

// BuildStockSetupBlankRowHint converts a CV sidecar response into a prompt
// fragment Claude sees at the top of the system prompt.
func BuildStockSetupBlankRowHint(r *stockSetupCVResponse) string {
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
	sb.WriteString("CV-CROSS-CHECK SIGNAL — A computer vision pre-pass detected the following register rows are BLANK (no handwriting). DO NOT extract any item for these rows; return null instead. Blank rows: ")
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

// StockSetupCVHintsCtxKey carries the per-image blank-row hint string from
// the service-level goroutine into extractRegisterWithClaudeSingle, where
// the system prompt is built. Empty value = no hint.
type stockSetupCVHintsCtxKeyT struct{}

var StockSetupCVHintsCtxKey = stockSetupCVHintsCtxKeyT{}

// StockSetupCVRowsCtxKey carries the full per-row CV analysis (including
// y_top/y_bottom) so the verifier can build pixel-accurate crops instead
// of the linear-partition heuristic.
type stockSetupCVRowsCtxKeyT struct{}

var StockSetupCVRowsCtxKey = stockSetupCVRowsCtxKeyT{}
