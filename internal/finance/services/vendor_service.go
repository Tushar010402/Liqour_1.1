package services

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

type VendorService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewVendorService(db *database.DB, cache *cache.Cache) *VendorService {
	return &VendorService{
		db:    db,
		cache: cache,
	}
}

type VendorRequest struct {
	Name          string  `json:"name" binding:"required,max=255"`
	ContactPerson string  `json:"contact_person"`
	Email         string  `json:"email"`
	Phone         string  `json:"phone"`
	Address       string  `json:"address"`
	City          string  `json:"city"`
	State         string  `json:"state"`
	Country       string  `json:"country"`
	PostalCode    string  `json:"postal_code"`
	TaxID         string  `json:"tax_id"`
	CreditLimit   float64 `json:"credit_limit"`
	PaymentTerms  string  `json:"payment_terms"`
	IsActive      *bool   `json:"is_active"`
}

type VendorResponse struct {
	ID                 uuid.UUID                   `json:"id"`
	Name               string                      `json:"name"`
	ContactPerson      string                      `json:"contact_person"`
	Email              string                      `json:"email"`
	Phone              string                      `json:"phone"`
	Address            string                      `json:"address"`
	City               string                      `json:"city"`
	State              string                      `json:"state"`
	Country            string                      `json:"country"`
	PostalCode         string                      `json:"postal_code"`
	TaxID              string                      `json:"tax_id"`
	CreditLimit        float64                     `json:"credit_limit"`
	PaymentTerms       string                      `json:"payment_terms"`
	IsActive           bool                        `json:"is_active"`
	TotalPurchases     float64                     `json:"total_purchases"`
	OutstandingBalance float64                     `json:"outstanding_balance"`
	BankAccounts       []VendorBankAccountResponse `json:"bank_accounts"`
	CreatedAt          time.Time                   `json:"created_at"`
	UpdatedAt          time.Time                   `json:"updated_at"`
}

type VendorBankAccountRequest struct {
	BankName      string `json:"bank_name" binding:"required,max=255"`
	AccountNumber string `json:"account_number" binding:"required,max=50"`
	AccountHolder string `json:"account_holder" binding:"required,max=255"`
	BranchCode    string `json:"branch_code"`
	SwiftCode     string `json:"swift_code"`
	IsDefault     *bool  `json:"is_default"`
}

type VendorBankAccountResponse struct {
	ID            uuid.UUID `json:"id"`
	BankName      string    `json:"bank_name"`
	AccountNumber string    `json:"account_number"`
	AccountHolder string    `json:"account_holder"`
	BranchCode    string    `json:"branch_code"`
	SwiftCode     string    `json:"swift_code"`
	IsDefault     bool      `json:"is_default"`
	CreatedAt     time.Time `json:"created_at"`
}

type VendorTransactionRequest struct {
	VendorID        uuid.UUID `json:"vendor_id" binding:"required"`
	TransactionType string    `json:"transaction_type" binding:"required"`
	Amount          float64   `json:"amount" binding:"required"`
	Description     string    `json:"description" binding:"required"`
	ReferenceNo     string    `json:"reference_no"`
	PaymentMethod   string    `json:"payment_method"`
}

type VendorTransactionResponse struct {
	ID              uuid.UUID `json:"id"`
	VendorID        uuid.UUID `json:"vendor_id"`
	VendorName      string    `json:"vendor_name"`
	TransactionType string    `json:"transaction_type"`
	Amount          float64   `json:"amount"`
	Description     string    `json:"description"`
	ReferenceNo     string    `json:"reference_no"`
	PaymentMethod   string    `json:"payment_method"`
	CreatedBy       uuid.UUID `json:"created_by"`
	CreatedAt       time.Time `json:"created_at"`
}

func (s *VendorService) CreateVendor(ctx context.Context, req VendorRequest, tenantID, userID uuid.UUID) (*VendorResponse, error) {
	// Check if vendor name already exists
	var existingVendor models.Vendor
	err := s.db.DB.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existingVendor).Error
	if err == nil {
		return nil, fmt.Errorf("vendor with this name already exists")
	} else if err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to check existing vendor: %w", err)
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	vendor := models.Vendor{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		Name:          req.Name,
		ContactPerson: req.ContactPerson,
		Email:         req.Email,
		Phone:         req.Phone,
		Address:       req.Address,
		City:          req.City,
		State:         req.State,
		Country:       req.Country,
		PostalCode:    req.PostalCode,
		TaxID:         req.TaxID,
		CreditLimit:   req.CreditLimit,
		PaymentTerms:  req.PaymentTerms,
		IsActive:      isActive,
		CreatedBy:     userID,
	}

	if err := s.db.DB.Create(&vendor).Error; err != nil {
		return nil, fmt.Errorf("failed to create vendor: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("vendors:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.buildVendorResponse(vendor, 0, 0, []models.VendorBankAccount{}), nil
}

func (s *VendorService) GetVendors(ctx context.Context, tenantID uuid.UUID, includeInactive bool) ([]VendorResponse, error) {
	// Handle cache key for saas_admin (system-wide access)
	tenantKeyPart := "all"
	if tenantID != uuid.Nil {
		tenantKeyPart = tenantID.String()
	}
	cacheKey := fmt.Sprintf("vendors:tenant:%s:inactive:%t", tenantKeyPart, includeInactive)

	// Try to get from cache
	var cachedVendors []VendorResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedVendors); err == nil {
		return cachedVendors, nil
	}

	var vendors []models.Vendor
	// Build query - if tenantID is uuid.Nil (saas_admin), don't filter by tenant
	query := s.db.DB
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	if !includeInactive {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Preload("BankAccounts").Order("name ASC").Find(&vendors).Error; err != nil {
		return nil, fmt.Errorf("failed to get vendors: %w", err)
	}

	// Batch-fetch totals for all vendors (eliminates N+1 queries)
	type purchaseTotal struct {
		VendorID       uuid.UUID `gorm:"column:vendor_id"`
		TotalPurchases float64   `gorm:"column:total_purchases"`
	}
	var purchaseTotals []purchaseTotal
	s.db.DB.Model(&models.StockPurchase{}).
		Select("vendor_id, COALESCE(SUM(total_amount), 0) as total_purchases").
		Where("tenant_id = ?", tenantID).
		Group("vendor_id").
		Scan(&purchaseTotals)
	purchaseMap := make(map[uuid.UUID]float64, len(purchaseTotals))
	for _, pt := range purchaseTotals {
		purchaseMap[pt.VendorID] = pt.TotalPurchases
	}

	type balanceResult struct {
		VendorID           uuid.UUID `gorm:"column:vendor_id"`
		OutstandingBalance float64   `gorm:"column:outstanding_balance"`
	}
	var balanceResults []balanceResult
	s.db.DB.Model(&models.VendorTransaction{}).
		Select("vendor_id, COALESCE(SUM(CASE WHEN transaction_type = 'purchase' THEN amount WHEN transaction_type = 'payment' THEN -amount ELSE 0 END), 0) as outstanding_balance").
		Where("tenant_id = ?", tenantID).
		Group("vendor_id").
		Scan(&balanceResults)
	balanceMap := make(map[uuid.UUID]float64, len(balanceResults))
	for _, br := range balanceResults {
		balanceMap[br.VendorID] = br.OutstandingBalance
	}

	var responses []VendorResponse
	for _, vendor := range vendors {
		response := s.buildVendorResponse(vendor, purchaseMap[vendor.ID], balanceMap[vendor.ID], vendor.BankAccounts)
		responses = append(responses, *response)
	}

	// Cache the result
	s.cache.Set(ctx, cacheKey, responses, 5*time.Minute) // Cache for 5 minutes

	return responses, nil
}

func (s *VendorService) GetVendorByID(ctx context.Context, id, tenantID uuid.UUID) (*VendorResponse, error) {
	var vendor models.Vendor
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("BankAccounts").
		First(&vendor).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("vendor not found")
		}
		return nil, fmt.Errorf("failed to get vendor: %w", err)
	}

	// Calculate totals
	var totalPurchases float64
	s.db.DB.Model(&models.StockPurchase{}).
		Where("vendor_id = ? AND tenant_id = ?", id, tenantID).
		Select("COALESCE(SUM(total_amount), 0)").
		Scan(&totalPurchases)

	var outstandingBalance float64
	s.db.DB.Model(&models.VendorTransaction{}).
		Where("vendor_id = ? AND tenant_id = ?", id, tenantID).
		Select("COALESCE(SUM(CASE WHEN transaction_type = 'purchase' THEN amount WHEN transaction_type = 'payment' THEN -amount ELSE 0 END), 0)").
		Scan(&outstandingBalance)

	return s.buildVendorResponse(vendor, totalPurchases, outstandingBalance, vendor.BankAccounts), nil
}

func (s *VendorService) UpdateVendor(ctx context.Context, id uuid.UUID, req VendorRequest, tenantID, userID uuid.UUID) (*VendorResponse, error) {
	var vendor models.Vendor
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).First(&vendor).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("vendor not found")
		}
		return nil, fmt.Errorf("failed to get vendor: %w", err)
	}

	// Check if updating name would create duplicate
	if req.Name != vendor.Name {
		var existingVendor models.Vendor
		err := s.db.DB.Where("name = ? AND tenant_id = ? AND id != ?", req.Name, tenantID, id).First(&existingVendor).Error
		if err == nil {
			return nil, fmt.Errorf("vendor with this name already exists")
		} else if err != gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("failed to check existing vendor: %w", err)
		}
	}

	// Update vendor
	updates := map[string]interface{}{
		"name":           req.Name,
		"contact_person": req.ContactPerson,
		"email":          req.Email,
		"phone":          req.Phone,
		"address":        req.Address,
		"city":           req.City,
		"state":          req.State,
		"country":        req.Country,
		"postal_code":    req.PostalCode,
		"tax_id":         req.TaxID,
		"credit_limit":   req.CreditLimit,
		"payment_terms":  req.PaymentTerms,
		"updated_by":     userID,
	}

	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}

	if err := s.db.DB.Model(&vendor).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update vendor: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("vendors:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Return updated vendor
	return s.GetVendorByID(ctx, id, tenantID)
}

func (s *VendorService) DeleteVendor(ctx context.Context, id, tenantID uuid.UUID) error {
	// Check if vendor has purchases
	var purchaseCount int64
	if err := s.db.DB.Model(&models.StockPurchase{}).Where("vendor_id = ? AND tenant_id = ?", id, tenantID).Count(&purchaseCount).Error; err != nil {
		return fmt.Errorf("failed to check purchases: %w", err)
	}

	if purchaseCount > 0 {
		return fmt.Errorf("cannot delete vendor: %d purchases exist", purchaseCount)
	}

	// Delete vendor
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).Delete(&models.Vendor{}).Error; err != nil {
		return fmt.Errorf("failed to delete vendor: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("vendors:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return nil
}

// Bank Account Operations
func (s *VendorService) AddVendorBankAccount(ctx context.Context, vendorID uuid.UUID, req VendorBankAccountRequest, tenantID, userID uuid.UUID) (*VendorBankAccountResponse, error) {
	// Verify vendor exists
	var vendor models.Vendor
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", vendorID, tenantID).First(&vendor).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("vendor not found")
		}
		return nil, fmt.Errorf("failed to get vendor: %w", err)
	}

	isDefault := false
	if req.IsDefault != nil {
		isDefault = *req.IsDefault
	}

	// If this is set as default, unset others
	if isDefault {
		s.db.DB.Model(&models.VendorBankAccount{}).
			Where("vendor_id = ? AND tenant_id = ?", vendorID, tenantID).
			Update("is_default", false)
	}

	bankAccount := models.VendorBankAccount{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		VendorID:      vendorID,
		BankName:      req.BankName,
		AccountNumber: req.AccountNumber,
		AccountHolder: req.AccountHolder,
		BranchCode:    req.BranchCode,
		SwiftCode:     req.SwiftCode,
		IsDefault:     isDefault,
		CreatedBy:     userID,
	}

	if err := s.db.DB.Create(&bankAccount).Error; err != nil {
		return nil, fmt.Errorf("failed to create bank account: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("vendors:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return &VendorBankAccountResponse{
		ID:            bankAccount.ID,
		BankName:      bankAccount.BankName,
		AccountNumber: bankAccount.AccountNumber,
		AccountHolder: bankAccount.AccountHolder,
		BranchCode:    bankAccount.BranchCode,
		SwiftCode:     bankAccount.SwiftCode,
		IsDefault:     bankAccount.IsDefault,
		CreatedAt:     bankAccount.CreatedAt,
	}, nil
}

// Transaction Operations
func (s *VendorService) CreateVendorTransaction(ctx context.Context, req VendorTransactionRequest, tenantID, userID uuid.UUID) (*VendorTransactionResponse, error) {
	// Verify vendor exists
	var vendor models.Vendor
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.VendorID, tenantID).First(&vendor).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("vendor not found")
		}
		return nil, fmt.Errorf("failed to get vendor: %w", err)
	}

	transaction := models.VendorTransaction{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		VendorID:        req.VendorID,
		TransactionType: req.TransactionType,
		Amount:          req.Amount,
		Notes:           req.Description,
		ReferenceNumber: req.ReferenceNo,
	}

	if err := s.db.DB.Create(&transaction).Error; err != nil {
		return nil, fmt.Errorf("failed to create transaction: %w", err)
	}

	return &VendorTransactionResponse{
		ID:              transaction.ID,
		VendorID:        transaction.VendorID,
		VendorName:      vendor.Name,
		TransactionType: transaction.TransactionType,
		Amount:          transaction.Amount,
		Description:     transaction.Notes,
		ReferenceNo:     transaction.ReferenceNumber,
		CreatedAt:       transaction.CreatedAt,
	}, nil
}

func (s *VendorService) GetVendorTransactions(ctx context.Context, vendorID, tenantID uuid.UUID, limit, offset int) ([]VendorTransactionResponse, int64, error) {
	var transactions []models.VendorTransaction
	var total int64

	query := s.db.DB.Where("vendor_id = ? AND tenant_id = ?", vendorID, tenantID)

	// Get total count
	if err := query.Model(&models.VendorTransaction{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count transactions: %w", err)
	}

	// Get transactions with pagination
	if err := query.
		Preload("Vendor").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&transactions).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get transactions: %w", err)
	}

	var responses []VendorTransactionResponse
	for _, transaction := range transactions {
		vendorName := ""
		if transaction.Vendor != nil {
			vendorName = transaction.Vendor.Name
		}

		response := VendorTransactionResponse{
			ID:              transaction.ID,
			VendorID:        transaction.VendorID,
			VendorName:      vendorName,
			TransactionType: transaction.TransactionType,
			Amount:          transaction.Amount,
			Description:     transaction.Notes,
			ReferenceNo:     transaction.ReferenceNumber,
			CreatedAt:       transaction.CreatedAt,
		}
		responses = append(responses, response)
	}

	return responses, total, nil
}

// Vendor Ledger Types
type VendorLedgerEntry struct {
	ID             uuid.UUID  `json:"id"`
	Date           time.Time  `json:"date"`
	Type           string     `json:"type"`            // "purchase", "payment", "adjustment"
	ReferenceNo    string     `json:"reference_no"`
	Description    string     `json:"description"`
	Debit          float64    `json:"debit"`           // Purchases increase balance owed
	Credit         float64    `json:"credit"`          // Payments decrease balance owed
	RunningBalance float64    `json:"running_balance"`
	PurchaseID     *uuid.UUID `json:"purchase_id,omitempty"`
	PaymentMethod  string     `json:"payment_method,omitempty"`
}

type VendorLedgerResponse struct {
	VendorID       uuid.UUID           `json:"vendor_id"`
	VendorName     string              `json:"vendor_name"`
	OpeningBalance float64             `json:"opening_balance"`
	TotalDebits    float64             `json:"total_debits"`
	TotalCredits   float64             `json:"total_credits"`
	ClosingBalance float64             `json:"closing_balance"`
	Entries        []VendorLedgerEntry `json:"entries"`
	Total          int64               `json:"total"`
	Page           int                 `json:"page"`
	PageSize       int                 `json:"page_size"`
}

// GetVendorLedger returns a full ledger view with running balance for a vendor
func (s *VendorService) GetVendorLedger(ctx context.Context, vendorID, tenantID uuid.UUID, page, pageSize int, startDate, endDate *time.Time) (*VendorLedgerResponse, error) {
	// Verify vendor exists
	var vendor models.Vendor
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", vendorID, tenantID).First(&vendor).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("vendor not found")
		}
		return nil, fmt.Errorf("failed to get vendor: %w", err)
	}

	// Fetch all vendor transactions
	var transactions []models.VendorTransaction
	txQuery := s.db.DB.Where("vendor_id = ? AND tenant_id = ?", vendorID, tenantID)
	if startDate != nil {
		txQuery = txQuery.Where("created_at >= ?", startDate)
	}
	if endDate != nil {
		txQuery = txQuery.Where("created_at <= ?", endDate)
	}
	if err := txQuery.Order("created_at ASC").Find(&transactions).Error; err != nil {
		return nil, fmt.Errorf("failed to get transactions: %w", err)
	}

	// Fetch all approved stock purchases for this vendor
	var purchases []models.StockPurchase
	purchaseQuery := s.db.DB.Where("vendor_id = ? AND tenant_id = ? AND status = ?", vendorID, tenantID, "approved")
	if startDate != nil {
		purchaseQuery = purchaseQuery.Where("created_at >= ?", startDate)
	}
	if endDate != nil {
		purchaseQuery = purchaseQuery.Where("created_at <= ?", endDate)
	}
	if err := purchaseQuery.Order("created_at ASC").Find(&purchases).Error; err != nil {
		return nil, fmt.Errorf("failed to get purchases: %w", err)
	}

	// Build ledger entries from both transactions and purchases
	var allEntries []VendorLedgerEntry

	// Add purchase entries (from stock purchases that don't already have a matching transaction)
	purchaseRefNos := make(map[string]bool)
	for _, tx := range transactions {
		if tx.TransactionType == "purchase" && tx.ReferenceNumber != "" {
			purchaseRefNos[tx.ReferenceNumber] = true
		}
	}

	for _, p := range purchases {
		// Skip if there's already a transaction for this purchase
		if purchaseRefNos[p.PurchaseNumber] {
			continue
		}
		purchaseID := p.ID
		entry := VendorLedgerEntry{
			ID:          p.ID,
			Date:        p.CreatedAt,
			Type:        "purchase",
			ReferenceNo: p.PurchaseNumber,
			Description: fmt.Sprintf("Stock Purchase %s", p.PurchaseNumber),
			Debit:       p.TotalAmount,
			Credit:      0,
			PurchaseID:  &purchaseID,
		}
		allEntries = append(allEntries, entry)
	}

	// Add transaction entries
	for _, tx := range transactions {
		entry := VendorLedgerEntry{
			ID:          tx.ID,
			Date:        tx.CreatedAt,
			Type:        tx.TransactionType,
			ReferenceNo: tx.ReferenceNumber,
			Description: tx.Notes,
		}

		if tx.TransactionType == "purchase" {
			entry.Debit = tx.Amount
			entry.Credit = 0
		} else if tx.TransactionType == "payment" {
			entry.Debit = 0
			entry.Credit = tx.Amount
		} else {
			// adjustment - could be positive or negative
			if tx.Amount > 0 {
				entry.Debit = tx.Amount
			} else {
				entry.Credit = -tx.Amount
			}
		}

		allEntries = append(allEntries, entry)
	}

	// Sort all entries by date (O(n log n) instead of O(n²))
	sort.Slice(allEntries, func(i, j int) bool {
		return allEntries[i].Date.Before(allEntries[j].Date)
	})

	// Calculate running balance and totals
	var runningBalance, totalDebits, totalCredits float64
	for i := range allEntries {
		runningBalance += allEntries[i].Debit - allEntries[i].Credit
		allEntries[i].RunningBalance = runningBalance
		totalDebits += allEntries[i].Debit
		totalCredits += allEntries[i].Credit
	}

	// Pagination
	total := int64(len(allEntries))
	startIdx := (page - 1) * pageSize
	endIdx := startIdx + pageSize
	if startIdx > len(allEntries) {
		startIdx = len(allEntries)
	}
	if endIdx > len(allEntries) {
		endIdx = len(allEntries)
	}

	paginatedEntries := allEntries
	if startIdx < len(allEntries) {
		paginatedEntries = allEntries[startIdx:endIdx]
	} else {
		paginatedEntries = []VendorLedgerEntry{}
	}

	return &VendorLedgerResponse{
		VendorID:       vendor.ID,
		VendorName:     vendor.Name,
		OpeningBalance: 0,
		TotalDebits:    totalDebits,
		TotalCredits:   totalCredits,
		ClosingBalance: runningBalance,
		Entries:        paginatedEntries,
		Total:          total,
		Page:           page,
		PageSize:       pageSize,
	}, nil
}

// Helper functions
func (s *VendorService) buildVendorResponse(
	vendor models.Vendor,
	totalPurchases, outstandingBalance float64,
	bankAccounts []models.VendorBankAccount,
) *VendorResponse {
	response := &VendorResponse{
		ID:                 vendor.ID,
		Name:               vendor.Name,
		ContactPerson:      vendor.ContactPerson,
		Email:              vendor.Email,
		Phone:              vendor.Phone,
		Address:            vendor.Address,
		City:               vendor.City,
		State:              vendor.State,
		Country:            vendor.Country,
		PostalCode:         vendor.PostalCode,
		TaxID:              vendor.TaxID,
		CreditLimit:        vendor.CreditLimit,
		PaymentTerms:       vendor.PaymentTerms,
		IsActive:           vendor.IsActive,
		TotalPurchases:     totalPurchases,
		OutstandingBalance: outstandingBalance,
		CreatedAt:          vendor.CreatedAt,
		UpdatedAt:          vendor.UpdatedAt,
	}

	for _, account := range bankAccounts {
		accountResponse := VendorBankAccountResponse{
			ID:            account.ID,
			BankName:      account.BankName,
			AccountNumber: account.AccountNumber,
			AccountHolder: account.AccountHolder,
			BranchCode:    account.BranchCode,
			SwiftCode:     account.SwiftCode,
			IsDefault:     account.IsDefault,
			CreatedAt:     account.CreatedAt,
		}
		response.BankAccounts = append(response.BankAccounts, accountResponse)
	}

	return response
}

// Advanced Financial Reports
type VendorAgingBucket struct {
	Period string  `json:"period"`
	Amount float64 `json:"amount"`
	Count  int     `json:"count"`
}

type VendorAgingEntry struct {
	VendorID   uuid.UUID           `json:"vendor_id"`
	VendorName string              `json:"vendor_name"`
	Total      float64             `json:"total"`
	Buckets    []VendorAgingBucket `json:"buckets"`
}

type VendorAgingReport struct {
	Vendors   []VendorAgingEntry `json:"vendors"`
	Summary   map[string]float64 `json:"summary"`
	TotalOwed float64            `json:"total_owed"`
}

func (s *VendorService) GetVendorAgingReport(ctx context.Context, tenantID uuid.UUID, asOfDate time.Time) (*VendorAgingReport, error) {
	// For now, create a mock report with realistic data structure
	// In production, this would calculate actual aging from vendor transactions
	mockVendors := []VendorAgingEntry{
		{
			VendorID:   uuid.New(),
			VendorName: "Premium Liquor Distributors",
			Total:      15000.00,
			Buckets: []VendorAgingBucket{
				{Period: "0-30 days", Amount: 8000.00, Count: 5},
				{Period: "31-60 days", Amount: 4000.00, Count: 2},
				{Period: "61-90 days", Amount: 2000.00, Count: 1},
				{Period: "90+ days", Amount: 1000.00, Count: 1},
			},
		},
		{
			VendorID:   uuid.New(),
			VendorName: "Wholesale Wine Company",
			Total:      8500.00,
			Buckets: []VendorAgingBucket{
				{Period: "0-30 days", Amount: 6000.00, Count: 3},
				{Period: "31-60 days", Amount: 2500.00, Count: 2},
				{Period: "61-90 days", Amount: 0, Count: 0},
				{Period: "90+ days", Amount: 0, Count: 0},
			},
		},
	}

	summary := map[string]float64{
		"0-30 days":  14000.00,
		"31-60 days": 6500.00,
		"61-90 days": 2000.00,
		"90+ days":   1000.00,
	}

	return &VendorAgingReport{
		Vendors:   mockVendors,
		Summary:   summary,
		TotalOwed: 23500.00,
	}, nil
}

type BalanceSheetAssets struct {
	CurrentAssets struct {
		Cash               float64 `json:"cash"`
		AccountsReceivable float64 `json:"accounts_receivable"`
		Inventory          float64 `json:"inventory"`
		OtherCurrentAssets float64 `json:"other_current_assets"`
		Total              float64 `json:"total"`
	} `json:"current_assets"`
	FixedAssets struct {
		Equipment  float64 `json:"equipment"`
		Furniture  float64 `json:"furniture"`
		OtherFixed float64 `json:"other_fixed"`
		Total      float64 `json:"total"`
	} `json:"fixed_assets"`
	TotalAssets float64 `json:"total_assets"`
}

type BalanceSheetLiabilities struct {
	CurrentLiabilities struct {
		AccountsPayable         float64 `json:"accounts_payable"`
		AccruedLiabilities      float64 `json:"accrued_liabilities"`
		ShortTermDebt           float64 `json:"short_term_debt"`
		OtherCurrentLiabilities float64 `json:"other_current_liabilities"`
		Total                   float64 `json:"total"`
	} `json:"current_liabilities"`
	LongTermLiabilities struct {
		LongTermDebt  float64 `json:"long_term_debt"`
		OtherLongTerm float64 `json:"other_long_term"`
		Total         float64 `json:"total"`
	} `json:"long_term_liabilities"`
	TotalLiabilities float64 `json:"total_liabilities"`
}

type BalanceSheetEquity struct {
	OwnersEquity     float64 `json:"owners_equity"`
	RetainedEarnings float64 `json:"retained_earnings"`
	Total            float64 `json:"total"`
}

type BalanceSheetReport struct {
	Assets      BalanceSheetAssets      `json:"assets"`
	Liabilities BalanceSheetLiabilities `json:"liabilities"`
	Equity      BalanceSheetEquity      `json:"equity"`
}

func (s *VendorService) GetBalanceSheetReport(ctx context.Context, tenantID uuid.UUID, asOfDate time.Time) (*BalanceSheetReport, error) {
	// Mock balance sheet data - in production, this would calculate from actual financial data
	report := &BalanceSheetReport{}

	// Assets
	report.Assets.CurrentAssets.Cash = 25000.00
	report.Assets.CurrentAssets.AccountsReceivable = 18000.00
	report.Assets.CurrentAssets.Inventory = 120000.00
	report.Assets.CurrentAssets.OtherCurrentAssets = 5000.00
	report.Assets.CurrentAssets.Total = report.Assets.CurrentAssets.Cash +
		report.Assets.CurrentAssets.AccountsReceivable +
		report.Assets.CurrentAssets.Inventory +
		report.Assets.CurrentAssets.OtherCurrentAssets

	report.Assets.FixedAssets.Equipment = 45000.00
	report.Assets.FixedAssets.Furniture = 15000.00
	report.Assets.FixedAssets.OtherFixed = 8000.00
	report.Assets.FixedAssets.Total = report.Assets.FixedAssets.Equipment +
		report.Assets.FixedAssets.Furniture +
		report.Assets.FixedAssets.OtherFixed

	report.Assets.TotalAssets = report.Assets.CurrentAssets.Total + report.Assets.FixedAssets.Total

	// Liabilities
	report.Liabilities.CurrentLiabilities.AccountsPayable = 23500.00
	report.Liabilities.CurrentLiabilities.AccruedLiabilities = 8000.00
	report.Liabilities.CurrentLiabilities.ShortTermDebt = 15000.00
	report.Liabilities.CurrentLiabilities.OtherCurrentLiabilities = 2500.00
	report.Liabilities.CurrentLiabilities.Total = report.Liabilities.CurrentLiabilities.AccountsPayable +
		report.Liabilities.CurrentLiabilities.AccruedLiabilities +
		report.Liabilities.CurrentLiabilities.ShortTermDebt +
		report.Liabilities.CurrentLiabilities.OtherCurrentLiabilities

	report.Liabilities.LongTermLiabilities.LongTermDebt = 35000.00
	report.Liabilities.LongTermLiabilities.OtherLongTerm = 5000.00
	report.Liabilities.LongTermLiabilities.Total = report.Liabilities.LongTermLiabilities.LongTermDebt +
		report.Liabilities.LongTermLiabilities.OtherLongTerm

	report.Liabilities.TotalLiabilities = report.Liabilities.CurrentLiabilities.Total +
		report.Liabilities.LongTermLiabilities.Total

	// Equity
	report.Equity.OwnersEquity = 100000.00
	report.Equity.RetainedEarnings = report.Assets.TotalAssets - report.Liabilities.TotalLiabilities - report.Equity.OwnersEquity
	report.Equity.Total = report.Equity.OwnersEquity + report.Equity.RetainedEarnings

	return report, nil
}
