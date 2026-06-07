package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// SmartPurchaseOCR handles AI-powered extraction from purchase invoice images
type SmartPurchaseOCR struct {
	openaiKey    string
	geminiKey    string
	anthropicKey string
	httpClient   *http.Client
}

// OpenAI API types (same as sales service)
type spOpenAIMessage struct {
	Role    string      `json:"role"`
	Content interface{} `json:"content"`
}

type spOpenAITextContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type spOpenAIImageURL struct {
	URL    string `json:"url"`
	Detail string `json:"detail,omitempty"`
}

type spOpenAIImageContent struct {
	Type     string           `json:"type"`
	ImageURL spOpenAIImageURL `json:"image_url"`
}

type spOpenAIRequest struct {
	Model               string            `json:"model"`
	Messages            []spOpenAIMessage `json:"messages"`
	MaxCompletionTokens int               `json:"max_completion_tokens"`
	Temperature         float64           `json:"temperature"`
	ResponseFormat      *spResponseFmt    `json:"response_format,omitempty"`
}

type spResponseFmt struct {
	Type string `json:"type"`
}

type spOpenAIChoice struct {
	Message struct {
		Content string `json:"content"`
	} `json:"message"`
}

type spOpenAIResponse struct {
	Choices []spOpenAIChoice `json:"choices"`
	Usage   struct {
		TotalTokens int `json:"total_tokens"`
	} `json:"usage"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// Gemini API types
type geminiRequest struct {
	Contents         []geminiContent        `json:"contents"`
	GenerationConfig geminiGenerationConfig `json:"generationConfig"`
}

type geminiContent struct {
	Parts []geminiPart `json:"parts"`
}

type geminiPart struct {
	Text       string          `json:"text,omitempty"`
	InlineData *geminiBlobData `json:"inline_data,omitempty"`
}

type geminiBlobData struct {
	MimeType string `json:"mime_type"`
	Data     string `json:"data"`
}

type geminiGenerationConfig struct {
	Temperature    float64 `json:"temperature"`
	MaxOutputTokens int    `json:"maxOutputTokens"`
	ResponseMimeType string `json:"responseMimeType,omitempty"`
}

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// NewSmartPurchaseOCR creates a new Smart Purchase OCR service
func NewSmartPurchaseOCR() *SmartPurchaseOCR {
	openaiKey := os.Getenv("OPENAI_API_KEY")
	if openaiKey == "" {
		if keyBytes, err := os.ReadFile("/app/credentials/openai-api-key.txt"); err == nil {
			openaiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	geminiKey := os.Getenv("GEMINI_API_KEY")
	if geminiKey == "" {
		if keyBytes, err := os.ReadFile("/app/credentials/gemini-api-key.txt"); err == nil {
			geminiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	anthropicKey := os.Getenv("ANTHROPIC_API_KEY")
	if anthropicKey != "" {
		log.Println("Smart Purchase OCR: Anthropic Claude key found (primary for stock setup)")
	}
	if openaiKey != "" {
		log.Println("Smart Purchase OCR: OpenAI API key found")
	}
	if geminiKey != "" {
		log.Println("Smart Purchase OCR: Gemini API key found")
	}
	if openaiKey == "" && geminiKey == "" && anthropicKey == "" {
		log.Println("Smart Purchase OCR: WARNING - No AI API keys configured")
	}

	return &SmartPurchaseOCR{
		openaiKey:    openaiKey,
		geminiKey:    geminiKey,
		anthropicKey: anthropicKey,
		httpClient:   &http.Client{Timeout: 180 * time.Second},
	}
}

// IsAvailable returns true if at least one AI API key is configured
func (s *SmartPurchaseOCR) IsAvailable() bool {
	return s.openaiKey != "" || s.geminiKey != "" || s.anthropicKey != ""
}

// ExtractFromImage is the LLM-tier extraction path. AWS Textract is the
// bill-pipeline primary (gated in smart_purchase_service.go) and runs first;
// this LLM path fires only when Textract fails its acceptance gate
// (drop-ratio > 40%, < 5 valid rows, severe skew, etc).
//
// LLM cascade (within this tier) is configurable via SMART_PURCHASE_PRIMARY:
//
//	gemini  → Gemini 3 Flash → Claude Sonnet 4.6 → OpenAI gpt-5.2 (default)
//	claude  → Claude Sonnet 4.6 → Gemini 3 Flash → OpenAI gpt-5.2
//	openai  → OpenAI gpt-5.2 → Gemini 3 Flash → Claude Sonnet 4.6
//
// Default order keeps Gemini first (cheapest at ~₹0.30/page), with Claude as
// the deterministic fallback because Sonnet 4.6 has been bulletproof on
// dense tables in Smart Stock Setup + Smart Sale (v1.0.115 / v1.0.119).
// Per-key skips happen automatically (a backend with no API key is bypassed).
func (s *SmartPurchaseOCR) ExtractFromImage(ctx context.Context, imageBytes []byte, contentType string) (*PurchaseExtractionResult, error) {
	primary := strings.ToLower(strings.TrimSpace(os.Getenv("SMART_PURCHASE_PRIMARY")))
	if primary == "" {
		primary = "gemini"
	}

	isGatePassErr := func(err error) bool {
		return err != nil && strings.HasPrefix(err.Error(), "gate_pass:")
	}

	// tryGemini extracts via Gemini once. On truncation, we DON'T retry the
	// same backend (Gemini's response cap is non-deterministic — retry rate
	// is ~50%, costing 30-60s for half the pages). Instead the caller's
	// cascade escalates to Claude immediately, which is deterministic on
	// dense tables.
	tryGemini := func() (*PurchaseExtractionResult, error) {
		if s.geminiKey == "" {
			return nil, fmt.Errorf("gemini: no api key")
		}
		return s.extractWithGemini(ctx, imageBytes, contentType)
	}

	tryClaude := func() (*PurchaseExtractionResult, error) {
		if s.anthropicKey == "" {
			return nil, fmt.Errorf("claude: no api key")
		}
		return s.extractPurchaseWithClaude(ctx, imageBytes, contentType)
	}

	tryOpenAI := func() (*PurchaseExtractionResult, error) {
		if s.openaiKey == "" {
			return nil, fmt.Errorf("openai: no api key")
		}
		return s.extractWithOpenAI(ctx, imageBytes, contentType)
	}

	// Build the cascade order from primary preference.
	type backend struct {
		name string
		fn   func() (*PurchaseExtractionResult, error)
	}
	cascade := []backend{}
	switch primary {
	case "claude":
		cascade = []backend{{"claude", tryClaude}, {"gemini", tryGemini}, {"openai", tryOpenAI}}
	case "openai":
		cascade = []backend{{"openai", tryOpenAI}, {"gemini", tryGemini}, {"claude", tryClaude}}
	default: // "gemini" or anything unrecognized
		cascade = []backend{{"gemini", tryGemini}, {"claude", tryClaude}, {"openai", tryOpenAI}}
	}

	var lastErr error
	var bestPartial *PurchaseExtractionResult
	for i, b := range cascade {
		result, err := b.fn()
		if err == nil {
			// Escalate on any truncation — the truncation flag means the
			// LLM cut its response mid-table; the next backend gets a
			// chance to deliver complete rows. Best partial is kept as a
			// safety net if all backends fail.
			if result != nil && result.Truncated && i < len(cascade)-1 {
				log.Printf("Smart Purchase OCR: %s returned truncated result (%d items) — escalating to next backend", b.name, len(result.Items))
				if bestPartial == nil || len(result.Items) > len(bestPartial.Items) {
					bestPartial = result
				}
				lastErr = fmt.Errorf("%s: response truncated", b.name)
				continue
			}
			return result, nil
		}
		// Gate-pass-misuploaded-as-invoice is a user error, not a backend
		// failure — surface it immediately so the operator sees the right
		// message instead of waiting through the whole cascade.
		if isGatePassErr(err) {
			return nil, err
		}
		// Skip-with-no-key reasons should not be logged as failures.
		if !strings.HasSuffix(err.Error(), "no api key") {
			log.Printf("Smart Purchase OCR: %s failed (%v), trying next backend", b.name, err)
		}
		lastErr = err
		if i == len(cascade)-1 {
			break
		}
	}
	// All backends exhausted. If we have a partial truncated result kept from
	// earlier in the cascade, prefer that over an outright error — the
	// operator at least sees what we got + a clear "X of Y rows extracted"
	// banner from the existing reconciliation gate.
	if bestPartial != nil {
		log.Printf("Smart Purchase OCR: all backends exhausted — returning best partial result (%d items, truncated)", len(bestPartial.Items))
		return bestPartial, nil
	}
	if lastErr == nil {
		return nil, fmt.Errorf("no AI API keys configured for Smart Purchase OCR")
	}
	return nil, lastErr
}

// extractWithOpenAI uses OpenAI GPT Vision to extract invoice data
func (s *SmartPurchaseOCR) extractWithOpenAI(ctx context.Context, imageBytes []byte, contentType string) (*PurchaseExtractionResult, error) {
	imgType := "jpeg"
	if strings.Contains(contentType, "png") {
		imgType = "png"
	}

	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imgType, base64Image)

	prompt := s.buildPurchasePrompt()

	content := []interface{}{
		spOpenAITextContent{Type: "text", Text: prompt},
		spOpenAIImageContent{
			Type: "image_url",
			ImageURL: spOpenAIImageURL{URL: imageDataURL, Detail: "high"},
		},
	}

	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}

	request := spOpenAIRequest{
		Model: model,
		Messages: []spOpenAIMessage{
			{Role: "user", Content: content},
		},
		MaxCompletionTokens: 16384,
		Temperature:         0.0,
		ResponseFormat:      &spResponseFmt{Type: "json_object"},
	}

	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openaiKey)

	log.Printf("Smart Purchase OCR: Sending to OpenAI %s...", model)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai api error %d: %s", resp.StatusCode, string(body))
	}

	var apiResp spOpenAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.Error != nil {
		return nil, fmt.Errorf("openai error: %s", apiResp.Error.Message)
	}

	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from OpenAI")
	}

	responseText := apiResp.Choices[0].Message.Content
	log.Printf("Smart Purchase OCR: OpenAI responded with %d tokens", apiResp.Usage.TotalTokens)

	return s.parseExtractionResponse(responseText)
}

// VerifyExtractionAgainstTotal re-examines an image with the previously-extracted rows and the
// known document total, asking the AI to identify which specific rows have wrong rates/amounts
// so the sum reconciles. Returns a map of row_number → corrected (rate_per_case, amount).
//
// This is a focused second pass — only runs when sum(items.amount) ≠ document_total by >2%.
// The first pass extracts the structure (rows, brands, qty); this pass refines the numeric
// fields where the AI mis-read digits in handwritten/blurry sections.
func (s *SmartPurchaseOCR) VerifyExtractionAgainstTotal(ctx context.Context, imageBytes []byte, contentType string,
	items []ExtractedPurchaseItem, documentTotal float64) (map[int]struct{ Rate, Amount float64 }, error) {

	if len(items) == 0 || documentTotal <= 0 {
		return nil, nil
	}

	imgType := "jpeg"
	if strings.Contains(contentType, "png") {
		imgType = "png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imgType, base64Image)

	// Build the row table for the AI
	var rowsJSON strings.Builder
	rowsJSON.WriteString("[\n")
	sumAmt := 0.0
	for i, it := range items {
		if i > 0 {
			rowsJSON.WriteString(",\n")
		}
		fmt.Fprintf(&rowsJSON, `  {"row":%d,"brand":%q,"size":%q,"qty":%g,"unit":%q,"rate_per_case":%.2f,"amount":%.2f}`,
			int(it.RowNumber), it.Brand, it.SizeText, it.QuantityRaw, it.QuantityUnit, it.RatePerCase, it.Amount)
		sumAmt += it.Amount
	}
	rowsJSON.WriteString("\n]")

	prompt := fmt.Sprintf(`You previously extracted these rows from a liquor invoice. The grand total
on the invoice footer is ₹%.2f, but the sum of the row amounts is ₹%.2f (a difference of ₹%.2f).
Some rows have wrong rates or amounts. Look at the SAME image and identify which rows are wrong.

Previously extracted rows:
%s

For each WRONG row, look at the image's Rate and Amount columns again and give the corrected values.
Match each row by its row number. Pay special attention to:
- Digit confusion: 0/8, 5/6, 1/7, 3/8, 5/7. Re-read carefully.
- Rate column may be cut off — check the per-Cs amount divided by the cases count.
- For dual-line rows (where a row has "(M Pcs)" beneath the case line), the amount = cases × rate_per_case + loose_pcs × rate_per_pcs.

Return ONLY valid JSON in this exact structure (omit rows that are correct):
{
  "corrections": [
    {"row": 12, "rate_per_case": 7573.44, "amount": 15146.88, "reason": "rate misread as 5737.44"},
    {"row": 13, "rate_per_case": 7573.44, "amount": 15146.88, "reason": "..."}
  ]
}

If everything is correct, return {"corrections": []}.`, documentTotal, sumAmt, documentTotal-sumAmt, rowsJSON.String())

	content := []interface{}{
		spOpenAITextContent{Type: "text", Text: prompt},
		spOpenAIImageContent{Type: "image_url", ImageURL: spOpenAIImageURL{URL: imageDataURL, Detail: "high"}},
	}
	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}
	request := spOpenAIRequest{
		Model:               model,
		Messages:            []spOpenAIMessage{{Role: "user", Content: content}},
		MaxCompletionTokens: 8192,
		Temperature:         0.0,
		ResponseFormat:      &spResponseFmt{Type: "json_object"},
	}
	requestBody, _ := json.Marshal(request)
	req, _ := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openaiKey)
	log.Printf("Smart Purchase OCR: Verification pass — total ₹%.2f vs sum ₹%.2f (Δ₹%.2f)", documentTotal, sumAmt, documentTotal-sumAmt)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("verification request failed: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("verification api error %d: %s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}
	var apiResp spOpenAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}
	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no choices in verification response")
	}
	respText := apiResp.Choices[0].Message.Content
	respText = strings.TrimSpace(respText)
	if idx := strings.Index(respText, "```json"); idx >= 0 {
		respText = respText[idx+7:]
	}
	if idx := strings.Index(respText, "```"); idx >= 0 {
		respText = respText[:idx]
	}
	respText = strings.TrimSpace(respText)

	var parsed struct {
		Corrections []struct {
			Row         int     `json:"row"`
			RatePerCase float64 `json:"rate_per_case"`
			Amount      float64 `json:"amount"`
			Reason      string  `json:"reason"`
		} `json:"corrections"`
	}
	if err := json.Unmarshal([]byte(respText), &parsed); err != nil {
		return nil, fmt.Errorf("verification parse error: %w", err)
	}
	corrections := make(map[int]struct{ Rate, Amount float64}, len(parsed.Corrections))
	for _, c := range parsed.Corrections {
		corrections[c.Row] = struct{ Rate, Amount float64 }{Rate: c.RatePerCase, Amount: c.Amount}
		log.Printf("Smart Purchase OCR: Verification correction — row %d: rate=₹%.2f, amount=₹%.2f (%s)",
			c.Row, c.RatePerCase, c.Amount, c.Reason)
	}
	return corrections, nil
}

// extractWithGemini uses Google Gemini to extract invoice data
func (s *SmartPurchaseOCR) extractWithGemini(ctx context.Context, imageBytes []byte, contentType string) (*PurchaseExtractionResult, error) {
	mimeType := "image/jpeg"
	if strings.Contains(contentType, "png") {
		mimeType = "image/png"
	}

	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	prompt := s.buildPurchasePrompt()

	request := geminiRequest{
		Contents: []geminiContent{
			{
				Parts: []geminiPart{
					{Text: prompt},
					{InlineData: &geminiBlobData{MimeType: mimeType, Data: base64Image}},
				},
			},
		},
		GenerationConfig: geminiGenerationConfig{
			Temperature:      0.0,
			MaxOutputTokens:  32768,
			// v1.0.190 — DROPPED ResponseMimeType: "application/json".
			// Real-data on chhotu's 41-row SONU SINGH FL-2 invoice exposed
			// that gemini-flash-latest's structured-output mode caps
			// internal generation around ~3000 chars regardless of
			// MaxOutputTokens=32768. Free-form text mode emits the full
			// response (~12-15k chars for 41 rows). The parser already
			// strips ```json / ``` fences, so dropping the MIME constraint
			// is safe.
		},
	}

	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// gemini-flash-latest resolves to gemini-3-flash-preview (as of 2026-04), which is
	// significantly better at table parsing than gemini-1.5/2.5-flash. Override with
	// GEMINI_MODEL env var if needed.
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-goog-api-key", s.geminiKey)

	log.Printf("Smart Purchase OCR: Sending to Gemini %s...", model)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gemini request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gemini api error %d: %s", resp.StatusCode, string(body))
	}

	var apiResp geminiResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.Error != nil {
		return nil, fmt.Errorf("gemini error: %s", apiResp.Error.Message)
	}

	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no response from Gemini")
	}

	responseText := apiResp.Candidates[0].Content.Parts[0].Text
	log.Printf("Smart Purchase OCR: Gemini response (%d chars, first 800): %s", len(responseText), responseText[:min(len(responseText), 800)])

	return s.parseExtractionResponse(responseText)
}

// extractPurchaseWithClaude is the LLM-tier fallback used when Gemini fails or
// returns truncated output. Sonnet 4.6 has been the bulletproof option on
// dense liquor-table extraction in Smart Stock Setup + Smart Sale, so when
// Gemini's response-length non-determinism bites (real chhotu case: 41 / 6
// items across runs of the same image), Claude takes over deterministically.
//
// Claude infrastructure (request/response types, endpoint, version headers)
// is shared with Smart Stock Setup via smart_stock_setup_claude.go; we reuse
// it here to keep one Claude client surface in the package.
func (s *SmartPurchaseOCR) extractPurchaseWithClaude(ctx context.Context, imageBytes []byte, contentType string) (*PurchaseExtractionResult, error) {
	if s.anthropicKey == "" {
		return nil, fmt.Errorf("claude: no api key")
	}

	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(contentType), "png") {
		mediaType = "image/png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)

	prompt := s.buildPurchasePrompt()

	systemBlocks := []claudeContent{
		{
			Type: "text",
			Text: prompt,
			CacheControl: &struct {
				Type string `json:"type"`
			}{Type: "ephemeral"},
		},
	}
	userBlocks := []claudeContent{
		{Type: "image", Source: &claudeImageSource{
			Type: "base64", MediaType: mediaType, Data: base64Image,
		}},
		{Type: "text", Text: "Extract the purchase invoice from this image into the JSON schema described above. Return ONLY the JSON — no prose, no markdown fences."},
	}

	model := os.Getenv("CLAUDE_PURCHASE_MODEL")
	if model == "" {
		model = claudeDefaultPrimary // claude-sonnet-4-6
	}

	request := claudeRequest{
		Model:       model,
		MaxTokens:   16384,
		Temperature: 0.0,
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

	log.Printf("Smart Purchase OCR: Sending to Claude %s (prompt: %d chars)...", model, len(prompt))
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
	responseText := textOut.String()

	log.Printf("Smart Purchase OCR: Claude responded — input=%d output=%d cache_create=%d cache_read=%d (%d chars, first 600): %s",
		apiResp.Usage.InputTokens, apiResp.Usage.OutputTokens,
		apiResp.Usage.CacheCreationInputTokens, apiResp.Usage.CacheReadInputTokens,
		len(responseText), responseText[:min(len(responseText), 600)])

	return s.parseExtractionResponse(responseText)
}

// ExtractPurchaseTailRescue runs a single Anthropic Sonnet call asking for ONLY
// the rows with S.No >= startSNo from the given image. Used to recover the
// LAST few rows of a page when AnalyzeExpense's bottom-edge truncation drops
// them (real-data: chhotu's bill page 1 always drops S.No 42).
//
// Returns nil-or-empty when no rows are recovered (Claude correctly declines
// to invent rows). Errors are returned but never block the caller — tail-
// rescue is best-effort, not a hard requirement.
func (s *SmartPurchaseOCR) ExtractPurchaseTailRescue(ctx context.Context, imageBytes []byte, contentType string, startSNo int) (*PurchaseExtractionResult, error) {
	if s.anthropicKey == "" {
		return nil, fmt.Errorf("claude: no api key")
	}
	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(contentType), "png") {
		mediaType = "image/png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)

	prompt := fmt.Sprintf(`You are reading a UP IMFL liquor invoice page. The page has been mostly extracted; ONLY rows with S.No >= %d still need extraction.

GOAL: Look at the visible printed S.No column on this page. Extract ONLY the rows whose printed S.No value is GREATER THAN OR EQUAL TO %d. If there are no such rows on this page, return an empty items array.

STRICT RULES:
- Do not invent rows. Do not extract any row whose S.No is < %d.
- Do not extract footer / total / grand total rows.
- The S.No is the small integer in the leftmost column of each line item.
- For each qualifying row, extract: row_number (the printed S.No), brand (item name with size), size_text, size_ml, quantity_raw (cases, integer), quantity_unit ("cases" usually), bottles_per_case, quantity_bottles, rate_per_bottle, amount.
- Return ONLY this JSON shape, no prose, no markdown fences:
{ "items": [ {"row_number": <int>, "brand": "...", "size_text": "...", "size_ml": <int>, "quantity_raw": <int>, "quantity_unit": "cases", "bottles_per_case": <int>, "quantity_bottles": <int>, "rate_per_bottle": <float>, "amount": <float>}, ... ] }

If no rows qualify, return: { "items": [] }
`, startSNo, startSNo, startSNo)

	systemBlocks := []claudeContent{
		{Type: "text", Text: prompt},
	}
	userBlocks := []claudeContent{
		{Type: "image", Source: &claudeImageSource{
			Type: "base64", MediaType: mediaType, Data: base64Image,
		}},
		{Type: "text", Text: fmt.Sprintf("Extract ONLY rows with S.No >= %d. Return JSON only.", startSNo)},
	}

	model := os.Getenv("CLAUDE_PURCHASE_MODEL")
	if model == "" {
		model = claudeDefaultPrimary
	}
	request := claudeRequest{
		Model:       model,
		MaxTokens:   4096,
		Temperature: 0.0,
		System:      systemBlocks,
		Messages:    []claudeMessage{{Role: "user", Content: userBlocks}},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, "POST", claudeAPIEndpoint, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.anthropicKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claude tail-rescue %d: %s", resp.StatusCode, string(body))
	}
	var apiResp claudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}
	if len(apiResp.Content) == 0 {
		return nil, fmt.Errorf("claude tail-rescue: empty content")
	}
	var textOut strings.Builder
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			textOut.WriteString(b.Text)
		}
	}
	log.Printf("Smart Purchase tail-rescue (Claude): startSNo=%d input=%d output=%d", startSNo, apiResp.Usage.InputTokens, apiResp.Usage.OutputTokens)
	return s.parseExtractionResponse(textOut.String())
}

// ExtractPurchaseTailRescueGemini is the Gemini-Vision counterpart of
// ExtractPurchaseTailRescue. v1.0.215.7 added because the Anthropic API
// key returned a 400 "credit balance is too low" error when the Claude
// tail-rescue first fired (2026-05-08). Gemini Flash has working credits
// per the v215.5 GP page-2 LLM rescue runs.
//
// Same prompt + same return shape as the Claude version. Caller in
// runTailRescuePerPage chooses provider via STOCK_PURCHASE_TAIL_RESCUE_PROVIDER
// env (default: gemini).
func (s *SmartPurchaseOCR) ExtractPurchaseTailRescueGemini(ctx context.Context, imageBytes []byte, contentType string, startSNo int) (*PurchaseExtractionResult, error) {
	if s.geminiKey == "" {
		return nil, fmt.Errorf("gemini: no api key")
	}
	mimeType := "image/jpeg"
	if strings.Contains(contentType, "png") {
		mimeType = "image/png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	prompt := fmt.Sprintf(`You are reading a UP IMFL liquor invoice page. The page has been mostly extracted; ONLY rows with S.No >= %d still need extraction.

GOAL: Look at the visible printed S.No column on this page. Extract ONLY the rows whose printed S.No value is GREATER THAN OR EQUAL TO %d. If there are no such rows on this page, return an empty items array.

STRICT RULES:
- Do not invent rows. Do not extract any row whose S.No is < %d.
- Do not extract footer / total / grand total rows.
- The S.No is the small integer in the leftmost column of each line item.
- For each qualifying row, extract: row_number (the printed S.No), brand (item name with size), size_text, size_ml, quantity_raw (cases, integer), quantity_unit ("cases" usually), bottles_per_case, quantity_bottles, rate_per_bottle, amount.
- Return ONLY this JSON shape, no prose, no markdown fences:
{ "items": [ {"row_number": <int>, "brand": "...", "size_text": "...", "size_ml": <int>, "quantity_raw": <int>, "quantity_unit": "cases", "bottles_per_case": <int>, "quantity_bottles": <int>, "rate_per_bottle": <float>, "amount": <float>}, ... ] }

If no rows qualify, return: { "items": [] }
`, startSNo, startSNo, startSNo)

	request := geminiRequest{
		Contents: []geminiContent{
			{
				Parts: []geminiPart{
					{Text: prompt},
					{InlineData: &geminiBlobData{MimeType: mimeType, Data: base64Image}},
				},
			},
		},
		GenerationConfig: geminiGenerationConfig{
			Temperature:     0.0,
			MaxOutputTokens: 4096,
		},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-goog-api-key", s.geminiKey)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gemini tail-rescue %d: %s", resp.StatusCode, string(body))
	}
	var apiResp geminiResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("gemini tail-rescue error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("gemini tail-rescue: empty response")
	}
	responseText := apiResp.Candidates[0].Content.Parts[0].Text
	log.Printf("Smart Purchase tail-rescue (Gemini): startSNo=%d response=%d chars", startSNo, len(responseText))
	return s.parseExtractionResponse(responseText)
}

// parseExtractionResponse parses the AI JSON response into PurchaseExtractionResult
func (s *SmartPurchaseOCR) parseExtractionResponse(responseText string) (*PurchaseExtractionResult, error) {
	// Strip markdown code fences if present
	jsonText := responseText
	if idx := strings.Index(jsonText, "```json"); idx >= 0 {
		jsonText = jsonText[idx+7:]
	} else if idx := strings.Index(jsonText, "```"); idx >= 0 {
		jsonText = jsonText[idx+3:]
	}
	if idx := strings.LastIndex(jsonText, "```"); idx >= 0 {
		jsonText = jsonText[:idx]
	}
	jsonText = strings.TrimSpace(jsonText)

	// Check for gate pass detection error before full unmarshal
	var quickCheck map[string]interface{}
	if json.Unmarshal([]byte(jsonText), &quickCheck) == nil {
		if errVal, _ := quickCheck["error"].(string); errVal == "gate_pass_not_invoice" {
			msg, _ := quickCheck["message"].(string)
			if msg == "" {
				msg = "This image appears to be a gate pass/transport permit. Please upload it in the Gate Pass section."
			}
			log.Printf("Smart Purchase OCR: Gate pass detected — %s", msg)
			return nil, fmt.Errorf("gate_pass: %s", msg)
		}
	}

	var result PurchaseExtractionResult
	if err := json.Unmarshal([]byte(jsonText), &result); err != nil {
		// Fallback 1: some models (Gemini 3) wrap the whole document inside a 1-element
		// array: [{"vendor_name": ..., "items": [...]}]. Unwrap it.
		var wrapped []PurchaseExtractionResult
		if altErr := json.Unmarshal([]byte(jsonText), &wrapped); altErr == nil && len(wrapped) > 0 {
			result = wrapped[0]
			for i := 1; i < len(wrapped); i++ {
				result.Items = append(result.Items, wrapped[i].Items...)
			}
			log.Printf("Smart Purchase OCR: AI wrapped document in array — unwrapping %d doc(s) with %d items total", len(wrapped), len(result.Items))
		} else {
			// Fallback 2: bare array of items (no wrapper).
			var items []ExtractedPurchaseItem
			if itemsErr := json.Unmarshal([]byte(jsonText), &items); itemsErr == nil && len(items) > 0 {
				log.Printf("Smart Purchase OCR: AI returned bare array — wrapping %d items into result object", len(items))
				result = PurchaseExtractionResult{Items: items}
			} else if repaired, repairedItems, ok := repairTruncatedExtraction(jsonText); ok && repairedItems > 0 {
				// Fallback 3 (v1.0.190): truncated mid-array. Real-data calibration on
				// chhotu's 41-row bill_2 page — Gemini's response was cut off mid-row
				// at "rate_per_bottle". Repair recovers all rows whose JSON closed
				// before the cut point so we keep the partial extraction instead of
				// throwing the whole page away. The matcher then surfaces the gap as
				// "X items extracted, Y expected" so the operator sees what's missing.
				if reErr := json.Unmarshal([]byte(repaired), &result); reErr == nil {
					log.Printf("Smart Purchase OCR: Recovered %d items from truncated JSON (response was %d chars, cut mid-token)",
						repairedItems, len(jsonText))
					// v1.0.192 — flag the result as truncated so the caller can
					// retry. Real-data showed gemini-flash-latest's response
					// length is non-deterministic on the same input (one run
					// returns 19 KB / 41 items, the next returns 3 KB / 6 items
					// for chhotu's bill page 1). Caller-side retry recovers the
					// full extraction without changing the model or prompt.
					result.Truncated = true
				} else {
					log.Printf("Smart Purchase OCR: Failed to parse JSON: %v\nRaw: %s", err, responseText[:min(len(responseText), 500)])
					return nil, fmt.Errorf("failed to parse extraction result: %w", err)
				}
			} else {
				log.Printf("Smart Purchase OCR: Failed to parse JSON: %v\nRaw: %s", err, responseText[:min(len(responseText), 500)])
				return nil, fmt.Errorf("failed to parse extraction result: %w", err)
			}
		}
	}

	// Post-process: ensure bottles_per_case and quantity_bottles are calculated
	for i := range result.Items {
		item := &result.Items[i]

		// Normalize size
		if item.SizeML == 0 && item.SizeText != "" {
			item.SizeML = float64(normalizeSizeText(item.SizeText))
		}

		// Set bottles per case from standard sizes
		if item.BottlesPerCase == 0 && item.SizeML > 0 {
			item.BottlesPerCase = float64(GetBottlesPerCase(int(item.SizeML)))
		}

		// Calculate quantity in bottles
		if item.QuantityBottles == 0 {
			if item.QuantityUnit == "cases" && item.BottlesPerCase > 0 {
				item.QuantityBottles = item.QuantityRaw * item.BottlesPerCase
			} else {
				item.QuantityBottles = item.QuantityRaw
			}
		}

		// Calculate rate per case/bottle if missing
		if item.RatePerBottle > 0 && item.RatePerCase == 0 && item.BottlesPerCase > 0 {
			item.RatePerCase = item.RatePerBottle * float64(item.BottlesPerCase)
		}
		if item.RatePerCase > 0 && item.RatePerBottle == 0 && item.BottlesPerCase > 0 {
			item.RatePerBottle = item.RatePerCase / float64(item.BottlesPerCase)
		}

		// Cross-validate: if amount doesn't match rate*qty, try to fix
		if item.Amount > 0 && item.RatePerBottle > 0 && item.QuantityRaw > 0 {
			expectedByBottle := item.RatePerBottle * float64(item.QuantityRaw)
			expectedByCase := item.RatePerCase * float64(item.QuantityRaw)

			// If amount matches rate_per_bottle * raw_qty, qty is in bottles
			if abs(expectedByBottle-item.Amount) < 1.0 && item.QuantityUnit == "cases" {
				item.QuantityUnit = "bottles"
				item.QuantityBottles = item.QuantityRaw
			}
			// If amount matches rate_per_case * raw_qty, qty is in cases
			if abs(expectedByCase-item.Amount) < 1.0 && item.QuantityUnit == "bottles" {
				item.QuantityUnit = "cases"
				item.QuantityBottles = item.QuantityRaw * item.BottlesPerCase
			}
		}

		// Dual-line invariant: Expected = cases*rate_per_case + loose*rate_per_bottle.
		// When the invariant is violated by >₹2, the row was likely shifted (a "(M Pcs)"
		// from the row above attributed here, or rate_per_bottle reading a different
		// row's per-Pcs rate). Flag the row so downstream can mark it for human review;
		// don't silently emit garbage. Tolerance ₹2 absorbs the AI's lakh-comma rounding.
		if item.Amount > 0 && item.QuantityRaw > 0 && item.QuantityUnit == "cases" {
			expected := float64(item.QuantityRaw) * item.RatePerCase
			if item.LooseBottles > 0 {
				expected += item.LooseBottles * item.RatePerBottle
			}
			diff := expected - item.Amount
			if diff < 0 {
				diff = -diff
			}
			tol := item.Amount * 0.01
			if tol < 2 {
				tol = 2
			}
			if diff > tol {
				if item.QuantityFlag == "" {
					item.QuantityFlag = "amount_qty_mismatch"
				}
				if item.Confidence > 0.55 {
					item.Confidence = 0.55
				}
				log.Printf("Smart Purchase OCR: Row %d AMOUNT/QTY MISMATCH — brand=%q cases=%.0f rate_case=%.2f loose=%.0f rate_bot=%.2f → expected ₹%.2f, got ₹%.2f (Δ%.2f)",
					int(item.RowNumber), item.Brand, item.QuantityRaw, item.RatePerCase, item.LooseBottles, item.RatePerBottle, expected, item.Amount, diff)
			}
		}

		// Loose-only row auto-correct: when amount/rate_per_bottle yields a small whole
		// number (1-12) AND that number is wildly different from quantity_raw interpreted
		// as cases, the AI likely mis-labeled "M Pcs" as "M cases". Recover by deriving
		// the correct bottle count from the amount column directly.
		if item.QuantityUnit == "cases" && item.Amount > 0 && item.RatePerBottle > 0 {
			derivedBottles := item.Amount / item.RatePerBottle
			rounded := float64(int(derivedBottles + 0.5))
			if rounded >= 1 && rounded <= 12 && abs(derivedBottles-rounded) < 0.05 {
				casesInterpretation := item.QuantityRaw * item.RatePerCase
				if abs(casesInterpretation-item.Amount) > item.Amount*0.05 {
					log.Printf("Smart Purchase OCR: Row %d auto-correct: %g cases → %g loose bottles (amount %.2f / rate_b %.2f = %g bottles, doesn't fit %g cases × %.2f)",
						int(item.RowNumber), item.QuantityRaw, rounded, item.Amount, item.RatePerBottle, rounded, item.QuantityRaw, item.RatePerCase)
					item.QuantityUnit = "bottles"
					item.QuantityRaw = rounded
					item.QuantityBottles = rounded
					item.LooseBottles = 0
					if item.QuantityFlag == "" {
						item.QuantityFlag = "auto_corrected_to_loose"
					}
				}
			}
		}

		// Amount auto-correct: when AI captured cases + loose correctly but amount only includes
		// the case-line subtotal (missing loose × rate_bot contribution), add it. Detected via:
		//   amount ≈ cases × rate_per_case (within ±2%)  AND  loose > 0  AND  rate_per_bottle > 0
		// The dual-line "(M Pcs)" amount line is a separate cell in the bill that the AI may
		// have read as qty/rate but skipped in the amount column.
		if item.QuantityUnit == "cases" && item.QuantityRaw > 0 && item.LooseBottles > 0 &&
			item.RatePerCase > 0 && item.RatePerBottle > 0 && item.Amount > 0 {
			caseSubtotal := item.QuantityRaw * item.RatePerCase
			tol := caseSubtotal * 0.02
			if tol < 5 {
				tol = 5
			}
			if abs(caseSubtotal-item.Amount) < tol {
				// Amount matches case subtotal exactly — loose contribution missing
				added := item.LooseBottles * item.RatePerBottle
				newAmount := item.Amount + added
				log.Printf("Smart Purchase OCR: Row %d auto-correct amount: ₹%.2f → ₹%.2f (added loose contribution %g × %.2f = %.2f)",
					int(item.RowNumber), item.Amount, newAmount, item.LooseBottles, item.RatePerBottle, added)
				item.Amount = newAmount
				if item.QuantityFlag == "" {
					item.QuantityFlag = "auto_added_loose_amount"
				}
			}
		}

		// NOTE: cases-from-amount auto-correct DISABLED. It created false positives when
		// the AI got the rate wrong — dividing bad amount by bad rate happened to yield a
		// clean integer that was nonetheless wrong. The verification pass handles these
		// cases more reliably by actually re-reading the image.

		// Ensure confidence has a default
		if item.Confidence == 0 {
			item.Confidence = 0.8
		}
	}

	// Post-filter: drop items where the "brand" field looks like a quantity code.
	// This fires when the AI confuses column layout (quantity column read as brand column).
	// Pattern: "32 CS", "L4CS", "B1 CS", "3410 CS", "(2 CS)" etc.
	quantityAsBrandRx := regexp.MustCompile(`(?i)^\(?\d{0,3}\w{0,3}\s*(cs\.?|pcs\.?|btl\.?)\)?$|^\d{1,3}\s*(cs\.?|pcs\.?)$`)
	cleaned := result.Items[:0]
	droppedQty := 0
	for _, item := range result.Items {
		b := strings.TrimSpace(item.Brand)
		if quantityAsBrandRx.MatchString(b) {
			log.Printf("Smart Purchase OCR: DROP row %d — brand=%q looks like a quantity code (column confusion)", int(item.RowNumber), b)
			droppedQty++
			continue
		}
		cleaned = append(cleaned, item)
	}
	if droppedQty > 0 {
		result.Items = cleaned
		log.Printf("Smart Purchase OCR: Dropped %d items with quantity-as-brand (column confusion detected)", droppedQty)
	}

	log.Printf("Smart Purchase OCR: Extracted %d items from invoice (vendor: %s, invoice: %s)",
		len(result.Items), result.VendorName, result.InvoiceNumber)

	return &result, nil
}

// buildPurchasePrompt creates the AI extraction prompt for Indian vendor purchase invoices
func (s *SmartPurchaseOCR) buildPurchasePrompt() string {
	return `You are extracting data from an Indian liquor vendor purchase invoice / bill.

✋ HANDWRITING POLICY (HARD RULE — read before anything else):
This document is ENTIRELY machine-printed by the supplier. Every value you extract
must come from the printed table. Treat ALL handwritten ink as operator-personal
NOISE and never include it in any field:
  - Margin notes, circled rows, ticks, asterisks, arrows, "OK" / "verified" stamps
  - Hand-tallied subtotals on the side / bottom
  - Pen strokes drawn through brand names or quantities
  - Any character whose slant / stroke thickness / ink-bleed is visibly different
    from the surrounding printed table cells
If a printed cell appears struck-through with handwritten ink BUT the printed
digit underneath is still legible, USE THE PRINTED VALUE — never the strikeout.
Never invent a value to "explain" a handwritten mark. If a printed cell is
genuinely unreadable, emit confidence ≤ 0.4 and let the operator review — don't
guess from handwritten clues.

⛔ GATE PASS DETECTION — READ THIS FIRST:
If the image says "DEPARTMENT OF EXCISE, UTTAR PRADESH", "Transport Permit", "IESCMS",
"Transport Pass", or has columns named "No of Cases Requested / Dispatched" or "Duty Fee"
as the last column — this is a GOVERNMENT GATE PASS, not a purchase invoice.
In that case, return: {"items": [], "error": "gate_pass_not_invoice", "message": "Please upload this image in the Gate Pass slot, not the Invoice slot."}

MOST COMMON INVOICE FORMAT (SONU SINGH style — appears as either 6 or 7 columns):
   6-col:  No. |     | Description of Goods | Quantity | Rate | per | Amount
   7-col:  No. | %   | Description of Goods | Quantity | Rate | per | Amount
- "No." is the serial number → row_number
- "%" (when present) = the excise tax rate percentage for that line (e.g. "12%", "20%").
  IGNORE THIS COLUMN for brand/qty/rate purposes. Capture as excise_rate_pct if convenient,
  otherwise skip. NEVER read the % column as the brand or as a quantity.
- "Description of Goods" contains BRAND NAME + CATEGORY ABBREV + SIZE all in one cell, e.g.
  "ROYAL GREEN WHY 180ML", "Officer's Choice Original Whisky 180ML",
  "8 Pm Black Whisky 180ML (Pet)", "Moonwalk Green Apple Vodka 180ML (Tetra)",
  "Blenders Pride Reserve Collection 375ML"
  Strip these tokens from brand_name BEFORE outputting:
    Trailing category abbrevs: WHY | Why. | WHISKY | RUM | GIN | VODKA | BRANDY | BEER
    Trailing/inline packaging: (Pet) | (PET) | (Glass) | (Laminate) | (Tetra)
  The size token (180ML | 375ML | 750ML | 1L | 1000ML | 90ML) appears at the END of the
  description (or just before the packaging suffix). Parse:
    size_text = "180ML" (preserve exactly as printed)
    size_ml = numeric integer
    brand_name = everything BEFORE the size token, with the abbrev/packaging suffixes removed
  Example: "ROYAL GREEN WHY 180ML"             → brand="Royal Green",  size_ml=180
  Example: "8 Pm Black Whisky 180ML (Pet)"     → brand="8 PM Black",   size_ml=180, packaging="Pet"
  Example: "Moonwalk Green Apple Vodka 180ML"  → brand="Moonwalk Green Apple", size_ml=180
- "Quantity" = "N CS" (always in cases on this format).
  Set quantity_unit="cases", quantity_raw=N. NEVER copy the "CS" suffix into brand_name.
- "Rate" = rate PER CASE. Set rate_per_case=Rate, rate_per_bottle = Rate/bottles_per_case
- "per" = always "CS" in this format
- "Amount" = Quantity × Rate (per case amount)
- These invoices are SINGLE-LINE per row (no dual-line format)
- TCS @ 2% appears in the footer — it's a tax line, skip it (don't emit as an item)
- ZERO-RATE ROWS: Some rows show Quantity > 0 with Rate = 0 / blank / "—" (free-stock or
  promo deliveries). These ARE valid product rows — emit them with rate_per_bottle=0,
  amount=0, confidence=0.55. Do NOT skip them; do NOT confuse them with tax/duty footer rows.

FIRST: Look at the TOP of the invoice for:
1. VENDOR NAME and address (the seller / supplier company)
2. VENDOR GST NUMBER (format like 09XXXXX1234X1Z5)
3. INVOICE NUMBER (Bill No, Invoice No, Inv No, "Bill No.", "Invoice #", etc.).
   CRITICAL: this is the SUPPLIER-PRINTED unique number, typically 3-10 digits
   (e.g. "459", "12345", "INV-2024-001"). It is NEVER the words "Page 1",
   "Page 2", "Continued", "Page", or any folio label — those are page markers
   added by the printer, not invoice numbers. If you only see a "Page N"
   marker on this image and no actual invoice number, leave invoice_number
   as "" (empty string) — DO NOT use the page marker.
4. INVOICE DATE (DD/MM/YYYY or DD-MM-YYYY format common in India)

The invoice table typically has columns like:
- S.No / Sr. / Sl.No / No. (Serial Number) — USE THIS as the row_number
- Description of Goods / Brand Name / Particulars / Item Name (brand name + size, one per row)
- Size (may be embedded in Description, or a separate column; 180ml, 375ml, 750ml, 1000ml)
- Quantity column — CRITICAL DUAL-LINE FORMAT (see rule 4b below)
- Rate / Price
- per (tells you the rate unit: "Cs." = per case, "Pcs" = per bottle/piece)
- Amount / Total (= Quantity × Rate)
- Batch No / Lot No (optional)

⚠️ FATAL ANTI-PATTERN — READ THIS BEFORE EXTRACTING ANYTHING:
If any item's "brand" field would be a quantity like "32 CS", "41 CS", "L4CS", "B1 CS",
"(2 CS)", "314CS", "102 CS" etc. — you have read the WRONG COLUMN. The brand field must
ONLY contain a liquor brand name (e.g. "Royal Stag", "Imperial Blue", "McDowell's No.1").
Quantities like "N Cs." or "M Pcs" belong in quantity_raw and quantity_unit ONLY.
If you cannot find the brand name column, scan the DESCRIPTION or PARTICULARS column which
typically appears immediately after the S.No column, spanning the full text "BRAND SIZE".
Never put a row number, serial code, case count, or amount in the "brand" field.

CRITICAL RULES:
1. ALWAYS extract vendor_name from the invoice header
2. ALWAYS extract invoice_number and invoice_date if visible
3. Extract vendor_gst if visible (Indian GST format: 2 digits + letters + digits)

4. ROW-NUMBER ANCHORING — 100% RECALL IS REQUIRED:
   Every row has a Serial Number in the leftmost column. ALWAYS use that S.No as
   row_number in the output. NEVER SKIP a serial. If a row is smudged, faded,
   handwritten-on, or partly obscured by glare, EMIT IT ANYWAY with confidence 0.4
   and a best-effort brand. Empty / blank fields are fine — emit row_number with
   brand="" rather than dropping it.

   Before you finish, count the rows you emitted. The set of row_numbers you emit
   MUST be the contiguous range [first_visible_serial .. highest_visible_serial]
   with NO gaps. If the bill has S.No 1..48 visible, your output's items array
   MUST contain row_number=1, 2, 3, ..., 48 — every integer. Missing 18 rows out
   of 48 is a CRITICAL FAILURE; the operator cannot use a partial scan.

   If you find yourself running out of context / patience, prefer emitting MORE
   rows with low confidence over FEWER rows with high confidence. The downstream
   reviewer can fix a low-confidence cell in 1 second; recovering a row you
   dropped requires a manual re-scan of the entire bill.

4b. DUAL-LINE QUANTITY CELLS — THIS IS THE #1 SOURCE OF EXTRACTION ERRORS. Read slowly.

    STRUCTURAL TRUTH: Each S.No is a HARD ROW BOUNDARY. Everything in Quantity, Rate, per, and
    Amount columns between S.No N and S.No (N+1) belongs to row N. Nothing from row N's columns
    spills into row (N+1)'s brand. No matter how the lines are visually stacked, the binding is:
    "lines between two S.No labels = that S.No's row".

    Indian liquor invoices routinely put TWO lines inside one row:
       Line 1 (top):     "N Cs."       ← full cases
       Line 2 (bottom):  "(M Pcs)"     ← ADDITIONAL loose bottles, typically in parentheses
    Both lines belong to the SAME S.No and the SAME brand. The Rate column has TWO matching lines:
       rate_line_1 = ₹/Cs  for the N cases
       rate_line_2 = ₹/Pcs for the M loose bottles
    The Amount column has TWO matching lines. The row's TOTAL amount is the sum.

    Some rows have ONLY loose bottles (no cases) — written as just "M Pcs" on Line 1:
       quantity_raw = M,  quantity_unit = "bottles",  loose_bottles = 0,  cases = 0
    Some rows have ONLY cases (no loose) — written as just "N Cs." on Line 1:
       quantity_raw = N,  quantity_unit = "cases",    loose_bottles = 0

    PARENTHESES ARE NEVER EXCLUSIONS. "(2 Pcs)" means 2 pieces, READ THE NUMBER.

    THE FOUR COMBINATIONS YOU MUST HANDLE — pick exactly one per row.
    Convention: quantity_raw = the PRIMARY count printed on Line 1.
                loose_bottles = "extra Pcs on top of cases" (only set in case (c)).
       (a) "N Cs."  only              → quantity_raw=N, unit="cases",   loose_bottles=0,  bottles=N*bpc
       (b) "M Pcs"  only              → quantity_raw=M, unit="bottles", loose_bottles=0,  bottles=M
       (c) "N Cs." + "(M Pcs)"        → quantity_raw=N, unit="cases",   loose_bottles=M,  bottles=N*bpc+M
       (d) Blank row                  → SKIP (do not emit)

    Dual-line worked example (memorize this exact structure):
       S.No 47 | Johnnie Walker Double Black 750ml | Quantity: "2 Cs." / "(1 Pcs)"
       Rate: "2,612.29" / "435.38"   | per: "Cs." / "Pcs"  | Amount: "5,224.58" / "435.38"
       → row_number=47, cases=2, loose=1, bottles=2*12+1=25, rate_per_case=2612.29,
         rate_per_bottle=435.38 (the Pcs line), amount=5224.58+435.38=5659.96

    A FULL DUAL-LINE BLOCK — exactly the pattern that breaks naive extractors:
       S.No 44 | Black & White Celebration 180ml Pet | Qty: "1 Cs." / "(2 Pcs)"
                Rate: "18,672.48" / "4,001.88"   per: "Cs." / "Pcs"   Amount: "18,672.48" / "8,003.76"
                → cases=1, loose=2, bottles=50, rate_per_case=18672.48, rate_per_bottle=4001.88,
                  amount = 18672.48 + 8003.76 = 26676.24

       S.No 45 | Indri Single Malt 750ml | Qty: "2 Pcs"  (LOOSE-ONLY ROW — no cases line!)
                Rate: "2,049.55"   per: "Pcs"   Amount: "4,099.10"
                → cases=0, loose=0, quantity_raw=2, unit="bottles", bottles=2,
                  rate_per_bottle=2049.55, amount=4099.10
                CAUTION: Do NOT inherit row 44's "(2 Pcs)" or its 4001.88 rate. Row 45's
                "2 Pcs" is its OWN primary line, with its OWN brand and rate.

       S.No 46 | Bombay Sapphire 750ml | Qty: "1 Cs." / "(2 Pcs)"
                Rate: "3,540.07" / "..."  Amount: "3,540.07" / "..."
                → cases=1, loose=2, bottles=14, amount = sum of both lines

       S.No 47 | JW Double Black 750ml | Qty: "2 Cs." / "(1 Pcs)"   (as in the example above)

       S.No 48 | Jack Daniel's Tennessee Whisky 750ml | Qty: "2 Cs." / "(2 Pcs)"
                Rate: "2,612.29" / "..."  Amount: "5,224.58" / "..."
                → cases=2, loose=2, bottles=26

    The KEY INSIGHT: when row N has "(M Pcs)" as its second line, that line's amount belongs to
    row N — NOT row N+1. The next S.No marks where row N's data ends and row (N+1) begins.

    AMOUNT IS THE GROUND TRUTH. Algorithm to use when extracting any row:
       Step 1: Find the S.No anchor on the leftmost column.
       Step 2: Read EVERY printed Amount cell between this S.No and the next S.No.
       Step 3: Read the matching Rate cells for those Amount cells (same lines).
       Step 4: For each (rate, amount) pair where the unit (per column) is "Cs.":
                 cases = round(amount / rate)
       Step 5: For each (rate, amount) pair where the unit is "Pcs":
                 loose_bottles = round(amount / rate)
       Step 6: Total amount for the row = sum of all Amount cells in that row's block.
       Step 7: Verify: amount / rate must be a SMALL INTEGER (1-10 typically). If your division
               doesn't produce a near-integer, you're reading the wrong rate or wrong amount.

    Worked example for Row 47 (JW Double Black 750ml):
       Amount cells in this row: ["5,224.58", "435.38"]   ← TWO cells, not one
       Rate cells in this row:   ["2,612.29", "435.38"]
       per cells:                ["Cs.",      "Pcs"]
       cases  = round(5224.58 / 2612.29) = round(2.0) = 2     ← MUST be 2, not 1
       loose  = round(435.38 / 435.38)   = 1
       total amount = 5224.58 + 435.38 = 5659.96
       quantity_raw=2, unit="cases", loose_bottles=1, bottles=2*12+1=25, amount=5659.96

    AMOUNT-BASED CROSS-CHECK — ALWAYS DO THIS BEFORE EMITTING A ROW:
       Expected amount = (cases × rate_per_case) + (loose_bottles × rate_per_bottle)
       If your extracted amount disagrees with Expected by more than ₹1, you have misread one of:
       brand/rate/quantity. Re-examine the row before emitting it. This check catches row-shift
       errors where "(M Pcs)" from the row above was attributed to this row.

    SANITY CHECK on rate magnitudes — typical Indian liquor rates per bottle:
       180ml IMFL: ₹100-₹500       375ml IMFL: ₹200-₹1000
       750ml IMFL: ₹400-₹3000      750ml premium scotch / single malt: ₹2000-₹6000
       750ml import (JW Double Black, Jack Daniel's, Indri SM): ₹2500-₹4500
    If your extracted rate_per_bottle is below ₹100 for a 750ml premium row OR if it differs
    from these ranges by 5x+, you've likely mis-attributed a rate from a different row.

5. rate_per_bottle should be the cost per individual bottle:
   - If a per-case rate is shown, compute per-bottle = rate_per_case / bottles_per_case
   - Per-bottle rates for Indian spirits typically range ₹50 to ₹3000 (flag outliers)

6. Standard UP India case sizes (bottles_per_case for a given size_ml):
   - 750ml = 12
   - 375ml = 24
   - 180ml = 48
   - 1000ml = 9
   - 90ml = 96
   - Beer 650ml = 12, Beer 500ml = 12, Beer 330ml = 24

7. SKIP tax/duty line items (GST, CGST, SGST, IMFL Duty, VAT, Cess, TDS, TCS)
8. SKIP total/subtotal/grand total rows — BUT extract the footer total:
   document_total_cases = the number before "Cs." in the "Total N Cs." footer (e.g. "77 Cs.")
   document_total_amount = the grand total amount in ₹ (e.g. ₹6,04,694.23 → 604694.23)
   Indian numbers use the lakh-crore comma convention ("6,04,694.23" = 604694.23, NOT 6.04M);
   always convert to plain decimal in the JSON.
9. Batch numbers look like alphanumeric codes (e.g., "B2024-1234", "LOT-567")
10. Size abbreviations: "QR"/"Qrt" = 180ml, "Hf"/"Half" = 375ml, "Fl"/"Full" = 750ml, "NP"/"Nip" = 90ml
11. Common category keywords: IMFL = spirits, CL = Country Liquor, BIO = Beer
12. KNOWN INDIAN LIQUOR BRAND NAMES — use these correct spellings when you recognize them on the invoice:
   IMFL whiskies: Imperial Blue, Blenders Pride, Royal Stag (Barrel Select / Premium / Classic),
     McDowell's No.1 (Platinum / Diet Mate / Luxury Gold), Officer's Choice (Blue / Red / Prestige),
     8 PM Black, 8 PM Premium Black, 8 PM Rare, 8 PM Bonus, 8 PM Gold, After Dark (Blue / Rare Grain),
     All Seasons (Reserve / Select / Rare Reserve), Royal Green, Royal Challenge (Classic / American Pride),
     Rockford (Reserve / Premium / Special), Iconiq White, Sterling Reserve (B7 / B10), Signature (Premier / Rare Aged),
     Morpheus, Morpheus Blue, Black Dog (Triple Gold / Centenary), 100 Pipers, Black & White,
     Royal Ranthambore, Indri (Single Malt), Ballantine's, Teacher's, Vat 69.
   Imported scotch/bourbon: Johnnie Walker (Red Label / Black Label / Double Black / Gold Label / Green Label / Blue Label),
     Jack Daniel's (Tennessee Whiskey / Honey / Apple), Jim Beam (White / Black / Honey / Devil's Cut),
     Chivas Regal (12 / 15 / 18), Monkey Shoulder, Jameson, Glenfiddich, Glenlivet.
   Rums: Old Monk (XXX / Gold Reserve / Supreme), Bacardi (White / Gold / Black / Limon), Contessa Rum, Hercules Rum.
   Vodka: Magic Moments (Superior Vodka, Remix Green Apple, Remix Orange, Remix Raspberry, Verve Lemon Zest,
     Verve Spicy Mint, Verve Cranberry Tease, Verve Jamun), M2 Magic Moments (same variants),
     Smirnoff (Red / Green Apple / Orange), Absolut, White Mischief, Romanov, Moonwalk, Moooz.
   Gin: Bombay Sapphire, Beefeater, Greater Than, Hapusa, Stranger & Sons.
   Beer: Kingfisher, Tuborg, Budweiser, Haywards 5000, Carlsberg.
   If handwritten text is unclear, use context + these known names to pick the most likely brand.

13. COMMON ABBREVIATIONS on invoices — ALWAYS expand these to the full brand name in the "brand" field.
    Never leave the abbreviation as the brand. If unsure which variant, pick the most common one and
    lower confidence to 0.6:
    - "JW" / "J.W" / "Jhon Walker" / "Johnie Walker" → "Johnnie Walker" (add the label if readable:
       "JW Double Black" → "Johnnie Walker Double Black", "JW Black" → "Johnnie Walker Black Label")
    - "JD" / "J.D" → "Jack Daniel's" (add variant if readable: "JD Honey" → "Jack Daniel's Honey")
    - "JB" → "Jim Beam"
    - "CR" / "CR 12" → "Chivas Regal" (add "12"/"15"/"18" if readable)
    - "MCD" / "Mc1" / "McD1" / "Mc No.1" → "McDowell's No.1"
    - "RS" / "R.S" / "R Stag" → "Royal Stag" (add variant if readable)
    - "IB" / "I.B" → "Imperial Blue"
    - "BP" / "B.P" → "Blenders Pride"
    - "BS" → "Bombay Sapphire"
    - "B&W" / "BW" → "Black & White"
    - "OC" → "Officer's Choice"
    - "AD" → "After Dark"
    - "MM" / "M2" → "Magic Moments" (preserve flavor variant words like "Green Apple", "Jamun", "Orange")
    - "SR" / "Sterling" → "Sterling Reserve"
    - "OM" → "Old Monk"
    FLAVOR VARIANT RULE — for Magic Moments / M2 / Smirnoff / Jack Daniel's / 8 PM, the flavor/variant word
    (Green Apple, Orange, Jamun, SpicyMint, Cranberry, Verve, Remix, Honey, Apple, Gold, Black, Premium) IS part
    of the brand identity. Preserve it verbatim in the brand field. Never collapse "Magic Moments Green Apple"
    to bare "Magic Moments" or "Magic Moments Jamun SpicyMint" to "Magic Moments Superior".

14. QUANTITY CROSS-VALIDATION — REQUIRED. After extracting rate_per_bottle, quantity_bottles, and amount,
    verify that amount ≈ rate_per_bottle × quantity_bottles (allow ±3% rounding tolerance). If the
    identity does NOT hold, the row probably has a rate/unit mismatch (per-case rate misread as per-bottle,
    or cases/bottles columns swapped). In that case:
    - Re-read the columns and try the alternate interpretation (rate_per_case vs rate_per_bottle).
    - Set confidence ≤ 0.6 and include "quantity_flag": "rate_unit_uncertain" in that item.
    Never silently emit rows where amount ≠ rate × qty — that's worse than flagging.

Return ONLY valid JSON with this exact structure:

{
  "vendor_name": "Vendor Company Name",
  "vendor_gst": "09ABCDE1234F1Z5",
  "vendor_address": "Full address if visible",
  "invoice_number": "INV-2024-001",
  "invoice_date": "2024-03-15",
  "items": [
    {
      "row_number": 1,
      "brand": "Brand Name as written on invoice",
      "category": "whiskey",
      "size_text": "750ml",
      "size_ml": 750,
      "quantity_raw": 10,
      "quantity_unit": "cases",
      "bottles_per_case": 12,
      "quantity_bottles": 120,
      "rate_per_bottle": 450.00,
      "rate_per_case": 5400.00,
      "amount": 54000.00,
      "loose_bottles": 1,
      "batch_number": "B2024-1234",
      "confidence": 0.95,
      "quantity_flag": ""
    }
  ],
  "expected_row_count": 48,
  "document_total_cases": 77,
  "document_total_amount": 604694.23,
  "subtotal": 54000.00,
  "tax_amount": 5400.00,
  "total_amount": 59400.00,
  "raw_text": ""
}

expected_row_count is the HIGHEST serial number (S.No) you see on the invoice (across all pages visible
to you), even if you couldn't read every row cleanly. It's used to detect partial extractions — if you
extract 42 items but S.No reaches 48, set expected_row_count: 48 so the system knows rows were dropped.

document_total_cases is the number printed on the "Total N Cs." footer line. document_total_amount is
the grand total amount (in plain ₹, no lakh commas). These are used to cross-check that the sum of
extracted per-row cases and amounts matches the footer; if not, the scan is partial or has bad rows.

loose_bottles is the "(M Pcs)" value when a row has both cases AND extra loose bottles on top. When the
row has only cases, set loose_bottles to 0.

Categories: whiskey, rum, vodka, beer, brandy, gin, wine, country_liquor, rtd
If you cannot determine category, use "spirits".
If you cannot read some text clearly, set confidence lower (0.5-0.7).
Return empty items array if no product line items found.
Return only valid JSON, no markdown formatting.`
}

// normalizeSizeText converts common size text to ML value
func normalizeSizeText(sizeText string) int {
	s := strings.ToLower(strings.TrimSpace(sizeText))
	s = strings.ReplaceAll(s, " ", "")

	// Direct ML values
	sizeMap := map[string]int{
		"90ml": 90, "180ml": 180, "375ml": 375, "750ml": 750, "1000ml": 1000,
		"90": 90, "180": 180, "375": 375, "750": 750, "1000": 1000,
		"1l": 1000, "1ltr": 1000, "1litre": 1000, "1liter": 1000,
	}
	if v, ok := sizeMap[s]; ok {
		return v
	}

	// Colloquial terms (UP India)
	colloquial := map[string]int{
		"nip": 90, "np": 90, "nips": 90,
		"quarter": 180, "qr": 180, "qrt": 180, "quart": 180,
		"half": 375, "hf": 375, "halfbottle": 375,
		"full": 750, "fl": 750, "bottle": 750, "btl": 750,
		"liter": 1000, "litre": 1000, "ltr": 1000,
	}
	if v, ok := colloquial[s]; ok {
		return v
	}

	// Generic numeric parser: extract digits from strings like "500ml", "330ML", "650"
	re := regexp.MustCompile(`(\d+)`)
	if matches := re.FindString(s); matches != "" {
		if val, err := strconv.Atoi(matches); err == nil && val > 0 && val <= 5000 {
			return val
		}
	}

	return 0
}

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

// extractGatePassWithAI extracts duty items from a gate pass image using AI.
// The new prompt returns a GatePassExtraction object with items + footer totals;
// we fall back to parsing a bare array for backward compatibility with any older prompt.
//
// v1.0.193 — cascade Gemini → Claude → OpenAI with footer reconciliation as
// the gate. If footer.total_cases is set on the response and the sum of
// items.cases is < 70% of footer.total_cases, the page is considered
// "truncated" (Gemini's non-deterministic response cap dropped rows). We
// escalate to Claude. Real-data trigger: chhotu's gate-pass had footer
// total_cases=86 but Gemini extracted only 29 rows-worth (sum=29). Claude
// gets the full 86 deterministically.
func (s *SmartPurchaseOCR) extractGatePassWithAI(ctx context.Context, imageData []byte, contentType string, prompt string) (*GatePassExtraction, error) {
	primary := os.Getenv("SMART_PURCHASE_PRIMARY")
	if primary == "" {
		primary = "gemini"
	}

	parse := func(responseText string) (*GatePassExtraction, error) {
		// Strip markdown fences first.
		responseText = strings.TrimSpace(responseText)
		if idx := strings.Index(responseText, "```json"); idx >= 0 {
			responseText = responseText[idx+7:]
		} else if idx := strings.Index(responseText, "```"); idx >= 0 {
			responseText = responseText[idx+3:]
		}
		if idx := strings.LastIndex(responseText, "```"); idx >= 0 {
			responseText = responseText[:idx]
		}
		responseText = strings.TrimSpace(responseText)

		// Some models (Claude in particular) like to preface the JSON
		// response with prose — "I'll carefully analyze...", "Looking at
		// the gate pass...". Strip everything before the first '{' or '['
		// and everything after the last matching brace/bracket.
		firstObj := strings.Index(responseText, "{")
		firstArr := strings.Index(responseText, "[")
		start := -1
		switch {
		case firstObj < 0 && firstArr < 0:
			return nil, fmt.Errorf("parse error: no JSON delimiter found")
		case firstObj < 0:
			start = firstArr
		case firstArr < 0:
			start = firstObj
		default:
			if firstObj < firstArr {
				start = firstObj
			} else {
				start = firstArr
			}
		}
		// Trim leading prose.
		responseText = responseText[start:]
		// Trim trailing prose by scanning balanced braces from the start.
		end := matchBalancedJSONEnd(responseText)
		if end > 0 {
			responseText = responseText[:end]
		}

		var extraction GatePassExtraction
		if uErr := json.Unmarshal([]byte(responseText), &extraction); uErr == nil && len(extraction.Items) > 0 {
			return &extraction, nil
		}
		var items []GatePassDutyItem
		if uErr := json.Unmarshal([]byte(responseText), &items); uErr != nil {
			return nil, fmt.Errorf("parse error: %w", uErr)
		}
		return &GatePassExtraction{Items: items}, nil
	}

	// looksTruncated returns true ONLY when extraction is severely under
	// (< 30% of footer cases). v1.0.193 latency-tuned: previously < 70%
	// would escalate which was burning 60s per page. Real-data: GP often
	// gets 50-70% coverage on the first try; that's good-enough — operator's
	// review screen flags missing rows via "bill_only_no_gp" cross-val.
	looksTruncated := func(ex *GatePassExtraction) bool {
		if ex == nil || ex.TotalCases <= 0 {
			return false
		}
		sum := 0
		for _, it := range ex.Items {
			sum += it.Cases
		}
		return sum*10 < ex.TotalCases*3 // sum < 30% of footer (was 70%)
	}

	type backend struct {
		name string
		fn   func() (string, error)
	}
	tryGemini := func() (string, error) {
		if s.geminiKey == "" {
			return "", fmt.Errorf("gemini: no api key")
		}
		return s.callGeminiForGatePass(ctx, imageData, contentType, prompt)
	}
	tryClaude := func() (string, error) {
		if s.anthropicKey == "" {
			return "", fmt.Errorf("claude: no api key")
		}
		return s.callClaudeForGatePass(ctx, imageData, contentType, prompt)
	}
	tryOpenAI := func() (string, error) {
		if s.openaiKey == "" {
			return "", fmt.Errorf("openai: no api key")
		}
		return s.callOpenAIForGatePass(ctx, imageData, contentType, prompt)
	}

	cascade := []backend{}
	switch primary {
	case "claude":
		cascade = []backend{{"claude", tryClaude}, {"gemini", tryGemini}, {"openai", tryOpenAI}}
	case "openai":
		cascade = []backend{{"openai", tryOpenAI}, {"gemini", tryGemini}, {"claude", tryClaude}}
	default:
		cascade = []backend{{"gemini", tryGemini}, {"claude", tryClaude}, {"openai", tryOpenAI}}
	}

	var bestPartial *GatePassExtraction
	var bestPartialBackend string
	var lastErr error
	for i, b := range cascade {
		responseText, err := b.fn()
		if err != nil {
			if !strings.HasSuffix(err.Error(), "no api key") {
				log.Printf("Smart Purchase Gate-Pass: %s failed (%v), trying next", b.name, err)
			}
			lastErr = err
			continue
		}
		ex, parseErr := parse(responseText)
		if parseErr != nil || ex == nil {
			log.Printf("Smart Purchase Gate-Pass: %s parse failed (%v) — trying next backend", b.name, parseErr)
			lastErr = parseErr
			continue
		}
		// v1.0.361 — fast mode (hybrid): accept the first parsed backend; skip the
		// truncation cascade (Textract backstops completeness, and a per-page footer
		// often carries the GRAND total → false "truncated" → wasted escalation).
		if looksTruncated(ex) && i < len(cascade)-1 && !gpFastLLM(ctx) {
			sum := 0
			for _, it := range ex.Items {
				sum += it.Cases
			}
			log.Printf("Smart Purchase Gate-Pass: %s under-extracted (%d items / %d cases vs footer %d) — escalating to next backend",
				b.name, len(ex.Items), sum, ex.TotalCases)
			if bestPartial == nil || len(ex.Items) > len(bestPartial.Items) {
				bestPartial = ex
				bestPartialBackend = b.name
			}
			continue
		}
		log.Printf("Smart Purchase Gate-Pass: %s returned %d items (footer cases=%d) — accepted", b.name, len(ex.Items), ex.TotalCases)
		return ex, nil
	}
	if bestPartial != nil {
		log.Printf("Smart Purchase Gate-Pass: cascade exhausted — returning best partial from %s (%d items)", bestPartialBackend, len(bestPartial.Items))
		return bestPartial, nil
	}
	if lastErr == nil {
		return nil, fmt.Errorf("no AI API keys configured for gate-pass extraction")
	}
	return nil, lastErr
}

// callClaudeForGatePass mirrors callGeminiForGatePass / callOpenAIForGatePass
// but uses Anthropic's Claude Sonnet 4.6 (deterministic on dense tables —
// gemini-flash-latest's response-cap on the 86-row gate-pass collapses 70%
// of dispatch rows).
func (s *SmartPurchaseOCR) callClaudeForGatePass(ctx context.Context, imageData []byte, contentType string, prompt string) (string, error) {
	if s.anthropicKey == "" {
		return "", fmt.Errorf("claude: no api key")
	}
	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(contentType), "png") {
		mediaType = "image/png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageData)
	systemBlocks := []claudeContent{
		{Type: "text", Text: prompt, CacheControl: &struct {
			Type string `json:"type"`
		}{Type: "ephemeral"}},
	}
	userBlocks := []claudeContent{
		{Type: "image", Source: &claudeImageSource{Type: "base64", MediaType: mediaType, Data: base64Image}},
		{Type: "text", Text: "Extract the gate-pass dispatch table per the schema in the system prompt. Return ONLY JSON, no prose."},
	}
	model := os.Getenv("CLAUDE_PURCHASE_MODEL")
	if model == "" {
		model = claudeDefaultPrimary // claude-sonnet-4-6
	}
	request := claudeRequest{
		Model:       model,
		MaxTokens:   16384,
		Temperature: 0.0,
		System:      systemBlocks,
		Messages:    []claudeMessage{{Role: "user", Content: userBlocks}},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, "POST", claudeAPIEndpoint, bytes.NewBuffer(requestBody))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.anthropicKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)
	req.Header.Set("anthropic-beta", claudeBetaPromptCaching)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("claude api error %d: %s", resp.StatusCode, string(body[:min(len(body), 300)]))
	}
	var apiResp claudeResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return "", err
	}
	if apiResp.Error != nil {
		return "", fmt.Errorf("claude error: %s", apiResp.Error.Message)
	}
	var sb strings.Builder
	for _, c := range apiResp.Content {
		if c.Type == "text" {
			sb.WriteString(c.Text)
		}
	}
	return sb.String(), nil
}

// callOpenAIForGatePass calls OpenAI Vision API for gate pass extraction
func (s *SmartPurchaseOCR) callOpenAIForGatePass(ctx context.Context, imageData []byte, contentType string, prompt string) (string, error) {
	// Reuse the same OpenAI Vision call pattern as extractWithOpenAI but with custom prompt
	base64Data := base64.StdEncoding.EncodeToString(imageData)
	dataURI := fmt.Sprintf("data:%s;base64,%s", contentType, base64Data)

	reqBody := map[string]interface{}{
		"model": "gpt-4o",
		"messages": []map[string]interface{}{
			{
				"role": "user",
				"content": []map[string]interface{}{
					{"type": "text", "text": prompt},
					{"type": "image_url", "image_url": map[string]string{"url": dataURI, "detail": "high"}},
				},
			},
		},
		"max_tokens": 16384,
		"temperature": 0.1,
		"response_format": map[string]string{"type": "json_object"},
	}

	jsonBytes, _ := json.Marshal(reqBody)
	req, _ := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(jsonBytes))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openaiKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("OpenAI error %d: %s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	json.Unmarshal(body, &result)
	if len(result.Choices) > 0 {
		return result.Choices[0].Message.Content, nil
	}
	return "", fmt.Errorf("no response from OpenAI")
}

// callGeminiForGatePass calls Gemini Vision API for gate pass extraction
func (s *SmartPurchaseOCR) callGeminiForGatePass(ctx context.Context, imageData []byte, contentType string, prompt string) (string, error) {
	base64Data := base64.StdEncoding.EncodeToString(imageData)

	reqBody := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"parts": []map[string]interface{}{
					{"text": prompt},
					{"inline_data": map[string]string{"mime_type": contentType, "data": base64Data}},
				},
			},
		},
		// v1.0.215.5 — temperature=0.0 for deterministic GP extraction. Was 0.1
		// which caused orphan-count fluctuation 3-14 across replays of the same
		// bill. Tushar reported the variability as confusing operator UX.
		"generationConfig": map[string]interface{}{"temperature": 0.0, "maxOutputTokens": 32768, "responseMimeType": "application/json"},
	}

	jsonBytes, _ := json.Marshal(reqBody)
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)
	req, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonBytes))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-goog-api-key", s.geminiKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("Gemini error %d: %s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}

	var result struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}
	json.Unmarshal(body, &result)
	if len(result.Candidates) > 0 && len(result.Candidates[0].Content.Parts) > 0 {
		return result.Candidates[0].Content.Parts[0].Text, nil
	}
	return "", fmt.Errorf("no response from Gemini")
}

// matchBalancedJSONEnd scans a string starting at index 0 (which must be '{'
// or '[') and returns the index of the position AFTER the closing brace or
// bracket that balances the opener. Returns 0 if no balanced match is found
// (caller treats that as "use the whole string").
//
// Used to trim trailing prose that LLMs sometimes append after the JSON
// response — e.g. Claude returns "{...} <newline> Hope this helps!" and
// json.Unmarshal chokes on the trailing text.
func matchBalancedJSONEnd(s string) int {
	if len(s) == 0 {
		return 0
	}
	open := s[0]
	var close byte
	switch open {
	case '{':
		close = '}'
	case '[':
		close = ']'
	default:
		return 0
	}
	depth := 0
	inString := false
	escape := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if escape {
			escape = false
			continue
		}
		if c == '\\' && inString {
			escape = true
			continue
		}
		if c == '"' {
			inString = !inString
			continue
		}
		if inString {
			continue
		}
		if c == open {
			depth++
		} else if c == close {
			depth--
			if depth == 0 {
				return i + 1
			}
		}
	}
	return 0
}

// repairTruncatedExtraction salvages a partial JSON document that was cut off
// mid-array. Returns the repaired JSON, the item count recovered, and ok=true
// when at least one complete item was found.
//
// Real-data trigger: chhotu's 2026-05-03 SONU SINGH FL-2 invoice (41 rows on
// page 1). Gemini's response was 3063 chars and cut off mid-token at row 1's
// "rate_per_bottle". Unrepaired the error was "unexpected end of JSON input"
// and the entire page was thrown away — losing 40+ rows. This function locates
// the last full item (depth-zero `}` inside the items array) and rebuilds a
// parseable document with the array + outer braces closed.
func repairTruncatedExtraction(jsonText string) (string, int, bool) {
	itemsIdx := strings.Index(jsonText, "\"items\"")
	if itemsIdx < 0 {
		return "", 0, false
	}
	openBracket := strings.Index(jsonText[itemsIdx:], "[")
	if openBracket < 0 {
		return "", 0, false
	}
	openBracket += itemsIdx

	depth := 0
	inString := false
	escape := false
	lastSafeEnd := -1
	itemCount := 0
	for i := openBracket + 1; i < len(jsonText); i++ {
		c := jsonText[i]
		if escape {
			escape = false
			continue
		}
		if c == '\\' && inString {
			escape = true
			continue
		}
		if c == '"' {
			inString = !inString
			continue
		}
		if inString {
			continue
		}
		switch c {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				lastSafeEnd = i + 1
				itemCount++
			}
		case ']':
			if depth == 0 {
				return jsonText, itemCount, itemCount > 0
			}
		}
	}
	if lastSafeEnd < 0 {
		return "", 0, false
	}
	return jsonText[:lastSafeEnd] + "]}", itemCount, true
}
