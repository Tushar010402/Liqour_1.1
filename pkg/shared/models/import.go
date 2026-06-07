package models

import (
	"time"

	"github.com/google/uuid"
)

// ImportType represents the type of import
type ImportType string

const (
	ImportTypeExcel   ImportType = "excel"
	ImportTypeCSV     ImportType = "csv"
	ImportTypeInvoice ImportType = "invoice"
	ImportTypeImage   ImportType = "image"
)

// ImportStatus represents the status of an import operation
type ImportStatus string

const (
	ImportStatusPending    ImportStatus = "pending"
	ImportStatusValidating ImportStatus = "validating"
	ImportStatusValidated  ImportStatus = "validated"
	ImportStatusProcessing ImportStatus = "processing"
	ImportStatusCompleted  ImportStatus = "completed"
	ImportStatusFailed     ImportStatus = "failed"
)

// ImportHistory tracks all import operations for audit and reference
type ImportHistory struct {
	ID              uuid.UUID    `gorm:"type:uuid;primary_key;default:uuid_generate_v4()" json:"id"`
	TenantID        uuid.UUID    `gorm:"type:uuid;not null;index" json:"tenant_id"`
	UserID          uuid.UUID    `gorm:"type:uuid;not null;index" json:"user_id"`
	ShopID          *uuid.UUID   `gorm:"type:uuid;index" json:"shop_id,omitempty"`
	ImportType      ImportType   `gorm:"type:varchar(20);not null" json:"import_type"`
	Status          ImportStatus `gorm:"type:varchar(20);not null;default:'pending'" json:"status"`
	FileName        string       `gorm:"type:varchar(255)" json:"file_name"`
	FileSize        int64        `json:"file_size"`
	TotalRows       int          `json:"total_rows"`
	ValidRows       int          `json:"valid_rows"`
	InvalidRows     int          `json:"invalid_rows"`
	ProcessedRows   int          `json:"processed_rows"`
	ProductsCreated int          `json:"products_created"`
	StocksCreated   int          `json:"stocks_created"`
	ErrorMessage    string       `gorm:"type:text" json:"error_message,omitempty"`
	ValidationJSON  *string      `gorm:"type:jsonb" json:"validation_json,omitempty"` // Stores validation results as JSON (nullable)
	ProcessingTime  int          `json:"processing_time_ms"`
	CreatedAt       time.Time    `json:"created_at"`
	UpdatedAt       time.Time    `json:"updated_at"`
	CompletedAt     *time.Time   `json:"completed_at,omitempty"`
}

// TableName specifies the table name for ImportHistory
func (ImportHistory) TableName() string {
	return "import_history"
}

// ImportRow represents a single row from import file with validation results
type ImportRow struct {
	RowNumber        int                    `json:"row_number"`
	BrandName        string                 `json:"brand_name"`
	Size             string                 `json:"size"`
	Category         string                 `json:"category"`
	Subcategory      string                 `json:"subcategory,omitempty"`
	Quantity         int                    `json:"quantity"`
	BuyingPrice      float64                `json:"buying_price,omitempty"`
	MRP              float64                `json:"mrp,omitempty"`
	Duty             float64                `json:"duty,omitempty"`
	SellingPrice     float64                `json:"selling_price,omitempty"`
	ShopName         string                 `json:"shop_name,omitempty"`
	ShopID           *uuid.UUID             `json:"shop_id,omitempty"`
	IsValid          bool                   `json:"is_valid"`
	ValidationErrors []string               `json:"validation_errors,omitempty"`
	MatchedBrand     *BrandMatchResult      `json:"matched_brand,omitempty"`
	ExtraFields      map[string]interface{} `json:"extra_fields,omitempty"` // For extensibility
}

// BrandMatchResult represents the result of smart brand matching
type BrandMatchResult struct {
	MatchType       string     `json:"match_type"`        // "exact", "fuzzy", "variant", "no_match"
	Confidence      float64    `json:"confidence"`        // 0-100 match confidence
	SaaSBrandID     *uuid.UUID `json:"saas_brand_id,omitempty"`
	SaaSVariantID   *uuid.UUID `json:"saas_variant_id,omitempty"`
	BrandName       string     `json:"brand_name"`
	VariantSize     string     `json:"variant_size,omitempty"`
	CategoryID      *uuid.UUID `json:"category_id,omitempty"`
	SubcategoryID   *uuid.UUID `json:"subcategory_id,omitempty"`
	CategoryName    string     `json:"category_name"`
	SubcategoryName string     `json:"subcategory_name,omitempty"`
	FetchedMRP      float64    `json:"fetched_mrp,omitempty"`
	FetchedDuty     float64    `json:"fetched_duty,omitempty"`
	FetchedCost     float64    `json:"fetched_cost,omitempty"`
	FetchedSelling  float64    `json:"fetched_selling,omitempty"`
	AlternateMatches []AlternateMatch `json:"alternate_matches,omitempty"` // Other possible matches
}

// AlternateMatch represents alternative brand matches for user selection
type AlternateMatch struct {
	SaaSBrandID   uuid.UUID `json:"saas_brand_id"`
	SaaSVariantID uuid.UUID `json:"saas_variant_id"`
	BrandName     string    `json:"brand_name"`
	VariantSize   string    `json:"variant_size"`
	Confidence    float64   `json:"confidence"`
	MRP           float64   `json:"mrp"`
	CategoryName  string    `json:"category_name"`
}

// ImportValidationResult represents the complete validation result for preview
type ImportValidationResult struct {
	ImportID         uuid.UUID    `json:"import_id"`
	TenantID         uuid.UUID    `json:"tenant_id"`
	ShopID           *uuid.UUID   `json:"shop_id,omitempty"`
	Status           ImportStatus `json:"status"`
	TotalRows        int          `json:"total_rows"`
	ValidRows        int          `json:"valid_rows"`
	InvalidRows      int          `json:"invalid_rows"`
	CanProceed       bool         `json:"can_proceed"`
	Rows             []ImportRow  `json:"rows"`
	GlobalErrors     []string     `json:"global_errors,omitempty"`
	Warnings         []string     `json:"warnings,omitempty"`
	ProcessingTimeMs int          `json:"processing_time_ms"`
}

// BulkImportRequest represents the request to upload and validate import file
type BulkImportRequest struct {
	TenantID       uuid.UUID  `json:"tenant_id" binding:"required"`
	UserID         uuid.UUID  `json:"user_id" binding:"required"`
	ShopID         *uuid.UUID `json:"shop_id,omitempty"`         // Optional: defaults to first shop or specified in Excel
	ImportType     ImportType `json:"import_type" binding:"required"`
	AutoCreateBrand bool      `json:"auto_create_brand"`         // If true, create custom brands when no match found
	StrictMatching  bool      `json:"strict_matching"`           // If true, reject fuzzy matches below threshold
	MinConfidence   float64   `json:"min_confidence,omitempty"`  // Minimum confidence for fuzzy matches (default 80)
}

// BulkImportConfirmRequest confirms the import after user reviews preview
type BulkImportConfirmRequest struct {
	ImportID           uuid.UUID            `json:"import_id" binding:"required"`
	TenantID           uuid.UUID            `json:"tenant_id" binding:"required"`
	UserID             uuid.UUID            `json:"user_id" binding:"required"`
	SelectedRows       []int                `json:"selected_rows,omitempty"`        // If empty, import all valid rows
	RowCorrections     map[int]ImportRow    `json:"row_corrections,omitempty"`      // User corrections for specific rows
	AlternateSelections map[int]uuid.UUID   `json:"alternate_selections,omitempty"` // User-selected alternate matches (row -> variant_id)
}

// ExcelTemplateRequest represents a request to generate Excel template
type ExcelTemplateRequest struct {
	TenantID       uuid.UUID  `json:"tenant_id" binding:"required"`
	ShopID         *uuid.UUID `json:"shop_id,omitempty"`
	IncludeExamples bool      `json:"include_examples"` // If true, add sample rows
	TemplateType    string    `json:"template_type"`    // "basic", "advanced", "invoice"
}

// ImportStatistics provides aggregated import stats for dashboard
type ImportStatistics struct {
	TenantID          uuid.UUID `json:"tenant_id"`
	TotalImports      int       `json:"total_imports"`
	SuccessfulImports int       `json:"successful_imports"`
	FailedImports     int       `json:"failed_imports"`
	TotalProductsAdded int      `json:"total_products_added"`
	TotalStockAdded   int       `json:"total_stock_added"`
	LastImportAt      *time.Time `json:"last_import_at,omitempty"`
	AverageProcessingTime int    `json:"average_processing_time_ms"`
}
