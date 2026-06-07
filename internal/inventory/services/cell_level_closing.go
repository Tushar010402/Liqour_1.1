package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// v1.0.134 Track B — cell-level closing-stock micro-extraction.
//
// After the primary Sonnet extraction + Opus verifier complete, identify rows
// where the closing-stock value is suspect (low field-confidence OR violates
// the math identity opening + receipt − sale = closing). For each such row,
// crop a tight strip = full row width × Y-band, keep just the rightmost 1/8
// (the closing-stock column), and send it to Sonnet as a single-purpose call:
// "What digit(s) are written in this cell?"
//
// Only replaces the primary closing value when the cell-level call returns
// confidence >= cellLevelMinConf (default 0.92). Otherwise the primary wins —
// so worst-case for a row is "no change," never a regression.
//
// Disabled by default. Enable with SMART_STOCK_SETUP_CELL_LEVEL=1.
//
// Cost: ~₹0.02 per cell call × ~5 cells/page = ₹0.10/page extra. Stays inside
// the ₹2.50/page envelope.

const (
	cellLevelDefMinConf      = 0.92
	cellLevelDefFieldConfMin = 0.85 // re-read closing when primary closing-conf < 0.85
	cellLevelMaxCellsPerPage = 8    // safety cap so a fully-broken page can't blow cost
	cellLevelTimeoutMs       = 25000
)

type cellLevelResult struct {
	Value      *int    `json:"value"` // null if blank
	Confidence float64 `json:"confidence"`
}

type cellLevelStats struct {
	candidates int
	called     int
	replaced   int
}

// cellLevelEnabled returns true when SMART_STOCK_SETUP_CELL_LEVEL=1.
func cellLevelEnabled() bool {
	return os.Getenv("SMART_STOCK_SETUP_CELL_LEVEL") == "1"
}

func cellLevelMinConf() float64 {
	v := os.Getenv("SMART_STOCK_SETUP_CELL_LEVEL_MIN_CONF")
	if v == "" {
		return cellLevelDefMinConf
	}
	var f float64
	if _, err := fmt.Sscanf(v, "%f", &f); err == nil && f > 0 && f <= 1 {
		return f
	}
	return cellLevelDefMinConf
}

// repairLowConfClosingCells runs the cell-level pass on the verified items.
// imageBytes is the SAME image already optimized for the primary call. Returns
// the items slice (possibly mutated in place) and per-page stats for logging.
func (s *SmartPurchaseOCR) repairLowConfClosingCells(ctx context.Context, imageBytes []byte, items []ExtractedStockRegisterItem) ([]ExtractedStockRegisterItem, cellLevelStats) {
	stats := cellLevelStats{}
	if !cellLevelEnabled() || s.anthropicKey == "" || len(items) == 0 || len(imageBytes) == 0 {
		return items, stats
	}
	cvRows, _ := ctx.Value(StockSetupCVRowsCtxKey).([]stockSetupCVRow)
	if len(cvRows) < 4 {
		return items, stats
	}

	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		log.Printf("Smart Stock Setup OCR: cell-level decode failed: %v", err)
		return items, stats
	}
	bounds := src.Bounds()
	W, H := bounds.Dx(), bounds.Dy()
	if W < 200 || H < 200 {
		return items, stats
	}
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	si, ok := src.(subImager)
	if !ok {
		rgba := image.NewRGBA(bounds)
		for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
			for x := bounds.Min.X; x < bounds.Max.X; x++ {
				rgba.Set(x, y, src.At(x, y))
			}
		}
		si = rgba
	}

	confFloor := cellLevelMinConf()
	fieldFloor := cellLevelDefFieldConfMin
	if v := os.Getenv("SMART_STOCK_SETUP_CELL_FIELD_FLOOR"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil && f > 0 && f <= 1 {
			fieldFloor = f
		}
	}

	pad := H / 80
	for i := range items {
		if stats.called >= cellLevelMaxCellsPerPage {
			break
		}
		row := &items[i]
		// Identify candidates: low closing-conf OR math violation.
		closingConf := 1.0
		if row.FieldConfidence != nil {
			if v, ok := row.FieldConfidence["closing"]; ok {
				closingConf = v
			} else if v, ok := row.FieldConfidence["closing_stock"]; ok {
				closingConf = v
			}
		}
		mathOK := row.Closing == row.Opening+row.Receipt-row.Sale
		needsRepair := closingConf < fieldFloor || !mathOK
		if !needsRepair {
			continue
		}
		idx := row.RowNumber - 1
		if idx < 0 || idx >= len(cvRows) {
			continue
		}
		stats.candidates++

		y0 := bounds.Min.Y + cvRows[idx].YTop - pad
		y1 := bounds.Min.Y + cvRows[idx].YBottom + pad
		if y0 < bounds.Min.Y {
			y0 = bounds.Min.Y
		}
		if y1 > bounds.Max.Y {
			y1 = bounds.Max.Y
		}
		if y1-y0 < 25 {
			continue
		}
		// Closing-stock column = rightmost 1/8 of width.
		x0 := bounds.Min.X + (W*7)/8
		x1 := bounds.Max.X
		strip := si.SubImage(image.Rect(x0, y0, x1, y1))

		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, strip, &jpeg.Options{Quality: 90}); err != nil {
			continue
		}
		stats.called++

		res, ok := s.callCellLevelDigit(ctx, buf.Bytes(), "closing")
		if !ok {
			continue
		}
		if res.Confidence < confFloor {
			continue
		}
		newClosing := 0
		if res.Value != nil {
			newClosing = *res.Value
		}
		if newClosing == row.Closing {
			continue
		}
		log.Printf("Smart Stock Setup OCR: cell-level repaired row %d closing %d → %d (conf %.2f)",
			row.RowNumber, row.Closing, newClosing, res.Confidence)
		row.Closing = newClosing
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		row.FieldConfidence["closing"] = res.Confidence
		stats.replaced++
	}
	return items, stats
}

// callCellLevelDigit sends a single tiny crop to Sonnet and parses a digit
// answer. column is "closing" / "opening" / etc — used purely for the prompt.
func (s *SmartPurchaseOCR) callCellLevelDigit(ctx context.Context, cropBytes []byte, column string) (*cellLevelResult, bool) {
	if len(cropBytes) == 0 {
		return nil, false
	}
	model := os.Getenv("CLAUDE_PRIMARY_MODEL")
	if model == "" {
		model = claudeDefaultPrimary
	}
	prompt := fmt.Sprintf(
		"You are reading ONE cell from the %s column of a stock register. The image is a thin horizontal strip showing exactly one row of that column.\n\n"+
			"Return ONLY valid JSON in this exact shape:\n"+
			"{\"value\": <integer or null>, \"confidence\": <0.0-1.0>}\n\n"+
			"- \"value\": the integer written in the cell, or null if the cell is empty/illegible.\n"+
			"- \"confidence\": your confidence the value is correct. Be conservative — return <0.7 if any digit is ambiguous.\n"+
			"- DO NOT return any prose or markdown fences. JSON only.",
		column)
	body := claudeRequest{
		Model:       model,
		MaxTokens:   64,
		Temperature: 0.0,
		Messages: []claudeMessage{{
			Role: "user",
			Content: []claudeContent{
				{Type: "image", Source: &claudeImageSource{
					Type: "base64", MediaType: "image/jpeg",
					Data: base64.StdEncoding.EncodeToString(cropBytes),
				}},
				{Type: "text", Text: prompt},
			},
		}},
	}
	reqBody, err := json.Marshal(body)
	if err != nil {
		return nil, false
	}
	cctx, cancel := context.WithTimeout(ctx, time.Duration(cellLevelTimeoutMs)*time.Millisecond)
	defer cancel()
	req, err := http.NewRequestWithContext(cctx, "POST", claudeAPIEndpoint, bytes.NewBuffer(reqBody))
	if err != nil {
		return nil, false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.anthropicKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, false
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, false
	}
	if resp.StatusCode != http.StatusOK {
		return nil, false
	}
	var apiResp claudeResponse
	if err := json.Unmarshal(raw, &apiResp); err != nil {
		return nil, false
	}
	if apiResp.Error != nil {
		return nil, false
	}
	var text strings.Builder
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			text.WriteString(b.Text)
		}
	}
	t := strings.TrimSpace(text.String())
	if i := strings.Index(t, "{"); i >= 0 {
		if j := strings.LastIndex(t, "}"); j > i {
			t = t[i : j+1]
		}
	}
	var out cellLevelResult
	if err := json.Unmarshal([]byte(t), &out); err != nil {
		return nil, false
	}
	if out.Confidence < 0 || out.Confidence > 1 {
		return nil, false
	}
	return &out, true
}
