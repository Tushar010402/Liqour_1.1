package models

import (
	"encoding/json"
	"time"
)

// TrainingImageData represents an image with its linked sale data for AI training
type TrainingImageData struct {
	ImageURL      string         `json:"image_url"`
	ImageFilename string         `json:"image_filename"`
	RecordID      string         `json:"record_id"`
	RecordDate    time.Time      `json:"record_date"`
	ShopID        string         `json:"shop_id"`
	ShopName      string         `json:"shop_name"`
	Items         []SaleItemData `json:"items"`
	TotalItems    int            `json:"total_items"`
	HasLinkedSale bool           `json:"has_linked_sale"`
}

// SaleItemData represents user-entered sale data (ground truth for AI training)
type SaleItemData struct {
	ProductID    string  `json:"product_id"`
	BrandName    string  `json:"brand_name"`
	Size         string  `json:"size"`
	OpeningStock int     `json:"opening_stock"`
	SaleQuantity int     `json:"sale_quantity"`
	Rate         float64 `json:"rate"`
	Amount       float64 `json:"amount"`
	ClosingStock int     `json:"closing_stock"`
}

// TrainingExportData represents a single entry in the JSONL export format
type TrainingExportData struct {
	Image       string                 `json:"image"`
	GroundTruth []GroundTruthItem      `json:"ground_truth"`
	Metadata    TrainingExportMetadata `json:"metadata"`
}

// GroundTruthItem represents a single item in the ground truth for training
type GroundTruthItem struct {
	Brand   string  `json:"brand"`
	Size    string  `json:"size"`
	Opening int     `json:"opening"`
	Sale    int     `json:"sale"`
	Rate    float64 `json:"rate"`
	Amount  float64 `json:"amount"`
	Closing int     `json:"closing"`
}

// TrainingExportMetadata contains metadata for training export
type TrainingExportMetadata struct {
	Date   string `json:"date"`
	Shop   string `json:"shop"`
	ShopID string `json:"shop_id"`
}

// TrainingImageListResponse represents the response for listing training images
type TrainingImageListResponse struct {
	Images      []TrainingImageData `json:"images"`
	TotalImages int                 `json:"total_images"`
	WithSales   int                 `json:"with_sales"`
	WithoutSales int               `json:"without_sales"`
}

// ===============================================
// Training Image Size Mapping Models
// ===============================================

// TrainingImageSizeMapping represents a mapping between an image and a specific size
type TrainingImageSizeMapping struct {
	ID                  string          `json:"id" db:"id"`
	TenantID            string          `json:"tenant_id" db:"tenant_id"`
	DailySalesRecordID  string          `json:"daily_sales_record_id" db:"daily_sales_record_id"`
	ImageFilename       string          `json:"image_filename" db:"image_filename"`
	ImageURL            string          `json:"image_url" db:"image_url"`
	DetectedSize        string          `json:"detected_size" db:"detected_size"`
	DetectionMethod     string          `json:"detection_method" db:"detection_method"`
	DetectionConfidence *float64        `json:"detection_confidence,omitempty" db:"detection_confidence"`
	IsCropped           bool            `json:"is_cropped" db:"is_cropped"`
	SourceImageFilename *string         `json:"source_image_filename,omitempty" db:"source_image_filename"`
	CropRegion          json.RawMessage `json:"crop_region,omitempty" db:"crop_region"`
	CroppedImagePath    *string         `json:"cropped_image_path,omitempty" db:"cropped_image_path"`
	IsBeerPage          bool            `json:"is_beer_page" db:"is_beer_page"`
	SizeSectionIndex    *int            `json:"size_section_index,omitempty" db:"size_section_index"`
	IsManuallyVerified  bool            `json:"is_manually_verified" db:"is_manually_verified"`
	VerifiedByID        *string         `json:"verified_by_id,omitempty" db:"verified_by_id"`
	VerifiedAt          *time.Time      `json:"verified_at,omitempty" db:"verified_at"`
	CreatedAt           time.Time       `json:"created_at" db:"created_at"`
	UpdatedAt           time.Time       `json:"updated_at" db:"updated_at"`
}

// CropRegionData represents the crop region coordinates
type CropRegionData struct {
	X          int     `json:"x"`
	Y          int     `json:"y"`
	Width      int     `json:"width"`
	Height     int     `json:"height"`
	YStartPct  float64 `json:"y_start_pct"`
	YEndPct    float64 `json:"y_end_pct"`
}

// SizeDetectionResult represents the result from Fomoa AI Vision
type SizeDetectionResult struct {
	IsBeerPage  bool              `json:"is_beer_page"`
	Sizes       []string          `json:"sizes"`
	SizeRegions []SizeRegionData  `json:"size_regions"`
	Confidence  float64           `json:"confidence"`
}

// SizeRegionData represents a size region in a beer page
type SizeRegionData struct {
	Size      string  `json:"size"`
	YStartPct float64 `json:"y_start_pct"`
	YEndPct   float64 `json:"y_end_pct"`
}

// TrainingImageWithMapping extends TrainingImageData with size mapping info
type TrainingImageWithMapping struct {
	TrainingImageData
	SizeMapping      *TrainingImageSizeMapping `json:"size_mapping,omitempty"`
	DetectedSize     string                    `json:"detected_size,omitempty"`
	DetectionMethod  string                    `json:"detection_method,omitempty"`
	IsBeerPage       bool                      `json:"is_beer_page"`
	ProcessingStatus string                    `json:"processing_status"` // "pending", "processed", "failed"
}

// TrainingExportDataV2 represents the new export format with size filtering
type TrainingExportDataV2 struct {
	Image       string                   `json:"image"`
	Size        string                   `json:"size"`
	GroundTruth []GroundTruthItem        `json:"ground_truth"`
	Metadata    TrainingExportMetadataV2 `json:"metadata"`
}

// TrainingExportMetadataV2 contains extended metadata for v2 training export
type TrainingExportMetadataV2 struct {
	Date          string `json:"date"`
	Shop          string `json:"shop"`
	ShopID        string `json:"shop_id"`
	IsBeerPage    bool   `json:"is_beer_page"`
	OriginalImage string `json:"original_image,omitempty"`
	IsCropped     bool   `json:"is_cropped"`
}

// ProcessImageRequest represents a request to process an image for size detection
type ProcessImageRequest struct {
	Filename string `json:"filename"`
	TenantID string `json:"tenant_id"`
	RecordID string `json:"record_id,omitempty"`
}

// ProcessImageResponse represents the response from processing an image
type ProcessImageResponse struct {
	Success         bool                       `json:"success"`
	Filename        string                     `json:"filename"`
	DetectionResult *SizeDetectionResult       `json:"detection_result,omitempty"`
	Mappings        []TrainingImageSizeMapping `json:"mappings,omitempty"`
	Error           string                     `json:"error,omitempty"`
}

// VerifySizeMappingRequest represents a request to manually verify/override size mapping
type VerifySizeMappingRequest struct {
	MappingID    string `json:"mapping_id"`
	CorrectSize  string `json:"correct_size"`
	IsBeerPage   bool   `json:"is_beer_page"`
	VerifiedByID string `json:"verified_by_id"`
}

// TrainingImageListResponseV2 represents the response for listing training images with mappings
type TrainingImageListResponseV2 struct {
	Images           []TrainingImageWithMapping `json:"images"`
	TotalImages      int                        `json:"total_images"`
	ProcessedImages  int                        `json:"processed_images"`
	PendingImages    int                        `json:"pending_images"`
	WithSales        int                        `json:"with_sales"`
	WithoutSales     int                        `json:"without_sales"`
	SizeDistribution map[string]int             `json:"size_distribution"`
}
