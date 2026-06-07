package handlers

import (
	"encoding/base64"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
)

// OCRHandlers handles OCR-related HTTP requests
type OCRHandlers struct {
	ocrService *services.SimpleOCRService
	logger     *logrus.Logger
}

// NewOCRHandlers creates a new OCR handlers instance
func NewOCRHandlers(ocrService *services.SimpleOCRService, logger *logrus.Logger) *OCRHandlers {
	return &OCRHandlers{
		ocrService: ocrService,
		logger:     logger,
	}
}

// CreateOCRSession creates a new OCR session
// @Summary Create OCR Session
// @Description Upload an image to create an OCR processing session
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.CreateOCRSessionRequest true "OCR session request"
// @Success 201 {object} models.OCRSession
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Router /sales/ocr/sessions [post]
func (h *OCRHandlers) CreateOCRSession(c *gin.Context) {
	// Get user context
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse request
	var req models.CreateOCRSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.logger.Warnf("Invalid OCR session request: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request format"})
		return
	}

	// Validate required fields
	if req.ImageData == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Image data is required"})
		return
	}

	// Validate shop_id is provided (not uuid.Nil)
	if req.ShopID == uuid.Nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shop ID is required"})
		return
	}

	// Validate image size (base64 encoded)
	// Base64 encoding increases size by ~33%, so 2MB image = ~2.67MB base64
	// Allow up to 4MB base64 (approximately 3MB actual image after compression)
	const maxBase64Size = 4 * 1024 * 1024 // 4MB
	if len(req.ImageData) > maxBase64Size {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Image size exceeds maximum allowed size (4MB base64)",
			"max_size_mb": 4,
			"actual_size_mb": float64(len(req.ImageData)) / (1024 * 1024),
		})
		return
	}

	if req.ImageType == "" {
		req.ImageType = "jpeg" // Default to JPEG
	}

	if req.SessionType == "" {
		req.SessionType = models.OCRSessionTypeQuickSale
	}

	// Parse UUIDs from string
	var userUUID, tenantUUID uuid.UUID
	var parseErr error

	// Parse user ID
	if userIDStr, ok := userID.(string); ok {
		userUUID, parseErr = uuid.Parse(userIDStr)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
			return
		}
	} else if uid, ok := userID.(uuid.UUID); ok {
		userUUID = uid
	}

	// Parse tenant ID
	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, parseErr = uuid.Parse(tenantIDStr)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Create OCR session
	session, err := h.ocrService.CreateOCRSession(
		c.Request.Context(),
		&req,
		userUUID,
		tenantUUID,
	)
	if err != nil {
		h.logger.Errorf("Failed to create OCR session: %v", err)
		if err.Error() == "image size exceeds maximum allowed size" {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create OCR session"})
		return
	}

	h.logger.Infof("Created OCR session %s for user %s", session.ID, userID)
	c.JSON(http.StatusCreated, session)
}

// GetOCRSession retrieves an OCR session with extracted items
// @Summary Get OCR Session
// @Description Get OCR session details with extracted items and matching results
// @Tags OCR
// @Produce json
// @Param id path string true "Session ID"
// @Success 200 {object} models.OCRSessionResponse
// @Failure 404 {object} map[string]string
// @Router /sales/ocr/sessions/{id} [get]
func (h *OCRHandlers) GetOCRSession(c *gin.Context) {
	// Get session ID
	sessionIDStr := c.Param("id")
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse tenant ID
	var tenantUUID uuid.UUID
	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, err = uuid.Parse(tenantIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Get OCR session
	response, err := h.ocrService.GetOCRSession(
		c.Request.Context(),
		sessionID,
		tenantUUID,
	)
	if err != nil {
		if err.Error() == "OCR session not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Session not found"})
			return
		}
		h.logger.Errorf("Failed to get OCR session: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve session"})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetOCRSessionStatus gets the current status of an OCR session
// @Summary Get OCR Session Status
// @Description Check the processing status of an OCR session
// @Tags OCR
// @Produce json
// @Param id path string true "Session ID"
// @Success 200 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Router /sales/ocr/sessions/{id}/status [get]
func (h *OCRHandlers) GetOCRSessionStatus(c *gin.Context) {
	// Get session ID
	sessionIDStr := c.Param("id")
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse tenant ID
	var tenantUUID uuid.UUID
	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, err = uuid.Parse(tenantIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Get session status (simplified - in production, create a dedicated method)
	response, err := h.ocrService.GetOCRSession(
		c.Request.Context(),
		sessionID,
		tenantUUID,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Session not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"session_id": response.Session.ID,
		"status":     response.Session.Status,
		"progress":   h.calculateProgress(response.Session.Status),
		"summary":    response.Summary,
	})
}

// ConfirmOCRItems confirms or corrects extracted items
// @Summary Confirm OCR Items
// @Description Confirm, reject, or correct extracted items before creating a sale
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.ConfirmOCRItemsRequest true "Confirmation request"
// @Success 200 {object} map[string]string
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/sessions/confirm [post]
func (h *OCRHandlers) ConfirmOCRItems(c *gin.Context) {
	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse request
	var req models.ConfirmOCRItemsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request format"})
		return
	}

	// Confirm items
	err := h.ocrService.ConfirmOCRItems(
		c.Request.Context(),
		&req,
		tenantID.(uuid.UUID),
	)
	if err != nil {
		h.logger.Errorf("Failed to confirm OCR items: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to confirm items"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Items confirmed successfully",
		"session_id": req.SessionID,
	})
}

// CreateQuickSaleFromOCR creates a sale from confirmed OCR items
// @Summary Create Quick Sale from OCR
// @Description Create a sale transaction from confirmed OCR extracted items
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.QuickSaleFromOCRRequest true "Quick sale request"
// @Success 201 {object} models.Sale
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/quick-sale [post]
func (h *OCRHandlers) CreateQuickSaleFromOCR(c *gin.Context) {
	// Get user context
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse request
	var req models.QuickSaleFromOCRRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request format"})
		return
	}

	// Validate payment method
	validPaymentMethods := map[string]bool{
		"cash": true,
		"card": true,
		"upi":  true,
	}
	if !validPaymentMethods[req.PaymentMethod] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid payment method"})
		return
	}

	// Create sale from OCR
	sale, err := h.ocrService.CreateQuickSaleFromOCR(
		c.Request.Context(),
		&req,
		userID.(uuid.UUID),
		tenantID.(uuid.UUID),
	)
	if err != nil {
		h.logger.Errorf("Failed to create quick sale from OCR: %v", err)
		if err.Error() == "no confirmed items found" {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create sale"})
		return
	}

	h.logger.Infof("Created quick sale %s from OCR session %s", sale.ID, req.SessionID)
	c.JSON(http.StatusCreated, sale)
}

// CreateBrandAlias creates a new brand alias
// @Summary Create Brand Alias
// @Description Add an alias for a brand to improve OCR matching
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.CreateBrandAliasRequest true "Brand alias request"
// @Success 201 {object} models.BrandAlias
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/brand-aliases [post]
func (h *OCRHandlers) CreateBrandAlias(c *gin.Context) {
	// Get user context
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Check user role (manager or admin)
	role, _ := c.Get("role")
	if role != "manager" && role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	// Parse request
	var req models.CreateBrandAliasRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request format"})
		return
	}

	// Validate alias text
	if len(req.AliasText) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Alias text too short"})
		return
	}

	// Create brand alias
	alias, err := h.ocrService.CreateBrandAlias(
		c.Request.Context(),
		&req,
		userID.(uuid.UUID),
		tenantID.(uuid.UUID),
	)
	if err != nil {
		h.logger.Errorf("Failed to create brand alias: %v", err)
		if err.Error() == "alias already exists" {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create alias"})
		return
	}

	h.logger.Infof("Created brand alias '%s' for brand %s", alias.AliasText, alias.BrandID)
	c.JSON(http.StatusCreated, alias)
}

// GetBrandAliases gets aliases for a brand
// @Summary Get Brand Aliases
// @Description Get all aliases for a specific brand
// @Tags OCR
// @Produce json
// @Param brand_id path string true "Brand ID"
// @Success 200 {array} models.BrandAlias
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/brands/{brand_id}/aliases [get]
func (h *OCRHandlers) GetBrandAliases(c *gin.Context) {
	// Get brand ID
	brandIDStr := c.Param("brand_id")
	brandID, err := uuid.Parse(brandIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand ID"})
		return
	}

	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Get brand aliases
	aliases, err := h.ocrService.GetBrandAliases(
		c.Request.Context(),
		brandID,
		tenantID.(uuid.UUID),
	)
	if err != nil {
		h.logger.Errorf("Failed to get brand aliases: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve aliases"})
		return
	}

	c.JSON(http.StatusOK, aliases)
}

// GetOCRConfig gets the current OCR configuration
// @Summary Get OCR Configuration
// @Description Get the current OCR matching configuration settings
// @Tags OCR
// @Produce json
// @Success 200 {object} models.OCRMatchingConfig
// @Router /sales/ocr/config [get]
func (h *OCRHandlers) GetOCRConfig(c *gin.Context) {
	// Return current configuration
	config := models.OCRMatchingConfig{
		MinConfidenceScore:     60,
		FuzzyMatchThreshold:    0.8,
		EnableAliasMatching:    true,
		EnablePatternMatching:  true,
		MaxSuggestionsPerItem:  5,
		AutoConfirmHighMatches: true,
	}

	c.JSON(http.StatusOK, config)
}

// SubmitOCRFeedback submits learning feedback for OCR matching
// @Summary Submit OCR Feedback
// @Description Submit feedback to improve OCR matching accuracy
// @Tags OCR
// @Accept json
// @Produce json
// @Param feedback body models.OCRLearningFeedback true "Feedback data"
// @Success 200 {object} map[string]string
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/feedback [post]
func (h *OCRHandlers) SubmitOCRFeedback(c *gin.Context) {
	// Get user context
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse feedback
	var feedback models.OCRLearningFeedback
	if err := c.ShouldBindJSON(&feedback); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid feedback format"})
		return
	}

	// Set user and tenant
	feedback.UserID = userID.(uuid.UUID)
	feedback.TenantID = tenantID.(uuid.UUID)

	// Store feedback (simplified - in production, implement proper storage)
	h.logger.Infof("Received OCR feedback from user %s for item %s", userID, feedback.ExtractedItemID)

	c.JSON(http.StatusOK, gin.H{
		"message": "Feedback received successfully",
		"item_id": feedback.ExtractedItemID,
	})
}

// CreateBatchOCRSession creates a batch OCR session for multiple images
// @Summary Create Batch OCR Session
// @Description Upload multiple images (up to 10) for batch OCR processing
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.CreateBatchOCRSessionRequest true "Batch OCR session request"
// @Success 201 {object} models.BatchOCRSession
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Router /sales/ocr/batch/sessions [post]
func (h *OCRHandlers) CreateBatchOCRSession(c *gin.Context) {
	// Get user context
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse multipart form data (2025 Best Practice for image uploads)
	if err := c.Request.ParseMultipartForm(32 << 20); err != nil { // 32MB max memory
		h.logger.Warnf("❌ [OCR] Failed to parse multipart form: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse multipart form: %v", err)})
		return
	}

	// Get form fields
	shopIDStr := c.PostForm("shop_id")
	sessionType := c.PostForm("session_type")

	// Validate shop_id
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
		return
	}

	// Set default session type
	if sessionType == "" {
		sessionType = string(models.OCRSessionTypeStockInitialization)
	}

	// Get uploaded files
	form := c.Request.MultipartForm
	files := form.File["images"]

	// Validate file count
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one image is required"})
		return
	}

	if len(files) > 10 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Maximum 10 images allowed per batch",
			"max_images": 10,
			"provided_images": len(files),
		})
		return
	}

	// Modern file validation (2025 best practices)
	const maxFileSize = 5 * 1024 * 1024 // 5MB per image
	allowedTypes := map[string]bool{
		"image/jpeg": true,
		"image/jpg":  true,
		"image/png":  true,
	}

	// Convert uploaded files to base64 for processing
	var req models.CreateBatchOCRSessionRequest
	req.ShopID = shopID
	req.SessionType = models.OCRSessionType(sessionType)
	req.Images = make([]models.ImageData, 0, len(files))

	for i, fileHeader := range files {
		// Validate file size
		if fileHeader.Size > maxFileSize {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Image size exceeds maximum allowed size",
				"image_index": i,
				"file_name": fileHeader.Filename,
				"max_size_mb": 5,
				"actual_size_mb": float64(fileHeader.Size) / (1024 * 1024),
			})
			return
		}

		// Validate file type
		contentType := fileHeader.Header.Get("Content-Type")
		if !allowedTypes[contentType] {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Invalid image format. Only JPEG and PNG allowed",
				"image_index": i,
				"file_name": fileHeader.Filename,
				"content_type": contentType,
			})
			return
		}

		// Open and read file
		file, err := fileHeader.Open()
		if err != nil {
			h.logger.Errorf("Failed to open uploaded file %s: %v", fileHeader.Filename, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to process image"})
			return
		}
		defer file.Close()

		// Read file content
		fileBytes := make([]byte, fileHeader.Size)
		if _, err := file.Read(fileBytes); err != nil {
			h.logger.Errorf("Failed to read uploaded file %s: %v", fileHeader.Filename, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read image"})
			return
		}

		// Convert to base64 for OCR service compatibility
		imageData := base64.StdEncoding.EncodeToString(fileBytes)
		imageType := "jpeg"
		if contentType == "image/png" {
			imageType = "png"
		}

		req.Images = append(req.Images, models.ImageData{
			ImageData: imageData,
			ImageType: imageType,
			ImageIndex: i,
		})

		h.logger.Debugf("📸 Processed image %d: %s (%.2f KB)", i, fileHeader.Filename, float64(fileHeader.Size)/1024)
	}

	// Parse UUIDs from string
	var userUUID, tenantUUID uuid.UUID
	var parseErr error

	// Parse user ID
	if userIDStr, ok := userID.(string); ok {
		userUUID, parseErr = uuid.Parse(userIDStr)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
			return
		}
	} else if uid, ok := userID.(uuid.UUID); ok {
		userUUID = uid
	}

	// Parse tenant ID
	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, parseErr = uuid.Parse(tenantIDStr)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Create batch OCR session
	batchSession, err := h.ocrService.CreateBatchOCRSession(
		c.Request.Context(),
		&req,
		userUUID,
		tenantUUID,
	)
	if err != nil {
		h.logger.Errorf("Failed to create batch OCR session: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create batch OCR session"})
		return
	}

	h.logger.Infof("Created batch OCR session %s with %d images for user %s",
		batchSession.ID, len(req.Images), userID)
	c.JSON(http.StatusCreated, batchSession)
}

// GetBatchOCRSession retrieves a batch OCR session with all sub-sessions and extracted items
// @Summary Get Batch OCR Session
// @Description Get batch OCR session details with progress and extracted items
// @Tags OCR
// @Produce json
// @Param id path string true "Batch Session ID"
// @Success 200 {object} models.BatchOCRSession
// @Failure 404 {object} map[string]string
// @Router /sales/ocr/batch/sessions/{id} [get]
func (h *OCRHandlers) GetBatchOCRSession(c *gin.Context) {
	// Get batch session ID
	batchSessionIDStr := c.Param("id")
	batchSessionID, err := uuid.Parse(batchSessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid batch session ID"})
		return
	}

	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse tenant ID
	var tenantUUID uuid.UUID
	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, err = uuid.Parse(tenantIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Get batch OCR session
	batchSession, err := h.ocrService.GetBatchOCRSession(
		c.Request.Context(),
		batchSessionID,
		tenantUUID,
	)
	if err != nil {
		if err.Error() == "batch OCR session not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Batch session not found"})
			return
		}
		h.logger.Errorf("Failed to get batch OCR session: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve batch session"})
		return
	}

	// Extract session IDs from the Sessions array
	sessionIDs := make([]uuid.UUID, len(batchSession.Sessions))
	for i, session := range batchSession.Sessions {
		sessionIDs[i] = session.ID
	}

	// Create response with session_ids field
	response := gin.H{
		"id":                    batchSession.ID,
		"tenant_id":             batchSession.TenantID,
		"user_id":               batchSession.UserID,
		"shop_id":               batchSession.ShopID,
		"status":                batchSession.Status,
		"session_type":          batchSession.SessionType,
		"total_images":          batchSession.TotalImages,
		"completed_images":      batchSession.CompletedImages,
		"failed_images":         batchSession.FailedImages,
		"total_items_extracted": batchSession.TotalItemsExtracted,
		"created_at":            batchSession.CreatedAt,
		"updated_at":            batchSession.UpdatedAt,
		"completed_at":          batchSession.CompletedAt,
		"session_ids":           sessionIDs,
		"sessions":              batchSession.Sessions,
	}

	c.JSON(http.StatusOK, response)
}

// GetDeduplicatedItems gets deduplicated items from batch OCR sessions
// @Summary Get Deduplicated Items
// @Description Get deduplicated items from multiple OCR sessions
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.GetDeduplicatedItemsRequest true "Session IDs"
// @Success 200 {array} models.DeduplicatedItem
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/batch/deduplicate [post]
func (h *OCRHandlers) GetDeduplicatedItems(c *gin.Context) {
	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse request
	var req struct {
		SessionIDs []uuid.UUID `json:"session_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request format"})
		return
	}

	if len(req.SessionIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one session ID is required"})
		return
	}

	// Parse tenant ID
	var tenantUUID uuid.UUID
	var err error
	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, err = uuid.Parse(tenantIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Get deduplicated items with receipt type
	response, err := h.ocrService.GetDeduplicatedItems(
		c.Request.Context(),
		req.SessionIDs,
		tenantUUID,
	)
	if err != nil {
		h.logger.Errorf("Failed to get deduplicated items: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to deduplicate items"})
		return
	}

	c.JSON(http.StatusOK, response)
}

// InitializeStockFromOCR initializes stock from OCR extracted and enriched items
// @Summary Initialize Stock from OCR
// @Description Create stock entries from OCR extracted items with enriched data
// @Tags OCR
// @Accept json
// @Produce json
// @Param request body models.InitializeStockFromOCRRequest true "Stock initialization request"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Router /sales/ocr/stock/initialize [post]
func (h *OCRHandlers) InitializeStockFromOCR(c *gin.Context) {
	// Get user context
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Check user role (manager or admin)
	role, _ := c.Get("role")
	if role != "manager" && role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions to initialize stock"})
		return
	}

	// Parse request
	var req models.InitializeStockFromOCRRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.logger.Warnf("Invalid stock initialization request: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request format"})
		return
	}

	// Validate request
	if len(req.SessionIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one session ID is required"})
		return
	}

	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one enriched item is required"})
		return
	}

	if req.ShopID == uuid.Nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Shop ID is required"})
		return
	}

	if req.Reason == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Reason is required for stock initialization"})
		return
	}

	// Validate each enriched item
	for i, item := range req.Items {
		if item.BrandText == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Brand text is required",
				"item_index": i,
			})
			return
		}

		if item.CategoryID == uuid.Nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Category ID is required",
				"item_index": i,
			})
			return
		}

		if item.SellingPrice <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Selling price must be greater than 0",
				"item_index": i,
			})
			return
		}

		if item.AvailableStock < 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Available stock cannot be negative",
				"item_index": i,
			})
			return
		}
	}

	// Parse UUIDs
	var userUUID, tenantUUID uuid.UUID
	var parseErr error

	if userIDStr, ok := userID.(string); ok {
		userUUID, parseErr = uuid.Parse(userIDStr)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
			return
		}
	} else if uid, ok := userID.(uuid.UUID); ok {
		userUUID = uid
	}

	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, parseErr = uuid.Parse(tenantIDStr)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Initialize stock from OCR
	result, err := h.ocrService.InitializeStockFromOCR(
		c.Request.Context(),
		&req,
		userUUID,
		tenantUUID,
	)
	if err != nil {
		h.logger.Errorf("Failed to initialize stock from OCR: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to initialize stock"})
		return
	}

	h.logger.Infof("Initialized stock from OCR for shop %s: %d items, user %s",
		req.ShopID, len(req.Items), userID)
	c.JSON(http.StatusCreated, result)
}

// Helper methods

func (h *OCRHandlers) calculateProgress(status models.OCRSessionStatus) int {
	switch status {
	case models.OCRStatusPending:
		return 0
	case models.OCRStatusProcessing:
		return 50
	case models.OCRStatusCompleted:
		return 100
	case models.OCRStatusFailed:
		return -1
	case models.OCRStatusExpired:
		return -1
	default:
		return 0
	}
}