package models

import (
	"time"
)

// BatchOCRSession represents a batch OCR processing session
type BatchOCRSession struct {
	ID                   string     `json:"id" db:"id"`
	SessionID            string     `json:"session_id" gorm:"-" db:"-"` // Alias for ID for Flutter compatibility
	TenantID             string     `json:"tenant_id" db:"tenant_id"`
	UserID               string     `json:"user_id" db:"user_id"`
	ShopID               string     `json:"shop_id" db:"shop_id"`
	SessionType          string     `json:"session_type" db:"session_type"`        // stock_initialization, invoice_import
	Status               string     `json:"status" db:"status"`                    // pending, processing, completed, partial, failed
	CurrentStage         string     `json:"current_stage" db:"current_stage"`      // pending, vision_api, gemini_extraction, item_matching, completed, failed
	ProgressPercentage   int        `json:"progress_percentage" db:"progress_percentage"` // 0-100
	TotalImages          int        `json:"total_images" db:"total_images"`
	CompletedImages      int        `json:"completed_images" db:"completed_images"`
	FailedImages         int        `json:"failed_images" db:"failed_images"`
	TotalItemsExtracted  int        `json:"total_items_extracted" db:"total_items_extracted"`
	SessionIDs           []string   `json:"session_ids,omitempty" gorm:"-" db:"-"` // Individual OCR session IDs (not stored in DB)
	Items                []OCRItem  `json:"items,omitempty" gorm:"-" db:"-"` // Extracted items (not stored in DB, populated on read)
	QualityMetrics       map[string]interface{} `json:"quality_metrics,omitempty" gorm:"-" db:"-"` // Quality metrics (not stored in DB)
	CreatedAt            time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at" db:"updated_at"`
	CompletedAt          *time.Time `json:"completed_at,omitempty" db:"completed_at"`
}

// OCRSession represents a single image OCR processing session
type OCRSession struct {
	ID                  string     `json:"id" gorm:"column:id;primaryKey"`
	BatchSessionID      string     `json:"batch_session_id" gorm:"column:batch_session_id"`
	TenantID            string     `json:"tenant_id" gorm:"column:tenant_id"`
	UserID              string     `json:"user_id" gorm:"column:user_id"`
	ShopID              string     `json:"shop_id,omitempty" gorm:"column:shop_id"`
	ImageURL            string     `json:"image_url" gorm:"column:image_url"`
	ImageSize           int        `json:"image_size" gorm:"column:image_size"`
	ImageType           string     `json:"image_type" gorm:"column:image_type"`
	Status              string     `json:"status" gorm:"column:status"` // pending, processing, completed, failed
	OCRProvider         string     `json:"ocr_provider,omitempty" gorm:"column:ocr_provider"`
	RawText             string     `json:"raw_text,omitempty" gorm:"column:raw_text"`
	ProcessedAt         *time.Time `json:"processed_at,omitempty" gorm:"column:processed_at"`
	ErrorMessage        string     `json:"error_message,omitempty" gorm:"column:error_message"`
	ConfidenceScore     *float64   `json:"confidence_score,omitempty" gorm:"column:confidence_score"`
	ProcessingTimeMS    *int       `json:"processing_time_ms,omitempty" gorm:"column:processing_time_ms"`
	ReceiptDate         *time.Time `json:"receipt_date,omitempty" gorm:"column:receipt_date"`
	ReceiptNumber       string     `json:"receipt_number,omitempty" gorm:"column:receipt_number"`
	VendorName          string     `json:"vendor_name,omitempty" gorm:"column:vendor_name"`
	TotalAmount         *float64   `json:"total_amount,omitempty" gorm:"column:total_amount"`
	SessionType         string     `json:"session_type,omitempty" gorm:"column:session_type"`
	ExpiresAt           *time.Time `json:"expires_at,omitempty" gorm:"column:expires_at"`
	CreatedAt           time.Time  `json:"created_at" gorm:"column:created_at"`
	UpdatedAt           time.Time  `json:"updated_at" gorm:"column:updated_at"`
	ExtractedData       string     `json:"extracted_data,omitempty" gorm:"column:extracted_data;type:jsonb;default:null"`
	CurrentStage        string     `json:"current_stage,omitempty" gorm:"column:current_stage"`
	ProgressPercentage  int        `json:"progress_percentage" gorm:"column:progress_percentage"`
	ExtractedItems      []OCRItem  `json:"extracted_items,omitempty" gorm:"-"` // Not stored in DB, loaded separately
}

// OCRItem represents an extracted item from invoice OCR
// Phase 1: Enhanced with ALL 7 columns for comprehensive validation
type OCRItem struct {
	ID                      string   `json:"id,omitempty" db:"id"`
	SessionID               string   `json:"session_id,omitempty" db:"session_id"`
	BatchID                 string   `json:"batch_id,omitempty" db:"batch_id"`
	RowNumber               int      `json:"row_number" db:"row_number"` // Serial number from invoice
	BrandText               string   `json:"brand_text" db:"brand_text"`
	SizeText                string   `json:"size_text" db:"size_text"`

	// ===== COMPLETE ROW DATA (7 Columns) =====
	// Column 1: Opening Stock - Stock at start of day
	OpeningStock            int      `json:"opening_stock" db:"opening_stock"`
	// Column 2: Receipt - New stock received during the day
	ReceiptQty              int      `json:"receipt_qty" db:"receipt_qty"`
	// Column 3: Total Stock = Opening + Receipt
	TotalStock              int      `json:"total_stock" db:"total_stock"`
	// Column 4: Sale Quantity - Number of bottles sold
	SaleQuantity            int      `json:"sale_quantity" db:"sale_quantity"`
	// Column 5: Rate/Selling Price per bottle (₹)
	Rate                    float64  `json:"rate" db:"rate"`
	SellingPrice            *float64 `json:"selling_price,omitempty" db:"selling_price"` // Legacy field, same as Rate
	// Column 6: Amount = Sale × Rate
	Amount                  float64  `json:"amount" db:"amount"`
	// Column 7: Closing Stock = Total - Sale
	ClosingStock            int      `json:"closing_stock" db:"closing_stock"`
	Quantity                int      `json:"quantity" db:"quantity"` // Legacy alias for ClosingStock

	// ===== MATHEMATICAL VALIDATION FLAGS =====
	// Phase 2: Validate mathematical relationships
	IsTotalValid            bool     `json:"is_total_valid" db:"is_total_valid"`     // Total == Opening + Receipt
	IsClosingValid          bool     `json:"is_closing_valid" db:"is_closing_valid"` // Closing == Total - Sale
	IsAmountValid           bool     `json:"is_amount_valid" db:"is_amount_valid"`   // Amount == Sale × Rate
	MathValidationNotes     string   `json:"math_validation_notes,omitempty" db:"math_validation_notes"`

	// ===== VERIFICATION & MATCHING =====
	VerificationStatus      string   `json:"verification_status" db:"verification_status"` // pending, verified, mismatch
	VerificationNotes       string   `json:"verification_notes,omitempty" db:"verification_notes"`
	MatchedBrandID          *string  `json:"matched_brand_id,omitempty" db:"matched_brand_id"`
	MatchedVariantID        *string  `json:"matched_variant_id,omitempty" db:"matched_variant_id"`
	MatchConfidence         *float64 `json:"match_confidence,omitempty" db:"match_confidence"`
	MatchStrategy           string   `json:"match_strategy,omitempty" db:"match_strategy"` // gemini_smart, exact, fuzzy, manual
	UserSelectedBrandID     *string  `json:"user_selected_brand_id,omitempty" db:"user_selected_brand_id"`
	IsReviewed              bool     `json:"is_reviewed" db:"is_reviewed"`
	IsSelected              bool     `json:"is_selected" db:"is_selected"`
	NormalizedBrandName     string   `json:"normalized_brand_name,omitempty" db:"normalized_brand_name"` // Gemini-cleaned brand name

	// ===== CATEGORY INFERENCE =====
	InferredCategoryID      *string  `json:"inferred_category_id,omitempty" db:"inferred_category_id"`
	InferredSubcategoryID   *string  `json:"inferred_subcategory_id,omitempty" db:"inferred_subcategory_id"`
	InferredCategoryName    string   `json:"inferred_category_name,omitempty" db:"inferred_category_name"`
	InferredSubcategoryName string   `json:"inferred_subcategory_name,omitempty" db:"inferred_subcategory_name"`
	CategoryConfidence      *float64 `json:"category_confidence,omitempty" db:"category_confidence"`

	// ===== FIELD-LEVEL CONFIDENCE (Phase 4) =====
	FieldConfidences        *FieldConfidenceScores `json:"field_confidences,omitempty" gorm:"-" db:"-"` // Not stored in DB

	// ===== TIMESTAMPS =====
	CreatedAt               time.Time `json:"created_at" db:"created_at"`
	UpdatedAt               time.Time `json:"updated_at" db:"updated_at"`
}

// FieldConfidenceScores holds confidence scores for each extracted field
// Used for field-level accuracy tracking and learning
type FieldConfidenceScores struct {
	Brand    float64 `json:"brand"`
	Opening  float64 `json:"opening"`
	Receipt  float64 `json:"receipt"`
	Total    float64 `json:"total"`
	Sale     float64 `json:"sale"`
	Rate     float64 `json:"rate"`
	Amount   float64 `json:"amount"`
	Closing  float64 `json:"closing"`
	Overall  float64 `json:"overall"`
}

// RejectedOCRItem represents an item that was filtered out during OCR processing
type RejectedOCRItem struct {
	BrandText        string   `json:"brand_text"`
	SizeText         string   `json:"size_text,omitempty"`
	Quantity         int      `json:"quantity,omitempty"`
	SellingPrice     *float64 `json:"selling_price,omitempty"`
	RejectionReason  string   `json:"rejection_reason"`  // Specific reason why item was rejected
	RejectionStage   string   `json:"rejection_stage"`   // Where it was rejected: validation, price_check, word_limit, etc.
	OriginalRowNumber int     `json:"original_row_number,omitempty"`
	Confidence       float64  `json:"confidence,omitempty"` // Confidence score before rejection
	CanRecover       bool     `json:"can_recover"`       // Whether this item can be manually recovered
}

// DeduplicationResponse represents the response from deduplication
type DeduplicationResponse struct {
	ReceiptType       string            `json:"receipt_type"`
	UniqueItems       []OCRItem         `json:"items"`
	TotalItems        int               `json:"total_items"`
	DuplicatesRemoved int               `json:"duplicates_removed"`
	RawTexts          map[string]string `json:"raw_texts,omitempty"`     // session_id -> raw_text mapping
	RejectedItems     []RejectedOCRItem `json:"rejected_items,omitempty"` // Items that were filtered out with reasons
	TotalRejected     int               `json:"total_rejected"`
}

// BrandMatchSuggestion represents a brand match suggestion from Gemini
type BrandMatchSuggestion struct {
	BrandID        string  `json:"brand_id"`
	BrandName      string  `json:"brand_name"`
	VariantID      string  `json:"variant_id,omitempty"`
	VariantName    string  `json:"variant_name,omitempty"`
	Confidence     float64 `json:"confidence"`     // 0-100
	MatchStrategy  string  `json:"match_strategy"` // gemini_smart, exact, fuzzy
	Reasoning      string  `json:"reasoning,omitempty"`
}

// ImportResult represents the result of importing OCR items as products
type ImportResult struct {
	ProductsCreated int               `json:"products_created"`
	ProductsUpdated int               `json:"products_updated"`
	BrandsCreated   int               `json:"brands_created"`
	Errors          []ImportError     `json:"errors,omitempty"`
}

// ImportError represents an error during import
type ImportError struct {
	ItemRowNumber int    `json:"item_row_number"`
	BrandText     string `json:"brand_text"`
	Error         string `json:"error"`
}

// ========== COMPREHENSIVE OCR VALIDATION & SUGGESTION MODELS ==========

// OCRValidationSuggestion represents a suggestion for correcting OCR data
type OCRValidationSuggestion struct {
	ID              string  `json:"id"`
	ItemID          string  `json:"item_id,omitempty"`
	Type            string  `json:"type"`            // missing_size, missing_rate, math_error, unusual_rate, zero_sales, duplicate_item, image_quality, brand_mismatch
	Severity        string  `json:"severity"`        // critical, warning, info
	Field           string  `json:"field,omitempty"` // size_text, rate, amount, brand_text
	CurrentValue    string  `json:"current_value,omitempty"`
	SuggestedValue  string  `json:"suggested_value,omitempty"`
	Confidence      float64 `json:"confidence"`      // 0-100
	Reasoning       string  `json:"reasoning"`
	AutoFixable     bool    `json:"auto_fixable"`
	RequiresReview  bool    `json:"requires_review"`
}

// OCRSizeSummary represents totals for a specific size category
type OCRSizeSummary struct {
	SizeCategory    string  `json:"size_category"`   // HALF, QUART, FULL, PEG, BOTTLE
	SizeML          string  `json:"size_ml"`         // 180ml, 375ml, 750ml, 90ml, etc.
	TotalItems      int     `json:"total_items"`
	TotalQuantity   int     `json:"total_quantity"`  // Total sale quantity
	TotalAmount     float64 `json:"total_amount"`
	ExpectedAmount  float64 `json:"expected_amount,omitempty"` // From receipt footer
	AmountMatches   bool    `json:"amount_matches"`
	Discrepancy     float64 `json:"discrepancy,omitempty"`
}

// OCRBrandSummary represents totals for a specific brand
type OCRBrandSummary struct {
	BrandText       string  `json:"brand_text"`
	TotalItems      int     `json:"total_items"`      // Across all sizes
	TotalQuantity   int     `json:"total_quantity"`
	TotalAmount     float64 `json:"total_amount"`
	Sizes           []string `json:"sizes"`           // All sizes found for this brand
	ExpectedAmount  float64 `json:"expected_amount,omitempty"`
	AmountMatches   bool    `json:"amount_matches"`
}

// OCRImageAnalysis represents analysis of an individual image
type OCRImageAnalysis struct {
	SessionID       string  `json:"session_id"`
	ImageIndex      int     `json:"image_index"`
	ReceiptType     string  `json:"receipt_type"`    // HALF, QUART, FULL, PEG, BOTTLE
	ItemsExtracted  int     `json:"items_extracted"`
	TotalAmount     float64 `json:"total_amount"`
	ImageQuality    string  `json:"image_quality"`   // good, fair, poor, unreadable
	QualityScore    float64 `json:"quality_score"`   // 0-100
	IsDuplicate     bool    `json:"is_duplicate"`
	DuplicateOf     string  `json:"duplicate_of,omitempty"`
	Issues          []string `json:"issues,omitempty"`
}

// OCRValidationResult represents comprehensive validation of OCR extraction
type OCRValidationResult struct {
	BatchID           string                    `json:"batch_id"`
	ValidationTime    string                    `json:"validation_time"`
	OverallStatus     string                    `json:"overall_status"`    // valid, has_warnings, has_errors
	OverallConfidence float64                   `json:"overall_confidence"`

	// Summary Statistics
	TotalImages       int                       `json:"total_images"`
	ImagesProcessed   int                       `json:"images_processed"`
	ImagesFailed      int                       `json:"images_failed"`
	DuplicateImages   int                       `json:"duplicate_images"`

	TotalItems        int                       `json:"total_items"`
	TotalAmount       float64                   `json:"total_amount"`
	ExpectedAmount    float64                   `json:"expected_amount,omitempty"`
	AmountDiscrepancy float64                   `json:"amount_discrepancy,omitempty"`

	// Detailed Analysis
	ImageAnalysis     []OCRImageAnalysis        `json:"image_analysis"`
	SizeSummaries     []OCRSizeSummary          `json:"size_summaries"`
	BrandSummaries    []OCRBrandSummary         `json:"brand_summaries"`

	// Suggestions for Correction
	Suggestions       []OCRValidationSuggestion `json:"suggestions"`
	CriticalIssues    int                       `json:"critical_issues"`
	Warnings          int                       `json:"warnings"`
	InfoItems         int                       `json:"info_items"`

	// Edge Cases Detected
	EdgeCases         []OCREdgeCase             `json:"edge_cases"`
}

// OCREdgeCase represents a detected edge case that needs attention
type OCREdgeCase struct {
	Type        string `json:"type"`
	Description string `json:"description"`
	AffectedItems []string `json:"affected_items,omitempty"`
	Resolution  string `json:"resolution,omitempty"`
}
