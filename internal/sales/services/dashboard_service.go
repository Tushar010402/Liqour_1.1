package services

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
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

	// Role-aware additions
	TeamStatus *TeamSubmissionStatus `json:"team_status,omitempty"`
	RoleCtx    *RoleContext          `json:"role_context,omitempty"`
	MyStatus   *MySubmissionStatus   `json:"my_status,omitempty"`
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
	CashAmount    float64   `json:"cash_amount"`
	CardAmount    float64   `json:"card_amount"`
	UpiAmount     float64   `json:"upi_amount"`
	CreditAmount  float64   `json:"credit_amount"`
	SalesmanName  string    `json:"salesman_name"`
}

// TopProductSummary represents top-selling products
type TopProductSummary struct {
	ProductID       uuid.UUID `json:"product_id"`
	ProductName     string    `json:"product_name"`
	BrandName       string    `json:"brand_name"`
	CategoryName    string    `json:"category_name"`
	SubcategoryName string    `json:"subcategory_name,omitempty"`
	ImageURL        string    `json:"image_url"`
	TotalQuantity   int       `json:"total_quantity"`
	TotalAmount     float64   `json:"total_amount"`
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

// SalesmanSubmissionStatus tracks per-salesman submission for a date
type SalesmanSubmissionStatus struct {
	SalesmanID   uuid.UUID  `json:"salesman_id"`
	SalesmanName string     `json:"salesman_name"`
	ShopID       uuid.UUID  `json:"shop_id"`
	ShopName     string     `json:"shop_name"`
	Status       string     `json:"status"`        // "submitted" or "missing"
	RecordID     *uuid.UUID `json:"record_id"`     // nil if missing
	RecordStatus string     `json:"record_status"` // "pending"/"approved"/"rejected" or ""
	SubmittedAt  *time.Time `json:"submitted_at"`
	TotalAmount  float64    `json:"total_amount"`
}

// ShopSubmissionSummary is per-shop rollup of salesman submissions
type ShopSubmissionSummary struct {
	ShopID         uuid.UUID                  `json:"shop_id"`
	ShopName       string                     `json:"shop_name"`
	TotalSalesmen  int                        `json:"total_salesmen"`
	SubmittedCount int                        `json:"submitted_count"`
	MissingCount   int                        `json:"missing_count"`
	Salesmen       []SalesmanSubmissionStatus `json:"salesmen"`
}

// TeamSubmissionStatus is the top-level team submission tracker
type TeamSubmissionStatus struct {
	Date           string                  `json:"date"`
	TotalSalesmen  int                     `json:"total_salesmen"`
	TotalSubmitted int                     `json:"total_submitted"`
	TotalMissing   int                     `json:"total_missing"`
	SubmissionRate float64                 `json:"submission_rate"` // 0-100
	Shops          []ShopSubmissionSummary `json:"shops"`
}

// RoleContext tells the client what to show per role
type RoleContext struct {
	Role            string `json:"role"`
	DisplayRole     string `json:"display_role"`
	ShowAllShops    bool   `json:"show_all_shops"`
	ShowTeamTracker bool   `json:"show_team_tracker"`
	ShowApprovals   bool   `json:"show_approvals"`
	ShowOwnStatus   bool   `json:"show_own_status"`
	CanApprove      bool   `json:"can_approve"`
	CanRevert       bool   `json:"can_revert"`
}

// MySubmissionStatus is a salesman's own submission status
type MySubmissionStatus struct {
	HasSubmitted bool       `json:"has_submitted"`
	RecordID     *uuid.UUID `json:"record_id"`
	RecordStatus string     `json:"record_status"`
	SubmittedAt  *time.Time `json:"submitted_at"`
	TotalAmount  float64    `json:"total_amount"`
	ShopID       uuid.UUID  `json:"shop_id"`
	ShopName     string     `json:"shop_name"`
}

// GetDashboardSummary returns dashboard summary for a tenant
func (s *DashboardService) GetDashboardSummary(ctx context.Context, tenantID, userID uuid.UUID, role string, shopID *uuid.UUID, startDate, endDate time.Time) (*DashboardSummaryResponse, error) {
	// Try to get from cache first — include role (and userID for salesman) since response differs per role
	cacheKey := fmt.Sprintf("dashboard_summary:%s:%s:%s:%s", tenantID.String(), role, startDate.Format("2006-01-02"), endDate.Format("2006-01-02"))
	if shopID != nil {
		cacheKey = fmt.Sprintf("dashboard_summary:%s:%s:%s:%s:%s", tenantID.String(), role, shopID.String(), startDate.Format("2006-01-02"), endDate.Format("2006-01-02"))
	}
	if role == models.RoleSalesman {
		cacheKey += ":" + userID.String()
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

	// Get sales stats for the date range
	if err := s.getTodaysSalesStats(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get sales stats: %w", err)
	}

	// Get returns stats for the date range
	if err := s.getTodaysReturnsStats(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get returns stats: %w", err)
	}

	// Get pending approvals count
	if err := s.getPendingApprovalsCount(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get pending approvals: %w", err)
	}

	// Get financial summary for the date range
	if err := s.getFinancialSummary(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get financial summary: %w", err)
	}

	// Get shop-wise breakdown
	if err := s.getShopSummaries(tenantID, shopID, startDate, endDate, summary); err != nil {
		return nil, fmt.Errorf("failed to get shop summaries: %w", err)
	}

	// Get top products (this month)
	if err := s.getTopProducts(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get top products: %w", err)
	}

	// Get recent activities
	if err := s.getRecentActivities(tenantID, shopID, summary); err != nil {
		return nil, fmt.Errorf("failed to get recent activities: %w", err)
	}

	// Role-aware additions
	summary.RoleCtx = s.buildRoleContext(role)

	if summary.RoleCtx.ShowTeamTracker {
		if ts, err := s.getTeamSubmissionStatus(tenantID, shopID, startDate, endDate); err != nil {
			log.Printf("[dashboard] warning: failed to get team submission status: %v", err)
		} else {
			summary.TeamStatus = ts
		}
	}

	if summary.RoleCtx.ShowOwnStatus {
		if ms, err := s.getMySubmissionStatus(tenantID, userID, shopID, startDate, endDate); err != nil {
			log.Printf("[dashboard] warning: failed to get my submission status: %v", err)
		} else {
			summary.MyStatus = ms
		}
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
	query := s.db.Model(&models.DailySalesRecord{}).Where("status = ?", "pending")

	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var count int64
	if err := query.Count(&count).Error; err != nil {
		count = 0
	}

	summary.PendingSales = int(count)
	summary.PendingReturns = 0
	return nil
}

// getFinancialSummary gets financial summary for date range
func (s *DashboardService) getFinancialSummary(tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time, summary *DashboardSummaryResponse) error {
	query := s.db.Model(&models.DailySalesRecord{}).
		Where("record_date >= ? AND record_date < ?", startDate, endDate)

	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var result struct {
		TotalRevenue float64 `gorm:"column:total_revenue"`
		CashAmount   float64 `gorm:"column:cash_amount"`
		CardAmount   float64 `gorm:"column:card_amount"`
		UpiAmount    float64 `gorm:"column:upi_amount"`
		CreditAmount float64 `gorm:"column:credit_amount"`
	}

	err := query.Select(`
		COALESCE(SUM(total_sales_amount), 0) as total_revenue,
		COALESCE(SUM(total_cash_amount), 0) as cash_amount,
		COALESCE(SUM(total_card_amount), 0) as card_amount,
		COALESCE(SUM(total_upi_amount), 0) as upi_amount,
		COALESCE(SUM(total_credit_amount), 0) as credit_amount
	`).Scan(&result).Error

	if err != nil {
		result = struct {
			TotalRevenue float64 `gorm:"column:total_revenue"`
			CashAmount   float64 `gorm:"column:cash_amount"`
			CardAmount   float64 `gorm:"column:card_amount"`
			UpiAmount    float64 `gorm:"column:upi_amount"`
			CreditAmount float64 `gorm:"column:credit_amount"`
		}{0, 0, 0, 0, 0}
	}

	summary.TotalRevenue = result.TotalRevenue
	summary.TotalDue = result.CreditAmount
	summary.CashAmount = result.CashAmount
	summary.CardAmount = result.CardAmount
	summary.UpiAmount = result.UpiAmount
	summary.CreditAmount = result.CreditAmount

	return nil
}

// getShopSummaries gets shop-wise summaries
func (s *DashboardService) getShopSummaries(tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time, summary *DashboardSummaryResponse) error {
	query := s.db.Model(&models.DailySalesRecord{}).
		Select(`
			d.shop_id,
			s.name as shop_name,
			COUNT(*) as total_sales,
			COALESCE(SUM(d.total_sales_amount), 0) as total_amount,
			COUNT(CASE WHEN d.status = 'pending' THEN 1 END) as pending_sales,
			COALESCE(SUM(CASE WHEN d.status = 'pending' THEN d.total_sales_amount ELSE 0 END), 0) as pending_amount,
			COALESCE(SUM(d.total_cash_amount), 0) as cash_amount,
			COALESCE(SUM(d.total_card_amount), 0) as card_amount,
			COALESCE(SUM(d.total_upi_amount), 0) as upi_amount,
			COALESCE(SUM(d.total_credit_amount), 0) as credit_amount,
			COALESCE(MAX(sm.name), '') as salesman_name
		`).
		Table("daily_sales_records d").
		Joins("LEFT JOIN shops s ON s.id = d.shop_id").
		Joins("LEFT JOIN salesmen sm ON sm.id = d.salesman_id").
		Where("d.record_date >= ? AND d.record_date < ?", startDate, endDate)

	if tenantID != uuid.Nil {
		query = query.Where("d.tenant_id = ?", tenantID)
	}
	if shopID != nil {
		query = query.Where("d.shop_id = ?", *shopID)
	}

	query = query.Group("d.shop_id, s.name")

	var shops []ShopSummary
	if err := query.Scan(&shops).Error; err != nil {
		summary.ShopSummaries = []ShopSummary{}
		return nil
	}

	if shops == nil {
		shops = []ShopSummary{}
	}
	summary.ShopSummaries = shops
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
	var records []models.DailySalesRecord

	query := s.db.Preload("Shop").Preload("Salesman").
		Order("created_at DESC").
		Limit(10)

	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}
	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	if err := query.Find(&records).Error; err != nil {
		summary.RecentSales = []RecentSaleActivity{}
		return nil
	}

	activities := make([]RecentSaleActivity, 0, len(records))
	for _, r := range records {
		shopName := ""
		if r.Shop != nil {
			shopName = r.Shop.Name
		}
		salesmanName := ""
		if r.Salesman != nil {
			salesmanName = r.Salesman.Name
		}

		activities = append(activities, RecentSaleActivity{
			ID:           r.ID,
			Type:         "daily_record",
			Number:       r.RecordDate.Format("2006-01-02"),
			ShopName:     shopName,
			SalesmanName: salesmanName,
			Amount:       r.TotalSalesAmount,
			Status:       r.Status,
			CreatedAt:    r.CreatedAt,
		})
	}

	summary.RecentSales = activities
	return nil
}

// buildRoleContext maps a role string to display flags for the client
func (s *DashboardService) buildRoleContext(role string) *RoleContext {
	rc := &RoleContext{Role: role}

	switch role {
	case models.RoleSaasAdmin:
		rc.DisplayRole = "SaaS Admin"
		rc.ShowAllShops = true
		rc.ShowTeamTracker = true
		rc.ShowApprovals = true
		rc.CanApprove = true
		rc.CanRevert = true
	case models.RoleOwner:
		rc.DisplayRole = "Owner"
		rc.ShowAllShops = true
		rc.ShowTeamTracker = true
		rc.ShowApprovals = true
		rc.CanApprove = true
		rc.CanRevert = true
	case models.RoleAdmin:
		rc.DisplayRole = "Admin"
		rc.ShowAllShops = true
		rc.ShowTeamTracker = true
		rc.ShowApprovals = true
		rc.CanApprove = true
		rc.CanRevert = true
	case models.RoleManager:
		rc.DisplayRole = "Manager"
		rc.ShowAllShops = true
		rc.ShowTeamTracker = true
		rc.ShowApprovals = true
		rc.CanApprove = true
	case models.RoleAssistantManager:
		rc.DisplayRole = "Assistant Manager"
		rc.ShowAllShops = true
		rc.ShowTeamTracker = true
		rc.ShowApprovals = true
		rc.CanApprove = true
	case models.RoleExecutive:
		rc.DisplayRole = "Executive"
		rc.ShowAllShops = true
		rc.ShowTeamTracker = true
	case models.RoleSalesman:
		rc.DisplayRole = "Salesman"
		rc.ShowOwnStatus = true
	default:
		rc.DisplayRole = role
	}

	return rc
}

// getTeamSubmissionStatus builds per-salesman submission tracking for a date range.
// Uses 2 SQL queries total (no N+1) and cross-references in Go.
// Matches records via salesman_id OR created_by_id (since salesman_id is often NULL).
func (s *DashboardService) getTeamSubmissionStatus(tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (*TeamSubmissionStatus, error) {
	// Query 1: All active salesmen with their shop names and user_id
	type salesmanRow struct {
		ID       uuid.UUID `gorm:"column:id"`
		UserID   uuid.UUID `gorm:"column:user_id"`
		Name     string    `gorm:"column:name"`
		ShopID   uuid.UUID `gorm:"column:shop_id"`
		ShopName string    `gorm:"column:shop_name"`
	}

	salesmenQuery := s.db.Table("salesmen sm").
		Select("sm.id, sm.user_id, sm.name, sm.shop_id, s.name as shop_name").
		Joins("JOIN shops s ON s.id = sm.shop_id").
		Where("sm.is_active = true AND sm.deleted_at IS NULL AND s.is_active = true AND s.deleted_at IS NULL")

	if tenantID != uuid.Nil {
		salesmenQuery = salesmenQuery.Where("sm.tenant_id = ?", tenantID)
	}
	if shopID != nil {
		salesmenQuery = salesmenQuery.Where("sm.shop_id = ?", *shopID)
	}

	salesmenQuery = salesmenQuery.Order("s.name, sm.name")

	var salesmen []salesmanRow
	if err := salesmenQuery.Scan(&salesmen).Error; err != nil {
		return nil, fmt.Errorf("failed to query salesmen: %w", err)
	}

	// Query 2: Daily sales records for the date range (include both salesman_id and created_by_id)
	type recordRow struct {
		SalesmanID       *uuid.UUID `gorm:"column:salesman_id"`
		CreatedByID      uuid.UUID  `gorm:"column:created_by_id"`
		ID               uuid.UUID  `gorm:"column:id"`
		Status           string     `gorm:"column:status"`
		CreatedAt        time.Time  `gorm:"column:created_at"`
		TotalSalesAmount float64    `gorm:"column:total_sales_amount"`
		ShopID           uuid.UUID  `gorm:"column:shop_id"`
	}

	recordsQuery := s.db.Table("daily_sales_records d").
		Select("d.salesman_id, d.created_by_id, d.id, d.status, d.created_at, d.total_sales_amount, d.shop_id").
		Where("d.record_date >= ? AND d.record_date < ?", startDate, endDate).
		Where("d.deleted_at IS NULL")

	if tenantID != uuid.Nil {
		recordsQuery = recordsQuery.Where("d.tenant_id = ?", tenantID)
	}
	if shopID != nil {
		recordsQuery = recordsQuery.Where("d.shop_id = ?", *shopID)
	}

	var records []recordRow
	if err := recordsQuery.Scan(&records).Error; err != nil {
		return nil, fmt.Errorf("failed to query daily sales records: %w", err)
	}

	// Build two maps for cross-referencing:
	// 1. salesman_id -> record (for records that have salesman_id set)
	// 2. created_by_id -> record (for matching via user_id)
	// Latest record wins in both maps.
	bySalesmanID := make(map[uuid.UUID]recordRow, len(records))
	byCreatedByID := make(map[uuid.UUID]recordRow, len(records))
	for _, r := range records {
		if r.SalesmanID != nil {
			if existing, ok := bySalesmanID[*r.SalesmanID]; !ok || r.CreatedAt.After(existing.CreatedAt) {
				bySalesmanID[*r.SalesmanID] = r
			}
		}
		if existing, ok := byCreatedByID[r.CreatedByID]; !ok || r.CreatedAt.After(existing.CreatedAt) {
			byCreatedByID[r.CreatedByID] = r
		}
	}

	// Group salesmen by shop and cross-reference with records
	shopMap := make(map[uuid.UUID]*ShopSubmissionSummary)
	shopOrder := make([]uuid.UUID, 0)
	totalSubmitted := 0

	for _, sm := range salesmen {
		// Ensure shop entry exists
		if _, ok := shopMap[sm.ShopID]; !ok {
			shopMap[sm.ShopID] = &ShopSubmissionSummary{
				ShopID:   sm.ShopID,
				ShopName: sm.ShopName,
				Salesmen: []SalesmanSubmissionStatus{},
			}
			shopOrder = append(shopOrder, sm.ShopID)
		}
		shop := shopMap[sm.ShopID]

		entry := SalesmanSubmissionStatus{
			SalesmanID:   sm.ID,
			SalesmanName: sm.Name,
			ShopID:       sm.ShopID,
			ShopName:     sm.ShopName,
		}

		// Check by salesman_id first, then fall back to created_by_id (user_id)
		rec, found := bySalesmanID[sm.ID]
		if !found {
			rec, found = byCreatedByID[sm.UserID]
		}

		if found {
			entry.Status = "submitted"
			recID := rec.ID
			entry.RecordID = &recID
			entry.RecordStatus = rec.Status
			createdAt := rec.CreatedAt
			entry.SubmittedAt = &createdAt
			entry.TotalAmount = rec.TotalSalesAmount
			shop.SubmittedCount++
			totalSubmitted++
		} else {
			entry.Status = "missing"
			shop.MissingCount++
		}

		shop.Salesmen = append(shop.Salesmen, entry)
		shop.TotalSalesmen++
	}

	// Build ordered shops slice
	shops := make([]ShopSubmissionSummary, 0, len(shopOrder))
	for _, sid := range shopOrder {
		shops = append(shops, *shopMap[sid])
	}

	totalSalesmen := len(salesmen)
	var submissionRate float64
	if totalSalesmen > 0 {
		submissionRate = math.Round(float64(totalSubmitted)/float64(totalSalesmen)*10000) / 100
	}

	return &TeamSubmissionStatus{
		Date:           startDate.Format("2006-01-02"),
		TotalSalesmen:  totalSalesmen,
		TotalSubmitted: totalSubmitted,
		TotalMissing:   totalSalesmen - totalSubmitted,
		SubmissionRate: submissionRate,
		Shops:          shops,
	}, nil
}

// getMySubmissionStatus checks if the logged-in salesman has submitted for the date range
func (s *DashboardService) getMySubmissionStatus(tenantID, userID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (*MySubmissionStatus, error) {
	// Find salesman record for this user
	type salesmanInfo struct {
		ID       uuid.UUID `gorm:"column:id"`
		ShopID   uuid.UUID `gorm:"column:shop_id"`
		ShopName string    `gorm:"column:shop_name"`
	}

	var sm salesmanInfo
	err := s.db.Table("salesmen s").
		Select("s.id, s.shop_id, sh.name as shop_name").
		Joins("JOIN shops sh ON sh.id = s.shop_id").
		Where("s.user_id = ? AND s.deleted_at IS NULL", userID).
		Where("s.tenant_id = ?", tenantID).
		Limit(1).
		Scan(&sm).Error

	if err != nil {
		return nil, fmt.Errorf("failed to find salesman record: %w", err)
	}
	if sm.ID == uuid.Nil {
		// User is not a salesman in any shop
		return &MySubmissionStatus{HasSubmitted: false}, nil
	}

	// Find their submission for the date range
	type recordInfo struct {
		ID               uuid.UUID `gorm:"column:id"`
		Status           string    `gorm:"column:status"`
		CreatedAt        time.Time `gorm:"column:created_at"`
		TotalSalesAmount float64   `gorm:"column:total_sales_amount"`
	}

	var rec recordInfo
	recordQuery := s.db.Table("daily_sales_records").
		Select("id, status, created_at, total_sales_amount").
		Where("(created_by_id = ? OR salesman_id = ?)", userID, sm.ID).
		Where("record_date >= ? AND record_date < ?", startDate, endDate).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	if shopID != nil {
		recordQuery = recordQuery.Where("shop_id = ?", *shopID)
	}

	err = recordQuery.Order("created_at DESC").Limit(1).Scan(&rec).Error
	if err != nil {
		return nil, fmt.Errorf("failed to query submission: %w", err)
	}

	ms := &MySubmissionStatus{
		ShopID:   sm.ShopID,
		ShopName: sm.ShopName,
	}

	if rec.ID != uuid.Nil {
		ms.HasSubmitted = true
		recID := rec.ID
		ms.RecordID = &recID
		ms.RecordStatus = rec.Status
		createdAt := rec.CreatedAt
		ms.SubmittedAt = &createdAt
		ms.TotalAmount = rec.TotalSalesAmount
	}

	return ms, nil
}
