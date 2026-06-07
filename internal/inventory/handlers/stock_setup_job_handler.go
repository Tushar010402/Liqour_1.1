package handlers

import (
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// SubmitStockSetupJob handles POST /api/inventory/stocks/smart-setup/jobs.
//
// Multipart request, same shape as the legacy synchronous /extract endpoint
// (shop_id, category_id, size, stock_column, images[]), but returns
// immediately after persisting the job + images to disk. The returned
// body looks like `{job_id, status: "pending"}` so the client can start
// polling straight away.
//
// Keeping the multipart shape identical to /extract lets the Flutter side
// switch to the job flow with zero new field wiring.
func (h *InventoryHandlers) SubmitStockSetupJob(c *gin.Context) {
	if h.smartStockJobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup jobs are not configured"})
		return
	}
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

	shopID := c.PostForm("shop_id")
	if shopID == "" {
		shopID = c.Query("shop_id")
	}
	if shopID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	stockColumn := c.DefaultPostForm("stock_column", c.DefaultQuery("stock_column", "total"))
	categoryID := c.DefaultPostForm("category_id", c.DefaultQuery("category_id", ""))
	sizeParam := c.DefaultPostForm("size", c.DefaultQuery("size", ""))

	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse multipart form: " + err.Error()})
		return
	}

	var images []services.SmartPurchaseImage
	fieldNames := []string{"images[]", "images", "image", "file", "files[]", "files"}
	for _, fieldName := range fieldNames {
		files := form.File[fieldName]
		if len(files) == 0 {
			continue
		}
		for _, fh := range files {
			if fh.Size > 10*1024*1024 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Image too large (max 10MB): " + fh.Filename})
				return
			}
			ct := strings.ToLower(fh.Header.Get("Content-Type"))
			if !strings.Contains(ct, "jpeg") && !strings.Contains(ct, "jpg") && !strings.Contains(ct, "png") {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Only JPEG and PNG images are supported: " + fh.Filename})
				return
			}
			f, err := fh.Open()
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image: " + fh.Filename})
				return
			}
			data, err := io.ReadAll(f)
			f.Close()
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image data: " + fh.Filename})
				return
			}
			images = append(images, services.SmartPurchaseImage{
				Data:        data,
				ContentType: ct,
				Filename:    fh.Filename,
			})
		}
		break
	}

	if len(images) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one register page image is required"})
		return
	}

	job, err := h.smartStockJobService.Submit(services.SubmitJobRequest{
		TenantID:    tenantID.(string),
		UserID:      userID.(string),
		ShopID:      shopID,
		CategoryID:  categoryID,
		Size:        sizeParam,
		StockColumn: stockColumn,
		Images:      images,
	})
	if err != nil {
		c.JSON(services.JobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}

	// Response is deliberately minimal — clients poll for the rest. Returning
	// the full row here would tempt clients to assume submit == done.
	c.JSON(http.StatusAccepted, gin.H{
		"job_id":     job.ID.String(),
		"status":     job.Status,
		"created_at": job.CreatedAt,
	})
}

// GetStockSetupJob handles GET /api/inventory/stocks/smart-setup/jobs/:id.
// Returns the full job row including the `result` blob once status=done.
// Tenant+user scoped — cross-user access returns 404, not 403, so the
// endpoint doesn't leak existence of other users' jobs.
func (h *InventoryHandlers) GetStockSetupJob(c *gin.Context) {
	if h.smartStockJobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup jobs are not configured"})
		return
	}
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
	jobID := c.Param("id")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job id is required"})
		return
	}
	job, err := h.smartStockJobService.Get(jobID, tenantID.(string), userID.(string))
	if err != nil {
		c.JSON(services.JobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, job)
}

// ListStockSetupJobs handles GET /api/inventory/stocks/smart-setup/jobs.
// Returns the caller's recent jobs, newest first. Used by the Flutter
// "active jobs" banner to surface in-flight extractions after a cold app
// launch.
func (h *InventoryHandlers) ListStockSetupJobs(c *gin.Context) {
	if h.smartStockJobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup jobs are not configured"})
		return
	}
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
	limit := 20
	if s := c.Query("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			limit = n
		}
	}
	jobs, err := h.smartStockJobService.List(tenantID.(string), userID.(string), limit)
	if err != nil {
		c.JSON(services.JobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"jobs": jobs})
}

// CancelStockSetupJob handles DELETE /api/inventory/stocks/smart-setup/jobs/:id.
// Pending jobs are canceled; already-running or terminal jobs are left
// untouched (endpoint returns 200 either way — the end state matches what
// the client wants either through cancel or natural completion).
func (h *InventoryHandlers) CancelStockSetupJob(c *gin.Context) {
	if h.smartStockJobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup jobs are not configured"})
		return
	}
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
	jobID := c.Param("id")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job id is required"})
		return
	}
	if err := h.smartStockJobService.Cancel(jobID, tenantID.(string), userID.(string)); err != nil {
		c.JSON(services.JobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// EvaluateStockSetupJob handles POST /api/inventory/stocks/smart-setup/jobs/:id/eval.
//
// Replays an existing job through one or more OCR backends and returns a
// row-by-row comparison. Body: {"models": ["claude", "gemini"]}. Used to
// measure the real impact of model / prompt / vote changes against actual
// production register images without making the user re-upload them.
//
// Tenant-scoped — caller can only evaluate jobs in their own tenant.
func (h *InventoryHandlers) EvaluateStockSetupJob(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup not configured"})
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
	jobID := c.Param("id")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job id is required"})
		return
	}
	var body struct {
		Models []string `json:"models"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || len(body.Models) == 0 {
		body.Models = []string{"claude", "gemini"}
	}
	res, err := h.smartStockSetupService.EvaluateJob(c.Request.Context(), jobID, tenantID, body.Models)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

// ReplayStockSetupJobLearning handles
// POST /api/inventory/stocks/smart-setup/jobs/:id/replay-learning.
//
// Born out of the May 1 2026 incident (job a1a30429-868f-4ece-ba2c-a3375f83da22)
// where the wrapping apply transaction aborted on a column-name mismatch
// (SQLSTATE 42703 → 25P02), the stock_setup_records insert silently
// disappeared, AND the alias-learning + correction-outcome capture that
// gated on `applied > 0` never fired — so the user's review-screen edits
// ("R.S Barrel" → SEAGRAM'S ROYAL STAG BARREL SELECT RESERVE, three
// negative aliases for the rejected rows) were lost from training data.
//
// v1.0.132 fixed the column tags AND moved learning out of that gate, but
// for jobs that already failed under the old code path, the signal is
// gone unless the user replays. This endpoint accepts the user's
// review-screen items (same shape as /apply, minus the actual stock
// writes) and runs them through captureApplyLearning. Idempotent — the
// alias upserts are safe to repeat.
//
// Body: SmartStockSetupApplyRequest (same as /apply).
// Response: 202 + { outcome: "replayed", items: N }.
func (h *InventoryHandlers) ReplayStockSetupJobLearning(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Stock Setup not configured"})
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

	// Authorize: caller must own the job (or be in the same tenant). Reuse
	// the existing Get path which already enforces tenant+user scope.
	if h.smartStockJobService != nil {
		if _, gerr := h.smartStockJobService.Get(jobID, tenantIDRaw.(string), userIDRaw.(string)); gerr != nil {
			c.JSON(services.JobErrorToStatus(gerr), gin.H{"error": gerr.Error()})
			return
		}
	}

	var req services.SmartStockSetupApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body: " + err.Error()})
		return
	}
	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "items are required — send the user's review-screen state so learning can replay"})
		return
	}

	h.smartStockSetupService.ReplayApplyLearning(tenantID, userID, jobID, req)

	c.JSON(http.StatusAccepted, gin.H{
		"job_id":  jobID,
		"items":   len(req.Items),
		"outcome": "replayed",
	})
}
