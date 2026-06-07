package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png" // decoder registration
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

// Anthropic Messages API request/response types (v2023-06-01).
// We model only the subset needed: text + image content blocks, prompt-cache
// markers, assistant text response. Tool-use schema isn't required because
// the model returns JSON in the assistant text and we parse via the shared
// parseStockRegisterResponse() helper — same pattern as Gemini and OpenAI.

type claudeImageSource struct {
	Type      string `json:"type"`
	MediaType string `json:"media_type"`
	Data      string `json:"data"`
}

type claudeContent struct {
	Type         string             `json:"type"`
	Text         string             `json:"text,omitempty"`
	Source       *claudeImageSource `json:"source,omitempty"`
	CacheControl *struct {
		Type string `json:"type"`
	} `json:"cache_control,omitempty"`
}

type claudeMessage struct {
	Role    string          `json:"role"`
	Content []claudeContent `json:"content"`
}

type claudeRequest struct {
	Model       string          `json:"model"`
	MaxTokens   int             `json:"max_tokens"`
	Temperature float64         `json:"temperature"`
	System      []claudeContent `json:"system,omitempty"`
	Messages    []claudeMessage `json:"messages"`
}

type claudeResponseUsage struct {
	InputTokens              int `json:"input_tokens"`
	OutputTokens             int `json:"output_tokens"`
	CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
	CacheReadInputTokens     int `json:"cache_read_input_tokens"`
}

type claudeResponseBlock struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
}

type claudeResponse struct {
	ID         string                `json:"id"`
	Type       string                `json:"type"`
	Role       string                `json:"role"`
	Model      string                `json:"model"`
	Content    []claudeResponseBlock `json:"content"`
	StopReason string                `json:"stop_reason"`
	Usage      claudeResponseUsage   `json:"usage"`
	Error      *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

const (
	claudeAPIEndpoint       = "https://api.anthropic.com/v1/messages"
	claudeAPIVersion        = "2023-06-01"
	claudeBetaPromptCaching = "prompt-caching-2024-07-31"
	claudeDefaultPrimary    = "claude-sonnet-4-6"
	claudeDefaultVerifier   = "claude-opus-4-7"
	claudeMaxOutputTokens      = 8192
	claudeVerifierMaxRows      = 5
	claudeVerifierDefConfFloor = 0.75 // v1.0.134 dropped 0.85→0.75 (parity with Smart Sale r10)
	// Self-consistency voting — Phase 2.7. When SMART_STOCK_SETUP_VOTE >= 2,
	// run the primary extractor that many times at temperature voteTemperature
	// and vote per cell. Disagreement on any of (brand/opening/sale/rate/amount)
	// flags the row needs_review with confidence capped at votePenaltyConf so
	// the user is forced to confirm before the row is approved silently.
	voteTemperature = 0.3
	votePenaltyConf = 0.55
	voteMaxPasses   = 3
)

// stockSetupVerifierConfFloor returns the confidence threshold below which
// rows are sent to the Opus verifier. v1.0.134: env-tunable, default 0.75
// (was hardcoded 0.85). Set SMART_STOCK_SETUP_VERIFIER_MIN_CONF=0.65 to
// verify almost every row, or =0.85 to revert to pre-r10 behavior.
func stockSetupVerifierConfFloor() float64 {
	v := os.Getenv("SMART_STOCK_SETUP_VERIFIER_MIN_CONF")
	if v == "" {
		return claudeVerifierDefConfFloor
	}
	var f float64
	if _, err := fmt.Sscanf(v, "%f", &f); err == nil && f > 0 && f <= 1 {
		return f
	}
	return claudeVerifierDefConfFloor
}

// extractRegisterWithClaude is the Phase 2.2 primary OCR path. Sonnet 4.6 with
// prompt caching reads the register image and returns structured JSON. The
// static prompt (rules + product list + master brands) is sent as the cached
// system block so subsequent calls within the cache window pay ~10% of the
// input-token cost.
//
// When SMART_STOCK_SETUP_VOTE=2 (or 3), runs the extractor that many times at
// non-zero temperature and votes per cell — the second/third pass benefits
// from the warm prompt cache so it's cheap. Cells where passes disagree are
// flagged needs_review with confidence forced down to votePenaltyConf.
func (s *SmartPurchaseOCR) extractRegisterWithClaude(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames []string, masterBrandNames []string) (*StockRegisterExtractionResult, error) {
	votePasses := 1
	if vp, err := strconv.Atoi(os.Getenv("SMART_STOCK_SETUP_VOTE")); err == nil && vp > 1 {
		votePasses = vp
		if votePasses > voteMaxPasses {
			votePasses = voteMaxPasses
		}
	}

	if votePasses > 1 {
		return s.extractRegisterWithClaudeVoting(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, votePasses)
	}
	return s.extractRegisterWithClaudeSingle(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, 0.0)
}

// extractRegisterWithClaudeSingle is the original single-pass extractor. The
// temperature parameter lets the voting wrapper retry at temp>0 to encourage
// diverse readings the vote can disagree on. temperature=0 is the default
// when called directly.
func (s *SmartPurchaseOCR) extractRegisterWithClaudeSingle(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames []string, masterBrandNames []string, temperature float64) (*StockRegisterExtractionResult, error) {
	if s.anthropicKey == "" {
		return nil, fmt.Errorf("anthropic api key not configured")
	}

	// v1.0.134 — pre-send image optimizer (parity with Smart Sale r10).
	origLen := len(imageBytes)
	optBytes, optMediaType := optimizeStockSetupImageForClaude(imageBytes)
	if len(optBytes) != origLen {
		log.Printf("Smart Stock Setup OCR: image optimized %d → %d bytes (%.1f%% saved)",
			origLen, len(optBytes), 100*(1-float64(len(optBytes))/float64(origLen)))
	}
	imageBytes = optBytes
	mediaType := optMediaType
	if strings.Contains(strings.ToLower(contentType), "png") && len(imageBytes) == origLen {
		mediaType = "image/png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)

	systemPrompt := buildStockRegisterPromptWithHints(ctx, categoryName, sizeML, productNames, masterBrandNames)

	// v1.0.134 — CV sidecar blank-row signal. Per-image hint goes AFTER the
	// cached static prompt so the cache prefix isn't invalidated.
	cvHint := ""
	if h, ok := ctx.Value(StockSetupCVHintsCtxKey).(string); ok {
		cvHint = h
	}

	systemBlocks := []claudeContent{
		{
			Type: "text",
			Text: systemPrompt,
			CacheControl: &struct {
				Type string `json:"type"`
			}{Type: "ephemeral"},
		},
	}
	if cvHint != "" {
		systemBlocks = append(systemBlocks, claudeContent{
			Type: "text",
			Text: cvHint,
		})
	}
	userBlocks := []claudeContent{
		{Type: "image", Source: &claudeImageSource{
			Type: "base64", MediaType: mediaType, Data: base64Image,
		}},
		{Type: "text", Text: "Extract the stock register from this image. Return a single JSON object matching the schema in the system prompt — no prose, no markdown fences, just JSON."},
	}

	model := os.Getenv("CLAUDE_PRIMARY_MODEL")
	if model == "" {
		model = claudeDefaultPrimary
	}

	request := claudeRequest{
		Model:       model,
		MaxTokens:   claudeMaxOutputTokens,
		Temperature: temperature,
		System:      systemBlocks,
		Messages:    []claudeMessage{{Role: "user", Content: userBlocks}},
	}

	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("claude marshal failed: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", claudeAPIEndpoint, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("claude request build failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.anthropicKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)
	req.Header.Set("anthropic-beta", claudeBetaPromptCaching)

	log.Printf("Smart Stock Setup OCR: Sending to Claude %s (products: %d, masters: %d, prompt: %d chars)",
		model, len(productNames), len(masterBrandNames), len(systemPrompt))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("claude request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("claude read body failed: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claude api error %d: %s", resp.StatusCode, string(body))
	}

	var apiResp claudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("claude parse response failed: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("claude error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Content) == 0 {
		return nil, fmt.Errorf("claude returned empty content")
	}

	var textOut strings.Builder
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			textOut.WriteString(b.Text)
		}
	}

	log.Printf("Smart Stock Setup OCR: Claude responded — input=%d output=%d cache_create=%d cache_read=%d (model=%s, stop=%s)",
		apiResp.Usage.InputTokens, apiResp.Usage.OutputTokens,
		apiResp.Usage.CacheCreationInputTokens, apiResp.Usage.CacheReadInputTokens,
		apiResp.Model, apiResp.StopReason)

	return parseStockRegisterResponse(textOut.String())
}

// extractRegisterWithClaudeVoting runs the extractor `passes` times at
// non-zero temperature and votes per cell. Pass 1 is at temperature=0
// (deterministic baseline); subsequent passes are at voteTemperature so the
// model surfaces alternative readings.
//
// Voting rule (per row):
//   - The row must agree across all passes on (RowNumber, PageNumber). If
//     primary pass has a row no later pass has, primary wins.
//   - For each numeric/text cell (Brand, Opening, Receipt, Total, Sale,
//     Closing, Rate, Amount): if all passes agree, keep value, set
//     field_confidence to max(any-pass conf, 0.95).
//   - If any pass disagrees, the cell takes the modal (most-common) value;
//     field_confidence drops to votePenaltyConf and the row is flagged
//     needs_review with a warning naming the disagreeing field.
//
// Cost: pass 2+ benefits from the warm prompt cache (~10% of input tokens),
// so 2-pass voting roughly costs 1.1× of single-pass — small price for the
// "did the AI read this consistently?" signal.
func (s *SmartPurchaseOCR) extractRegisterWithClaudeVoting(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames []string, masterBrandNames []string, passes int) (*StockRegisterExtractionResult, error) {
	results := make([]*StockRegisterExtractionResult, 0, passes)
	for p := 0; p < passes; p++ {
		temp := 0.0
		if p > 0 {
			temp = voteTemperature
		}
		r, err := s.extractRegisterWithClaudeSingle(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, temp)
		if err != nil {
			if len(results) == 0 {
				return nil, fmt.Errorf("voting pass %d failed: %w", p+1, err)
			}
			log.Printf("Smart Stock Setup OCR: voting pass %d failed (%v), continuing with %d passes", p+1, err, len(results))
			break
		}
		results = append(results, r)
	}
	if len(results) == 1 {
		return results[0], nil
	}

	primary := results[0]
	rest := results[1:]
	for i := range primary.Items {
		row := &primary.Items[i]
		// Find the same row in each subsequent pass.
		others := make([]*ExtractedStockRegisterItem, 0, len(rest))
		for _, o := range rest {
			for j := range o.Items {
				if o.Items[j].RowNumber == row.RowNumber && o.Items[j].PageNumber == row.PageNumber {
					others = append(others, &o.Items[j])
					break
				}
			}
		}
		if len(others) == 0 {
			continue // primary's row wasn't found in any other pass — keep as-is, no penalty
		}

		// Per-field vote.
		fieldsDisagreed := []string{}
		if disagree := func() bool {
			for _, o := range others {
				if o.Brand != row.Brand {
					return true
				}
			}
			return false
		}(); disagree {
			fieldsDisagreed = append(fieldsDisagreed, "brand")
		}
		if anyDiffInt(row.Opening, others, func(o *ExtractedStockRegisterItem) int { return o.Opening }) {
			fieldsDisagreed = append(fieldsDisagreed, "opening")
		}
		if anyDiffInt(row.Receipt, others, func(o *ExtractedStockRegisterItem) int { return o.Receipt }) {
			fieldsDisagreed = append(fieldsDisagreed, "receipt")
		}
		if anyDiffInt(row.Total, others, func(o *ExtractedStockRegisterItem) int { return o.Total }) {
			fieldsDisagreed = append(fieldsDisagreed, "total")
		}
		if anyDiffInt(row.Sale, others, func(o *ExtractedStockRegisterItem) int { return o.Sale }) {
			fieldsDisagreed = append(fieldsDisagreed, "sale")
		}
		if anyDiffInt(row.Closing, others, func(o *ExtractedStockRegisterItem) int { return o.Closing }) {
			fieldsDisagreed = append(fieldsDisagreed, "closing")
		}
		if anyDiffFloat(row.Rate, others, func(o *ExtractedStockRegisterItem) float64 { return o.Rate }) {
			fieldsDisagreed = append(fieldsDisagreed, "rate")
		}
		if anyDiffFloat(row.Amount, others, func(o *ExtractedStockRegisterItem) float64 { return o.Amount }) {
			fieldsDisagreed = append(fieldsDisagreed, "amount")
		}

		if len(fieldsDisagreed) == 0 {
			// All passes agreed — bump confidence floor.
			if row.Confidence < 0.95 {
				row.Confidence = 0.95
			}
			if row.FieldConfidence == nil {
				row.FieldConfidence = map[string]float64{}
			}
			for _, f := range []string{"brand", "opening", "receipt", "total", "sale", "closing", "rate", "amount"} {
				if row.FieldConfidence[f] < 0.95 {
					row.FieldConfidence[f] = 0.95
				}
			}
			continue
		}

		// At least one field disagreed. Drop confidence on the disagreeing
		// fields specifically, plus the row-level confidence.
		log.Printf("Smart Stock Setup OCR: voting disagreement on row %d page %d — fields: %v",
			row.RowNumber, row.PageNumber, fieldsDisagreed)
		if row.Confidence > votePenaltyConf {
			row.Confidence = votePenaltyConf
		}
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		for _, f := range fieldsDisagreed {
			row.FieldConfidence[f] = votePenaltyConf
		}
	}
	log.Printf("Smart Stock Setup OCR: voting (%d passes) complete on %d rows", len(results), len(primary.Items))
	return primary, nil
}

// anyDiffInt returns true when any of `others` disagrees with v on the int field
// produced by extract().
func anyDiffInt(v int, others []*ExtractedStockRegisterItem, extract func(*ExtractedStockRegisterItem) int) bool {
	for _, o := range others {
		if extract(o) != v {
			return true
		}
	}
	return false
}

// anyDiffFloat returns true when any of `others` disagrees with v on the float
// field, with a small tolerance for floating-point noise.
func anyDiffFloat(v float64, others []*ExtractedStockRegisterItem, extract func(*ExtractedStockRegisterItem) float64) bool {
	const eps = 0.01
	for _, o := range others {
		d := extract(o) - v
		if d < 0 {
			d = -d
		}
		if d > eps {
			return true
		}
	}
	return false
}

// verifyRowsWithClaude is the Phase 2.3 verification pass. After the primary
// extractor returns, the orchestrator sends the lowest-confidence rows
// (cap claudeVerifierMaxRows per call) to Opus 4.7 for re-reading. Opus's
// per-row output overrides the primary on disagreement; agreement bumps the
// primary's confidence floor to 0.92. Most jobs touch zero verifier calls
// because Sonnet's average confidence is already high.
func (s *SmartPurchaseOCR) verifyRowsWithClaude(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, primary []ExtractedStockRegisterItem) ([]ExtractedStockRegisterItem, error) {
	if s.anthropicKey == "" {
		return primary, nil
	}

	type idxConf struct {
		idx  int
		conf float64
	}
	confFloor := stockSetupVerifierConfFloor()
	var lowConf []idxConf
	for i, item := range primary {
		if item.Confidence < confFloor {
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
	if len(lowConf) > claudeVerifierMaxRows {
		lowConf = lowConf[:claudeVerifierMaxRows]
	}

	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(contentType), "png") {
		mediaType = "image/png"
	}

	// WS-2.5: per-row Y-band cropping. Send Opus a header strip plus one
	// focused crop per disputed row so the model isn't distracted by the
	// rest of the page. Falls back to the full-image text-hint flow when
	// decoding fails or there's only one disputed row (cropping ROI ≈
	// page anyway). Estimate Y-band by rowNumber/totalRows × imageHeight.
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
	// v1.0.134 — prefer pixel-accurate CV-driven crops when the sidecar
	// detected row Y-bounds for this image. Fixes the column-drift bug class
	// where the AI's row counter has slipped from the actual register row.
	cropContent, useCrops := buildStockSetupVerifierCropsCVFirst(ctx, imageBytes, rowNumbers, totalRows)

	var focus strings.Builder
	focus.WriteString("VERIFY ONLY THESE ROWS. Return JSON {\"items\":[...]} with one entry per row below using the same extraction schema. If primary read is correct, copy it back with confidence >= 0.92. If wrong, correct it.\n\n")
	if categoryName != "" || sizeML > 0 {
		focus.WriteString(fmt.Sprintf("Context: %s %dML register page.\n\n", categoryName, sizeML))
	}
	if useCrops {
		focus.WriteString("Each cropped image below corresponds to one register row. The first crop is the page header so you have column titles for reference.\n\n")
	}
	focus.WriteString("Rows to verify (Sonnet's reading shown):\n")
	for _, lc := range lowConf {
		p := primary[lc.idx]
		focus.WriteString(fmt.Sprintf("- Row %d page %d: brand=%q opening=%d receipt=%d total=%d sale=%d closing=%d rate=%.0f amount=%.0f conf=%.2f\n",
			p.RowNumber, p.PageNumber, p.Brand, p.Opening, p.Receipt, p.Total, p.Sale, p.Closing, p.Rate, p.Amount, p.Confidence))
	}

	verifierModel := os.Getenv("CLAUDE_VERIFIER_MODEL")
	if verifierModel == "" {
		verifierModel = claudeDefaultVerifier
	}

	// Build the user-message content blocks: either cropped bands (preferred)
	// or the full image (fallback).
	contentBlocks := []claudeContent{}
	if useCrops {
		contentBlocks = append(contentBlocks, cropContent...)
	} else {
		base64Image := base64.StdEncoding.EncodeToString(imageBytes)
		contentBlocks = append(contentBlocks, claudeContent{
			Type:   "image",
			Source: &claudeImageSource{Type: "base64", MediaType: mediaType, Data: base64Image},
		})
	}
	contentBlocks = append(contentBlocks, claudeContent{Type: "text", Text: focus.String()})

	request := claudeRequest{
		Model:       verifierModel,
		MaxTokens:   2048,
		Temperature: 0.0,
		Messages:    []claudeMessage{{Role: "user", Content: contentBlocks}},
	}

	requestBody, err := json.Marshal(request)
	if err != nil {
		return primary, fmt.Errorf("claude verifier marshal failed: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", claudeAPIEndpoint, bytes.NewBuffer(requestBody))
	if err != nil {
		return primary, fmt.Errorf("claude verifier build failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.anthropicKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)

	log.Printf("Smart Stock Setup OCR: Claude Opus verifier checking %d low-conf rows", len(lowConf))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return primary, fmt.Errorf("claude verifier request failed: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return primary, fmt.Errorf("claude verifier read failed: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return primary, fmt.Errorf("claude verifier api error %d: %s", resp.StatusCode, string(body))
	}

	var apiResp claudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return primary, fmt.Errorf("claude verifier parse failed: %w", err)
	}
	if apiResp.Error != nil {
		return primary, fmt.Errorf("claude verifier error: %s", apiResp.Error.Message)
	}

	var textOut strings.Builder
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			textOut.WriteString(b.Text)
		}
	}
	verified, err := parseStockRegisterResponse(textOut.String())
	if err != nil || verified == nil {
		log.Printf("Smart Stock Setup OCR: verifier returned unparseable JSON; keeping primary read (err=%v)", err)
		return primary, nil
	}

	out := make([]ExtractedStockRegisterItem, len(primary))
	copy(out, primary)
	for _, v := range verified.Items {
		matched := false
		for i := range out {
			if out[i].RowNumber == v.RowNumber && out[i].PageNumber == v.PageNumber {
				disagree := out[i].Brand != v.Brand || out[i].Opening != v.Opening ||
					out[i].Receipt != v.Receipt || out[i].Total != v.Total ||
					out[i].Sale != v.Sale || out[i].Closing != v.Closing ||
					out[i].Rate != v.Rate || out[i].Amount != v.Amount
				if disagree {
					log.Printf("Smart Stock Setup OCR: verifier disagreed on row %d page %d — overriding (was %q sale=%d rate=%.0f, now %q sale=%d rate=%.0f)",
						v.RowNumber, v.PageNumber, out[i].Brand, out[i].Sale, out[i].Rate, v.Brand, v.Sale, v.Rate)
					v.Source = "claude_verifier"
					out[i] = v
				} else {
					if out[i].Confidence < 0.92 {
						out[i].Confidence = 0.92
					}
				}
				matched = true
				break
			}
		}
		if !matched {
			log.Printf("Smart Stock Setup OCR: verifier produced row %d page %d that doesn't match any primary row — ignoring",
				v.RowNumber, v.PageNumber)
		}
	}
	return out, nil
}


// buildVerifierCrops slices the source image into a header strip plus one
// focused band per disputed row, encodes each to JPEG, and returns Claude
// content blocks. Returns (nil, false) on decode failure or when fewer than
// 2 disputed rows exist (full-image fallback is just as cheap).
//
// Y-band estimation: rowNumber/totalRows × imageHeight. Bands are padded ±10%
// on each side so the row's neighbours stay visible (helps Opus disambiguate
// when handwriting straddles a row boundary). Header strip = top 10% of page.
func buildVerifierCrops(imageBytes []byte, rowNumbers []int, totalRows int) ([]claudeContent, bool) {
	if len(rowNumbers) < 2 || totalRows < 4 {
		return nil, false
	}
	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		log.Printf("Smart Stock Setup OCR: verifier crop decode failed (using full image): %v", err)
		return nil, false
	}
	bounds := src.Bounds()
	W, H := bounds.Dx(), bounds.Dy()
	if W < 200 || H < 200 {
		return nil, false // image too small to crop usefully
	}
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	si, ok := src.(subImager)
	if !ok {
		// RGBA copy if decoded type doesn't support SubImage directly.
		rgba := image.NewRGBA(bounds)
		for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
			for x := bounds.Min.X; x < bounds.Max.X; x++ {
				rgba.Set(x, y, src.At(x, y))
			}
		}
		si = rgba
	}
	out := make([]claudeContent, 0, len(rowNumbers)+1)
	encode := func(img image.Image) (claudeContent, bool) {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 88}); err != nil {
			return claudeContent{}, false
		}
		return claudeContent{
			Type: "image",
			Source: &claudeImageSource{
				Type:      "base64",
				MediaType: "image/jpeg",
				Data:      base64.StdEncoding.EncodeToString(buf.Bytes()),
			},
		}, true
	}
	// Header strip — top 10% of page.
	headerH := H / 10
	if headerH < 60 {
		headerH = 60
	}
	if c, ok2 := encode(si.SubImage(image.Rect(bounds.Min.X, bounds.Min.Y, bounds.Max.X, bounds.Min.Y+headerH))); ok2 {
		out = append(out, c)
	}
	// One band per disputed row.
	pad := H / 50 // ~2% padding above/below
	for _, row := range rowNumbers {
		if row <= 0 {
			continue
		}
		// Row Y-position: ((row-0.5) / totalRows) × H from header end.
		rowSpan := (H - headerH)
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
		if c, ok2 := encode(si.SubImage(image.Rect(bounds.Min.X, y0, bounds.Max.X, y1))); ok2 {
			out = append(out, c)
		}
	}
	if len(out) < 2 {
		return nil, false
	}
	log.Printf("Smart Stock Setup OCR: verifier sending %d cropped bands (header + %d rows of %d)", len(out), len(out)-1, totalRows)
	return out, true
}
