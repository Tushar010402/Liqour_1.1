package services

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/google/generative-ai-go/genai"
	"github.com/sirupsen/logrus"
	"google.golang.org/api/option"
)

// GeminiOCRService handles OCR extraction using Google Gemini API
type GeminiOCRService struct {
	client         *genai.Client
	logger         *logrus.Logger
	sizeNormalizer *SizeNormalizer
}

// ExtractedReceiptItem represents a single item extracted from the receipt
type ExtractedReceiptItem struct {
	Brand         string   `json:"brand"`
	Category      string   `json:"category"`      // Detected category (whiskey, rum, vodka, beer, gin)
	Subcategory   string   `json:"subcategory"`   // Detected subcategory (premium, normal)
	SizeText      string   `json:"size_text"`
	SizeML        int      `json:"size_ml"`
	Quantity      int      `json:"quantity"`
	Price         *float64 `json:"price,omitempty"`
	RatePerUnit   *float64 `json:"rate_per_unit,omitempty"`
	OpeningStock  *int     `json:"opening_stock,omitempty"`
	Receipt       *int     `json:"receipt,omitempty"`       // New stock received
	Total         *int     `json:"total,omitempty"`         // Opening + Receipt
	ClosingStock  *int     `json:"closing_stock,omitempty"` // Total - Sale
	RowNumber     int      `json:"row_number"`
	// PageNumber is the 1-based source-image index this item came from. Set
	// server-side in the image loop (NOT from the AI output) so per-page
	// validators can scope checks correctly and the Flutter review UI can
	// group rows under page headers. Replaces the prior row_number*1000 math
	// hack that fused page and row into one field and broke per-page logic.
	PageNumber    int      `json:"page_number,omitempty"`
	Confidence    float64  `json:"confidence"`
	RawText       string   `json:"raw_text"`  // Raw handwritten text before AI normalization
	// v1.0.131 — IsZeroQuantity flags rows with quantity == 0 that were
	// preserved through the extraction pipeline (instead of dropped via the
	// pre-v1.0.131 prefilter). Drives downstream "AI may have missed qty"
	// chip + apply-time filter. Mirrors SmartSaleExtractedItem.IsZeroQuantity.
	IsZeroQuantity bool   `json:"is_zero_quantity,omitempty"`
	// v1.0.131 — Source tags how this row was produced inside the OCR pipeline.
	// "main" (initial pass), "vote" (added by self-consistency vote pass),
	// "recovery" (gap-based recovery pass), "page_rescue" (full-page handwritten
	// rescue when actual<70% of expected). Carried through to SmartSaleExtractedItem.Source
	// for Flutter chip rendering.
	Source         string `json:"source,omitempty"`
	// v1.0.131 — FieldConfidence is per-cell confidence (brand, quantity, sale,
	// rate, amount, opening, closing). Populated by Claude natively; voting
	// pass writes 0.95 on agreement / 0.55 on disagreement. Spread to
	// SmartSaleExtractedItem.FieldConfidence in validateExtractedData so the
	// Flutter amber-underline UI can pinpoint which column the AI was unsure
	// about.
	FieldConfidence map[string]float64 `json:"field_confidence,omitempty"`
	// v1.0.138 — Warnings is per-row natural-language flags raised by the
	// extractor that the Flutter review screen turns into amber chips. Set
	// by the sheet-grid pipeline on rows that need operator confirmation
	// (e.g. "ai-sale-math-disagree", "addon-unresolved", "triple_disagreement").
	// Carried through to SmartSaleExtractedItem.Warnings. Distinct from
	// the page-level coverage_summary warnings.
	Warnings []string `json:"warnings,omitempty"`
	// v1.0.168 — MatchedProductIDHint is set by the alias-cascade pre-matcher
	// when an EXACT-source alias resolves a product. The downstream matcher
	// honors this hint by skipping its own search loop and assigning this
	// product directly. Pollution-guard etc. doesn't apply because the alias
	// was operator-confirmed. nil = no hint, run the normal matcher.
	MatchedProductIDHint string `json:"matched_product_id_hint,omitempty"`
	// v1.0.168 — MatchedProductIDHintSource records which alias tier produced
	// the hint ("shop_exact", "tenant_exact", "shop_fuzzy", "tenant_fuzzy").
	// Logged for diagnostics + audit. Empty when hint not set.
	MatchedProductIDHintSource string `json:"matched_product_id_hint_source,omitempty"`
	// v1.0.183 Track C — per-row invariant doubts surfaced by the extractor's
	// math-gate. Each doubt is a violation of one of the five sales-register
	// invariants (Sale ≤ effective_opening, Closing == effective_opening etc.)
	// where the system either auto-fixed (rule recorded with AutoFixed=true)
	// or wants the operator to resolve via the C2 doubt-popup queue. Empty on
	// rows that satisfy every invariant.
	CellDoubts []CellDoubt `json:"cell_doubts,omitempty"`
}

// CellDoubt is one suspicion the math-gate has about a single cell on a row.
// See textract_pipeline.go applyInvariantGate for the rule definitions and
// smart_sale_screen.dart _DoubtQueueModal for the operator-facing flow.
type CellDoubt struct {
	Field      string  `json:"field"`                // sale | closing | opening | rate | row_missing
	Rule       string  `json:"rule"`                 // sale_gt_supply | close_gt_supply | no_change_but_sale | sale_does_not_balance | missing_sale | ai_missed_row
	AIValue    *int    `json:"ai_value,omitempty"`   // what AI extracted (nil = blank)
	Suggested  *int    `json:"suggested,omitempty"`  // arithmetic-derived value (nil when system can't suggest)
	Confidence float64 `json:"confidence"`           // 0-1 confidence in Suggested
	HumanText  string  `json:"human_text"`           // operator-facing one-liner
	AutoFixed  bool    `json:"auto_fixed,omitempty"` // true when extractor wrote Suggested into the row (no popup needed)
}

// ReceiptExtractionResult represents the complete extraction result
type ReceiptExtractionResult struct {
	Items          []ExtractedReceiptItem `json:"items"`
	ReceiptNumber  *string                `json:"receipt_number,omitempty"`
	ReceiptDate    *string                `json:"receipt_date,omitempty"`
	VendorName     *string                `json:"vendor_name,omitempty"`
	ShopName       *string                `json:"shop_name,omitempty"`       // Shop name from register header
	PageSize       *string                `json:"page_size,omitempty"`       // Size category from header (e.g., "375ML", "180ML")
	PageSizeML     int                    `json:"page_size_ml,omitempty"`    // Normalized size in ML
	TotalAmount    *float64               `json:"total_amount,omitempty"`
	ProcessingTime int                    `json:"processing_time_ms"`
	RawText        string                 `json:"raw_text"`
	// v1.0.131 — RowCountOnPage is the AI-reported count of every visible
	// numbered row line on this page (including blanks/zero-qty rows the AI
	// couldn't read). Page-level field, NOT per-item. Drives the page-rescue
	// gate (smart_sale_service.go): if actual extracted < 70% of this
	// expected count AND avg confidence < 0.85, re-extract via
	// ExtractHandwrittenBand(1, RowCountOnPage). PARITY:
	// smart_stock_setup_ocr.go uses the same field on Stock Setup result.
	RowCountOnPage int                    `json:"row_count_on_page,omitempty"`
	// v1.0.306 — pre-filter per-page stats so the caller can detect a
	// "page collapsed" condition (Textract returned 2 rows where the page
	// has 20+ rows) and dispatch a Gemini per-page rescue BEFORE the
	// global qty=0 filter strips the evidence.
	PerPageStats []ExtractionPageStats `json:"per_page_stats,omitempty"`
}

// ExtractionPageStats — pre-filter per-page provenance from the Textract
// pipeline. Populated by extractWithTextract; consumed by smart_sale_service
// to drive per-page rescue and the page-incomplete warning.
type ExtractionPageStats struct {
	PageNumber             int  `json:"page_number"`
	RawRowCount            int  `json:"raw_row_count"`              // rows out of runTextractPage (header/total/blank-stripped)
	MaxRowNumber           int  `json:"max_row_number"`             // highest RowNumber any row had on this page
	PostFilterRowCount     int  `json:"post_filter_row_count"`      // rows that survived the qty=0 filter
	SuspiciousBrandCount   int  `json:"suspicious_brand_count"`     // all-digit / super-short brand rows
	LayoutDetected         bool `json:"layout_detected,omitempty"`  // v1.0.316 — Textract header_detect succeeded on this page
	BlankSaleWithRateCount int  `json:"blank_sale_with_rate_count"` // v1.0.325 — rows where Textract said qty=0 but rate>0 (likely missed reads)
}

// NewGeminiOCRService creates a new Gemini OCR service
func NewGeminiOCRService(logger *logrus.Logger) (*GeminiOCRService, error) {
	// Get API key from multiple sources in order of preference
	var apiKey string

	// 1. Check environment variable first (highest priority)
	apiKey = os.Getenv("GEMINI_API_KEY")

	// 2. Try Docker-mounted path
	if apiKey == "" {
		dockerPath := "/app/credentials/gemini-api-key.txt"
		if keyBytes, err := os.ReadFile(dockerPath); err == nil {
			apiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	// 3. Try local development path
	if apiKey == "" {
		localPath := "./credentials/gemini-api-key.txt"
		if keyBytes, err := os.ReadFile(localPath); err == nil {
			apiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	// 4. Try absolute path for backward compatibility
	if apiKey == "" {
		absPath := "/Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor/credentials/gemini-api-key.txt"
		if keyBytes, err := os.ReadFile(absPath); err == nil {
			apiKey = strings.TrimSpace(string(keyBytes))
		}
	}

	if apiKey == "" {
		logger.Warn("Gemini API key not found, OCR will use fallback mode")
		logger.Info("To enable real AI extraction, provide API key via:")
		logger.Info("  1. GEMINI_API_KEY environment variable")
		logger.Info("  2. ./credentials/gemini-api-key.txt file")
		logger.Info("  3. Docker mount at /app/credentials/gemini-api-key.txt")
		return &GeminiOCRService{
			logger:         logger,
			sizeNormalizer: NewSizeNormalizer(),
		}, nil
	}

	// Create Gemini client
	ctx := context.Background()
	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		logger.Warnf("Failed to create Gemini client: %v, using fallback mode", err)
		return &GeminiOCRService{
			logger:         logger,
			sizeNormalizer: NewSizeNormalizer(),
		}, nil
	}

	logger.Info("Gemini OCR service initialized successfully")
	return &GeminiOCRService{
		client:         client,
		logger:         logger,
		sizeNormalizer: NewSizeNormalizer(),
	}, nil
}

// ExtractFromImage extracts liquor items from receipt image using Gemini
func (g *GeminiOCRService) ExtractFromImage(ctx context.Context, imageBytes []byte, imageType string) (*ReceiptExtractionResult, error) {
	startTime := time.Now()

	if g.client == nil {
		g.logger.Warn("Gemini client not available, using mock extraction")
		return g.mockExtraction(), nil
	}

	// Use Gemini 2.0 Flash for fast, cost-effective extraction
	model := g.client.GenerativeModel("gemini-2.5-flash")

	// Configure for JSON output
	model.ResponseMIMEType = "application/json"

	// Set temperature for deterministic output
	temp := float32(0.1)
	model.Temperature = &temp

	// Create the prompt for liquor receipt extraction
	prompt := g.createLiquorExtractionPrompt()

	// Prepare image data
	imageData := &genai.Blob{
		MIMEType: fmt.Sprintf("image/%s", imageType),
		Data:     imageBytes,
	}

	// Generate content
	resp, err := model.GenerateContent(ctx, genai.Text(prompt), imageData)
	if err != nil {
		g.logger.Errorf("Gemini API error: %v", err)
		return nil, fmt.Errorf("gemini extraction failed: %w", err)
	}

	// Parse response
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		g.logger.Warn("No response from Gemini, using mock data")
		return g.mockExtraction(), nil
	}

	// Extract text from response
	responseText := ""
	for _, part := range resp.Candidates[0].Content.Parts {
		if text, ok := part.(genai.Text); ok {
			responseText += string(text)
		}
	}

	// Parse JSON response
	var extractedData struct {
		Items          []ExtractedReceiptItem `json:"items"`
		ReceiptNumber  *string                `json:"receipt_number"`
		ReceiptDate    *string                `json:"receipt_date"`
		VendorName     *string                `json:"vendor_name"`
		TotalAmount    *float64               `json:"total_amount"`
		RawText        string                 `json:"raw_text"`
		RowCountOnPage int                    `json:"row_count_on_page"` // v1.0.131
	}

	if err := json.Unmarshal([]byte(responseText), &extractedData); err != nil {
		g.logger.Errorf("Failed to parse Gemini response: %v", err)
		g.logger.Debugf("Raw response: %s", responseText)
		return nil, fmt.Errorf("failed to parse extraction: %w", err)
	}

	// Normalize sizes and validate extracted data
	validItems := []ExtractedReceiptItem{}
	for i := range extractedData.Items {
		item := &extractedData.Items[i]

		// CRITICAL VALIDATION: Detect if closing_stock is actually Amount (price)
		if item.ClosingStock != nil && *item.ClosingStock > 10000 {
			g.logger.Warnf("Row %d (%s): Closing stock %d is > 10000, likely extracted Amount column! Attempting to fix...",
				item.RowNumber, item.Brand, *item.ClosingStock)

			// Try to fix: If we have opening_stock and quantity, calculate closing
			if item.OpeningStock != nil && item.Quantity > 0 {
				calculatedClosing := *item.OpeningStock - item.Quantity
				if calculatedClosing >= 0 && calculatedClosing < 10000 {
					g.logger.Infof("Row %d: Fixed closing stock: %d (was %d)", item.RowNumber, calculatedClosing, *item.ClosingStock)
					// Move the large value to price if not set
					if item.Price == nil {
						price := float64(*item.ClosingStock)
						item.Price = &price
					}
					item.ClosingStock = &calculatedClosing
				} else {
					// v1.0.56: Don't skip - keep item with nil stock value
					g.logger.Warnf("Row %d: Cannot fix closing stock, setting to nil but keeping item", item.RowNumber)
					item.ClosingStock = nil
				}
			} else {
				// v1.0.56: Don't skip - keep item with nil stock value
				g.logger.Warnf("Row %d: Insufficient data to fix closing stock, setting to nil but keeping item", item.RowNumber)
				item.ClosingStock = nil
			}
		}

		// Validate opening_stock is reasonable
		if item.OpeningStock != nil && *item.OpeningStock > 10000 {
			g.logger.Warnf("Row %d (%s): Opening stock %d is > 10000, likely wrong column extraction",
				item.RowNumber, item.Brand, *item.OpeningStock)
			// Set to nil rather than skipping - we can still use the item
			item.OpeningStock = nil
		}

		// ⭐ CRITICAL VALIDATION: Detect if rate_per_unit is actually Amount (price)
		if item.RatePerUnit != nil {
			rateValue := *item.RatePerUnit

			// Rate must be in realistic range for Indian liquor: ₹10-₹70000 per bottle
			// Values >70000 are almost always from the Amount column
			if rateValue > 70000 || rateValue < 10 {
				g.logger.Warnf("Row %d (%s): Rate %.2f is INVALID (must be 10-70000)! This is likely the Amount column, not Rate!",
					item.RowNumber, item.Brand, rateValue)

				// If rate is very large (>70000) and we don't have a price, this might be the Amount
				if rateValue > 70000 && item.Price == nil {
					g.logger.Infof("Row %d: Moving invalid rate %.2f to Price field", item.RowNumber, rateValue)
					item.Price = item.RatePerUnit
				}

				// Set rate to nil - it's incorrect
				item.RatePerUnit = nil
				g.logger.Infof("Row %d: Rate set to nil (was %.2f)", item.RowNumber, rateValue)
			} else {
				// Rate is in valid range (50-1000), TRUST Gemini extraction!
				// Only do cross-validation as a warning, don't reject the rate
				if item.Quantity > 0 && item.Price != nil {
					expectedPrice := rateValue * float64(item.Quantity)
					priceDiff := *item.Price - expectedPrice

					// Allow 20% tolerance or ₹200 difference (more lenient)
					tolerance := expectedPrice * 0.2
					if tolerance < 200 {
						tolerance = 200
					}

					if priceDiff < -tolerance || priceDiff > tolerance {
						// ⚠️ Log warning but KEEP the rate (user wants rates from OCR!)
						g.logger.Warnf("Row %d (%s): Rate cross-check warning: %.2f × %d = %.2f but extracted price is %.2f (diff: %.2f)",
							item.RowNumber, item.Brand, rateValue, item.Quantity, expectedPrice, *item.Price, priceDiff)
						g.logger.Infof("Row %d: Keeping rate %.2f despite cross-check mismatch (trusting Gemini extraction)", item.RowNumber, rateValue)
						// ✅ DO NOT set to nil - keep the rate!
					} else {
						g.logger.Debugf("Row %d (%s): Rate validation PASSED ✓ %.2f × %d ≈ %.2f",
							item.RowNumber, item.Brand, rateValue, item.Quantity, *item.Price)
					}
				} else {
					// No quantity or price to cross-validate, keep the rate as-is
					g.logger.Debugf("Row %d (%s): Rate %.2f accepted (no cross-validation data available)",
						item.RowNumber, item.Brand, rateValue)
				}
			}
		}

		// If size not detected, try to normalize from text
		if item.SizeML == 0 && item.SizeText != "" {
			ml, _ := g.sizeNormalizer.Normalize(item.SizeText, item.Category)
			item.SizeML = ml
		}

		// If category empty, try to detect from brand
		if item.Category == "" {
			item.Category = g.sizeNormalizer.detectCategory(item.Brand)
		}

		// Validate and calculate stock if available
		if item.OpeningStock != nil && item.Quantity > 0 {
			// Auto-calculate closing stock if not provided
			if item.ClosingStock == nil {
				// Assume this is a sales document (opening - sold = closing)
				closing := *item.OpeningStock - item.Quantity
				if closing >= 0 {
					item.ClosingStock = &closing
					g.logger.Debugf("Calculated closing stock for %s: %d - %d = %d",
						item.Brand, *item.OpeningStock, item.Quantity, closing)
				}
			} else {
				// Validate the calculation
				expectedClosing := *item.OpeningStock - item.Quantity
				if *item.ClosingStock != expectedClosing {
					// Check if it's a purchase document (opening + purchased = closing)
					expectedClosingPurchase := *item.OpeningStock + item.Quantity
					if *item.ClosingStock == expectedClosingPurchase {
						g.logger.Debugf("Detected purchase document for %s", item.Brand)
					} else {
						g.logger.Warnf("Stock calculation mismatch for %s: Opening=%d, Qty=%d, Closing=%d",
							item.Brand, *item.OpeningStock, item.Quantity, *item.ClosingStock)
					}
				}
			}
		}

		// Calculate total price if rate is available
		if item.RatePerUnit != nil && item.Quantity > 0 {
			calculatedPrice := *item.RatePerUnit * float64(item.Quantity)
			if item.Price == nil {
				item.Price = &calculatedPrice
			} else if *item.Price != calculatedPrice {
				// Log price mismatch for debugging
				g.logger.Warnf("Price mismatch for %s: Calculated=%.2f, Extracted=%.2f",
					item.Brand, calculatedPrice, *item.Price)
			}
		}

		// Set confidence based on data completeness
		if item.Confidence == 0 {
			item.Confidence = g.calculateConfidence(item)
		}

		// Add validated item to results
		validItems = append(validItems, *item)
	}

	processingTime := int(time.Since(startTime).Milliseconds())

	result := &ReceiptExtractionResult{
		Items:          validItems,
		ReceiptNumber:  extractedData.ReceiptNumber,
		ReceiptDate:    extractedData.ReceiptDate,
		VendorName:     extractedData.VendorName,
		TotalAmount:    extractedData.TotalAmount,
		ProcessingTime: processingTime,
		RawText:        extractedData.RawText,
		RowCountOnPage: extractedData.RowCountOnPage,
	}

	g.logger.Infof("Gemini extracted %d items (%d valid after validation), row_count_on_page=%d in %dms",
		len(extractedData.Items), len(validItems), extractedData.RowCountOnPage, processingTime)
	return result, nil
}

// ExtractRecoveryPass re-extracts an image with a gap-closing prompt when the
// main pass returned fewer rows than the register appears to contain.
// Mirrors OpenAIOCRService.ExtractRecoveryPass so the caller can swap vendors
// transparently. See the OpenAI variant for the full rationale; the short
// version: explicit "you returned X but should have ~Y" framing forces the
// model to re-scan trailing + handwritten rows instead of re-emitting the
// same truncated list.
func (g *GeminiOCRService) ExtractRecoveryPass(
	ctx context.Context,
	imageBytes []byte,
	imageType string,
	productNames []string,
	mainPassRows int,
	maxRowSeen int,
) (*ReceiptExtractionResult, error) {
	startTime := time.Now()
	if g.client == nil {
		return nil, fmt.Errorf("gemini client not available for recovery pass")
	}
	model := g.client.GenerativeModel("gemini-2.5-flash")
	model.ResponseMIMEType = "application/json"
	temp := float32(0.0)
	model.Temperature = &temp

	basePrompt := g.createLiquorExtractionPrompt()

	// Recovery preamble placed ahead of the base prompt so the model reads
	// the "you missed rows, find them" instruction first. Concrete counts
	// beat vague emphasis — the specific gap size is what makes the model
	// actually re-scan rather than re-emit the same truncated list.
	recoveryPreamble := fmt.Sprintf(`!! SECOND-PASS RECOVERY EXTRACTION — CRITICAL !!

A previous extraction pass returned only %d items from this page. The highest serial number that pass reported was %d, meaning the page should have approximately %d items. About %d rows are MISSING.

YOUR TASK: Find the missed rows. Focus attention on:
1. LAST 10-15 rows of the printed table — AI models commonly truncate trailing rows.
2. HANDWRITTEN additions below the pre-printed list (rows numbered 40, 41, 42...).
3. Rows with empty Sale cells — they are real products with quantity=0, not rows to skip.
4. Rows with smudged/slanted/faint brand names — they count.
5. Rows where the brand name wraps across two visual lines.

Return ALL items on the page (the server will merge and dedupe by row_number). Target count: approximately %d items.

Use row_number = in-page position matching the printed S.No exactly. Do NOT invent a new sequence.

All the base extraction rules below still apply.

---

%s`, mainPassRows, maxRowSeen, maxRowSeen, maxRowSeen-mainPassRows, maxRowSeen, basePrompt)

	imageData := &genai.Blob{
		MIMEType: fmt.Sprintf("image/%s", imageType),
		Data:     imageBytes,
	}
	g.logger.Infof("🔁 Gemini recovery-pass (main_pass=%d rows, expected≈%d)", mainPassRows, maxRowSeen)
	resp, err := model.GenerateContent(ctx, genai.Text(recoveryPreamble), imageData)
	if err != nil {
		return nil, fmt.Errorf("gemini recovery failed: %w", err)
	}
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no response from gemini recovery")
	}
	responseText := ""
	for _, part := range resp.Candidates[0].Content.Parts {
		if text, ok := part.(genai.Text); ok {
			responseText += string(text)
		}
	}
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
	if err := json.Unmarshal([]byte(responseText), &extractedData); err != nil {
		return nil, fmt.Errorf("parse gemini recovery: %w", err)
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
	processingTime := int(time.Since(startTime).Milliseconds())
	g.logger.Infof("✅ Gemini recovery extracted %d items (main pass had %d) in %dms",
		len(extractedData.Items), mainPassRows, processingTime)
	return &ReceiptExtractionResult{
		Items:          extractedData.Items,
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

// ExtractHandwrittenBand re-extracts a row range with a handwriting-specialized
// prompt. v1.0.131 — last-resort fallback when Claude + OpenAI both fail. Mirrors
// the OCR API in claude_ocr_service.go and openai_ocr_service.go so smart_sale_
// service.go's page-rescue gate can hop providers transparently.
// salvageTruncatedHandwrittenJSON tries to recover items from a Gemini
// response that ran out of tokens mid-array. Strategy: locate the items
// array opening, then walk balanced-brace objects forwards from there,
// stopping at the first unparseable trailing fragment. Returns
// (true, items) on any successful salvage, (false, nil) otherwise.
//
// v1.0.244 — chhotu's real Parchas hit this every 5-10 extractions; without
// salvage the whole handwritten band is dropped and the main extraction
// fills in zeros for missed rows, producing the "rubbish" the operator sees.
func salvageTruncatedHandwrittenJSON(raw string) (bool, []ExtractedReceiptItem) {
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSpace(raw)

	idx := strings.Index(raw, "\"items\"")
	if idx < 0 {
		return false, nil
	}
	open := strings.Index(raw[idx:], "[")
	if open < 0 {
		return false, nil
	}
	cursor := idx + open + 1

	var items []ExtractedReceiptItem
	for cursor < len(raw) {
		// Skip whitespace, commas, trailing closer.
		for cursor < len(raw) && (raw[cursor] == ' ' || raw[cursor] == '\n' || raw[cursor] == '\t' || raw[cursor] == ',' || raw[cursor] == '\r') {
			cursor++
		}
		if cursor >= len(raw) || raw[cursor] == ']' {
			break
		}
		if raw[cursor] != '{' {
			break // unexpected
		}
		// Walk balanced braces, respecting strings.
		depth := 0
		inStr := false
		escape := false
		start := cursor
		for cursor < len(raw) {
			ch := raw[cursor]
			if escape {
				escape = false
			} else if ch == '\\' && inStr {
				escape = true
			} else if ch == '"' {
				inStr = !inStr
			} else if !inStr {
				if ch == '{' {
					depth++
				} else if ch == '}' {
					depth--
					if depth == 0 {
						cursor++
						break
					}
				}
			}
			cursor++
		}
		if depth != 0 {
			break // truncated mid-object — stop here, what we have is good
		}
		objStr := raw[start:cursor]
		var item ExtractedReceiptItem
		if err := json.Unmarshal([]byte(objStr), &item); err != nil {
			break // malformed — stop salvage
		}
		items = append(items, item)
	}
	return len(items) > 0, items
}

func (g *GeminiOCRService) ExtractHandwrittenBand(
	ctx context.Context,
	imageBytes []byte,
	imageType string,
	productNames []string,
	fromRow, toRow int,
) (*ReceiptExtractionResult, error) {
	startTime := time.Now()
	if g.client == nil {
		return nil, fmt.Errorf("gemini client not available for handwritten-band")
	}
	if toRow < fromRow {
		return nil, fmt.Errorf("invalid range fromRow=%d toRow=%d", fromRow, toRow)
	}
	model := g.client.GenerativeModel("gemini-2.5-flash")
	model.ResponseMIMEType = "application/json"
	temp := float32(0.15)
	model.Temperature = &temp

	basePrompt := g.createLiquorExtractionPrompt()
	bandPreamble := fmt.Sprintf(`!! HANDWRITTEN-BAND PASS — CRITICAL !!

The page has rows numbered %d through %d. The main extraction pass MISSED a significant portion of these rows. Re-extract this page focusing on COMPLETENESS over speed.

ROW-LINE ANCHORING (CRITICAL):
- Walk the page TOP-TO-BOTTOM. For each numbered row line you can see — including ones with faint, smudged, partially-blank, or all-zero cells — emit one item.
- The S.No column is your anchor: rows are numbered %d, %d+1, ..., %d. Do not skip any.
- Set row_number to the in-page S.No exactly as printed/written.
- ZERO-QTY ROWS ARE VALID: emit them with quantity=0.

HANDWRITING-WINS RULE:
- If a row has BOTH printed text and handwritten text, the HANDWRITTEN string is the actual brand.
- Common handwritten abbreviations: 8PM, BP, RS (Royal Stag), MCD, JW, M2/MM (Magic Moments + flavor), VOV (Old Monk), B7.

RANGE SCOPE:
- Return ONLY items with row_number in the inclusive range [%d, %d].
- Set row_count_on_page to %d.

All the base extraction rules below still apply.

---

%s`, fromRow, toRow, fromRow, fromRow, toRow, fromRow, toRow, toRow-fromRow+1, basePrompt)

	imageData := &genai.Blob{
		MIMEType: fmt.Sprintf("image/%s", imageType),
		Data:     imageBytes,
	}
	g.logger.Infof("✍️  Gemini handwritten-band (rows [%d, %d])", fromRow, toRow)
	resp, err := model.GenerateContent(ctx, genai.Text(bandPreamble), imageData)
	if err != nil {
		return nil, fmt.Errorf("gemini handwritten-band failed: %w", err)
	}
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no response from gemini handwritten-band")
	}
	responseText := ""
	for _, part := range resp.Candidates[0].Content.Parts {
		if text, ok := part.(genai.Text); ok {
			responseText += string(text)
		}
	}
	var extractedData struct {
		Items          []ExtractedReceiptItem `json:"items"`
		PageSize       *string                `json:"page_size"`
		PageSizeML     int                    `json:"page_size_ml"`
		RowCountOnPage int                    `json:"row_count_on_page"`
	}
	if err := json.Unmarshal([]byte(responseText), &extractedData); err != nil {
		// v1.0.244 — Gemini 2.5 Flash sometimes truncates the JSON mid-row
		// when the output budget is hit (rows count > 30 or wide register).
		// Detect a truncated tail (no trailing `}` for the outer object) and
		// try a salvage: parse only the rows that were emitted cleanly so we
		// don't lose the entire pass. If even that fails, fall through and
		// log — the main extraction rows are preserved upstream regardless.
		if salvaged, items := salvageTruncatedHandwrittenJSON(responseText); salvaged {
			extractedData.Items = items
			g.logger.Warnf("Gemini handwritten-band JSON truncated; salvaged %d clean items (was full parse error: %v)", len(items), err)
		} else {
			g.logger.Errorf("Gemini handwritten-band JSON truncated AND unsalvageable; dropping this pass (rows [%d,%d]): %v", fromRow, toRow, err)
			return nil, fmt.Errorf("parse gemini handwritten-band: %w", err)
		}
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
	processingTime := int(time.Since(startTime).Milliseconds())
	g.logger.Infof("✅ Gemini handwritten-band returned %d items for rows [%d, %d] in %dms",
		len(filtered), fromRow, toRow, processingTime)
	return &ReceiptExtractionResult{
		Items:          filtered,
		PageSize:       extractedData.PageSize,
		PageSizeML:     extractedData.PageSizeML,
		RowCountOnPage: extractedData.RowCountOnPage,
		ProcessingTime: processingTime,
	}, nil
}

// createLiquorExtractionPrompt creates a specialized prompt for liquor receipt extraction
func (g *GeminiOCRService) createLiquorExtractionPrompt() string {
	return `Analyze this INDIAN LIQUOR STORE stock/sales document and extract all items in JSON format with CRITICAL ACCURACY.

**🚨 CRITICAL: INDIAN LIQUOR SHOP FORMAT RECOGNITION**
This is an INDIAN liquor shop daily stock register with a SPECIFIC column structure:

**EXACT COLUMN ORDER** (left to right):
1. **S.No** - Serial number (1, 2, 3...)
2. **Brand Name** - Product name (may be on multiple lines)
3. **Opening** - Opening stock units (typically 0-10000)
4. **Receipt** - New stock received (typically 0-5000)
5. **Total** - Opening + Receipt (auto-calculated)
6. **Sale** - Units sold today (typically 0-5000)
7. **Rate** - Price per unit in ₹ (typically 10-70000, NEVER >70000!) ⭐
8. **Amount** - Sale × Rate in ₹ (typically 500-500000) ⚠️ THIS IS PRICE, NOT STOCK!
9. **Closing** - Remaining stock = Total - Sale (typically 0-10000) ✅ THIS IS THE CRITICAL VALUE!

**⚠️ CRITICAL WARNING - COMMON AI MISTAKE:**
- **Amount** column contains LARGE numbers (10000+) because it's PRICE IN RUPEES
- **Closing** column contains numbers (0-10000) because it's BOTTLE COUNT
- **DO NOT** confuse Amount (price) with Closing Stock (bottles)!
- If you extract a value > 10000 as "closing_stock", YOU ARE EXTRACTING THE WRONG COLUMN!

**🎯 ROW-WISE EXTRACTION RULES:**
1. Text may be fragmented - reconstruct each row by grouping nearby text
2. Each row = ONE brand entry with 6-8 numbers
3. Numbers MUST be mapped to correct columns based on their VALUE RANGES:
   - Opening/Receipt/Total/Sale/Closing: **0-10000** (bottle counts)
   - **Rate: **10-70000** (SELLING PRICE PER BOTTLE - NEVER >70000!)** ⭐
   - Amount: **500-5000000** (total price = Sale × Rate)

**⭐ CRITICAL: ALWAYS EXTRACT THE RATE (SELLING PRICE)!**
The Rate column contains the selling price per bottle (e.g., ₹320, ₹150, ₹800, ₹5000).
This is a medium-range number (10-70000, NEVER >70000!) that appears BEFORE the Amount column.
**DO NOT skip this column! It is REQUIRED for inventory management.**
**If you extract a Rate > 70000, YOU ARE EXTRACTING THE AMOUNT COLUMN BY MISTAKE!**

**EXAMPLE FROM REAL DOCUMENT:**

Row 1: 8 PM. 750ml
Numbers: 240, 240, 62
Correct mapping:
- Opening: 240 bottles
- Receipt: (missing/0)
- Closing: 62 bottles (This is what we need!)
- Rate: (not visible in this row)

Row 2: Imperial Blue 750ml
Numbers: 74, 4, 320, 11280, 70
Correct mapping:
- Opening: 74 bottles
- Sale: 4 bottles
- **Rate: Rs 320 per bottle** ⭐ (THIS IS THE SELLING PRICE - EXTRACT THIS!)
- Amount: Rs 11,280 (4 x 320)
- Closing: 70 bottles (Extract this, NOT 11280!)

**VALIDATION RULES (MANDATORY):**
1. **closing_stock** MUST be 0-10000 (if > 10000, you extracted Amount by mistake!)
2. **rate_per_unit** MUST be 10-70000 (price per bottle, NEVER >70000!)
3. **price/amount** can be 500-5000000 (total price)
4. Closing ≈ Opening + Receipt - Sale (±5 tolerance)
5. Amount = Sale × Rate is for VERIFICATION ONLY. Read the Amount cell INDEPENDENTLY. If the Amount cell is blank/illegible/faded, output price=0 — never back-fill from Sale × Rate.
6. **If Rate > 70000, it's WRONG - you extracted Amount instead!**

**SIZE DETECTION:**
**Product categories:** Beer, Whiskey, Rum, Vodka, Wine, Brandy, Gin
**Standard sizes:**
- Quarter/Qtr/90ml/180ml → 180ml
- Half/375ml → 375ml
- Bottle/Full/750ml → 750ml
- Beer: 330ml, 500ml, 650ml
- If no size found, default to 750ml for spirits, 650ml for beer

**Common OCR Errors to Fix:**
- "O" vs "0": Check context (in numbers = 0)
- "|" vs "1" vs "I": Use context and position
- Spaces in numbers: "1 1 2 8 0" → 11280
- Missing separators in brand names: "ImperialBlue" → "Imperial Blue"

**BRAND NAME CLEANING:**
Fix common OCR errors:
- "8PM" / "8 P.M." / "8pm" → "8 PM"
- "Mc. Dowell" / "McDowell" → "McDowell's"
- "I Conik" / "Iconik" → "Iconic"
- "Altar Dark" → "Aftar Dark"
- "B7" → "B7 Whisky"
- Remove extra spaces and normalize

**ROW COUNT (CRITICAL — v1.0.131):** At the top of the JSON output, set "row_count_on_page" to the count of every numbered row line you can see on this page — including blank rows, rows where you couldn't read the brand, and zero-qty rows. This MUST be >= len(items[]). The server uses this as the rescue trigger threshold; if you under-report or omit it, missed-row recovery cannot fire.

**JSON OUTPUT FORMAT:**

{
  "items": [
    {
      "row_number": 1,
      "brand": "Imperial Blue",
      "category": "whiskey",
      "size_text": "750ml",
      "size_ml": 750,
      "opening_stock": 74,
      "quantity": 4,
      "rate_per_unit": 320.00,
      "price": 1280.00,
      "closing_stock": 70,
      "confidence": 0.95
    },
    {
      "row_number": 2,
      "brand": "8 PM",
      "category": "whiskey",
      "size_text": "750ml",
      "size_ml": 750,
      "opening_stock": 240,
      "quantity": 0,
      "closing_stock": 62,
      "confidence": 0.90
    }
  ],
  "row_count_on_page": 28,
  "receipt_number": null,
  "receipt_date": null,
  "vendor_name": null,
  "total_amount": null,
  "raw_text": "Extracted text"
}

**CRITICAL VALIDATION BEFORE RETURNING:**
For EACH item, verify:
1. ✅ closing_stock < 10000 (if >= 10000, you grabbed Amount column by mistake!)
2. ✅ rate_per_unit is 10-70000 or null
3. ✅ opening_stock < 10000 (if >= 10000, wrong column!)
4. ✅ quantity (sale) is 0-5000 (reasonable daily sales)
5. ✅ IF price > 10000, it goes in "price" field, NOT "closing_stock"!

**STEP-BY-STEP PROCESS:**
1. **Identify rows**: Group text by spatial proximity (same Y-coordinate = same row)
2. **Extract all numbers** in each row in left-to-right order
3. **Map by value range**:
   - Small numbers (0-200): Stock counts (Opening, Sale, Closing)
   - **Medium numbers (100-2000): Rate (SELLING PRICE PER BOTTLE)** ⭐ ALWAYS EXTRACT!
   - Large numbers (1000+): Amount (total price)
4. **Rate extraction priority**: Look for a number between 100-2000 that appears:
   - After Sale column (quantity sold)
   - Before Amount column (total price)
   - This is the SELLING PRICE per bottle - CRITICAL data!
5. **Closing stock** = The LAST small number (0-200) in the row, OR Opening - Sale
6. **Validate** all fields before adding to output
7. **Confidence**: 0.95 if all fields valid including Rate, 0.8 if Rate missing, 0.6 if suspicious values

**⚠️ FINAL CHECK**: If ANY item has closing_stock > 500, STOP and re-extract that row!

Extract now with PRECISION and VALIDATION:`
}

// calculateConfidence estimates confidence based on data completeness
func (g *GeminiOCRService) calculateConfidence(item *ExtractedReceiptItem) float64 {
	confidence := 0.5 // Base confidence

	// Brand detected
	if item.Brand != "" && len(item.Brand) > 2 {
		confidence += 0.15
	}

	// Size detected and normalized
	if item.SizeML > 0 {
		confidence += 0.15
	}

	// Category detected
	if item.Category != "" {
		confidence += 0.1
	}

	// Quantity makes sense
	if item.Quantity > 0 && item.Quantity < 100 {
		confidence += 0.1
	}

	// Price/Rate available and consistent
	if item.RatePerUnit != nil && *item.RatePerUnit > 0 {
		confidence += 0.05
		// Check if total price matches rate * quantity
		if item.Price != nil {
			expectedPrice := *item.RatePerUnit * float64(item.Quantity)
			if *item.Price == expectedPrice {
				confidence += 0.05 // Bonus for consistency
			}
		}
	} else if item.Price != nil && *item.Price > 0 {
		confidence += 0.05
	}

	// Stock tracking data available and consistent
	if item.OpeningStock != nil && item.ClosingStock != nil {
		confidence += 0.05
		// Check stock calculation consistency
		expectedClosing := *item.OpeningStock - item.Quantity
		expectedClosingPurchase := *item.OpeningStock + item.Quantity
		if *item.ClosingStock == expectedClosing || *item.ClosingStock == expectedClosingPurchase {
			confidence += 0.05 // Bonus for valid calculation
		}
	}

	// Row number present (indicates structured extraction)
	if item.RowNumber > 0 {
		confidence += 0.05
	}

	// Cap at 1.0
	if confidence > 1.0 {
		confidence = 1.0
	}

	return confidence
}

// mockExtraction returns mock data for testing when Gemini is unavailable
func (g *GeminiOCRService) mockExtraction() *ReceiptExtractionResult {
	g.logger.Info("Using mock Gemini extraction (demo mode)")

	price1 := 1700.0
	price2 := 720.0
	price3 := 1200.0
	price4 := 900.0
	rate1 := 850.0
	rate2 := 120.0
	rate3 := 1200.0
	rate4 := 450.0
	opening1 := 10
	opening2 := 24
	opening3 := 5
	opening4 := 8
	closing1 := 8
	closing2 := 18
	closing3 := 4
	closing4 := 6
	total := 4520.0
	receiptNum := "STOCK-12345"
	receiptDate := "2025-10-25"
	vendor := "Liquor Pro Shop"

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
			{
				Brand:        "Kingfisher Premium",
				Category:     "beer",
				SizeText:     "650ml",
				SizeML:       650,
				Quantity:     6,
				Price:        &price2,
				RatePerUnit:  &rate2,
				OpeningStock: &opening2,
				ClosingStock: &closing2,
				RowNumber:    2,
				Confidence:   0.92,
			},
			{
				Brand:        "Black Label",
				Category:     "whiskey",
				SizeText:     "750ml",
				SizeML:       750,
				Quantity:     1,
				Price:        &price3,
				RatePerUnit:  &rate3,
				OpeningStock: &opening3,
				ClosingStock: &closing3,
				RowNumber:    3,
				Confidence:   0.90,
			},
			{
				Brand:        "100 Pipers",
				Category:     "whiskey",
				SizeText:     "375ml",
				SizeML:       375,
				Quantity:     2,
				Price:        &price4,
				RatePerUnit:  &rate4,
				OpeningStock: &opening4,
				ClosingStock: &closing4,
				RowNumber:    4,
				Confidence:   0.88,
			},
		},
		ReceiptNumber:  &receiptNum,
		ReceiptDate:    &receiptDate,
		VendorName:     &vendor,
		TotalAmount:    &total,
		ProcessingTime: 1200,
		RawText:        "LIQUOR PRO SHOP\nStock Report: STOCK-12345\nDate: 2025-10-25\n\nBrand | Opening | Sold | Rate | Total | Closing\nRoyal Stag 750ml | 10 | 2 | 850 | 1700 | 8\nKingfisher 650ml | 24 | 6 | 120 | 720 | 18\nBlack Label 750ml | 5 | 1 | 1200 | 1200 | 4\n100 Pipers 375ml | 8 | 2 | 450 | 900 | 6\n\nTotal: Rs 4520",
	}
}

// CleanedBrandResult represents the result of brand name cleanup
type CleanedBrandResult struct {
	CleanedName string `json:"cleaned_name"`
	SizeText    string `json:"size_text"`
	SizeML      int    `json:"size_ml"`
	Category    string `json:"category"`
	Confidence  float64 `json:"confidence"`
}

// CleanBrandName uses Gemini API to clean up OCR errors in brand names
func (g *GeminiOCRService) CleanBrandName(ctx context.Context, rawBrandText string) (*CleanedBrandResult, error) {
	if g.client == nil {
		g.logger.Warn("Gemini client not available for brand cleanup, returning original")
		return &CleanedBrandResult{
			CleanedName: rawBrandText,
			SizeText:    "750ml",
			SizeML:      750,
			Category:    "unknown",
			Confidence:  0.3,
		}, nil
	}

	// Use Gemini 2.0 Flash Experimental (fast, cost-effective, same as ExtractFromImage)
	model := g.client.GenerativeModel("gemini-2.5-flash")

	// Configure for JSON output
	model.ResponseMIMEType = "application/json"

	// Set temperature for deterministic output
	temp := float32(0.1)
	model.Temperature = &temp

	// Create cleanup prompt
	prompt := g.createBrandCleanupPrompt(rawBrandText)

	// Retry with exponential backoff for rate limiting
	maxRetries := 3
	baseDelay := 2 * time.Second

	var resp *genai.GenerateContentResponse
	var err error

	for attempt := 0; attempt <= maxRetries; attempt++ {
		resp, err = model.GenerateContent(ctx, genai.Text(prompt))

		if err == nil {
			break // Success!
		}

		// Check if it's a rate limit error
		errStr := err.Error()
		isRateLimit := strings.Contains(errStr, "429") ||
			strings.Contains(errStr, "quota") ||
			strings.Contains(errStr, "rate limit") ||
			strings.Contains(errStr, "Resource exhausted")

		if !isRateLimit || attempt == maxRetries {
			// Not a rate limit error, or final attempt failed
			g.logger.Errorf("Gemini brand cleanup error (attempt %d/%d): %v", attempt+1, maxRetries+1, err)
			return &CleanedBrandResult{
				CleanedName: rawBrandText,
				SizeText:    "750ml",
				SizeML:      750,
				Category:    "unknown",
				Confidence:  0.3,
			}, nil
		}

		// Rate limit hit - wait with exponential backoff
		delay := baseDelay * time.Duration(1<<uint(attempt))
		g.logger.Warnf("Rate limit hit for brand '%s', retrying in %v (attempt %d/%d)",
			rawBrandText, delay, attempt+1, maxRetries+1)
		time.Sleep(delay)
	}

	if err != nil {
		// All retries exhausted
		g.logger.Errorf("Gemini brand cleanup failed after %d retries: %v", maxRetries+1, err)
		return &CleanedBrandResult{
			CleanedName: rawBrandText,
			SizeText:    "750ml",
			SizeML:      750,
			Category:    "unknown",
			Confidence:  0.3,
		}, nil
	}

	// Parse response
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		g.logger.Warn("No response from Gemini for brand cleanup")
		return &CleanedBrandResult{
			CleanedName: rawBrandText,
			SizeText:    "750ml",
			SizeML:      750,
			Category:    "unknown",
			Confidence:  0.3,
		}, nil
	}

	// Extract text from response
	responseText := ""
	for _, part := range resp.Candidates[0].Content.Parts {
		if text, ok := part.(genai.Text); ok {
			responseText += string(text)
		}
	}

	// Parse JSON response
	var result CleanedBrandResult
	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		g.logger.Errorf("Failed to parse Gemini cleanup response: %v", err)
		g.logger.Debugf("Raw response: %s", responseText)
		return &CleanedBrandResult{
			CleanedName: rawBrandText,
			SizeText:    "750ml",
			SizeML:      750,
			Category:    "unknown",
			Confidence:  0.3,
		}, nil
	}

	g.logger.Debugf("Brand cleanup: '%s' -> '%s' (%s, %dml, %.2f confidence)",
		rawBrandText, result.CleanedName, result.Category, result.SizeML, result.Confidence)

	return &result, nil
}

// TableRow represents a single row extracted from a table structure
type TableRow struct {
	SerialNo     int      `json:"serial_no"`
	BrandName    string   `json:"brand_name"`
	SizeText     string   `json:"size_text"`
	Category     string   `json:"category"`       // Detected category (whiskey, rum, vodka, beer, gin)
	Subcategory  string   `json:"subcategory"`    // Detected subcategory (premium, normal)
	Opening      *int     `json:"opening_stock"`
	Receipt      *int     `json:"receipt"`
	Total        *int     `json:"total"`
	Sale         *int     `json:"sale"`
	Rate         *int     `json:"rate"`
	Amount       *int     `json:"amount"`
	Closing      *int     `json:"closing_stock"`
	Confidence   float64  `json:"confidence"`
}

// TableExtractionResult represents the complete table extraction
type TableExtractionResult struct {
	Rows           []TableRow `json:"rows"`
	TotalRows      int        `json:"total_rows"`
	ProcessingTime int        `json:"processing_time_ms"`
}

// ExtractTableStructure uses Gemini to intelligently extract ALL rows from table-structured OCR text
func (g *GeminiOCRService) ExtractTableStructure(ctx context.Context, rawOCRText string, categoryMapper *CategoryMapper) (*TableExtractionResult, error) {
	startTime := time.Now()

	if g.client == nil {
		g.logger.Warn("Gemini client not available for table extraction")
		return nil, fmt.Errorf("gemini client not initialized")
	}

	if rawOCRText == "" {
		return nil, fmt.Errorf("raw OCR text is empty")
	}

	// Use Gemini 2.0 Flash Experimental (fast, cost-effective, same as ExtractFromImage)
	model := g.client.GenerativeModel("gemini-2.5-flash")

	// Configure for JSON output
	model.ResponseMIMEType = "application/json"

	// Set temperature for deterministic output
	temp := float32(0.1)
	model.Temperature = &temp

	// Pre-process OCR text to improve extraction accuracy
	processedText := g.preprocessOCRText(rawOCRText)
	g.logger.Debugf("Pre-processed OCR text from %d to %d chars", len(rawOCRText), len(processedText))

	// Create the table extraction prompt with dynamic categories
	prompt := g.createTableExtractionPrompt(processedText, categoryMapper)

	// Retry with exponential backoff for rate limiting
	maxRetries := 3
	baseDelay := 2 * time.Second

	var resp *genai.GenerateContentResponse
	var err error

	for attempt := 0; attempt <= maxRetries; attempt++ {
		resp, err = model.GenerateContent(ctx, genai.Text(prompt))

		if err == nil {
			break // Success!
		}

		// Check if it's a rate limit error
		errStr := err.Error()
		isRateLimit := strings.Contains(errStr, "429") ||
			strings.Contains(errStr, "quota") ||
			strings.Contains(errStr, "rate limit") ||
			strings.Contains(errStr, "Resource exhausted")

		if !isRateLimit || attempt == maxRetries {
			// Not a rate limit error, or final attempt failed
			g.logger.Errorf("Gemini table extraction error (attempt %d/%d): %v", attempt+1, maxRetries+1, err)
			return nil, err
		}

		// Rate limit hit - wait with exponential backoff
		delay := baseDelay * time.Duration(1<<uint(attempt))
		g.logger.Warnf("Rate limit hit for table extraction, retrying in %v (attempt %d/%d)",
			delay, attempt+1, maxRetries+1)
		time.Sleep(delay)
	}

	if err != nil {
		// All retries exhausted
		g.logger.Errorf("Gemini table extraction failed after %d retries: %v", maxRetries+1, err)
		return nil, err
	}

	// Parse response
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		g.logger.Warn("No response from Gemini for table extraction")
		return nil, fmt.Errorf("no response from Gemini")
	}

	// Extract text from response
	responseText := ""
	for _, part := range resp.Candidates[0].Content.Parts {
		if text, ok := part.(genai.Text); ok {
			responseText += string(text)
		}
	}

	// Parse JSON response
	var result TableExtractionResult
	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		g.logger.Errorf("Failed to parse Gemini table extraction response: %v", err)
		g.logger.Debugf("Raw response: %s", responseText)
		return nil, fmt.Errorf("failed to parse extraction: %w", err)
	}

	result.ProcessingTime = int(time.Since(startTime).Milliseconds())
	result.TotalRows = len(result.Rows)

	g.logger.Infof("Gemini extracted %d table rows in %dms", result.TotalRows, result.ProcessingTime)
	return &result, nil
}

// createTableExtractionPrompt creates a specialized prompt for table structure extraction
func (g *GeminiOCRService) createTableExtractionPrompt(rawText string, categoryMapper *CategoryMapper) string {
	// Get dynamic category and subcategory text from database
	categoryText := categoryMapper.GetCategoryPromptText()
	subcategoryText := categoryMapper.GetSubcategoryPromptText()
	categoryList := categoryMapper.GetCategoryList()

	return fmt.Sprintf(`Parse this INDIAN LIQUOR SHOP stock register and extract ALL rows. The text is fragmented OCR output.

**OCR TEXT:**
%s

**INSTRUCTIONS:**

1. **DETECT BOTTLE SIZE** from header (first 3 lines):
   - "90 M.L" / "90ML" → 90ml
   - "180 M.L" / "180ML" / "QUARTER" / "QUATER" → 180ml
   - "375 M.L" / "HALF" → 375ml
   - "750 M.L" / "FULL" → 750ml
   - Default: 750ml
   - **ALL items use this SAME size**

2. **FIND ALL SERIAL NUMBERS** (1, 2, 3...):
   - Count them (e.g., see serials 1-10 = extract 10 rows)
   - **Extract EVERY row - don't stop early!**
   - **ENUMERATION CHECK**: If highest serial on the page is N, your output MUST contain approximately N items. If the S.No column runs from 1 to 38, you MUST output ~38 rows. A gap in serials means you skipped a row — re-scan.
   - **LAST-ROW EMPHASIS**: Pay EXTRA attention to rows 25, 26, 27, 28+ on dense pages. AI often truncates trailing rows. Before finalizing, verify the very last row of the printed table is in your output.
   - **HANDWRITTEN ADDITIONS**: Rows added by hand below the pre-printed list (numbered 40+) are REAL products — include them.
   - **ROW-NUMBER REPORTING**: Set the row_number field to the in-page position (1 for first row on THIS image). Each page/image starts fresh at 1. The server attaches page identity separately.
   - **COMPLETENESS SELF-CHECK**: Before returning, count the items in your output against the highest serial number. If the count is lower, you missed a row — STOP and rescan.

3. **FOR EACH ROW, extract:**
   - Serial number (S.No)
   - Brand name (after serial, BEFORE next serial)
   - Numbers in order: Opening, Receipt, Total, Sale, Rate, Amount, Closing
   - **Rate = medium number 10-70000 (SELLING PRICE per bottle)**
   - **Amount = large number >10000 (total price)**
   - **Closing = number <10000 at row end (bottles remaining)**

4. **CRITICAL VALIDATIONS:**
   - Closing < 10000 (if ≥10000, you grabbed Amount!)
   - Rate is 10-70000 (if >70000, you grabbed Amount!)
   - Opening < 10000
   - Extract Rate whenever visible (it's between Sale and Amount)

5. **IGNORE column header lines** like "Brand Name", "Opening", "Receipt", "Rate", "Closing"
   - Headers are NOT part of brand names
   - If you see "Royal Green + Royal Challenge Opening Receipt..." - you mixed header text into brand!

6. **CLEAN brand names:**
   - Remove foreign chars (ду, ୮, etc.)
   - Remove trailing numbers (3840, 43., etc.)
   - Fix: "8pm"→"8 PM", "I Conik"→"Iconic"

7. **📊 CATEGORY & SUBCATEGORY DETECTION:**
   For EACH brand, detect the product category and quality level based on the brand name:

   **Categories (main product types from SaaS system):**
%s

   **Subcategories (quality levels from SaaS system):**
%s

   **Detection Rules:**
   1. Match brand name to known brands listed above
   2. Use Rate (price) as secondary indicator for quality level
   3. Return lowercase category name from this list: %s
   4. Return lowercase subcategory if confident, or null if unsure
   5. If brand is not recognized, make best guess based on similar brands

**OUTPUT FORMAT:**
{
  "rows": [
    {
      "serial_no": 1,
      "brand_name": "8 PM Black",
      "size_text": "90ml",
      "category": "whiskey",
      "subcategory": "normal",
      "opening_stock": 90,
      "receipt": null,
      "total": null,
      "sale": 13,
      "rate": 90,
      "amount": 1170,
      "closing_stock": 27,
      "confidence": 0.85
    },
    {
      "serial_no": 2,
      "brand_name": "Royal Stag",
      "size_text": "90ml",
      "category": "whiskey",
      "subcategory": "premium",
      "opening_stock": null,
      "receipt": null,
      "total": null,
      "sale": 5,
      "rate": 90,
      "amount": null,
      "closing_stock": 40,
      "confidence": 0.75
    }
  ]
}

**BEFORE RETURNING - VERIFY:**
✅ Row count matches highest serial number seen?
✅ ALL closing_stock < 10000?
✅ ALL rate is 10-70000 or null?
✅ ALL size_text identical (from header)?
✅ NO brand names contain header words (Opening, Receipt, Closing)?
✅ ALL rows have category and subcategory detected?

Extract ALL rows now:`, rawText, categoryText, subcategoryText, categoryList)
}

// createBrandCleanupPrompt creates a prompt for cleaning brand names
func (g *GeminiOCRService) createBrandCleanupPrompt(rawBrandText string) string {
	return fmt.Sprintf(`You are an expert in Indian liquor brands. Clean up this OCR-extracted brand name and extract size information.

**Raw OCR Text:** "%s"

**Common OCR Errors in Indian Liquor Brand Names:**
1. **Foreign Characters**: Remove Cyrillic (ду, здо), Devanagari (২৫, ୮, ५०, ૨૧૯), Odia, Bengali, and other non-English characters
2. **Garbage Numbers**: Remove trailing numbers like "3840 19", "43.", "212", etc.
3. **Spacing Issues**: Fix "I Conik" → "Iconic", "8pm" → "8 PM"
4. **Common Brands**: Normalize to standard names:
   - "8 P.M." / "8pm" / "8 PM." → "8 PM"
   - "8 P.M. Black" / "8pm black" → "8 PM Black"
   - "Mc. Dowell" / "McDowell" → "McDowell's"
   - "I Conik" / "Iconik" → "Iconic"
   - "Altar Dark" / "Aftar" → "Aftar Dark"
   - "B7" → "B7 Whisky"
   - "Royal Stag" / "royal stag" → "Royal Stag"
   - "Imperial Blue" → "Imperial Blue"
   - "Blenders Pride" / "blenders pride" → "Blenders Pride"
   - "R.S. Barrel" / "r.s. barrel" → "RS Barrel"
   - "Signature" → "Signature"
   - "Antiquity Blue" → "Antiquity Blue"
   - "Black Dog" → "Black Dog"
   - "100 Piper" / "100 Pipers" → "100 Pipers"
   - "Golfer Short" → "Golfer Short"
   - "Royal Green" → "Royal Green"
   - "Royal Challenge" → "Royal Challenge"

**Size Detection:**
Extract size from the text if present:
- "750ml" / "750 ml" / "750" → 750ml (default for spirits)
- "375ml" / "375 ml" / "half" → 375ml
- "180ml" / "180 ml" / "quarter" → 180ml
- "90ml" / "90 ml" → 90ml
- "650ml" / "650 ml" → 650ml (common for beer)
- "330ml" / "330 ml" → 330ml (beer)
- "500ml" / "500 ml" → 500ml (beer)
- If no size detected, default to 750ml for spirits

**Category Detection:**
- Whiskey/Whisky: Royal Stag, Imperial Blue, 8 PM, McDowell's, Blenders Pride, Black Dog, 100 Pipers, Signature, Antiquity, RS Barrel, B7
- Rum: Old Monk, Bacardi, Captain Morgan
- Vodka: Magic Moments, Smirnoff, Absolute
- Beer: Kingfisher, Carlsberg, Budweiser, Heineken, Tuborg
- Brandy: Morpheus, Mansion House
- Gin: Bombay Sapphire, Tanqueray
- Wine: Sula, Fratelli

**Cleaning Rules:**
1. Remove ALL non-English characters (Cyrillic, Devanagari, Odia, Bengali, etc.)
2. Remove trailing/appended numbers that don't represent size
3. Capitalize properly (title case)
4. Standardize spacing
5. Extract size and remove from brand name
6. Return ONLY the clean brand name without size suffix

**Examples:**
- "royal stag ду" → "Royal Stag", 750ml, whiskey
- "8 pm. black ୮" → "8 PM Black", 750ml, whiskey
- "r.s. barrel здо" → "RS Barrel", 750ml, whiskey
- "blenders pride 3840 19" → "Blenders Pride", 750ml, whiskey
- "mc. dowell no. 1 43." → "McDowell's No 1", 750ml, whiskey
- "I Conik 750ml" → "Iconic", 750ml, whiskey
- "imperial blue 180ml ५०" → "Imperial Blue", 180ml, whiskey

**JSON Output Format:**
{
  "cleaned_name": "Cleaned brand name without size",
  "size_text": "750ml",
  "size_ml": 750,
  "category": "whiskey",
  "confidence": 0.95
}

**Confidence Scoring:**
- 0.95: Known brand, clear size, no OCR errors
- 0.80: Known brand, assumed default size
- 0.60: Unknown brand, cleaned text
- 0.40: Minimal cleanup possible

Clean this brand now:`, rawBrandText)
}

// preprocessOCRText cleans and prepares OCR text for better Gemini extraction
func (g *GeminiOCRService) preprocessOCRText(rawText string) string {
	// Step 1: Detect and separate header section (first 5 lines)
	lines := strings.Split(rawText, "\n")
	if len(lines) < 5 {
		return rawText // Too short, return as-is
	}

	g.logger.Debugf("Pre-processing %d lines of OCR text", len(lines))

	// Step 2: Identify header end (where serial numbers start)
	headerEnd := 0
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		// Look for first serial number (1, 2, 3...) or "S.No" header
		if strings.HasPrefix(trimmed, "1") || strings.HasPrefix(trimmed, "S.No") {
			headerEnd = i
			break
		}
		// Stop searching after 10 lines
		if i > 10 {
			break
		}
	}

	if headerEnd == 0 {
		headerEnd = 5 // Default: assume first 5 lines are header
	}

	g.logger.Debugf("Detected header section: lines 0-%d", headerEnd)

	// Step 3: Extract header (contains size info)
	headerText := strings.Join(lines[0:headerEnd], "\n")

	// Step 4: Extract body (data rows)
	bodyText := strings.Join(lines[headerEnd:], "\n")

	// Step 5: Group fragmented rows using serial numbers as anchors
	processedBody := g.groupRowsBySerialNumber(bodyText)

	// Step 6: Combine header + processed body with clear separator
	result := fmt.Sprintf("%s\n\n=== TABLE DATA ROWS ===\n%s", headerText, processedBody)

	g.logger.Debugf("Pre-processing complete: %d → %d chars", len(rawText), len(result))
	return result
}

// groupRowsBySerialNumber groups fragmented text by serial numbers
func (g *GeminiOCRService) groupRowsBySerialNumber(bodyText string) string {
	lines := strings.Split(bodyText, "\n")
	if len(lines) == 0 {
		return bodyText
	}

	var result []string
	currentRow := []string{}

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue // Skip empty lines
		}

		// Check if this is a serial number line
		isSerial := false
		if len(trimmed) <= 2 {
			// Could be a serial number (1-2 digits)
			for _, ch := range trimmed {
				if ch >= '0' && ch <= '9' {
					isSerial = true
				} else {
					isSerial = false
					break
				}
			}
		}

		if isSerial {
			// Start of new row - flush current row first
			if len(currentRow) > 0 {
				result = append(result, strings.Join(currentRow, " | "))
			}
			// Start new row with serial number
			currentRow = []string{trimmed}
		} else {
			// Continue current row
			currentRow = append(currentRow, trimmed)
		}
	}

	// Flush last row
	if len(currentRow) > 0 {
		result = append(result, strings.Join(currentRow, " | "))
	}

	g.logger.Debugf("Grouped %d lines into %d rows by serial numbers", len(lines), len(result))
	return strings.Join(result, "\n")
}

// ExtractFromImageDirectly uses Gemini Vision to extract data directly from image
// This is a fallback when text-based extraction fails
func (g *GeminiOCRService) ExtractFromImageDirectly(ctx context.Context, imageBytes []byte, imageType string, categoryMapper *CategoryMapper) (*TableExtractionResult, error) {
	startTime := time.Now()

	if g.client == nil {
		g.logger.Warn("Gemini client not available for direct image extraction")
		return nil, fmt.Errorf("gemini client not initialized")
	}

	g.logger.Info("🎨 Using Gemini Vision DIRECT image extraction (fallback mode)")

	// Use Gemini 2.0 Flash Experimental with vision
	model := g.client.GenerativeModel("gemini-2.5-flash")

	// Configure for JSON output
	model.ResponseMIMEType = "application/json"

	// Set temperature for deterministic output
	temp := float32(0.1)
	model.Temperature = &temp

	// Create visual extraction prompt with dynamic categories
	prompt := g.createVisionExtractionPrompt(categoryMapper)

	// Prepare image data
	imageData := &genai.Blob{
		MIMEType: fmt.Sprintf("image/%s", imageType),
		Data:     imageBytes,
	}

	// Generate content with image
	resp, err := model.GenerateContent(ctx, genai.Text(prompt), imageData)
	if err != nil {
		g.logger.Errorf("Gemini Vision direct extraction error: %v", err)
		return nil, fmt.Errorf("gemini vision extraction failed: %w", err)
	}

	// Parse response
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		g.logger.Warn("No response from Gemini Vision")
		return nil, fmt.Errorf("no response from Gemini Vision")
	}

	// Extract text from response
	responseText := ""
	for _, part := range resp.Candidates[0].Content.Parts {
		if text, ok := part.(genai.Text); ok {
			responseText += string(text)
		}
	}

	// Parse JSON response
	var result TableExtractionResult
	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		g.logger.Errorf("Failed to parse Gemini Vision response: %v", err)
		g.logger.Debugf("Raw response: %s", responseText)
		return nil, fmt.Errorf("failed to parse vision extraction: %w", err)
	}

	result.ProcessingTime = int(time.Since(startTime).Milliseconds())
	result.TotalRows = len(result.Rows)

	g.logger.Infof("✅ Gemini Vision extracted %d table rows in %dms", result.TotalRows, result.ProcessingTime)
	return &result, nil
}

// createVisionExtractionPrompt creates a prompt for Gemini Vision direct extraction
func (g *GeminiOCRService) createVisionExtractionPrompt(categoryMapper *CategoryMapper) string {
	// Get dynamic category and subcategory text from database
	categoryText := categoryMapper.GetCategoryPromptText()
	subcategoryText := categoryMapper.GetSubcategoryPromptText()
	categoryList := categoryMapper.GetCategoryList()

	return fmt.Sprintf(`You are analyzing a scanned INDIAN LIQUOR SHOP stock register IMAGE. Use your VISION to extract ALL rows from the table by analyzing the visual structure.

**🎯 v1.0.47 CRITICAL: USE VISUAL POSITION, NOT TEXT PARSING!**
This is a tabular document with visible grid lines. Look at the IMAGE structure - where columns are visually positioned.

**COLUMNS (left to right in the IMAGE):**
1. S.No - Serial number (visually leftmost, small numbers: 1, 2, 3...)
2. Brand Name - Product name (text column)
3. Opening - Opening stock (small numbers: 0-500)
4. Receipt - New stock received (small numbers: 0-100)
5. Total - Sum (Opening + Receipt, small numbers: 0-500)
6. Sale - Units sold (small numbers: 0-100)
7. **Rate - Price per bottle (50-1000) ⭐ CRITICAL - This column is VISUALLY between Sale and Amount!**
8. **Amount - Total price (Sale × Rate, LARGE numbers: 1000-50000) - Second-to-last column!**
9. **Closing - Remaining stock (0-500) ✅ MOST IMPORTANT - VISUALLY the LAST/RIGHTMOST column!**

**🔍 VISUAL DETECTION RULES:**
1. **Look at column POSITION in the image, not text order!**
2. **Closing stock** = The LAST/RIGHTMOST column with small numbers (0-500)
3. **Amount** = Second-to-last column with LARGE numbers (>1000)
4. **Rate** = Column BETWEEN Sale and Amount, medium numbers (50-1000)
5. **Use grid lines** to identify column boundaries
6. **If a number appears in the Closing position but is >500, it's WRONG - you're reading Amount column by mistake!**

**CRITICAL INSTRUCTIONS:**
1. **Extract EVERY row** - count serial numbers (1, 2, 3...) and extract that many rows
2. **Use visual position** to determine which column a number belongs to:
   - Numbers in LAST/RIGHTMOST column = Closing stock (0-500)
   - Numbers in second-to-last column = Amount (if >1000)
   - **Medium numbers (50-1000) in the column BEFORE Amount = Rate (CRITICAL!)**
   - Small numbers before Rate column = Sale/Quantity
3. **Detect bottle size** from header (90ml, 180ml, 375ml, 750ml) - ALL rows use SAME size
4. **Clean brand names** - remove foreign chars, trailing numbers, fix spacing

**⭐ CRITICAL RATE EXTRACTION (v1.0.47):**
- **Rate column is ALWAYS between Sale and Amount columns**
- **Look for numbers in range 50-1000 in this position**
- **If you see a number >1000 before Amount, it's WRONG - you're reading Amount twice!**
- **Rate is REQUIRED - extract it for EVERY row if visible**
- **Example: If you see "13 | 90 | 1170 | 27", then 90 is Rate, 1170 is Amount, 27 is Closing**

**📊 CATEGORY & SUBCATEGORY DETECTION:**
For EACH brand, detect the product category and quality level based on the brand name:

**Categories (main product types from SaaS system):**
%s

**Subcategories (quality levels from SaaS system):**
%s

**Detection Rules:**
1. Match brand name to known brands listed above
2. Use Rate (price) as secondary indicator for quality level
3. Return lowercase category name from this list: %s
4. Return lowercase subcategory if confident, or null if unsure
5. If brand is not recognized, make best guess based on similar brands

**VALIDATIONS:**
- Closing stock < 10000 (if ≥10000, wrong column!)
- Rate is 10-70000 (if >70000, wrong column!)
- Opening stock < 10000
- Amount ≥ 1000 (if present)
- **Rate × Sale ≈ Amount (cross-validation)**

**OUTPUT FORMAT:**
{
  "rows": [
    {
      "serial_no": 1,
      "brand_name": "8 PM Black",
      "size_text": "90ml",
      "category": "whiskey",
      "subcategory": "normal",
      "opening_stock": 90,
      "receipt": null,
      "total": null,
      "sale": 13,
      "rate": 90,
      "amount": 1170,
      "closing_stock": 27,
      "confidence": 0.90
    }
  ]
}

**🎨 USE YOUR VISION** to see the grid structure and extract data accurately. Look at where columns are VISUALLY positioned in the image - don't rely on text order!

**📍 PRIORITY ORDER:**
1. First, identify CLOSING (rightmost column with small numbers)
2. Then, identify AMOUNT (second-to-last with large numbers >1000)
3. Then, identify RATE (column between Sale and Amount, numbers 50-1000)
4. Detect CATEGORY from brand name (match to lists above)
5. Detect SUBCATEGORY from brand + price (premium if Rate >150 OR known premium brand)
6. Extract all other columns based on visual position

Extract ALL rows now with RATE and CATEGORY included:`, categoryText, subcategoryText, categoryList)
}

// Close closes the Gemini client
func (g *GeminiOCRService) Close() error {
	if g.client != nil {
		return g.client.Close()
	}
	return nil
}
