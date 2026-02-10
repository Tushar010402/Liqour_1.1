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
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/liquorpro/go-backend/internal/sales/models"
)

// OpenAIVisionClient handles GPT-4o Vision API calls for receipt OCR
type OpenAIVisionClient struct {
	apiKey     string
	httpClient *http.Client
	model      string
	maxRetries int
}

// OpenAIRequest represents the request structure for GPT-4o Vision API
type OpenAIRequest struct {
	Model       string          `json:"model"`
	Messages    []OpenAIMessage `json:"messages"`
	MaxTokens   int             `json:"max_tokens"`
	Temperature float64         `json:"temperature"`
}

// OpenAIMessage represents a message in the conversation
type OpenAIMessage struct {
	Role    string           `json:"role"`
	Content []OpenAIContent  `json:"content"`
}

// OpenAIContent represents content in a message (text or image)
type OpenAIContent struct {
	Type     string            `json:"type"`
	Text     string            `json:"text,omitempty"`
	ImageURL *OpenAIImageURL   `json:"image_url,omitempty"`
}

// OpenAIImageURL represents an image URL in the content
type OpenAIImageURL struct {
	URL    string `json:"url"`
	Detail string `json:"detail,omitempty"` // "low", "high", or "auto"
}

// OpenAIResponse represents the response from GPT-4o Vision API
type OpenAIResponse struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index   int `json:"index"`
		Message struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage struct {
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

// FlexibleString handles JSON fields that may be string or number
type FlexibleString string

// UnmarshalJSON implements custom unmarshaling for FlexibleString
func (fs *FlexibleString) UnmarshalJSON(data []byte) error {
	// Try string first
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*fs = FlexibleString(s)
		return nil
	}

	// Try number (int or float)
	var f float64
	if err := json.Unmarshal(data, &f); err == nil {
		// Convert number to string, append "ml" for sizes
		if f == float64(int(f)) {
			*fs = FlexibleString(fmt.Sprintf("%d", int(f)))
		} else {
			*fs = FlexibleString(fmt.Sprintf("%.1f", f))
		}
		return nil
	}

	// If both fail, treat as empty string
	*fs = ""
	return nil
}

// String returns the string value
func (fs FlexibleString) String() string {
	return string(fs)
}

// ExtractedSalesRow represents a single row extracted from the receipt
type ExtractedSalesRow struct {
	RowNumber    int            `json:"row_number"`
	BrandName    string         `json:"brand_name"`
	Size         FlexibleString `json:"size"`
	OpeningStock int            `json:"opening_stock"`
	Receipt      int            `json:"receipt"`
	TotalStock   int            `json:"total_stock"`
	SaleQty      int            `json:"sale_qty"`
	Rate         float64        `json:"rate"`
	Amount       float64        `json:"amount"`
	ClosingStock int            `json:"closing_stock"`
	Confidence   float64        `json:"confidence"`
	Notes        string         `json:"notes,omitempty"`
}

// ExtractionResult represents the complete extraction result
type ExtractionResult struct {
	ReceiptType    string              `json:"receipt_type"`
	ReceiptDate    string              `json:"receipt_date"`
	ShopName       string              `json:"shop_name"`
	Items          []ExtractedSalesRow `json:"items"`
	TotalItems     int                 `json:"total_items"`
	TotalAmount    float64             `json:"total_amount"`
	ExtractionTime time.Duration       `json:"extraction_time"`
	ModelUsed      string              `json:"model_used"`
	Warnings       []string            `json:"warnings,omitempty"`
}

// NewOpenAIVisionClient creates a new OpenAI Vision client
func NewOpenAIVisionClient() (*OpenAIVisionClient, error) {
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY environment variable not set")
	}

	return &OpenAIVisionClient{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 120 * time.Second, // 2 minute timeout for vision processing
		},
		model:      "gpt-4o-2024-11-20", // Latest GPT-4o model with vision support
		maxRetries: 3,
	}, nil
}

// ExtractSalesFromImage extracts sales data from a receipt image
func (c *OpenAIVisionClient) ExtractSalesFromImage(ctx context.Context, imageData []byte, imageURL string) (*ExtractionResult, error) {
	startTime := time.Now()

	fmt.Printf("🤖 [OpenAI Vision] Starting extraction with GPT-4o...\n")

	// Prepare image content
	var imageContent OpenAIContent
	if len(imageData) > 0 {
		// Use base64 encoded image
		base64Image := base64.StdEncoding.EncodeToString(imageData)
		mimeType := detectMimeType(imageData)
		imageContent = OpenAIContent{
			Type: "image_url",
			ImageURL: &OpenAIImageURL{
				URL:    fmt.Sprintf("data:%s;base64,%s", mimeType, base64Image),
				Detail: "high", // High detail for accurate text extraction
			},
		}
		fmt.Printf("📸 [OpenAI Vision] Using base64 image (%d bytes, %s)\n", len(imageData), mimeType)
	} else if imageURL != "" {
		imageContent = OpenAIContent{
			Type: "image_url",
			ImageURL: &OpenAIImageURL{
				URL:    imageURL,
				Detail: "high",
			},
		}
		fmt.Printf("🔗 [OpenAI Vision] Using image URL: %s\n", truncateString(imageURL, 50))
	} else {
		return nil, fmt.Errorf("no image data or URL provided")
	}

	// Create the extraction prompt
	prompt := c.buildExtractionPrompt()

	// Build the request with increased token limit for large receipts
	// 16384 tokens supports 40+ items with full JSON structure
	request := OpenAIRequest{
		Model: c.model,
		Messages: []OpenAIMessage{
			{
				Role: "user",
				Content: []OpenAIContent{
					{
						Type: "text",
						Text: prompt,
					},
					imageContent,
				},
			},
		},
		MaxTokens:   16384, // GPT-4o maximum: 16384 completion tokens (sufficient for 40+ items)
		Temperature: 0.1,   // Low temperature for consistent, accurate extraction
	}

	// Make the API call with retries
	var response *OpenAIResponse
	var err error
	for attempt := 1; attempt <= c.maxRetries; attempt++ {
		response, err = c.makeAPICall(ctx, request)
		if err == nil {
			break
		}
		fmt.Printf("⚠️  [OpenAI Vision] Attempt %d failed: %v\n", attempt, err)
		if attempt < c.maxRetries {
			time.Sleep(time.Duration(attempt) * 2 * time.Second) // Exponential backoff
		}
	}
	if err != nil {
		return nil, fmt.Errorf("OpenAI API call failed after %d attempts: %w", c.maxRetries, err)
	}

	// Parse the response
	result, err := c.parseExtractionResponse(response)
	if err != nil {
		return nil, fmt.Errorf("failed to parse extraction response: %w", err)
	}

	result.ExtractionTime = time.Since(startTime)
	result.ModelUsed = c.model

	fmt.Printf("✅ [OpenAI Vision] Extracted %d items in %v\n", len(result.Items), result.ExtractionTime)

	return result, nil
}

// buildExtractionPrompt creates the prompt for GPT-4o to extract sales data
// This prompt is optimized for single receipts (after image splitting)
func (c *OpenAIVisionClient) buildExtractionPrompt() string {
	return c.buildSingleReceiptPrompt()
}

// buildSingleReceiptPrompt creates a focused prompt for single receipt extraction
// Used after image splitting - simpler, more accurate, lower token usage
func (c *OpenAIVisionClient) buildSingleReceiptPrompt() string {
	return `Extract ALL items from this Indian liquor sales receipt (handwritten register).

RECEIPT FORMAT: Look for "SALE RECEIPT - XXXml" header to determine size (90ml, 180ml, 375ml, 750ml)
DATE: Extract receipt date from top right (format: DD/MM/YY or DD/M/YY)

COLUMNS (left to right): S.No | Brand Name | Opening | Receipt | Total | Sale | Rate | Amount | Closing

CRITICAL MATH VALIDATION:
- Opening - Sale = Closing (OR Opening + Receipt - Sale = Closing if Receipt exists)
- If your extracted Closing ≠ calculated Closing, RE-READ the numbers
- Amount = Sale × Rate (verify this)

NUMBER READING TIPS (handwritten):
- "1" vs "7": 1 has no horizontal stroke at top, 7 does
- "17" looks like "17" not "7" - look for the "1" before
- "0" vs "6": 0 is round, 6 has a tail
- Dash "-" in a cell means 0 or blank
- If a number looks wrong, use math to verify

COMMON BRANDS: 8 PM (Black/Gold/Rare), Imperial Blue (IB), Royal Stag (RS), Old Monk (OM), Magic Moments (MM), Blenders Pride (BP/BPR), Officers Choice (OC), McDowells (MCD), After Dark, Bacardi, Kingfisher

OUTPUT JSON:
{
  "receipt_type": "90ML/180ML/375ML/750ML",
  "receipt_date": "DD/MM/YYYY",
  "items": [
    {
      "row_number": 1,
      "brand_name": "8 PM Black Whisky",
      "size": "90ml",
      "opening_stock": 30,
      "receipt": 0,
      "total_stock": 30,
      "sale_qty": 22,
      "rate": 90.00,
      "amount": 1980.00,
      "closing_stock": 8,
      "math_check": "30-22=8 ✓",
      "confidence": 95.0
    }
  ],
  "total_items": 27,
  "total_amount": 32500.00,
  "grand_total_from_receipt": 32500.00,
  "warnings": ["List any rows where math doesn't add up"]
}

Extract ALL items with careful number reading:`
}

// buildMultiReceiptPrompt creates prompt for images that may contain multiple receipts
// Used when image splitting is not possible or as fallback
func (c *OpenAIVisionClient) buildMultiReceiptPrompt() string {
	return `Extract ALL items from this Indian liquor sales receipt image (handwritten register).

⚠️ CHECK FIRST: Does this image contain MULTIPLE receipt pages SIDE-BY-SIDE?
If yes: Extract from BOTH receipts completely (LEFT first, then RIGHT)

RECEIPT FORMAT: Look for "SALE RECEIPT - XXXml" header to determine size
DATE: Extract receipt date from top right corner (format: DD/MM/YY)

COLUMNS (left to right): S.No | Brand Name | Opening | Receipt | Total | Sale | Rate | Amount | Closing

CRITICAL MATH VALIDATION:
- Opening - Sale = Closing (OR Opening + Receipt - Sale = Closing)
- If extracted Closing ≠ calculated Closing, RE-READ the numbers
- Amount = Sale × Rate

NUMBER READING TIPS (handwritten):
- "1" vs "7": 1 has no horizontal stroke at top, 7 does
- "17" looks like "17" not "7" - look for the "1" before
- "0" vs "6": 0 is round, 6 has a tail
- Dash "-" means 0 or blank

RULES:
1. Extract EVERY row - if 2 receipts, expect 35-45 items total
2. For side-by-side: LEFT receipt rows 1-27, then RIGHT receipt continues
3. Rate = price per bottle (₹80-400 for 180ml, ₹300-900 for 375ml, ₹500-2000 for 750ml)
4. Amount = Sale × Rate (use to verify rate)
5. If total_amount is HALF the grand_total, you missed half the items!

OUTPUT JSON:
{
  "receipt_type": "90ML/180ML/375ML/750ML",
  "receipt_date": "DD/MM/YYYY",
  "receipt_count": 2,
  "items": [
    {
      "row_number": 1,
      "brand_name": "8 PM Black Whisky",
      "size": "180ml",
      "opening_stock": 30,
      "receipt": 0,
      "total_stock": 30,
      "sale_qty": 5,
      "rate": 180.00,
      "amount": 900.00,
      "closing_stock": 25,
      "math_check": "30-5=25 ✓",
      "confidence": 95.0
    }
  ],
  "total_items": 38,
  "total_amount": 65390.00,
  "grand_total_from_receipt": 65390.00,
  "warnings": ["List any rows where math doesn't add up"]
}

Extract ALL items with careful number reading:`
}

// ExtractSalesFromImageWithPrompt extracts using a specific prompt
func (c *OpenAIVisionClient) ExtractSalesFromImageWithPrompt(ctx context.Context, imageData []byte, imageURL string, prompt string) (*ExtractionResult, error) {
	startTime := time.Now()

	fmt.Printf("🤖 [OpenAI Vision] Starting extraction with GPT-4o...\n")

	// Prepare image content
	var imageContent OpenAIContent
	if len(imageData) > 0 {
		base64Image := base64.StdEncoding.EncodeToString(imageData)
		mimeType := detectMimeType(imageData)
		imageContent = OpenAIContent{
			Type: "image_url",
			ImageURL: &OpenAIImageURL{
				URL:    fmt.Sprintf("data:%s;base64,%s", mimeType, base64Image),
				Detail: "high",
			},
		}
		fmt.Printf("📸 [OpenAI Vision] Using base64 image (%d bytes, %s)\n", len(imageData), mimeType)
	} else if imageURL != "" {
		imageContent = OpenAIContent{
			Type: "image_url",
			ImageURL: &OpenAIImageURL{
				URL:    imageURL,
				Detail: "high",
			},
		}
		fmt.Printf("🔗 [OpenAI Vision] Using image URL: %s\n", truncateString(imageURL, 50))
	} else {
		return nil, fmt.Errorf("no image data or URL provided")
	}

	request := OpenAIRequest{
		Model: c.model,
		Messages: []OpenAIMessage{
			{
				Role: "user",
				Content: []OpenAIContent{
					{Type: "text", Text: prompt},
					imageContent,
				},
			},
		},
		MaxTokens:   16384,
		Temperature: 0.1,
	}

	var response *OpenAIResponse
	var err error
	for attempt := 1; attempt <= c.maxRetries; attempt++ {
		response, err = c.makeAPICall(ctx, request)
		if err == nil {
			break
		}
		fmt.Printf("⚠️  [OpenAI Vision] Attempt %d failed: %v\n", attempt, err)
		if attempt < c.maxRetries {
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("OpenAI API call failed after %d attempts: %w", c.maxRetries, err)
	}

	result, err := c.parseExtractionResponse(response)
	if err != nil {
		return nil, fmt.Errorf("failed to parse extraction response: %w", err)
	}

	result.ExtractionTime = time.Since(startTime)
	result.ModelUsed = c.model

	fmt.Printf("✅ [OpenAI Vision] Extracted %d items in %v\n", len(result.Items), result.ExtractionTime)

	return result, nil
}

// makeAPICall makes the HTTP request to OpenAI API
func (c *OpenAIVisionClient) makeAPICall(ctx context.Context, request OpenAIRequest) (*OpenAIResponse, error) {
	jsonData, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var response OpenAIResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if response.Error != nil {
		return nil, fmt.Errorf("API error: %s (%s)", response.Error.Message, response.Error.Type)
	}

	fmt.Printf("📊 [OpenAI Vision] Model: %s, Tokens used: %d (prompt: %d, completion: %d)\n",
		response.Model, response.Usage.TotalTokens, response.Usage.PromptTokens, response.Usage.CompletionTokens)

	return &response, nil
}

// parseExtractionResponse parses the GPT-4o response into structured data
func (c *OpenAIVisionClient) parseExtractionResponse(response *OpenAIResponse) (*ExtractionResult, error) {
	if len(response.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	content := response.Choices[0].Message.Content

	// Clean up the response (remove markdown code blocks if present)
	content = cleanJSONResponse(content)

	fmt.Printf("🔍 [OpenAI Vision] Raw response length: %d chars\n", len(content))
	fmt.Printf("📄 [OpenAI Vision] Response preview: %s\n", truncateString(content, 300))

	var result ExtractionResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		// Try to extract JSON from the response if it's wrapped in text
		jsonStart := strings.Index(content, "{")
		jsonEnd := strings.LastIndex(content, "}")
		if jsonStart >= 0 && jsonEnd > jsonStart {
			cleanedJSON := content[jsonStart : jsonEnd+1]
			if err := json.Unmarshal([]byte(cleanedJSON), &result); err != nil {
				fmt.Printf("❌ [OpenAI Vision] Failed to parse JSON: %v\n", err)
				fmt.Printf("📄 [OpenAI Vision] Full response content: %s\n", content)
				return nil, fmt.Errorf("failed to parse JSON response: %w", err)
			}
		} else {
			fmt.Printf("❌ [OpenAI Vision] No JSON found - model may have declined or image not a receipt\n")
			fmt.Printf("📄 [OpenAI Vision] Full response: %s\n", content)
			return nil, fmt.Errorf("no valid JSON found - image may not be a liquor sales receipt: %s", truncateString(content, 100))
		}
	}

	// Validate and enrich the extracted items
	result.Items = c.validateAndEnrichItems(result.Items)
	result.TotalItems = len(result.Items)

	// Recalculate total amount
	var totalAmount float64
	for _, item := range result.Items {
		if item.Amount > 0 {
			totalAmount += item.Amount
		}
	}
	result.TotalAmount = totalAmount

	return &result, nil
}

// validateAndEnrichItems validates mathematical relationships and enriches item data
func (c *OpenAIVisionClient) validateAndEnrichItems(items []ExtractedSalesRow) []ExtractedSalesRow {
	validated := make([]ExtractedSalesRow, 0, len(items))

	for i, item := range items {
		// Skip empty items
		if item.BrandName == "" || (item.SaleQty == 0 && item.OpeningStock == 0 && item.ClosingStock == 0) {
			continue
		}

		// Clean brand name
		item.BrandName = openaiCleanBrandName(item.BrandName)

		// Normalize size
		item.Size = FlexibleString(openaiNormalizeSize(item.Size.String()))

		// Validate mathematical relationships
		var issues []string

		// Check Total = Opening + Receipt
		if item.OpeningStock >= 0 && item.Receipt >= 0 && item.TotalStock >= 0 {
			expectedTotal := item.OpeningStock + item.Receipt
			if item.TotalStock != expectedTotal && item.TotalStock != -1 {
				issues = append(issues, fmt.Sprintf("Total mismatch: expected %d, got %d", expectedTotal, item.TotalStock))
			}
		}

		// Check Closing = Total - Sale
		if item.TotalStock >= 0 && item.SaleQty >= 0 && item.ClosingStock >= 0 {
			expectedClosing := item.TotalStock - item.SaleQty
			if item.ClosingStock != expectedClosing && item.ClosingStock != -1 {
				issues = append(issues, fmt.Sprintf("Closing mismatch: expected %d, got %d", expectedClosing, item.ClosingStock))
			}
		}

		// Check Amount = Sale × Rate
		if item.SaleQty > 0 && item.Rate > 0 && item.Amount > 0 {
			expectedAmount := float64(item.SaleQty) * item.Rate
			if absFloat(item.Amount-expectedAmount) > 1.0 { // Allow ₹1 tolerance
				issues = append(issues, fmt.Sprintf("Amount mismatch: expected %.2f, got %.2f", expectedAmount, item.Amount))
			}
		}

		// Auto-fix missing closing stock if we can calculate it
		if item.ClosingStock == -1 && item.TotalStock >= 0 && item.SaleQty >= 0 {
			item.ClosingStock = item.TotalStock - item.SaleQty
			issues = append(issues, "Auto-calculated closing stock")
		}

		// Auto-fix missing amount if we can calculate it
		if item.Amount == 0 && item.SaleQty > 0 && item.Rate > 0 {
			item.Amount = float64(item.SaleQty) * item.Rate
			issues = append(issues, "Auto-calculated amount")
		}

		if len(issues) > 0 {
			item.Notes = strings.Join(issues, "; ")
			item.Confidence = item.Confidence * 0.9 // Reduce confidence for items with issues
		}

		// Ensure row number is set
		if item.RowNumber == 0 {
			item.RowNumber = i + 1
		}

		validated = append(validated, item)
	}

	return validated
}

// ConvertToOCRItems converts extraction result to OCRItem models
func (c *OpenAIVisionClient) ConvertToOCRItems(result *ExtractionResult, sessionID, batchID string) []models.OCRItem {
	items := make([]models.OCRItem, 0, len(result.Items))

	for _, extracted := range result.Items {
		rate := extracted.Rate
		item := models.OCRItem{
			SessionID:          sessionID,
			BatchID:            batchID,
			RowNumber:          extracted.RowNumber,
			BrandText:          extracted.BrandName,
			SizeText:           extracted.Size.String(),
			OpeningStock:       extracted.OpeningStock,
			ReceiptQty:         extracted.Receipt,
			TotalStock:         extracted.TotalStock,
			SaleQuantity:       extracted.SaleQty,
			Rate:               rate,
			SellingPrice:       &rate,
			Amount:             extracted.Amount,
			ClosingStock:       extracted.ClosingStock,
			Quantity:           extracted.ClosingStock, // Legacy alias
			VerificationStatus: "pending",
			IsSelected:         true,
			IsReviewed:         false,
		}

		// Set mathematical validation flags
		item.IsTotalValid = (extracted.OpeningStock + extracted.Receipt) == extracted.TotalStock
		item.IsClosingValid = (extracted.TotalStock - extracted.SaleQty) == extracted.ClosingStock
		item.IsAmountValid = absFloat(float64(extracted.SaleQty)*extracted.Rate-extracted.Amount) < 1.0

		if extracted.Notes != "" {
			item.MathValidationNotes = extracted.Notes
		}

		// Set confidence
		confidence := extracted.Confidence
		item.MatchConfidence = &confidence

		items = append(items, item)
	}

	return items
}

// Helper functions

func cleanJSONResponse(content string) string {
	// Remove markdown code blocks
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)
	return content
}

func openaiCleanBrandName(name string) string {
	// Remove common OCR artifacts
	name = strings.TrimSpace(name)

	// Fix common OCR misreads
	replacements := map[string]string{
		"P.M,": "PM",
		"P.M.": "PM",
		"8 P.M": "8 PM",
		"8P.M": "8 PM",
		"l.B": "IB",
		"l.B.": "IB",
		"O.M": "Old Monk",
		"M.M": "Magic Moments",
		"B.7": "B7",
		"B-7": "B7",
	}

	for old, new := range replacements {
		name = strings.ReplaceAll(name, old, new)
	}

	// Remove multiple spaces
	spaceRegex := regexp.MustCompile(`\s+`)
	name = spaceRegex.ReplaceAllString(name, " ")

	return name
}

func detectMimeType(data []byte) string {
	if len(data) < 4 {
		return "image/jpeg"
	}

	// Check magic bytes
	if data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
		return "image/jpeg"
	}
	if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
		return "image/png"
	}
	if data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 {
		return "image/gif"
	}
	if data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 {
		return "image/webp"
	}

	return "image/jpeg" // Default
}

func absFloat(f float64) float64 {
	if f < 0 {
		return -f
	}
	return f
}

func openaiNormalizeSize(size string) string {
	size = strings.ToLower(strings.TrimSpace(size))

	// Normalize common variations
	sizeMap := map[string]string{
		"180":    "180ml",
		"180 ml": "180ml",
		"375":    "375ml",
		"375 ml": "375ml",
		"750":    "750ml",
		"750 ml": "750ml",
		"90":     "90ml",
		"90 ml":  "90ml",
		"1l":     "1000ml",
		"1 l":    "1000ml",
		"half":   "375ml",
		"quart":  "180ml",
		"full":   "750ml",
		"peg":    "90ml",
	}

	if normalized, ok := sizeMap[size]; ok {
		return normalized
	}

	// Ensure "ml" suffix
	if !strings.HasSuffix(size, "ml") && len(size) > 0 {
		// Try to extract number
		numStr := strings.TrimRight(size, "mlML ")
		if _, err := strconv.Atoi(numStr); err == nil {
			return numStr + "ml"
		}
	}

	return size
}
