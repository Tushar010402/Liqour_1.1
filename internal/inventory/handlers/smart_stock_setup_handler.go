package handlers

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// SmartStockSetupExtract handles AI-powered extraction from stock register images
func (h *InventoryHandlers) SmartStockSetupExtract(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}

	// Extract auth context
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	// Parse form data
	shopID := c.PostForm("shop_id")
	if shopID == "" {
		shopID = c.Query("shop_id")
	}
	if shopID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	stockColumn := c.DefaultPostForm("stock_column", c.DefaultQuery("stock_column", "total"))

	// Parse optional category and size for scoped matching
	categoryID := c.DefaultPostForm("category_id", c.DefaultQuery("category_id", ""))
	sizeParam := c.DefaultPostForm("size", c.DefaultQuery("size", ""))

	// Parse uploaded images
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse multipart form: " + err.Error()})
		return
	}

	var images []services.SmartPurchaseImage

	fieldNames := []string{"images[]", "images", "image", "file", "files[]", "files"}
	for _, fieldName := range fieldNames {
		files := form.File[fieldName]
		if len(files) > 0 {
			for _, fileHeader := range files {
				if fileHeader.Size > 10*1024*1024 {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Image too large (max 10MB): " + fileHeader.Filename})
					return
				}

				ct := strings.ToLower(fileHeader.Header.Get("Content-Type"))
				if !strings.Contains(ct, "jpeg") && !strings.Contains(ct, "jpg") && !strings.Contains(ct, "png") {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Only JPEG and PNG images are supported: " + fileHeader.Filename})
					return
				}

				file, err := fileHeader.Open()
				if err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image: " + fileHeader.Filename})
					return
				}
				data, err := io.ReadAll(file)
				file.Close()
				if err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image data: " + fileHeader.Filename})
					return
				}

				images = append(images, services.SmartPurchaseImage{
					Data:        data,
					ContentType: ct,
					Filename:    fileHeader.Filename,
				})
			}
			break
		}
	}

	if len(images) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one register page image is required"})
		return
	}
	if len(images) > 5 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 5 images allowed"})
		return
	}

	// v1.0.178 — defense-in-depth severe-quality reject (parity with Smart
	// Sale). The Flutter preflight already gates client-side; this catches
	// stale APKs. Operators can opt into "use anyway" via override indices.
	if cv := h.smartStockSetupService.CVSidecar(); cv != nil && os.Getenv("STOCK_SETUP_QUALITY_GATE") != "0" {
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
		for idx, img := range images {
			if overrideSet[idx] {
				continue
			}
			res := cv.QualityCheck(c.Request.Context(), img.Data)
			if res != nil && res.Severe {
				c.JSON(http.StatusUnprocessableEntity, gin.H{
					"error":         "image_quality_severe",
					"message":       "One or more photos are too unclear to extract reliably. Please retake.",
					"image_index":   idx,
					"severe_issues": res.SevereIssues,
					"issues":        res.Issues,
					"score":         res.Score,
				})
				return
			}
		}
	}

	req := services.SmartStockSetupRequest{
		TenantID:    tenantID.(string),
		UserID:      userID.(string),
		ShopID:      shopID,
		StockColumn: stockColumn,
		CategoryID:  categoryID,
		Size:        sizeParam,
		Images:      images,
	}

	// Use a detached context with generous timeout for AI processing.
	// The request context is tied to the client connection — if the Flutter
	// client times out (e.g., 60s), the AI call is canceled mid-flight.
	// AI processing for multi-image registers can take 2-3 minutes.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	result, err := h.smartStockSetupService.ProcessExtraction(ctx, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// SmartStockSetupApply bulk-sets stock from confirmed extraction data
func (h *InventoryHandlers) SmartStockSetupApply(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}

	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	// Get user role for approval flow
	userRole := ""
	if role, exists := c.Get("role"); exists {
		if r, ok := role.(string); ok {
			userRole = r
		}
	}

	var req services.SmartStockSetupApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.smartStockSetupService.ApplyStockSetup(c.Request.Context(), req, tenantID, userID, userRole)
	if err != nil {
		// v1.0.243 — UnverifiedRowsError → 422 with rejected_rows envelope so
		// Flutter can scroll to the offending rows and show a targeted dialog.
		var unverifiedErr *services.UnverifiedRowsError
		if errors.As(err, &unverifiedErr) {
			c.JSON(http.StatusUnprocessableEntity, gin.H{
				"error":            "Some rows still need photo verification",
				"unverified_count": unverifiedErr.UnverifiedCount,
				"rejected_rows":    unverifiedErr.RejectedRows,
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(applyResultHTTPStatus(result), result)
}

// applyResultHTTPStatus maps a Stock Setup apply result to its HTTP status.
//
// v1.0.278 — TRUTH IN THE CONTRACT. The service swallows the apply tx error
// (returns result,nil with Status="failed"); the handler previously ALWAYS
// returned 200, so the Flutter client (which keyed success off HTTP 200)
// showed "submitted" even when 0 rows persisted. A failed / nothing-persisted
// apply MUST NOT be a 200 — return 422 (with the FULL structured result body
// so the client can show errors[]/counts and offer a safe idempotent retry).
// "partial" and "pending_approval" are genuine partial successes (rows did
// persist / are queued for approval) and stay 200.
//
// Pure + side-effect-free so it is unit-tested with no DB/auth/customer data
// (smart_stock_setup_handler_status_test.go) — this is the regression guard
// that makes the "submitted but nothing saved" lie impossible to reintroduce.
func applyResultHTTPStatus(result *services.SmartStockSetupApplyResult) int {
	if result != nil && (result.Status == "failed" ||
		(result.ItemsApplied == 0 && result.ItemsReceived > 0 &&
			result.Status != "pending_approval" && result.Status != "partial")) {
		return http.StatusUnprocessableEntity
	}
	return http.StatusOK
}

// ListStockSetupRecords returns paginated stock setup records
func (h *InventoryHandlers) ListStockSetupRecords(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}

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

	shopID := c.Query("shop_id")
	status := c.Query("status")
	category := c.Query("category")
	size := c.Query("size")
	page := 1
	pageSize := 20
	if p := c.Query("page"); p != "" {
		fmt.Sscanf(p, "%d", &page)
	}
	if ps := c.Query("page_size"); ps != "" {
		fmt.Sscanf(ps, "%d", &pageSize)
	}

	result, err := h.smartStockSetupService.ListStockSetupRecords(c.Request.Context(), tenantID, shopID, status, category, size, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetStockSetupPendingCount returns the number of pending (awaiting-approval)
// stock-setup records for the caller's tenant, scoped optionally by shop.
// Drives the admin sidebar's "AI Stock Setup ⓷" badge so managers see at a
// glance how many records need their attention.
//
// v1.0.203 — added per Tushar's request alongside operator-mobile + support
// phone tracks. Cheap query (uses idx_stock_setup_records_status implicitly
// via the status WHERE clause) — safe to poll every 60s.
func (h *InventoryHandlers) GetStockSetupPendingCount(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}
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
	shopID := c.Query("shop_id")
	count, err := h.smartStockSetupService.PendingCount(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"count":     count,
		"tenant_id": tenantIDStr,
	})
}

// GetStockSetupRecordByID returns a single stock setup record
func (h *InventoryHandlers) GetStockSetupRecordByID(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}

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

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	result, err := h.smartStockSetupService.GetStockSetupRecordByID(c.Request.Context(), recordID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// UpdateStockSetupRecord handles PATCH /api/inventory/stocks/smart-setup/records/:id.
// Lets managers reconcile an AI-extracted record before approving: swap a
// misidentified product on a row, correct the four register values, add a
// missed brand, or delete a phantom row. Only allowed on pending records.
func (h *InventoryHandlers) UpdateStockSetupRecord(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}
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
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}
	userID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	var req services.UpdateStockSetupRecordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.smartStockSetupService.UpdateStockSetupRecord(c.Request.Context(), recordID, tenantID, userID, req)
	if err != nil {
		// Approved (or rejected) records are immutable — surface as 409 so clients can
		// distinguish "you sent bad data" (400) from "this record can't be edited" (409).
		if strings.Contains(err.Error(), "only pending records can be edited") {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// AutoFixBrandLinks handles POST /api/inventory/stocks/smart-setup/records/:id/auto-fix-brand-links.
// Scans the record's items for product↔brand name mismatches and rewires
// each flagged product's brand_id to the best-matching brand in the tenant
// catalog. Returns a summary of what was fixed vs what still needs manual
// review. Safe to run multiple times — already-fixed rows are skipped
// because their product↔brand overlap will pass the threshold.
func (h *InventoryHandlers) AutoFixBrandLinks(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}
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
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}
	result, err := h.smartStockSetupService.AutoFixBrandLinks(c.Request.Context(), recordID, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// ApproveStockSetup approves a pending stock setup record
func (h *InventoryHandlers) ApproveStockSetup(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}

	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}
	approvedByID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	role, _ := c.Get("role")
	approverRole, _ := role.(string)

	result, err := h.smartStockSetupService.ApproveStockSetup(c.Request.Context(), recordID, tenantID, approvedByID, approverRole)
	if err != nil {
		if strings.Contains(err.Error(), "only admin or manager") {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// ReapplyStockSetup handles POST /api/inventory/stocks/smart-setup/records/:id/reapply.
//
// One-tap "snap stock back to this approved baseline" for the 7 days after
// approval. Useful when a shop wants to undo accidental sales / receipts
// without redoing the entire AI Stock Setup. Returns 410 Gone past the
// 7-day window so users know they need a fresh setup.
func (h *InventoryHandlers) ReapplyStockSetup(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}
	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}
	reappliedByID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}
	role, _ := c.Get("role")
	approverRole, _ := role.(string)

	result, err := h.smartStockSetupService.ReapplyStockSetup(c.Request.Context(), recordID, tenantID, reappliedByID, approverRole)
	if err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "only admin or manager"):
			c.JSON(http.StatusForbidden, gin.H{"error": msg})
		case strings.Contains(msg, "reapply window expired"):
			c.JSON(http.StatusGone, gin.H{"error": msg})
		case strings.Contains(msg, "only approved records"):
			c.JSON(http.StatusConflict, gin.H{"error": msg})
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		}
		return
	}
	c.JSON(http.StatusOK, result)
}

// PreviewStockSetupReplace handles
// GET /api/inventory/stocks/smart-setup/records/:id/replace-preview.
//
// Read-only dry-run: exactly which in-scope products approving this record
// would deactivate (snapshot-replace). Mutates nothing — safe to call before
// approve so a manager sees the blast radius first.
func (h *InventoryHandlers) PreviewStockSetupReplace(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}
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
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}
	result, err := h.smartStockSetupService.PreviewStockSetupReplace(c.Request.Context(), recordID, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// RestoreStockSetupReplace handles
// POST /api/inventory/stocks/smart-setup/records/:id/restore-replace.
//
// Fully reverses the snapshot-replace from this record's approval:
// re-activates every product it deactivated and restores still-zeroed stock
// to its pre-replace quantity. Use when an approved register turns out to
// have silently dropped a real item. Admin/manager only.
func (h *InventoryHandlers) RestoreStockSetupReplace(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}
	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}
	byID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}
	role, _ := c.Get("role")
	roleStr, _ := role.(string)

	result, err := h.smartStockSetupService.RestoreStockSetupReplace(c.Request.Context(), recordID, tenantID, byID, roleStr)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "only admin or manager") {
			c.JSON(http.StatusForbidden, gin.H{"error": msg})
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		}
		return
	}
	c.JSON(http.StatusOK, result)
}

// RejectStockSetup rejects a pending stock setup record
func (h *InventoryHandlers) RejectStockSetup(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
		return
	}

	tenantIDStr, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	userIDStr, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}
	rejectedByID, err := uuid.Parse(userIDStr.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.smartStockSetupService.RejectStockSetup(c.Request.Context(), recordID, tenantID, rejectedByID, req.Reason); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Stock setup record rejected successfully"})
}

// ResolveStockSetupDoubt handles POST /api/inventory/stocks/smart-setup/doubt/resolve.
//
// v1.0.185 Track S5 — operator answers ONE doubted cell from the popup queue
// (Flutter StockSetupDoubtModal). The handler immediately captures the
// (raw → corrected) pair into ocr_digit_corrections (source='stock_setup') so
// the next extraction at this shop already knows the right value, regardless
// of whether the operator later abandons the apply. "Ask once, learn
// forever" — same loop Smart Sale uses (POST /smart-sale/doubt/resolve).
//
// Request body:
//
//	{
//	  "shop_id":            "uuid",         // required — anchors the lesson
//	  "job_id":             "uuid",         // optional — for telemetry
//	  "client_row_id":      "uuid",         // optional — Flutter row identity
//	  "field":              "opening|closing|total|sale|rate|amount|brand|name",
//	  "rule":               "low_confidence|math_disagree|brand_no_match|...",
//	  "ai_value_int":       23,             // when AI extracted an int
//	  "ai_value_float":     1040.0,         // when AI extracted a float (rate/amount)
//	  "ai_value_text":      "Royal Stag",   // when AI extracted text (brand/name)
//	  "user_value_int":     17,             // operator's integer answer
//	  "user_value_float":   1050.0,         // operator's float answer
//	  "user_value_text":    "Royal Stag Premium", // operator's text answer
//	  "accepted_suggested": true            // true=Accept, false=typed
//	}
//
// Response: 200 { "status": "ok", "persisted": true|false }.
func (h *InventoryHandlers) ResolveStockSetupDoubt(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup is not configured"})
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

	var req struct {
		ShopID            string   `json:"shop_id" binding:"required"`
		JobID             string   `json:"job_id"`
		ClientRowID       string   `json:"client_row_id"`
		Field             string   `json:"field" binding:"required"`
		Rule              string   `json:"rule"`
		AIValueInt        *int     `json:"ai_value_int"`
		AIValueFloat      *float64 `json:"ai_value_float"`
		AIValueText       string   `json:"ai_value_text"`
		UserValueInt      *int     `json:"user_value_int"`
		UserValueFloat    *float64 `json:"user_value_float"`
		UserValueText     string   `json:"user_value_text"`
		AcceptedSuggested bool     `json:"accepted_suggested"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
		return
	}

	persisted, perr := h.smartStockSetupService.ResolveDoubt(
		tenantID, shopID, req.JobID, req.ClientRowID,
		req.Field, req.Rule,
		req.AIValueInt, req.AIValueFloat, req.AIValueText,
		req.UserValueInt, req.UserValueFloat, req.UserValueText,
		req.AcceptedSuggested,
	)
	if perr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": perr.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok", "persisted": persisted})
}
