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
	TotalRevenue float64 `json:"total_revenue"`
	TotalDue     float64 `json:"total_due"`
	CashAmount   float64 `json:"cash_amount"`
	CardAmount   float64 `json:"card_amount"`
	UpiAmount    float64 `json:"upi_amount"`
	CreditAmount float64 `json:"credit_amount"`

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

	// Simplified query for existing table structure - treat all records as approved for now
	err := dailySalesQuery.Select(`
		COUNT(*) as total_records,
		COALESCE(SUM(total_sales_amount), 0) as total_amount,
		COUNT(*) as approved_records,
		COALESCE(SUM(total_sales_amount), 0) as approved_amount,
		0 as pending_records,
		0 as pending_amount
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

	// Simplified query for existing sales table - treat all sales as approved for now
	err = individualSalesQuery.Select(`
		COUNT(*) as total_sales,
		COALESCE(SUM(total_amount), 0) as total_amount,
		COUNT(*) as approved_sales,
		COALESCE(SUM(total_amount), 0) as approved_amount,
		0 as pending_sales,
		0 as pending_amount
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
	// For now, return empty stats since returns table doesn't exist yet
	// This will be implemented when returns functionality is added
	summary.TodayReturns = DailyReturnsStats{
		TotalReturns:    0,
		TotalAmount:     0,
		ApprovedReturns: 0,
		ApprovedAmount:  0,
		PendingReturns:  0,
		PendingAmount:   0,
	}
	return nil
}

// getPendingApprovalsCount gets count of pending approvals
func (s *DashboardService) getPendingApprovalsCount(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	// For new users, return zero pending approvals since status columns don't exist yet
	summary.PendingSales = 0
	summary.PendingReturns = 0
	return nil
}

// getFinancialSummary gets financial summary for current month
func (s *DashboardService) getFinancialSummary(tenantID uuid.UUID, shopID *uuid.UUID, summary *DashboardSummaryResponse) error {
	now := time.Now()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	monthEnd := monthStart.AddDate(0, 1, 0)

	// Get basic revenue from daily sales records (simplified for existing table structure)
	dailySalesQuery := s.db.Model(&models.DailySalesRecord{}).
		Where("record_date >= ? AND record_date < ?", monthStart, monthEnd)

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
		Where("sale_date >= ? AND sale_date < ?", monthStart, monthEnd)

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

	// Set financial summary (simplified for new users)
	summary.TotalRevenue = dailyRevenue + salesRevenue
	summary.TotalDue = 0                      // No due tracking yet
	summary.CashAmount = summary.TotalRevenue // Assume all cash for now
	summary.CardAmount = 0
	summary.UpiAmount = 0
	summary.CreditAmount = 0

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
