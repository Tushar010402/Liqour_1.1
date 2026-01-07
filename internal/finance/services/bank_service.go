package services

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

type BankService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewBankService(db *database.DB, cache *cache.Cache) *BankService {
	return &BankService{
		db:    db,
		cache: cache,
	}
}

// ==================== BANK ACCOUNTS ====================

type BankAccountResponse struct {
	ID                uuid.UUID `json:"id"`
	TenantID          uuid.UUID `json:"tenant_id"`
	BankName          string    `json:"bank_name"`
	AccountNumber     string    `json:"account_number"`
	IFSCCode          string    `json:"ifsc_code"`
	AccountHolderName string    `json:"account_holder_name"`
	AccountType       string    `json:"account_type"`
	BranchName        string    `json:"branch_name"`
	OpeningBalance    float64   `json:"opening_balance"`
	CurrentBalance    float64   `json:"current_balance"`
	ODLimit           float64   `json:"od_limit"`
	ODInterestRate    float64   `json:"od_interest_rate"`
	Notes             string    `json:"notes"`
	IsActive          bool      `json:"is_active"`
	IsPrimary         bool      `json:"is_primary"`
	IsDefault         bool      `json:"is_default"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

func (s *BankService) ListBankAccounts(ctx context.Context, tenantID uuid.UUID) ([]BankAccountResponse, error) {
	var accounts []models.BankAccount
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
		Order("is_primary DESC, bank_name ASC").
		Find(&accounts).Error

	if err != nil {
		return nil, fmt.Errorf("failed to list bank accounts: %w", err)
	}

	responses := make([]BankAccountResponse, len(accounts))
	for i, acc := range accounts {
		responses[i] = s.toBankAccountResponse(&acc)
	}
	return responses, nil
}

func (s *BankService) GetBankAccountByID(ctx context.Context, tenantID uuid.UUID, id uuid.UUID) (*BankAccountResponse, error) {
	var account models.BankAccount
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&account).Error

	if err != nil {
		return nil, fmt.Errorf("bank account not found: %w", err)
	}

	resp := s.toBankAccountResponse(&account)
	return &resp, nil
}

type CreateBankAccountRequest struct {
	BankName          string  `json:"bank_name" binding:"required"`
	AccountNumber     string  `json:"account_number" binding:"required"`
	IFSCCode          string  `json:"ifsc_code"`
	AccountHolderName string  `json:"account_holder_name" binding:"required"`
	AccountType       string  `json:"account_type"`
	BranchName        string  `json:"branch_name"`
	OpeningBalance    float64 `json:"opening_balance"`
	ODLimit           float64 `json:"od_limit"`
	ODInterestRate    float64 `json:"od_interest_rate"`
	Notes             string  `json:"notes"`
	IsPrimary         bool    `json:"is_primary"`
	IsDefault         bool    `json:"is_default"`
}

func (s *BankService) CreateBankAccount(ctx context.Context, tenantID uuid.UUID, req *CreateBankAccountRequest) (*BankAccountResponse, error) {
	account := &models.BankAccount{
		TenantModel: models.TenantModel{
			TenantID: &tenantID,
		},
		BankName:          req.BankName,
		AccountNumber:     req.AccountNumber,
		IFSCCode:          req.IFSCCode,
		AccountHolderName: req.AccountHolderName,
		AccountType:       req.AccountType,
		BranchName:        req.BranchName,
		OpeningBalance:    req.OpeningBalance,
		CurrentBalance:    req.OpeningBalance, // Start with opening balance
		ODLimit:           req.ODLimit,
		ODInterestRate:    req.ODInterestRate,
		Notes:             req.Notes,
		IsPrimary:         req.IsPrimary,
		IsDefault:         req.IsDefault,
		IsActive:          true,
	}

	if account.AccountType == "" {
		account.AccountType = "savings"
	}

	// If this is set as primary/default, unset other primary accounts
	if account.IsPrimary {
		s.db.WithContext(ctx).Model(&models.BankAccount{}).
			Where("tenant_id = ? AND is_primary = true", tenantID).
			Update("is_primary", false)
	}
	if account.IsDefault {
		s.db.WithContext(ctx).Model(&models.BankAccount{}).
			Where("tenant_id = ? AND is_default = true", tenantID).
			Update("is_default", false)
	}

	if err := s.db.WithContext(ctx).Create(account).Error; err != nil {
		return nil, fmt.Errorf("failed to create bank account: %w", err)
	}

	resp := s.toBankAccountResponse(account)
	return &resp, nil
}

func (s *BankService) toBankAccountResponse(acc *models.BankAccount) BankAccountResponse {
	return BankAccountResponse{
		ID:                acc.ID,
		TenantID:          *acc.TenantID,
		BankName:          acc.BankName,
		AccountNumber:     acc.AccountNumber,
		IFSCCode:          acc.IFSCCode,
		AccountHolderName: acc.AccountHolderName,
		AccountType:       acc.AccountType,
		BranchName:        acc.BranchName,
		OpeningBalance:    acc.OpeningBalance,
		CurrentBalance:    acc.CurrentBalance,
		ODLimit:           acc.ODLimit,
		ODInterestRate:    acc.ODInterestRate,
		Notes:             acc.Notes,
		IsActive:          acc.IsActive,
		IsPrimary:         acc.IsPrimary,
		IsDefault:         acc.IsDefault,
		CreatedAt:         acc.CreatedAt,
		UpdatedAt:         acc.UpdatedAt,
	}
}

// ==================== CASH DEPOSITS ====================

type CashDepositResponse struct {
	ID              uuid.UUID  `json:"id"`
	BankAccountID   uuid.UUID  `json:"bank_account_id"`
	BankAccountName string     `json:"bank_account_name"`
	ShopID          *uuid.UUID `json:"shop_id,omitempty"`
	ShopName        string     `json:"shop_name,omitempty"`
	Amount          float64    `json:"amount"`
	DepositDate     time.Time  `json:"deposit_date"`
	SlipNumber      string     `json:"slip_number"`
	Notes           string     `json:"notes"`
	ReceiptURL      string     `json:"receipt_url,omitempty"`
	ReceiptPhotoURL string     `json:"receipt_photo_url,omitempty"` // Flutter compatibility - same as receipt_url
	Status          string     `json:"status"`
	RejectionReason string     `json:"rejection_reason,omitempty"`
	ApprovedAt      *time.Time `json:"approved_at,omitempty"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id,omitempty"`
	ApprovedByName  string     `json:"approved_by_name,omitempty"`
	CreatedByID     uuid.UUID  `json:"created_by_id"`
	CreatedByName   string     `json:"created_by_name"`
	CreatedAt       time.Time  `json:"created_at"`
	// Balance warning (included when approving a deposit where user has insufficient balance)
	BalanceWarning string `json:"balance_warning,omitempty"`
}

type CreateCashDepositRequest struct {
	BankAccountID   uuid.UUID  `json:"bank_account_id" binding:"required"`
	ShopID          *uuid.UUID `json:"shop_id"`
	Amount          float64    `json:"amount" binding:"required,gt=0"`
	DepositDate     string     `json:"deposit_date" binding:"required"`
	SlipNumber      string     `json:"slip_number"`
	Notes           string     `json:"notes"`
	ReceiptURL      string     `json:"receipt_url"`
	ReceiptPhotoURL string     `json:"receipt_photo_url"` // Flutter app sends this field name
}

func (s *BankService) CreateCashDeposit(ctx context.Context, tenantID uuid.UUID, userID uuid.UUID, req *CreateCashDepositRequest) (*CashDepositResponse, error) {
	depositDate, err := time.Parse("2006-01-02", req.DepositDate)
	if err != nil {
		return nil, fmt.Errorf("invalid deposit date format, use YYYY-MM-DD: %w", err)
	}

	// Validate bank account exists and belongs to tenant
	var bankAccount models.BankAccount
	if err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", req.BankAccountID, tenantID).
		First(&bankAccount).Error; err != nil {
		return nil, fmt.Errorf("bank account not found or not accessible: %w", err)
	}

	// Use receipt_photo_url if receipt_url is not provided (Flutter compatibility)
	receiptURL := req.ReceiptURL
	if receiptURL == "" && req.ReceiptPhotoURL != "" {
		receiptURL = req.ReceiptPhotoURL
	}

	deposit := &models.CashDeposit{
		TenantModel: models.TenantModel{
			TenantID: &tenantID,
		},
		BankAccountID: req.BankAccountID,
		ShopID:        req.ShopID, // Now a pointer, can be nil
		Amount:        req.Amount,
		DepositDate:   depositDate,
		SlipNumber:    req.SlipNumber,
		Notes:         req.Notes,
		ReceiptURL:    receiptURL,
		Status:        "pending",
		CreatedByID:   userID,
	}

	if err := s.db.WithContext(ctx).Create(deposit).Error; err != nil {
		return nil, fmt.Errorf("failed to create cash deposit: %w", err)
	}

	return s.GetCashDepositByID(ctx, tenantID, deposit.ID)
}

func (s *BankService) GetCashDepositByID(ctx context.Context, tenantID uuid.UUID, id uuid.UUID) (*CashDepositResponse, error) {
	var deposit models.CashDeposit
	err := s.db.WithContext(ctx).
		Preload("BankAccount").
		Preload("Shop").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&deposit).Error

	if err != nil {
		return nil, fmt.Errorf("cash deposit not found: %w", err)
	}

	return s.toCashDepositResponse(&deposit), nil
}

func (s *BankService) ListCashDeposits(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]CashDepositResponse, int64, error) {
	var deposits []models.CashDeposit
	var total int64

	query := s.db.WithContext(ctx).
		Preload("BankAccount").
		Preload("Shop").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	// Apply filters
	if status, ok := filters["status"].(string); ok && status != "" {
		query = query.Where("status = ?", status)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if bankAccountID, ok := filters["bank_account_id"].(uuid.UUID); ok {
		query = query.Where("bank_account_id = ?", bankAccountID)
	}
	// Filter by creator (for "my deposits" view)
	if createdByID, ok := filters["created_by_id"].(uuid.UUID); ok {
		query = query.Where("created_by_id = ?", createdByID)
	}
	// Date range filters
	if fromDate, ok := filters["from_date"].(string); ok && fromDate != "" {
		query = query.Where("deposit_date >= ?", fromDate)
	}
	if toDate, ok := filters["to_date"].(string); ok && toDate != "" {
		query = query.Where("deposit_date <= ?", toDate)
	}

	// Count total
	query.Model(&models.CashDeposit{}).Count(&total)

	// Pagination
	limit := 50
	offset := 0
	if l, ok := filters["limit"].(int); ok {
		limit = l
	}
	if o, ok := filters["offset"].(int); ok {
		offset = o
	}

	if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&deposits).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to list cash deposits: %w", err)
	}

	responses := make([]CashDepositResponse, len(deposits))
	for i, d := range deposits {
		responses[i] = *s.toCashDepositResponse(&d)
	}

	return responses, total, nil
}

// GetPendingDepositCount returns the count of pending cash deposits for dashboard badges
func (s *BankService) GetPendingDepositCount(ctx context.Context, tenantID uuid.UUID) (int64, error) {
	var count int64
	err := s.db.WithContext(ctx).
		Model(&models.CashDeposit{}).
		Where("tenant_id = ? AND status = 'pending' AND deleted_at IS NULL", tenantID).
		Count(&count).Error
	return count, err
}

// updateCashHolding updates a user's cash balance and creates an audit trail transaction
// This is used when approving cash deposits to deduct from user's cash holdings
func (s *BankService) updateCashHolding(tx *gorm.DB, tenantID, userID uuid.UUID, amount float64, refID uuid.UUID, transactionType, relatedType, description string) error {
	var holding models.CashHolding

	err := tx.Where("user_id = ? AND tenant_id = ?", userID, tenantID).First(&holding).Error
	if err == gorm.ErrRecordNotFound {
		// Get user role for the new holding record
		var user models.User
		if err := tx.Where("id = ?", userID).First(&user).Error; err != nil {
			return fmt.Errorf("failed to get user: %w", err)
		}
		// Create new holding record
		holding = models.CashHolding{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			UserID:         userID,
			Role:           user.Role,
			CurrentBalance: 0,
		}
	} else if err != nil {
		return fmt.Errorf("failed to get cash holding: %w", err)
	}

	previousBalance := holding.CurrentBalance
	newBalance := previousBalance + amount
	holding.CurrentBalance = newBalance
	holding.LastUpdatedAt = time.Now()

	if err := tx.Save(&holding).Error; err != nil {
		return fmt.Errorf("failed to update cash holding: %w", err)
	}

	// Create audit transaction
	absAmount := amount
	if amount < 0 {
		absAmount = -amount
	}

	transaction := models.CashTransaction{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		UserID:          userID,
		TransactionType: transactionType,
		Amount:          absAmount,
		BalanceBefore:   previousBalance,
		BalanceAfter:    newBalance,
		RelatedType:     relatedType,
		RelatedID:       &refID,
		Notes:           description,
		TransactionDate: time.Now(),
	}

	return tx.Create(&transaction).Error
}

func (s *BankService) ApproveCashDeposit(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID) (*CashDepositResponse, error) {
	var balanceWarning string

	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var deposit models.CashDeposit

		// 1. Lock the deposit row with FOR UPDATE to prevent race conditions
		err := tx.Set("gorm:query_option", "FOR UPDATE").
			Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
			First(&deposit).Error

		if err != nil {
			if err == gorm.ErrRecordNotFound {
				return fmt.Errorf("cash deposit not found")
			}
			return fmt.Errorf("failed to get cash deposit: %w", err)
		}

		// 2. Validate status is pending
		if deposit.Status != "pending" {
			return fmt.Errorf("cannot approve: deposit is not in pending status (current: %s)", deposit.Status)
		}

		// 3. Lock user's cash_holdings to prevent concurrent modifications
		var holding models.CashHolding
		err = tx.Set("gorm:query_option", "FOR UPDATE").
			Where("user_id = ? AND tenant_id = ?", deposit.CreatedByID, tenantID).
			First(&holding).Error

		// 4. Check if user has sufficient balance (warn but allow if insufficient)
		if err == nil && holding.CurrentBalance < deposit.Amount {
			balanceWarning = fmt.Sprintf("Warning: User's cash balance (%.2f) is less than deposit amount (%.2f). Proceeding with approval may result in negative balance.", holding.CurrentBalance, deposit.Amount)
		}
		// Note: We continue even if balance is insufficient (per business rule)

		// 5. Get bank account name for audit description
		var bankAccount models.BankAccount
		if err := tx.Where("id = ?", deposit.BankAccountID).First(&bankAccount).Error; err != nil {
			return fmt.Errorf("failed to get bank account: %w", err)
		}

		// 6. ATOMIC: Deduct from user's cash_holdings (creates audit trail)
		description := fmt.Sprintf("Bank deposit to %s - Slip: %s", bankAccount.BankName, deposit.SlipNumber)
		if err := s.updateCashHolding(tx, tenantID, deposit.CreatedByID, -deposit.Amount, deposit.ID, "deposit", "cash_deposit", description); err != nil {
			return fmt.Errorf("failed to deduct from user's cash holdings: %w", err)
		}

		// 7. ATOMIC: Credit to bank_accounts.current_balance
		if err := tx.Model(&models.BankAccount{}).
			Where("id = ?", deposit.BankAccountID).
			UpdateColumn("current_balance", gorm.Expr("current_balance + ?", deposit.Amount)).Error; err != nil {
			return fmt.Errorf("failed to update bank balance: %w", err)
		}

		// 8. Update deposit status to approved
		now := time.Now()
		if err := tx.Model(&deposit).Updates(map[string]interface{}{
			"status":         "approved",
			"approved_at":    &now,
			"approved_by_id": &approverID,
		}).Error; err != nil {
			return fmt.Errorf("failed to approve cash deposit: %w", err)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Fetch the updated deposit with relationships
	resp, err := s.GetCashDepositByID(ctx, tenantID, id)
	if err != nil {
		return nil, err
	}

	// Include balance warning if applicable
	if balanceWarning != "" {
		resp.BalanceWarning = balanceWarning
	}

	return resp, nil
}

func (s *BankService) RejectCashDeposit(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID, reason string) (*CashDepositResponse, error) {
	var deposit models.CashDeposit
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&deposit).Error

	if err != nil {
		return nil, fmt.Errorf("cash deposit not found: %w", err)
	}

	if deposit.Status != "pending" {
		return nil, fmt.Errorf("cannot reject: deposit is not in pending status (current: %s)", deposit.Status)
	}

	now := time.Now()
	if err := s.db.WithContext(ctx).Model(&deposit).Updates(map[string]interface{}{
		"status":           "rejected",
		"rejection_reason": reason,
		"approved_at":      &now,
		"approved_by_id":   &approverID,
	}).Error; err != nil {
		return nil, fmt.Errorf("failed to reject cash deposit: %w", err)
	}

	return s.GetCashDepositByID(ctx, tenantID, id)
}

func (s *BankService) toCashDepositResponse(d *models.CashDeposit) *CashDepositResponse {
	// Convert relative receipt URL to full URL if needed
	receiptURL := d.ReceiptURL
	if receiptURL != "" && !strings.HasPrefix(receiptURL, "http") {
		// It's a relative path, prepend the production domain
		receiptURL = "https://new.v2.floelife.in" + receiptURL
	}

	resp := &CashDepositResponse{
		ID:              d.ID,
		BankAccountID:   d.BankAccountID,
		ShopID:          d.ShopID,
		Amount:          d.Amount,
		DepositDate:     d.DepositDate,
		SlipNumber:      d.SlipNumber,
		Notes:           d.Notes,
		ReceiptURL:      receiptURL,
		ReceiptPhotoURL: receiptURL, // Flutter compatibility - same value as receipt_url
		Status:          d.Status,
		RejectionReason: d.RejectionReason,
		ApprovedAt:      d.ApprovedAt,
		ApprovedByID:    d.ApprovedByID,
		CreatedByID:     d.CreatedByID,
		CreatedAt:       d.CreatedAt,
	}

	if d.BankAccount != nil {
		resp.BankAccountName = d.BankAccount.BankName + " - " + d.BankAccount.AccountNumber
	}
	if d.Shop != nil {
		resp.ShopName = d.Shop.Name
	}
	if d.ApprovedBy != nil {
		resp.ApprovedByName = d.ApprovedBy.FirstName + " " + d.ApprovedBy.LastName
	}
	if d.CreatedBy != nil {
		resp.CreatedByName = d.CreatedBy.FirstName + " " + d.CreatedBy.LastName
	}

	return resp
}

// ==================== BANK RECONCILIATION ====================

type ReconciliationResponse struct {
	ID                      uuid.UUID                  `json:"id"`
	BankAccountID           uuid.UUID                  `json:"bank_account_id"`
	BankAccountName         string                     `json:"bank_account_name"`
	PeriodStart             time.Time                  `json:"period_start"`
	PeriodEnd               time.Time                  `json:"period_end"`
	StatementOpeningBalance float64                    `json:"statement_opening_balance"`
	StatementClosingBalance float64                    `json:"statement_closing_balance"`
	BookOpeningBalance      float64                    `json:"book_opening_balance"`
	BookClosingBalance      float64                    `json:"book_closing_balance"`
	Difference              float64                    `json:"difference"`
	IsBalanced              bool                       `json:"is_balanced"`
	Status                  string                     `json:"status"`
	ReconciledByID          *uuid.UUID                 `json:"reconciled_by_id,omitempty"`
	ReconciledByName        string                     `json:"reconciled_by_name,omitempty"`
	ReconciledAt            *time.Time                 `json:"reconciled_at,omitempty"`
	ApprovedByID            *uuid.UUID                 `json:"approved_by_id,omitempty"`
	ApprovedByName          string                     `json:"approved_by_name,omitempty"`
	ApprovedAt              *time.Time                 `json:"approved_at,omitempty"`
	Notes                   string                     `json:"notes"`
	CreatedByID             uuid.UUID                  `json:"created_by_id"`
	CreatedByName           string                     `json:"created_by_name"`
	CreatedAt               time.Time                  `json:"created_at"`
	Entries                 []BankStatementEntryResponse `json:"entries,omitempty"`
}

type BankStatementEntryResponse struct {
	ID                   uuid.UUID  `json:"id"`
	TransactionDate      time.Time  `json:"transaction_date"`
	ValueDate            time.Time  `json:"value_date"`
	Description          string     `json:"description"`
	ReferenceNumber      string     `json:"reference_number"`
	TransactionType      string     `json:"transaction_type"`
	Amount               float64    `json:"amount"`
	RunningBalance       float64    `json:"running_balance"`
	IsMatched            bool       `json:"is_matched"`
	MatchedTransactionID *uuid.UUID `json:"matched_transaction_id,omitempty"`
	MatchedDepositID     *uuid.UUID `json:"matched_deposit_id,omitempty"`
}

type CreateReconciliationRequest struct {
	BankAccountID           uuid.UUID `json:"bank_account_id" binding:"required"`
	PeriodStart             string    `json:"period_start" binding:"required"`
	PeriodEnd               string    `json:"period_end" binding:"required"`
	StatementOpeningBalance float64   `json:"statement_opening_balance"`
	StatementClosingBalance float64   `json:"statement_closing_balance"`
	Notes                   string    `json:"notes"`
}

func (s *BankService) CreateReconciliation(ctx context.Context, tenantID uuid.UUID, userID uuid.UUID, req *CreateReconciliationRequest) (*ReconciliationResponse, error) {
	periodStart, err := time.Parse("2006-01-02", req.PeriodStart)
	if err != nil {
		return nil, fmt.Errorf("invalid period_start format, use YYYY-MM-DD: %w", err)
	}
	periodEnd, err := time.Parse("2006-01-02", req.PeriodEnd)
	if err != nil {
		return nil, fmt.Errorf("invalid period_end format, use YYYY-MM-DD: %w", err)
	}

	// Get current bank account balance as book balance
	var bankAccount models.BankAccount
	if err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ?", req.BankAccountID, tenantID).
		First(&bankAccount).Error; err != nil {
		return nil, fmt.Errorf("bank account not found: %w", err)
	}

	reconciliation := &models.BankReconciliation{
		TenantModel: models.TenantModel{
			TenantID: &tenantID,
		},
		BankAccountID:           req.BankAccountID,
		PeriodStart:             periodStart,
		PeriodEnd:               periodEnd,
		StatementOpeningBalance: req.StatementOpeningBalance,
		StatementClosingBalance: req.StatementClosingBalance,
		BookOpeningBalance:      bankAccount.CurrentBalance,
		BookClosingBalance:      bankAccount.CurrentBalance,
		Status:                  "draft",
		Notes:                   req.Notes,
		CreatedByID:             userID,
	}

	// Calculate initial difference
	reconciliation.Difference = reconciliation.StatementClosingBalance - reconciliation.BookClosingBalance
	reconciliation.IsBalanced = reconciliation.Difference == 0

	if err := s.db.WithContext(ctx).Create(reconciliation).Error; err != nil {
		return nil, fmt.Errorf("failed to create reconciliation: %w", err)
	}

	return s.GetReconciliationByID(ctx, tenantID, reconciliation.ID)
}

func (s *BankService) GetReconciliationByID(ctx context.Context, tenantID uuid.UUID, id uuid.UUID) (*ReconciliationResponse, error) {
	var reconciliation models.BankReconciliation
	err := s.db.WithContext(ctx).
		Preload("BankAccount").
		Preload("ReconciledBy").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Preload("Entries").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&reconciliation).Error

	if err != nil {
		return nil, fmt.Errorf("reconciliation not found: %w", err)
	}

	return s.toReconciliationResponse(&reconciliation), nil
}

func (s *BankService) ListReconciliations(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]ReconciliationResponse, int64, error) {
	var reconciliations []models.BankReconciliation
	var total int64

	query := s.db.WithContext(ctx).
		Preload("BankAccount").
		Preload("ReconciledBy").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	// Apply filters
	if status, ok := filters["status"].(string); ok && status != "" {
		query = query.Where("status = ?", status)
	}
	if bankAccountID, ok := filters["bank_account_id"].(uuid.UUID); ok {
		query = query.Where("bank_account_id = ?", bankAccountID)
	}

	// Count total
	query.Model(&models.BankReconciliation{}).Count(&total)

	// Pagination
	limit := 50
	offset := 0
	if l, ok := filters["limit"].(int); ok {
		limit = l
	}
	if o, ok := filters["offset"].(int); ok {
		offset = o
	}

	if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&reconciliations).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to list reconciliations: %w", err)
	}

	responses := make([]ReconciliationResponse, len(reconciliations))
	for i, r := range reconciliations {
		responses[i] = *s.toReconciliationResponse(&r)
	}

	return responses, total, nil
}

func (s *BankService) ApproveReconciliation(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID) (*ReconciliationResponse, error) {
	var reconciliation models.BankReconciliation
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&reconciliation).Error

	if err != nil {
		return nil, fmt.Errorf("reconciliation not found: %w", err)
	}

	if reconciliation.Status != "completed" {
		return nil, fmt.Errorf("cannot approve: reconciliation must be in completed status (current: %s)", reconciliation.Status)
	}

	now := time.Now()
	reconciliation.Status = "approved"
	reconciliation.ApprovedAt = &now
	reconciliation.ApprovedByID = &approverID

	if err := s.db.WithContext(ctx).Save(&reconciliation).Error; err != nil {
		return nil, fmt.Errorf("failed to approve reconciliation: %w", err)
	}

	return s.GetReconciliationByID(ctx, tenantID, id)
}

func (s *BankService) CompleteReconciliation(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, userID uuid.UUID) (*ReconciliationResponse, error) {
	var reconciliation models.BankReconciliation
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&reconciliation).Error

	if err != nil {
		return nil, fmt.Errorf("reconciliation not found: %w", err)
	}

	if reconciliation.Status != "draft" && reconciliation.Status != "in_progress" {
		return nil, fmt.Errorf("cannot complete: reconciliation must be in draft or in_progress status (current: %s)", reconciliation.Status)
	}

	now := time.Now()
	reconciliation.Status = "completed"
	reconciliation.ReconciledAt = &now
	reconciliation.ReconciledByID = &userID

	if err := s.db.WithContext(ctx).Save(&reconciliation).Error; err != nil {
		return nil, fmt.Errorf("failed to complete reconciliation: %w", err)
	}

	return s.GetReconciliationByID(ctx, tenantID, id)
}

func (s *BankService) toReconciliationResponse(r *models.BankReconciliation) *ReconciliationResponse {
	resp := &ReconciliationResponse{
		ID:                      r.ID,
		BankAccountID:           r.BankAccountID,
		PeriodStart:             r.PeriodStart,
		PeriodEnd:               r.PeriodEnd,
		StatementOpeningBalance: r.StatementOpeningBalance,
		StatementClosingBalance: r.StatementClosingBalance,
		BookOpeningBalance:      r.BookOpeningBalance,
		BookClosingBalance:      r.BookClosingBalance,
		Difference:              r.Difference,
		IsBalanced:              r.IsBalanced,
		Status:                  r.Status,
		ReconciledByID:          r.ReconciledByID,
		ReconciledAt:            r.ReconciledAt,
		ApprovedByID:            r.ApprovedByID,
		ApprovedAt:              r.ApprovedAt,
		Notes:                   r.Notes,
		CreatedByID:             r.CreatedByID,
		CreatedAt:               r.CreatedAt,
	}

	if r.BankAccount != nil {
		resp.BankAccountName = r.BankAccount.BankName + " - " + r.BankAccount.AccountNumber
	}
	if r.ReconciledBy != nil {
		resp.ReconciledByName = r.ReconciledBy.FirstName + " " + r.ReconciledBy.LastName
	}
	if r.ApprovedBy != nil {
		resp.ApprovedByName = r.ApprovedBy.FirstName + " " + r.ApprovedBy.LastName
	}
	if r.CreatedBy != nil {
		resp.CreatedByName = r.CreatedBy.FirstName + " " + r.CreatedBy.LastName
	}

	// Convert entries
	if len(r.Entries) > 0 {
		resp.Entries = make([]BankStatementEntryResponse, len(r.Entries))
		for i, e := range r.Entries {
			resp.Entries[i] = BankStatementEntryResponse{
				ID:                   e.ID,
				TransactionDate:      e.TransactionDate,
				ValueDate:            e.ValueDate,
				Description:          e.Description,
				ReferenceNumber:      e.ReferenceNumber,
				TransactionType:      e.TransactionType,
				Amount:               e.Amount,
				RunningBalance:       e.RunningBalance,
				IsMatched:            e.IsMatched,
				MatchedTransactionID: e.MatchedTransactionID,
				MatchedDepositID:     e.MatchedDepositID,
			}
		}
	}

	return resp
}
