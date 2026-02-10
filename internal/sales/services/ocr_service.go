package services

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/pkg/ocr"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/logger"
	"github.com/liquorpro/go-backend/pkg/shared/websocket"
	"gorm.io/gorm"
)

// multiReceiptConfig holds settings for multi-receipt detection
type multiReceiptConfig struct {
	enableAutoDetection bool    // Enable automatic multi-receipt detection
	minItemsForSplit    int     // Minimum expected items to trigger detection
	detectionConfidence float64 // Minimum confidence to split (0-100)
}

// OCRService handles OCR processing logic
type OCRService struct {
	db                   *database.DB
	visionClient         *ocr.VisionClient
	geminiClient         *ocr.GeminiClient
	openaiClient         *OpenAIVisionClient    // OpenAI GPT-4o Vision (legacy)
	ollamaClient         *OllamaVisionClient    // Ollama local LLM (cost-free)
	providerManager      *OCRProviderManager    // Multi-provider manager with fallback
	columnDetector       *SmartColumnDetector   // Intelligent column detection
	rejectedItemsCache   sync.Map               // Temporary storage for rejected items per batch
	useOpenAI            bool                   // Flag to use OpenAI as primary extractor
	useOllama            bool                   // Flag to use Ollama as primary extractor
	receiptDetector      *ReceiptDetector       // Multi-receipt detection
	imageProcessor       *ocr.ImageProcessor    // Image cropping for multi-receipt
	rateCorrector        *RateCorrector         // Rate validation and correction
	extractionValidator  *ExtractionValidator   // Extraction completeness validation
	multiReceiptConfig   multiReceiptConfig     // Multi-receipt detection settings
}

// Text cleaning and preprocessing functions

// cleanOCRText removes common OCR artifacts and garbage from raw text
func cleanOCRText(text string) string {
	// Remove Devanagari numerals (Unicode range: U+0966 to U+096F)
	// These appear as: ०१२३४५६७८९
	devanagariRegex := regexp.MustCompile(`[०-९]+`)
	text = devanagariRegex.ReplaceAllString(text, "")

	// Remove other common Indic script numerals that might appear
	// Bengali: ০১২৩৪৫৬৭৮৯ (U+09E6 to U+09EF)
	bengaliRegex := regexp.MustCompile(`[০-৯]+`)
	text = bengaliRegex.ReplaceAllString(text, "")

	// Remove excessive whitespace and normalize
	text = regexp.MustCompile(`\s+`).ReplaceAllString(text, " ")

	// Remove common OCR artifacts
	text = strings.ReplaceAll(text, "| |", "|") // Double pipes
	text = strings.ReplaceAll(text, "||", "|")  // Adjacent pipes

	// Clean up pipe artifacts at edges
	text = strings.Trim(text, " |")

	return strings.TrimSpace(text)
}

// cleanBrandName removes trailing garbage from extracted brand names
// parseDashOrInt converts a string to int, treating dash "-" as 0
func parseDashOrInt(s string) int {
	s = strings.TrimSpace(s)
	if s == "-" || s == "" {
		return 0
	}
	val, _ := strconv.Atoi(s)
	return val
}

// parseDashOrFloat converts a string to float64, treating dash "-" as 0
func parseDashOrFloat(s string) float64 {
	s = strings.TrimSpace(s)
	if s == "-" || s == "" {
		return 0.0
	}
	val, _ := strconv.ParseFloat(s, 64)
	return val
}

// calculateSimilarity calculates the similarity between two strings using a combination of
// Levenshtein distance, word-level matching, and position weighting for better accuracy
func calculateSimilarity(s1, s2 string) float64 {
	if s1 == s2 {
		return 1.0
	}
	if len(s1) == 0 || len(s2) == 0 {
		return 0.0
	}

	// Combine character-level (Levenshtein) and word-level similarity
	// Uses levenshteinSimilarity from validation_service.go (same package)
	charSim := levenshteinSimilarity(s1, s2)
	wordSim := weightedWordSimilarity(s1, s2)

	// Weight: 40% character-level, 60% word-level (words are more meaningful for brands)
	return charSim*0.4 + wordSim*0.6
}

// weightedWordSimilarity calculates word-level similarity with position weighting
// First word is most important for brand names
func weightedWordSimilarity(s1, s2 string) float64 {
	words1 := strings.Fields(s1)
	words2 := strings.Fields(s2)

	if len(words1) == 0 || len(words2) == 0 {
		return 0.0
	}

	// Position weights: first word = 50%, rest distributed equally
	// This prevents "TUBORG STRONG" matching "KINGFISHER STRONG"
	firstWordWeight := 0.50
	remainingWeight := 0.50

	totalScore := 0.0
	totalWeight := 0.0

	// First word comparison (highest weight)
	// Uses levenshteinSimilarity from validation_service.go (same package)
	firstWordSim := levenshteinSimilarity(words1[0], words2[0])
	totalScore += firstWordSim * firstWordWeight
	totalWeight += firstWordWeight

	// Remaining words comparison
	if len(words1) > 1 || len(words2) > 1 {
		remainingWords1 := words1[1:]
		remainingWords2 := words2[1:]

		if len(remainingWords1) == 0 && len(remainingWords2) == 0 {
			// Both have only one word, done
		} else {
			// Count matching remaining words
			matches := 0
			maxRemaining := len(remainingWords1)
			if len(remainingWords2) > maxRemaining {
				maxRemaining = len(remainingWords2)
			}

			for _, w1 := range remainingWords1 {
				for _, w2 := range remainingWords2 {
					// Use Levenshtein for word matching (threshold 0.7)
					if levenshteinSimilarity(w1, w2) >= 0.7 {
						matches++
						break
					}
				}
			}

			if maxRemaining > 0 {
				remainingScore := float64(matches) / float64(maxRemaining)
				totalScore += remainingScore * remainingWeight
				totalWeight += remainingWeight
			}
		}
	}

	if totalWeight == 0 {
		return 0.0
	}

	return totalScore / totalWeight
}

func cleanBrandName(brandName string) string {
	// Remove Devanagari and other Indic numerals first
	devanagariRegex := regexp.MustCompile(`[०-९]+`)
	brandName = devanagariRegex.ReplaceAllString(brandName, "")

	bengaliRegex := regexp.MustCompile(`[০-৯]+`)
	brandName = bengaliRegex.ReplaceAllString(brandName, "")

	// Remove trailing numbers, pipes, and special characters
	// But preserve intentional numbers in brand names like "8 P.M.", "100 Pipers", "Old Monk 7"
	// These are at the START or middle of the name, not trailing
	words := strings.Fields(brandName)
	if len(words) > 0 {
		// Clean from the end, stop at first non-garbage word
		cleanWords := []string{}
		foundValidWord := false

		for i := len(words) - 1; i >= 0; i-- {
			word := words[i]

			// Check if this is garbage (pure numbers, pipes, single letters)
			isGarbage := false

			// Pure number?
			if _, err := regexp.MatchString(`^\d+$`, word); err == nil && regexp.MustCompile(`^\d+$`).MatchString(word) {
				isGarbage = true
			}

			// Pipe or single letter?
			if word == "|" || (len(word) == 1 && unicode.IsLower(rune(word[0]))) {
				isGarbage = true
			}

			// Period or dot?
			if word == "." || word == "0" {
				isGarbage = true
			}

			if !isGarbage {
				foundValidWord = true
			}

			// Once we found valid word, keep everything before it
			if foundValidWord {
				cleanWords = append([]string{word}, cleanWords...)
			}
		}

		if len(cleanWords) > 0 {
			brandName = strings.Join(cleanWords, " ")
		}
	}

	// Remove excessive whitespace
	brandName = regexp.MustCompile(`\s+`).ReplaceAllString(brandName, " ")

	return strings.TrimSpace(brandName)
}

// 🔧 Phase 1.5: truncateString truncates a string to maxLen and adds "..." if truncated
func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	if maxLen <= 3 {
		return s[:maxLen]
	}
	return s[:maxLen-3] + "..."
}

// detectMultipleBrands checks if a brand name contains multiple known brands merged together
func detectMultipleBrands(brandName string) (bool, string) {
	nameLower := strings.ToLower(brandName)

	// List of common Indian liquor brands (partial match patterns)
	knownBrands := []string{
		"royal stag", "royal challenge", "royal green", "royal reserve",
		"blenders pride", "imperial blue", "black dog", "black & white",
		"officer's choice", "officers choice", "8 p.m.", "8pm", "eight pm",
		"signature", "100 piper", "antiquity", "mcdo", "mc do", "old monk",
		"bacardi", "absolute", "absolut", "smirnoff", "magic moments",
		"morpheus", "mansion house", "honeybee", "honey bee",
		"r.s. barrel", "rs barrel", "peter scott", "bagpiper",
		"director special", "rock ford", "rockford",
	}

	foundBrands := []string{}

	// Check how many known brands appear in the name
	for _, knownBrand := range knownBrands {
		if strings.Contains(nameLower, knownBrand) {
			foundBrands = append(foundBrands, knownBrand)
		}
	}

	// If we found 2 or more distinct brands, it's likely a merge
	if len(foundBrands) >= 2 {
		return true, fmt.Sprintf("Contains multiple brands: %v", foundBrands)
	}

	return false, ""
}

// RejectionInfo contains details about why an item was rejected
type RejectionInfo struct {
	IsValid    bool
	Reason     string
	Stage      string
	CanRecover bool
}

// validateExtractedItemWithReason checks if an extracted item looks valid and returns detailed rejection info
func validateExtractedItemWithReason(item *models.OCRItem) RejectionInfo {
	// 🔧 Phase 1.5: Enhanced logging for all validation decisions

	if item == nil {
		fmt.Printf("🚫 [Validation] Item is nil\n")
		return RejectionInfo{false, "Item is null", "null_check", false}
	}

	// Brand name must exist and be reasonable length
	brandName := strings.TrimSpace(item.BrandText)
	if brandName == "" {
		fmt.Printf("🚫 [Validation] Empty brand name (row %d)\n", item.RowNumber)
		return RejectionInfo{false, "Empty brand name", "empty_brand", true}
	}

	if len(brandName) < 2 {
		fmt.Printf("🚫 [Validation] Brand name too short (%d chars): '%s'\n", len(brandName), brandName)
		return RejectionInfo{false, fmt.Sprintf("Brand name too short (%d characters)", len(brandName)), "length_check", true}
	}

	// Check if brand name is mostly numbers (garbage)
	digitCount := 0
	alphaCount := 0
	for _, char := range brandName {
		if unicode.IsDigit(char) {
			digitCount++
		} else if unicode.IsLetter(char) {
			alphaCount++
		}
	}

	// If more than 70% digits, it's probably garbage
	digitRatio := float64(digitCount) / float64(len(brandName))
	if len(brandName) > 0 && digitRatio > 0.7 {
		fmt.Printf("🚫 [Validation] Brand name mostly digits (%.0f%%): '%s'\n", digitRatio*100, brandName)
		return RejectionInfo{false, fmt.Sprintf("Brand name is %.0f%% digits (likely not a brand)", digitRatio*100), "digit_ratio", true}
	}

	// Must have at least some letters
	if alphaCount < 2 {
		fmt.Printf("🚫 [Validation] Insufficient letters (%d) in: '%s'\n", alphaCount, brandName)
		return RejectionInfo{false, fmt.Sprintf("Only %d letters found (minimum 2 required)", alphaCount), "letter_count", true}
	}

	// ✅ RELAXED: Allow up to 5 words for brand names to accommodate premium brands
	wordCount := len(strings.Fields(brandName))
	if wordCount > 5 {
		// Too many words - likely merged brand names or includes extra data
		fmt.Printf("🚫 [Validation] Brand name too long (%d words): '%s'\n", wordCount, brandName)
		return RejectionInfo{false, fmt.Sprintf("Brand has %d words (maximum 5 allowed)", wordCount), "word_limit", true}
	}

	// ⚠️  SOFTENED: Check for multiple brands but only warn, don't reject
	isMerged, reason := detectMultipleBrands(brandName)
	if isMerged {
		fmt.Printf("⚠️  [Validation] WARNING - Possible merged brands: '%s' - %s\n", brandName, reason)
		// Don't reject - let it through with lower confidence (handled elsewhere)
	}

	return RejectionInfo{true, "", "", false}
}

// validateExtractedItem checks if an extracted item looks valid (backward compatibility wrapper)
func validateExtractedItem(item *models.OCRItem) bool {
	result := validateExtractedItemWithReason(item)
	return result.IsValid
}

// validatePriceWithSize checks if a price looks reasonable for liquor based on bottle size
func validatePriceWithSize(price float64, sizeText, brandName string) (bool, string) {
	if price < 0 {
		return false, fmt.Sprintf("Negative price: ₹%.2f", price)
	}

	// Normalize size
	sizeLower := strings.ToLower(sizeText)
	var minPrice, maxPrice float64
	var sizeCategory string

	// Determine expected price range based on size
	if strings.Contains(sizeLower, "90") || strings.Contains(sizeLower, "nip") {
		sizeCategory = "90ml"
		minPrice = 40   // Minimum valid price for 90ml
		maxPrice = 300  // Maximum normal price for 90ml
	} else if strings.Contains(sizeLower, "180") || strings.Contains(sizeLower, "quarter") || strings.Contains(sizeLower, "quart") {
		sizeCategory = "180ml"
		minPrice = 80   // Minimum valid price for 180ml
		maxPrice = 500  // Maximum normal price for 180ml
	} else if strings.Contains(sizeLower, "375") || strings.Contains(sizeLower, "half") || strings.Contains(sizeLower, "pint") {
		sizeCategory = "375ml"
		minPrice = 150  // Minimum valid price for 375ml
		maxPrice = 1000 // Maximum normal price for 375ml
	} else if strings.Contains(sizeLower, "750") || strings.Contains(sizeLower, "bottle") || strings.Contains(sizeLower, "full") {
		sizeCategory = "750ml"
		minPrice = 300  // Minimum valid price for 750ml
		maxPrice = 3000 // Maximum normal price for 750ml
	} else {
		// Unknown size - use conservative ranges
		sizeCategory = "unknown"
		minPrice = 40
		maxPrice = 2000
	}

	// Check if price is too low
	if price > 0 && price < minPrice {
		return false, fmt.Sprintf("Price ₹%.2f too low for %s (expected ≥₹%.0f)", price, sizeCategory, minPrice)
	}

	// Check if price is too high (unless premium brand)
	if price > maxPrice {
		// Check if brand name suggests premium
		brandLower := strings.ToLower(brandName)
		premiumKeywords := []string{
			"johnnie walker blue", "johnnie walker black", "blue label", "black label",
			"chivas 18", "chivas 25", "macallan", "glenfiddich", "royal salute",
			"louis xiii", "hennessy xo", "remy martin", "glenlivet",
			"ballantine", "antiquity blue", "black dog triple",
		}

		isPremium := false
		for _, keyword := range premiumKeywords {
			if strings.Contains(brandLower, keyword) {
				isPremium = true
				break
			}
		}

		if !isPremium {
			return false, fmt.Sprintf("Price ₹%.2f too high for %s standard brand (expected ≤₹%.0f)", price, sizeCategory, maxPrice)
		}
	}

	return true, ""
}

// validatePrice checks if a price looks reasonable (legacy function, kept for compatibility)
func validatePrice(price float64, brandName string) (bool, string) {
	// Use generic validation without size information
	return validatePriceWithSize(price, "180ml", brandName) // Default to 180ml
}

// flagPriceAnomaly adds a warning flag to an item with suspicious pricing
func flagPriceAnomaly(item *models.OCRItem, reason string) {
	// Reduce confidence score
	if item.MatchConfidence != nil {
		reducedConfidence := math.Max(*item.MatchConfidence-25.0, 40.0)
		item.MatchConfidence = &reducedConfidence
	} else {
		lowConfidence := 40.0
		item.MatchConfidence = &lowConfidence
	}

	// Mark for review
	item.IsReviewed = false

	fmt.Printf("⚠️  [Price Validation] %s - Brand: '%s'\n", reason, item.BrandText)
}

// detectReceiptType detects the bottle size from raw text header
func detectReceiptType(rawText string) string {
	textLower := strings.ToLower(rawText)

	// 🔧 Phase 1.3: Fuzzy size detection with regex to handle OCR errors
	// Common OCR errors: 0→O, 1→l, space variations, case issues

	// 90ml patterns (handles: "90ml", "90 m.l", "9O ml", "9Oml", "nip")
	size90Patterns := []string{
		`9[0oO]\s*m[\.\s]*l`,  // 90ml, 9O ml, 9o m.l
		`nip`,                  // Common alias
	}
	for _, pattern := range size90Patterns {
		if matched, _ := regexp.MatchString(pattern, textLower); matched {
			fmt.Printf("🔧 [OCR] Fuzzy matched 90ml using pattern: %s\n", pattern)
			return "90ml"
		}
	}

	// 180ml patterns (handles: "180ml", "180 m.l", "18O ml", "l8Oml", "quarter")
	size180Patterns := []string{
		`[1l][8]\s*[0oO]\s*m[\.\s]*l`,  // 180ml, 18O ml, l8O m.l
		`quarter`,                        // Common alias
		`quart`,                          // Short form
	}
	for _, pattern := range size180Patterns {
		if matched, _ := regexp.MatchString(pattern, textLower); matched {
			fmt.Printf("🔧 [OCR] Fuzzy matched 180ml using pattern: %s\n", pattern)
			return "180ml"
		}
	}

	// 375ml patterns (handles: "375ml", "375 m.l", "37S ml", "half", "pint")
	size375Patterns := []string{
		`3[7][5sS]\s*m[\.\s]*l`,  // 375ml, 37S ml
		`half`,                    // Common alias
		`pint`,                    // Common alias
	}
	for _, pattern := range size375Patterns {
		if matched, _ := regexp.MatchString(pattern, textLower); matched {
			fmt.Printf("🔧 [OCR] Fuzzy matched 375ml using pattern: %s\n", pattern)
			return "375ml"
		}
	}

	// 750ml patterns (handles: "750ml", "750 m.l", "75O ml", "7SO ml", "bottle", "full")
	size750Patterns := []string{
		`[7][5sS][0oO]\s*m[\.\s]*l`,  // 750ml, 75O ml, 7SO ml
		`bottle`,                       // Common alias
		`full`,                         // Common alias
	}
	for _, pattern := range size750Patterns {
		if matched, _ := regexp.MatchString(pattern, textLower); matched {
			fmt.Printf("🔧 [OCR] Fuzzy matched 750ml using pattern: %s\n", pattern)
			return "750ml"
		}
	}

	// Default to 180ml (most common)
	fmt.Printf("⚠️  [OCR] No size pattern matched, defaulting to 180ml\n")
	return "180ml"
}

// detect180mlFormat determines if a 180ml invoice uses 7-column or compact format
// by analyzing the header structure
func detect180mlFormat(rawText string) string {
	textLower := strings.ToLower(rawText)
	lines := strings.Split(textLower, "\n")

	// Check for beer sales register format first (has dashes instead of zeros)
	if strings.Contains(textLower, "beer sales register") || strings.Contains(textLower, "beer sales") {
		return "beer"
	}

	// Check if text contains dashes as column separators (common in beer format)
	dashCount := strings.Count(rawText, " - ")
	if dashCount > 5 {
		return "beer"
	}

	// Look for header row with column names
	for _, line := range lines {
		// Check if this line contains common column headers
		if strings.Contains(line, "opening") || strings.Contains(line, "receipt") || strings.Contains(line, "brand") {
			// Check for 7-column format indicators
			hasOpening := strings.Contains(line, "opening")
			hasReceipt := strings.Contains(line, "receipt")
			hasTotal := strings.Contains(line, "total")

			// 7-column format: has Opening AND Receipt AND Total columns
			if hasOpening && hasReceipt && hasTotal {
				return "7-column"
			}

			// Compact format: has Total but missing Opening or Receipt
			if hasTotal && (!hasOpening || !hasReceipt) {
				return "compact"
			}
		}
	}

	// Default to 7-column (most common)
	return "7-column"
}

// getColumnMapping returns the expected column positions based on receipt type, number count, and format
func getColumnMapping(receiptType string, numCount int, invoiceFormat string) map[string]int {
	// For 180ml invoices, use format-aware mapping
	if receiptType == "180ml" && invoiceFormat == "compact" {
		// Compact 180ml format: Total, Sale, Rate, Amount, Closing (no Opening/Receipt)
		// Expected 5 numbers per row
		if numCount >= 5 {
			return map[string]int{
				"total":   0,
				"sale":    1,
				"rate":    2, // Rate at position 2 in compact format
				"amount":  3,
				"closing": 4,
			}
		}
	}

	// Standard 7-column structure (most common for all types including 180ml)
	if numCount >= 7 {
		return map[string]int{
			"opening": 0,
			"receipt": 1,
			"total":   2,
			"sale":    3,
			"rate":    4, // Rate at position 4 in standard 7-column
			"amount":  5,
			"closing": 6,
		}
	}

	// 6-column structure (missing one column, usually Receipt)
	if numCount == 6 {
		return map[string]int{
			"opening": 0,
			"total":   1,
			"sale":    2,
			"rate":    3, // RATE shifts left by 1
			"amount":  4,
			"closing": 5,
		}
	}

	// 5-column structure (compact format)
	if numCount == 5 {
		return map[string]int{
			"total":   0,
			"sale":    1,
			"rate":    2, // RATE shifts further left
			"amount":  3,
			"closing": 4,
		}
	}

	// Default to standard 7-column
	return map[string]int{
		"opening": 0,
		"receipt": 1,
		"total":   2,
		"sale":    3,
		"rate":    4,
		"amount":  5,
		"closing": 6,
	}
}

// 🔧 Phase 2.1: Refactored price calculation - broken into focused functions

// BrandRowMatch contains the result of finding a brand's row in raw text
type BrandRowMatch struct {
	Row        string
	MatchScore int
	Found      bool
}

// validatePriceRange checks if a price is reasonable for the given receipt type
func validatePriceRange(price float64, receiptType string) bool {
	switch receiptType {
	case "90ml":
		return price >= 40 && price <= 300
	case "180ml":
		return price >= 80 && price <= 500
	case "375ml":
		return price >= 150 && price <= 1000
	case "750ml":
		return price >= 300 && price <= 3000
	default:
		return price >= 50 && price <= 2000
	}
}

// 🔧 Phase 3.1: CrossFieldValidation validates consistency across multiple fields
type CrossFieldValidation struct {
	IsValid       bool
	Issues        []string
	WarningCount  int
	CriticalCount int
}

// validateCrossFields checks for consistency between Price, Sale, Amount, etc.
// 🔧 Phase 3.1: Detects calculation errors and inconsistencies
func validateCrossFields(brand *ocr.ExtractedBrand, detectedSize string) CrossFieldValidation {
	result := CrossFieldValidation{
		IsValid: true,
		Issues:  []string{},
	}

	// Validation 1: Price and quantity consistency
	if brand.Price > 0 && brand.Quantity > 0 {
		// Note: We're using Quantity field which might represent Sale quantity
		// expectedAmount := brand.Price * float64(brand.Quantity)
		// This would need Sale and Amount fields in ExtractedBrand to validate properly
		// For now, just validate that price exists when quantity exists

		if brand.Price < 10 {
			result.Issues = append(result.Issues, fmt.Sprintf("Price too low (₹%.2f) for quantity %d", brand.Price, brand.Quantity))
			result.WarningCount++
		}
	}

	// Validation 2: Size consistency - Gemini size should match detected header size
	if brand.Size != "" && detectedSize != "" && brand.Size != detectedSize {
		result.Issues = append(result.Issues, fmt.Sprintf("Size mismatch: item='%s' vs header='%s'", brand.Size, detectedSize))
		result.WarningCount++
	}

	// Validation 3: Quantity sanity check
	if brand.Quantity < 0 {
		result.Issues = append(result.Issues, fmt.Sprintf("Invalid negative quantity: %d", brand.Quantity))
		result.CriticalCount++
		result.IsValid = false
	} else if brand.Quantity > 1000 {
		result.Issues = append(result.Issues, fmt.Sprintf("CRITICAL: Quantity %d exceeds maximum allowed (1000 units) - likely OCR error", brand.Quantity))
		result.CriticalCount++
		result.IsValid = false
		fmt.Printf("🔴 [Validation] REJECTED: %s - Quantity %d > 1000 (stock anomaly prevented)\n", brand.NormalizedName, brand.Quantity)
	}

	// Validation 4: Price sanity check
	if brand.Price < 0 {
		result.Issues = append(result.Issues, fmt.Sprintf("Invalid negative price: ₹%.2f", brand.Price))
		result.CriticalCount++
		result.IsValid = false
	} else if brand.Price > 10000 {
		result.Issues = append(result.Issues, fmt.Sprintf("Suspiciously high price: ₹%.2f (possible OCR error)", brand.Price))
		result.WarningCount++
	}

	// Validation 5: Ensure size is one of the standard values if present
	if brand.Size != "" {
		standardSizes := map[string]bool{
			"90ml": true, "180ml": true, "375ml": true, "750ml": true,
			"1L": true, "1000ml": true,
		}
		if !standardSizes[brand.Size] {
			result.Issues = append(result.Issues, fmt.Sprintf("Non-standard size: '%s'", brand.Size))
			result.WarningCount++
		}
	}

	return result
}

// extractPriceFromRate extracts price directly from the rate column
func extractPriceFromRate(numbers []float64, receiptType string, columnMap map[string]int) (float64, bool) {
	ratePos := columnMap["rate"]

	if ratePos >= len(numbers) {
		return 0, false
	}

	rate := numbers[ratePos]
	if rate <= 0 {
		return 0, false
	}

	if !validatePriceRange(rate, receiptType) {
		fmt.Printf("   ⚠️  [Price Calc] Rate ₹%.2f at position %d outside range for %s\n", rate, ratePos, receiptType)
		return 0, false
	}

	rate = math.Round(rate*100) / 100
	fmt.Printf("   ✅ [Price Calc] Direct extraction - Rate column (Position %d): ₹%.2f\n", ratePos, rate)
	return rate, true
}

// extractPriceFromCalculation calculates price from Amount ÷ Sale
func extractPriceFromCalculation(numbers []float64, columnMap map[string]int) (float64, bool) {
	salePos := columnMap["sale"]
	amountPos := columnMap["amount"]

	if salePos >= len(numbers) || amountPos >= len(numbers) {
		return 0, false
	}

	sale := numbers[salePos]
	amount := numbers[amountPos]

	if sale <= 0 || amount <= 0 {
		return 0, false
	}

	price := amount / sale
	price = math.Round(price*100) / 100

	// Validate calculated price with increased upper limit for premium brands
	// Changed from ₹5,000 to ₹10,000 to support high-end bottles
	if price < 30 || price > 10000 {
		fmt.Printf("   ⚠️  [Price Calc] Calculated price ₹%.2f out of range (₹30-₹10,000), rejecting\n", price)
		return 0, false
	}

	fmt.Printf("   💰 [Price Calc] Fallback calculation: ₹%.2f = %.0f (Amount) ÷ %.0f (Sale)\n", price, amount, sale)
	return price, true
}

// 🔧 Phase 2.2: detectMergedRows finds and splits rows with multiple serial numbers
func detectMergedRows(line string) []string {
	// Pattern: Look for serial numbers (1-2 digits followed by dot or space, then brand name)
	// NOTE: Brand can start with letter OR digit (like "100 Pipers", "8 P.M.")
	serialPattern := regexp.MustCompile(`\b(\d{1,2})[\.\s]+([A-Za-z0-9])`)
	matches := serialPattern.FindAllStringIndex(line, -1)

	// If we find 2+ serial numbers, this is likely a merged row
	if len(matches) < 2 {
		return []string{line} // Single row, return as-is
	}

	fmt.Printf("   🔍 [Merged Rows] Found %d potential serial numbers in line\n", len(matches))

	// Split at each serial number position (except the first)
	rows := []string{}
	startIdx := 0

	for i, match := range matches {
		if i == 0 {
			continue // Skip first serial (it's the start of first row)
		}

		// Extract row from previous serial to this serial
		row := strings.TrimSpace(line[startIdx:match[0]])
		if row != "" {
			rows = append(rows, row)
			fmt.Printf("   ✂️  [Merged Rows] Split row #%d: %s\n", i, truncateString(row, 60))
		}
		startIdx = match[0]
	}

	// Add the last row (from last serial to end of line)
	lastRow := strings.TrimSpace(line[startIdx:])
	if lastRow != "" {
		rows = append(rows, lastRow)
		fmt.Printf("   ✂️  [Merged Rows] Split row #%d: %s\n", len(rows), truncateString(lastRow, 60))
	}

	if len(rows) > 1 {
		fmt.Printf("   ✅ [Merged Rows] Successfully split into %d rows\n", len(rows))
	}

	return rows
}

// findBrandRow locates the brand's row in raw text using fuzzy matching
func findBrandRow(rawText, brandOriginalText string) BrandRowMatch {
	lines := strings.Split(rawText, "\n")

	// 🔧 Phase 2.2: Apply merged row detection before matching
	expandedLines := []string{}
	for _, line := range lines {
		splitRows := detectMergedRows(line)
		expandedLines = append(expandedLines, splitRows...)
	}
	lines = expandedLines

	var targetRow string
	var serialNumber int
	bestMatchScore := 0

	// Try to find the line containing the brand original text
	brandTextNormalized := strings.ToLower(strings.TrimSpace(brandOriginalText))

	fmt.Printf("   🔍 [Row Match] Searching for brand: '%s' (searching %d lines)\n", brandOriginalText, len(lines))

	// Extract serial number from brand text if present
	serialPattern := regexp.MustCompile(`^(\d+)[\.\s]+(.+)`)
	if matches := serialPattern.FindStringSubmatch(brandOriginalText); len(matches) > 1 {
		serialNumber, _ = strconv.Atoi(matches[1])
		if matches[2] != "" {
			brandTextNormalized = strings.ToLower(strings.TrimSpace(matches[2]))
		}
		fmt.Printf("   🔍 [Row Match] Extracted S.No: %d, Brand: '%s'\n", serialNumber, brandTextNormalized)
	}

	// Split brand name into words for fuzzy matching
	brandWords := strings.Fields(brandTextNormalized)
	// Filter out common words that don't help matching
	significantWords := []string{}
	commonWords := map[string]bool{"whisky": true, "whiskey": true, "rum": true, "vodka": true, "gin": true, "brandy": true, "beer": true, "wine": true}
	for _, word := range brandWords {
		if len(word) >= 2 && !commonWords[word] {
			significantWords = append(significantWords, word)
		}
	}

	fmt.Printf("   🔍 [Row Match] Significant words to match: %v\n", significantWords)

	// Search for the best matching row using fuzzy word-based matching
	lineNumber := 0
	for _, line := range lines {
		lineNumber++
		lineNormalized := strings.ToLower(strings.TrimSpace(line))

		// Skip header lines and empty lines
		if lineNormalized == "" ||
		   strings.Contains(lineNormalized, "sl no") ||
		   strings.Contains(lineNormalized, "brand name") ||
		   strings.Contains(lineNormalized, "opening receipt") {
			continue
		}

		matchScore := 0
		matchReasons := []string{}

		// Method 1: Exact full brand text match (strongest)
		if strings.Contains(lineNormalized, brandTextNormalized) {
			matchScore += 15
			matchReasons = append(matchReasons, "exact-brand-match")
		} else {
			// Method 2: Word-based fuzzy matching
			matchedWords := 0
			for _, word := range significantWords {
				// Normalize common variations
				normalizedWord := word
				normalizedWord = strings.ReplaceAll(normalizedWord, ".", "")
				normalizedWord = strings.ReplaceAll(normalizedWord, "'", "")

				// Check for word match with fuzzy variations
				if strings.Contains(lineNormalized, normalizedWord) {
					matchedWords++
				} else {
					// Check common abbreviations
					if (normalizedWord == "8pm" || normalizedWord == "8 pm") && strings.Contains(lineNormalized, "8") && strings.Contains(lineNormalized, "p") {
						matchedWords++
					} else if (normalizedWord == "rs" || normalizedWord == "r s") && strings.Contains(lineNormalized, "r") && strings.Contains(lineNormalized, "s") {
						matchedWords++
					}
				}
			}

			if len(significantWords) > 0 {
				matchPercentage := float64(matchedWords) / float64(len(significantWords))
				if matchPercentage >= 0.5 { // At least 50% of words match
					wordScore := int(matchPercentage * 10)
					matchScore += wordScore
					matchReasons = append(matchReasons, fmt.Sprintf("word-match-%d/%d", matchedWords, len(significantWords)))
				}
			}
		}

		// If we have a serial number, verify it matches
		if serialNumber > 0 {
			lineSerialPattern := regexp.MustCompile(`^\s*(\d+)[\.\s]+`)
			if serialMatches := lineSerialPattern.FindStringSubmatch(line); len(serialMatches) > 1 {
				lineSerial, _ := strconv.Atoi(serialMatches[1])
				if lineSerial == serialNumber {
					matchScore += 20 // Serial number match is strong evidence
					matchReasons = append(matchReasons, fmt.Sprintf("serial-%d", serialNumber))
				}
			}
		}

		// Check if line has reasonable number of fields (data row should have 6-10 fields)
		fields := strings.Fields(line)
		if len(fields) >= 6 && len(fields) <= 15 {
			matchScore += 5
			matchReasons = append(matchReasons, fmt.Sprintf("fields-%d", len(fields)))
		}

		// Log each line evaluation for debugging
		if matchScore > 0 {
			linePreview := line
			if len(line) > 60 {
				linePreview = line[:60] + "..."
			}
			fmt.Printf("   📝 [Row Match] Line %d (score: %d, %v): %s\n", lineNumber, matchScore, matchReasons, linePreview)
		}

		// Pick the best match
		if matchScore > bestMatchScore {
			bestMatchScore = matchScore
			targetRow = line
		}
	}

	if targetRow == "" {
		fmt.Printf("   ❌ [Row Match] Could not find row for brand: %s\n", brandOriginalText)
		return BrandRowMatch{Row: "", MatchScore: 0, Found: false}
	}

	// Safely truncate row preview
	rowPreview := targetRow
	if len(targetRow) > 80 {
		rowPreview = targetRow[:80]
	}
	fmt.Printf("   ✅ [Row Match] Found row (score: %d): %s\n", bestMatchScore, rowPreview)

	return BrandRowMatch{Row: targetRow, MatchScore: bestMatchScore, Found: true}
}

// calculatePriceFromRawText extracts price from raw OCR text using focused helper functions
// 🔧 Phase 2.1: Simplified from 260 lines to ~60 lines using modular design
func calculatePriceFromRawText(rawText, brandOriginalText string) float64 {
	if rawText == "" || brandOriginalText == "" {
		return 0.0
	}

	// STEP 1: Detect receipt type
	receiptType := detectReceiptType(rawText)
	fmt.Printf("   📋 [Price Calc] Detected receipt type: %s\n", receiptType)

	// STEP 2: Find the brand's row using fuzzy matching
	rowMatch := findBrandRow(rawText, brandOriginalText)
	if !rowMatch.Found {
		return 0.0
	}

	// STEP 3: Extract numbers from the matched row
	numbers := extractNumbersFromRow(rowMatch.Row)
	if len(numbers) == 0 {
		return 0.0
	}

	fmt.Printf("   🔢 [Price Calc] Found %d numbers: %v\n", len(numbers), numbers)

	// STEP 4: Detect 180ml format for precise column mapping
	invoiceFormat := "7-column"
	if receiptType == "180ml" {
		invoiceFormat = detect180mlFormat(rawText)
		fmt.Printf("   📋 [Price Calc] Detected 180ml format: %s\n", invoiceFormat)
	}

	// STEP 5: Get dynamic column mapping
	columnMap := getColumnMapping(receiptType, len(numbers), invoiceFormat)
	fmt.Printf("   📊 [Price Calc] Using column mapping: Rate@%d, Sale@%d, Amount@%d\n",
		columnMap["rate"], columnMap["sale"], columnMap["amount"])

	// STEP 6: Try direct extraction from rate column
	if price, ok := extractPriceFromRate(numbers, receiptType, columnMap); ok {
		return price
	}

	// STEP 7: Fallback to calculation from Amount ÷ Sale
	if price, ok := extractPriceFromCalculation(numbers, columnMap); ok {
		return price
	}

	// 🔧 Phase 2.1: Removed risky heuristic guessing - fail cleanly instead
	fmt.Printf("   ❌ [Price Calc] Cannot determine valid price from numbers: %v\n", numbers)
	fmt.Printf("   ℹ️  [Price Calc] Suggestion: Check if row has proper column structure\n")
	return 0.0
}

// extractNumbersFromRow extracts all numeric values from a text row
// CRITICAL: This function MUST only process a SINGLE row, not multiple lines
func extractNumbersFromRow(row string) []float64 {
	// VALIDATION: Ensure we're only processing a single row
	if strings.Contains(row, "\n") {
		fmt.Printf("   ⚠️  [Extract] WARNING: Input contains multiple lines (%d chars), rejecting\n", len(row))
		return []float64{}
	}

	// Remove pipes and extra spaces
	row = strings.ReplaceAll(row, "|", " ")
	row = regexp.MustCompile(`\s+`).ReplaceAllString(row, " ")

	// Split by spaces
	parts := strings.Fields(row)

	var numbers []float64
	for _, part := range parts {
		// Try to parse as number
		// Remove common OCR noise characters
		part = strings.Trim(part, ".,;:")

		// Skip if it contains letters (brand names)
		hasLetter := false
		for _, r := range part {
			if unicode.IsLetter(r) {
				hasLetter = true
				break
			}
		}
		if hasLetter {
			continue
		}

		// Try to parse
		var num float64
		if _, err := fmt.Sscanf(part, "%f", &num); err == nil {
			// CRITICAL VALIDATION: Prevent anomalously large numbers (stock/price concatenation bug)
			// Stock columns should never exceed 5,000 units
			// Price columns should never exceed ₹10,000
			// If we see a number > 10,000, it's likely a parsing error (e.g., "10 250" → "10250")
			if num > 10000 {
				fmt.Printf("   🔴 [Extract] REJECTED: Suspiciously large number %.0f detected (likely OCR concatenation error)\n", num)
				fmt.Printf("   📋 Context: '%s' in row: %s\n", part, row)
				// Skip this number to prevent stock anomalies
				continue
			}
			numbers = append(numbers, num)
		}
	}

	// VALIDATION: Check if we extracted a reasonable number of values for a table row
	// Standard Kerala Beverage invoice format has 6-10 columns
	if len(numbers) > 20 {
		fmt.Printf("   ⚠️  [Extract] WARNING: Extracted %d numbers (expected 6-10), likely processing multiple rows\n", len(numbers))
		return []float64{}
	}

	return numbers
}

// preprocessVisionText cleans raw Vision API output before Gemini processing
func preprocessVisionText(rawText string) string {
	fmt.Printf("📝 [OCR Preprocessing] Original text length: %d chars\n", len(rawText))

	// Step 1: Remove Indic numerals
	cleaned := cleanOCRText(rawText)

	// Step 2: Fix common table structure issues
	// Vision API might output: "Brand | | 50 | | 180"
	// Fix to: "Brand | 50 | 180"
	cleaned = regexp.MustCompile(`\|\s*\|`).ReplaceAllString(cleaned, "|")

	// Step 3: Clean up excessive pipes at line endings
	lines := strings.Split(cleaned, "\n")
	cleanedLines := make([]string, 0, len(lines))

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Remove trailing pipes and spaces
		line = strings.TrimRight(line, " |")
		cleanedLines = append(cleanedLines, line)
	}

	cleaned = strings.Join(cleanedLines, "\n")

	fmt.Printf("✅ [OCR Preprocessing] Cleaned text length: %d chars (removed %d chars)\n",
		len(cleaned), len(rawText)-len(cleaned))

	return cleaned
}

// NewOCRService creates a new OCR service
func NewOCRService(db *database.DB) (*OCRService, error) {
	ctx := context.Background()

	// Initialize OCR Provider Manager (handles Ollama → OpenAI → Gemini fallback)
	var providerManager *OCRProviderManager
	providerManager, err := NewOCRProviderManager()
	if err != nil {
		fmt.Printf("⚠️  OCR Provider Manager initialization warning: %v\n", err)
	} else {
		fmt.Printf("✅ OCR Provider Manager initialized with providers: %v\n", providerManager.ListProviders())
	}

	// Initialize Ollama Vision client (LOCAL - cost-free)
	var ollamaClient *OllamaVisionClient
	var useOllama bool
	ollamaClient, err = NewOllamaVisionClient()
	if err != nil {
		fmt.Printf("⚠️  Ollama Vision not available: %v\n", err)
		useOllama = false
	} else {
		// Check if Ollama is actually available
		if ollamaClient.IsAvailable(ctx) {
			fmt.Println("✅ Ollama local LLM initialized successfully (PRIMARY - cost-free)")
			useOllama = true
		} else {
			fmt.Println("⚠️  Ollama initialized but model not available - will use OpenAI")
			useOllama = false
		}
	}

	// Initialize OpenAI Vision client (FALLBACK - GPT-4o for best accuracy)
	var openaiClient *OpenAIVisionClient
	var useOpenAI bool
	openaiClient, err = NewOpenAIVisionClient()
	if err != nil {
		fmt.Printf("⚠️  OpenAI Vision API not available: %v\n", err)
		fmt.Println("ℹ️  Will use Google Cloud Vision + Gemini as fallback")
		useOpenAI = false
	} else {
		if useOllama {
			fmt.Println("✅ OpenAI GPT-4o Vision API initialized (FALLBACK)")
		} else {
			fmt.Println("✅ OpenAI GPT-4o Vision API initialized (PRIMARY)")
		}
		useOpenAI = true
	}

	// Initialize Google Cloud Vision client (fallback for text extraction)
	visionClient, err := ocr.NewVisionClient(ctx)
	if err != nil {
		fmt.Printf("⚠️  Google Cloud Vision API not available: %v\n", err)
		if !useOpenAI {
			fmt.Println("ℹ️  Will use Gemini Vision as last fallback for text extraction")
		}
	} else {
		fmt.Println("✅ Google Cloud Vision API initialized successfully (FALLBACK)")
	}

	// Initialize Gemini client (for structured data extraction and brand matching - fallback)
	geminiClient := ocr.NewGeminiClient()
	fmt.Println("✅ Gemini AI client initialized successfully (FALLBACK)")

	// Initialize Smart Column Detector
	columnDetector := NewSmartColumnDetector()
	fmt.Println("🧠 Smart Column Detector initialized successfully")

	// Initialize Multi-Receipt Detection Services
	var receiptDetector *ReceiptDetector
	receiptDetector, err = NewReceiptDetector()
	if err != nil {
		fmt.Printf("⚠️  Receipt Detector not available: %v\n", err)
		fmt.Println("ℹ️  Multi-receipt detection will be disabled")
	} else {
		fmt.Println("✅ Receipt Detector initialized successfully")
	}

	// Initialize Image Processor for multi-receipt cropping
	imageProcessor := ocr.NewImageProcessor()
	fmt.Println("✅ Image Processor initialized successfully")

	// Initialize Rate Corrector
	rateCorrector := NewRateCorrector()
	fmt.Println("✅ Rate Corrector initialized successfully")

	// Initialize Extraction Validator
	extractionValidator := NewExtractionValidator()
	fmt.Println("✅ Extraction Validator initialized successfully")

	// Log active OCR pipeline
	if useOllama {
		fmt.Println("📊 OCR Pipeline: Ollama Qwen2.5-VL (LOCAL FREE) → OpenAI GPT-4o (FALLBACK)")
	} else if useOpenAI {
		fmt.Println("📊 OCR Pipeline: OpenAI GPT-4o Vision (PRIMARY)")
	} else {
		fmt.Println("📊 OCR Pipeline: Cloud Vision (Text Extraction) → Smart Column Detection → Brand Matching")
	}

	return &OCRService{
		db:                  db,
		visionClient:        visionClient,
		geminiClient:        geminiClient,
		openaiClient:        openaiClient,
		ollamaClient:        ollamaClient,
		providerManager:     providerManager,
		columnDetector:      columnDetector,
		useOpenAI:           useOpenAI,
		useOllama:           useOllama,
		receiptDetector:     receiptDetector,
		imageProcessor:      imageProcessor,
		rateCorrector:       rateCorrector,
		extractionValidator: extractionValidator,
		multiReceiptConfig: multiReceiptConfig{
			enableAutoDetection: true,
			minItemsForSplit:    15,  // Detect multi-receipt if 15+ items expected
			detectionConfidence: 80,  // 80% confidence threshold
		},
	}, nil
}

// GetDB returns the database connection for use by other services
func (s *OCRService) GetDB() *gorm.DB {
	return s.db.DB
}

// CreateBatchSession creates a new batch OCR session
func (s *OCRService) CreateBatchSession(ctx context.Context, tenantID, userID, shopID, sessionType string, imageCount int) (*models.BatchOCRSession, error) {
	sessionID := uuid.New().String()
	session := &models.BatchOCRSession{
		ID:                  sessionID,
		SessionID:           sessionID, // Alias for Flutter compatibility
		TenantID:            tenantID,
		UserID:              userID,
		ShopID:              shopID,
		SessionType:         sessionType,
		Status:              "processing",
		CurrentStage:        "vision_api",
		ProgressPercentage:  0,
		TotalImages:         imageCount,
		CompletedImages:     0,
		FailedImages:        0,
		TotalItemsExtracted: 0,
		CreatedAt:           time.Now(),
		UpdatedAt:           time.Now(),
	}

	if err := s.db.Create(session).Error; err != nil {
		return nil, fmt.Errorf("failed to create batch session: %w", err)
	}

	return session, nil
}

// ParsedInvoiceRow represents a row parsed from invoice text
type ParsedInvoiceRow struct {
	RowNumber    int
	BrandName    string
	Opening      int
	Receipt      int
	Total        int
	Sale         int
	Rate         float64
	Amount       float64
	Closing      int
	Confidence   float64  // 0-100
}

// parseInvoiceWithRegex parses invoice rows directly from raw OCR text using regex patterns
// This is a fallback for when Vision API table detection fails
func (s *OCRService) parseInvoiceWithRegex(rawText, receiptType string) []ParsedInvoiceRow {
	fmt.Printf("🔧 [Regex Parser] Parsing invoice for type: %s\n", receiptType)

	// Check if text is all on one line (no newlines)
	lines := strings.Split(rawText, "\n")
	if len(lines) <= 1 {
		// Text is on one line - try to split by row numbers
		// Pattern: find row numbers like " 1 " " 2 " " 3 " followed by brand names
		fmt.Println("📋 [Regex Parser] Text appears to be on single line - attempting row-based splitting")

		// Strategy: Look for patterns that indicate row starts
		// In 180ml format, rows typically start with: " <row#> <brand> <numbers>..."
		// We need to identify where each row starts by looking for:
		// 1. Whitespace + row number (1-2 digits) + whitespace
		// 2. Followed by brand text (can start with digit like "8 P.M." or letter like "Conik")
		// 3. Then followed by multiple numbers (the data columns)

		// Find all row number positions using a comprehensive pattern
		// This handles BOTH letter-starting brands (like "Iconiq") AND digit-starting brands (like "100 Pipers", "8 P.M.")
		// Pattern: whitespace + 1-2 digit row number + whitespace
		fmt.Println("🔧 [Regex Parser] Using comprehensive pattern for all brand types (letter AND digit-starting)...")

		// Find ALL occurrences of " <digit> " and check if they're likely row numbers
		digitPattern := regexp.MustCompile(`\s+(\d{1,2})\s+`)
		allMatches := digitPattern.FindAllStringSubmatchIndex(rawText, -1)

		if len(allMatches) > 0 {
			fmt.Printf("🔍 [Regex Parser] Found %d potential row number positions\n", len(allMatches))

			// Filter to find sequential row numbers (1, 2, 3, ...)
			var rowStarts []int
			for _, match := range allMatches {
				numStr := rawText[match[2]:match[3]]
				num, _ := strconv.Atoi(numStr)

				// Only consider numbers 1-50 as potential row numbers
				if num >= 1 && num <= 50 {
					// Check if this looks like a row start (not a price/quantity)
					// Row numbers are typically followed by brand text, not just more numbers
					pos := match[1] // End of the match (after the whitespace following the number)
					if pos < len(rawText) {
						// Look ahead to see what follows
						endPos := pos + 30
						if endPos > len(rawText) {
							endPos = len(rawText)
						}
						nextChunk := rawText[pos:endPos]
						// If it starts with a letter OR digit followed by more chars (like "8 P.M." or "100 Pipers"), likely a brand
						if len(nextChunk) > 0 && (unicode.IsLetter(rune(nextChunk[0])) ||
						   (unicode.IsDigit(rune(nextChunk[0])) && len(nextChunk) > 2)) {
							rowStarts = append(rowStarts, match[0])
						}
					}
				}
			}

			if len(rowStarts) > 1 {
				fmt.Printf("📋 [Regex Parser] Filtered to %d likely row starts\n", len(rowStarts))
				newLines := make([]string, 0, len(rowStarts))
				for i := 0; i < len(rowStarts); i++ {
					start := rowStarts[i]
					var end int
					if i < len(rowStarts)-1 {
						end = rowStarts[i+1]
					} else {
						end = len(rawText)
					}
					line := strings.TrimSpace(rawText[start:end])
					if line != "" {
						newLines = append(newLines, line)
					}
				}
				lines = newLines
				fmt.Printf("📋 [Regex Parser] Split into %d lines (all brands)\n", len(lines))
			} else {
				fmt.Println("⚠️  [Regex Parser] Could not find row patterns in single-line text")
			}
		} else {
			fmt.Println("⚠️  [Regex Parser] Could not find row patterns in single-line text")
		}
	}

	var rows []ParsedInvoiceRow

	// Detect invoice format
	invoiceFormat := "7-column"
	if receiptType == "180ml" {
		invoiceFormat = detect180mlFormat(rawText)
		fmt.Printf("📋 [Regex Parser] Detected format: %s\n", invoiceFormat)
	}

	// Define regex patterns for different formats
	// Made more flexible to handle real OCR text variations:
	// - \s*\|?\s* allows optional pipe delimiters with flexible spacing
	// - Brand name: capture everything between row number and first sequence of 2+ digit groups
	// - Numbers can have decimals (\d+(?:\.\d+)?)
	var rowPattern *regexp.Regexp

	if invoiceFormat == "beer" {
		// Beer format: S.No | Brand Name | Op | Rec | Sale | Rate | Amount | Closing
		// Uses dashes (-) instead of zeros, columns can be "-" or numbers
		// Example: "3 BUDWEISER MAGNUM 24 - 5 210 1050 19" or "4 100 Pipers 10 0 1 450 450 9"
		// Pattern captures all 6 columns to extract closing stock and sale quantity
		// NOTE: Brand can start with letter OR digit (like "100 Pipers", "8 P.M.")
		rowPattern = regexp.MustCompile(`^\s*(\d+)\s+([A-Za-z0-9][A-Za-z0-9\s&'.#]*?)\s+(\d+|-)\s+(\d+|-)\s+(\d+|-)\s+(\d+(?:\.\d+)?|-)\s+(\d+(?:\.\d+)?|-)\s+(\d+)\s*$`)
	} else if invoiceFormat == "compact" {
		// Compact format: S.No | Brand Name | Total | Sale | Rate | Amount | Closing
		// Captures row num, then brand (can start with letter OR digit like "8 P.M."), then 7 number columns
		// Example: "1 8 P.M. 300 0 0 60 120 25 0"  → extracts "8 P.M."
		rowPattern = regexp.MustCompile(`^\s*(\d+)\s*\|?\s*([A-Za-z0-9][A-Za-z0-9\s&'.#-|]*?)\s+(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s*$`)
	} else {
		// Standard 7-column format: S.No | Brand Name | Opening | Receipt | Total | Sale | Rate | Amount | Closing
		// Captures row num, then brand (can start with letter OR digit like "8 P.M."), then 9 number columns
		// Allows brands starting with alphanumeric to handle cases like "8 P.M.", "100 Piper"
		rowPattern = regexp.MustCompile(`^\s*(\d+)\s*\|?\s*([A-Za-z0-9][A-Za-z0-9\s&'.#-|]*?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s*$`)
	}

	fmt.Printf("📋 [Regex Parser] Using pattern for format: %s\n", invoiceFormat)

	matchAttempts := 0
	validMatches := 0

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Skip header lines
		lineLower := strings.ToLower(line)
		if strings.Contains(lineLower, "brand") || strings.Contains(lineLower, "s.no") ||
		   strings.Contains(lineLower, "opening") || strings.Contains(lineLower, "receipt") {
			continue
		}

		// Try to match the row pattern
		matchAttempts++
		matches := rowPattern.FindStringSubmatch(line)

		// Debug: Show first few failed matches to understand why pattern isn't working
		if len(matches) == 0 && matchAttempts <= 5 {
			fmt.Printf("   ⚠️  No match for line %d: %q\n", matchAttempts, line)
		}

		if len(matches) > 0 {
			var row ParsedInvoiceRow
			var err error

			if invoiceFormat == "beer" && len(matches) >= 9 {
				// Beer format parsing (with dashes as zeros)
				// Format: RowNum, Brand, Opening, Receipt, Sale, Rate, Amount, Closing
				row.RowNumber, _ = strconv.Atoi(matches[1])
				row.BrandName = strings.TrimSpace(matches[2])
				row.Opening = parseDashOrInt(matches[3])
				row.Receipt = parseDashOrInt(matches[4])
				row.Sale = parseDashOrInt(matches[5])
				row.Rate = parseDashOrFloat(matches[6])
				row.Amount = parseDashOrFloat(matches[7])
				row.Closing, _ = strconv.Atoi(matches[8])
				row.Total = row.Opening + row.Receipt
				row.Confidence = 90.0  // High confidence for beer format match

			} else if invoiceFormat == "compact" && len(matches) >= 8 {
				// Compact format parsing
				row.RowNumber, _ = strconv.Atoi(matches[1])
				row.BrandName = strings.TrimSpace(matches[2])
				row.Total, _ = strconv.Atoi(matches[3])
				row.Sale, _ = strconv.Atoi(matches[4])
				row.Rate, _ = strconv.ParseFloat(matches[5], 64)
				row.Amount, _ = strconv.ParseFloat(matches[6], 64)
				row.Closing, _ = strconv.Atoi(matches[7])
				row.Opening = 0  // Not available in compact format
				row.Receipt = 0  // Not available in compact format
				row.Confidence = 90.0  // High confidence for regex match

			} else if invoiceFormat == "7-column" && len(matches) >= 10 {
				// Standard 7-column format parsing
				row.RowNumber, _ = strconv.Atoi(matches[1])
				row.BrandName = strings.TrimSpace(matches[2])
				row.Opening, _ = strconv.Atoi(matches[3])
				row.Receipt, _ = strconv.Atoi(matches[4])
				row.Total, _ = strconv.Atoi(matches[5])
				row.Sale, _ = strconv.Atoi(matches[6])
				row.Rate, _ = strconv.ParseFloat(matches[7], 64)
				row.Amount, _ = strconv.ParseFloat(matches[8], 64)
				row.Closing, _ = strconv.Atoi(matches[9])
				row.Confidence = 95.0  // Very high confidence for full row match
			} else {
				continue  // Pattern matched but not enough groups
			}

			// Validate the parsed row
			if err == nil && row.BrandName != "" && row.RowNumber > 0 {
				// Clean brand name
				row.BrandName = cleanBrandName(row.BrandName)

				// Additional validation
				if len(row.BrandName) >= 2 {
					rows = append(rows, row)
					validMatches++
					fmt.Printf("✅ [Regex Parser] Row %d: %s (Rate: %.2f, Closing: %d)\n",
						row.RowNumber, row.BrandName, row.Rate, row.Closing)
				}
			}
		}
	}

	fmt.Printf("📊 [Regex Parser] Attempted %d lines, found %d valid matches, parsed %d rows\n",
		matchAttempts, validMatches, len(rows))
	return rows
}

// parseTableDataToItems converts Vision API TableData to OCRItems
func (s *OCRService) parseTableDataToItems(tableData *ocr.TableData, sessionID, batchID, receiptType string) []models.OCRItem {
	if tableData == nil {
		return []models.OCRItem{}
	}

	fmt.Printf("📋 [Table Parser] Processing %d rows from Vision API table\n", len(tableData.Rows))

	// Extract sample data rows for smart analysis
	var sampleDataRows [][]string
	maxSamples := 10 // Use first 10 rows for analysis
	for i, row := range tableData.Rows {
		if i >= maxSamples {
			break
		}
		sampleDataRows = append(sampleDataRows, row.Cells)
	}

	// Get tenant ID from session for cached patterns (if available)
	var tenantID string
	var session models.OCRSession
	if err := s.db.Where("id = ?", sessionID).First(&session).Error; err == nil {
		tenantID = session.TenantID
	}

	// Use SMART column detection with data analysis
	var columnMap map[string]int
	if s.columnDetector != nil {
		columnMap = s.columnDetector.DetectColumns(tableData.Headers, sampleDataRows, tenantID, receiptType)
	} else {
		// Fallback to old detection if smart detector not initialized
		columnMap = s.detectColumnIndices(tableData.Headers)
	}

	var items []models.OCRItem

	for _, row := range tableData.Rows {
		if len(row.Cells) == 0 {
			continue
		}

		// Parse row data based on column mapping
		item := s.parseTableRow(row, columnMap, sessionID, batchID, receiptType)

		if item != nil && validateExtractedItem(item) {
			items = append(items, *item)
			fmt.Printf("✅ [Table Parser] Row %d: %s (Price: %.2f, Qty: %d)\n",
				item.RowNumber, item.BrandText, *item.SellingPrice, item.Quantity)
		}
	}

	fmt.Printf("📊 [Table Parser] Extracted %d valid items\n", len(items))
	return items
}

// detectColumnIndices finds column positions from headers
func (s *OCRService) detectColumnIndices(headers []string) map[string]int {
	columnMap := make(map[string]int)

	// Debug: Show what headers Vision API returned
	fmt.Printf("🔍 [Column Detection] Received %d headers from Vision API:\n", len(headers))
	for i, h := range headers {
		fmt.Printf("   [%d] = '%s'\n", i, h)
	}

	for i, header := range headers {
		headerLower := strings.ToLower(strings.TrimSpace(header))

		// Remove dots and special characters for better matching
		headerClean := strings.ReplaceAll(headerLower, ".", "")
		headerClean = strings.ReplaceAll(headerClean, " ", "")

		if strings.Contains(headerClean, "sno") || strings.Contains(headerClean, "serial") ||
		   strings.Contains(headerLower, "s.no") || strings.Contains(headerLower, "s no") {
			columnMap["sno"] = i
			fmt.Printf("   ✅ Column %d: S.No\n", i)
		} else if strings.Contains(headerLower, "brand") || strings.Contains(headerLower, "item") ||
		          (strings.Contains(headerLower, "name") && !strings.Contains(headerLower, "shop")) {
			columnMap["brand"] = i
			fmt.Printf("   ✅ Column %d: Brand\n", i)
		} else if strings.Contains(headerLower, "opening") {
			columnMap["opening"] = i
			fmt.Printf("   ✅ Column %d: Opening\n", i)
		} else if strings.Contains(headerLower, "receipt") {
			columnMap["receipt"] = i
			fmt.Printf("   ✅ Column %d: Receipt\n", i)
		} else if strings.Contains(headerLower, "total") {
			columnMap["total"] = i
			fmt.Printf("   ✅ Column %d: Total\n", i)
		} else if strings.Contains(headerLower, "sale") {
			columnMap["sale"] = i
			fmt.Printf("   ✅ Column %d: Sale\n", i)
		} else if strings.Contains(headerLower, "rate") || strings.Contains(headerLower, "price") {
			columnMap["rate"] = i
			fmt.Printf("   ✅ Column %d: Rate\n", i)
		} else if strings.Contains(headerLower, "amount") {
			columnMap["amount"] = i
			fmt.Printf("   ✅ Column %d: Amount\n", i)
		} else if strings.Contains(headerLower, "closing") {
			columnMap["closing"] = i
			fmt.Printf("   ✅ Column %d: Closing\n", i)
		}
	}

	// Fallback: If critical columns are missing, try positional detection for 180ml format
	// Expected format: S.No (0), Brand (1), Opening (2), Receipt (3), Total (4), Sale (5), Rate (6), Amount (7), Closing (8)
	if _, hasSno := columnMap["sno"]; !hasSno && len(headers) >= 9 {
		columnMap["sno"] = 0
		fmt.Println("   🔧 [Fallback] Assuming column 0 = S.No (positional)")
	}
	if _, hasBrand := columnMap["brand"]; !hasBrand && len(headers) >= 9 {
		columnMap["brand"] = 1
		fmt.Println("   🔧 [Fallback] Assuming column 1 = Brand (positional)")
	}
	if _, hasRate := columnMap["rate"]; !hasRate && len(headers) >= 9 {
		columnMap["rate"] = 6
		fmt.Println("   🔧 [Fallback] Assuming column 6 = Rate (positional)")
	}
	if _, hasClosing := columnMap["closing"]; !hasClosing && len(headers) >= 9 {
		columnMap["closing"] = 8
		fmt.Println("   🔧 [Fallback] Assuming column 8 = Closing (positional)")
	}

	fmt.Printf("📊 [Column Detection] Final column map: %v\n", columnMap)
	return columnMap
}

// parseTableRow parses a single table row into an OCRItem
func (s *OCRService) parseTableRow(row ocr.TableRow, columnMap map[string]int, sessionID, batchID, receiptType string) *models.OCRItem {
	cells := row.Cells

	// Extract data from cells based on column mapping
	var rowNum int
	var brandName string
	var opening int
	var sale int
	var rate float64
	var closing int

	// Row number
	if idx, ok := columnMap["sno"]; ok && idx < len(cells) {
		rowNum, _ = strconv.Atoi(cells[idx])
	}

	// Brand name
	if idx, ok := columnMap["brand"]; ok && idx < len(cells) {
		brandName = cleanBrandName(cells[idx])
	}

	// Opening stock
	if idx, ok := columnMap["opening"]; ok && idx < len(cells) {
		opening = parseDashOrInt(cells[idx])
	}

	// Sale quantity
	if idx, ok := columnMap["sale"]; ok && idx < len(cells) {
		sale = parseDashOrInt(cells[idx])
	}

	// Rate (price)
	if idx, ok := columnMap["rate"]; ok && idx < len(cells) {
		rate = parseDashOrFloat(cells[idx])
	}

	// Closing stock (quantity)
	if idx, ok := columnMap["closing"]; ok && idx < len(cells) {
		closing = parseDashOrInt(cells[idx])
	}

	// Fallback: If rate is 0, try to calculate from amount and sale
	if rate == 0 {
		if saleIdx, saleOk := columnMap["sale"]; saleOk && saleIdx < len(cells) {
			if amountIdx, amountOk := columnMap["amount"]; amountOk && amountIdx < len(cells) {
				saleVal := parseDashOrInt(cells[saleIdx])
				amount := parseDashOrFloat(cells[amountIdx])
				if saleVal > 0 && amount > 0 {
					rate = amount / float64(saleVal)
				}
			}
		}
	}

	// Validate extracted data
	if brandName == "" || rowNum == 0 {
		return nil
	}

	item := &models.OCRItem{
		ID:                 uuid.New().String(),
		SessionID:          sessionID,
		BatchID:            batchID,
		RowNumber:          rowNum,
		BrandText:          brandName,
		SizeText:           receiptType,
		OpeningStock:       opening,
		SaleQuantity:       sale,
		Quantity:           closing,
		Rate:               rate,  // Column 5 - Rate per bottle
		SellingPrice:       &rate,
		IsSelected:         true,
		IsReviewed:         false,
		MatchStrategy:      "vision_direct",
		VerificationStatus: "pending",
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	return item
}

// ProcessImageBatch processes multiple images in a batch with parallel processing
func (s *OCRService) ProcessImageBatch(ctx context.Context, batchID string, images []string) error {
	session, err := s.GetBatchSession(ctx, batchID)
	if err != nil {
		return err
	}

	// ✨ PHASE 1: Process images in parallel with goroutines
	fmt.Printf("🚀 [OCR] Processing %d images in parallel (max 3 concurrent)...\n", len(images))

	type imageResult struct {
		index     int
		sessionID string
		err       error
	}

	// Create worker pool with max 3 concurrent workers to avoid API rate limits
	maxWorkers := 3
	if len(images) < maxWorkers {
		maxWorkers = len(images)
	}

	results := make(chan imageResult, len(images))
	imageChan := make(chan int, len(images))

	// Send image indices to channel
	for i := range images {
		imageChan <- i
	}
	close(imageChan)

	// Start worker goroutines
	var wg sync.WaitGroup
	for w := 0; w < maxWorkers; w++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			for i := range imageChan {
				fmt.Printf("⚙️  [Worker %d] Processing image %d/%d\n", workerID, i+1, len(images))

				sessionID, err := s.ProcessSingleImage(ctx, batchID, session.TenantID, session.UserID, session.ShopID, images[i])

				results <- imageResult{
					index:     i,
					sessionID: sessionID,
					err:       err,
				}

				// Update progress after each image
				completed := i + 1
				progress := float64(completed) / float64(len(images)) * 30.0
				s.UpdateBatchProgress(ctx, batchID, "vision_api", progress, completed, 0)
			}
		}(w)
	}

	// Wait for all workers to finish
	go func() {
		wg.Wait()
		close(results)
	}()

	// Collect results
	sessionIDs := make([]string, 0, len(images))
	failedCount := 0

	for result := range results {
		if result.err != nil {
			fmt.Printf("❌ [OCR] Image %d failed: %v\n", result.index+1, result.err)
			failedCount++
			continue
		}
		sessionIDs = append(sessionIDs, result.sessionID)
	}

	fmt.Printf("✅ [OCR] Phase 1 complete: %d/%d images processed successfully\n", len(sessionIDs), len(images))

	// Check if all images failed
	if len(sessionIDs) == 0 {
		fmt.Printf("❌ All %d images failed to process\n", len(images))
		s.UpdateBatchProgress(ctx, batchID, "failed", 0, 0, 0)
		s.db.Model(&models.BatchOCRSession{}).
			Where("id = ?", batchID).
			Updates(map[string]interface{}{
				"status":       "failed",
				"completed_at": time.Now(),
				"updated_at":   time.Now(),
			})
		return fmt.Errorf("all images failed to process")
	}

	// Save session IDs
	err = s.SaveSessionIDs(ctx, batchID, sessionIDs)
	if err != nil {
		return fmt.Errorf("failed to save session IDs: %w", err)
	}

	// ✨ PHASE 2: Extract items with Gemini in parallel
	fmt.Printf("🚀 [OCR] Extracting items from %d sessions in parallel...\n", len(sessionIDs))
	s.UpdateBatchProgress(ctx, batchID, "gemini_extraction", 50.0, len(sessionIDs), 0)

	type extractionResult struct {
		sessionID string
		items     []models.OCRItem
		err       error
	}

	extractResults := make(chan extractionResult, len(sessionIDs))
	sessionChan := make(chan string, len(sessionIDs))

	// Send session IDs to channel
	for _, sid := range sessionIDs {
		sessionChan <- sid
	}
	close(sessionChan)

	// Start extraction workers (max 3 concurrent)
	// Add staggered delays to avoid rate limiting
	var extractWg sync.WaitGroup
	for w := 0; w < maxWorkers; w++ {
		extractWg.Add(1)

		// Stagger worker starts by 500ms each to avoid simultaneous API calls
		time.Sleep(time.Duration(w) * 500 * time.Millisecond)

		go func(workerID int) {
			defer extractWg.Done()
			for sessionID := range sessionChan {
				fmt.Printf("⚙️  [Direct Extraction Worker %d] Starting extraction for session %s\n", workerID, sessionID)
				items, err := s.ExtractItemsDirect(ctx, sessionID, "")

				if err != nil {
					fmt.Printf("❌ [Direct Extraction Worker %d] Extraction FAILED for session %s: %v\n", workerID, sessionID, err)
					// Get session details for debugging
					var session models.OCRSession
					dbErr := s.db.Where("id = ?", sessionID).First(&session).Error
					if dbErr == nil {
						fmt.Printf("📝 [DEBUG] Session %s raw text length: %d chars\n", sessionID, len(session.RawText))
						if len(session.RawText) > 200 {
							fmt.Printf("📝 [DEBUG] First 200 chars: %s...\n", session.RawText[:200])
						} else {
							fmt.Printf("📝 [DEBUG] Full text: %s\n", session.RawText)
						}
					} else {
						fmt.Printf("📝 [DEBUG] Could not retrieve session %s: %v\n", sessionID, dbErr)
					}
				} else {
					fmt.Printf("✅ [Direct Extraction Worker %d] Successfully extracted %d items from session %s\n", workerID, len(items), sessionID)
				}

				extractResults <- extractionResult{
					sessionID: sessionID,
					items:     items,
					err:       err,
				}
			}
		}(w)
	}

	// Wait for all extraction workers
	go func() {
		extractWg.Wait()
		close(extractResults)
	}()

	// Collect extraction results
	totalItems := 0
	for result := range extractResults {
		if result.err != nil {
			fmt.Printf("❌ [OCR] Extraction failed for session %s: %v\n", result.sessionID, result.err)
			continue
		}
		totalItems += len(result.items)
	}

	fmt.Printf("✅ [OCR] Phase 2 complete: %d items extracted from %d sessions\n", totalItems, len(sessionIDs))

	// Check if no items were extracted from Phase 2, but items may already exist from Phase 1 (OpenAI)
	if totalItems == 0 {
		// Check if items already exist in database (e.g., from OpenAI extraction in Phase 1)
		var existingItemCount int64
		s.db.Model(&models.OCRItem{}).Where("batch_id = ?", batchID).Count(&existingItemCount)
		if existingItemCount > 0 {
			fmt.Printf("✅ [OCR] Found %d items already extracted by OpenAI in Phase 1\n", existingItemCount)
			totalItems = int(existingItemCount)
		} else {
			fmt.Println("⚠️  No items extracted from any images")
			s.UpdateBatchProgress(ctx, batchID, "failed", 0, len(sessionIDs), 0)
			s.db.Model(&models.BatchOCRSession{}).
				Where("id = ?", batchID).
				Updates(map[string]interface{}{
					"status":       "failed",
					"completed_at": time.Now(),
					"updated_at":   time.Now(),
				})
			return fmt.Errorf("no items extracted")
		}
	}

	// Update progress
	s.UpdateBatchProgress(ctx, batchID, "item_matching", 80.0, len(sessionIDs), totalItems)

	// Perform matching (sequential - needs database consistency)
	// Using fuzzy matching instead of Gemini
	err = s.PerformFuzzyMatching(ctx, batchID)
	if err != nil {
		fmt.Printf("Warning: Fuzzy matching had errors: %v\n", err)
	}

	// Mark as completed
	s.UpdateBatchProgress(ctx, batchID, "completed", 100.0, len(sessionIDs), totalItems)

	completedAt := time.Now()
	s.db.Model(&models.BatchOCRSession{}).
		Where("id = ?", batchID).
		Updates(map[string]interface{}{
			"status":             "completed",
			"completed_images":   len(sessionIDs),
			"failed_images":      failedCount,
			"total_items_extracted": totalItems,
			"completed_at":       completedAt,
			"updated_at":         time.Now(),
		})

	fmt.Printf("✅ Batch OCR session %s completed: %d/%d images successful, %d items extracted\n", batchID, len(sessionIDs), len(images), totalItems)

	return nil
}

// ProcessSingleImage processes a single image with Vision API or Gemini
func (s *OCRService) ProcessSingleImage(ctx context.Context, batchID, tenantID, userID, shopID, imageData string) (string, error) {
	// 📊 Record request
	metrics := GetOCRMetrics()
	metrics.RecordRequest()
	requestStartTime := time.Now()

	// ✨ Input validation
	if batchID == "" || tenantID == "" || userID == "" || shopID == "" {
		metrics.RecordFailure()
		return "", fmt.Errorf("missing required parameters: batchID, tenantID, userID, or shopID")
	}

	if imageData == "" {
		metrics.RecordFailure()
		return "", fmt.Errorf("empty image data")
	}

	// ✨ Smart image input detection: file path, URL, or base64
	var imageBytes []byte
	var decodeErr error
	var err error // Used for Vision API and Gemini calls

	// Helper function to detect base64 encoded image data
	// JPEG base64 starts with /9j/, PNG with iVBOR, GIF with R0lGO
	isBase64Image := strings.HasPrefix(imageData, "/9j/") || // JPEG
		strings.HasPrefix(imageData, "iVBOR") || // PNG
		strings.HasPrefix(imageData, "R0lGO") || // GIF
		strings.HasPrefix(imageData, "data:image/") // Data URL

	// Check for actual file paths (not base64 that happens to start with /)
	isFilePath := (strings.HasPrefix(imageData, "/") || strings.HasPrefix(imageData, "./")) && !isBase64Image

	if isFilePath {
		// File path - read from disk
		fmt.Printf("📁 [OCR] Reading image from file path: %s\n", imageData)

		// Handle relative paths - prepend working directory if needed
		filePath := imageData
		if strings.HasPrefix(imageData, "/uploads/") {
			// Convert URL-style path to actual file path
			filePath = "." + imageData
		}

		// Resolve to absolute path
		absPath, err := filepath.Abs(filePath)
		if err != nil {
			metrics.RecordFailure()
			return "", fmt.Errorf("failed to resolve file path %s: %w", imageData, err)
		}

		imageBytes, decodeErr = os.ReadFile(absPath)
		if decodeErr != nil {
			metrics.RecordFailure()
			return "", fmt.Errorf("failed to read image file %s: %w", absPath, decodeErr)
		}

		// Convert to base64 for Gemini Vision fallback
		imageData = base64.StdEncoding.EncodeToString(imageBytes)
		fmt.Printf("✅ [OCR] Read %d bytes from file\n", len(imageBytes))

	} else if strings.HasPrefix(imageData, "http://") || strings.HasPrefix(imageData, "https://") {
		// URL - download from remote
		fmt.Printf("🌐 [OCR] Downloading image from URL: %s\n", imageData)

		resp, err := http.Get(imageData)
		if err != nil {
			metrics.RecordFailure()
			return "", fmt.Errorf("failed to download image from %s: %w", imageData, err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			metrics.RecordFailure()
			return "", fmt.Errorf("failed to download image: HTTP %d", resp.StatusCode)
		}

		imageBytes, decodeErr = io.ReadAll(resp.Body)
		if decodeErr != nil {
			metrics.RecordFailure()
			return "", fmt.Errorf("failed to read image response: %w", decodeErr)
		}

		// Convert to base64 for Gemini Vision fallback
		imageData = base64.StdEncoding.EncodeToString(imageBytes)
		fmt.Printf("✅ [OCR] Downloaded %d bytes from URL\n", len(imageBytes))

	} else {
		// Assume base64 encoded image data
		imageBytes, decodeErr = base64.StdEncoding.DecodeString(imageData)
		if decodeErr != nil {
			metrics.RecordFailure()
			return "", fmt.Errorf("invalid base64 image data: %w", decodeErr)
		}
	}

	// Check image size (max 10MB for safety)
	const maxImageSize = 10 * 1024 * 1024 // 10MB
	if len(imageBytes) > maxImageSize {
		metrics.RecordFailure()
		return "", fmt.Errorf("image too large: %d bytes (max %d bytes)", len(imageBytes), maxImageSize)
	}

	if len(imageBytes) < 100 {
		metrics.RecordFailure()
		return "", fmt.Errorf("image too small: %d bytes (likely corrupted)", len(imageBytes))
	}

	fmt.Printf("📸 [OCR] Processing image: %d bytes, batch: %s\n", len(imageBytes), batchID)

	// ✨ MULTI-RECEIPT DETECTION - Check if image contains multiple receipts
	var multiReceiptAnalysis *MultiReceiptAnalysis
	if s.multiReceiptConfig.enableAutoDetection && s.receiptDetector != nil {
		fmt.Println("🔍 [OCR] Running multi-receipt detection...")
		var detectErr error
		multiReceiptAnalysis, detectErr = s.receiptDetector.AnalyzeImage(ctx, imageBytes)
		if detectErr != nil {
			fmt.Printf("⚠️  Multi-receipt detection failed: %v (continuing with single-receipt flow)\n", detectErr)
		} else if multiReceiptAnalysis.NeedsSplitting && len(multiReceiptAnalysis.Regions) > 1 {
			// Multiple receipts detected! Process each region separately
			fmt.Printf("📋 [OCR] MULTI-RECEIPT DETECTED: %d receipts, %d total items (layout: %s)\n",
				multiReceiptAnalysis.ReceiptCount, multiReceiptAnalysis.TotalEstimatedItems, multiReceiptAnalysis.LayoutType)

			// Process multiple receipts - if it fails, continue with normal processing
			sessionID, multiErr := s.processMultiReceipt(ctx, batchID, tenantID, userID, shopID, imageBytes, imageData, multiReceiptAnalysis, metrics, requestStartTime)
			if multiErr == nil {
				return sessionID, nil
			}
			fmt.Printf("⚠️  Multi-receipt processing failed: %v (continuing with enhanced single-receipt extraction)\n", multiErr)
			// Fall through to normal processing with the improved prompt that handles multi-receipts
		} else {
			fmt.Printf("📋 [OCR] Single receipt detected (%d estimated items)\n", multiReceiptAnalysis.TotalEstimatedItems)
		}
	}

	var rawText string
	startTime := time.Now()

	// ============================================================================
	// OCR EXTRACTION PIPELINE (Priority Order):
	// 1. PRIMARY: Google Vision OCR (reliable text extraction)
	// 2. FALLBACK 1: Gemini for brand matching
	// 3. FALLBACK 2: ChatGPT (GPT-4o Vision) if others fail
	// ============================================================================

	// 📸 PRIMARY: GOOGLE VISION OCR - Reliable text extraction
	// Skip ChatGPT and go directly to Google Vision for stability
	if s.visionClient != nil {
		fmt.Println("📸 [OCR] ═══════════════════════════════════════════════")
		fmt.Println("📸 [OCR] PRIMARY: Google Vision OCR")
		fmt.Println("📸 [OCR] ═══════════════════════════════════════════════")

		var googleErr error
		rawText, googleErr = s.visionClient.ExtractTextFromImage(ctx, imageBytes)
		if googleErr != nil {
			fmt.Printf("⚠️  [PRIMARY] Google Vision failed: %v\n", googleErr)
			fmt.Println("🔄 [OCR] Trying Gemini Vision as backup...")
			rawText, googleErr = s.geminiClient.ExtractTextFromImage(ctx, imageData)
			if googleErr != nil {
				fmt.Printf("❌ [PRIMARY] Both Google Vision and Gemini failed: %v\n", googleErr)
			}
		}

		if rawText != "" && len(rawText) > 50 {
			fmt.Printf("✅ [PRIMARY] Google Vision extracted %d characters in %v\n", len(rawText), time.Since(startTime))
			// Continue to text processing for brand matching
			goto processGeminiText
		}
	}

	// 🤖 FALLBACK: OPENAI GPT-4o VISION - Only if Google Vision fails
	// ChatGPT processes the image directly and extracts structured data
	if s.openaiClient != nil && rawText == "" {
		fmt.Println("🤖 [OCR] ═══════════════════════════════════════════════")
		fmt.Println("🤖 [OCR] FALLBACK: ChatGPT (GPT-4o Vision) - Direct Image Processing")
		fmt.Println("🤖 [OCR] ═══════════════════════════════════════════════")

		result, openaiErr := s.openaiClient.ExtractSalesFromImage(ctx, imageBytes, "")
		if openaiErr != nil {
			fmt.Printf("❌ [PRIMARY] ChatGPT GPT-4o failed: %v\n", openaiErr)
			fmt.Println("🔄 [OCR] Moving to FALLBACK 1: Fomoa + Gemini...")
			// Continue to FALLBACK 1 below
		} else if len(result.Items) > 0 {
			// Success! Convert OpenAI result to OCR items and save directly
			fmt.Printf("✅ [PRIMARY] ChatGPT extracted %d items in %v\n", len(result.Items), result.ExtractionTime)

			// Create OCR session for this image
			sessionID := uuid.New().String()
			processedAt := time.Now()
			ocrSession := models.OCRSession{
				ID:             sessionID,
				BatchSessionID: batchID,
				TenantID:       tenantID,
				UserID:         userID,
				ShopID:         shopID,
				Status:         "completed",
				CurrentStage:   "completed",
				RawText:        fmt.Sprintf("ChatGPT GPT-4o extraction: %d items", len(result.Items)),
				OCRProvider:    "chatgpt-gpt4o",
				ProcessedAt:    &processedAt,
			}

			// Parse and store receipt date from extraction
			if result.ReceiptDate != "" {
				// Try multiple date formats
				dateFormats := []string{
					"02/01/2006", "2/1/2006", "02/1/2006", "2/01/2006", // DD/MM/YYYY
					"02-01-2006", "2-1-2006",                             // DD-MM-YYYY
					"02/01/06", "2/1/26", "2/1/06",                       // DD/MM/YY
				}
				for _, format := range dateFormats {
					if parsed, err := time.Parse(format, result.ReceiptDate); err == nil {
						// Handle 2-digit year (assume 2000s)
						if parsed.Year() < 100 {
							parsed = parsed.AddDate(2000, 0, 0)
						}
						ocrSession.ReceiptDate = &parsed
						fmt.Printf("📅 [OCR] Receipt date extracted: %s\n", parsed.Format("2006-01-02"))
						break
					}
				}
			}

			if err := s.db.Create(&ocrSession).Error; err != nil {
				fmt.Printf("⚠️  Failed to create OCR session: %v\n", err)
			}

			// Convert and save OCR items in batch
			ocrItems := s.openaiClient.ConvertToOCRItems(result, sessionID, batchID)
			for i := range ocrItems {
				ocrItems[i].ID = uuid.New().String()
			}
			if len(ocrItems) > 0 {
				s.db.CreateInBatches(&ocrItems, 100)
			}

			// Record success metrics
			processingTimeMS := time.Since(requestStartTime).Milliseconds()
			metrics.RecordSuccess(processingTimeMS)

			return sessionID, nil
		} else {
			fmt.Println("⚠️  [PRIMARY] ChatGPT returned empty result")
			fmt.Println("🔄 [OCR] Moving to FALLBACK 1: Fomoa + Gemini...")
		}
	} else {
		fmt.Println("⚠️  [PRIMARY] ChatGPT not configured (no OPENAI_API_KEY)")
		fmt.Println("🔄 [OCR] Moving to FALLBACK 1: Fomoa + Gemini...")
	}

	// ============================================================================
	// FALLBACK 1: Fomoa + Gemini OCR Text
	// Step 1: Extract text from image using Gemini Vision
	// Step 2: Use Fomoa AI for brand matching (text processing)
	// ============================================================================
	fmt.Println("🔄 [OCR] ═══════════════════════════════════════════════")
	fmt.Println("🔄 [OCR] FALLBACK 1: Fomoa + Gemini OCR Text")
	fmt.Println("🔄 [OCR] ═══════════════════════════════════════════════")

	if s.geminiClient != nil {
		fmt.Println("📸 [FALLBACK 1] Step 1: Extracting text with Gemini Vision...")
		geminiText, geminiErr := s.geminiClient.ExtractTextFromImage(ctx, imageData)
		if geminiErr == nil && len(geminiText) > 50 {
			fmt.Printf("✅ [FALLBACK 1] Gemini extracted %d characters\n", len(geminiText))

			// Store raw text for later use
			rawText = geminiText

			// Note: Fomoa will be used for brand matching in the validation phase
			// The text is extracted here, and Fomoa matches OCR text to products during validation
			fmt.Println("📝 [FALLBACK 1] Text extracted - Fomoa will process during validation")

			// Continue to create session and save items using Gemini extraction
			// The Fomoa AI matching happens in matchOCRItemsToProducts() during validation
			goto processGeminiText
		} else {
			if geminiErr != nil {
				fmt.Printf("❌ [FALLBACK 1] Gemini Vision failed: %v\n", geminiErr)
			} else {
				fmt.Printf("⚠️  [FALLBACK 1] Gemini returned insufficient text (%d chars)\n", len(geminiText))
			}
			fmt.Println("🔄 [OCR] Moving to FALLBACK 2: Google Vision OCR...")
		}
	} else {
		fmt.Println("⚠️  [FALLBACK 1] Gemini not configured (no GEMINI_API_KEY)")
		fmt.Println("🔄 [OCR] Moving to FALLBACK 2: Google Vision OCR...")
	}

	// ============================================================================
	// FALLBACK 2: Google Vision OCR (Complete Google-based pipeline)
	// Uses Google Cloud Vision API for text extraction
	// ============================================================================
	fmt.Println("📸 [OCR] ═══════════════════════════════════════════════")
	fmt.Println("📸 [OCR] FALLBACK 2: Google Vision OCR (Complete)")
	fmt.Println("📸 [OCR] ═══════════════════════════════════════════════")

	if s.visionClient != nil {
		rawText, err = s.visionClient.ExtractTextFromImage(ctx, imageBytes)
		if err != nil {
			metrics.RecordVisionAPICall(false)
			fmt.Printf("❌ [FALLBACK 2] Google Cloud Vision failed: %v\n", err)

			// Final fallback: try Gemini Vision if Cloud Vision fails
			fmt.Println("🔍 [FALLBACK 2] Last resort: Gemini Vision...")
			rawText, err = s.geminiClient.ExtractTextFromImage(ctx, imageData)
			if err != nil {
				metrics.RecordFailure()
				return "", fmt.Errorf("all OCR providers failed (ChatGPT, Gemini, Google Vision): %w", err)
			}
			fmt.Printf("✅ [FALLBACK 2] Gemini Vision extracted %d characters\n", len(rawText))
		} else {
			metrics.RecordVisionAPICall(true)
			fmt.Printf("✅ [FALLBACK 2] Google Vision extracted %d characters in %v\n", len(rawText), time.Since(startTime))
		}
	} else {
		// No Cloud Vision client available
		fmt.Println("⚠️  [FALLBACK 2] Google Vision not configured")
		metrics.RecordFailure()
		return "", fmt.Errorf("all OCR providers failed - Google Vision not configured")
	}

	// ============================================================================
	// PROCESS EXTRACTED TEXT (Common path for Gemini and Google Vision)
	// ============================================================================
processGeminiText:
	fmt.Printf("📝 [OCR] Processing extracted text (%d characters)...\n", len(rawText))

	// Determine which OCR provider was used based on the flow
	var ocrProvider string
	if s.geminiClient != nil && rawText != "" {
		// If we got here via FALLBACK 1, it was Gemini + Fomoa
		ocrProvider = "gemini+fomoa"
	}
	if s.visionClient != nil && ocrProvider == "" {
		// If we got here via FALLBACK 2, it was Google Vision
		ocrProvider = "google-vision"
	}
	if ocrProvider == "" {
		ocrProvider = "fallback"
	}
	fmt.Printf("📝 [OCR] OCR Provider: %s\n", ocrProvider)

	// ✨ Apply preprocessing to clean Indic numerals and artifacts
	preprocessedText := preprocessVisionText(rawText)
	fmt.Printf("🔍 [DEBUG] After preprocessing: %d chars (removed %d chars)\n", len(preprocessedText), len(rawText)-len(preprocessedText))
	rawText = preprocessedText

	// Store base64 image data temporarily for table extraction
	// This will be used by ExtractItemsDirect for Vision API table detection
	imageDataJSON := fmt.Sprintf(`{"image_data": "%s"}`, imageData)

	session := &models.OCRSession{
		ID:                 uuid.New().String(),
		BatchSessionID:     batchID,
		TenantID:           tenantID,
		UserID:             userID,
		ShopID:             shopID,
		ImageURL:           "",
		ImageSize:          len(imageBytes),
		ImageType:          "image/jpeg",
		Status:             "completed",
		CurrentStage:       "completed",
		ProgressPercentage: 100,
		RawText:            rawText,
		OCRProvider:        ocrProvider, // Track which OCR provider was used
		ExtractedData:      imageDataJSON,
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	if err := s.db.Create(session).Error; err != nil {
		metrics.RecordFailure()
		return "", fmt.Errorf("failed to save OCR session: %w", err)
	}

	// 📊 Record success with processing time
	processingTimeMS := time.Since(requestStartTime).Milliseconds()
	metrics.RecordSuccess(processingTimeMS)

	return session.ID, nil
}

// processMultiReceipt handles images containing multiple receipt pages
// OPTIMIZED: Splits side-by-side receipts into separate images and processes in parallel
// This approach is more accurate and cost-effective than asking one API call to handle both
func (s *OCRService) processMultiReceipt(ctx context.Context, batchID, tenantID, userID, shopID string,
	imageBytes []byte, imageData string, analysis *MultiReceiptAnalysis,
	metrics *OCRMetrics, requestStartTime time.Time) (string, error) {

	fmt.Printf("📋 [OCR] Processing multi-receipt image: %d receipts detected, layout: %s\n",
		analysis.ReceiptCount, analysis.LayoutType)
	fmt.Printf("   Expected items: %d across %d receipt(s)\n",
		analysis.TotalEstimatedItems, analysis.ReceiptCount)

	// Log detected regions
	for i, region := range analysis.Regions {
		fmt.Printf("   Region %d: position=%s, estimated_items=%d, confidence=%.1f%%\n",
			i+1, region.Position, region.EstimatedItems, region.Confidence)
	}

	// Check if OpenAI is available
	if !s.useOpenAI || s.openaiClient == nil {
		return "", fmt.Errorf("OpenAI client not available for multi-receipt processing")
	}

	// STRATEGY: For side-by-side layout, split image and process each half in parallel
	// This is more accurate and uses less tokens per request
	if analysis.LayoutType == "side-by-side" && s.imageProcessor != nil {
		fmt.Println("✂️  [OCR] OPTIMIZED: Splitting side-by-side image for parallel processing")
		return s.processMultiReceiptWithSplitting(ctx, batchID, tenantID, userID, shopID,
			imageBytes, analysis, metrics, requestStartTime)
	}

	// Fallback for other layouts or if image processor unavailable: use multi-receipt prompt
	fmt.Println("🤖 [OCR] Using multi-receipt prompt (no splitting)")
	return s.processMultiReceiptWithPrompt(ctx, batchID, tenantID, userID, shopID,
		imageBytes, analysis, metrics, requestStartTime)
}

// processMultiReceiptWithSplitting splits image and processes each half in parallel
// BEST PRACTICE: Each API call handles one receipt = simpler, more accurate, cost-effective
func (s *OCRService) processMultiReceiptWithSplitting(ctx context.Context, batchID, tenantID, userID, shopID string,
	imageBytes []byte, analysis *MultiReceiptAnalysis,
	metrics *OCRMetrics, requestStartTime time.Time) (string, error) {

	// Split image horizontally (left and right halves)
	splitImages, err := s.imageProcessor.SplitImageHorizontally(imageBytes)
	if err != nil {
		fmt.Printf("⚠️  Image splitting failed: %v (falling back to multi-receipt prompt)\n", err)
		return s.processMultiReceiptWithPrompt(ctx, batchID, tenantID, userID, shopID,
			imageBytes, analysis, metrics, requestStartTime)
	}

	if len(splitImages) != 2 {
		fmt.Printf("⚠️  Expected 2 split images, got %d (falling back to multi-receipt prompt)\n", len(splitImages))
		return s.processMultiReceiptWithPrompt(ctx, batchID, tenantID, userID, shopID,
			imageBytes, analysis, metrics, requestStartTime)
	}

	fmt.Printf("✂️  [OCR] Split image into 2 halves: LEFT=%dx%d (%d bytes), RIGHT=%dx%d (%d bytes)\n",
		splitImages[0].CroppedSize.X, splitImages[0].CroppedSize.Y, len(splitImages[0].ImageData),
		splitImages[1].CroppedSize.X, splitImages[1].CroppedSize.Y, len(splitImages[1].ImageData))

	// Process both halves in parallel using goroutines
	type extractionResult struct {
		index  int
		result *ExtractionResult
		err    error
	}

	resultChan := make(chan extractionResult, 2)
	prompt := s.openaiClient.buildSingleReceiptPrompt()

	// Launch parallel extraction
	for i, splitImg := range splitImages {
		go func(idx int, imgData []byte) {
			position := "LEFT"
			if idx == 1 {
				position = "RIGHT"
			}
			fmt.Printf("🚀 [Parallel] Starting extraction for %s receipt...\n", position)

			result, err := s.openaiClient.ExtractSalesFromImageWithPrompt(ctx, imgData, "", prompt)
			if err != nil {
				fmt.Printf("⚠️  [Parallel] %s receipt extraction failed: %v\n", position, err)
			} else {
				fmt.Printf("✅ [Parallel] %s receipt: extracted %d items in %v\n",
					position, len(result.Items), result.ExtractionTime)
			}
			resultChan <- extractionResult{index: idx, result: result, err: err}
		}(i, splitImg.ImageData)
	}

	// Collect results
	var leftResult, rightResult *ExtractionResult
	var leftErr, rightErr error

	for i := 0; i < 2; i++ {
		res := <-resultChan
		if res.index == 0 {
			leftResult, leftErr = res.result, res.err
		} else {
			rightResult, rightErr = res.result, res.err
		}
	}

	// Merge results
	var allItems []ExtractedSalesRow
	var totalAmount float64
	var warnings []string

	// Add left receipt items
	if leftErr != nil {
		warnings = append(warnings, fmt.Sprintf("Left receipt extraction failed: %v", leftErr))
	} else if leftResult != nil {
		for _, item := range leftResult.Items {
			item.Notes = "from left receipt"
			allItems = append(allItems, item)
		}
		totalAmount += leftResult.TotalAmount
		fmt.Printf("📝 [Merge] Added %d items from LEFT receipt (₹%.2f)\n", len(leftResult.Items), leftResult.TotalAmount)
	}

	// Add right receipt items with continued row numbering
	if rightErr != nil {
		warnings = append(warnings, fmt.Sprintf("Right receipt extraction failed: %v", rightErr))
	} else if rightResult != nil {
		baseRowNumber := len(allItems)
		for _, item := range rightResult.Items {
			item.RowNumber = baseRowNumber + item.RowNumber
			item.Notes = "from right receipt"
			allItems = append(allItems, item)
		}
		totalAmount += rightResult.TotalAmount
		fmt.Printf("📝 [Merge] Added %d items from RIGHT receipt (₹%.2f) starting at row %d\n",
			len(rightResult.Items), rightResult.TotalAmount, baseRowNumber+1)
	}

	// Check if we got enough items
	if len(allItems) == 0 {
		return "", fmt.Errorf("no items extracted from either receipt half")
	}

	expectedMinItems := analysis.TotalEstimatedItems / 2
	if len(allItems) < expectedMinItems && expectedMinItems > 10 {
		warnings = append(warnings,
			fmt.Sprintf("Extracted %d items but expected at least %d - some items may be missing",
				len(allItems), analysis.TotalEstimatedItems))
	}

	fmt.Printf("✅ [MultiReceipt-Split] Total: %d items, ₹%.2f (from %d receipts processed in parallel)\n",
		len(allItems), totalAmount, analysis.ReceiptCount)

	// Create merged result
	mergedResult := &ExtractionResult{
		ReceiptType: "HALF", // Default for 180ml receipts
		Items:       allItems,
		TotalItems:  len(allItems),
		TotalAmount: totalAmount,
		ModelUsed:   "gpt-4o-split-parallel",
		Warnings:    warnings,
	}

	// Save to database
	return s.saveMultiReceiptResult(batchID, tenantID, userID, shopID, mergedResult,
		analysis, metrics, requestStartTime)
}

// processMultiReceiptWithPrompt uses enhanced prompt for multi-receipt extraction (fallback)
func (s *OCRService) processMultiReceiptWithPrompt(ctx context.Context, batchID, tenantID, userID, shopID string,
	imageBytes []byte, analysis *MultiReceiptAnalysis,
	metrics *OCRMetrics, requestStartTime time.Time) (string, error) {

	fmt.Println("🤖 [OCR] Using OpenAI GPT-4o Vision with MULTI-RECEIPT prompt")

	prompt := s.openaiClient.buildMultiReceiptPrompt()
	result, openaiErr := s.openaiClient.ExtractSalesFromImageWithPrompt(ctx, imageBytes, "", prompt)
	if openaiErr != nil {
		fmt.Printf("⚠️  OpenAI GPT-4o failed for multi-receipt: %v\n", openaiErr)
		return "", fmt.Errorf("multi-receipt extraction failed: %w", openaiErr)
	}

	// Validate extraction count
	expectedMinItems := analysis.TotalEstimatedItems / 2
	if len(result.Items) < expectedMinItems && expectedMinItems > 10 {
		fmt.Printf("⚠️  [MultiReceipt] Only extracted %d items but expected at least %d\n",
			len(result.Items), expectedMinItems)
		result.Warnings = append(result.Warnings,
			fmt.Sprintf("Extracted %d items but %d+ were expected - some items may be missing",
				len(result.Items), analysis.TotalEstimatedItems))
	}

	fmt.Printf("✅ [MultiReceipt-Prompt] Extracted %d items from %d-receipt image in %v\n",
		len(result.Items), analysis.ReceiptCount, result.ExtractionTime)

	return s.saveMultiReceiptResult(batchID, tenantID, userID, shopID, result,
		analysis, metrics, requestStartTime)
}

// saveMultiReceiptResult saves the extraction result to database
func (s *OCRService) saveMultiReceiptResult(batchID, tenantID, userID, shopID string,
	result *ExtractionResult, analysis *MultiReceiptAnalysis,
	metrics *OCRMetrics, requestStartTime time.Time) (string, error) {

	sessionID := uuid.New().String()
	processedAt := time.Now()

	ocrSession := models.OCRSession{
		ID:             sessionID,
		BatchSessionID: batchID,
		TenantID:       tenantID,
		UserID:         userID,
		ShopID:         shopID,
		Status:         "completed",
		CurrentStage:   "completed",
		RawText: fmt.Sprintf("Multi-receipt extraction (%s): %d items from %d receipts, model=%s",
			analysis.LayoutType, len(result.Items), analysis.ReceiptCount, result.ModelUsed),
		OCRProvider: "openai-gpt4o-multi",
		ProcessedAt: &processedAt,
	}

	if err := s.db.Create(&ocrSession).Error; err != nil {
		fmt.Printf("⚠️  Failed to create OCR session: %v\n", err)
	}

	// Convert and save OCR items
	ocrItems := s.openaiClient.ConvertToOCRItems(result, sessionID, batchID)
	for i := range ocrItems {
		ocrItems[i].ID = uuid.New().String()
		if err := s.db.Create(&ocrItems[i]).Error; err != nil {
			fmt.Printf("⚠️  Failed to save OCR item: %v\n", err)
		}
	}

	fmt.Printf("✅ [MultiReceipt] Saved %d items to database (session: %s)\n", len(ocrItems), sessionID)

	// Record success metrics
	processingTimeMS := time.Since(requestStartTime).Milliseconds()
	metrics.RecordSuccess(processingTimeMS)

	return sessionID, nil
}

// ExtractItemsWithGemini extracts and normalizes items using Gemini AI
func (s *OCRService) ExtractItemsWithGemini(ctx context.Context, sessionID string) ([]models.OCRItem, error) {
	var session models.OCRSession
	if err := s.db.Where("id = ?", sessionID).First(&session).Error; err != nil {
		return nil, fmt.Errorf("failed to get OCR session: %w", err)
	}

	fmt.Printf("📊 [Gemini] Extracting items from %d characters of raw text...\n", len(session.RawText))

	// 📊 Get metrics
	metrics := GetOCRMetrics()

	extractedBrands, err := s.geminiClient.ExtractAndNormalizeBrands(ctx, session.RawText)
	if err != nil {
		metrics.RecordGeminiAPICall(false, 0)
		return nil, fmt.Errorf("gemini extraction failed: %w", err)
	}
	metrics.RecordGeminiAPICall(true, 0) // Retries tracked in gemini_client

	fmt.Printf("📊 [Gemini] Extracted %d potential items from text\n", len(extractedBrands))

	// 🔧 Phase 1.5: Detailed extraction summary for debugging
	fmt.Printf("┌─────────────────────────────────────────────────────────────────┐\n")
	fmt.Printf("│ Gemini Extraction Results (Total: %d items)                     \n", len(extractedBrands))
	fmt.Printf("├─────────────────────────────────────────────────────────────────┤\n")
	for i, brand := range extractedBrands {
		validIcon := "✅"
		if !brand.IsValidBrand {
			validIcon = "❌"
		}
		priceStr := "N/A"
		if brand.Price > 0 {
			priceStr = fmt.Sprintf("₹%.0f", brand.Price)
		}
		sizeStr := brand.Size
		if sizeStr == "" {
			sizeStr = "N/A"
		}
		fmt.Printf("│ %s #%d: %-25s | Size: %-6s | Price: %-8s | Qty: %d\n",
			validIcon, i+1, truncateString(brand.NormalizedName, 25), sizeStr, priceStr, brand.Quantity)
		if !brand.IsValidBrand && brand.RejectionReason != "" {
			fmt.Printf("│      Rejected: %s\n", brand.RejectionReason)
		}
	}
	fmt.Printf("└─────────────────────────────────────────────────────────────────┘\n")

	items := make([]models.OCRItem, 0, len(extractedBrands))
	rejectedItems := make([]models.RejectedOCRItem, 0) // Track rejected items
	filteredCount := 0
	itemsWithGarbage := 0
	itemsCleaned := 0

	for i, brand := range extractedBrands {
		// 🔧 FIX: Track invalid items but DON'T filter them - let user review and fix
		// Instead of filtering, mark them for review
		needsReviewDueToValidation := false
		validationWarnings := []string{}

		if !brand.IsValidBrand || strings.TrimSpace(brand.NormalizedName) == "" {
			needsReviewDueToValidation = true
			fmt.Printf("⚠️  [OCR] Item needs review: original='%s', normalized='%s', is_valid=%v, reason='%s'\n",
				brand.OriginalText, brand.NormalizedName, brand.IsValidBrand, brand.RejectionReason)

			// Add to rejected items list for tracking but DON'T skip - continue processing
			rejectedItem := models.RejectedOCRItem{
				BrandText:         brand.NormalizedName,
				SizeText:          brand.Size,
				Quantity:          brand.Quantity,
				SellingPrice:      &brand.Price,
				RejectionReason:   brand.RejectionReason,
				RejectionStage:    "gemini_validation",
				OriginalRowNumber: i + 1,
				Confidence:        brand.Confidence,
				CanRecover:        true,
			}
			if brand.RejectionReason == "" {
				rejectedItem.RejectionReason = "Failed Gemini validation"
			}
			rejectedItems = append(rejectedItems, rejectedItem)

			// Add warning but DON'T filter out
			if brand.RejectionReason != "" {
				validationWarnings = append(validationWarnings, "Validation: "+brand.RejectionReason)
			} else {
				validationWarnings = append(validationWarnings, "Needs brand name review")
			}
			// DON'T continue - let user fix it
		}

		// ✨ FIXED: Use normalized_name (already clean) for brand_text instead of original_text (contaminated with row data)
		// Gemini extraction returns:
		//   - original_text: Full OCR row with all columns (e.g., "27 13 | 90 | 1170 Royal Stag")
		//   - normalized_name: Clean brand name only (e.g., "Royal Stag")
		// We want the clean brand name, not the contaminated full row!
		cleanedBrandText := cleanBrandName(brand.NormalizedName)
		cleanedNormalizedName := cleanBrandName(brand.NormalizedName)

		// Track cleaning metrics
		if cleanedBrandText != brand.NormalizedName {
			itemsWithGarbage++
			itemsCleaned++
			fmt.Printf("🧹 [OCR] Cleaned brand: '%s' → '%s'\n", brand.NormalizedName, cleanedBrandText)
		}

		// ✅ FIX 3: Apply normalization EARLY (before validation and saving)
		// This fixes incomplete names like "Mc. Dowell No." → "McDowell's No.1"
		// and misspellings like "Absolute" → "Absolut"
		normalizedBrandName, normErr := s.geminiClient.NormalizeBrandName(ctx, cleanedBrandText)
		if normErr == nil && normalizedBrandName != "" && normalizedBrandName != "INVALID" {
			if normalizedBrandName != cleanedBrandText {
				fmt.Printf("   🔧 [Normalization] '%s' → '%s'\n", cleanedBrandText, normalizedBrandName)
				cleanedBrandText = normalizedBrandName
				cleanedNormalizedName = normalizedBrandName
			}
		} else if normErr != nil {
			fmt.Printf("   ⚠️  [Normalization] Failed for '%s': %v\n", cleanedBrandText, normErr)
			// Continue with original cleaned name
		}

		// ✨ Validation and logging for debugging
		price := brand.Price
		confidence := brand.Confidence

		// 💰 BACKEND PRICE CALCULATION: ALWAYS calculate price using row isolation for verification
		// This ensures we use row-specific numbers instead of Gemini's potentially incorrect column identification
		if session.RawText != "" {
			calculatedPrice := calculatePriceFromRawText(session.RawText, brand.OriginalText)

			if calculatedPrice > 0 {
				// If Gemini didn't return a price, use the calculated one
				if price == 0 {
					price = calculatedPrice
					fmt.Printf("   ✅ [Price Calc] Using backend-calculated price: ₹%.2f (Gemini returned 0)\n", price)
				} else {
					// If Gemini returned a price, compare with our row-isolated calculation
					priceDiff := math.Abs(price - calculatedPrice)
					percentDiff := (priceDiff / math.Max(price, calculatedPrice)) * 100

					// If prices differ by more than 15%, trust the backend calculation (row-isolated)
					if percentDiff > 15 {
						fmt.Printf("   ⚠️  [Price Calc] Gemini price (₹%.2f) differs from row-isolated price (₹%.2f) by %.1f%%\n",
							price, calculatedPrice, percentDiff)
						fmt.Printf("   ✅ [Price Calc] Using row-isolated backend price: ₹%.2f\n", calculatedPrice)
						price = calculatedPrice
					} else {
						fmt.Printf("   ✅ [Price Calc] Gemini price (₹%.2f) matches backend calculation (₹%.2f), using Gemini\n",
							price, calculatedPrice)
					}
				}
			} else if price == 0 {
				fmt.Printf("   ⚠️  [Price Calc] Both Gemini and backend calculation returned 0 for: %s\n", brand.OriginalText)
			}
		}

		// ✅ NEW: Validate price for anomalies using SIZE-AWARE validation
		if price > 0 {
			isValid, validationReason := validatePriceWithSize(price, brand.Size, cleanedBrandText)
			if !isValid {
				fmt.Printf("   ⚠️  [Price Validation] ANOMALY DETECTED: %s\n", validationReason)
				fmt.Printf("   📋 [Price Validation] Brand: '%s', Size: %s, Extracted Price: ₹%.2f\n", cleanedBrandText, brand.Size, price)
				fmt.Printf("   💡 [Price Validation] This item will be flagged for manual review\n")

				// Reduce confidence but don't reject the item
				confidence = math.Max(confidence-30.0, 40.0)
			}
		}

		// 🔧 Phase 3.1: Cross-field validation
		detectedReceiptSize := detectReceiptType(session.RawText)
		crossValidation := validateCrossFields(&brand, detectedReceiptSize)
		if !crossValidation.IsValid {
			// 🔧 FIX: DON'T filter - mark for review and let user fix
			fmt.Printf("   ⚠️  [Cross-Field Validation] Item needs review (failed validation)\n")
			for _, issue := range crossValidation.Issues {
				fmt.Printf("      - %s\n", issue)
				validationWarnings = append(validationWarnings, "Math: "+issue)
			}
			fmt.Printf("   📝 [OCR] Item added for manual review instead of filtering\n")
			needsReviewDueToValidation = true
			// DON'T continue - let user fix it
		} else if len(crossValidation.Issues) > 0 {
			fmt.Printf("   ⚠️  [Cross-Field Validation] Found %d warnings:\n", crossValidation.WarningCount)
			for _, issue := range crossValidation.Issues {
				fmt.Printf("      - %s\n", issue)
			}
			// Reduce confidence for warnings
			if crossValidation.WarningCount > 0 {
				confidencePenalty := float64(crossValidation.WarningCount) * 10.0
				confidence = math.Max(confidence-confidencePenalty, 50.0)
				fmt.Printf("   📉 [Confidence] Reduced by %.0f%% due to validation warnings (new: %.0f%%)\n",
					confidencePenalty, confidence)
			}
		} else {
			fmt.Printf("   ✅ [Cross-Field Validation] All checks passed\n")
		}

		// Log extracted data for debugging
		fmt.Printf("📋 [OCR] Extracted item #%d:\n", i+1)
		fmt.Printf("   Brand: '%s'\n", cleanedBrandText)
		fmt.Printf("   Size: '%s' (from Gemini)\n", brand.Size)
		fmt.Printf("   Quantity: %d\n", brand.Quantity)
		fmt.Printf("   Price: %.2f\n", price)
		fmt.Printf("   Category: '%s' (confidence: %.0f%%)\n", brand.Category, brand.CategoryConfidence)
		fmt.Printf("   Subcategory: '%s'\n", brand.Subcategory)
		fmt.Printf("   Original text: '%s'\n", brand.OriginalText)

		// 🔧 Phase 1.2: Add missing field defaults with fallback extraction
		itemSize := brand.Size
		itemQuantity := brand.Quantity
		itemPrice := price

		// Fallback 1: If size is missing, detect from raw text
		if itemSize == "" {
			detectedSize := detectReceiptType(session.RawText)
			if detectedSize != "" {
				itemSize = detectedSize
				fmt.Printf("🔧 [OCR] Fixed missing size for '%s': detected '%s' from header\n", cleanedBrandText, detectedSize)
			}
		}

		// Fallback 2: If price is 0 or very low, try backend calculation
		if itemPrice == 0 || (itemPrice > 0 && itemPrice < 10) {
			backendPrice := calculatePriceFromRawText(session.RawText, brand.OriginalText)
			if backendPrice > 0 {
				itemPrice = backendPrice
				fmt.Printf("🔧 [OCR] Fixed missing/invalid price for '%s': calculated ₹%.2f from backend\n", cleanedBrandText, backendPrice)
			}
		}

		// CRITICAL VALIDATION: Flag items with zero price for manual review
		// Instead of rejecting, mark them for review so users can fix the price
		receiptType := detectReceiptType(session.RawText)
		needsPriceReview := false
		if itemPrice == 0 && (strings.Contains(receiptType, "SALE") || strings.Contains(receiptType, "STOCK")) {
			fmt.Printf("⚠️  [Validation] WARNING: %s - Price is 0 for stock/sale receipt (needs manual review)\n", cleanedBrandText)
			fmt.Printf("   📋 Receipt Type: %s\n", receiptType)
			fmt.Printf("   💡 Item added for manual price review - extraction failed for both Gemini and backend\n")
			// Don't skip - mark for review with lower confidence
			needsPriceReview = true
			confidence = 30.0 // Low confidence for items needing price review
		}

		// Fallback 3: If quantity is 0, try to extract closing stock from original text
		if itemQuantity == 0 && brand.OriginalText != "" {
			// Extract numbers from the original text row
			numbers := extractNumbersFromRow(brand.OriginalText)
			if len(numbers) > 0 {
				// Closing stock is typically the last number in the row
				closingStock := int(numbers[len(numbers)-1])
				if closingStock > 0 && closingStock < 10000 {  // Sanity check
					itemQuantity = closingStock
					fmt.Printf("🔧 [OCR] Fixed missing quantity for '%s': extracted %d from row\n", cleanedBrandText, closingStock)
				}
			}
		}

		// Prepare category confidence
		categoryConfidence := brand.CategoryConfidence

		// CONFIDENCE-BASED FILTERING: Categorize items based on confidence levels
		// High confidence (>60%) - Auto-accept
		// Medium confidence (40-60%) - Flag for review
		// Low confidence (<40%) - Consider rejecting or heavy review needed
		var needsConfidenceReview bool
		var confidenceBasedSelection bool

		if confidence < 40 {
			// Low confidence - needs manual review, deselect by default
			needsConfidenceReview = true
			confidenceBasedSelection = false
			fmt.Printf("⚠️  [Confidence] LOW confidence (%.1f%%) for '%s' - needs review\n", confidence, cleanedBrandText)
		} else if confidence >= 40 && confidence < 60 {
			// Medium confidence - flag for review but keep selected
			needsConfidenceReview = true
			confidenceBasedSelection = true
			fmt.Printf("🔍 [Confidence] MEDIUM confidence (%.1f%%) for '%s' - review recommended\n", confidence, cleanedBrandText)
		} else {
			// High confidence - auto-accept
			needsConfidenceReview = false
			confidenceBasedSelection = true
			fmt.Printf("✅ [Confidence] HIGH confidence (%.1f%%) for '%s' - auto-accepted\n", confidence, cleanedBrandText)
		}

		// Combine with price review flag
		shouldBeSelected := confidenceBasedSelection && !needsPriceReview
		// Track if item needs any review (for future use)
		// needsAnyReview := needsPriceReview || needsConfidenceReview

		// Phase 1: Map all 7 columns from Gemini extraction
		// Use extracted values if available, fallback to legacy fields
		openingStock := brand.OpeningStock
		receiptQty := brand.ReceiptQty
		totalStock := brand.TotalStock
		saleQuantity := brand.SaleQuantity
		rate := brand.Rate
		amount := brand.Amount
		closingStock := brand.ClosingStock

		// Fallback: If rate is 0 but we calculated itemPrice, use itemPrice
		if rate == 0 && itemPrice > 0 {
			rate = itemPrice
		}
		// Fallback: If closingStock is 0 but we have itemQuantity, use itemQuantity
		if closingStock == 0 && itemQuantity > 0 {
			closingStock = itemQuantity
		}

		// Log the complete row data extraction
		fmt.Printf("   📊 Complete Row Data: Opening=%d, Receipt=%d, Total=%d, Sale=%d, Rate=%.2f, Amount=%.2f, Closing=%d\n",
			openingStock, receiptQty, totalStock, saleQuantity, rate, amount, closingStock)

		// Log mathematical validation status from Gemini
		if brand.IsTotalValid && brand.IsClosingValid && brand.IsAmountValid {
			fmt.Printf("   ✅ [Math Validation] All calculations valid (from Gemini)\n")
		} else {
			if !brand.IsTotalValid {
				fmt.Printf("   ⚠️  [Math Validation] Total calculation mismatch\n")
			}
			if !brand.IsClosingValid {
				fmt.Printf("   ⚠️  [Math Validation] Closing calculation mismatch\n")
			}
			if !brand.IsAmountValid {
				fmt.Printf("   ⚠️  [Math Validation] Amount calculation mismatch\n")
			}
			if brand.MathValidationNotes != "" {
				fmt.Printf("   📝 [Math Notes] %s\n", brand.MathValidationNotes)
			}
		}

		// Map field confidences if available
		var fieldConfidences *models.FieldConfidenceScores
		if brand.FieldConfidences != nil {
			fieldConfidences = &models.FieldConfidenceScores{
				Brand:   brand.FieldConfidences.Brand,
				Opening: brand.FieldConfidences.Opening,
				Receipt: brand.FieldConfidences.Receipt,
				Total:   brand.FieldConfidences.Total,
				Sale:    brand.FieldConfidences.Sale,
				Rate:    brand.FieldConfidences.Rate,
				Amount:  brand.FieldConfidences.Amount,
				Closing: brand.FieldConfidences.Closing,
			}
			fmt.Printf("   📈 Field Confidences: Brand=%.0f%%, Opening=%.0f%%, Rate=%.0f%%, Closing=%.0f%%\n",
				fieldConfidences.Brand, fieldConfidences.Opening, fieldConfidences.Rate, fieldConfidences.Closing)
		}

		// 🔧 FIX: Items needing validation review should be deselected but still included
		shouldSelect := shouldBeSelected && !needsConfidenceReview && !needsReviewDueToValidation

		// Build verification notes from validation warnings
		verificationNotes := ""
		if len(validationWarnings) > 0 {
			verificationNotes = strings.Join(validationWarnings, "; ")
		}

		// Set verification status based on validation
		verificationStatus := "pending"
		if needsReviewDueToValidation {
			verificationStatus = "needs_review"
		}

		item := models.OCRItem{
			ID:                     uuid.New().String(),
			SessionID:              sessionID,
			BatchID:                session.BatchSessionID,
			RowNumber:              brand.RowNumber,          // Use actual row number from Gemini
			BrandText:              cleanedBrandText,
			NormalizedBrandName:    cleanedNormalizedName,
			SizeText:               itemSize,                 // Use fallback value

			// ===== COMPLETE ROW DATA (7 Columns) =====
			OpeningStock:           openingStock,             // Column 1
			ReceiptQty:             receiptQty,               // Column 2
			TotalStock:             totalStock,               // Column 3
			SaleQuantity:           saleQuantity,             // Column 4
			Rate:                   rate,                     // Column 5 (₹ per bottle)
			Amount:                 amount,                   // Column 6 (Sale × Rate)
			ClosingStock:           closingStock,             // Column 7

			// Legacy fields for backward compatibility
			Quantity:               closingStock,             // Alias for ClosingStock
			SellingPrice:           &rate,                    // Alias for Rate

			// ===== MATHEMATICAL VALIDATION FLAGS =====
			IsTotalValid:           brand.IsTotalValid,
			IsClosingValid:         brand.IsClosingValid,
			IsAmountValid:          brand.IsAmountValid,
			MathValidationNotes:    brand.MathValidationNotes,

			// ===== FIELD-LEVEL CONFIDENCE =====
			FieldConfidences:       fieldConfidences,
			MatchConfidence:        &confidence,

			// ===== CATEGORY INFERENCE =====
			InferredCategoryName:   brand.Category,
			InferredSubcategoryName: brand.Subcategory,
			CategoryConfidence:     &categoryConfidence,

			// ===== VERIFICATION & STATUS FLAGS =====
			VerificationStatus:     verificationStatus,
			VerificationNotes:      verificationNotes, // Store validation warnings for user review
			IsReviewed:             false, // Items start as unreviewed
			IsSelected:             shouldSelect, // Deselect items that need validation review
			CreatedAt:              time.Now(),
			UpdatedAt:              time.Now(),
		}

		// Use actual row number if available, fallback to loop index
		if brand.RowNumber == 0 {
			item.RowNumber = i + 1
		}

		// ✨ Validate the cleaned item with detailed rejection info
		validationResult := validateExtractedItemWithReason(&item)
		if !validationResult.IsValid {
			// 🔧 FIX: DON'T filter - mark for review and let user fix
			fmt.Printf("⚠️  [OCR] Item needs review after cleaning: brand='%s' - %s\n", cleanedBrandText, validationResult.Reason)

			// Add to rejected items for tracking but DON'T skip
			rejectedItem := models.RejectedOCRItem{
				BrandText:         cleanedBrandText,
				SizeText:          itemSize,
				Quantity:          itemQuantity,
				SellingPrice:      &itemPrice,
				RejectionReason:   validationResult.Reason,
				RejectionStage:    validationResult.Stage,
				OriginalRowNumber: i + 1,
				Confidence:        confidence,
				CanRecover:        validationResult.CanRecover,
			}
			rejectedItems = append(rejectedItems, rejectedItem)

			// Mark item as needing review but DON'T filter out
			needsReviewDueToValidation = true
			validationWarnings = append(validationWarnings, "Validation: "+validationResult.Reason)
			item.IsSelected = false // Deselect by default for invalid items

			// Update item's verification notes and status with the additional warnings
			item.VerificationStatus = "needs_review"
			item.VerificationNotes = strings.Join(validationWarnings, "; ")
			// DON'T continue - let user fix it
		}

		// 🏷️  Infer category and subcategory based on brand name and price
		if categoryMatch, err := s.InferCategory(ctx, session.TenantID, cleanedBrandText, &price); err == nil {
			item.InferredCategoryID = &categoryMatch.CategoryID
			item.InferredCategoryName = categoryMatch.CategoryName
			item.CategoryConfidence = &categoryMatch.Confidence
			if categoryMatch.SubcategoryID != nil {
				item.InferredSubcategoryID = categoryMatch.SubcategoryID
				item.InferredSubcategoryName = categoryMatch.PriceRange
			}
			fmt.Printf("🏷️  [OCR] Inferred category: %s", categoryMatch.CategoryName)
			if categoryMatch.SubcategoryID != nil {
				fmt.Printf(" > %s", categoryMatch.PriceRange)
			}
			fmt.Printf(" (confidence: %.1f%%)\n", categoryMatch.Confidence)
		} else {
			fmt.Printf("⚠️  [OCR] Category inference failed for '%s': %v\n", cleanedBrandText, err)
		}

		if err := s.db.Create(&item).Error; err != nil {
			return nil, fmt.Errorf("failed to save OCR item: %w", err)
		}

		items = append(items, item)
	}

	// 🔧 FIX: All items are now included - filteredCount only counts items added to rejectedItems list for tracking
	fmt.Printf("✅ [OCR] Created %d items total (including %d needing review)\n", len(items), len(rejectedItems))

	// Store rejected items in cache for later retrieval
	if len(rejectedItems) > 0 && session.BatchSessionID != "" {
		s.storeRejectedItems(session.BatchSessionID, rejectedItems)
		fmt.Printf("📋 [OCR] %d rejected items stored for batch %s (can be retrieved in review screen)\n",
			len(rejectedItems), session.BatchSessionID)
	}

	// 📊 Record extraction metrics
	totalExtracted := len(extractedBrands)
	validItems := len(items)
	invalidItems := filteredCount
	metrics.RecordItemExtraction(totalExtracted, validItems, invalidItems, itemsWithGarbage, itemsCleaned)

	return items, nil
}

// ExtractItemsDirect extracts items directly from raw OCR text WITHOUT using Gemini
// Uses Vision API table detection + regex parsing fallback
func (s *OCRService) ExtractItemsDirect(ctx context.Context, sessionID, imageData string) ([]models.OCRItem, error) {
	var session models.OCRSession
	if err := s.db.Where("id = ?", sessionID).First(&session).Error; err != nil {
		return nil, fmt.Errorf("failed to get OCR session: %w", err)
	}

	fmt.Printf("📊 [Direct Extraction] Processing session %s...\n", sessionID)
	fmt.Printf("   Raw text length: %d characters\n", len(session.RawText))

	// STEP 1: Detect receipt type (size)
	receiptType := detectReceiptType(session.RawText)
	fmt.Printf("📋 [Direct Extraction] Detected receipt type: %s\n", receiptType)

	var items []models.OCRItem

	// STEP 2: Try Vision API table extraction first (hybrid approach)
	var imageBytes []byte
	var imageErr error

	if imageData != "" {
		// Image data provided as base64
		imageBytes, imageErr = base64.StdEncoding.DecodeString(imageData)
	} else if session.ExtractedData != "" && session.ExtractedData != "{}" {
		// Extract base64 image from ExtractedData JSON
		fmt.Println("📥 [Direct Extraction] Extracting image from session data...")
		var data map[string]string
		if err := json.Unmarshal([]byte(session.ExtractedData), &data); err == nil {
			if base64Image, ok := data["image_data"]; ok && base64Image != "" {
				imageBytes, imageErr = base64.StdEncoding.DecodeString(base64Image)
				if imageErr == nil {
					imageData = base64Image  // Store base64 for Gemini Vision fallback
					fmt.Printf("✅ [Direct Extraction] Extracted %d bytes of image data\n", len(imageBytes))
				}
			}
		}
	} else if session.ImageURL != "" {
		// Fetch image from URL (if available)
		fmt.Printf("📥 [Direct Extraction] Fetching image from URL: %s\n", session.ImageURL)
		imageBytes, imageErr = s.fetchImageFromURL(session.ImageURL)
		if imageErr == nil && len(imageBytes) > 0 {
			imageData = base64.StdEncoding.EncodeToString(imageBytes)  // Convert for Gemini Vision fallback
		}
	}

	if imageErr == nil && len(imageBytes) > 0 {
		fmt.Println("📊 [Direct Extraction] Attempting Vision API table detection...")
		tableData, err := s.visionClient.ExtractTableData(ctx, imageBytes)
		if err == nil && tableData != nil && len(tableData.Rows) > 0 {
			fmt.Printf("✅ [Direct Extraction] Vision API extracted %d rows\n", len(tableData.Rows))
			items = s.parseTableDataToItems(tableData, sessionID, session.BatchSessionID, receiptType)
		} else {
			fmt.Printf("⚠️  [Direct Extraction] Vision API table extraction failed or returned no rows: %v\n", err)
		}
	} else if imageErr != nil {
		fmt.Printf("⚠️  [Direct Extraction] Failed to get image data: %v\n", imageErr)
	}

	// STEP 3: Fallback to Gemini Vision if Vision API table parsing failed
	if len(items) == 0 && len(imageBytes) > 0 && imageData != "" {
		// Detect if this is a beer format document
		invoiceFormat := detect180mlFormat(session.RawText)

		if invoiceFormat == "beer" {
			// Use specialized Beer Register extraction
			fmt.Println("🍺 [Direct Extraction] Detected BEER format - using specialized extraction...")
			beerResp, rawText, beerErr := s.geminiClient.ExtractBeerRegister(ctx, imageData)

			if beerErr == nil && beerResp != nil && len(beerResp.Sections) > 0 {
				// Process structured beer response
				globalRowNum := 0
				for _, section := range beerResp.Sections {
					fmt.Printf("   📋 Section: %s (%d items)\n", section.Name, len(section.Items))
					for _, beerItem := range section.Items {
						globalRowNum++
						rate := beerItem.Rate
						confidence := 95.0 // High confidence for structured JSON extraction

						item := models.OCRItem{
							ID:                 uuid.New().String(),
							SessionID:          sessionID,
							BatchID:            session.BatchSessionID,
							RowNumber:          globalRowNum,
							BrandText:          beerItem.Brand,
							SizeText:           beerItem.Size,
							OpeningStock:       beerItem.Opening,
							SaleQuantity:       beerItem.Sale,
							Quantity:           beerItem.Closing,
							Rate:               rate,           // Column 5 - Rate per bottle
							SellingPrice:       &rate,
							MatchConfidence:    &confidence,
							IsReviewed:         false,
							IsSelected:         true,
							MatchStrategy:      "gemini_beer_json",
							VerificationStatus: "pending",
							CreatedAt:          time.Now(),
							UpdatedAt:          time.Now(),
						}
						if validateExtractedItem(&item) {
							items = append(items, item)
						}
					}
				}
				fmt.Printf("✅ [Direct Extraction] Beer JSON extracted %d items\n", len(items))
			} else if rawText != "" {
				// Fallback to regex parsing of the raw text
				fmt.Printf("⚠️  [Direct Extraction] Beer JSON parsing failed, falling back to regex...\n")
				parsedRows := s.parseInvoiceWithRegex(rawText, receiptType)
				for _, row := range parsedRows {
					item := models.OCRItem{
						ID:                 uuid.New().String(),
						SessionID:          sessionID,
						BatchID:            session.BatchSessionID,
						RowNumber:          row.RowNumber,
						BrandText:          row.BrandName,
						SizeText:           receiptType,
						OpeningStock:       row.Opening,
						SaleQuantity:       row.Sale,
						Quantity:           row.Closing,
						Rate:               row.Rate,  // Column 5 - Rate per bottle
						SellingPrice:       &row.Rate,
						MatchConfidence:    &row.Confidence,
						IsReviewed:         false,
						IsSelected:         true,
						MatchStrategy:      "gemini_vision",
						VerificationStatus: "pending",
						CreatedAt:          time.Now(),
						UpdatedAt:          time.Now(),
					}
					if validateExtractedItem(&item) {
						items = append(items, item)
					}
				}
			}
		} else {
			// Standard extraction for non-beer formats
			fmt.Println("🤖 [Direct Extraction] Falling back to Gemini Vision for complex table...")
			geminiText, geminiErr := s.geminiClient.ExtractTextFromImage(ctx, imageData)
			if geminiErr == nil && geminiText != "" {
				fmt.Printf("✅ [Direct Extraction] Gemini Vision extracted %d chars\n", len(geminiText))
				// Parse the Gemini output with regex
				parsedRows := s.parseInvoiceWithRegex(geminiText, receiptType)
				if len(parsedRows) > 0 {
					fmt.Printf("✅ [Direct Extraction] Gemini+Regex parsed %d rows\n", len(parsedRows))
					for _, row := range parsedRows {
						item := models.OCRItem{
							ID:                 uuid.New().String(),
							SessionID:          sessionID,
							BatchID:            session.BatchSessionID,
							RowNumber:          row.RowNumber,
							BrandText:          row.BrandName,
							SizeText:           receiptType,
							OpeningStock:       row.Opening,
							SaleQuantity:       row.Sale,
							Quantity:           row.Closing,
							Rate:               row.Rate,  // Column 5 - Rate per bottle
							SellingPrice:       &row.Rate,
							MatchConfidence:    &row.Confidence,
							IsReviewed:         false,
							IsSelected:         true,
							MatchStrategy:      "gemini_vision",
							VerificationStatus: "pending",
							CreatedAt:          time.Now(),
							UpdatedAt:          time.Now(),
						}
						if validateExtractedItem(&item) {
							items = append(items, item)
						}
					}
				}
			} else {
				fmt.Printf("⚠️  [Direct Extraction] Gemini Vision failed: %v\n", geminiErr)
			}
		}
	}

	// STEP 4: Fallback to regex parsing of raw text if all else failed
	if len(items) == 0 && session.RawText != "" {
		fmt.Println("🔧 [Direct Extraction] Falling back to regex parsing of raw text...")
		parsedRows := s.parseInvoiceWithRegex(session.RawText, receiptType)

		if len(parsedRows) > 0 {
			fmt.Printf("✅ [Direct Extraction] Regex parsed %d rows\n", len(parsedRows))

			// Convert parsed rows to OCR items
			for _, row := range parsedRows {
				item := models.OCRItem{
					ID:              uuid.New().String(),
					SessionID:       sessionID,
					BatchID:         session.BatchSessionID,
					RowNumber:       row.RowNumber,
					BrandText:       row.BrandName,
					SizeText:        receiptType,
					OpeningStock:    row.Opening,
					SaleQuantity:    row.Sale,
					Quantity:        row.Closing,
					Rate:            row.Rate,  // Column 5 - Rate per bottle
					SellingPrice:    &row.Rate,
					MatchConfidence: &row.Confidence,
					IsReviewed:      false,
					IsSelected:      true,
					MatchStrategy:   "regex_direct",  // No Gemini involved
					VerificationStatus: "pending",
					CreatedAt:       time.Now(),
					UpdatedAt:       time.Now(),
				}

				// Validate item
				if validateExtractedItem(&item) {
					items = append(items, item)
				} else {
					fmt.Printf("🗑️  [Direct Extraction] Filtered invalid item: %s\n", row.BrandName)
				}
			}
		} else {
			fmt.Println("❌ [Direct Extraction] Regex parsing found no valid rows")
		}
	}

	// STEP 5: Use Gemini ONLY for category inference (not extraction)
	fmt.Printf("🏷️  [Direct Extraction] Inferring categories for %d items...\n", len(items))
	for i := range items {
		item := &items[i]

		// Infer category using Gemini (ONLY step where Gemini is used)
		price := 0.0
		if item.SellingPrice != nil {
			price = *item.SellingPrice
		}

		if categoryMatch, err := s.InferCategory(ctx, session.TenantID, item.BrandText, &price); err == nil {
			item.InferredCategoryID = &categoryMatch.CategoryID
			item.InferredCategoryName = categoryMatch.CategoryName
			item.CategoryConfidence = &categoryMatch.Confidence
			if categoryMatch.SubcategoryID != nil {
				item.InferredSubcategoryID = categoryMatch.SubcategoryID
				item.InferredSubcategoryName = categoryMatch.PriceRange
			}
			fmt.Printf("   🏷️  Item %d: %s → %s (%.0f%% confidence)\n",
				item.RowNumber, item.BrandText, categoryMatch.CategoryName, categoryMatch.Confidence)
		} else {
			fmt.Printf("   ⚠️  Item %d: Category inference failed for '%s': %v\n", item.RowNumber, item.BrandText, err)
		}

		// Save item to database
		if err := s.db.Create(item).Error; err != nil {
			fmt.Printf("   ❌ Failed to save item %d: %v\n", item.RowNumber, err)
			continue
		}
	}

	fmt.Printf("✅ [Direct Extraction] Completed: %d items extracted and saved\n", len(items))

	// STEP 6: Run verification and gap detection
	if len(items) > 0 && session.BatchSessionID != "" {
		fmt.Println("\n🔍 [Direct Extraction] Running post-extraction verification...")
		s.verifyOCRItems(ctx, session.BatchSessionID)
		s.detectGapsInExtraction(ctx, session.BatchSessionID)
	}

	return items, nil
}

// PerformIntelligentMatching performs intelligent brand matching using Gemini
func (s *OCRService) PerformIntelligentMatching(ctx context.Context, batchID string) error {
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchID).Find(&items).Error; err != nil {
		return fmt.Errorf("failed to get items: %w", err)
	}

	// ✨ STEP 1: Normalize brand names BEFORE matching to fix OCR errors
	fmt.Println("🔄 [OCR] Step 1/3: Normalizing brand names to fix OCR errors...")
	normalizedCount := 0
	for i, item := range items {
		if item.BrandText == "" {
			continue
		}

		normalized, err := s.geminiClient.NormalizeBrandName(ctx, item.BrandText)
		if err != nil {
			fmt.Printf("⚠️  Failed to normalize '%s': %v\n", item.BrandText, err)
			continue
		}

		if normalized != "" && normalized != item.NormalizedBrandName {
			items[i].NormalizedBrandName = normalized
			s.db.Model(&models.OCRItem{}).
				Where("id = ?", item.ID).
				Update("normalized_brand_name", normalized)

			fmt.Printf("  ✓ Fixed: '%s' → '%s'\n", item.BrandText, normalized)
			normalizedCount++
		}
	}
	fmt.Printf("✅ Normalized %d brand names\n\n", normalizedCount)

	// STEP 2: Get available brands
	fmt.Println("🔄 [OCR] Step 2/3: Loading available brands from inventory...")
	availableBrands, err := s.getAvailableBrands(ctx)
	if err != nil {
		return fmt.Errorf("failed to get available brands: %w", err)
	}

	brandNames := make([]string, len(availableBrands))
	for i, brand := range availableBrands {
		brandNames[i] = brand.Name
	}
	fmt.Printf("✅ Loaded %d brands from inventory\n\n", len(availableBrands))

	// STEP 3: Intelligent matching with stricter thresholds
	fmt.Println("🔄 [OCR] Step 3/3: Matching brands with confidence verification...")
	matchedCount := 0
	reviewCount := 0

	for _, item := range items {
		if item.MatchedBrandID != nil {
			continue
		}

		matches, err := s.geminiClient.FindBrandMatches(ctx, item.NormalizedBrandName, brandNames)
		if err != nil {
			fmt.Printf("⚠️  Failed to find matches for '%s': %v\n", item.BrandText, err)
			continue
		}

		if len(matches) > 0 {
			bestMatch := matches[0]

			// Find the brand ID
			var brandID string
			for _, brand := range availableBrands {
				if brand.Name == bestMatch.BrandName {
					brandID = brand.ID
					break
				}
			}

			if brandID == "" {
				continue
			}

			// ✨ NEW: Apply stricter confidence thresholds with fuzzy verification
			confidence := bestMatch.Confidence
			strategy := "gemini_smart"
			needsReview := false

			// Verify match with Levenshtein distance
			distance := levenshteinDistance(
				strings.ToLower(item.NormalizedBrandName),
				strings.ToLower(bestMatch.BrandName),
			)

			// Downgrade confidence if strings are too different
			if distance > 3 {
				fmt.Printf("⚠️  Fuzzy check failed: distance=%d for '%s' → '%s'\n",
					distance, item.NormalizedBrandName, bestMatch.BrandName)
				confidence = math.Max(confidence-20.0, 50.0)
			}

			// Apply confidence-based logic
			if confidence >= 85.0 {
				// High confidence: Auto-match
				fmt.Printf("  ✅ High confidence: '%s' → '%s' (%.1f%%)\n",
					item.BrandText, bestMatch.BrandName, confidence)
				matchedCount++
			} else if confidence >= 70.0 {
				// Medium confidence: Flag for review
				fmt.Printf("  ⚠️  Needs review: '%s' → '%s' (%.1f%%)\n",
					item.BrandText, bestMatch.BrandName, confidence)
				needsReview = true
				strategy = "gemini_low_confidence"
				reviewCount++
			} else {
				// Low confidence: Skip
				fmt.Printf("  ❌ Too low: '%s' → '%s' (%.1f%%)\n",
					item.BrandText, bestMatch.BrandName, confidence)
				continue
			}

			// ✨ NEW: Try to match variant by brand + size
			variantID := s.findMatchingVariant(ctx, brandID, item.SizeText)

			// Update database with brand and optionally variant
			updates := map[string]interface{}{
				"matched_brand_id": brandID,
				"match_confidence": confidence,
				"match_strategy":   strategy,
				"is_reviewed":      false, // Reset review flag
				"updated_at":       time.Now(),
			}

			if variantID != "" {
				updates["matched_variant_id"] = variantID
				fmt.Printf("     ✓ Matched variant: %s\n", item.SizeText)
			}

			s.db.Model(&models.OCRItem{}).
				Where("id = ?", item.ID).
				Updates(updates)

			// Mark for manual review if needed
			if needsReview {
				s.db.Model(&models.OCRItem{}).
					Where("id = ?", item.ID).
					Update("is_reviewed", false) // Ensures manual review
			}
		}
	}

	fmt.Printf("\n✅ Matching complete:\n")
	fmt.Printf("   • Auto-matched (85%%+): %d items\n", matchedCount)
	fmt.Printf("   • Needs review (70-85%%): %d items\n", reviewCount)
	fmt.Printf("   • Total processed: %d items\n\n", len(items))

	return nil
}

// levenshteinDistance calculates the Levenshtein distance between two strings
func levenshteinDistance(s1, s2 string) int {
	if len(s1) == 0 {
		return len(s2)
	}
	if len(s2) == 0 {
		return len(s1)
	}

	// Create matrix
	matrix := make([][]int, len(s1)+1)
	for i := range matrix {
		matrix[i] = make([]int, len(s2)+1)
		matrix[i][0] = i
	}
	for j := range matrix[0] {
		matrix[0][j] = j
	}

	// Fill matrix
	for i := 1; i <= len(s1); i++ {
		for j := 1; j <= len(s2); j++ {
			cost := 0
			if s1[i-1] != s2[j-1] {
				cost = 1
			}

			matrix[i][j] = min3(
				matrix[i-1][j]+1,      // deletion
				matrix[i][j-1]+1,      // insertion
				matrix[i-1][j-1]+cost, // substitution
			)
		}
	}

	return matrix[len(s1)][len(s2)]
}

// min3 returns the minimum of three integers
func min3(a, b, c int) int {
	if a < b {
		if a < c {
			return a
		}
		return c
	}
	if b < c {
		return b
	}
	return c
}

// PerformFuzzyMatching performs simple fuzzy brand matching without Gemini
// Uses only Levenshtein distance for string similarity
func (s *OCRService) PerformFuzzyMatching(ctx context.Context, batchID string) error {
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchID).Find(&items).Error; err != nil {
		return fmt.Errorf("failed to get items: %w", err)
	}

	fmt.Printf("🔄 [Fuzzy Matching] Processing %d items...\n", len(items))

	// Load available brands from inventory
	availableBrands, err := s.getAvailableBrands(ctx)
	if err != nil {
		return fmt.Errorf("failed to get available brands: %w", err)
	}

	fmt.Printf("📊 [Fuzzy Matching] Loaded %d brands from inventory\n", len(availableBrands))

	matchedCount := 0
	noMatchCount := 0

	for _, item := range items {
		// Skip already matched items
		if item.MatchedBrandID != nil {
			continue
		}

		brandText := strings.ToLower(strings.TrimSpace(item.BrandText))
		if brandText == "" {
			continue
		}

		// Find best match using Levenshtein distance
		var bestMatch string
		var bestBrandID string
		var bestVariantID string
		minDistance := 999999
		maxSimilarity := 0.0

		for _, brand := range availableBrands {
			brandName := strings.ToLower(strings.TrimSpace(brand.Name))

			// Calculate Levenshtein distance
			distance := levenshteinDistance(brandText, brandName)

			// Calculate similarity score (0-100)
			maxLen := math.Max(float64(len(brandText)), float64(len(brandName)))
			similarity := 0.0
			if maxLen > 0 {
				similarity = (1.0 - float64(distance)/maxLen) * 100.0
			}

			// Check if this is the best match so far
			if similarity > maxSimilarity && distance <= 5 {  // Distance threshold
				maxSimilarity = similarity
				minDistance = distance
				bestMatch = brand.Name
				bestBrandID = brand.ID

				// Try to find matching variant by size
				bestVariantID = s.findMatchingVariant(ctx, brand.ID, item.SizeText)
			}
		}

		// Apply matching based on similarity threshold
		if maxSimilarity >= 75.0 {  // 75% similarity required
			confidence := maxSimilarity
			strategy := "fuzzy_direct"

			// High confidence (90%+): Auto-match
			if confidence >= 90.0 {
				fmt.Printf("  ✅ High confidence: '%s' → '%s' (%.1f%%, distance=%d)\n",
					item.BrandText, bestMatch, confidence, minDistance)
			} else {
				// Medium confidence (75-90%): Flag for review
				fmt.Printf("  ⚠️  Needs review: '%s' → '%s' (%.1f%%, distance=%d)\n",
					item.BrandText, bestMatch, confidence, minDistance)
			}

			// Update database
			updates := map[string]interface{}{
				"matched_brand_id": bestBrandID,
				"match_confidence": confidence,
				"match_strategy":   strategy,
				"is_reviewed":      false,
				"updated_at":       time.Now(),
			}

			if bestVariantID != "" {
				updates["matched_variant_id"] = bestVariantID
				fmt.Printf("     ✓ Matched variant: %s\n", item.SizeText)
			}

			s.db.Model(&models.OCRItem{}).
				Where("id = ?", item.ID).
				Updates(updates)

			matchedCount++
		} else {
			fmt.Printf("  ❌ No good match: '%s' (best: '%s' at %.1f%%)\n",
				item.BrandText, bestMatch, maxSimilarity)
			noMatchCount++
		}
	}

	fmt.Printf("\n✅ Fuzzy matching complete:\n")
	fmt.Printf("   • Matched: %d items\n", matchedCount)
	fmt.Printf("   • No match: %d items\n", noMatchCount)
	fmt.Printf("   • Total processed: %d items\n\n", len(items))

	// Step 4: Verify items against inventory
	fmt.Println("🔍 [Verification] Verifying extracted items against inventory...")
	s.verifyOCRItems(ctx, batchID)

	return nil
}

// verifyOCRItems verifies extracted OCR items against current inventory
func (s *OCRService) verifyOCRItems(ctx context.Context, batchSessionID string) {
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchSessionID).Find(&items).Error; err != nil {
		fmt.Printf("⚠️  [Verification] Failed to load items: %v\n", err)
		return
	}

	verifiedCount := 0
	mismatchCount := 0

	for _, item := range items {
		var notes []string
		status := "verified"

		// Check 1: Validate math (Opening - Sale = Closing, assuming no receipts for daily sales)
		expectedClosing := item.OpeningStock - item.SaleQuantity
		if item.Quantity != expectedClosing && item.SaleQuantity > 0 {
			notes = append(notes, fmt.Sprintf("Math check: Opening(%d) - Sale(%d) = %d, but Closing is %d",
				item.OpeningStock, item.SaleQuantity, expectedClosing, item.Quantity))
			status = "mismatch"
		}

		// Check 2: If brand matched, verify against inventory stock
		if item.MatchedBrandID != nil && *item.MatchedBrandID != "" {
			var currentStock int
			err := s.db.Table("brand_variants").
				Select("COALESCE(current_stock, 0)").
				Where("brand_id = ?", *item.MatchedBrandID).
				Limit(1).
				Scan(&currentStock).Error

			if err == nil && currentStock > 0 {
				// Compare Opening stock with current inventory
				// Allow some tolerance (within 10% or 5 units)
				diff := item.OpeningStock - currentStock
				if diff < 0 {
					diff = -diff
				}
				tolerance := currentStock / 10
				if tolerance < 5 {
					tolerance = 5
				}
				if diff > tolerance {
					notes = append(notes, fmt.Sprintf("Stock mismatch: OCR Opening=%d, Inventory=%d (diff=%d)",
						item.OpeningStock, currentStock, item.OpeningStock-currentStock))
					status = "mismatch"
				}
			}
		}

		// Check 3: Validate quantities are reasonable
		if item.OpeningStock < 0 || item.SaleQuantity < 0 || item.Quantity < 0 {
			notes = append(notes, "Negative quantity detected")
			status = "mismatch"
		}

		// Check 4: Sale quantity shouldn't exceed opening stock
		if item.SaleQuantity > item.OpeningStock && item.OpeningStock > 0 {
			notes = append(notes, fmt.Sprintf("Sale(%d) exceeds Opening(%d)", item.SaleQuantity, item.OpeningStock))
			status = "mismatch"
		}

		// Check 5: Validate rate is within expected range for the category
		if item.SellingPrice != nil {
			rate := *item.SellingPrice
			// Beer rates typically between 100-350
			// IMFL rates typically between 50-2000
			if strings.Contains(strings.ToLower(item.SizeText), "ml") {
				if rate > 0 && (rate < 50 || rate > 2500) {
					notes = append(notes, fmt.Sprintf("Rate %.2f seems unusual", rate))
					// Don't mark as mismatch, just note
				}
			}
		}

		// Check 6: Validate brand name exists in inventory (fuzzy match)
		if item.MatchedBrandID == nil || *item.MatchedBrandID == "" {
			// Try to find a matching brand by name
			var matchedBrandID string
			var matchConfidence float64
			brandName := strings.ToUpper(strings.TrimSpace(item.BrandText))

			// Check if brand exists with similar name
			var brands []struct {
				ID   string
				Name string
			}
			s.db.Table("brands").
				Select("id, name").
				Where("tenant_id = ?", item.SessionID). // This might need adjustment
				Find(&brands)

			for _, brand := range brands {
				similarity := calculateSimilarity(brandName, strings.ToUpper(brand.Name))
				if similarity > matchConfidence && similarity >= 0.7 {
					matchedBrandID = brand.ID
					matchConfidence = similarity
				}
			}

			if matchedBrandID != "" && matchConfidence >= 0.7 {
				// Update the matched brand
				s.db.Model(&models.OCRItem{}).
					Where("id = ?", item.ID).
					Updates(map[string]interface{}{
						"matched_brand_id":  matchedBrandID,
						"match_confidence":  matchConfidence * 100,
						"match_strategy":    "post_verification_fuzzy",
					})
				notes = append(notes, fmt.Sprintf("Auto-matched to brand (%.0f%% confidence)", matchConfidence*100))
			}
		}

		// Update verification status
		notesStr := strings.Join(notes, "; ")
		s.db.Model(&models.OCRItem{}).
			Where("id = ?", item.ID).
			Updates(map[string]interface{}{
				"verification_status": status,
				"verification_notes":  notesStr,
			})

		if status == "verified" {
			verifiedCount++
			fmt.Printf("  ✅ Verified: %s (Opening: %d, Sale: %d, Closing: %d)\n",
				item.BrandText, item.OpeningStock, item.SaleQuantity, item.Quantity)
		} else {
			mismatchCount++
			fmt.Printf("  ⚠️  Mismatch: %s - %s\n", item.BrandText, notesStr)
		}
	}

	fmt.Printf("\n✅ Verification complete:\n")
	fmt.Printf("   • Verified: %d items\n", verifiedCount)
	fmt.Printf("   • Mismatches: %d items\n", mismatchCount)
}

// GapReport represents a report of missing or problematic rows
type GapReport struct {
	TotalExtracted   int      `json:"total_extracted"`
	ExpectedRows     int      `json:"expected_rows"`
	MissingRows      []int    `json:"missing_rows"`
	DuplicateRows    []int    `json:"duplicate_rows"`
	GapPercentage    float64  `json:"gap_percentage"`
	QualityScore     float64  `json:"quality_score"` // 0-100
	Recommendations  []string `json:"recommendations"`
}

// detectGapsInExtraction analyzes extracted items for missing row numbers
func (s *OCRService) detectGapsInExtraction(ctx context.Context, batchSessionID string) *GapReport {
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchSessionID).Order("row_number").Find(&items).Error; err != nil {
		fmt.Printf("⚠️  [Gap Detection] Failed to load items: %v\n", err)
		return nil
	}

	if len(items) == 0 {
		return &GapReport{
			TotalExtracted: 0,
			QualityScore:   0,
			Recommendations: []string{"No items were extracted. Please try re-uploading the image."},
		}
	}

	// Find the maximum row number to determine expected range
	maxRow := 0
	rowSet := make(map[int]int) // row_number -> count
	for _, item := range items {
		if item.RowNumber > maxRow {
			maxRow = item.RowNumber
		}
		rowSet[item.RowNumber]++
	}

	// Detect gaps (missing row numbers)
	var missingRows []int
	for i := 1; i <= maxRow; i++ {
		if _, exists := rowSet[i]; !exists {
			missingRows = append(missingRows, i)
		}
	}

	// Detect duplicates
	var duplicateRows []int
	for row, count := range rowSet {
		if count > 1 {
			duplicateRows = append(duplicateRows, row)
		}
	}

	report := &GapReport{
		TotalExtracted: len(items),
		ExpectedRows:   maxRow,
		MissingRows:    missingRows,
		DuplicateRows:  duplicateRows,
	}

	// Calculate gap percentage
	if maxRow > 0 {
		report.GapPercentage = float64(len(missingRows)) / float64(maxRow) * 100
	}

	// Calculate quality score (100 = perfect, 0 = terrible)
	if maxRow > 0 {
		// Base score on extraction completeness
		completeness := float64(len(items)) / float64(maxRow) * 100
		// Penalize for duplicates
		duplicatePenalty := float64(len(duplicateRows)) * 2
		report.QualityScore = completeness - duplicatePenalty
		if report.QualityScore < 0 {
			report.QualityScore = 0
		}
		if report.QualityScore > 100 {
			report.QualityScore = 100
		}
	}

	// Generate recommendations
	if len(missingRows) > 0 {
		if len(missingRows) <= 5 {
			report.Recommendations = append(report.Recommendations,
				fmt.Sprintf("Missing rows: %v - manual review recommended", missingRows))
		} else {
			report.Recommendations = append(report.Recommendations,
				fmt.Sprintf("%d rows missing - document may need re-scan with better lighting", len(missingRows)))
		}
	}

	if len(duplicateRows) > 0 {
		report.Recommendations = append(report.Recommendations,
			fmt.Sprintf("Duplicate rows detected: %v - review and remove duplicates", duplicateRows))
	}

	if report.QualityScore == 100 {
		report.Recommendations = append(report.Recommendations, "Excellent extraction quality - no gaps detected")
	} else if report.QualityScore >= 90 {
		report.Recommendations = append(report.Recommendations, "Good extraction quality with minor gaps")
	} else if report.QualityScore >= 70 {
		report.Recommendations = append(report.Recommendations, "Moderate extraction quality - some manual review needed")
	} else {
		report.Recommendations = append(report.Recommendations, "Poor extraction quality - consider re-scanning document")
	}

	// Log the gap report
	fmt.Printf("\n📊 [Gap Detection] Analysis for batch %s:\n", batchSessionID)
	fmt.Printf("   • Extracted rows: %d\n", report.TotalExtracted)
	fmt.Printf("   • Expected rows (max row number): %d\n", report.ExpectedRows)
	fmt.Printf("   • Missing rows: %d (%.1f%%)\n", len(missingRows), report.GapPercentage)
	if len(missingRows) > 0 && len(missingRows) <= 10 {
		fmt.Printf("   • Missing row numbers: %v\n", missingRows)
	}
	if len(duplicateRows) > 0 {
		fmt.Printf("   • Duplicate rows: %v\n", duplicateRows)
	}
	fmt.Printf("   • Quality score: %.1f%%\n", report.QualityScore)

	return report
}

// Brand represents a brand for matching
type Brand struct {
	ID   string `gorm:"column:id"`
	Name string `gorm:"column:name"`
}

// getAvailableBrands gets all available brands from inventory
func (s *OCRService) getAvailableBrands(ctx context.Context) ([]Brand, error) {
	var brands []Brand
	if err := s.db.Table("brands").Select("id, name").Order("name").Find(&brands).Error; err != nil {
		return nil, err
	}
	return brands, nil
}

// findMatchingVariant finds a matching variant by brand ID and size
func (s *OCRService) findMatchingVariant(ctx context.Context, brandID string, sizeText string) string {
	if sizeText == "" {
		return ""
	}

	// Normalize size text for comparison
	normalizedSize := strings.ToLower(strings.TrimSpace(sizeText))

	// Common size variations mapping
	sizeVariations := map[string][]string{
		"90ml":    {"90ml", "90 ml", "90", "nip"},
		"180ml":   {"180ml", "180 ml", "180", "quarter", "quart"},
		"375ml":   {"375ml", "375 ml", "375", "half", "pint"},
		"750ml":   {"750ml", "750 ml", "750", "full", "bottle"},
		"1000ml":  {"1000ml", "1000 ml", "1l", "1 l", "litre", "liter"},
		"50ml":    {"50ml", "50 ml", "50", "mini"},
		"60ml":    {"60ml", "60 ml", "60"},
		"650ml":   {"650ml", "650 ml", "650"},
	}

	// Find which standard size this matches
	var standardSize string
	for stdSize, variations := range sizeVariations {
		for _, variation := range variations {
			if normalizedSize == strings.ToLower(variation) {
				standardSize = stdSize
				break
			}
		}
		if standardSize != "" {
			break
		}
	}

	// If no standard size found, use the original
	if standardSize == "" {
		standardSize = normalizedSize
	}

	// Query variants table for matching brand + size
	type Variant struct {
		ID   string `gorm:"column:id"`
		Size string `gorm:"column:size"`
	}

	var variants []Variant
	if err := s.db.Table("variants").
		Select("id, size").
		Where("brand_id = ?", brandID).
		Find(&variants).Error; err != nil {
		return ""
	}

	// Try exact match first
	for _, variant := range variants {
		variantSize := strings.ToLower(strings.TrimSpace(variant.Size))
		if variantSize == standardSize || variantSize == normalizedSize {
			return variant.ID
		}
	}

	// Try fuzzy match with size variations
	for _, variant := range variants {
		variantSize := strings.ToLower(strings.TrimSpace(variant.Size))

		// Check if variant size matches any variation
		for _, variations := range sizeVariations {
			matchesStandard := false
			matchesVariant := false

			for _, variation := range variations {
				if strings.ToLower(variation) == normalizedSize {
					matchesStandard = true
				}
				if strings.ToLower(variation) == variantSize {
					matchesVariant = true
				}
			}

			if matchesStandard && matchesVariant {
				return variant.ID
			}
		}
	}

	return ""
}

// GetBatchSession retrieves a batch session
func (s *OCRService) GetBatchSession(ctx context.Context, batchID string) (*models.BatchOCRSession, error) {
	var session models.BatchOCRSession
	if err := s.db.Where("id = ?", batchID).First(&session).Error; err != nil {
		return nil, fmt.Errorf("failed to get batch session: %w", err)
	}

	// Fetch session IDs for this batch
	var ocrSessions []models.OCRSession
	fmt.Printf("🔍 [GetBatchSession] Fetching OCR sessions for batch: %s\n", batchID)
	if err := s.db.Where("batch_session_id = ?", batchID).
		Select("id").
		Find(&ocrSessions).Error; err != nil {
		// Log error but don't fail the request
		fmt.Printf("⚠️ Warning: Failed to fetch session IDs for batch %s: %v\n", batchID, err)
	} else {
		// Populate session IDs
		sessionIDs := make([]string, len(ocrSessions))
		for i, s := range ocrSessions {
			sessionIDs[i] = s.ID
		}
		session.SessionIDs = sessionIDs
		fmt.Printf("✅ [GetBatchSession] Found %d OCR sessions for batch %s\n", len(sessionIDs), batchID)
		if len(sessionIDs) > 0 {
			fmt.Printf("📋 [GetBatchSession] Session IDs: %v\n", sessionIDs)
		}
	}

	return &session, nil
}

// GetBatchItems retrieves all OCR items for a batch session
func (s *OCRService) GetBatchItems(ctx context.Context, batchID string) ([]models.OCRItem, error) {
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchID).Order("row_number").Find(&items).Error; err != nil {
		return nil, fmt.Errorf("failed to get batch items: %w", err)
	}
	return items, nil
}

// GetQualityMetrics calculates quality metrics for a batch session
func (s *OCRService) GetQualityMetrics(ctx context.Context, batchID string) map[string]interface{} {
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchID).Order("row_number").Find(&items).Error; err != nil {
		return nil
	}

	if len(items) == 0 {
		return map[string]interface{}{
			"total_items":      0,
			"quality_score":    0.0,
			"verified_count":   0,
			"mismatch_count":   0,
			"missing_rows":     []int{},
			"recommendations":  []string{"No items extracted"},
		}
	}

	// Count verification status
	verifiedCount := 0
	mismatchCount := 0
	pendingCount := 0
	for _, item := range items {
		switch item.VerificationStatus {
		case "verified":
			verifiedCount++
		case "mismatch":
			mismatchCount++
		default:
			pendingCount++
		}
	}

	// Find missing row numbers
	maxRow := 0
	rowSet := make(map[int]bool)
	for _, item := range items {
		if item.RowNumber > maxRow {
			maxRow = item.RowNumber
		}
		rowSet[item.RowNumber] = true
	}

	var missingRows []int
	for i := 1; i <= maxRow; i++ {
		if !rowSet[i] {
			missingRows = append(missingRows, i)
		}
	}

	// Calculate quality score
	qualityScore := 100.0
	if maxRow > 0 {
		// Penalize for missing rows
		qualityScore = float64(len(items)) / float64(maxRow) * 100
		// Penalize for mismatches (5% per mismatch)
		qualityScore -= float64(mismatchCount) * 5
		if qualityScore < 0 {
			qualityScore = 0
		}
	}

	// Generate recommendations
	var recommendations []string
	if len(missingRows) > 0 {
		if len(missingRows) <= 5 {
			recommendations = append(recommendations, fmt.Sprintf("Missing rows: %v - review document", missingRows))
		} else {
			recommendations = append(recommendations, fmt.Sprintf("%d rows missing - consider re-scanning", len(missingRows)))
		}
	}
	if mismatchCount > 0 {
		recommendations = append(recommendations, fmt.Sprintf("%d items have math errors - review quantities", mismatchCount))
	}
	if qualityScore >= 95 {
		recommendations = append(recommendations, "Excellent extraction quality")
	} else if qualityScore >= 80 {
		recommendations = append(recommendations, "Good extraction quality")
	} else if qualityScore >= 60 {
		recommendations = append(recommendations, "Moderate quality - manual review recommended")
	} else {
		recommendations = append(recommendations, "Low quality - consider re-scanning document")
	}

	return map[string]interface{}{
		"total_items":      len(items),
		"quality_score":    qualityScore,
		"verified_count":   verifiedCount,
		"mismatch_count":   mismatchCount,
		"pending_count":    pendingCount,
		"missing_rows":     missingRows,
		"max_row_number":   maxRow,
		"recommendations":  recommendations,
	}
}

// UpdateBatchProgress updates the progress of a batch session
func (s *OCRService) UpdateBatchProgress(ctx context.Context, batchID, stage string, progress float64, completedImages, totalItemsExtracted int) error {
	// Convert progress to percentage (0-100)
	progressPercentage := int(progress)
	if progressPercentage > 100 {
		progressPercentage = 100
	}

	// Update database
	err := s.db.Model(&models.BatchOCRSession{}).
		Where("id = ?", batchID).
		Updates(map[string]interface{}{
			"current_stage":         stage,
			"progress_percentage":   progressPercentage,
			"completed_images":      completedImages,
			"total_items_extracted": totalItemsExtracted,
			"updated_at":            time.Now(),
		}).Error

	if err != nil {
		return err
	}

	// Broadcast progress via WebSocket
	hub := websocket.GetHub(logger.Logger)
	if hub != nil {
		data := map[string]interface{}{
			"batch_id":              batchID,
			"stage":                 stage,
			"progress":              progressPercentage,
			"total_items_extracted": totalItemsExtracted,
			"completed_images":      completedImages,
			"status":                "processing",
			"completed":             false,
		}

		// Set status based on stage
		if stage == "completed" {
			data["status"] = "completed"
			data["completed"] = true
		} else if stage == "failed" {
			data["status"] = "failed"
			data["completed"] = true
		}

		hub.Broadcast("ocr_progress", "progress", data)
		fmt.Printf("🌐 Broadcasting OCR progress: batch=%s, stage=%s, progress=%d%%\n", batchID, stage, progressPercentage)
	}

	return nil
}

// SaveSessionIDs saves session IDs for a batch (in-memory only, not persisted to DB)
func (s *OCRService) SaveSessionIDs(ctx context.Context, batchID string, sessionIDs []string) error {
	// Session IDs are tracked in individual ocr_sessions via batch_session_id foreign key
	// No need to store them in batch_ocr_sessions table
	// This is a no-op for now, kept for API compatibility
	return nil
}

// DeduplicateItems deduplicates items from multiple sessions
func (s *OCRService) DeduplicateItems(ctx context.Context, sessionIDs []string) (*models.DeduplicationResponse, error) {
	var allItems []models.OCRItem
	if err := s.db.Where("session_id IN ?", sessionIDs).Order("row_number").Find(&allItems).Error; err != nil {
		return nil, fmt.Errorf("failed to get items: %w", err)
	}

	// Fetch raw texts from OCR sessions
	var sessions []models.OCRSession
	if err := s.db.Where("id IN ?", sessionIDs).Find(&sessions).Error; err != nil {
		return nil, fmt.Errorf("failed to get sessions: %w", err)
	}

	// Build raw_texts map (session_id -> raw_text)
	rawTexts := make(map[string]string)
	for _, session := range sessions {
		if session.RawText != "" {
			rawTexts[session.ID] = session.RawText
		}
	}

	fmt.Printf("📝 [OCR] Including raw texts from %d sessions\n", len(rawTexts))

	uniqueMap := make(map[string]*models.OCRItem)
	for i := range allItems {
		item := &allItems[i]
		// Use BrandText if NormalizedBrandName is empty (happens in Direct Extraction)
		brandForKey := item.NormalizedBrandName
		if brandForKey == "" {
			brandForKey = item.BrandText
		}
		key := strings.ToLower(brandForKey + "|" + item.SizeText)

		if existing, exists := uniqueMap[key]; exists {
			// ✨ FIXED: Preserve non-zero values when merging duplicates
			existing.Quantity += item.Quantity

			// Preserve non-zero price from duplicate items
			if existing.SellingPrice == nil || *existing.SellingPrice == 0 {
				if item.SellingPrice != nil && *item.SellingPrice > 0 {
					existing.SellingPrice = item.SellingPrice
					fmt.Printf("  💰 Preserved price ₹%.2f from duplicate: %s\n",
						*item.SellingPrice, item.NormalizedBrandName)
				}
			}
		} else {
			uniqueMap[key] = item
		}
	}

	uniqueItems := make([]models.OCRItem, 0, len(uniqueMap))
	for _, item := range uniqueMap {
		uniqueItems = append(uniqueItems, *item)
	}

	// Get rejected items from temporary storage (if available)
	rejectedItems := make([]models.RejectedOCRItem, 0)
	totalRejected := 0

	// Check if we have a batch ID to look up rejected items
	if len(sessions) > 0 && sessions[0].BatchSessionID != "" {
		if stored, exists := s.getRejectedItems(sessions[0].BatchSessionID); exists {
			rejectedItems = stored
			totalRejected = len(rejectedItems)
			fmt.Printf("📋 [OCR] Retrieved %d rejected items for batch %s\n", totalRejected, sessions[0].BatchSessionID)
		}
	}

	response := &models.DeduplicationResponse{
		ReceiptType:       "SALE RECEIPT",
		UniqueItems:       uniqueItems,
		TotalItems:        len(uniqueItems),
		DuplicatesRemoved: len(allItems) - len(uniqueItems),
		RawTexts:          rawTexts,
		RejectedItems:     rejectedItems,
		TotalRejected:     totalRejected,
	}

	return response, nil
}

// GetAvailableBrands gets all brands (exposed for handlers)
func (s *OCRService) GetAvailableBrands(ctx context.Context) ([]Brand, error) {
	return s.getAvailableBrands(ctx)
}

// storeRejectedItems stores rejected items in temporary cache for a batch
func (s *OCRService) storeRejectedItems(batchID string, items []models.RejectedOCRItem) {
	if batchID != "" && len(items) > 0 {
		s.rejectedItemsCache.Store(batchID, items)
		fmt.Printf("📋 [OCR] Stored %d rejected items for batch %s\n", len(items), batchID)
	}
}

// getRejectedItems retrieves rejected items from temporary cache
func (s *OCRService) getRejectedItems(batchID string) ([]models.RejectedOCRItem, bool) {
	if batchID == "" {
		return nil, false
	}
	if val, exists := s.rejectedItemsCache.Load(batchID); exists {
		if items, ok := val.([]models.RejectedOCRItem); ok {
			return items, true
		}
	}
	return nil, false
}

// clearRejectedItems removes rejected items from cache (cleanup after processing)
func (s *OCRService) clearRejectedItems(batchID string) {
	if batchID != "" {
		s.rejectedItemsCache.Delete(batchID)
	}
}

// GeminiClient returns the Gemini client (exposed for handlers)
func (s *OCRService) GeminiClient() *ocr.GeminiClient {
	return s.geminiClient
}

// CreateBrand creates a new brand
func (s *OCRService) CreateBrand(ctx context.Context, tenantID, brandName, description string) (string, error) {
	brand := map[string]interface{}{
		"id":          uuid.New().String(),
		"tenant_id":   tenantID,
		"name":        brandName,
		"description": description,
		"created_at":  time.Now(),
		"updated_at":  time.Now(),
	}

	if err := s.db.Table("brands").Create(brand).Error; err != nil {
		return "", fmt.Errorf("failed to create brand: %w", err)
	}

	return brand["id"].(string), nil
}

// CategoryMatch represents a category inference result
type CategoryMatch struct {
	CategoryID    string
	CategoryName  string
	SubcategoryID *string
	PriceRange    string
	Confidence    float64
}

// InferCategory infers category and subcategory from brand name and price
func (s *OCRService) InferCategory(ctx context.Context, tenantID, brandName string, sellingPrice *float64) (*CategoryMatch, error) {
	// First, try to infer category from brand name using pattern matching
	categoryName := s.inferCategoryFromBrandName(brandName)

	// Get category ID from database
	var category struct {
		ID   string `gorm:"column:id"`
		Name string `gorm:"column:name"`
	}

	err := s.db.Table("categories").
		Select("id, name").
		Where("tenant_id = ? AND name = ?", tenantID, categoryName).
		First(&category).Error

	if err != nil {
		// If specific category not found, try to get default "IMFL" category
		fmt.Printf("⚠️  [OCR] Category '%s' not found, using IMFL default\n", categoryName)
		err = s.db.Table("categories").
			Select("id, name").
			Where("tenant_id = ? AND name = ?", tenantID, "IMFL").
			First(&category).Error

		if err != nil {
			// If IMFL also not found, create it
			categoryID := uuid.New().String()
			defaultCategory := map[string]interface{}{
				"id":          categoryID,
				"tenant_id":   tenantID,
				"name":        "IMFL",
				"description": "Indian Made Foreign Liquor",
				"is_active":   true,
				"sort_order":  1,
				"created_at":  time.Now(),
				"updated_at":  time.Now(),
			}
			if createErr := s.db.Table("categories").Create(defaultCategory).Error; createErr != nil {
				return nil, fmt.Errorf("failed to create default category: %w", createErr)
			}
			category.ID = categoryID
			category.Name = "IMFL"
			fmt.Printf("✅ [OCR] Created default IMFL category\n")
		}
	}

	// Infer subcategory based on price
	var subcategoryID *string
	var priceRange string
	if sellingPrice != nil && *sellingPrice > 0 {
		priceRange, subcategoryID = s.inferSubcategoryFromPrice(ctx, tenantID, category.ID, *sellingPrice)
	}

	confidence := s.calculateCategoryConfidence(brandName, categoryName)

	return &CategoryMatch{
		CategoryID:    category.ID,
		CategoryName:  category.Name,
		SubcategoryID: subcategoryID,
		PriceRange:    priceRange,
		Confidence:    confidence,
	}, nil
}

// inferCategoryFromBrandName uses pattern matching to infer category from brand name
func (s *OCRService) inferCategoryFromBrandName(brandName string) string {
	name := strings.ToLower(brandName)

	// Whisky patterns (most common in India)
	whiskyPatterns := []string{
		"whisky", "whiskey", "mcdowell", "mcdowells", "royal challenge", "royal stag",
		"blenders pride", "signature", "100 piper", "100 pipers", "black dog",
		"teachers", "vat 69", "antiquity", "imperial blue", "officers choice",
		"director special", "rockford", "rock ford", "bagpiper", "old tavern",
		// Additional whiskey brands from user's inventory
		"royal green", "8 p.m.", "8pm", "eight pm", "r.s. barrel", "rs barrel",
		"peter scott", "john paul", "original choice", "haywards fine",
		"royal reserve", "golden reserve", "8pm", "royal barrel",
		// Common premium whiskey brands
		"johnny walker", "johnnie walker", "jack daniels", "chivas", "jameson",
		"glenfiddich", "glenlivet", "ballantines", "dewars", "jw", "j&b",
	}
	for _, pattern := range whiskyPatterns {
		if strings.Contains(name, pattern) {
			return "Whiskey" // Use "Whiskey" to match database
		}
	}

	// Rum patterns
	rumPatterns := []string{
		"rum", "old monk", "bacardi", "captain morgan", "malibu", "contessa",
		"don angel", "hercules", "old port", "mcdo rum",
		// Additional rum variants
		"white rum", "dark rum", "spiced rum", "old port white", "old port dark",
		"havana club", "diplomatico", "mount gay", "appleton", "sailors choice",
		"camikara", "flip flop", "bounty", "mcdowells rum",
	}
	for _, pattern := range rumPatterns {
		if strings.Contains(name, pattern) {
			return "Rum"
		}
	}

	// Vodka patterns
	vodkaPatterns := []string{
		"vodka", "magic moments", "smirnoff", "absolut", "grey goose", "ciroc",
		"belvedere", "romanov", "vladivar", "white mischief", "eristoff",
		// Additional vodka brands
		"fuel vodka", "white magic", "blue magic", "skyy", "russian standard",
		"ketel one", "stolichnaya", "finlandia", "boru", "green apple vodka",
		"black magic", "new amsterdam", "reyka",
	}
	for _, pattern := range vodkaPatterns {
		if strings.Contains(name, pattern) {
			return "Vodka"
		}
	}

	// Gin patterns
	ginPatterns := []string{
		"gin", "bombay sapphire", "tanqueray", "greater than", "jaisalmer",
		"hendricks", "beefeater", "gordons",
		// Additional gin brands
		"bombay", "plymouth", "martin millers", "monkey 47", "botanist",
		"hapusa", "stranger & sons", "nao spirits", "jin jiji", "samsara",
		"london dry gin", "pink gin", "sloe gin",
	}
	for _, pattern := range ginPatterns {
		if strings.Contains(name, pattern) {
			return "Gin"
		}
	}

	// Beer patterns
	beerPatterns := []string{
		"beer", "kingfisher", "budweiser", "corona", "heineken", "carlsberg",
		"tuborg", "fosters", "bira", "simba", "haywards", "knockout",
		// Additional beer brands
		"white rhino", "godfather", "thunderbolt", "zingaro", "hoegaarden",
		"amstel", "stella artois", "miller", "guinness", "peroni", "asahi",
		"bira 91", "white owl", "geist", "doolally", "gateway", "arbor",
		"lager", "ale", "ipa", "stout", "pilsner",
	}
	for _, pattern := range beerPatterns {
		if strings.Contains(name, pattern) {
			return "Beer"
		}
	}

	// Wine patterns
	winePatterns := []string{
		"wine", "sula", "grover", "fratelli", "zampa", "chateau", "red wine",
		"white wine", "rose", "sparkling", "champagne", "port wine",
		// Additional wine brands
		"big banyan", "krsma", "myra", "vallonne", "reveilo", "charosa",
		"yorkshire", "four seasons", "nine hills", "cabernet", "shiraz",
		"chardonnay", "sauvignon", "merlot", "pinot", "riesling", "moscato",
		"prosecco", "cava", "moet", "veuve clicquot", "dom perignon",
	}
	for _, pattern := range winePatterns {
		if strings.Contains(name, pattern) {
			return "Wine"
		}
	}

	// Brandy patterns
	brandyPatterns := []string{
		"brandy", "morpheus", "mansion house", "honey bee", "old admiral",
		"honeybee", "doctor", "dreher",
		// Additional brandy brands
		"hennessy", "remy martin", "courvoisier", "martell", "paul john",
		"mcdo brandy", "mcdowells brandy", "royal commander", "napoleon",
		"vsop", "xo", "cognac", "armagnac",
	}
	for _, pattern := range brandyPatterns {
		if strings.Contains(name, pattern) {
			return "Brandy"
		}
	}

	// Tequila patterns
	tequilaPatterns := []string{
		"tequila", "jose cuervo", "patron", "don julio",
		// Additional tequila brands
		"1800", "casamigos", "herradura", "espolon", "olmeca", "sauza",
		"el jimador", "corralejo", "reposado", "añejo", "blanco", "silver",
		"gold tequila", "mezcal",
	}
	for _, pattern := range tequilaPatterns {
		if strings.Contains(name, pattern) {
			return "Tequila"
		}
	}

	// Default to IMFL for unrecognized brands
	return "IMFL"
}

// inferSubcategoryFromPrice determines subcategory based on price range
func (s *OCRService) inferSubcategoryFromPrice(ctx context.Context, tenantID, categoryID string, price float64) (string, *string) {
	var priceRange string

	// Determine price range
	if price >= 2000 {
		priceRange = "Ultra Premium"
	} else if price >= 1000 {
		priceRange = "Premium"
	} else if price >= 500 {
		priceRange = "Normal"
	} else {
		priceRange = "Basic"
	}

	// Try to find or create subcategory
	var subcategory struct {
		ID string `gorm:"column:id"`
	}

	err := s.db.Table("subcategories").
		Select("id").
		Where("category_id = ? AND price_range = ?", categoryID, priceRange).
		First(&subcategory).Error

	if err != nil {
		// Create subcategory if it doesn't exist
		subcategoryID := uuid.New().String()
		newSubcategory := map[string]interface{}{
			"id":          subcategoryID,
			"tenant_id":   tenantID,
			"category_id": categoryID,
			"name":        priceRange,
			"price_range": priceRange,
			"description": fmt.Sprintf("%s price range (auto-created)", priceRange),
			"is_active":   true,
			"created_at":  time.Now(),
			"updated_at":  time.Now(),
		}

		if createErr := s.db.Table("subcategories").Create(newSubcategory).Error; createErr != nil {
			fmt.Printf("⚠️  [OCR] Failed to create subcategory: %v\n", createErr)
			return priceRange, nil
		}

		fmt.Printf("✅ [OCR] Created subcategory: %s (%s)\n", priceRange, subcategoryID)
		return priceRange, &subcategoryID
	}

	return priceRange, &subcategory.ID
}

// calculateCategoryConfidence calculates confidence score for category inference
func (s *OCRService) calculateCategoryConfidence(brandName, categoryName string) float64 {
	name := strings.ToLower(brandName)
	category := strings.ToLower(categoryName)

	// If category name is explicitly in brand name, high confidence
	if strings.Contains(name, category) {
		return 95.0
	}

	// If we matched on a specific pattern, good confidence
	if category != "imfl" {
		return 85.0
	}

	// IMFL is default fallback, lower confidence
	return 60.0
}

// ImportItems imports OCR items as products and stock with complete categorization and pricing
func (s *OCRService) ImportItems(ctx context.Context, tenantID, shopID string, items []models.OCRItem, autoCreateBrands bool) (*models.ImportResult, error) {
	result := &models.ImportResult{
		ProductsCreated: 0,
		ProductsUpdated: 0,
		BrandsCreated:   0,
		Errors:          []models.ImportError{},
	}

	fmt.Printf("🔄 [OCR Import] Starting import of %d items for shop %s\n", len(items), shopID)
	fmt.Printf("📋 [OCR Import] Features: Auto-categorization, Complete pricing, Stock history tracking\n")

	// Parse UUIDs for StockService
	tenantUUID, err := uuid.Parse(tenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant ID: %w", err)
	}

	shopUUID, err := uuid.Parse(shopID)
	if err != nil {
		return nil, fmt.Errorf("invalid shop ID: %w", err)
	}

	// Create StockService for proper stock management with history
	// Note: We pass nil for cache as it's optional and not critical for OCR imports
	inventoryServices := struct {
		db    *database.DB
		cache interface{}
	}{s.db, nil}

	for _, item := range items {
		if !item.IsSelected {
			continue
		}

		// 1. Handle Brand Creation/Matching
		brandID := item.MatchedBrandID
		if brandID == nil && autoCreateBrands {
			newBrandID, err := s.CreateBrand(ctx, tenantID, item.NormalizedBrandName, "Auto-created from OCR")
			if err != nil {
				result.Errors = append(result.Errors, models.ImportError{
					ItemRowNumber: item.RowNumber,
					BrandText:     item.BrandText,
					Error:         fmt.Sprintf("Failed to create brand: %v", err),
				})
				continue
			}
			brandID = &newBrandID
			result.BrandsCreated++
			fmt.Printf("✅ [OCR Import] Created brand: %s (ID: %s)\n", item.NormalizedBrandName, newBrandID)
		}

		if brandID == nil {
			result.Errors = append(result.Errors, models.ImportError{
				ItemRowNumber: item.RowNumber,
				BrandText:     item.BrandText,
				Error:         "No brand match found and auto-create is disabled",
			})
			continue
		}

		// 2. Infer Category and Subcategory
		categoryMatch, err := s.InferCategory(ctx, tenantID, item.NormalizedBrandName, item.SellingPrice)
		if err != nil {
			fmt.Printf("⚠️  [OCR Import] Category inference failed for %s: %v, using defaults\n", item.BrandText, err)
			// Continue with product creation even if categorization fails
		}

		var categoryID string
		var subcategoryID *string
		if categoryMatch != nil {
			categoryID = categoryMatch.CategoryID
			subcategoryID = categoryMatch.SubcategoryID
			fmt.Printf("🏷️  [OCR Import] Categorized '%s' as %s (%.0f%% confidence)\n",
				item.NormalizedBrandName, categoryMatch.CategoryName, categoryMatch.Confidence)
			if categoryMatch.PriceRange != "" {
				fmt.Printf("   💰 Price tier: %s\n", categoryMatch.PriceRange)
			}
		}

		// 3. Calculate Complete Pricing
		var sellingPrice, costPrice, mrp float64
		if item.SellingPrice != nil && *item.SellingPrice > 0 {
			sellingPrice = *item.SellingPrice
			// Estimate cost price as 65% of selling (typical liquor markup)
			costPrice = sellingPrice * 0.65
			// Estimate MRP as 110% of selling (10% margin for retailer)
			mrp = sellingPrice * 1.10
		} else {
			// If no price from OCR, use minimal defaults
			sellingPrice = 0
			costPrice = 0
			mrp = 0
		}

		// 4. Create or Update Product with Complete Data
		productName := fmt.Sprintf("%s %s", item.NormalizedBrandName, item.SizeText)
		var existingProduct struct {
			ID string `gorm:"column:id"`
		}

		err = s.db.Table("products").
			Select("id").
			Where("brand_id = ? AND tenant_id = ? AND size = ?", *brandID, tenantID, item.SizeText).
			First(&existingProduct).Error

		var productID string
		if err == nil && existingProduct.ID != "" {
			// Product exists, update it with latest pricing and category
			productID = existingProduct.ID
			updates := map[string]interface{}{
				"selling_price": sellingPrice,
				"cost_price":    costPrice,
				"mrp":           mrp,
				"updated_at":    time.Now(),
			}
			// Update category if we have one
			if categoryID != "" {
				updates["category_id"] = categoryID
			}
			if subcategoryID != nil {
				updates["subcategory_id"] = *subcategoryID
			}

			s.db.Table("products").Where("id = ?", existingProduct.ID).Updates(updates)
			result.ProductsUpdated++
			fmt.Printf("📦 [OCR Import] Updated product: %s (ID: %s)\n", productName, productID)
		} else {
			// Create new product with complete data
			productID = uuid.New().String()
			product := map[string]interface{}{
				"id":            productID,
				"tenant_id":     tenantID,
				"brand_id":      *brandID,
				"name":          productName,
				"size":          item.SizeText,
				"unit":          "ml",
				"selling_price": sellingPrice,
				"cost_price":    costPrice,
				"mrp":           mrp,
				"is_active":     true,
				"created_at":    time.Now(),
				"updated_at":    time.Now(),
			}

			// Add category if available
			if categoryID != "" {
				product["category_id"] = categoryID
			}
			if subcategoryID != nil {
				product["subcategory_id"] = *subcategoryID
			}

			if err := s.db.Table("products").Create(product).Error; err != nil {
				result.Errors = append(result.Errors, models.ImportError{
					ItemRowNumber: item.RowNumber,
					BrandText:     item.BrandText,
					Error:         fmt.Sprintf("Failed to create product: %v", err),
				})
				continue
			}

			result.ProductsCreated++
			fmt.Printf("✅ [OCR Import] Created product: %s\n", productName)
			fmt.Printf("   💵 Prices - Selling: ₹%.2f, Cost: ₹%.2f, MRP: ₹%.2f\n", sellingPrice, costPrice, mrp)
		}

		// 5. Set Stock using Direct DB Access (simpler than full StockService for OCR)
		// We use SET operation to replace existing stock with OCR quantity
		productUUID, err := uuid.Parse(productID)
		if err != nil {
			result.Errors = append(result.Errors, models.ImportError{
				ItemRowNumber: item.RowNumber,
				BrandText:     item.BrandText,
				Error:         fmt.Sprintf("Invalid product ID: %v", err),
			})
			continue
		}

		// Check if stock record exists
		var existingStock struct {
			ID       string `gorm:"column:id"`
			Quantity int    `gorm:"column:quantity"`
		}

		stockErr := s.db.Table("stock").
			Select("id, quantity").
			Where("product_id = ? AND shop_id = ? AND tenant_id = ?", productUUID, shopUUID, tenantUUID).
			First(&existingStock).Error

		if stockErr == nil && existingStock.ID != "" {
			// Stock exists - UPDATE with SET operation
			oldQuantity := existingStock.Quantity
			updateErr := s.db.Table("stock").
				Where("id = ?", existingStock.ID).
				Updates(map[string]interface{}{
					"quantity":   item.Quantity,
					"updated_at": time.Now(),
				}).Error

			if updateErr != nil {
				result.Errors = append(result.Errors, models.ImportError{
					ItemRowNumber: item.RowNumber,
					BrandText:     item.BrandText,
					Error:         fmt.Sprintf("Failed to update stock: %v", updateErr),
				})
			} else {
				// Create stock history record for audit trail
				historyID := uuid.New().String()
				stockHistory := map[string]interface{}{
					"id":                 historyID,
					"stock_id":           existingStock.ID,
					"tenant_id":          tenantID,
					"adjustment_type":    "set",
					"quantity_before":    oldQuantity,
					"quantity_after":     item.Quantity,
					"quantity_change":    item.Quantity - oldQuantity,
					"reason":             "OCR Import - Opening Stock",
					"notes":              fmt.Sprintf("Batch: %s, Row: %d - Initial stock from invoice", item.BatchID, item.RowNumber),
					"performed_by":       "system",
					"created_at":         time.Now(),
				}
				s.db.Table("stock_history").Create(stockHistory)

				fmt.Printf("📊 [OCR Import] Updated stock for %s: %d → %d units (change: %+d)\n",
					productName, oldQuantity, item.Quantity, item.Quantity-oldQuantity)
			}
		} else {
			// Stock doesn't exist - CREATE new record
			stockID := uuid.New().String()
			stock := map[string]interface{}{
				"id":         stockID,
				"product_id": productUUID.String(),
				"shop_id":    shopUUID.String(),
				"tenant_id":  tenantID,
				"quantity":   item.Quantity,
				"created_at": time.Now(),
				"updated_at": time.Now(),
			}

			createErr := s.db.Table("stock").Create(stock).Error
			if createErr != nil {
				result.Errors = append(result.Errors, models.ImportError{
					ItemRowNumber: item.RowNumber,
					BrandText:     item.BrandText,
					Error:         fmt.Sprintf("Failed to create stock: %v", createErr),
				})
			} else {
				// Create initial stock history record
				historyID := uuid.New().String()
				stockHistory := map[string]interface{}{
					"id":                 historyID,
					"stock_id":           stockID,
					"tenant_id":          tenantID,
					"adjustment_type":    "set",
					"quantity_before":    0,
					"quantity_after":     item.Quantity,
					"quantity_change":    item.Quantity,
					"reason":             "OCR Import - Opening Stock",
					"notes":              fmt.Sprintf("Batch: %s, Row: %d - Initial stock from invoice", item.BatchID, item.RowNumber),
					"performed_by":       "system",
					"created_at":         time.Now(),
				}
				s.db.Table("stock_history").Create(stockHistory)

				fmt.Printf("✅ [OCR Import] Created stock for %s: %d units\n", productName, item.Quantity)
			}
		}

		// Suppress unused variable warning
		_ = inventoryServices
	}

	fmt.Printf("📈 [OCR Import] Complete: %d products created, %d updated, %d brands created, %d errors\n",
		result.ProductsCreated, result.ProductsUpdated, result.BrandsCreated, len(result.Errors))

	return result, nil
}

// fetchImageFromURL fetches image data from a URL and returns it as bytes
func (s *OCRService) fetchImageFromURL(url string) ([]byte, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch image: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch image: HTTP %d", resp.StatusCode)
	}

	imageBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read image data: %w", err)
	}

	return imageBytes, nil
}

// Close closes the OCR service connections
func (s *OCRService) Close() error {
	if s.visionClient != nil {
		return s.visionClient.Close()
	}
	return nil
}

// ========== COMPREHENSIVE OCR VALIDATION & SUGGESTION SYSTEM ==========

// ValidateBatchOCR performs comprehensive validation of OCR extraction and generates suggestions
func (s *OCRService) ValidateBatchOCR(ctx context.Context, batchID string, expectedTotal float64) (*models.OCRValidationResult, error) {
	fmt.Printf("🔍 [OCR Validation] Starting comprehensive validation for batch: %s\n", batchID)

	result := &models.OCRValidationResult{
		BatchID:        batchID,
		ValidationTime: time.Now().Format(time.RFC3339),
		Suggestions:    []models.OCRValidationSuggestion{},
		EdgeCases:      []models.OCREdgeCase{},
		ExpectedAmount: expectedTotal,
	}

	// 1. Get all OCR items for this batch
	var items []models.OCRItem
	if err := s.db.DB.Where("batch_id = ?", batchID).Order("session_id, row_number").Find(&items).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch OCR items: %w", err)
	}
	result.TotalItems = len(items)

	// 2. Get all sessions for this batch
	var sessions []models.OCRSession
	if err := s.db.DB.Where("batch_session_id = ?", batchID).Find(&sessions).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch OCR sessions: %w", err)
	}
	result.TotalImages = len(sessions)

	// 3. Analyze each image/session
	result.ImageAnalysis = s.analyzeImages(sessions, items)

	// 4. Detect duplicate images
	result.DuplicateImages = s.detectDuplicateImages(result.ImageAnalysis)

	// 5. Calculate size summaries
	result.SizeSummaries = s.calculateSizeSummaries(items)

	// 6. Calculate brand summaries
	result.BrandSummaries = s.calculateBrandSummaries(items)

	// 7. Calculate total amount
	for _, item := range items {
		result.TotalAmount += item.Amount
	}

	// 8. Generate suggestions for each edge case
	s.generateSuggestions(result, items, sessions)

	// 9. Calculate discrepancy
	if expectedTotal > 0 {
		result.AmountDiscrepancy = expectedTotal - result.TotalAmount
	}

	// 10. Determine overall status
	result.OverallStatus = s.determineOverallStatus(result)
	result.OverallConfidence = s.calculateOverallConfidence(result)

	// Count issues by severity
	for _, sugg := range result.Suggestions {
		switch sugg.Severity {
		case "critical":
			result.CriticalIssues++
		case "warning":
			result.Warnings++
		case "info":
			result.InfoItems++
		}
	}

	result.ImagesProcessed = result.TotalImages - result.ImagesFailed
	fmt.Printf("✅ [OCR Validation] Complete: %d items, %d suggestions, status=%s\n",
		result.TotalItems, len(result.Suggestions), result.OverallStatus)

	return result, nil
}

// analyzeImages analyzes each image session
func (s *OCRService) analyzeImages(sessions []models.OCRSession, items []models.OCRItem) []models.OCRImageAnalysis {
	analyses := make([]models.OCRImageAnalysis, 0, len(sessions))

	for idx, session := range sessions {
		analysis := models.OCRImageAnalysis{
			SessionID:  session.ID,
			ImageIndex: idx + 1,
			Issues:     []string{},
		}

		// Count items for this session
		var sessionAmount float64
		for _, item := range items {
			if item.SessionID == session.ID {
				analysis.ItemsExtracted++
				sessionAmount += item.Amount
			}
		}
		analysis.TotalAmount = sessionAmount

		// Determine receipt type from raw text or items
		analysis.ReceiptType = s.detectReceiptType(session.RawText, items, session.ID)

		// Assess image quality
		if analysis.ItemsExtracted == 0 {
			analysis.ImageQuality = "unreadable"
			analysis.QualityScore = 0
			analysis.Issues = append(analysis.Issues, "No items extracted - image may be blank, faded, or unreadable")
		} else if analysis.ItemsExtracted < 3 {
			analysis.ImageQuality = "poor"
			analysis.QualityScore = 30
			analysis.Issues = append(analysis.Issues, "Very few items extracted - image quality may be poor")
		} else {
			analysis.ImageQuality = "good"
			analysis.QualityScore = 90
		}

		analyses = append(analyses, analysis)
	}

	return analyses
}

// detectReceiptType determines the receipt type from content
func (s *OCRService) detectReceiptType(rawText string, items []models.OCRItem, sessionID string) string {
	rawTextLower := strings.ToLower(rawText)

	if strings.Contains(rawTextLower, "bottle") {
		return "BOTTLE"
	}
	if strings.Contains(rawTextLower, "90 m.l") || strings.Contains(rawTextLower, "90ml") || strings.Contains(rawTextLower, "peg") {
		return "PEG"
	}
	if strings.Contains(rawTextLower, "half") {
		return "HALF"
	}
	if strings.Contains(rawTextLower, "quart") {
		return "QUART"
	}
	if strings.Contains(rawTextLower, "full") {
		return "FULL"
	}

	// Infer from item sizes
	for _, item := range items {
		if item.SessionID != sessionID {
			continue
		}
		sizeLower := strings.ToLower(item.SizeText)
		if strings.Contains(sizeLower, "750") {
			return "FULL"
		}
		if strings.Contains(sizeLower, "375") {
			return "HALF"
		}
		if strings.Contains(sizeLower, "180") {
			return "QUART"
		}
		if strings.Contains(sizeLower, "90") || strings.Contains(sizeLower, "50") {
			return "PEG"
		}
		if sizeLower == "-1ml" || sizeLower == "-1" {
			return "BOTTLE"
		}
	}

	return "UNKNOWN"
}

// detectDuplicateImages checks for duplicate images based on extracted content
func (s *OCRService) detectDuplicateImages(analyses []models.OCRImageAnalysis) int {
	duplicates := 0
	seen := make(map[string]int) // key: "receiptType_itemCount_amount" -> index

	for i := range analyses {
		key := fmt.Sprintf("%s_%d_%.0f", analyses[i].ReceiptType, analyses[i].ItemsExtracted, analyses[i].TotalAmount)
		if prevIdx, exists := seen[key]; exists && analyses[i].ItemsExtracted > 0 {
			analyses[i].IsDuplicate = true
			analyses[i].DuplicateOf = analyses[prevIdx].SessionID
			analyses[i].Issues = append(analyses[i].Issues, fmt.Sprintf("Possible duplicate of image %d", prevIdx+1))
			duplicates++
		} else if analyses[i].ItemsExtracted > 0 {
			seen[key] = i
		}
	}

	return duplicates
}

// calculateSizeSummaries calculates totals by size category
func (s *OCRService) calculateSizeSummaries(items []models.OCRItem) []models.OCRSizeSummary {
	sizeMap := make(map[string]*models.OCRSizeSummary)

	for _, item := range items {
		sizeCategory := s.categorizeSize(item.SizeText)
		if _, exists := sizeMap[sizeCategory]; !exists {
			sizeMap[sizeCategory] = &models.OCRSizeSummary{
				SizeCategory:  sizeCategory,
				SizeML:        item.SizeText,
				AmountMatches: true,
			}
		}
		sizeMap[sizeCategory].TotalItems++
		sizeMap[sizeCategory].TotalQuantity += item.SaleQuantity
		sizeMap[sizeCategory].TotalAmount += item.Amount
	}

	summaries := make([]models.OCRSizeSummary, 0, len(sizeMap))
	for _, summary := range sizeMap {
		summaries = append(summaries, *summary)
	}
	return summaries
}

// categorizeSize maps size text to a category
func (s *OCRService) categorizeSize(sizeText string) string {
	sizeLower := strings.ToLower(sizeText)
	switch {
	case strings.Contains(sizeLower, "750") || strings.Contains(sizeLower, "1000"):
		return "FULL"
	case strings.Contains(sizeLower, "375"):
		return "HALF"
	case strings.Contains(sizeLower, "180"):
		return "QUART"
	case strings.Contains(sizeLower, "90") || strings.Contains(sizeLower, "50"):
		return "PEG"
	case sizeLower == "-1ml" || sizeLower == "-1":
		return "BOTTLE"
	default:
		return "UNKNOWN"
	}
}

// calculateBrandSummaries calculates totals by brand
func (s *OCRService) calculateBrandSummaries(items []models.OCRItem) []models.OCRBrandSummary {
	brandMap := make(map[string]*models.OCRBrandSummary)

	for _, item := range items {
		brandKey := strings.ToLower(strings.TrimSpace(item.BrandText))
		if _, exists := brandMap[brandKey]; !exists {
			brandMap[brandKey] = &models.OCRBrandSummary{
				BrandText:     item.BrandText,
				Sizes:         []string{},
				AmountMatches: true,
			}
		}
		brandMap[brandKey].TotalItems++
		brandMap[brandKey].TotalQuantity += item.SaleQuantity
		brandMap[brandKey].TotalAmount += item.Amount

		// Track unique sizes
		sizeFound := false
		for _, s := range brandMap[brandKey].Sizes {
			if s == item.SizeText {
				sizeFound = true
				break
			}
		}
		if !sizeFound {
			brandMap[brandKey].Sizes = append(brandMap[brandKey].Sizes, item.SizeText)
		}
	}

	summaries := make([]models.OCRBrandSummary, 0, len(brandMap))
	for _, summary := range brandMap {
		summaries = append(summaries, *summary)
	}
	return summaries
}

// generateSuggestions creates suggestions for all detected issues
func (s *OCRService) generateSuggestions(result *models.OCRValidationResult, items []models.OCRItem, sessions []models.OCRSession) {
	suggestionID := 0

	// 1. Check for unreadable images
	for _, analysis := range result.ImageAnalysis {
		if analysis.ImageQuality == "unreadable" {
			suggestionID++
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				Type:           "image_quality",
				Severity:       "critical",
				Reasoning:      fmt.Sprintf("Image %d returned 0 items - the image appears to be blank, faded, or unreadable. This may contain missing sales data.", analysis.ImageIndex),
				AutoFixable:    false,
				RequiresReview: true,
			})
			result.EdgeCases = append(result.EdgeCases, models.OCREdgeCase{
				Type:        "unreadable_image",
				Description: fmt.Sprintf("Image %d could not be processed - 0 items extracted", analysis.ImageIndex),
				Resolution:  "Please provide a clearer image or manually enter the data",
			})
		}

		// Check for duplicates
		if analysis.IsDuplicate {
			suggestionID++
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				Type:           "duplicate_image",
				Severity:       "warning",
				Reasoning:      fmt.Sprintf("Image %d appears to be a duplicate (same receipt type, item count, and amount)", analysis.ImageIndex),
				AutoFixable:    true,
				RequiresReview: true,
			})
		}
	}

	// 2. Check each item for issues
	for _, item := range items {
		// Missing size (-1ml)
		if item.SizeText == "-1ml" || item.SizeText == "-1" || item.SizeText == "" {
			suggestionID++
			suggestedSize := s.inferSizeFromRate(item.Rate)
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				ItemID:         item.ID,
				Type:           "missing_size",
				Severity:       "warning",
				Field:          "size_text",
				CurrentValue:   item.SizeText,
				SuggestedValue: suggestedSize,
				Confidence:     70,
				Reasoning:      fmt.Sprintf("Size not detected for %s. Based on rate Rs %.0f, suggested size: %s", item.BrandText, item.Rate, suggestedSize),
				AutoFixable:    true,
				RequiresReview: true,
			})
		}

		// Missing or invalid rate
		if item.Rate <= 0 {
			suggestionID++
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				ItemID:         item.ID,
				Type:           "missing_rate",
				Severity:       "critical",
				Field:          "rate",
				CurrentValue:   fmt.Sprintf("%.2f", item.Rate),
				Reasoning:      fmt.Sprintf("Rate is missing or invalid for %s (%s). Please enter the correct rate.", item.BrandText, item.SizeText),
				AutoFixable:    false,
				RequiresReview: true,
			})
		}

		// Zero sales with stock change (potential issue)
		if item.SaleQuantity == 0 && item.OpeningStock > 0 {
			suggestionID++
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				ItemID:         item.ID,
				Type:           "zero_sales",
				Severity:       "info",
				Field:          "sale_quantity",
				CurrentValue:   "0",
				Reasoning:      fmt.Sprintf("%s (%s) shows 0 sales. Verify this is correct or if OCR missed the sale quantity.", item.BrandText, item.SizeText),
				AutoFixable:    false,
				RequiresReview: true,
			})
		}

		// Math validation errors
		if !item.IsAmountValid {
			suggestionID++
			expectedAmount := float64(item.SaleQuantity) * item.Rate
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				ItemID:         item.ID,
				Type:           "math_error",
				Severity:       "warning",
				Field:          "amount",
				CurrentValue:   fmt.Sprintf("%.2f", item.Amount),
				SuggestedValue: fmt.Sprintf("%.2f", expectedAmount),
				Confidence:     95,
				Reasoning:      fmt.Sprintf("Amount mismatch for %s: Qty(%d) × Rate(%.0f) = %.2f, but extracted %.2f", item.BrandText, item.SaleQuantity, item.Rate, expectedAmount, item.Amount),
				AutoFixable:    true,
				RequiresReview: false,
			})
		}

		// Unusual high rates (>Rs 3000)
		if item.Rate > 3000 {
			suggestionID++
			result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
				ID:             fmt.Sprintf("S%03d", suggestionID),
				ItemID:         item.ID,
				Type:           "unusual_rate",
				Severity:       "info",
				Field:          "rate",
				CurrentValue:   fmt.Sprintf("%.2f", item.Rate),
				Reasoning:      fmt.Sprintf("Rate Rs %.0f for %s seems unusually high. Please verify this is correct.", item.Rate, item.BrandText),
				AutoFixable:    false,
				RequiresReview: true,
			})
		}
	}

	// 3. Check for amount discrepancy
	if result.ExpectedAmount > 0 && math.Abs(result.AmountDiscrepancy) > 1 {
		suggestionID++
		severity := "warning"
		if math.Abs(result.AmountDiscrepancy) > 1000 {
			severity = "critical"
		}
		result.Suggestions = append(result.Suggestions, models.OCRValidationSuggestion{
			ID:             fmt.Sprintf("S%03d", suggestionID),
			Type:           "total_mismatch",
			Severity:       severity,
			Field:          "total_amount",
			CurrentValue:   fmt.Sprintf("%.2f", result.TotalAmount),
			SuggestedValue: fmt.Sprintf("%.2f", result.ExpectedAmount),
			Reasoning:      fmt.Sprintf("Total mismatch: Extracted Rs %.0f but expected Rs %.0f (difference: Rs %.0f). Missing data may be in unreadable images.", result.TotalAmount, result.ExpectedAmount, result.AmountDiscrepancy),
			AutoFixable:    false,
			RequiresReview: true,
		})

		result.EdgeCases = append(result.EdgeCases, models.OCREdgeCase{
			Type:        "total_discrepancy",
			Description: fmt.Sprintf("Rs %.0f discrepancy between extracted and expected total", math.Abs(result.AmountDiscrepancy)),
			Resolution:  "Check unreadable images or manually verify missing items",
		})
	}
}

// inferSizeFromRate suggests a size based on the rate
func (s *OCRService) inferSizeFromRate(rate float64) string {
	switch {
	case rate <= 100:
		return "90ml (PEG)"
	case rate <= 200:
		return "180ml (QUART)"
	case rate <= 400:
		return "375ml (HALF)"
	case rate <= 800:
		return "750ml (FULL)"
	default:
		return "750ml (BOTTLE/Premium)"
	}
}

// determineOverallStatus determines the validation status
func (s *OCRService) determineOverallStatus(result *models.OCRValidationResult) string {
	hasCritical := false
	hasWarning := false

	for _, sugg := range result.Suggestions {
		if sugg.Severity == "critical" {
			hasCritical = true
		}
		if sugg.Severity == "warning" {
			hasWarning = true
		}
	}

	if hasCritical {
		return "has_errors"
	}
	if hasWarning {
		return "has_warnings"
	}
	return "valid"
}

// calculateOverallConfidence calculates confidence score
func (s *OCRService) calculateOverallConfidence(result *models.OCRValidationResult) float64 {
	if result.TotalItems == 0 {
		return 0
	}

	baseConfidence := 100.0

	// Deduct for critical issues
	baseConfidence -= float64(result.CriticalIssues) * 15

	// Deduct for warnings
	baseConfidence -= float64(result.Warnings) * 5

	// Deduct for failed images
	if result.TotalImages > 0 {
		failedRatio := float64(result.ImagesFailed) / float64(result.TotalImages)
		baseConfidence -= failedRatio * 30
	}

	// Deduct for amount discrepancy
	if result.ExpectedAmount > 0 && result.TotalAmount > 0 {
		discrepancyRatio := math.Abs(result.AmountDiscrepancy) / result.ExpectedAmount
		baseConfidence -= discrepancyRatio * 50
	}

	if baseConfidence < 0 {
		baseConfidence = 0
	}

	return baseConfidence
}
