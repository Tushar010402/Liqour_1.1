package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/internal/sales/services"
)

// OCRHandlers handles OCR-related HTTP requests
type OCRHandlers struct {
	ocrService *services.OCRService
}

// NewOCRHandlers creates a new OCR handlers instance
func NewOCRHandlers(ocrService *services.OCRService) *OCRHandlers {
	return &OCRHandlers{
		ocrService: ocrService,
	}
}

// CreateBatchSessionRequest represents the request to create a batch OCR session
// Supports flexible image formats from Flutter app
type CreateBatchSessionRequest struct {
	ShopID      string          `json:"shop_id"`
	SessionType string          `json:"session_type"`
	Images      json.RawMessage `json:"images"` // Can be array of strings or array of objects
	Image       string          `json:"image"`  // Single base64 encoded image (alternative)
}

// ImageObject represents an image object with various field names
type ImageObject struct {
	Data      string `json:"data"`
	Base64    string `json:"base64"`
	Content   string `json:"content"`
	ImageData string `json:"imageData"`
	Image     string `json:"image"`
}

// GetBase64 returns the base64 string from whichever field contains it
func (img ImageObject) GetBase64() string {
	if img.Data != "" {
		return img.Data
	}
	if img.Base64 != "" {
		return img.Base64
	}
	if img.Content != "" {
		return img.Content
	}
	if img.ImageData != "" {
		return img.ImageData
	}
	if img.Image != "" {
		return img.Image
	}
	return ""
}

// CreateBatchSession creates a new batch OCR session and processes images
// POST /api/sales/ocr/batch/sessions
// Supports both JSON (with base64 images) and multipart/form-data requests
func (h *OCRHandlers) CreateBatchSession(c *gin.Context) {
	// Log incoming request
	contentType := c.GetHeader("Content-Type")
	println("📸 [OCR] CreateBatchSession called")
	println("📸 [OCR] Content-Type:", contentType)
	println("📸 [OCR] Content-Length:", c.GetHeader("Content-Length"))

	var shopID, sessionType string
	var base64Images []string

	// Check if JSON request or multipart form
	if strings.Contains(contentType, "application/json") {
		// Parse JSON request with base64 encoded images
		println("📸 [OCR] Parsing JSON request")
		var req CreateBatchSessionRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			println("❌ [OCR] Failed to parse JSON:", err.Error())
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON request", "details": err.Error()})
			return
		}
		shopID = req.ShopID
		sessionType = req.SessionType

		// Handle flexible images format
		if len(req.Images) > 0 {
			println("📸 [OCR] Parsing images field, raw length:", len(req.Images))
			// Try parsing as array of strings first
			var stringImages []string
			if err := json.Unmarshal(req.Images, &stringImages); err == nil {
				base64Images = stringImages
				println("📸 [OCR] Parsed as string array:", len(base64Images), "images")
			} else {
				// Try parsing as array of generic maps to see actual field names
				var genericImages []map[string]interface{}
				if err := json.Unmarshal(req.Images, &genericImages); err == nil {
					println("📸 [OCR] Parsed as object array, count:", len(genericImages))
					for i, imgMap := range genericImages {
						// Log the field names
						var fields []string
						for k := range imgMap {
							fields = append(fields, k)
						}
						println("📸 [OCR] Image", i, "fields:", strings.Join(fields, ", "))

						// Try to extract base64 from any field that might contain it
						var b64 string
						for _, key := range []string{"data", "base64", "content", "imageData", "image", "bytes", "encoded", "value"} {
							if val, ok := imgMap[key]; ok {
								if strVal, ok := val.(string); ok && len(strVal) > 100 {
									b64 = strVal
									println("📸 [OCR] Found base64 in field:", key, "length:", len(b64))
									break
								}
							}
						}

						if b64 != "" {
							base64Images = append(base64Images, b64)
							println("📸 [OCR] Image", i, "extracted, length:", len(b64))
						} else {
							// If no standard field found, try the first string field that looks like base64
							for k, v := range imgMap {
								if strVal, ok := v.(string); ok && len(strVal) > 1000 {
									b64 = strVal
									println("📸 [OCR] Found base64 in non-standard field:", k, "length:", len(b64))
									base64Images = append(base64Images, b64)
									break
								}
							}
							if b64 == "" {
								println("❌ [OCR] Image", i, "has no base64 data in any field")
							}
						}
					}
					println("📸 [OCR] Total images extracted:", len(base64Images))
				} else {
					// Try parsing as a single object
					var singleObj ImageObject
					if err := json.Unmarshal(req.Images, &singleObj); err == nil {
						b64 := singleObj.GetBase64()
						if b64 != "" {
							base64Images = []string{b64}
							println("📸 [OCR] Parsed as single object, length:", len(b64))
						}
					} else {
						// Log first 200 chars to see what format it is
						preview := string(req.Images)
						if len(preview) > 200 {
							preview = preview[:200]
						}
						println("❌ [OCR] Could not parse images field, preview:", preview)
					}
				}
			}
		}

		// Fallback to single "image" field
		if len(base64Images) == 0 && req.Image != "" {
			base64Images = []string{req.Image}
			println("📸 [OCR] Using single image field")
		}
		println("✅ [OCR] JSON parsed - shop_id:", shopID, "session_type:", sessionType, "images:", len(base64Images))
	} else {
		// Parse multipart form
		println("📸 [OCR] Parsing multipart form")
		if err := c.Request.ParseMultipartForm(50 << 20); err != nil { // 50MB max
			println("❌ [OCR] Failed to parse multipart form:", err.Error())
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse multipart form", "details": err.Error()})
			return
		}
		println("✅ [OCR] Multipart form parsed successfully")

		// Get form values
		shopID = c.PostForm("shop_id")
		sessionType = c.PostForm("session_type")
		println("📸 [OCR] Form values - shop_id:", shopID, "session_type:", sessionType)

		// Get uploaded files
		form, _ := c.MultipartForm()
		files := form.File["images"]
		println("📸 [OCR] Received", len(files), "image files")

		if len(files) == 0 {
			println("❌ [OCR] No images found in request")
			c.JSON(http.StatusBadRequest, gin.H{"error": "At least one image is required"})
			return
		}

		// Read and encode images as base64
		for _, fileHeader := range files {
			file, err := fileHeader.Open()
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image", "details": err.Error()})
				return
			}
			defer file.Close()

			// Read file content
			fileBytes, err := io.ReadAll(file)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image data", "details": err.Error()})
				return
			}

			// Encode to base64
			base64Str := base64.StdEncoding.EncodeToString(fileBytes)
			base64Images = append(base64Images, base64Str)
		}
	}

	// Validate required fields
	if shopID == "" || sessionType == "" {
		println("❌ [OCR] Missing required fields - shop_id or session_type")
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id and session_type are required"})
		return
	}

	if len(base64Images) == 0 {
		println("❌ [OCR] No images provided")
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one image is required"})
		return
	}

	// Get tenant ID from context
	tenantID, _ := c.Get("tenant_id")
	tenantIDStr, ok := tenantID.(string)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Get user ID from context
	userID, _ := c.Get("user_id")
	userIDStr, ok := userID.(string)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	// Create batch session
	session, err := h.ocrService.CreateBatchSession(
		c.Request.Context(),
		tenantIDStr,
		userIDStr,
		shopID,
		sessionType,
		len(base64Images),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create batch session", "details": err.Error()})
		return
	}

	// Process images asynchronously
	// Create a background context that won't be canceled when the HTTP request completes
	go func() {
		// Use context.Background() instead of c.Request.Context() to avoid cancellation
		ctx := context.Background()
		err := h.ocrService.ProcessImageBatch(ctx, session.ID, base64Images)
		if err != nil {
			// Log error but don't fail the request
			println("Error processing image batch:", err.Error())
		}
	}()

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "Batch session created successfully",
		"data":    session,
	})
}

// GetBatchSession retrieves a batch OCR session by ID
// GET /api/sales/ocr/batch/sessions/:id
func (h *OCRHandlers) GetBatchSession(c *gin.Context) {
	batchID := c.Param("id")
	if batchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Batch ID is required"})
		return
	}

	session, err := h.ocrService.GetBatchSession(c.Request.Context(), batchID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Batch session not found", "details": err.Error()})
		return
	}

	// Get extracted items if session is completed - populate inside session for Flutter compatibility
	if session.Status == "completed" || session.TotalItemsExtracted > 0 {
		session.Items, _ = h.ocrService.GetBatchItems(c.Request.Context(), batchID)
		session.QualityMetrics = h.ocrService.GetQualityMetrics(c.Request.Context(), batchID)
	}

	// Return response with items inside session object for Flutter compatibility
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    session,
	})
}

// DeduplicateItemsRequest represents the request to deduplicate OCR items
type DeduplicateItemsRequest struct {
	SessionIDs []string `json:"session_ids" binding:"required,min=1"`
}

// DeduplicateItems deduplicates items from multiple OCR sessions
// POST /api/sales/ocr/batch/deduplicate
func (h *OCRHandlers) DeduplicateItems(c *gin.Context) {
	var req DeduplicateItemsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	result, err := h.ocrService.DeduplicateItems(c.Request.Context(), req.SessionIDs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to deduplicate items", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":            true,
		"receipt_type":       result.ReceiptType,
		"items":              result.UniqueItems,
		"total_items":        result.TotalItems,
		"duplicates_removed": result.DuplicatesRemoved,
		"raw_texts":          result.RawTexts,
	})
}

// FindBrandMatchesRequest represents the request to find brand matches
type FindBrandMatchesRequest struct {
	BrandText  string `json:"brand_text" binding:"required"`
	MaxResults int    `json:"max_results"`
}

// FindBrandMatches finds brand matches for OCR text using Gemini
// POST /api/sales/ocr/brands/match
func (h *OCRHandlers) FindBrandMatches(c *gin.Context) {
	var req FindBrandMatchesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if req.MaxResults == 0 {
		req.MaxResults = 5
	}

	// Get available brands
	availableBrands, err := h.ocrService.GetAvailableBrands(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get brands", "details": err.Error()})
		return
	}

	brandNames := make([]string, len(availableBrands))
	for i, brand := range availableBrands {
		brandNames[i] = brand.Name
	}

	// Find matches using Gemini
	matches, err := h.ocrService.GeminiClient().FindBrandMatches(c.Request.Context(), req.BrandText, brandNames)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to find matches", "details": err.Error()})
		return
	}

	// Convert to suggestions
	suggestions := make([]models.BrandMatchSuggestion, 0, len(matches))
	for _, match := range matches {
		// Find brand ID
		var brandID string
		for _, brand := range availableBrands {
			if brand.Name == match.BrandName {
				brandID = brand.ID
				break
			}
		}

		suggestion := models.BrandMatchSuggestion{
			BrandID:       brandID,
			BrandName:     match.BrandName,
			Confidence:    match.Confidence,
			MatchStrategy: "gemini_smart",
			Reasoning:     match.Reasoning,
		}
		suggestions = append(suggestions, suggestion)
	}

	// Limit results
	if len(suggestions) > req.MaxResults {
		suggestions = suggestions[:req.MaxResults]
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    suggestions,
	})
}

// CreateBrandRequest represents the request to auto-create a brand
type CreateBrandRequest struct {
	BrandText   string `json:"brand_text" binding:"required"`
	Description string `json:"description"`
}

// AutoCreateBrand auto-creates a brand from OCR text
// POST /api/sales/ocr/brands/create
func (h *OCRHandlers) AutoCreateBrand(c *gin.Context) {
	var req CreateBrandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	// Get tenant ID from context
	tenantID, _ := c.Get("tenant_id")
	tenantIDStr, ok := tenantID.(string)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Normalize brand name with Gemini
	normalizedName, err := h.ocrService.GeminiClient().NormalizeBrandName(c.Request.Context(), req.BrandText)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand name", "details": err.Error()})
		return
	}

	// Create brand
	brandID, err := h.ocrService.CreateBrand(c.Request.Context(), tenantIDStr, normalizedName, req.Description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create brand", "details": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "Brand created successfully",
		"data":    brandID,
	})
}

// ImportReviewedItemsRequest represents the request to import reviewed OCR items
type ImportReviewedItemsRequest struct {
	BatchID          string         `json:"batch_id" binding:"required"`
	ShopID           string         `json:"shop_id" binding:"required"`
	Items            []models.OCRItem `json:"items" binding:"required"`
	AutoCreateBrands bool           `json:"auto_create_brands"`
}

// ImportReviewedItems imports reviewed OCR items as products
// POST /api/sales/ocr/batch/import
func (h *OCRHandlers) ImportReviewedItems(c *gin.Context) {
	var req ImportReviewedItemsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	// Get tenant ID from context
	tenantID, _ := c.Get("tenant_id")
	tenantIDStr, ok := tenantID.(string)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Import items
	result, err := h.ocrService.ImportItems(c.Request.Context(), tenantIDStr, req.ShopID, req.Items, req.AutoCreateBrands)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to import items", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Items imported successfully",
		"data":    result,
	})
}

// GetOCRMetrics returns real-time OCR performance metrics
// GET /api/sales/ocr/metrics
func (h *OCRHandlers) GetOCRMetrics(c *gin.Context) {
	metrics := services.GetOCRMetrics()
	snapshot := metrics.GetSnapshot()

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "OCR metrics retrieved successfully",
		"data":    snapshot,
	})
}

// ResetOCRMetrics resets all OCR metrics (for testing)
// POST /api/sales/ocr/metrics/reset
func (h *OCRHandlers) ResetOCRMetrics(c *gin.Context) {
	metrics := services.GetOCRMetrics()
	metrics.Reset()

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "OCR metrics reset successfully",
	})
}

// ValidateBatchSession performs comprehensive mathematical and inventory validation
// POST /api/sales/ocr/batch/validate/:id
// Phase 5: Industrial-Grade AI Validation System
func (h *OCRHandlers) ValidateBatchSession(c *gin.Context) {
	batchID := c.Param("id")
	if batchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Batch session ID is required",
		})
		return
	}

	// Get tenant ID from context
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Tenant ID not found in context",
		})
		return
	}

	// Get shop ID (optional, from query param)
	shopID := c.Query("shop_id")

	// Create validation service
	rowValidationService := services.NewRowValidationService(h.ocrService.GetDB())

	// Perform comprehensive validation
	result, err := rowValidationService.ValidateBatchSession(
		context.Background(),
		batchID,
		tenantID.(string),
		shopID,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Validation completed successfully",
		"data":    result,
	})
}

// GetRowValidation validates a single row and returns detailed results
// POST /api/sales/ocr/batch/validate-row
func (h *OCRHandlers) ValidateRow(c *gin.Context) {
	var item models.OCRItem
	if err := c.ShouldBindJSON(&item); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Invalid request body: " + err.Error(),
		})
		return
	}

	// Create validation service
	rowValidationService := services.NewRowValidationService(h.ocrService.GetDB())

	// Validate the row
	result := rowValidationService.ValidateRow(item)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// ValidateBatchComprehensive performs comprehensive OCR validation with suggestions
// POST /api/sales/ocr/batch/validate-comprehensive/:id
// Request body: { "expected_total": 93100 }
func (h *OCRHandlers) ValidateBatchComprehensive(c *gin.Context) {
	batchID := c.Param("id")
	if batchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"success": false,
			"error":   "Batch session ID is required",
		})
		return
	}

	// Parse expected total from request body
	var req struct {
		ExpectedTotal float64 `json:"expected_total"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		// If no body provided, use 0 as expected total
		req.ExpectedTotal = 0
	}

	// Perform comprehensive validation
	result, err := h.ocrService.ValidateBatchOCR(c.Request.Context(), batchID, req.ExpectedTotal)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Comprehensive validation completed",
		"data":    result,
	})
}

// GetAccuracyDashboard returns the OCR accuracy dashboard with all field metrics
// GET /api/sales/ocr/accuracy/dashboard
func (h *OCRHandlers) GetAccuracyDashboard(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "Tenant ID not found in context",
		})
		return
	}

	// Query the accuracy dashboard view
	var dashboard struct {
		TenantID           string   `json:"tenant_id"`
		AvgBrandAccuracy   *float64 `json:"avg_brand_accuracy"`
		AvgQuantityAccuracy *float64 `json:"avg_quantity_accuracy"`
		AvgPriceAccuracy   *float64 `json:"avg_price_accuracy"`
		AvgOpeningAccuracy *float64 `json:"avg_opening_accuracy"`
		AvgReceiptAccuracy *float64 `json:"avg_receipt_accuracy"`
		AvgTotalAccuracy   *float64 `json:"avg_total_accuracy"`
		AvgSaleAccuracy    *float64 `json:"avg_sale_accuracy"`
		AvgRateAccuracy    *float64 `json:"avg_rate_accuracy"`
		AvgAmountAccuracy  *float64 `json:"avg_amount_accuracy"`
		AvgClosingAccuracy *float64 `json:"avg_closing_accuracy"`
		AvgRowAccuracy     *float64 `json:"avg_row_accuracy"`
		AvgMathAccuracy    *float64 `json:"avg_math_accuracy"`
		TotalCorrections   int      `json:"total_corrections"`
		TotalMathChecks    int      `json:"total_math_checks"`
		PassedMathChecks   int      `json:"passed_math_checks"`
		FailedMathChecks   int      `json:"failed_math_checks"`
		MathPassRate       float64  `json:"math_pass_rate"`
		OverallAccuracy    float64  `json:"overall_accuracy"`
	}

	if err := h.ocrService.GetDB().Table("ocr_accuracy_dashboard").
		Where("tenant_id = ?", tenantID).
		First(&dashboard).Error; err != nil {
		// If view doesn't exist or no data, return empty dashboard
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": "No accuracy data available yet",
			"data": gin.H{
				"tenant_id":           tenantID,
				"overall_accuracy":    0,
				"field_accuracies":    gin.H{},
				"math_validation":     gin.H{"pass_rate": 0, "total_checks": 0},
				"total_corrections":   0,
			},
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"tenant_id":         dashboard.TenantID,
			"overall_accuracy":  dashboard.OverallAccuracy,
			"field_accuracies": gin.H{
				"brand":    dashboard.AvgBrandAccuracy,
				"quantity": dashboard.AvgQuantityAccuracy,
				"price":    dashboard.AvgPriceAccuracy,
				"opening":  dashboard.AvgOpeningAccuracy,
				"receipt":  dashboard.AvgReceiptAccuracy,
				"total":    dashboard.AvgTotalAccuracy,
				"sale":     dashboard.AvgSaleAccuracy,
				"rate":     dashboard.AvgRateAccuracy,
				"amount":   dashboard.AvgAmountAccuracy,
				"closing":  dashboard.AvgClosingAccuracy,
				"row":      dashboard.AvgRowAccuracy,
			},
			"math_validation": gin.H{
				"pass_rate":      dashboard.MathPassRate,
				"total_checks":   dashboard.TotalMathChecks,
				"passed_checks":  dashboard.PassedMathChecks,
				"failed_checks":  dashboard.FailedMathChecks,
			},
			"total_corrections": dashboard.TotalCorrections,
		},
	})
}
