package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

// ClaudeOCRService is the Smart Sale Anthropic Claude extractor (v1.0.119).
// Mirrors the AI Stock Setup Claude integration (smart_stock_setup_claude.go)
// but emits ReceiptExtractionResult — the Smart Sale schema. Activated by
// SMART_SALE_PRIMARY=claude. Falls through to OpenAI when key missing or the
// extractor errors. Same prompt as OpenAI (createLiquorExtractionPrompt) so
// brand-matching parity is preserved across providers.
type ClaudeOCRService struct {
	apiKey       string
	model        string
	httpClient   *http.Client
	logger       *logrus.Logger
	productNames []string // set per-call by ExtractFromImageWithProducts
}

// saleDigitHintsCtxKeyT is a private type for the context key — avoids
// accidental collisions with other libraries' context keys per Go conventions.
type saleDigitHintsCtxKeyT struct{}

// SaleDigitHintsCtxKey is the context key used to inject the per-shop
// digit-handwriting confusion hint into the Claude system prompt. Set by the
// Smart Sale processing path before calling the OCR service.
var SaleDigitHintsCtxKey = saleDigitHintsCtxKeyT{}

// v1.0.133-r5 — alias few-shot key. Loaded by extractFromImages from
// ocr_brand_aliases (tenant-scoped, min-occurrence 3) and prepended to the
// Claude system prompt so confident learned aliases steer the extractor
// instead of being passive corpus rows. Mirrors Stock Setup's FewShotPromptHint.
type saleAliasHintsCtxKeyT struct{}

var SaleAliasHintsCtxKey = saleAliasHintsCtxKeyT{}

const (
	saleClaudeAPIEndpoint     = "https://api.anthropic.com/v1/messages"
	saleClaudeAPIVersion      = "2023-06-01"
	saleClaudeBetaCache       = "prompt-caching-2024-07-31"
	saleClaudeDefaultModel    = "claude-sonnet-4-6"
	saleClaudeMaxOutputTokens = 8192
)

type saleClaudeImageSrc struct {
	Type      string `json:"type"`
	MediaType string `json:"media_type"`
	Data      string `json:"data"`
}
type saleClaudeContent struct {
	Type         string              `json:"type"`
	Text         string              `json:"text,omitempty"`
	Source       *saleClaudeImageSrc `json:"source,omitempty"`
	CacheControl *struct {
		Type string `json:"type"`
	} `json:"cache_control,omitempty"`
}
type saleClaudeMessage struct {
	Role    string              `json:"role"`
	Content []saleClaudeContent `json:"content"`
}
type saleClaudeRequest struct {
	Model       string              `json:"model"`
	MaxTokens   int                 `json:"max_tokens"`
	Temperature float64             `json:"temperature"`
	System      []saleClaudeContent `json:"system,omitempty"`
	Messages    []saleClaudeMessage `json:"messages"`
}
type saleClaudeRespBlock struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
}
type saleClaudeUsage struct {
	InputTokens              int `json:"input_tokens"`
	OutputTokens             int `json:"output_tokens"`
	CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
	CacheReadInputTokens     int `json:"cache_read_input_tokens"`
}
type saleClaudeResponse struct {
	Content    []saleClaudeRespBlock `json:"content"`
	StopReason string                `json:"stop_reason"`
	Usage      *saleClaudeUsage      `json:"usage,omitempty"`
	Error      *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// NewClaudeOCRService — returns nil when ANTHROPIC_API_KEY is unset, allowing
// the smart sale service to fall back to OpenAI without explicit branching.
func NewClaudeOCRService(logger *logrus.Logger) *ClaudeOCRService {
	apiKey := strings.TrimSpace(os.Getenv("ANTHROPIC_API_KEY"))
	if apiKey == "" {
		// Try mounted credentials (matches stock-setup pattern).
		for _, p := range []string{"/app/credentials/anthropic-api-key.txt", "./credentials/anthropic-api-key.txt"} {
			if b, err := os.ReadFile(p); err == nil {
				apiKey = strings.TrimSpace(string(b))
				if apiKey != "" {
					break
				}
			}
		}
	}
	if apiKey == "" {
		logger.Info("SmartSale Claude: ANTHROPIC_API_KEY not configured — Claude path disabled")
		return nil
	}
	model := strings.TrimSpace(os.Getenv("CLAUDE_PRIMARY_MODEL"))
	if model == "" {
		model = saleClaudeDefaultModel
	}
	logger.Infof("SmartSale Claude: enabled (model=%s)", model)
	return &ClaudeOCRService{
		apiKey:     apiKey,
		model:      model,
		httpClient: &http.Client{Timeout: 120 * time.Second},
		logger:     logger,
	}
}

// ExtractFromImageWithProducts mirrors the OpenAI signature so the smart sale
// service can call it interchangeably. Sets productNames for the prompt builder
// (same product-aware prompt body OpenAI uses), then runs the Claude pass.
func (c *ClaudeOCRService) ExtractFromImageWithProducts(ctx context.Context, imageBytes []byte, imageType string, productNames []string) (*ReceiptExtractionResult, error) {
	c.productNames = productNames
	defer func() { c.productNames = nil }()
	return c.ExtractFromImage(ctx, imageBytes, imageType)
}

// ExtractFromImage — single-pass Claude extraction. Uses the same Smart Sale
// liquor-extraction prompt as OpenAI (built via the helper on OpenAIOCRService)
// so the JSON schema and rules are identical across providers.
func (c *ClaudeOCRService) ExtractFromImage(ctx context.Context, imageBytes []byte, imageType string) (*ReceiptExtractionResult, error) {
	if c == nil || c.apiKey == "" {
		return nil, fmt.Errorf("claude not configured")
	}
	startTime := time.Now()

	// v1.0.133-r10 — resize + re-encode before send. ~50% cost cut on input.
	origLen := len(imageBytes)
	imageBytes, mediaType := optimizeImageForClaude(imageBytes)
	if origLen != len(imageBytes) {
		c.logger.Infof("SmartSale Claude: image optimized %d → %d bytes (%.1f%% saving)", origLen, len(imageBytes), 100*(1-float64(len(imageBytes))/float64(origLen)))
	}
	if strings.Contains(strings.ToLower(imageType), "png") && len(imageBytes) == origLen {
		mediaType = "image/png"
	}
	b64 := base64.StdEncoding.EncodeToString(imageBytes)

	systemPrompt := buildSaleClaudeSystemPrompt(c.productNames)
	// v1.0.133 — prepend per-shop digit-handwriting confusions when set on
	// the call context. Empty for shops with no learned signal yet.
	if hint, ok := ctx.Value(SaleDigitHintsCtxKey).(string); ok && hint != "" {
		systemPrompt = hint + "\n" + systemPrompt
	}
	// v1.0.133-r5 — alias-few-shot priors (separate context key so the two
	// hint blocks compose). Alias hints first so they appear nearest the
	// register-extraction instruction in the final prompt.
	if hint, ok := ctx.Value(SaleAliasHintsCtxKey).(string); ok && hint != "" {
		systemPrompt = hint + "\n" + systemPrompt
	}
	// v1.0.133-r10 — CV sidecar blank-row signal. Goes ABOVE alias hints so
	// it lands at the top of the system prompt (closest to the user image
	// in the model's attention pattern). Note we do NOT mark this block
	// cache_control: ephemeral because it varies per-image.
	cvHint := ""
	if h, ok := ctx.Value(SaleCVHintsCtxKey).(string); ok {
		cvHint = h
	}

	// Stable system block (cacheable: same for every image of this tenant).
	systemBlocks := []saleClaudeContent{
		{
			Type: "text",
			Text: systemPrompt,
			CacheControl: &struct {
				Type string `json:"type"`
			}{Type: "ephemeral"},
		},
	}
	// Per-image CV cross-check block — appended AFTER the cached block so
	// the cached prefix isn't invalidated. Anthropic prompt-caching matches
	// from the start; trailing variable content is fine.
	if cvHint != "" {
		systemBlocks = append(systemBlocks, saleClaudeContent{
			Type: "text",
			Text: cvHint,
		})
	}
	userBlocks := []saleClaudeContent{
		{Type: "image", Source: &saleClaudeImageSrc{Type: "base64", MediaType: mediaType, Data: b64}},
		{Type: "text", Text: "Extract the daily sales register from this image. Return a single JSON object matching the schema in the system prompt — no prose, no markdown fences, just JSON."},
	}

	reqBody, err := json.Marshal(saleClaudeRequest{
		Model:       c.model,
		MaxTokens:   saleClaudeMaxOutputTokens,
		Temperature: 0.0,
		System:      systemBlocks,
		Messages:    []saleClaudeMessage{{Role: "user", Content: userBlocks}},
	})
	if err != nil {
		return nil, fmt.Errorf("claude marshal failed: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", saleClaudeAPIEndpoint, bytes.NewBuffer(reqBody))
	if err != nil {
		return nil, fmt.Errorf("claude request build failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", saleClaudeAPIVersion)
	req.Header.Set("anthropic-beta", saleClaudeBetaCache)

	c.logger.Infof("🧠 SmartSale Claude: extracting (model=%s, products=%d, prompt=%d chars)", c.model, len(c.productNames), len(systemPrompt))

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("claude request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("claude read failed: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claude api error %d: %s", resp.StatusCode, string(body))
	}
	var apiResp saleClaudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("claude decode failed: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("claude error: %s", apiResp.Error.Message)
	}
	var assistantText string
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			assistantText += b.Text
		}
	}
	if assistantText == "" {
		return nil, fmt.Errorf("claude returned empty response")
	}

	// Strip any wrapping markdown fences just in case the model added them.
	clean := strings.TrimSpace(assistantText)
	if strings.HasPrefix(clean, "```") {
		// Remove leading ```json or ``` line.
		if idx := strings.Index(clean, "\n"); idx > 0 {
			clean = clean[idx+1:]
		}
		clean = strings.TrimSuffix(clean, "```")
		clean = strings.TrimSpace(clean)
	}

	var result ReceiptExtractionResult
	if err := json.Unmarshal([]byte(clean), &result); err != nil {
		// Try array-only fallback (some prompts return bare list).
		var items []ExtractedReceiptItem
		if err2 := json.Unmarshal([]byte(clean), &items); err2 == nil {
			result.Items = items
		} else {
			return nil, fmt.Errorf("claude JSON parse failed: %w (body: %s)", err, truncateForLog(clean, 400))
		}
	}
	result.ProcessingTime = int(time.Since(startTime).Milliseconds())
	if apiResp.Usage != nil {
		c.logger.Infof("SmartSale Claude: extracted %d items in %dms — tokens in=%d (cache_read=%d cache_create=%d) out=%d",
			len(result.Items), result.ProcessingTime,
			apiResp.Usage.InputTokens, apiResp.Usage.CacheReadInputTokens, apiResp.Usage.CacheCreationInputTokens, apiResp.Usage.OutputTokens)
	} else {
		c.logger.Infof("SmartSale Claude: extracted %d items in %dms", len(result.Items), result.ProcessingTime)
	}
	return &result, nil
}

// ExtractRecoveryPass mirrors the OpenAI signature so smart_sale_service.go's
// recovery loop can call Claude when SMART_SALE_PRIMARY=claude. Reuses the
// same prompt with an explicit completeness-focused instruction.
func (c *ClaudeOCRService) ExtractRecoveryPass(ctx context.Context, imageBytes []byte, imageType string, productNames []string, mainRows int, maxRowSeen int) (*ReceiptExtractionResult, error) {
	c.productNames = productNames
	defer func() { c.productNames = nil }()
	gap := maxRowSeen - mainRows
	if gap < 0 {
		gap = 0
	}
	hint := fmt.Sprintf("\n\nRECOVERY PASS — the main pass missed approximately %d rows out of %d total visible rows. RE-EXTRACT EVERY VISIBLE ROW, including rows with quantity=0 and trailing handwritten additions. Do NOT skip any product line.", gap, maxRowSeen)
	original := c.productNames
	defer func() { c.productNames = original }()
	// Append hint by piggybacking on the standard prompt builder via productNames list trick — simpler to inline a one-shot user message instead.
	if c == nil || c.apiKey == "" {
		return nil, fmt.Errorf("claude not configured")
	}
	imageBytes, mediaType := optimizeImageForClaude(imageBytes)
	if strings.Contains(strings.ToLower(imageType), "png") && mediaType == "image/jpeg" {
		// optimizeImageForClaude returns "image/jpeg" by default — keep png only when
		// the original was PNG and the optimizer returned the original bytes.
		_ = mediaType
	}
	b64 := base64.StdEncoding.EncodeToString(imageBytes)
	systemPrompt := buildSaleClaudeSystemPrompt(c.productNames)
	if hint, ok := ctx.Value(SaleDigitHintsCtxKey).(string); ok && hint != "" {
		systemPrompt = hint + "\n" + systemPrompt
	}
	// v1.0.133-r5 — alias-few-shot priors (separate context key so the two
	// hint blocks compose). Alias hints first so they appear nearest the
	// register-extraction instruction in the final prompt.
	if hint, ok := ctx.Value(SaleAliasHintsCtxKey).(string); ok && hint != "" {
		systemPrompt = hint + "\n" + systemPrompt
	}
	systemBlocks := []saleClaudeContent{{
		Type: "text",
		Text: systemPrompt,
		CacheControl: &struct {
			Type string `json:"type"`
		}{Type: "ephemeral"},
	}}
	userBlocks := []saleClaudeContent{
		{Type: "image", Source: &saleClaudeImageSrc{Type: "base64", MediaType: mediaType, Data: b64}},
		{Type: "text", Text: "Extract the daily sales register from this image, focusing on COMPLETENESS." + hint + " Return a single JSON object matching the schema in the system prompt — no prose, no markdown fences, just JSON."},
	}
	reqBody, err := json.Marshal(saleClaudeRequest{
		Model:       c.model,
		MaxTokens:   saleClaudeMaxOutputTokens,
		Temperature: 0.2,
		System:      systemBlocks,
		Messages:    []saleClaudeMessage{{Role: "user", Content: userBlocks}},
	})
	if err != nil {
		return nil, err
	}
	req, _ := http.NewRequestWithContext(ctx, "POST", saleClaudeAPIEndpoint, bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", saleClaudeAPIVersion)
	req.Header.Set("anthropic-beta", saleClaudeBetaCache)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claude recovery api error %d: %s", resp.StatusCode, string(body))
	}
	var apiResp saleClaudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("claude recovery error: %s", apiResp.Error.Message)
	}
	var assistantText string
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			assistantText += b.Text
		}
	}
	clean := strings.TrimSpace(assistantText)
	if strings.HasPrefix(clean, "```") {
		if idx := strings.Index(clean, "\n"); idx > 0 {
			clean = clean[idx+1:]
		}
		clean = strings.TrimSuffix(clean, "```")
		clean = strings.TrimSpace(clean)
	}
	var result ReceiptExtractionResult
	if err := json.Unmarshal([]byte(clean), &result); err != nil {
		var items []ExtractedReceiptItem
		if err2 := json.Unmarshal([]byte(clean), &items); err2 == nil {
			result.Items = items
		} else {
			return nil, fmt.Errorf("claude recovery JSON parse failed: %w", err)
		}
	}
	return &result, nil
}

// ExtractHandwrittenBand re-extracts a specific row range of a register page
// with a handwriting-specialized prompt. Used by smart_sale_service.go's
// page-rescue gate (v1.0.131): when the main pass + voting + recovery still
// returns < 70% of the AI-reported RowCountOnPage AND average confidence on
// the extracted rows is < 0.85, this method is called with fromRow=1 and
// toRow=expected to re-OCR the page from scratch with row-line anchoring
// turned ON. PARITY: mirrors smart_stock_setup_ocr.go's ExtractHandwrittenBand
// but adapted to Smart Sale's column schema (Sale instead of just Closing).
//
// Caller passes fromRow/toRow inclusive (1-indexed). The prompt instructs the
// model to return ONLY rows in that range; results are merged into the main
// extraction by row_number with main pass winning collisions.
//
// Cost: one full Claude vision call per page that needs rescue. In practice
// fires on ~10-30% of multi-page handwritten registers — multiplies API spend
// on the hardest pages, leaves clean printed registers untouched.
func (c *ClaudeOCRService) ExtractHandwrittenBand(ctx context.Context, imageBytes []byte, imageType string, productNames []string, fromRow, toRow int) (*ReceiptExtractionResult, error) {
	if c == nil || c.apiKey == "" {
		return nil, fmt.Errorf("claude not configured")
	}
	if toRow < fromRow {
		return nil, fmt.Errorf("invalid range fromRow=%d toRow=%d", fromRow, toRow)
	}
	c.productNames = productNames
	defer func() { c.productNames = nil }()
	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(imageType), "png") {
		mediaType = "image/png"
	}
	b64 := base64.StdEncoding.EncodeToString(imageBytes)
	systemPrompt := buildSaleClaudeSystemPrompt(c.productNames)
	if hint, ok := ctx.Value(SaleDigitHintsCtxKey).(string); ok && hint != "" {
		systemPrompt = hint + "\n" + systemPrompt
	}
	// v1.0.133-r5 — alias-few-shot priors (separate context key so the two
	// hint blocks compose). Alias hints first so they appear nearest the
	// register-extraction instruction in the final prompt.
	if hint, ok := ctx.Value(SaleAliasHintsCtxKey).(string); ok && hint != "" {
		systemPrompt = hint + "\n" + systemPrompt
	}
	systemBlocks := []saleClaudeContent{{
		Type: "text",
		Text: systemPrompt,
		CacheControl: &struct {
			Type string `json:"type"`
		}{Type: "ephemeral"},
	}}
	bandHint := fmt.Sprintf(`HANDWRITTEN-BAND PASS — the page has rows numbered %d through %d. The main extraction pass MISSED a significant portion of these rows. Re-extract this page focusing on COMPLETENESS over speed.

ROW-LINE ANCHORING (CRITICAL):
- Walk the page TOP-TO-BOTTOM. For each numbered row line you can see — including ones with faint, smudged, partially-blank, or all-zero cells — emit one item.
- The S.No column is your anchor: rows are numbered %d, %d+1, %d+2, ... Stop at row %d.
- Set row_number to the in-page S.No exactly as printed/written. Do NOT renumber.
- If the brand cell is blank but the row has any other content (Opening, Sale, Rate, Amount), still emit the row with brand="" and raw_text capturing whatever you can read.
- ZERO-QTY ROWS ARE VALID: emit them with quantity=0. The server keeps them through the pipeline.

HANDWRITING-WINS RULE:
- If a row has BOTH printed text and handwritten text (overwrite, strike-through, or beside), the HANDWRITTEN string is the actual brand. Set brand to the handwritten text and raw_text to the same.
- Common handwritten abbreviations: 8PM, BP, RS (Royal Stag), MCD, JW, M2/MM (Magic Moments + flavor), VOV (Old Monk), B7. For M2/MM rows, the FOLLOWING WORD is the flavor (Green Apple, Cranberry, Jamun, etc.) — keep the flavor with the brand.

RANGE SCOPE:
- Return ONLY items with row_number in the inclusive range [%d, %d]. Do NOT return rows outside this range.
- Set row_count_on_page to %d (the size of the requested range).

Return a SINGLE JSON object matching the schema in the system prompt — no prose, no markdown fences, just JSON.`, fromRow, toRow, fromRow, fromRow, fromRow, toRow, fromRow, toRow, toRow-fromRow+1)
	userBlocks := []saleClaudeContent{
		{Type: "image", Source: &saleClaudeImageSrc{Type: "base64", MediaType: mediaType, Data: b64}},
		{Type: "text", Text: bandHint},
	}
	reqBody, err := json.Marshal(saleClaudeRequest{
		Model:       c.model,
		MaxTokens:   saleClaudeMaxOutputTokens,
		Temperature: 0.15,
		System:      systemBlocks,
		Messages:    []saleClaudeMessage{{Role: "user", Content: userBlocks}},
	})
	if err != nil {
		return nil, err
	}
	req, _ := http.NewRequestWithContext(ctx, "POST", saleClaudeAPIEndpoint, bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", saleClaudeAPIVersion)
	req.Header.Set("anthropic-beta", saleClaudeBetaCache)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claude handwritten-band api error %d: %s", resp.StatusCode, truncateForLog(string(body), 400))
	}
	var apiResp saleClaudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("claude handwritten-band error: %s", apiResp.Error.Message)
	}
	var assistantText string
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			assistantText += b.Text
		}
	}
	clean := strings.TrimSpace(assistantText)
	if strings.HasPrefix(clean, "```") {
		if idx := strings.Index(clean, "\n"); idx > 0 {
			clean = clean[idx+1:]
		}
		clean = strings.TrimSuffix(clean, "```")
		clean = strings.TrimSpace(clean)
	}
	var result ReceiptExtractionResult
	if err := json.Unmarshal([]byte(clean), &result); err != nil {
		var items []ExtractedReceiptItem
		if err2 := json.Unmarshal([]byte(clean), &items); err2 == nil {
			result.Items = items
		} else {
			return nil, fmt.Errorf("claude handwritten-band JSON parse failed: %w (body: %s)", err, truncateForLog(clean, 400))
		}
	}
	// Server-side range filter — defense against models that ignore the
	// "rows in [fromRow, toRow]" instruction. PARITY:
	// smart_stock_setup_ocr.go does the same scope check.
	filtered := make([]ExtractedReceiptItem, 0, len(result.Items))
	for _, it := range result.Items {
		if it.RowNumber >= fromRow && it.RowNumber <= toRow {
			filtered = append(filtered, it)
		}
	}
	if len(filtered) != len(result.Items) {
		c.logger.Infof("SmartSale Claude: handwritten-band filtered %d out-of-range rows (kept %d in [%d, %d])", len(result.Items)-len(filtered), len(filtered), fromRow, toRow)
	}
	result.Items = filtered
	c.logger.Infof("SmartSale Claude: handwritten-band returned %d items for rows [%d, %d]", len(result.Items), fromRow, toRow)
	return &result, nil
}

// buildSaleClaudeSystemPrompt returns the Smart Sale extraction prompt for
// Claude. Same rules + JSON schema as OpenAI's createLiquorExtractionPrompt
// (kept inline here so we don't need to refactor OpenAIOCRService into a
// shared package). When the OpenAI prompt is updated for accuracy fixes,
// mirror the changes here. Product names are appended when present so the
// extractor can do brand-name normalization at the model layer.
func buildSaleClaudeSystemPrompt(productNames []string) string {
	prompt := saleExtractionPromptBase
	if len(productNames) > 0 {
		var sb strings.Builder
		sb.WriteString(prompt)
		sb.WriteString("\n\nKNOWN PRODUCT NAMES IN THIS SHOP'S CATALOG (for normalization — when an OCR-extracted brand looks like a misspelled or abbreviated form of one of these, output the canonical full form):\n")
		for i, n := range productNames {
			if i >= 200 { // cap so the system block stays cache-friendly
				break
			}
			sb.WriteString("  - ")
			sb.WriteString(n)
			sb.WriteString("\n")
		}
		prompt = sb.String()
	}
	return prompt
}

// truncateForLog keeps log lines bounded.
func truncateForLog(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// saleExtractionPromptBase mirrors OpenAIOCRService.createLiquorExtractionPrompt.
// Kept short here; the full sale-register rules are in openai_ocr_service.go and
// can be referenced when expanding this. We use a compact-but-equivalent prompt
// with the same JSON schema so cross-provider parity is maintained.
const saleExtractionPromptBase = `You are extracting data from an Indian liquor shop DAILY SALES register image.

FIRST: Look at the TOP/HEADER for:
1. SHOP NAME (e.g., "XYZ Wine Shop")
2. PAGE SIZE / bottle size category (e.g., "375 ML", "180ML", "750ML")
3. RECEIPT DATE (DD/MM/YY format — "8/4/26" = April 8, 2026; convert to YYYY-MM-DD)

The register table columns left-to-right: S.No | Brand | Opening | Receipt | Total | Sale | Rate | Amount | Closing.

CRITICAL RULES:
- Sale (column 6) is the QUANTITY SOLD. Closing = Total - Sale.
- Rate (column 7) is per-unit price in ₹ (typically ₹50–₹5000).
- Amount (column 8) = the value HANDWRITTEN in the Amount cell. If the Amount cell is empty/illegible/faded, return price=0 (DO NOT compute price = Sale × Rate; that masks a missing OCR signal that downstream cross-checks need). The math relationship Amount = Sale × Rate is a *verification* tool, not a back-fill instruction.
- If Sale cell is empty/dash, set quantity=0. If only ONE numeric column has a value, it's likely Opening, set quantity=0.
- DELTA FALLBACK: if Sale cell is illegible BUT Opening AND Closing are clearly readable, compute Sale = Opening + Receipt − Closing, set confidence ≤ 0.6, append " (inferred from delta)" to raw_text.
- v1.0.133-r7 ANTI-HALLUCINATION RULE — most registers have many BLANK rows where the shopkeeper had no sale that day. A row is BLANK when the Brand cell is empty (no handwritten text, only the pre-printed brand name OR fully empty) AND all of (Sale, Rate, Amount, Opening, Closing) cells are empty. **Never extract blank rows. Returning fewer rows than the visible serial count is correct and expected.** Inventing data for blank rows breaks downstream matching and is the worst kind of error. ONLY extract a row when at least one of these is true:
  (a) the Brand cell has handwritten text the shopkeeper added, OR
  (b) at least one of (Sale, Rate, Amount) has a non-zero handwritten value, OR
  (c) Opening AND Closing are both non-empty and they DIFFER (proves activity).
  If none of these hold, SKIP the row entirely — do not include it in items[]. Do not invent placeholder values like opening=0 quantity=17 closing=96 just to fill a slot. row_count_on_page should still reflect total visible serial numbers, but items[] only contains the rows that actually have data.
- v1.0.133-r7 — the LAST row of any register may be labelled "GRAND TOTAL", "TOTAL", or "G.TOTAL". Never extract this row as an item. It is a sum row, not a sale row. If you see "GRAND TOTAL" anywhere in the brand cell or row label, skip that row.
- SERIAL CHECK: report row_count_on_page (top-level integer) as the count of numbered serial rows visible on the page (regardless of whether they have data). items[] count will typically be smaller than this when most rows are blank — that is correct.
- LAST-ROWS EMPHASIS: rows 25+ on dense pages are most often missed — extract them WHEN they have data per the rules above.
- HANDWRITTEN ADDITIONS: shopkeeper-added rows below pre-printed lines (rows 40+) are valid; extract them.
- Set row_number to position on this page (1-based). Server attaches page identity separately.
- HONEST UNCERTAINTY: if cell confidence < 0.6, return raw text in raw_text rather than guessing a known brand. It is BETTER to return brand="" and the actual handwritten string than to hallucinate a brand we'll have to undo later.
- "Stop"/"X" margin annotations mean the product is stopped; quantity=0 but extract the brand. If a replacement brand is written, extract the replacement.
- Do NOT merge multi-row text into one brand. Ignore non-brand notes in adjacent columns.

CRITICAL: schema-key leak guard. NEVER return literal schema keys ("brand", "raw_text", "name", "size", "rate", "quantity", "amount", "total", "opening_stock", "closing_stock", "receipt", "row_number") as VALUES. If a cell is unreadable, output empty string for brand and the actual handwritten/OCR text in raw_text.

Return a SINGLE JSON object with this exact schema:

{
  "items": [
    {
      "brand": "<brand name>",
      "category": "<whiskey|rum|vodka|beer|gin|brandy|wine>",
      "subcategory": "<premium|normal>",
      "size_text": "<e.g. 750ML>",
      "size_ml": <number>,
      "quantity": <int — Sale column>,
      "price": <total amount>,
      "rate_per_unit": <Rate column>,
      "opening_stock": <int>,
      "receipt": <int>,
      "total": <int>,
      "closing_stock": <int>,
      "row_number": <int — 1-based position on this page>,
      "confidence": <0.0–1.0>,
      "raw_text": "<original handwritten string for this row>"
    }
  ],
  "shop_name": "<from header>",
  "page_size": "<bottle size from header e.g. 375ML>",
  "page_size_ml": <number>,
  "receipt_date": "<YYYY-MM-DD>",
  "row_count_on_page": <int — count of every visible numbered row line on this page, including blanks; MUST be >= len(items[])>,
  "raw_text": "<full page raw OCR if helpful>"
}`
