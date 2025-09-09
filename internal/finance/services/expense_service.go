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

type ExpenseService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewExpenseService(db *database.DB, cache *cache.Cache) *ExpenseService {
	return &ExpenseService{
		db:    db,
		cache: cache,
	}
}

type ExpenseRequest struct {
	CategoryID    uuid.UUID `json:"category_id" binding:"required"`
	ShopID        uuid.UUID `json:"shop_id" binding:"required"`
	Amount        float64   `json:"amount" binding:"required,gt=0"`
	Description   string    `json:"description" binding:"required"`
	ExpenseDate   time.Time `json:"expense_date" binding:"required"`
	ReceiptNo     string    `json:"receipt_no"`
	PaymentMethod string    `json:"payment_method" binding:"required"`
	VendorID      *uuid.UUID `json:"vendor_id"`
	Notes         string    `json:"notes"`
}

type ExpenseResponse struct {
	ID            uuid.UUID `json:"id"`
	CategoryID    uuid.UUID `json:"category_id"`
	CategoryName  string    `json:"category_name"`
	ShopID        uuid.UUID `json:"shop_id"`
	ShopName      string    `json:"shop_name"`
	Amount        float64   `json:"amount"`
	Description   string    `json:"description"`
	ExpenseDate   time.Time `json:"expense_date"`
	ReceiptNo     string    `json:"receipt_no"`
	PaymentMethod string    `json:"payment_method"`
	VendorID      *uuid.UUID `json:"vendor_id"`
	VendorName    string    `json:"vendor_name,omitempty"`
	Notes         string    `json:"notes"`
	CreatedBy     uuid.UUID `json:"created_by"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type ExpenseCategoryRequest struct {
	Name        string `json:"name" binding:"required,max=255"`
	Description string `json:"description"`
	IsActive    *bool  `json:"is_active"`
}

type ExpenseCategoryResponse struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	IsActive    bool      `json:"is_active"`
	TotalAmount float64   `json:"total_amount"`
	ExpenseCount int64    `json:"expense_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type ExpenseSummaryResponse struct {
	TotalExpenses        float64            `json:"total_expenses"`
	ExpensesByCategory   []CategorySummary  `json:"expenses_by_category"`
	ExpensesByPaymentMethod []PaymentMethodSummary `json:"expenses_by_payment_method"`
	ExpensesByShop       []ShopSummary      `json:"expenses_by_shop"`
	MonthlyTrend         []MonthlySummary   `json:"monthly_trend"`
}

type CategorySummary struct {
	CategoryID   uuid.UUID `json:"category_id"`
	CategoryName string    `json:"category_name"`
	Amount       float64   `json:"amount"`
	Count        int64     `json:"count"`
}

type PaymentMethodSummary struct {
	PaymentMethod string  `json:"payment_method"`
	Amount        float64 `json:"amount"`
	Count         int64   `json:"count"`
}

type ShopSummary struct {
	ShopID   uuid.UUID `json:"shop_id"`
	ShopName string    `json:"shop_name"`
	Amount   float64   `json:"amount"`
	Count    int64     `json:"count"`
}

type MonthlySummary struct {
	Year   int     `json:"year"`
	Month  int     `json:"month"`
	Amount float64 `json:"amount"`
	Count  int64   `json:"count"`
}

// Expense CRUD Operations
func (s *ExpenseService) CreateExpense(ctx context.Context, req ExpenseRequest, tenantID, userID uuid.UUID) (*ExpenseResponse, error) {
	// Validate category exists
	var category models.ExpenseCategory
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("expense category not found")
		}
		return nil, fmt.Errorf("failed to validate category: %w", err)
	}

	// Validate shop exists
	var shop models.Shop
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("shop not found")
		}
		return nil, fmt.Errorf("failed to validate shop: %w", err)
	}

	// Validate vendor if provided
	var vendor *models.Vendor
	if req.VendorID != nil {
		vendor = &models.Vendor{}
		if err := s.db.DB.Where("id = ? AND tenant_id = ?", *req.VendorID, tenantID).First(vendor).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				return nil, fmt.Errorf("vendor not found")
			}
			return nil, fmt.Errorf("failed to validate vendor: %w", err)
		}
	}

	expense := models.Expense{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  tenantID,
		},
		CategoryID:    &req.CategoryID,
		ShopID:        &req.ShopID,
		Amount:        req.Amount,
		Description:   req.Description,
		ExpenseDate:   req.ExpenseDate,
		ReceiptNo:     req.ReceiptNo,
		PaymentMethod: req.PaymentMethod,
		VendorID:      req.VendorID,
		Notes:         req.Notes,
		CreatedByID:   userID,
	}

	if err := s.db.DB.Create(&expense).Error; err != nil {
		return nil, fmt.Errorf("failed to create expense: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("expenses:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Build response
	response := s.buildExpenseResponse(expense, category.Name, shop.Name, "")
	if vendor != nil {
		response.VendorName = vendor.Name
	}

	return response, nil
}

func (s *ExpenseService) GetExpenses(ctx context.Context, tenantID uuid.UUID, filters ExpenseFilters, limit, offset int) ([]ExpenseResponse, int64, error) {
	var expenses []models.Expense
	var total int64

	query := s.db.DB.Where("tenant_id = ?", tenantID)
	
	// Apply filters
	if filters.CategoryID != nil {
		query = query.Where("category_id = ?", *filters.CategoryID)
	}
	if filters.ShopID != nil {
		query = query.Where("shop_id = ?", *filters.ShopID)
	}
	if filters.VendorID != nil {
		query = query.Where("vendor_id = ?", *filters.VendorID)
	}
	if !filters.StartDate.IsZero() {
		query = query.Where("expense_date >= ?", filters.StartDate)
	}
	if !filters.EndDate.IsZero() {
		query = query.Where("expense_date <= ?", filters.EndDate)
	}
	if filters.PaymentMethod != "" {
		query = query.Where("payment_method = ?", filters.PaymentMethod)
	}

	// Get total count
	if err := query.Model(&models.Expense{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count expenses: %w", err)
	}

	// Get expenses with pagination
	if err := query.
		Preload("Category").
		Preload("Shop").
		Preload("Vendor").
		Order("expense_date DESC, created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&expenses).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get expenses: %w", err)
	}

	var responses []ExpenseResponse
	for _, expense := range expenses {
		response := s.buildExpenseResponseFromModel(expense)
		responses = append(responses, *response)
	}

	return responses, total, nil
}

type ExpenseFilters struct {
	CategoryID    *uuid.UUID
	ShopID        *uuid.UUID
	VendorID      *uuid.UUID
	StartDate     time.Time
	EndDate       time.Time
	PaymentMethod string
}

func (s *ExpenseService) GetExpenseByID(ctx context.Context, id, tenantID uuid.UUID) (*ExpenseResponse, error) {
	var expense models.Expense
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Category").
		Preload("Shop").
		Preload("Vendor").
		First(&expense).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("expense not found")
		}
		return nil, fmt.Errorf("failed to get expense: %w", err)
	}

	return s.buildExpenseResponseFromModel(expense), nil
}

func (s *ExpenseService) UpdateExpense(ctx context.Context, id uuid.UUID, req ExpenseRequest, tenantID, userID uuid.UUID) (*ExpenseResponse, error) {
	var expense models.Expense
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).First(&expense).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("expense not found")
		}
		return nil, fmt.Errorf("failed to get expense: %w", err)
	}

	// Validate references (same as create)
	var category models.ExpenseCategory
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
		return nil, fmt.Errorf("expense category not found")
	}

	var shop models.Shop
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		return nil, fmt.Errorf("shop not found")
	}

	if req.VendorID != nil {
		var vendor models.Vendor
		if err := s.db.DB.Where("id = ? AND tenant_id = ?", *req.VendorID, tenantID).First(&vendor).Error; err != nil {
			return nil, fmt.Errorf("vendor not found")
		}
	}

	// Update expense
	updates := map[string]interface{}{
		"category_id":    req.CategoryID,
		"shop_id":        req.ShopID,
		"amount":         req.Amount,
		"description":    req.Description,
		"expense_date":   req.ExpenseDate,
		"receipt_no":     req.ReceiptNo,
		"payment_method": req.PaymentMethod,
		"vendor_id":      req.VendorID,
		"notes":          req.Notes,
		"updated_by":     userID,
	}

	if err := s.db.DB.Model(&expense).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update expense: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("expenses:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.GetExpenseByID(ctx, id, tenantID)
}

func (s *ExpenseService) DeleteExpense(ctx context.Context, id, tenantID uuid.UUID) error {
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).Delete(&models.Expense{}).Error; err != nil {
		return fmt.Errorf("failed to delete expense: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("expenses:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return nil
}

// Expense Category Operations
func (s *ExpenseService) CreateExpenseCategory(ctx context.Context, req ExpenseCategoryRequest, tenantID, userID uuid.UUID) (*ExpenseCategoryResponse, error) {
	// Check if category name already exists
	var existingCategory models.ExpenseCategory
	err := s.db.DB.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existingCategory).Error
	if err == nil {
		return nil, fmt.Errorf("expense category with this name already exists")
	} else if err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to check existing category: %w", err)
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	category := models.ExpenseCategory{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  tenantID,
		},
		Name:        req.Name,
		Description: req.Description,
		IsActive:    isActive,
		CreatedBy:   userID,
	}

	if err := s.db.DB.Create(&category).Error; err != nil {
		return nil, fmt.Errorf("failed to create expense category: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("expense_categories:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.buildExpenseCategoryResponse(category, 0, 0), nil
}

func (s *ExpenseService) GetExpenseCategories(ctx context.Context, tenantID uuid.UUID, includeInactive bool) ([]ExpenseCategoryResponse, error) {
	cacheKey := fmt.Sprintf("expense_categories:tenant:%s:inactive:%t", tenantID.String(), includeInactive)
	
	// Try to get from cache
	var cachedCategories []ExpenseCategoryResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedCategories); err == nil {
		return cachedCategories, nil
	}

	var categories []models.ExpenseCategory
	query := s.db.DB.Where("tenant_id = ?", tenantID)
	
	if !includeInactive {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Order("name ASC").Find(&categories).Error; err != nil {
		return nil, fmt.Errorf("failed to get expense categories: %w", err)
	}

	// Calculate totals for each category
	var responses []ExpenseCategoryResponse
	for _, category := range categories {
		var totalAmount float64
		var expenseCount int64
		
		s.db.DB.Model(&models.Expense{}).
			Where("category_id = ? AND tenant_id = ?", category.ID, tenantID).
			Select("COALESCE(SUM(amount), 0)").
			Scan(&totalAmount)
		
		s.db.DB.Model(&models.Expense{}).
			Where("category_id = ? AND tenant_id = ?", category.ID, tenantID).
			Count(&expenseCount)

		response := s.buildExpenseCategoryResponse(category, totalAmount, expenseCount)
		responses = append(responses, *response)
	}

	// Cache the result
	s.cache.Set(ctx, cacheKey, responses, 5*time.Minute) // Cache for 5 minutes

	return responses, nil
}

// Summary and Reports
func (s *ExpenseService) GetExpenseSummary(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time) (*ExpenseSummaryResponse, error) {
	cacheKey := fmt.Sprintf("expense_summary:tenant:%s:start:%s:end:%s", 
		tenantID.String(), startDate.Format("2006-01-02"), endDate.Format("2006-01-02"))
	
	// Try to get from cache
	var cachedSummary ExpenseSummaryResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedSummary); err == nil {
		return &cachedSummary, nil
	}

	query := s.db.DB.Where("tenant_id = ?", tenantID)
	if !startDate.IsZero() {
		query = query.Where("expense_date >= ?", startDate)
	}
	if !endDate.IsZero() {
		query = query.Where("expense_date <= ?", endDate)
	}

	// Get total expenses
	var totalExpenses float64
	query.Model(&models.Expense{}).Select("COALESCE(SUM(amount), 0)").Scan(&totalExpenses)

	summary := &ExpenseSummaryResponse{
		TotalExpenses: totalExpenses,
	}

	// Get expenses by category
	var categorySummaries []CategorySummary
	s.db.DB.Table("expenses e").
		Select("e.category_id, ec.name as category_name, SUM(e.amount) as amount, COUNT(*) as count").
		Joins("JOIN expense_categories ec ON e.category_id = ec.id").
		Where("e.tenant_id = ? AND e.expense_date BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("e.category_id, ec.name").
		Scan(&categorySummaries)
	summary.ExpensesByCategory = categorySummaries

	// Get expenses by payment method
	var paymentMethodSummaries []PaymentMethodSummary
	s.db.DB.Table("expenses").
		Select("payment_method, SUM(amount) as amount, COUNT(*) as count").
		Where("tenant_id = ? AND expense_date BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("payment_method").
		Scan(&paymentMethodSummaries)
	summary.ExpensesByPaymentMethod = paymentMethodSummaries

	// Get expenses by shop
	var shopSummaries []ShopSummary
	s.db.DB.Table("expenses e").
		Select("e.shop_id, s.name as shop_name, SUM(e.amount) as amount, COUNT(*) as count").
		Joins("JOIN shops s ON e.shop_id = s.id").
		Where("e.tenant_id = ? AND e.expense_date BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("e.shop_id, s.name").
		Scan(&shopSummaries)
	summary.ExpensesByShop = shopSummaries

	// Get monthly trend
	var monthlySummaries []MonthlySummary
	s.db.DB.Table("expenses").
		Select("EXTRACT(YEAR FROM expense_date) as year, EXTRACT(MONTH FROM expense_date) as month, SUM(amount) as amount, COUNT(*) as count").
		Where("tenant_id = ? AND expense_date BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("EXTRACT(YEAR FROM expense_date), EXTRACT(MONTH FROM expense_date)").
		Order("year, month").
		Scan(&monthlySummaries)
	summary.MonthlyTrend = monthlySummaries

	// Cache the result
	s.cache.Set(ctx, cacheKey, summary, 600) // Cache for 10 minutes

	return summary, nil
}

// Helper functions
func (s *ExpenseService) buildExpenseResponse(expense models.Expense, categoryName, shopName, vendorName string) *ExpenseResponse {
	var categoryID, shopID uuid.UUID
	if expense.CategoryID != nil {
		categoryID = *expense.CategoryID
	}
	if expense.ShopID != nil {
		shopID = *expense.ShopID
	}
	
	return &ExpenseResponse{
		ID:            expense.ID,
		CategoryID:    categoryID,
		CategoryName:  categoryName,
		ShopID:        shopID,
		ShopName:      shopName,
		Amount:        expense.Amount,
		Description:   expense.Description,
		ExpenseDate:   expense.ExpenseDate,
		ReceiptNo:     expense.ReceiptNo,
		PaymentMethod: expense.PaymentMethod,
		VendorID:      expense.VendorID,
		VendorName:    vendorName,
		Notes:         expense.Notes,
		CreatedBy:     expense.CreatedByID,
		CreatedAt:     expense.CreatedAt,
		UpdatedAt:     expense.UpdatedAt,
	}
}

func (s *ExpenseService) buildExpenseResponseFromModel(expense models.Expense) *ExpenseResponse {
	var categoryID, shopID uuid.UUID
	if expense.CategoryID != nil {
		categoryID = *expense.CategoryID
	}
	if expense.ShopID != nil {
		shopID = *expense.ShopID
	}
	
	response := &ExpenseResponse{
		ID:            expense.ID,
		CategoryID:    categoryID,
		ShopID:        shopID,
		Amount:        expense.Amount,
		Description:   expense.Description,
		ExpenseDate:   expense.ExpenseDate,
		ReceiptNo:     expense.ReceiptNo,
		PaymentMethod: expense.PaymentMethod,
		VendorID:      expense.VendorID,
		Notes:         expense.Notes,
		CreatedBy:     expense.CreatedByID,
		CreatedAt:     expense.CreatedAt,
		UpdatedAt:     expense.UpdatedAt,
	}

	if expense.Category != nil {
		response.CategoryName = expense.Category.Name
	}
	if expense.Shop != nil {
		response.ShopName = expense.Shop.Name
	}
	if expense.Vendor != nil {
		response.VendorName = expense.Vendor.Name
	}

	return response
}

func (s *ExpenseService) buildExpenseCategoryResponse(category models.ExpenseCategory, totalAmount float64, expenseCount int64) *ExpenseCategoryResponse {
	return &ExpenseCategoryResponse{
		ID:           category.ID,
		Name:         category.Name,
		Description:  category.Description,
		IsActive:     category.IsActive,
		TotalAmount:  totalAmount,
		ExpenseCount: expenseCount,
		CreatedAt:    category.CreatedAt,
		UpdatedAt:    category.UpdatedAt,
	}
}