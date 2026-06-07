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

// OpenAIOCRService handles OCR extraction using OpenAI GPT-4o Vision API
type OpenAIOCRService struct {
	apiKey         string
	logger         *logrus.Logger
	sizeNormalizer *SizeNormalizer
	httpClient     *http.Client
	productNames   []string // temporarily set for product-aware extraction
}

// OpenAI API structures
type openAIMessage struct {
	Role    string      `json:"role"`
	Content interface{} `json:"content"`
}

type openAITextContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type openAIImageURL struct {
	URL    string `json:"url"`
	Detail string `json:"detail,omitempty"`
}

type openAIImageContent struct {
	Type     string         `json:"type"`
	ImageURL openAIImageURL `json:"image_url"`
}

type openAIRequest struct {
	Model               string              `json:"model"`
	Messages            []openAIMessage     `json:"messages"`
	MaxCompletionTokens int                 `json:"max_completion_tokens"`
	Temperature         float64             `json:"temperature"`
	ResponseFormat      *openAIResponseFmt  `json:"response_format,omitempty"`
}

type openAIResponseFmt struct {
	Type string `json:"type"`
}

type openAIChoice struct {
	Message struct {
		Content string `json:"content"`
	} `json:"message"`
	FinishReason string `json:"finish_reason"`
}

type openAIResponse struct {
	ID      string         `json:"id"`
	Choices []openAIChoice `json:"choices"`
	Usage   struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage"`
	Error *struct {
		Message string `json:"message"`
		Type    string `json:"type"`
		Code    string `json:"code"`
	} `json:"error,omitempty"`
}

// NewOpenAIOCRService creates a new OpenAI OCR service
func NewOpenAIOCRService(logger *logrus.Logger) (*OpenAIOCRService, error) {
	// Get API key from multiple sources in order of preference
	var apiKey string

	// 1. Check environment variable first (highest priority)
	apiKey = os.Getenv("OPENAI_API_KEY")

	// 2. Try Docker-mounted path
	if apiKey == "" {
		dockerPath := "/app/credentials/openai-api-key.txt"
		if keyBytes, err := os.ReadFile(dockerPath); err == nil {
			apiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	// 3. Try local development path
	if apiKey == "" {
		localPath := "./credentials/openai-api-key.txt"
		if keyBytes, err := os.ReadFile(localPath); err == nil {
			apiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	if apiKey == "" {
		logger.Warn("OpenAI API key not found, OCR will use fallback mode")
		return &OpenAIOCRService{
			logger:         logger,
			sizeNormalizer: NewSizeNormalizer(),
			httpClient: &http.Client{
				Timeout: 120 * time.Second,
			},
		}, nil
	}

	logger.Info("OpenAI OCR service initialized with GPT-5.2 (best accuracy)")
	return &OpenAIOCRService{
		apiKey:         apiKey,
		logger:         logger,
		sizeNormalizer: NewSizeNormalizer(),
		httpClient: &http.Client{
			Timeout: 120 * time.Second,
		},
	}, nil
}

// ExtractFromImageWithProducts extracts with a product-aware prompt for better matching
func (o *OpenAIOCRService) ExtractFromImageWithProducts(ctx context.Context, imageBytes []byte, imageType string, productNames []string) (*ReceiptExtractionResult, error) {
	if len(productNames) == 0 {
		return o.ExtractFromImage(ctx, imageBytes, imageType)
	}

	// Temporarily set product names, call standard extraction, then clear
	o.productNames = productNames
	defer func() { o.productNames = nil }()
	return o.ExtractFromImage(ctx, imageBytes, imageType)
}

// ExtractFromImage extracts liquor items from receipt image using OpenAI GPT-5.2 Vision
func (o *OpenAIOCRService) ExtractFromImage(ctx context.Context, imageBytes []byte, imageType string) (*ReceiptExtractionResult, error) {
	startTime := time.Now()

	if o.apiKey == "" {
		o.logger.Warn("OpenAI API key not available, using mock extraction")
		return o.mockExtraction(), nil
	}

	// Use GPT-5.2 for best accuracy (same as ChatGPT interface)
	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2" // Most accurate model for OCR extraction
	}
	o.logger.Infof("🧠 OpenAI: Starting image extraction with model %s...", model)

	// Encode image to base64
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imageType, base64Image)

	// Create the extraction prompt
	prompt := o.createLiquorExtractionPrompt()

	// Build request with vision content
	content := []interface{}{
		openAITextContent{
			Type: "text",
			Text: prompt,
		},
		openAIImageContent{
			Type: "image_url",
			ImageURL: openAIImageURL{
				URL:    imageDataURL,
				Detail: "high", // High detail for accurate OCR
			},
		},
	}

	request := openAIRequest{
		Model: model,
		Messages: []openAIMessage{
			{
				Role:    "user",
				Content: content,
			},
		},
		MaxCompletionTokens: 8192,
		Temperature:         0.0,
		ResponseFormat:      &openAIResponseFmt{Type: "json_object"}, // Force JSON output
	}

	// Make API request
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+o.apiKey)

	o.logger.Debugf("OpenAI: Sending request to GPT-4o Vision API...")

	resp, err := o.httpClient.Do(req)
	if err != nil {
		o.logger.Errorf("OpenAI API request failed: %v", err)
		return nil, fmt.Errorf("openai request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		o.logger.Errorf("OpenAI API error: %s - %s", resp.Status, string(body))
		return nil, fmt.Errorf("openai api error: %s", resp.Status)
	}

	// Parse response
	var apiResp openAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.Error != nil {
		o.logger.Errorf("OpenAI API error: %s", apiResp.Error.Message)
		return nil, fmt.Errorf("openai api error: %s", apiResp.Error.Message)
	}

	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from OpenAI")
	}

	responseText := apiResp.Choices[0].Message.Content
	o.logger.Debugf("OpenAI: Received response with %d tokens", apiResp.Usage.TotalTokens)

	// Extract JSON from response (handle markdown code blocks)
	jsonText := o.extractJSONFromResponse(responseText)

	// Parse JSON response
	var extractedData struct {
		Items          []ExtractedReceiptItem `json:"items"`
		ReceiptNumber  *string                `json:"receipt_number"`
		ReceiptDate    *string                `json:"receipt_date"`
		VendorName     *string                `json:"vendor_name"`
		ShopName       *string                `json:"shop_name"`
		PageSize       *string                `json:"page_size"`
		PageSizeML     int                    `json:"page_size_ml"`
		TotalAmount    *float64               `json:"total_amount"`
		RawText        string                 `json:"raw_text"`
		RowCountOnPage int                    `json:"row_count_on_page"` // v1.0.131
	}

	if err := json.Unmarshal([]byte(jsonText), &extractedData); err != nil {
		o.logger.Errorf("Failed to parse OpenAI response: %v", err)
		o.logger.Debugf("Raw response: %s", responseText)
		return nil, fmt.Errorf("failed to parse extraction: %w", err)
	}

	// Apply page size to all items if detected from header
	if extractedData.PageSizeML > 0 {
		o.logger.Infof("📐 Page size detected from header: %s (%d ML)",
			safeString(extractedData.PageSize), extractedData.PageSizeML)
		for i := range extractedData.Items {
			if extractedData.Items[i].SizeML == 0 {
				extractedData.Items[i].SizeML = extractedData.PageSizeML
			}
			if extractedData.Items[i].SizeText == "" && extractedData.PageSize != nil {
				extractedData.Items[i].SizeText = *extractedData.PageSize
			}
		}
	}

	// Validate and normalize extracted data
	validItems := o.validateAndNormalizeItems(extractedData.Items)

	processingTime := int(time.Since(startTime).Milliseconds())

	// Use ShopName if VendorName is not set
	vendorName := extractedData.VendorName
	if vendorName == nil || *vendorName == "" {
		vendorName = extractedData.ShopName
	}

	result := &ReceiptExtractionResult{
		Items:          validItems,
		ReceiptNumber:  extractedData.ReceiptNumber,
		ReceiptDate:    extractedData.ReceiptDate,
		VendorName:     vendorName,
		ShopName:       extractedData.ShopName,
		PageSize:       extractedData.PageSize,
		PageSizeML:     extractedData.PageSizeML,
		TotalAmount:    extractedData.TotalAmount,
		ProcessingTime: processingTime,
		RawText:        extractedData.RawText,
		RowCountOnPage: extractedData.RowCountOnPage,
	}

	// Log shop name and page size if detected
	o.logger.Infof("✅ OpenAI extracted: Shop='%s', Size='%s' (%dML), %d items (%d valid), row_count_on_page=%d in %dms",
		safeString(extractedData.ShopName), safeString(extractedData.PageSize), extractedData.PageSizeML,
		len(extractedData.Items), len(validItems), extractedData.RowCountOnPage, processingTime)
	return result, nil
}

// ExtractRecoveryPass re-extracts an image with a completeness-focused prompt
// when the main pass returned fewer rows than the register appears to contain.
// This is the "D" improvement from the accuracy-pattern memory: rather than
// silently shipping an incomplete result, we issue one extra API call that
// explicitly tells the model it missed rows, with hints about WHERE the misses
// typically happen (trailing rows, handwritten additions).
//
// Cost: ~1 extra API call per image with suspected gaps. In practice this is
// only ~20-40% of images (the ones that the per-page validator flagged), so
// net inference cost usually rises by 30-40% while completeness jumps
// significantly on the hardest pages.
//
// mainPassRows is what we already have from the first call; maxRowSeen is the
// highest in-page row_number the AI returned. The prompt uses both to frame
// "I saw X items but the page has ~Y, find the gap".
func (o *OpenAIOCRService) ExtractRecoveryPass(
	ctx context.Context,
	imageBytes []byte,
	imageType string,
	productNames []string,
	mainPassRows int,
	maxRowSeen int,
) (*ReceiptExtractionResult, error) {
	startTime := time.Now()
	if o.apiKey == "" {
		return nil, fmt.Errorf("openai recovery requires API key")
	}
	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imageType, base64Image)

	// Stash product names briefly so the base prompt's KNOWN PRODUCTS section
	// renders — same trick as ExtractFromImageWithProducts.
	prevProducts := o.productNames
	o.productNames = productNames
	defer func() { o.productNames = prevProducts }()
	basePrompt := o.createLiquorExtractionPrompt()

	// Recovery preamble + explicit gap-closing directive. Placed at the TOP
	// so the model's attention weights it highest. GPT-5.2 responds well to
	// specific counts ("you returned 23 but should have ~30") over vague
	// "be thorough" — the concreteness forces a re-scan.
	recoveryPreamble := fmt.Sprintf(`!! SECOND-PASS RECOVERY EXTRACTION — CRITICAL !!

A first extraction pass on this image returned only %d items. The highest serial number the first pass reported was %d, meaning the page should have approximately %d items. We are missing roughly %d rows.

YOUR JOB: Find the MISSED rows. Pay MAXIMUM attention to:
1. The LAST 10-15 rows of the table — AI models truncate trailing rows most often.
2. HANDWRITTEN additions below the pre-printed list (rows numbered 40+ by hand).
3. Rows with blank/empty Sale cells — these were likely skipped as "no data" but they're real products.
4. Rows with faint, smudged, or sideways-written brand names.
5. Rows in the Brand column that wrap across two visual lines.

Return ALL items on the page (including ones the first pass caught — the server will merge and dedupe by row_number). Target: approximately %d items.

Use row_number = in-page position (1, 2, 3, ...) matching the printed S.No on the register. Do NOT use a separate sequence; anchor to the printed serial so we can align with the first pass's rows.

All the original extraction rules below still apply. Read them carefully.

---

%s`, mainPassRows, maxRowSeen, maxRowSeen, maxRowSeen-mainPassRows, maxRowSeen, basePrompt)

	content := []interface{}{
		openAITextContent{Type: "text", Text: recoveryPreamble},
		openAIImageContent{Type: "image_url", ImageURL: openAIImageURL{URL: imageDataURL, Detail: "high"}},
	}
	request := openAIRequest{
		Model:    model,
		Messages: []openAIMessage{{Role: "user", Content: content}},
		// Recovery typically returns the full page (not just missed rows) so
		// keep token budget at main-pass level.
		MaxCompletionTokens: 8192,
		Temperature:         0.0,
		ResponseFormat:      &openAIResponseFmt{Type: "json_object"},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal recovery request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("create recovery request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+o.apiKey)
	o.logger.Infof("🔁 OpenAI recovery-pass → %s (main_pass=%d rows, expected≈%d)", model, mainPassRows, maxRowSeen)
	resp, err := o.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai recovery request: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read recovery response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai recovery api error %d: %s", resp.StatusCode, string(body))
	}
	var apiResp openAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("parse recovery response: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("openai recovery error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from openai recovery")
	}
	jsonText := o.extractJSONFromResponse(apiResp.Choices[0].Message.Content)
	var extractedData struct {
		Items         []ExtractedReceiptItem `json:"items"`
		ReceiptNumber *string                `json:"receipt_number"`
		ReceiptDate   *string                `json:"receipt_date"`
		VendorName    *string                `json:"vendor_name"`
		ShopName      *string                `json:"shop_name"`
		PageSize      *string                `json:"page_size"`
		PageSizeML    int                    `json:"page_size_ml"`
		TotalAmount   *float64               `json:"total_amount"`
		RawText       string                 `json:"raw_text"`
	}
	if err := json.Unmarshal([]byte(jsonText), &extractedData); err != nil {
		return nil, fmt.Errorf("parse recovery extraction: %w", err)
	}
	// Apply page-size fallback, same as main extraction.
	if extractedData.PageSizeML > 0 {
		for i := range extractedData.Items {
			if extractedData.Items[i].SizeML == 0 {
				extractedData.Items[i].SizeML = extractedData.PageSizeML
			}
			if extractedData.Items[i].SizeText == "" && extractedData.PageSize != nil {
				extractedData.Items[i].SizeText = *extractedData.PageSize
			}
		}
	}
	validItems := o.validateAndNormalizeItems(extractedData.Items)
	processingTime := int(time.Since(startTime).Milliseconds())
	o.logger.Infof("✅ OpenAI recovery extracted %d items (main pass had %d) in %dms",
		len(validItems), mainPassRows, processingTime)
	return &ReceiptExtractionResult{
		Items:          validItems,
		ReceiptNumber:  extractedData.ReceiptNumber,
		ReceiptDate:    extractedData.ReceiptDate,
		VendorName:     extractedData.VendorName,
		ShopName:       extractedData.ShopName,
		PageSize:       extractedData.PageSize,
		PageSizeML:     extractedData.PageSizeML,
		TotalAmount:    extractedData.TotalAmount,
		ProcessingTime: processingTime,
		RawText:        extractedData.RawText,
	}, nil
}

// ExtractHandwrittenBand re-extracts a specific row range with a handwriting-
// specialized prompt. Used by smart_sale_service.go's page-rescue gate (v1.0.131)
// when the main pass + voting + recovery returned < 70% of the AI-reported
// RowCountOnPage. PARITY: smart_stock_setup_ocr.go's ExtractHandwrittenBand,
// adapted for Smart Sale columns (Sale instead of just Closing).
//
// fromRow/toRow are inclusive 1-indexed. Result rows outside the requested
// range are filtered server-side as a defense against models that ignore the
// scope instruction.
func (o *OpenAIOCRService) ExtractHandwrittenBand(
	ctx context.Context,
	imageBytes []byte,
	imageType string,
	productNames []string,
	fromRow, toRow int,
) (*ReceiptExtractionResult, error) {
	startTime := time.Now()
	if o.apiKey == "" {
		return nil, fmt.Errorf("openai handwritten-band requires API key")
	}
	if toRow < fromRow {
		return nil, fmt.Errorf("invalid range fromRow=%d toRow=%d", fromRow, toRow)
	}
	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imageType, base64Image)

	prevProducts := o.productNames
	o.productNames = productNames
	defer func() { o.productNames = prevProducts }()
	basePrompt := o.createLiquorExtractionPrompt()

	bandPreamble := fmt.Sprintf(`!! HANDWRITTEN-BAND PASS — CRITICAL !!

The page has rows numbered %d through %d. The main extraction pass MISSED a significant portion of these rows. Re-extract this page focusing on COMPLETENESS over speed.

ROW-LINE ANCHORING (CRITICAL):
- Walk the page TOP-TO-BOTTOM. For each numbered row line you can see — including ones with faint, smudged, partially-blank, or all-zero cells — emit one item.
- The S.No column is your anchor: rows are numbered %d, %d+1, ..., %d. Do not skip any.
- Set row_number to the in-page S.No exactly as printed/written. Do NOT renumber.
- If the brand cell is blank but the row has any other content (Opening, Sale, Rate, Amount), still emit the row with brand="" and raw_text capturing whatever you can read.
- ZERO-QTY ROWS ARE VALID: emit them with quantity=0. The server keeps them through the pipeline.

HANDWRITING-WINS RULE:
- If a row has BOTH printed text and handwritten text (overwrite, strike-through, or beside), the HANDWRITTEN string is the actual brand.
- Common handwritten abbreviations: 8PM, BP, RS (Royal Stag), MCD, JW, M2/MM (Magic Moments + flavor), VOV (Old Monk), B7. For M2/MM rows the FOLLOWING WORD is the flavor — keep it.

RANGE SCOPE:
- Return ONLY items with row_number in the inclusive range [%d, %d]. Do NOT return rows outside this range.
- Set row_count_on_page to %d.

All the original extraction rules below still apply. Read them carefully.

---

%s`, fromRow, toRow, fromRow, fromRow, toRow, fromRow, toRow, toRow-fromRow+1, basePrompt)

	content := []interface{}{
		openAITextContent{Type: "text", Text: bandPreamble},
		openAIImageContent{Type: "image_url", ImageURL: openAIImageURL{URL: imageDataURL, Detail: "high"}},
	}
	request := openAIRequest{
		Model:               model,
		Messages:            []openAIMessage{{Role: "user", Content: content}},
		MaxCompletionTokens: 8192,
		Temperature:         0.15,
		ResponseFormat:      &openAIResponseFmt{Type: "json_object"},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal handwritten-band request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("create handwritten-band request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+o.apiKey)
	o.logger.Infof("✍️  OpenAI handwritten-band → %s (rows [%d, %d])", model, fromRow, toRow)
	resp, err := o.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai handwritten-band request: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read handwritten-band response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai handwritten-band api error %d: %s", resp.StatusCode, string(body))
	}
	var apiResp openAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("parse handwritten-band response: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("openai handwritten-band error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from openai handwritten-band")
	}
	jsonText := o.extractJSONFromResponse(apiResp.Choices[0].Message.Content)
	var extractedData struct {
		Items          []ExtractedReceiptItem `json:"items"`
		PageSize       *string                `json:"page_size"`
		PageSizeML     int                    `json:"page_size_ml"`
		RowCountOnPage int                    `json:"row_count_on_page"`
	}
	if err := json.Unmarshal([]byte(jsonText), &extractedData); err != nil {
		return nil, fmt.Errorf("parse handwritten-band extraction: %w", err)
	}
	if extractedData.PageSizeML > 0 {
		for i := range extractedData.Items {
			if extractedData.Items[i].SizeML == 0 {
				extractedData.Items[i].SizeML = extractedData.PageSizeML
			}
			if extractedData.Items[i].SizeText == "" && extractedData.PageSize != nil {
				extractedData.Items[i].SizeText = *extractedData.PageSize
			}
		}
	}
	// Server-side range filter
	filtered := make([]ExtractedReceiptItem, 0, len(extractedData.Items))
	for _, it := range extractedData.Items {
		if it.RowNumber >= fromRow && it.RowNumber <= toRow {
			filtered = append(filtered, it)
		}
	}
	if len(filtered) != len(extractedData.Items) {
		o.logger.Infof("OpenAI handwritten-band filtered %d out-of-range rows (kept %d in [%d, %d])",
			len(extractedData.Items)-len(filtered), len(filtered), fromRow, toRow)
	}
	validItems := o.validateAndNormalizeItems(filtered)
	processingTime := int(time.Since(startTime).Milliseconds())
	o.logger.Infof("✅ OpenAI handwritten-band returned %d items for rows [%d, %d] in %dms",
		len(validItems), fromRow, toRow, processingTime)
	return &ReceiptExtractionResult{
		Items:          validItems,
		PageSize:       extractedData.PageSize,
		PageSizeML:     extractedData.PageSizeML,
		RowCountOnPage: extractedData.RowCountOnPage,
		ProcessingTime: processingTime,
	}, nil
}

// extractJSONFromResponse extracts JSON from markdown code blocks or raw text
func (o *OpenAIOCRService) extractJSONFromResponse(response string) string {
	// Try to find JSON in code block
	if idx := strings.Index(response, "```json"); idx != -1 {
		start := idx + 7
		if end := strings.Index(response[start:], "```"); end != -1 {
			return strings.TrimSpace(response[start : start+end])
		}
	}

	// Try plain code block
	if idx := strings.Index(response, "```"); idx != -1 {
		start := idx + 3
		// Skip language identifier if present
		if newline := strings.Index(response[start:], "\n"); newline != -1 {
			start = start + newline + 1
		}
		if end := strings.Index(response[start:], "```"); end != -1 {
			return strings.TrimSpace(response[start : start+end])
		}
	}

	// Try to find raw JSON object
	if idx := strings.Index(response, "{"); idx != -1 {
		depth := 0
		for i := idx; i < len(response); i++ {
			if response[i] == '{' {
				depth++
			} else if response[i] == '}' {
				depth--
				if depth == 0 {
					return response[idx : i+1]
				}
			}
		}
	}

	return response
}

// validateAndNormalizeItems validates and normalizes extracted items
func (o *OpenAIOCRService) validateAndNormalizeItems(items []ExtractedReceiptItem) []ExtractedReceiptItem {
	validItems := []ExtractedReceiptItem{}

	for i := range items {
		item := &items[i]

		// CRITICAL FIX: Detect when Opening was misread as Quantity
		// Daily sales are typically 0-30, if quantity > 50, it's likely wrong
		if item.Quantity > 50 && item.OpeningStock != nil && *item.OpeningStock < 50 {
			o.logger.Warnf("Row %d (%s): Quantity %d too high, Opening %d too low - likely swapped columns",
				item.RowNumber, item.Brand, item.Quantity, *item.OpeningStock)
			// Swap: the "quantity" is actually opening, and we need to find real quantity
			// Real quantity is likely in closing_stock or needs to be inferred
			actualOpening := item.Quantity
			item.OpeningStock = &actualOpening
			// Try to calculate quantity from price/rate if available
			if item.Price != nil && item.RatePerUnit != nil && *item.RatePerUnit > 0 {
				calculatedQty := int(*item.Price / *item.RatePerUnit)
				if calculatedQty > 0 && calculatedQty < 50 {
					item.Quantity = calculatedQty
					o.logger.Infof("Row %d (%s): Fixed - Opening=%d, Quantity=%d (from price/rate)",
						item.RowNumber, item.Brand, actualOpening, calculatedQty)
				}
			}
		}

		// Also check: if quantity > 50 and closing is negative, quantity is wrong
		if item.Quantity > 50 && item.ClosingStock != nil && *item.ClosingStock < 0 {
			o.logger.Warnf("Row %d (%s): Quantity %d causes negative closing %d - recalculating",
				item.RowNumber, item.Brand, item.Quantity, *item.ClosingStock)
			// Try to calculate quantity from price/rate
			if item.Price != nil && item.RatePerUnit != nil && *item.RatePerUnit > 0 {
				calculatedQty := int(*item.Price / *item.RatePerUnit)
				if calculatedQty > 0 && calculatedQty < 100 {
					item.Quantity = calculatedQty
					// Recalculate closing
					if item.OpeningStock != nil {
						newClosing := *item.OpeningStock - calculatedQty
						item.ClosingStock = &newClosing
					}
					o.logger.Infof("Row %d (%s): Fixed - Quantity=%d, Closing=%d",
						item.RowNumber, item.Brand, calculatedQty, *item.ClosingStock)
				}
			}
		}

		// Fix: If quantity == opening AND closing == opening, AI confused columns.
		// Mathematically: closing = opening - sale. If closing == opening → sale = 0.
		// This catches page 2 column confusion where AI puts Opening in all fields.
		if item.Quantity > 0 && item.OpeningStock != nil && item.ClosingStock != nil {
			if item.Quantity == *item.OpeningStock && *item.ClosingStock == *item.OpeningStock {
				o.logger.Warnf("Row %d (%s): quantity=%d equals opening=%d AND closing=%d — AI confused Opening with Sale column. Setting quantity=0",
					item.RowNumber, item.Brand, item.Quantity, *item.OpeningStock, *item.ClosingStock)
				item.Quantity = 0
				// Reset amount since it was calculated from wrong quantity
				if item.Price != nil {
					zero := 0.0
					item.Price = &zero
				}
			}
		}

		// Infer Sale = (Opening + Receipt) - Closing when AI returned quantity=0 but
		// stock dropped. Common when the Sale column ink is faded but Opening and
		// Closing are legible — happens on dense 750ml pages where the Sale column
		// is the smallest and the AI defaults to 0 rather than guess.
		// Caps: 50 mirrors the swap heuristic on line 514, base mirrors physical
		// reality (can't sell more than was on shelf). Confidence drop to ≤0.6
		// routes the row through flagItemsForReview in smart_sale_service.go so
		// the user confirms before the sale is saved.
		if item.Quantity == 0 && item.OpeningStock != nil && item.ClosingStock != nil {
			base := *item.OpeningStock
			if item.Receipt != nil {
				base += *item.Receipt
			}
			delta := base - *item.ClosingStock
			if delta > 0 && delta <= 50 && delta <= base {
				o.logger.Warnf("Row %d (%s): inferred quantity=%d from opening=%d closing=%d (Sale column unreadable)",
					item.RowNumber, item.Brand, delta, *item.OpeningStock, *item.ClosingStock)
				item.Quantity = delta
				if item.Confidence > 0.6 {
					item.Confidence = 0.6
				}
				if item.RatePerUnit != nil && item.Price == nil {
					p := float64(delta) * *item.RatePerUnit
					item.Price = &p
				}
			}
		}

		// Second-chance recovery: if Sale and Opening/Closing all failed but the AI
		// did read Amount and Rate, derive Sale = Amount / Rate. Common on rows
		// where the Sale digit is overwritten but the Amount column is in clearer
		// ink (shopkeeper double-checks money totals more carefully than counts).
		// Same 50-bottle cap and 0.6 confidence ceiling as the delta path so the
		// row still routes to the user for confirmation.
		if item.Quantity == 0 && item.Price != nil && item.RatePerUnit != nil &&
			*item.Price > 0 && *item.RatePerUnit > 0 {
			calc := *item.Price / *item.RatePerUnit
			if calc > 0.5 && calc < 50.5 {
				inferred := int(calc + 0.5) // round to nearest int
				// Only commit if amount is an exact integer multiple of rate (±₹1
				// rounding tolerance), otherwise the rate is probably wrong and
				// inferring would compound the error.
				if absFloat(*item.Price-(float64(inferred)*(*item.RatePerUnit))) <= 1.0 {
					o.logger.Warnf("Row %d (%s): inferred quantity=%d from amount=%.0f / rate=%.0f (Sale unreadable)",
						item.RowNumber, item.Brand, inferred, *item.Price, *item.RatePerUnit)
					item.Quantity = inferred
					if item.Confidence > 0.6 {
						item.Confidence = 0.6
					}
				}
			}
		}

		// Validate closing stock (must be < 10000 to avoid Amount confusion)
		if item.ClosingStock != nil && *item.ClosingStock > 10000 {
			o.logger.Warnf("Row %d (%s): Closing stock %d > 10000, likely Amount column - fixing",
				item.RowNumber, item.Brand, *item.ClosingStock)

			// Try to fix using opening stock - quantity
			if item.OpeningStock != nil && item.Quantity > 0 {
				calculated := *item.OpeningStock - item.Quantity
				if calculated >= 0 && calculated < 10000 {
					if item.Price == nil {
						price := float64(*item.ClosingStock)
						item.Price = &price
					}
					item.ClosingStock = &calculated
				} else {
					item.ClosingStock = nil
				}
			} else {
				item.ClosingStock = nil
			}
		}

		// Validate opening stock
		if item.OpeningStock != nil && *item.OpeningStock > 10000 {
			o.logger.Warnf("Row %d (%s): Opening stock %d > 10000, setting to nil",
				item.RowNumber, item.Brand, *item.OpeningStock)
			item.OpeningStock = nil
		}

		// Validate rate (must be 10-70000)
		if item.RatePerUnit != nil {
			rate := *item.RatePerUnit
			if rate > 70000 || rate < 10 {
				o.logger.Warnf("Row %d (%s): Rate %.2f invalid, setting to nil",
					item.RowNumber, item.Brand, rate)
				if rate > 70000 && item.Price == nil {
					item.Price = item.RatePerUnit
				}
				item.RatePerUnit = nil
			}
		}

		// Normalize size if needed
		if item.SizeML == 0 && item.SizeText != "" {
			ml, _ := o.sizeNormalizer.Normalize(item.SizeText, item.Category)
			item.SizeML = ml
		}

		// Detect category if empty
		if item.Category == "" {
			item.Category = o.sizeNormalizer.detectCategory(item.Brand)
		}

		// Calculate Total if missing (Total = Opening + Receipt)
		if item.Total == nil && item.OpeningStock != nil {
			receipt := 0
			if item.Receipt != nil {
				receipt = *item.Receipt
			}
			total := *item.OpeningStock + receipt
			item.Total = &total
		}

		// Calculate closing stock if missing: Closing = Total - Sale
		if item.ClosingStock == nil && item.Quantity >= 0 {
			var baseStock int
			if item.Total != nil {
				baseStock = *item.Total // Use Total (Opening + Receipt)
			} else if item.OpeningStock != nil {
				baseStock = *item.OpeningStock // Fallback to Opening
			}
			if baseStock > 0 {
				closing := baseStock - item.Quantity
				if closing >= 0 {
					item.ClosingStock = &closing
				}
			}
		}

		// Calculate price from rate if missing
		if item.Price == nil && item.RatePerUnit != nil && item.Quantity > 0 {
			price := *item.RatePerUnit * float64(item.Quantity)
			item.Price = &price
		}

		// Set confidence
		if item.Confidence == 0 {
			item.Confidence = o.calculateConfidence(item)
		}

		// Ensure raw_text is always populated (fallback to brand)
		if item.RawText == "" {
			item.RawText = item.Brand
		}

		validItems = append(validItems, *item)
	}

	return validItems
}

// createLiquorExtractionPrompt creates a specialized prompt for liquor receipt extraction
func (o *OpenAIOCRService) createLiquorExtractionPrompt() string {
	basePrompt := `You are extracting data from an Indian liquor shop stock register image.

FIRST: Look at the TOP/HEADER of the register page to find:
1. SHOP NAME - Usually at the very top (e.g., "XYZ Wine Shop", "ABC Liquor Store")
2. SIZE CATEGORY - Often shows bottle size for the page (e.g., "375 ML", "180ML", "750ML", "IMFL 375")

The register table has these columns from left to right:
1. S.No (Serial Number)
2. Brand Name
3. Opening (stock at start of day)
4. Receipt (new stock received - often 0)
5. Total (= Opening + Receipt)
6. Sale (quantity sold - this is the QUANTITY field)
7. Rate (price per unit in Rupees - MUST EXTRACT)
8. Amount (= Sale × Rate in Rupees - MUST EXTRACT)
9. Closing (= Total - Sale)

CRITICAL RULES FOR ACCURATE EXTRACTION:
1. ALWAYS extract shop_name from page header/title
2. ALWAYS extract page_size from header (bottle size for this page)
3. Closing = Total - Sale (NOT Opening - Sale)
4. If Receipt > 0, then Total = Opening + Receipt
5. If Receipt = 0, then Total = Opening
6. ALWAYS extract Rate (column 7) - price per bottle/unit
7. ALWAYS extract Amount (column 8) - Sale × Rate
8. Rate is typically between ₹50 and ₹5000 per unit

SALE COLUMN RULES (MOST IMPORTANT — READ CAREFULLY):
9. The Sale column (column 6) is the QUANTITY SOLD. It is the most important number to extract correctly.
10. In handwritten registers, the Sale column is BETWEEN the Total column (5) and Rate column (7). Look for the number in that specific position.
11. If the Sale column cell is EMPTY or has a dash (-), set quantity to 0. Many products have zero sales on a given day.
12. DO NOT confuse Opening (column 3) with Sale (column 6). They are separated by Receipt (4) and Total (5).
13. If only ONE number appears in a row's numeric columns, it is likely the Opening stock, NOT the sale. Set quantity=0.
14. MATHEMATICAL VERIFICATION: Closing = Total - Sale. If your extracted Closing equals Opening, then Sale MUST be 0.
15. For multi-page registers: page 2 has the SAME column layout as page 1. Do NOT shift columns between pages.
16. NEVER assume a product was sold if you cannot clearly read a number in the Sale column. Default to quantity=0 when uncertain — UNLESS rule 16a applies (Opening AND Closing are both clearly readable).
16a. SALE-COLUMN DELTA FALLBACK: If the Sale cell is blurry, smudged, partially obscured, or unreadable BUT the Opening and Closing cells are BOTH clearly legible, compute Sale = (Opening + Receipt) − Closing and use that as the quantity. Set confidence to 0.6 or lower and append " (inferred from delta)" to raw_text so the user can verify. This rule unlocks otherwise-lost rows on dense pages where the Sale column has the smallest digits. Only apply this rule when BOTH Opening and Closing are unambiguous; if either is also unclear, fall back to quantity=0 per rule 16.
17. Read the Amount cell INDEPENDENTLY. If the Amount cell is empty/illegible/faded, output price=0 (DO NOT back-fill price = Sale × Rate — that destroys a signal we use for cross-checking). The math relationship Amount = Sale × Rate is for VERIFICATION only, never substitution. A blank Amount cell does NOT mean Sale is 0; only the Sale cell decides quantity.

EXTRACTION COMPLETENESS (CRITICAL — read ALL these rules):
18. Extract EVERY row that has a brand name, even if all numeric columns are empty or zero.
19. Items with zero sales are VALID entries — they represent products in stock that weren't sold today. Include them with quantity=0.
20. Do NOT skip rows just because the Sale column is empty. Every product listed in the register must appear in the output.
21. Handwritten rows at the bottom (added by the shopkeeper) are equally important — extract them too.
22. **SERIAL-NUMBER ENUMERATION CHECK**: If the S.No column runs from 1 to N on this page, your output MUST contain approximately N items. If serial numbers go 1 to 38, output ~38 items. Before finalizing, count your extracted items against the highest serial number you saw — if short, re-scan the page for the missing rows.
23. **LAST-ROW EMPHASIS**: Pay EXTRA attention to the last 5-10 rows of the page. AI models often skip or truncate trailing rows. Rows 25, 26, 27, 28 and beyond on a densely-written page are the most frequently missed — extract them explicitly, in order, with their exact serial numbers.
24. **HANDWRITTEN ADDITIONS AT PAGE BOTTOM**: Many registers have handwritten additions BELOW the pre-printed rows (rows numbered 40, 41, 42, etc. by hand). These are NEW products added by the shopkeeper. Extract every one of them.
25. **ROW-NUMBER REPORTING**: Set the row_number field to the position of the row on THIS page starting from 1 (not the printed S.No, which might be garbled). Each page starts fresh at row_number=1. The server attaches the page identity separately — you only report the in-page row index.
26. **COMPLETENESS SELF-CHECK**: Before returning JSON, verify you have one item per row of the table. If you see a row with text in the Brand column that didn't get extracted, STOP and add it. A missing row is a critical failure.
26a. **ROW COUNT (NEW v1.0.131)**: At the top of the JSON output, set "row_count_on_page" to the count of every numbered row line you can see on this page — including blank rows, rows where you couldn't read the brand, and zero-qty rows. This MUST be >= len(items[]). If row_count_on_page > len(items[]), you missed rows and should rescan before returning. The server uses this as the rescue trigger threshold.
26b. **HONEST UNCERTAINTY (NEW v1.0.131)**: If your confidence on the brand cell is < 0.6, set brand = "" and put the raw handwritten string in raw_text rather than guessing. It is BETTER to surface uncertainty than to hallucinate a known brand we'll have to undo later. The downstream matcher can recover from a blank brand via raw_text + alias lookup; it cannot recover from a confidently wrong brand.

CRITICAL DATE HANDLING:
22. Dates on Indian liquor receipts are DD/MM/YY format (e.g., "8/4/26" = April 8, 2026, "15/3/26" = March 15, 2026).
23. The year "26" means 2026. NEVER output 2024, 2020, or any other year unless explicitly written in full.
24. Convert to YYYY-MM-DD format in receipt_date output (e.g., "8/4/26" -> "2026-04-08").

CRITICAL BRAND NAME HANDLING:
25. Each row is ONE product. Never merge text from multiple rows into a single brand name.
26. "Smirhoof", "SMIRnoof", or similar scribbles in the Amount column are shopkeeper notes, NOT part of the brand name. Ignore text that appears outside the Brand Name column.
27. "Stop" or "X" annotations NEXT TO or ACROSS a product row (often in red/different ink, in margins) mean the product is stopped/banned — set quantity to 0 for that row, but still extract the brand name. But if the shopkeeper has written a REPLACEMENT product name in the brand column (not just "Stop"), extract the replacement name.
28. Handwritten additions at bottom (rows 40+) are separate products NOT on the pre-printed list — extract them as individual rows.
29. Common handwritten abbreviations: "MCD" = McDowell's, "BP" = Blenders Pride, "RS" = Royal Stag, "VOV" = Old Monk, "JW" = Johnnie Walker, "8PM" = 8 PM.

HANDWRITTEN OVERRIDES:
30. In Indian excise registers, pre-printed product names may be CROSSED OUT, OVERWRITTEN, or have a DIFFERENT handwritten product name written next to them. When this happens, the HANDWRITTEN text is the actual product — use it as the brand name. The shopkeeper is indicating they sold a different product in that row. Set raw_text to the handwritten text.
31. Signs of override: strikethrough on printed text, different ink color for brand name, handwritten text clearly replacing/beside the printed name. When in doubt, prefer the handwritten text.

COLUMN PARSING:
32. The "Sale" column has the actual quantity sold. "Opening", "Receipt", "Total" are inventory tracking columns.
33. If Sale column is blank or dash, quantity = 0 (no sale that day).
34. Read the Amount cell directly from the image. If illegible, return 0 — never compute it from Sale × Rate. Cross-validation between Sale × Rate and the read Amount can flag misreads but should NOT replace a blank Amount with a synthesized value.

Extract ALL rows and return as JSON:

{
  "shop_name": "Shop Name from Header",
  "page_size": "375ML",
  "page_size_ml": 375,
  "row_count_on_page": 28,
  "items": [
    {
      "row_number": 1,
      "brand": "Royal Stag Superior Whisky",
      "raw_text": "Royl Stag",
      "category": "whiskey",
      "subcategory": "normal",
      "size_text": "375ml",
      "size_ml": 375,
      "opening_stock": 50,
      "receipt": 0,
      "total": 50,
      "quantity": 5,
      "rate_per_unit": 280.00,
      "price": 1400.00,
      "closing_stock": 45,
      "confidence": 0.95
    }
  ],
  "receipt_date": null,
  "total_amount": null
}

Field mapping:
- shop_name = Shop/store name from register header
- page_size = Bottle size category from header (375ML, 180ML, 750ML, etc.)
- page_size_ml = Size in milliliters (375, 180, 750, etc.)
- raw_text = EXACTLY what is handwritten/printed in the register — copy character by character, including abbreviations, misspellings, shorthand. Do NOT correct, normalize, or expand this field. This is critical for learning.
- brand = MUST be the EXACT product name from the KNOWN PRODUCTS list (if provided and matched). Do NOT modify the product name. If no confident match, set brand = raw_text.
- rate_per_unit = Rate column (column 7) - price per bottle
- price = Amount column (column 8) - total for that row (Sale × Rate)

Categories: whiskey, rum, vodka, beer, brandy, gin, wine
Sizes: 90ml, 180ml, 375ml, 750ml

Return only valid JSON, no markdown.`

	// Inject product list if available (product-aware mode)
	if len(o.productNames) > 0 {
		productSection := "\n\nKNOWN PRODUCTS IN THIS SHOP'S INVENTORY (THIS IS THE COMPLETE LIST — NO OTHER PRODUCTS EXIST):\n"
		productSection += "ABSOLUTE RULE: The 'brand' field MUST be one of these EXACT product names, or the raw_text if no match. NEVER use any brand name not in this list. NEVER hallucinate or guess brand names from your training data.\n"
		productSection += "ALWAYS set 'raw_text' to the EXACT handwritten text you see in the register, even if you matched it to a known product.\n"
		for i, name := range o.productNames {
			productSection += fmt.Sprintf("%d. %s\n", i+1, name)
		}
		productSection += "\nMATCHING RULES:\n"
		productSection += "- Handwritten registers use abbreviations and shorthand.\n"

		// Generate dynamic abbreviation hints from product names
		// Extract initials and common short forms automatically
		productSection += "- Likely abbreviations for these products:\n"
		for _, name := range o.productNames {
			words := strings.Fields(name)
			if len(words) >= 2 {
				// Generate initials (e.g., "Royal Stag Whisky" -> "RS", "RSW")
				initials2 := ""
				initials3 := ""
				for j, w := range words {
					if j < 2 {
						initials2 += strings.ToUpper(w[:1])
					}
					if j < 3 {
						initials3 += strings.ToUpper(w[:1])
					}
				}
				// Also generate first-word shorthand
				productSection += fmt.Sprintf("  '%s' or '%s' or '%s' = \"%s\"\n", initials2, initials3, words[0], name)
			}
		}

		productSection += "- ABSOLUTE: The 'brand' field MUST be COPIED EXACTLY from the product list above (character for character). Do NOT use any other brand name.\n"
		productSection += "- If register says 'BP Blue', 'B.P Blue', or any abbreviation containing 'Blue' — match to the product with 'Blue' in its name\n"
		productSection += "- If register says 'BP', 'BP Premium', 'BPP' — match to the product with 'Premium' in its name\n"
		productSection += "- ALWAYS set 'raw_text' to the EXACT handwritten text from the register image — do NOT clean, correct, or normalize\n"
		productSection += "- If unsure, set 'brand' to the raw_text value (do NOT guess brands from your training data like 'Imperial Blue', 'McDowell's', etc.)\n"
		productSection += "- DISTINGUISHING WORDS are critical: 'Blue', 'Premium', 'Reserve', 'Gold', 'Silver', 'Black' determine which variant to match\n"
		return basePrompt + productSection
	}

	return basePrompt
}

// calculateConfidence calculates confidence score based on data completeness
func (o *OpenAIOCRService) calculateConfidence(item *ExtractedReceiptItem) float64 {
	confidence := 0.5

	if item.Brand != "" && len(item.Brand) > 2 {
		confidence += 0.15
	}
	if item.SizeML > 0 {
		confidence += 0.15
	}
	if item.Category != "" {
		confidence += 0.1
	}
	if item.Quantity > 0 && item.Quantity < 100 {
		confidence += 0.1
	}
	if item.RatePerUnit != nil && *item.RatePerUnit > 0 {
		confidence += 0.05
	}
	if item.OpeningStock != nil && item.ClosingStock != nil {
		confidence += 0.05
	}
	if item.RowNumber > 0 {
		confidence += 0.05
	}

	if confidence > 1.0 {
		confidence = 1.0
	}
	return confidence
}

// safeString returns the string value or empty string if nil
func safeString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// mockExtraction returns mock data when API is unavailable
func (o *OpenAIOCRService) mockExtraction() *ReceiptExtractionResult {
	o.logger.Info("Using mock OpenAI extraction (demo mode)")

	price1 := 1700.0
	rate1 := 850.0
	opening1 := 10
	closing1 := 8
	total := 1700.0
	receiptNum := "MOCK-12345"

	return &ReceiptExtractionResult{
		Items: []ExtractedReceiptItem{
			{
				Brand:        "Royal Stag",
				Category:     "whiskey",
				SizeText:     "750ml",
				SizeML:       750,
				Quantity:     2,
				Price:        &price1,
				RatePerUnit:  &rate1,
				OpeningStock: &opening1,
				ClosingStock: &closing1,
				RowNumber:    1,
				Confidence:   0.95,
			},
		},
		ReceiptNumber:  &receiptNum,
		TotalAmount:    &total,
		ProcessingTime: 500,
		RawText:        "Mock extraction - OpenAI API key not configured",
	}
}

// Close closes any resources (no-op for HTTP client)
func (o *OpenAIOCRService) Close() error {
	return nil
}
