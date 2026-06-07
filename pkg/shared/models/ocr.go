package models

import (
	"database/sql/driver"
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// OCRSessionStatus represents the status of an OCR session
type OCRSessionStatus string

const (
	OCRStatusPending    OCRSessionStatus = "pending"
	OCRStatusProcessing OCRSessionStatus = "processing"
	OCRStatusCompleted  OCRSessionStatus = "completed"
	OCRStatusFailed     OCRSessionStatus = "failed"
	OCRStatusExpired    OCRSessionStatus = "expired"
)

// OCRProvider represents the OCR service provider
type OCRProvider string

const (
	OCRProviderGoogleVision OCRProvider = "google_vision"
	OCRProviderTesseract    OCRProvider = "tesseract"
)

// OCRSessionType represents the type of OCR session
type OCRSessionType string

const (
	OCRSessionTypeQuickSale          OCRSessionType = "quick_sale"
	OCRSessionTypeInventoryCheck     OCRSessionType = "inventory_check"
	OCRSessionTypeStockInitialization OCRSessionType = "stock_initialization" // NEW: For initial stock setup from invoices
	OCRSessionTypeInvoiceImport      OCRSessionType = "invoice_import"        // NEW: General invoice import
)

// OCRSession represents an OCR processing session
type OCRSession struct {
	ID       uuid.UUID `json:"id" db:"id"`
	TenantID uuid.UUID `json:"tenant_id" db:"tenant_id"`
	UserID   uuid.UUID `json:"user_id" db:"user_id"`
	ShopID   uuid.UUID `json:"shop_id" db:"shop_id"`

	// Image information
	ImageURL  string `json:"image_url" db:"image_url"`
	ImageSize int    `json:"image_size" db:"image_size"` // in bytes
	ImageType string `json:"image_type" db:"image_type"` // jpeg, png, etc

	// OCR processing status
	Status      OCRSessionStatus `json:"status" db:"status"`
	OCRProvider OCRProvider      `json:"ocr_provider" db:"ocr_provider"`

	// Extracted text and metadata
	RawText      *string    `json:"raw_text" db:"raw_text"`
	ProcessedAt  *time.Time `json:"processed_at" db:"processed_at"`
	ErrorMessage *string    `json:"error_message" db:"error_message"`

	// Processing metrics
	ConfidenceScore  *float64 `json:"confidence_score" db:"confidence_score"`     // 0-100
	ProcessingTimeMs *int     `json:"processing_time_ms" db:"processing_time_ms"` // milliseconds

	// Progress tracking fields (v1.0.27)
	CurrentStage       string `json:"current_stage" db:"current_stage"`
	ProgressPercentage int    `json:"progress_percentage" db:"progress_percentage"`

	// Receipt metadata (if extractable)
	ReceiptDate   *time.Time `json:"receipt_date" db:"receipt_date"`
	ReceiptNumber *string    `json:"receipt_number" db:"receipt_number"`
	VendorName    *string    `json:"vendor_name" db:"vendor_name"`
	TotalAmount   *float64   `json:"total_amount" db:"total_amount"`

	// Session metadata
	SessionType OCRSessionType `json:"session_type" db:"session_type"`
	ExpiresAt   time.Time      `json:"expires_at" db:"expires_at"`

	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`

	// Related data (not from DB, populated in service)
	ExtractedItems []OCRExtractedItem `json:"extracted_items,omitempty" gorm:"-"`
}

// MatchMethod represents how an item was matched
type MatchMethod string

const (
	MatchMethodExact  MatchMethod = "exact"
	MatchMethodFuzzy  MatchMethod = "fuzzy"
	MatchMethodAlias  MatchMethod = "alias"
	MatchMethodPattern MatchMethod = "pattern"
	MatchMethodManual MatchMethod = "manual"
)

// BoundingBox represents OCR bounding box coordinates
type BoundingBox struct {
	X      int `json:"x"`
	Y      int `json:"y"`
	Width  int `json:"width"`
	Height int `json:"height"`
}

// Value implements driver.Valuer for BoundingBox
func (b BoundingBox) Value() (driver.Value, error) {
	return json.Marshal(b)
}

// Scan implements sql.Scanner for BoundingBox
func (b *BoundingBox) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return nil
	}
	return json.Unmarshal(bytes, b)
}

// MatchDetails contains additional matching metadata
type MatchDetails struct {
	Algorithm       string                 `json:"algorithm,omitempty"`
	Score           float64                `json:"score,omitempty"`
	MatchedFields   []string               `json:"matched_fields,omitempty"`
	SimilarProducts []string               `json:"similar_products,omitempty"`
	Metadata        map[string]interface{} `json:"metadata,omitempty"` // For storing SaaS brand info, variant details, etc.
}

// Value implements driver.Valuer for MatchDetails
func (m MatchDetails) Value() (driver.Value, error) {
	return json.Marshal(m)
}

// Scan implements sql.Scanner for MatchDetails
func (m *MatchDetails) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return nil
	}
	return json.Unmarshal(bytes, m)
}

// OCRExtractedItem represents an item extracted from OCR text
type OCRExtractedItem struct {
	ID        uuid.UUID `json:"id" db:"id"`
	SessionID uuid.UUID `json:"session_id" db:"session_id"`

	// Extracted product information
	ExtractedText string  `json:"extracted_text" db:"extracted_text"`
	BrandText     *string `json:"brand_text" db:"brand_text"`
	SizeText      *string `json:"size_text" db:"size_text"`
	QuantityText  *string `json:"quantity_text" db:"quantity_text"`
	PriceText     *string `json:"price_text" db:"price_text"`

	// Parsed values
	ParsedQuantity *int     `json:"parsed_quantity" db:"parsed_quantity"`
	ParsedPrice    *float64 `json:"parsed_price" db:"parsed_price"`
	ParsedSize     *string  `json:"parsed_size" db:"parsed_size"`

	// Stock tracking fields
	RatePerUnit  *float64 `json:"rate_per_unit" db:"rate_per_unit"`
	OpeningStock *int     `json:"opening_stock" db:"opening_stock"`
	ClosingStock *int     `json:"closing_stock" db:"closing_stock"`
	RowNumber    *int     `json:"row_number" db:"row_number"`

	// Category detection fields (Gemini AI detected)
	DetectedCategory    *string    `json:"detected_category" db:"detected_category"`       // e.g., "whiskey", "rum", "vodka"
	DetectedSubcategory *string    `json:"detected_subcategory" db:"detected_subcategory"` // e.g., "premium", "normal"
	CategoryID          *uuid.UUID `json:"category_id" db:"category_id"`                   // Mapped SaaS category ID
	SubcategoryID       *uuid.UUID `json:"subcategory_id" db:"subcategory_id"`             // Mapped SaaS subcategory ID

	// Matching results
	MatchedProductID *uuid.UUID `json:"matched_product_id" db:"matched_product_id"`
	MatchedBrandID   *uuid.UUID `json:"matched_brand_id" db:"matched_brand_id"`
	MatchedVariantID *uuid.UUID `json:"matched_variant_id" db:"matched_variant_id"`

	// Matching confidence and method
	MatchConfidence float64      `json:"match_confidence" db:"match_confidence"` // 0-100
	MatchMethod     *MatchMethod `json:"match_method" db:"match_method"`
	MatchDetails    *MatchDetails `json:"match_details" db:"match_details"`

	// User corrections
	IsConfirmed            bool       `json:"is_confirmed" db:"is_confirmed"`
	IsRejected             bool       `json:"is_rejected" db:"is_rejected"`
	UserCorrectedProductID *uuid.UUID `json:"user_corrected_product_id" db:"user_corrected_product_id"`
	UserCorrectedQuantity  *int       `json:"user_corrected_quantity" db:"user_corrected_quantity"`
	CorrectionReason       *string    `json:"correction_reason" db:"correction_reason"`

	// Item position in receipt
	LineNumber  *int         `json:"line_number" db:"line_number"`
	BoundingBox *BoundingBox `json:"bounding_box" db:"bounding_box"`

	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`

	// Related data (populated in service)
	MatchedProduct *Product          `json:"matched_product,omitempty" db:"-"`
	MatchedBrand   *SaaSBrand        `json:"matched_brand,omitempty" db:"-"`
	MatchedVariant *SaaSBrandVariant `json:"matched_variant,omitempty" db:"-"`
}

// AliasType represents the type of brand alias
type AliasType string

const (
	AliasTypeAbbreviation AliasType = "abbreviation"
	AliasTypeTypo         AliasType = "typo"
	AliasTypeColloquial   AliasType = "colloquial"
	AliasTypeOCRCommon    AliasType = "ocr_common"
)

// BrandAlias represents an alternative name for a brand
type BrandAlias struct {
	ID       uuid.UUID `json:"id" db:"id"`
	TenantID uuid.UUID `json:"tenant_id" db:"tenant_id"`
	BrandID  uuid.UUID `json:"brand_id" db:"brand_id"`

	AliasText string    `json:"alias_text" db:"alias_text"`
	AliasType AliasType `json:"alias_type" db:"alias_type"`

	// Usage tracking
	MatchCount    int        `json:"match_count" db:"match_count"`
	LastMatchedAt *time.Time `json:"last_matched_at" db:"last_matched_at"`

	// Management
	IsActive   bool       `json:"is_active" db:"is_active"`
	CreatedBy  *uuid.UUID `json:"created_by" db:"created_by"`
	ApprovedBy *uuid.UUID `json:"approved_by" db:"approved_by"`

	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`

	// Related data
	Brand *SaaSBrand `json:"brand,omitempty" db:"-"`
}

// PatternType represents the type of size pattern
type PatternType string

const (
	PatternTypeStandard      PatternType = "standard"
	PatternTypeRegional      PatternType = "regional"
	PatternTypeBrandSpecific PatternType = "brand_specific"
)

// SizePattern represents a pattern for extracting and normalizing sizes
type SizePattern struct {
	ID            uuid.UUID  `json:"id" db:"id"`
	CategoryID    *uuid.UUID `json:"category_id" db:"category_id"`
	SubcategoryID *uuid.UUID `json:"subcategory_id" db:"subcategory_id"`

	// Pattern information
	PatternRegex   string      `json:"pattern_regex" db:"pattern_regex"`
	NormalizedSize string      `json:"normalized_size" db:"normalized_size"`
	SizeML         *int        `json:"size_ml" db:"size_ml"` // Size in ML for liquor
	PatternType    PatternType `json:"pattern_type" db:"pattern_type"`
	Priority       int         `json:"priority" db:"priority"`

	// Usage tracking
	MatchCount    int        `json:"match_count" db:"match_count"`
	LastMatchedAt *time.Time `json:"last_matched_at" db:"last_matched_at"`

	IsActive  bool      `json:"is_active" db:"is_active"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}

// FeedbackType represents the type of OCR feedback
type FeedbackType string

const (
	FeedbackTypeCorrectMatch   FeedbackType = "correct_match"
	FeedbackTypeWrongMatch     FeedbackType = "wrong_match"
	FeedbackTypeMissingProduct FeedbackType = "missing_product"
	FeedbackTypeWrongQuantity  FeedbackType = "wrong_quantity"
)

// OCRLearningFeedback represents user feedback for improving OCR matching
type OCRLearningFeedback struct {
	ID               uuid.UUID    `json:"id" db:"id"`
	TenantID         uuid.UUID    `json:"tenant_id" db:"tenant_id"`
	ExtractedItemID  uuid.UUID    `json:"extracted_item_id" db:"extracted_item_id"`
	FeedbackType     FeedbackType `json:"feedback_type" db:"feedback_type"`
	CorrectProductID *uuid.UUID   `json:"correct_product_id" db:"correct_product_id"`
	CorrectQuantity  *int         `json:"correct_quantity" db:"correct_quantity"`
	OriginalConfidence *float64   `json:"original_confidence" db:"original_confidence"`
	UserID           uuid.UUID    `json:"user_id" db:"user_id"`
	CreatedAt        time.Time    `json:"created_at" db:"created_at"`
}

// OCRBrandAlias maps OCR misreads and shorthand to correct product names for instant matching.
//
// v1.0.160 — added ShopID for shop-scoped learning. NULL = tenant-wide alias
// (legacy behaviour), non-NULL = the specific shop that taught this alias.
// Uniqueness is enforced by two partial unique indexes created in migration
// 20260504_add_shop_scope_to_aliases.sql:
//   UNIQUE (tenant_id, alias_name)            WHERE shop_id IS NULL
//   UNIQUE (tenant_id, shop_id, alias_name)   WHERE shop_id IS NOT NULL
// The legacy uniqueIndex tag is intentionally dropped because GORM AutoMigrate
// cannot express partial unique indexes; the migration is the source of
// truth. Plain non-unique indexes here are fine — they speed lookups but
// don't conflict with the partial uniques.
type OCRBrandAlias struct {
	ID                 uuid.UUID  `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	TenantID           uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index:idx_ocr_brand_aliases_tenant_alias,priority:1"`
	ShopID             *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid;index:idx_ocr_brand_aliases_tenant_shop,priority:2"`
	CanonicalBrandName string     `json:"canonical_brand_name" gorm:"type:varchar(255);not null"`
	ProductID          *uuid.UUID `json:"product_id" gorm:"type:uuid"`
	AliasName          string     `json:"alias_name" gorm:"type:varchar(255);not null;index:idx_ocr_brand_aliases_tenant_alias,priority:2;index:idx_ocr_brand_aliases_tenant_shop,priority:3"`
	OccurrenceCount    int        `json:"occurrence_count" gorm:"default:1"`
	ConfidenceScore    float64    `json:"confidence_score" gorm:"type:decimal(5,2);default:100.00"`
	Source             string     `json:"source" gorm:"type:varchar(50);default:'manual'"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	LastUsedAt         *time.Time `json:"last_used_at"`
}

func (OCRBrandAlias) TableName() string {
	return "ocr_brand_aliases"
}

// OCRNegativeAlias records rejected matches — "SMITH Rum" should NOT match "Old Monk".
//
// v1.0.160 — added ShopID for shop-scoped negative learning. NULL = tenant-wide
// rejection (legacy), non-NULL = the shop that taught it. Migration
// 20260504_add_shop_scope_to_aliases.sql replaces the legacy single-key
// uniqueness with two partial unique indexes:
//   UNIQUE (tenant_id, alias_name, rejected_product_id)            WHERE shop_id IS NULL
//   UNIQUE (tenant_id, shop_id, alias_name, rejected_product_id)   WHERE shop_id IS NOT NULL
type OCRNegativeAlias struct {
	ID                uuid.UUID  `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	TenantID          uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index:idx_ocr_negative_aliases_tenant"`
	ShopID            *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid;index:idx_ocr_negative_aliases_tenant_shop"`
	AliasName         string     `json:"alias_name" gorm:"type:varchar(255);not null"`
	RejectedProductID uuid.UUID  `json:"rejected_product_id" gorm:"type:uuid;not null"`
	OccurrenceCount   int        `json:"occurrence_count" gorm:"default:1"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

func (OCRNegativeAlias) TableName() string {
	return "ocr_negative_aliases"
}

// OCR API Request/Response Types

// CreateOCRSessionRequest represents a request to create an OCR session
type CreateOCRSessionRequest struct {
	ImageData   string         `json:"image_data"`   // Base64 encoded image
	ImageType   string         `json:"image_type"`   // jpeg, png
	SessionType OCRSessionType `json:"session_type"` // quick_sale, inventory_check
	ShopID      uuid.UUID      `json:"shop_id"`
}

// ProcessOCRRequest represents a request to process OCR
type ProcessOCRRequest struct {
	SessionID uuid.UUID `json:"session_id"`
}

// ConfirmOCRItemsRequest represents a request to confirm OCR extracted items
type ConfirmOCRItemsRequest struct {
	SessionID uuid.UUID              `json:"session_id"`
	Items     []OCRItemConfirmation  `json:"items"`
}

// OCRItemConfirmation represents confirmation data for an extracted item
type OCRItemConfirmation struct {
	ItemID      uuid.UUID  `json:"item_id"`
	IsConfirmed bool       `json:"is_confirmed"`
	ProductID   *uuid.UUID `json:"product_id,omitempty"`
	Quantity    int        `json:"quantity"`
}

// CreateBrandAliasRequest represents a request to create a brand alias
type CreateBrandAliasRequest struct {
	BrandID   uuid.UUID `json:"brand_id"`
	AliasText string    `json:"alias_text"`
	AliasType AliasType `json:"alias_type"`
}

// OCRSessionResponse represents the response for an OCR session
type OCRSessionResponse struct {
	Session        *OCRSession         `json:"session"`
	ExtractedItems []OCRExtractedItem  `json:"extracted_items,omitempty"`
	Summary        *OCRProcessingSummary `json:"summary,omitempty"`
}

// OCRProcessingSummary provides a summary of OCR processing
type OCRProcessingSummary struct {
	TotalItems      int     `json:"total_items"`
	MatchedItems    int     `json:"matched_items"`
	UnmatchedItems  int     `json:"unmatched_items"`
	ConfidenceAvg   float64 `json:"confidence_avg"`
	ProcessingTime  int     `json:"processing_time_ms"`
	RequiresReview  bool    `json:"requires_review"`
}

// QuickSaleFromOCRRequest represents a request to create a sale from OCR
type QuickSaleFromOCRRequest struct {
	SessionID     uuid.UUID `json:"session_id"`
	CustomerPhone *string   `json:"customer_phone,omitempty"`
	PaymentMethod string    `json:"payment_method"` // cash, card, upi
	Notes         *string   `json:"notes,omitempty"`
}

// OCRMatchingConfig represents configuration for OCR matching
type OCRMatchingConfig struct {
	MinConfidenceScore     float64 `json:"min_confidence_score"`      // Minimum confidence to auto-match
	FuzzyMatchThreshold    float64 `json:"fuzzy_match_threshold"`     // Levenshtein distance threshold
	EnableAliasMatching    bool    `json:"enable_alias_matching"`     // Use brand aliases
	EnablePatternMatching  bool    `json:"enable_pattern_matching"`   // Use size patterns
	MaxSuggestionsPerItem  int     `json:"max_suggestions_per_item"`  // Max product suggestions
	AutoConfirmHighMatches bool    `json:"auto_confirm_high_matches"` // Auto-confirm >95% confidence
}

// ============================================================================
// Batch OCR Models for Multi-Image Processing
// ============================================================================

// BatchOCRStatus represents the status of a batch OCR session
type BatchOCRStatus string

const (
	BatchOCRStatusPending    BatchOCRStatus = "pending"
	BatchOCRStatusProcessing BatchOCRStatus = "processing"
	BatchOCRStatusCompleted  BatchOCRStatus = "completed"
	BatchOCRStatusPartial    BatchOCRStatus = "partial"    // Some images failed
	BatchOCRStatusFailed     BatchOCRStatus = "failed"
)

// BatchOCRSession represents a batch processing session for multiple images
type BatchOCRSession struct {
	ID              uuid.UUID       `json:"id" db:"id"`
	TenantID        uuid.UUID       `json:"tenant_id" db:"tenant_id"`
	UserID          uuid.UUID       `json:"user_id" db:"user_id"`
	ShopID          uuid.UUID       `json:"shop_id" db:"shop_id"`

	Status          BatchOCRStatus  `json:"status" db:"status"`
	SessionType     OCRSessionType  `json:"session_type" db:"session_type"`

	TotalImages     int             `json:"total_images" db:"total_images"`
	CompletedImages int             `json:"completed_images" db:"completed_images"`
	FailedImages    int             `json:"failed_images" db:"failed_images"`

	TotalItemsExtracted int         `json:"total_items_extracted" db:"total_items_extracted"`

	// Progress tracking fields (v1.0.27)
	CurrentStage        string      `json:"current_stage" db:"current_stage"`
	ProgressPercentage  int         `json:"progress_percentage" db:"progress_percentage"`

	CreatedAt       time.Time       `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at" db:"updated_at"`
	CompletedAt     *time.Time      `json:"completed_at" db:"completed_at"`

	// Related data (populated in service)
	Sessions        []OCRSession    `json:"sessions,omitempty" gorm:"-" db:"-"`
}

// CreateBatchOCRSessionRequest represents a request to create a batch OCR session
type CreateBatchOCRSessionRequest struct {
	Images      []ImageData      `json:"images"`       // Array of images to process
	ShopID      uuid.UUID        `json:"shop_id"`
	SessionType OCRSessionType   `json:"session_type"` // stock_initialization, invoice_import
}

// ImageData represents image data for batch processing
type ImageData struct {
	ImageData   string `json:"image_data"` // Base64 encoded image
	ImageType   string `json:"image_type"` // jpeg, png
	ImageIndex  int    `json:"image_index"` // Order in batch (optional)
}

// BatchOCRSessionResponse represents the response for a batch OCR session
type BatchOCRSessionResponse struct {
	BatchID         string             `json:"batch_id"`
	Status          BatchOCRStatus     `json:"status"`
	TotalImages     int                `json:"total_images"`
	CompletedImages int                `json:"completed_images"`
	FailedImages    int                `json:"failed_images"`
	Sessions        []SessionSummary   `json:"sessions"`
	CreatedAt       time.Time          `json:"created_at"`
	UpdatedAt       time.Time          `json:"updated_at"`
}

// SessionSummary represents a summary of an individual OCR session in a batch
type SessionSummary struct {
	SessionID       string           `json:"session_id"`
	ImageIndex      int              `json:"image_index"`
	Status          OCRSessionStatus `json:"status"`
	ItemsExtracted  int              `json:"items_extracted"`
	ErrorMessage    *string          `json:"error_message,omitempty"`
}

// ============================================================================
// Stock Initialization Models
// ============================================================================

// EnrichedStockItem represents an OCR-extracted item with enriched product data
type EnrichedStockItem struct {
	OCRItemID       uuid.UUID  `json:"ocr_item_id"`       // Reference to OCR extracted item

	// Product identification
	BrandText       string     `json:"brand_text"`
	SizeText        string     `json:"size_text"`

	// Enriched data (provided by user)
	CategoryID      uuid.UUID  `json:"category_id"`
	SubcategoryID   *uuid.UUID `json:"subcategory_id,omitempty"`
	SizeOverride    *string    `json:"size_override,omitempty"`    // User can override extracted size

	// Pricing
	SellingPrice    float64    `json:"selling_price"`
	CostPrice       *float64   `json:"cost_price,omitempty"`       // Optional
	MRP             *float64   `json:"mrp,omitempty"`              // Optional

	// Stock quantities
	AvailableStock  int        `json:"available_stock"`            // From closing_stock in OCR
	ReorderLevel    *int       `json:"reorder_level,omitempty"`    // Optional

	// Metadata
	Notes           *string    `json:"notes,omitempty"`
	SourceInvoices  []string   `json:"source_invoices,omitempty"` // Session IDs where this was found
	IsDuplicate     bool       `json:"is_duplicate"`              // True if merged from multiple images
}

// InitializeStockFromOCRRequest represents a request to initialize stock from OCR
type InitializeStockFromOCRRequest struct {
	SessionIDs []uuid.UUID         `json:"session_ids"`    // OCR session IDs (can be multiple from batch)
	Items      []EnrichedStockItem `json:"items"`          // Enriched items with category, price, etc.
	ShopID     uuid.UUID           `json:"shop_id"`
	Reason     string              `json:"reason"`         // e.g., "Initial Stock Setup from Invoices"
	Notes      *string             `json:"notes,omitempty"`
}

// StockInitializationResponse represents the response after stock initialization
type StockInitializationResponse struct {
	Success         bool       `json:"success"`
	TotalItems      int        `json:"total_items"`
	CreatedProducts int        `json:"created_products"`    // New products created
	UpdatedStock    int        `json:"updated_stock"`       // Existing products stock updated
	Errors          []string   `json:"errors,omitempty"`
	ProductIDs      []uuid.UUID `json:"product_ids,omitempty"` // IDs of created/updated products
}

// DeduplicatedItem represents an OCR item deduplicated across multiple sessions
type DeduplicatedItem struct {
	BrandText       string       `json:"brand_text"`
	SizeText        string       `json:"size_text"`
	RowNumber       *int         `json:"row_number,omitempty"`         // Serial number from receipt (S.No column)
	TotalStock      int          `json:"total_stock"`        // Sum of closing stocks
	AverageConfidence float64    `json:"average_confidence"` // Average match confidence
	SourceSessions  []uuid.UUID  `json:"source_sessions"`    // Session IDs where found
	SourceItems     []uuid.UUID  `json:"source_items"`       // OCR item IDs
	HighestMatch    *uuid.UUID   `json:"highest_match,omitempty"` // Best product match ID

	// Brand/Variant matching fields
	MatchedBrandID   *uuid.UUID   `json:"matched_brand_id,omitempty"`   // Matched SaaS brand ID
	MatchedVariantID *uuid.UUID   `json:"matched_variant_id,omitempty"` // Matched SaaS brand variant ID
	MatchConfidence  *float64     `json:"match_confidence,omitempty"`   // Match confidence score (0-100)

	// Pricing fields (from matched brand variant)
	SellingPrice     *float64     `json:"selling_price,omitempty"`      // Suggested selling price from brand variant
	BuyingPrice      *float64     `json:"buying_price,omitempty"`       // Suggested buying price from brand variant
	MRP              *float64     `json:"mrp,omitempty"`                // Maximum Retail Price from brand variant
}

// DeduplicatedItemsResponse represents the response with receipt type identification
type DeduplicatedItemsResponse struct {
	ReceiptType       string              `json:"receipt_type,omitempty"`    // Receipt type (e.g., "SALE RECEIPT QUATER", "SALE RECEIPT HALF")
	Items             []DeduplicatedItem  `json:"items"`                     // Deduplicated items
	RawTexts          map[string]string   `json:"raw_texts,omitempty"`       // Map of session_id -> complete Vision API raw text
	TotalItems        int                 `json:"total_items"`               // Total number of items after deduplication
	DuplicatesRemoved int                 `json:"duplicates_removed"`        // Number of duplicate items that were merged
}