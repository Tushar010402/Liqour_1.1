package handlers

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/validators"
)

// SalesHandlers handles HTTP requests for sales operations
type SalesHandlers struct {
	dailySalesService *services.DailySalesService
	salesService      *services.SalesService
	returnsService    *services.ReturnsService
	dashboardService  *services.DashboardService
}

// NewSalesHandlers creates new sales handlers
func NewSalesHandlers(
	dailySalesService *services.DailySalesService,
	salesService *services.SalesService,
	returnsService *services.ReturnsService,
	dashboardService *services.DashboardService,
) *SalesHandlers {
	return &SalesHandlers{
		dailySalesService: dailySalesService,
		salesService:      salesService,
		returnsService:    returnsService,
		dashboardService:  dashboardService,
	}
}

// Health check endpoint
func (h *SalesHandlers) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"service": "sales",
	})
}

// Daily Sales Endpoints (Critical for bulk entry workflow)

// CreateDailySalesRecord creates a new daily sales record
func (h *SalesHandlers) CreateDailySalesRecord(c *gin.Context) {
	tenantID, createdByID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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

	record, err := h.dailySalesService.CreateDailySalesRecord(c.Request.Context(), req, tenantID, createdByID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, record)
}

// GetDailySalesRecords returns paginated list of daily sales records
func (h *SalesHandlers) GetDailySalesRecords(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
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
	tenantID, _, err := h.getTenantAndUserID(c)
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
	tenantID, _, err := h.getTenantAndUserID(c)
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

	sales, err := h.salesService.GetPendingSales(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, sales)
}

// GetUncollectedSales returns sales with due amounts
func (h *SalesHandlers) GetUncollectedSales(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
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
	tenantID, _, err := h.getTenantAndUserID(c)
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
	tenantID, _, err := h.getTenantAndUserID(c)
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
	tenantID, _, err := h.getTenantAndUserID(c)
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

	summary, err := h.dashboardService.GetDashboardSummary(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, summary)
}

// Helper methods


func (h *SalesHandlers) getTenantAndUserID(c *gin.Context) (tenantID, userID uuid.UUID, err error) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.GetString("user_id")

	if tenantIDStr == "" || userIDStr == "" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("tenant ID or user ID not found in context")
	}

	tenantID, err = uuid.Parse(tenantIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid tenant ID")
	}

	userID, err = uuid.Parse(userIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid user ID")
	}

	return tenantID, userID, nil
}