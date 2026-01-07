package services

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

type ExpenseService struct {
	db                   *database.DB
	cache                *cache.Cache
	workflowNotification *notifservices.WorkflowNotificationService
}

func NewExpenseService(db *database.DB, cache *cache.Cache) *ExpenseService {
	return &ExpenseService{
		db:    db,
		cache: cache,
	}
}

// SetWorkflowNotificationService sets the workflow notification service
func (s *ExpenseService) SetWorkflowNotificationService(wn *notifservices.WorkflowNotificationService) {
	s.workflowNotification = wn
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
	// Query actual cash transactions from cash_transactions table
	var results []struct {
		Period  string  `gorm:"column:period"`
		Inflow  float64 `gorm:"column:inflow"`
		Outflow float64 `gorm:"column:outflow"`
	}

	// Determine period format based on groupBy parameter
	periodFormat := "YYYY-MM" // default monthly
	if groupBy == "daily" {
		periodFormat = "YYYY-MM-DD"
	} else if groupBy == "weekly" {
		periodFormat = "IYYY-IW" // ISO year and week number
	}

	// Query to aggregate inflows and outflows by period
	query := fmt.Sprintf(`
		SELECT
			TO_CHAR(transaction_date, '%s') as period,
			COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) as inflow,
			COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0) as outflow
		FROM cash_transactions
		WHERE tenant_id = ? AND transaction_date BETWEEN ? AND ?
		GROUP BY period
		ORDER BY period
	`, periodFormat)

	if err := s.db.WithContext(ctx).Raw(query, tenantID, startDate, endDate).Scan(&results).Error; err != nil {
		return nil, fmt.Errorf("failed to get cash flow data: %w", err)
	}

	var periods []CashFlowPeriod
	var totalInflow, totalOutflow float64

	for _, r := range results {
		periods = append(periods, CashFlowPeriod{
			Period:      r.Period,
			Inflow:      r.Inflow,
			Outflow:     r.Outflow,
			NetCashFlow: r.Inflow - r.Outflow,
		})
		totalInflow += r.Inflow
		totalOutflow += r.Outflow
	}

	return &CashFlowReport{
		Periods:      periods,
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

	// Ensure arrays are never nil (initialize empty arrays if nil)
	topCategories := expenseSummary.ExpensesByCategory
	if topCategories == nil {
		topCategories = []CategorySummary{}
	}

	recentTxns := recentExpenses
	if recentTxns == nil {
		recentTxns = []ExpenseResponse{}
	}

	// Build dashboard with real calculated data
	dashboard := &FinancialDashboard{
		TotalRevenue:         totalRevenue,
		TotalExpenses:        expenseSummary.TotalExpenses,
		NetProfit:            totalRevenue - expenseSummary.TotalExpenses,
		CashOnHand:           cashOnHand,
		AccountsReceivable:   accountsReceivable,
		AccountsPayable:      accountsPayable,
		TopExpenseCategories: topCategories,
		RecentTransactions:   recentTxns,
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

// Calculate cash on hand from cash_holdings table
func (s *ExpenseService) calculateCashOnHand(ctx context.Context, tenantID uuid.UUID) (float64, error) {
	var cashOnHand float64

	query := s.db.WithContext(ctx).Table("cash_holdings")
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ? AND deleted_at IS NULL", tenantID)
	}

	err := query.Select("COALESCE(SUM(current_balance), 0)").Scan(&cashOnHand).Error
	if err != nil {
		return 0, fmt.Errorf("failed to calculate cash on hand: %w", err)
	}

	return cashOnHand, nil
}

// TeamBalanceResponse represents a single team member's cash balance
type TeamBalanceResponse struct {
	UserID         uuid.UUID `json:"user_id"`
	Username       string    `json:"username"`
	FullName       string    `json:"full_name"`
	Role           string    `json:"role"`
	CurrentBalance float64   `json:"current_balance"`
	ShopID         string    `json:"shop_id"`
	ShopName       string    `json:"shop_name"`
	LastUpdatedAt  time.Time `json:"last_updated_at"`
}

// GetTeamBalances returns cash balances for team members in a tenant
// Results are filtered by role hierarchy - users only see balances of users at or below their level
func (s *ExpenseService) GetTeamBalances(ctx context.Context, tenantID uuid.UUID, currentUserRole string) ([]TeamBalanceResponse, float64, error) {
	var teamBalances []TeamBalanceResponse
	var totalBalance float64

	// Get allowed roles based on the current user's role hierarchy
	allowedRoles := utils.GetAllowedRoles(currentUserRole)
	if len(allowedRoles) == 0 {
		// Unknown role sees no users
		return []TeamBalanceResponse{}, 0, nil
	}

	// Build role placeholders for SQL: $2, $3, $4...
	rolePlaceholders := make([]string, len(allowedRoles))
	queryArgs := make([]interface{}, len(allowedRoles)+1)
	queryArgs[0] = tenantID
	for i, role := range allowedRoles {
		rolePlaceholders[i] = fmt.Sprintf("$%d", i+2)
		queryArgs[i+1] = role
	}
	roleFilter := strings.Join(rolePlaceholders, ", ")

	// Query users with cash balance filtered by role hierarchy
	// Priority: cash_holdings table (if exists), otherwise calculate from cash_transactions
	query := fmt.Sprintf(`
		SELECT
			u.id as user_id,
			u.username,
			CONCAT(u.first_name, ' ', u.last_name) as full_name,
			u.role,
			COALESCE(
				ch.current_balance,
				(
					SELECT COALESCE(SUM(
						CASE
							WHEN ct.transaction_type IN ('collection_received', 'sale') THEN ct.amount
							WHEN ct.transaction_type IN ('collection_sent', 'expense') THEN -ct.amount
							ELSE 0
						END
					), 0)
					FROM cash_transactions ct
					WHERE ct.user_id = u.id
						AND ct.tenant_id = $1
						AND ct.deleted_at IS NULL
				)
			) as current_balance,
			ch.shop_id,
			COALESCE(s.name, '') as shop_name,
			COALESCE(ch.last_updated_at, u.updated_at) as last_updated_at
		FROM users u
		LEFT JOIN cash_holdings ch ON u.id = ch.user_id AND ch.tenant_id = $1 AND ch.deleted_at IS NULL
		LEFT JOIN shops s ON ch.shop_id = s.id
		WHERE u.tenant_id = $1
			AND u.deleted_at IS NULL
			AND u.is_active = true
			AND u.role IN (%s)
		ORDER BY current_balance DESC, u.first_name ASC
	`, roleFilter)

	rows, err := s.db.DB.Raw(query, queryArgs...).Rows()
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query team balances: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var tb TeamBalanceResponse
		var shopID *uuid.UUID

		err := rows.Scan(
			&tb.UserID,
			&tb.Username,
			&tb.FullName,
			&tb.Role,
			&tb.CurrentBalance,
			&shopID,
			&tb.ShopName,
			&tb.LastUpdatedAt,
		)
		if err != nil {
			return nil, 0, fmt.Errorf("failed to scan team balance: %w", err)
		}

		// Convert UUID pointer to string (empty string if nil)
		if shopID != nil {
			tb.ShopID = shopID.String()
		} else {
			tb.ShopID = ""
		}
		teamBalances = append(teamBalances, tb)
		totalBalance += tb.CurrentBalance
	}

	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("error iterating team balances: %w", err)
	}

	// Ensure we return empty array instead of nil
	if teamBalances == nil {
		teamBalances = []TeamBalanceResponse{}
	}

	return teamBalances, totalBalance, nil
}

// GetCashBalance returns the total cash balance for a tenant filtered by user's role hierarchy.
// Users can only see the total balance of users at their role level or below.
// This ensures proper data isolation - managers cannot see admin's cash, etc.
func (s *ExpenseService) GetCashBalance(ctx context.Context, tenantID uuid.UUID, userRole string) (float64, error) {
	// Validate role to prevent unauthorized access
	if userRole == "" {
		return 0, fmt.Errorf("user role is required for cash balance calculation")
	}

	// Use GetTeamBalances with the actual user's role for proper filtering
	_, totalBalance, err := s.GetTeamBalances(ctx, tenantID, userRole)
	if err != nil {
		return 0, fmt.Errorf("failed to calculate cash balance: %w", err)
	}
	return totalBalance, nil
}

// GetUserCashBalance returns the cash balance for a specific user
func (s *ExpenseService) GetUserCashBalance(ctx context.Context, tenantID, userID uuid.UUID) (float64, error) {
	// First check if user has a cash_holdings record
	var holding struct {
		CurrentBalance float64
	}
	err := s.db.DB.Table("cash_holdings").
		Select("current_balance").
		Where("user_id = ? AND tenant_id = ? AND deleted_at IS NULL", userID, tenantID).
		Scan(&holding).Error

	// If we found a cash_holdings record, use it (even if balance is 0)
	if err == nil {
		return holding.CurrentBalance, nil
	}

	// If error is not "record not found", return the error
	if err != gorm.ErrRecordNotFound {
		return 0, fmt.Errorf("failed to get cash holding: %w", err)
	}

	// Fallback: Calculate from cash_transactions table (more accurate than sales - collections)
	var calculatedBalance float64
	err = s.db.DB.Table("cash_transactions").
		Select("COALESCE(SUM(CASE WHEN transaction_type IN ('collection_received', 'sale') THEN amount WHEN transaction_type IN ('collection_sent', 'expense') THEN -amount ELSE 0 END), 0)").
		Where("user_id = ? AND tenant_id = ? AND deleted_at IS NULL", userID, tenantID).
		Scan(&calculatedBalance).Error

	if err != nil {
		return 0, fmt.Errorf("failed to calculate balance from transactions: %w", err)
	}

	return calculatedBalance, nil
}

// RecalculateAllBalances recalculates all user balances from cash_transactions
// This is useful for fixing balance discrepancies and ensuring data consistency
func (s *ExpenseService) RecalculateAllBalances(ctx context.Context, tenantID uuid.UUID) (int64, error) {
	query := `
		UPDATE cash_holdings ch
		SET current_balance = COALESCE((
			SELECT SUM(
				CASE
					WHEN ct.transaction_type IN ('collection_received', 'sale') THEN ct.amount
					WHEN ct.transaction_type IN ('collection_sent', 'expense') THEN -ct.amount
					ELSE 0
				END
			)
			FROM cash_transactions ct
			WHERE ct.user_id = ch.user_id
			  AND ct.tenant_id = ch.tenant_id
			  AND ct.deleted_at IS NULL
		), 0),
		last_updated_at = NOW(),
		updated_at = NOW()
		WHERE ch.tenant_id = $1
		  AND ch.deleted_at IS NULL
	`

	result := s.db.DB.Exec(query, tenantID)
	if result.Error != nil {
		return 0, fmt.Errorf("failed to recalculate balances: %w", result.Error)
	}

	return result.RowsAffected, nil
}

// TenantUserResponse represents a user in the tenant for cash management
type TenantUserResponse struct {
	ID             uuid.UUID `json:"id"`
	Username       string    `json:"username"`
	FullName       string    `json:"full_name"`
	FirstName      string    `json:"first_name"`
	LastName       string    `json:"last_name"`
	Email          string    `json:"email"`
	Phone          string    `json:"phone"`
	Role           string    `json:"role"`
	IsActive       bool      `json:"is_active"`
	CurrentBalance float64   `json:"current_balance"`
	ShopID         string    `json:"shop_id"`
	ShopName       string    `json:"shop_name"`
}

// GetTenantUsers returns users for a tenant (for cash management purposes)
// Shows ALL users in tenant, but only displays balance for users at or below the requester's hierarchy level
func (s *ExpenseService) GetTenantUsers(ctx context.Context, tenantID uuid.UUID, currentUserRole string) ([]TenantUserResponse, error) {
	var users []TenantUserResponse

	// Get current user's role level for hierarchy comparison
	currentUserLevel := utils.GetRoleLevel(currentUserRole)

	// Query shows ALL users but conditionally displays balance based on hierarchy
	// Balance is only shown for users whose role level is <= current user's level
	// Role levels: salesman=1, executive=2, assistant_manager=3, manager=4, admin=5, owner=6
	query := `
		SELECT
			u.id,
			COALESCE(u.username, '') as username,
			COALESCE(CONCAT(u.first_name, ' ', u.last_name), '') as full_name,
			COALESCE(u.first_name, '') as first_name,
			COALESCE(u.last_name, '') as last_name,
			COALESCE(u.email, '') as email,
			COALESCE(u.phone, '') as phone,
			COALESCE(u.role, '') as role,
			COALESCE(u.is_active, false) as is_active,
			CASE
				WHEN (
					CASE u.role
						WHEN 'salesman' THEN 1
						WHEN 'executive' THEN 2
						WHEN 'assistant_manager' THEN 3
						WHEN 'manager' THEN 4
						WHEN 'admin' THEN 5
						WHEN 'owner' THEN 6
						ELSE 0
					END
				) <= $2 THEN
					COALESCE(
						ch.current_balance,
						(
							SELECT COALESCE(SUM(dsr.total_cash_amount), 0)
							FROM daily_sales_records dsr
							WHERE (dsr.salesman_id = u.id OR dsr.created_by_id = u.id)
								AND dsr.tenant_id = $1
								AND dsr.deleted_at IS NULL
						) - (
							SELECT COALESCE(SUM(mc.amount), 0)
							FROM money_collections mc
							WHERE mc.requested_from_user_id = u.id
								AND mc.tenant_id = $1
								AND mc.status = 'approved'
								AND mc.deleted_at IS NULL
						)
					)
				ELSE 0
			END as current_balance,
			'' as shop_id,
			'' as shop_name
		FROM users u
		LEFT JOIN cash_holdings ch ON u.id = ch.user_id AND ch.tenant_id = $1 AND ch.deleted_at IS NULL
		WHERE u.tenant_id = $1
			AND u.deleted_at IS NULL
		ORDER BY u.role, u.first_name ASC
	`

	rows, err := s.db.DB.Raw(query, tenantID, currentUserLevel).Rows()
	if err != nil {
		return nil, fmt.Errorf("failed to query tenant users: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var user TenantUserResponse
		err := rows.Scan(
			&user.ID,
			&user.Username,
			&user.FullName,
			&user.FirstName,
			&user.LastName,
			&user.Email,
			&user.Phone,
			&user.Role,
			&user.IsActive,
			&user.CurrentBalance,
			&user.ShopID,
			&user.ShopName,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, user)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating users: %w", err)
	}

	// Ensure we return empty array instead of nil
	if users == nil {
		users = []TenantUserResponse{}
	}

	return users, nil
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

// CashTransactionResponse represents a unified cash transaction for API responses
type CashTransactionResponse struct {
	ID                string    `json:"id"`
	UserID            string    `json:"user_id"`
	UserName          string    `json:"user_name"`
	ShopID            string    `json:"shop_id"`
	TransactionType   string    `json:"transaction_type"`
	Amount            float64   `json:"amount"`
	PreviousBalance   float64   `json:"previous_balance"`
	NewBalance        float64   `json:"new_balance"`
	RelatedEntityType string    `json:"related_entity_type"`
	RelatedEntityID   string    `json:"related_entity_id"`
	Description       string    `json:"description"`
	CounterpartyID    string    `json:"counterparty_id"`
	CounterpartyName  string    `json:"counterparty_name"`
	TransactionDate   time.Time `json:"transaction_date"`
	CreatedAt         time.Time `json:"created_at"`
}

// ==================== ADMIN CASH BALANCE MANAGEMENT ====================

// Pre-defined adjustment reasons for admin balance operations
var AdminAdjustmentReasons = map[string]string{
	"fresh_start":    "Fresh Start - New Period",
	"correction":     "Balance Correction",
	"audit_fix":      "Audit Adjustment",
	"reconciliation": "Cash Reconciliation",
	"period_close":   "Period/Month Close",
	"system_error":   "System Error Fix",
	"other":          "Other (See Notes)",
}

// AdminSetBalance sets a user's cash balance to an exact amount
// This creates a compensating transaction to adjust the balance
func (s *ExpenseService) AdminSetBalance(
	ctx context.Context,
	targetUserID, adminUserID, tenantID uuid.UUID,
	newBalance float64,
	reason, notes string,
) error {
	// 1. Get current balance for this user
	currentBalance, err := s.GetUserCashBalance(ctx, tenantID, targetUserID)
	if err != nil {
		return fmt.Errorf("failed to get current balance: %w", err)
	}

	// 2. Calculate adjustment amount
	adjustment := newBalance - currentBalance
	if adjustment == 0 {
		return nil // No change needed
	}

	// 3. Build description with reason
	reasonText := AdminAdjustmentReasons[reason]
	if reasonText == "" {
		reasonText = reason
	}
	description := fmt.Sprintf("Admin Adjustment: %s", reasonText)
	if notes != "" {
		description += fmt.Sprintf(". Note: %s", notes)
	}

	// 4. Use a transaction to ensure consistency
	tx := s.db.DB.Begin()
	if tx.Error != nil {
		return fmt.Errorf("failed to begin transaction: %w", tx.Error)
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// 5. Create the cash transaction record
	transaction := models.CashTransaction{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		UserID:          targetUserID,
		Amount:          adjustment,
		TransactionType: "admin_adjustment",
		BalanceBefore:   currentBalance,
		BalanceAfter:    newBalance,
		RelatedType:     "admin_action",
		RelatedID:       &adminUserID,
		Notes:           description,
		TransactionDate: time.Now(),
	}

	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to create transaction: %w", err)
	}

	// 6. Update or create the cash_holdings record
	var holding models.CashHolding
	err = tx.Where("user_id = ? AND tenant_id = ?", targetUserID, tenantID).First(&holding).Error

	if err == gorm.ErrRecordNotFound {
		// Create new holding
		holding = models.CashHolding{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			UserID:         targetUserID,
			CurrentBalance: newBalance,
			LastUpdatedAt:  time.Now(),
		}
		if err := tx.Create(&holding).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create cash holding: %w", err)
		}
	} else if err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to check cash holding: %w", err)
	} else {
		// Update existing holding
		if err := tx.Model(&holding).Updates(map[string]interface{}{
			"current_balance":  newBalance,
			"last_updated_at":  time.Now(),
			"updated_at":       time.Now(),
		}).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to update balance: %w", err)
		}
	}

	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// AdminBulkReset resets multiple users' balances to a specified amount
// If no userIDs provided, resets all users in the tenant
func (s *ExpenseService) AdminBulkReset(
	ctx context.Context,
	adminUserID, tenantID uuid.UUID,
	userIDs []uuid.UUID,
	newBalance float64,
	reason, notes string,
) (int, error) {
	// If no userIDs provided, get all users in the tenant (except the admin)
	if len(userIDs) == 0 {
		var users []struct {
			ID uuid.UUID
		}
		if err := s.db.DB.Table("users").
			Select("id").
			Where("tenant_id = ? AND id != ? AND deleted_at IS NULL", tenantID, adminUserID).
			Scan(&users).Error; err != nil {
			return 0, fmt.Errorf("failed to get users: %w", err)
		}
		for _, u := range users {
			userIDs = append(userIDs, u.ID)
		}
	}

	// Process each user
	successCount := 0
	for _, userID := range userIDs {
		err := s.AdminSetBalance(ctx, userID, adminUserID, tenantID, newBalance, reason, notes)
		if err != nil {
			// Log error but continue processing other users
			fmt.Printf("Failed to reset balance for user %s: %v\n", userID, err)
			continue
		}
		successCount++
	}

	return successCount, nil
}

// GetCashTransactions aggregates cash transactions from multiple sources
func (s *ExpenseService) GetCashTransactions(ctx context.Context, tenantID uuid.UUID, userID *uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time, limit, offset int) ([]CashTransactionResponse, int64, error) {
	var transactions []CashTransactionResponse
	var totalCount int64

	// Query 1: Get transactions from executive_finances (cash handovers)
	var execFinances []struct {
		ID              uuid.UUID `gorm:"column:id"`
		ShopID          uuid.UUID `gorm:"column:shop_id"`
		FromUserID      uuid.UUID `gorm:"column:from_user_id"`
		TransactionType string    `gorm:"column:transaction_type"`
		Amount          float64   `gorm:"column:amount"`
		Description     string    `gorm:"column:description"`
		SubmittedAt     time.Time `gorm:"column:submitted_at"`
		CreatedAt       time.Time `gorm:"column:created_at"`
	}

	execQuery := s.db.WithContext(ctx).
		Table("executive_finances").
		Where("tenant_id = ? AND submitted_at BETWEEN ? AND ?", tenantID, startDate, endDate)

	if userID != nil {
		execQuery = execQuery.Where("from_user_id = ? OR to_user_id = ?", *userID, *userID)
	}
	if shopID != nil {
		execQuery = execQuery.Where("shop_id = ?", *shopID)
	}

	if err := execQuery.Find(&execFinances).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get executive finances: %w", err)
	}

	for _, ef := range execFinances {
		txnType := "handover"
		if ef.TransactionType == "expense_claim" {
			txnType = "expense_claim"
		}
		transactions = append(transactions, CashTransactionResponse{
			ID:                ef.ID.String(),
			UserID:            ef.FromUserID.String(),
			ShopID:            ef.ShopID.String(),
			TransactionType:   txnType,
			Amount:            ef.Amount,
			PreviousBalance:   0,
			NewBalance:        0,
			RelatedEntityType: "executive_finance",
			RelatedEntityID:   ef.ID.String(),
			Description:       ef.Description,
			TransactionDate:   ef.SubmittedAt,
			CreatedAt:         ef.CreatedAt,
		})
	}

	// Query 2: Get transactions from expenses
	var expenses []struct {
		ID            uuid.UUID  `gorm:"column:id"`
		ShopID        *uuid.UUID `gorm:"column:shop_id"`
		CreatedByID   uuid.UUID  `gorm:"column:created_by_id"`
		Amount        float64    `gorm:"column:amount"`
		Description   string     `gorm:"column:description"`
		ExpenseDate   time.Time  `gorm:"column:expense_date"`
		CreatedAt     time.Time  `gorm:"column:created_at"`
		PaymentMethod string     `gorm:"column:payment_method"`
	}

	expenseQuery := s.db.WithContext(ctx).
		Table("expenses").
		Where("tenant_id = ? AND expense_date BETWEEN ? AND ?", tenantID, startDate, endDate)

	// Note: The expenses table may not have created_by_id column in all deployments
	// Skip user filtering for expenses if column doesn't exist (will be fixed in migration)
	if shopID != nil {
		expenseQuery = expenseQuery.Where("shop_id = ?", *shopID)
	}

	if err := expenseQuery.Find(&expenses).Error; err != nil {
		// Log error but continue - expenses are optional for cash transactions list
		fmt.Printf("Warning: Failed to get expenses: %v\n", err)
		expenses = nil
	}

	for _, exp := range expenses {
		shopIDStr := ""
		if exp.ShopID != nil {
			shopIDStr = exp.ShopID.String()
		}
		transactions = append(transactions, CashTransactionResponse{
			ID:                exp.ID.String(),
			UserID:            exp.CreatedByID.String(),
			ShopID:            shopIDStr,
			TransactionType:   "expense",
			Amount:            -exp.Amount, // Negative for outflow
			PreviousBalance:   0,
			NewBalance:        0,
			RelatedEntityType: "expense",
			RelatedEntityID:   exp.ID.String(),
			Description:       exp.Description,
			TransactionDate:   exp.ExpenseDate,
			CreatedAt:         exp.CreatedAt,
		})
	}

	// Query 3: Get transactions from cash_deposits
	var deposits []struct {
		ID          uuid.UUID `gorm:"column:id"`
		ShopID      uuid.UUID `gorm:"column:shop_id"`
		CreatedByID uuid.UUID `gorm:"column:created_by_id"`
		Amount      float64   `gorm:"column:amount"`
		Notes       string    `gorm:"column:notes"`
		DepositDate time.Time `gorm:"column:deposit_date"`
		CreatedAt   time.Time `gorm:"column:created_at"`
	}

	depositQuery := s.db.WithContext(ctx).
		Table("cash_deposits").
		Where("tenant_id = ? AND deposit_date BETWEEN ? AND ?", tenantID, startDate, endDate)

	if userID != nil {
		depositQuery = depositQuery.Where("created_by_id = ?", *userID)
	}
	if shopID != nil {
		depositQuery = depositQuery.Where("shop_id = ?", *shopID)
	}

	if err := depositQuery.Find(&deposits).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get cash deposits: %w", err)
	}

	for _, dep := range deposits {
		transactions = append(transactions, CashTransactionResponse{
			ID:                dep.ID.String(),
			UserID:            dep.CreatedByID.String(),
			ShopID:            dep.ShopID.String(),
			TransactionType:   "deposit",
			Amount:            -dep.Amount, // Negative for outflow (cash going to bank)
			PreviousBalance:   0,
			NewBalance:        0,
			RelatedEntityType: "cash_deposit",
			RelatedEntityID:   dep.ID.String(),
			Description:       dep.Notes,
			TransactionDate:   dep.DepositDate,
			CreatedAt:         dep.CreatedAt,
		})
	}

	// Query 4: Get transactions from cash_transactions table with user and counterparty names
	// This captures transactions created by updateCashHolding() from daily sales approvals
	// Uses raw SQL with JOINs to get UPI-like sender/receiver names
	var cashTxns []struct {
		ID               uuid.UUID  `gorm:"column:id"`
		UserID           uuid.UUID  `gorm:"column:user_id"`
		UserName         string     `gorm:"column:user_name"`
		TransactionType  string     `gorm:"column:transaction_type"`
		Amount           float64    `gorm:"column:amount"`
		BalanceBefore    float64    `gorm:"column:balance_before"`
		BalanceAfter     float64    `gorm:"column:balance_after"`
		RelatedType      string     `gorm:"column:related_type"`
		RelatedID        *uuid.UUID `gorm:"column:related_id"`
		Notes            string     `gorm:"column:notes"`
		CounterpartyID   *uuid.UUID `gorm:"column:counterparty_id"`
		CounterpartyName string     `gorm:"column:counterparty_name"`
		TransactionDate  time.Time  `gorm:"column:transaction_date"`
		CreatedAt        time.Time  `gorm:"column:created_at"`
	}

	// Build raw SQL query with JOINs to get user and counterparty names
	// MoneyCollection fields:
	//   - created_by = Requester (person who RECEIVES money)
	//   - executive_id = Target (person who SENDS money)
	// For collection_sent (user sent money): counterparty = created_by (who received it)
	// For collection_received (user received money): counterparty = executive_id (who sent it)
	baseQuery := `
		SELECT
			ct.id,
			ct.user_id,
			COALESCE(CONCAT(u.first_name, ' ', u.last_name), '') as user_name,
			ct.transaction_type,
			ct.amount,
			ct.balance_before,
			ct.balance_after,
			ct.related_type,
			ct.related_id,
			ct.notes,
			CASE
				WHEN ct.transaction_type = 'collection_sent' THEN mc.created_by
				WHEN ct.transaction_type = 'collection_received' THEN mc.executive_id
				ELSE NULL
			END as counterparty_id,
			CASE
				WHEN ct.transaction_type = 'collection_sent' THEN COALESCE(CONCAT(requester.first_name, ' ', requester.last_name), '')
				WHEN ct.transaction_type = 'collection_received' THEN COALESCE(CONCAT(target.first_name, ' ', target.last_name), '')
				ELSE ''
			END as counterparty_name,
			ct.transaction_date,
			ct.created_at
		FROM cash_transactions ct
		INNER JOIN users u ON ct.user_id = u.id
		LEFT JOIN money_collections mc ON ct.related_id = mc.id AND ct.related_type = 'money_collection'
		LEFT JOIN users requester ON mc.created_by = requester.id
		LEFT JOIN users target ON mc.executive_id = target.id
		WHERE ct.tenant_id = $1
		  AND ct.transaction_date BETWEEN $2 AND $3
		  AND ct.deleted_at IS NULL
	`

	var queryArgs []interface{}
	queryArgs = append(queryArgs, tenantID, startDate, endDate)

	if userID != nil {
		baseQuery += " AND ct.user_id = $4"
		queryArgs = append(queryArgs, *userID)
	}

	baseQuery += " ORDER BY ct.transaction_date DESC"

	if err := s.db.WithContext(ctx).Raw(baseQuery, queryArgs...).Scan(&cashTxns).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get cash transactions: %w", err)
	}

	for _, ct := range cashTxns {
		relatedIDStr := ""
		if ct.RelatedID != nil {
			relatedIDStr = ct.RelatedID.String()
		}
		counterpartyIDStr := ""
		if ct.CounterpartyID != nil {
			counterpartyIDStr = ct.CounterpartyID.String()
		}

		transactions = append(transactions, CashTransactionResponse{
			ID:                ct.ID.String(),
			UserID:            ct.UserID.String(),
			UserName:          ct.UserName,
			ShopID:            "", // cash_transactions doesn't have shop_id
			TransactionType:   ct.TransactionType,
			Amount:            ct.Amount,
			PreviousBalance:   ct.BalanceBefore,
			NewBalance:        ct.BalanceAfter,
			RelatedEntityType: ct.RelatedType,
			RelatedEntityID:   relatedIDStr,
			Description:       ct.Notes,
			CounterpartyID:    counterpartyIDStr,
			CounterpartyName:  ct.CounterpartyName,
			TransactionDate:   ct.TransactionDate,
			CreatedAt:         ct.CreatedAt,
		})
	}

	// Sort by transaction date descending
	for i := 0; i < len(transactions)-1; i++ {
		for j := i + 1; j < len(transactions); j++ {
			if transactions[j].TransactionDate.After(transactions[i].TransactionDate) {
				transactions[i], transactions[j] = transactions[j], transactions[i]
			}
		}
	}

	totalCount = int64(len(transactions))

	// Apply pagination
	if offset < len(transactions) {
		end := offset + limit
		if end > len(transactions) {
			end = len(transactions)
		}
		transactions = transactions[offset:end]
	} else {
		transactions = []CashTransactionResponse{}
	}

	return transactions, totalCount, nil
}
