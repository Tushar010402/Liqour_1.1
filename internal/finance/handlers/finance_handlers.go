package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/finance/services"
)

type FinanceHandlers struct {
	vendorService           *services.VendorService
	expenseService          *services.ExpenseService
	assistantManagerService *services.AssistantManagerService
}

func NewFinanceHandlers(
	vendorService *services.VendorService,
	expenseService *services.ExpenseService,
	assistantManagerService *services.AssistantManagerService,
) *FinanceHandlers {
	return &FinanceHandlers{
		vendorService:           vendorService,
		expenseService:          expenseService,
		assistantManagerService: assistantManagerService,
	}
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
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	status := c.Query("status")
	includeOverdue := c.Query("include_overdue") == "true"
	limit, offset := h.getPagination(c)

	collections, total, err := h.assistantManagerService.GetMoneyCollections(c.Request.Context(), tenantID, status, includeOverdue, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"collections": collections,
		"total":       total,
		"limit":       limit,
		"offset":      offset,
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
	c.ShouldBindJSON(&reqBody)

	err = h.assistantManagerService.RejectMoneyCollection(c.Request.Context(), id, tenantID, userID, reqBody.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Money collection rejected successfully"})
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

// Helper functions
func (h *FinanceHandlers) extractTenantID(c *gin.Context) (uuid.UUID, error) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		return uuid.Nil, fmt.Errorf("tenant ID not found")
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
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
	tenantID, err := h.extractTenantID(c)
	if err != nil {
		return uuid.Nil, uuid.Nil, err
	}

	userID, err := h.extractUserID(c)
	if err != nil {
		return uuid.Nil, uuid.Nil, err
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