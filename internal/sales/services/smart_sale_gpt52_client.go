package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// SmartSaleGPT52Client - Dedicated GPT-5.2 client for Smart Sale OCR
// Uses OpenAI's latest GPT-5.2 model for superior vision and extraction
type SmartSaleGPT52Client struct {
	apiKey     string
	httpClient *http.Client
	model      string
}

// SmartSaleExtractedRow represents a single row extracted from receipt image
type SmartSaleExtractedRow struct {
	SerialNumber int     `json:"serial_number"`
	BrandName    string  `json:"brand_name"`
	Size         string  `json:"size"`

	// 7-Column Data from Image
	ImageOpening  int     `json:"image_opening"`   // Opening stock from image
	ImageReceipt  int     `json:"image_receipt"`   // Receipt from image
	ImageTotal    int     `json:"image_total"`     // Total from image
	ImageSale     int     `json:"image_sale"`      // Sale quantity from image
	ImageRate     float64 `json:"image_rate"`      // Rate from image
	ImageAmount   float64 `json:"image_amount"`    // Amount from image
	ImageClosing  int     `json:"image_closing"`   // Closing from image

	// Confidence
	Confidence    float64 `json:"confidence"`
	RawText       string  `json:"raw_text"`
}

// SmartSaleGPT52Response represents the structured response from GPT-5.2
type SmartSaleGPT52Response struct {
	ReceiptType   string                  `json:"receipt_type"`   // "SALE RECEIPT", "STOCK REGISTER", etc.
	Size          string                  `json:"size"`           // "180ML", "375ML", "750ML"
	ShopName      string                  `json:"shop_name"`
	Date          string                  `json:"date"`
	Rows          []SmartSaleExtractedRow `json:"rows"`
	TotalAmount   float64                 `json:"total_amount"`
	Confidence    float64                 `json:"confidence"`
}

// NewSmartSaleGPT52Client creates a new GPT-5.2 client for Smart Sale
func NewSmartSaleGPT52Client() *SmartSaleGPT52Client {
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		fmt.Println("⚠️  [GPT-5.2] OPENAI_API_KEY not set")
		return nil
	}

	client := &SmartSaleGPT52Client{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 120 * time.Second, // GPT-5.2 may need more time for complex images
		},
		model: "gpt-5.2", // Latest GPT-5.2 model
	}

	fmt.Println("✅ [GPT-5.2] Smart Sale client initialized with model:", client.model)
	return client
}

// ExtractReceiptData extracts all data from receipt image using GPT-5.2
func (c *SmartSaleGPT52Client) ExtractReceiptData(ctx context.Context, imageBase64 string) (*SmartSaleGPT52Response, error) {
	if c.apiKey == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY not configured")
	}

	fmt.Println("🤖 [GPT-5.2] Extracting receipt data...")

	// Build the extraction prompt
	prompt := c.buildExtractionPrompt()

	// Prepare the request - GPT-5.2 uses different parameters
	reqBody := map[string]interface{}{
		"model": c.model,
		"messages": []map[string]interface{}{
			{
				"role": "user",
				"content": []map[string]interface{}{
					{
						"type": "text",
						"text": prompt,
					},
					{
						"type": "image_url",
						"image_url": map[string]string{
							"url":    fmt.Sprintf("data:image/jpeg;base64,%s", imageBase64),
							"detail": "high", // Use high detail for better OCR
						},
					},
				},
			},
		},
		"max_completion_tokens": 4096, // GPT-5.2 uses max_completion_tokens instead of max_tokens
		"temperature": 0.1, // Low temperature for consistent extraction
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Make the API call
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	startTime := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("API request failed: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime)
	fmt.Printf("🤖 [GPT-5.2] API call completed in %v\n", duration)

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	// Parse the response
	var apiResp OpenAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.Error != nil {
		return nil, fmt.Errorf("API error: %s", apiResp.Error.Message)
	}

	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from GPT-5.2")
	}

	content := apiResp.Choices[0].Message.Content
	fmt.Printf("🤖 [GPT-5.2] Response length: %d chars\n", len(content))

	// Parse the JSON response from GPT-5.2
	result, err := c.parseGPT52Response(content)
	if err != nil {
		return nil, fmt.Errorf("failed to parse GPT-5.2 response: %w", err)
	}

	fmt.Printf("✅ [GPT-5.2] Extracted %d rows from receipt\n", len(result.Rows))
	return result, nil
}

// buildExtractionPrompt creates the extraction prompt for GPT-5.2
func (c *SmartSaleGPT52Client) buildExtractionPrompt() string {
	return `You are an expert OCR system for Indian liquor sale receipts/registers with 99.9% accuracy.

TASK: Extract ALL data from this receipt image into structured JSON. Be extremely careful with EVERY cell.

🚫 CRITICAL ROW ISOLATION RULES:
1. Each row = ONE product only - NEVER mix data between rows
2. Serial numbers MUST be sequential (1, 2, 3...)
3. If two rows have identical sale quantities, VERIFY each independently
4. Read each row LEFT to RIGHT completely before moving to next row
5. Do NOT assume adjacent rows have similar values

⚠️ BRAND VARIANT RULES - Read COMPLETE brand names:
- A base brand with additional words is a DIFFERENT product (e.g., "BRAND X" ≠ "BRAND X PREMIUM")
- Include ALL words you see in the brand name - never truncate
- Pay attention to variant/suffix words like: MATURED, WHITE, GOLD, STRONG, PREMIUM, ULTRA,
  MAX, RESERVE, SELECT, CLASSIC, ORIGINAL, SPECIAL, DELUXE, BLACK, XXX, etc.
- Two brands sharing the same first word but having different suffixes are DIFFERENT products
- When in doubt, include MORE words rather than fewer

📋 RECEIPT COLUMNS (typical order, names may vary):
1. S.No/Sr - Serial number (1, 2, 3...)
2. Brand Name/Item/Description - Liquor brand name
3. Opening/Open/Op - Opening stock at start of day
4. Receipt/Rcpt/Recd/Received - New stock received (often 0 or empty)
5. Total/Tot - Total stock (Opening + Receipt)
6. **SALE/ISSUE/ISSU/SOLD/QTY** - Number of bottles SOLD (CRITICAL!)
7. Rate/MRP/Price - Price per bottle in ₹
8. Amount/Amt/Value - Total amount (Sale × Rate)
9. Closing/Close/Cl/Balance - Remaining stock (Total - Sale)

🚨 CRITICAL - SALE COLUMN EXTRACTION:
The SALE/ISSUE column is the MOST IMPORTANT column. It shows bottles SOLD.
- Located BETWEEN "Total" and "Rate" columns
- May be labeled: "Sale", "SALE", "Sal", "Issue", "ISSUE", "Issu", "Sold", "Qty"
- Contains small numbers (usually 0-20 per row)
- If Amount > 0 and Rate > 0, then Sale = Amount ÷ Rate (verify your extraction!)
- NEVER assume Sale is 0 if there's a visible number in that column
- Look VERY carefully at each cell - numbers like 1, 2, 3 are easy to miss

🔍 VALIDATION RULES (apply to EVERY row):
1. If image_amount > 0 and image_rate > 0: image_sale SHOULD = image_amount ÷ image_rate
2. If image_closing < image_total: image_sale SHOULD = image_total - image_closing
3. If your extracted sale doesn't match these calculations, RE-CHECK the image!
4. A sale of 0 means NO bottles were sold - only use 0 if the cell is truly empty or shows "-"

🎯 EXTRACTION RULES:
1. Extract EVERY row - do not skip any
2. Read each cell value EXACTLY as shown - do not guess
3. Empty cell or "-" = use 0
4. Brand names: extract as-is even with OCR errors
5. Detect size from header (90ML, 180ML, 375ML, 750ML)
6. Double-check all sale quantities - this is critical for accurate totals

📤 RESPOND WITH ONLY THIS JSON (no markdown):
{
  "receipt_type": "SALE RECEIPT",
  "size": "750ML",
  "shop_name": "detected shop name",
  "date": "detected date",
  "rows": [
    {
      "serial_number": 1,
      "brand_name": "Brand Name Here",
      "size": "750ML",
      "image_opening": 10,
      "image_receipt": 0,
      "image_total": 10,
      "image_sale": 2,
      "image_rate": 500.00,
      "image_amount": 1000.00,
      "image_closing": 8,
      "confidence": 95.0,
      "raw_text": "1 Brand Name 10 0 10 2 500 1000 8"
    }
  ],
  "total_amount": 1000.00,
  "confidence": 95.0
}

⚠️ FINAL CHECK before responding:
- Did you extract EVERY row from the image?
- Does each row's sale quantity match: Amount ÷ Rate?
- Does each row's closing match: Total - Sale?
- If mismatches exist, re-examine that row in the image!`
}

// parseGPT52Response parses the JSON response from GPT-5.2
func (c *SmartSaleGPT52Client) parseGPT52Response(content string) (*SmartSaleGPT52Response, error) {
	// Clean up the response - remove any markdown formatting
	content = strings.TrimSpace(content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	// Find JSON object boundaries
	startIdx := strings.Index(content, "{")
	endIdx := strings.LastIndex(content, "}")
	if startIdx == -1 || endIdx == -1 || startIdx >= endIdx {
		return nil, fmt.Errorf("no valid JSON found in response")
	}
	content = content[startIdx : endIdx+1]

	var result SmartSaleGPT52Response
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		fmt.Printf("❌ [GPT-5.2] JSON parse error: %v\n", err)
		fmt.Printf("   Content: %s\n", content[:gpt52MinInt(500, len(content))])
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	// Post-process and validate
	for i := range result.Rows {
		row := &result.Rows[i]

		// Clean brand name
		row.BrandName = strings.TrimSpace(row.BrandName)

		// ===== SALE QUANTITY RECOVERY =====
		// If sale is 0 but we have amount and rate, calculate sale
		if row.ImageSale == 0 && row.ImageAmount > 0 && row.ImageRate > 0 {
			calculatedSale := int(row.ImageAmount / row.ImageRate)
			if calculatedSale > 0 {
				fmt.Printf("🔧 [GPT-5.2] Row %d (%s): Recovered sale=%d from amount=%.2f/rate=%.2f\n",
					i+1, row.BrandName, calculatedSale, row.ImageAmount, row.ImageRate)
				row.ImageSale = calculatedSale
			}
		}

		// If sale is 0 but we have total and closing, calculate sale
		if row.ImageSale == 0 && row.ImageTotal > 0 && row.ImageClosing > 0 && row.ImageClosing < row.ImageTotal {
			calculatedSale := row.ImageTotal - row.ImageClosing
			if calculatedSale > 0 {
				fmt.Printf("🔧 [GPT-5.2] Row %d (%s): Recovered sale=%d from total=%d-closing=%d\n",
					i+1, row.BrandName, calculatedSale, row.ImageTotal, row.ImageClosing)
				row.ImageSale = calculatedSale
			}
		}

		// ===== AMOUNT RECOVERY =====
		// If amount is 0 but we have sale and rate, calculate amount
		if row.ImageAmount == 0 && row.ImageSale > 0 && row.ImageRate > 0 {
			row.ImageAmount = float64(row.ImageSale) * row.ImageRate
			fmt.Printf("🔧 [GPT-5.2] Row %d (%s): Recovered amount=%.2f from sale=%d*rate=%.2f\n",
				i+1, row.BrandName, row.ImageAmount, row.ImageSale, row.ImageRate)
		}

		// Validate math relationships
		expectedTotal := row.ImageOpening + row.ImageReceipt
		expectedClosing := row.ImageTotal - row.ImageSale
		expectedAmount := float64(row.ImageSale) * row.ImageRate

		// Adjust confidence based on math validation
		if row.ImageTotal > 0 && row.ImageTotal != expectedTotal {
			row.Confidence -= 10
		}
		if row.ImageClosing > 0 && row.ImageClosing != expectedClosing {
			row.Confidence -= 10
		}
		if row.ImageAmount > 0 && absFloat64(row.ImageAmount-expectedAmount) > 1 {
			row.Confidence -= 10
		}

		// Ensure confidence is in valid range
		if row.Confidence < 0 {
			row.Confidence = 0
		}
		if row.Confidence > 100 {
			row.Confidence = 100
		}

		// Log extraction for debugging
		if row.ImageSale > 0 {
			fmt.Printf("📊 [GPT-5.2] Row %d: %s | Sale=%d | Rate=%.0f | Amount=%.0f\n",
				i+1, row.BrandName, row.ImageSale, row.ImageRate, row.ImageAmount)
		}
	}

	// Run post-extraction validation to detect potential row confusion
	c.validateExtractedRows(&result)

	return &result, nil
}

// gpt52MinInt returns the minimum of two integers (local helper to avoid conflicts)
func gpt52MinInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// validateExtractedRows performs post-extraction validation to detect row confusion issues
func (c *SmartSaleGPT52Client) validateExtractedRows(result *SmartSaleGPT52Response) []string {
	warnings := []string{}

	if len(result.Rows) == 0 {
		return warnings
	}

	// Check 1: Sequential serial numbers
	for i, row := range result.Rows {
		expectedSerial := i + 1
		if row.SerialNumber != expectedSerial && row.SerialNumber != 0 {
			warnings = append(warnings, fmt.Sprintf(
				"⚠️ Row %d: Serial number %d is not sequential (expected %d)",
				i+1, row.SerialNumber, expectedSerial))
		}
	}

	// Check 2: Detect suspicious duplicate sale quantities between adjacent rows
	for i := 1; i < len(result.Rows); i++ {
		prevRow := result.Rows[i-1]
		currRow := result.Rows[i]

		// If two adjacent rows have identical sale quantities AND identical amounts, flag it
		if prevRow.ImageSale == currRow.ImageSale &&
			prevRow.ImageSale > 0 &&
			prevRow.ImageAmount == currRow.ImageAmount &&
			prevRow.ImageAmount > 0 {
			warnings = append(warnings, fmt.Sprintf(
				"⚠️ Rows %d-%d: Identical sale=%d and amount=%.0f - possible row confusion between '%s' and '%s'",
				i, i+1, currRow.ImageSale, currRow.ImageAmount, prevRow.BrandName, currRow.BrandName))
		}
	}

	// Check 3: Dynamically detect similar brand names that might be confused
	// Look for brands that share a common base but have different variants
	brandNames := make([]string, len(result.Rows))
	for i, row := range result.Rows {
		brandNames[i] = strings.ToUpper(strings.TrimSpace(row.BrandName))
	}

	// Compare each pair of brands to find potential variants
	for i := 0; i < len(brandNames); i++ {
		for j := i + 1; j < len(brandNames); j++ {
			if arePotentialVariants(brandNames[i], brandNames[j]) {
				warnings = append(warnings, fmt.Sprintf(
					"ℹ️ Similar brands detected: '%s' and '%s' may be variants - verify row data is correctly isolated",
					result.Rows[i].BrandName, result.Rows[j].BrandName))
			}
		}
	}

	// Log warnings if any
	if len(warnings) > 0 {
		fmt.Println("🔍 [GPT-5.2] Post-extraction validation warnings:")
		for _, w := range warnings {
			fmt.Printf("   %s\n", w)
		}
	}

	return warnings
}

// arePotentialVariants checks if two brand names are likely variants of each other
// e.g., "OLD MONK" and "OLD MONK MATURED RUM" are potential variants
func arePotentialVariants(brand1, brand2 string) bool {
	if brand1 == brand2 || brand1 == "" || brand2 == "" {
		return false
	}

	words1 := strings.Fields(brand1)
	words2 := strings.Fields(brand2)

	if len(words1) == 0 || len(words2) == 0 {
		return false
	}

	// Check 1: One is a prefix of the other
	shorter, longer := words1, words2
	if len(words1) > len(words2) {
		shorter, longer = words2, words1
	}

	if len(shorter) < len(longer) {
		isPrefix := true
		for i := 0; i < len(shorter); i++ {
			if !strings.EqualFold(shorter[i], longer[i]) {
				isPrefix = false
				break
			}
		}
		if isPrefix {
			return true
		}
	}

	// Check 2: Same first word with different suffixes
	if len(words1) >= 1 && len(words2) >= 1 {
		if strings.EqualFold(words1[0], words2[0]) && len(words1) != len(words2) {
			return true
		}
	}

	// Check 3: High word overlap (share 50%+ words) but not identical
	matchCount := 0
	for _, w1 := range words1 {
		for _, w2 := range words2 {
			if strings.EqualFold(w1, w2) {
				matchCount++
				break
			}
		}
	}

	minWords := len(words1)
	if len(words2) < minWords {
		minWords = len(words2)
	}

	if minWords > 0 && float64(matchCount)/float64(minWords) >= 0.5 {
		// High overlap but different - potential variants
		return len(words1) != len(words2) || matchCount < len(words1)
	}

	return false
}

// SmartSaleSystemData represents system data for comparison
type SmartSaleSystemData struct {
	ProductID     string
	BrandName     string
	Size          string
	SystemOpening int     // Current stock in database (becomes opening for new day)
	SystemRate    float64 // MRP/Selling price from products table
	SystemStock   int     // Current total stock
}

// SmartSaleComparisonResult represents comparison between image and system data
type SmartSaleComparisonResult struct {
	// Extracted from Image
	ImageRow SmartSaleExtractedRow

	// System Data (Truth)
	SystemData *SmartSaleSystemData

	// Final Values to Use
	FinalOpening  int     // Use System value
	FinalRate     float64 // Use System value
	FinalSale     int     // Use Image value (actual sale)
	FinalAmount   float64 // Calculated: FinalSale × FinalRate
	FinalClosing  int     // Calculated: FinalOpening - FinalSale

	// Discrepancy Flags
	HasOpeningMismatch bool
	HasRateMismatch    bool
	OpeningDifference  int
	RateDifference     float64

	// Warnings for UI
	Warnings []string

	// Match status
	ProductMatched bool
	MatchConfidence float64
}

// CompareWithSystem compares extracted data with system data
// System values are used as TRUTH, image discrepancies are flagged
func CompareWithSystem(extracted SmartSaleExtractedRow, system *SmartSaleSystemData) *SmartSaleComparisonResult {
	result := &SmartSaleComparisonResult{
		ImageRow:   extracted,
		SystemData: system,
		Warnings:   []string{},
	}

	if system == nil {
		// No system data - use image values
		result.FinalOpening = extracted.ImageOpening
		result.FinalRate = extracted.ImageRate
		result.FinalSale = extracted.ImageSale
		result.FinalAmount = extracted.ImageAmount
		result.FinalClosing = extracted.ImageClosing
		result.ProductMatched = false
		result.Warnings = append(result.Warnings, "⚠️ Product not found in database - using image values")
		return result
	}

	result.ProductMatched = true
	result.MatchConfidence = extracted.Confidence

	// ===== USE SYSTEM VALUES AS TRUTH =====

	// Opening Stock: Use SYSTEM value (current stock in DB)
	result.FinalOpening = system.SystemOpening

	// Rate: Use SYSTEM value (MRP from products table)
	result.FinalRate = system.SystemRate

	// Sale: Use IMAGE value (this is what was actually sold)
	result.FinalSale = extracted.ImageSale

	// Calculate Amount using SYSTEM rate
	result.FinalAmount = float64(result.FinalSale) * result.FinalRate

	// Calculate Closing using SYSTEM opening
	result.FinalClosing = result.FinalOpening - result.FinalSale

	// ===== FLAG DISCREPANCIES =====

	// Check Opening Stock mismatch
	if extracted.ImageOpening > 0 && extracted.ImageOpening != system.SystemOpening {
		result.HasOpeningMismatch = true
		result.OpeningDifference = extracted.ImageOpening - system.SystemOpening

		severity := "⚠️"
		if absInt(result.OpeningDifference) > 10 {
			severity = "🚨"
		}

		result.Warnings = append(result.Warnings, fmt.Sprintf(
			"%s Opening Stock Mismatch: Image shows %d, System has %d (Diff: %+d) - Using System value",
			severity, extracted.ImageOpening, system.SystemOpening, result.OpeningDifference,
		))
	}

	// Check Rate mismatch
	if extracted.ImageRate > 0 && extracted.ImageRate != system.SystemRate {
		result.HasRateMismatch = true
		result.RateDifference = extracted.ImageRate - system.SystemRate

		percentDiff := (result.RateDifference / system.SystemRate) * 100
		severity := "⚠️"
		if absFloat64(percentDiff) > 10 {
			severity = "🚨"
		}

		result.Warnings = append(result.Warnings, fmt.Sprintf(
			"%s Rate Mismatch: Image shows ₹%.2f, System has ₹%.2f (Diff: ₹%+.2f / %.1f%%) - Using System value",
			severity, extracted.ImageRate, system.SystemRate, result.RateDifference, percentDiff,
		))
	}

	// Check Amount calculation
	imageExpectedAmount := float64(extracted.ImageSale) * extracted.ImageRate
	if extracted.ImageAmount > 0 && absFloat64(extracted.ImageAmount-imageExpectedAmount) > 1 {
		result.Warnings = append(result.Warnings, fmt.Sprintf(
			"ℹ️ Image Amount (₹%.2f) differs from calculated (₹%.2f = %d × ₹%.2f)",
			extracted.ImageAmount, imageExpectedAmount, extracted.ImageSale, extracted.ImageRate,
		))
	}

	return result
}

// ParseSize parses size string to integer ML value
func ParseSize(sizeStr string) int {
	sizeStr = strings.ToUpper(strings.TrimSpace(sizeStr))
	sizeStr = strings.TrimSuffix(sizeStr, "ML")
	sizeStr = strings.TrimSpace(sizeStr)

	if val, err := strconv.Atoi(sizeStr); err == nil {
		return val
	}
	return 0
}
