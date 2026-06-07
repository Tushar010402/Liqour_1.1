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
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// DashboardService handles dashboard and reporting operations
type DashboardService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewDashboardService creates a new dashboard service
func NewDashboardService(db *database.DB, cache *cache.Cache) *DashboardService {
	return &DashboardService{
		db:    db,
		cache: cache,
	}
}

// applyTenantFilter conditionally applies tenant filtering for non-system admin users
func (s *DashboardService) applyTenantFilter(query *gorm.DB, tenantID uuid.UUID) *gorm.DB {
	if tenantID != uuid.Nil {
		return query.Where("tenant_id = ?", tenantID)
	}
	return query
}

// DashboardSummaryResponse represents dashboard summary data
type DashboardSummaryResponse struct {
	// Today's numbers
	TodaySales   DailySalesStats   `json:"todays_sales"`
	TodayReturns DailyReturnsStats `json:"todays_returns"`

	// Pending approvals
	PendingSales   int `json:"pending_sales"`
	PendingReturns int `json:"pending_returns"`

	// Financial summary
	TotalRevenue    float64 `json:"total_revenue"`
	TotalDue        float64 `json:"total_due"`
	CashAmount      float64 `json:"cash_amount"`
	CardAmount      float64 `json:"card_amount"`
	UpiAmount       float64 `json:"upi_amount"`
	CreditAmount    float64 `json:"credit_amount"`
	PurchaseAmount  float64 `json:"purchase_amount"`
	PurchaseCount   int     `json:"purchase_count"`
	ExpenseAmount   float64 `json:"expense_amount"`

	// Product coverage (for progress bar)
	UniqueProductsSold   int `json:"unique_products_sold"`
	TotalStockedProducts int `json:"total_stocked_products"`

	// Shop-wise breakdown
	ShopSummaries []ShopSummary `json:"shop_summaries"`

	// Top products
	TopProducts []TopProductSummary `json:"top_products"`

	// Recent activities
	RecentSales []RecentSaleActivity `json:"recent_sales"`

	// Generated at
	GeneratedAt time.Time `json:"generated_at"`
}

// DailySalesStats represents daily sales statistics
type DailySalesStats struct {
	TotalSales     int     `json:"total_sales"`
	TotalAmount    float64 `json:"total_amount"`
	ApprovedSales  int     `json:"approved_sales"`
	ApprovedAmount float64 `json:"approved_amount"`
	PendingSales   int     `json:"pending_sales"`
	PendingAmount  float64 `json:"pending_amount"`
}

// DailyReturnsStats represents daily returns statistics
type DailyReturnsStats struct {
	TotalReturns    int     `json:"total_returns"`
	TotalAmount     float64 `json:"total_amount"`
	ApprovedReturns int     `json:"approved_returns"`
	ApprovedAmount  float64 `json:"approved_amount"`
	PendingReturns  int     `json:"pending_returns"`
	PendingAmount   float64 `json:"pending_amount"`
}

// ShopSummary represents shop-wise summary
type ShopSummary struct {
	ShopID        uuid.UUID `json:"shop_id"`
	ShopName      string    `json:"shop_name"`
	TotalSales    int       `json:"total_sales"`
	TotalAmount   float64   `json:"total_amount"`
	PendingSales  int       `json:"pending_sales"`
	PendingAmount float64   `json:"pending_amount"`
}

// TopProductSummary represents top-selling products
type TopProductSummary struct {
	ProductID     uuid.UUID `json:"product_id"`
	ProductName   string    `json:"product_name"`
	BrandName     string    `json:"brand_name"`
	CategoryName  string    `json:"category_name"`
	TotalQuantity int       `json:"total_quantity"`
	TotalAmount   float64   `json:"total_amount"`
}

// RecentSaleActivity represents recent sale activities
type RecentSaleActivity struct {
	ID           uuid.UUID `json:"id"`
	Type         string    `json:"type"` // "sale", "return", "daily_record"
	Number       string    `json:"number"`
	ShopName     string    `json:"shop_name"`
	SalesmanName string    `json:"salesman_name"`
	Amount       float64   `json:"amount"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
}

// GetSalesmanShopID looks up the shop assigned to a salesman by user_id
func (s *DashboardService) GetSalesmanShopID(userID uuid.UUID) (*uuid.UUID, error) {
	var shopIDStr string
	err := s.db.Table("salesmen").
		Select("shop_id::text").
		Where("user_id = ? AND deleted_at IS NULL AND is_active = true", userID).
		Limit(1).
		Scan(&shopIDStr).Error
	if err != nil {
		return nil, err
	}
	if shopIDStr == "" {
		return nil, nil
	}
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		return nil, err
	}
	return &shopID, nil
}

// getDateRange converts a date_filter string to start/end time range
func (s *DashboardService) getDateRange(dateFilter, startDateStr, endDateStr string) (time.Time, time.Time) {
	now := time.Now()
	today := utils.StartOfDay(now)
	tomorrow := today.AddDate(0, 0, 1)

	switch dateFilter {
	case "custom":
		// Parse custom start_date and end_date (format: 2026-03-22)
		start, err1 := time.ParseInLocation("2006-01-02", startDateStr, now.Location())
		end, err2 := time.ParseInLocation("2006-01-02", endDateStr, now.Location())
		if err1 == nil && err2 == nil {
			// end_date is inclusive, so add 1 day
			return start, end.AddDate(0, 0, 1)
		}
		// Fallback to today if parsing fails
		return today, tomorrow
	case "yesterday":
		yesterday := today.AddDate(0, 0, -1)
		return yesterday, today
	case "last_7_days", "7days", "week":
		return today.AddDate(0, 0, -7), tomorrow
	case "last_30_days", "30days", "month":
		return today.AddDate(0, 0, -30), tomorrow
	case "this_month":
		monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
		return monthStart, tomorrow
	case "last_month":
		monthStart := time.Date(now.Year(), now.Month()-1, 1, 0, 0, 0, 0, now.Location())
		monthEnd := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
		return monthStart, monthEnd
	case "all_time", "all":
		return time.Date(2020, 1, 1, 0, 0, 0, 0, now.Location()), tomorrow
	default: // "today"
		return today, tomorrow
	}
}

// GetDashboardSummary returns dashboard summary for a tenant
func (s *DashboardService) GetDashboardSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, dateFilter, startDateStr, endDateStr string) (*DashboardSummaryResponse, error) {
	// Try to get from cache first
	cacheKey := fmt.Sprintf("dashboard_summary:%s:%s:%s:%s", tenantID.String(), dateFilter, startDateStr, endDateStr)
	if shopID != nil {
		cacheKey = fmt.Sprintf("dashboard_summary:%s:%s:%s:%s:%s", tenantID.String(), shopID.String(), dateFilter, startDateStr, endDateStr)
	}

	var cached DashboardSummaryResponse
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		// Return cached data if less than 5 minutes old
		if time.Since(cached.GeneratedAt) < 5*time.Minute {
			return &cached, nil
		}
	}

	// Generate fresh dashboard data
	summary := &DashboardSummaryResponse{
		GeneratedAt: time.Now(),
	}

	startDate, endDate := s.getDateRange(dateFilter, startDateStr, endDateStr)

	// Get sales stats for the date range
	if err := s.getTodaysSalesStats(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get sales stats: %w", err)
	}

	// Get returns stats for the date range
	if err := s.getTodaysReturnsStats(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get returns stats: %w", err)
	}

	// Get pending approvals count (always all-time, not filtered by date)
	if err := s.getPendingApprovalsCount(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get pending approvals: %w", err)
	}

	// Get financial summary for the date range
	if err := s.getFinancialSummary(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get financial summary: %w", err)
	}

	// Get shop-wise breakdown
	if shopID == nil { // Only for tenant-wide view
		if err := s.getShopSummaries(tenantID, startDate, endDate, summary); err != nil {
			return nil, fmt.Errorf("failed to get shop summaries: %w", err)
		}
	}

	// Get top products for the date range
	if err := s.getTopProducts(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get top products: %w", err)
	}

	// Get recent activities
	if err := s.getRecentActivities(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get recent activities: %w", err)
	}

	// Get product coverage stats (for progress bar)
	if err := s.getProductCoverage(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get product coverage: %w", err)
	}

	// Cache the result for 5 minutes
	s.cache.Set(ctx, cacheKey, summary, 5*time.Minute)

	return summary, nil
}

// getTodaysSalesStats gets today's sales statistics
func (s *DashboardService) getTodaysSalesStats(tenantID uuid.UUID, shopID *uuid.UUID, today, tomorrow time.Time, summary *DashboardSummaryResponse) error {
	// Daily sales records stats
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("record_date >= ? AND record_date < ?", today, tomorrow)

	// For non-system admin users, filter by tenant_id
	if tenantID != uuid.Nil {
		dailySalesQuery = dailySalesQuery.Where("tenant_id = ?", tenantID)
	}

	if shopID != nil {
		dailySalesQuery = dailySalesQuery.Where("shop_id = ?", *shopID)
	}

	var dailySalesStats struct {
		TotalRecords    int64   `gorm:"column:total_records"`
		TotalAmount     float64 `gorm:"column:total_amount"`
		ApprovedRecords int64   `gorm:"column:approved_records"`
		ApprovedAmount  float64 `gorm:"column:approved_amount"`
		PendingRecords  int64   `gorm:"column:pending_records"`
		PendingAmount   float64 `gorm:"column:pending_amount"`
	}

	// Query with actual status-based counts
	err := dailySalesQuery.Select(`
		COUNT(*) as total_records,
		COALESCE(SUM(total_sales_amount), 0) as total_amount,
		COUNT(CASE WHEN status = 'approved' THEN 1 END) as approved_records,
		COALESCE(SUM(CASE WHEN status = 'approved' THEN total_sales_amount ELSE 0 END), 0) as approved_amount,
		COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_records,
		COALESCE(SUM(CASE WHEN status = 'pending' THEN total_sales_amount ELSE 0 END), 0) as pending_amount
	`).Scan(&dailySalesStats).Error

	if err != nil {
		// If daily sales records query fails, use default values
		dailySalesStats = struct {
			TotalRecords    int64   `gorm:"column:total_records"`
			TotalAmount     float64 `gorm:"column:total_amount"`
			ApprovedRecords int64   `gorm:"column:approved_records"`
			ApprovedAmount  float64 `gorm:"column:approved_amount"`
			PendingRecords  int64   `gorm:"column:pending_records"`
			PendingAmount   float64 `gorm:"column:pending_amount"`
		}{0, 0, 0, 0, 0, 0}
	}

	// Individual sales stats (if any)
	individualSalesQuery := s.db.Model(&models.Sale{}).
		Where("sale_date >= ? AND sale_date < ?", today, tomorrow)

	// For non-system admin users, filter by tenant_id
	if tenantID != uuid.Nil {
		individualSalesQuery = individualSalesQuery.Where("tenant_id = ?", tenantID)
	}

	if shopID != nil {
		individualSalesQuery = individualSalesQuery.Where("shop_id = ?", *shopID)
	}

	var individualSalesStats struct {
		TotalSales     int64   `gorm:"column:total_sales"`
		TotalAmount    float64 `gorm:"column:total_amount"`
		ApprovedSales  int64   `gorm:"column:approved_sales"`
		ApprovedAmount float64 `gorm:"column:approved_amount"`
		PendingSales   int64   `gorm:"column:pending_sales"`
		PendingAmount  float64 `gorm:"column:pending_amount"`
	}

	// Query with actual status-based counts
	err = individualSalesQuery.Select(`
		COUNT(*) as total_sales,
		COALESCE(SUM(total_amount), 0) as total_amount,
		COUNT(CASE WHEN status = 'approved' THEN 1 END) as approved_sales,
		COALESCE(SUM(CASE WHEN status = 'approved' THEN total_amount ELSE 0 END), 0) as approved_amount,
		COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_sales,
		COALESCE(SUM(CASE WHEN status = 'pending' THEN total_amount ELSE 0 END), 0) as pending_amount
	`).Scan(&individualSalesStats).Error

	if err != nil {
		// If individual sales query fails, use default values
		individualSalesStats = struct {
			TotalSales     int64   `gorm:"column:total_sales"`
			TotalAmount    float64 `gorm:"column:total_amount"`
			ApprovedSales  int64   `gorm:"column:approved_sales"`
			ApprovedAmount float64 `gorm:"column:approved_amount"`
			PendingSales   int64   `gorm:"column:pending_sales"`
			PendingAmount  float64 `gorm:"column:pending_amount"`
		}{0, 0, 0, 0, 0, 0}
	}

	// Combine stats
	summary.TodaySales = DailySalesStats{
		TotalSales:     int(dailySalesStats.TotalRecords + individualSalesStats.TotalSales),
		TotalAmount:    dailySalesStats.TotalAmount + individualSalesStats.TotalAmount,
		ApprovedSales:  int(dailySalesStats.ApprovedRecords + individualSalesStats.ApprovedSales),
		ApprovedAmount: dailySalesStats.ApprovedAmount + individualSalesStats.ApprovedAmount,
		PendingSales:   int(dailySalesStats.PendingRecords + individualSalesStats.PendingSales),
		PendingAmount:  dailySalesStats.PendingAmount + individualSalesStats.PendingAmount,
	}

	return nil
}

// getTodaysReturnsStats gets today's returns statistics
func (s *DashboardService) getTodaysReturnsStats(tenantID uuid.UUID, shopID *uuid.UUID, today, tomorrow time.Time, summary *DashboardSummaryResponse) error {
	// Query returns for today
	returnsQuery := s.db.Model(&models.SaleReturn{}).
		Where("return_date >= ? AND return_date < ?", today, tomorrow)

	if tenantID != uuid.Nil {
		returnsQuery = returnsQuery.Where("tenant_id = ?", tenantID)
	}

	// Note: SaleReturn doesn't have shop_id directly - skip shop filtering for now
	// If shop filtering is needed, would require joining with sales table

	var returnsStats struct {
		TotalReturns    int64   `gorm:"column:total_returns"`
		TotalAmount     float64 `gorm:"column:total_amount"`
		ApprovedReturns int64   `gorm:"column:approved_returns"`
		ApprovedAmount  float64 `gorm:"column:approved_amount"`
		PendingReturns  int64   `gorm:"column:pending_returns"`
		PendingAmount   float64 `gorm:"column:pending_amount"`
	}

	err := returnsQuery.Select(`
		COUNT(*) as total_returns,
		COALESCE(SUM(total_amount), 0) as total_amount,
		COUNT(CASE WHEN status = 'approved' THEN 1 END) as approved_returns,
		COALESCE(SUM(CASE WHEN status = 'approved' THEN total_amount ELSE 0 END), 0) as approved_amount,
		COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_returns,
		COALESCE(SUM(CASE WHEN status = 'pending' THEN total_amount ELSE 0 END), 0) as pending_amount
	`).Scan(&returnsStats).Error

	if err != nil {
		// If query fails, use default values
		returnsStats = struct {
			TotalReturns    int64   `gorm:"column:total_returns"`
			TotalAmount     float64 `gorm:"column:total_amount"`
			ApprovedReturns int64   `gorm:"column:approved_returns"`
			ApprovedAmount  float64 `gorm:"column:approved_amount"`
			PendingReturns  int64   `gorm:"column:pending_returns"`
			PendingAmount   float64 `gorm:"column:pending_amount"`
		}{0, 0, 0, 0, 0, 0}
	}

	summary.TodayReturns = DailyReturnsStats{
		TotalReturns:    int(returnsStats.TotalReturns),
		TotalAmount:     returnsStats.TotalAmount,
		ApprovedReturns: int(returnsStats.ApprovedReturns),
		ApprovedAmount:  returnsStats.ApprovedAmount,
		PendingReturns:  int(returnsStats.PendingReturns),
		PendingAmount:   returnsStats.PendingAmount,
	}

	return nil
}

// getPendingApprovalsCount gets count of pending approvals (total across all time, not just today)
func (s *DashboardService) getPendingApprovalsCount(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	// Count pending daily sales records
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("status = ?", "pending")

	if tenantID != uuid.Nil {
		dailySalesQuery = dailySalesQuery.Where("tenant_id = ?", tenantID)
	}

	if shopID != nil {
		dailySalesQuery = dailySalesQuery.Where("shop_id = ?", *shopID)
	}

	var pendingDailyRecords int64
	if err := dailySalesQuery.Count(&pendingDailyRecords).Error; err != nil {
		pendingDailyRecords = 0
	}

	// Count pending individual sales
	individualSalesQuery := s.db.Model(&models.Sale{}).
		Where("status = ?", "pending")

	if tenantID != uuid.Nil {
		individualSalesQuery = individualSalesQuery.Where("tenant_id = ?", tenantID)
	}

	if shopID != nil {
		individualSalesQuery = individualSalesQuery.Where("shop_id = ?", *shopID)
	}

	var pendingIndividualSales int64
	if err := individualSalesQuery.Count(&pendingIndividualSales).Error; err != nil {
		pendingIndividualSales = 0
	}

	// Count pending returns
	returnsQuery := s.db.Model(&models.SaleReturn{}).
		Where("status = ?", "pending")

	if tenantID != uuid.Nil {
		returnsQuery = returnsQuery.Where("tenant_id = ?", tenantID)
	}

	// Note: SaleReturn doesn't have shop_id directly, need to join with Sale table if filtering by shop
	// For now, we skip shop filtering on returns since they're linked to sales

	var pendingReturns int64
	if err := returnsQuery.Count(&pendingReturns).Error; err != nil {
		pendingReturns = 0
	}

	// Total pending sales = daily records + individual sales
	summary.PendingSales = int(pendingDailyRecords + pendingIndividualSales)
	summary.PendingReturns = int(pendingReturns)

	return nil
}

// getFinancialSummary gets financial summary for the given date range
func (s *DashboardService) getFinancialSummary(tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time, summary *DashboardSummaryResponse) error {
	// Get basic revenue from daily sales records
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("record_date >= ? AND record_date < ?", startDate, endDate)

	// Apply tenant filtering for non-system admin users
	if tenantID != uuid.Nil {
		dailySalesQuery = dailySalesQuery.Where("tenant_id = ?", tenantID)
	}

	if shopID != nil {
		dailySalesQuery = dailySalesQuery.Where("shop_id = ?", *shopID)
	}

	var dailyRevenue float64
	err := dailySalesQuery.Select("COALESCE(SUM(total_sales_amount), 0)").Scan(&dailyRevenue).Error
	if err != nil {
		dailyRevenue = 0 // Default to 0 if query fails
	}

	// Get revenue from individual sales
	salesQuery := s.db.Model(&models.Sale{}).
		Where("sale_date >= ? AND sale_date < ?", startDate, endDate)

	// Apply tenant filtering for non-system admin users
	if tenantID != uuid.Nil {
		salesQuery = salesQuery.Where("tenant_id = ?", tenantID)
	}

	if shopID != nil {
		salesQuery = salesQuery.Where("shop_id = ?", *shopID)
	}

	var salesRevenue float64
	err = salesQuery.Select("COALESCE(SUM(total_amount), 0)").Scan(&salesRevenue).Error
	if err != nil {
		salesRevenue = 0 // Default to 0 if query fails
	}

	// Get purchase totals for the date range from stock_purchases
	purchaseQuery := s.db.Table("stock_purchases").
		Where("purchase_date >= ? AND purchase_date < ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if tenantID != uuid.Nil {
		purchaseQuery = purchaseQuery.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		purchaseQuery = purchaseQuery.Where("shop_id = ?", *shopID)
	}

	var purchaseResult struct {
		Amount float64 `gorm:"column:amount"`
		Count  int     `gorm:"column:count"`
	}
	if err := purchaseQuery.Select("COALESCE(SUM(total_amount), 0) as amount, COUNT(*) as count").Scan(&purchaseResult).Error; err != nil {
		purchaseResult.Amount = 0
		purchaseResult.Count = 0
	}

	// Get expense totals for the date range from expenses
	expenseQuery := s.db.Table("expenses").
		Where("expense_date >= ? AND expense_date < ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if tenantID != uuid.Nil {
		expenseQuery = expenseQuery.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		expenseQuery = expenseQuery.Where("shop_id = ?", *shopID)
	}

	var expenseAmount float64
	if err := expenseQuery.Select("COALESCE(SUM(amount), 0)").Scan(&expenseAmount).Error; err != nil {
		expenseAmount = 0
	}

	// Get payment method breakdown from daily sales records
	paymentQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("record_date >= ? AND record_date < ?", startDate, endDate)
	if tenantID != uuid.Nil {
		paymentQuery = paymentQuery.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		paymentQuery = paymentQuery.Where("shop_id = ?", *shopID)
	}

	var paymentBreakdown struct {
		CashAmount   float64 `gorm:"column:cash_amount"`
		CardAmount   float64 `gorm:"column:card_amount"`
		UpiAmount    float64 `gorm:"column:upi_amount"`
		CreditAmount float64 `gorm:"column:credit_amount"`
	}
	if err := paymentQuery.Select(`
		COALESCE(SUM(total_cash_amount), 0) as cash_amount,
		COALESCE(SUM(total_card_amount), 0) as card_amount,
		COALESCE(SUM(total_upi_amount), 0) as upi_amount,
		COALESCE(SUM(total_credit_amount), 0) as credit_amount
	`).Scan(&paymentBreakdown).Error; err != nil {
		paymentBreakdown.CashAmount = 0
		paymentBreakdown.CardAmount = 0
		paymentBreakdown.UpiAmount = 0
		paymentBreakdown.CreditAmount = 0
	}

	// Check for day-closing records (manual reconciliation from salesman)
	dayClosingQuery := s.db.Model(&models.DayClosingRecord{}).
		Where("date >= ? AND date < ? AND deleted_at IS NULL", startDate, endDate)
	if tenantID != uuid.Nil {
		dayClosingQuery = dayClosingQuery.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		dayClosingQuery = dayClosingQuery.Where("shop_id = ?", *shopID)
	}

	var dayClosingTotals struct {
		CashTotal    float64 `gorm:"column:cash_total"`
		UpiTotal     float64 `gorm:"column:upi_total"`
		ExpenseTotal float64 `gorm:"column:expense_total"`
	}
	hasDayClosing := false
	if err := dayClosingQuery.Select(`
		COALESCE(SUM(cash_total), 0) as cash_total,
		COALESCE(SUM(upi_total), 0) as upi_total,
		COALESCE(SUM(expense_total), 0) as expense_total
	`).Scan(&dayClosingTotals).Error; err == nil {
		if dayClosingTotals.CashTotal > 0 || dayClosingTotals.UpiTotal > 0 || dayClosingTotals.ExpenseTotal > 0 {
			hasDayClosing = true
		}
	}

	// Set financial summary
	summary.TotalRevenue = dailyRevenue + salesRevenue
	summary.TotalDue = 0
	summary.PurchaseAmount = purchaseResult.Amount
	summary.PurchaseCount = purchaseResult.Count

	if hasDayClosing {
		// Use day-closing data: expenses reduce cash in hand
		summary.CashAmount = dayClosingTotals.CashTotal - dayClosingTotals.ExpenseTotal
		if summary.CashAmount < 0 {
			summary.CashAmount = 0
		}
		summary.UpiAmount = dayClosingTotals.UpiTotal
		summary.ExpenseAmount = dayClosingTotals.ExpenseTotal
		summary.CardAmount = paymentBreakdown.CardAmount
		summary.CreditAmount = paymentBreakdown.CreditAmount
	} else {
		// Fallback: use payment breakdown from daily sales records
		summary.CashAmount = paymentBreakdown.CashAmount
		summary.CardAmount = paymentBreakdown.CardAmount
		summary.UpiAmount = paymentBreakdown.UpiAmount
		summary.CreditAmount = paymentBreakdown.CreditAmount
		summary.ExpenseAmount = expenseAmount
	}

	return nil
}

// getShopSummaries gets shop-wise summaries
func (s *DashboardService) getShopSummaries(tenantID uuid.UUID, today, tomorrow time.Time, summary *DashboardSummaryResponse) error {
	// For new users, return empty shop summaries for now
	// This will be implemented when shop management is fully set up
	summary.ShopSummaries = []ShopSummary{}
	return nil
}

// getTopProducts gets top-selling products for current month
func (s *DashboardService) getTopProducts(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	// For new users, return empty top products for now
	// This will be implemented when product and sales item tracking is fully set up
	summary.TopProducts = []TopProductSummary{}
	return nil
}

// getRecentActivities gets recent sale activities
func (s *DashboardService) getRecentActivities(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	// For new users, return empty recent activities for now
	// This will be implemented when activity tracking is fully set up
	summary.RecentSales = []RecentSaleActivity{}
	return nil
}

// getProductCoverage calculates unique category+size-range "packs" sold vs
// total stocked category+size-range packs.
//
// Definition of a "pack" — matches the user's mental model and mirrors
// the SizeRangeConstants groups the Flutter app uses everywhere else:
//
//   A pack is one unique (category_id, size_range_bucket) tuple that the
//   shop has in stock. A shop stocking whisky 750ml AND whisky 700ml
//   counts as ONE whisky pack — both sizes fall in the same "750ml
//   (Full)" bucket. Beer uses a different set of buckets (330ml, 500ml,
//   650ml, Keg/Bulk). Unique-size-string counting (the prior approach)
//   over-counted when a shop had close-but-not-identical sizes in the
//   same range.
//
// Buckets mirror SizeRangeConstants.dart:
//   Non-beer (whisky / rum / vodka / etc.):
//     1-100     → 90ml
//     101-250   → 180ml
//     251-400   → 375ml
//     401-999   → 750ml
//     1000+     → 1L+
//   Beer:
//     1-400     → 330ml & Below
//     401-550   → 500ml
//     551-999   → 650ml
//     1000+     → Keg/Bulk
//
// Implementation note: the bucketing runs in Go (not SQL) because the
// rules depend on category being "beer" vs not. Doing it in SQL would
// need a big CASE WHEN with a LIKE '%beer%' join — more fragile. Fetch
// the raw (category_name, size) rows and map in the worker. For any
// reasonable shop the set is small (tens of rows), so the extra DB
// round-trip is worth the readability.
func (s *DashboardService) getProductCoverage(tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time, summary *DashboardSummaryResponse) error {
	// Denominator: distinct (category_id, size_range_bucket) the shop stocks.
	var stockRows []struct {
		CategoryID   string
		CategoryName string
		Size         string
	}
	{
		args := []interface{}{}
		sql := `SELECT DISTINCT products.category_id::text AS category_id,
		                 COALESCE(categories.name, '') AS category_name,
		                 products.size
		        FROM stocks
		        JOIN products ON products.id = stocks.product_id
		        LEFT JOIN categories ON categories.id = products.category_id
		        WHERE stocks.quantity > 0
		          AND stocks.deleted_at IS NULL
		          AND products.size IS NOT NULL AND products.size != ''`
		if tenantID != uuid.Nil {
			sql += " AND stocks.tenant_id = ?"
			args = append(args, tenantID)
		}
		if shopID != nil {
			sql += " AND stocks.shop_id = ?"
			args = append(args, *shopID)
		}
		if err := s.db.Raw(sql, args...).Scan(&stockRows).Error; err != nil {
			stockRows = nil
		}
	}
	// Group identity: "english" (all non-beer categories together) OR
	// "beer". Size doesn't subdivide the count — the user's mental model
	// is "1 slot for English, 1 for Beer", regardless of how many size
	// buckets the shop actually stocks under each. Matches the English
	// chip semantics used in Inventory + DSE. So a shop with Gin 750ml
	// + Vodka 750ml + Whisky 180ml + Whisky 375ml + Whisky 750ml = ONE
	// English slot. Add beer stock → total becomes 2.
	stockedPacks := map[string]struct{}{}
	for _, r := range stockRows {
		stockedPacks[salesGroupLabel(r.CategoryName)] = struct{}{}
	}
	summary.TotalStockedProducts = len(stockedPacks)

	// Numerator: distinct (category_id, size_range_bucket) sold in the window.
	var soldRows []struct {
		CategoryID   string
		CategoryName string
		Size         string
	}
	{
		args := []interface{}{startDate, endDate}
		sql := `SELECT DISTINCT products.category_id::text AS category_id,
		                 COALESCE(categories.name, '') AS category_name,
		                 products.size
		        FROM daily_sales_items
		        JOIN daily_sales_records ON daily_sales_records.id = daily_sales_items.daily_sales_record_id
		        JOIN products ON products.id = daily_sales_items.product_id
		        LEFT JOIN categories ON categories.id = products.category_id
		        WHERE daily_sales_records.record_date >= ?
		          AND daily_sales_records.record_date < ?
		          AND daily_sales_items.deleted_at IS NULL
		          AND daily_sales_records.deleted_at IS NULL
		          AND products.size IS NOT NULL AND products.size != ''`
		if tenantID != uuid.Nil {
			sql += " AND daily_sales_records.tenant_id = ?"
			args = append(args, tenantID)
		}
		if shopID != nil {
			sql += " AND daily_sales_records.shop_id = ?"
			args = append(args, *shopID)
		}
		if err := s.db.Raw(sql, args...).Scan(&soldRows).Error; err != nil {
			soldRows = nil
		}
	}
	soldPacks := map[string]struct{}{}
	for _, r := range soldRows {
		soldPacks[salesGroupLabel(r.CategoryName)] = struct{}{}
	}
	summary.UniqueProductsSold = len(soldPacks)

	return nil
}

// sizeRangeBucket returns the SizeRangeConstants bucket label for a given
// size string + category. Mirrors Flutter's SizeRangeConstants so the home
// progress bar, Add Missing filters, and AI extraction all agree on which
// "pack" a product belongs to.
//
// The extractMl helper handles common forms: "750ML", "750 ml", "1L",
// "700ml" → numeric ml. For "1L"-style labels (no "ml"), a number < 100
// is treated as litres (500 is unchanged; 1 → 1000).
func sizeRangeBucket(categoryName, size string) string {
	ml := extractSizeMl(size)
	isBeer := strings.Contains(strings.ToLower(categoryName), "beer")
	if isBeer {
		switch {
		case ml <= 400:
			return "330ml & Below"
		case ml <= 550:
			return "500ml"
		case ml <= 999:
			return "650ml"
		default:
			return "Keg/Bulk"
		}
	}
	switch {
	case ml <= 100:
		return "90ml"
	case ml <= 250:
		return "180ml"
	case ml <= 400:
		return "375ml"
	case ml <= 999:
		return "750ml"
	default:
		return "1L+"
	}
}

// salesGroupLabel returns "beer" for beer-category products and "english"
// for everything else. Mirrors the "English chip = not Beer" convention
// used in Inventory + DSE — a single non-beer bucket means Gin + Vodka +
// Whisky + Rum + Brandy all share one slot per size bucket, matching how
// users mentally group their catalog (English vs Beer).
func salesGroupLabel(categoryName string) string {
	if strings.Contains(strings.ToLower(categoryName), "beer") {
		return "beer"
	}
	return "english"
}

// extractSizeMl parses a size string into milliliters. Matches Flutter's
// SizeRangeConstants.extractMl semantics: strip non-digits, then upgrade
// small numbers with a bare "L" suffix (no "ML") from litres to ml.
func extractSizeMl(size string) int {
	digits := make([]byte, 0, len(size))
	for i := 0; i < len(size); i++ {
		c := size[i]
		if c >= '0' && c <= '9' {
			digits = append(digits, c)
		}
	}
	if len(digits) == 0 {
		return 0
	}
	n := 0
	for _, c := range digits {
		n = n*10 + int(c-'0')
	}
	upper := strings.ToUpper(size)
	if strings.Contains(upper, "L") && !strings.Contains(upper, "ML") && n < 100 {
		return n * 1000
	}
	return n
}
