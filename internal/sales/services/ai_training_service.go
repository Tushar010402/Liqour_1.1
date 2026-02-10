package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"gorm.io/gorm"
)

// AITrainingService handles AI training image processing and management
type AITrainingService struct {
	db         *database.DB
	apiKey     string
	httpClient *http.Client
	model      string
	maxRetries int
	uploadPath string
}

// NewAITrainingService creates a new AI training service
func NewAITrainingService(db *database.DB) (*AITrainingService, error) {
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY environment variable not set")
	}

	// Ensure upload directory exists
	uploadPath := os.Getenv("AI_TRAINING_UPLOAD_PATH")
	if uploadPath == "" {
		uploadPath = "/var/www/liquorpro/uploads/ai-training"
	}
	if err := os.MkdirAll(uploadPath, 0755); err != nil {
		return nil, fmt.Errorf("failed to create upload directory: %w", err)
	}

	return &AITrainingService{
		db:     db,
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 180 * time.Second, // 3 minute timeout for vision processing
		},
		model:      "gpt-4o-2024-11-20",
		maxRetries: 3,
		uploadPath: uploadPath,
	}, nil
}

// UploadAndProcess uploads an image and immediately processes it with AI extraction
func (s *AITrainingService) UploadAndProcess(ctx context.Context, imageData []byte, filename string, tenantID, userID *uuid.UUID) (*models.AITrainingUploadResponse, error) {
	startTime := time.Now()

	fmt.Printf("🤖 [AI Training] Starting upload and processing for: %s\n", filename)

	// Generate unique filename
	ext := filepath.Ext(filename)
	uniqueFilename := fmt.Sprintf("%s_%s%s", time.Now().Format("20060102_150405"), uuid.New().String()[:8], ext)
	filePath := filepath.Join(s.uploadPath, uniqueFilename)

	// Save file to disk
	if err := os.WriteFile(filePath, imageData, 0644); err != nil {
		return nil, fmt.Errorf("failed to save image: %w", err)
	}

	// Generate URL for the image (relative to web root)
	imageURL := fmt.Sprintf("/uploads/ai-training/%s", uniqueFilename)

	// Extract data using AI
	fmt.Printf("🔍 [AI Training] Running AI extraction...\n")
	extractedData, err := s.ExtractWithFomoa(ctx, imageData)
	if err != nil {
		// Still save the image even if extraction fails
		fmt.Printf("⚠️  [AI Training] Extraction failed: %v\n", err)
		extractedData = &models.AIExtractionResult{
			DocumentType: "unknown",
			RawText:      "Extraction failed: " + err.Error(),
			Confidence:   0,
		}
	}

	// Convert to JSON for storage
	extractedJSON, err := json.Marshal(extractedData)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal extracted data: %w", err)
	}

	// Create database record
	imageType := extractedData.DocumentType
	confidence := extractedData.Confidence

	trainingImage := &models.AITrainingImage{
		ID:                 uuid.New(),
		TenantID:           tenantID,
		ImageFilename:      filename,
		ImageURL:           imageURL,
		ImageType:          &imageType,
		AIExtractedData:    extractedJSON,
		AIExtractionMethod: "fomoa_vision",
		AIConfidence:       &confidence,
		UploadedByID:       userID,
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	if err := s.db.DB.Create(trainingImage).Error; err != nil {
		return nil, fmt.Errorf("failed to save training image: %w", err)
	}

	processingTime := float64(time.Since(startTime).Milliseconds())
	fmt.Printf("✅ [AI Training] Processed in %.0fms, saved with ID: %s\n", processingTime, trainingImage.ID)

	return &models.AITrainingUploadResponse{
		ID:             trainingImage.ID,
		ImageURL:       imageURL,
		ImageFilename:  filename,
		ExtractedData:  extractedData,
		Confidence:     confidence,
		ProcessingTime: processingTime,
		CreatedAt:      trainingImage.CreatedAt,
	}, nil
}

// ExtractWithFomoa extracts content from an image using GPT-4o Vision
func (s *AITrainingService) ExtractWithFomoa(ctx context.Context, imageData []byte) (*models.AIExtractionResult, error) {
	fmt.Printf("🤖 [Fomoa Vision] Starting extraction with GPT-4o...\n")

	// Prepare image content
	base64Image := base64.StdEncoding.EncodeToString(imageData)
	mimeType := detectMimeType(imageData)

	// Build the extraction prompt for generic document extraction
	prompt := s.buildGenericExtractionPrompt()

	// Build the request
	request := OpenAIRequest{
		Model: s.model,
		Messages: []OpenAIMessage{
			{
				Role: "user",
				Content: []OpenAIContent{
					{
						Type: "text",
						Text: prompt,
					},
					{
						Type: "image_url",
						ImageURL: &OpenAIImageURL{
							URL:    fmt.Sprintf("data:%s;base64,%s", mimeType, base64Image),
							Detail: "high",
						},
					},
				},
			},
		},
		MaxTokens:   8192, // Sufficient for document extraction
		Temperature: 0.1,  // Low temperature for accurate extraction
	}

	// Make API call with retries
	var response *OpenAIResponse
	var err error
	for attempt := 1; attempt <= s.maxRetries; attempt++ {
		response, err = s.makeAPICall(ctx, request)
		if err == nil {
			break
		}
		fmt.Printf("⚠️  [Fomoa Vision] Attempt %d failed: %v\n", attempt, err)
		if attempt < s.maxRetries {
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("API call failed after %d attempts: %w", s.maxRetries, err)
	}

	// Parse the response
	result, err := s.parseExtractionResponse(response)
	if err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	fmt.Printf("✅ [Fomoa Vision] Extracted document type: %s, confidence: %.1f%%\n", result.DocumentType, result.Confidence)

	return result, nil
}

// buildGenericExtractionPrompt creates the prompt for generic document extraction
func (s *AITrainingService) buildGenericExtractionPrompt() string {
	return `You are an expert document OCR system. Analyze this image and extract ALL content.

STEP 1: Identify the document type:
- table: structured rows and columns
- receipt: sales/purchase receipt with items and totals
- invoice: formal invoice with line items
- form: form with labels and values
- register: handwritten or printed register/ledger
- text: plain text document

STEP 2: Extract all content maintaining structure:
- For tables/receipts/invoices/registers: identify headers and extract each row
- For forms: extract label-value pairs
- For text: extract paragraphs in order

Return ONLY valid JSON (no markdown code blocks):
{
  "document_type": "table|receipt|invoice|form|register|text",
  "headers": ["Column1", "Column2", "..."],
  "rows": [
    {"Column1": "value", "Column2": "value"},
    {"Column1": "value", "Column2": "value"}
  ],
  "form_fields": [
    {"label": "Field Name", "value": "Field Value"}
  ],
  "raw_text": "Full OCR text preserving line breaks...",
  "totals": {
    "subtotal": "100.00",
    "tax": "10.00",
    "total": "110.00"
  },
  "confidence": 85
}

IMPORTANT RULES:
- Extract EXACTLY what you see - do not infer or guess
- Preserve original spelling even if it seems wrong
- Include empty cells as empty strings ""
- Numbers should be strings to preserve formatting (e.g., "100.00" not 100)
- For tables with no clear headers, use generic names like "Column1", "Column2", etc.
- If handwritten, do your best to read the text accurately
- Confidence should be 0-100 based on image quality and extraction certainty
- If form_fields is not applicable, return empty array []
- If totals is not applicable, return null
- If the document has no table structure, rows and headers can be empty arrays`
}

// makeAPICall makes the HTTP request to OpenAI API
func (s *AITrainingService) makeAPICall(ctx context.Context, request OpenAIRequest) (*OpenAIResponse, error) {
	jsonData, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var response OpenAIResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if response.Error != nil {
		return nil, fmt.Errorf("API error: %s (%s)", response.Error.Message, response.Error.Type)
	}

	fmt.Printf("📊 [Fomoa Vision] Tokens used: %d (prompt: %d, completion: %d)\n",
		response.Usage.TotalTokens, response.Usage.PromptTokens, response.Usage.CompletionTokens)

	return &response, nil
}

// parseExtractionResponse parses the GPT-4o response into AIExtractionResult
func (s *AITrainingService) parseExtractionResponse(response *OpenAIResponse) (*models.AIExtractionResult, error) {
	if len(response.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	content := response.Choices[0].Message.Content

	// Clean up the response
	content = cleanJSONResponse(content)

	fmt.Printf("🔍 [Fomoa Vision] Response length: %d chars\n", len(content))

	var result models.AIExtractionResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		// Try to extract JSON if wrapped in text
		jsonStart := strings.Index(content, "{")
		jsonEnd := strings.LastIndex(content, "}")
		if jsonStart >= 0 && jsonEnd > jsonStart {
			cleanedJSON := content[jsonStart : jsonEnd+1]
			if err := json.Unmarshal([]byte(cleanedJSON), &result); err != nil {
				fmt.Printf("❌ [Fomoa Vision] Failed to parse JSON: %v\n", err)
				return nil, fmt.Errorf("failed to parse JSON response: %w", err)
			}
		} else {
			return nil, fmt.Errorf("no valid JSON found in response")
		}
	}

	return &result, nil
}

// SaveVerifiedData saves user-verified/corrected data for a training image
func (s *AITrainingService) SaveVerifiedData(ctx context.Context, imageID uuid.UUID, verifiedData json.RawMessage, userID *uuid.UUID) error {
	now := time.Now()

	result := s.db.DB.Model(&models.AITrainingImage{}).
		Where("id = ?", imageID).
		Updates(map[string]interface{}{
			"verified_data":   verifiedData,
			"is_verified":     true,
			"verified_by_id":  userID,
			"verified_at":     now,
			"updated_at":      now,
		})

	if result.Error != nil {
		return fmt.Errorf("failed to save verified data: %w", result.Error)
	}

	if result.RowsAffected == 0 {
		return fmt.Errorf("image not found: %s", imageID)
	}

	fmt.Printf("✅ [AI Training] Verified data saved for image: %s\n", imageID)
	return nil
}

// GetImage retrieves a single training image by ID
func (s *AITrainingService) GetImage(ctx context.Context, imageID uuid.UUID) (*models.AITrainingImage, error) {
	var image models.AITrainingImage
	if err := s.db.DB.Where("id = ?", imageID).First(&image).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("image not found: %s", imageID)
		}
		return nil, fmt.Errorf("failed to get image: %w", err)
	}
	return &image, nil
}

// GetAllImages retrieves all training images with optional filtering
func (s *AITrainingService) GetAllImages(ctx context.Context, filter models.AITrainingImageFilter) (*models.AITrainingListResponse, error) {
	// Default pagination
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.PageSize < 1 || filter.PageSize > 100 {
		filter.PageSize = 20
	}

	query := s.db.DB.Model(&models.AITrainingImage{})

	// Apply filters
	if filter.TenantID != nil {
		query = query.Where("tenant_id = ?", filter.TenantID)
	}
	if filter.IsVerified != nil {
		query = query.Where("is_verified = ?", *filter.IsVerified)
	}
	if filter.ImageType != nil && *filter.ImageType != "" {
		query = query.Where("image_type = ?", *filter.ImageType)
	}

	// Count total
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, fmt.Errorf("failed to count images: %w", err)
	}

	// Get stats
	stats, err := s.getStats(ctx, filter.TenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to get stats: %w", err)
	}

	// Get paginated results
	var images []models.AITrainingImageListItem
	offset := (filter.Page - 1) * filter.PageSize

	if err := query.
		Select("id, image_filename, image_url, image_type, is_verified, ai_confidence, created_at, verified_at").
		Order("created_at DESC").
		Offset(offset).
		Limit(filter.PageSize).
		Find(&images).Error; err != nil {
		return nil, fmt.Errorf("failed to list images: %w", err)
	}

	totalPages := int(total) / filter.PageSize
	if int(total)%filter.PageSize > 0 {
		totalPages++
	}

	return &models.AITrainingListResponse{
		Images:      images,
		Total:       int(total),
		TotalPages:  totalPages,
		CurrentPage: filter.Page,
		Stats:       *stats,
	}, nil
}

// getStats retrieves summary statistics
func (s *AITrainingService) getStats(ctx context.Context, tenantID *uuid.UUID) (*models.AITrainingStats, error) {
	var stats models.AITrainingStats

	query := s.db.DB.Model(&models.AITrainingImage{})
	if tenantID != nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	// Total images
	var total int64
	query.Count(&total)
	stats.TotalImages = int(total)

	// Verified count
	var verified int64
	verifyQuery := s.db.DB.Model(&models.AITrainingImage{}).Where("is_verified = ?", true)
	if tenantID != nil {
		verifyQuery = verifyQuery.Where("tenant_id = ?", tenantID)
	}
	verifyQuery.Count(&verified)
	stats.VerifiedCount = int(verified)

	// Pending count
	stats.PendingCount = stats.TotalImages - stats.VerifiedCount

	// Exported count
	var exported int64
	exportQuery := s.db.DB.Model(&models.AITrainingImage{}).Where("is_used_for_training = ?", true)
	if tenantID != nil {
		exportQuery = exportQuery.Where("tenant_id = ?", tenantID)
	}
	exportQuery.Count(&exported)
	stats.ExportedCount = int(exported)

	return &stats, nil
}

// ExportTrainingData exports verified training pairs in JSONL format
func (s *AITrainingService) ExportTrainingData(ctx context.Context, tenantID *uuid.UUID) ([]models.AITrainingExportItem, error) {
	query := s.db.DB.Model(&models.AITrainingImage{}).
		Where("is_verified = ?", true)

	if tenantID != nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	var images []models.AITrainingImage
	if err := query.Find(&images).Error; err != nil {
		return nil, fmt.Errorf("failed to query verified images: %w", err)
	}

	exportItems := make([]models.AITrainingExportItem, 0, len(images))
	now := time.Now()

	for _, img := range images {
		imageType := "unknown"
		if img.ImageType != nil {
			imageType = *img.ImageType
		}

		confidence := 0.0
		if img.AIConfidence != nil {
			confidence = *img.AIConfidence
		}

		verifiedAt := now
		if img.VerifiedAt != nil {
			verifiedAt = *img.VerifiedAt
		}

		item := models.AITrainingExportItem{
			ImageURL:     img.ImageURL,
			ImageType:    imageType,
			AIOutput:     img.AIExtractedData,
			VerifiedData: img.VerifiedData,
			Confidence:   confidence,
			VerifiedAt:   verifiedAt,
		}
		exportItems = append(exportItems, item)

		// Mark as exported
		s.db.DB.Model(&models.AITrainingImage{}).
			Where("id = ?", img.ID).
			Updates(map[string]interface{}{
				"is_used_for_training":  true,
				"training_exported_at": now,
			})
	}

	fmt.Printf("📦 [AI Training] Exported %d verified training pairs\n", len(exportItems))

	return exportItems, nil
}

// DeleteImage deletes a training image and its file
func (s *AITrainingService) DeleteImage(ctx context.Context, imageID uuid.UUID) error {
	// Get image to find file path
	var image models.AITrainingImage
	if err := s.db.DB.Where("id = ?", imageID).First(&image).Error; err != nil {
		return fmt.Errorf("image not found: %w", err)
	}

	// Delete file from disk
	filename := filepath.Base(image.ImageURL)
	filePath := filepath.Join(s.uploadPath, filename)
	if err := os.Remove(filePath); err != nil && !os.IsNotExist(err) {
		fmt.Printf("⚠️  [AI Training] Failed to delete file %s: %v\n", filePath, err)
	}

	// Delete database record
	if err := s.db.DB.Delete(&image).Error; err != nil {
		return fmt.Errorf("failed to delete image record: %w", err)
	}

	fmt.Printf("🗑️  [AI Training] Deleted image: %s\n", imageID)
	return nil
}
