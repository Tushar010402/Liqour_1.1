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

// BrandPhotoCandidate is one OCR'd brand-text candidate from the bottle photo.
// Higher confidence → more likely to be the correct brand name.
type BrandPhotoCandidate struct {
	Name       string  `json:"name"`
	Confidence float64 `json:"confidence"`
}

// BrandPhotoResult is what cv-sidecar's /extract-brand-from-photo returns.
type BrandPhotoResult struct {
	OCRText         string                `json:"ocr_text"`
	Candidates      []BrandPhotoCandidate `json:"candidates"`
	DetectedSizeML  int                   `json:"detected_size_ml,omitempty"`
	DetectedMRPText string                `json:"detected_mrp_text,omitempty"`
	Source          string                `json:"source,omitempty"` // "textract" | "paddle" | "claude"
}

// BrandPhotoClient is a thin HTTP client for cv-sidecar /extract-brand-from-photo.
//
// Reuses the same env knobs as StockSetupCVClient (CV_SIDECAR_URL,
// CV_SIDECAR_TIMEOUT_MS) so ops only configures one set. Photos are larger
// than register cells so the timeout defaults higher (8s vs 4s).
type BrandPhotoClient struct {
	url    string
	client *http.Client
	logger *logrus.Logger
}

// NewBrandPhotoClient wires the client. Reads CV_SIDECAR_URL (default
// http://cv-sidecar:8000) and BRAND_PHOTO_TIMEOUT_MS (default 8000).
func NewBrandPhotoClient(logger *logrus.Logger) *BrandPhotoClient {
	url := strings.TrimSpace(os.Getenv("CV_SIDECAR_URL"))
	if url == "" {
		url = "http://cv-sidecar:8000"
	}
	timeoutMs := 8000
	if v := os.Getenv("BRAND_PHOTO_TIMEOUT_MS"); v != "" {
		fmt.Sscanf(v, "%d", &timeoutMs)
	}
	return &BrandPhotoClient{
		url:    url,
		client: &http.Client{Timeout: time.Duration(timeoutMs) * time.Millisecond},
		logger: logger,
	}
}

// ExtractFromPhoto posts a bottle-label photo to cv-sidecar and returns the
// OCR'd text + brand candidates. Best-effort: nil result + non-nil error on
// any failure (network, non-2xx, JSON parse). Caller decides whether to
// fall back to a different strategy or surface the error to the operator.
func (c *BrandPhotoClient) ExtractFromPhoto(ctx context.Context, imageBytes []byte, contentType string) (*BrandPhotoResult, error) {
	if c == nil || c.url == "" {
		return nil, fmt.Errorf("brand-photo client not configured")
	}
	if len(imageBytes) == 0 {
		return nil, fmt.Errorf("empty image")
	}

	body := &bytes.Buffer{}
	mw := multipart.NewWriter(body)
	fw, err := mw.CreateFormFile("file", "photo.jpg")
	if err != nil {
		return nil, fmt.Errorf("multipart create: %w", err)
	}
	if _, err := fw.Write(imageBytes); err != nil {
		return nil, fmt.Errorf("multipart write: %w", err)
	}
	mw.Close()

	url := strings.TrimRight(c.url, "/") + "/extract-brand-from-photo"
	req, err := http.NewRequestWithContext(ctx, "POST", url, body)
	if err != nil {
		return nil, fmt.Errorf("brand-photo request build: %w", err)
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("brand-photo request: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("brand-photo non-2xx %d: %s", resp.StatusCode, string(respBody[:min(len(respBody), 300)]))
	}

	var result BrandPhotoResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("brand-photo parse: %w", err)
	}
	if c.logger != nil {
		c.logger.Infof("BrandPhoto: extracted via %s — text=%q, %d candidates, size=%d ml",
			result.Source, result.OCRText, len(result.Candidates), result.DetectedSizeML)
	}
	return &result, nil
}
