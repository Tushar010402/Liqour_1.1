package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/jpeg"
	"io"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// v1.0.135 Track F + Track G — sale-quantity 100% push.
//
// Sale extraction occasionally hits a column-drift class where the AI reads
// every cell of a row from the *adjacent* column (e.g. closes the qty cell
// off-by-one and pulls Sale from the Rate column). The page-level OCR sees
// well-formed digits, so confidence stays high and the Track E tri-source
// consensus *agrees* on the wrong number — three drifted reads still vote
// together.
//
// Two complementary fixes:
//
//   F. Cell-level qty re-extraction. After primary + verifier complete, we
//      use the CV sidecar's per-row Y-bounds to crop the Sale column for
//      rows we suspect, send each crop to Sonnet as a single-cell digit
//      read ("what number is in this cell?"), and replace primary qty
//      when the cell-level call returns confidence ≥ cellLevelMinConf.
//      Mirrors Stock Setup's Track B.
//
//   G. Column-drift detector. For every row computes
//      expected_amount = qty * rate. If any row on a page has
//      |expected − actual_amount| / actual_amount > driftThreshold (default
//      5 %), the entire page is flagged drifted and Track F is dispatched
//      across every row of that page (not just low-conf ones). Catches the
//      class where no individual cell looks suspicious but the columns are
//      mis-aligned.
//
// Both are gated by SMART_SALE_CELL_LEVEL_QTY=1 (default off — opt-in cost).
// Cost: ~₹0.02 per cell × ≤8 cells/page = ₹0.16/page when active.
//
// Hallucination guards:
//   • Cell-level result is REJECTED unless confidence ≥ cellLevelMinConf
//     (default 0.92).
//   • If the cell-level value disagrees with BOTH Track-E corroborators
//     (open−close AND amount÷rate), we decline to overwrite — primary wins.
//   • Hard cap at 8 cell calls per image to bound cost on a fully broken page.
//   • Single-purpose prompt forbids prose: "Return ONLY {"value":N,"confidence":0..1}".
//   • temperature=0 + max_tokens=64 to keep outputs stable.

const (
	saleCellLevelDefMinConf      = 0.92
	saleCellLevelDefFieldFloor   = 0.85
	saleCellLevelMaxCellsPerPage = 8
	saleCellLevelTimeoutMs       = 25000

	saleColumnDriftDefThreshold = 0.05 // 5 % delta between qty*rate and amount
	saleColumnDriftMinSignal    = 2    // require ≥2 drifted rows before flagging the page
)

type saleCellLevelResult struct {
	Value      *int    `json:"value"`
	Confidence float64 `json:"confidence"`
}

type SaleCellLevelStats struct {
	Candidates    int `json:"candidates"`
	Called        int `json:"called"`
	Replaced      int `json:"replaced"`
	DriftedPages  int `json:"drifted_pages"`
	DriftedRows   int `json:"drifted_rows"`
	OverwriteConf float64 `json:"overwrite_conf_avg,omitempty"`
}

func saleCellLevelEnabled() bool {
	return os.Getenv("SMART_SALE_CELL_LEVEL_QTY") == "1"
}

func saleCellLevelMinConf() float64 {
	v := os.Getenv("SMART_SALE_CELL_LEVEL_MIN_CONF")
	if v == "" {
		return saleCellLevelDefMinConf
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil && f > 0 && f <= 1 {
		return f
	}
	return saleCellLevelDefMinConf
}

func saleCellLevelFieldFloor() float64 {
	v := os.Getenv("SMART_SALE_CELL_LEVEL_FIELD_FLOOR")
	if v == "" {
		return saleCellLevelDefFieldFloor
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil && f > 0 && f <= 1 {
		return f
	}
	return saleCellLevelDefFieldFloor
}

func saleCellLevelDriftedConfFloor() float64 {
	v := os.Getenv("SMART_SALE_CELL_LEVEL_DRIFTED_MIN_CONF")
	if v == "" {
		return 0.80
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil && f > 0 && f <= 1 {
		return f
	}
	return 0.80
}

func saleColumnDriftThreshold() float64 {
	v := os.Getenv("SMART_SALE_DRIFT_THRESHOLD")
	if v == "" {
		return saleColumnDriftDefThreshold
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil && f > 0 && f < 1 {
		return f
	}
	return saleColumnDriftDefThreshold
}

// detectColumnDriftOnImage runs Track G — returns true when the items on this
// image fail the qty*rate ≈ amount identity by more than the configured
// threshold on at least saleColumnDriftMinSignal rows. We scope this to a
// single image because PageNumber may not yet be stamped onto items at this
// point in the pipeline (goroutine runs before extractFromImages stamps it).
func detectColumnDriftOnImage(items []ExtractedReceiptItem, threshold float64) (bool, int) {
	drifted := 0
	for _, it := range items {
		if it.Quantity <= 0 {
			continue
		}
		if it.RatePerUnit == nil || it.Price == nil {
			continue
		}
		rate := *it.RatePerUnit
		amount := *it.Price
		if rate <= 0 || amount <= 0 {
			continue
		}
		expected := float64(it.Quantity) * rate
		delta := math.Abs(expected-amount) / amount
		if delta > threshold {
			drifted++
		}
	}
	return drifted >= saleColumnDriftMinSignal, drifted
}

// repairLowConfQtyCells implements Track F — cell-level qty micro-extraction.
// Runs only when SMART_SALE_CELL_LEVEL_QTY=1. Per-image (caller loops over
// pages); operates on the items already extracted from THIS image.
//
// imageBytes — same optimized bytes already sent to the primary call.
// pageNumber — the 1-based PageNumber of these items (used to scope drift).
// driftedPage — true when Track G flagged this page; forces re-read on every
//                row (not just low-conf ones).
func (c *ClaudeOCRService) repairLowConfQtyCells(
	ctx context.Context,
	imageBytes []byte,
	items []ExtractedReceiptItem,
	pageNumber int,
	driftedPage bool,
) ([]ExtractedReceiptItem, SaleCellLevelStats) {
	stats := SaleCellLevelStats{}
	if c == nil || c.apiKey == "" || !saleCellLevelEnabled() || len(items) == 0 || len(imageBytes) == 0 {
		return items, stats
	}
	cvRows, _ := ctx.Value(SaleCVRowsCtxKey).([]cvSidecarRow)
	if len(cvRows) < 4 {
		return items, stats
	}

	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		c.logger.Warnf("SmartSale cell-level: decode failed: %v", err)
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

	confFloor := saleCellLevelMinConf()
	fieldFloor := saleCellLevelFieldFloor()
	pad := H / 80
	confSum := 0.0

	// v1.0.135-fix2: send the FULL row strip (not just one column). The model
	// can use the column header context above the row to find the Sale column
	// even when grid alignment is imperfect. Narrow crops are fragile on tilted
	// or hand-drawn registers; full-row crops are self-grounding because the
	// model sees the column boundaries.

	for i := range items {
		if stats.Called >= saleCellLevelMaxCellsPerPage {
			break
		}
		row := &items[i]
		if row.PageNumber != 0 && row.PageNumber != pageNumber {
			continue
		}
		// Identify candidates: drifted page → all rows; otherwise only when
		// quantity-confidence is below the field floor.
		qtyConf := 1.0
		if row.FieldConfidence != nil {
			if v, ok := row.FieldConfidence["quantity"]; ok {
				qtyConf = v
			} else if v, ok := row.FieldConfidence["sale"]; ok {
				qtyConf = v
			}
		}
		needsRepair := driftedPage || qtyConf < fieldFloor || row.Confidence < fieldFloor
		if !needsRepair {
			continue
		}
		idx := row.RowNumber - 1
		if idx < 0 || idx >= len(cvRows) {
			continue
		}
		stats.Candidates++

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
		// Anchor crop above and below: include 1.2 row heights of header context
		// above the target row so the model sees the column labels.
		rowH := y1 - y0
		yHeaderTop := y0 - int(float64(rowH)*1.2)
		if yHeaderTop < bounds.Min.Y {
			yHeaderTop = bounds.Min.Y
		}
		// If we have CV row 0 (the header row), use that as the top anchor.
		if len(cvRows) > 0 && cvRows[0].YTop > 0 && cvRows[0].YTop < y0 {
			yHeaderTop = bounds.Min.Y + cvRows[0].YTop - pad
		}
		strip := si.SubImage(image.Rect(bounds.Min.X, yHeaderTop, bounds.Max.X, y1))
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, strip, &jpeg.Options{Quality: 92}); err != nil {
			continue
		}
		stats.Called++

		res, ok := c.callSaleCellLevelDigit(ctx, buf.Bytes(), "Sale (qty)")
		if !ok {
			c.logger.Infof("SmartSale cell-level: row=%d call returned not-ok", row.RowNumber)
			continue
		}
		valStr := "null"
		if res.Value != nil {
			valStr = strconv.Itoa(*res.Value)
		}
		c.logger.Infof("SmartSale cell-level: row=%d API returned value=%s conf=%.2f primary=%d drifted=%v",
			row.RowNumber, valStr, res.Confidence, row.Quantity, driftedPage)
		// Pick the floor based on regime: drifted pages use a looser floor
		// (Opus is conservative on drifted handwriting), non-drifted use the
		// strict floor since corroboration also has to pass.
		effectiveFloor := confFloor
		if driftedPage {
			effectiveFloor = saleCellLevelDriftedConfFloor()
		}
		if res.Confidence < effectiveFloor {
			c.logger.Infof("SmartSale cell-level: row=%d declined (conf %.2f < floor %.2f, drifted=%v)",
				row.RowNumber, res.Confidence, effectiveFloor, driftedPage)
			continue
		}
		newQty := 0
		if res.Value != nil {
			newQty = *res.Value
		}
		if newQty == row.Quantity {
			c.logger.Infof("SmartSale cell-level: row=%d cell=%d agrees with primary (conf %.2f) — no change",
				row.RowNumber, newQty, res.Confidence)
			continue
		}
		c.logger.Infof("SmartSale cell-level: row=%d primary=%d cell-level=%d (conf %.2f, drifted=%v) — evaluating guards",
			row.RowNumber, row.Quantity, newQty, res.Confidence, driftedPage)
		// Hallucination guard. Two regimes:
		//
		//   • Non-drifted page: require corroboration with at least ONE of
		//     (open-close, amount/rate). If neither corroborates, the cell-
		//     level call itself may have mis-read — primary wins.
		//
		//   • Drifted page (Track G fired): the corroborators are themselves
		//     drifted reads, so corroboration would systematically reject
		//     correct cell-level repairs. In this regime we require ONLY a
		//     higher confidence floor (driftedConfFloor, default 0.95) and
		//     accept the cell-level value as authoritative on the qty cell.
		//
		// Both regimes still gate on confFloor; both still skip when
		// newQty == row.Quantity. So the worst case for any row is "no change".
		if !driftedPage {
			corroborated := false
			if row.OpeningStock != nil && row.ClosingStock != nil {
				s2 := *row.OpeningStock - *row.ClosingStock
				if absInt(s2-newQty) <= 1 {
					corroborated = true
				}
			}
			if !corroborated && row.Price != nil && row.RatePerUnit != nil && *row.RatePerUnit > 0 {
				s3 := int(math.Round(*row.Price / *row.RatePerUnit))
				if absInt(s3-newQty) <= 1 {
					corroborated = true
				}
			}
			if !corroborated {
				c.logger.Infof("SmartSale cell-level: row=%d cell=%d (conf %.2f) declined — no Track-E corroboration on non-drifted page",
					row.RowNumber, newQty, res.Confidence)
				continue
			}
		} else {
			// Drifted regime — Track E2: even on a drifted page, the
			// open-close cells are the LEAST drift-prone columns (they are
			// adjacent extremes of the data band — column 3 and column 9 of
			// 9). When `open − close` is available and within ±1 of either
			// cell-level or amount/rate, take it as authoritative.
			//
			// Decision tree (all comparisons within ±1):
			//   • If S2 (open-close) agrees with cell-level → take that value (any tie wins).
			//   • If S2 agrees with S3 (amount/rate) → take S2; cell-level is the outlier.
			//   • If cell-level agrees with S3 → take cell-level.
			//   • If three pairwise disagreements → take cell-level (Opus
			//     read with conf ≥ floor) but log the conflict.
			//
			// This way the open-close identity is ALWAYS consulted as a
			// 4th source on drifted pages, not just on non-drifted ones.
			if newQty > 200 {
				c.logger.Infof("SmartSale cell-level: row=%d cell=%d (conf %.2f) declined — exceeds plausible per-row qty cap",
					row.RowNumber, newQty, res.Confidence)
				continue
			}
			s2, s2ok := -1, false
			if row.OpeningStock != nil && row.ClosingStock != nil && *row.OpeningStock >= 0 && *row.ClosingStock >= 0 {
				s2 = *row.OpeningStock - *row.ClosingStock
				if s2 >= 0 && s2 <= 200 {
					s2ok = true
				}
			}
			s3, s3ok := -1, false
			if row.Price != nil && row.RatePerUnit != nil && *row.RatePerUnit > 0 && *row.Price > 0 {
				s3 = int(math.Round(*row.Price / *row.RatePerUnit))
				if s3 >= 0 && s3 <= 200 {
					s3ok = true
				}
			}
			finalQty := newQty
			source := "cell-level"
			switch {
			case s2ok && absInt(s2-newQty) <= 1:
				// open-close confirms cell-level
				finalQty = s2
				source = "open-close+cell-level"
			case s2ok && s3ok && absInt(s2-s3) <= 1:
				// open-close + amount/rate agree against cell-level — trust them
				finalQty = s2
				source = "open-close+amount/rate"
				c.logger.Infof("SmartSale cell-level: row=%d cell-level=%d outvoted by open-close=%d, amount/rate=%d",
					row.RowNumber, newQty, s2, s3)
			case s3ok && absInt(s3-newQty) <= 1:
				finalQty = s3
				source = "amount/rate+cell-level"
			default:
				// All three pairwise disagree (or only cell-level is
				// available). Trust cell-level since its floor is high.
				if s2ok || s3ok {
					c.logger.Infof("SmartSale cell-level: row=%d three-way disagreement — cell=%d open-close=%d amount/rate=%d → keeping cell-level",
						row.RowNumber, newQty, s2, s3)
				}
			}
			if finalQty != newQty {
				c.logger.Infof("SmartSale cell-level: row=%d Track E2 promoted %s → qty %d (cell-level was %d)",
					row.RowNumber, source, finalQty, newQty)
				newQty = finalQty
			}
		}
		c.logger.Infof("SmartSale cell-level: row=%d quantity %d → %d (conf %.2f, drifted=%v)",
			row.RowNumber, row.Quantity, newQty, res.Confidence, driftedPage)
		row.Quantity = newQty
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		// v1.0.163 — write both "quantity" and "sale" keys so the
		// flagItemsForReview gate (which checks BOTH keys) sees the repaired
		// confidence. Pre-fix: gate stayed amber on every Track-F-repaired row
		// because the original FieldConfidence["sale"] was still <0.70 even
		// after qty was successfully replaced. Refs chhotu's 64 "AI was
		// unsure of: sale" review rows on May 4 — most were already repaired
		// by Track F but the gate never noticed.
		row.FieldConfidence["quantity"] = res.Confidence
		row.FieldConfidence["sale"] = res.Confidence
		stats.Replaced++
		confSum += res.Confidence
	}
	if stats.Replaced > 0 {
		stats.OverwriteConf = confSum / float64(stats.Replaced)
	}
	if driftedPage {
		stats.DriftedPages = 1
	}
	return items, stats
}

// callSaleCellLevelDigit sends a full-row crop (with header context) to a
// Claude model and parses the Sale column value. The crop spans the entire
// row width AND includes the column-header band above the target row, so
// the model can self-locate the Sale column even on tilted or imperfectly
// gridded photos. Switches to Opus by default for accuracy; override with
// SMART_SALE_CELL_LEVEL_MODEL.
func (c *ClaudeOCRService) callSaleCellLevelDigit(ctx context.Context, cropBytes []byte, column string) (*saleCellLevelResult, bool) {
	if len(cropBytes) == 0 {
		return nil, false
	}
	model := os.Getenv("SMART_SALE_CELL_LEVEL_MODEL")
	if model == "" {
		// Use the verifier model (Opus 4.7) by default — small per-row crops,
		// only fires on suspect rows, and Opus's column-header tracking is
		// noticeably stronger than Sonnet's on dense registers.
		model = os.Getenv("CLAUDE_VERIFIER_MODEL")
	}
	if model == "" {
		model = saleClaudeDefaultModel
	}
	prompt := "" +
		"This image is a strip from a daily-sales register. Columns left-to-right are:\n" +
		"  S.No | Brand | Opening | Receipt | Total | Sale | Rate | Amount | Closing\n\n" +
		"The TOP of the strip shows column headers (or rows above the target). The BOTTOM row of the strip is the TARGET row whose Sale-column (column 6) value I want.\n\n" +
		"Return ONLY valid JSON in this exact shape, with no prose, no markdown:\n" +
		"  {\"value\": <integer or null>, \"confidence\": <0.0-1.0>}\n\n" +
		"Rules:\n" +
		"- \"value\" is the integer written in the Sale (column 6) cell of the BOTTOM row, or null if that cell is empty.\n" +
		"- DO NOT return Opening, Receipt, Total, Rate, Amount, or Closing — only Sale (col 6).\n" +
		"- Sale values on this register are typically 1–99. A value > 200 almost certainly means you read the wrong column — return null + confidence 0.5 in that case.\n" +
		"- \"confidence\" 0.0–1.0; be conservative — < 0.7 if any digit is ambiguous, smudged, or you cannot tell which column you're reading.\n" +
		"- DO NOT invent a value. NULL is the correct answer for empty cells.\n" +
		"- JSON ONLY. No prose. No markdown fences."
	_ = column // single-purpose; kept for future per-column reuse

	// Build the body as a map so we can omit `temperature` for Opus 4.7
	// (which rejects an explicit temperature field).
	body := map[string]any{
		"model":      model,
		"max_tokens": 64,
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
		return nil, false
	}
	cctx, cancel := context.WithTimeout(ctx, time.Duration(saleCellLevelTimeoutMs)*time.Millisecond)
	defer cancel()
	req, err := http.NewRequestWithContext(cctx, "POST", saleClaudeAPIEndpoint, bytes.NewBuffer(reqBody))
	if err != nil {
		c.logger.Warnf("SmartSale cell-level: NewRequest failed: %v", err)
		return nil, false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", saleClaudeAPIVersion)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Warnf("SmartSale cell-level: HTTP failed: %v", err)
		return nil, false
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		c.logger.Warnf("SmartSale cell-level: read body failed: %v", err)
		return nil, false
	}
	if resp.StatusCode != http.StatusOK {
		bodySnippet := raw
		if len(bodySnippet) > 200 {
			bodySnippet = bodySnippet[:200]
		}
		c.logger.Warnf("SmartSale cell-level: non-200 status=%d body=%s", resp.StatusCode, string(bodySnippet))
		return nil, false
	}
	var apiResp saleClaudeResponse
	if err := json.Unmarshal(raw, &apiResp); err != nil {
		bodySnippet := raw
		if len(bodySnippet) > 200 {
			bodySnippet = bodySnippet[:200]
		}
		c.logger.Warnf("SmartSale cell-level: outer JSON unmarshal failed: %v body=%s", err, string(bodySnippet))
		return nil, false
	}
	if apiResp.Error != nil {
		c.logger.Warnf("SmartSale cell-level: API error: %s", apiResp.Error.Message)
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
	var out saleCellLevelResult
	if err := json.Unmarshal([]byte(t), &out); err != nil {
		c.logger.Warnf("SmartSale cell-level: inner JSON unmarshal failed: %v text=%q", err, t)
		return nil, false
	}
	if out.Confidence < 0 || out.Confidence > 1 {
		c.logger.Warnf("SmartSale cell-level: invalid confidence: %v parsed=%+v", out.Confidence, out)
		return nil, false
	}
	c.logger.Debugf("SmartSale cell-level OK: parsed=%+v", out)
	return &out, true
}


