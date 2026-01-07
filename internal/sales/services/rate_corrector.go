package services

import (
	"fmt"
	"math"
)

// RateCorrector validates and corrects rate extraction errors
type RateCorrector struct {
	tolerance float64 // Percentage tolerance for math validation (default 5%)
}

// RateCorrectionResult contains the result of rate validation and correction
type RateCorrectionResult struct {
	OriginalRate      float64 `json:"original_rate"`
	CorrectedRate     float64 `json:"corrected_rate"`
	WasCorrected      bool    `json:"was_corrected"`
	CorrectionType    string  `json:"correction_type,omitempty"` // "decimal_shift", "calculated", etc.
	CalculatedRate    float64 `json:"calculated_rate"`
	MathValidation    bool    `json:"math_validation"`
	ValidationMessage string  `json:"validation_message,omitempty"`
}

// NewRateCorrector creates a new rate corrector with default settings
func NewRateCorrector() *RateCorrector {
	return &RateCorrector{
		tolerance: 5.0, // 5% tolerance
	}
}

// NewRateCorrectorWithTolerance creates a rate corrector with custom tolerance
func NewRateCorrectorWithTolerance(tolerancePercent float64) *RateCorrector {
	if tolerancePercent < 0.1 {
		tolerancePercent = 0.1
	}
	if tolerancePercent > 20 {
		tolerancePercent = 20
	}
	return &RateCorrector{
		tolerance: tolerancePercent,
	}
}

// ValidateAndCorrectRate validates rate using Amount = Sale × Rate formula
// Returns corrected rate if decimal error detected
func (r *RateCorrector) ValidateAndCorrectRate(saleQty int, originalRate, amount float64) *RateCorrectionResult {
	result := &RateCorrectionResult{
		OriginalRate:   originalRate,
		CorrectedRate:  originalRate,
		WasCorrected:   false,
		MathValidation: false,
	}

	// Can't validate without sale quantity
	if saleQty <= 0 {
		result.ValidationMessage = "Cannot validate: sale quantity is zero or negative"
		return result
	}

	// Calculate expected rate from Amount / Sale
	calculatedRate := amount / float64(saleQty)
	result.CalculatedRate = calculatedRate

	// Check if original rate matches calculated rate (within tolerance)
	if r.isWithinTolerance(originalRate, calculatedRate) {
		result.MathValidation = true
		result.ValidationMessage = "Rate validated: matches Amount/Sale calculation"
		return result
	}

	// Check for common decimal errors

	// Case 1: Rate is 10x too low (e.g., 18.00 instead of 180.00)
	if r.isWithinTolerance(originalRate*10, calculatedRate) {
		result.CorrectedRate = originalRate * 10
		result.WasCorrected = true
		result.CorrectionType = "decimal_shift_x10"
		result.MathValidation = true
		result.ValidationMessage = fmt.Sprintf("Rate corrected: decimal error detected (%.2f → %.2f)", originalRate, result.CorrectedRate)
		fmt.Printf("🔧 [RateCorrector] Decimal error x10: %.2f → %.2f (calculated: %.2f)\n", originalRate, result.CorrectedRate, calculatedRate)
		return result
	}

	// Case 2: Rate is 100x too low (e.g., 1.80 instead of 180.00)
	if r.isWithinTolerance(originalRate*100, calculatedRate) {
		result.CorrectedRate = originalRate * 100
		result.WasCorrected = true
		result.CorrectionType = "decimal_shift_x100"
		result.MathValidation = true
		result.ValidationMessage = fmt.Sprintf("Rate corrected: decimal error detected (%.2f → %.2f)", originalRate, result.CorrectedRate)
		fmt.Printf("🔧 [RateCorrector] Decimal error x100: %.2f → %.2f (calculated: %.2f)\n", originalRate, result.CorrectedRate, calculatedRate)
		return result
	}

	// Case 3: Rate is 10x too high (e.g., 1800.00 instead of 180.00)
	if r.isWithinTolerance(originalRate/10, calculatedRate) {
		result.CorrectedRate = originalRate / 10
		result.WasCorrected = true
		result.CorrectionType = "decimal_shift_div10"
		result.MathValidation = true
		result.ValidationMessage = fmt.Sprintf("Rate corrected: decimal error detected (%.2f → %.2f)", originalRate, result.CorrectedRate)
		fmt.Printf("🔧 [RateCorrector] Decimal error /10: %.2f → %.2f (calculated: %.2f)\n", originalRate, result.CorrectedRate, calculatedRate)
		return result
	}

	// Case 4: Use calculated rate if original rate is way off
	percentError := math.Abs(originalRate-calculatedRate) / calculatedRate * 100
	if percentError > 50 {
		result.CorrectedRate = calculatedRate
		result.WasCorrected = true
		result.CorrectionType = "calculated_replacement"
		result.MathValidation = true
		result.ValidationMessage = fmt.Sprintf("Rate replaced with calculated value: %.2f → %.2f (%.0f%% error)", originalRate, calculatedRate, percentError)
		fmt.Printf("🔧 [RateCorrector] Rate replaced: %.2f → %.2f (%.0f%% error)\n", originalRate, calculatedRate, percentError)
		return result
	}

	// Rate doesn't match but error is within acceptable range
	result.ValidationMessage = fmt.Sprintf("Rate mismatch: original=%.2f, calculated=%.2f (%.1f%% error)", originalRate, calculatedRate, percentError)
	return result
}

// ValidateAmount checks if Amount = Sale × Rate
func (r *RateCorrector) ValidateAmount(saleQty int, rate, amount float64) (bool, float64) {
	if saleQty <= 0 {
		return false, 0
	}

	expectedAmount := float64(saleQty) * rate
	return r.isWithinTolerance(expectedAmount, amount), expectedAmount
}

// isWithinTolerance checks if two values are within the tolerance percentage
func (r *RateCorrector) isWithinTolerance(value1, value2 float64) bool {
	if value2 == 0 {
		return value1 == 0
	}

	percentDiff := math.Abs(value1-value2) / math.Abs(value2) * 100
	return percentDiff <= r.tolerance
}

// CorrectOCRItemRates corrects rates for a batch of OCR items
func (r *RateCorrector) CorrectOCRItemRates(items []map[string]interface{}) []map[string]interface{} {
	correctedItems := make([]map[string]interface{}, len(items))
	correctedCount := 0

	for i, item := range items {
		correctedItems[i] = make(map[string]interface{})
		for k, v := range item {
			correctedItems[i][k] = v
		}

		// Get required fields
		saleQty := getIntField(item, "sale")
		rate := getFloatField(item, "rate")
		amount := getFloatField(item, "amount")

		// Skip if missing data
		if saleQty <= 0 || rate <= 0 || amount <= 0 {
			continue
		}

		// Validate and correct rate
		result := r.ValidateAndCorrectRate(saleQty, rate, amount)

		if result.WasCorrected {
			correctedItems[i]["rate"] = result.CorrectedRate
			correctedItems[i]["rate_corrected"] = true
			correctedItems[i]["rate_correction_note"] = result.ValidationMessage
			correctedCount++
		}

		// Add math validation status
		correctedItems[i]["math_validated"] = result.MathValidation
	}

	if correctedCount > 0 {
		fmt.Printf("📊 [RateCorrector] Corrected %d/%d item rates\n", correctedCount, len(items))
	}

	return correctedItems
}

// Helper functions to extract fields from map
func getIntField(m map[string]interface{}, key string) int {
	if v, ok := m[key]; ok {
		switch val := v.(type) {
		case int:
			return val
		case float64:
			return int(val)
		case int64:
			return int(val)
		}
	}
	return 0
}

func getFloatField(m map[string]interface{}, key string) float64 {
	if v, ok := m[key]; ok {
		switch val := v.(type) {
		case float64:
			return val
		case int:
			return float64(val)
		case int64:
			return float64(val)
		}
	}
	return 0
}

// BatchRateValidation contains stats for a batch validation
type BatchRateValidation struct {
	TotalItems      int     `json:"total_items"`
	ValidatedItems  int     `json:"validated_items"`
	CorrectedItems  int     `json:"corrected_items"`
	FailedItems     int     `json:"failed_items"`
	ValidationRate  float64 `json:"validation_rate"`  // Percentage of items that passed validation
	CorrectionRate  float64 `json:"correction_rate"`  // Percentage of items that needed correction
}

// ValidateBatch returns validation statistics for a batch of items
func (r *RateCorrector) ValidateBatch(items []map[string]interface{}) *BatchRateValidation {
	stats := &BatchRateValidation{
		TotalItems: len(items),
	}

	for _, item := range items {
		saleQty := getIntField(item, "sale")
		rate := getFloatField(item, "rate")
		amount := getFloatField(item, "amount")

		if saleQty <= 0 || rate <= 0 || amount <= 0 {
			continue
		}

		result := r.ValidateAndCorrectRate(saleQty, rate, amount)

		if result.MathValidation {
			stats.ValidatedItems++
		} else {
			stats.FailedItems++
		}

		if result.WasCorrected {
			stats.CorrectedItems++
		}
	}

	if stats.TotalItems > 0 {
		stats.ValidationRate = float64(stats.ValidatedItems) / float64(stats.TotalItems) * 100
		stats.CorrectionRate = float64(stats.CorrectedItems) / float64(stats.TotalItems) * 100
	}

	return stats
}
