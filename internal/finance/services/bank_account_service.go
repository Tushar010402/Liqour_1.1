package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// BankAccountService handles all bank account management operations
type BankAccountService struct {
	db *database.DB
}

// NewBankAccountService creates a new bank account service instance
func NewBankAccountService(db *database.DB) *BankAccountService {
	return &BankAccountService{db: db}
}

// ═══════════════════════════════════════════════════════════════════════════
// Bank Account CRUD Operations
// ═══════════════════════════════════════════════════════════════════════════

// CreateBankAccountRequest represents a request to create a bank account
type CreateBankAccountRequest struct {
	TenantID          uuid.UUID
	BankName          string
	AccountNumber     string
	AccountHolderName string
	IFSCCode          string
	BranchName        string
	BranchAddress     string
	AccountType       string  // current, savings, od, cash_credit
	ODLimit           float64 // Overdraft limit
	ODInterestRate    float64 // Annual interest rate for OD
	IsDefault         bool
	Notes             string
	CreatedBy         uuid.UUID
}

// CreateBankAccount creates a new bank account for a tenant
func (s *BankAccountService) CreateBankAccount(ctx context.Context, req *CreateBankAccountRequest) (*models.TenantBankAccount, error) {
	var account *models.TenantBankAccount

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Check if account number already exists for this tenant
		var existing models.TenantBankAccount
		err := tx.Where("tenant_id = ? AND account_number = ?", req.TenantID, req.AccountNumber).
			First(&existing).Error

		if err == nil {
			return fmt.Errorf("bank account with number %s already exists for this tenant", req.AccountNumber)
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("failed to check existing account: %w", err)
		}

		// If this is set as default, unset other defaults
		if req.IsDefault {
			err = tx.Model(&models.TenantBankAccount{}).
				Where("tenant_id = ?", req.TenantID).
				Update("is_default", false).Error
			if err != nil {
				return fmt.Errorf("failed to unset existing defaults: %w", err)
			}
		}

		// Create new bank account
		account = &models.TenantBankAccount{
			TenantModel: models.TenantModel{
				TenantID: &req.TenantID,
			},
			BankName:          req.BankName,
			AccountNumber:     req.AccountNumber,
			AccountHolderName: req.AccountHolderName,
			IFSCCode:          req.IFSCCode,
			BranchName:        req.BranchName,
			BranchAddress:     req.BranchAddress,
			AccountType:       req.AccountType,
			IsActive:          true,
			IsDefault:         req.IsDefault,
			CurrentBalance:    0,
			ODLimit:           req.ODLimit,
			UsedODAmount:      0,
			// AvailableOD and TotalAvailableBalance are GENERATED columns - database will compute them automatically
			ODInterestRate:    req.ODInterestRate,
			Notes:             req.Notes,
			CreatedBy:         &req.CreatedBy,
		}

		if err := tx.Create(account).Error; err != nil {
			return fmt.Errorf("failed to create bank account: %w", err)
		}

		log.Printf("🏦 Bank account created: %s (%s) for tenant %s, OD Limit: %.2f",
			account.BankName, account.AccountNumber, req.TenantID, req.ODLimit)

		return nil
	})

	if err != nil {
		return nil, err
	}

	return account, nil
}

// UpdateBankAccountRequest represents a request to update a bank account
type UpdateBankAccountRequest struct {
	AccountID       uuid.UUID
	TenantID        uuid.UUID
	BankName        *string
	BranchName      *string
	BranchAddress   *string
	ODLimit         *float64
	ODInterestRate  *float64
	IsActive        *bool
	IsDefault       *bool
	Notes           *string
	UpdatedBy       uuid.UUID
}

// UpdateBankAccount updates an existing bank account
func (s *BankAccountService) UpdateBankAccount(ctx context.Context, req *UpdateBankAccountRequest) (*models.TenantBankAccount, error) {
	var account models.TenantBankAccount

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Fetch existing account
		err := tx.Where("id = ? AND tenant_id = ?", req.AccountID, req.TenantID).
			First(&account).Error
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("bank account not found")
			}
			return fmt.Errorf("failed to fetch account: %w", err)
		}

		// If setting as default, unset other defaults
		if req.IsDefault != nil && *req.IsDefault {
			err = tx.Model(&models.TenantBankAccount{}).
				Where("tenant_id = ? AND id != ?", req.TenantID, req.AccountID).
				Update("is_default", false).Error
			if err != nil {
				return fmt.Errorf("failed to unset existing defaults: %w", err)
			}
		}

		// Update fields
		if req.BankName != nil {
			account.BankName = *req.BankName
		}
		if req.BranchName != nil {
			account.BranchName = *req.BranchName
		}
		if req.BranchAddress != nil {
			account.BranchAddress = *req.BranchAddress
		}
		if req.ODLimit != nil {
			// Update OD limit - AvailableOD and TotalAvailableBalance are GENERATED columns
			account.ODLimit = *req.ODLimit
			// Database will automatically recalculate available_od and total_available_balance
		}
		if req.ODInterestRate != nil {
			account.ODInterestRate = *req.ODInterestRate
		}
		if req.IsActive != nil {
			account.IsActive = *req.IsActive
		}
		if req.IsDefault != nil {
			account.IsDefault = *req.IsDefault
		}
		if req.Notes != nil {
			account.Notes = *req.Notes
		}
		account.UpdatedBy = &req.UpdatedBy

		if err := tx.Save(&account).Error; err != nil {
			return fmt.Errorf("failed to update account: %w", err)
		}

		log.Printf("🏦 Bank account updated: %s (%s)", account.BankName, account.AccountNumber)

		return nil
	})

	if err != nil {
		return nil, err
	}

	return &account, nil
}

// GetBankAccount retrieves a single bank account by ID
func (s *BankAccountService) GetBankAccount(ctx context.Context, accountID, tenantID uuid.UUID) (*models.TenantBankAccount, error) {
	var account models.TenantBankAccount

	err := s.db.DB.WithContext(ctx).
		Preload("Transactions", func(db *gorm.DB) *gorm.DB {
			return db.Order("transaction_date DESC").Limit(10) // Latest 10 transactions
		}).
		// TODO: Fix bank_reconciliations table schema to include deleted_at column
		// Preload("Reconciliations", func(db *gorm.DB) *gorm.DB {
		// 	return db.Order("reconciliation_date DESC").Limit(5) // Latest 5 reconciliations
		// }).
		Where("id = ? AND tenant_id = ?", accountID, tenantID).
		First(&account).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, fmt.Errorf("bank account not found")
		}
		return nil, fmt.Errorf("failed to fetch account: %w", err)
	}

	return &account, nil
}

// GetBankAccounts retrieves all bank accounts for a tenant with filters
func (s *BankAccountService) GetBankAccounts(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]models.TenantBankAccount, error) {
	var accounts []models.TenantBankAccount

	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if accountType, ok := filters["account_type"].(string); ok {
		query = query.Where("account_type = ?", accountType)
	}
	if isActive, ok := filters["is_active"].(bool); ok {
		query = query.Where("is_active = ?", isActive)
	}
	if isDefault, ok := filters["is_default"].(bool); ok {
		query = query.Where("is_default = ?", isDefault)
	}

	err := query.
		Order("is_default DESC, created_at DESC").
		Find(&accounts).Error

	if err != nil {
		return nil, fmt.Errorf("failed to fetch accounts: %w", err)
	}

	return accounts, nil
}

// GetDefaultBankAccount retrieves the default bank account for a tenant
func (s *BankAccountService) GetDefaultBankAccount(ctx context.Context, tenantID uuid.UUID) (*models.TenantBankAccount, error) {
	var account models.TenantBankAccount

	err := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND is_default = ? AND is_active = ?", tenantID, true, true).
		First(&account).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil // No default account set
		}
		return nil, fmt.Errorf("failed to fetch default account: %w", err)
	}

	return &account, nil
}

// DeleteBankAccount soft deletes a bank account
func (s *BankAccountService) DeleteBankAccount(ctx context.Context, accountID, tenantID uuid.UUID) error {
	return s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var account models.TenantBankAccount
		err := tx.Where("id = ? AND tenant_id = ?", accountID, tenantID).
			First(&account).Error

		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("bank account not found")
			}
			return fmt.Errorf("failed to fetch account: %w", err)
		}

		// Check if account has transactions
		var transactionCount int64
		err = tx.Model(&models.TenantBankTransaction{}).
			Where("bank_account_id = ?", accountID).
			Count(&transactionCount).Error
		if err != nil {
			return fmt.Errorf("failed to check transactions: %w", err)
		}

		if transactionCount > 0 {
			// Don't actually delete - just deactivate
			account.IsActive = false
			if err := tx.Save(&account).Error; err != nil {
				return fmt.Errorf("failed to deactivate account: %w", err)
			}
			log.Printf("🏦 Bank account deactivated (has transactions): %s", account.AccountNumber)
		} else {
			// Safe to delete
			if err := tx.Delete(&account).Error; err != nil {
				return fmt.Errorf("failed to delete account: %w", err)
			}
			log.Printf("🏦 Bank account deleted: %s", account.AccountNumber)
		}

		return nil
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Bank Transaction Management
// ═══════════════════════════════════════════════════════════════════════════

// BankTransactionRequest represents a request to record a bank transaction
type BankTransactionRequest struct {
	AccountID       uuid.UUID
	TenantID        uuid.UUID
	TransactionType string  // deposit, withdrawal, od_usage, od_repayment, interest_charge, bank_charges, adjustment
	Amount          float64
	ReferenceType   string     // cash_submission, manual_entry, bank_statement, etc.
	ReferenceID     *uuid.UUID
	BankReferenceNo string
	TransactionDate time.Time
	Description     string
	Notes           string
	CreatedBy       uuid.UUID
}

// RecordBankTransaction records a bank transaction and updates account balance
func (s *BankAccountService) RecordBankTransaction(ctx context.Context, req *BankTransactionRequest) (*models.TenantBankTransaction, error) {
	var transaction *models.TenantBankTransaction

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Fetch account with FOR UPDATE lock to prevent race conditions
		var account models.TenantBankAccount
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ? AND tenant_id = ?", req.AccountID, req.TenantID).
			First(&account).Error
		if err != nil {
			return fmt.Errorf("bank account not found: %w", err)
		}

		// Validate account is active
		if !account.IsActive {
			return fmt.Errorf("bank account is inactive")
		}

		// Record balance snapshots
		balanceBefore := account.CurrentBalance
		odUsedBefore := account.UsedODAmount

		// Update balance based on transaction type
		switch req.TransactionType {
		case "deposit", "od_repayment":
			if req.TransactionType == "deposit" {
				account.CurrentBalance += req.Amount
			} else {
				// OD repayment reduces used OD
				if account.UsedODAmount > 0 {
					repayment := req.Amount
					if repayment > account.UsedODAmount {
						// Excess goes to balance
						excess := repayment - account.UsedODAmount
						account.UsedODAmount = 0
						account.CurrentBalance += excess
					} else {
						account.UsedODAmount -= repayment
					}
				} else {
					// No OD used, add to balance
					account.CurrentBalance += req.Amount
				}
			}

		case "withdrawal", "bank_charges", "interest_charge":
			// Check if withdrawal can be made
			totalAvailable := account.CurrentBalance + (account.ODLimit - account.UsedODAmount)
			if totalAvailable < req.Amount {
				return fmt.Errorf("insufficient funds: available %.2f, requested %.2f", totalAvailable, req.Amount)
			}

			// Deduct from balance first
			if account.CurrentBalance >= req.Amount {
				account.CurrentBalance -= req.Amount
			} else {
				// Use OD
				shortfall := req.Amount - account.CurrentBalance
				account.CurrentBalance = 0
				account.UsedODAmount += shortfall

				if account.UsedODAmount > account.ODLimit {
					return fmt.Errorf("OD limit exceeded")
				}
			}

		case "od_usage":
			// Direct OD usage
			if account.UsedODAmount+req.Amount > account.ODLimit {
				return fmt.Errorf("OD limit exceeded: limit %.2f, used %.2f, requested %.2f",
					account.ODLimit, account.UsedODAmount, req.Amount)
			}
			account.UsedODAmount += req.Amount

		case "adjustment":
			// Manual adjustment - can be positive or negative
			account.CurrentBalance += req.Amount
			if account.CurrentBalance < 0 {
				// Negative balance goes to OD
				account.UsedODAmount += -account.CurrentBalance
				account.CurrentBalance = 0
			}

		default:
			return fmt.Errorf("invalid transaction type: %s", req.TransactionType)
		}

		// AvailableOD and TotalAvailableBalance are GENERATED columns - database will compute them automatically

		// 🔍 CRITICAL DEBUG: Log balance BEFORE Save
		log.Printf("🔍 [DEBUG] BEFORE Update() - In-memory balance: %.2f (from %.2f + %.2f)",
			account.CurrentBalance, balanceBefore, req.Amount)

		// Use explicit Updates() instead of Save() to only update specific fields
		// This prevents GORM from potentially calling hooks or doing unexpected operations
		if err := tx.Model(&account).Updates(map[string]interface{}{
			"current_balance": account.CurrentBalance,
			"used_od_amount":  account.UsedODAmount,
			"updated_at":      time.Now(),
		}).Error; err != nil {
			return fmt.Errorf("failed to update account balance: %w", err)
		}

		// 🔍 CRITICAL DEBUG: Verify balance AFTER Save by re-fetching from database
		var verifyAccount models.TenantBankAccount
		if err := tx.Where("id = ?", req.AccountID).First(&verifyAccount).Error; err == nil {
			log.Printf("🔍 [DEBUG] AFTER Save() - In-memory: %.2f, Database actual: %.2f",
				account.CurrentBalance, verifyAccount.CurrentBalance)
			if verifyAccount.CurrentBalance != account.CurrentBalance {
				log.Printf("⚠️ [CRITICAL BUG DETECTED] Balance mismatch! Expected: %.2f, Got: %.2f, Difference: %.2f",
					account.CurrentBalance, verifyAccount.CurrentBalance, verifyAccount.CurrentBalance - account.CurrentBalance)
			}
		}

		// Create transaction record
		transaction = &models.TenantBankTransaction{
			TenantModel: models.TenantModel{
				TenantID: &req.TenantID,
			},
			BankAccountID:   req.AccountID,
			TransactionType: req.TransactionType,
			Amount:          req.Amount,
			BalanceBefore:   balanceBefore,
			BalanceAfter:    account.CurrentBalance,
			ODUsedBefore:    odUsedBefore,
			ODUsedAfter:     account.UsedODAmount,
			ReferenceType:   req.ReferenceType,
			ReferenceID:     req.ReferenceID,
			BankReferenceNo: req.BankReferenceNo,
			TransactionDate: req.TransactionDate,
			Description:     req.Description,
			Notes:           req.Notes,
			IsReconciled:    false,
			CreatedBy:       &req.CreatedBy,
		}

		if err := tx.Create(transaction).Error; err != nil {
			return fmt.Errorf("failed to create transaction: %w", err)
		}

		log.Printf("💳 Bank transaction recorded: %s %.2f on account %s, New Balance: %.2f, OD Used: %.2f",
			req.TransactionType, req.Amount, account.AccountNumber, account.CurrentBalance, account.UsedODAmount)

		return nil
	})

	if err != nil {
		return nil, err
	}

	return transaction, nil
}

// GetBankTransactions retrieves bank transactions with filters
func (s *BankAccountService) GetBankTransactions(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}, limit, offset int) ([]models.TenantBankTransaction, int64, error) {
	var transactions []models.TenantBankTransaction
	var total int64

	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if accountID, ok := filters["account_id"].(uuid.UUID); ok {
		query = query.Where("bank_account_id = ?", accountID)
	}
	if transactionType, ok := filters["transaction_type"].(string); ok {
		query = query.Where("transaction_type = ?", transactionType)
	}
	if startDate, ok := filters["start_date"].(time.Time); ok {
		query = query.Where("transaction_date >= ?", startDate)
	}
	if endDate, ok := filters["end_date"].(time.Time); ok {
		query = query.Where("transaction_date <= ?", endDate)
	}
	if isReconciled, ok := filters["is_reconciled"].(bool); ok {
		query = query.Where("is_reconciled = ?", isReconciled)
	}

	// Get total count
	if err := query.Model(&models.TenantBankTransaction{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count transactions: %w", err)
	}

	// Get paginated results
	err := query.
		Preload("BankAccount").
		Order("transaction_date DESC").
		Limit(limit).
		Offset(offset).
		Find(&transactions).Error

	if err != nil {
		return nil, 0, fmt.Errorf("failed to fetch transactions: %w", err)
	}

	return transactions, total, nil
}

// ═══════════════════════════════════════════════════════════════════════════
// Bank Reconciliation
// ═══════════════════════════════════════════════════════════════════════════

// CreateReconciliationRequest represents a request to create a reconciliation
type CreateReconciliationRequest struct {
	AccountID            uuid.UUID
	TenantID             uuid.UUID
	ReconciliationDate   time.Time
	StatementStartDate   time.Time
	StatementEndDate     time.Time
	BankStatementBalance float64
	Notes                string
	CreatedBy            uuid.UUID
}

// CreateReconciliation creates a new bank reconciliation record
func (s *BankAccountService) CreateReconciliation(ctx context.Context, req *CreateReconciliationRequest) (*models.BankReconciliation, error) {
	var reconciliation *models.BankReconciliation

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Fetch account
		var account models.TenantBankAccount
		err := tx.Where("id = ? AND tenant_id = ?", req.AccountID, req.TenantID).
			First(&account).Error
		if err != nil {
			return fmt.Errorf("bank account not found: %w", err)
		}

		// Calculate system balance at end date
		systemBalance := account.CurrentBalance

		// Calculate difference
		difference := req.BankStatementBalance - systemBalance

		// Determine status
		status := "completed"
		if difference != 0 {
			status = "discrepancy"
		}

		// Create reconciliation
		reconciliation = &models.BankReconciliation{
			TenantModel: models.TenantModel{
				TenantID: &req.TenantID,
			},
			BankAccountID:        req.AccountID,
			ReconciliationDate:   req.ReconciliationDate,
			StatementStartDate:   req.StatementStartDate,
			StatementEndDate:     req.StatementEndDate,
			SystemBalance:        systemBalance,
			BankStatementBalance: req.BankStatementBalance,
			Difference:           difference,
			Status:               status,
			Notes:                req.Notes,
			CreatedBy:            &req.CreatedBy,
		}

		if status == "completed" {
			now := time.Now()
			reconciliation.CompletedAt = &now
			reconciliation.CompletedBy = &req.CreatedBy
		}

		if err := tx.Create(reconciliation).Error; err != nil {
			return fmt.Errorf("failed to create reconciliation: %w", err)
		}

		log.Printf("📊 Bank reconciliation created: Account %s, Status: %s, Difference: %.2f",
			account.AccountNumber, status, difference)

		return nil
	})

	if err != nil {
		return nil, err
	}

	return reconciliation, nil
}

// GetReconciliations retrieves bank reconciliations with filters
func (s *BankAccountService) GetReconciliations(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]models.BankReconciliation, error) {
	var reconciliations []models.BankReconciliation

	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if accountID, ok := filters["account_id"].(uuid.UUID); ok {
		query = query.Where("bank_account_id = ?", accountID)
	}
	if status, ok := filters["status"].(string); ok {
		query = query.Where("status = ?", status)
	}
	if startDate, ok := filters["start_date"].(time.Time); ok {
		query = query.Where("reconciliation_date >= ?", startDate)
	}

	err := query.
		Preload("BankAccount").
		Order("reconciliation_date DESC").
		Find(&reconciliations).Error

	if err != nil {
		return nil, fmt.Errorf("failed to fetch reconciliations: %w", err)
	}

	return reconciliations, nil
}

// ═══════════════════════════════════════════════════════════════════════════
// Utility Methods
// ═══════════════════════════════════════════════════════════════════════════

// GetAccountSummary returns summary statistics for a bank account
type BankAccountSummary struct {
	Account                *models.TenantBankAccount
	TotalDepositsThisMonth float64
	TotalWithdrawalsThisMonth float64
	TransactionCount       int64
	LastReconciliationDate *time.Time
	ODUtilizationPercent   float64
}

// GetAccountSummary retrieves summary information for a bank account
func (s *BankAccountService) GetAccountSummary(ctx context.Context, accountID, tenantID uuid.UUID) (*BankAccountSummary, error) {
	var summary BankAccountSummary

	// Fetch account
	account, err := s.GetBankAccount(ctx, accountID, tenantID)
	if err != nil {
		return nil, err
	}
	summary.Account = account

	// Calculate this month's transactions
	startOfMonth := time.Now().UTC().Truncate(24 * time.Hour)
	startOfMonth = time.Date(startOfMonth.Year(), startOfMonth.Month(), 1, 0, 0, 0, 0, time.UTC)

	// Total deposits this month
	var totalDeposits float64
	err = s.db.DB.WithContext(ctx).
		Model(&models.TenantBankTransaction{}).
		Where("bank_account_id = ? AND transaction_type IN ? AND transaction_date >= ?",
			accountID, []string{"deposit", "od_repayment"}, startOfMonth).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&totalDeposits).Error
	if err != nil {
		return nil, fmt.Errorf("failed to calculate deposits: %w", err)
	}
	summary.TotalDepositsThisMonth = totalDeposits

	// Total withdrawals this month
	var totalWithdrawals float64
	err = s.db.DB.WithContext(ctx).
		Model(&models.TenantBankTransaction{}).
		Where("bank_account_id = ? AND transaction_type IN ? AND transaction_date >= ?",
			accountID, []string{"withdrawal", "bank_charges", "interest_charge", "od_usage"}, startOfMonth).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&totalWithdrawals).Error
	if err != nil {
		return nil, fmt.Errorf("failed to calculate withdrawals: %w", err)
	}
	summary.TotalWithdrawalsThisMonth = totalWithdrawals

	// Transaction count
	err = s.db.DB.WithContext(ctx).
		Model(&models.TenantBankTransaction{}).
		Where("bank_account_id = ?", accountID).
		Count(&summary.TransactionCount).Error
	if err != nil {
		return nil, fmt.Errorf("failed to count transactions: %w", err)
	}

	// Last reconciliation date
	var lastReconciliation models.BankReconciliation
	err = s.db.DB.WithContext(ctx).
		Where("bank_account_id = ?", accountID).
		Order("reconciliation_date DESC").
		First(&lastReconciliation).Error
	if err == nil {
		summary.LastReconciliationDate = &lastReconciliation.ReconciliationDate
	}

	// OD utilization percent
	if account.ODLimit > 0 {
		summary.ODUtilizationPercent = (account.UsedODAmount / account.ODLimit) * 100
	}

	return &summary, nil
}

// LinkCashSubmissionToBank links a cash submission to a bank account and records deposit
func (s *BankAccountService) LinkCashSubmissionToBank(ctx context.Context, submissionID, bankAccountID, tenantID, userID uuid.UUID) error {
	return s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Fetch cash submission
		var submission models.CashSubmission
		err := tx.Where("id = ? AND tenant_id = ?", submissionID, tenantID).
			First(&submission).Error
		if err != nil {
			return fmt.Errorf("cash submission not found: %w", err)
		}

		// Update submission with bank account
		submission.BankAccountID = &bankAccountID
		if err := tx.Save(&submission).Error; err != nil {
			return fmt.Errorf("failed to link submission to bank: %w", err)
		}

		// Record bank deposit transaction
		transactionReq := &BankTransactionRequest{
			AccountID:       bankAccountID,
			TenantID:        tenantID,
			TransactionType: "deposit",
			Amount:          submission.TotalAmount,
			ReferenceType:   "cash_submission",
			ReferenceID:     &submissionID,
			BankReferenceNo: submission.BankSlipNumber,
			TransactionDate: submission.DepositDate,
			Description:     fmt.Sprintf("Cash deposit from submission %s", submissionID),
			Notes:           submission.Notes,
			CreatedBy:       userID,
		}

		_, err = s.RecordBankTransaction(ctx, transactionReq)
		if err != nil {
			return fmt.Errorf("failed to record deposit transaction: %w", err)
		}

		log.Printf("🔗 Cash submission %s linked to bank account and deposit recorded: %.2f",
			submissionID, submission.TotalAmount)

		return nil
	})
}
