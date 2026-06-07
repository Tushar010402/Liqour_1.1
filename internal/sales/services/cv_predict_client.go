package services

// v1.0.140 — Go client for cv-sidecar /predict-cells.
//
// Mirrors cv_sidecar_client.go shape. One method: PredictCells(ctx, imgBytes,
// cells) → []CellPrediction. Returns nil + nil when no model is loaded
// server-side so the caller falls back to AI cleanly.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
)

// CellPrediction is the per-cell result returned by /predict-cells.
type CellPrediction struct {
	RowIdx     int     `json:"row_idx"`
	ColName    string  `json:"col_name"`
	Digit      string  `json:"digit"` // "0".."9", multi-digit "12", or "" (blank)
	Confidence float64 `json:"confidence"`
}

type predictCellsResponse struct {
	ModelLoaded  bool             `json:"model_loaded"`
	ModelVersion string           `json:"model_version"`
	Predictions  []CellPrediction `json:"predictions"`
	Error        string           `json:"error,omitempty"`
}

// PredictCells calls cv-sidecar /predict-cells. The cells slice is converted
// into the multipart 'cells' JSON form field. Returns nil predictions when
// no model is loaded (caller should fall back to AI). Errors only on
// transport-level failures; protocol-level "model not loaded" is a soft
// signal — predictions slice will be empty.
func (c *CVSidecarClient) PredictCells(ctx context.Context, imgBytes []byte, cells []SheetCell) ([]CellPrediction, string, error) {
	if c == nil || !c.enabled || len(imgBytes) == 0 || len(cells) == 0 {
		return nil, "", nil
	}
	cellsJSON, mErr := json.Marshal(cells)
	if mErr != nil {
		return nil, "", mErr
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "register.jpg")
	if err != nil {
		return nil, "", err
	}
	if _, err := part.Write(imgBytes); err != nil {
		return nil, "", err
	}
	if err := w.WriteField("cells", string(cellsJSON)); err != nil {
		return nil, "", err
	}
	w.Close()

	req, err := http.NewRequestWithContext(ctx, "POST", c.url+"/predict-cells", body)
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 400))
		return nil, "", fmt.Errorf("cv /predict-cells %d: %s", resp.StatusCode, string(raw))
	}
	var out predictCellsResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, "", err
	}
	if !out.ModelLoaded {
		return nil, out.ModelVersion, nil
	}
	return out.Predictions, out.ModelVersion, nil
}

// BrandRead is a single PaddleOCR row read from /extract-brands.
type BrandRead struct {
	RowIdx     int     `json:"row_idx"`
	BrandText  string  `json:"brand_text"`
	Confidence float64 `json:"confidence"`
}

type extractBrandsResponse struct {
	OK       bool        `json:"ok"`
	Engine   string      `json:"engine"`
	RowCount int         `json:"row_count"`
	Rows     []BrandRead `json:"rows"`
}

// ExtractBrands calls cv-sidecar /extract-brands. Returns one BrandRead per
// detected row using PaddleOCR (CPU, free). When the engine is unavailable
// or grid detection failed, returns nil so the caller falls back to AI.
//
// v1.0.157 Phase 2 — replaces the per-page Sonnet brand-text call.
func (c *CVSidecarClient) ExtractBrands(ctx context.Context, imgBytes []byte) ([]BrandRead, error) {
	if c == nil || !c.enabled || len(imgBytes) == 0 {
		return nil, nil
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "register.jpg")
	if err != nil {
		return nil, err
	}
	if _, err := part.Write(imgBytes); err != nil {
		return nil, err
	}
	w.Close()

	req, err := http.NewRequestWithContext(ctx, "POST", c.url+"/extract-brands", body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 400))
		return nil, fmt.Errorf("cv /extract-brands %d: %s", resp.StatusCode, string(raw))
	}
	var out extractBrandsResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if !out.OK || out.Engine != "paddleocr" {
		return nil, nil
	}
	return out.Rows, nil
}
