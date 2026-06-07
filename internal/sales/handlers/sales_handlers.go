package handlers

import (
	"context"
	"fmt"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/validators"
)

// SalesHandlers handles HTTP requests for sales operations
type SalesHandlers struct {
	dailySalesService *services.DailySalesService
	salesService      *services.SalesService
	returnsService    *services.ReturnsService
	dashboardService  *services.DashboardService
	dayClosingService *services.DayClosingService
	aliasService      *alias.AliasService // v1.0.175 — Brand Shortcuts CRUD
	db                *database.DB        // v1.0.175 — direct alias list/delete
}

// NewSalesHandlers creates new sales handlers.
//
// v1.0.175 — added aliasService + db params so the Brand Shortcuts settings
// screen can list/create/delete operator-confirmed brand aliases. The
// existing Smart Sale matcher already reads the same ocr_brand_aliases
// rows; this just exposes them to the operator.
func NewSalesHandlers(
	dailySalesService *services.DailySalesService,
	salesService *services.SalesService,
	returnsService *services.ReturnsService,
	dashboardService *services.DashboardService,
	dayClosingService *services.DayClosingService,
	aliasService *alias.AliasService,
	db *database.DB,
) *SalesHandlers {
	return &SalesHandlers{
		dailySalesService: dailySalesService,
		salesService:      salesService,
		returnsService:    returnsService,
		dashboardService:  dashboardService,
		dayClosingService: dayClosingService,
		aliasService:      aliasService,
		db:                db,
	}
}

// ComponentStatus represents the health status of a single component
type ComponentStatus struct {
	Status  string `json:"status"`  // "up", "down", "degraded"
	Message string `json:"message,omitempty"`
}

// HealthResponse represents the structured health check response
type HealthResponse struct {
	Status     string                      `json:"status"` // "healthy", "degraded", "unhealthy"
	Service    string                      `json:"service"`
	Version    string                      `json:"version"`
	Components map[string]ComponentStatus  `json:"components"`
}

// Health check endpoint with dependency validation (2025 best practices)
// Returns 200 OK even if degraded to allow Docker/K8s to distinguish from network issues
func (h *SalesHandlers) Health(c *gin.Context) {
	components := make(map[string]ComponentStatus)
	overallStatus := "healthy"
	ctx := c.Request.Context()

	// Check database connectivity
	dbStatus := h.checkDatabase(ctx)
	components["database"] = dbStatus
	if dbStatus.Status == "down" {
		overallStatus = "unhealthy"
	} else if dbStatus.Status == "degraded" {
		overallStatus = "degraded"
	}

	// Check Redis cache connectivity
	cacheStatus := h.checkCache(ctx)
	components["cache"] = cacheStatus
	if cacheStatus.Status == "down" && overallStatus == "healthy" {
		overallStatus = "degraded" // Cache down is degraded, not unhealthy
	}

	// Return appropriate status code
	statusCode := http.StatusOK
	if overallStatus == "unhealthy" {
		statusCode = http.StatusServiceUnavailable
	}

	c.JSON(statusCode, HealthResponse{
		Status:     overallStatus,
		Service:    "sales",
		Version:    "1.0.0",
		Components: components,
	})
}

// checkDatabase validates database connectivity
func (h *SalesHandlers) checkDatabase(ctx context.Context) ComponentStatus {
	if h.dailySalesService == nil {
		return ComponentStatus{Status: "down", Message: "service not initialized"}
	}

	// Try to ping database through service
	if err := h.dailySalesService.HealthCheck(ctx); err != nil {
		return ComponentStatus{Status: "down", Message: fmt.Sprintf("connection failed: %v", err)}
	}

	return ComponentStatus{Status: "up"}
}

// checkCache validates Redis cache connectivity
func (h *SalesHandlers) checkCache(ctx context.Context) ComponentStatus {
	if h.dailySalesService == nil {
		return ComponentStatus{Status: "down", Message: "service not initialized"}
	}

	// Cache failures are non-critical, service can run without it
	if err := h.dailySalesService.CacheHealthCheck(ctx); err != nil {
		return ComponentStatus{Status: "degraded", Message: fmt.Sprintf("cache unavailable: %v", err)}
	}

	return ComponentStatus{Status: "up"}
}

// Daily Sales Endpoints (Critical for bulk entry workflow)

// CreateDailySalesRecord creates a new daily sales record
func (h *SalesHandlers) CreateDailySalesRecord(c *gin.Context) {
	tenantID, createdByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get user role from JWT context for auto-approval logic
	userRole := c.GetString("role")
	if userRole == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user role not found in context"})
		return
	}

	var req services.DailySalesRecordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.ShopID.String(), "shop_id")
	validator.Positive(req.TotalSalesAmount, "total_sales_amount")
	validator.NonNegative(req.TotalCashAmount, "total_cash_amount")
	validator.NonNegative(req.TotalCardAmount, "total_card_amount")
	validator.NonNegative(req.TotalUpiAmount, "total_upi_amount")
	validator.NonNegative(req.TotalCreditAmount, "total_credit_amount")

	// Validate items
	if len(req.Items) == 0 {
		validator.AddError("items", "at least one item is required")
	} else {
		for i, item := range req.Items {
			field := fmt.Sprintf("items[%d]", i)
			validator.Required(item.ProductID.String(), field+".product_id")
			validator.Positive(item.Quantity, field+".quantity")
			validator.Positive(item.UnitPrice, field+".unit_price")
			validator.Positive(item.TotalAmount, field+".total_amount")
		}
	}

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	record, err := h.dailySalesService.CreateDailySalesRecord(c.Request.Context(), req, tenantID, createdByID, userRole)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, record)
}

// GetDailySalesRecords returns paginated list of daily sales records
func (h *SalesHandlers) GetDailySalesRecords(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse filters
	var filters services.DailySalesFilters
	if err := c.ShouldBindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Enforce salesman shop filter
	if c.GetString("role") == "salesman" {
		if assignedShopID, err := h.dashboardService.GetSalesmanShopID(userID); err == nil && assignedShopID != nil {
			filters.ShopID = assignedShopID.String()
		}
	}

	// Translate SDUI date_filter shorthand to start_date/end_date
	if dateFilter := c.Query("date_filter"); dateFilter != "" && filters.StartDate.IsZero() {
		now := time.Now()
		today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
		switch dateFilter {
		case "today":
			filters.StartDate = today
			filters.EndDate = today
		case "yesterday":
			yesterday := today.AddDate(0, 0, -1)
			filters.StartDate = yesterday
			filters.EndDate = yesterday
		case "7d":
			filters.StartDate = today.AddDate(0, 0, -7)
			filters.EndDate = today
		case "15d":
			filters.StartDate = today.AddDate(0, 0, -15)
			filters.EndDate = today
		case "30d":
			filters.StartDate = today.AddDate(0, 0, -30)
			filters.EndDate = today
		case "this_month":
			filters.StartDate = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
			filters.EndDate = today
		case "last_month":
			firstOfMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
			filters.StartDate = firstOfMonth.AddDate(0, -1, 0)
			filters.EndDate = firstOfMonth.AddDate(0, 0, -1)
		}
	}

	// Set defaults
	if filters.Page <= 0 {
		filters.Page = 1
	}
	if filters.PageSize <= 0 || filters.PageSize > 100 {
		filters.PageSize = 20
	}

	records, err := h.dailySalesService.GetDailySalesRecords(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, records)
}

// GetDailySalesRecordByID returns daily sales record by ID
func (h *SalesHandlers) GetDailySalesRecordByID(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	record, err := h.dailySalesService.GetDailySalesRecordByID(c.Request.Context(), recordID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, record)
}

// UpdateDailySalesRecord updates daily sales record
func (h *SalesHandlers) UpdateDailySalesRecord(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	var req services.DailySalesRecordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request (similar to create)
	validator := validators.New()
	validator.Required(req.ShopID.String(), "shop_id")
	validator.Positive(req.TotalSalesAmount, "total_sales_amount")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	record, err := h.dailySalesService.UpdateDailySalesRecord(c.Request.Context(), recordID, tenantID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, record)
}

// UpdateDailySalesRecordDate is the dedicated PATCH endpoint for date-only
// edits from the admin sales list. Body: {"record_date": "2026-04-29"} or
// any RFC3339 timestamp. v1.0.121.
func (h *SalesHandlers) UpdateDailySalesRecordDate(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}
	var body struct {
		RecordDate string `json:"record_date" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// Accept either YYYY-MM-DD or full RFC3339 — frontend usually sends YYYY-MM-DD
	// from the <input type="date"> element.
	var parsed time.Time
	if t, e := time.Parse("2006-01-02", body.RecordDate); e == nil {
		parsed = t
	} else if t2, e2 := time.Parse(time.RFC3339, body.RecordDate); e2 == nil {
		parsed = t2
	} else {
		c.JSON(http.StatusBadRequest, gin.H{"error": "record_date must be YYYY-MM-DD or RFC3339"})
		return
	}
	rec, err := h.dailySalesService.UpdateDailySalesRecordDate(c.Request.Context(), recordID, tenantID, parsed)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, rec)
}

// ApproveDailySalesRecord approves a daily sales record
func (h *SalesHandlers) ApproveDailySalesRecord(c *gin.Context) {
	tenantID, approvedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	record, err := h.dailySalesService.ApproveDailySalesRecord(c.Request.Context(), recordID, tenantID, approvedByID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, record)
}

// ReapplyDailySalesRecord re-applies an approved daily sales record's stock
// effects within 7 days of approval. Mirror of Stock Setup's reapply.
// 410 Gone past the 7-day window. 409 if the record isn't approved.
func (h *SalesHandlers) ReapplyDailySalesRecord(c *gin.Context) {
	tenantID, reappliedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}
	record, err := h.dailySalesService.ReapplyDailySalesRecord(c.Request.Context(), recordID, tenantID, reappliedByID)
	if err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "reapply window expired"):
			c.JSON(http.StatusGone, gin.H{"error": msg})
		case strings.Contains(msg, "only approved records"):
			c.JSON(http.StatusConflict, gin.H{"error": msg})
		case strings.Contains(msg, "not found"):
			c.JSON(http.StatusNotFound, gin.H{"error": msg})
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		}
		return
	}
	c.JSON(http.StatusOK, record)
}

// RejectDailySalesRecord rejects a daily sales record
func (h *SalesHandlers) RejectDailySalesRecord(c *gin.Context) {
	tenantID, rejectedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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

	if err := h.dailySalesService.RejectDailySalesRecord(c.Request.Context(), recordID, tenantID, rejectedByID, req.Reason); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Daily sales record rejected successfully"})
}

// Individual Sales Endpoints

// CreateSale creates a new individual sale
func (h *SalesHandlers) CreateSale(c *gin.Context) {
	tenantID, createdByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var req services.SaleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.ShopID.String(), "shop_id")
	validator.ValidPaymentMethod(req.PaymentMethod, "payment_method")
	validator.NonNegative(req.PaidAmount, "paid_amount")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	sale, err := h.salesService.CreateSale(c.Request.Context(), req, tenantID, createdByID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, sale)
}

// GetSales returns paginated list of sales
func (h *SalesHandlers) GetSales(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse filters
	var filters services.SalesFilters
	if err := c.ShouldBindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Enforce salesman shop filter
	if c.GetString("role") == "salesman" {
		if assignedShopID, err := h.dashboardService.GetSalesmanShopID(userID); err == nil && assignedShopID != nil {
			filters.ShopID = *assignedShopID
		}
	}

	// Set defaults
	if filters.Page <= 0 {
		filters.Page = 1
	}
	if filters.PageSize <= 0 || filters.PageSize > 100 {
		filters.PageSize = 20
	}

	sales, err := h.salesService.GetSales(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sales)
}

// GetSaleByID returns sale by ID
func (h *SalesHandlers) GetSaleByID(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	saleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sale ID"})
		return
	}

	sale, err := h.salesService.GetSaleByID(c.Request.Context(), saleID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sale)
}

// ApproveSale approves a sale
func (h *SalesHandlers) ApproveSale(c *gin.Context) {
	tenantID, approvedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	saleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sale ID"})
		return
	}

	sale, err := h.salesService.ApproveSale(c.Request.Context(), saleID, tenantID, approvedByID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sale)
}

// RejectSale rejects a sale
func (h *SalesHandlers) RejectSale(c *gin.Context) {
	tenantID, rejectedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	saleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sale ID"})
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.salesService.RejectSale(c.Request.Context(), saleID, tenantID, rejectedByID, req.Reason); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Sale rejected successfully"})
}

// GetPendingSales returns pending sales
func (h *SalesHandlers) GetPendingSales(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &parsed
		}
	}
	shopID = h.enforceSalesmanShop(c, userID, shopID)

	sales, err := h.salesService.GetPendingSales(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sales)
}

// GetUncollectedSales returns sales with due amounts
func (h *SalesHandlers) GetUncollectedSales(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &parsed
		}
	}
	shopID = h.enforceSalesmanShop(c, userID, shopID)

	sales, err := h.salesService.GetUncollectedSales(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sales)
}

// Returns Endpoints

// CreateSaleReturn creates a new sale return
func (h *SalesHandlers) CreateSaleReturn(c *gin.Context) {
	tenantID, createdByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var req services.SaleReturnRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.SaleID.String(), "sale_id")
	validator.Required(req.Reason, "reason")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	saleReturn, err := h.returnsService.CreateSaleReturn(c.Request.Context(), req, tenantID, createdByID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, saleReturn)
}

// GetSaleReturns returns paginated list of returns
func (h *SalesHandlers) GetSaleReturns(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse filters
	var filters services.ReturnsFilters
	if err := c.ShouldBindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Enforce salesman shop filter
	if c.GetString("role") == "salesman" {
		if assignedShopID, err := h.dashboardService.GetSalesmanShopID(userID); err == nil && assignedShopID != nil {
			filters.ShopID = *assignedShopID
		}
	}

	// Set defaults
	if filters.Page <= 0 {
		filters.Page = 1
	}
	if filters.PageSize <= 0 || filters.PageSize > 100 {
		filters.PageSize = 20
	}

	returns, err := h.returnsService.GetSaleReturns(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, returns)
}

// GetSaleReturnByID returns sale return by ID
func (h *SalesHandlers) GetSaleReturnByID(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	returnID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid return ID"})
		return
	}

	saleReturn, err := h.returnsService.GetSaleReturnByID(c.Request.Context(), returnID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, saleReturn)
}

// ApproveSaleReturn approves a sale return
func (h *SalesHandlers) ApproveSaleReturn(c *gin.Context) {
	tenantID, approvedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	returnID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid return ID"})
		return
	}

	saleReturn, err := h.returnsService.ApproveSaleReturn(c.Request.Context(), returnID, tenantID, approvedByID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, saleReturn)
}

// RejectSaleReturn rejects a sale return
func (h *SalesHandlers) RejectSaleReturn(c *gin.Context) {
	tenantID, rejectedByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	returnID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid return ID"})
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.returnsService.RejectSaleReturn(c.Request.Context(), returnID, tenantID, rejectedByID, req.Reason); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Sale return rejected successfully"})
}

// GetPendingReturns returns pending returns
func (h *SalesHandlers) GetPendingReturns(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &parsed
		}
	}
	shopID = h.enforceSalesmanShop(c, userID, shopID)

	returns, err := h.returnsService.GetPendingReturns(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, returns)
}

// Dashboard Endpoints

// GetDashboardSummary returns dashboard summary
func (h *SalesHandlers) GetDashboardSummary(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &parsed
		}
	}
	shopID = h.enforceSalesmanShop(c, userID, shopID)

	dateFilter := c.DefaultQuery("date_filter", "today")
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	summary, err := h.dashboardService.GetDashboardSummary(c.Request.Context(), tenantID, shopID, dateFilter, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, summary)
}

// Day Closing Endpoints

// SaveDayClosing saves day-closing reconciliation data (upsert)
func (h *SalesHandlers) SaveDayClosing(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var req services.DayClosingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate
	validator := validators.New()
	validator.Required(req.ShopID.String(), "shop_id")
	validator.Required(req.Date, "date")
	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	resp, err := h.dayClosingService.SaveDayClosing(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, resp)
}

// GetDayClosing retrieves day-closing data for a shop+date
func (h *SalesHandlers) GetDayClosing(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	shopIDStr := c.Query("shop_id")
	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
		return
	}

	date := c.Query("date")
	if date == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date is required"})
		return
	}

	resp, err := h.dayClosingService.GetDayClosing(c.Request.Context(), tenantID, shopID, date)
	if err != nil {
		// No record for this date is normal — return null, not 404
		c.JSON(http.StatusOK, nil)
		return
	}

	c.JSON(http.StatusOK, resp)
}

// Helper methods

// enforceSalesmanShop returns the shop_id that should be used for filtering.
// For salesman role, it forces their assigned shop. For other roles, it uses the provided shopID.
func (h *SalesHandlers) enforceSalesmanShop(c *gin.Context, userID uuid.UUID, requestedShopID *uuid.UUID) *uuid.UUID {
	userRole := c.GetString("role")
	if userRole == "salesman" {
		assignedShopID, err := h.dashboardService.GetSalesmanShopID(userID)
		if err != nil {
			// Fail securely: deny access if we can't verify the salesman's shop assignment
			return nil
		}
		if assignedShopID != nil {
			return assignedShopID
		}
		// Salesman has no assigned shop — deny access
		return nil
	}
	return requestedShopID
}

func (h *SalesHandlers) getTenantAndUserID(c *gin.Context) (tenantID, userID uuid.UUID, err error) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.GetString("user_id")
	userRole := c.GetString("role")

	// User ID is always required
	if userIDStr == "" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("user ID not found in context")
	}

	userID, err = uuid.Parse(userIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid user ID")
	}

	// For saas_admin users, tenant_id can be empty (they have system-wide access)
	if userRole == "saas_admin" {
		// Return uuid.Nil for tenant_id to indicate no tenant restriction
		return uuid.Nil, userID, nil
	}

	// For all other users, tenant_id is required
	if tenantIDStr == "" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("tenant ID not found in context")
	}

	tenantID, err = uuid.Parse(tenantIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid tenant ID")
	}

	return tenantID, userID, nil
}

// UploadDailySalesImage handles receipt image upload for manual daily sales entries
func (h *SalesHandlers) UploadDailySalesImage(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse multipart form (max 10MB)
	if err := c.Request.ParseMultipartForm(10 << 20); err != nil {
		fmt.Printf("📤 [UPLOAD] ParseMultipartForm error: %v, Content-Type: %s\n", err, c.ContentType())
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid multipart form: %v", err)})
		return
	}

	// Log all form fields for debugging
	if c.Request.MultipartForm != nil && c.Request.MultipartForm.File != nil {
		for key, files := range c.Request.MultipartForm.File {
			fmt.Printf("📤 [UPLOAD] Form file field: '%s' (%d files)\n", key, len(files))
		}
	} else {
		fmt.Printf("📤 [UPLOAD] No multipart files found. Content-Type: %s\n", c.ContentType())
	}

	// Try all common field names
	var header *multipart.FileHeader
	for _, field := range []string{"image", "file", "photo", "receipt", "images", "images[]"} {
		_, h, e := c.Request.FormFile(field)
		if e == nil {
			header = h
			fmt.Printf("📤 [UPLOAD] Found image in field '%s': %s (%d bytes)\n", field, h.Filename, h.Size)
			break
		}
	}
	if header == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image file is required (field: image, file, photo, receipt, images)"})
		return
	}

	// Validate file type
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "only JPG and PNG images are supported"})
		return
	}

	// Validate file size (max 10MB)
	if header.Size > 10*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image size must be under 10MB"})
		return
	}

	// Create upload directory
	tenantShort := tenantID.String()[:8]
	uploadDir := filepath.Join("/app/uploads/daily_sales", tenantShort)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create upload directory"})
		return
	}

	// Save file with unique name
	fileName := fmt.Sprintf("daily_sales_%s_%s%s", tenantShort, uuid.New().String()[:8], ext)
	filePath := filepath.Join(uploadDir, fileName)

	if err := c.SaveUploadedFile(header, filePath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save image"})
		return
	}

	// Return the URL path (relative to uploads root)
	imageURL := fmt.Sprintf("/uploads/daily_sales/%s/%s", tenantShort, fileName)

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"image_url": imageURL,
		"file_name": fileName,
		"file_size": header.Size,
	})
}

// ReorderDailySalesItems persists the operator's drag-reorder of items on
// the Sales Summary screen. Body: {"items": [{"id": "<uuid>", "position": 0}, ...]}.
// Bulk-updates daily_sales_items.position so every other view (web admin,
// daily entry summary, sales history, exports) renders the same order.
//
// v1.0.149 — first user-driven row-order persistence. Initial order on
// Smart Sale apply is page*1000+row_number (image order); the operator
// can refine that here.
func (h *SalesHandlers) ReorderDailySalesItems(c *gin.Context) {
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant not found"})
		return
	}
	tenantID, ok := tenantIDRaw.(uuid.UUID)
	if !ok {
		// Sometimes set as string; convert.
		if s, sok := tenantIDRaw.(string); sok {
			parsed, err := uuid.Parse(s)
			if err != nil {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid tenant"})
				return
			}
			tenantID = parsed
		} else {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid tenant"})
			return
		}
	}
	recordIDStr := c.Param("id")
	recordID, err := uuid.Parse(recordIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid record id"})
		return
	}
	var req struct {
		Items []struct {
			ID       string `json:"id" binding:"required"`
			Position int    `json:"position"`
		} `json:"items" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid body: %v", err)})
		return
	}
	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "items required"})
		return
	}
	if len(req.Items) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "too many items in one reorder (max 500)"})
		return
	}
	pairs := make([]services.ItemPosition, 0, len(req.Items))
	for _, it := range req.Items {
		id, err := uuid.Parse(it.ID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid item id: %s", it.ID)})
			return
		}
		pairs = append(pairs, services.ItemPosition{ID: id, Position: it.Position})
	}
	if err := h.dailySalesService.ReorderItems(c.Request.Context(), recordID, tenantID, pairs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"updated": len(pairs)})
}

// HealApproveCorruption fixes opening/closing on daily_sales_items rows where
// the v1.0.133-r4 approval-time bug stamped opening==closing. Admin-gated.
// Body: {"record_ids": ["<uuid>", ...], "dry_run": true|false}.
//
// v1.0.162.
func (h *SalesHandlers) HealApproveCorruption(c *gin.Context) {
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant not found"})
		return
	}
	tenantID, ok := tenantIDRaw.(uuid.UUID)
	if !ok {
		if s, sok := tenantIDRaw.(string); sok {
			parsed, err := uuid.Parse(s)
			if err != nil {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid tenant"})
				return
			}
			tenantID = parsed
		} else {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid tenant"})
			return
		}
	}
	var req struct {
		RecordIDs []string `json:"record_ids" binding:"required"`
		DryRun    bool     `json:"dry_run"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid body: %v", err)})
		return
	}
	if len(req.RecordIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "record_ids required"})
		return
	}
	parsedIDs := make([]uuid.UUID, 0, len(req.RecordIDs))
	for _, idStr := range req.RecordIDs {
		id, err := uuid.Parse(strings.TrimSpace(idStr))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid record_id: %s", idStr)})
			return
		}
		parsedIDs = append(parsedIDs, id)
	}
	result, err := h.dailySalesService.HealApproveCorruption(c.Request.Context(), tenantID, parsedIDs, req.DryRun)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// =====================================================================
// v1.0.175 — Brand Shortcuts management
//
// Three handlers expose the operator-confirmed brand-alias corpus the
// Smart Sale + Stock Setup matchers already consume:
//
//   GET    /api/sales/aliases?shop_id=<uuid_or_blank>
//   POST   /api/sales/aliases
//   DELETE /api/sales/aliases/:id
//
// Today operators couldn't see, edit, or remove the entries they
// (or auto-learning) accumulated. This unblocks the "Brand Shortcuts"
// settings screen and gives shopkeepers a UI for the alias loop their
// app already silently maintains.
//
// All three pull tenant_id from the authenticated context; shop_id
// comes from the query/body and may be blank (tenant-wide rows). Soft-
// delete via ocr_brand_aliases.deleted_at = NOW() (column was added
// in 20260504_add_shop_scope_to_aliases.sql so the lookup cascade
// already filters them out).
// =====================================================================

// salesHandlersExtractTenantID centralises the (uuid|string) → uuid.UUID
// coercion used throughout this file. Returns false on failure with
// a 401 already written to the response.
func (h *SalesHandlers) salesHandlersExtractTenantID(c *gin.Context) (uuid.UUID, bool) {
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant not found"})
		return uuid.Nil, false
	}
	if id, ok := tenantIDRaw.(uuid.UUID); ok {
		return id, true
	}
	if s, sok := tenantIDRaw.(string); sok {
		parsed, err := uuid.Parse(s)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid tenant"})
			return uuid.Nil, false
		}
		return parsed, true
	}
	c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid tenant"})
	return uuid.Nil, false
}

// brandAliasResponse is the shape a single alias row takes on the wire.
// Kept flat so the Flutter list cell can bind directly without nested
// model classes.
type brandAliasResponse struct {
	ID                 string     `json:"id"`
	AliasName          string     `json:"alias_name"`
	CanonicalBrandName string     `json:"canonical_brand_name"`
	ProductID          *string    `json:"product_id,omitempty"`
	ShopID             *string    `json:"shop_id,omitempty"`
	Source             string     `json:"source"`
	OccurrenceCount    int        `json:"occurrence_count"`
	ConfidenceScore    float64    `json:"confidence_score"`
	LastUsedAt         *time.Time `json:"last_used_at,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
}

func toBrandAliasResponse(a models.OCRBrandAlias) brandAliasResponse {
	resp := brandAliasResponse{
		ID:                 a.ID.String(),
		AliasName:          a.AliasName,
		CanonicalBrandName: a.CanonicalBrandName,
		Source:             a.Source,
		OccurrenceCount:    a.OccurrenceCount,
		ConfidenceScore:    a.ConfidenceScore,
		LastUsedAt:         a.LastUsedAt,
		CreatedAt:          a.CreatedAt,
	}
	if a.ProductID != nil {
		s := a.ProductID.String()
		resp.ProductID = &s
	}
	if a.ShopID != nil {
		s := a.ShopID.String()
		resp.ShopID = &s
	}
	return resp
}

// ListBrandAliases returns operator-visible aliases split by scope:
//
//	tenant_aliases — shop_id IS NULL rows (apply to every shop)
//	shop_aliases   — shop_id = <query.shop_id> rows (current shop only)
//
// When shop_id is blank, shop_aliases is empty. Soft-deleted rows are
// excluded server-side (deleted_at IS NOT NULL).
//
// Sorted by occurrence_count DESC, last_used_at DESC NULLS LAST so the
// "most useful" rows surface first in the UI. Capped at 1000 per scope
// to keep the payload reasonable; the Flutter side filters client-side.
func (h *SalesHandlers) ListBrandAliases(c *gin.Context) {
	tenantID, ok := h.salesHandlersExtractTenantID(c)
	if !ok {
		return
	}
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "alias service not configured"})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := strings.TrimSpace(c.Query("shop_id")); shopIDStr != "" {
		parsed, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
		shopID = &parsed
	}

	const maxPerScope = 1000

	// Tenant-wide rows (always returned).
	var tenantRows []models.OCRBrandAlias
	if err := h.db.Model(&models.OCRBrandAlias{}).
		Where("tenant_id = ? AND shop_id IS NULL AND deleted_at IS NULL", tenantID).
		Order("occurrence_count DESC, last_used_at DESC NULLS LAST, alias_name ASC").
		Limit(maxPerScope).
		Find(&tenantRows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("list tenant aliases: %v", err)})
		return
	}

	// Shop-scoped rows — only when caller asked for a shop.
	var shopRows []models.OCRBrandAlias
	if shopID != nil {
		if err := h.db.Model(&models.OCRBrandAlias{}).
			Where("tenant_id = ? AND shop_id = ? AND deleted_at IS NULL", tenantID, *shopID).
			Order("occurrence_count DESC, last_used_at DESC NULLS LAST, alias_name ASC").
			Limit(maxPerScope).
			Find(&shopRows).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("list shop aliases: %v", err)})
			return
		}
	}

	tenantOut := make([]brandAliasResponse, 0, len(tenantRows))
	for _, row := range tenantRows {
		tenantOut = append(tenantOut, toBrandAliasResponse(row))
	}
	shopOut := make([]brandAliasResponse, 0, len(shopRows))
	for _, row := range shopRows {
		shopOut = append(shopOut, toBrandAliasResponse(row))
	}

	c.JSON(http.StatusOK, gin.H{
		"tenant_aliases": tenantOut,
		"shop_aliases":   shopOut,
		"shop_id":        shopID,
		"counts": gin.H{
			"tenant": len(tenantOut),
			"shop":   len(shopOut),
		},
	})
}

// CreateBrandAlias writes an operator-defined alias.
//
// Body:
//
//	{
//	  "ocr_text":   "MCD",                                  // required, ≥2 chars
//	  "product_id": "<uuid>",                               // required
//	  "scope":      "shop" | "tenant",                      // required
//	  "shop_id":    "<uuid>"                                // required when scope=shop
//	}
//
// Goes through the same hygiene gate the auto-learning loop uses
// (LearnAliasScoped → jaccard ≥ 0.20, not blocked by negative alias)
// so manual entries can't bypass safety checks. source = "user_manual"
// scores 80.0 (same band as user_correction-grade learning).
func (h *SalesHandlers) CreateBrandAlias(c *gin.Context) {
	tenantID, ok := h.salesHandlersExtractTenantID(c)
	if !ok {
		return
	}
	if h.aliasService == nil || h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "alias service not configured"})
		return
	}

	var req struct {
		OCRText   string `json:"ocr_text" binding:"required"`
		ProductID string `json:"product_id" binding:"required"`
		Scope     string `json:"scope" binding:"required"`
		ShopID    string `json:"shop_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid body: %v", err)})
		return
	}

	ocrText := strings.TrimSpace(req.OCRText)
	if len(ocrText) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ocr_text must be at least 2 characters"})
		return
	}

	productID, err := uuid.Parse(strings.TrimSpace(req.ProductID))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid product_id"})
		return
	}

	scope := strings.ToLower(strings.TrimSpace(req.Scope))
	if scope != "shop" && scope != "tenant" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "scope must be 'shop' or 'tenant'"})
		return
	}

	var shopID uuid.UUID
	if scope == "shop" {
		if strings.TrimSpace(req.ShopID) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id required when scope=shop"})
			return
		}
		parsed, err := uuid.Parse(strings.TrimSpace(req.ShopID))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
		shopID = parsed
	}

	// Look up the canonical brand/product name so the alias row carries
	// it (the matcher reads canonical_brand_name straight off the row).
	var product models.Product
	if err := h.db.Model(&models.Product{}).
		Where("id = ? AND tenant_id = ?", productID, tenantID).
		First(&product).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "product not found in this tenant"})
		return
	}
	canonical := product.Name
	if canonical == "" {
		canonical = ocrText // last-resort fallback so we never write empty canonical
	}

	if err := h.aliasService.LearnAliasScoped(tenantID, shopID, ocrText, canonical, &productID, "user_manual"); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("learn alias: %v", err)})
		return
	}
	// v1.0.199 — when the operator targets a SHOP scope, also mirror the
	// alias tenant-wide as the cross-shop default. Skip when scope=="tenant"
	// (already tenant) or shop is nil. This is the manual brand-shortcuts UX
	// path; manual writes should propagate by default — operators rarely want
	// a per-shop brand-shortcut override.
	if scope == "shop" && shopID != uuid.Nil {
		_ = h.aliasService.LearnAliasScoped(tenantID, uuid.Nil, ocrText, canonical, &productID, "user_manual_tenant")
	}

	// Read back the freshly upserted row so the client gets the canonical
	// id/timestamps for optimistic UI updates.
	var saved models.OCRBrandAlias
	q := h.db.Model(&models.OCRBrandAlias{}).
		Where("tenant_id = ? AND LOWER(alias_name) = ? AND deleted_at IS NULL",
			tenantID, strings.ToLower(ocrText))
	if scope == "shop" {
		q = q.Where("shop_id = ?", shopID)
	} else {
		q = q.Where("shop_id IS NULL")
	}
	if err := q.First(&saved).Error; err != nil {
		// Hygiene gate may have rejected (jaccard < 0.20, blocked negative,
		// etc.) — surface a 200 with a no-op marker so the UI can show
		// "Shortcut not added (rejected by safety check)".
		c.JSON(http.StatusOK, gin.H{
			"alias":    nil,
			"created":  false,
			"message":  "alias not stored — failed hygiene gate (too dissimilar from canonical, or in negative-alias table)",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"alias":   toBrandAliasResponse(saved),
		"created": true,
	})
}

// DeleteBrandAlias soft-deletes a brand alias by ID. Tenant-scoped — a
// tenant cannot remove another tenant's alias even if the ID is guessed.
// We also invalidate the Redis cache for the underlying (tenant, shop,
// alias_name) key by simply re-using the alias-service path: write
// deleted_at and let the next lookup miss + repopulate.
func (h *SalesHandlers) DeleteBrandAlias(c *gin.Context) {
	tenantID, ok := h.salesHandlersExtractTenantID(c)
	if !ok {
		return
	}
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "alias service not configured"})
		return
	}

	idStr := c.Param("id")
	id, err := uuid.Parse(strings.TrimSpace(idStr))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid alias id"})
		return
	}

	// Soft-delete — UPDATE … SET deleted_at = NOW() scoped to tenant_id.
	// RowsAffected lets us 404 cleanly when nothing matched.
	res := h.db.Exec(
		`UPDATE ocr_brand_aliases SET deleted_at = NOW(), updated_at = NOW()
		 WHERE id = ? AND tenant_id = ? AND deleted_at IS NULL`,
		id, tenantID,
	)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("delete alias: %v", res.Error)})
		return
	}
	if res.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "alias not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"deleted": true, "id": id.String()})
}

// ListSuggestedAliases — v1.0.182 Track D2.
//
// GET /sales/aliases/suggested?shop_id=<uuid>&days=30
//
// Returns the top OCR strings (last N days, default 30) extracted by Smart
// Sale that hit `not_found` / `low_confidence` / `not_matched` AND don't
// have a learned alias yet. Each row carries occurrence_count so the UI
// can prioritise the most-frequently-stuck strings. Caps at top 50.
//
// Source: smart_sale_setup_jobs.result->'extracted_items' jsonb. Each item
// with status in (not_found, low_confidence, not_matched) contributes its
// raw_brand_name / ocr_text. Aliases that already exist in
// ocr_brand_aliases (any source, any shop scope) are excluded.
//
// Tenant-scoped via auth context. shop_id query param optional — when
// blank, returns tenant-wide stuck strings; when set, filters to that shop
// only. Operator UX: Brand Shortcuts page renders this with a 2-tap "map
// to existing brand" flow that POSTs back to /sales/aliases.
func (h *SalesHandlers) ListSuggestedAliases(c *gin.Context) {
	tenantID, ok := h.salesHandlersExtractTenantID(c)
	if !ok {
		return
	}
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "alias service not configured"})
		return
	}
	days := 30
	if v := strings.TrimSpace(c.Query("days")); v != "" {
		var d int
		if _, err := fmt.Sscanf(v, "%d", &d); err == nil && d > 0 && d <= 90 {
			days = d
		}
	}
	since := time.Now().AddDate(0, 0, -days)

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

	type suggestion struct {
		OCRText         string `json:"ocr_text"`
		OccurrenceCount int    `json:"occurrence_count"`
		LastSeen        string `json:"last_seen"`
		ExampleStatus   string `json:"example_status"`
	}

	rows, err := h.db.DB.Raw(`
		WITH extracted AS (
			SELECT
				j.shop_id,
				j.created_at,
				LOWER(TRIM(COALESCE(item->>'ocr_text',
				                    item->>'original_ai_brand',
				                    item->>'brand_name',
				                    item->>'raw_brand_name',
				                    ''))) AS ocr_text,
				LOWER(TRIM(COALESCE(item->>'validation_status', ''))) AS validation_status
			FROM smart_sale_setup_jobs j,
			     jsonb_array_elements(COALESCE(j.result->'extracted_items','[]'::jsonb)) item
			WHERE j.tenant_id = ?
			  AND j.created_at >= ?
			  AND j.deleted_at IS NULL
			  AND j.status = 'done'
			  AND (? = '' OR j.shop_id = ?)
		)
		SELECT
			ocr_text,
			COUNT(*) AS occ,
			MAX(created_at)::text AS last_seen,
			MAX(validation_status) AS example_status
		FROM extracted
		WHERE ocr_text <> ''
		  AND length(ocr_text) >= 3
		  AND validation_status IN ('not_found','low_confidence','ambiguous','no_match','missing','not_matched')
		  AND NOT EXISTS (
		      SELECT 1 FROM ocr_brand_aliases a
		      WHERE a.tenant_id = ?
		        AND LOWER(a.alias_name) = ocr_text
		        AND a.deleted_at IS NULL
		  )
		GROUP BY ocr_text
		HAVING COUNT(*) >= 2
		ORDER BY occ DESC, last_seen DESC
		LIMIT 50
	`, tenantID, since, shopFilter, shopUUID, tenantID).Rows()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	out := make([]suggestion, 0, 16)
	for rows.Next() {
		var s suggestion
		if err := rows.Scan(&s.OCRText, &s.OccurrenceCount, &s.LastSeen, &s.ExampleStatus); err != nil {
			continue
		}
		out = append(out, s)
	}
	c.JSON(http.StatusOK, gin.H{
		"days":        days,
		"since":       since.UTC().Format(time.RFC3339),
		"suggestions": out,
		"count":       len(out),
	})
}
