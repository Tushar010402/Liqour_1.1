package services

import (
	"fmt"
	"math"
	"sort"
)

// ExtractionValidator validates OCR extraction completeness
type ExtractionValidator struct {
	minCompletenessRate float64 // Minimum acceptable extraction rate (default 90%)
	amountTolerance     float64 // Tolerance for grand total validation (default 5%)
}

// ExtractionValidation contains the result of extraction validation
type ExtractionValidation struct {
	ExpectedItems      int       `json:"expected_items"`
	ExtractedItems     int       `json:"extracted_items"`
	CompletionRate     float64   `json:"completion_rate"`     // Percentage of items extracted
	MissingRowNumbers  []int     `json:"missing_row_numbers"` // Gap analysis
	DuplicateRows      []int     `json:"duplicate_rows"`
	MathValidatedItems int       `json:"math_validated_items"`
	MathErrorItems     int       `json:"math_error_items"`
	MathValidationRate float64   `json:"math_validation_rate"`
	GrandTotalMatch    bool      `json:"grand_total_match"`
	GrandTotalExtracted float64  `json:"grand_total_extracted"`
	GrandTotalCalculated float64 `json:"grand_total_calculated"`
	GrandTotalDiff     float64   `json:"grand_total_diff"`
	IsComplete         bool      `json:"is_complete"` // True if meets minimum requirements
	Warnings           []string  `json:"warnings"`
	Suggestions        []string  `json:"suggestions"`
}

// NewExtractionValidator creates a new extraction validator with default settings
func NewExtractionValidator() *ExtractionValidator {
	return &ExtractionValidator{
		minCompletenessRate: 90.0, // 90% minimum
		amountTolerance:     5.0,  // 5% tolerance
	}
}

// NewExtractionValidatorWithOptions creates a validator with custom settings
func NewExtractionValidatorWithOptions(minCompleteness, amountTolerance float64) *ExtractionValidator {
	if minCompleteness < 50 {
		minCompleteness = 50
	}
	if minCompleteness > 100 {
		minCompleteness = 100
	}
	if amountTolerance < 0.1 {
		amountTolerance = 0.1
	}
	if amountTolerance > 20 {
		amountTolerance = 20
	}

	return &ExtractionValidator{
		minCompletenessRate: minCompleteness,
		amountTolerance:     amountTolerance,
	}
}

// ValidateExtraction validates the completeness and accuracy of extracted items
func (v *ExtractionValidator) ValidateExtraction(
	items []map[string]interface{},
	expectedItemCount int,
	grandTotalFromReceipt float64,
) *ExtractionValidation {
	result := &ExtractionValidation{
		ExpectedItems:   expectedItemCount,
		ExtractedItems:  len(items),
		Warnings:        []string{},
		Suggestions:     []string{},
	}

	// Calculate completion rate
	if expectedItemCount > 0 {
		result.CompletionRate = float64(len(items)) / float64(expectedItemCount) * 100
	} else {
		result.CompletionRate = 100 // If no expected count, assume complete
	}

	// Analyze row numbers for gaps
	v.analyzeRowNumbers(items, result)

	// Calculate grand total from extracted items
	result.GrandTotalCalculated = v.calculateGrandTotal(items)
	result.GrandTotalExtracted = grandTotalFromReceipt

	// Validate grand total
	if grandTotalFromReceipt > 0 {
		diff := math.Abs(result.GrandTotalCalculated - grandTotalFromReceipt)
		result.GrandTotalDiff = diff
		percentDiff := diff / grandTotalFromReceipt * 100
		result.GrandTotalMatch = percentDiff <= v.amountTolerance

		if !result.GrandTotalMatch {
			result.Warnings = append(result.Warnings, fmt.Sprintf(
				"Grand total mismatch: extracted=%.2f, calculated=%.2f (diff=%.2f, %.1f%%)",
				grandTotalFromReceipt, result.GrandTotalCalculated, diff, percentDiff))

			// Estimate missing items based on amount difference
			if result.GrandTotalCalculated < grandTotalFromReceipt && len(items) > 0 {
				avgItemAmount := result.GrandTotalCalculated / float64(len(items))
				if avgItemAmount > 0 {
					estimatedMissing := int(diff / avgItemAmount)
					if estimatedMissing > 0 {
						result.Suggestions = append(result.Suggestions, fmt.Sprintf(
							"Based on amount difference, approximately %d items may be missing", estimatedMissing))
					}
				}
			}
		}
	}

	// Math validation for each item
	v.validateItemMath(items, result)

	// Determine if extraction is complete
	result.IsComplete = v.determineCompleteness(result)

	// Log summary
	fmt.Printf("📋 [ExtractionValidator] Validation: %d/%d items (%.1f%%), Grand Total: %.2f vs %.2f, Complete: %v\n",
		result.ExtractedItems, result.ExpectedItems, result.CompletionRate,
		result.GrandTotalCalculated, result.GrandTotalExtracted, result.IsComplete)

	return result
}

// analyzeRowNumbers finds gaps and duplicates in row numbers
func (v *ExtractionValidator) analyzeRowNumbers(items []map[string]interface{}, result *ExtractionValidation) {
	rowNumbers := make([]int, 0)
	rowCounts := make(map[int]int)

	for _, item := range items {
		if rowNum := getIntField(item, "s_no"); rowNum > 0 {
			rowNumbers = append(rowNumbers, rowNum)
			rowCounts[rowNum]++
		}
	}

	if len(rowNumbers) == 0 {
		return
	}

	// Sort row numbers
	sort.Ints(rowNumbers)

	// Find gaps
	result.MissingRowNumbers = []int{}
	for i := 1; i < len(rowNumbers); i++ {
		expected := rowNumbers[i-1] + 1
		actual := rowNumbers[i]
		if actual > expected {
			for j := expected; j < actual; j++ {
				result.MissingRowNumbers = append(result.MissingRowNumbers, j)
			}
		}
	}

	// Find duplicates
	result.DuplicateRows = []int{}
	for row, count := range rowCounts {
		if count > 1 {
			result.DuplicateRows = append(result.DuplicateRows, row)
		}
	}

	if len(result.MissingRowNumbers) > 0 {
		result.Warnings = append(result.Warnings, fmt.Sprintf(
			"Missing row numbers: %v", result.MissingRowNumbers))
	}

	if len(result.DuplicateRows) > 0 {
		result.Warnings = append(result.Warnings, fmt.Sprintf(
			"Duplicate row numbers: %v", result.DuplicateRows))
	}
}

// calculateGrandTotal sums the amount column
func (v *ExtractionValidator) calculateGrandTotal(items []map[string]interface{}) float64 {
	var total float64
	for _, item := range items {
		amount := getFloatField(item, "amount")
		if amount > 0 {
			total += amount
		}
	}
	return total
}

// validateItemMath validates Amount = Sale × Rate for each item
func (v *ExtractionValidator) validateItemMath(items []map[string]interface{}, result *ExtractionValidation) {
	for _, item := range items {
		sale := getIntField(item, "sale")
		rate := getFloatField(item, "rate")
		amount := getFloatField(item, "amount")

		if sale <= 0 || rate <= 0 || amount <= 0 {
			continue
		}

		expectedAmount := float64(sale) * rate
		percentDiff := math.Abs(expectedAmount-amount) / amount * 100

		if percentDiff <= v.amountTolerance {
			result.MathValidatedItems++
		} else {
			result.MathErrorItems++
		}
	}

	validatable := result.MathValidatedItems + result.MathErrorItems
	if validatable > 0 {
		result.MathValidationRate = float64(result.MathValidatedItems) / float64(validatable) * 100
	}

	if result.MathErrorItems > 0 {
		result.Warnings = append(result.Warnings, fmt.Sprintf(
			"%d items failed math validation (Amount != Sale × Rate)", result.MathErrorItems))
	}
}

// determineCompleteness decides if extraction meets quality requirements
func (v *ExtractionValidator) determineCompleteness(result *ExtractionValidation) bool {
	// Must meet minimum completion rate
	if result.CompletionRate < v.minCompletenessRate {
		result.Suggestions = append(result.Suggestions,
			fmt.Sprintf("Extraction below %.0f%% threshold - re-extraction recommended", v.minCompletenessRate))
		return false
	}

	// Grand total should match if available
	if result.GrandTotalExtracted > 0 && !result.GrandTotalMatch {
		// If grand total mismatch is significant, flag as incomplete
		percentDiff := math.Abs(result.GrandTotalCalculated-result.GrandTotalExtracted) / result.GrandTotalExtracted * 100
		if percentDiff > 10 {
			result.Suggestions = append(result.Suggestions,
				"Significant grand total mismatch - some items may be missing")
			return false
		}
	}

	// Math validation should be high
	if result.MathValidationRate < 80 && result.MathValidatedItems+result.MathErrorItems > 5 {
		result.Suggestions = append(result.Suggestions,
			"Low math validation rate - rate/amount corrections recommended")
		// Don't mark as incomplete just for math errors, they can be corrected
	}

	return true
}

// QuickValidation performs a fast validation check
type QuickValidationResult struct {
	ItemCount          int     `json:"item_count"`
	TotalAmount        float64 `json:"total_amount"`
	HasGaps            bool    `json:"has_gaps"`
	HighestRowNumber   int     `json:"highest_row_number"`
	ExpectedByRowNum   int     `json:"expected_by_row_num"` // Based on highest row number
	LikelyMissingItems int     `json:"likely_missing_items"`
	NeedsReExtraction  bool    `json:"needs_re_extraction"`
}

// QuickValidate performs a fast validation without full analysis
func (v *ExtractionValidator) QuickValidate(items []map[string]interface{}, grandTotal float64) *QuickValidationResult {
	result := &QuickValidationResult{
		ItemCount: len(items),
	}

	// Find highest row number and calculate total
	for _, item := range items {
		if rowNum := getIntField(item, "s_no"); rowNum > result.HighestRowNumber {
			result.HighestRowNumber = rowNum
		}
		result.TotalAmount += getFloatField(item, "amount")
	}

	// Expected items based on row numbers
	result.ExpectedByRowNum = result.HighestRowNumber
	if result.ExpectedByRowNum > result.ItemCount {
		result.HasGaps = true
		result.LikelyMissingItems = result.ExpectedByRowNum - result.ItemCount
	}

	// Check if grand total suggests missing items
	if grandTotal > 0 && result.TotalAmount > 0 {
		if result.TotalAmount < grandTotal*0.8 { // Less than 80% of grand total
			avgAmount := result.TotalAmount / float64(result.ItemCount)
			diff := grandTotal - result.TotalAmount
			estimatedMissing := int(diff / avgAmount)
			if estimatedMissing > result.LikelyMissingItems {
				result.LikelyMissingItems = estimatedMissing
			}
		}
	}

	// Determine if re-extraction is needed
	if result.LikelyMissingItems > 3 || (result.HasGaps && result.LikelyMissingItems > 0) {
		result.NeedsReExtraction = true
	}

	return result
}

// ValidateAgainstExpected validates extraction against expected item count from detection
func (v *ExtractionValidator) ValidateAgainstExpected(items []map[string]interface{}, expectedFromDetection int) *ExtractionValidation {
	return v.ValidateExtraction(items, expectedFromDetection, 0)
}

// SuggestReExtraction determines if and how to re-extract
type ReExtractionSuggestion struct {
	ShouldReExtract bool     `json:"should_re_extract"`
	Reason          string   `json:"reason"`
	Strategy        string   `json:"strategy"` // "full", "partial", "chunked"
	Regions         []int    `json:"regions,omitempty"` // Which regions to re-extract
}

// GetReExtractionSuggestion provides guidance on re-extraction
func (v *ExtractionValidator) GetReExtractionSuggestion(validation *ExtractionValidation) *ReExtractionSuggestion {
	suggestion := &ReExtractionSuggestion{
		ShouldReExtract: false,
	}

	// Severe incompleteness
	if validation.CompletionRate < 50 {
		suggestion.ShouldReExtract = true
		suggestion.Reason = fmt.Sprintf("Severe incompleteness: only %.0f%% extracted", validation.CompletionRate)
		suggestion.Strategy = "full"
		return suggestion
	}

	// Moderate incompleteness
	if validation.CompletionRate < 80 {
		suggestion.ShouldReExtract = true
		suggestion.Reason = fmt.Sprintf("Moderate incompleteness: %.0f%% extracted", validation.CompletionRate)
		suggestion.Strategy = "chunked" // Try extracting in chunks
		return suggestion
	}

	// Grand total mismatch suggests missing items
	if !validation.GrandTotalMatch && validation.GrandTotalExtracted > 0 {
		percentDiff := validation.GrandTotalDiff / validation.GrandTotalExtracted * 100
		if percentDiff > 15 {
			suggestion.ShouldReExtract = true
			suggestion.Reason = fmt.Sprintf("Grand total mismatch: %.0f%% difference", percentDiff)
			suggestion.Strategy = "partial"
			return suggestion
		}
	}

	// Many missing rows
	if len(validation.MissingRowNumbers) > 5 {
		suggestion.ShouldReExtract = true
		suggestion.Reason = fmt.Sprintf("%d row numbers missing", len(validation.MissingRowNumbers))
		suggestion.Strategy = "partial"
		suggestion.Regions = validation.MissingRowNumbers
		return suggestion
	}

	return suggestion
}
