package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/finance/services"
)

// BankAccountHandlers handles all bank account management endpoints
type BankAccountHandlers struct {
	bankService *services.BankAccountService
}

// NewBankAccountHandlers creates a new bank account handlers instance
func NewBankAccountHandlers(bankService *services.BankAccountService) *BankAccountHandlers {
	return &BankAccountHandlers{
		bankService: bankService,
	}
}

// ═══════════════════════════════════════════════════════════════════════════
// Bank Account CRUD Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// CreateBankAccountRequest represents the request body for creating a bank account
type CreateBankAccountRequest struct {
	BankName          string  `json:"bank_name" binding:"required"`
	AccountNumber     string  `json:"account_number" binding:"required"`
	AccountHolderName string  `json:"account_holder_name" binding:"required"`
	IFSCCode          string  `json:"ifsc_code"`
	BranchName        string  `json:"branch_name"`
	BranchAddress     string  `json:"branch_address"`
	AccountType       string  `json:"account_type" binding:"required,oneof=current savings od cash_credit"`
	ODLimit           float64 `json:"od_limit" binding:"gte=0"`
	ODInterestRate    float64 `json:"od_interest_rate" binding:"gte=0,lte=100"`
	IsDefault         bool    `json:"is_default"`
	Notes             string  `json:"notes"`
}

// CreateBankAccount godoc
// @Summary Create a new bank account
// @Description Create a new bank account for the tenant with OD limit tracking
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Param request body CreateBankAccountRequest true "Bank account details"
// @Success 201 {object} models.TenantBankAccount
// @Router /api/finance/bank-accounts [post]
func (h *BankAccountHandlers) CreateBankAccount(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req CreateBankAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create service request
	serviceReq := &services.CreateBankAccountRequest{
		TenantID:          tenantID,
		BankName:          req.BankName,
		AccountNumber:     req.AccountNumber,
		AccountHolderName: req.AccountHolderName,
		IFSCCode:          req.IFSCCode,
		BranchName:        req.BranchName,
		BranchAddress:     req.BranchAddress,
		AccountType:       req.AccountType,
		ODLimit:           req.ODLimit,
		ODInterestRate:    req.ODInterestRate,
		IsDefault:         req.IsDefault,
		Notes:             req.Notes,
		CreatedBy:         userID,
	}

	account, err := h.bankService.CreateBankAccount(c.Request.Context(), serviceReq)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"bank_account": account,
		"message":      "Bank account created successfully",
	})
}

// UpdateBankAccountRequest represents the request body for updating a bank account
type UpdateBankAccountRequest struct {
	BankName       *string  `json:"bank_name"`
	BranchName     *string  `json:"branch_name"`
	BranchAddress  *string  `json:"branch_address"`
	ODLimit        *float64 `json:"od_limit" binding:"omitempty,gte=0"`
	ODInterestRate *float64 `json:"od_interest_rate" binding:"omitempty,gte=0,lte=100"`
	IsActive       *bool    `json:"is_active"`
	IsDefault      *bool    `json:"is_default"`
	Notes          *string  `json:"notes"`
}

// UpdateBankAccount godoc
// @Summary Update a bank account
// @Description Update bank account details and OD limits
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Param id path string true "Bank Account ID"
// @Param request body UpdateBankAccountRequest true "Update details"
// @Success 200 {object} models.TenantBankAccount
// @Router /api/finance/bank-accounts/{id} [put]
func (h *BankAccountHandlers) UpdateBankAccount(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accountID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid account ID"})
		return
	}

	var req UpdateBankAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create service request
	serviceReq := &services.UpdateBankAccountRequest{
		AccountID:      accountID,
		TenantID:       tenantID,
		BankName:       req.BankName,
		BranchName:     req.BranchName,
		BranchAddress:  req.BranchAddress,
		ODLimit:        req.ODLimit,
		ODInterestRate: req.ODInterestRate,
		IsActive:       req.IsActive,
		IsDefault:      req.IsDefault,
		Notes:          req.Notes,
		UpdatedBy:      userID,
	}

	account, err := h.bankService.UpdateBankAccount(c.Request.Context(), serviceReq)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"bank_account": account,
		"message":      "Bank account updated successfully",
	})
}

// GetBankAccount godoc
// @Summary Get a bank account
// @Description Get bank account details with recent transactions
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Param id path string true "Bank Account ID"
// @Success 200 {object} models.TenantBankAccount
// @Router /api/finance/bank-accounts/{id} [get]
func (h *BankAccountHandlers) GetBankAccount(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accountID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid account ID"})
		return
	}

	account, err := h.bankService.GetBankAccount(c.Request.Context(), accountID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"bank_account": account,
	})
}

// GetBankAccounts godoc
// @Summary List all bank accounts
// @Description Get list of bank accounts for the tenant with filters
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Param account_type query string false "Account type (current/savings/od/cash_credit)"
// @Param is_active query boolean false "Active status"
// @Param is_default query boolean false "Default account"
// @Success 200 {array} models.TenantBankAccount
// @Router /api/finance/bank-accounts [get]
func (h *BankAccountHandlers) GetBankAccounts(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters
	filters := make(map[string]interface{})

	if accountType := c.Query("account_type"); accountType != "" {
		filters["account_type"] = accountType
	}

	if isActiveStr := c.Query("is_active"); isActiveStr != "" {
		if isActive, err := strconv.ParseBool(isActiveStr); err == nil {
			filters["is_active"] = isActive
		}
	}

	if isDefaultStr := c.Query("is_default"); isDefaultStr != "" {
		if isDefault, err := strconv.ParseBool(isDefaultStr); err == nil {
			filters["is_default"] = isDefault
		}
	}

	accounts, err := h.bankService.GetBankAccounts(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"bank_accounts": accounts,
		"count":         len(accounts),
	})
}

// GetDefaultBankAccount godoc
// @Summary Get default bank account
// @Description Get the tenant's default bank account
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Success 200 {object} models.TenantBankAccount
// @Router /api/finance/bank-accounts/default [get]
func (h *BankAccountHandlers) GetDefaultBankAccount(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	account, err := h.bankService.GetDefaultBankAccount(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if account == nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "No default bank account set",
			"message": "Please set a default bank account in settings",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"bank_account": account,
	})
}

// DeleteBankAccount godoc
// @Summary Delete a bank account
// @Description Soft delete a bank account (deactivates if has transactions)
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Param id path string true "Bank Account ID"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/bank-accounts/{id} [delete]
func (h *BankAccountHandlers) DeleteBankAccount(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accountID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid account ID"})
		return
	}

	err = h.bankService.DeleteBankAccount(c.Request.Context(), accountID, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Bank account deleted successfully",
		"account_id": accountID,
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Bank Transaction Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// RecordBankTransactionRequest represents the request body for recording a transaction
type RecordBankTransactionRequest struct {
	TransactionType string     `json:"transaction_type" binding:"required,oneof=deposit withdrawal od_usage od_repayment interest_charge bank_charges adjustment"`
	Amount          float64    `json:"amount" binding:"required,gt=0"`
	ReferenceType   string     `json:"reference_type"`
	ReferenceID     *uuid.UUID `json:"reference_id"`
	BankReferenceNo string     `json:"bank_reference_no"`
	TransactionDate time.Time  `json:"transaction_date"`
	Description     string     `json:"description"` // Optional field - can be empty
	Notes           string     `json:"notes"`
}

// RecordBankTransaction godoc
// @Summary Record a bank transaction
// @Description Record a bank transaction (deposit/withdrawal) and update account balance
// @Tags Bank Transactions
// @Accept json
// @Produce json
// @Param id path string true "Bank Account ID"
// @Param request body RecordBankTransactionRequest true "Transaction details"
// @Success 201 {object} models.TenantBankTransaction
// @Router /api/finance/bank-accounts/{id}/transactions [post]
func (h *BankAccountHandlers) RecordBankTransaction(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accountID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid account ID"})
		return
	}

	var req RecordBankTransactionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Default transaction date to now if not provided
	transactionDate := req.TransactionDate
	if transactionDate.IsZero() {
		transactionDate = time.Now()
	}

	// Create service request
	serviceReq := &services.BankTransactionRequest{
		AccountID:       accountID,
		TenantID:        tenantID,
		TransactionType: req.TransactionType,
		Amount:          req.Amount,
		ReferenceType:   req.ReferenceType,
		ReferenceID:     req.ReferenceID,
		BankReferenceNo: req.BankReferenceNo,
		TransactionDate: transactionDate,
		Description:     req.Description,
		Notes:           req.Notes,
		CreatedBy:       userID,
	}

	transaction, err := h.bankService.RecordBankTransaction(c.Request.Context(), serviceReq)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"transaction": transaction,
		"message":     "Transaction recorded successfully",
	})
}

// GetBankTransactions godoc
// @Summary Get bank transactions
// @Description Get list of bank transactions with filters
// @Tags Bank Transactions
// @Accept json
// @Produce json
// @Param id path string false "Bank Account ID"
// @Param transaction_type query string false "Transaction type"
// @Param start_date query string false "Start date (YYYY-MM-DD)"
// @Param end_date query string false "End date (YYYY-MM-DD)"
// @Param is_reconciled query boolean false "Reconciliation status"
// @Param limit query int false "Limit (default 50)"
// @Param offset query int false "Offset (default 0)"
// @Success 200 {array} models.TenantBankTransaction
// @Router /api/finance/bank-accounts/{id}/transactions [get]
func (h *BankAccountHandlers) GetBankTransactions(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse pagination
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	if limit > 100 {
		limit = 100 // Max limit
	}

	// Build filters
	filters := make(map[string]interface{})

	// Optional account ID filter
	if accountIDStr := c.Param("id"); accountIDStr != "" {
		if accountID, err := uuid.Parse(accountIDStr); err == nil {
			filters["account_id"] = accountID
		}
	}

	if transactionType := c.Query("transaction_type"); transactionType != "" {
		filters["transaction_type"] = transactionType
	}

	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if startDate, err := time.Parse("2006-01-02", startDateStr); err == nil {
			filters["start_date"] = startDate
		}
	}

	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if endDate, err := time.Parse("2006-01-02", endDateStr); err == nil {
			filters["end_date"] = endDate
		}
	}

	if isReconciledStr := c.Query("is_reconciled"); isReconciledStr != "" {
		if isReconciled, err := strconv.ParseBool(isReconciledStr); err == nil {
			filters["is_reconciled"] = isReconciled
		}
	}

	transactions, total, err := h.bankService.GetBankTransactions(c.Request.Context(), tenantID, filters, limit, offset)
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

// ═══════════════════════════════════════════════════════════════════════════
// Bank Reconciliation Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// CreateReconciliationRequest represents the request body for creating a reconciliation
type CreateReconciliationRequest struct {
	ReconciliationDate   time.Time `json:"reconciliation_date" binding:"required"`
	StatementStartDate   time.Time `json:"statement_start_date" binding:"required"`
	StatementEndDate     time.Time `json:"statement_end_date" binding:"required"`
	BankStatementBalance float64   `json:"bank_statement_balance" binding:"required"`
	Notes                string    `json:"notes"`
}

// CreateReconciliation godoc
// @Summary Create a bank reconciliation
// @Description Create a new bank reconciliation record comparing system vs bank statement
// @Tags Bank Reconciliations
// @Accept json
// @Produce json
// @Param id path string true "Bank Account ID"
// @Param request body CreateReconciliationRequest true "Reconciliation details"
// @Success 201 {object} models.BankReconciliation
// @Router /api/finance/bank-accounts/{id}/reconciliations [post]
func (h *BankAccountHandlers) CreateReconciliation(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accountID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid account ID"})
		return
	}

	var req CreateReconciliationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create service request
	serviceReq := &services.CreateReconciliationRequest{
		AccountID:            accountID,
		TenantID:             tenantID,
		ReconciliationDate:   req.ReconciliationDate,
		StatementStartDate:   req.StatementStartDate,
		StatementEndDate:     req.StatementEndDate,
		BankStatementBalance: req.BankStatementBalance,
		Notes:                req.Notes,
		CreatedBy:            userID,
	}

	reconciliation, err := h.bankService.CreateReconciliation(c.Request.Context(), serviceReq)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"reconciliation": reconciliation,
		"message":        "Reconciliation created successfully",
	})
}

// GetReconciliations godoc
// @Summary Get bank reconciliations
// @Description Get list of bank reconciliations with filters
// @Tags Bank Reconciliations
// @Accept json
// @Produce json
// @Param id path string false "Bank Account ID"
// @Param status query string false "Status (pending/in_progress/completed/discrepancy)"
// @Param start_date query string false "Start date (YYYY-MM-DD)"
// @Success 200 {array} models.BankReconciliation
// @Router /api/finance/bank-accounts/{id}/reconciliations [get]
func (h *BankAccountHandlers) GetReconciliations(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters
	filters := make(map[string]interface{})

	// Optional account ID filter
	if accountIDStr := c.Param("id"); accountIDStr != "" {
		if accountID, err := uuid.Parse(accountIDStr); err == nil {
			filters["account_id"] = accountID
		}
	}

	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}

	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if startDate, err := time.Parse("2006-01-02", startDateStr); err == nil {
			filters["start_date"] = startDate
		}
	}

	reconciliations, err := h.bankService.GetReconciliations(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"reconciliations": reconciliations,
		"count":           len(reconciliations),
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Utility Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// GetAccountSummary godoc
// @Summary Get account summary
// @Description Get account summary with statistics (deposits, withdrawals, OD utilization)
// @Tags Bank Accounts
// @Accept json
// @Produce json
// @Param id path string true "Bank Account ID"
// @Success 200 {object} services.BankAccountSummary
// @Router /api/finance/bank-accounts/{id}/summary [get]
func (h *BankAccountHandlers) GetAccountSummary(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	accountID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid account ID"})
		return
	}

	summary, err := h.bankService.GetAccountSummary(c.Request.Context(), accountID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"summary": summary,
	})
}
