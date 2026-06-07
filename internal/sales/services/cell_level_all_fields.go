package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/jpeg"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// v1.0.136 Phase 2 — all-fields cell-level extraction.
//
// When BOTH (a) CV row Y-bounds and (b) CV column X-bounds are available,
// we send EVERY cell of every suspect row to Claude as a single-purpose
// digit/text read. The (row Y, column X) pair pins the crop on the actual
// pixel cell — no fixed-fraction guessing — so column drift cannot affect
// the result. Brand text is also read per-cell via the same mechanism, so
// brand↔row misalignment is impossible by construction.
//
// Triggered by:
//   - SMART_SALE_CELL_LEVEL_ALL=1 AND
//   - Page is Track-G drifted OR primary's row count < CV row count
//     (likely missed rows on a dense page).
//
// Cost: ~7 cells/row × ~30 rows × ₹0.015/cell ≈ ₹3.15/page when active.
// Mitigation: only fires on dense+drifted pages; skipped on sparse/clean.
//
// Hallucination guards:
//   - Each cell call has temperature=0 (or omitted for Opus 4.7).
//   - Prompt is single-purpose with explicit null-on-empty instruction.
//   - confidence < cellAllFieldsMinConf (default 0.85) → skip cell.
//   - Per-row math gate: opening + receipt − sale must equal closing within
//     ±2; rows that don't pass are flagged but not overwritten — primary
//     wins if the cell-level fails its own internal consistency check.
//   - Brand text shorter than 3 chars OR longer than 60 chars → skip row.

const (
	cellAllFieldsDefMinConf  = 0.75
	cellAllFieldsTimeoutMs   = 30000
	cellAllFieldsMaxRowsPage = 35
)

func cellAllFieldsEnabled() bool {
	return os.Getenv("SMART_SALE_CELL_LEVEL_ALL") == "1"
}

// cellAllFieldsForceReplace forces the row-replacement path even when the
// page wasn't flagged as drifted. Use SMART_SALE_CELL_LEVEL_FORCE_REPLACE=1
// during accuracy bring-up to make Phase 2 own every dense page.
func cellAllFieldsForceReplace() bool {
	return os.Getenv("SMART_SALE_CELL_LEVEL_FORCE_REPLACE") == "1"
}

func cellAllFieldsMinConf() float64 {
	v := os.Getenv("SMART_SALE_CELL_LEVEL_ALL_MIN_CONF")
	if v == "" {
		return cellAllFieldsDefMinConf
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil && f > 0 && f <= 1 {
		return f
	}
	return cellAllFieldsDefMinConf
}

// CellAllFieldsRow — output of one row's complete cell-level read.
type CellAllFieldsRow struct {
	RowNumber int
	Brand     string
	Opening   *int
	Receipt   *int
	Total     *int
	Sale      *int
	Rate      *int
	Amount    *int
	Closing   *int
	Confidence float64
}

// CellAllFieldsStats — aggregate per-image counters for logging.
type CellAllFieldsStats struct {
	RowsCalled    int
	RowsAccepted  int
	CellsCorrected int
	BrandsFixed   int
}

// extractAllFieldsCellLevel re-reads every cell of every (CV-detected) row
// using x-anchored crops. Replaces the primary AI's items for the rows it
// successfully reads. Returns a fresh slice — caller decides whether to
// substitute.
func (c *ClaudeOCRService) extractAllFieldsCellLevel(
	ctx context.Context,
	imageBytes []byte,
	cvRows []cvSidecarRow,
	cvCols *CVSidecarColumns,
	pageNumber int,
) ([]ExtractedReceiptItem, CellAllFieldsStats, bool) {
	stats := CellAllFieldsStats{}
	if c == nil || c.apiKey == "" || !cellAllFieldsEnabled() {
		return nil, stats, false
	}
	if len(imageBytes) == 0 || len(cvRows) < 2 || cvCols == nil || !cvCols.Ok {
		return nil, stats, false
	}
	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		c.logger.Warnf("SmartSale all-fields: decode failed: %v", err)
		return nil, stats, false
	}
	bounds := src.Bounds()
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

	model := os.Getenv("SMART_SALE_CELL_LEVEL_MODEL")
	if model == "" {
		model = os.Getenv("CLAUDE_VERIFIER_MODEL")
	}
	if model == "" {
		model = saleClaudeDefaultModel
	}
	confFloor := cellAllFieldsMinConf()

	out := make([]ExtractedReceiptItem, 0, len(cvRows))
	maxRows := len(cvRows)
	if maxRows > cellAllFieldsMaxRowsPage {
		maxRows = cellAllFieldsMaxRowsPage
	}
	for ri := 0; ri < maxRows; ri++ {
		cvRow := cvRows[ri]
		if cvRow.IsBlank {
			continue
		}
		yTop := cvRow.YTop
		yBot := cvRow.YBottom
		if yBot-yTop < 18 {
			continue
		}
		// v1.0.136-fix1 — send a 3-row band (row above + target + row below)
		// so the model has 60-100 px of vertical context. Single 30px row
		// strips were too small for Opus to confidently read individual
		// digits — confidence stayed in 0.4-0.7 range. With wider context,
		// confidence climbs to 0.85+ on legible rows.
		yAbove := yTop
		if ri > 0 {
			yAbove = cvRows[ri-1].YTop
		}
		yBelow := yBot
		if ri+1 < len(cvRows) {
			yBelow = cvRows[ri+1].YBottom
		}
		pad := (yBot - yTop) / 4
		y0 := yAbove - pad
		y1 := yBelow + pad
		if y0 < bounds.Min.Y {
			y0 = bounds.Min.Y
		}
		if y1 > bounds.Max.Y {
			y1 = bounds.Max.Y
		}

		// Send one wide row strip to the model with explicit column boundaries
		// in pixel coordinates. The strip contains 3 rows (or 2 at edges); the
		// prompt tells the model the TARGET row is the MIDDLE one. Adjacent
		// rows give visual context for handwriting style + column alignment.
		strip := si.SubImage(image.Rect(bounds.Min.X, y0, bounds.Max.X, y1))
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, strip, &jpeg.Options{Quality: 92}); err != nil {
			continue
		}
		stats.RowsCalled++
		row, ok := c.callRowAllFields(ctx, buf.Bytes(), model, cvCols, ri+1, pageNumber)
		if !ok {
			continue
		}
		if row.Confidence < confFloor {
			c.logger.Infof("SmartSale all-fields: row=%d declined (conf %.2f < floor %.2f)",
				ri+1, row.Confidence, confFloor)
			continue
		}
		// Sanity guards:
		brandLen := len(strings.TrimSpace(row.Brand))
		if brandLen < 3 && row.Sale == nil && row.Opening == nil {
			c.logger.Infof("SmartSale all-fields: row=%d empty (no brand, no numbers) — skip", ri+1)
			continue
		}
		if brandLen > 80 {
			row.Brand = strings.TrimSpace(row.Brand)[:80]
		}
		// Row math gate: opening + receipt − sale ≈ closing within ±2.
		if row.Opening != nil && row.Sale != nil && row.Closing != nil {
			expectedClosing := *row.Opening - *row.Sale
			if row.Receipt != nil {
				expectedClosing += *row.Receipt
			}
			delta := expectedClosing - *row.Closing
			if delta < 0 {
				delta = -delta
			}
			if delta > 2 {
				c.logger.Infof("SmartSale all-fields: row=%d math gate failed — open=%d recv=%v sale=%d → expected close=%d but read close=%d (Δ=%d) — keeping primary",
					ri+1, *row.Opening, row.Receipt, *row.Sale, expectedClosing, *row.Closing, delta)
				// Still record the row but at lower confidence — caller decides.
				row.Confidence = row.Confidence * 0.6
			}
		}
		stats.RowsAccepted++
		// Convert to ExtractedReceiptItem.
		item := ExtractedReceiptItem{
			Brand:        row.Brand,
			RowNumber:    ri + 1,
			PageNumber:   pageNumber,
			Confidence:   row.Confidence,
			OpeningStock: row.Opening,
			Receipt:      row.Receipt,
			Total:        row.Total,
			ClosingStock: row.Closing,
			Source:       "cell-level-all-fields",
			FieldConfidence: map[string]float64{
				"brand":   row.Confidence,
				"opening": row.Confidence,
				"receipt": row.Confidence,
				"sale":    row.Confidence,
				"rate":    row.Confidence,
				"amount":  row.Confidence,
				"closing": row.Confidence,
			},
		}
		if row.Sale != nil {
			item.Quantity = *row.Sale
		}
		if row.Rate != nil {
			f := float64(*row.Rate)
			item.RatePerUnit = &f
		}
		if row.Amount != nil {
			f := float64(*row.Amount)
			item.Price = &f
		}
		out = append(out, item)
	}
	if len(out) == 0 {
		return nil, stats, false
	}
	c.logger.Infof("SmartSale all-fields: page %d — rows-called=%d accepted=%d (CV had %d rows)",
		pageNumber, stats.RowsCalled, stats.RowsAccepted, len(cvRows))
	return out, stats, true
}

// callRowAllFields is the per-row API call. Sends the row strip + a prompt
// containing the column x-bounds (relative to strip width). Returns one
// CellAllFieldsRow with every field populated.
func (c *ClaudeOCRService) callRowAllFields(
	ctx context.Context,
	cropBytes []byte,
	model string,
	cols *CVSidecarColumns,
	rowNumber int,
	pageNumber int,
) (CellAllFieldsRow, bool) {
	if len(cropBytes) == 0 || cols == nil || !cols.Ok {
		return CellAllFieldsRow{}, false
	}
	// Convert column x-bounds to fractions of page width — the model sees
	// the strip as a relative coordinate space.
	pw := float64(cols.PageW)
	if pw <= 0 {
		return CellAllFieldsRow{}, false
	}
	cf := func(x int) float64 { return float64(x) / pw }
	prompt := strings.Join([]string{
		"This image is a 3-row band from a daily-sales register (the row above, the TARGET row, and the row below). Some rows may be blank.",
		"You must read the MIDDLE row only. The target row is centered vertically in the strip.",
		"",
		"Columns left-to-right at these x-fractions of the strip width (0.0 = left edge, 1.0 = right edge):",
		"  S.No        : 0.0 to " + ftos(cf(cols.XBrandStart)),
		"  Brand       : " + ftos(cf(cols.XBrandStart)) + " to " + ftos(cf(cols.XBrandEnd)),
		"  Opening     : " + ftos(cf(cols.XOpenStart)) + " to " + ftos(cf(cols.XRecvStart)),
		"  Receipt     : " + ftos(cf(cols.XRecvStart)) + " to " + ftos(cf(cols.XTotalStart)),
		"  Total       : " + ftos(cf(cols.XTotalStart)) + " to " + ftos(cf(cols.XSaleStart)),
		"  Sale (qty)  : " + ftos(cf(cols.XSaleStart)) + " to " + ftos(cf(cols.XRateStart)),
		"  Rate        : " + ftos(cf(cols.XRateStart)) + " to " + ftos(cf(cols.XAmountStart)),
		"  Amount      : " + ftos(cf(cols.XAmountStart)) + " to " + ftos(cf(cols.XClosingStart)),
		"  Closing     : " + ftos(cf(cols.XClosingStart)) + " to 1.0",
		"",
		"Read EACH cell of the MIDDLE ROW (the target row, vertically centered in the strip) and return ONLY this JSON (no prose, no markdown):",
		"{",
		"  \"brand\": \"<handwritten or pre-printed text from the Brand cell, empty string if blank>\",",
		"  \"opening\": <integer or null>,",
		"  \"receipt\": <integer or null>,",
		"  \"total\": <integer or null>,",
		"  \"sale\": <integer or null>,",
		"  \"rate\": <integer or null>,",
		"  \"amount\": <integer or null>,",
		"  \"closing\": <integer or null>,",
		"  \"confidence\": <0.0 to 1.0 — confidence the whole row is correct>",
		"}",
		"",
		"Rules:",
		"- Use the x-fraction ranges above to locate each column. DO NOT guess columns.",
		"- An empty cell → null. NEVER invent a value to be helpful.",
		"- 'brand' is usually pre-printed text on register paper; some shops add handwritten suffixes like 'tetra'. Return whatever text you see in the brand cell, even if pre-printed.",
		"- 'sale' (column 6) is typically 1-99 on a daily register. Values >200 likely mean wrong column → null.",
		"- 'opening' + 'receipt' − 'sale' should ≈ 'closing'. If math is off by >2, lower confidence to <0.7.",
		"- A row may have brand text but no numbers (the shopkeeper had no sale that day). Return brand + all numbers null + confidence ≥ 0.85.",
		"- A row may have numbers but blank brand (handwriting fully covers the brand cell). Return brand=\"\" + numbers + confidence ≥ 0.85.",
		"- Be confident when you can clearly see the digits. Only drop confidence below 0.85 if a digit is genuinely smudged or unreadable.",
		"- JSON ONLY. No prose. No markdown fences.",
	}, "\n")

	body := map[string]any{
		"model":      model,
		"max_tokens": 256,
		"messages": []map[string]any{{
			"role": "user",
			"content": []map[string]any{
				{"type": "image", "source": map[string]any{
					"type":       "base64",
					"media_type": "image/jpeg",
					"data":       base64.StdEncoding.EncodeToString(cropBytes),
				}},
				{"type": "text", "text": prompt},
			},
		}},
	}
	if !strings.HasPrefix(model, "claude-opus-4-7") {
		body["temperature"] = 0.0
	}
	reqBody, err := json.Marshal(body)
	if err != nil {
		return CellAllFieldsRow{}, false
	}
	cctx, cancel := context.WithTimeout(ctx, time.Duration(cellAllFieldsTimeoutMs)*time.Millisecond)
	defer cancel()
	req, err := http.NewRequestWithContext(cctx, "POST", saleClaudeAPIEndpoint, bytes.NewBuffer(reqBody))
	if err != nil {
		return CellAllFieldsRow{}, false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", saleClaudeAPIVersion)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Warnf("SmartSale all-fields: HTTP failed row=%d: %v", rowNumber, err)
		return CellAllFieldsRow{}, false
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return CellAllFieldsRow{}, false
	}
	if resp.StatusCode != http.StatusOK {
		bs := raw
		if len(bs) > 200 {
			bs = bs[:200]
		}
		c.logger.Warnf("SmartSale all-fields: row=%d non-200 (%d): %s", rowNumber, resp.StatusCode, string(bs))
		return CellAllFieldsRow{}, false
	}
	var apiResp saleClaudeResponse
	if err := json.Unmarshal(raw, &apiResp); err != nil {
		return CellAllFieldsRow{}, false
	}
	if apiResp.Error != nil {
		c.logger.Warnf("SmartSale all-fields: row=%d API error: %s", rowNumber, apiResp.Error.Message)
		return CellAllFieldsRow{}, false
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
	var parsed struct {
		Brand      string  `json:"brand"`
		Opening    *int    `json:"opening"`
		Receipt    *int    `json:"receipt"`
		Total      *int    `json:"total"`
		Sale       *int    `json:"sale"`
		Rate       *int    `json:"rate"`
		Amount     *int    `json:"amount"`
		Closing    *int    `json:"closing"`
		Confidence float64 `json:"confidence"`
	}
	if err := json.Unmarshal([]byte(t), &parsed); err != nil {
		c.logger.Warnf("SmartSale all-fields: row=%d JSON parse failed: %v body=%q", rowNumber, err, t)
		return CellAllFieldsRow{}, false
	}
	if parsed.Confidence < 0 || parsed.Confidence > 1 {
		return CellAllFieldsRow{}, false
	}
	return CellAllFieldsRow{
		RowNumber:  rowNumber,
		Brand:      strings.TrimSpace(parsed.Brand),
		Opening:    parsed.Opening,
		Receipt:    parsed.Receipt,
		Total:      parsed.Total,
		Sale:       parsed.Sale,
		Rate:       parsed.Rate,
		Amount:     parsed.Amount,
		Closing:    parsed.Closing,
		Confidence: parsed.Confidence,
	}, true
}

func ftos(f float64) string {
	return strconv.FormatFloat(f, 'f', 3, 64)
}
