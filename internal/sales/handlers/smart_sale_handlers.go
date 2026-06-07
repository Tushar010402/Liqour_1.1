package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
)

// SmartSaleHandlers handles Smart Sale HTTP requests
type SmartSaleHandlers struct {
	smartSaleService *services.SmartSaleService
	aliasService     *alias.AliasService
	db               *database.DB
	logger           *logrus.Logger
}

// NewSmartSaleHandlers creates a new Smart Sale handlers instance
func NewSmartSaleHandlers(smartSaleService *services.SmartSaleService, aliasService *alias.AliasService, db *database.DB, logger *logrus.Logger) *SmartSaleHandlers {
	return &SmartSaleHandlers{
		smartSaleService: smartSaleService,
		aliasService:     aliasService,
		db:               db,
		logger:           logger,
	}
}

// ProcessSmartSale handles the smart sale image processing endpoint
// @Summary Process Smart Sale
// @Description Upload receipt images to extract and create daily sales entries using AI
// @Tags Smart Sale
// @Accept multipart/form-data
// @Produce json
// @Param images formData file true "Receipt images (max 5)"
// @Param shop_id formData string true "Shop UUID"
// @Param shop_name formData string true "Shop name for validation"
// @Param date formData string true "Sale date (YYYY-MM-DD)"
// @Param category formData string true "Category: beer or non_beer"
// @Param size formData string false "Size filter: 180ML, 375ML, 750ML, etc."
// @Success 200 {object} services.SmartSaleResult
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Router /sales/smart-sale/process [post]
func (h *SmartSaleHandlers) ProcessSmartSale(c *gin.Context) {
	h.logger.Info("📤 SmartSale: Processing request")

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

	userRole, _ := c.Get("role")
	roleStr := ""
	if role, ok := userRole.(string); ok {
		roleStr = role
	}

	// Parse multipart form (50MB max)
	if err := c.Request.ParseMultipartForm(50 << 20); err != nil {
		h.logger.Warnf("SmartSale: Failed to parse multipart form: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse form: %v", err)})
		return
	}

	// Get form fields
	shopIDStr := c.PostForm("shop_id")
	shopName := c.PostForm("shop_name")
	dateStr := c.PostForm("date")
	category := c.PostForm("category")
	size := c.PostForm("size")

	h.logger.Infof("SmartSale: Request params - shop_id=%s, date=%s, category=%s, size=%s",
		shopIDStr, dateStr, category, size)

	// Validate required fields
	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}
	if dateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date is required"})
		return
	}
	if category == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category is required (beer or non_beer)"})
		return
	}

	// Parse shop ID
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id format"})
		return
	}

	// Parse date
	saleDate, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
		return
	}

	// Validate category
	if category != "beer" && category != "non_beer" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category must be 'beer' or 'non_beer'"})
		return
	}

	// Get uploaded images - try multiple field names for compatibility
	form := c.Request.MultipartForm

	// Log all received form file fields for debugging
	h.logger.Infof("SmartSale: Received form file fields: %v", func() []string {
		keys := make([]string, 0, len(form.File))
		for k, v := range form.File {
			keys = append(keys, fmt.Sprintf("%s(%d files)", k, len(v)))
		}
		return keys
	}())

	// Try multiple field names for compatibility with different clients
	var files []*multipart.FileHeader
	for _, fieldName := range []string{"images", "images[]", "image", "image[]", "files", "files[]"} {
		if f := form.File[fieldName]; len(f) > 0 {
			files = append(files, f...)
			h.logger.Infof("SmartSale: Found %d images in field '%s'", len(f), fieldName)
		}
	}

	h.logger.Infof("SmartSale: Total images received: %d", len(files))

	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one image is required"})
		return
	}
	if len(files) > 5 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":           "Maximum 5 images allowed",
			"max_images":      5,
			"provided_images": len(files),
		})
		return
	}

	// Validate and read images
	const maxFileSize = 10 * 1024 * 1024 // 10MB per image
	allowedTypes := map[string]bool{
		"image/jpeg": true,
		"image/jpg":  true,
		"image/png":  true,
	}

	var imageData [][]byte
	for i, fileHeader := range files {
		// Validate file size
		if fileHeader.Size > maxFileSize {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":          "Image size exceeds maximum allowed size",
				"image_index":    i,
				"file_name":      fileHeader.Filename,
				"max_size_mb":    10,
				"actual_size_mb": float64(fileHeader.Size) / (1024 * 1024),
			})
			return
		}

		// Validate content type
		contentType := fileHeader.Header.Get("Content-Type")
		if !allowedTypes[contentType] {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":        "Invalid image format. Only JPEG and PNG allowed",
				"image_index":  i,
				"file_name":    fileHeader.Filename,
				"content_type": contentType,
			})
			return
		}

		// Read file
		file, err := fileHeader.Open()
		if err != nil {
			h.logger.Errorf("SmartSale: Failed to open file %s: %v", fileHeader.Filename, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read image"})
			return
		}
		defer file.Close()

		data, err := io.ReadAll(file)
		if err != nil {
			h.logger.Errorf("SmartSale: Failed to read file %s: %v", fileHeader.Filename, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read image data"})
			return
		}

		imageData = append(imageData, data)
		h.logger.Debugf("SmartSale: Processed image %d: %s (%.2f KB)",
			i+1, fileHeader.Filename, float64(fileHeader.Size)/1024)
	}

	// v1.0.178 — defense-in-depth severe-quality reject. The Flutter preflight
	// already gates this client-side, but a stale APK could bypass it. Skip
	// when the operator explicitly opted into "use anyway" via override flags
	// (form field "quality_override_indices" — comma-separated 0-based image
	// indices). cv-sidecar disabled / unreachable fails open.
	if cv := h.smartSaleService.CVSidecar(); cv != nil && os.Getenv("SMART_SALE_QUALITY_GATE") != "0" {
		overrideSet := map[int]bool{}
		for _, raw := range strings.Split(c.PostForm("quality_override_indices"), ",") {
			raw = strings.TrimSpace(raw)
			if raw == "" {
				continue
			}
			var idx int
			if _, err := fmt.Sscanf(raw, "%d", &idx); err == nil {
				overrideSet[idx] = true
			}
		}
		for idx, data := range imageData {
			if overrideSet[idx] {
				continue
			}
			res := cv.QualityCheck(c.Request.Context(), data)
			if res != nil && res.Severe {
				h.logger.Warnf("SmartSale: severe-quality reject image %d issues=%v score=%.1f",
					idx, res.SevereIssues, res.Score)
				c.JSON(http.StatusUnprocessableEntity, gin.H{
					"error":          "image_quality_severe",
					"message":        "One or more photos are too unclear to extract reliably. Please retake.",
					"image_index":    idx,
					"severe_issues":  res.SevereIssues,
					"issues":         res.Issues,
					"score":          res.Score,
				})
				return
			}
		}
	}

	// Parse UUIDs
	var userUUID, tenantUUID uuid.UUID
	if userIDStr, ok := userID.(string); ok {
		userUUID, err = uuid.Parse(userIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
			return
		}
	} else if uid, ok := userID.(uuid.UUID); ok {
		userUUID = uid
	}

	if tenantIDStr, ok := tenantID.(string); ok {
		tenantUUID, err = uuid.Parse(tenantIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
			return
		}
	} else if tid, ok := tenantID.(uuid.UUID); ok {
		tenantUUID = tid
	}

	// Create request
	req := &services.SmartSaleRequest{
		ShopID:    shopID,
		ShopName:  shopName,
		SaleDate:  saleDate,
		Category:  category,
		Size:      size,
		ImageData: imageData,
	}

	// Process smart sale
	result, err := h.smartSaleService.ProcessSmartSale(
		c.Request.Context(),
		req,
		userUUID,
		tenantUUID,
		roleStr,
	)
	if err != nil {
		h.logger.Errorf("SmartSale: Processing failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to process smart sale"})
		return
	}

	h.logger.Infof("SmartSale: Completed - Status: %s, Items: %d",
		result.Status, len(result.ExtractedItems))

	c.JSON(http.StatusOK, result)
}

// PreflightQualityCheck handles POST /api/sales/smart-sale/preflight/quality-check
// — v1.0.178 image-quality preflight. Flutter calls this before /process so
// blurry/tilted photos hit the modal instead of the AI bill. Single image
// per call (multipart "file" field). cv-sidecar disabled / unreachable
// returns an optimistic OK so we never block uploads on infra blips.
func (h *SmartSaleHandlers) PreflightQualityCheck(c *gin.Context) {
	if _, exists := c.Get("user_id"); !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	if err := c.Request.ParseMultipartForm(15 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse form: %v", err)})
		return
	}
	fileHeader, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file is required"})
		return
	}
	if fileHeader.Size > 15*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Image exceeds 15MB"})
		return
	}
	f, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to open upload"})
		return
	}
	defer f.Close()
	data, err := io.ReadAll(f)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read upload"})
		return
	}
	cv := h.smartSaleService.CVSidecar()
	if cv == nil {
		c.JSON(http.StatusOK, gin.H{
			"ok": true, "advisory": false, "severe": false,
			"score": 100.0, "issues": []string{}, "severe_issues": []string{},
			"sidecar_available": false,
		})
		return
	}
	res := cv.QualityCheck(c.Request.Context(), data)
	if res == nil {
		c.JSON(http.StatusOK, gin.H{
			"ok": true, "advisory": false, "severe": false,
			"score": 100.0, "issues": []string{}, "severe_issues": []string{},
			"sidecar_available": false,
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"ok":                res.OK,
		"page_size_px":      res.PageSizePx,
		"blur":              res.Blur,
		"contrast":          res.Contrast,
		"brightness":        res.Brightness,
		"skew_deg":          res.SkewDeg,
		"issues":            res.Issues,
		"severe_issues":     res.SevereIssues,
		"advisory":          res.Advisory,
		"severe":            res.Severe,
		"score":             res.Score,
		"sidecar_available": true,
	})
}

// GetSmartSaleHistory returns history of smart sale submissions
// @Summary Get Smart Sale History
// @Description Get history of smart sale submissions for a shop
// @Tags Smart Sale
// @Produce json
// @Param shop_id query string false "Shop UUID filter"
// @Param start_date query string false "Start date (YYYY-MM-DD)"
// @Param end_date query string false "End date (YYYY-MM-DD)"
// @Param page query int false "Page number"
// @Param page_size query int false "Page size"
// @Success 200 {object} map[string]interface{}
// @Router /sales/smart-sale/history [get]
func (h *SmartSaleHandlers) GetSmartSaleHistory(c *gin.Context) {
	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}

	// Parse query parameters
	shopIDStr := c.Query("shop_id")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	h.logger.Infof("SmartSale: History request - tenant=%v, shop=%s, start=%s, end=%s",
		tenantID, shopIDStr, startDate, endDate)

	// For now, return empty history (can be implemented with a smart_sales tracking table)
	c.JSON(http.StatusOK, gin.H{
		"records":     []interface{}{},
		"total_count": 0,
		"page":        1,
		"page_size":   20,
		"message":     "Smart sale history tracking will be available in a future update",
	})
}

// RetrySmartSale retries a failed smart sale
// @Summary Retry Smart Sale
// @Description Retry processing a failed smart sale submission
// @Tags Smart Sale
// @Produce json
// @Param id path string true "Smart Sale ID"
// @Success 200 {object} services.SmartSaleResult
// @Failure 400 {object} map[string]string
// @Router /sales/smart-sale/{id}/retry [post]
func (h *SmartSaleHandlers) RetrySmartSale(c *gin.Context) {
	smartSaleID := c.Param("id")
	h.logger.Infof("SmartSale: Retry request for ID: %s", smartSaleID)

	// For now, return not implemented
	c.JSON(http.StatusNotImplemented, gin.H{
		"error":   "Retry functionality will be available in a future update",
		"sale_id": smartSaleID,
	})
}

// ApplySmartSale creates the daily sale from user-confirmed items
func (h *SmartSaleHandlers) ApplySmartSale(c *gin.Context) {
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant not found"})
		return
	}
	userRole, _ := c.Get("role")
	roleStr := ""
	if role, ok := userRole.(string); ok {
		roleStr = role
	}

	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req services.SmartSaleApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// v1.0.124 — apply audit log. Without this, every diagnosis on a
	// "saved data ≠ submitted data" complaint becomes guesswork. Logged at
	// INFO with idempotency key + hash + first 4KB of items JSON.
	itemsBlob, _ := json.Marshal(req.Items)
	itemsBlobStr := string(itemsBlob)
	if len(itemsBlobStr) > 4096 {
		itemsBlobStr = itemsBlobStr[:4096] + "…(truncated)"
	}
	log.Printf("ApplySmartSale: idempotency_key=%s hash=%s user=%s tenant=%s items=%d payload=%s",
		req.IdempotencyKey, req.ClientPayloadHash, userID, tenantID, len(req.Items), itemsBlobStr)

	// v1.0.160 — mandatory review-warning gate. Refuses to persist any row
	// carrying a blocking warning the user hasn't acknowledged on the review
	// screen. Returns 422 + per-row diagnostics so Flutter can scroll to the
	// offender and re-prompt for confirmation. Bypassable in log-only mode
	// via SMART_SALE_MANDATORY_REVIEW=0 (rollout escape hatch only).
	gate := services.ValidateWarningConfirmations(req.Items)
	if len(gate.Rejected) > 0 && gate.Enforced {
		log.Printf("ApplySmartSale: REJECTED %d rows for unconfirmed warnings (user=%s tenant=%s)",
			len(gate.Rejected), userID, tenantID)
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":         "Some rows have warnings that need user confirmation",
			"rejected_rows": gate.Rejected,
		})
		return
	}

	// v1.0.327 — alias-conflict guard. Refuses to persist when two apply rows
	// bind to the same product_id at meaningfully-divergent OCR rates (would
	// trigger the silent qty/amount merge in createDailySalesEntries and destroy
	// one SKU's sale). Bypassable in log-only via SMART_SALE_ALIAS_CONFLICT_GUARD=0.
	aliasGate := services.ValidateNoAliasConflicts(req.Items)
	if len(aliasGate.Conflicts) > 0 && aliasGate.Enforced {
		log.Printf("ApplySmartSale: REJECTED %d alias-conflict collision(s) (user=%s tenant=%s)",
			len(aliasGate.Conflicts), userID, tenantID)
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":           "Cannot apply: two or more rows match the same product at different rates",
			"alias_conflicts": aliasGate.Conflicts,
		})
		return
	}

	result, err := h.smartSaleService.ApplySmartSale(c.Request.Context(), &req, userID, tenantID, roleStr)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// LearnFromSmartSale teaches the AI alias system from user corrections
func (h *SmartSaleHandlers) LearnFromSmartSale(c *gin.Context) {
	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req struct {
		// v1.0.160 — accept optional shop_id so the alias write is anchored
		// to the shop that taught the correction. Empty / missing →
		// tenant-wide learn (legacy behaviour preserved for older clients).
		ShopID string `json:"shop_id"`
		Items  []struct {
			OCRText   string `json:"ocr_text" binding:"required"`
			ProductID string `json:"product_id" binding:"required"`
		} `json:"items" binding:"required,min=1"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	shopID := uuid.Nil
	if req.ShopID != "" {
		if parsed, perr := uuid.Parse(req.ShopID); perr == nil {
			shopID = parsed
		}
	}

	learned := 0
	for _, item := range req.Items {
		pid, err := uuid.Parse(item.ProductID)
		if err != nil {
			continue
		}
		// Look up product canonical name
		var product models.Product
		if err := h.db.Select("name").Where("id = ? AND tenant_id = ?", pid, tenantID).First(&product).Error; err != nil {
			continue
		}
		if err := h.aliasService.LearnAliasScoped(tenantID, shopID, item.OCRText, product.Name, &pid, "user_correction"); err == nil {
			learned++
		}
		// v1.0.199 — also write tenant-wide so sibling shops benefit.
		if shopID != uuid.Nil {
			h.aliasService.LearnAliasScoped(tenantID, uuid.Nil, item.OCRText, product.Name, &pid, "user_correction_tenant")
		}
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok", "learned": learned})
}

// ResolveDoubt handles POST /api/sales/smart-sale/doubt/resolve.
//
// v1.0.183 Track C2 — operator answers ONE doubted cell from the popup queue
// (smart_sale_screen.dart _DoubtQueueModal). The handler immediately captures
// the (raw → corrected) pair into ocr_digit_corrections so the next
// extraction at this shop already knows the right value, regardless of
// whether the operator later abandons the apply. This is the "ask once,
// learn forever" loop the user explicitly asked for.
//
// Request body:
//
//	{
//	  "shop_id":     "uuid",            // required — anchors the lesson
//	  "job_id":      "uuid",            // optional — for telemetry/audit
//	  "client_row_id": "uuid",          // optional — Flutter row identity
//	  "field":       "sale|closing|opening|rate",
//	  "rule":        "sale_gt_supply|...",  // which invariant fired
//	  "ai_value":    23,                // what AI extracted (omit if blank)
//	  "user_value":  17,                // operator's answer (required)
//	  "accepted_suggested": true        // true=Accept, false=typed
//	}
func (h *SmartSaleHandlers) ResolveDoubt(c *gin.Context) {
	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req struct {
		ShopID            string  `json:"shop_id" binding:"required"`
		JobID             string  `json:"job_id"`
		ClientRowID       string  `json:"client_row_id"`
		Field             string  `json:"field" binding:"required"`
		Rule              string  `json:"rule"`
		AIValue           *int    `json:"ai_value"`
		AIRate            *float64 `json:"ai_rate"`
		UserValue         *int    `json:"user_value"`
		UserRate          *float64 `json:"user_rate"`
		AcceptedSuggested bool    `json:"accepted_suggested"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
		return
	}

	// Hand off to the service. Returns whether the lesson was actually
	// persisted (it may dedup against an existing identical pair).
	persisted, perr := h.smartSaleService.ResolveDoubt(
		tenantID, shopID, req.JobID, req.ClientRowID,
		req.Field, req.Rule,
		req.AIValue, req.AIRate, req.UserValue, req.UserRate,
		req.AcceptedSuggested,
	)
	if perr != nil {
		log.Printf("ResolveDoubt: tenant=%s shop=%s field=%s err=%v", tenantID, shopID, req.Field, perr)
		c.JSON(http.StatusInternalServerError, gin.H{"error": perr.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok", "persisted": persisted})
}


// AccuracyShopSummary handles GET /api/sales/smart-sale/accuracy/shop.
//
// v1.0.181 — lightweight per-shop aggregate over Smart Sale jobs in the last
// N days. Tenant-scoped via auth context; optional ?shop_id and ?days
// query params. Returns total / done / failed counts per shop, avg
// extracted-items count, avg runtime, and completion ratio.
//
// Operational health metrics, NOT true accuracy (no ground truth here).
// Intent: an admin dashboard plots completion% trend per shop and flags
// regressions. Image-quality histograms become available once
// quality_check_results jsonb is plumbed onto the job row (next iteration).
func (h *SmartSaleHandlers) AccuracyShopSummary(c *gin.Context) {
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	var tenantID uuid.UUID
	switch v := tenantIDRaw.(type) {
	case uuid.UUID:
		tenantID = v
	case string:
		parsed, err := uuid.Parse(v)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id"})
			return
		}
		tenantID = parsed
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id"})
		return
	}

	days := 30
	if v := strings.TrimSpace(c.Query("days")); v != "" {
		var d int
		if _, err := fmt.Sscanf(v, "%d", &d); err == nil && d > 0 && d <= 365 {
			days = d
		}
	}
	since := time.Now().AddDate(0, 0, -days)

	// Optional shop scope. Empty string = all shops in tenant.
	shopFilter := strings.TrimSpace(c.Query("shop_id"))
	var shopUUID uuid.UUID
	if shopFilter != "" {
		parsed, err := uuid.Parse(shopFilter)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
		shopUUID = parsed
	}

	type bucket struct {
		ShopID        string  `json:"shop_id"`
		ShopName      string  `json:"shop_name"`
		Total         int     `json:"total"`
		Done          int     `json:"done"`
		Failed        int     `json:"failed"`
		Pending       int     `json:"pending"`
		AvgItems      float64 `json:"avg_items"`
		AvgRuntimeSec float64 `json:"avg_runtime_sec"`
		CompletionPct float64 `json:"completion_pct"`
		// v1.0.182 — image-quality aggregates from quality_check_results jsonb.
		// Null/zero when no jobs in the window have snapshots yet (column was
		// introduced in v1.0.182; older rows show 0 across all four).
		AvgBlur       float64 `json:"avg_blur"`
		AvgContrast   float64 `json:"avg_contrast"`
		AvgBrightness float64 `json:"avg_brightness"`
		AvgQualityScore float64 `json:"avg_quality_score"`
		AdvisoryPct   float64 `json:"advisory_pct"`   // % images flagged advisory
		SeverePct     float64 `json:"severe_pct"`     // % images flagged severe
		ImagesScored  int     `json:"images_scored"`
	}

	// Single GORM ?-style placeholder per binding. Aggregates pull from
	// quality_check_results jsonb via jsonb_array_elements; jobs with NULL
	// quality_check_results just don't contribute to the avg (FILTER WHERE).
	q := h.db.DB.Raw(`
		SELECT
			j.shop_id::text,
			COALESCE(MAX(j.shop_name), '') AS shop_name,
			COUNT(*) AS total,
			COUNT(*) FILTER (WHERE j.status='done') AS done,
			COUNT(*) FILTER (WHERE j.status='failed') AS failed,
			COUNT(*) FILTER (WHERE j.status='pending' OR j.status='running') AS pending,
			COALESCE(AVG(jsonb_array_length(COALESCE(j.result->'extracted_items','[]'::jsonb)))
				FILTER (WHERE j.status='done'), 0) AS avg_items,
			COALESCE(AVG(EXTRACT(EPOCH FROM (j.completed_at - j.started_at)))
				FILTER (WHERE j.status='done' AND j.started_at IS NOT NULL AND j.completed_at IS NOT NULL), 0) AS avg_runtime_sec,
			COALESCE((
				SELECT AVG((q->>'blur')::float)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS avg_blur,
			COALESCE((
				SELECT AVG((q->>'contrast')::float)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS avg_contrast,
			COALESCE((
				SELECT AVG((q->>'brightness')::float)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS avg_brightness,
			COALESCE((
				SELECT AVG((q->>'score')::float)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS avg_quality_score,
			COALESCE((
				SELECT (COUNT(*) FILTER (WHERE (q->>'advisory')::bool))::float * 100.0 / NULLIF(COUNT(*),0)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS advisory_pct,
			COALESCE((
				SELECT (COUNT(*) FILTER (WHERE (q->>'severe')::bool))::float * 100.0 / NULLIF(COUNT(*),0)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS severe_pct,
			COALESCE((
				SELECT COUNT(*)
				FROM smart_sale_setup_jobs j2,
				     jsonb_array_elements(COALESCE(j2.quality_check_results,'[]'::jsonb)) q
				WHERE j2.shop_id = j.shop_id
				  AND j2.tenant_id = j.tenant_id
				  AND j2.created_at >= ?
				  AND j2.deleted_at IS NULL
			), 0) AS images_scored
		FROM smart_sale_setup_jobs j
		WHERE j.tenant_id = ?
		  AND j.created_at >= ?
		  AND j.deleted_at IS NULL
		  AND (? = '' OR j.shop_id = ?)
		GROUP BY j.shop_id, j.tenant_id
		ORDER BY COUNT(*) DESC
		LIMIT 200
	`, since, since, since, since, since, since, since, tenantID, since, shopFilter, shopUUID)

	rows, err := q.Rows()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	out := make([]bucket, 0, 8)
	totalAll, doneAll := 0, 0
	for rows.Next() {
		var b bucket
		if err := rows.Scan(&b.ShopID, &b.ShopName, &b.Total, &b.Done, &b.Failed,
			&b.Pending, &b.AvgItems, &b.AvgRuntimeSec,
			&b.AvgBlur, &b.AvgContrast, &b.AvgBrightness, &b.AvgQualityScore,
			&b.AdvisoryPct, &b.SeverePct, &b.ImagesScored); err != nil {
			continue
		}
		if b.Total > 0 {
			b.CompletionPct = float64(b.Done) / float64(b.Total) * 100.0
		}
		totalAll += b.Total
		doneAll += b.Done
		out = append(out, b)
	}
	overallPct := 0.0
	if totalAll > 0 {
		overallPct = float64(doneAll) / float64(totalAll) * 100.0
	}
	c.JSON(http.StatusOK, gin.H{
		"days":           days,
		"since":          since.UTC().Format(time.RFC3339),
		"shops":          out,
		"total_jobs":     totalAll,
		"total_done":     doneAll,
		"completion_pct": overallPct,
	})
}

// EvaluateJob handles POST /api/sales/smart-sale/jobs/:id/eval.
//
// Replays a stored Smart Sale job through the current OCR pipeline and
// returns a fresh-vs-original comparison. Tenant-scoped via the same
// X-Tenant-ID header pattern the rest of the inventory handlers use.
//
// Body (optional): {} — no models knob today since Smart Sale is single-
// backend; the field exists for future Sonnet/Opus parallel rollout.
func (h *SmartSaleHandlers) EvaluateJob(c *gin.Context) {
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id"})
		return
	}
	jobID := c.Param("id")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job id is required"})
		return
	}
	// v1.0.131 — optional `pipeline` arg: "current" (legacy Gemini single-pass)
	// or "v_next" (Claude + voting + recovery + page-rescue + handwritten-band).
	// Default "current" so existing UI clients keep working.
	var body struct {
		Pipeline string `json:"pipeline"`
	}
	_ = c.ShouldBindJSON(&body)
	res, err := h.smartSaleService.EvaluateJob(c.Request.Context(), jobID, tenantID, body.Pipeline)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

// ReplayJobLearning handles POST /api/sales/smart-sale/jobs/:id/replay-learning.
//
// Mirrors Stock Setup's ReplayStockSetupJobLearning — retroactively feeds the
// user's review-screen edits through the alias / negative-alias / shop-rate /
// correction-outcome pipelines without writing any sale rows. Used to recover
// learning signal from jobs whose apply failed before v1.0.132 (when learning
// was gated on `applied > 0`).
//
// Body: SmartSaleApplyRequest (same shape as /apply).
// Response: 202 + { outcome: "replayed", items: N }.
func (h *SmartSaleHandlers) ReplayJobLearning(c *gin.Context) {
	if h.smartSaleService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Sale not configured"})
		return
	}
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id"})
		return
	}
	userIDRaw, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}
	userID, err := uuid.Parse(userIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user_id"})
		return
	}
	jobID := c.Param("id")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job id is required"})
		return
	}
	var req services.SmartSaleApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body: " + err.Error()})
		return
	}
	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "items are required — send the user's review-screen state so learning can replay"})
		return
	}
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
		return
	}
	h.smartSaleService.ReplayApplyLearning(tenantID, userID, shopID, jobID, req.Items)
	c.JSON(http.StatusAccepted, gin.H{
		"job_id":  jobID,
		"items":   len(req.Items),
		"outcome": "replayed",
	})
}

// GetPageGrid returns per-cell crops + grid structure for a single uploaded
// page so the Flutter "apple-to-apple" preview screen can render the image
// reconstructed cell-by-cell BEFORE the Sales Summary review. Thin proxy
// over cv-sidecar /sheet-with-crops; no extraction or AI calls happen here.
func (h *SmartSaleHandlers) GetPageGrid(c *gin.Context) {
	if _, exists := c.Get("user_id"); !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	if err := c.Request.ParseMultipartForm(32 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Failed to parse form: %v", err)})
		return
	}
	fh, err := c.FormFile("file")
	if err != nil {
		fh, err = c.FormFile("image")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "file (image) is required"})
			return
		}
	}
	src, err := fh.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open uploaded file"})
		return
	}
	defer src.Close()
	imgBytes, err := io.ReadAll(src)
	if err != nil || len(imgBytes) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "empty or unreadable image"})
		return
	}

	cvURL := strings.TrimSpace(os.Getenv("CV_SIDECAR_URL"))
	if cvURL == "" {
		cvURL = "http://cv-sidecar:8099"
	}

	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", fh.Filename)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal multipart error"})
		return
	}
	if _, err := part.Write(imgBytes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal multipart write error"})
		return
	}
	w.Close()

	timeoutMs := 20000
	if v := os.Getenv("CV_SIDECAR_GRID_TIMEOUT_MS"); v != "" {
		fmt.Sscanf(v, "%d", &timeoutMs)
	}
	client := &http.Client{Timeout: time.Duration(timeoutMs) * time.Millisecond}
	req, err := http.NewRequestWithContext(c.Request.Context(), "POST", cvURL+"/sheet-with-crops", body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to build sidecar request"})
		return
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := client.Do(req)
	if err != nil {
		h.logger.Warnf("GetPageGrid: cv-sidecar /sheet-with-crops failed: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "cv-sidecar unreachable", "detail": err.Error()})
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 800))
		h.logger.Warnf("GetPageGrid: cv-sidecar non-200 (%d): %s", resp.StatusCode, string(raw))
		c.Data(resp.StatusCode, "application/json", raw)
		return
	}
	c.Header("Content-Type", "application/json")
	if _, err := io.Copy(c.Writer, resp.Body); err != nil {
		h.logger.Warnf("GetPageGrid: streaming sidecar response failed: %v", err)
	}
}

