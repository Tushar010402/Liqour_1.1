package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// AITrainingImage represents a standalone image for AI training
type AITrainingImage struct {
	ID       uuid.UUID  `json:"id" db:"id"`
	TenantID *uuid.UUID `json:"tenant_id,omitempty" db:"tenant_id"`

	// Image info
	ImageFilename string  `json:"image_filename" db:"image_filename"`
	ImageURL      string  `json:"image_url" db:"image_url"`
	ImageType     *string `json:"image_type,omitempty" db:"image_type"`

	// AI extraction
	AIExtractedData     json.RawMessage `json:"ai_extracted_data" db:"ai_extracted_data"`
	AIExtractionMethod  string          `json:"ai_extraction_method" db:"ai_extraction_method"`
	AIConfidence        *float64        `json:"ai_confidence,omitempty" db:"ai_confidence"`

	// User verification
	VerifiedData   json.RawMessage `json:"verified_data,omitempty" db:"verified_data"`
	IsVerified     bool            `json:"is_verified" db:"is_verified"`
	VerifiedByID   *uuid.UUID      `json:"verified_by_id,omitempty" db:"verified_by_id"`
	VerifiedAt     *time.Time      `json:"verified_at,omitempty" db:"verified_at"`

	// Training status
	IsUsedForTraining   bool       `json:"is_used_for_training" db:"is_used_for_training"`
	TrainingExportedAt  *time.Time `json:"training_exported_at,omitempty" db:"training_exported_at"`

	// Metadata
	UploadedByID *uuid.UUID `json:"uploaded_by_id,omitempty" db:"uploaded_by_id"`
	CreatedAt    time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at" db:"updated_at"`
}

// AIExtractionResult represents the structured extraction from Fomoa AI
type AIExtractionResult struct {
	DocumentType string                   `json:"document_type"` // table, receipt, invoice, form, register, text
	Headers      []string                 `json:"headers,omitempty"`
	Rows         []map[string]interface{} `json:"rows,omitempty"`
	FormFields   []FormField              `json:"form_fields,omitempty"`
	RawText      string                   `json:"raw_text,omitempty"`
	Totals       *DocumentTotals          `json:"totals,omitempty"`
	Confidence   float64                  `json:"confidence"`
}

// FormField represents a label-value pair from form extraction
type FormField struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

// DocumentTotals represents totals extracted from receipts/invoices
type DocumentTotals struct {
	Subtotal string `json:"subtotal,omitempty"`
	Tax      string `json:"tax,omitempty"`
	Total    string `json:"total,omitempty"`
	Discount string `json:"discount,omitempty"`
}

// AITrainingUploadRequest represents an upload request
type AITrainingUploadRequest struct {
	Filename string `json:"filename"`
}

// AITrainingUploadResponse represents the response after upload and AI extraction
type AITrainingUploadResponse struct {
	ID              uuid.UUID           `json:"id"`
	ImageURL        string              `json:"image_url"`
	ImageFilename   string              `json:"image_filename"`
	ExtractedData   *AIExtractionResult `json:"extracted_data"`
	Confidence      float64             `json:"confidence"`
	ProcessingTime  float64             `json:"processing_time_ms"`
	CreatedAt       time.Time           `json:"created_at"`
}

// AITrainingVerifyRequest represents a verification/correction request
type AITrainingVerifyRequest struct {
	VerifiedData json.RawMessage `json:"verified_data"`
}

// AITrainingImageListItem represents an image in the list view
type AITrainingImageListItem struct {
	ID            uuid.UUID  `json:"id" db:"id"`
	ImageFilename string     `json:"image_filename" db:"image_filename"`
	ImageURL      string     `json:"image_url" db:"image_url"`
	ImageType     *string    `json:"image_type,omitempty" db:"image_type"`
	IsVerified    bool       `json:"is_verified" db:"is_verified"`
	AIConfidence  *float64   `json:"ai_confidence,omitempty" db:"ai_confidence"`
	CreatedAt     time.Time  `json:"created_at" db:"created_at"`
	VerifiedAt    *time.Time `json:"verified_at,omitempty" db:"verified_at"`
}

// AITrainingListResponse represents the list endpoint response
type AITrainingListResponse struct {
	Images      []AITrainingImageListItem `json:"images"`
	Total       int                       `json:"total"`
	TotalPages  int                       `json:"total_pages"`
	CurrentPage int                       `json:"current_page"`
	Stats       AITrainingStats           `json:"stats"`
}

// AITrainingStats provides summary statistics
type AITrainingStats struct {
	TotalImages     int `json:"total_images"`
	VerifiedCount   int `json:"verified_count"`
	PendingCount    int `json:"pending_count"`
	ExportedCount   int `json:"exported_count"`
}

// AITrainingExportItem represents a single item in the training export
type AITrainingExportItem struct {
	ImageURL     string          `json:"image_url"`
	ImageType    string          `json:"image_type"`
	AIOutput     json.RawMessage `json:"ai_output"`
	VerifiedData json.RawMessage `json:"verified_data"`
	Confidence   float64         `json:"ai_confidence"`
	VerifiedAt   time.Time       `json:"verified_at"`
}

// AITrainingImageFilter represents filtering options for listing images
type AITrainingImageFilter struct {
	TenantID   *uuid.UUID
	IsVerified *bool
	ImageType  *string
	Page       int
	PageSize   int
}
