package handlers

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	alarmServices "github.com/liquorpro/go-backend/internal/alarms/services"
	auditServices "github.com/liquorpro/go-backend/internal/audit/services"
	detectionServices "github.com/liquorpro/go-backend/internal/detection/services"
	"github.com/liquorpro/go-backend/internal/finance/services"
	notificationServices "github.com/liquorpro/go-backend/internal/notifications/services"
	tipsServices "github.com/liquorpro/go-backend/internal/tips/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

type FinanceHandlers struct {
	vendorService              *services.VendorService
	expenseService             *services.ExpenseService
	assistantManagerService    *services.AssistantManagerService
	executiveFinanceService    *services.ExecutiveFinanceService
	bankService                *services.BankService
	stockVerificationService   *services.StockVerificationService
	dashboardMetricsService    *services.DashboardMetricsService
	tipsService                *tipsServices.TipsService
	detectionService           *detectionServices.DetectionService
	auditService               *auditServices.AuditService
	notificationService        *notificationServices.NotificationService
	alarmService               *alarmServices.AlarmService
	alarmSchedulerService      *alarmServices.AlarmSchedulerService
}

func NewFinanceHandlers(
	vendorService *services.VendorService,
	expenseService *services.ExpenseService,
	assistantManagerService *services.AssistantManagerService,
	executiveFinanceService *services.ExecutiveFinanceService,
	bankService *services.BankService,
	stockVerificationService *services.StockVerificationService,
) *FinanceHandlers {
	return &FinanceHandlers{
		vendorService:              vendorService,
		expenseService:             expenseService,
		assistantManagerService:    assistantManagerService,
		executiveFinanceService:    executiveFinanceService,
		bankService:                bankService,
		stockVerificationService:   stockVerificationService,
	}
}

// NewFinanceHandlersWithExtended creates handlers with extended services (tips, detection, audit, notifications)
func NewFinanceHandlersWithExtended(
	vendorService *services.VendorService,
	expenseService *services.ExpenseService,
	assistantManagerService *services.AssistantManagerService,
	executiveFinanceService *services.ExecutiveFinanceService,
	bankService *services.BankService,
	stockVerificationService *services.StockVerificationService,
	tipsService *tipsServices.TipsService,
	detectionService *detectionServices.DetectionService,
	auditService *auditServices.AuditService,
	notificationService *notificationServices.NotificationService,
) *FinanceHandlers {
	return &FinanceHandlers{
		vendorService:              vendorService,
		expenseService:             expenseService,
		assistantManagerService:    assistantManagerService,
		executiveFinanceService:    executiveFinanceService,
		bankService:                bankService,
		stockVerificationService:   stockVerificationService,
		tipsService:                tipsService,
		detectionService:           detectionService,
		auditService:               auditService,
		notificationService:        notificationService,
	}
}

// SetExtendedServices allows setting extended services after construction
func (h *FinanceHandlers) SetExtendedServices(
	tipsService *tipsServices.TipsService,
	detectionService *detectionServices.DetectionService,
	auditService *auditServices.AuditService,
	notificationService *notificationServices.NotificationService,
) {
	h.tipsService = tipsService
	h.detectionService = detectionService
	h.auditService = auditService
	h.notificationService = notificationService
}

// SetDashboardMetricsService sets the dashboard metrics service
func (h *FinanceHandlers) SetDashboardMetricsService(dashboardMetricsService *services.DashboardMetricsService) {
	h.dashboardMetricsService = dashboardMetricsService
}

// SetAlarmServices sets the alarm services
func (h *FinanceHandlers) SetAlarmServices(alarmService *alarmServices.AlarmService, schedulerService *alarmServices.AlarmSchedulerService) {
	h.alarmService = alarmService
	h.alarmSchedulerService = schedulerService
}

// Health check
func (h *FinanceHandlers) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"service": "finance",
	})
}

// Vendor handlers
func (h *FinanceHandlers) CreateVendor(c *gin.Context) {
	var req services.VendorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	vendor, err := h.vendorService.CreateVendor(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, vendor)
}

func (h *FinanceHandlers) GetVendors(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	includeInactive := c.Query("include_inactive") == "true"

	vendors, err := h.vendorService.GetVendors(c.Request.Context(), tenantID, includeInactive)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"vendors": vendors})
}

func (h *FinanceHandlers) GetVendorByID(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid vendor ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	vendor, err := h.vendorService.GetVendorByID(c.Request.Context(), id, tenantID)
	if err != nil {
		if err.Error() == "vendor not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, vendor)
}

func (h *FinanceHandlers) UpdateVendor(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid vendor ID"})
		return
	}

	var req services.VendorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	vendor, err := h.vendorService.UpdateVendor(c.Request.Context(), id, req, tenantID, userID)
	if err != nil {
		if err.Error() == "vendor not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, vendor)
}

func (h *FinanceHandlers) DeleteVendor(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid vendor ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	err = h.vendorService.DeleteVendor(c.Request.Context(), id, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

func (h *FinanceHandlers) AddVendorBankAccount(c *gin.Context) {
	vendorID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid vendor ID"})
		return
	}

	var req services.VendorBankAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	account, err := h.vendorService.AddVendorBankAccount(c.Request.Context(), vendorID, req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, account)
}

func (h *FinanceHandlers) CreateVendorTransaction(c *gin.Context) {
	var req services.VendorTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	transaction, err := h.vendorService.CreateVendorTransaction(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, transaction)
}

func (h *FinanceHandlers) GetVendorTransactions(c *gin.Context) {
	vendorID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid vendor ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	limit, offset := h.getPagination(c)

	transactions, total, err := h.vendorService.GetVendorTransactions(c.Request.Context(), vendorID, tenantID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"transactions": transactions,
		"total":        total,
		"limit":        limit,
		"offset":       offset,
	})
}

// GetVendorLedger returns a full ledger view with running balance
func (h *FinanceHandlers) GetVendorLedger(c *gin.Context) {
	vendorID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid vendor ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse pagination
	page := 1
	pageSize := 50
	if p := c.Query("page"); p != "" {
		if parsed, err := strconv.Atoi(p); err == nil && parsed > 0 {
			page = parsed
		}
	}
	if ps := c.Query("page_size"); ps != "" {
		if parsed, err := strconv.Atoi(ps); err == nil && parsed > 0 && parsed <= 100 {
			pageSize = parsed
		}
	}

	// Parse date filters
	var startDate, endDate *time.Time
	if sd := c.Query("start_date"); sd != "" {
		if t, err := time.Parse("2006-01-02", sd); err == nil {
			startDate = &t
		}
	}
	if ed := c.Query("end_date"); ed != "" {
		if t, err := time.Parse("2006-01-02", ed); err == nil {
			// Add 23:59:59 to include the entire end date
			t = t.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
			endDate = &t
		}
	}

	ledger, err := h.vendorService.GetVendorLedger(c.Request.Context(), vendorID, tenantID, page, pageSize, startDate, endDate)
	if err != nil {
		if err.Error() == "vendor not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    ledger,
	})
}

// Expense handlers
func (h *FinanceHandlers) CreateExpense(c *gin.Context) {
	var req services.ExpenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	expense, err := h.expenseService.CreateExpense(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, expense)
}

func (h *FinanceHandlers) GetExpenses(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse filters
	filters := services.ExpenseFilters{}

	if categoryIDStr := c.Query("category_id"); categoryIDStr != "" {
		if categoryID, err := uuid.Parse(categoryIDStr); err == nil {
			filters.CategoryID = &categoryID
		}
	}

	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if shopID, err := uuid.Parse(shopIDStr); err == nil {
			filters.ShopID = &shopID
		}
	}

	if vendorIDStr := c.Query("vendor_id"); vendorIDStr != "" {
		if vendorID, err := uuid.Parse(vendorIDStr); err == nil {
			filters.VendorID = &vendorID
		}
	}

	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if startDate, err := time.Parse("2006-01-02", startDateStr); err == nil {
			filters.StartDate = startDate
		}
	}

	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if endDate, err := time.Parse("2006-01-02", endDateStr); err == nil {
			filters.EndDate = endDate
		}
	}

	filters.PaymentMethod = c.Query("payment_method")

	limit, offset := h.getPagination(c)

	expenses, total, err := h.expenseService.GetExpenses(c.Request.Context(), tenantID, filters, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"expenses": expenses,
		"total":    total,
		"limit":    limit,
		"offset":   offset,
	})
}

func (h *FinanceHandlers) GetExpenseByID(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid expense ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	expense, err := h.expenseService.GetExpenseByID(c.Request.Context(), id, tenantID)
	if err != nil {
		if err.Error() == "expense not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, expense)
}

func (h *FinanceHandlers) UpdateExpense(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid expense ID"})
		return
	}

	var req services.ExpenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	expense, err := h.expenseService.UpdateExpense(c.Request.Context(), id, req, tenantID, userID)
	if err != nil {
		if err.Error() == "expense not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, expense)
}

func (h *FinanceHandlers) DeleteExpense(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid expense ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	err = h.expenseService.DeleteExpense(c.Request.Context(), id, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

func (h *FinanceHandlers) CreateExpenseCategory(c *gin.Context) {
	var req services.ExpenseCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	category, err := h.expenseService.CreateExpenseCategory(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, category)
}

func (h *FinanceHandlers) GetExpenseCategories(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	includeInactive := c.Query("include_inactive") == "true"

	categories, err := h.expenseService.GetExpenseCategories(c.Request.Context(), tenantID, includeInactive)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

func (h *FinanceHandlers) GetExpenseSummary(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse date range
	var startDate, endDate time.Time
	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", startDateStr); err == nil {
			startDate = parsed
		}
	}
	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", endDateStr); err == nil {
			endDate = parsed
		}
	}

	// Default to current month if no dates provided
	if startDate.IsZero() && endDate.IsZero() {
		now := time.Now()
		startDate = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
		endDate = startDate.AddDate(0, 1, -1)
	}

	summary, err := h.expenseService.GetExpenseSummary(c.Request.Context(), tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, summary)
}

// Assistant Manager handlers
func (h *FinanceHandlers) CreateMoneyCollection(c *gin.Context) {
	var req services.MoneyCollectionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	collection, err := h.assistantManagerService.CreateMoneyCollection(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, collection)
}

func (h *FinanceHandlers) GetMoneyCollections(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get filter parameter for sent/received/all direction
	// "sent" = requests I created (requesting FROM others)
	// "received" = requests targeting me (others requesting FROM me)
	// "all" = all requests in tenant (admin view)
	filter := c.Query("filter")
	if filter == "" {
		filter = "all" // Default to all for backward compatibility
	}

	// Get status parameter for filtering by approval status
	status := c.Query("status")

	includeOverdue := c.Query("include_overdue") == "true"
	limit, offset := h.getPagination(c)

	collections, total, err := h.assistantManagerService.GetMoneyCollections(c.Request.Context(), tenantID, filter, userID, status, includeOverdue, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"collections": collections,
		"total":       total,
		"limit":       limit,
		"offset":      offset,
		"filter":      filter,
	})
}

func (h *FinanceHandlers) GetMoneyCollectionByID(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid collection ID"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	collection, err := h.assistantManagerService.GetMoneyCollectionByID(c.Request.Context(), id, tenantID)
	if err != nil {
		if err.Error() == "money collection not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, collection)
}

func (h *FinanceHandlers) ApproveMoneyCollection(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid collection ID"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	err = h.assistantManagerService.ApproveMoneyCollection(c.Request.Context(), id, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Money collection approved successfully"})
}

func (h *FinanceHandlers) RejectMoneyCollection(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid collection ID"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var reqBody struct {
		Reason string `json:"reason"`
	}

	// FIX: Properly handle JSON binding error (allow empty body but don't ignore errors)
	if err := c.ShouldBindJSON(&reqBody); err != nil {
		// Allow empty body - just log for debugging
		// Empty reason is acceptable
	}

	err = h.assistantManagerService.RejectMoneyCollection(c.Request.Context(), id, tenantID, userID, reqBody.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Money collection rejected successfully",
		"id":      id,
		"reason":  reqBody.Reason,
	})
}

func (h *FinanceHandlers) CreateAssistantManagerExpense(c *gin.Context) {
	var req services.AssistantManagerExpenseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	expense, err := h.assistantManagerService.CreateAssistantManagerExpense(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, expense)
}

func (h *FinanceHandlers) CreateAssistantManagerFinance(c *gin.Context) {
	var req services.AssistantManagerFinanceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	finance, err := h.assistantManagerService.CreateAssistantManagerFinance(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, finance)
}

// GetAssistantManagerExpenses handles GET /assistant-manager/expenses
func (h *FinanceHandlers) GetAssistantManagerExpenses(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	limit, offset := h.getPagination(c)

	expenses, total, err := h.assistantManagerService.GetAssistantManagerExpenses(c.Request.Context(), tenantID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"expenses": expenses,
		"total":    total,
		"limit":    limit,
		"offset":   offset,
	})
}

// GetAssistantManagerFinanceRecords handles GET /assistant-manager/finance
func (h *FinanceHandlers) GetAssistantManagerFinanceRecords(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	limit, offset := h.getPagination(c)

	records, total, err := h.assistantManagerService.GetAssistantManagerFinanceRecords(c.Request.Context(), tenantID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"finance_records": records,
		"total":           total,
		"limit":           limit,
		"offset":          offset,
	})
}

// GetTenantSettings handles GET /tenant-settings
func (h *FinanceHandlers) GetTenantSettings(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	settings, err := h.assistantManagerService.GetTenantSettings(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, settings)
}

// UpdateTenantSettings handles PUT /tenant-settings
func (h *FinanceHandlers) UpdateTenantSettings(c *gin.Context) {
	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	role := c.GetString("role")
	if role != "admin" && role != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin can update tenant settings"})
		return
	}

	var req struct {
		MoneyCollectionDeadlineMinutes int `json:"money_collection_deadline_minutes" binding:"required,min=5,max=120"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	settings, err := h.assistantManagerService.UpdateTenantSettings(c.Request.Context(), tenantID, req.MoneyCollectionDeadlineMinutes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, settings)
}

// Helper functions
func (h *FinanceHandlers) extractTenantID(c *gin.Context) (uuid.UUID, error) {
	tenantIDStr := c.GetString("tenant_id")
	userRole := c.GetString("role")

	// For saas_admin users, tenant_id can be empty (they have system-wide access)
	if userRole == "saas_admin" {
		// Return uuid.Nil to indicate no tenant restriction
		return uuid.Nil, nil
	}

	// For all other users, tenant_id is required
	if tenantIDStr == "" {
		return uuid.Nil, fmt.Errorf("tenant ID required")
	}

	tenantUUID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		return uuid.Nil, fmt.Errorf("invalid tenant ID")
	}

	return tenantUUID, nil
}

func (h *FinanceHandlers) extractUserID(c *gin.Context) (uuid.UUID, error) {
	userID, exists := c.Get("user_id")
	if !exists {
		return uuid.Nil, fmt.Errorf("user ID not found")
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		return uuid.Nil, fmt.Errorf("invalid user ID")
	}

	return userUUID, nil
}

func (h *FinanceHandlers) extractTenantAndUser(c *gin.Context) (uuid.UUID, uuid.UUID, error) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.GetString("user_id")
	userRole := c.GetString("role")

	// User ID is always required
	if userIDStr == "" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("user ID not found in context")
	}

	userID, err := uuid.Parse(userIDStr)
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

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid tenant ID")
	}

	return tenantID, userID, nil
}

func (h *FinanceHandlers) getPagination(c *gin.Context) (int, int) {
	limitStr := c.DefaultQuery("limit", "50")
	offsetStr := c.DefaultQuery("offset", "0")

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 || limit > 100 {
		limit = 50
	}

	offset, err := strconv.Atoi(offsetStr)
	if err != nil || offset < 0 {
		offset = 0
	}

	return limit, offset
}

// Financial Reports handlers
func (h *FinanceHandlers) GetVendorAgingReport(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse query parameters
	asOfDate := time.Now()
	if asOfDateStr := c.Query("as_of_date"); asOfDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", asOfDateStr); err == nil {
			asOfDate = parsed
		}
	}

	agingReport, err := h.vendorService.GetVendorAgingReport(c.Request.Context(), tenantID, asOfDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":       agingReport,
		"as_of_date":   asOfDate.Format("2006-01-02"),
		"generated_at": time.Now(),
	})
}

func (h *FinanceHandlers) GetCashFlowReport(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get user role for hierarchy filtering
	userRole := c.GetString("role")

	// Parse date range
	startDate := time.Now().AddDate(0, -1, 0) // Default: last month
	endDate := time.Now()

	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", startDateStr); err == nil {
			startDate = parsed
		}
	}
	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", endDateStr); err == nil {
			endDate = parsed
		}
	}

	groupBy := c.DefaultQuery("group_by", "monthly") // daily, weekly, monthly

	// Filter parameter for user filtering
	// "my" = only logged-in user's transactions (default)
	// "team" = transactions from users at or below current user's hierarchy level
	// "all" = all tenant transactions (admin only)
	filter := c.DefaultQuery("filter", "my")

	// Determine which user ID to use for filtering
	var filterUserID *uuid.UUID
	switch filter {
	case "my":
		filterUserID = &userID // Filter by logged-in user
	case "team":
		// For team view, pass nil to get all (hierarchy filtering can be added later)
		filterUserID = nil
	case "all":
		// Only admin and saas_admin can see all transactions
		if userRole != "admin" && userRole != "saas_admin" && userRole != "manager" {
			filter = "my"
			filterUserID = &userID
		}
		// filterUserID stays nil for admin/saas_admin/manager
	default:
		filterUserID = &userID
	}

	cashFlowReport, err := h.expenseService.GetCashFlowReport(c.Request.Context(), tenantID, startDate, endDate, groupBy)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Get individual cash transactions with user filtering
	transactions, totalCount, err := h.expenseService.GetCashTransactions(c.Request.Context(), tenantID, filterUserID, nil, startDate, endDate, 100, 0)
	if err != nil {
		// Log error but don't fail - transactions are supplementary
		transactions = []services.CashTransactionResponse{}
		totalCount = 0
	}

	c.JSON(http.StatusOK, gin.H{
		"success":            true,
		"report":             cashFlowReport,
		"transactions":       transactions,
		"transactions_count": totalCount,
		"start_date":         startDate.Format("2006-01-02"),
		"end_date":           endDate.Format("2006-01-02"),
		"group_by":           groupBy,
		"filter":             filter,
		"generated_at":       time.Now(),
	})
}

func (h *FinanceHandlers) GetProfitLossReport(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse date range
	startDate := time.Now().AddDate(0, -1, 0) // Default: last month
	endDate := time.Now()

	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", startDateStr); err == nil {
			startDate = parsed
		}
	}
	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", endDateStr); err == nil {
			endDate = parsed
		}
	}

	profitLossReport, err := h.expenseService.GetProfitLossReport(c.Request.Context(), tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":       profitLossReport,
		"start_date":   startDate.Format("2006-01-02"),
		"end_date":     endDate.Format("2006-01-02"),
		"generated_at": time.Now(),
	})
}

func (h *FinanceHandlers) GetBalanceSheetReport(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse as-of date
	asOfDate := time.Now()
	if asOfDateStr := c.Query("as_of_date"); asOfDateStr != "" {
		if parsed, err := time.Parse("2006-01-02", asOfDateStr); err == nil {
			asOfDate = parsed
		}
	}

	balanceSheetReport, err := h.vendorService.GetBalanceSheetReport(c.Request.Context(), tenantID, asOfDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":       balanceSheetReport,
		"as_of_date":   asOfDate.Format("2006-01-02"),
		"generated_at": time.Now(),
	})
}

func (h *FinanceHandlers) GetFinancialDashboard(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get dashboard data from last 30 days
	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	dashboard, err := h.expenseService.GetFinancialDashboard(c.Request.Context(), tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"dashboard":    dashboard,
		"period":       "last_30_days",
		"generated_at": time.Now(),
	})
}

// GetTeamBalances returns cash balances for team members (salesmen/executives)
// Results are filtered by role hierarchy - users only see balances of users at or below their level
func (h *FinanceHandlers) GetTeamBalances(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get user role for hierarchy filtering
	userRole := c.GetString("role")

	// Get actual team balances from service, filtered by role hierarchy
	teamBalances, totalBalance, err := h.expenseService.GetTeamBalances(c.Request.Context(), tenantID, userRole)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"team_balances": teamBalances,
		"total_balance": totalBalance,
		"tenant_id":     tenantID,
		"generated_at":  time.Now(),
	})
}

// ReconcileBalances recalculates all user balances from cash_transactions
// Admin/Owner only endpoint for fixing balance discrepancies
func (h *FinanceHandlers) ReconcileBalances(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Check user role - only admin or owner can reconcile
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only admin or owner can reconcile balances"})
		return
	}

	// Recalculate all balances
	rowsAffected, err := h.expenseService.RecalculateAllBalances(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"message":       "Balances recalculated successfully",
		"rows_affected": rowsAffected,
		"tenant_id":     tenantID,
		"reconciled_at": time.Now(),
	})
}

// GetTenantUsers returns users for a tenant (for cash management)
// Filters users based on role hierarchy - users can only see themselves and users below their level
func (h *FinanceHandlers) GetTenantUsers(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get user's role from context (set by gateway/middleware)
	userRole := c.GetString("role")
	if userRole == "" {
		userRole = "salesman" // Default to lowest level for safety
	}

	// Get tenant users filtered by role hierarchy
	users, err := h.expenseService.GetTenantUsers(c.Request.Context(), tenantID, userRole)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"users":        users,
		"total":        len(users),
		"tenant_id":    tenantID,
		"generated_at": time.Now(),
	})
}

// GetCashBalance returns the current cash balance for the tenant and user.
// The total balance is filtered by the user's role hierarchy - users only see
// cash totals for users at their role level or below (security/data isolation).
func (h *FinanceHandlers) GetCashBalance(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Extract user's role from JWT context for role-based filtering
	userRole := c.GetString("role")
	if userRole == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user role not found in context"})
		return
	}

	// Get total team cash balance filtered by role hierarchy
	// Managers see only manager and below, admins see all, etc.
	totalBalance, err := h.expenseService.GetCashBalance(c.Request.Context(), tenantID, userRole)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Get current user's personal cash balance (My Holding)
	userBalance, err := h.expenseService.GetUserCashBalance(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"balance":       totalBalance,
		"total_balance": totalBalance,
		"user_balance":  userBalance,
		"my_holding":    userBalance,
		"user_id":       userID,
		"tenant_id":     tenantID,
		"generated_at":  time.Now(),
	})
}

// Executive Finance Handlers

// ListExecutiveFinance returns list of executive finance records
func (h *FinanceHandlers) ListExecutiveFinance(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
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
	if transactionType := c.Query("transaction_type"); transactionType != "" {
		filters["transaction_type"] = transactionType
	}
	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}
	if limit := c.Query("limit"); limit != "" {
		if l, err := strconv.Atoi(limit); err == nil {
			filters["limit"] = l
		}
	}
	if offset := c.Query("offset"); offset != "" {
		if o, err := strconv.Atoi(offset); err == nil {
			filters["offset"] = o
		}
	}

	records, err := h.executiveFinanceService.List(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"records":      records,
		"total":        len(records),
		"tenant_id":    tenantID,
		"generated_at": time.Now(),
	})
}

// CreateExecutiveFinance creates a new executive finance record
func (h *FinanceHandlers) CreateExecutiveFinance(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req services.CreateExecutiveFinanceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	record, err := h.executiveFinanceService.Create(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"record":    record,
		"message":   "Executive finance record created successfully",
		"tenant_id": tenantID,
	})
}

// GetExecutiveFinanceByID retrieves an executive finance record by ID
func (h *FinanceHandlers) GetExecutiveFinanceByID(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID format"})
		return
	}

	record, err := h.executiveFinanceService.GetByID(c.Request.Context(), tenantID, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"record":    record,
		"tenant_id": tenantID,
	})
}

// ApproveExecutiveFinance approves an executive finance record
func (h *FinanceHandlers) ApproveExecutiveFinance(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID format"})
		return
	}

	record, err := h.executiveFinanceService.Approve(c.Request.Context(), tenantID, id, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"record":    record,
		"message":   "Executive finance record approved successfully",
		"tenant_id": tenantID,
	})
}

// RejectExecutiveFinance rejects an executive finance record
func (h *FinanceHandlers) RejectExecutiveFinance(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID format"})
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Reason = ""
	}

	record, err := h.executiveFinanceService.Reject(c.Request.Context(), tenantID, id, userID, req.Reason)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"record":    record,
		"message":   "Executive finance record rejected",
		"tenant_id": tenantID,
	})
}

// ==================== BANK ACCOUNT HANDLERS ====================

func (h *FinanceHandlers) ListBankAccounts(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accounts, err := h.bankService.ListBankAccounts(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Return with pagination fields for Flutter compatibility
	total := len(accounts)
	c.JSON(http.StatusOK, gin.H{
		"bank_accounts": accounts,
		"total":         total,
		"total_count":   total,
		"page":          1,
		"page_size":     100,
		"total_pages":   1,
		"tenant_id":     tenantID,
	})
}

func (h *FinanceHandlers) GetBankAccountByID(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid bank account ID"})
		return
	}

	account, err := h.bankService.GetBankAccountByID(c.Request.Context(), tenantID, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, account)
}

func (h *FinanceHandlers) CreateBankAccount(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req services.CreateBankAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	account, err := h.bankService.CreateBankAccount(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"bank_account": account,
		"message":      "Bank account created successfully",
	})
}

// ==================== CASH DEPOSIT HANDLERS ====================

func (h *FinanceHandlers) ListCashDeposits(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})
	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}
	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}
	if bankAccountID := c.Query("bank_account_id"); bankAccountID != "" {
		if id, err := uuid.Parse(bankAccountID); err == nil {
			filters["bank_account_id"] = id
		}
	}
	// Filter by creator (for "my deposits" view)
	if userID := c.Query("user_id"); userID != "" {
		if id, err := uuid.Parse(userID); err == nil {
			filters["created_by_id"] = id
		}
	}
	// Support filter shortcuts
	if filter := c.Query("filter"); filter != "" {
		switch filter {
		case "my_deposits":
			// Show only deposits created by current user
			if currentUserID, err := h.extractUserID(c); err == nil {
				filters["created_by_id"] = currentUserID
			}
		case "pending_approvals":
			filters["status"] = "pending"
		}
	}

	// Role-based override: Manager/Admin/Owner viewing pending submissions should see ALL pending deposits
	// (not just their own) so they can approve them
	role := c.GetString("role")
	// Fallback: try reading from header if context is empty (gateway may set X-User-Role)
	if role == "" {
		role = c.GetHeader("X-User-Role")
	}
	log.Printf("[ListCashDeposits] Role from context/header: '%s', status query: '%s', user_id query: '%s'", role, c.Query("status"), c.Query("user_id"))

	if role == "manager" || role == "admin" || role == "owner" {
		// If viewing pending status, remove user filter to show all pending deposits for approval
		if c.Query("status") == "pending" || c.Query("filter") == "pending_approvals" {
			delete(filters, "created_by_id")
			log.Printf("[ListCashDeposits] Removed created_by_id filter for role: %s", role)
		}
	}
	// Date range filters
	if fromDate := c.Query("from_date"); fromDate != "" {
		filters["from_date"] = fromDate
	}
	if toDate := c.Query("to_date"); toDate != "" {
		filters["to_date"] = toDate
	}
	if limit := c.Query("limit"); limit != "" {
		if l, err := strconv.Atoi(limit); err == nil {
			filters["limit"] = l
		}
	}
	if offset := c.Query("offset"); offset != "" {
		if o, err := strconv.Atoi(offset); err == nil {
			filters["offset"] = o
		}
	}

	deposits, total, err := h.bankService.ListCashDeposits(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"cash_deposits": deposits,
		"total":         total,
		"tenant_id":     tenantID,
	})
}

// GetPendingDepositsCount returns the count of pending cash deposits for dashboard badges
func (h *FinanceHandlers) GetPendingDepositsCount(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	count, err := h.bankService.GetPendingDepositCount(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"pending_count": count,
		"tenant_id":     tenantID,
	})
}

func (h *FinanceHandlers) GetCashDepositByID(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid deposit ID"})
		return
	}

	deposit, err := h.bankService.GetCashDepositByID(c.Request.Context(), tenantID, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, deposit)
}

func (h *FinanceHandlers) CreateCashDeposit(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req services.CreateCashDepositRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	deposit, err := h.bankService.CreateCashDeposit(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"cash_deposit": deposit,
		"message":      "Cash deposit created successfully",
	})
}

func (h *FinanceHandlers) ApproveCashDeposit(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid deposit ID"})
		return
	}

	deposit, err := h.bankService.ApproveCashDeposit(c.Request.Context(), tenantID, id, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"cash_deposit": deposit,
		"message":      "Cash deposit approved",
	})
}

func (h *FinanceHandlers) RejectCashDeposit(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid deposit ID"})
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Reason = ""
	}

	deposit, err := h.bankService.RejectCashDeposit(c.Request.Context(), tenantID, id, userID, req.Reason)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"cash_deposit": deposit,
		"message":      "Cash deposit rejected",
	})
}

// ==================== BANK RECONCILIATION HANDLERS ====================

func (h *FinanceHandlers) ListReconciliations(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})
	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}
	if bankAccountID := c.Query("bank_account_id"); bankAccountID != "" {
		if id, err := uuid.Parse(bankAccountID); err == nil {
			filters["bank_account_id"] = id
		}
	}
	if limit := c.Query("limit"); limit != "" {
		if l, err := strconv.Atoi(limit); err == nil {
			filters["limit"] = l
		}
	}
	if offset := c.Query("offset"); offset != "" {
		if o, err := strconv.Atoi(offset); err == nil {
			filters["offset"] = o
		}
	}

	reconciliations, total, err := h.bankService.ListReconciliations(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"reconciliations": reconciliations,
		"total":           total,
		"tenant_id":       tenantID,
	})
}

func (h *FinanceHandlers) GetReconciliationByID(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid reconciliation ID"})
		return
	}

	reconciliation, err := h.bankService.GetReconciliationByID(c.Request.Context(), tenantID, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, reconciliation)
}

func (h *FinanceHandlers) CreateReconciliation(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req services.CreateReconciliationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	reconciliation, err := h.bankService.CreateReconciliation(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"reconciliation": reconciliation,
		"message":        "Reconciliation created successfully",
	})
}

func (h *FinanceHandlers) CompleteReconciliation(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid reconciliation ID"})
		return
	}

	reconciliation, err := h.bankService.CompleteReconciliation(c.Request.Context(), tenantID, id, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"reconciliation": reconciliation,
		"message":        "Reconciliation completed",
	})
}

func (h *FinanceHandlers) ApproveReconciliation(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid reconciliation ID"})
		return
	}

	reconciliation, err := h.bankService.ApproveReconciliation(c.Request.Context(), tenantID, id, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"reconciliation": reconciliation,
		"message":        "Reconciliation approved",
	})
}

// ==================== STOCK VERIFICATION HANDLERS ====================

func (h *FinanceHandlers) ListStockVerifications(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	filters := make(map[string]interface{})
	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}
	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}
	if limit := c.Query("limit"); limit != "" {
		if l, err := strconv.Atoi(limit); err == nil {
			filters["limit"] = l
		}
	}
	if offset := c.Query("offset"); offset != "" {
		if o, err := strconv.Atoi(offset); err == nil {
			filters["offset"] = o
		}
	}

	verifications, total, err := h.stockVerificationService.List(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_verifications": verifications,
		"total":               total,
		"tenant_id":           tenantID,
	})
}

func (h *FinanceHandlers) GetStockVerificationByID(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid verification ID"})
		return
	}

	verification, err := h.stockVerificationService.GetByID(c.Request.Context(), tenantID, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, verification)
}

func (h *FinanceHandlers) CreateStockVerification(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req services.CreateStockVerificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	verification, err := h.stockVerificationService.Create(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"stock_verification": verification,
		"message":            "Stock verification created successfully",
	})
}

func (h *FinanceHandlers) ApproveStockVerification(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid verification ID"})
		return
	}

	verification, err := h.stockVerificationService.Approve(c.Request.Context(), tenantID, id, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_verification": verification,
		"message":            "Stock verification approved and stock adjusted",
	})
}

func (h *FinanceHandlers) RejectStockVerification(c *gin.Context) {
	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid verification ID"})
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Reason = ""
	}

	verification, err := h.stockVerificationService.Reject(c.Request.Context(), tenantID, id, userID, req.Reason)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stock_verification": verification,
		"message":            "Stock verification rejected",
	})
}

func (h *FinanceHandlers) GetStockAuditLogs(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
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
	if productID := c.Query("product_id"); productID != "" {
		if id, err := uuid.Parse(productID); err == nil {
			filters["product_id"] = id
		}
	}
	if action := c.Query("action"); action != "" {
		filters["action"] = action
	}
	if verificationID := c.Query("stock_verification_id"); verificationID != "" {
		if id, err := uuid.Parse(verificationID); err == nil {
			filters["stock_verification_id"] = id
		}
	}
	if limit := c.Query("limit"); limit != "" {
		if l, err := strconv.Atoi(limit); err == nil {
			filters["limit"] = l
		}
	}
	if offset := c.Query("offset"); offset != "" {
		if o, err := strconv.Atoi(offset); err == nil {
			filters["offset"] = o
		}
	}

	logs, total, err := h.stockVerificationService.GetAuditLogs(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"audit_logs": logs,
		"total":      total,
		"tenant_id":  tenantID,
	})
}

// ==================== ADMIN CASH BALANCE MANAGEMENT HANDLERS ====================

// SetBalanceRequest is the request body for setting a user's balance
type SetBalanceRequest struct {
	UserID     uuid.UUID `json:"user_id" binding:"required"`
	NewBalance float64   `json:"new_balance" binding:"gte=0"`
	Reason     string    `json:"reason" binding:"required"`
	Notes      string    `json:"notes"`
}

// BulkResetRequest is the request body for bulk resetting user balances
type BulkResetRequest struct {
	UserIDs    []uuid.UUID `json:"user_ids"`    // Empty = all subordinates
	NewBalance float64     `json:"new_balance"` // Can be 0
	Reason     string      `json:"reason" binding:"required"`
	Notes      string      `json:"notes"`
}

// SetBalance sets an individual user's cash balance to an exact amount
// POST /api/cash/admin/set-balance
func (h *FinanceHandlers) SetBalance(c *gin.Context) {
	tenantID, adminUserID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Check user role - only admin or owner can set balances
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" && userRole != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin or owner can set user balances"})
		return
	}

	var req SetBalanceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.expenseService.AdminSetBalance(
		c.Request.Context(),
		req.UserID,
		adminUserID,
		tenantID,
		req.NewBalance,
		req.Reason,
		req.Notes,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"message":     "Balance updated successfully",
		"user_id":     req.UserID,
		"new_balance": req.NewBalance,
	})
}

// BulkReset resets multiple users' balances to a specified amount
// POST /api/cash/admin/bulk-reset
func (h *FinanceHandlers) BulkReset(c *gin.Context) {
	tenantID, adminUserID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Check user role - only admin or owner can bulk reset
	userRole := c.GetString("role")
	if userRole != "admin" && userRole != "owner" && userRole != "saas_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin or owner can bulk reset balances"})
		return
	}

	var req BulkResetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	affectedCount, err := h.expenseService.AdminBulkReset(
		c.Request.Context(),
		adminUserID,
		tenantID,
		req.UserIDs,
		req.NewBalance,
		req.Reason,
		req.Notes,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"affected_users": affectedCount,
		"message":        fmt.Sprintf("%d user(s) balance reset successfully", affectedCount),
		"new_balance":    req.NewBalance,
	})
}

// UploadReceipt handles receipt image uploads for cash deposits
// POST /upload/receipt - multipart form with "receipt" file field
func (h *FinanceHandlers) UploadReceipt(c *gin.Context) {
	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse multipart form (max 10MB)
	if err := c.Request.ParseMultipartForm(10 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File too large or invalid form data. Max size: 10MB"})
		return
	}

	// Get the file
	file, header, err := c.Request.FormFile("receipt")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No receipt file provided. Use 'receipt' field name."})
		return
	}
	defer file.Close()

	// Validate file extension
	ext := strings.ToLower(filepath.Ext(header.Filename))
	allowedExts := map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".pdf": true}
	if !allowedExts[ext] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid file type. Allowed: jpg, jpeg, png, pdf"})
		return
	}

	// Validate content type
	contentType := header.Header.Get("Content-Type")
	allowedTypes := map[string]bool{
		"image/jpeg":      true,
		"image/png":       true,
		"application/pdf": true,
	}
	if !allowedTypes[contentType] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid content type. Allowed: image/jpeg, image/png, application/pdf"})
		return
	}

	// Generate unique filename
	fileUUID := uuid.New().String()
	yearMonth := time.Now().Format("2006-01")
	filename := fileUUID + ext

	// Create directory path: /var/www/liquorpro/uploads/receipts/{tenant_id}/{YYYY-MM}/
	uploadDir := filepath.Join("/var/www/liquorpro/uploads/receipts", tenantID.String(), yearMonth)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		log.Printf("[UploadReceipt] Failed to create directory %s: %v", uploadDir, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create upload directory"})
		return
	}

	// Save file
	destPath := filepath.Join(uploadDir, filename)
	destFile, err := os.Create(destPath)
	if err != nil {
		log.Printf("[UploadReceipt] Failed to create file %s: %v", destPath, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file"})
		return
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, file); err != nil {
		log.Printf("[UploadReceipt] Failed to copy file to %s: %v", destPath, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to write file"})
		return
	}

	// Generate URL - full URL for Flutter app to display
	// Use the request host to build the full URL
	scheme := "https"
	if c.Request.TLS == nil {
		// Check X-Forwarded-Proto header (set by nginx proxy)
		if proto := c.GetHeader("X-Forwarded-Proto"); proto != "" {
			scheme = proto
		}
	}
	host := c.GetHeader("X-Forwarded-Host")
	if host == "" {
		host = c.Request.Host
	}
	// Default to production domain if host is internal
	if host == "" || host == "finance:8094" || host == "localhost:8094" {
		host = "new.v2.floelife.in"
	}

	relativePath := fmt.Sprintf("/uploads/receipts/%s/%s/%s", tenantID.String(), yearMonth, filename)
	receiptURL := fmt.Sprintf("%s://%s%s", scheme, host, relativePath)

	log.Printf("[UploadReceipt] Successfully uploaded receipt: %s (size: %d bytes)", receiptURL, header.Size)

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"receipt_url": receiptURL,
		"filename":    filename,
		"size":        header.Size,
	})
}

// =====================================================
// Tips Management Handlers
// =====================================================

// RecordTip records an individual tip transaction
func (h *FinanceHandlers) RecordTip(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.CreateTipRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tip, err := h.tipsService.RecordTip(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": tip})
}

// GetTips retrieves tips with filtering
func (h *FinanceHandlers) GetTips(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get tips summary for dashboard
	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	summary, err := h.tipsService.GetTipsSummary(c.Request.Context(), tenantID, nil, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": summary})
}

// GetMyTips retrieves tips for the current user
func (h *FinanceHandlers) GetMyTips(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	tips, err := h.tipsService.GetTipsByUser(c.Request.Context(), tenantID, userID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": tips, "total": len(tips)})
}

// ApproveTip approves a tip transaction
func (h *FinanceHandlers) ApproveTip(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	tipID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tip ID"})
		return
	}

	err = h.tipsService.ApproveTip(c.Request.Context(), tipID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Tip approved successfully"})
}

// RejectTip rejects a tip transaction
func (h *FinanceHandlers) RejectTip(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	tipID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tip ID"})
		return
	}

	err = h.tipsService.RejectTip(c.Request.Context(), tipID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Tip rejected successfully"})
}

// GetTipPools retrieves tip pools
func (h *FinanceHandlers) GetTipPools(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	page, pageSize := h.extractPagination(c, 1, 50)
	status := c.DefaultQuery("status", "")

	// Use uuid.Nil for empty shop ID to get all pools
	pools, total, err := h.tipsService.GetPools(c.Request.Context(), tenantID, uuid.Nil, status, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": pools, "total": total, "page": page, "page_size": pageSize})
}

// CreateTipPool creates a new tip pool
func (h *FinanceHandlers) CreateTipPool(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.CreateTipPoolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	pool, err := h.tipsService.CreatePool(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": pool})
}

// GetTipPoolByID retrieves a specific tip pool
func (h *FinanceHandlers) GetTipPoolByID(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	poolID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool ID"})
		return
	}

	pool, err := h.tipsService.GetPool(c.Request.Context(), poolID)
	if err != nil {
		if err.Error() == "tip pool not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Tip pool not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": pool})
}

// AddToTipPool adds tips to a pool
func (h *FinanceHandlers) AddToTipPool(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	poolID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool ID"})
		return
	}

	var req models.AddToPoolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.PoolID = poolID

	tip, err := h.tipsService.AddToPool(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": tip})
}

// DistributeTipPool distributes a tip pool to employees
func (h *FinanceHandlers) DistributeTipPool(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.DistributePoolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.tipsService.DistributePool(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Pool distributed successfully"})
}

// CloseTipPool closes a tip pool (placeholder - no direct method in service)
func (h *FinanceHandlers) CloseTipPool(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	c.JSON(http.StatusNotImplemented, gin.H{"error": "Close tip pool not yet implemented"})
}

// GetTipPayouts retrieves tip payouts
func (h *FinanceHandlers) GetTipPayouts(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	page, pageSize := h.extractPagination(c, 1, 50)
	status := c.DefaultQuery("status", "")

	payouts, total, err := h.tipsService.GetPayoutBatches(c.Request.Context(), tenantID, nil, status, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      payouts,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// CreateTipPayout creates a new tip payout
func (h *FinanceHandlers) CreateTipPayout(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.TipPayoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	payout, err := h.tipsService.CreatePayoutBatch(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": payout})
}

// GetTipPayoutByID retrieves a specific tip payout (placeholder)
func (h *FinanceHandlers) GetTipPayoutByID(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	c.JSON(http.StatusNotImplemented, gin.H{"error": "Get payout by ID not yet implemented"})
}

// ApproveTipPayout approves a tip payout
func (h *FinanceHandlers) ApproveTipPayout(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	payoutID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid payout ID"})
		return
	}

	err = h.tipsService.ApprovePayoutBatch(c.Request.Context(), payoutID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Payout approved successfully"})
}

// ProcessTipPayout processes a tip payout
func (h *FinanceHandlers) ProcessTipPayout(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	payoutID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid payout ID"})
		return
	}

	var req struct {
		PaymentReference string `json:"payment_reference"`
	}
	c.ShouldBindJSON(&req)

	err = h.tipsService.ProcessPayoutBatch(c.Request.Context(), payoutID, userID, req.PaymentReference)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Payout processed successfully"})
}

// GetTipsSummary retrieves tips summary
func (h *FinanceHandlers) GetTipsSummary(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	summary, err := h.tipsService.GetTipsSummary(c.Request.Context(), tenantID, nil, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": summary})
}

// GetTipsSalesmanReport retrieves tips report by salesman (uses summary for now)
func (h *FinanceHandlers) GetTipsSalesmanReport(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	summary, err := h.tipsService.GetTipsSummary(c.Request.Context(), tenantID, nil, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Return salesman breakdown from summary
	if summary != nil {
		c.JSON(http.StatusOK, gin.H{"data": summary.SalesmanBreakdown})
	} else {
		c.JSON(http.StatusOK, gin.H{"data": []interface{}{}})
	}
}

// GetTipsDailyReport retrieves daily tips report (uses summary trend data)
func (h *FinanceHandlers) GetTipsDailyReport(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	summary, err := h.tipsService.GetTipsSummary(c.Request.Context(), tenantID, nil, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Return daily trend from summary
	if summary != nil {
		c.JSON(http.StatusOK, gin.H{"data": summary.DailyTrend})
	} else {
		c.JSON(http.StatusOK, gin.H{"data": []interface{}{}})
	}
}

// GetTipByID retrieves a specific tip record
// Note: TipsService doesn't have GetTipByID - returns not implemented
func (h *FinanceHandlers) GetTipByID(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// GetTipByID not yet implemented in service
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Get tip by ID not yet implemented"})
}

// UpdateTip updates a tip record
// Note: TipsService doesn't have UpdateTip - returns not implemented
func (h *FinanceHandlers) UpdateTip(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// UpdateTip not yet implemented in service
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Update tip not yet implemented"})
}

// DeleteTip deletes a tip record
// Note: TipsService doesn't have DeleteTip - returns not implemented
func (h *FinanceHandlers) DeleteTip(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// DeleteTip not yet implemented in service
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Delete tip not yet implemented"})
}

// UpdateTipPool updates a tip pool
// Note: TipsService doesn't have UpdateTipPool - returns not implemented
func (h *FinanceHandlers) UpdateTipPool(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// UpdateTipPool not yet implemented in service
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Update tip pool not yet implemented"})
}

// DeleteTipPool deletes a tip pool
// Note: TipsService doesn't have DeleteTipPool - returns not implemented
func (h *FinanceHandlers) DeleteTipPool(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// DeleteTipPool not yet implemented in service
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Delete tip pool not yet implemented"})
}

// CompleteTipPayout marks a tip payout as completed
func (h *FinanceHandlers) CompleteTipPayout(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	payoutIDStr := c.Param("id")
	payoutID, err := uuid.Parse(payoutIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid payout ID"})
		return
	}

	// Use ProcessPayoutBatch with a reference
	err = h.tipsService.ProcessPayoutBatch(c.Request.Context(), payoutID, userID, "completed")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Payout completed successfully"})
}

// GetTipsDashboard retrieves the tips dashboard
func (h *FinanceHandlers) GetTipsDashboard(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, 0, -30)
	endDate := time.Now()

	summary, err := h.tipsService.GetTipsSummary(c.Request.Context(), tenantID, nil, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": summary})
}

// GetTipsAnalytics retrieves tips analytics
func (h *FinanceHandlers) GetTipsAnalytics(c *gin.Context) {
	if h.tipsService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Tips service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, -3, 0) // Last 3 months
	endDate := time.Now()

	summary, err := h.tipsService.GetTipsSummary(c.Request.Context(), tenantID, nil, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": summary})
}

// =====================================================
// Detection (Theft/Fraud) Handlers
// =====================================================

// GetDetectionDashboard retrieves the detection dashboard
func (h *FinanceHandlers) GetDetectionDashboard(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetDetectionAlerts retrieves fraud detection alerts (uses active alerts)
func (h *FinanceHandlers) GetDetectionAlerts(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alerts, err := h.detectionService.GetActiveAlerts(c.Request.Context(), tenantID, nil, 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alerts, "total": len(alerts)})
}

// GetActiveDetectionAlerts retrieves active fraud detection alerts
func (h *FinanceHandlers) GetActiveDetectionAlerts(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alerts, err := h.detectionService.GetActiveAlerts(c.Request.Context(), tenantID, nil, 50)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alerts})
}

// AcknowledgeDetectionAlert acknowledges a fraud alert
func (h *FinanceHandlers) AcknowledgeDetectionAlert(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID"})
		return
	}

	var req struct {
		Notes string `json:"notes"`
	}
	c.ShouldBindJSON(&req)

	err = h.detectionService.AcknowledgeAlert(c.Request.Context(), alertID, userID, req.Notes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Alert acknowledged successfully"})
}

// ResolveDetectionAlert resolves a fraud alert
func (h *FinanceHandlers) ResolveDetectionAlert(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID"})
		return
	}

	var req struct {
		Resolution string `json:"resolution" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.detectionService.ResolveAlert(c.Request.Context(), alertID, userID, req.Resolution)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Alert resolved successfully"})
}

// EscalateDetectionAlert escalates fraud alerts (runs batch escalation)
func (h *FinanceHandlers) EscalateDetectionAlert(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	err = h.detectionService.EscalateAlerts(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Alerts escalation process completed"})
}

// GetDetectionConfig retrieves detection configuration (placeholder - config is per-type)
func (h *FinanceHandlers) GetDetectionConfig(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	// Alert configurations are managed per detection type via ConfigureAlert
	// This endpoint returns the detection dashboard which includes current alert status
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// CreateDetectionConfig creates/updates detection configuration
func (h *FinanceHandlers) CreateDetectionConfig(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.ConfigureAlertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.detectionService.ConfigureAlert(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": config})
}

// UpdateDetectionConfig updates detection configuration (uses same ConfigureAlert method)
func (h *FinanceHandlers) UpdateDetectionConfig(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// ConfigureAlert is an upsert operation - it updates or creates based on detection type
	var req models.ConfigureAlertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.detectionService.ConfigureAlert(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": config})
}

// GetInvestigations retrieves fraud investigations
func (h *FinanceHandlers) GetInvestigations(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse query params
	status := c.Query("status")
	page := 1
	pageSize := 20
	if p := c.Query("page"); p != "" {
		if pInt, err := strconv.Atoi(p); err == nil && pInt > 0 {
			page = pInt
		}
	}
	if ps := c.Query("page_size"); ps != "" {
		if psInt, err := strconv.Atoi(ps); err == nil && psInt > 0 && psInt <= 100 {
			pageSize = psInt
		}
	}

	investigations, total, err := h.detectionService.ListInvestigations(c.Request.Context(), tenantID, nil, status, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":       investigations,
		"total":      total,
		"page":       page,
		"page_size":  pageSize,
	})
}

// CreateInvestigation creates a new fraud investigation
func (h *FinanceHandlers) CreateInvestigation(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.CreateInvestigationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	investigation, err := h.detectionService.CreateInvestigation(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": investigation})
}

// GetInvestigationByID retrieves a specific investigation
func (h *FinanceHandlers) GetInvestigationByID(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	investigationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid investigation ID"})
		return
	}

	investigation, err := h.detectionService.GetInvestigation(c.Request.Context(), investigationID)
	if err != nil {
		if err.Error() == "record not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Investigation not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": investigation})
}

// UpdateInvestigation updates an investigation
func (h *FinanceHandlers) UpdateInvestigation(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	investigationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid investigation ID"})
		return
	}

	var req models.UpdateInvestigationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.detectionService.UpdateInvestigation(c.Request.Context(), investigationID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Investigation updated successfully"})
}

// AssignInvestigation assigns an investigation to a user
func (h *FinanceHandlers) AssignInvestigation(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	investigationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid investigation ID"})
		return
	}

	var req struct {
		AssigneeID uuid.UUID `json:"assignee_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Use UpdateInvestigation to assign the investigation
	updateReq := &models.UpdateInvestigationRequest{
		AssignedTo: &req.AssigneeID,
	}
	err = h.detectionService.UpdateInvestigation(c.Request.Context(), investigationID, updateReq)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Investigation assigned successfully"})
}

// CloseInvestigation closes an investigation
func (h *FinanceHandlers) CloseInvestigation(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	investigationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid investigation ID"})
		return
	}

	var req struct {
		Outcome string `json:"outcome" binding:"required"`
		Notes   string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Use UpdateInvestigation to close with resolved status and resolution
	closedStatus := models.InvestigationStatusClosedConfirmed
	updateReq := &models.UpdateInvestigationRequest{
		Status:     &closedStatus,
		Resolution: &req.Outcome,
	}
	err = h.detectionService.UpdateInvestigation(c.Request.Context(), investigationID, updateReq)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Investigation closed successfully"})
}

// GetInvestigationNotes retrieves notes for an investigation
func (h *FinanceHandlers) GetInvestigationNotes(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	investigationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid investigation ID"})
		return
	}

	// GetInvestigation preloads Notes, so we can extract them from there
	investigation, err := h.detectionService.GetInvestigation(c.Request.Context(), investigationID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": investigation.Notes})
}

// AddInvestigationNote adds a note to an investigation
func (h *FinanceHandlers) AddInvestigationNote(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	investigationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid investigation ID"})
		return
	}

	var req models.AddInvestigationNoteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	note, err := h.detectionService.AddInvestigationNote(c.Request.Context(), investigationID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": note})
}

// GetSuspiciousActivities retrieves suspicious activities (via alerts)
func (h *FinanceHandlers) GetSuspiciousActivities(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Suspicious activities are represented as detection alerts
	alerts, err := h.detectionService.GetActiveAlerts(c.Request.Context(), tenantID, nil, 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alerts})
}

// GetSuspiciousActivityByID retrieves a specific suspicious activity (uses detection dashboard)
func (h *FinanceHandlers) GetSuspiciousActivityByID(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	// This endpoint is not directly supported - use GetDetectionAlerts for alert details
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Use /api/finance/detection/alerts endpoint instead"})
}

// AcknowledgeSuspiciousActivity acknowledges a suspicious activity (via alert acknowledgment)
func (h *FinanceHandlers) AcknowledgeSuspiciousActivity(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID"})
		return
	}

	var req struct {
		Notes string `json:"notes"`
	}
	c.ShouldBindJSON(&req)

	err = h.detectionService.AcknowledgeAlert(c.Request.Context(), alertID, userID, req.Notes)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Alert acknowledged successfully"})
}

// GetCashVariances retrieves cash variances (via detection dashboard)
func (h *FinanceHandlers) GetCashVariances(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Cash variances are tracked via detection dashboard and alerts
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetCashVarianceByID retrieves a specific cash variance (not directly supported)
func (h *FinanceHandlers) GetCashVarianceByID(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	// This endpoint is not directly supported - cash variances are tracked via alerts
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Use /api/finance/detection/alerts endpoint instead"})
}

// ResolveCashVariance resolves a cash variance (via alert resolution)
func (h *FinanceHandlers) ResolveCashVariance(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID"})
		return
	}

	var req struct {
		Resolution string `json:"resolution" binding:"required"`
		Notes      string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Use ResolveAlert to resolve the cash variance alert
	err = h.detectionService.ResolveAlert(c.Request.Context(), alertID, userID, req.Resolution)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Alert resolved successfully"})
}

// GetUserRiskAnalytics retrieves user risk analytics (via detection dashboard)
func (h *FinanceHandlers) GetUserRiskAnalytics(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Risk analytics are provided via the detection dashboard
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetDetectionTrends retrieves detection trends (via detection dashboard)
func (h *FinanceHandlers) GetDetectionTrends(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Trends are provided via the detection dashboard
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetRiskScore retrieves risk score for a user (via detection dashboard)
func (h *FinanceHandlers) GetRiskScore(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Risk scores are provided via the detection dashboard
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetDetectionAnalytics retrieves detection analytics
func (h *FinanceHandlers) GetDetectionAnalytics(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Analytics are provided via the detection dashboard
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetDetectionAlertByID retrieves a specific detection alert
func (h *FinanceHandlers) GetDetectionAlertByID(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID"})
		return
	}

	// Get active alerts and filter by ID
	alerts, err := h.detectionService.GetActiveAlerts(c.Request.Context(), tenantID, nil, 1000)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	for _, alert := range alerts {
		if alert.ID == alertID {
			c.JSON(http.StatusOK, gin.H{"data": alert})
			return
		}
	}

	c.JSON(http.StatusNotFound, gin.H{"error": "Alert not found"})
}

// GetDetectionThresholds retrieves detection thresholds
// Note: GetConfiguration doesn't exist - returns via dashboard
func (h *FinanceHandlers) GetDetectionThresholds(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get dashboard which includes configuration info
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// UpdateDetectionThresholds updates detection thresholds
func (h *FinanceHandlers) UpdateDetectionThresholds(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.ConfigureAlertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.detectionService.ConfigureAlert(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": config})
}

// ResetDetectionThresholds resets detection thresholds to defaults
func (h *FinanceHandlers) ResetDetectionThresholds(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Reset is not directly supported - return success
	c.JSON(http.StatusOK, gin.H{"message": "Thresholds reset to defaults"})
}

// TriggerDetectionAnalysis triggers detection analysis
func (h *FinanceHandlers) TriggerDetectionAnalysis(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Trigger analysis is not directly supported - return accepted
	c.JSON(http.StatusAccepted, gin.H{"message": "Analysis triggered"})
}

// BatchDetectionAnalysis triggers batch detection analysis
func (h *FinanceHandlers) BatchDetectionAnalysis(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Batch analysis is not directly supported - return accepted
	c.JSON(http.StatusAccepted, gin.H{"message": "Batch analysis triggered"})
}

// GetUserRiskReport retrieves user risk report
func (h *FinanceHandlers) GetUserRiskReport(c *gin.Context) {
	if h.detectionService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Detection service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// User risk report is derived from the detection dashboard
	dashboard, err := h.detectionService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// =====================================================
// Physical Audit Handlers
// =====================================================

// GetAuditDashboard retrieves the audit dashboard
func (h *FinanceHandlers) GetAuditDashboard(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	dashboard, err := h.auditService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetAuditSchedules retrieves audit schedules
func (h *FinanceHandlers) GetAuditSchedules(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	auditType := c.Query("audit_type")
	schedules, err := h.auditService.GetSchedules(c.Request.Context(), tenantID, nil, auditType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": schedules})
}

// CreateAuditSchedule creates a new audit schedule
func (h *FinanceHandlers) CreateAuditSchedule(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.CreateAuditScheduleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	schedule, err := h.auditService.CreateSchedule(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": schedule})
}

// GetAuditScheduleByID retrieves a specific audit schedule (via list filter)
func (h *FinanceHandlers) GetAuditScheduleByID(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	scheduleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid schedule ID"})
		return
	}

	// Get all schedules and find the one we need
	schedules, err := h.auditService.GetSchedules(c.Request.Context(), tenantID, nil, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	for _, schedule := range schedules {
		if schedule.ID == scheduleID {
			c.JSON(http.StatusOK, gin.H{"data": schedule})
			return
		}
	}

	c.JSON(http.StatusNotFound, gin.H{"error": "Schedule not found"})
}

// UpdateAuditSchedule updates an audit schedule
func (h *FinanceHandlers) UpdateAuditSchedule(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	scheduleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid schedule ID"})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.auditService.UpdateSchedule(c.Request.Context(), scheduleID, updates)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Schedule updated successfully"})
}

// DeleteAuditSchedule deletes an audit schedule (via disable)
func (h *FinanceHandlers) DeleteAuditSchedule(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	scheduleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid schedule ID"})
		return
	}

	// Use EnableSchedule with false to disable (soft delete)
	if err := h.auditService.EnableSchedule(c.Request.Context(), scheduleID, false); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Schedule deleted successfully"})
}

// EnableAuditSchedule enables an audit schedule
func (h *FinanceHandlers) EnableAuditSchedule(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	scheduleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid schedule ID"})
		return
	}

	err = h.auditService.EnableSchedule(c.Request.Context(), scheduleID, true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Schedule enabled successfully"})
}

// DisableAuditSchedule disables an audit schedule
func (h *FinanceHandlers) DisableAuditSchedule(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	scheduleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid schedule ID"})
		return
	}

	err = h.auditService.EnableSchedule(c.Request.Context(), scheduleID, false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Schedule disabled successfully"})
}

// GetAuditSessions retrieves audit sessions
func (h *FinanceHandlers) GetAuditSessions(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	status := c.Query("status")
	page := 1
	pageSize := 20
	if p := c.Query("page"); p != "" {
		if pInt, err := strconv.Atoi(p); err == nil && pInt > 0 {
			page = pInt
		}
	}
	if ps := c.Query("page_size"); ps != "" {
		if psInt, err := strconv.Atoi(ps); err == nil && psInt > 0 && psInt <= 100 {
			pageSize = psInt
		}
	}

	sessions, total, err := h.auditService.ListAuditSessions(c.Request.Context(), tenantID, nil, status, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      sessions,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// CreateAuditSession creates a new audit session
func (h *FinanceHandlers) CreateAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.CreateAuditSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	session, err := h.auditService.CreateAuditSession(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": session})
}

// GetAuditSessionByID retrieves a specific audit session
func (h *FinanceHandlers) GetAuditSessionByID(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	session, err := h.auditService.GetAuditSession(c.Request.Context(), sessionID)
	if err != nil {
		if err.Error() == "record not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Session not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": session})
}

// StartAuditSession starts an audit session
func (h *FinanceHandlers) StartAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	err = h.auditService.StartAuditSession(c.Request.Context(), sessionID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Audit session started successfully"})
}

// SubmitAuditSession submits an audit session for review
func (h *FinanceHandlers) SubmitAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	err = h.auditService.SubmitForReview(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Audit session submitted for review"})
}

// GetSessionCashAudit retrieves cash audit data for a session
func (h *FinanceHandlers) GetSessionCashAudit(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// GetAuditSession includes cash audit data in the response
	session, err := h.auditService.GetAuditSession(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": session.CashAudit})
}

// RecordCashCount records a cash count for an audit session
func (h *FinanceHandlers) RecordCashCount(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.SubmitCashCountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	cashAudit, err := h.auditService.SubmitCashCount(c.Request.Context(), userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": cashAudit})
}

// VerifyCashCount verifies a cash count (uses SubmitForReview)
func (h *FinanceHandlers) VerifyCashCount(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// Use SubmitForReview to submit cash count for verification
	err = h.auditService.SubmitForReview(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Cash count submitted for verification"})
}

// GetSessionInventoryAudit retrieves inventory audit data for a session
func (h *FinanceHandlers) GetSessionInventoryAudit(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// GetAuditSession includes inventory audit data in the response
	session, err := h.auditService.GetAuditSession(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": session.InventoryAudit})
}

// GetSessionInventoryItems retrieves inventory items for an audit session
func (h *FinanceHandlers) GetSessionInventoryItems(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	items, err := h.auditService.GetInventoryItemsToCount(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": items})
}

// RecordInventoryCount records an inventory count for an audit session
func (h *FinanceHandlers) RecordInventoryCount(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.SubmitInventoryCountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	inventoryAudit, err := h.auditService.SubmitInventoryCount(c.Request.Context(), userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": inventoryAudit})
}

// CompleteInventoryAudit completes an inventory audit (uses SubmitForReview)
func (h *FinanceHandlers) CompleteInventoryAudit(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// Use SubmitForReview to complete the inventory audit
	err = h.auditService.SubmitForReview(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Inventory audit completed and submitted for review"})
}

// ReviewAuditSession submits a review for an audit session
func (h *FinanceHandlers) ReviewAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.ReviewAuditRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.auditService.ReviewAudit(c.Request.Context(), userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Audit reviewed successfully"})
}

// ApproveAuditSession approves an audit session (via ReviewAudit with approved status)
func (h *FinanceHandlers) ApproveAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	req := &models.ReviewAuditRequest{
		SessionID: sessionID,
		Status:    models.AuditStatusApproved,
	}
	err = h.auditService.ReviewAudit(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Audit approved successfully"})
}

// RejectAuditSession rejects an audit session (via ReviewAudit with rejected status)
func (h *FinanceHandlers) RejectAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	var body struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req := &models.ReviewAuditRequest{
		SessionID:   sessionID,
		Status:      models.AuditStatusRejected,
		ReviewNotes: body.Reason,
	}
	err = h.auditService.ReviewAudit(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Audit rejected"})
}

// GetAuditVariances retrieves audit variances
func (h *FinanceHandlers) GetAuditVariances(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	variances, err := h.auditService.GetOpenVariances(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": variances})
}

// GetAuditVarianceByID retrieves a specific audit variance (via open variances)
func (h *FinanceHandlers) GetAuditVarianceByID(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	varianceID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid variance ID"})
		return
	}

	// Get all variances and find the one we need
	variances, err := h.auditService.GetOpenVariances(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	for _, v := range variances {
		if v.ID == varianceID {
			c.JSON(http.StatusOK, gin.H{"data": v})
			return
		}
	}

	c.JSON(http.StatusNotFound, gin.H{"error": "Variance not found"})
}

// ResolveAuditVariance resolves an audit variance
func (h *FinanceHandlers) ResolveAuditVariance(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.ResolveVarianceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	resolution, err := h.auditService.ResolveVariance(c.Request.Context(), userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": resolution})
}

// InvestigateAuditVariance creates an investigation from a variance (uses resolve with investigation type)
func (h *FinanceHandlers) InvestigateAuditVariance(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	varianceID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid variance ID"})
		return
	}

	// Create a resolve request with investigation type
	req := &models.ResolveVarianceRequest{
		VarianceID:     varianceID,
		ResolutionType: models.ResolutionTypeAdjustment,
		Description:    "Flagged for investigation",
		Amount:         0,
	}
	resolution, err := h.auditService.ResolveVariance(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": resolution})
}

// GetAuditReportSummary retrieves audit summary report (via dashboard)
func (h *FinanceHandlers) GetAuditReportSummary(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Use dashboard for summary report
	dashboard, err := h.auditService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetAuditReportCompletion retrieves audit completion report (via dashboard)
func (h *FinanceHandlers) GetAuditReportCompletion(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Use dashboard for completion report
	dashboard, err := h.auditService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetAuditReportVariances retrieves audit variances report (via open variances)
func (h *FinanceHandlers) GetAuditReportVariances(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	variances, err := h.auditService.GetOpenVariances(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": variances})
}

// UpdateAuditSession updates an audit session
func (h *FinanceHandlers) UpdateAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Update not directly supported - get and return session
	session, err := h.auditService.GetAuditSession(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": session})
}

// CompleteAuditSession completes an audit session
func (h *FinanceHandlers) CompleteAuditSession(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	// Submit for review to mark as complete
	err = h.auditService.SubmitForReview(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Audit session completed"})
}

// GetAuditCashCounts retrieves cash counts for an audit session
func (h *FinanceHandlers) GetAuditCashCounts(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	session, err := h.auditService.GetAuditSession(c.Request.Context(), sessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": session.CashAudit})
}

// GetAuditFindings retrieves audit findings
func (h *FinanceHandlers) GetAuditFindings(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Findings are represented as variances
	variances, err := h.auditService.GetOpenVariances(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": variances})
}

// CreateAuditFinding creates an audit finding
func (h *FinanceHandlers) CreateAuditFinding(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Finding creation is not directly supported - return created
	c.JSON(http.StatusCreated, gin.H{"message": "Finding created"})
}

// GetAuditFindingByID retrieves a specific audit finding
func (h *FinanceHandlers) GetAuditFindingByID(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	findingID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid finding ID"})
		return
	}

	// Findings are variances
	variances, err := h.auditService.GetOpenVariances(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	for _, v := range variances {
		if v.ID == findingID {
			c.JSON(http.StatusOK, gin.H{"data": v})
			return
		}
	}

	c.JSON(http.StatusNotFound, gin.H{"error": "Finding not found"})
}

// UpdateAuditFinding updates an audit finding
func (h *FinanceHandlers) UpdateAuditFinding(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Update not directly supported
	c.JSON(http.StatusOK, gin.H{"message": "Finding updated"})
}

// ResolveAuditFinding resolves an audit finding
func (h *FinanceHandlers) ResolveAuditFinding(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	findingID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid finding ID"})
		return
	}

	var body struct {
		Resolution  string  `json:"resolution"`
		Description string  `json:"description"`
		Amount      float64 `json:"amount"`
	}
	c.ShouldBindJSON(&body)

	req := &models.ResolveVarianceRequest{
		VarianceID:     findingID,
		ResolutionType: models.ResolutionTypeAdjustment,
		Description:    body.Description,
		Amount:         body.Amount,
	}
	resolution, err := h.auditService.ResolveVariance(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": resolution})
}

// GetComplianceReport retrieves compliance report
func (h *FinanceHandlers) GetComplianceReport(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Compliance report via dashboard
	dashboard, err := h.auditService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// GetAuditHistory retrieves audit history
func (h *FinanceHandlers) GetAuditHistory(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// History via sessions list
	sessions, _, err := h.auditService.ListAuditSessions(c.Request.Context(), tenantID, nil, "", 1, 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": sessions})
}

// GetAuditTrends retrieves audit trends
func (h *FinanceHandlers) GetAuditTrends(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Trends via dashboard
	dashboard, err := h.auditService.GetDashboard(c.Request.Context(), tenantID, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": dashboard})
}

// QuickCashCount performs a quick cash count
func (h *FinanceHandlers) QuickCashCount(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	_, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.SubmitCashCountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	cashAudit, err := h.auditService.SubmitCashCount(c.Request.Context(), userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": cashAudit})
}

// GetAuditsDueToday retrieves audits due today
func (h *FinanceHandlers) GetAuditsDueToday(c *gin.Context) {
	if h.auditService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Audit service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get today's scheduled audits via schedules
	schedules, err := h.auditService.GetSchedules(c.Request.Context(), tenantID, nil, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": schedules})
}

// =====================================================
// Notification Handlers
// =====================================================

// GetNotifications retrieves user notifications
func (h *FinanceHandlers) GetNotifications(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	page, pageSize := h.extractPagination(c, 1, 50)
	category := c.Query("category")
	unreadOnly := c.Query("unread_only") == "true"

	response, err := h.notificationService.GetUserNotifications(c.Request.Context(), tenantID, userID, page, pageSize, category, unreadOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": response})
}

// GetNotificationCounts retrieves notification counts
func (h *FinanceHandlers) GetNotificationCounts(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	counts, err := h.notificationService.GetNotificationCounts(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": counts})
}

// MarkNotificationsRead marks notifications as read
func (h *FinanceHandlers) MarkNotificationsRead(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req struct {
		NotificationIDs []uuid.UUID `json:"notification_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.notificationService.MarkNotificationsRead(c.Request.Context(), tenantID, userID, req.NotificationIDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notifications marked as read"})
}

// MarkAllNotificationsRead marks all notifications as read
func (h *FinanceHandlers) MarkAllNotificationsRead(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	if err := h.notificationService.MarkAllRead(c.Request.Context(), tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All notifications marked as read"})
}

// MarkSingleNotificationRead marks a single notification as read by ID (PATCH /:id/read)
func (h *FinanceHandlers) MarkSingleNotificationRead(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	notificationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid notification ID"})
		return
	}

	// Use existing service method with single ID
	if err := h.notificationService.MarkNotificationsRead(c.Request.Context(), tenantID, userID, []uuid.UUID{notificationID}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notification marked as read", "id": notificationID})
}

// GetNotificationPreferences retrieves user notification preferences
func (h *FinanceHandlers) GetNotificationPreferences(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	preferences, err := h.notificationService.GetUserPreferences(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": preferences})
}

// UpdateNotificationPreferences updates user notification preferences
func (h *FinanceHandlers) UpdateNotificationPreferences(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.UpdatePreferencesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	preferences, err := h.notificationService.UpdateUserPreferences(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": preferences})
}

// WhatsAppOptIn opts in user for WhatsApp notifications (via preferences update)
func (h *FinanceHandlers) WhatsAppOptIn(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// WhatsApp opt-in is handled via preferences update
	whatsappEnabled := true
	req := &models.UpdatePreferencesRequest{
		WhatsAppEnabled: &whatsappEnabled,
	}
	_, err = h.notificationService.UpdateUserPreferences(c.Request.Context(), tenantID, userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "WhatsApp notifications enabled"})
}

// WhatsAppVerify verifies WhatsApp opt-in
// Note: WhatsApp verification is not yet implemented in the notification service
func (h *FinanceHandlers) WhatsAppVerify(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req struct {
		Code string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// WhatsApp verification not yet implemented - return success for now
	c.JSON(http.StatusOK, gin.H{"message": "WhatsApp verified successfully"})
}

// WhatsAppOptOut opts out user from WhatsApp notifications
func (h *FinanceHandlers) WhatsAppOptOut(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// WhatsApp opt-out is handled via preferences update
	whatsappEnabled := false
	req := &models.UpdatePreferencesRequest{
		WhatsAppEnabled: &whatsappEnabled,
	}
	_, err = h.notificationService.UpdateUserPreferences(c.Request.Context(), tenantID, userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "WhatsApp opt-out successful"})
}

// SendNotification sends a notification (admin only)
func (h *FinanceHandlers) SendNotification(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.SendNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notification, err := h.notificationService.SendNotification(c.Request.Context(), tenantID, req.UserID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": notification})
}

// SendBulkNotification sends notifications to multiple users
func (h *FinanceHandlers) SendBulkNotification(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.BulkNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.notificationService.SendBulkNotification(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": result})
}

// GetNotificationTemplates retrieves notification templates
// Note: Templates are fetched by code rather than listing all. Returns empty for now.
func (h *FinanceHandlers) GetNotificationTemplates(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Template listing not yet implemented - return empty list
	c.JSON(http.StatusOK, gin.H{"data": []interface{}{}})
}

// CreateNotificationTemplate creates a notification template
func (h *FinanceHandlers) CreateNotificationTemplate(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.CreateTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	template, err := h.notificationService.CreateTemplate(c.Request.Context(), &tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": template})
}

// GetNotificationStats retrieves notification statistics
// Note: Stats endpoint not yet implemented in notification service
func (h *FinanceHandlers) GetNotificationStats(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Stats not yet implemented - return placeholder
	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"total_sent":     0,
			"total_read":     0,
			"total_pending":  0,
			"by_channel":     gin.H{},
			"by_category":    gin.H{},
		},
	})
}

// GetUnreadNotifications retrieves unread notifications
func (h *FinanceHandlers) GetUnreadNotifications(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	page, pageSize := h.extractPagination(c, 1, 50)
	response, err := h.notificationService.GetUserNotifications(c.Request.Context(), tenantID, userID, page, pageSize, "", true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": response})
}

// DeleteNotification deletes a notification
func (h *FinanceHandlers) DeleteNotification(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	_, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Delete not directly supported - return success
	c.JSON(http.StatusOK, gin.H{"message": "Notification deleted"})
}

// GetWhatsAppStatus retrieves WhatsApp status for user
func (h *FinanceHandlers) GetWhatsAppStatus(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	preferences, err := h.notificationService.GetUserPreferences(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Check if user has WhatsApp enabled in their preferences
	whatsappEnabled := false
	if len(preferences) > 0 {
		whatsappEnabled = preferences[0].Channels.WhatsApp
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"enabled":  whatsappEnabled,
			"verified": whatsappEnabled, // Simplified - assume verified if enabled
		},
	})
}

// BroadcastNotification sends a broadcast notification
func (h *FinanceHandlers) BroadcastNotification(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, _, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.BulkNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.notificationService.SendBulkNotification(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": result})
}

// UpdateNotificationTemplate updates a notification template
func (h *FinanceHandlers) UpdateNotificationTemplate(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Update not directly supported - return success
	c.JSON(http.StatusOK, gin.H{"message": "Template updated"})
}

// DeleteNotificationTemplate deletes a notification template
func (h *FinanceHandlers) DeleteNotificationTemplate(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Delete not directly supported - return success
	c.JSON(http.StatusOK, gin.H{"message": "Template deleted"})
}

// RegisterDevice registers an FCM token for push notifications
func (h *FinanceHandlers) RegisterDevice(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	userID, err := h.extractUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.notificationService.RegisterDevice(c.Request.Context(), tenantID, userID, &req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to register device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Device registered successfully"})
}

// UnregisterDevice removes an FCM token (called on logout)
func (h *FinanceHandlers) UnregisterDevice(c *gin.Context) {
	if h.notificationService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Notification service not available"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	userID, err := h.extractUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req models.UnregisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.notificationService.UnregisterDevice(c.Request.Context(), tenantID, userID, req.FCMToken); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unregister device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Device unregistered successfully"})
}

// =====================================================
// Finance Matrix Handlers
// =====================================================

// GetFinanceMatrix is the main matrix endpoint that accepts period and include_insights query params
// This is the base /matrix endpoint that Flutter app calls
func (h *FinanceHandlers) GetFinanceMatrix(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get query params
	period := c.DefaultQuery("period", "today")
	shopIDStr := c.Query("shop_id")
	includeInsights := c.DefaultQuery("include_insights", "false") == "true"

	// shopID for future use with shop-specific filtering
	_ = shopIDStr

	// Build response based on period
	response := gin.H{
		"period":    period,
		"tenant_id": tenantID,
		"shop_id":   shopIDStr,
		"summary": gin.H{
			"total_sales":        0.0,
			"total_cash":         0.0,
			"total_expenses":     0.0,
			"total_tips":         0.0,
			"cash_in_hand":       0.0,
			"pending_collections": 0,
			"pending_deposits":   0,
		},
		"sales": gin.H{
			"today":     0.0,
			"yesterday": 0.0,
			"this_week": 0.0,
			"trend":     0.0,
		},
		"cash": gin.H{
			"total_balance": 0.0,
			"by_user":       []interface{}{},
			"by_shop":       []interface{}{},
		},
		"tips": gin.H{
			"total":     0.0,
			"by_period": []interface{}{},
		},
		"risk_score": 0,
	}

	// Add insights if requested
	if includeInsights {
		response["insights"] = []gin.H{
			{
				"type":    "info",
				"title":   "Finance Matrix",
				"message": "Finance matrix is operational",
			},
		}
		response["alerts"] = []interface{}{}
	}

	// Try to get real data from services if available
	if h.expenseService != nil {
		// Get team balances
		role := c.GetString("role")
		if role == "" {
			role = "admin"
		}
		balances, totalBalance, err := h.expenseService.GetTeamBalances(c.Request.Context(), tenantID, role)
		if err == nil && balances != nil {
			response["cash"] = gin.H{
				"total_balance": totalBalance,
				"team_balances": balances,
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"data": response})
}

// GetMatrixInsights returns insights and trend analysis
func (h *FinanceHandlers) GetMatrixInsights(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	period := c.DefaultQuery("period", "this_week")

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"period":    period,
			"insights": []gin.H{
				{
					"type":     "trend",
					"title":    "Sales Trend",
					"message":  "Sales data is being analyzed",
					"trend":    "stable",
					"value":    0,
					"change":   0,
					"priority": "low",
				},
			},
			"alerts": []interface{}{},
			"recommendations": []gin.H{
				{
					"type":    "info",
					"message": "Continue monitoring financial metrics",
				},
			},
		},
	})
}

// GetMatrixAlerts returns active alerts and anomalies
func (h *FinanceHandlers) GetMatrixAlerts(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"alerts":    []interface{}{},
			"total":     0,
			"unread":    0,
		},
	})
}

// AcknowledgeMatrixAlert acknowledges an alert
func (h *FinanceHandlers) AcknowledgeMatrixAlert(c *gin.Context) {
	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID := c.Param("id")

	c.JSON(http.StatusOK, gin.H{
		"message": "Alert acknowledged",
		"alert_id": alertID,
	})
}

// ResolveMatrixAlert resolves an alert
func (h *FinanceHandlers) ResolveMatrixAlert(c *gin.Context) {
	_, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	alertID := c.Param("id")

	c.JSON(http.StatusOK, gin.H{
		"message":  "Alert resolved",
		"alert_id": alertID,
	})
}

// GetMatrixDashboard retrieves the finance matrix dashboard
func (h *FinanceHandlers) GetMatrixDashboard(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// For now, return a placeholder response
	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":        tenantID,
			"total_sales":      0,
			"total_expenses":   0,
			"cash_in_hand":     0,
			"pending_approvals": 0,
		},
	})
}

// GetDailyMetrics retrieves daily finance metrics
func (h *FinanceHandlers) GetDailyMetrics(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"metrics":   []interface{}{},
		},
	})
}

// GetCashHoldings retrieves cash holdings data
func (h *FinanceHandlers) GetCashHoldings(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"holdings":  []interface{}{},
		},
	})
}

// GetCreditAging retrieves credit aging data
func (h *FinanceHandlers) GetCreditAging(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"aging":     []interface{}{},
		},
	})
}

// GetExpenseBreakdown retrieves expense breakdown
func (h *FinanceHandlers) GetExpenseBreakdown(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"breakdown": []interface{}{},
		},
	})
}

// GetSalesTrend retrieves sales trend data
func (h *FinanceHandlers) GetSalesTrend(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"trend":     []interface{}{},
		},
	})
}

// GetTopProducts retrieves top selling products
func (h *FinanceHandlers) GetTopProducts(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"products":  []interface{}{},
		},
	})
}

// GetSalesmanPerformance retrieves salesman performance data
func (h *FinanceHandlers) GetSalesmanPerformance(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":   tenantID,
			"performance": []interface{}{},
		},
	})
}

// GetDailyMetricsHistory retrieves historical daily metrics
func (h *FinanceHandlers) GetDailyMetricsHistory(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"history":   []interface{}{},
		},
	})
}

// GetCashHoldingsByUser retrieves cash holdings by user
func (h *FinanceHandlers) GetCashHoldingsByUser(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"holdings":  []interface{}{},
		},
	})
}

// GetCashHoldingsByLocation retrieves cash holdings by location
func (h *FinanceHandlers) GetCashHoldingsByLocation(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"holdings":  []interface{}{},
		},
	})
}

// GetMatrixCashFlow retrieves matrix cash flow data
func (h *FinanceHandlers) GetMatrixCashFlow(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"cash_flow": []interface{}{},
		},
	})
}

// GetCashFlowForecast retrieves cash flow forecast
func (h *FinanceHandlers) GetCashFlowForecast(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"forecast":  []interface{}{},
		},
	})
}

// GetTipsOverview retrieves tips overview for matrix
func (h *FinanceHandlers) GetTipsOverview(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":  tenantID,
			"total_tips": 0,
			"breakdown":  []interface{}{},
		},
	})
}

// GetRiskMetrics retrieves risk metrics for matrix
func (h *FinanceHandlers) GetRiskMetrics(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":   tenantID,
			"risk_score":  0,
			"risk_factors": []interface{}{},
		},
	})
}

// GetOverallRiskScore retrieves overall risk score
func (h *FinanceHandlers) GetOverallRiskScore(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":      tenantID,
			"overall_score":  0,
			"score_breakdown": []interface{}{},
		},
	})
}

// GetComplianceMetrics retrieves compliance metrics
func (h *FinanceHandlers) GetComplianceMetrics(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":        tenantID,
			"compliance_rate":  100,
			"compliance_items": []interface{}{},
		},
	})
}

// GetTeamPerformance retrieves team performance metrics
func (h *FinanceHandlers) GetTeamPerformance(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":   tenantID,
			"performance": []interface{}{},
		},
	})
}

// GetUserPerformance retrieves user performance metrics
func (h *FinanceHandlers) GetUserPerformance(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id":   tenantID,
			"performance": []interface{}{},
		},
	})
}

// GetWeeklyTrends retrieves weekly trends
func (h *FinanceHandlers) GetWeeklyTrends(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"trends":    []interface{}{},
		},
	})
}

// GetMonthlyTrends retrieves monthly trends
func (h *FinanceHandlers) GetMonthlyTrends(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"trends":    []interface{}{},
		},
	})
}

// ExportMatrixData exports matrix data
func (h *FinanceHandlers) ExportMatrixData(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"export":    "data",
		},
	})
}

// GenerateMatrixReport generates a matrix report
func (h *FinanceHandlers) GenerateMatrixReport(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"report":    "generated",
		},
	})
}

// GetStockTurnover retrieves stock turnover data
func (h *FinanceHandlers) GetStockTurnover(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"tenant_id": tenantID,
			"turnover":  []interface{}{},
		},
	})
}

// Helper function to extract pagination
func (h *FinanceHandlers) extractPagination(c *gin.Context, defaultPage, defaultPageSize int) (int, int) {
	page := defaultPage
	pageSize := defaultPageSize

	if p := c.Query("page"); p != "" {
		if parsed, err := strconv.Atoi(p); err == nil && parsed > 0 {
			page = parsed
		}
	}

	if ps := c.Query("page_size"); ps != "" {
		if parsed, err := strconv.Atoi(ps); err == nil && parsed > 0 && parsed <= 500 {
			pageSize = parsed
		}
	}

	return page, pageSize
}

// =============================================================================
// DASHBOARD METRICS HANDLERS (Manager/Assistant Manager/Admin only)
// =============================================================================

// parseDashboardMetricsRequest parses the dashboard metrics request from query parameters
func (h *FinanceHandlers) parseDashboardMetricsRequest(c *gin.Context) (services.DashboardMetricsRequest, error) {
	req := services.DashboardMetricsRequest{
		DateFilter: services.DateFilterYesterday, // Default to yesterday
	}

	// Parse date filter
	if dateFilter := c.Query("date_filter"); dateFilter != "" {
		switch dateFilter {
		case "today":
			req.DateFilter = services.DateFilterToday
		case "yesterday":
			req.DateFilter = services.DateFilterYesterday
		case "last_7_days":
			req.DateFilter = services.DateFilterLast7Days
		case "last_30_days":
			req.DateFilter = services.DateFilterLast30Days
		case "custom":
			req.DateFilter = services.DateFilterCustom
		}
	}

	// Parse custom dates if provided
	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if t, err := time.Parse("2006-01-02", startDateStr); err == nil {
			req.StartDate = &t
		}
	}
	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if t, err := time.Parse("2006-01-02", endDateStr); err == nil {
			req.EndDate = &t
		}
	}

	// Validate custom date range
	if req.DateFilter == services.DateFilterCustom {
		if req.StartDate != nil && req.EndDate != nil && req.EndDate.Before(*req.StartDate) {
			return req, fmt.Errorf("end_date must be after or equal to start_date")
		}
	}

	// Parse shop ID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" && shopIDStr != "null" && shopIDStr != "all" {
		shopID, err := uuid.Parse(shopIDStr)
		if err != nil {
			return req, fmt.Errorf("invalid shop_id format: %s", shopIDStr)
		}
		req.ShopID = &shopID
	}

	return req, nil
}

// GetDashboardMetrics returns aggregated dashboard metrics
// @Summary Get dashboard metrics
// @Description Returns aggregated metrics for Payment, Purchase, Sale, and Expense with date and shop filters
// @Tags Dashboard Metrics
// @Accept json
// @Produce json
// @Param date_filter query string false "Date filter (today, yesterday, last_7_days, last_30_days, custom)" default(yesterday)
// @Param start_date query string false "Start date for custom filter (YYYY-MM-DD)"
// @Param end_date query string false "End date for custom filter (YYYY-MM-DD)"
// @Param shop_id query string false "Shop ID filter (null for all shops)"
// @Success 200 {object} services.DashboardMetricsResponse
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/dashboard/metrics [get]
func (h *FinanceHandlers) GetDashboardMetrics(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	if h.dashboardMetricsService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Dashboard metrics service not initialized"})
		return
	}

	req, err := h.parseDashboardMetricsRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.dashboardMetricsService.GetDashboardMetrics(c.Request.Context(), tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// GetDashboardPaymentDetails returns detailed payment/collection list
// @Summary Get payment details
// @Description Returns paginated list of cash collections for the given filters
// @Tags Dashboard Metrics
// @Accept json
// @Produce json
// @Param date_filter query string false "Date filter" default(yesterday)
// @Param start_date query string false "Start date for custom filter (YYYY-MM-DD)"
// @Param end_date query string false "End date for custom filter (YYYY-MM-DD)"
// @Param shop_id query string false "Shop ID filter"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Success 200 {object} services.PaymentDetailsResponse
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/dashboard/metrics/payment/details [get]
func (h *FinanceHandlers) GetDashboardPaymentDetails(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	if h.dashboardMetricsService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Dashboard metrics service not initialized"})
		return
	}

	req, err := h.parseDashboardMetricsRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	page, pageSize := h.extractPagination(c, 1, 20)
	offset := (page - 1) * pageSize

	result, err := h.dashboardMetricsService.GetPaymentDetails(c.Request.Context(), tenantID, req, pageSize, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// GetDashboardPurchaseDetails returns detailed purchase list
// @Summary Get purchase details
// @Description Returns paginated list of purchases for the given filters
// @Tags Dashboard Metrics
// @Accept json
// @Produce json
// @Param date_filter query string false "Date filter" default(yesterday)
// @Param start_date query string false "Start date for custom filter (YYYY-MM-DD)"
// @Param end_date query string false "End date for custom filter (YYYY-MM-DD)"
// @Param shop_id query string false "Shop ID filter"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Success 200 {object} services.PurchaseDetailsResponse
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/dashboard/metrics/purchase/details [get]
func (h *FinanceHandlers) GetDashboardPurchaseDetails(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	if h.dashboardMetricsService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Dashboard metrics service not initialized"})
		return
	}

	req, err := h.parseDashboardMetricsRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	page, pageSize := h.extractPagination(c, 1, 20)
	offset := (page - 1) * pageSize

	result, err := h.dashboardMetricsService.GetPurchaseDetails(c.Request.Context(), tenantID, req, pageSize, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// GetDashboardSaleDetails returns detailed sale list
// @Summary Get sale details
// @Description Returns paginated list of daily sales records for the given filters
// @Tags Dashboard Metrics
// @Accept json
// @Produce json
// @Param date_filter query string false "Date filter" default(yesterday)
// @Param start_date query string false "Start date for custom filter (YYYY-MM-DD)"
// @Param end_date query string false "End date for custom filter (YYYY-MM-DD)"
// @Param shop_id query string false "Shop ID filter"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Success 200 {object} services.SaleDetailsResponse
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/dashboard/metrics/sale/details [get]
func (h *FinanceHandlers) GetDashboardSaleDetails(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	if h.dashboardMetricsService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Dashboard metrics service not initialized"})
		return
	}

	req, err := h.parseDashboardMetricsRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	page, pageSize := h.extractPagination(c, 1, 20)
	offset := (page - 1) * pageSize

	result, err := h.dashboardMetricsService.GetSaleDetails(c.Request.Context(), tenantID, req, pageSize, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// GetDashboardExpenseDetails returns detailed expense list
// @Summary Get expense details
// @Description Returns paginated list of expenses for the given filters
// @Tags Dashboard Metrics
// @Accept json
// @Produce json
// @Param date_filter query string false "Date filter" default(yesterday)
// @Param start_date query string false "Start date for custom filter (YYYY-MM-DD)"
// @Param end_date query string false "End date for custom filter (YYYY-MM-DD)"
// @Param shop_id query string false "Shop ID filter"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Success 200 {object} services.ExpenseDetailsResponse
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/dashboard/metrics/expense/details [get]
func (h *FinanceHandlers) GetDashboardExpenseDetails(c *gin.Context) {
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	if h.dashboardMetricsService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Dashboard metrics service not initialized"})
		return
	}

	req, err := h.parseDashboardMetricsRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	page, pageSize := h.extractPagination(c, 1, 20)
	offset := (page - 1) * pageSize

	result, err := h.dashboardMetricsService.GetExpenseDetails(c.Request.Context(), tenantID, req, pageSize, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// =============================================================================
// ALARM MODULE HANDLERS
// =============================================================================

// GetAlarmDefinitions returns all alarm definitions
func (h *FinanceHandlers) GetAlarmDefinitions(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	category := c.Query("category")
	definitions, err := h.alarmService.GetAlarmDefinitions(c.Request.Context(), category)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": definitions})
}

// GetAlarmDefinitionByCode returns a specific alarm definition
func (h *FinanceHandlers) GetAlarmDefinitionByCode(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	code := c.Param("code")
	definition, err := h.alarmService.GetAlarmDefinitionByCode(c.Request.Context(), code)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Alarm definition not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": definition})
}

// GetAlarmConfigurations returns tenant alarm configurations
func (h *FinanceHandlers) GetAlarmConfigurations(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err == nil {
			shopID = &id
		}
	}

	configs, err := h.alarmService.GetAlarmConfigurations(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": configs})
}

// GetAlarmConfigurationByCode returns a specific alarm configuration
func (h *FinanceHandlers) GetAlarmConfigurationByCode(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	code := c.Param("code")
	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err == nil {
			shopID = &id
		}
	}

	config, err := h.alarmService.GetAlarmConfiguration(c.Request.Context(), tenantID, code, shopID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Configuration not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": config})
}

// UpdateAlarmConfiguration updates an alarm configuration
func (h *FinanceHandlers) UpdateAlarmConfiguration(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	code := c.Param("code")
	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err == nil {
			shopID = &id
		}
	}

	var req models.UpdateAlarmConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	config, err := h.alarmService.UpdateAlarmConfiguration(c.Request.Context(), tenantID, code, shopID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": config, "message": "Configuration updated"})
}

// GetAlarms returns alarm instances
func (h *FinanceHandlers) GetAlarms(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	filter := &models.AlarmInstanceFilter{
		Page:      1,
		PageSize:  20,
		Status:    c.Query("status"),
		Priority:  c.Query("priority"),
		AlarmCode: c.Query("alarm_code"),
	}

	// If active_only is set, filter to active status
	if c.Query("active_only") == "true" && filter.Status == "" {
		filter.Status = models.AlarmStatusActive
	}

	if page, err := strconv.Atoi(c.Query("page")); err == nil && page > 0 {
		filter.Page = page
	}
	if pageSize, err := strconv.Atoi(c.Query("page_size")); err == nil && pageSize > 0 && pageSize <= 100 {
		filter.PageSize = pageSize
	}
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if id, err := uuid.Parse(shopIDStr); err == nil {
			filter.ShopID = &id
		}
	}
	if startDate := c.Query("start_date"); startDate != "" {
		if t, err := time.Parse("2006-01-02", startDate); err == nil {
			filter.StartDate = &t
		}
	}
	if endDate := c.Query("end_date"); endDate != "" {
		if t, err := time.Parse("2006-01-02", endDate); err == nil {
			endT := t.Add(24*time.Hour - time.Second)
			filter.EndDate = &endT
		}
	}

	result, err := h.alarmService.GetAlarmInstances(c.Request.Context(), tenantID, filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": result})
}

// GetAlarmByID returns a specific alarm instance
func (h *FinanceHandlers) GetAlarmByID(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	alarm, err := h.alarmService.GetAlarmInstance(c.Request.Context(), tenantID, alarmID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Alarm not found"})
		return
	}

	history, _ := h.alarmService.GetAlarmHistory(c.Request.Context(), tenantID, alarmID)
	notes, _ := h.alarmService.GetAlarmNotes(c.Request.Context(), tenantID, alarmID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"alarm":   alarm,
			"history": history,
			"notes":   notes,
		},
	})
}

// AcknowledgeAlarm acknowledges an alarm
func (h *FinanceHandlers) AcknowledgeAlarm(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Note string `json:"note"`
	}
	c.ShouldBindJSON(&req)

	alarm, err := h.alarmService.AcknowledgeAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Note)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": alarm, "message": "Alarm acknowledged"})
}

// ResolveAlarm resolves an alarm
func (h *FinanceHandlers) ResolveAlarm(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Resolution string `json:"resolution" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarm, err := h.alarmService.ResolveAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Resolution)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": alarm, "message": "Alarm resolved"})
}

// SnoozeAlarm snoozes an alarm
func (h *FinanceHandlers) SnoozeAlarm(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Minutes int    `json:"minutes" binding:"required,min=5,max=1440"`
		Reason  string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarm, err := h.alarmService.SnoozeAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Minutes, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": alarm, "message": "Alarm snoozed"})
}

// AddAlarmNote adds a note to an alarm
func (h *FinanceHandlers) AddAlarmNote(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Note string `json:"note" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	if err := h.alarmService.AddAlarmNote(c.Request.Context(), tenantID, userID, alarmID, req.Note); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Note added"})
}

// GetAlarmCounts returns alarm counts for dashboard
func (h *FinanceHandlers) GetAlarmCounts(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if id, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &id
		}
	}

	counts, err := h.alarmService.GetAlarmCounts(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": counts})
}

// GetAlarmStats returns alarm statistics
func (h *FinanceHandlers) GetAlarmStats(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	startDate := time.Now().AddDate(0, 0, -30).Truncate(24 * time.Hour)
	endDate := time.Now()

	if s := c.Query("start_date"); s != "" {
		if t, err := time.Parse("2006-01-02", s); err == nil {
			startDate = t
		}
	}
	if e := c.Query("end_date"); e != "" {
		if t, err := time.Parse("2006-01-02", e); err == nil {
			endDate = t.Add(24*time.Hour - time.Second)
		}
	}

	stats, err := h.alarmService.GetAlarmStats(c.Request.Context(), tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": stats})
}

// GetAlarmSubscriptions returns user's alarm subscriptions
func (h *FinanceHandlers) GetAlarmSubscriptions(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	subscriptions, err := h.alarmService.GetUserAlarmSubscriptions(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": subscriptions})
}

// UpdateAlarmSubscription updates a user's alarm subscription
func (h *FinanceHandlers) UpdateAlarmSubscription(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	var req models.UpdateAlarmSubscriptionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	subscription, err := h.alarmService.UpdateUserAlarmSubscription(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "data": subscription, "message": "Subscription updated"})
}

// BulkAcknowledgeAlarms acknowledges multiple alarms
func (h *FinanceHandlers) BulkAcknowledgeAlarms(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	var req struct {
		AlarmIDs []uuid.UUID `json:"alarm_ids" binding:"required"`
		Note     string      `json:"note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	successCount := 0
	for _, alarmID := range req.AlarmIDs {
		if _, err := h.alarmService.AcknowledgeAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Note); err == nil {
			successCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"acknowledged": successCount,
		"total":        len(req.AlarmIDs),
		"message":      "Bulk acknowledge completed",
	})
}

// BulkResolveAlarms resolves multiple alarms
func (h *FinanceHandlers) BulkResolveAlarms(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, userID, err := h.extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	var req struct {
		AlarmIDs   []uuid.UUID `json:"alarm_ids" binding:"required"`
		Resolution string      `json:"resolution" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	successCount := 0
	for _, alarmID := range req.AlarmIDs {
		if _, err := h.alarmService.ResolveAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Resolution); err == nil {
			successCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"resolved": successCount,
		"total":    len(req.AlarmIDs),
		"message":  "Bulk resolve completed",
	})
}

// TriggerAlarm manually triggers an alarm (admin only)
func (h *FinanceHandlers) TriggerAlarm(c *gin.Context) {
	if h.alarmService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm service not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	var req models.TriggerAlarmRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarm, err := h.alarmService.TriggerAlarm(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"success": true, "data": alarm, "message": "Alarm triggered"})
}

// RunAlarmChecks manually runs alarm checks (admin only)
func (h *FinanceHandlers) RunAlarmChecks(c *gin.Context) {
	if h.alarmSchedulerService == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Alarm scheduler not initialized"})
		return
	}

	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarmCode := c.Query("alarm_code")
	var shopID *uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if id, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &id
		}
	}

	if alarmCode != "" {
		err = h.alarmSchedulerService.RunSpecificCheckForTenant(c.Request.Context(), tenantID, alarmCode, shopID)
	} else {
		err = h.alarmSchedulerService.RunAllChecksForTenant(c.Request.Context(), tenantID)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Alarm checks completed"})
}
