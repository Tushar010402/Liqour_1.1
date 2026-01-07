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

	"github.com/liquorpro/go-backend/internal/sales/models"
)

// OllamaVisionClient handles Qwen2.5-VL via Ollama for receipt OCR
type OllamaVisionClient struct {
	baseURL    string
	model      string
	httpClient *http.Client
	maxRetries int
}

// OllamaGenerateRequest represents the request for Ollama generate API
type OllamaGenerateRequest struct {
	Model   string   `json:"model"`
	Prompt  string   `json:"prompt"`
	Images  []string `json:"images,omitempty"` // Base64 encoded images (without data URI prefix)
	Stream  bool     `json:"stream"`
	Options *OllamaOptions `json:"options,omitempty"`
}

// OllamaOptions represents model options for inference
type OllamaOptions struct {
	Temperature   float64 `json:"temperature,omitempty"`
	NumPredict    int     `json:"num_predict,omitempty"` // Max tokens
	NumCtx        int     `json:"num_ctx,omitempty"`     // Context window
	TopK          int     `json:"top_k,omitempty"`
	TopP          float64 `json:"top_p,omitempty"`
}

// OllamaGenerateResponse represents the response from Ollama generate API
type OllamaGenerateResponse struct {
	Model     string `json:"model"`
	Response  string `json:"response"`
	Done      bool   `json:"done"`
	Context   []int  `json:"context,omitempty"`
	TotalDuration     int64 `json:"total_duration,omitempty"`
	LoadDuration      int64 `json:"load_duration,omitempty"`
	PromptEvalCount   int   `json:"prompt_eval_count,omitempty"`
	PromptEvalDuration int64 `json:"prompt_eval_duration,omitempty"`
	EvalCount         int   `json:"eval_count,omitempty"`
	EvalDuration      int64 `json:"eval_duration,omitempty"`
}

// OllamaTagsResponse represents the response from /api/tags
type OllamaTagsResponse struct {
	Models []struct {
		Name string `json:"name"`
		Size int64  `json:"size"`
	} `json:"models"`
}

// NewOllamaVisionClient creates a new Ollama Vision client
func NewOllamaVisionClient() (*OllamaVisionClient, error) {
	baseURL := os.Getenv("OLLAMA_HOST")
	if baseURL == "" {
		baseURL = "http://ollama:11434" // Default Docker network address
	}

	model := os.Getenv("OLLAMA_MODEL")
	if model == "" {
		model = "qwen2.5vl:7b" // Default vision model
	}

	client := &OllamaVisionClient{
		baseURL: baseURL,
		model:   model,
		httpClient: &http.Client{
			Timeout: 300 * time.Second, // 5 minute timeout for CPU inference
		},
		maxRetries: 2,
	}

	fmt.Printf("🦙 [Ollama] Client initialized: %s with model %s\n", baseURL, model)

	return client, nil
}

// Name returns the provider name
func (c *OllamaVisionClient) Name() string {
	return "ollama"
}

// IsAvailable checks if Ollama service is available and model is loaded
func (c *OllamaVisionClient) IsAvailable(ctx context.Context) bool {
	// Check if service is responding
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/api/tags", nil)
	if err != nil {
		fmt.Printf("⚠️  [Ollama] Failed to create health check request: %v\n", err)
		return false
	}

	// Use shorter timeout for health check
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("⚠️  [Ollama] Service not available: %v\n", err)
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Printf("⚠️  [Ollama] Service returned status %d\n", resp.StatusCode)
		return false
	}

	// Check if our model is available
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false
	}

	var tags OllamaTagsResponse
	if err := json.Unmarshal(body, &tags); err != nil {
		return false
	}

	for _, m := range tags.Models {
		if m.Name == c.model {
			fmt.Printf("✅ [Ollama] Model %s is available\n", c.model)
			return true
		}
	}

	fmt.Printf("⚠️  [Ollama] Model %s not found in available models\n", c.model)
	return false
}

// ExtractSalesFromImage extracts sales data from a receipt image using Ollama
func (c *OllamaVisionClient) ExtractSalesFromImage(ctx context.Context, imageData []byte, imageURL string) (*ExtractionResult, error) {
	startTime := time.Now()

	fmt.Printf("🦙 [Ollama] Starting extraction with %s...\n", c.model)

	// Prepare image
	var base64Image string
	if len(imageData) > 0 {
		base64Image = base64.StdEncoding.EncodeToString(imageData)
		mimeType := detectMimeType(imageData)
		fmt.Printf("📸 [Ollama] Using base64 image (%d bytes, %s)\n", len(imageData), mimeType)
	} else if imageURL != "" {
		// Download image from URL
		downloaded, err := c.downloadImage(ctx, imageURL)
		if err != nil {
			return nil, fmt.Errorf("failed to download image: %w", err)
		}
		base64Image = base64.StdEncoding.EncodeToString(downloaded)
		fmt.Printf("📥 [Ollama] Downloaded image from URL (%d bytes)\n", len(downloaded))
	} else {
		return nil, fmt.Errorf("no image data or URL provided")
	}

	// Build the extraction prompt optimized for Qwen2.5-VL
	prompt := c.buildExtractionPrompt()

	// Create the request
	request := OllamaGenerateRequest{
		Model:  c.model,
		Prompt: prompt,
		Images: []string{base64Image},
		Stream: false,
		Options: &OllamaOptions{
			Temperature: 0.1,       // Low for consistent output
			NumPredict:  8192,      // Max tokens for large receipts
			NumCtx:      4096,      // Context window
			TopK:        40,
			TopP:        0.9,
		},
	}

	// Make the API call with retries
	var response *OllamaGenerateResponse
	var err error
	for attempt := 1; attempt <= c.maxRetries; attempt++ {
		response, err = c.makeAPICall(ctx, request)
		if err == nil {
			break
		}
		fmt.Printf("⚠️  [Ollama] Attempt %d failed: %v\n", attempt, err)
		if attempt < c.maxRetries {
			time.Sleep(time.Duration(attempt) * 5 * time.Second)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("Ollama API call failed after %d attempts: %w", c.maxRetries, err)
	}

	// Parse the response
	result, err := c.parseExtractionResponse(response)
	if err != nil {
		return nil, fmt.Errorf("failed to parse extraction response: %w", err)
	}

	result.ExtractionTime = time.Since(startTime)
	result.ModelUsed = c.model

	// Log performance metrics
	if response.TotalDuration > 0 {
		totalSec := float64(response.TotalDuration) / 1e9
		evalSec := float64(response.EvalDuration) / 1e9
		tokensPerSec := float64(response.EvalCount) / evalSec
		fmt.Printf("📊 [Ollama] Performance: %.1fs total, %.1f tokens/sec, %d tokens generated\n",
			totalSec, tokensPerSec, response.EvalCount)
	}

	fmt.Printf("✅ [Ollama] Extracted %d items in %v\n", len(result.Items), result.ExtractionTime)

	return result, nil
}

// ExtractSalesFromImageWithPrompt extracts using a specific prompt
func (c *OllamaVisionClient) ExtractSalesFromImageWithPrompt(ctx context.Context, imageData []byte, imageURL string, prompt string) (*ExtractionResult, error) {
	startTime := time.Now()

	fmt.Printf("🦙 [Ollama] Starting extraction with custom prompt...\n")

	var base64Image string
	if len(imageData) > 0 {
		base64Image = base64.StdEncoding.EncodeToString(imageData)
	} else if imageURL != "" {
		downloaded, err := c.downloadImage(ctx, imageURL)
		if err != nil {
			return nil, fmt.Errorf("failed to download image: %w", err)
		}
		base64Image = base64.StdEncoding.EncodeToString(downloaded)
	} else {
		return nil, fmt.Errorf("no image data or URL provided")
	}

	request := OllamaGenerateRequest{
		Model:  c.model,
		Prompt: prompt,
		Images: []string{base64Image},
		Stream: false,
		Options: &OllamaOptions{
			Temperature: 0.1,
			NumPredict:  8192,
			NumCtx:      4096,
		},
	}

	response, err := c.makeAPICall(ctx, request)
	if err != nil {
		return nil, fmt.Errorf("Ollama API call failed: %w", err)
	}

	result, err := c.parseExtractionResponse(response)
	if err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	result.ExtractionTime = time.Since(startTime)
	result.ModelUsed = c.model

	return result, nil
}

// buildExtractionPrompt creates the optimized prompt for Qwen2.5-VL
func (c *OllamaVisionClient) buildExtractionPrompt() string {
	return `You are an expert OCR system. Extract ALL rows from this Indian liquor sales receipt.

TABLE COLUMNS: S.No | Brand | Opening | Receipt | Total | Sale | Rate | Amount | Closing

EXTRACTION RULES:
1. Extract EVERY row from S.No 1 to the last item before totals
2. Rate = price per bottle (typically ₹80-400 for 180ml liquor)
3. Amount = Sale × Rate (use this to verify rate is correct)
4. If rate seems wrong (e.g., 18.00 instead of 180.00), calculate: Amount ÷ Sale

COMMON BRAND ABBREVIATIONS:
- IB = Imperial Blue
- RS = Royal Stag
- OC = Officer's Choice
- MM = Magic Moments
- BP = Blenders Pride
- OM = Old Monk
- MCD = McDowell's

OUTPUT ONLY valid JSON in this exact format:
{
  "receipt_type": "HALF",
  "items": [
    {
      "row_number": 1,
      "brand_name": "Brand Name Here",
      "size": "180ml",
      "opening_stock": 10,
      "receipt": 0,
      "total_stock": 10,
      "sale_qty": 5,
      "rate": 180.00,
      "amount": 900.00,
      "closing_stock": 5,
      "confidence": 95.0
    }
  ],
  "total_items": 27,
  "total_amount": 32500.00
}

Extract ALL items now - output JSON only, no explanation:`
}

// makeAPICall makes the HTTP request to Ollama API
func (c *OllamaVisionClient) makeAPICall(ctx context.Context, request OllamaGenerateRequest) (*OllamaGenerateResponse, error) {
	jsonData, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/generate", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	fmt.Printf("⏳ [Ollama] Sending request to %s (this may take 1-2 minutes on CPU)...\n", c.baseURL)

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

	var response OllamaGenerateResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &response, nil
}

// parseExtractionResponse parses Ollama response into ExtractionResult
func (c *OllamaVisionClient) parseExtractionResponse(response *OllamaGenerateResponse) (*ExtractionResult, error) {
	content := response.Response

	// Clean up the response
	content = cleanJSONResponse(content)

	fmt.Printf("🔍 [Ollama] Raw response length: %d chars\n", len(content))
	fmt.Printf("📄 [Ollama] Response preview: %s\n", truncateString(content, 300))

	var result ExtractionResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		// Try to extract JSON from the response
		jsonStart := strings.Index(content, "{")
		jsonEnd := strings.LastIndex(content, "}")
		if jsonStart >= 0 && jsonEnd > jsonStart {
			cleanedJSON := content[jsonStart : jsonEnd+1]
			if err := json.Unmarshal([]byte(cleanedJSON), &result); err != nil {
				fmt.Printf("❌ [Ollama] Failed to parse JSON: %v\n", err)
				fmt.Printf("📄 [Ollama] Full response: %s\n", content)
				return nil, fmt.Errorf("failed to parse JSON response: %w", err)
			}
		} else {
			return nil, fmt.Errorf("no valid JSON found in response")
		}
	}

	// Validate and enrich items
	result.Items = c.validateAndEnrichItems(result.Items)
	result.TotalItems = len(result.Items)

	// Recalculate total
	var totalAmount float64
	for _, item := range result.Items {
		totalAmount += item.Amount
	}
	result.TotalAmount = totalAmount

	return &result, nil
}

// validateAndEnrichItems validates extracted items
func (c *OllamaVisionClient) validateAndEnrichItems(items []ExtractedSalesRow) []ExtractedSalesRow {
	validated := make([]ExtractedSalesRow, 0, len(items))

	for i, item := range items {
		if item.BrandName == "" || (item.SaleQty == 0 && item.OpeningStock == 0 && item.ClosingStock == 0) {
			continue
		}

		item.BrandName = openaiCleanBrandName(item.BrandName)
		item.Size = FlexibleString(openaiNormalizeSize(item.Size.String()))

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
			if absFloat(item.Amount-expectedAmount) > 1.0 {
				issues = append(issues, fmt.Sprintf("Amount mismatch: expected %.2f, got %.2f", expectedAmount, item.Amount))
			}
		}

		// Auto-fix rate if amount and sale are valid but rate is wrong
		if item.SaleQty > 0 && item.Amount > 0 {
			calculatedRate := item.Amount / float64(item.SaleQty)
			if absFloat(item.Rate-calculatedRate) > 1.0 {
				item.Rate = calculatedRate
				issues = append(issues, "Auto-corrected rate")
			}
		}

		if len(issues) > 0 {
			item.Notes = strings.Join(issues, "; ")
			item.Confidence = item.Confidence * 0.9
		}

		if item.RowNumber == 0 {
			item.RowNumber = i + 1
		}

		if item.Confidence == 0 {
			item.Confidence = 85.0 // Default confidence for Ollama
		}

		validated = append(validated, item)
	}

	return validated
}

// downloadImage downloads an image from URL
func (c *OllamaVisionClient) downloadImage(ctx context.Context, imageURL string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", imageURL, nil)
	if err != nil {
		return nil, err
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to download image: status %d", resp.StatusCode)
	}

	return io.ReadAll(resp.Body)
}

// ConvertToOCRItems converts extraction result to OCRItem models
func (c *OllamaVisionClient) ConvertToOCRItems(result *ExtractionResult, sessionID, batchID string) []models.OCRItem {
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
			Quantity:           extracted.ClosingStock,
			VerificationStatus: "pending",
			IsSelected:         true,
			IsReviewed:         false,
		}

		item.IsTotalValid = (extracted.OpeningStock + extracted.Receipt) == extracted.TotalStock
		item.IsClosingValid = (extracted.TotalStock - extracted.SaleQty) == extracted.ClosingStock
		item.IsAmountValid = absFloat(float64(extracted.SaleQty)*extracted.Rate-extracted.Amount) < 1.0

		if extracted.Notes != "" {
			item.MathValidationNotes = extracted.Notes
		}

		confidence := extracted.Confidence
		item.MatchConfidence = &confidence

		items = append(items, item)
	}

	return items
}
