package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ValidationResult holds the complete comparison results between entered data and OCR extraction
type ValidationResult struct {
	OverallStatus    string               `json:"overall_status"`     // verified, mismatches, error
	OverallAccuracy  float64              `json:"overall_accuracy"`   // 0-100%
	TotalItems       int                  `json:"total_items"`        // Total items in entered data
	MatchedItems     int                  `json:"matched_items"`      // Items that matched OCR
	MismatchedItems  int                  `json:"mismatched_items"`   // Items with discrepancies
	ExtraOCRItems    int                  `json:"extra_ocr_items"`    // In OCR but not in entered data
	MissingOCRItems  int                  `json:"missing_ocr_items"`  // Entered but not found in OCR
	Mismatches       []ValidationMismatch `json:"mismatches,omitempty"`
	OCRConfidence    float64              `json:"ocr_confidence"`     // Average OCR confidence
	ProcessingTimeMs int64                `json:"processing_time_ms"` // Time taken to validate
	OCRSessionID     string               `json:"ocr_session_id,omitempty"`
	ValidatedAt      time.Time            `json:"validated_at"`

	// Comprehensive accuracy metrics
	EntryMatchRate      float64 `json:"entry_match_rate"`      // % of entered items found in OCR
	OCRCoverageRate     float64 `json:"ocr_coverage_rate"`     // % of OCR items matched to entries
	QuantityAccuracy    float64 `json:"quantity_accuracy"`     // % of quantities matched exactly
	StockMathAccuracy   float64 `json:"stock_math_accuracy"`   // % of items where Opening-Sale=Closing
	PriceAccuracy       float64 `json:"price_accuracy"`        // % of prices matched within tolerance

	// Summary statistics
	TotalOCRItems           int `json:"total_ocr_items"`            // Total OCR extracted items (after dedup)
	StockMathErrors         int `json:"stock_math_errors"`          // Items with Opening-Sale≠Closing
	QuantityMismatches      int `json:"quantity_mismatches"`        // Sale quantity differences
	OpeningStockMismatches  int `json:"opening_stock_mismatches"`   // Opening stock differences
	ClosingStockMismatches  int `json:"closing_stock_mismatches"`   // Closing stock differences
	PriceMismatches         int `json:"price_mismatches"`           // Price differences

	// Detailed match summary
	MatchDetails []ItemMatchDetail `json:"match_details,omitempty"` // Detailed per-item match info

	// AI-Powered Review Suggestions (for Manager Approval Screen)
	AISummary           *AISummary         `json:"ai_summary,omitempty"`            // AI-generated summary
	PerItemInsights     []ItemInsight      `json:"per_item_insights,omitempty"`     // Per-product AI insights
	MissingItemsGrouped []MissingItemGroup `json:"missing_items_grouped,omitempty"` // Missing items grouped by severity
}

// ValidationMismatch represents a single discrepancy between entered and OCR data
type ValidationMismatch struct {
	ProductID       uuid.UUID `json:"product_id"`
	ProductName     string    `json:"product_name"`
	BrandName       string    `json:"brand_name,omitempty"`
	Size            string    `json:"size,omitempty"`
	FieldName       string    `json:"field_name"`       // quantity, unit_price, brand, opening_stock, closing_stock, stock_math
	EnteredValue    string    `json:"entered_value"`    // What salesman entered
	OCRValue        string    `json:"ocr_value"`        // What OCR extracted
	Difference      string    `json:"difference"`       // Human-readable difference
	Severity        string    `json:"severity"`         // low, medium, high, critical
	MatchConfidence float64   `json:"match_confidence"` // How confident is the product match
	SuggestedAction string    `json:"suggested_action,omitempty"`
	MismatchType    string    `json:"mismatch_type,omitempty"` // data_entry_error, stock_discrepancy, ocr_misread, missing_entry
}

// ItemMatchDetail provides comprehensive per-item validation details
type ItemMatchDetail struct {
	ProductID       uuid.UUID `json:"product_id"`
	ProductName     string    `json:"product_name"`
	BrandName       string    `json:"brand_name"`
	Size            string    `json:"size"`
	MatchStatus     string    `json:"match_status"` // matched, partial, not_found
	MatchConfidence float64   `json:"match_confidence"`

	// Entered values
	EnteredOpening  int     `json:"entered_opening"`
	EnteredSale     int     `json:"entered_sale"`
	EnteredClosing  int     `json:"entered_closing"`
	EnteredPrice    float64 `json:"entered_price"`

	// OCR extracted values
	OCROpening      int     `json:"ocr_opening"`
	OCRSale         int     `json:"ocr_sale"`
	OCRClosing      int     `json:"ocr_closing"`
	OCRPrice        float64 `json:"ocr_price"`
	OCRBrandText    string  `json:"ocr_brand_text"`

	// AI-matched product info (for display when OCR reads wrong brand)
	AIMatchedProduct string  `json:"ai_matched_product,omitempty"` // AI-identified actual product name
	AIMatchedBrand   string  `json:"ai_matched_brand,omitempty"`   // AI-identified actual brand name
	AIMatchReason    string  `json:"ai_match_reason,omitempty"`    // Reason for AI match

	// Validation results
	OpeningMatch    bool    `json:"opening_match"`
	SaleMatch       bool    `json:"sale_match"`
	ClosingMatch    bool    `json:"closing_match"`
	PriceMatch      bool    `json:"price_match"`
	StockMathValid  bool    `json:"stock_math_valid"` // Opening - Sale = Closing

	// Calculated differences
	OpeningDiff     int     `json:"opening_diff,omitempty"`
	SaleDiff        int     `json:"sale_diff,omitempty"`
	ClosingDiff     int     `json:"closing_diff,omitempty"`
	PriceDiff       float64 `json:"price_diff,omitempty"`

	// Issues found
	Issues          []string `json:"issues,omitempty"`
}

// ValidationCorrection represents a correction made by manager during confirmation
type ValidationCorrection struct {
	ProductID    uuid.UUID `json:"product_id"`
	FieldName    string    `json:"field_name"`    // quantity, unit_price
	OriginalValue string   `json:"original_value"`
	CorrectedValue string  `json:"corrected_value"`
	Reason       string    `json:"reason,omitempty"`
}

// ConfirmValidationRequest represents the request to confirm validation
type ConfirmValidationRequest struct {
	RecordID    uuid.UUID              `json:"record_id"`
	Corrections []ValidationCorrection `json:"corrections,omitempty"`
	Notes       string                 `json:"notes,omitempty"`
	IsAccurate  bool                   `json:"is_accurate"` // True if no corrections needed
}

// OCRTrainingSample stores OCR extractions paired with human-verified data for auto-learning
type OCRTrainingSample struct {
	gorm.Model
	ID                   uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID             uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null"`
	DailySalesRecordID   *uuid.UUID `json:"daily_sales_record_id" gorm:"type:uuid"`
	OCRSessionID         *uuid.UUID `json:"ocr_session_id" gorm:"type:uuid"`
	ImageURL             string     `json:"image_url" gorm:"not null"`
	ImageHash            string     `json:"image_hash" gorm:"size:64"`
	OCRExtractedItems    []byte     `json:"ocr_extracted_items" gorm:"type:jsonb"`
	VerifiedItems        []byte     `json:"verified_items" gorm:"type:jsonb"`
	OverallAccuracy      float64    `json:"overall_accuracy"`
	BrandMatchAccuracy   float64    `json:"brand_match_accuracy"`
	QuantityAccuracy     float64    `json:"quantity_accuracy"`
	PriceAccuracy        float64    `json:"price_accuracy"`
	IsVerified           bool       `json:"is_verified" gorm:"default:false"`
	IsUsedForTraining    bool       `json:"is_used_for_training" gorm:"default:false"`
	TrainingBatchID      string     `json:"training_batch_id" gorm:"size:50"`
	VerifiedAt           *time.Time `json:"verified_at"`
}

// TableName specifies the table name for OCRTrainingSample
func (OCRTrainingSample) TableName() string {
	return "ocr_training_samples"
}

// OCRAccuracyMetric tracks daily aggregated accuracy metrics
type OCRAccuracyMetric struct {
	gorm.Model
	ID                   uuid.UUID `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID             uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null"`
	MetricDate           time.Time `json:"metric_date" gorm:"type:date;not null"`
	TotalValidations     int       `json:"total_validations" gorm:"default:0"`
	AutoVerified         int       `json:"auto_verified" gorm:"default:0"`
	RequiredCorrection   int       `json:"required_correction" gorm:"default:0"`
	AvgBrandAccuracy     float64   `json:"avg_brand_accuracy"`
	AvgQuantityAccuracy  float64   `json:"avg_quantity_accuracy"`
	AvgPriceAccuracy     float64   `json:"avg_price_accuracy"`
	AvgOverallAccuracy   float64   `json:"avg_overall_accuracy"`
	TrainingSamplesAdded int       `json:"training_samples_added" gorm:"default:0"`
	ModelVersion         string    `json:"model_version" gorm:"size:50"`
}

// TableName specifies the table name for OCRAccuracyMetric
func (OCRAccuracyMetric) TableName() string {
	return "ocr_accuracy_metrics"
}

// OCRBrandAlias maps OCR misreads to correct brand names
type OCRBrandAlias struct {
	gorm.Model
	ID                 uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID           uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null"`
	CanonicalBrandName string     `json:"canonical_brand_name" gorm:"size:255;not null"`
	ProductID          *uuid.UUID `json:"product_id" gorm:"type:uuid"`
	AliasName          string     `json:"alias_name" gorm:"size:255;not null"`
	OccurrenceCount    int        `json:"occurrence_count" gorm:"default:1"`
	ConfidenceScore    float64    `json:"confidence_score" gorm:"default:100.00"`
	Source             string     `json:"source" gorm:"size:50;default:'manual'"` // manual, ocr_learning, user_correction
	LastUsedAt         *time.Time `json:"last_used_at"`
}

// TableName specifies the table name for OCRBrandAlias
func (OCRBrandAlias) TableName() string {
	return "ocr_brand_aliases"
}

// AccuracyDashboard provides metrics for the accuracy tracking dashboard
type AccuracyDashboard struct {
	TotalValidations      int              `json:"total_validations"`
	AutoVerifiedCount     int              `json:"auto_verified_count"`
	AutoVerifiedRate      float64          `json:"auto_verified_rate"`      // Percentage of auto-verified (target: 100%)
	AvgOverallAccuracy    float64          `json:"avg_overall_accuracy"`
	AccuracyTrend         []AccuracyPoint  `json:"accuracy_trend"`          // Last 30 days
	TopMismatches         []MismatchPattern `json:"top_mismatches"`
	TrainingSamplesCount  int              `json:"training_samples_count"`
	ImprovementSinceStart float64          `json:"improvement_since_start"` // Percentage improvement
}

// AccuracyPoint represents a single data point in accuracy trend
type AccuracyPoint struct {
	Date     string  `json:"date"`     // YYYY-MM-DD format
	Accuracy float64 `json:"accuracy"` // 0-100%
	Count    int     `json:"count"`    // Number of validations
}

// MismatchPattern represents a frequently occurring mismatch pattern
type MismatchPattern struct {
	FieldName    string `json:"field_name"`    // quantity, price, brand
	OCRPattern   string `json:"ocr_pattern"`   // What OCR frequently gets wrong
	CorrectValue string `json:"correct_value"` // What it should be
	Count        int    `json:"count"`         // How often this occurs
}

// ItemComparisonResult represents the result of comparing a single item
type ItemComparisonResult struct {
	Matched         bool      `json:"matched"`
	EnteredProductID uuid.UUID `json:"entered_product_id"`
	EnteredProductName string  `json:"entered_product_name"`
	EnteredQuantity int       `json:"entered_quantity"`
	EnteredPrice    float64   `json:"entered_price"`
	OCRBrandText    string    `json:"ocr_brand_text,omitempty"`
	OCRQuantity     int       `json:"ocr_quantity,omitempty"`
	OCRPrice        float64   `json:"ocr_price,omitempty"`
	MatchConfidence float64   `json:"match_confidence"`
	Mismatches      []ValidationMismatch `json:"mismatches,omitempty"`
}

// TriggerValidationRequest represents a request to trigger validation
type TriggerValidationRequest struct {
	RecordID uuid.UUID `json:"record_id"`
	Force    bool      `json:"force"` // Re-run even if already validated
}

// TriggerValidationResponse represents the response from triggering validation
type TriggerValidationResponse struct {
	RecordID         uuid.UUID `json:"record_id"`
	Status           string    `json:"status"` // triggered, already_processing, error
	Message          string    `json:"message"`
	OCRSessionID     string    `json:"ocr_session_id,omitempty"`
}

// ============================================================================
// AI-Powered Review Suggestions (for Manager Approval Screen)
// ============================================================================

// AISummary provides an AI-generated summary for the review screen
type AISummary struct {
	OverallAccuracy   float64 `json:"overall_accuracy"`    // 0-100%
	CriticalCount     int     `json:"critical_count"`      // Count of critical issues
	WarningCount      int     `json:"warning_count"`       // Count of warnings (high + medium)
	MatchedCount      int     `json:"matched_count"`       // Items found in OCR
	MissingCount      int     `json:"missing_count"`       // Items in OCR but not entered (deprecated, use MissingEntryCount)
	Recommendation    string  `json:"recommendation"`      // AI recommendation text
	ConfidenceLevel   string  `json:"confidence_level"`    // high, medium, low
	RecommendedAction string  `json:"recommended_action"`  // approve, review, reject

	// Issue type breakdown for accurate frontend messages
	MissingEntryCount    int `json:"missing_entry_count"`    // Items in receipt but NOT entered by salesman
	QuantityMismatchCount int `json:"quantity_mismatch_count"` // Items with quantity differences
	PriceMismatchCount   int `json:"price_mismatch_count"`   // Items with price differences
	StockMismatchCount   int `json:"stock_mismatch_count"`   // Items with opening/closing stock differences
	NotInReceiptCount    int `json:"not_in_receipt_count"`   // Items entered but NOT found in receipt
}

// ItemInsight provides AI insights for a single product/item
type ItemInsight struct {
	ProductID       string   `json:"product_id"`
	ProductName     string   `json:"product_name"`
	BrandName       string   `json:"brand_name"`
	Size            string   `json:"size"`
	Status          string   `json:"status"`           // matched, warning, critical
	IssueCount      int      `json:"issue_count"`
	Issues          []Issue  `json:"issues"`
	MatchConfidence float64  `json:"match_confidence"` // 0-100%

	// Field comparison for quick view
	EnteredQty  int     `json:"entered_qty"`
	OCRQty      int     `json:"ocr_qty"`
	EnteredRate float64 `json:"entered_rate"`
	OCRRate     float64 `json:"ocr_rate"`
}

// Issue represents a single issue/suggestion for an item
type Issue struct {
	Type        string `json:"type"`          // quantity, price, stock, math, missing
	Severity    string `json:"severity"`      // critical, warning, info
	Field       string `json:"field"`         // opening_stock, quantity, closing_stock, rate, amount
	EnteredVal  string `json:"entered_value"`
	OCRVal      string `json:"ocr_value"`
	Difference  string `json:"difference"`    // Human-readable difference
	Message     string `json:"message"`       // Short description of issue
	Suggestion  string `json:"suggestion"`    // AI suggestion for fixing
	AutoFixable bool   `json:"auto_fixable"`  // Can be auto-corrected
}

// MissingItemGroup groups missing items by severity
type MissingItemGroup struct {
	Severity string        `json:"severity"` // critical, warning
	Count    int           `json:"count"`
	Items    []MissingItem `json:"items"`
}

// MissingItem represents an item found in OCR but not entered by salesman
type MissingItem struct {
	BrandText  string  `json:"brand_text"`
	Size       string  `json:"size"`
	SaleQty    int     `json:"sale_qty"`
	OpeningQty int     `json:"opening_qty"`
	ClosingQty int     `json:"closing_qty"`
	Amount     float64 `json:"amount,omitempty"`
	Severity   string  `json:"severity"` // critical if high quantity, warning otherwise
}
