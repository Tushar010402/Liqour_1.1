package ocr

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

// 🔧 Phase 2.3: Cache entry for brand normalization with TTL
type brandCacheEntry struct {
	normalizedName string
	timestamp      time.Time
}

// GeminiClient handles interactions with Google Gemini API
type GeminiClient struct {
	apiKey          string
	httpClient      *http.Client
	baseURL         string
	brandCache      map[string]brandCacheEntry // 🔧 Phase 2.3: Normalization cache
	cacheMutex      sync.RWMutex               // 🔧 Phase 2.3: Thread-safe access
	cacheTTL        time.Duration              // 🔧 Phase 2.3: Cache lifetime (default: 1 hour)
}

// NewGeminiClient creates a new Gemini API client
func NewGeminiClient() *GeminiClient {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		fmt.Println("⚠️  GEMINI_API_KEY not set")
	}

	client := &GeminiClient{
		apiKey:  apiKey,
		baseURL: "https://generativelanguage.googleapis.com/v1beta",
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
		},
		brandCache: make(map[string]brandCacheEntry), // 🔧 Phase 2.3: Initialize cache
		cacheTTL:   1 * time.Hour,                     // 🔧 Phase 2.3: 1 hour TTL
	}

	// 🔧 Phase 2.3: Start cache cleanup goroutine
	go client.cleanupExpiredCache()

	return client
}

// 🔧 Phase 2.3: cleanupExpiredCache periodically removes expired cache entries
func (g *GeminiClient) cleanupExpiredCache() {
	ticker := time.NewTicker(15 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		g.cacheMutex.Lock()
		now := time.Now()
		removed := 0

		for key, entry := range g.brandCache {
			if now.Sub(entry.timestamp) > g.cacheTTL {
				delete(g.brandCache, key)
				removed++
			}
		}

		if removed > 0 {
			fmt.Printf("🧹 [Cache Cleanup] Removed %d expired entries (%d remaining)\n", removed, len(g.brandCache))
		}
		g.cacheMutex.Unlock()
	}
}

// ExtractedBrand represents a brand extracted and normalized by Gemini
// Phase 1: Enhanced with ALL 7 columns for comprehensive validation
type ExtractedBrand struct {
	OriginalText       string  `json:"original_text"`
	NormalizedName     string  `json:"normalized_name"`
	Size               string  `json:"size"`
	RowNumber          int     `json:"row_number"`           // Serial number from invoice

	// ===== COMPLETE ROW DATA (7 Columns) =====
	// Column 1: Opening Stock - Stock at start of day
	OpeningStock       int     `json:"opening_stock"`
	// Column 2: Receipt - New stock received during the day
	ReceiptQty         int     `json:"receipt_qty"`
	// Column 3: Total Stock = Opening + Receipt
	TotalStock         int     `json:"total_stock"`
	// Column 4: Sale Quantity - Number of bottles sold
	SaleQuantity       int     `json:"sale_quantity"`
	// Column 5: Rate/Selling Price per bottle (₹)
	Rate               float64 `json:"rate"`
	// Column 6: Amount = Sale × Rate
	Amount             float64 `json:"amount"`
	// Column 7: Closing Stock = Total - Sale
	ClosingStock       int     `json:"closing_stock"`

	// Legacy fields for backward compatibility
	Quantity           int     `json:"quantity"`             // Alias for ClosingStock
	Price              float64 `json:"price,omitempty"`      // Alias for Rate

	// ===== MATHEMATICAL VALIDATION FLAGS =====
	IsTotalValid       bool    `json:"is_total_valid"`       // Total == Opening + Receipt
	IsClosingValid     bool    `json:"is_closing_valid"`     // Closing == Total - Sale
	IsAmountValid      bool    `json:"is_amount_valid"`      // Amount == Sale × Rate
	MathValidationNotes string `json:"math_validation_notes,omitempty"`

	// ===== CONFIDENCE & VALIDATION =====
	Confidence         float64 `json:"confidence"`           // 0-100 overall confidence
	IsValidBrand       bool    `json:"is_valid_brand"`
	RejectionReason    string  `json:"rejection_reason,omitempty"`

	// ===== FIELD-LEVEL CONFIDENCE (Phase 4) =====
	FieldConfidences   *ExtractedFieldConfidences `json:"field_confidences,omitempty"`

	// ===== CATEGORY INFERENCE =====
	Category           string  `json:"category"`             // Whiskey, Vodka, Rum, Beer, etc.
	Subcategory        string  `json:"subcategory"`          // Premium, Normal, Economy, etc.
	CategoryConfidence float64 `json:"category_confidence"`  // 0-100
}

// ExtractedFieldConfidences holds confidence scores for each extracted field
type ExtractedFieldConfidences struct {
	Brand    float64 `json:"brand"`
	Opening  float64 `json:"opening"`
	Receipt  float64 `json:"receipt"`
	Total    float64 `json:"total"`
	Sale     float64 `json:"sale"`
	Rate     float64 `json:"rate"`
	Amount   float64 `json:"amount"`
	Closing  float64 `json:"closing"`
}

// GeminiRequest represents a request to Gemini API
type GeminiRequest struct {
	Contents []GeminiContent `json:"contents"`
}

type GeminiContent struct {
	Parts []GeminiPart `json:"parts"`
}

type GeminiPart struct {
	Text string `json:"text"`
}

// GeminiResponse represents a response from Gemini API
type GeminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
}

// ExtractAndNormalizeBrands uses Gemini to extract and normalize brand names from OCR text
func (g *GeminiClient) ExtractAndNormalizeBrands(ctx context.Context, rawText string) ([]ExtractedBrand, error) {
	if g.apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY not configured")
	}

	prompt := g.buildExtractionPrompt(rawText)

	// Call Gemini API
	responseText, err := g.callGeminiAPI(ctx, prompt)
	if err != nil {
		return nil, fmt.Errorf("gemini API call failed: %w", err)
	}

	// Parse the JSON response
	brands, err := g.parseExtractedBrands(responseText)
	if err != nil {
		return nil, fmt.Errorf("failed to parse Gemini response: %w", err)
	}

	return brands, nil
}

// NormalizeBrandName uses Gemini to normalize a single brand name with caching
// 🔧 Phase 2.3: Added in-memory cache to reduce API calls by ~70%
func (g *GeminiClient) NormalizeBrandName(ctx context.Context, brandText string) (string, error) {
	if g.apiKey == "" {
		return brandText, nil // Fallback to original if no API key
	}

	// Normalize the cache key (case-insensitive, trimmed)
	cacheKey := strings.ToLower(strings.TrimSpace(brandText))

	// 🔧 Phase 2.3: Check cache first (read lock)
	g.cacheMutex.RLock()
	if entry, found := g.brandCache[cacheKey]; found {
		// Check if entry is still valid
		if time.Since(entry.timestamp) <= g.cacheTTL {
			g.cacheMutex.RUnlock()
			fmt.Printf("   💨 [Cache HIT] '%s' → '%s' (saved API call)\n", brandText, entry.normalizedName)
			return entry.normalizedName, nil
		}
	}
	g.cacheMutex.RUnlock()

	// Cache miss - call Gemini API
	fmt.Printf("   🌐 [Cache MISS] '%s' - calling Gemini API\n", brandText)

	prompt := fmt.Sprintf(`You are an expert in Indian liquor brands.

Normalize this brand name to its standard, official name:
"%s"

Rules:
1. Fix OCR errors (e.g., "| Conik" → "Iconic", "8 P.M." → "8PM", "Mc. Dowell No. 1" → "McDowell's No.1")
2. Standardize punctuation and spacing
3. Use official brand spelling
4. Remove artifacts like pipes (|), extra spaces
5. Keep numbers and special characters that are part of the brand name
6. If it's clearly not a brand (like "Total", "Amount", pure numbers), return "INVALID"

Return ONLY the normalized brand name, nothing else.`, brandText)

	responseText, err := g.callGeminiAPI(ctx, prompt)
	if err != nil {
		return brandText, err // Fallback to original on error
	}

	normalized := strings.TrimSpace(responseText)
	if normalized == "INVALID" || normalized == "" {
		return "", fmt.Errorf("invalid brand name")
	}

	// 🔧 Phase 2.3: Store in cache (write lock)
	g.cacheMutex.Lock()
	g.brandCache[cacheKey] = brandCacheEntry{
		normalizedName: normalized,
		timestamp:      time.Now(),
	}
	cacheSize := len(g.brandCache)
	g.cacheMutex.Unlock()

	fmt.Printf("   ✅ [Cache STORE] '%s' → '%s' (cache size: %d)\n", brandText, normalized, cacheSize)

	return normalized, nil
}

// FindBrandMatches uses Gemini to find brand matches using its knowledge base
func (g *GeminiClient) FindBrandMatches(ctx context.Context, ocrBrandText string, availableBrands []string) ([]BrandMatch, error) {
	if g.apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY not configured")
	}

	// Build prompt with available brands
	brandsJSON, _ := json.Marshal(availableBrands)

	prompt := fmt.Sprintf(`You are an expert in Indian liquor brand matching.

OCR extracted this text: "%s"

Available brands in the database:
%s

Your task:
1. Identify what brand the OCR text refers to
2. Find the best match from the available brands
3. Rate your confidence (0-100)
4. Explain your reasoning

Consider:
- OCR errors (visual similarity: "| Conik" might be "Iconic")
- Common abbreviations ("Mc." for "Mc Dowell", "No.1" for "Number 1")
- Spacing and punctuation differences
- Partial matches
- Indian liquor brand knowledge

Respond in JSON format:
{
  "matches": [
    {
      "brand_name": "exact name from available brands",
      "confidence": 85,
      "reasoning": "why this is a good match"
    }
  ]
}

If no good match (confidence < 50), return empty matches array.`, ocrBrandText, string(brandsJSON))

	responseText, err := g.callGeminiAPI(ctx, prompt)
	if err != nil {
		return nil, err
	}

	matches, err := g.parseBrandMatches(responseText)
	if err != nil {
		return nil, fmt.Errorf("failed to parse matches: %w", err)
	}

	return matches, nil
}

// BrandMatch represents a brand match suggestion from Gemini
type BrandMatch struct {
	BrandName  string  `json:"brand_name"`
	Confidence float64 `json:"confidence"`
	Reasoning  string  `json:"reasoning"`
}

// buildExtractionPrompt creates a focused, concise prompt for brand extraction
// Phase 1: Enhanced to extract ALL 7 columns with mathematical validation
func (g *GeminiClient) buildExtractionPrompt(rawText string) string {
	return fmt.Sprintf(`Extract liquor brands from this Indian invoice OCR text (Kerala Beverage Corporation format).

RAW TEXT:
%s

📋 TABLE STRUCTURE - Complete 7-Column Format:
1. Serial No. - Sequential number (1, 2, 3...)
2. Brand Name - Liquor brand (text between serial and first number cluster)
3. Opening - Stock at start of day
4. Receipt - New stock received during the day
5. Total - Total stock (Opening + Receipt)
6. Sale - Number of bottles sold
7. Rate - Selling price per bottle (₹)
8. Amount - Total sale amount (Sale × Rate)
9. Closing - Stock at end of day (Total - Sale)

🎯 EXTRACTION GOAL: Extract ALL 7 numeric columns for each row
This enables mathematical validation and cross-checking with inventory.

📊 COLUMN RELATIONSHIPS (Mathematical Validation):
• Total = Opening + Receipt
• Closing = Total - Sale
• Amount = Sale × Rate

🎯 THREE COMMON FORMATS (by number count AFTER brand name):

FORMAT A: 7 numbers (MOST COMMON - Full columns)
[Opening] [Receipt] [Total] [Sale] [RATE] [Amount] [Closing]
    0         1        2       3      4       5         6
Example: "16 Blenders Pride 0 0 240 0 280 0 8"

FORMAT B: 5 numbers (COMPACT - No Opening/Receipt)
[Total] [Sale] [RATE] [Amount] [Closing]
   0      1       2       3         4
(Infer: Opening=Total, Receipt=0)

FORMAT C: 9 numbers (EXTENDED - Additional columns)
[Opening] [Receipt] [Total] [Sale] [RATE] [Amount] [Tax] [Final] [Closing]
(Extract core 7 columns, ignore extras)

🔑 KEY EXTRACTION RULES:

📌 WORKED EXAMPLES WITH COMPLETE DATA:

Example 1 - FORMAT A (7 numbers - MOST COMMON):
Row: "2 Royal Stag 40 0 40 12 97.5 1170 28"
Header: "90 M.L"
→ Numbers: [40, 0, 40, 12, 97.5, 1170, 28]
→ Opening=40, Receipt=0, Total=40, Sale=12, Rate=97.5, Amount=1170, Closing=28
→ Validation: Total(40) = Opening(40) + Receipt(0) ✓
→ Validation: Closing(28) = Total(40) - Sale(12) ✓
→ Validation: Amount(1170) = Sale(12) × Rate(97.5) ✓
{
  "original_text": "2 Royal Stag 40 0 40 12 97.5 1170 28",
  "normalized_name": "Royal Stag",
  "size": "90ml",
  "row_number": 2,
  "opening_stock": 40,
  "receipt_qty": 0,
  "total_stock": 40,
  "sale_quantity": 12,
  "rate": 97.5,
  "amount": 1170.0,
  "closing_stock": 28,
  "quantity": 28,
  "price": 97.5,
  "is_total_valid": true,
  "is_closing_valid": true,
  "is_amount_valid": true,
  "confidence": 98,
  "is_valid_brand": true,
  "category": "Whiskey",
  "subcategory": "Normal",
  "category_confidence": 100
}

Example 2 - FORMAT B (5 numbers - COMPACT):
Row: "5 Imperial Blue 20 8 320 2560 12"
Header: "180 M.L"
→ Numbers: [20, 8, 320, 2560, 12]
→ Total=20, Sale=8, Rate=320, Amount=2560, Closing=12
→ Infer: Opening=20, Receipt=0 (since no opening/receipt columns)
{
  "original_text": "5 Imperial Blue 20 8 320 2560 12",
  "normalized_name": "Imperial Blue",
  "size": "180ml",
  "row_number": 5,
  "opening_stock": 20,
  "receipt_qty": 0,
  "total_stock": 20,
  "sale_quantity": 8,
  "rate": 320.0,
  "amount": 2560.0,
  "closing_stock": 12,
  "quantity": 12,
  "price": 320.0,
  "is_total_valid": true,
  "is_closing_valid": true,
  "is_amount_valid": true,
  "confidence": 95,
  "is_valid_brand": true,
  "category": "Whiskey",
  "subcategory": "Normal",
  "category_confidence": 100
}

CRITICAL EXTRACTION RULES:
1. **Serial Number**: First number on each row (1, 2, 3, etc.)
2. **Brand Name** (MOST IMPORTANT - Prevent Merging):
   - Starts IMMEDIATELY after serial number
   - Ends BEFORE the first numeric data column
   - May contain: letters, spaces, dots, dashes, ampersands, numbers (if part of brand like "8PM", "100 Pipers")
   - MAXIMUM LENGTH: 5 words maximum (e.g., "Blenders Pride", "Royal Stag", "P.M. Black Royal Stag")
   - STOP at first number that represents stock/quantity data
   - Remove any trailing pipes, spaces, or garbage

   ⚠️  **PREVENT BRAND MERGING (CRITICAL):**
   - DO NOT combine two separate brands into one name
   - Example WRONG: "8 P.M. Black Royal Stag" (this is TWO brands: "8 P.M. Black" AND "Royal Stag" from different rows)
   - Each SERIAL NUMBER (1, 2, 3...) indicates a NEW row = NEW brand
   - If you see two known brand names together, they are on SEPARATE rows
   - Cross-reference with the common brands list below to identify individual brands
   - When in doubt, prefer shorter brand names (2-3 words) over longer ones
   - VALIDATE: After extracting each brand, check if it contains multiple known brands - if yes, it's WRONG

3. **Numeric Columns** (in order after brand name):
   - Opening (column 3)
   - Receipt (column 4)
   - Total (column 5)
   - Sale (column 6)
   - **Rate (column 7) - THIS IS THE SELLING PRICE PER BOTTLE (₹)**
   - Amount (column 8) - Total sale amount (Rate × Sale)
   - Closing (column 9)

4. **Size Extraction** (IMPORTANT - ALWAYS Use Header):
   - **ALWAYS** extract bottle size from the HEADER/TITLE of the receipt
   - Look for: "SALE RECEIPT - 90 M.L", "QUARTER", "HALF", "BOTTLE", "180 M.L", etc.
   - Common header formats:
     * "90 M.L" → "90ml"
     * "QUARTER" → "180ml"
     * "HALF" → "375ml"
     * "BOTTLE" → "750ml"
     * "120 M.L" → "120ml"
   - **Use this SAME size for ALL items in the receipt**
   - **The size is uniform for the entire invoice based on the header**

5. **Quantity**: Use "Closing" column (last column) as the current stock quantity

6. **Selling Price** (CRITICAL - Extract from Rate Column):

   The Rate column contains the **selling price per bottle in ₹ (Rupees)**.

   **STEP-BY-STEP PRICE EXTRACTION:**

   Step 1: **Isolate numbers after brand name**
   - After extracting brand name, collect all remaining numeric values in the row
   - Skip OCR errors like 'a', 'b', 'O', 'Q'
   - Example: "16 Blenders Pride 0 0 240 0 280 0 8" → Numbers: [0, 0, 240, 0, 280, 0, 8]

   Step 2: **Determine column format based on number count**

   **Format A: 7-9 numbers (STANDARD FORMAT - Most Common)**
   [Opening] [Receipt] [Total] [Sale] [RATE] [Amount] [Closing]
      0         1        2       3      4       5         6

   - **Position 4 = RATE = SELLING PRICE** ← **THIS IS THE PRICE!**
   - Position 6 (last) = Closing = Quantity
   - Example: [0, 0, 240, 0, 280, 0, 8] → Rate = 280 (Position 4), Quantity = 8 (Position 6)

   **Format B: 5-6 numbers (COMPACT FORMAT - No Opening/Receipt columns)**
   [Total] [Sale] [RATE] [Amount] [Closing]
     0       1      2       3         4

   - **Position 2 = RATE = SELLING PRICE** ← **THIS IS THE PRICE!**
   - Position 4 (last) = Closing = Quantity
   - Example: [20, 8, 320, 2560, 3] → Rate = 320 (Position 2), Quantity = 3 (Position 4)

   **Format C: 4 numbers or less (MINIMAL FORMAT - Rare)**
   [Sale] [RATE] [Amount] [Closing]
     0      1       2        3

   - **Position 1 = RATE = SELLING PRICE**
   - Position 3 (last) = Closing = Quantity

   Step 3: **Extract price based on format**

   Logic:
   - If number_count >= 7: price = Numbers[4] (Standard format)
   - If number_count == 5 or 6: price = Numbers[2] (Compact format)
   - If number_count == 4: price = Numbers[1] (Minimal format)
   - Otherwise: Use fallback heuristic

   Step 4: **Verify price is reasonable**
   - 90ml: ₹40-₹300 typical range
   - 180ml: ₹80-₹500 typical range
   - 375ml: ₹150-₹1000 typical range
   - 750ml: ₹300-₹3000 typical range
   - Premium brands can be much higher (₹2000+)

   **WORKED EXAMPLES BY FORMAT:**

   Example A1 (7 numbers, 180ml): "16 Blenders Pride 0 0 240 0 280 0 8"
     Numbers: [0, 0, 240, 0, 280, 0, 8] → Count: 7
     Format: STANDARD (7 numbers)
     Position 4 (Rate): 280 → **price = 280.0**
     Position 6 (Closing): 8 → **quantity = 8**
     ✓ Reasonable: ₹280 for 180ml ✓

   Example A2 (7 numbers, 90ml): "2 Royal Stag 40 0 0 12 97.5 1170 27"
     Numbers: [40, 0, 0, 12, 97.5, 1170, 27] → Count: 7
     Format: STANDARD (7 numbers)
     Position 4 (Rate): 97.5 → **price = 97.5**
     Position 6 (Closing): 27 → **quantity = 27**
     ✓ Reasonable: ₹97.50 for 90ml ✓
     ✓ Verification: Amount (1170) = Sale (12) × Rate (97.5) ✓

   Example B (5 numbers, 180ml): "5 Imperial Blue 20 8 320 2560 3"
     Numbers: [20, 8, 320, 2560, 3] → Count: 5
     Format: COMPACT (5 numbers)
     Position 2 (Rate): 320 → **price = 320.0**
     Position 4 (Closing): 3 → **quantity = 3**
     ✓ Reasonable: ₹320 for 180ml ✓
     ✓ Verification: Amount (2560) = Sale (8) × Rate (320) ✓

   **FALLBACK METHOD** (when format is unclear):
   - Calculate: **price = Amount ÷ Sale**
   - Amount is usually the 2nd largest number (largest is often Total)
   - Sale is usually a small-to-medium number
   - Only use this when position-based extraction fails

   **CRITICAL WARNINGS:**
   ⚠️  DO NOT use the LAST number as price - that's the Closing stock (quantity)!
   ⚠️  DO NOT confuse Total/Amount columns with Rate
   ⚠️  Rate is ALWAYS in the middle of the number sequence, NEVER at the end
   ⚠️  If extracted price seems too low (< ₹30) or too high (> ₹10000 for standard brands), recheck column positions

7. **Category & Subcategory Extraction** (NEW - IMPORTANT):

   Extract the category and subcategory for each liquor brand.

   **A. CATEGORY** (Based on Brand Knowledge):

   Use your knowledge of Indian liquor brands to determine the category:

   **Categories:**
   - "Whiskey" - IMFL whiskey brands
   - "Vodka" - Vodka brands
   - "Rum" - Rum brands
   - "Brandy" - Brandy brands
   - "Gin" - Gin brands
   - "Beer" - Beer brands
   - "Wine" - Wine brands
   - "Country Liquor" - Local/country liquor
   - "Other" - Unknown or other types

   **Common Brand Examples:**
   - **Whiskey**: Royal Stag, Royal Challenge, Royal Green, Blenders Pride, Imperial Blue, Officer's Choice, 8PM Black, McDowell's, Signature Premium, Black Dog, 100 Pipers, Black & White, Antiquity Blue, Rock Ford, Morpheus, Green Label
   - **Vodka**: Absolute Vodka, Smirnoff, Magic Moments, Romanov, White Mischief
   - **Rum**: Old Monk (Rum/Coffee), Bacardi (White/Black/Lemon), Captain Morgan, Hercules, Old Port
   - **Beer**: Kingfisher, Tuborg, Budweiser, Corona, Carlsberg
   - **Brandy**: Morpheus (sometimes brandy), Mansion House
   - **Wine**: Sula, Grover, Fratelli

   **B. SUBCATEGORY** (Based on Selling Price):

   Use the extracted **selling price** to determine the subcategory:

   **Subcategory by Price Range:**
   - **"Ultra Premium"**: ₹2000+ per bottle (premium imports, aged whiskeys)
   - **"Premium"**: ₹500-1999 per bottle (good quality, mid-range brands)
   - **"Normal"**: ₹100-499 per bottle (standard IMFL brands)
   - **"Economy"**: Below ₹100 per bottle (budget brands, country liquor)

   **Examples:**
   - Royal Stag @ ₹97.50 → Subcategory: "Normal"
   - R.S. Barrel @ ₹195.00 → Subcategory: "Normal"
   - Officer's Choice @ ₹65.00 → Subcategory: "Economy"
   - Signature Premium @ ₹120.00 → Subcategory: "Normal"
   - Johnnie Walker Blue @ ₹18000 → Subcategory: "Ultra Premium"
   - Black Dog @ ₹800 → Subcategory: "Premium"

   **C. CATEGORY CONFIDENCE** (Scoring):

   Rate your confidence in the category/subcategory assignment (0-100):
   - **95-100**: Well-known brand, clear category (e.g., "Royal Stag" → Whiskey)
   - **80-94**: Recognizable brand, confident category
   - **60-79**: Inferred category from brand name pattern
   - **40-59**: Uncertain, educated guess
   - **0-39**: Cannot determine, return "Other" for category

   **UPDATED JSON OUTPUT FORMAT:**
   Include the new fields: "category", "subcategory", "category_confidence"

BRAND NAME EXTRACTION EXAMPLES (from RAW unstructured text):

✅ CORRECT - Extract brand between serial number and first number cluster:
- "1 8 P.M. Black 0 0 0 0 90 0 0" → Brand: "8 P.M. Black"
- "2 Royal Stag 40 0 0 12 90 1170 27" → Brand: "Royal Stag"
- "P.M. Black 0 1 8 0 0 0 90 0 27 13" → Brand: "8 P.M. Black" (jumbled but identify by context)
- "27 13 90 1170 Royal Stag 40 0 0 0 90" → Brand: "Royal Stag" (highly jumbled - use position reasoning)
- "3 Royal Green 0 0 0 0 90 0 0" → Brand: "Royal Green"
- "Royal Challenge 30 0 30 b 0 195 5" → Brand: "Royal Challenge"
- "5 R.S. Barrel 10 0 0 5 195 0 5" → Brand: "R.S. Barrel"
- "Signature Premium 0 Q 6 0 O 0 0" → Brand: "Signature Premium"

❌ WRONG - Don't include data from other columns:
- "27 Royal Stag" ← WRONG (27 is closing stock, not part of name)
- "Royal Green 0 0" ← WRONG (0s are data columns)
- "Black Dog a 0" ← WRONG ('a' and '0' are data/garbage)

HEADER DETECTION:
Skip these rows (mark is_valid_brand=false):
- "SALE RECEIPT", "STOCK RECEIPT"
- "S.No.", "Brand Name", "Opening", "Receipt", "Total", "Sale", "Rate", "Amount", "Closing"
- "Shop Name", "Date", "Enter shop name"
- Pure numbers: "0", "90", "180"
- Single characters: "a", "o", "|"

COMMON INDIAN LIQUOR BRANDS (for validation):
Royal Stag, Royal Challenge, Royal Green, Blenders Pride, Blenders Blue, Imperial Blue, Black Dog, Officer's Choice, 8PM Black, 8 P.M. Black, Old Monk, Bacardi, Absolute Vodka, Signature, Signature Premium, 100 Pipers, Black & White, Morpheus, Antiquity, McDowell's, Rock Ford, R.S. Barrel

📊 OUTPUT JSON FORMAT - COMPLETE ROW DATA (no extra text):
{
  "brands": [
    {
      "original_text": "complete row text as found in OCR",
      "normalized_name": "ONLY the brand name, cleaned",
      "size": "90ml",
      "row_number": 1,
      "opening_stock": 40,
      "receipt_qty": 0,
      "total_stock": 40,
      "sale_quantity": 12,
      "rate": 97.5,
      "amount": 1170.0,
      "closing_stock": 28,
      "quantity": 28,
      "price": 97.5,
      "is_total_valid": true,
      "is_closing_valid": true,
      "is_amount_valid": true,
      "math_validation_notes": "",
      "confidence": 95,
      "is_valid_brand": true,
      "field_confidences": {
        "brand": 95,
        "opening": 90,
        "receipt": 90,
        "total": 90,
        "sale": 95,
        "rate": 98,
        "amount": 95,
        "closing": 92
      },
      "category": "Whiskey",
      "subcategory": "Normal",
      "category_confidence": 95
    }
  ]
}

⚠️ CRITICAL VALIDATION RULES FOR JSON OUTPUT:
1. **is_total_valid**: Set to true ONLY if Total == Opening + Receipt
2. **is_closing_valid**: Set to true ONLY if Closing == Total - Sale
3. **is_amount_valid**: Set to true ONLY if Amount == Sale × Rate (within ₹1 tolerance)
4. **math_validation_notes**: If any validation fails, explain the discrepancy
5. **field_confidences**: Score each field 0-100 based on OCR clarity

📊 FIELD CONFIDENCE SCORING:
- 95-100: Clear, unambiguous extraction
- 80-94: Confident but minor OCR artifacts
- 60-79: Some uncertainty, may need verification
- Below 60: Low confidence, flag for review

PARSING STRATEGY FOR RAW UNSTRUCTURED TEXT:
1. **First, extract size from the header**: Look for "SALE RECEIPT - 90 M.L", "QUATER", "180 M.L" or similar → extract "90ml", "180ml", "375ml"
2. **Identify rows**: Look for serial numbers (1, 2, 3...) OR known brand names to detect row boundaries
3. **Extract brand name intelligently**:
   - Look for text that appears BETWEEN serial number and clusters of numbers
   - Brand names contain letters, spaces, dots, dashes, ampersands
   - STOP at the first sequence of multiple numbers (stock data)
   - If text is jumbled (e.g., "P.M. Black 0 1 8"), use context to identify the brand ("8 P.M. Black")
4. **Extract numeric data**: Look for number sequences that match expected column count
   - Even if jumbled, try to identify: Opening, Receipt, Total, Sale, Rate, Amount, Closing
   - Closing stock is often the LAST number in a row
   - Sale amount (Amount column) is often a larger number (1170, 1440, etc.)
5. **Size determination**:
   - **ALWAYS** use the header size for ALL items (e.g., "90 M.L" means ALL items are 90ml)
   - Look for: "SALE RECEIPT - 90 M.L", "QUARTER" (180ml), "HALF" (375ml), "BOTTLE" (750ml)
   - The size is uniform for the entire invoice
6. **Quantity**: Use the last/rightmost number as closing stock (quantity)
7. **Price extraction** (USE DIRECT RATE COLUMN - See section 6 above):
   - After extracting brand, collect remaining numbers
   - For 7-9 numbers: **Position 4 = Rate = Selling Price per bottle**
   - Directly extract numbers[4] as the price
   - For ambiguous cases: Use fallback: price = Amount ÷ Sale
   - Example: [10, 0, 0, 0, 195, 0, 5] → Rate=195 (pos 4) → price=195.0
   - Example: [40, 0, 0, 12, 97.5, 1170, 27] → Rate=97.5 (pos 4) → price=97.5

KEY POINTS FOR HANDLING JUMBLED TEXT:
- **Be flexible**: Text may not follow perfect column structure due to OCR errors
- **Use context**: If you see "P.M. Black 0 1 8", recognize this as "8 P.M. Black" (serial 1, brand "8 P.M. Black")
- **Brand recognition**: Use the list of common Indian brands to validate extraction
- **Size from header**: ALWAYS extract size from header ("90 M.L", "QUARTER", "HALF", "BOTTLE") - uniform for entire invoice
- **Price from Rate column**: Extract Position 4 as selling price per bottle
- **Quantity is last number**: Closing stock typically appears at end of row
- **Ignore garbage**: Skip characters like 'a', 'b', 'Q', 'O' which are OCR errors

HANDLING JUMBLED EXAMPLES:
Input: "P.M. Black | 0 1 8 | 0 | 0 | 0 | 90 | 0 27 13 | 90 1170"
Analysis: Serial="1", Brand="8 P.M. Black" (recognize despite jumbling), Numbers after brand are data
Output: {"normalized_name": "8 P.M. Black", "size": "90ml", "quantity": 0}

Input: "27 13 | 90 1170 Royal Stag | 40 | 0 | 0 0 | 90"
Analysis: Brand="Royal Stag" appears in middle, identify by known brand list
Output: {"normalized_name": "Royal Stag", "size": "90ml", "quantity": 27}

REMEMBER: Use intelligent reasoning to identify brands even when text is jumbled or lacks pipe delimiters!`, rawText)
}

// callGeminiAPI makes a request to Gemini API with retry logic and rate limiting
func (g *GeminiClient) callGeminiAPI(ctx context.Context, prompt string) (string, error) {
	const maxRetries = 3
	const baseDelay = 1 * time.Second

	url := fmt.Sprintf("%s/models/gemini-2.0-flash:generateContent?key=%s", g.baseURL, g.apiKey)

	reqBody := GeminiRequest{
		Contents: []GeminiContent{
			{
				Parts: []GeminiPart{
					{Text: prompt},
				},
			},
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	var lastErr error
	for attempt := 1; attempt <= maxRetries; attempt++ {
		// Create new request for each attempt (can't reuse request body after first read)
		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
		if err != nil {
			return "", fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("Content-Type", "application/json")

		// Execute request
		resp, err := g.httpClient.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("request failed: %w", err)
			if attempt < maxRetries {
				delay := baseDelay * time.Duration(attempt)
				fmt.Printf("⚠️  [Gemini] Attempt %d/%d failed: %v, retrying in %v...\n", attempt, maxRetries, err, delay)
				time.Sleep(delay)
				continue
			}
			return "", lastErr
		}

		// Read response body
		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()

		if err != nil {
			lastErr = fmt.Errorf("failed to read response: %w", err)
			if attempt < maxRetries {
				delay := baseDelay * time.Duration(attempt)
				fmt.Printf("⚠️  [Gemini] Attempt %d/%d failed reading response, retrying in %v...\n", attempt, maxRetries, delay)
				time.Sleep(delay)
				continue
			}
			return "", lastErr
		}

		// Handle rate limiting (429) and server errors (5xx)
		if resp.StatusCode == 429 || resp.StatusCode >= 500 {
			lastErr = fmt.Errorf("gemini API error (status %d): %s", resp.StatusCode, string(body))
			if attempt < maxRetries {
				// Exponential backoff for rate limits
				delay := baseDelay * time.Duration(attempt*2)
				fmt.Printf("⚠️  [Gemini] Rate limit/server error (attempt %d/%d), retrying in %v...\n", attempt, maxRetries, delay)
				time.Sleep(delay)
				continue
			}
			return "", lastErr
		}

		// Other non-200 status codes are not retryable
		if resp.StatusCode != http.StatusOK {
			return "", fmt.Errorf("gemini API error (status %d): %s", resp.StatusCode, string(body))
		}

		// Parse successful response
		var geminiResp GeminiResponse
		if err := json.Unmarshal(body, &geminiResp); err != nil {
			return "", fmt.Errorf("failed to unmarshal response: %w", err)
		}

		// Validate response has content
		if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
			return "", fmt.Errorf("no response from Gemini (empty candidates)")
		}

		// Success!
		responseText := geminiResp.Candidates[0].Content.Parts[0].Text
		fmt.Printf("✅ [Gemini] API call successful (attempt %d/%d, response length: %d chars)\n", attempt, maxRetries, len(responseText))
		return responseText, nil
	}

	// All retries exhausted
	return "", fmt.Errorf("gemini API failed after %d attempts: %w", maxRetries, lastErr)
}

// 🔧 Phase 1.4: repairJSON attempts to fix common JSON malformation issues
func repairJSON(jsonStr string) string {
	// Make a copy for repair attempts
	repaired := jsonStr

	// Fix 1: Remove trailing commas before closing braces/brackets
	// Example: {"key": "value",} → {"key": "value"}
	trailingCommaRegex := regexp.MustCompile(`,(\s*[}\]])`)
	repaired = trailingCommaRegex.ReplaceAllString(repaired, "$1")

	// Fix 2: Remove duplicate commas
	// Example: "key": "value",, → "key": "value",
	duplicateCommaRegex := regexp.MustCompile(`,{2,}`)
	repaired = duplicateCommaRegex.ReplaceAllString(repaired, ",")

	// Fix 3: Fix missing commas between objects in arrays
	// Example: }{"brands" → },{"brands"
	missingCommaRegex := regexp.MustCompile(`}\s*{`)
	repaired = missingCommaRegex.ReplaceAllString(repaired, "},{")

	// Fix 4: Remove commas before colons (common OCR error)
	// Example: "key", : "value" → "key": "value"
	commaBeforeColonRegex := regexp.MustCompile(`,\s*:`)
	repaired = commaBeforeColonRegex.ReplaceAllString(repaired, ":")

	// Fix 5: Ensure proper spacing around colons
	// Example: "key" :"value" → "key": "value"
	colonSpacingRegex := regexp.MustCompile(`"\s*:\s*"`)
	repaired = colonSpacingRegex.ReplaceAllString(repaired, `": "`)

	// Fix 6: Remove any non-JSON characters before/after the main object
	// Example: Some text {"brands": [...]} more text → {"brands": [...]}
	trimmedRegex := regexp.MustCompile(`(?s)^[^{]*({.*})[^}]*$`)
	if matches := trimmedRegex.FindStringSubmatch(repaired); len(matches) > 1 {
		repaired = matches[1]
	}

	if repaired != jsonStr {
		fmt.Printf("🔧 [JSON Repair] Fixed malformed JSON\n")
		fmt.Printf("   Original length: %d chars\n", len(jsonStr))
		fmt.Printf("   Repaired length: %d chars\n", len(repaired))
	}

	return repaired
}

// parseExtractedBrands parses the Gemini response into ExtractedBrand structs
func (g *GeminiClient) parseExtractedBrands(responseText string) ([]ExtractedBrand, error) {
	// Extract JSON from markdown code blocks if present
	jsonStr := g.extractJSON(responseText)

	// 🔧 Phase 1.4: Apply JSON repair before parsing
	jsonStr = repairJSON(jsonStr)

	var response struct {
		Brands []ExtractedBrand `json:"brands"`
	}

	if err := json.Unmarshal([]byte(jsonStr), &response); err != nil {
		// If repair failed, log the problematic JSON for debugging
		fmt.Printf("❌ [JSON Parse] Failed even after repair. First 200 chars: %s\n",
			jsonStr[:min(200, len(jsonStr))])
		return nil, fmt.Errorf("failed to parse JSON: %w (response: %s)", err, jsonStr)
	}

	// Filter to only valid brands
	validBrands := make([]ExtractedBrand, 0)
	for _, brand := range response.Brands {
		if brand.IsValidBrand && brand.NormalizedName != "" {
			validBrands = append(validBrands, brand)
		}
	}

	return validBrands, nil
}

// parseBrandMatches parses the Gemini response into BrandMatch structs
func (g *GeminiClient) parseBrandMatches(responseText string) ([]BrandMatch, error) {
	jsonStr := g.extractJSON(responseText)

	// 🔧 Phase 1.4: Apply JSON repair before parsing
	jsonStr = repairJSON(jsonStr)

	var response struct {
		Matches []BrandMatch `json:"matches"`
	}

	if err := json.Unmarshal([]byte(jsonStr), &response); err != nil {
		fmt.Printf("❌ [JSON Parse] Failed to parse brand matches even after repair\n")
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	return response.Matches, nil
}

// extractJSON extracts JSON from markdown code blocks or returns the raw text
func (g *GeminiClient) extractJSON(text string) string {
	// Try to extract JSON from markdown code blocks
	jsonRegex := regexp.MustCompile("(?s)```(?:json)?\\s*({.*?})\\s*```")
	matches := jsonRegex.FindStringSubmatch(text)
	if len(matches) > 1 {
		return matches[1]
	}

	// If no code block, try to find JSON object directly
	jsonObjRegex := regexp.MustCompile("(?s)({\\s*\".*?})")
	matches = jsonObjRegex.FindStringSubmatch(text)
	if len(matches) > 1 {
		return matches[1]
	}

	// Return as-is if no JSON found
	return text
}

// ExtractTextFromImage uses Gemini Vision to extract text from an image
func (g *GeminiClient) ExtractTextFromImage(ctx context.Context, imageBase64 string) (string, error) {
	if g.apiKey == "" {
		return "", fmt.Errorf("GEMINI_API_KEY not configured")
	}

	// Use Gemini 2.0 Flash with vision capabilities (faster and more cost-effective)
	url := fmt.Sprintf("%s/models/gemini-2.0-flash:generateContent?key=%s", g.baseURL, g.apiKey)

	// Create request with image
	reqBody := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"parts": []map[string]interface{}{
					{
						"text": `You are an expert OCR system for reading SALE RECEIPT tables with liquor stock data.

🚨 CRITICAL LINE BREAK RULE 🚨
EVERY TABLE ROW MUST BE ON A SEPARATE LINE WITH A NEWLINE CHARACTER.
IF TEXT APPEARS JUMBLED, YOU MUST RECONSTRUCT IT WITH PROPER LINE BREAKS.

TABLE FORMAT (9 columns per row):
Serial | Brand Name | Opening | Receipt | Total | Sale | Rate | Amount | Closing

EXTRACTION RULES:
1. **MANDATORY NEWLINES**: Insert \n after EVERY row. No exceptions.
2. **ONE ROW PER LINE**: Each serial number starts a NEW LINE
3. **Preserve Row Integrity**: NEVER mix data from different rows
4. **Fix Jumbled Text**: If you see merged rows, split them at serial numbers
5. **Column Spacing**: Use spaces to separate columns within a row
6. **Sequential Order**: Extract rows in serial number order (1, 2, 3...)

EXAMPLE INPUT (what you see in image):
  1  8 P.M. Black      0   0   0   0   90    0      0
  2  Royal Stag       40   0   0  12   90  1170    27
  3  Royal Green       0   0   0   0   90    0      0

REQUIRED OUTPUT (one row per line):
  SALE RECEIPT -90 M.L
  S.No. Brand Name Opening Receipt Total Sale Rate Amount Closing
  1 8 P.M. Black 0 0 0 0 90 0 0
  2 Royal Stag 40 0 0 12 90 1170 27
  3 Royal Green 0 0 0 0 90 0 0

CRITICAL MISTAKES TO AVOID:
  WRONG: "27 Royal Stag 40 0 0 12" (mixing closing from row 2 with row 3)
  WRONG: "5 R.S. Barrel 5 0 10 0 120 Signature Premium" (mixing two rows)
  WRONG: "7 Blenders 11 0 0 Rock Ford" (mixing row 7 and row 8)

CORRECT: Each row complete and separate:
  2 Royal Stag 40 0 0 12 90 1170 27
  5 R.S. Barrel 0 0 0 5 90 0 5
  7 Blenders Pride 0 0 0 0 90 0 0

HANDLING JUMBLED TEXT:
If you see text like: "1 Royal Stag 40 0 0 12 90 1170 27 2 Blenders Pride 0 0 0 0 90 0 0"
YOU MUST split it into separate lines:
  1 Royal Stag 40 0 0 12 90 1170 27
  2 Blenders Pride 0 0 0 0 90 0 0

ROW IDENTIFICATION:
- Look for serial numbers (1, 2, 3...) - each one starts a NEW LINE
- When you see a new serial number, INSERT A NEWLINE before it
- Extract ALL columns for that row before moving to next serial number
- NEVER let two rows appear on the same line

BRAND NAME EXTRACTION:
- Brand name appears between serial number and first numeric column
- May contain letters, spaces, dots, dashes, numbers (like "8 P.M.")
- Keep brand name together - do not split across lines

OUTPUT FORMAT:
- First line: Header (SALE RECEIPT -90 M.L or similar)
- Second line: Column headers (S.No. Brand Name Opening Receipt...)
- Following lines: One data row per line, in serial number order
- Use spaces to separate columns
- NO explanations, ONLY the extracted table data`,
					},
					{
						"inline_data": map[string]string{
							"mime_type": "image/jpeg",
							"data":      imageBase64,
						},
					},
				},
			},
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := g.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("gemini API error (status %d): %s", resp.StatusCode, string(body))
	}

	var geminiResp GeminiResponse
	if err := json.Unmarshal(body, &geminiResp); err != nil {
		return "", fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("no response from Gemini")
	}

	return geminiResp.Candidates[0].Content.Parts[0].Text, nil
}

// BeerRegisterItem represents a single row from beer sales register
type BeerRegisterItem struct {
	RowNumber int     `json:"row_number"`
	Brand     string  `json:"brand"`
	Opening   int     `json:"opening"`
	Receipt   int     `json:"receipt"`
	Sale      int     `json:"sale"`
	Rate      float64 `json:"rate"`
	Amount    float64 `json:"amount"`
	Closing   int     `json:"closing"`
	Size      string  `json:"size"` // 650ML, 500ML, 330ML, etc.
	Section   string  `json:"section"` // Which section this belongs to
}

// BeerRegisterResponse represents the structured response from Gemini
type BeerRegisterResponse struct {
	Sections []struct {
		Name  string             `json:"name"`
		Items []BeerRegisterItem `json:"items"`
	} `json:"sections"`
	TotalRows int `json:"total_rows"`
}

// ExtractBeerRegister uses Gemini Vision to extract BEER SALES REGISTER with structured JSON output
func (g *GeminiClient) ExtractBeerRegister(ctx context.Context, imageBase64 string) (*BeerRegisterResponse, string, error) {
	if g.apiKey == "" {
		return nil, "", fmt.Errorf("GEMINI_API_KEY not configured")
	}

	url := fmt.Sprintf("%s/models/gemini-2.0-flash:generateContent?key=%s", g.baseURL, g.apiKey)

	reqBody := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"parts": []map[string]interface{}{
					{
						"text": `You are an expert OCR system for extracting data from BEER SALES REGISTER documents.

DOCUMENT TYPE: BEER SALES REGISTER
This document has multiple sections for different beer sizes (650ML, 500ML, 330ML, etc.)

TABLE COLUMNS (8 columns per row):
S.No | Brand Name | Opening | Receipt | Sale | Rate | Amount | Closing

IMPORTANT RULES:
1. Extract EVERY row from EVERY section - do not skip any items
2. Sections are typically: "STRONG BEER-650ML", "STRONG BEER-500ML", "PREMIUM BEER-330ML", etc.
3. "-" (dash) means 0 (zero) for numeric columns
4. Row numbers restart from 1 in each section
5. Include the section name for each item
6. Preserve exact brand names as written

RESPONSE FORMAT - Return ONLY valid JSON:
{
  "sections": [
    {
      "name": "STRONG BEER-650ML",
      "items": [
        {"row_number": 1, "brand": "KINGFISHER STRONG", "opening": 24, "receipt": 0, "sale": 5, "rate": 210.0, "amount": 1050.0, "closing": 19, "size": "650ML", "section": "STRONG BEER-650ML"},
        {"row_number": 2, "brand": "BUDWEISER MAGNUM", "opening": 12, "receipt": 0, "sale": 2, "rate": 220.0, "amount": 440.0, "closing": 10, "size": "650ML", "section": "STRONG BEER-650ML"}
      ]
    },
    {
      "name": "STRONG BEER-500ML",
      "items": [
        {"row_number": 1, "brand": "TUBORG STRONG", "opening": 48, "receipt": 0, "sale": 10, "rate": 175.0, "amount": 1750.0, "closing": 38, "size": "500ML", "section": "STRONG BEER-500ML"}
      ]
    }
  ],
  "total_rows": 3
}

EXTRACTION TIPS:
- Look carefully at each section header to identify the size (650ML, 500ML, 330ML)
- Count all rows in each section
- Common beer brands: KINGFISHER, BUDWEISER, TUBORG, CARLSBERG, HEINEKEN, CORONA, HOEGAARDEN, BRO CODE, ULTRA MAX
- If a cell shows "-", use 0 in the JSON
- Rate is typically 150-300 for beers
- Amount = Sale * Rate (verify if possible)
- Closing = Opening + Receipt - Sale (verify if possible)

CRITICAL: Extract ALL rows from ALL sections. Missing rows = failed extraction.
Return ONLY the JSON object, no markdown code blocks, no explanations.`,
					},
					{
						"inline_data": map[string]string{
							"mime_type": "image/jpeg",
							"data":      imageBase64,
						},
					},
				},
			},
		},
		"generationConfig": map[string]interface{}{
			"temperature":     0.1, // Low temperature for accuracy
			"maxOutputTokens": 8192,
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := g.httpClient.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("gemini API error (status %d): %s", resp.StatusCode, string(body))
	}

	var geminiResp GeminiResponse
	if err := json.Unmarshal(body, &geminiResp); err != nil {
		return nil, "", fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
		return nil, "", fmt.Errorf("no response from Gemini")
	}

	rawText := geminiResp.Candidates[0].Content.Parts[0].Text
	fmt.Printf("🍺 [Beer Register] Gemini raw response length: %d chars\n", len(rawText))

	// Clean the response - remove markdown code blocks if present
	cleanedText := strings.TrimSpace(rawText)
	if strings.HasPrefix(cleanedText, "```json") {
		cleanedText = strings.TrimPrefix(cleanedText, "```json")
		cleanedText = strings.TrimSuffix(cleanedText, "```")
		cleanedText = strings.TrimSpace(cleanedText)
	} else if strings.HasPrefix(cleanedText, "```") {
		cleanedText = strings.TrimPrefix(cleanedText, "```")
		cleanedText = strings.TrimSuffix(cleanedText, "```")
		cleanedText = strings.TrimSpace(cleanedText)
	}

	// Parse the JSON response
	var beerResp BeerRegisterResponse
	if err := json.Unmarshal([]byte(cleanedText), &beerResp); err != nil {
		fmt.Printf("⚠️ [Beer Register] Failed to parse JSON response: %v\n", err)
		fmt.Printf("   Raw text: %s\n", cleanedText[:min(500, len(cleanedText))])
		// Return raw text for fallback parsing
		return nil, rawText, nil
	}

	// Count total items
	totalItems := 0
	for _, section := range beerResp.Sections {
		totalItems += len(section.Items)
	}
	fmt.Printf("✅ [Beer Register] Extracted %d items from %d sections\n", totalItems, len(beerResp.Sections))

	return &beerResp, rawText, nil
}
