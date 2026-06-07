package services

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// SizeNormalizer handles intelligent size normalization for liquor products
type SizeNormalizer struct {
	// Category-specific size mappings
	categoryRules map[string]*CategorySizeRules

	// Common typos and their corrections
	typoCorrections map[string]string

	// Size unit conversions
	unitConversions map[string]float64
}

// CategorySizeRules defines size rules for a product category
type CategorySizeRules struct {
	Category      string
	DefaultSizes  []int              // Standard sizes in ML
	SizeAliases   map[string]int     // Alias → ML mapping
	Keywords      []string           // Keywords to identify this category
}

// NewSizeNormalizer creates a new size normalizer with industry-standard rules
func NewSizeNormalizer() *SizeNormalizer {
	return &SizeNormalizer{
		categoryRules: map[string]*CategorySizeRules{
			"whiskey": {
				Category: "whiskey",
				DefaultSizes: []int{90, 180, 375, 750, 1000}, // Added 90ml for Indian market
				SizeAliases: map[string]int{
					// Standard aliases - FULL BOTTLE (750ml)
					"bottle": 750,
					"btl":    750,
					"fl":     750,
					"full":   750,
					"full bottle": 750,

					// HALF BOTTLE (375ml) - colloquial terms
					"half":   375,
					"half bottle": 375,
					"half btl": 375,
					"1/2":    375,
					"1/2 bottle": 375,

					// QUARTER BOTTLE (180ml) - colloquial terms
					"quarter": 180,
					"qtr":     180,
					"quart":   180,
					"quarter bottle": 180,
					"qtr btl": 180,
					"1/4":     180,
					"1/4 bottle": 180,

					// Other standard sizes
					"pint":    200,
					"nip":     90,  // 90ml nip bottle

					// Common variations with ML
					"90ml":  90,
					"90 ml": 90,
					"750ml": 750,
					"750 ml": 750,
					"375ml": 375,
					"375 ml": 375,
					"180ml": 180,
					"180 ml": 180,
					"1l":    1000,
					"1 l":   1000,
					"1ltr":  1000,
					"1 ltr": 1000,
					"1000ml": 1000,

					// Regional terms
					"half pint": 200,
					"peg":    60,

					// Common OCR errors and misspellings
					"quartar": 180,
					"quater":  180,
					"quatr":   180,
					"haff":    375,
					"haf":     375,
					"bottl":   750,
				},
				Keywords: []string{"whiskey", "whisky", "scotch", "bourbon", "rum", "vodka", "gin", "brandy"},
			},
			"beer": {
				Category: "beer",
				DefaultSizes: []int{330, 500, 650, 1000},
				SizeAliases: map[string]int{
					// Beer-specific
					"can":     330,
					"small":   330,
					"regular": 500,
					"large":   650,
					"king":    650,
					"pitcher": 1000,
					"jug":     1000,

					// Standard sizes
					"330ml": 330,
					"500ml": 500,
					"650ml": 650,
					"1l":    1000,
					"1 l":   1000,

					// Pint variations
					"pint":      568, // UK pint
					"half pint": 284,
				},
				Keywords: []string{"beer", "lager", "ale", "stout", "ipa", "pilsner"},
			},
			"wine": {
				Category: "wine",
				DefaultSizes: []int{187, 375, 750, 1500},
				SizeAliases: map[string]int{
					"bottle":       750,
					"half bottle":  375,
					"split":        187,
					"magnum":       1500,
					"standard":     750,
					"750ml":        750,
					"1.5l":         1500,
				},
				Keywords: []string{"wine", "champagne", "prosecco", "red wine", "white wine"},
			},
		},

		// Common typos in OCR
		// NOTE: Be careful with substrings! "37ml" would match inside "375ml"
		typoCorrections: map[string]string{
			"7S0ml":   "750ml",  // S instead of 5
			"7S0":     "750ml",
			"75O":     "750ml",  // O instead of 0
			"6S0ml":   "650ml",
			"3T5ml":   "375ml",  // T instead of 7
			"18O":     "180ml",  // O instead of 0
			"1Oml":    "10ml",   // O instead of 0
			"l00ml":   "100ml",  // l instead of 1
		},

		// Unit conversions to ML
		unitConversions: map[string]float64{
			"l":      1000,
			"liter":  1000,
			"litre":  1000,
			"ltr":    1000,
			"oz":     29.5735, // Fluid ounce
			"fl oz":  29.5735,
			"ml":     1,
			"cl":     10,      // Centiliter
		},
	}
}

// Normalize converts any size text to standardized ML value
func (sn *SizeNormalizer) Normalize(sizeText string, category string) (int, string) {
	if sizeText == "" {
		return 0, ""
	}

	// Clean the input
	cleaned := sn.cleanInput(sizeText)

	// DEBUG: Log if cleaning changed the input
	if cleaned != strings.ToLower(sizeText) {
		fmt.Printf("[SizeNormalizer] Input '%s' cleaned to '%s'\n", sizeText, cleaned)
	}

	// Get category rules (default to whiskey if unknown)
	rules := sn.getCategoryRules(category)

	// Step 1: Try direct alias match (highest priority)
	if ml, ok := rules.SizeAliases[cleaned]; ok {
		fmt.Printf("[SizeNormalizer] ✅ Alias match: '%s' → %d ml\n", sizeText, ml)
		return ml, cleaned
	}

	// Step 2: Try numeric extraction with unit
	if ml := sn.extractNumericSize(cleaned); ml > 0 {
		// Validate against category default sizes
		normalized := sn.closestStandardSize(ml, rules.DefaultSizes)
		fmt.Printf("[SizeNormalizer] ⚙️  Numeric extraction: '%s' → %d ml → normalized to %d ml\n", sizeText, ml, normalized)
		return normalized, cleaned
	}

	// Step 3: Try pattern matching for complex formats
	if ml := sn.patternMatch(cleaned, rules); ml > 0 {
		fmt.Printf("[SizeNormalizer] 🔍 Pattern match: '%s' → %d ml\n", sizeText, ml)
		return ml, cleaned
	}

	// Step 4: Fallback to category default (750ml for spirits, 650ml for beer)
	fmt.Printf("[SizeNormalizer] ⚠️  Default fallback: '%s' → 750ml (no match found)\n", sizeText)
	if category == "beer" {
		return 650, "default"
	}
	return 750, "default" // Whiskey/spirits default
}

// NormalizeWithCategory detects category and normalizes size
func (sn *SizeNormalizer) NormalizeWithCategory(sizeText, brandText string) (int, string, string) {
	// Detect category from brand text
	detectedCategory := sn.detectCategory(brandText)

	ml, originalText := sn.Normalize(sizeText, detectedCategory)
	return ml, originalText, detectedCategory
}

// cleanInput standardizes the input text
func (sn *SizeNormalizer) cleanInput(input string) string {
	// Convert to lowercase
	lower := strings.ToLower(input)

	// Remove extra whitespace
	lower = strings.TrimSpace(lower)
	lower = regexp.MustCompile(`\s+`).ReplaceAllString(lower, " ")

	// Fix common typos
	for typo, correction := range sn.typoCorrections {
		if strings.Contains(lower, strings.ToLower(typo)) {
			lower = strings.Replace(lower, strings.ToLower(typo), correction, -1)
		}
	}

	return lower
}

// extractNumericSize extracts ML value from text like "750ml", "1L", "1.5 liter"
func (sn *SizeNormalizer) extractNumericSize(text string) int {
	// Pattern: number (with optional decimal) + optional space + unit
	re := regexp.MustCompile(`(\d+\.?\d*)\s*(ml|l|liter|litre|ltr|oz|fl\s*oz|cl)?`)
	matches := re.FindStringSubmatch(text)

	if len(matches) < 2 {
		return 0
	}

	// Parse the number
	value, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return 0
	}

	// Get unit (default to ml if not specified)
	unit := "ml"
	if len(matches) >= 3 && matches[2] != "" {
		unit = strings.TrimSpace(matches[2])
	}

	// Convert to ML
	multiplier := sn.unitConversions[unit]
	if multiplier == 0 {
		multiplier = 1 // Default to ML
	}

	ml := value * multiplier
	return int(ml)
}

// patternMatch tries to match complex patterns like "750 ML BOTTLE", "1L FULL"
func (sn *SizeNormalizer) patternMatch(text string, rules *CategorySizeRules) int {
	// Try common patterns
	patterns := []string{
		// "750 ml bottle" pattern
		`(\d+)\s*ml.*(?:bottle|full|fl)`,
		// "1 liter" pattern
		`(\d+\.?\d*)\s*(?:l|liter|litre)`,
		// "quarter 180" pattern
		`(?:quarter|quart).*?(\d+)`,
		// "half 375" pattern
		`(?:half).*?(\d+)`,
	}

	for _, pattern := range patterns {
		re := regexp.MustCompile(pattern)
		if matches := re.FindStringSubmatch(text); len(matches) >= 2 {
			if ml := sn.extractNumericSize(matches[1]); ml > 0 {
				return ml
			}
		}
	}

	return 0
}

// closestStandardSize finds the nearest standard size for the category
func (sn *SizeNormalizer) closestStandardSize(ml int, standardSizes []int) int {
	if len(standardSizes) == 0 {
		return ml
	}

	// Allow 10% tolerance
	tolerance := 0.10

	for _, size := range standardSizes {
		minSize := float64(size) * (1 - tolerance)
		maxSize := float64(size) * (1 + tolerance)

		if float64(ml) >= minSize && float64(ml) <= maxSize {
			return size // Snap to standard size
		}
	}

	// If no match within tolerance, return closest
	closest := standardSizes[0]
	minDiff := abs(ml - closest)

	for _, size := range standardSizes[1:] {
		diff := abs(ml - size)
		if diff < minDiff {
			minDiff = diff
			closest = size
		}
	}

	return closest
}

// detectCategory detects product category from brand name or text
func (sn *SizeNormalizer) detectCategory(text string) string {
	lower := strings.ToLower(text)

	// Check each category's keywords
	for category, rules := range sn.categoryRules {
		for _, keyword := range rules.Keywords {
			if strings.Contains(lower, keyword) {
				return category
			}
		}
	}

	// Default to whiskey (most common spirits)
	return "whiskey"
}

// getCategoryRules gets rules for a category, with fallback to whiskey
func (sn *SizeNormalizer) getCategoryRules(category string) *CategorySizeRules {
	if rules, ok := sn.categoryRules[category]; ok {
		return rules
	}
	return sn.categoryRules["whiskey"] // Default
}

// GetStandardSizesForCategory returns standard sizes for a category
func (sn *SizeNormalizer) GetStandardSizesForCategory(category string) []int {
	rules := sn.getCategoryRules(category)
	return rules.DefaultSizes
}

// IsValidSizeForCategory checks if a size is valid for the category
func (sn *SizeNormalizer) IsValidSizeForCategory(ml int, category string) bool {
	rules := sn.getCategoryRules(category)

	// Check if it's a standard size or within 10% tolerance
	for _, size := range rules.DefaultSizes {
		if ml == size {
			return true
		}

		minSize := float64(size) * 0.9
		maxSize := float64(size) * 1.1
		if float64(ml) >= minSize && float64(ml) <= maxSize {
			return true
		}
	}

	return false
}

// Helper function
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
