package handlers

import (
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/sirupsen/logrus"
)

// SmartPurchaseJobHandlers wires the HTTP endpoints for the Smart Purchase
// async job queue. Mirrors SmartSaleJobHandlers (sales domain) — same
// multipart shape, same status-code mapping, same response payloads. Kept
// separate from the legacy synchronous /process endpoint so rolling back the
// async flow is a one-line router change.
type SmartPurchaseJobHandlers struct {
	jobService *services.SmartPurchaseJobService
	logger     *logrus.Logger
}

// NewSmartPurchaseJobHandlers wires the handler to its service.
func NewSmartPurchaseJobHandlers(jobService *services.SmartPurchaseJobService, logger *logrus.Logger) *SmartPurchaseJobHandlers {
	return &SmartPurchaseJobHandlers{jobService: jobService, logger: logger}
}

// SubmitJob handles POST /api/inventory/smart-purchase/jobs.
//
// Multipart request (same shape as the legacy synchronous /process endpoint):
//   - shop_id (required)
//   - shop_name (optional)
//   - vendor_id (optional)
//   - invoice_date (optional, YYYY-MM-DD)
//   - images / images[] / image / file / files / files[]  → invoice pages
//   - gate_pass / gate_pass[] / gate_pass_images          → gate-pass pages
//
// Returns 202 with `{job_id, status: "pending", created_at}`. Clients poll the
// status endpoint for the actual result.
func (h *SmartPurchaseJobHandlers) SubmitJob(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase jobs are not configured"})
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

	// v1.0.193 — 120MB ceiling: up to 10 invoice + 10 gate-pass × 6MB
	// practical mean (headroom for the 10MB-each cap). One AI extraction
	// per submission so per-tenant memory ramp is bounded. Bumped from
	// 60MB to support multi-page bills (chhotu-class invoices span 4-6
	// pages on FL-2 wholesale runs; split shipments push gate-pass to
	// 7-8 pages).
	if err := c.Request.ParseMultipartForm(120 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form: " + err.Error()})
		return
	}

	shopID := c.PostForm("shop_id")
	shopName := c.PostForm("shop_name")
	vendorID := c.PostForm("vendor_id")
	invoiceDate := c.PostForm("invoice_date")

	if shopID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	form := c.Request.MultipartForm

	collect := func(fields []string) ([]services.SmartPurchaseJobImage, error) {
		var out []services.SmartPurchaseJobImage
		for _, fieldName := range fields {
			files := form.File[fieldName]
			if len(files) == 0 {
				continue
			}
			for _, fh := range files {
				if fh.Size > 10*1024*1024 {
					return nil, &httpUserError{msg: "Image too large (max 10MB): " + fh.Filename}
				}
				ct := strings.ToLower(fh.Header.Get("Content-Type"))
				if !strings.Contains(ct, "jpeg") && !strings.Contains(ct, "jpg") && !strings.Contains(ct, "png") {
					return nil, &httpUserError{msg: "Only JPEG and PNG images are supported: " + fh.Filename}
				}
				f, err := fh.Open()
				if err != nil {
					return nil, &httpUserError{msg: "Failed to read image: " + fh.Filename}
				}
				data, err := io.ReadAll(f)
				f.Close()
				if err != nil {
					return nil, &httpUserError{msg: "Failed to read image data: " + fh.Filename}
				}
				out = append(out, services.SmartPurchaseJobImage{
					Data:        data,
					ContentType: ct,
					Filename:    fh.Filename,
				})
			}
			// First matching field wins so we don't double-count.
			break
		}
		return out, nil
	}

	invoiceImages, err := collect([]string{"images", "images[]", "image", "image[]", "files", "files[]"})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	gatePassImages, err := collect([]string{"gate_pass", "gate_pass[]", "gate_pass_images", "gate_pass_images[]"})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(invoiceImages) == 0 && len(gatePassImages) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one invoice or gate-pass image is required"})
		return
	}

	job, err := h.jobService.Submit(services.SubmitPurchaseJobRequest{
		TenantID:       tenantID.(string),
		UserID:         userID.(string),
		ShopID:         shopID,
		ShopName:       shopName,
		VendorID:       vendorID,
		InvoiceDate:    invoiceDate,
		InvoiceImages:  invoiceImages,
		GatePassImages: gatePassImages,
	})
	if err != nil {
		c.JSON(services.PurchaseJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"job_id":     job.ID.String(),
		"status":     job.Status,
		"created_at": job.CreatedAt,
	})
}

// GetParchaOrder handles GET /purchases/smart-purchase/parcha-order?shop_id=.
// Returns the product order of the shop's latest submitted sale register so the
// app can offer a "Latest-sale (Parsha) order" view of the purchase items.
func (h *SmartPurchaseJobHandlers) GetParchaOrder(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase jobs are not configured"})
		return
	}
	if _, exists := c.Get("tenant_id"); !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	shopID := c.Query("shop_id")
	if shopID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}
	order, recordDate, err := h.jobService.GetParchaOrder(shopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"record_date": recordDate, "order": order})
}

// GetJob handles GET /api/inventory/smart-purchase/jobs/:id.
// Returns the full job row including the `result` blob once status=done.
func (h *SmartPurchaseJobHandlers) GetJob(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase jobs are not configured"})
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
		c.JSON(services.PurchaseJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, job)
}

// ListJobs handles GET /api/inventory/smart-purchase/jobs.
func (h *SmartPurchaseJobHandlers) ListJobs(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase jobs are not configured"})
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
		c.JSON(services.PurchaseJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"jobs": jobs})
}

// CancelJob handles DELETE /api/inventory/smart-purchase/jobs/:id.
func (h *SmartPurchaseJobHandlers) CancelJob(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase jobs are not configured"})
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
		c.JSON(services.PurchaseJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// ExportGPXLSX handles GET /api/inventory/purchases/smart-purchase/jobs/:id/export-gp.xlsx
//
// v1.0.238 Track E — streams a .xlsx workbook with one sheet per GP page (12
// canonical UP Excise columns) plus a Summary sheet (vendor / invoice /
// reconciliation totals). The operator gets a "photocopy" of what AWS
// Textract / Claude actually read from the source GPs, without re-running OCR.
//
// Returns 404 when the job hasn't completed yet OR has no duty_items (e.g.
// 0-GP submission).
func (h *SmartPurchaseJobHandlers) ExportGPXLSX(c *gin.Context) {
	if h.jobService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase jobs are not configured"})
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
		c.JSON(services.PurchaseJobErrorToStatus(err), gin.H{"error": err.Error()})
		return
	}
	if job.Status != "done" {
		c.JSON(http.StatusConflict, gin.H{
			"error":  "job_not_complete",
			"status": job.Status,
		})
		return
	}
	if len(job.Result) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no result on job"})
		return
	}
	xlsx, err := services.BuildGatePassPhotocopyXLSX(map[string]interface{}(job.Result))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "xlsx render failed: " + err.Error()})
		return
	}
	filename := "gp-photocopy-" + jobID + ".xlsx"
	c.Writer.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	c.Writer.Header().Set("Content-Disposition", `attachment; filename="`+filename+`"`)
	c.Writer.Header().Set("Cache-Control", "no-store")
	_, _ = c.Writer.Write(xlsx)
}

// httpUserError lets the multipart-collection helper surface a clean error
// string back to SubmitJob for HTTP 400 responses.
type httpUserError struct{ msg string }

func (e *httpUserError) Error() string { return e.msg }
