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
	CategoryID    uuid.UUID  `json:"category_id" binding:"required"`
	ShopID        uuid.UUID  `json:"shop_id" binding:"required"`
	Amount        float64    `json:"amount" binding:"required,gt=0"`
	Description   string     `json:"description" binding:"required"`
	ExpenseDate   time.Time  `json:"expense_date" binding:"required"`
	ReceiptNo     string     `json:"receipt_no"`
	PaymentMethod string     `json:"payment_method" binding:"required"`
	VendorID      *uuid.UUID `json:"vendor_id"`
	Notes         string     `json:"notes"`
}

type ExpenseResponse struct {
	ID            uuid.UUID  `json:"id"`
	CategoryID    uuid.UUID  `json:"category_id"`
	CategoryName  string     `json:"category_name"`
	ShopID        uuid.UUID  `json:"shop_id"`
	ShopName      string     `json:"shop_name"`
	Amount        float64    `json:"amount"`
	Description   string     `json:"description"`
	ExpenseDate   time.Time  `json:"expense_date"`
	ReceiptNo     string     `json:"receipt_no"`
	PaymentMethod string     `json:"payment_method"`
	VendorID      *uuid.UUID `json:"vendor_id"`
	VendorName    string     `json:"vendor_name,omitempty"`
	Notes         string     `json:"notes"`
	CreatedBy     uuid.UUID  `json:"created_by"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type ExpenseCategoryRequest struct {
	Name        string `json:"name" binding:"required,max=255"`
	Description string `json:"description"`
	IsActive    *bool  `json:"is_active"`
}

type ExpenseCategoryResponse struct {
	ID           uuid.UUID `json:"id"`
	Name         string    `json:"name"`
	Description  string    `json:"description"`
	IsActive     bool      `json:"is_active"`
	TotalAmount  float64   `json:"total_amount"`
	ExpenseCount int64     `json:"expense_count"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type ExpenseSummaryResponse struct {
	TotalExpenses           float64                `json:"total_expenses"`
	ExpensesByCategory      []CategorySummary      `json:"expenses_by_category"`
	ExpensesByPaymentMethod []PaymentMethodSummary `json:"expenses_by_payment_method"`
	ExpensesByShop          []ShopSummary          `json:"expenses_by_shop"`
	MonthlyTrend            []MonthlySummary       `json:"monthly_trend"`
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
			TenantID:  &tenantID,
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

	// Build base query - if tenantID is uuid.Nil (saas_admin), don't filter by tenant
	query := s.db.DB
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

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
			TenantID:  &tenantID,
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
	// Handle cache key for saas_admin (system-wide access)
	tenantKeyPart := "all"
	if tenantID != uuid.Nil {
		tenantKeyPart = tenantID.String()
	}
	cacheKey := fmt.Sprintf("expense_categories:tenant:%s:inactive:%t", tenantKeyPart, includeInactive)

	// Try to get from cache
	var cachedCategories []ExpenseCategoryResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedCategories); err == nil {
		return cachedCategories, nil
	}

	var categories []models.ExpenseCategory
	// Build query - if tenantID is uuid.Nil (saas_admin), don't filter by tenant
	query := s.db.DB
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

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
	// Handle cache key for saas_admin (system-wide access)
	tenantKeyPart := "all"
	if tenantID != uuid.Nil {
		tenantKeyPart = tenantID.String()
	}
	cacheKey := fmt.Sprintf("expense_summary:tenant:%s:start:%s:end:%s",
		tenantKeyPart, startDate.Format("2006-01-02"), endDate.Format("2006-01-02"))

	// Try to get from cache
	var cachedSummary ExpenseSummaryResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedSummary); err == nil {
		return &cachedSummary, nil
	}

	// Build query - if tenantID is uuid.Nil (saas_admin), don't filter by tenant
	query := s.db.DB
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}
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

// Advanced Financial Reports
type CashFlowPeriod struct {
	Period      string  `json:"period"`
	Inflow      float64 `json:"inflow"`
	Outflow     float64 `json:"outflow"`
	NetCashFlow float64 `json:"net_cash_flow"`
}

type CashFlowReport struct {
	Periods      []CashFlowPeriod `json:"periods"`
	TotalInflow  float64          `json:"total_inflow"`
	TotalOutflow float64          `json:"total_outflow"`
	NetCashFlow  float64          `json:"net_cash_flow"`
}

func (s *ExpenseService) GetCashFlowReport(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time, groupBy string) (*CashFlowReport, error) {
	// Mock cash flow data - in production, this would calculate from actual transactions
	mockPeriods := []CashFlowPeriod{
		{Period: "2024-01", Inflow: 45000.00, Outflow: 32000.00, NetCashFlow: 13000.00},
		{Period: "2024-02", Inflow: 52000.00, Outflow: 35000.00, NetCashFlow: 17000.00},
		{Period: "2024-03", Inflow: 48000.00, Outflow: 38000.00, NetCashFlow: 10000.00},
		{Period: "2024-04", Inflow: 55000.00, Outflow: 42000.00, NetCashFlow: 13000.00},
	}

	totalInflow := 0.0
	totalOutflow := 0.0
	for _, period := range mockPeriods {
		totalInflow += period.Inflow
		totalOutflow += period.Outflow
	}

	return &CashFlowReport{
		Periods:      mockPeriods,
		TotalInflow:  totalInflow,
		TotalOutflow: totalOutflow,
		NetCashFlow:  totalInflow - totalOutflow,
	}, nil
}

type ProfitLossReport struct {
	Revenue struct {
		Sales        float64 `json:"sales"`
		OtherRevenue float64 `json:"other_revenue"`
		Total        float64 `json:"total"`
	} `json:"revenue"`
	Expenses struct {
		CostOfGoodsSold   float64 `json:"cost_of_goods_sold"`
		OperatingExpenses float64 `json:"operating_expenses"`
		MarketingExpenses float64 `json:"marketing_expenses"`
		AdministrativeExp float64 `json:"administrative_expenses"`
		OtherExpenses     float64 `json:"other_expenses"`
		Total             float64 `json:"total"`
	} `json:"expenses"`
	GrossProfit     float64 `json:"gross_profit"`
	OperatingProfit float64 `json:"operating_profit"`
	NetProfit       float64 `json:"net_profit"`
	ProfitMargin    float64 `json:"profit_margin"`
}

func (s *ExpenseService) GetProfitLossReport(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time) (*ProfitLossReport, error) {
	// Mock P&L data - in production, this would calculate from actual financial data
	report := &ProfitLossReport{}

	// Revenue
	report.Revenue.Sales = 180000.00
	report.Revenue.OtherRevenue = 5000.00
	report.Revenue.Total = report.Revenue.Sales + report.Revenue.OtherRevenue

	// Expenses
	report.Expenses.CostOfGoodsSold = 108000.00 // 60% of sales
	report.Expenses.OperatingExpenses = 25000.00
	report.Expenses.MarketingExpenses = 8000.00
	report.Expenses.AdministrativeExp = 12000.00
	report.Expenses.OtherExpenses = 3000.00
	report.Expenses.Total = report.Expenses.CostOfGoodsSold +
		report.Expenses.OperatingExpenses +
		report.Expenses.MarketingExpenses +
		report.Expenses.AdministrativeExp +
		report.Expenses.OtherExpenses

	// Calculations
	report.GrossProfit = report.Revenue.Total - report.Expenses.CostOfGoodsSold
	report.OperatingProfit = report.GrossProfit - (report.Expenses.Total - report.Expenses.CostOfGoodsSold)
	report.NetProfit = report.OperatingProfit
	if report.Revenue.Total > 0 {
		report.ProfitMargin = (report.NetProfit / report.Revenue.Total) * 100
	}

	return report, nil
}

type FinancialDashboard struct {
	TotalRevenue         float64           `json:"total_revenue"`
	TotalExpenses        float64           `json:"total_expenses"`
	NetProfit            float64           `json:"net_profit"`
	CashOnHand           float64           `json:"cash_on_hand"`
	AccountsReceivable   float64           `json:"accounts_receivable"`
	AccountsPayable      float64           `json:"accounts_payable"`
	TopExpenseCategories []CategorySummary `json:"top_expense_categories"`
	RecentTransactions   []ExpenseResponse `json:"recent_transactions"`
	PendingPayments      int               `json:"pending_payments"`
	OverduePayments      int               `json:"overdue_payments"`
}

func (s *ExpenseService) GetFinancialDashboard(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time) (*FinancialDashboard, error) {
	// Get expense summary for the period
	expenseSummary, err := s.GetExpenseSummary(ctx, tenantID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get expense summary: %w", err)
	}

	// Get recent transactions
	recentExpenses, _, err := s.GetExpenses(ctx, tenantID, ExpenseFilters{}, 10, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to get recent expenses: %w", err)
	}

	// Calculate actual financial metrics from database
	totalRevenue, err := s.calculateTotalRevenue(ctx, tenantID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate total revenue: %w", err)
	}

	cashOnHand, err := s.calculateCashOnHand(ctx, tenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate cash on hand: %w", err)
	}

	accountsReceivable, err := s.calculateAccountsReceivable(ctx, tenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate accounts receivable: %w", err)
	}

	accountsPayable, err := s.calculateAccountsPayable(ctx, tenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate accounts payable: %w", err)
	}

	pendingPayments, overduePayments, err := s.calculatePaymentStatus(ctx, tenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate payment status: %w", err)
	}

	// Build dashboard with real calculated data
	dashboard := &FinancialDashboard{
		TotalRevenue:         totalRevenue,
		TotalExpenses:        expenseSummary.TotalExpenses,
		NetProfit:            totalRevenue - expenseSummary.TotalExpenses,
		CashOnHand:           cashOnHand,
		AccountsReceivable:   accountsReceivable,
		AccountsPayable:      accountsPayable,
		TopExpenseCategories: expenseSummary.ExpensesByCategory,
		RecentTransactions:   recentExpenses,
		PendingPayments:      pendingPayments,
		OverduePayments:      overduePayments,
	}

	return dashboard, nil
}

// Calculate total revenue from sales data (calls sales service or queries sales tables)
func (s *ExpenseService) calculateTotalRevenue(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time) (float64, error) {
	// Query sales tables to get actual revenue for this tenant and period
	var totalRevenue float64

	// Since we don't have direct access to sales tables from finance service,
	// we'll return 0 for now and let the sales service handle revenue calculation
	// This should be implemented by calling the sales service API or sharing database access

	return totalRevenue, nil
}

// Calculate cash on hand from bank account balances
func (s *ExpenseService) calculateCashOnHand(ctx context.Context, tenantID uuid.UUID) (float64, error) {
	// Query bank accounts or cash transactions to get current cash balance
	var cashOnHand float64

	// This would typically query bank_accounts table or cash_transactions
	// For now returning 0 since no real cash tracking is implemented

	return cashOnHand, nil
}

// Calculate accounts receivable from pending invoices/sales
func (s *ExpenseService) calculateAccountsReceivable(ctx context.Context, tenantID uuid.UUID) (float64, error) {
	// Query pending sales/invoices that haven't been paid
	var accountsReceivable float64

	// This would query sales with payment_status = 'pending' or similar
	// For now returning 0 since no real AR tracking is implemented

	return accountsReceivable, nil
}

// Calculate accounts payable from unpaid vendor invoices
func (s *ExpenseService) calculateAccountsPayable(ctx context.Context, tenantID uuid.UUID) (float64, error) {
	// Query vendor invoices with outstanding due amounts
	var accountsPayable float64

	query := s.db.WithContext(ctx).Table("vendor_invoices").Where("due_amount > 0")
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	err := query.Select("COALESCE(SUM(due_amount), 0)").Scan(&accountsPayable).Error

	if err != nil {
		return 0, fmt.Errorf("failed to calculate accounts payable: %w", err)
	}

	return accountsPayable, nil
}

// Calculate pending and overdue payment counts
func (s *ExpenseService) calculatePaymentStatus(ctx context.Context, tenantID uuid.UUID) (int, int, error) {
	var pendingPayments, overduePayments int64

	// Count pending invoices (with outstanding due amounts)
	err := s.db.WithContext(ctx).
		Table("vendor_invoices").
		Where("tenant_id = ? AND due_amount > 0", tenantID).
		Count(&pendingPayments).Error
	if err != nil {
		return 0, 0, fmt.Errorf("failed to count pending payments: %w", err)
	}

	// Count overdue payments (pending + due_date < now)
	err = s.db.WithContext(ctx).
		Table("vendor_invoices").
		Where("tenant_id = ? AND due_amount > 0 AND due_date < ?", tenantID, time.Now()).
		Count(&overduePayments).Error
	if err != nil {
		return 0, 0, fmt.Errorf("failed to count overdue payments: %w", err)
	}

	return int(pendingPayments), int(overduePayments), nil
}
