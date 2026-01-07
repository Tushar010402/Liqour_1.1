package handlers

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"github.com/liquorpro/go-backend/pkg/shared/validators"
)

// SalesHandlers handles HTTP requests for sales operations
type SalesHandlers struct {
	dailySalesService *services.DailySalesService
	salesService      *services.SalesService
	returnsService    *services.ReturnsService
	dashboardService  *services.DashboardService
	validationService *services.ValidationService
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

// SetValidationService sets the validation service for AI-powered validation
func (h *SalesHandlers) SetValidationService(vs *services.ValidationService) {
	h.validationService = vs
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

	// Enforce shop restriction for salesmen - they can only create records for their shop
	enforcedShopID, err := h.enforceShopFilter(c, &req.ShopID, tenantID, createdByID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	req.ShopID = enforcedShopID

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

	// Auto-trigger AI validation if images are attached
	if h.validationService != nil && len(req.ImageURLs) > 0 {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			defer cancel()
			if err := h.validationService.TriggerValidation(ctx, record.ID, tenantID); err != nil {
				fmt.Printf("[SalesHandler] Auto-validation failed for record %s: %v\n", record.ID, err)
			} else {
				fmt.Printf("[SalesHandler] Auto-validation triggered for record %s\n", record.ID)
			}
		}()
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

	// Enforce shop restriction for salesmen
	var filterShopPtr *uuid.UUID
	if filters.ShopID != uuid.Nil {
		filterShopPtr = &filters.ShopID
	}
	enforcedShopID, err := h.enforceShopFilter(c, filterShopPtr, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	filters.ShopID = enforcedShopID

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

// CheckDailySalesRecordExists - Flutter calls this BEFORE restoring drafts
// SINGLE SOURCE OF TRUTH for draft management - prevents race conditions and stale drafts
func (h *SalesHandlers) CheckDailySalesRecordExists(c *gin.Context) {
	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse query params: ?shop_id=xxx&record_date=2026-01-06
	shopIDStr := c.Query("shop_id")
	recordDateStr := c.Query("record_date")

	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	if recordDateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "record_date is required"})
		return
	}

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id format"})
		return
	}

	recordDate, err := time.Parse("2006-01-02", recordDateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record_date format (use YYYY-MM-DD)"})
		return
	}

	result, err := h.dailySalesService.CheckRecordExistsForShopDate(
		c.Request.Context(), tenantID, shopID, recordDate,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// UpdateDailySalesRecord updates daily sales record
func (h *SalesHandlers) UpdateDailySalesRecord(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get user role for admin override check
	userRole := c.GetString("role")

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

	// Enforce shop restriction for salesmen
	enforcedShopID, err := h.enforceShopFilter(c, &req.ShopID, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	req.ShopID = enforcedShopID

	record, err := h.dailySalesService.UpdateDailySalesRecord(c.Request.Context(), recordID, tenantID, userRole, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Re-trigger AI validation if images are attached (data may have changed)
	if h.validationService != nil && len(req.ImageURLs) > 0 {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			defer cancel()
			if err := h.validationService.TriggerValidation(ctx, record.ID, tenantID); err != nil {
				fmt.Printf("[SalesHandler] Auto-validation failed for updated record %s: %v\n", record.ID, err)
			} else {
				fmt.Printf("[SalesHandler] Auto-validation re-triggered for updated record %s\n", record.ID)
			}
		}()
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

	// Enforce shop restriction for salesmen - they can only create sales for their shop
	enforcedShopID, err := h.enforceShopFilter(c, &req.ShopID, tenantID, createdByID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	req.ShopID = enforcedShopID

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

	// Enforce shop restriction for salesmen
	var filterShopPtr *uuid.UUID
	if filters.ShopID != uuid.Nil {
		filterShopPtr = &filters.ShopID
	}
	enforcedShopID, err := h.enforceShopFilter(c, filterShopPtr, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	filters.ShopID = enforcedShopID

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

// UpdateSale updates an existing sale
func (h *SalesHandlers) UpdateSale(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get user role from context
	userRole, exists := c.Get("role")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user role not found"})
		return
	}
	roleStr, ok := userRole.(string)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid role type"})
		return
	}

	saleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sale ID"})
		return
	}

	// Enforce shop restriction for salesmen - verify they can access the sale's shop
	restrictedShopID, err := h.getSalesmanShopRestriction(c, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	if restrictedShopID != nil {
		// Salesman - verify the sale belongs to their shop
		existingSale, err := h.salesService.GetSaleByID(c.Request.Context(), saleID, tenantID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Sale not found"})
			return
		}
		if existingSale.ShopID != *restrictedShopID {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied: you can only update sales for your assigned shop"})
			return
		}
	}

	var req services.UpdateSaleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate required fields
	if len(req.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "at least one item is required"})
		return
	}

	sale, err := h.salesService.UpdateSale(c.Request.Context(), saleID, tenantID, userID, roleStr, req)
	if err != nil {
		errMsg := err.Error()
		// Determine appropriate status code based on error message
		switch {
		case errMsg == "sale not found":
			c.JSON(http.StatusNotFound, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "cannot be edited") || strings.Contains(errMsg, "only"):
			c.JSON(http.StatusForbidden, gin.H{"error": errMsg})
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		}
		return
	}

	c.JSON(http.StatusOK, sale)
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

	// Enforce shop restriction for salesmen
	enforcedShopID, err := h.enforceShopFilter(c, shopID, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	sales, err := h.salesService.GetPendingSales(c.Request.Context(), tenantID, &enforcedShopID)
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

	// Enforce shop restriction for salesmen
	enforcedShopID, err := h.enforceShopFilter(c, shopID, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	sales, err := h.salesService.GetUncollectedSales(c.Request.Context(), tenantID, &enforcedShopID)
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

	// Enforce shop restriction for salesmen - verify they can access the sale's shop
	restrictedShopID, err := h.getSalesmanShopRestriction(c, tenantID, createdByID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	if restrictedShopID != nil {
		// Salesman - verify the sale belongs to their shop
		sale, err := h.salesService.GetSaleByID(c.Request.Context(), req.SaleID, tenantID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Sale not found"})
			return
		}
		if sale.ShopID != *restrictedShopID {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied: you can only create returns for your assigned shop"})
			return
		}
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

	// Enforce shop restriction for salesmen
	var filterShopPtr *uuid.UUID
	if filters.ShopID != uuid.Nil {
		filterShopPtr = &filters.ShopID
	}
	enforcedShopID, err := h.enforceShopFilter(c, filterShopPtr, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	filters.ShopID = enforcedShopID

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

	// Enforce shop restriction for salesmen
	enforcedShopID, err := h.enforceShopFilter(c, shopID, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	returns, err := h.returnsService.GetPendingReturns(c.Request.Context(), tenantID, &enforcedShopID)
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

	// Enforce shop restriction for salesmen
	enforcedShopID, err := h.enforceShopFilter(c, shopID, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	if enforcedShopID != uuid.Nil {
		shopID = &enforcedShopID
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

// getSalesmanShopRestriction returns the shop_id that a user is restricted to.
// Uses centralized shop access control from utils.GetUserShopAccess
// Returns nil for roles with full access (they can access all shops in their tenant).
// Returns error if restricted user has no shop assigned.
func (h *SalesHandlers) getSalesmanShopRestriction(c *gin.Context, tenantID, userID uuid.UUID) (*uuid.UUID, error) {
	userRole := c.GetString("role")

	// Use centralized shop access control
	if !utils.IsShopRestricted(userRole) {
		return nil, nil // No restriction for this role
	}

	// Lookup salesman's assigned shop
	shopID, err := h.salesService.GetSalesmanShopID(c.Request.Context(), userID, tenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to get salesman shop: %w", err)
	}

	if shopID == nil {
		return nil, fmt.Errorf("user has no shop assigned")
	}

	return shopID, nil
}

// enforceShopFilter applies shop restriction for salesmen.
// For salesmen: overrides/enforces their assigned shop_id
// For others: uses the provided filter shop_id (optional)
func (h *SalesHandlers) enforceShopFilter(c *gin.Context, filterShopID *uuid.UUID, tenantID, userID uuid.UUID) (uuid.UUID, error) {
	restrictedShopID, err := h.getSalesmanShopRestriction(c, tenantID, userID)
	if err != nil {
		return uuid.Nil, err
	}

	if restrictedShopID != nil {
		// Salesman - enforce their shop
		// If they requested a different shop, reject
		if filterShopID != nil && *filterShopID != uuid.Nil && *filterShopID != *restrictedShopID {
			return uuid.Nil, fmt.Errorf("access denied: you can only access your assigned shop")
		}
		return *restrictedShopID, nil
	}

	// Non-salesman - use provided filter (can be Nil for all shops)
	if filterShopID != nil {
		return *filterShopID, nil
	}
	return uuid.Nil, nil
}

// ChangeDailySalesRecordDate changes only the date of a daily sales record
// PATCH /api/daily-sales/:id/change-date
// Rules:
// - Pending status: Any authorized user can change
// - Approved status: Admin/Manager can change directly, others get error
// - Rejected status: Cannot change (must copy and create new record)
func (h *SalesHandlers) ChangeDailySalesRecordDate(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userRole := c.GetString("role")

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	// Use flexible request struct to accept multiple date formats
	var rawReq struct {
		NewDate string `json:"new_date" binding:"required"`
		Reason  string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&rawReq); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request: " + err.Error()})
		return
	}

	// Parse new_date with multiple formats (RFC3339, date-only, etc.)
	var parsedDate time.Time
	dateFormats := []string{
		time.RFC3339,
		"2006-01-02T15:04:05Z",
		"2006-01-02T15:04:05",
		"2006-01-02",
	}
	for _, format := range dateFormats {
		if t, err := time.Parse(format, rawReq.NewDate); err == nil {
			parsedDate = t
			break
		}
	}
	if parsedDate.IsZero() {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD or ISO 8601 format"})
		return
	}

	req := services.ChangeDateRequest{
		NewDate: parsedDate,
		Reason:  rawReq.Reason,
	}

	// Enforce shop restriction for salesmen
	restrictedShopID, err := h.getSalesmanShopRestriction(c, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	if restrictedShopID != nil {
		// Salesman - verify the record belongs to their shop
		existingRecord, err := h.dailySalesService.GetDailySalesRecordByID(c.Request.Context(), recordID, tenantID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Record not found"})
			return
		}
		if existingRecord.ShopID != *restrictedShopID {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied: you can only modify records for your assigned shop"})
			return
		}
	}

	result, err := h.dailySalesService.ChangeDailySalesRecordDate(c.Request.Context(), recordID, tenantID, userID, userRole, req)
	if err != nil {
		// Check if it's a permission error
		if result != nil && !result.Success {
			c.JSON(http.StatusForbidden, result)
			return
		}
		// Other errors
		if strings.Contains(err.Error(), "not found") {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		} else if strings.Contains(err.Error(), "permission denied") {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, result)
}

// CopyDailySalesRecord creates a copy of an existing daily sales record for correction
// This allows users to copy rejected records instead of re-entering all items manually
func (h *SalesHandlers) CopyDailySalesRecord(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	// Enforce shop restriction for salesmen - verify they can access the original record's shop
	restrictedShopID, err := h.getSalesmanShopRestriction(c, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	if restrictedShopID != nil {
		// Salesman - verify the original record belongs to their shop
		existingRecord, err := h.dailySalesService.GetDailySalesRecordByID(c.Request.Context(), recordID, tenantID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Record not found"})
			return
		}
		if existingRecord.ShopID != *restrictedShopID {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied: you can only copy records for your assigned shop"})
			return
		}
	}

	result, err := h.dailySalesService.CopyDailySalesRecord(c.Request.Context(), recordID, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, result)
}

// UploadDailySalesImages handles multiple image uploads for daily sales records
// POST /api/daily-records/upload-image
func (h *SalesHandlers) UploadDailySalesImages(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse multipart form (max 50MB total)
	if err := c.Request.ParseMultipartForm(50 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse multipart form", "details": err.Error()})
		return
	}

	// Get uploaded files
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to get multipart form", "details": err.Error()})
		return
	}

	files := form.File["images"]
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No images provided. Use 'images' field for file upload."})
		return
	}

	// Allowed file types
	allowedTypes := map[string]bool{
		"image/jpeg": true,
		"image/jpg":  true,
		"image/png":  true,
		"image/webp": true,
	}

	// Create uploads directory if not exists
	uploadDir := "./uploads/daily_sales"
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create upload directory"})
		return
	}

	var imageURLs []string
	timestamp := time.Now().Format("20060102_150405")

	for i, fileHeader := range files {
		// Validate file size (max 10MB per file)
		if fileHeader.Size > 10*1024*1024 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":    "File too large",
				"details":  fmt.Sprintf("File '%s' exceeds 10MB limit", fileHeader.Filename),
				"maxSize":  "10MB",
				"uploaded": len(imageURLs),
			})
			return
		}

		// Validate file type
		contentType := fileHeader.Header.Get("Content-Type")
		if !allowedTypes[contentType] {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":        "Invalid file type",
				"details":      fmt.Sprintf("File '%s' has invalid type '%s'. Allowed: JPEG, PNG, WebP", fileHeader.Filename, contentType),
				"allowedTypes": []string{"image/jpeg", "image/png", "image/webp"},
				"uploaded":     len(imageURLs),
			})
			return
		}

		// Open file
		file, err := fileHeader.Open()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image", "details": err.Error()})
			return
		}
		defer file.Close()

		// Generate unique filename
		ext := filepath.Ext(fileHeader.Filename)
		if ext == "" {
			// Determine extension from content type
			switch contentType {
			case "image/jpeg", "image/jpg":
				ext = ".jpg"
			case "image/png":
				ext = ".png"
			case "image/webp":
				ext = ".webp"
			}
		}
		filename := fmt.Sprintf("daily_sales_%s_%s_%s_%d%s",
			tenantID.String()[:8],
			userID.String()[:8],
			timestamp,
			i+1,
			ext,
		)

		// Save file
		filePath := filepath.Join(uploadDir, filename)
		out, err := os.Create(filePath)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file", "details": err.Error()})
			return
		}
		defer out.Close()

		if _, err := io.Copy(out, file); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to write file", "details": err.Error()})
			return
		}

		// Add URL to list
		imageURL := fmt.Sprintf("/uploads/daily_sales/%s", filename)
		imageURLs = append(imageURLs, imageURL)
	}

	// Build response with multiple URL formats for compatibility
	response := gin.H{
		"success":    true,
		"image_urls": imageURLs,
		"urls":       imageURLs,
		"count":      len(imageURLs),
	}
	// Add singular 'url' field for Flutter app compatibility
	if len(imageURLs) > 0 {
		response["url"] = imageURLs[0]
	}
	c.JSON(http.StatusOK, response)
}

// =============================================================================
// AI Validation Endpoints
// =============================================================================

// GetValidation returns the AI validation result for a daily sales record
// GET /api/sales/daily-records/:id/validation
func (h *SalesHandlers) GetValidation(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordIDStr := c.Param("id")
	recordID, err := uuid.Parse(recordIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	result, err := h.validationService.GetValidationResult(c.Request.Context(), recordID, tenantID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			c.JSON(http.StatusNotFound, gin.H{"error": "Record not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// TriggerValidation manually triggers AI validation for a daily sales record
// POST /api/sales/daily-records/:id/validation/trigger
func (h *SalesHandlers) TriggerValidation(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordIDStr := c.Param("id")
	recordID, err := uuid.Parse(recordIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	// Parse optional request body
	var req models.TriggerValidationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Ignore binding errors - body is optional
		req.Force = false
	}

	// Trigger validation asynchronously with background context
	// Using background context to prevent cancellation when HTTP response is sent
	go func() {
		ctx := context.Background()
		if err := h.validationService.TriggerValidation(ctx, recordID, tenantID); err != nil {
			// Log error but don't block response
			fmt.Printf("Validation trigger failed for record %s: %v\n", recordID, err)
		}
	}()

	c.JSON(http.StatusAccepted, models.TriggerValidationResponse{
		RecordID: recordID,
		Status:   "triggered",
		Message:  "Validation triggered successfully. Check status with GET /validation",
	})
}

// ConfirmValidation allows manager to confirm/correct validation results
// POST /api/sales/daily-records/:id/validation/confirm
func (h *SalesHandlers) ConfirmValidation(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	recordIDStr := c.Param("id")
	recordID, err := uuid.Parse(recordIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	var req models.ConfirmValidationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.RecordID = recordID

	if err := h.validationService.ConfirmValidation(c.Request.Context(), recordID, tenantID, userID, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Validation confirmed successfully",
	})
}

// GetAccuracyDashboard returns OCR accuracy metrics for the dashboard
// GET /api/sales/validation/accuracy
func (h *SalesHandlers) GetAccuracyDashboard(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	dashboard, err := h.validationService.GetAccuracyDashboard(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, dashboard)
}

// =============================================================================
// Industrial-Grade Learning & Analytics Endpoints
// =============================================================================

// GetLearningStats returns statistics about the self-learning system
// GET /api/sales/learning/stats
func (h *SalesHandlers) GetLearningStats(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stats, err := h.validationService.GetLearningStats(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// GetAccuracyTrend returns accuracy trend analysis for the specified period
// GET /api/sales/learning/accuracy-trend?days=30
func (h *SalesHandlers) GetAccuracyTrend(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse days parameter (default 30)
	days := 30
	if daysStr := c.Query("days"); daysStr != "" {
		if d, err := strconv.Atoi(daysStr); err == nil && d > 0 && d <= 365 {
			days = d
		}
	}

	trend, err := h.validationService.GetAccuracyTrend(c.Request.Context(), tenantID, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, trend)
}

// TriggerBatchLearning triggers batch learning process for the tenant
// POST /api/sales/learning/batch-process
func (h *SalesHandlers) TriggerBatchLearning(c *gin.Context) {
	if h.validationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Validation service not available"})
		return
	}

	tenantID, _, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Run batch learning asynchronously
	go func() {
		ctx := context.Background()
		result, err := h.validationService.ProcessBatchLearning(ctx, tenantID)
		if err != nil {
			fmt.Printf("[BatchLearning] Error for tenant %s: %v\n", tenantID, err)
		} else {
			fmt.Printf("[BatchLearning] Completed for tenant %s: %+v\n", tenantID, result)
		}
	}()

	c.JSON(http.StatusAccepted, gin.H{
		"status":  "processing",
		"message": "Batch learning triggered. Check learning stats for results.",
	})
}

// =============================================================================
// Sale Revert with Dual OTP Verification (Admin-only)
// =============================================================================

// RequestRevertOTP sends dual OTPs (email and phone) for sale revert verification
// POST /api/sales/sales/:id/revert/request-otp
func (h *SalesHandlers) RequestRevertOTP(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Admin role check
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" && userRole != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only admin or owner can revert sales"})
		return
	}

	saleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sale ID"})
		return
	}

	response, err := h.salesService.RequestRevertOTP(c.Request.Context(), saleID, tenantID, userID)
	if err != nil {
		errMsg := err.Error()
		switch {
		case strings.Contains(errMsg, "not found"):
			c.JSON(http.StatusNotFound, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "only approved"):
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		}
		return
	}

	c.JSON(http.StatusOK, response)
}

// RevertSaleWithOTP reverts an approved sale after verifying dual OTPs
// POST /api/sales/sales/:id/revert
func (h *SalesHandlers) RevertSaleWithOTP(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Admin role check
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" && userRole != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only admin or owner can revert sales"})
		return
	}

	saleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid sale ID"})
		return
	}

	var req services.RevertSaleWithOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate required fields
	if req.EmailOTP == "" || req.PhoneOTP == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "both email_otp and phone_otp are required"})
		return
	}
	if req.Reason == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason is required"})
		return
	}

	sale, err := h.salesService.RevertSaleWithOTP(c.Request.Context(), saleID, tenantID, userID, req)
	if err != nil {
		errMsg := err.Error()
		switch {
		case strings.Contains(errMsg, "OTP expired") || strings.Contains(errMsg, "not requested"):
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "invalid"):
			c.JSON(http.StatusUnauthorized, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "maximum"):
			c.JSON(http.StatusTooManyRequests, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "not found"):
			c.JSON(http.StatusNotFound, gin.H{"error": errMsg})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Sale reverted successfully",
		"sale":    sale,
	})
}

// ========================================
// Daily Sales Record Revert Handlers
// ========================================

// RequestDailySalesRevertOTP requests OTP for daily sales record revert
// POST /api/daily-sales/:id/revert/request-otp
func (h *SalesHandlers) RequestDailySalesRevertOTP(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Admin/Owner role check
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" && userRole != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only admin or owner can revert daily sales records"})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	response, err := h.dailySalesService.RequestDailySalesRevertOTP(c.Request.Context(), recordID, tenantID, userID)
	if err != nil {
		errMsg := err.Error()
		switch {
		case strings.Contains(errMsg, "not found"):
			c.JSON(http.StatusNotFound, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "only approved"):
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		}
		return
	}

	c.JSON(http.StatusOK, response)
}

// RevertDailySalesRecordWithOTP reverts an approved daily sales record after verifying dual OTPs
// POST /api/daily-sales/:id/revert
func (h *SalesHandlers) RevertDailySalesRecordWithOTP(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Admin/Owner role check
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" && userRole != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only admin or owner can revert daily sales records"})
		return
	}

	recordID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid record ID"})
		return
	}

	var req services.DailySalesRevertWithOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate required fields
	if req.EmailOTP == "" || req.PhoneOTP == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "both email_otp and phone_otp are required"})
		return
	}
	if req.Reason == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason is required"})
		return
	}

	record, err := h.dailySalesService.RevertDailySalesRecordWithOTP(c.Request.Context(), recordID, tenantID, userID, req)
	if err != nil {
		errMsg := err.Error()
		switch {
		case strings.Contains(errMsg, "OTP expired") || strings.Contains(errMsg, "not requested"):
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "OTP") && strings.Contains(errMsg, "invalid"):
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "attempts exceeded"):
			c.JSON(http.StatusTooManyRequests, gin.H{"error": errMsg})
		case strings.Contains(errMsg, "not found"):
			c.JSON(http.StatusNotFound, gin.H{"error": errMsg})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Daily sales record reverted successfully",
		"record":  record,
	})
}
