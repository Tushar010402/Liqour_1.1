package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
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

// DashboardSummaryResponse represents dashboard summary data
type DashboardSummaryResponse struct {
	// Today's numbers
	TodaySales       DailySalesStats    `json:"todays_sales"`
	TodayReturns     DailyReturnsStats  `json:"todays_returns"`
	
	// Pending approvals
	PendingSales     int                `json:"pending_sales"`
	PendingReturns   int                `json:"pending_returns"`
	
	// Financial summary
	TotalRevenue     float64            `json:"total_revenue"`
	TotalDue         float64            `json:"total_due"`
	CashAmount       float64            `json:"cash_amount"`
	CardAmount       float64            `json:"card_amount"`
	UpiAmount        float64            `json:"upi_amount"`
	CreditAmount     float64            `json:"credit_amount"`
	
	// Shop-wise breakdown
	ShopSummaries    []ShopSummary      `json:"shop_summaries"`
	
	// Top products
	TopProducts      []TopProductSummary `json:"top_products"`
	
	// Recent activities
	RecentSales      []RecentSaleActivity `json:"recent_sales"`
	
	// Generated at
	GeneratedAt      time.Time          `json:"generated_at"`
}

// DailySalesStats represents daily sales statistics
type DailySalesStats struct {
	TotalSales       int     `json:"total_sales"`
	TotalAmount      float64 `json:"total_amount"`
	ApprovedSales    int     `json:"approved_sales"`
	ApprovedAmount   float64 `json:"approved_amount"`
	PendingSales     int     `json:"pending_sales"`
	PendingAmount    float64 `json:"pending_amount"`
}

// DailyReturnsStats represents daily returns statistics
type DailyReturnsStats struct {
	TotalReturns     int     `json:"total_returns"`
	TotalAmount      float64 `json:"total_amount"`
	ApprovedReturns  int     `json:"approved_returns"`
	ApprovedAmount   float64 `json:"approved_amount"`
	PendingReturns   int     `json:"pending_returns"`
	PendingAmount    float64 `json:"pending_amount"`
}

// ShopSummary represents shop-wise summary
type ShopSummary struct {
	ShopID           uuid.UUID `json:"shop_id"`
	ShopName         string    `json:"shop_name"`
	TotalSales       int       `json:"total_sales"`
	TotalAmount      float64   `json:"total_amount"`
	PendingSales     int       `json:"pending_sales"`
	PendingAmount    float64   `json:"pending_amount"`
}

// TopProductSummary represents top-selling products
type TopProductSummary struct {
	ProductID        uuid.UUID `json:"product_id"`
	ProductName      string    `json:"product_name"`
	BrandName        string    `json:"brand_name"`
	CategoryName     string    `json:"category_name"`
	TotalQuantity    int       `json:"total_quantity"`
	TotalAmount      float64   `json:"total_amount"`
}

// RecentSaleActivity represents recent sale activities
type RecentSaleActivity struct {
	ID               uuid.UUID  `json:"id"`
	Type             string     `json:"type"` // "sale", "return", "daily_record"
	Number           string     `json:"number"`
	ShopName         string     `json:"shop_name"`
	SalesmanName     string     `json:"salesman_name"`
	Amount           float64    `json:"amount"`
	Status           string     `json:"status"`
	CreatedAt        time.Time  `json:"created_at"`
}

// GetDashboardSummary returns dashboard summary for a tenant
func (s *DashboardService) GetDashboardSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) (*DashboardSummaryResponse, error) {
	// Try to get from cache first
	cacheKey := fmt.Sprintf("dashboard_summary:%s", tenantID.String())
	if shopID != nil {
		cacheKey = fmt.Sprintf("dashboard_summary:%s:%s", tenantID.String(), shopID.String())
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

	today := utils.StartOfDay(time.Now())
	tomorrow := today.AddDate(0, 0, 1)

	// Get today's sales stats
	if err := s.getTodaysSalesStats(tenantID, shopID, today, tomorrow, summary); err != nil {
		return nil, fmt.Errorf("failed to get today's sales stats: %w", err)
	}

	// Get today's returns stats
	if err := s.getTodaysReturnsStats(tenantID, shopID, today, tomorrow, summary); err != nil {
		return nil, fmt.Errorf("failed to get today's returns stats: %w", err)
	}

	// Get pending approvals count
	if err := s.getPendingApprovalsCount(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get pending approvals: %w", err)
	}

	// Get financial summary (this month)
	if err := s.getFinancialSummary(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get financial summary: %w", err)
	}

	// Get shop-wise breakdown
	if shopID == nil { // Only for tenant-wide view
		if err := s.getShopSummaries(tenantID, today, tomorrow, summary); err != nil {
			return nil, fmt.Errorf("failed to get shop summaries: %w", err)
		}
	}

	// Get top products (this month)
	if err := s.getTopProducts(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get top products: %w", err)
	}

	// Get recent activities
	if err := s.getRecentActivities(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get recent activities: %w", err)
	}

	// Cache the result for 5 minutes
	s.cache.Set(ctx, cacheKey, summary, 5*time.Minute)

	return summary, nil
}

// getTodaysSalesStats gets today's sales statistics
func (s *DashboardService) getTodaysSalesStats(tenantID uuid.UUID, shopID *uuid.UUID, today, tomorrow time.Time, summary *DashboardSummaryResponse) error {
	// Daily sales records stats
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("tenant_id = ? AND record_date >= ? AND record_date < ?", tenantID, today, tomorrow)
	
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

	err := dailySalesQuery.Select(`
		COUNT(*) as total_records,
		COALESCE(SUM(total_sales_amount), 0) as total_amount,
		COUNT(CASE WHEN status = ? THEN 1 END) as approved_records,
		COALESCE(SUM(CASE WHEN status = ? THEN total_sales_amount END), 0) as approved_amount,
		COUNT(CASE WHEN status = ? THEN 1 END) as pending_records,
		COALESCE(SUM(CASE WHEN status = ? THEN total_sales_amount END), 0) as pending_amount
	`, models.StatusApproved, models.StatusApproved, models.StatusPending, models.StatusPending).
		Scan(&dailySalesStats).Error

	if err != nil {
		return err
	}

	// Individual sales stats (if any)
	individualSalesQuery := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND sale_date >= ? AND sale_date < ?", tenantID, today, tomorrow)
	
	if shopID != nil {
		individualSalesQuery = individualSalesQuery.Where("shop_id = ?", *shopID)
	}

	var individualSalesStats struct {
		TotalSales      int64   `gorm:"column:total_sales"`
		TotalAmount     float64 `gorm:"column:total_amount"`
		ApprovedSales   int64   `gorm:"column:approved_sales"`
		ApprovedAmount  float64 `gorm:"column:approved_amount"`
		PendingSales    int64   `gorm:"column:pending_sales"`
		PendingAmount   float64 `gorm:"column:pending_amount"`
	}

	err = individualSalesQuery.Select(`
		COUNT(*) as total_sales,
		COALESCE(SUM(total_amount), 0) as total_amount,
		COUNT(CASE WHEN status = ? THEN 1 END) as approved_sales,
		COALESCE(SUM(CASE WHEN status = ? THEN total_amount END), 0) as approved_amount,
		COUNT(CASE WHEN status = ? THEN 1 END) as pending_sales,
		COALESCE(SUM(CASE WHEN status = ? THEN total_amount END), 0) as pending_amount
	`, models.StatusApproved, models.StatusApproved, models.StatusPending, models.StatusPending).
		Scan(&individualSalesStats).Error

	if err != nil {
		return err
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
	query := s.db.Model(&models.SaleReturn{}).
		Where("tenant_id = ? AND return_date >= ? AND return_date < ?", tenantID, today, tomorrow)

	if shopID != nil {
		query = query.Joins("JOIN sales ON sale_returns.sale_id = sales.id").
			Where("sales.shop_id = ?", *shopID)
	}

	var returnsStats struct {
		TotalReturns    int64   `gorm:"column:total_returns"`
		TotalAmount     float64 `gorm:"column:total_amount"`
		ApprovedReturns int64   `gorm:"column:approved_returns"`
		ApprovedAmount  float64 `gorm:"column:approved_amount"`
		PendingReturns  int64   `gorm:"column:pending_returns"`
		PendingAmount   float64 `gorm:"column:pending_amount"`
	}

	err := query.Select(`
		COUNT(*) as total_returns,
		COALESCE(SUM(return_amount), 0) as total_amount,
		COUNT(CASE WHEN sale_returns.status = ? THEN 1 END) as approved_returns,
		COALESCE(SUM(CASE WHEN sale_returns.status = ? THEN return_amount END), 0) as approved_amount,
		COUNT(CASE WHEN sale_returns.status = ? THEN 1 END) as pending_returns,
		COALESCE(SUM(CASE WHEN sale_returns.status = ? THEN return_amount END), 0) as pending_amount
	`, models.StatusApproved, models.StatusApproved, models.StatusPending, models.StatusPending).
		Scan(&returnsStats).Error

	if err != nil {
		return err
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

// getPendingApprovalsCount gets count of pending approvals
func (s *DashboardService) getPendingApprovalsCount(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	// Count pending daily sales records
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("tenant_id = ? AND status = ?", tenantID, models.StatusPending)
	
	if shopID != nil {
		dailySalesQuery = dailySalesQuery.Where("shop_id = ?", *shopID)
	}

	var pendingDailySales int64
	if err := dailySalesQuery.Count(&pendingDailySales).Error; err != nil {
		return err
	}

	// Count pending individual sales
	salesQuery := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND status = ?", tenantID, models.StatusPending)
	
	if shopID != nil {
		salesQuery = salesQuery.Where("shop_id = ?", *shopID)
	}

	var pendingSales int64
	if err := salesQuery.Count(&pendingSales).Error; err != nil {
		return err
	}

	// Count pending returns
	returnsQuery := s.db.Model(&models.SaleReturn{}).
		Where("tenant_id = ? AND status = ?", tenantID, models.StatusPending)

	if shopID != nil {
		returnsQuery = returnsQuery.Joins("JOIN sales ON sale_returns.sale_id = sales.id").
			Where("sales.shop_id = ?", *shopID)
	}

	var pendingReturns int64
	if err := returnsQuery.Count(&pendingReturns).Error; err != nil {
		return err
	}

	summary.PendingSales = int(pendingDailySales + pendingSales)
	summary.PendingReturns = int(pendingReturns)

	return nil
}

// getFinancialSummary gets financial summary for current month
func (s *DashboardService) getFinancialSummary(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	now := time.Now()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	monthEnd := monthStart.AddDate(0, 1, 0)

	// Get financial summary from daily sales records
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("tenant_id = ? AND status = ? AND record_date >= ? AND record_date < ?", 
			tenantID, models.StatusApproved, monthStart, monthEnd)
	
	if shopID != nil {
		dailySalesQuery = dailySalesQuery.Where("shop_id = ?", *shopID)
	}

	var dailyFinancial struct {
		TotalRevenue  float64 `gorm:"column:total_revenue"`
		CashAmount    float64 `gorm:"column:cash_amount"`
		CardAmount    float64 `gorm:"column:card_amount"`
		UpiAmount     float64 `gorm:"column:upi_amount"`
		CreditAmount  float64 `gorm:"column:credit_amount"`
	}

	err := dailySalesQuery.Select(`
		COALESCE(SUM(total_sales_amount), 0) as total_revenue,
		COALESCE(SUM(total_cash_amount), 0) as cash_amount,
		COALESCE(SUM(total_card_amount), 0) as card_amount,
		COALESCE(SUM(total_upi_amount), 0) as upi_amount,
		COALESCE(SUM(total_credit_amount), 0) as credit_amount
	`).Scan(&dailyFinancial).Error

	if err != nil {
		return err
	}

	// Get due amount from individual sales
	salesQuery := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND status = ? AND sale_date >= ? AND sale_date < ?", 
			tenantID, models.StatusApproved, monthStart, monthEnd)
	
	if shopID != nil {
		salesQuery = salesQuery.Where("shop_id = ?", *shopID)
	}

	var salesFinancial struct {
		TotalRevenue  float64 `gorm:"column:total_revenue"`
		TotalDue      float64 `gorm:"column:total_due"`
	}

	err = salesQuery.Select(`
		COALESCE(SUM(total_amount), 0) as total_revenue,
		COALESCE(SUM(due_amount), 0) as total_due
	`).Scan(&salesFinancial).Error

	if err != nil {
		return err
	}

	summary.TotalRevenue = dailyFinancial.TotalRevenue + salesFinancial.TotalRevenue
	summary.TotalDue = salesFinancial.TotalDue + dailyFinancial.CreditAmount
	summary.CashAmount = dailyFinancial.CashAmount
	summary.CardAmount = dailyFinancial.CardAmount
	summary.UpiAmount = dailyFinancial.UpiAmount
	summary.CreditAmount = dailyFinancial.CreditAmount

	return nil
}

// getShopSummaries gets shop-wise summaries
func (s *DashboardService) getShopSummaries(tenantID uuid.UUID, today, tomorrow time.Time, summary *DashboardSummaryResponse) error {
	// Get shop summaries from daily sales records
	var shopSummaries []ShopSummary
	
	err := s.db.Model(&models.DailySalesRecord{}).
		Select(`
			shops.id as shop_id,
			shops.name as shop_name,
			COUNT(*) as total_sales,
			COALESCE(SUM(daily_sales_records.total_sales_amount), 0) as total_amount,
			COUNT(CASE WHEN daily_sales_records.status = ? THEN 1 END) as pending_sales,
			COALESCE(SUM(CASE WHEN daily_sales_records.status = ? THEN daily_sales_records.total_sales_amount END), 0) as pending_amount
		`, models.StatusPending, models.StatusPending).
		Joins("JOIN shops ON daily_sales_records.shop_id = shops.id").
		Where("daily_sales_records.tenant_id = ? AND daily_sales_records.record_date >= ? AND daily_sales_records.record_date < ?", 
			tenantID, today, tomorrow).
		Group("shops.id, shops.name").
		Scan(&shopSummaries).Error

	if err != nil {
		return err
	}

	summary.ShopSummaries = shopSummaries
	return nil
}

// getTopProducts gets top-selling products for current month
func (s *DashboardService) getTopProducts(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	now := time.Now()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	monthEnd := monthStart.AddDate(0, 1, 0)

	query := s.db.Model(&models.DailySalesItem{}).
		Select(`
			products.id as product_id,
			products.name as product_name,
			brands.name as brand_name,
			categories.name as category_name,
			SUM(daily_sales_items.quantity) as total_quantity,
			SUM(daily_sales_items.total_amount) as total_amount
		`).
		Joins("JOIN daily_sales_records ON daily_sales_items.daily_sales_record_id = daily_sales_records.id").
		Joins("JOIN products ON daily_sales_items.product_id = products.id").
		Joins("LEFT JOIN brands ON products.brand_id = brands.id").
		Joins("LEFT JOIN categories ON products.category_id = categories.id").
		Where("daily_sales_items.tenant_id = ? AND daily_sales_records.status = ? AND daily_sales_records.record_date >= ? AND daily_sales_records.record_date < ?", 
			tenantID, models.StatusApproved, monthStart, monthEnd)

	if shopID != nil {
		query = query.Where("daily_sales_records.shop_id = ?", *shopID)
	}

	var topProducts []TopProductSummary
	err := query.Group("products.id, products.name, brands.name, categories.name").
		Order("total_quantity DESC").
		Limit(10).
		Scan(&topProducts).Error

	if err != nil {
		return err
	}

	summary.TopProducts = topProducts
	return nil
}

// getRecentActivities gets recent sale activities
func (s *DashboardService) getRecentActivities(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	var activities []RecentSaleActivity

	// Get recent daily sales records
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Select(`
			daily_sales_records.id,
			'daily_record' as type,
			CONCAT('DSR-', TO_CHAR(daily_sales_records.record_date, 'YYYY-MM-DD')) as number,
			shops.name as shop_name,
			COALESCE(salesmen.name, '') as salesman_name,
			daily_sales_records.total_sales_amount as amount,
			daily_sales_records.status,
			daily_sales_records.created_at
		`).
		Joins("JOIN shops ON daily_sales_records.shop_id = shops.id").
		Joins("LEFT JOIN salesmen ON daily_sales_records.salesman_id = salesmen.id").
		Where("daily_sales_records.tenant_id = ?", tenantID)

	if shopID != nil {
		dailySalesQuery = dailySalesQuery.Where("daily_sales_records.shop_id = ?", *shopID)
	}

	var dailyActivities []RecentSaleActivity
	if err := dailySalesQuery.Order("daily_sales_records.created_at DESC").Limit(5).Scan(&dailyActivities).Error; err != nil {
		return err
	}

	activities = append(activities, dailyActivities...)

	// Get recent individual sales
	salesQuery := s.db.Model(&models.Sale{}).
		Select(`
			sales.id,
			'sale' as type,
			sales.sale_number as number,
			shops.name as shop_name,
			COALESCE(salesmen.name, '') as salesman_name,
			sales.total_amount as amount,
			sales.status,
			sales.created_at
		`).
		Joins("JOIN shops ON sales.shop_id = shops.id").
		Joins("LEFT JOIN salesmen ON sales.salesman_id = salesmen.id").
		Where("sales.tenant_id = ?", tenantID)

	if shopID != nil {
		salesQuery = salesQuery.Where("sales.shop_id = ?", *shopID)
	}

	var salesActivities []RecentSaleActivity
	if err := salesQuery.Order("sales.created_at DESC").Limit(5).Scan(&salesActivities).Error; err != nil {
		return err
	}

	activities = append(activities, salesActivities...)

	// Sort all activities by created_at desc and take top 10
	if len(activities) > 10 {
		// Simple sort - in production, you might want to sort in the database
		activities = activities[:10]
	}

	summary.RecentSales = activities
	return nil
}