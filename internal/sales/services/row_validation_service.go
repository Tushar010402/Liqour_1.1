package services

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"gorm.io/gorm"
)

// RowValidationService handles comprehensive validation of OCR extracted rows
// Phase 2: Mathematical validation + Phase 3: Inventory cross-validation
type RowValidationService struct {
	db *gorm.DB
}

// NewRowValidationService creates a new row validation service
func NewRowValidationService(db *gorm.DB) *RowValidationService {
	return &RowValidationService{db: db}
}

// MathCheck represents a single mathematical validation check
type MathCheck struct {
	CheckName     string  `json:"check_name"`      // "total_calculation", "closing_calculation", "amount_calculation"
	Formula       string  `json:"formula"`         // "Opening + Receipt = Total"
	LeftSide      float64 `json:"left_side"`       // Calculated value
	RightSide     float64 `json:"right_side"`      // Extracted value
	IsValid       bool    `json:"is_valid"`
	Difference    float64 `json:"difference"`
	Tolerance     float64 `json:"tolerance"`       // Acceptable difference
	Severity      string  `json:"severity"`        // low, medium, high, critical
	Suggestion    string  `json:"suggestion,omitempty"`
}

// FieldValidation represents validation result for a single field
type FieldValidation struct {
	FieldName     string      `json:"field_name"`
	OCRValue      interface{} `json:"ocr_value"`
	EnteredValue  interface{} `json:"entered_value,omitempty"`
	ExpectedValue interface{} `json:"expected_value,omitempty"` // From math or database
	IsMatch       bool        `json:"is_match"`
	Confidence    float64     `json:"confidence"`
	Severity      string      `json:"severity"`                 // low, medium, high, critical
	Source        string      `json:"source,omitempty"`         // ocr, math, database
}

// InventoryValidation represents cross-validation with inventory data
type InventoryValidation struct {
	CheckName     string  `json:"check_name"`
	OCRValue      int     `json:"ocr_value"`
	ExpectedValue int     `json:"expected_value"`
	IsMatch       bool    `json:"is_match"`
	Difference    int     `json:"difference"`
	Severity      string  `json:"severity"`
	Suggestion    string  `json:"suggestion,omitempty"`
}

// RateValidation represents validation of rate against product MRP
type RateValidation struct {
	CheckName     string  `json:"check_name"`
	OCRRate       float64 `json:"ocr_rate"`
	ProductMRP    float64 `json:"product_mrp"`
	IsMatch       bool    `json:"is_match"`
	Difference    float64 `json:"difference"`
	Severity      string  `json:"severity"`
	Suggestion    string  `json:"suggestion,omitempty"`
}

// RowValidationResult represents the complete validation result for a single row
type RowValidationResult struct {
	RowNumber       int                         `json:"row_number"`
	BrandName       string                      `json:"brand_name"`

	// Field-level validation
	Fields          map[string]FieldValidation  `json:"fields"`

	// Mathematical checks
	MathChecks      []MathCheck                 `json:"math_checks"`
	MathValidation  MathValidationSummary       `json:"math_validation"`

	// Inventory cross-validation
	InventoryChecks []InventoryValidation       `json:"inventory_checks,omitempty"`
	RateChecks      []RateValidation            `json:"rate_checks,omitempty"`

	// Overall row status
	IsRowValid      bool                        `json:"is_row_valid"`
	RowConfidence   float64                     `json:"row_confidence"`
	Issues          []ValidationIssue           `json:"issues,omitempty"`
	Suggestions     []string                    `json:"suggestions,omitempty"`
}

// MathValidationSummary provides an overall summary of mathematical validation
type MathValidationSummary struct {
	TotalChecks   int     `json:"total_checks"`
	PassedChecks  int     `json:"passed_checks"`
	FailedChecks  int     `json:"failed_checks"`
	PassRate      float64 `json:"pass_rate"`       // 0-100%
	AllPassed     bool    `json:"all_passed"`
}

// ValidationIssue represents a single validation issue
type ValidationIssue struct {
	RowNumber   int    `json:"row_number"`
	FieldName   string `json:"field_name"`
	IssueType   string `json:"issue_type"`     // math_mismatch, inventory_mismatch, rate_mismatch
	Description string `json:"description"`
	OCRValue    string `json:"ocr_value"`
	ExpectedValue string `json:"expected_value,omitempty"`
	EnteredValue  string `json:"entered_value,omitempty"`
	Severity    string `json:"severity"`
	Suggestion  string `json:"suggestion"`
}

// ComprehensiveValidationResult represents the complete validation result for all rows
type ComprehensiveValidationResult struct {
	// Overall Status
	OverallStatus       string                  `json:"overall_status"`       // verified, mismatches, errors
	OverallAccuracy     float64                 `json:"overall_accuracy"`     // 0-100%
	OverallConfidence   float64                 `json:"overall_confidence"`   // 0-100%

	// Row-by-Row Results
	Rows                []RowValidationResult   `json:"rows"`
	TotalRows           int                     `json:"total_rows"`
	ValidRows           int                     `json:"valid_rows"`
	InvalidRows         int                     `json:"invalid_rows"`

	// Field-Level Aggregates
	FieldAccuracies     map[string]float64      `json:"field_accuracies"`

	// Mathematical Validation Summary
	MathValidation      MathValidationSummary   `json:"math_validation"`

	// Inventory Validation Summary
	InventoryValidation InventoryValidationSummary `json:"inventory_validation,omitempty"`

	// Suggestions for Manager
	CriticalIssues      []ValidationIssue       `json:"critical_issues"`
	Warnings            []ValidationIssue       `json:"warnings"`
	Recommendations     []string                `json:"recommendations"`

	// Decision Helper
	RecommendedAction   string                  `json:"recommended_action"` // approve, reject, review
	ConfidenceLevel     string                  `json:"confidence_level"`   // high, medium, low

	// Timestamps
	ValidatedAt         time.Time               `json:"validated_at"`
}

// InventoryValidationSummary provides summary of inventory cross-validation
type InventoryValidationSummary struct {
	TotalChecks   int     `json:"total_checks"`
	PassedChecks  int     `json:"passed_checks"`
	FailedChecks  int     `json:"failed_checks"`
	PassRate      float64 `json:"pass_rate"`
	AllPassed     bool    `json:"all_passed"`
}

// ValidateRow performs comprehensive validation on a single OCR extracted row
func (s *RowValidationService) ValidateRow(row models.OCRItem) RowValidationResult {
	result := RowValidationResult{
		RowNumber:  row.RowNumber,
		BrandName:  row.BrandText,
		Fields:     make(map[string]FieldValidation),
		MathChecks: make([]MathCheck, 0, 3),
		Issues:     make([]ValidationIssue, 0),
		Suggestions: make([]string, 0),
		IsRowValid: true,
		RowConfidence: 100.0,
	}

	// ===== PHASE 2: Mathematical Validation =====

	// 1. Total Validation: Opening + Receipt = Total
	totalCheck := MathCheck{
		CheckName:  "total_calculation",
		Formula:    "Opening + Receipt = Total",
		LeftSide:   float64(row.OpeningStock + row.ReceiptQty),
		RightSide:  float64(row.TotalStock),
		Tolerance:  0, // Exact match required for integers
	}
	totalCheck.Difference = totalCheck.LeftSide - totalCheck.RightSide
	totalCheck.IsValid = totalCheck.LeftSide == totalCheck.RightSide

	if !totalCheck.IsValid {
		totalCheck.Severity = getSeverityFromDifference(totalCheck.Difference, float64(row.TotalStock))
		totalCheck.Suggestion = fmt.Sprintf("Expected Total = %d + %d = %d, but got %d",
			row.OpeningStock, row.ReceiptQty, row.OpeningStock+row.ReceiptQty, row.TotalStock)
		result.IsRowValid = false
		result.RowConfidence -= 15.0
		result.Issues = append(result.Issues, ValidationIssue{
			RowNumber:   row.RowNumber,
			FieldName:   "total_stock",
			IssueType:   "math_mismatch",
			Description: "Total stock does not match Opening + Receipt",
			OCRValue:    fmt.Sprintf("%d", row.TotalStock),
			ExpectedValue: fmt.Sprintf("%d", row.OpeningStock+row.ReceiptQty),
			Severity:    totalCheck.Severity,
			Suggestion:  totalCheck.Suggestion,
		})
	}
	result.MathChecks = append(result.MathChecks, totalCheck)

	// 2. Closing Validation: Total - Sale = Closing
	closingCheck := MathCheck{
		CheckName:  "closing_calculation",
		Formula:    "Total - Sale = Closing",
		LeftSide:   float64(row.TotalStock - row.SaleQuantity),
		RightSide:  float64(row.ClosingStock),
		Tolerance:  0, // Exact match required for integers
	}
	closingCheck.Difference = closingCheck.LeftSide - closingCheck.RightSide
	closingCheck.IsValid = closingCheck.LeftSide == closingCheck.RightSide

	if !closingCheck.IsValid {
		closingCheck.Severity = getSeverityFromDifference(closingCheck.Difference, float64(row.ClosingStock))
		closingCheck.Suggestion = fmt.Sprintf("Expected Closing = %d - %d = %d, but got %d",
			row.TotalStock, row.SaleQuantity, row.TotalStock-row.SaleQuantity, row.ClosingStock)
		result.IsRowValid = false
		result.RowConfidence -= 15.0
		result.Issues = append(result.Issues, ValidationIssue{
			RowNumber:   row.RowNumber,
			FieldName:   "closing_stock",
			IssueType:   "math_mismatch",
			Description: "Closing stock does not match Total - Sale",
			OCRValue:    fmt.Sprintf("%d", row.ClosingStock),
			ExpectedValue: fmt.Sprintf("%d", row.TotalStock-row.SaleQuantity),
			Severity:    closingCheck.Severity,
			Suggestion:  closingCheck.Suggestion,
		})
	}
	result.MathChecks = append(result.MathChecks, closingCheck)

	// 3. Amount Validation: Sale × Rate = Amount
	expectedAmount := float64(row.SaleQuantity) * row.Rate
	amountCheck := MathCheck{
		CheckName:  "amount_calculation",
		Formula:    "Sale × Rate = Amount",
		LeftSide:   expectedAmount,
		RightSide:  row.Amount,
		Tolerance:  1.0, // ₹1 tolerance for rounding
	}
	amountCheck.Difference = math.Abs(amountCheck.LeftSide - amountCheck.RightSide)
	amountCheck.IsValid = amountCheck.Difference <= amountCheck.Tolerance

	if !amountCheck.IsValid {
		amountCheck.Severity = getSeverityFromDifference(amountCheck.Difference, row.Amount)
		amountCheck.Suggestion = fmt.Sprintf("Expected Amount = %d × %.2f = %.2f, but got %.2f (diff: %.2f)",
			row.SaleQuantity, row.Rate, expectedAmount, row.Amount, amountCheck.Difference)
		result.IsRowValid = false
		result.RowConfidence -= 10.0
		result.Issues = append(result.Issues, ValidationIssue{
			RowNumber:   row.RowNumber,
			FieldName:   "amount",
			IssueType:   "math_mismatch",
			Description: "Amount does not match Sale × Rate",
			OCRValue:    fmt.Sprintf("%.2f", row.Amount),
			ExpectedValue: fmt.Sprintf("%.2f", expectedAmount),
			Severity:    amountCheck.Severity,
			Suggestion:  amountCheck.Suggestion,
		})
	}
	result.MathChecks = append(result.MathChecks, amountCheck)

	// Calculate math validation summary
	passedCount := 0
	for _, check := range result.MathChecks {
		if check.IsValid {
			passedCount++
		}
	}

	result.MathValidation = MathValidationSummary{
		TotalChecks:  len(result.MathChecks),
		PassedChecks: passedCount,
		FailedChecks: len(result.MathChecks) - passedCount,
		PassRate:     float64(passedCount) / float64(len(result.MathChecks)) * 100,
		AllPassed:    passedCount == len(result.MathChecks),
	}

	// Ensure confidence doesn't go below 0
	if result.RowConfidence < 0 {
		result.RowConfidence = 0
	}

	// Add field validations for each column
	result.Fields["opening_stock"] = FieldValidation{
		FieldName:   "opening_stock",
		OCRValue:    row.OpeningStock,
		Confidence:  getFieldConfidence(row.FieldConfidences, "Opening"),
		Source:      "ocr",
	}
	result.Fields["receipt_qty"] = FieldValidation{
		FieldName:   "receipt_qty",
		OCRValue:    row.ReceiptQty,
		Confidence:  getFieldConfidence(row.FieldConfidences, "Receipt"),
		Source:      "ocr",
	}
	result.Fields["total_stock"] = FieldValidation{
		FieldName:     "total_stock",
		OCRValue:      row.TotalStock,
		ExpectedValue: row.OpeningStock + row.ReceiptQty,
		IsMatch:       totalCheck.IsValid,
		Confidence:    getFieldConfidence(row.FieldConfidences, "Total"),
		Severity:      totalCheck.Severity,
		Source:        "ocr",
	}
	result.Fields["sale_quantity"] = FieldValidation{
		FieldName:   "sale_quantity",
		OCRValue:    row.SaleQuantity,
		Confidence:  getFieldConfidence(row.FieldConfidences, "Sale"),
		Source:      "ocr",
	}
	result.Fields["rate"] = FieldValidation{
		FieldName:   "rate",
		OCRValue:    row.Rate,
		Confidence:  getFieldConfidence(row.FieldConfidences, "Rate"),
		Source:      "ocr",
	}
	result.Fields["amount"] = FieldValidation{
		FieldName:     "amount",
		OCRValue:      row.Amount,
		ExpectedValue: expectedAmount,
		IsMatch:       amountCheck.IsValid,
		Confidence:    getFieldConfidence(row.FieldConfidences, "Amount"),
		Severity:      amountCheck.Severity,
		Source:        "ocr",
	}
	result.Fields["closing_stock"] = FieldValidation{
		FieldName:     "closing_stock",
		OCRValue:      row.ClosingStock,
		ExpectedValue: row.TotalStock - row.SaleQuantity,
		IsMatch:       closingCheck.IsValid,
		Confidence:    getFieldConfidence(row.FieldConfidences, "Closing"),
		Severity:      closingCheck.Severity,
		Source:        "ocr",
	}

	// Generate suggestions based on issues
	if len(result.Issues) > 0 {
		result.Suggestions = append(result.Suggestions,
			"Review the highlighted calculations carefully before approving")
	}
	if result.MathValidation.FailedChecks > 1 {
		result.Suggestions = append(result.Suggestions,
			"Multiple calculation errors detected - may indicate OCR extraction issue")
	}

	return result
}

// ValidateOpeningStock validates opening stock against previous day's closing
// Phase 3.1: Inventory Cross-Validation
func (s *RowValidationService) ValidateOpeningStock(
	ctx context.Context,
	tenantID, shopID string,
	productID *string,
	ocrOpening int,
	recordDate time.Time,
) InventoryValidation {

	result := InventoryValidation{
		CheckName: "opening_stock_reconciliation",
		OCRValue:  ocrOpening,
		Severity:  "low",
	}

	if productID == nil || *productID == "" {
		result.Suggestion = "Product not matched - cannot verify against previous closing"
		return result
	}

	// Get previous day's closing stock from daily_sales_items
	var previousClosing int
	err := s.db.Table("daily_sales_items dsi").
		Joins("JOIN daily_sales_records dsr ON dsi.daily_sales_record_id = dsr.id").
		Where("dsr.tenant_id = ? AND dsr.shop_id = ? AND dsi.product_id = ?",
			tenantID, shopID, *productID).
		Where("dsr.record_date < ? AND dsr.status = 'approved'", recordDate).
		Order("dsr.record_date DESC").
		Limit(1).
		Select("dsi.closing_stock").
		Scan(&previousClosing).Error

	if err != nil || previousClosing == 0 {
		result.Suggestion = "No previous closing stock found - this may be a new product entry"
		return result
	}

	result.ExpectedValue = previousClosing
	result.Difference = ocrOpening - previousClosing
	result.IsMatch = ocrOpening == previousClosing

	if !result.IsMatch {
		absDiff := result.Difference
		if absDiff < 0 {
			absDiff = -absDiff
		}

		if absDiff <= 2 {
			result.Severity = "low"
			result.Suggestion = fmt.Sprintf("Minor difference (%d) - may be acceptable", absDiff)
		} else if absDiff <= 5 {
			result.Severity = "medium"
			result.Suggestion = fmt.Sprintf("Opening (%d) differs from previous closing (%d) by %d units",
				ocrOpening, previousClosing, absDiff)
		} else {
			result.Severity = "high"
			result.Suggestion = fmt.Sprintf("CRITICAL: Opening (%d) differs significantly from previous closing (%d)",
				ocrOpening, previousClosing)
		}
	}

	return result
}

// ValidateRate validates the extracted rate against product MRP
// Phase 3.2: Rate/MRP Validation
func (s *RowValidationService) ValidateRate(
	ctx context.Context,
	tenantID string,
	productID *string,
	ocrRate float64,
) RateValidation {

	result := RateValidation{
		CheckName: "rate_mrp_validation",
		OCRRate:   ocrRate,
		Severity:  "low",
	}

	if productID == nil || *productID == "" {
		result.Suggestion = "Product not matched - cannot verify rate against MRP"
		return result
	}

	// Get product MRP from brand_variants
	var productMRP float64
	err := s.db.Table("brand_variants").
		Where("id = ? AND tenant_id = ?", *productID, tenantID).
		Select("COALESCE(selling_price, mrp, 0)").
		Scan(&productMRP).Error

	if err != nil || productMRP == 0 {
		result.Suggestion = "Product MRP not found in database"
		return result
	}

	result.ProductMRP = productMRP
	result.Difference = ocrRate - productMRP

	// Allow 2% tolerance for price differences
	tolerance := productMRP * 0.02
	result.IsMatch = math.Abs(result.Difference) <= tolerance

	if !result.IsMatch {
		absDiff := math.Abs(result.Difference)
		percentDiff := (absDiff / productMRP) * 100

		if percentDiff <= 5 {
			result.Severity = "low"
			result.Suggestion = fmt.Sprintf("Rate differs by %.1f%% from MRP", percentDiff)
		} else if percentDiff <= 10 {
			result.Severity = "medium"
			result.Suggestion = fmt.Sprintf("Rate (%.2f) differs from MRP (%.2f) by %.1f%%",
				ocrRate, productMRP, percentDiff)
		} else {
			result.Severity = "high"
			result.Suggestion = fmt.Sprintf("CRITICAL: Rate (%.2f) differs significantly from MRP (%.2f)",
				ocrRate, productMRP)
		}
	}

	return result
}

// ValidateAllRows validates all OCR items in a batch
func (s *RowValidationService) ValidateAllRows(
	ctx context.Context,
	items []models.OCRItem,
) ComprehensiveValidationResult {

	result := ComprehensiveValidationResult{
		Rows:            make([]RowValidationResult, 0, len(items)),
		TotalRows:       len(items),
		FieldAccuracies: make(map[string]float64),
		CriticalIssues:  make([]ValidationIssue, 0),
		Warnings:        make([]ValidationIssue, 0),
		Recommendations: make([]string, 0),
		ValidatedAt:     time.Now(),
	}

	var totalConfidence float64
	var totalMathChecks, passedMathChecks int

	// Field accuracy accumulators
	fieldMatches := make(map[string]int)
	fieldTotals := make(map[string]int)
	fields := []string{"opening_stock", "receipt_qty", "total_stock", "sale_quantity", "rate", "amount", "closing_stock"}

	for _, field := range fields {
		fieldMatches[field] = 0
		fieldTotals[field] = 0
	}

	// Validate each row
	for _, item := range items {
		rowResult := s.ValidateRow(item)
		result.Rows = append(result.Rows, rowResult)

		totalConfidence += rowResult.RowConfidence
		totalMathChecks += rowResult.MathValidation.TotalChecks
		passedMathChecks += rowResult.MathValidation.PassedChecks

		if rowResult.IsRowValid {
			result.ValidRows++
		} else {
			result.InvalidRows++
		}

		// Categorize issues by severity
		for _, issue := range rowResult.Issues {
			if issue.Severity == "critical" || issue.Severity == "high" {
				result.CriticalIssues = append(result.CriticalIssues, issue)
			} else {
				result.Warnings = append(result.Warnings, issue)
			}
		}

		// Update field accuracy tracking
		for field, validation := range rowResult.Fields {
			fieldTotals[field]++
			if validation.IsMatch || validation.ExpectedValue == nil {
				fieldMatches[field]++
			}
		}
	}

	// Calculate overall metrics
	if len(items) > 0 {
		result.OverallConfidence = totalConfidence / float64(len(items))
		result.OverallAccuracy = float64(result.ValidRows) / float64(result.TotalRows) * 100
	}

	// Calculate field accuracies
	for field := range fieldTotals {
		if fieldTotals[field] > 0 {
			result.FieldAccuracies[field] = float64(fieldMatches[field]) / float64(fieldTotals[field]) * 100
		}
	}

	// Math validation summary
	if totalMathChecks > 0 {
		result.MathValidation = MathValidationSummary{
			TotalChecks:  totalMathChecks,
			PassedChecks: passedMathChecks,
			FailedChecks: totalMathChecks - passedMathChecks,
			PassRate:     float64(passedMathChecks) / float64(totalMathChecks) * 100,
			AllPassed:    passedMathChecks == totalMathChecks,
		}
	}

	// Generate recommendation
	s.generateRecommendation(&result)

	return result
}

// generateRecommendation generates an action recommendation based on validation results
func (s *RowValidationService) generateRecommendation(result *ComprehensiveValidationResult) {
	criticalCount := len(result.CriticalIssues)
	warningCount := len(result.Warnings)
	accuracy := result.OverallAccuracy

	if criticalCount == 0 && accuracy >= 95 {
		result.RecommendedAction = "approve"
		result.ConfidenceLevel = "high"
		result.OverallStatus = "verified"
		result.Recommendations = append(result.Recommendations,
			"All mathematical validations passed - safe to approve")
	} else if criticalCount == 0 && accuracy >= 80 {
		result.RecommendedAction = "approve"
		result.ConfidenceLevel = "medium"
		result.OverallStatus = "verified"
		result.Recommendations = append(result.Recommendations,
			"Most validations passed with minor warnings - review warnings before approving")
	} else if criticalCount <= 2 && accuracy >= 70 {
		result.RecommendedAction = "review"
		result.ConfidenceLevel = "medium"
		result.OverallStatus = "mismatches"
		result.Recommendations = append(result.Recommendations,
			fmt.Sprintf("Found %d critical issues requiring review", criticalCount))
		result.Recommendations = append(result.Recommendations,
			"Verify the highlighted rows manually before making a decision")
	} else {
		result.RecommendedAction = "reject"
		result.ConfidenceLevel = "low"
		result.OverallStatus = "errors"
		result.Recommendations = append(result.Recommendations,
			fmt.Sprintf("High number of issues detected (%d critical, %d warnings)", criticalCount, warningCount))
		result.Recommendations = append(result.Recommendations,
			"Consider re-uploading the receipt image or manual entry")
	}
}

// Helper functions

// getSeverityFromDifference determines severity based on the magnitude of difference
func getSeverityFromDifference(diff, baseValue float64) string {
	if baseValue == 0 {
		if diff == 0 {
			return ""
		}
		return "high"
	}

	percentDiff := math.Abs(diff / baseValue) * 100

	if percentDiff <= 1 {
		return "low"
	} else if percentDiff <= 5 {
		return "medium"
	} else if percentDiff <= 10 {
		return "high"
	}
	return "critical"
}

// getFieldConfidence retrieves confidence for a specific field from FieldConfidenceScores
func getFieldConfidence(fc *models.FieldConfidenceScores, fieldName string) float64 {
	if fc == nil {
		return 0
	}

	switch fieldName {
	case "Brand":
		return fc.Brand
	case "Opening":
		return fc.Opening
	case "Receipt":
		return fc.Receipt
	case "Total":
		return fc.Total
	case "Sale":
		return fc.Sale
	case "Rate":
		return fc.Rate
	case "Amount":
		return fc.Amount
	case "Closing":
		return fc.Closing
	default:
		return 0
	}
}

// ValidateBatchSession validates all items in a batch OCR session
func (s *RowValidationService) ValidateBatchSession(
	ctx context.Context,
	batchSessionID string,
	tenantID string,
	shopID string,
) (*ComprehensiveValidationResult, error) {

	// Fetch all OCR items for this batch
	var items []models.OCRItem
	if err := s.db.Where("batch_id = ?", batchSessionID).Find(&items).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch OCR items: %w", err)
	}

	if len(items) == 0 {
		return nil, fmt.Errorf("no items found for batch session: %s", batchSessionID)
	}

	fmt.Printf("📊 [Validation] Starting comprehensive validation for batch %s (%d items)\n",
		batchSessionID, len(items))

	// Perform comprehensive validation
	result := s.ValidateAllRows(ctx, items)

	// Log summary
	fmt.Printf("📊 [Validation] Complete:\n")
	fmt.Printf("   Total Rows: %d\n", result.TotalRows)
	fmt.Printf("   Valid Rows: %d (%.1f%%)\n", result.ValidRows, result.OverallAccuracy)
	fmt.Printf("   Math Checks: %d/%d passed (%.1f%%)\n",
		result.MathValidation.PassedChecks,
		result.MathValidation.TotalChecks,
		result.MathValidation.PassRate)
	fmt.Printf("   Critical Issues: %d\n", len(result.CriticalIssues))
	fmt.Printf("   Warnings: %d\n", len(result.Warnings))
	fmt.Printf("   Recommended Action: %s (%s confidence)\n",
		result.RecommendedAction, result.ConfidenceLevel)

	return &result, nil
}

// StoreValidationResult stores the validation result for audit and learning
func (s *RowValidationService) StoreValidationResult(
	ctx context.Context,
	batchSessionID string,
	result *ComprehensiveValidationResult,
) error {
	// This can be expanded to store validation results in a dedicated table
	// for analytics and learning purposes

	// For now, update the batch session with validation status
	updates := map[string]interface{}{
		"validation_status":   result.OverallStatus,
		"validation_accuracy": result.OverallAccuracy,
		"updated_at":          time.Now(),
	}

	if err := s.db.Table("batch_ocr_sessions").
		Where("id = ?", batchSessionID).
		Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to update batch session: %w", err)
	}

	return nil
}

// Helper to parse UUID strings
func parseUUID(s string) uuid.UUID {
	id, _ := uuid.Parse(s)
	return id
}
