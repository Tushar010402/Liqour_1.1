package handlers

import (
	"net/http"
	"net/url"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/internal/sales/services"
)

// TrainingHandlers handles training data API requests
type TrainingHandlers struct {
	service *services.TrainingImageService
}

// NewTrainingHandlers creates a new training handlers instance
func NewTrainingHandlers(service *services.TrainingImageService) *TrainingHandlers {
	return &TrainingHandlers{
		service: service,
	}
}

// GetTrainingImages returns all training images with their linked sale status
// GET /api/training/images
func (h *TrainingHandlers) GetTrainingImages(c *gin.Context) {
	// Get tenant ID from context (optional for this endpoint)
	tenantID := ""
	if tid, exists := c.Get("tenant_id"); exists {
		if tidStr, ok := tid.(string); ok {
			tenantID = tidStr
		}
	}

	response, err := h.service.GetTrainingImagesWithSales(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch training images",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    response,
	})
}

// GetImageSaleData returns sale data for a specific image
// GET /api/training/images/:filename
func (h *TrainingHandlers) GetImageSaleData(c *gin.Context) {
	filename := c.Param("filename")
	if filename == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Image filename is required",
		})
		return
	}

	// URL decode the filename in case it contains special characters
	decodedFilename, err := url.QueryUnescape(filename)
	if err != nil {
		decodedFilename = filename
	}

	// Get tenant ID from context (optional for this endpoint)
	tenantID := ""
	if tid, exists := c.Get("tenant_id"); exists {
		if tidStr, ok := tid.(string); ok {
			tenantID = tidStr
		}
	}

	imageData, err := h.service.GetImageSaleData(c.Request.Context(), decodedFilename, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch image sale data",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"image_url":      imageData.ImageURL,
		"image_filename": imageData.ImageFilename,
		"record_id":      imageData.RecordID,
		"record_date":    imageData.RecordDate,
		"shop_id":        imageData.ShopID,
		"shop_name":      imageData.ShopName,
		"items":          imageData.Items,
		"total_items":    imageData.TotalItems,
		"has_linked_sale": imageData.HasLinkedSale,
	})
}

// GetRecordsWithImages returns records that have images attached (for debugging)
// GET /api/training/debug/records
func (h *TrainingHandlers) GetRecordsWithImages(c *gin.Context) {
	records, err := h.service.GetRecordsWithImages(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch records",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"count":   len(records),
		"data":    records,
	})
}

// ExportTrainingData exports all training images with sale data as JSONL
// GET /api/training/images/export
func (h *TrainingHandlers) ExportTrainingData(c *gin.Context) {
	// Get tenant ID from context (optional for this endpoint)
	tenantID := ""
	if tid, exists := c.Get("tenant_id"); exists {
		if tidStr, ok := tid.(string); ok {
			tenantID = tidStr
		}
	}

	jsonlContent, err := h.service.ExportTrainingData(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to export training data",
			"details": err.Error(),
		})
		return
	}

	c.Header("Content-Disposition", "attachment; filename=training_data.jsonl")
	c.Header("Content-Type", "application/x-ndjson")
	c.String(http.StatusOK, jsonlContent)
}

// ===============================================
// V2 Handlers - Size-based Training Images
// ===============================================

// GetTrainingImagesV2 returns training images with size mappings
// GET /api/training/images/v2
func (h *TrainingHandlers) GetTrainingImagesV2(c *gin.Context) {
	tenantID := h.getTenantID(c)
	sizeFilter := c.Query("size") // Optional size filter

	response, err := h.service.GetTrainingImagesWithMappings(c.Request.Context(), tenantID, sizeFilter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch training images",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    response,
	})
}

// ProcessImage processes a single image for size detection
// POST /api/training/images/process/:filename
func (h *TrainingHandlers) ProcessImage(c *gin.Context) {
	filename := c.Param("filename")
	if filename == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Image filename is required",
		})
		return
	}

	// URL decode the filename
	decodedFilename, err := url.QueryUnescape(filename)
	if err != nil {
		decodedFilename = filename
	}

	tenantID := h.getTenantID(c)

	response, err := h.service.ProcessImageForTraining(c.Request.Context(), decodedFilename, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to process image",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": response.Success,
		"data":    response,
	})
}

// ProcessAllImages batch processes all unprocessed images
// POST /api/training/images/process-all
func (h *TrainingHandlers) ProcessAllImages(c *gin.Context) {
	tenantID := h.getTenantID(c)

	processed, failed, err := h.service.ProcessAllImages(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to process images",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"processed": processed,
		"failed":    failed,
		"message":   "Batch processing completed",
	})
}

// DetectImageSize detects size from an image without saving
// POST /api/training/images/detect-size/:filename
func (h *TrainingHandlers) DetectImageSize(c *gin.Context) {
	filename := c.Param("filename")
	if filename == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Image filename is required",
		})
		return
	}

	decodedFilename, err := url.QueryUnescape(filename)
	if err != nil {
		decodedFilename = filename
	}

	// Create detector
	detector, err := services.NewSizeHeaderDetector()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to create detector",
			"details": err.Error(),
		})
		return
	}

	// Find and read image file
	imageDirs := []string{
		"./uploads/daily_sales",
		"/var/www/liquorpro/uploads/daily_sales",
	}

	var imageData []byte
	for _, dir := range imageDirs {
		path := dir + "/" + decodedFilename
		data, err := services.ReadFileHelper(path)
		if err == nil {
			imageData = data
			break
		}
	}

	if imageData == nil {
		c.JSON(http.StatusNotFound, gin.H{
			"success": false,
			"error":   "Image file not found",
		})
		return
	}

	// Detect size
	result, err := detector.DetectSizeFromImage(c.Request.Context(), imageData, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Size detection failed",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"filename": decodedFilename,
		"result":   result,
	})
}

// GetSizeMappings returns size mappings for a daily sales record
// GET /api/training/mappings/:record_id
func (h *TrainingHandlers) GetSizeMappings(c *gin.Context) {
	recordID := c.Param("record_id")
	if recordID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Record ID is required",
		})
		return
	}

	mappings, err := h.service.GetSizeMappingsForRecord(c.Request.Context(), recordID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch mappings",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"count":    len(mappings),
		"mappings": mappings,
	})
}

// VerifySizeMapping manually verifies or overrides a size mapping
// POST /api/training/mappings/:id/verify
func (h *TrainingHandlers) VerifySizeMapping(c *gin.Context) {
	mappingID := c.Param("id")
	if mappingID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Mapping ID is required",
		})
		return
	}

	var req models.VerifySizeMappingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request body",
			"details": err.Error(),
		})
		return
	}

	req.MappingID = mappingID

	// Get user ID from context if available
	if userID, exists := c.Get("user_id"); exists {
		if userIDStr, ok := userID.(string); ok {
			req.VerifiedByID = userIDStr
		}
	}

	if err := h.service.VerifySizeMapping(c.Request.Context(), &req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to verify mapping",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Mapping verified successfully",
	})
}

// ExportTrainingDataV2 exports training data with size-filtered ground truth
// GET /api/training/images/export-v2
func (h *TrainingHandlers) ExportTrainingDataV2(c *gin.Context) {
	tenantID := h.getTenantID(c)

	jsonlContent, err := h.service.ExportTrainingDataV2(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to export training data",
			"details": err.Error(),
		})
		return
	}

	c.Header("Content-Disposition", "attachment; filename=training_data_v2.jsonl")
	c.Header("Content-Type", "application/x-ndjson")
	c.String(http.StatusOK, jsonlContent)
}

// GetSizeFilteredItems returns items filtered by size for a record
// GET /api/training/items/:record_id/:size
func (h *TrainingHandlers) GetSizeFilteredItems(c *gin.Context) {
	recordID := c.Param("record_id")
	size := c.Param("size")

	if recordID == "" || size == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Record ID and size are required",
		})
		return
	}

	items, err := h.service.GetSizeFilteredItems(c.Request.Context(), recordID, size)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch items",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"size":    size,
		"count":   len(items),
		"items":   items,
	})
}

// Helper function to get tenant ID from context
func (h *TrainingHandlers) getTenantID(c *gin.Context) string {
	if tid, exists := c.Get("tenant_id"); exists {
		if tidStr, ok := tid.(string); ok {
			return tidStr
		}
	}
	return ""
}
