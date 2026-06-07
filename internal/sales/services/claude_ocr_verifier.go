package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"strings"
)

// v1.0.131 — Smart Sale Opus 4.7 verifier. PARITY:
// smart_stock_setup_claude.go:378-553 + buildVerifierCrops L564-643.
//
// After the Claude main pass returns a ReceiptExtractionResult, this method
// finds the lowest-confidence rows (Confidence < saleClaudeVerifierConfFloor),
// caps the set at saleClaudeVerifierMaxRows, slices the source image into
// header + per-row Y-bands, and asks Opus 4.7 to re-read just those rows. On
// disagreement Opus's per-row output overrides the primary; on agreement the
// primary's confidence is bumped to 0.92.
//
// Most jobs touch zero verifier calls because Sonnet's average confidence is
// already high. The cost is bounded: max 5 disputed rows per page, one Opus
// call per page that has any low-conf rows.
//
// Returns the primary slice unchanged on any error — verifier is best-effort
// and must NEVER block the happy path.

const (
	saleClaudeDefaultVerifier      = "claude-opus-4-7"
	saleClaudeVerifierMaxRows      = 5
	saleClaudeVerifierDefConfFloor = 0.75
)

// saleClaudeVerifierConfFloor is now env-tunable. v1.0.133-r10: dropped from
// 0.85 to 0.75 by default — halves verifier load. Tighten further with
// SMART_SALE_VERIFIER_MIN_CONF=0.65 to almost eliminate Opus calls.
func saleClaudeVerifierConfFloor() float64 {
	v := os.Getenv("SMART_SALE_VERIFIER_MIN_CONF")
	if v == "" {
		return saleClaudeVerifierDefConfFloor
	}
	var f float64
	_, err := fmt.Sscanf(v, "%f", &f)
	if err != nil || f <= 0 || f > 1 {
		return saleClaudeVerifierDefConfFloor
	}
	return f
}

// verifierItem is the per-row payload Opus returns. Same JSON keys as
// ExtractedReceiptItem so we can unmarshal directly into the same struct;
// declared here only as a doc-comment anchor — actual unmarshal target is
// ReceiptExtractionResult.

// VerifyLowConfRows runs the Opus 4.7 re-read pass on rows with
// Confidence < saleClaudeVerifierConfFloor. Returns primary unchanged on any
// error. Caller MUST pass the same imageBytes/imageType used for the main pass
// (the Y-band crop math depends on the same source image).
func (c *ClaudeOCRService) VerifyLowConfRows(ctx context.Context, imageBytes []byte, imageType string, productNames []string, primary []ExtractedReceiptItem) ([]ExtractedReceiptItem, error) {
	if c == nil || c.apiKey == "" {
		return primary, nil
	}
	if len(primary) == 0 {
		return primary, nil
	}

	type idxConf struct {
		idx  int
		conf float64
	}
	confFloor := saleClaudeVerifierConfFloor()
	var lowConf []idxConf
	for i, item := range primary {
		if item.Confidence > 0 && item.Confidence < confFloor {
			lowConf = append(lowConf, idxConf{i, item.Confidence})
		}
	}
	if len(lowConf) == 0 {
		return primary, nil
	}
	for i := 0; i < len(lowConf); i++ {
		for j := i + 1; j < len(lowConf); j++ {
			if lowConf[j].conf < lowConf[i].conf {
				lowConf[i], lowConf[j] = lowConf[j], lowConf[i]
			}
		}
	}
	if len(lowConf) > saleClaudeVerifierMaxRows {
		lowConf = lowConf[:saleClaudeVerifierMaxRows]
	}

	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(imageType), "png") {
		mediaType = "image/png"
	}

	totalRows := 0
	for _, it := range primary {
		if it.RowNumber > totalRows {
			totalRows = it.RowNumber
		}
	}
	rowNumbers := make([]int, 0, len(lowConf))
	for _, lc := range lowConf {
		rowNumbers = append(rowNumbers, primary[lc.idx].RowNumber)
	}
	// v1.0.133-r10 — when CV sidecar exposes row Y-bounds via context, prefer
	// those over the linear-partition heuristic. CV-driven crops land on the
	// correct pixels even when the AI's row counter has drifted (which is the
	// dominant column-drift bug class on dense 180/375/750 ml registers).
	cropContent, useCrops := buildSaleVerifierCropsCVFirst(c, ctx, imageBytes, rowNumbers, totalRows)

	var focus strings.Builder
	focus.WriteString("VERIFY ONLY THESE ROWS. Return JSON {\"items\":[...]} with one entry per row below using the same Smart Sale schema. If primary read is correct, copy it back with confidence >= 0.92. If wrong, correct it.\n\n")
	if useCrops {
		focus.WriteString("Each cropped image below corresponds to one register row. The first crop is the page header so you have column titles for reference.\n\n")
	}
	focus.WriteString("Rows to verify (Sonnet's reading shown):\n")
	for _, lc := range lowConf {
		p := primary[lc.idx]
		opening, receipt, total, closing := 0, 0, 0, 0
		if p.OpeningStock != nil {
			opening = *p.OpeningStock
		}
		if p.Receipt != nil {
			receipt = *p.Receipt
		}
		if p.Total != nil {
			total = *p.Total
		}
		if p.ClosingStock != nil {
			closing = *p.ClosingStock
		}
		rate, amount := 0.0, 0.0
		if p.RatePerUnit != nil {
			rate = *p.RatePerUnit
		}
		if p.Price != nil {
			amount = *p.Price
		}
		focus.WriteString(fmt.Sprintf("- Row %d page %d: brand=%q opening=%d receipt=%d total=%d sale=%d closing=%d rate=%.0f amount=%.0f conf=%.2f\n",
			p.RowNumber, p.PageNumber, p.Brand, opening, receipt, total, closing, p.Quantity, rate, amount, p.Confidence))
	}

	verifierModel := os.Getenv("CLAUDE_VERIFIER_MODEL")
	if verifierModel == "" {
		verifierModel = saleClaudeDefaultVerifier
	}

	contentBlocks := []saleClaudeContent{}
	if useCrops {
		contentBlocks = append(contentBlocks, cropContent...)
	} else {
		base64Image := base64.StdEncoding.EncodeToString(imageBytes)
		contentBlocks = append(contentBlocks, saleClaudeContent{
			Type:   "image",
			Source: &saleClaudeImageSrc{Type: "base64", MediaType: mediaType, Data: base64Image},
		})
	}
	contentBlocks = append(contentBlocks, saleClaudeContent{Type: "text", Text: focus.String()})

	systemPrompt := buildSaleClaudeSystemPrompt(productNames)
	systemBlocks := []saleClaudeContent{{
		Type: "text",
		Text: systemPrompt,
		CacheControl: &struct {
			Type string `json:"type"`
		}{Type: "ephemeral"},
	}}

	// Opus 4.7 deprecated the `temperature` parameter. Build the JSON
	// manually so we can omit it for verifier calls; main extractors keep
	// their explicit 0.0 setting via saleClaudeRequest.
	requestPayload := map[string]interface{}{
		"model":      verifierModel,
		"max_tokens": 2048,
		"system":     systemBlocks,
		"messages":   []saleClaudeMessage{{Role: "user", Content: contentBlocks}},
	}
	requestBody, err := json.Marshal(requestPayload)
	if err != nil {
		return primary, fmt.Errorf("smart sale verifier marshal failed: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", saleClaudeAPIEndpoint, bytes.NewBuffer(requestBody))
	if err != nil {
		return primary, fmt.Errorf("smart sale verifier build failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", saleClaudeAPIVersion)
	req.Header.Set("anthropic-beta", saleClaudeBetaCache)

	c.logger.Infof("SmartSale Claude: Opus verifier checking %d low-conf rows (model=%s)", len(lowConf), verifierModel)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return primary, fmt.Errorf("smart sale verifier request failed: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return primary, fmt.Errorf("smart sale verifier read failed: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return primary, fmt.Errorf("smart sale verifier api error %d: %s", resp.StatusCode, truncateForLog(string(body), 400))
	}

	var apiResp saleClaudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return primary, fmt.Errorf("smart sale verifier parse failed: %w", err)
	}
	if apiResp.Error != nil {
		return primary, fmt.Errorf("smart sale verifier error: %s", apiResp.Error.Message)
	}

	var textOut strings.Builder
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			textOut.WriteString(b.Text)
		}
	}
	clean := strings.TrimSpace(textOut.String())
	if strings.HasPrefix(clean, "```") {
		if idx := strings.Index(clean, "\n"); idx > 0 {
			clean = clean[idx+1:]
		}
		clean = strings.TrimSuffix(clean, "```")
		clean = strings.TrimSpace(clean)
	}
	var verified ReceiptExtractionResult
	if err := json.Unmarshal([]byte(clean), &verified); err != nil {
		var arr []ExtractedReceiptItem
		if err2 := json.Unmarshal([]byte(clean), &arr); err2 == nil {
			verified.Items = arr
		} else {
			c.logger.Warnf("SmartSale Claude: verifier returned unparseable JSON; keeping primary read (err=%v)", err)
			return primary, nil
		}
	}

	overrides, agreements := 0, 0
	out := make([]ExtractedReceiptItem, len(primary))
	copy(out, primary)
	for _, v := range verified.Items {
		matched := false
		for i := range out {
			if out[i].RowNumber == v.RowNumber && out[i].PageNumber == v.PageNumber {
				disagree := !saleVerifierEqual(out[i], v)
				if disagree {
					oldBrand, oldQty := out[i].Brand, out[i].Quantity
					oldRate := 0.0
					if out[i].RatePerUnit != nil {
						oldRate = *out[i].RatePerUnit
					}
					newRate := 0.0
					if v.RatePerUnit != nil {
						newRate = *v.RatePerUnit
					}
					c.logger.Infof("SmartSale Claude: verifier disagreed on row %d page %d — overriding (was %q sale=%d rate=%.0f, now %q sale=%d rate=%.0f)",
						v.RowNumber, v.PageNumber, oldBrand, oldQty, oldRate, v.Brand, v.Quantity, newRate)
					v.Source = "claude_verifier"
					out[i] = v
					overrides++
				} else {
					if out[i].Confidence < 0.92 {
						out[i].Confidence = 0.92
					}
					agreements++
				}
				matched = true
				break
			}
		}
		if !matched {
			c.logger.Warnf("SmartSale Claude: verifier produced row %d page %d that doesn't match any primary row — ignoring",
				v.RowNumber, v.PageNumber)
		}
	}
	c.logger.Infof("SmartSale Claude: verifier finished — %d agreements, %d overrides", agreements, overrides)
	return out, nil
}

// saleVerifierEqual returns true when two ExtractedReceiptItems describe the
// same data (modulo confidence/source/raw_text). Used by the verifier to decide
// whether Opus's read was an agreement or a real correction.
func saleVerifierEqual(a, b ExtractedReceiptItem) bool {
	if !strings.EqualFold(strings.TrimSpace(a.Brand), strings.TrimSpace(b.Brand)) {
		return false
	}
	if a.Quantity != b.Quantity {
		return false
	}
	if a.SizeML != 0 && b.SizeML != 0 && a.SizeML != b.SizeML {
		return false
	}
	floatPtrEq := func(x, y *float64) bool {
		xv, yv := 0.0, 0.0
		if x != nil {
			xv = *x
		}
		if y != nil {
			yv = *y
		}
		d := xv - yv
		if d < 0 {
			d = -d
		}
		return d < 0.5
	}
	intPtrEq := func(x, y *int) bool {
		xv, yv := 0, 0
		if x != nil {
			xv = *x
		}
		if y != nil {
			yv = *y
		}
		return xv == yv
	}
	if !floatPtrEq(a.RatePerUnit, b.RatePerUnit) {
		return false
	}
	if !floatPtrEq(a.Price, b.Price) {
		return false
	}
	if !intPtrEq(a.OpeningStock, b.OpeningStock) {
		return false
	}
	if !intPtrEq(a.ClosingStock, b.ClosingStock) {
		return false
	}
	return true
}

// buildSaleVerifierCrops slices the source image into a header strip plus one
// focused band per disputed row. PARITY: smart_stock_setup_claude.go's
// buildVerifierCrops L564-643 — same Y-band math (rowNumber/totalRows ×
// imageHeight, ±2% padding, header = top 10%). Returns (nil, false) on decode
// failure or when fewer than 2 disputed rows exist (full-image fallback is
// just as cheap for one row).
func buildSaleVerifierCrops(c *ClaudeOCRService, imageBytes []byte, rowNumbers []int, totalRows int) ([]saleClaudeContent, bool) {
	if len(rowNumbers) < 2 || totalRows < 4 {
		return nil, false
	}
	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		c.logger.Warnf("SmartSale Claude: verifier crop decode failed (using full image): %v", err)
		return nil, false
	}
	bounds := src.Bounds()
	W, H := bounds.Dx(), bounds.Dy()
	if W < 200 || H < 200 {
		return nil, false
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
	out := make([]saleClaudeContent, 0, len(rowNumbers)+1)
	encode := func(img image.Image) (saleClaudeContent, bool) {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 88}); err != nil {
			return saleClaudeContent{}, false
		}
		return saleClaudeContent{
			Type: "image",
			Source: &saleClaudeImageSrc{
				Type:      "base64",
				MediaType: "image/jpeg",
				Data:      base64.StdEncoding.EncodeToString(buf.Bytes()),
			},
		}, true
	}
	headerH := H / 10
	if headerH < 60 {
		headerH = 60
	}
	if cb, ok2 := encode(si.SubImage(image.Rect(bounds.Min.X, bounds.Min.Y, bounds.Max.X, bounds.Min.Y+headerH))); ok2 {
		out = append(out, cb)
	}
	pad := H / 50
	for _, row := range rowNumbers {
		if row <= 0 {
			continue
		}
		rowSpan := H - headerH
		y0 := bounds.Min.Y + headerH + (row-1)*rowSpan/totalRows - pad
		y1 := bounds.Min.Y + headerH + row*rowSpan/totalRows + pad
		if y0 < bounds.Min.Y {
			y0 = bounds.Min.Y
		}
		if y1 > bounds.Max.Y {
			y1 = bounds.Max.Y
		}
		if y1-y0 < 30 {
			continue
		}
		if cb, ok2 := encode(si.SubImage(image.Rect(bounds.Min.X, y0, bounds.Max.X, y1))); ok2 {
			out = append(out, cb)
		}
	}
	if len(out) < 2 {
		return nil, false
	}
	c.logger.Infof("SmartSale Claude: verifier sending %d cropped bands (header + %d rows of %d)", len(out), len(out)-1, totalRows)
	return out, true
}
