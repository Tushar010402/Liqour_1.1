package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/excise/models"
	"github.com/liquorpro/go-backend/internal/excise/services"
)

// getTenantID extracts tenant ID from context
func getTenantID(c *gin.Context) (uuid.UUID, error) {
	// Try to get from context (set by auth middleware)
	if tenantIDValue, exists := c.Get("tenant_id"); exists {
		if tenantID, ok := tenantIDValue.(uuid.UUID); ok {
			return tenantID, nil
		}
	}
	return uuid.Nil, fmt.Errorf("tenant ID not found in context")
}

type ExciseHandlers struct {
	licenseService     *services.LicenseService
	reportService      *services.DailyReportService
	securityService    *services.SecurityCodeService
	complianceService  *services.ComplianceService
}

func NewExciseHandlers(
	licenseService *services.LicenseService,
	reportService *services.DailyReportService,
	securityService *services.SecurityCodeService,
	complianceService *services.ComplianceService,
) *ExciseHandlers {
	return &ExciseHandlers{
		licenseService:    licenseService,
		reportService:     reportService,
		securityService:   securityService,
		complianceService: complianceService,
	}
}

// ===================== LICENSE HANDLERS =====================

// CreateLicense creates a new excise license
func (h *ExciseHandlers) CreateLicense(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	_ = tenantID // Use it for validation/logging if needed

	var req models.CreateLicenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	license, err := h.licenseService.CreateLicense(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, license)
}

// GetLicenses retrieves all licenses for tenant
func (h *ExciseHandlers) GetLicenses(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})

	// Parse query parameters
	if isActive := c.Query("is_active"); isActive != "" {
		filters["is_active"] = isActive == "true"
	}
	if licenseType := c.Query("license_type"); licenseType != "" {
		filters["license_type"] = licenseType
	}
	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	licenses, err := h.licenseService.GetLicensesByTenant(tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, licenses)
}

// GetLicenseByID retrieves a single license
func (h *ExciseHandlers) GetLicenseByID(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	licenseID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid license ID"})
		return
	}

	license, err := h.licenseService.GetLicenseByID(tenantID, licenseID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, license)
}

// UpdateLicense updates a license
func (h *ExciseHandlers) UpdateLicense(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	licenseID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid license ID"})
		return
	}

	var req models.UpdateLicenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	license, err := h.licenseService.UpdateLicense(tenantID, licenseID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, license)
}

// PayLicenseFee records a license fee payment
func (h *ExciseHandlers) PayLicenseFee(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.PayLicenseFeeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	expense, err := h.licenseService.PayLicenseFee(tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, expense)
}

// GetLicenseFeePayments retrieves payment history for a license
func (h *ExciseHandlers) GetLicenseFeePayments(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	licenseID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid license ID"})
		return
	}

	payments, err := h.licenseService.GetLicenseFeePayments(tenantID, licenseID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, payments)
}

// GetLicenseComplianceStatus retrieves compliance status for a license
func (h *ExciseHandlers) GetLicenseComplianceStatus(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	licenseID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid license ID"})
		return
	}

	status, err := h.licenseService.GetComplianceStatus(tenantID, licenseID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, status)
}

// RenewLicense renews an expiring license
func (h *ExciseHandlers) RenewLicense(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	licenseID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid license ID"})
		return
	}

	var req struct {
		NewExpiryDate time.Time `json:"new_expiry_date" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	license, err := h.licenseService.RenewLicense(tenantID, licenseID, req.NewExpiryDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, license)
}

// ===================== DAILY REPORT HANDLERS =====================

// AutoGenerateDailyReport auto-generates a daily report
func (h *ExciseHandlers) AutoGenerateDailyReport(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.AutoGenerateReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	report, err := h.reportService.AutoGenerateDailyReport(tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, report)
}

// GetDailyReports retrieves daily reports
func (h *ExciseHandlers) GetDailyReports(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})
	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	reports, err := h.reportService.GetPendingReports(tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, reports)
}

// GetDailyReportByDate retrieves a report by date
func (h *ExciseHandlers) GetDailyReportByDate(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	shopID, err := uuid.Parse(c.Query("shop_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	date, err := time.Parse("2006-01-02", c.Param("date"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid date format"})
		return
	}

	report, err := h.reportService.GetReportByDate(tenantID, shopID, date)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, report)
}

// GetDailyReportByID retrieves a report by ID
func (h *ExciseHandlers) GetDailyReportByID(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	reportID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid report ID"})
		return
	}

	report, err := h.reportService.GetReportByID(tenantID, reportID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, report)
}

// UploadReportToPortal uploads a report to UP Excise portal
func (h *ExciseHandlers) UploadReportToPortal(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	reportID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid report ID"})
		return
	}

	report, err := h.reportService.UploadToPortal(tenantID, reportID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Report uploaded successfully",
		"report":  report,
	})
}

// RetryReportUpload retries uploading a failed report
func (h *ExciseHandlers) RetryReportUpload(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	reportID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid report ID"})
		return
	}

	report, err := h.reportService.RetryUpload(tenantID, reportID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Report uploaded successfully",
		"report":  report,
	})
}

// ===================== SECURITY CODE HANDLERS =====================

// ValidateSecurityCode validates a security code
func (h *ExciseHandlers) ValidateSecurityCode(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.ValidateSecurityCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.securityService.ValidateSecurityCode(tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// BulkAddSecurityCodes adds multiple security codes
func (h *ExciseHandlers) BulkAddSecurityCodes(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.BulkAddSecurityCodesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	codes, err := h.securityService.BulkAddSecurityCodes(tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Security codes added successfully",
		"count":   len(codes),
		"codes":   codes,
	})
}

// GetSecurityCode retrieves a security code
func (h *ExciseHandlers) GetSecurityCode(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	code := c.Param("code")

	response, err := h.securityService.GetSecurityCodeByCode(tenantID, code)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// SearchSecurityCodes searches security codes
func (h *ExciseHandlers) SearchSecurityCodes(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})

	if productID := c.Query("product_id"); productID != "" {
		if id, err := uuid.Parse(productID); err == nil {
			filters["product_id"] = id
		}
	}
	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}
	if sourceType := c.Query("source_type"); sourceType != "" {
		filters["source_type"] = sourceType
	}
	if batchNumber := c.Query("batch_number"); batchNumber != "" {
		filters["batch_number"] = batchNumber
	}

	codes, err := h.securityService.SearchSecurityCodes(tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, codes)
}

// MarkSecurityCodesAsSold marks security codes as sold
func (h *ExciseHandlers) MarkSecurityCodesAsSold(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req struct {
		SecurityCodes []string  `json:"security_codes" binding:"required"`
		SaleID        uuid.UUID `json:"sale_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.securityService.MarkAsSold(tenantID, req.SecurityCodes, req.SaleID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Security codes marked as sold"})
}

// MarkSecurityCodesAsDamaged marks security codes as damaged
func (h *ExciseHandlers) MarkSecurityCodesAsDamaged(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req struct {
		SecurityCodes []string `json:"security_codes" binding:"required"`
		Reason        string   `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.securityService.MarkAsDamaged(tenantID, req.SecurityCodes, req.Reason); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Security codes marked as damaged"})
}

// GetSecurityCodeStats retrieves statistics
func (h *ExciseHandlers) GetSecurityCodeStats(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if id, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &id
		}
	}

	stats, err := h.securityService.GetSecurityCodeStats(tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// ===================== COMPLIANCE HANDLERS =====================

// GetComplianceDashboard retrieves compliance dashboard
func (h *ExciseHandlers) GetComplianceDashboard(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if id, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &id
		}
	}

	dashboard, err := h.complianceService.GetComplianceDashboard(tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, dashboard)
}

// GetComplianceLogs retrieves compliance logs
func (h *ExciseHandlers) GetComplianceLogs(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})

	if logType := c.Query("log_type"); logType != "" {
		filters["log_type"] = logType
	}
	if logLevel := c.Query("log_level"); logLevel != "" {
		filters["log_level"] = logLevel
	}
	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	limit := 50
	if limitStr := c.Query("limit"); limitStr != "" {
		// Parse limit as integer
		if parsedLimit, err := strconv.Atoi(limitStr); err == nil && parsedLimit > 0 && parsedLimit <= 1000 {
			limit = parsedLimit
		}
	}

	logs, err := h.complianceService.GetComplianceLogs(tenantID, filters, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, logs)
}

// GetExpiringLicenses retrieves expiring licenses
func (h *ExciseHandlers) GetExpiringLicenses(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	daysAhead := 30
	if days := c.Query("days"); days != "" {
		// Parse days parameter if needed
	}

	licenses, err := h.complianceService.GetExpiringLicenses(tenantID, daysAhead)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, licenses)
}

// GetPendingLicenseFees retrieves pending license fees
func (h *ExciseHandlers) GetPendingLicenseFees(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if id, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &id
		}
	}

	fees, err := h.complianceService.GetPendingLicenseFees(tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, fees)
}

// GetConsiderationFeeSummary retrieves consideration fee summary
func (h *ExciseHandlers) GetConsiderationFeeSummary(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate, err := time.Parse("2006-01-02", c.Query("start_date"))
	if err != nil {
		startDate = time.Now().AddDate(0, -1, 0) // Default: last month
	}

	endDate, err := time.Parse("2006-01-02", c.Query("end_date"))
	if err != nil {
		endDate = time.Now() // Default: today
	}

	summary, err := h.complianceService.GetConsiderationFeeSummary(tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, summary)
}

// GetComplianceReport generates comprehensive compliance report
func (h *ExciseHandlers) GetComplianceReport(c *gin.Context) {
	tenantID, err := getTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate, err := time.Parse("2006-01-02", c.Query("start_date"))
	if err != nil {
		startDate = time.Now().AddDate(0, -1, 0)
	}

	endDate, err := time.Parse("2006-01-02", c.Query("end_date"))
	if err != nil {
		endDate = time.Now()
	}

	report, err := h.complianceService.GetComplianceReport(tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, report)
}
