package services

import (
	"context"
	"fmt"
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
	Name            string  `json:"name" binding:"required,max=255"`
	ContactPerson   string  `json:"contact_person"`
	Email           string  `json:"email"`
	Phone           string  `json:"phone"`
	Address         string  `json:"address"`
	City            string  `json:"city"`
	State           string  `json:"state"`
	Country         string  `json:"country"`
	PostalCode      string  `json:"postal_code"`
	TaxID           string  `json:"tax_id"`
	CreditLimit     float64 `json:"credit_limit"`
	PaymentTerms    string  `json:"payment_terms"`
	IsActive        *bool   `json:"is_active"`
}

type VendorResponse struct {
	ID              uuid.UUID                    `json:"id"`
	Name            string                       `json:"name"`
	ContactPerson   string                       `json:"contact_person"`
	Email           string                       `json:"email"`
	Phone           string                       `json:"phone"`
	Address         string                       `json:"address"`
	City            string                       `json:"city"`
	State           string                       `json:"state"`
	Country         string                       `json:"country"`
	PostalCode      string                       `json:"postal_code"`
	TaxID           string                       `json:"tax_id"`
	CreditLimit     float64                      `json:"credit_limit"`
	PaymentTerms    string                       `json:"payment_terms"`
	IsActive        bool                         `json:"is_active"`
	TotalPurchases  float64                      `json:"total_purchases"`
	OutstandingBalance float64                   `json:"outstanding_balance"`
	BankAccounts    []VendorBankAccountResponse  `json:"bank_accounts"`
	CreatedAt       time.Time                    `json:"created_at"`
	UpdatedAt       time.Time                    `json:"updated_at"`
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
			TenantID:  tenantID,
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
	cacheKey := fmt.Sprintf("vendors:tenant:%s:inactive:%t", tenantID.String(), includeInactive)
	
	// Try to get from cache
	var cachedVendors []VendorResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedVendors); err == nil {
		return cachedVendors, nil
	}

	var vendors []models.Vendor
	query := s.db.DB.Where("tenant_id = ?", tenantID)
	
	if !includeInactive {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Preload("BankAccounts").Order("name ASC").Find(&vendors).Error; err != nil {
		return nil, fmt.Errorf("failed to get vendors: %w", err)
	}

	// Calculate totals for each vendor
	var responses []VendorResponse
	for _, vendor := range vendors {
		// Get total purchases
		var totalPurchases float64
		s.db.DB.Model(&models.StockPurchase{}).
			Where("vendor_id = ? AND tenant_id = ?", vendor.ID, tenantID).
			Select("COALESCE(SUM(total_amount), 0)").
			Scan(&totalPurchases)

		// Get outstanding balance
		var outstandingBalance float64
		s.db.DB.Model(&models.VendorTransaction{}).
			Where("vendor_id = ? AND tenant_id = ?", vendor.ID, tenantID).
			Select("COALESCE(SUM(CASE WHEN transaction_type = 'purchase' THEN amount WHEN transaction_type = 'payment' THEN -amount ELSE 0 END), 0)").
			Scan(&outstandingBalance)

		response := s.buildVendorResponse(vendor, totalPurchases, outstandingBalance, vendor.BankAccounts)
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
			TenantID:  tenantID,
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
			TenantID:  tenantID,
		},
		VendorID:        req.VendorID,
		TransactionType: req.TransactionType,
		Amount:          req.Amount,
		Description:     req.Description,
		ReferenceNo:     req.ReferenceNo,
		PaymentMethod:   req.PaymentMethod,
		CreatedBy:       userID,
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
		Description:     transaction.Description,
		ReferenceNo:     transaction.ReferenceNo,
		PaymentMethod:   transaction.PaymentMethod,
		CreatedBy:       transaction.CreatedBy,
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
			Description:     transaction.Description,
			ReferenceNo:     transaction.ReferenceNo,
			PaymentMethod:   transaction.PaymentMethod,
			CreatedBy:       transaction.CreatedBy,
			CreatedAt:       transaction.CreatedAt,
		}
		responses = append(responses, response)
	}

	return responses, total, nil
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