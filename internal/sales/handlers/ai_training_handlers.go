package handlers

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/internal/sales/services"
)

// AITrainingHandlers handles AI training endpoints
type AITrainingHandlers struct {
	service *services.AITrainingService
}

// NewAITrainingHandlers creates a new AI training handler
func NewAITrainingHandlers(service *services.AITrainingService) *AITrainingHandlers {
	return &AITrainingHandlers{
		service: service,
	}
}

// Upload handles image upload and AI extraction
// POST /api/ai-training/upload
func (h *AITrainingHandlers) Upload(c *gin.Context) {
	// Get user info from context (set by auth middleware)
	userID, _ := c.Get("user_id")
	tenantID, _ := c.Get("tenant_id")

	var userUUID, tenantUUID *uuid.UUID
	if uid, ok := userID.(uuid.UUID); ok {
		userUUID = &uid
	}
	if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = &tid
	}

	// Parse multipart form
	file, header, err := c.Request.FormFile("image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "No image file provided",
			"details": err.Error(),
		})
		return
	}
	defer file.Close()

	// Validate file size (max 20MB)
	if header.Size > 20*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "File too large. Maximum size is 20MB",
		})
		return
	}

	// Validate content type
	contentType := header.Header.Get("Content-Type")
	validTypes := map[string]bool{
		"image/jpeg": true,
		"image/png":  true,
		"image/gif":  true,
		"image/webp": true,
	}
	if !validTypes[contentType] {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid file type. Supported: JPEG, PNG, GIF, WebP",
		})
		return
	}

	// Read file data
	imageData, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to read image data",
			"details": err.Error(),
		})
		return
	}

	// Process image with AI
	result, err := h.service.UploadAndProcess(c.Request.Context(), imageData, header.Filename, tenantUUID, userUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to process image",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Image uploaded and processed successfully",
		"data":    result,
	})
}

// ListImages lists all training images with filtering
// GET /api/ai-training/images
func (h *AITrainingHandlers) ListImages(c *gin.Context) {
	// Get tenant from context
	tenantID, _ := c.Get("tenant_id")
	var tenantUUID *uuid.UUID
	if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = &tid
	}

	// Parse query parameters
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	filter := models.AITrainingImageFilter{
		TenantID: tenantUUID,
		Page:     page,
		PageSize: pageSize,
	}

	// Filter by verification status
	if verified := c.Query("verified"); verified != "" {
		isVerified := verified == "true"
		filter.IsVerified = &isVerified
	}

	// Filter by image type
	if imageType := c.Query("type"); imageType != "" {
		filter.ImageType = &imageType
	}

	result, err := h.service.GetAllImages(c.Request.Context(), filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to list images",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// GetImage retrieves a single training image
// GET /api/ai-training/images/:id
func (h *AITrainingHandlers) GetImage(c *gin.Context) {
	idStr := c.Param("id")
	imageID, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid image ID",
		})
		return
	}

	image, err := h.service.GetImage(c.Request.Context(), imageID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "Image not found",
			"details": err.Error(),
		})
		return
	}

	// Parse AI extracted data for response
	var extractedData interface{}
	if len(image.AIExtractedData) > 0 {
		json.Unmarshal(image.AIExtractedData, &extractedData)
	}

	// Parse verified data for response
	var verifiedData interface{}
	if len(image.VerifiedData) > 0 {
		json.Unmarshal(image.VerifiedData, &verifiedData)
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"id":                    image.ID,
			"image_filename":        image.ImageFilename,
			"image_url":             image.ImageURL,
			"image_type":            image.ImageType,
			"ai_extracted_data":     extractedData,
			"ai_extraction_method":  image.AIExtractionMethod,
			"ai_confidence":         image.AIConfidence,
			"verified_data":         verifiedData,
			"is_verified":           image.IsVerified,
			"verified_at":           image.VerifiedAt,
			"is_used_for_training":  image.IsUsedForTraining,
			"created_at":            image.CreatedAt,
			"updated_at":            image.UpdatedAt,
		},
	})
}

// VerifyImage saves user verification/correction for an image
// PUT /api/ai-training/images/:id/verify
func (h *AITrainingHandlers) VerifyImage(c *gin.Context) {
	// Get user from context
	userID, _ := c.Get("user_id")
	var userUUID *uuid.UUID
	if uid, ok := userID.(uuid.UUID); ok {
		userUUID = &uid
	}

	idStr := c.Param("id")
	imageID, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid image ID",
		})
		return
	}

	var req models.AITrainingVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request body",
			"details": err.Error(),
		})
		return
	}

	if err := h.service.SaveVerifiedData(c.Request.Context(), imageID, req.VerifiedData, userUUID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to save verified data",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Verification saved successfully",
	})
}

// ExportTraining exports verified training data in JSONL format
// GET /api/ai-training/export
func (h *AITrainingHandlers) ExportTraining(c *gin.Context) {
	// Get tenant from context
	tenantID, _ := c.Get("tenant_id")
	var tenantUUID *uuid.UUID
	if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = &tid
	}

	exportItems, err := h.service.ExportTrainingData(c.Request.Context(), tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to export training data",
			"details": err.Error(),
		})
		return
	}

	if len(exportItems) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": "No verified images to export",
			"count":   0,
		})
		return
	}

	// Check if JSONL format requested
	if c.Query("format") == "jsonl" {
		// Set headers for file download
		c.Header("Content-Type", "application/x-ndjson")
		c.Header("Content-Disposition", "attachment; filename=ai_training_data.jsonl")

		// Stream JSONL output
		writer := bufio.NewWriter(c.Writer)
		for _, item := range exportItems {
			line, _ := json.Marshal(item)
			writer.Write(line)
			writer.WriteString("\n")
		}
		writer.Flush()
		return
	}

	// Return as JSON array
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": fmt.Sprintf("Exported %d verified training pairs", len(exportItems)),
		"count":   len(exportItems),
		"data":    exportItems,
	})
}

// DeleteImage deletes a training image
// DELETE /api/ai-training/images/:id
func (h *AITrainingHandlers) DeleteImage(c *gin.Context) {
	idStr := c.Param("id")
	imageID, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid image ID",
		})
		return
	}

	if err := h.service.DeleteImage(c.Request.Context(), imageID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to delete image",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Image deleted successfully",
	})
}
