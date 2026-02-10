package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"
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

	var shopID, sessionType string
	var base64Images []string

	// Check if JSON request or multipart form
	if strings.Contains(contentType, "application/json") {
		// Parse JSON request with base64 encoded images
		var req CreateBatchSessionRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON request", "details": err.Error()})
			return
		}
		shopID = req.ShopID
		sessionType = req.SessionType

		// Handle flexible images format
		if len(req.Images) > 0 {
			// Try parsing as array of strings first
			var stringImages []string
			if err := json.Unmarshal(req.Images, &stringImages); err == nil {
				base64Images = stringImages
			} else {
				// Try parsing as array of generic maps to see actual field names
				var genericImages []map[string]interface{}
				if err := json.Unmarshal(req.Images, &genericImages); err == nil {
					for _, imgMap := range genericImages {
						// Log the field names
						var fields []string
						for k := range imgMap {
							fields = append(fields, k)
						}

						// Try to extract base64 from any field that might contain it
						var b64 string
						for _, key := range []string{"data", "base64", "content", "imageData", "image", "bytes", "encoded", "value"} {
							if val, ok := imgMap[key]; ok {
								if strVal, ok := val.(string); ok && len(strVal) > 100 {
									b64 = strVal
									break
								}
							}
						}

						if b64 != "" {
							base64Images = append(base64Images, b64)
						} else {
							// If no standard field found, try the first string field that looks like base64
							for _, v := range imgMap {
								if strVal, ok := v.(string); ok && len(strVal) > 1000 {
									b64 = strVal
									base64Images = append(base64Images, b64)
									break
								}
							}
							if b64 == "" {
							}
						}
					}
				} else {
					// Try parsing as a single object
					var singleObj ImageObject
					if err := json.Unmarshal(req.Images, &singleObj); err == nil {
						b64 := singleObj.GetBase64()
						if b64 != "" {
							base64Images = []string{b64}
						}
					} else {
						// Log first 200 chars to see what format it is
						preview := string(req.Images)
						if len(preview) > 200 {
							preview = preview[:200]
						}
					}
				}
			}
		}

		// Fallback to single "image" field
		if len(base64Images) == 0 && req.Image != "" {
			base64Images = []string{req.Image}
		}
	} else {
		// Parse multipart form
		if err := c.Request.ParseMultipartForm(50 << 20); err != nil { // 50MB max
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse multipart form", "details": err.Error()})
			return
		}

		// Get form values
		shopID = c.PostForm("shop_id")
		sessionType = c.PostForm("session_type")

		// Get uploaded files
		form, _ := c.MultipartForm()
		files := form.File["images"]

		if len(files) == 0 {
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id and session_type are required"})
		return
	}

	if len(base64Images) == 0 {
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

// ============================================================================
// Smart Sale Processing (AI-assisted sale creation from images)
// ============================================================================

// SmartSaleProcessRequest represents the request to process images for smart sale
type SmartSaleProcessRequest struct {
	ShopID   string          `json:"shop_id" binding:"required"`
	ShopName string          `json:"shop_name"`
	Date     string          `json:"date" binding:"required"` // YYYY-MM-DD
	Category string          `json:"category"`                // e.g., "non_beer", "beer"
	Size     string          `json:"size"`                    // e.g., "375ML"
	Images   json.RawMessage `json:"images" binding:"required"`
}

// SmartSaleExtractedItem represents an extracted item from AI processing
// Contains both OCR-extracted values and Database values for comparison
type SmartSaleExtractedItem struct {
	ProductID        string   `json:"product_id"`
	BrandName        string   `json:"brand_name"`
	Size             string   `json:"size"`
	Category         string   `json:"category"`
	SerialNumber     int      `json:"serial_number"`

	// ===== FINAL VALUES (used for sale) =====
	Quantity         int      `json:"quantity"`          // Sale quantity (from OCR)
	Rate             float64  `json:"rate"`              // Final rate used (OCR or DB fallback)
	Amount           float64  `json:"amount"`            // Final amount (quantity × rate)
	OpeningStock     int      `json:"opening_stock"`     // Final opening (from OCR)
	Receipt          int      `json:"receipt"`           // Final receipt (from OCR)
	Total            int      `json:"total"`             // Final total (opening + receipt)
	ClosingStock     int      `json:"closing_stock"`     // Final closing (total - sale)

	// ===== OCR EXTRACTED VALUES (from image) =====
	OCRRate          float64  `json:"ocr_rate"`          // Rate extracted from image
	OCRAmount        float64  `json:"ocr_amount"`        // Amount extracted from image
	OCROpening       int      `json:"ocr_opening"`       // Opening stock from image
	OCRReceipt       int      `json:"ocr_receipt"`       // Receipt from image
	OCRTotal         int      `json:"ocr_total"`         // Total from image
	OCRClosing       int      `json:"ocr_closing"`       // Closing from image

	// ===== DATABASE VALUES (from inventory) =====
	DBStock          int      `json:"db_stock"`          // Current stock in database
	DBRate           float64  `json:"db_rate"`           // MRP/Rate from products table
	InventoryRate    float64  `json:"inventory_rate"`    // Alias for db_rate (backward compat)

	// ===== DISCREPANCY DETECTION =====
	HasDiscrepancy       bool              `json:"has_discrepancy"`        // True if any value differs
	Discrepancies        []DiscrepancyInfo `json:"discrepancies"`          // List of all discrepancies
	StockDiscrepancy     int               `json:"stock_discrepancy"`      // DB stock - OCR opening
	RateDiscrepancy      float64           `json:"rate_discrepancy"`       // DB rate - OCR rate
	RateSource           string            `json:"rate_source"`            // "ocr", "database", "calculated"

	// ===== VALIDATION =====
	IsValid          bool     `json:"is_valid"`
	ValidationStatus string   `json:"validation_status"` // "matched", "unmatched", "partial"
	Confidence       float64  `json:"confidence"`
	Warnings         []string `json:"warnings"`
	Errors           []string `json:"errors"`
	ExpectedAmount   float64  `json:"expected_amount,omitempty"`
}

// DiscrepancyInfo represents a single discrepancy between OCR and DB values
type DiscrepancyInfo struct {
	Field       string      `json:"field"`        // "rate", "opening_stock", "amount", etc.
	OCRValue    interface{} `json:"ocr_value"`    // Value from image
	DBValue     interface{} `json:"db_value"`     // Value from database
	Difference  interface{} `json:"difference"`   // DBValue - OCRValue
	Severity    string      `json:"severity"`     // "critical", "warning", "info"
	Message     string      `json:"message"`      // Human-readable description
}

// ProcessSmartSale processes images for smart sale using AI extraction
// POST /api/sales/smart-sale/process
// Supports both multipart/form-data (from Flutter) and JSON requests
func (h *OCRHandlers) ProcessSmartSale(c *gin.Context) {

	// Get tenant and user from context
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantIDStr := tenantID.(string)

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}
	userIDStr := userID.(string)

	var shopID, shopName, date, category, size string
	var base64Images []string

	// Check content type to determine parsing method
	contentType := c.ContentType()
	if strings.Contains(contentType, "multipart/form-data") {
		// Parse multipart form data (from Flutter app)

		shopID = c.PostForm("shop_id")
		shopName = c.PostForm("shop_name")
		date = c.PostForm("date")
		category = c.PostForm("category")
		size = c.PostForm("size")

		// Validate required fields
		if shopID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
			return
		}
		if date == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "date is required"})
			return
		}

		// Parse multipart files
		form, err := c.MultipartForm()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form data: " + err.Error()})
			return
		}

		// Try multiple possible field names for images
		var files []*multipart.FileHeader
		for _, key := range []string{"images", "images[]", "image", "files", "files[]"} {
			if f, ok := form.File[key]; ok && len(f) > 0 {
				files = f
				break
			}
		}

		if len(files) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No images provided"})
			return
		}


		// Convert files to base64
		for _, fileHeader := range files {
			file, err := fileHeader.Open()
			if err != nil {
				continue
			}
			defer file.Close()

			imageBytes, err := io.ReadAll(file)
			if err != nil {
				continue
			}

			base64Str := base64.StdEncoding.EncodeToString(imageBytes)
			base64Images = append(base64Images, base64Str)
		}
	} else {
		// Parse JSON request with flexible field name support (snake_case and camelCase)

		// Parse into a flexible map first to support both camelCase and snake_case
		var rawRequest map[string]json.RawMessage
		if err := c.ShouldBindJSON(&rawRequest); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request: " + err.Error()})
			return
		}

		// Helper function to get string value from multiple possible keys
		getStringField := func(keys ...string) string {
			for _, key := range keys {
				if raw, ok := rawRequest[key]; ok {
					var val string
					if json.Unmarshal(raw, &val) == nil {
						return val
					}
				}
			}
			return ""
		}

		// Extract fields with multiple possible names (snake_case, camelCase)
		shopID = getStringField("shop_id", "shopId", "shop")
		shopName = getStringField("shop_name", "shopName")
		date = getStringField("date", "recordDate", "record_date")
		category = getStringField("category", "categoryName", "category_name")
		size = getStringField("size", "sizeML", "size_ml")


		// Parse images from multiple possible field names
		var imagesRaw json.RawMessage
		for _, key := range []string{"images", "imageList", "image_list"} {
			if raw, ok := rawRequest[key]; ok {
				imagesRaw = raw
				break
			}
		}

		if len(imagesRaw) > 0 {
			// Try parsing as array of strings first
			var stringImages []string
			if err := json.Unmarshal(imagesRaw, &stringImages); err == nil {
				base64Images = stringImages
			} else {
				// Try parsing as array of objects
				var imageObjects []map[string]interface{}
				if err := json.Unmarshal(imagesRaw, &imageObjects); err == nil {
					for _, imgObj := range imageObjects {
						for _, key := range []string{"data", "base64", "content", "imageData", "image", "bytes"} {
							if val, ok := imgObj[key]; ok {
								if strVal, ok := val.(string); ok && len(strVal) > 100 {
									base64Images = append(base64Images, strVal)
									break
								}
							}
						}
					}
				}
			}
		}
	}


	if len(base64Images) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No valid images provided"})
		return
	}

	// category parsed for future use
	_ = category

	// Create batch session for OCR processing
	session, err := h.ocrService.CreateBatchSession(
		c.Request.Context(),
		tenantIDStr,
		userIDStr,
		shopID,
		"smart_sale",
		len(base64Images),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create processing session"})
		return
	}

	// Process images synchronously for smart sale (need immediate results)
	err = h.ocrService.ProcessImageBatch(c.Request.Context(), session.ID, base64Images)
	if err != nil {
		// Continue even with errors - we might have partial results
	}

	// Get the processed session with items
	session, err = h.ocrService.GetBatchSession(c.Request.Context(), session.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get processing results"})
		return
	}

	// Get extracted items
	ocrItems, _ := h.ocrService.GetBatchItems(c.Request.Context(), session.ID)

	// ===== FETCH INVENTORY DATA FOR MATCHED BRANDS =====
	// Build list of matched brand IDs (note: MatchedBrandID contains brand_id, not product id)
	var matchedBrandIDs []string
	for _, item := range ocrItems {
		if item.MatchedBrandID != nil && *item.MatchedBrandID != "" {
			matchedBrandIDs = append(matchedBrandIDs, *item.MatchedBrandID)
		}
	}

	// Maps to store inventory data keyed by brand_id+size for accurate matching
	// brandSizeKey = brandID + "_" + normalizedSize (e.g., "uuid_375ML")
	productRates := make(map[string]float64)   // brandSizeKey -> MRP/SellingPrice
	productStocks := make(map[string]int)      // brandSizeKey -> current stock quantity
	productIDMap := make(map[string]string)    // brandSizeKey -> actual product ID

	if len(matchedBrandIDs) > 0 {
		db := h.ocrService.GetDB()

		// Query products table by brand_id (not id!) to get MRP/SellingPrice
		type ProductInfo struct {
			ID           string  `gorm:"column:id"`
			BrandID      string  `gorm:"column:brand_id"`
			Size         string  `gorm:"column:size"`
			MRP          float64 `gorm:"column:mrp"`
			SellingPrice float64 `gorm:"column:selling_price"`
		}
		var products []ProductInfo
		if err := db.Table("products").
			Select("id, brand_id, size, mrp, selling_price").
			Where("brand_id IN ? AND tenant_id = ?", matchedBrandIDs, tenantIDStr).
			Find(&products).Error; err == nil {

			// Collect actual product IDs for stock query
			var actualProductIDs []string
			for _, p := range products {
				// Create composite key: brandID_size for accurate matching
				normalizedSize := strings.ToUpper(strings.TrimSpace(p.Size))
				brandSizeKey := p.BrandID + "_" + normalizedSize

				// Prefer MRP, fallback to SellingPrice
				rate := p.MRP
				if rate == 0 {
					rate = p.SellingPrice
				}
				productRates[brandSizeKey] = rate
				productIDMap[brandSizeKey] = p.ID
				actualProductIDs = append(actualProductIDs, p.ID)

			}

			// Query stocks table for current stock in this shop using actual product IDs
			if len(actualProductIDs) > 0 {
				type StockInfo struct {
					ProductID string `gorm:"column:product_id"`
					Quantity  int    `gorm:"column:quantity"`
				}
				var stocks []StockInfo
				if err := db.Table("stocks").
					Select("product_id, quantity").
					Where("product_id IN ? AND shop_id = ?", actualProductIDs, shopID).
					Find(&stocks).Error; err == nil {
					// Create productID -> quantity map first
					stockByProductID := make(map[string]int)
					for _, s := range stocks {
						stockByProductID[s.ProductID] = s.Quantity
					}
					// Then map back to brandSizeKey
					for brandSizeKey, productID := range productIDMap {
						if qty, ok := stockByProductID[productID]; ok {
							productStocks[brandSizeKey] = qty
						}
					}
				} else {
				}
			}
		} else {
		}
	}

	// Convert OCR items to SmartSaleExtractedItems with inventory validation
	var extractedItems []SmartSaleExtractedItem
	var totalAmount float64
	var validCount, invalidCount, discrepancyCount int

	for i, item := range ocrItems {
		// Safely dereference pointer fields
		brandID := ""
		if item.MatchedBrandID != nil {
			brandID = *item.MatchedBrandID
		}
		confidence := 0.0
		if item.MatchConfidence != nil {
			confidence = *item.MatchConfidence
		}

		// Create brandSizeKey for lookup (brandID + normalized size)
		normalizedSize := strings.ToUpper(strings.TrimSpace(item.SizeText))
		if normalizedSize == "" {
			normalizedSize = strings.ToUpper(strings.TrimSpace(size)) // Use request size as fallback
		}
		brandSizeKey := brandID + "_" + normalizedSize
		actualProductID := productIDMap[brandSizeKey]

		// Get inventory data for this product using composite key
		dbRate := productRates[brandSizeKey]
		dbStock := productStocks[brandSizeKey]

		// Log lookup for debugging
		if brandID != "" {
		}

		// ===== STORE OCR EXTRACTED VALUES =====
		ocrRate := item.Rate
		ocrAmount := item.Amount
		ocrOpening := item.OpeningStock
		ocrReceipt := item.ReceiptQty
		ocrTotal := item.TotalStock
		ocrClosing := item.ClosingStock

		// ===== DETERMINE FINAL VALUES =====
		// Rate: prefer DB rate when available, fallback to OCR only if DB is missing
		// This ensures accurate pricing from the product database
		effectiveRate := ocrRate
		rateSource := "ocr"

		if dbRate > 0 {
			// Always prefer database rate when available (it's the authoritative source)
			if ocrRate > 0 && ocrRate != dbRate {
				// Calculate percentage difference
				rateDiffPercent := 0.0
				if dbRate > 0 {
					rateDiffPercent = (dbRate - ocrRate) / dbRate * 100
				}
				if rateDiffPercent > 20 || rateDiffPercent < -20 {
					// Large discrepancy - use DB rate
					effectiveRate = dbRate
					rateSource = "database_override"
				} else {
					// Small discrepancy - still use DB rate for consistency
					effectiveRate = dbRate
					rateSource = "database"
				}
			} else if ocrRate == 0 {
				effectiveRate = dbRate
				rateSource = "database"
			} else {
				// OCR and DB rates match
				effectiveRate = dbRate
				rateSource = "database"
			}
		} else if ocrRate == 0 {
			rateSource = "missing"
		}

		// Calculate total stock: opening + receipt
		totalStock := ocrTotal
		if totalStock == 0 {
			totalStock = ocrOpening + ocrReceipt
		}

		// Calculate amount: quantity × rate
		// Always recalculate amount using effective rate for consistency
		amount := ocrAmount
		if item.SaleQuantity > 0 && effectiveRate > 0 {
			calculatedAmount := float64(item.SaleQuantity) * effectiveRate
			// Use calculated amount if OCR amount is missing OR if we're using DB rate (for consistency)
			if amount == 0 || rateSource == "database_override" || rateSource == "database" {
				if amount != calculatedAmount && amount > 0 {
				}
				amount = calculatedAmount
			}
		}

		// Calculate closing stock: total - sale
		closingStock := ocrClosing
		if closingStock == 0 && totalStock > 0 {
			closingStock = totalStock - item.SaleQuantity
		}

		// ===== DISCREPANCY DETECTION =====
		var discrepancies []DiscrepancyInfo
		hasDiscrepancy := false

		// Stock discrepancy: compare OCR opening with DB current stock
		stockDiff := 0
		if dbStock > 0 && ocrOpening > 0 {
			stockDiff = dbStock - ocrOpening
			if stockDiff != 0 {
				hasDiscrepancy = true
				severity := "warning"
				if abs(stockDiff) > 10 {
					severity = "critical"
				}
				discrepancies = append(discrepancies, DiscrepancyInfo{
					Field:      "opening_stock",
					OCRValue:   ocrOpening,
					DBValue:    dbStock,
					Difference: stockDiff,
					Severity:   severity,
					Message:    fmt.Sprintf("Opening stock from image (%d) differs from database stock (%d) by %d units", ocrOpening, dbStock, stockDiff),
				})
			}
		}

		// Rate discrepancy: compare OCR rate with DB rate
		rateDiff := 0.0
		if dbRate > 0 && ocrRate > 0 {
			rateDiff = dbRate - ocrRate
			if rateDiff != 0 {
				hasDiscrepancy = true
				severity := "warning"
				percentDiff := (rateDiff / dbRate) * 100
				if percentDiff > 10 || percentDiff < -10 {
					severity = "critical"
				}
				discrepancies = append(discrepancies, DiscrepancyInfo{
					Field:      "rate",
					OCRValue:   ocrRate,
					DBValue:    dbRate,
					Difference: rateDiff,
					Severity:   severity,
					Message:    fmt.Sprintf("Rate from image (₹%.2f) differs from database MRP (₹%.2f) by ₹%.2f", ocrRate, dbRate, rateDiff),
				})
			}
		}

		// Amount discrepancy: check if OCR amount matches calculated amount
		if ocrAmount > 0 && effectiveRate > 0 && item.SaleQuantity > 0 {
			calculatedAmount := float64(item.SaleQuantity) * effectiveRate
			amountDiff := ocrAmount - calculatedAmount
			if absFloat64(amountDiff) > 1 { // Allow ₹1 tolerance
				hasDiscrepancy = true
				discrepancies = append(discrepancies, DiscrepancyInfo{
					Field:      "amount",
					OCRValue:   ocrAmount,
					DBValue:    calculatedAmount,
					Difference: amountDiff,
					Severity:   "warning",
					Message:    fmt.Sprintf("Amount from image (₹%.2f) differs from calculated (₹%.2f = %d × ₹%.2f)", ocrAmount, calculatedAmount, item.SaleQuantity, effectiveRate),
				})
			}
		}

		// Total stock discrepancy: check math (opening + receipt = total)
		if ocrTotal > 0 && ocrOpening >= 0 && ocrReceipt >= 0 {
			expectedTotal := ocrOpening + ocrReceipt
			if ocrTotal != expectedTotal {
				hasDiscrepancy = true
				discrepancies = append(discrepancies, DiscrepancyInfo{
					Field:      "total_stock",
					OCRValue:   ocrTotal,
					DBValue:    expectedTotal,
					Difference: ocrTotal - expectedTotal,
					Severity:   "warning",
					Message:    fmt.Sprintf("Total from image (%d) doesn't match opening+receipt (%d+%d=%d)", ocrTotal, ocrOpening, ocrReceipt, expectedTotal),
				})
			}
		}

		// Closing stock discrepancy: check math (total - sale = closing)
		if ocrClosing > 0 && totalStock > 0 && item.SaleQuantity >= 0 {
			expectedClosing := totalStock - item.SaleQuantity
			if ocrClosing != expectedClosing {
				hasDiscrepancy = true
				discrepancies = append(discrepancies, DiscrepancyInfo{
					Field:      "closing_stock",
					OCRValue:   ocrClosing,
					DBValue:    expectedClosing,
					Difference: ocrClosing - expectedClosing,
					Severity:   "warning",
					Message:    fmt.Sprintf("Closing from image (%d) doesn't match total-sale (%d-%d=%d)", ocrClosing, totalStock, item.SaleQuantity, expectedClosing),
				})
			}
		}

		if hasDiscrepancy {
			discrepancyCount++
		}

		// ===== BUILD EXTRACTED ITEM =====
		// Use actual product ID if found, fallback to brand ID for display
		displayProductID := actualProductID
		if displayProductID == "" {
			displayProductID = brandID // Fallback for unmatched cases
		}

		extracted := SmartSaleExtractedItem{
			ProductID:    displayProductID,
			BrandName:    item.BrandText,
			Size:         item.SizeText,
			Category:     item.InferredCategoryName,
			SerialNumber: i + 1,

			// Final values
			Quantity:     item.SaleQuantity,
			Rate:         effectiveRate,
			Amount:       amount,
			OpeningStock: ocrOpening,
			Receipt:      ocrReceipt,
			Total:        totalStock,
			ClosingStock: closingStock,

			// OCR extracted values (from image)
			OCRRate:    ocrRate,
			OCRAmount:  ocrAmount,
			OCROpening: ocrOpening,
			OCRReceipt: ocrReceipt,
			OCRTotal:   ocrTotal,
			OCRClosing: ocrClosing,

			// Database values (from inventory)
			DBStock:       dbStock,
			DBRate:        dbRate,
			InventoryRate: dbRate, // Backward compatibility

			// Discrepancy info
			HasDiscrepancy:   hasDiscrepancy,
			Discrepancies:    discrepancies,
			StockDiscrepancy: stockDiff,
			RateDiscrepancy:  rateDiff,
			RateSource:       rateSource,

			// Validation - matched if we found actual product ID in DB
			IsValid:          actualProductID != "",
			ValidationStatus: "unmatched",
			Confidence:       confidence,
			Warnings:         []string{},
			Errors:           []string{},
			ExpectedAmount:   amount,
		}

		// Add warnings based on issues
		if rateSource == "database" {
			extracted.Warnings = append(extracted.Warnings, "Rate from database (OCR could not extract from image)")
		}
		if rateSource == "missing" {
			extracted.Errors = append(extracted.Errors, "Rate missing - could not extract from image or find in database")
		}
		if rateSource == "calculated" {
			extracted.Warnings = append(extracted.Warnings, "Amount calculated using database rate")
		}

		// Set validation status - use actualProductID (from DB lookup) for true match
		if actualProductID != "" {
			extracted.ValidationStatus = "matched"
			extracted.IsValid = true
			validCount++
		} else if brandID != "" {
			// Brand was matched but product not found (size mismatch?)
			extracted.ValidationStatus = "partial"
			extracted.Warnings = append(extracted.Warnings, "Brand matched but product not found for size "+normalizedSize)
			invalidCount++
		} else if item.BrandText != "" {
			extracted.ValidationStatus = "partial"
			invalidCount++
		} else {
			extracted.ValidationStatus = "unmatched"
			invalidCount++
		}

		totalAmount += extracted.Amount
		extractedItems = append(extractedItems, extracted)

		// Log discrepancies for debugging
		_ = hasDiscrepancy
	}

	// Helper function for absolute value

	// Determine overall status
	status := "success"
	message := fmt.Sprintf("Extracted %d items, %d valid.", len(extractedItems), validCount)
	if invalidCount > 0 {
		status = "partial"
		message = fmt.Sprintf("Extracted %d items, %d valid. Review required.", len(extractedItems), validCount)
	}


	// Build response
	// Convert size to integer (e.g., "375ML" -> 375)
	sizeML := 0
	sizeStr := strings.TrimSuffix(strings.ToUpper(size), "ML")
	if parsed, err := strconv.Atoi(sizeStr); err == nil {
		sizeML = parsed
	}

	c.JSON(http.StatusOK, gin.H{
		"status":             status,
		"message":            message,
		"detected_shop_name": shopName,
		"detected_size":      size,
		"detected_size_ml":   sizeML,
		"extracted_items":    extractedItems,
		"total_amount":       totalAmount,
		"validation": gin.H{
			"shop": shopID != "",
			"date": date != "",
		},
		"processing_details": gin.H{
			"session_id":       session.ID,
			"images_processed": len(base64Images),
			"status":           session.Status,
		},
		"comparison_summary": gin.H{
			"total_items":            len(extractedItems),
			"matched_items":          validCount,
			"unmatched_items":        invalidCount,
			"items_with_discrepancy": discrepancyCount,
			"has_discrepancies":      discrepancyCount > 0,
		},
		"image_urls": []string{}, // Would need to store images to return URLs
	})
}

// Helper functions for discrepancy detection and matching

// abs returns the absolute value of an integer
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// absFloat64 returns the absolute value of a float64
func absFloat64(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

// levenshteinDistance calculates the Levenshtein distance between two strings
// Used for fuzzy brand name matching
func levenshteinDistance(s1, s2 string) int {
	s1 = strings.ToLower(s1)
	s2 = strings.ToLower(s2)

	if len(s1) == 0 {
		return len(s2)
	}
	if len(s2) == 0 {
		return len(s1)
	}
	if s1 == s2 {
		return 0
	}

	// Create distance matrix
	lenS1 := len(s1)
	lenS2 := len(s2)
	matrix := make([][]int, lenS1+1)
	for i := range matrix {
		matrix[i] = make([]int, lenS2+1)
		matrix[i][0] = i
	}
	for j := 0; j <= lenS2; j++ {
		matrix[0][j] = j
	}

	// Fill in the rest of the matrix
	for i := 1; i <= lenS1; i++ {
		for j := 1; j <= lenS2; j++ {
			cost := 1
			if s1[i-1] == s2[j-1] {
				cost = 0
			}
			matrix[i][j] = minInt(
				matrix[i-1][j]+1,      // deletion
				minInt(
					matrix[i][j-1]+1,  // insertion
					matrix[i-1][j-1]+cost, // substitution
				),
			)
		}
	}
	return matrix[lenS1][lenS2]
}

// minInt returns the minimum of two integers
func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// maxInt returns the maximum of two integers
func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// calculateMatchScore calculates a 0-100 match score between two brand names
// Uses Levenshtein distance and various heuristics
func calculateMatchScore(ocrBrand, productName, productBrand string) int {
	ocrLower := strings.ToLower(strings.TrimSpace(ocrBrand))
	productLower := strings.ToLower(strings.TrimSpace(productName))
	brandLower := strings.ToLower(strings.TrimSpace(productBrand))

	if ocrLower == "" || (productLower == "" && brandLower == "") {
		return 0
	}

	// Check for exact match
	if ocrLower == productLower || ocrLower == brandLower {
		return 100
	}

	// Check if OCR brand is contained in product name or vice versa
	if strings.Contains(productLower, ocrLower) {
		return 90
	}
	if strings.Contains(ocrLower, productLower) && len(productLower) > 3 {
		return 85
	}
	if strings.Contains(brandLower, ocrLower) || strings.Contains(ocrLower, brandLower) {
		return 88
	}

	// Calculate Levenshtein distance score
	// Compare with brand name first (if available), then product name
	bestScore := 0

	if brandLower != "" {
		dist := levenshteinDistance(ocrLower, brandLower)
		maxLen := maxInt(len(ocrLower), len(brandLower))
		if maxLen > 0 {
			score := 100 - (dist * 100 / maxLen)
			if score > bestScore {
				bestScore = score
			}
		}
	}

	if productLower != "" {
		// Extract brand portion from product name (first part before size indicator)
		productParts := strings.Split(productLower, " - ")
		productBrandPart := productParts[0]

		dist := levenshteinDistance(ocrLower, productBrandPart)
		maxLen := maxInt(len(ocrLower), len(productBrandPart))
		if maxLen > 0 {
			score := 100 - (dist * 100 / maxLen)
			if score > bestScore {
				bestScore = score
			}
		}
	}

	// Penalize very low scores
	if bestScore < 50 {
		bestScore = bestScore / 2
	}

	return bestScore
}

// ============================================================================
// GPT-5.2 SMART SALE V2 - Uses Latest Model with System Data as Truth
// ============================================================================

// SmartSaleV2Response represents the V2 response with IMAGE values as final
// System values are included for reference and discrepancy detection
type SmartSaleV2Response struct {
	Status            string                    `json:"status"`
	Message           string                    `json:"message"`
	Model             string                    `json:"model"`
	DetectedShopName  string                    `json:"detected_shop_name"`
	DetectedSize      string                    `json:"detected_size"`
	DetectedSizeML    int                       `json:"detected_size_ml"`
	Items             []SmartSaleV2Item         `json:"items"`
	TotalAmount       float64                   `json:"total_amount"`
	Summary           SmartSaleV2Summary        `json:"summary"`
	ProcessingDetails map[string]interface{}    `json:"processing_details"`
}

// SmartSaleV2Item represents an extracted item with system comparison
// IMAGE values are FINAL (user reviews/corrects before submission)
// System values shown for REFERENCE and discrepancy detection
type SmartSaleV2Item struct {
	SerialNumber int     `json:"serial_number"`
	ProductID    string  `json:"product_id"`
	BrandName    string  `json:"brand_name"`
	Size         string  `json:"size"`
	Category     string  `json:"category"`

	// FINAL VALUES (from IMAGE - user can review/correct)
	OpeningStock int     `json:"opening_stock"`   // From SYSTEM
	Receipt      int     `json:"receipt"`         // From IMAGE (new stock received)
	Total        int     `json:"total"`           // Calculated: Opening + Receipt
	Rate         float64 `json:"rate"`            // From SYSTEM
	Quantity     int     `json:"quantity"`        // Sale quantity from IMAGE
	Amount       float64 `json:"amount"`          // Calculated: Quantity × Rate
	ClosingStock int     `json:"closing_stock"`   // Calculated: Total - Sale

	// IMAGE VALUES (for comparison/audit)
	ImageOpening int     `json:"image_opening"`
	ImageReceipt int     `json:"image_receipt"`   // Receipt from IMAGE
	ImageTotal   int     `json:"image_total"`     // Total from IMAGE
	ImageRate    float64 `json:"image_rate"`
	ImageAmount  float64 `json:"image_amount"`
	ImageClosing int     `json:"image_closing"`

	// SYSTEM VALUES (source of truth) - ENHANCED with complete product info
	SystemOpening      int     `json:"system_opening"`       // Available stock from stocks table
	SystemRate         float64 `json:"system_rate"`          // MRP from products table
	SystemProductName  string  `json:"system_product_name"`  // Full product name from inventory
	SystemBrandName    string  `json:"system_brand_name"`    // Brand name from inventory
	SystemSize         string  `json:"system_size"`          // Size from inventory (e.g., "375ML")
	SystemMRP          float64 `json:"system_mrp"`           // MRP from products table
	SystemSellingPrice float64 `json:"system_selling_price"` // Selling price from products table

	// STOCK DATA (from stocks table) - ENHANCED
	SystemStock      int `json:"system_stock"`       // Current available stock
	SystemTotalStock int `json:"system_total_stock"` // Total physical stock (quantity)
	SystemReserved   int `json:"system_reserved"`    // Reserved quantity
	SystemDamaged    int `json:"system_damaged"`     // Damaged quantity

	// BACKWARD COMPATIBILITY ALIASES (for Flutter app)
	DBStock       int     `json:"db_stock"`        // Alias for SystemStock (Flutter expects this)
	DBRate        float64 `json:"db_rate"`         // Alias for SystemRate (Flutter expects this)
	InventoryRate float64 `json:"inventory_rate"`  // Alias for SystemRate (Flutter expects this)

	// DISCREPANCY FLAGS - ENHANCED
	HasDiscrepancy    bool     `json:"has_discrepancy"`
	OpeningMismatch   bool     `json:"opening_mismatch"`
	RateMismatch      bool     `json:"rate_mismatch"`
	SizeMismatch      bool     `json:"size_mismatch"`       // NEW: Does size match
	OpeningDifference int      `json:"opening_difference"`
	RateDifference    float64  `json:"rate_difference"`
	Warnings          []string `json:"warnings"`

	// MATCHING QUALITY - NEW
	NameMatchScore int  `json:"name_match_score"` // 0-100 how well names matched
	SizeMatch      bool `json:"size_match"`       // Does size match exactly

	// VALIDATION
	IsMatched       bool    `json:"is_matched"`
	IsValid         bool    `json:"is_valid"`          // Alias for is_matched (Flutter compatibility)
	Matched         bool    `json:"matched"`           // Alias for is_matched (Flutter compatibility)
	Confidence      float64 `json:"confidence"`
	ValidationNotes string  `json:"validation_notes"`
}

// SmartSaleV2Summary represents the summary of extraction with detailed breakdowns
type SmartSaleV2Summary struct {
	TotalItems           int  `json:"total_items"`
	MatchedItems         int  `json:"matched_items"`
	UnmatchedItems       int  `json:"unmatched_items"`
	ItemsWithDiscrepancy int  `json:"items_with_discrepancy"`

	// Detailed breakdowns - ENHANCED
	OpeningMismatches int `json:"opening_mismatches"`
	RateMismatches    int `json:"rate_mismatches"`
	SizeMismatches    int `json:"size_mismatches"` // NEW

	// Amount totals - ENHANCED
	ImageTotalAmount  float64 `json:"image_total_amount"`  // Sum of all image amounts
	SystemTotalAmount float64 `json:"system_total_amount"` // Calculated using system rates
	AmountDifference  float64 `json:"amount_difference"`   // System - Image

	HasDiscrepancies  bool `json:"has_discrepancies"`
	HasCriticalIssues bool `json:"has_critical_issues"`
}

// ProcessSmartSaleV2 processes images using GPT-5.2 for extraction
// POST /smart-sale/v2/process (also served as default at /smart-sale/process)
// Uses GPT-5.2 exclusively for extraction. IMAGE values are returned as FINAL.
// System values (DB stock, DB rate) shown for REFERENCE and discrepancy detection.
// User reviews and corrects values before submission.
func (h *OCRHandlers) ProcessSmartSaleV2(c *gin.Context) {

	// Get tenant and user from context
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantIDStr := tenantID.(string)

	// Parse request (same as V1)
	var shopID, shopName, date, size string
	var base64Images []string

	contentType := c.ContentType()
	if strings.Contains(contentType, "multipart/form-data") {
		shopID = c.PostForm("shop_id")
		shopName = c.PostForm("shop_name")
		date = c.PostForm("date")
		size = c.PostForm("size")

		form, err := c.MultipartForm()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form data"})
			return
		}

		for _, key := range []string{"images", "images[]", "image", "files"} {
			if files, ok := form.File[key]; ok {
				for _, fh := range files {
					file, _ := fh.Open()
					if file != nil {
						data, _ := io.ReadAll(file)
						base64Images = append(base64Images, base64.StdEncoding.EncodeToString(data))
						file.Close()
					}
				}
				break
			}
		}
	} else {
		// JSON request
		var rawRequest map[string]json.RawMessage
		if err := c.ShouldBindJSON(&rawRequest); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON"})
			return
		}

		getField := func(keys ...string) string {
			for _, key := range keys {
				if raw, ok := rawRequest[key]; ok {
					var val string
					if json.Unmarshal(raw, &val) == nil {
						return val
					}
				}
			}
			return ""
		}

		shopID = getField("shop_id", "shopId")
		shopName = getField("shop_name", "shopName")
		date = getField("date")
		size = getField("size")

		// Parse images
		if imagesRaw, ok := rawRequest["images"]; ok {
			var stringImages []string
			if json.Unmarshal(imagesRaw, &stringImages) == nil {
				base64Images = stringImages
			}
		}
	}

	if shopID == "" || date == "" || len(base64Images) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id, date, and images are required"})
		return
	}


	// Initialize GPT-5.2 client
	gpt52Client := services.NewSmartSaleGPT52Client()
	if gpt52Client == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "GPT-5.2 client not available - check OPENAI_API_KEY"})
		return
	}

	// ===== PROCESS ALL IMAGES (not just the first one) =====
	// Combine results from all uploaded images into one unified result
	var combinedRows []services.SmartSaleExtractedRow
	var detectedSize string
	var totalAmountFromImages float64
	var successfulImages, failedImages int

	for _, imgBase64 := range base64Images {

		imgResult, imgErr := gpt52Client.ExtractReceiptData(c.Request.Context(), imgBase64)
		if imgErr != nil {
			failedImages++
			continue // Continue with other images instead of failing completely
		}

		successfulImages++

		// Use first detected size as the primary size
		if detectedSize == "" && imgResult.Size != "" {
			detectedSize = imgResult.Size
		}

		// Combine rows from all images
		combinedRows = append(combinedRows, imgResult.Rows...)
		totalAmountFromImages += imgResult.TotalAmount
	}

	// Check if any images were processed successfully
	if successfulImages == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "GPT-5.2 extraction failed for all images"})
		return
	}


	// Create a combined result structure
	gpt52Result := &services.SmartSaleGPT52Response{
		Size:        detectedSize,
		Rows:        combinedRows,
		TotalAmount: totalAmountFromImages,
	}

	// Use provided size if no size detected from images
	if detectedSize == "" {
		detectedSize = size
	}

	// Get database for system data lookup
	db := h.ocrService.GetDB()

	// Build list of brand names for matching
	var brandNames []string
	for _, row := range gpt52Result.Rows {
		if row.BrandName != "" {
			brandNames = append(brandNames, row.BrandName)
		}
	}

	// Query products by brand name (fuzzy matching) - ENHANCED
	type ProductInfo struct {
		ID           string  `gorm:"column:id"`
		Name         string  `gorm:"column:name"`
		BrandID      string  `gorm:"column:brand_id"`
		BrandName    string  `gorm:"column:brand_name"` // From brands join
		Size         string  `gorm:"column:size"`
		MRP          float64 `gorm:"column:mrp"`
		SellingPrice float64 `gorm:"column:selling_price"`
		CategoryID   string  `gorm:"column:category_id"`
		CategoryName string  `gorm:"column:category_name"`
		SKU          string  `gorm:"column:sku"`
	}
	var products []ProductInfo

	// 🔧 FIX: Normalize detected size for matching (e.g., "375ML", "375ml", "375")
	normalizedSize := strings.ToUpper(strings.TrimSpace(detectedSize))
	normalizedSize = strings.TrimSuffix(normalizedSize, "ML")
	normalizedSize = strings.TrimSpace(normalizedSize)
	sizePattern := normalizedSize + "ML" // e.g., "375ML"


	if len(brandNames) > 0 {
		// ENHANCED: Join with brands table to get brand name for better matching
		query := db.Table("products").
			Select("products.id, products.name, products.brand_id, products.size, products.mrp, products.selling_price, products.category_id, products.sku, COALESCE(brands.name, '') as brand_name, COALESCE(categories.name, '') as category_name").
			Joins("LEFT JOIN brands ON products.brand_id = brands.id").
			Joins("LEFT JOIN categories ON products.category_id = categories.id").
			Where("products.tenant_id = ?", tenantIDStr)

		// 🔧 FIX: Filter by size if detected (e.g., products containing "375ML")
		if normalizedSize != "" {
			query = query.Where("UPPER(products.size) = ? OR UPPER(products.name) LIKE ?", sizePattern, "%"+sizePattern+"%")
		}

		// Build OR conditions for brand name matching - check both product name and brand name
		orConditions := db.Where("1=0") // Start with false
		for _, name := range brandNames {
			// Clean name and create search pattern
			cleanName := strings.TrimSpace(name)
			if len(cleanName) >= 3 {
				pattern := "%" + strings.ToLower(cleanName) + "%"
				orConditions = orConditions.Or("LOWER(products.name) LIKE ? OR LOWER(brands.name) LIKE ?", pattern, pattern)
			}
		}
		query = query.Where(orConditions)
		query.Find(&products)
	}


	// Create product map for quick lookup
	productMap := make(map[string]ProductInfo)
	for _, p := range products {
		productMap[strings.ToLower(p.Name)] = p
	}

	// Query current stock for shop - ENHANCED with all stock fields
	type StockInfo struct {
		ProductID         string  `gorm:"column:product_id"`
		Quantity          int     `gorm:"column:quantity"`          // Total physical stock
		AvailableQuantity int     `gorm:"column:available_quantity"` // Available for sale
		ReservedQuantity  int     `gorm:"column:reserved_quantity"`  // Reserved
		DamagedQuantity   int     `gorm:"column:damaged_quantity"`   // Damaged
		LastPurchasePrice float64 `gorm:"column:last_purchase_price"` // Last purchase cost
	}
	var stocks []StockInfo
	if len(products) > 0 {
		var productIDs []string
		for _, p := range products {
			productIDs = append(productIDs, p.ID)
		}
		db.Table("stocks").
			Select("product_id, quantity, COALESCE(available_quantity, quantity) as available_quantity, COALESCE(reserved_quantity, 0) as reserved_quantity, COALESCE(damaged_quantity, 0) as damaged_quantity, COALESCE(last_purchase_price, 0) as last_purchase_price").
			Where("shop_id = ? AND product_id IN ?", shopID, productIDs).
			Find(&stocks)
	}

	// Create stock maps - comprehensive stock data per product
	stockMap := make(map[string]int)           // ProductID -> available quantity
	stockTotalMap := make(map[string]int)      // ProductID -> total quantity
	stockReservedMap := make(map[string]int)   // ProductID -> reserved quantity
	stockDamagedMap := make(map[string]int)    // ProductID -> damaged quantity

	for _, s := range stocks {
		// Use available_quantity as primary stock value (accounts for reserved/damaged)
		if s.AvailableQuantity > 0 {
			stockMap[s.ProductID] = s.AvailableQuantity
		} else {
			stockMap[s.ProductID] = s.Quantity
		}
		stockTotalMap[s.ProductID] = s.Quantity
		stockReservedMap[s.ProductID] = s.ReservedQuantity
		stockDamagedMap[s.ProductID] = s.DamagedQuantity
	}

	// Process extracted rows and compare with system - ENHANCED
	var items []SmartSaleV2Item
	var totalAmount float64
	var imageTotalAmount float64   // Sum of all image amounts
	var systemTotalAmount float64  // Sum calculated using system rates
	var matchedCount, unmatchedCount, discrepancyCount int
	var openingMismatches, rateMismatches, sizeMismatches int

	for _, row := range gpt52Result.Rows {
		item := SmartSaleV2Item{
			SerialNumber: row.SerialNumber,
			BrandName:    row.BrandName,
			Size:         row.Size,
			Warnings:     []string{},
			SizeMatch:    true, // Default to true, will be set to false if mismatch detected

			// Image values (all 7 columns from OCR)
			ImageOpening: row.ImageOpening,
			ImageReceipt: row.ImageReceipt,  // New stock received
			ImageTotal:   row.ImageTotal,    // Opening + Receipt
			ImageRate:    row.ImageRate,
			ImageAmount:  row.ImageAmount,
			ImageClosing: row.ImageClosing,
			Confidence:   row.Confidence,
		}

		// Track image amount for summary
		imageTotalAmount += row.ImageAmount

		// Try to match product - ENHANCED with Levenshtein distance
		var matchedProduct *ProductInfo
		var bestMatchScore int

		// Get row-level size or use detected size
		rowSize := strings.ToUpper(strings.TrimSpace(row.Size))
		if rowSize == "" {
			rowSize = sizePattern
		}
		rowSize = strings.TrimSuffix(rowSize, "ML")
		rowSizePattern := rowSize + "ML" // e.g., "375ML"

		// ENHANCED: Use Levenshtein distance for fuzzy matching
		for _, p := range products {
			// Calculate match score using Levenshtein distance
			nameScore := calculateMatchScore(row.BrandName, p.Name, p.BrandName)

			if nameScore < 50 {
				continue // Skip poor matches
			}

			// Calculate total score with size weighting
			totalScore := nameScore

			// Size matching - critical for correct product
			productSize := strings.ToUpper(strings.TrimSpace(p.Size))
			if productSize == "" {
				// Extract size from product name
				if strings.Contains(strings.ToUpper(p.Name), rowSizePattern) {
					totalScore += 30 // Bonus for size match in name
				}
			} else if productSize == rowSizePattern {
				totalScore += 50 // Heavy bonus for exact size match
			} else {
				// Size mismatch - penalize heavily
				totalScore -= 40
			}

			// Update best match if this is better
			if totalScore > bestMatchScore {
				bestMatchScore = totalScore
				pCopy := p // Make a copy to avoid pointer issues
				matchedProduct = &pCopy
			}
		}

		// Store match score
		item.NameMatchScore = bestMatchScore

		if matchedProduct != nil {
			item.ProductID = matchedProduct.ID
			item.Category = matchedProduct.CategoryName
			item.IsMatched = true
			item.IsValid = true   // Alias for Flutter compatibility
			item.Matched = true   // Alias for Flutter compatibility
			matchedCount++

			// ===== POPULATE SYSTEM PRODUCT DATA (ENHANCED) =====
			item.SystemProductName = matchedProduct.Name
			item.SystemBrandName = matchedProduct.BrandName
			item.SystemSize = matchedProduct.Size
			item.SystemMRP = matchedProduct.MRP
			item.SystemSellingPrice = matchedProduct.SellingPrice

			// Get SYSTEM stock values
			item.SystemOpening = stockMap[matchedProduct.ID]
			item.SystemStock = stockMap[matchedProduct.ID]
			item.SystemTotalStock = stockTotalMap[matchedProduct.ID]
			item.SystemReserved = stockReservedMap[matchedProduct.ID]
			item.SystemDamaged = stockDamagedMap[matchedProduct.ID]

			// Get SYSTEM rate (prefer MRP, fallback to selling price)
			item.SystemRate = matchedProduct.MRP
			if item.SystemRate == 0 {
				item.SystemRate = matchedProduct.SellingPrice
			}

			// ===== BACKWARD COMPATIBILITY ALIASES (for Flutter) =====
			item.DBStock = item.SystemStock         // Flutter expects db_stock
			item.DBRate = item.SystemRate           // Flutter expects db_rate
			item.InventoryRate = item.SystemRate    // Flutter expects inventory_rate

			// ===== SIZE MATCH VALIDATION (ENHANCED) =====
			productSize := strings.ToUpper(strings.TrimSpace(matchedProduct.Size))
			imageSize := strings.ToUpper(strings.TrimSpace(row.Size))
			if imageSize == "" {
				imageSize = rowSizePattern
			}
			imageSize = strings.TrimSuffix(imageSize, "ML") + "ML"

			if productSize != "" && productSize != imageSize {
				// Also check if size is in product name
				if !strings.Contains(strings.ToUpper(matchedProduct.Name), imageSize) {
					item.SizeMatch = false
					item.SizeMismatch = true
					item.HasDiscrepancy = true
					sizeMismatches++
					item.Warnings = append(item.Warnings, fmt.Sprintf(
						"⚠️ Size: Image=%s, Product=%s",
						imageSize, productSize,
					))
				}
			}

			// ===== USE IMAGE VALUES AS FINAL VALUES (user will review and fix) =====
			// Image values are the primary data - system values are for reference only
			item.OpeningStock = row.ImageOpening    // IMAGE value (what OCR extracted)
			item.Receipt = row.ImageReceipt         // IMAGE value (new stock received)
			item.Total = row.ImageTotal             // IMAGE value (should be Opening + Receipt)
			if item.Total == 0 {
				item.Total = item.OpeningStock + item.Receipt  // Calculate if not extracted
			}
			item.Rate = row.ImageRate               // IMAGE value (rate from receipt)
			if item.Rate == 0 && item.SystemRate > 0 {
				item.Rate = item.SystemRate         // Fallback to system only if image rate is 0
			}
			item.Quantity = row.ImageSale           // IMAGE value (actual sale)
			item.Amount = float64(item.Quantity) * item.Rate
			// If calculated amount is 0 but OCR extracted an amount, use OCR amount
			if item.Amount == 0 && row.ImageAmount > 0 {
				item.Amount = row.ImageAmount
			}
			item.ClosingStock = row.ImageClosing    // IMAGE value
			if item.ClosingStock == 0 && item.Total > 0 {
				item.ClosingStock = item.Total - item.Quantity  // Calculate if not extracted
			}

			// Calculate system amount for summary
			systemTotalAmount += float64(row.ImageSale) * item.SystemRate

			// ===== CHECK FOR DISCREPANCIES (flag but don't override) =====

			// Opening Stock Mismatch - flag but keep Image value
			if item.SystemOpening > 0 && row.ImageOpening > 0 && row.ImageOpening != item.SystemOpening {
				item.OpeningMismatch = true
				item.HasDiscrepancy = true
				item.OpeningDifference = row.ImageOpening - item.SystemOpening
				openingMismatches++

				severity := "⚠️"
				if abs(item.OpeningDifference) > 10 {
					severity = "🚨"
				}
				item.Warnings = append(item.Warnings, fmt.Sprintf(
					"%s Opening: Image=%d, System=%d (Diff: %+d)",
					severity, row.ImageOpening, item.SystemOpening, item.OpeningDifference,
				))
			}

			// Rate Mismatch - allow 2% tolerance as per plan
			if item.SystemRate > 0 && row.ImageRate > 0 {
				rateDiff := absFloat64(row.ImageRate - item.SystemRate)
				toleranceThreshold := item.SystemRate * 0.02 // 2% tolerance

				if rateDiff > toleranceThreshold {
					item.RateMismatch = true
					item.HasDiscrepancy = true
					item.RateDifference = row.ImageRate - item.SystemRate
					rateMismatches++

					percentDiff := (item.RateDifference / item.SystemRate) * 100
					severity := "⚠️"
					if absFloat64(percentDiff) > 10 {
						severity = "🚨"
					}
					item.Warnings = append(item.Warnings, fmt.Sprintf(
						"%s Rate: Image=₹%.2f, MRP=₹%.2f (Diff: ₹%+.2f)",
						severity, row.ImageRate, item.SystemRate, item.RateDifference,
					))
				}
			}

			if item.HasDiscrepancy {
				discrepancyCount++
			}

			item.ValidationNotes = fmt.Sprintf("✅ Product matched (score: %d) - using Image values (review discrepancies)", item.NameMatchScore)
		} else {
			// No match - use image values with warning
			item.IsMatched = false
			item.IsValid = false   // Alias for Flutter compatibility
			item.Matched = false   // Alias for Flutter compatibility
			item.NameMatchScore = 0 // No match found
			unmatchedCount++
			item.OpeningStock = row.ImageOpening
			item.Receipt = row.ImageReceipt      // Use image receipt
			item.Total = row.ImageTotal          // Use image total (or calculate if 0)
			if item.Total == 0 {
				item.Total = item.OpeningStock + item.Receipt  // Calculate: Opening + Receipt
			}
			item.Rate = row.ImageRate
			item.Quantity = row.ImageSale
			item.Amount = row.ImageAmount
			if item.Amount == 0 && item.Quantity > 0 && item.Rate > 0 {
				item.Amount = float64(item.Quantity) * item.Rate  // Calculate if not provided
			}
			item.ClosingStock = row.ImageClosing
			if item.ClosingStock == 0 && item.Total > 0 {
				item.ClosingStock = item.Total - item.Quantity  // Calculate: Total - Sale
			}
			// For unmatched items, system total amount uses image rate (since no system rate available)
			systemTotalAmount += item.Amount
			item.Warnings = append(item.Warnings, "⚠️ Product not found in database - using image values (needs manual review)")
			item.ValidationNotes = "❌ Product not matched - requires manual selection"
		}

		totalAmount += item.Amount
		items = append(items, item)

		// Log for debugging
		_ = item.HasDiscrepancy
	}

	// Parse size to ML
	sizeML := 0
	sizeStr := strings.TrimSuffix(strings.ToUpper(detectedSize), "ML")
	if parsed, err := strconv.Atoi(strings.TrimSpace(sizeStr)); err == nil {
		sizeML = parsed
	}

	// Build response - Use V1 field names for backward compatibility with Flutter app
	status := "success"
	message := fmt.Sprintf("Extracted %d items using GPT-5.2. %d matched, %d need review.", len(items), matchedCount, unmatchedCount)

	if unmatchedCount > 0 || discrepancyCount > 0 {
		status = "partial"
		message = fmt.Sprintf("⚠️ Extracted %d items. %d matched, %d unmatched, %d with discrepancies. Review required.",
			len(items), matchedCount, unmatchedCount, discrepancyCount)
	}


	// Count is_matched items for debug
	validItemCount := 0
	for _, item := range items {
		if item.IsMatched {
			validItemCount++
		}
	}

	// 🔧 FIX: Use V1-compatible response format with 'extracted_items' for Flutter compatibility
	// Also add multiple field aliases to ensure Flutter can parse correctly
	c.JSON(http.StatusOK, gin.H{
		"status":             status,
		"message":            message,
		"model":              "gpt-5.2",
		"detected_shop_name": shopName,
		"detected_size":      detectedSize,
		"detected_size_ml":   sizeML,
		"extracted_items":    items,  // Use 'extracted_items' not 'items' for Flutter compatibility
		"items":              items,  // Also provide as 'items' in case Flutter uses this
		"total_amount":       totalAmount,

		// ===== FLUTTER COMPATIBILITY: Multiple field name formats =====
		// Validation as nested object
		"validation": gin.H{
			"shop": shopID != "",
			"date": date != "",
		},
		// Validation as top-level booleans (Flutter may use these)
		"shop_validated":  shopID != "",
		"date_validated":  date != "",
		"is_shop_valid":   shopID != "",
		"is_date_valid":   date != "",
		// Item counts at top level for easy access
		"valid_items":     matchedCount,
		"invalid_items":   unmatchedCount,
		"matched_count":   matchedCount,
		"unmatched_count": unmatchedCount,
		"total_items":     len(items),

		"processing_details": gin.H{
			"images_processed": len(base64Images),
			"extraction_model": "gpt-5.2",
			"data_source":      "system_as_truth",
			"shop_id":          shopID,
			"date":             date,
		},
		"comparison_summary": gin.H{
			"total_items":            len(items),
			"matched_items":          matchedCount,
			"unmatched_items":        unmatchedCount,
			"items_with_discrepancy": discrepancyCount,
			// Detailed breakdowns
			"opening_mismatches":     openingMismatches,
			"rate_mismatches":        rateMismatches,
			"size_mismatches":        sizeMismatches,
			// Amount totals
			"image_total_amount":     imageTotalAmount,
			"system_total_amount":    systemTotalAmount,
			"amount_difference":      systemTotalAmount - imageTotalAmount,
			// Flags
			"has_discrepancies":      discrepancyCount > 0,
			"has_critical_issues":    unmatchedCount > 0 || openingMismatches > 5 || rateMismatches > 5,
			// Flutter-friendly aliases
			"valid_items":            matchedCount,
			"invalid_items":          unmatchedCount,
		},
		"image_urls": []string{},
	})
}
