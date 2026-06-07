package handlers

import (
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/sirupsen/logrus"
)

// SmartSaleJobHandlers wires the HTTP endpoints for the Smart Sale async
// job queue. It's a thin translation layer: parse multipart, call the
// service, translate service errors to status codes.
//
// Kept separate from SmartSaleHandlers (which owns the legacy synchronous
// /process endpoint) so rolling back the async flow is a one-line router
// change, not a handler-refactor.
type SmartSaleJobHandlers struct {
	jobService *services.SmartSaleJobService
	logger     *logrus.Logger
}

// NewSmartSaleJobHandlers wires the handler to its service.
func NewSmartSaleJobHandlers(jobService *services.SmartSaleJobService, logger *logrus.Logger) *SmartSaleJobHandlers {
	return &SmartSaleJobHandlers{jobService: jobService, logger: logger}
}

// SubmitJob handles POST /api/sales/smart-sale/jobs.
//
// Multipart request — same shape as the legacy synchronous /process endpoint
// (shop_id, shop_name, date, category, size, images[]) — but returns
// immediately after persisting the job + images to disk. Response body is
// `{job_id, status: "pending", created_at}`. Clients poll the status
// endpoint for the actual result.
//
// Keeping the multipart shape identical to /process lets the Flutter side
// swap in the job flow with zero new-field wiring.
func (h *SmartSaleJobHandlers) SubmitJob(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Sale jobs are not configured"})
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
	userRole, _ := c.Get("role")
	roleStr := ""
	if r, ok := userRole.(string); ok {
		roleStr = r
	}

	// Parse multipart (50MB ceiling — matches the sync handler's
	// ParseMultipartForm(50 << 20), five 10MB images max).
	if err := c.Request.ParseMultipartForm(50 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form: " + err.Error()})
		return
	}

	shopID := c.PostForm("shop_id")
	shopName := c.PostForm("shop_name")
	dateStr := c.PostForm("date")
	category := c.PostForm("category")
	sizeParam := c.PostForm("size")

	if shopID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}
	if dateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date is required"})
		return
	}
	if category != "beer" && category != "non_beer" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category must be 'beer' or 'non_beer'"})
		return
	}

	saleDate, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
		return
	}

	form := c.Request.MultipartForm

	// Accept multiple field-name conventions for cross-client compat —
	// same set the legacy /process endpoint accepts.
	var images []services.SmartSaleJobImage
	for _, fieldName := range []string{"images", "images[]", "image", "image[]", "files", "files[]"} {
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
			images = append(images, services.SmartSaleJobImage{
				Data:        data,
				ContentType: ct,
				Filename:    fh.Filename,
			})
		}
		// Break after first matching field-name so we don't double-count.
		break
	}

	if len(images) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one receipt image is required"})
		return
	}

	job, err := h.jobService.Submit(services.SubmitSaleJobRequest{
		TenantID: tenantID.(string),
		UserID:   userID.(string),
		UserRole: roleStr,
		ShopID:   shopID,
		ShopName: shopName,
		SaleDate: saleDate,
		Category: category,
		Size:     sizeParam,
		Images:   images,
	})
	if err != nil {
		c.JSON(services.SaleJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}

	// Response is deliberately minimal — clients poll for the rest.
	// Returning the full row here would tempt clients to assume
	// submit == done.
	c.JSON(http.StatusAccepted, gin.H{
		"job_id":     job.ID.String(),
		"status":     job.Status,
		"created_at": job.CreatedAt,
	})
}

// GetJob handles GET /api/sales/smart-sale/jobs/:id. Returns the full job
// row including the `result` blob once status=done. Tenant+user scoped —
// cross-user access returns 404 (not 403) so the endpoint doesn't leak
// existence of other users' jobs.
func (h *SmartSaleJobHandlers) GetJob(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Sale jobs are not configured"})
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
	job, err := h.jobService.Get(jobID, tenantID.(string), userID.(string))
	if err != nil {
		c.JSON(services.SaleJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, job)
}

// ListJobs handles GET /api/sales/smart-sale/jobs. Returns the caller's
// recent jobs, newest first. Used by the "active jobs" banner the Flutter
// client shows after a cold app launch to surface in-flight extractions.
func (h *SmartSaleJobHandlers) ListJobs(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Sale jobs are not configured"})
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
	jobs, err := h.jobService.List(tenantID.(string), userID.(string), limit)
	if err != nil {
		c.JSON(services.SaleJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"jobs": jobs})
}

// CancelJob handles DELETE /api/sales/smart-sale/jobs/:id. Pending jobs
// are canceled; already-running or terminal jobs are left untouched (the
// endpoint returns 200 either way — the end state matches what the client
// wants through either cancel or natural completion).
func (h *SmartSaleJobHandlers) CancelJob(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Sale jobs are not configured"})
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
	if err := h.jobService.Cancel(jobID, tenantID.(string), userID.(string)); err != nil {
		c.JSON(services.SaleJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
