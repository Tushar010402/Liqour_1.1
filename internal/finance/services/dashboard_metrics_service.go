package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// DateFilterType represents the type of date filter
type DateFilterType string

const (
	DateFilterToday      DateFilterType = "today"
	DateFilterYesterday  DateFilterType = "yesterday"
	DateFilterLast7Days  DateFilterType = "last_7_days"
	DateFilterLast30Days DateFilterType = "last_30_days"
	DateFilterCustom     DateFilterType = "custom"
)

// DashboardMetricsRequest represents the request parameters for dashboard metrics
type DashboardMetricsRequest struct {
	DateFilter DateFilterType `json:"date_filter" form:"date_filter"`
	StartDate  *time.Time     `json:"start_date" form:"start_date"`
	EndDate    *time.Time     `json:"end_date" form:"end_date"`
	ShopID     *uuid.UUID     `json:"shop_id" form:"shop_id"`
}

// MetricSummary represents a single metric summary
type MetricSummary struct {
	TotalAmount float64 `json:"total_amount"`
}

// DateRangeInfo contains information about the resolved date range
type DateRangeInfo struct {
	StartDate     time.Time `json:"start_date"`
	EndDate       time.Time `json:"end_date"`
	FilterApplied string    `json:"filter_applied"`
}

// ShopFilterInfo contains information about the shop filter
type ShopFilterInfo struct {
	ShopID   *uuid.UUID `json:"shop_id"`
	ShopName string     `json:"shop_name"`
}

// DashboardMetrics contains all dashboard metrics
type DashboardMetrics struct {
	Payment  MetricSummary `json:"payment"`
	Purchase MetricSummary `json:"purchase"`
	Sale     MetricSummary `json:"sale"`
	Expense  MetricSummary `json:"expense"`
}

// DashboardMetricsResponse represents the response for dashboard metrics
type DashboardMetricsResponse struct {
	DateRange   DateRangeInfo    `json:"date_range"`
	ShopFilter  ShopFilterInfo   `json:"shop_filter"`
	Metrics     DashboardMetrics `json:"metrics"`
	GeneratedAt time.Time        `json:"generated_at"`
}

// PaymentDetail represents a single payment/collection detail
type PaymentDetail struct {
	ID             uuid.UUID  `json:"id"`
	CollectionDate time.Time  `json:"collection_date"`
	Amount         float64    `json:"amount"`
	CollectionType string     `json:"collection_type"`
	FromUserID     uuid.UUID  `json:"from_user_id"`
	FromUserName   string     `json:"from_user_name"`
	ToUserID       *uuid.UUID `json:"to_user_id,omitempty"`
	ToUserName     string     `json:"to_user_name,omitempty"`
	ShopID         *uuid.UUID `json:"shop_id,omitempty"`
	ShopName       string     `json:"shop_name,omitempty"`
	Status         string     `json:"status"`
	Description    string     `json:"description,omitempty"`
}

// PaymentDetailsResponse represents the response for payment details
type PaymentDetailsResponse struct {
	Payments    []PaymentDetail `json:"payments"`
	Total       int64           `json:"total"`
	Limit       int             `json:"limit"`
	Offset      int             `json:"offset"`
	TotalAmount float64         `json:"total_amount"`
	DateRange   DateRangeInfo   `json:"date_range"`
	ShopFilter  ShopFilterInfo  `json:"shop_filter"`
}

// PurchaseDetail represents a single purchase detail
type PurchaseDetail struct {
	ID             uuid.UUID `json:"id"`
	PurchaseNumber string    `json:"purchase_number"`
	PurchaseDate   time.Time `json:"purchase_date"`
	VendorID       uuid.UUID `json:"vendor_id"`
	VendorName     string    `json:"vendor_name"`
	ShopID         uuid.UUID `json:"shop_id"`
	ShopName       string    `json:"shop_name"`
	TotalAmount    float64   `json:"total_amount"`
	Status         string    `json:"status"`
	ReceiptNo      string    `json:"receipt_no,omitempty"`
}

// PurchaseDetailsResponse represents the response for purchase details
type PurchaseDetailsResponse struct {
	Purchases   []PurchaseDetail `json:"purchases"`
	Total       int64            `json:"total"`
	Limit       int              `json:"limit"`
	Offset      int              `json:"offset"`
	TotalAmount float64          `json:"total_amount"`
	DateRange   DateRangeInfo    `json:"date_range"`
	ShopFilter  ShopFilterInfo   `json:"shop_filter"`
}

// SaleDetail represents a single sale detail
type SaleDetail struct {
	ID               uuid.UUID  `json:"id"`
	RecordDate       time.Time  `json:"record_date"`
	ShopID           uuid.UUID  `json:"shop_id"`
	ShopName         string     `json:"shop_name"`
	SalesmanID       *uuid.UUID `json:"salesman_id,omitempty"`
	SalesmanName     string     `json:"salesman_name,omitempty"`
	TotalSalesAmount float64    `json:"total_sales_amount"`
	CashAmount       float64    `json:"cash_amount"`
	CardAmount       float64    `json:"card_amount"`
	UpiAmount        float64    `json:"upi_amount"`
	CreditAmount     float64    `json:"credit_amount"`
	Status           string     `json:"status"`
}

// SaleDetailsResponse represents the response for sale details
type SaleDetailsResponse struct {
	Sales       []SaleDetail   `json:"sales"`
	Total       int64          `json:"total"`
	Limit       int            `json:"limit"`
	Offset      int            `json:"offset"`
	TotalAmount float64        `json:"total_amount"`
	DateRange   DateRangeInfo  `json:"date_range"`
	ShopFilter  ShopFilterInfo `json:"shop_filter"`
}

// ExpenseDetail represents a single expense detail
type ExpenseDetail struct {
	ID            uuid.UUID  `json:"id"`
	ExpenseDate   time.Time  `json:"expense_date"`
	CategoryID    *uuid.UUID `json:"category_id,omitempty"`
	CategoryName  string     `json:"category_name,omitempty"`
	ShopID        *uuid.UUID `json:"shop_id,omitempty"`
	ShopName      string     `json:"shop_name,omitempty"`
	Amount        float64    `json:"amount"`
	Description   string     `json:"description"`
	PaymentMethod string     `json:"payment_method"`
	CreatedByID   uuid.UUID  `json:"created_by_id"`
	CreatedByName string     `json:"created_by_name,omitempty"`
}

// ExpenseDetailsResponse represents the response for expense details
type ExpenseDetailsResponse struct {
	Expenses    []ExpenseDetail `json:"expenses"`
	Total       int64           `json:"total"`
	Limit       int             `json:"limit"`
	Offset      int             `json:"offset"`
	TotalAmount float64         `json:"total_amount"`
	DateRange   DateRangeInfo   `json:"date_range"`
	ShopFilter  ShopFilterInfo  `json:"shop_filter"`
}

// DashboardMetricsService provides dashboard metrics functionality
type DashboardMetricsService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewDashboardMetricsService creates a new dashboard metrics service
func NewDashboardMetricsService(db *database.DB, cache *cache.Cache) *DashboardMetricsService {
	return &DashboardMetricsService{
		db:    db,
		cache: cache,
	}
}

// ResolveDateRange converts a date filter to actual start and end dates
func (s *DashboardMetricsService) ResolveDateRange(filter DateFilterType, customStart, customEnd *time.Time) (time.Time, time.Time) {
	now := time.Now()
	loc := now.Location()

	switch filter {
	case DateFilterToday:
		start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
		end := start.Add(24*time.Hour - time.Nanosecond)
		return start, end

	case DateFilterYesterday:
		yesterday := now.AddDate(0, 0, -1)
		start := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), 0, 0, 0, 0, loc)
		end := start.Add(24*time.Hour - time.Nanosecond)
		return start, end

	case DateFilterLast7Days:
		end := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 999999999, loc)
		start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc).AddDate(0, 0, -6)
		return start, end

	case DateFilterLast30Days:
		end := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 999999999, loc)
		start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc).AddDate(0, 0, -29)
		return start, end

	case DateFilterCustom:
		if customStart != nil && customEnd != nil {
			start := time.Date(customStart.Year(), customStart.Month(), customStart.Day(), 0, 0, 0, 0, loc)
			end := time.Date(customEnd.Year(), customEnd.Month(), customEnd.Day(), 23, 59, 59, 999999999, loc)
			return start, end
		}
		// Default to yesterday if custom dates not provided
		return s.ResolveDateRange(DateFilterYesterday, nil, nil)

	default:
		// Default to yesterday
		return s.ResolveDateRange(DateFilterYesterday, nil, nil)
	}
}

// GetCacheTTL returns the appropriate cache TTL based on the date filter
func (s *DashboardMetricsService) GetCacheTTL(filter DateFilterType) time.Duration {
	switch filter {
	case DateFilterToday:
		return 2 * time.Minute
	case DateFilterYesterday:
		return 30 * time.Minute
	case DateFilterLast7Days:
		return 15 * time.Minute
	case DateFilterLast30Days:
		return 30 * time.Minute
	default:
		return 15 * time.Minute
	}
}

// GetShopName returns the shop name for a given shop ID
func (s *DashboardMetricsService) GetShopName(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) string {
	if shopID == nil {
		return "All Shops"
	}

	var shop models.Shop
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ?", shopID, tenantID).
		First(&shop).Error
	if err != nil {
		return "Unknown Shop"
	}
	return shop.Name
}

// GetDashboardMetrics returns the aggregated dashboard metrics (cached for 2 minutes)
func (s *DashboardMetricsService) GetDashboardMetrics(ctx context.Context, tenantID uuid.UUID, req DashboardMetricsRequest) (*DashboardMetricsResponse, error) {
	// Resolve date range
	startDate, endDate := s.ResolveDateRange(req.DateFilter, req.StartDate, req.EndDate)

	// Check cache first
	shopIDStr := "all"
	if req.ShopID != nil {
		shopIDStr = req.ShopID.String()
	}
	cacheKey := fmt.Sprintf("dashboard_metrics:%s:%s:%s:%s", tenantID.String(), shopIDStr, startDate.Format("2006-01-02"), endDate.Format("2006-01-02"))
	var cached DashboardMetricsResponse
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		return &cached, nil
	}

	// Get shop name
	shopName := s.GetShopName(ctx, tenantID, req.ShopID)

	// Get payment total (cash collections)
	paymentTotal, err := s.getPaymentTotal(ctx, tenantID, req.ShopID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get payment total: %w", err)
	}

	// Get purchase total
	purchaseTotal, err := s.getPurchaseTotal(ctx, tenantID, req.ShopID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get purchase total: %w", err)
	}

	// Get sale total
	saleTotal, err := s.getSaleTotal(ctx, tenantID, req.ShopID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get sale total: %w", err)
	}

	// Get expense total
	expenseTotal, err := s.getExpenseTotal(ctx, tenantID, req.ShopID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get expense total: %w", err)
	}

	result := &DashboardMetricsResponse{
		DateRange: DateRangeInfo{
			StartDate:     startDate,
			EndDate:       endDate,
			FilterApplied: string(req.DateFilter),
		},
		ShopFilter: ShopFilterInfo{
			ShopID:   req.ShopID,
			ShopName: shopName,
		},
		Metrics: DashboardMetrics{
			Payment:  MetricSummary{TotalAmount: paymentTotal},
			Purchase: MetricSummary{TotalAmount: purchaseTotal},
			Sale:     MetricSummary{TotalAmount: saleTotal},
			Expense:  MetricSummary{TotalAmount: expenseTotal},
		},
		GeneratedAt: time.Now(),
	}

	// Cache for 2 minutes
	s.cache.Set(ctx, cacheKey, result, 2*time.Minute)

	return result, nil
}

// getPaymentTotal returns the total cash collections for the given filters
func (s *DashboardMetricsService) getPaymentTotal(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (float64, error) {
	var total float64

	query := s.db.WithContext(ctx).
		Model(&models.MoneyCollection{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("collection_date >= ? AND collection_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}

	err := query.Scan(&total).Error
	return total, err
}

// getPurchaseTotal returns the total purchases for the given filters
func (s *DashboardMetricsService) getPurchaseTotal(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (float64, error) {
	var total float64

	query := s.db.WithContext(ctx).
		Table("stock_purchases").
		Select("COALESCE(SUM(total_amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("purchase_date >= ? AND purchase_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}

	err := query.Scan(&total).Error
	return total, err
}

// getSaleTotal returns the total sales for the given filters
func (s *DashboardMetricsService) getSaleTotal(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (float64, error) {
	var total float64

	query := s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select("COALESCE(SUM(total_sales_amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("record_date >= ? AND record_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}

	err := query.Scan(&total).Error
	return total, err
}

// getExpenseTotal returns the total expenses for the given filters
func (s *DashboardMetricsService) getExpenseTotal(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (float64, error) {
	var total float64

	// Note: expenses table currently doesn't have a status column in the database
	// All expenses are treated as approved until workflow is implemented
	query := s.db.WithContext(ctx).
		Model(&models.Expense{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("expense_date >= ? AND expense_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}

	err := query.Scan(&total).Error
	return total, err
}

// GetPaymentDetails returns the detailed list of cash collections
func (s *DashboardMetricsService) GetPaymentDetails(ctx context.Context, tenantID uuid.UUID, req DashboardMetricsRequest, limit, offset int) (*PaymentDetailsResponse, error) {
	startDate, endDate := s.ResolveDateRange(req.DateFilter, req.StartDate, req.EndDate)
	shopName := s.GetShopName(ctx, tenantID, req.ShopID)

	// Get total count
	var total int64
	countQuery := s.db.WithContext(ctx).
		Model(&models.MoneyCollection{}).
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("collection_date >= ? AND collection_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		countQuery = countQuery.Where("shop_id = ?", req.ShopID)
	}
	countQuery.Count(&total)

	// Get total amount
	var totalAmount float64
	totalQuery := s.db.WithContext(ctx).
		Model(&models.MoneyCollection{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("collection_date >= ? AND collection_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		totalQuery = totalQuery.Where("shop_id = ?", req.ShopID)
	}
	totalQuery.Scan(&totalAmount)

	// Get paginated results
	var collections []models.MoneyCollection
	query := s.db.WithContext(ctx).
		Preload("Executive").
		Preload("AssistantManager").
		Preload("Shop").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("collection_date >= ? AND collection_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		query = query.Where("shop_id = ?", req.ShopID)
	}

	err := query.
		Order("collection_date DESC").
		Limit(limit).
		Offset(offset).
		Find(&collections).Error
	if err != nil {
		return nil, err
	}

	// Convert to response format
	payments := make([]PaymentDetail, len(collections))
	for i, c := range collections {
		var toUserName string
		if c.AssistantManager != nil {
			toUserName = c.AssistantManager.FullName()
		}
		var fromUserName string
		if c.Executive != nil {
			fromUserName = c.Executive.FullName()
		}
		var shopNameDetail string
		if c.Shop != nil {
			shopNameDetail = c.Shop.Name
		}

		payments[i] = PaymentDetail{
			ID:             c.ID,
			CollectionDate: c.CollectionDate,
			Amount:         c.Amount,
			CollectionType: c.CollectionType,
			FromUserID:     c.ExecutiveID,
			FromUserName:   fromUserName,
			ToUserID:       c.AssistantManagerID,
			ToUserName:     toUserName,
			ShopID:         c.ShopID,
			ShopName:       shopNameDetail,
			Status:         c.Status,
			Description:    c.Description,
		}
	}

	return &PaymentDetailsResponse{
		Payments:    payments,
		Total:       total,
		Limit:       limit,
		Offset:      offset,
		TotalAmount: totalAmount,
		DateRange: DateRangeInfo{
			StartDate:     startDate,
			EndDate:       endDate,
			FilterApplied: string(req.DateFilter),
		},
		ShopFilter: ShopFilterInfo{
			ShopID:   req.ShopID,
			ShopName: shopName,
		},
	}, nil
}

// GetPurchaseDetails returns the detailed list of purchases
func (s *DashboardMetricsService) GetPurchaseDetails(ctx context.Context, tenantID uuid.UUID, req DashboardMetricsRequest, limit, offset int) (*PurchaseDetailsResponse, error) {
	startDate, endDate := s.ResolveDateRange(req.DateFilter, req.StartDate, req.EndDate)
	shopName := s.GetShopName(ctx, tenantID, req.ShopID)

	// Get total count
	var total int64
	countQuery := s.db.WithContext(ctx).
		Table("stock_purchases").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("purchase_date >= ? AND purchase_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		countQuery = countQuery.Where("shop_id = ?", req.ShopID)
	}
	countQuery.Count(&total)

	// Get total amount
	var totalAmount float64
	totalQuery := s.db.WithContext(ctx).
		Table("stock_purchases").
		Select("COALESCE(SUM(total_amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("purchase_date >= ? AND purchase_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		totalQuery = totalQuery.Where("shop_id = ?", req.ShopID)
	}
	totalQuery.Scan(&totalAmount)

	// Get paginated results with raw query for better control
	type purchaseRow struct {
		ID             uuid.UUID `gorm:"column:id"`
		PurchaseNumber string    `gorm:"column:purchase_number"`
		PurchaseDate   time.Time `gorm:"column:purchase_date"`
		VendorID       uuid.UUID `gorm:"column:vendor_id"`
		VendorName     string    `gorm:"column:vendor_name"`
		ShopID         uuid.UUID `gorm:"column:shop_id"`
		ShopName       string    `gorm:"column:shop_name"`
		TotalAmount    float64   `gorm:"column:total_amount"`
		Status         string    `gorm:"column:status"`
		ReceiptNo      string    `gorm:"column:receipt_no"`
	}

	var rows []purchaseRow
	query := s.db.WithContext(ctx).
		Table("stock_purchases sp").
		Select("sp.id, sp.purchase_number, sp.purchase_date, sp.vendor_id, COALESCE(v.name, '') as vendor_name, sp.shop_id, COALESCE(s.name, '') as shop_name, sp.total_amount, sp.status, COALESCE(sp.receipt_no, '') as receipt_no").
		Joins("LEFT JOIN vendors v ON sp.vendor_id = v.id").
		Joins("LEFT JOIN shops s ON sp.shop_id = s.id").
		Where("sp.tenant_id = ?", tenantID).
		Where("sp.status = ?", "approved").
		Where("sp.purchase_date >= ? AND sp.purchase_date <= ?", startDate, endDate).
		Where("sp.deleted_at IS NULL")

	if req.ShopID != nil {
		query = query.Where("sp.shop_id = ?", req.ShopID)
	}

	err := query.
		Order("sp.purchase_date DESC").
		Limit(limit).
		Offset(offset).
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	// Convert to response format
	purchases := make([]PurchaseDetail, len(rows))
	for i, r := range rows {
		purchases[i] = PurchaseDetail{
			ID:             r.ID,
			PurchaseNumber: r.PurchaseNumber,
			PurchaseDate:   r.PurchaseDate,
			VendorID:       r.VendorID,
			VendorName:     r.VendorName,
			ShopID:         r.ShopID,
			ShopName:       r.ShopName,
			TotalAmount:    r.TotalAmount,
			Status:         r.Status,
			ReceiptNo:      r.ReceiptNo,
		}
	}

	return &PurchaseDetailsResponse{
		Purchases:   purchases,
		Total:       total,
		Limit:       limit,
		Offset:      offset,
		TotalAmount: totalAmount,
		DateRange: DateRangeInfo{
			StartDate:     startDate,
			EndDate:       endDate,
			FilterApplied: string(req.DateFilter),
		},
		ShopFilter: ShopFilterInfo{
			ShopID:   req.ShopID,
			ShopName: shopName,
		},
	}, nil
}

// GetSaleDetails returns the detailed list of sales
func (s *DashboardMetricsService) GetSaleDetails(ctx context.Context, tenantID uuid.UUID, req DashboardMetricsRequest, limit, offset int) (*SaleDetailsResponse, error) {
	startDate, endDate := s.ResolveDateRange(req.DateFilter, req.StartDate, req.EndDate)
	shopName := s.GetShopName(ctx, tenantID, req.ShopID)

	// Get total count
	var total int64
	countQuery := s.db.WithContext(ctx).
		Table("daily_sales_records").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("record_date >= ? AND record_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		countQuery = countQuery.Where("shop_id = ?", req.ShopID)
	}
	countQuery.Count(&total)

	// Get total amount
	var totalAmount float64
	totalQuery := s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select("COALESCE(SUM(total_sales_amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("status = ?", "approved").
		Where("record_date >= ? AND record_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		totalQuery = totalQuery.Where("shop_id = ?", req.ShopID)
	}
	totalQuery.Scan(&totalAmount)

	// Get paginated results with raw query
	type saleRow struct {
		ID               uuid.UUID  `gorm:"column:id"`
		RecordDate       time.Time  `gorm:"column:record_date"`
		ShopID           uuid.UUID  `gorm:"column:shop_id"`
		ShopName         string     `gorm:"column:shop_name"`
		SalesmanID       *uuid.UUID `gorm:"column:salesman_id"`
		SalesmanName     string     `gorm:"column:salesman_name"`
		TotalSalesAmount float64    `gorm:"column:total_sales_amount"`
		CashAmount       float64    `gorm:"column:total_cash_amount"`
		CardAmount       float64    `gorm:"column:total_card_amount"`
		UpiAmount        float64    `gorm:"column:total_upi_amount"`
		CreditAmount     float64    `gorm:"column:total_credit_amount"`
		Status           string     `gorm:"column:status"`
	}

	var rows []saleRow
	query := s.db.WithContext(ctx).
		Table("daily_sales_records dsr").
		Select("dsr.id, dsr.record_date, dsr.shop_id, COALESCE(s.name, '') as shop_name, dsr.salesman_id, COALESCE(sm.name, '') as salesman_name, dsr.total_sales_amount, dsr.total_cash_amount, dsr.total_card_amount, dsr.total_upi_amount, dsr.total_credit_amount, dsr.status").
		Joins("LEFT JOIN shops s ON dsr.shop_id = s.id").
		Joins("LEFT JOIN salesmen sm ON dsr.salesman_id = sm.id").
		Where("dsr.tenant_id = ?", tenantID).
		Where("dsr.status = ?", "approved").
		Where("dsr.record_date >= ? AND dsr.record_date <= ?", startDate, endDate).
		Where("dsr.deleted_at IS NULL")

	if req.ShopID != nil {
		query = query.Where("dsr.shop_id = ?", req.ShopID)
	}

	err := query.
		Order("dsr.record_date DESC").
		Limit(limit).
		Offset(offset).
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	// Convert to response format
	sales := make([]SaleDetail, len(rows))
	for i, r := range rows {
		sales[i] = SaleDetail{
			ID:               r.ID,
			RecordDate:       r.RecordDate,
			ShopID:           r.ShopID,
			ShopName:         r.ShopName,
			SalesmanID:       r.SalesmanID,
			SalesmanName:     r.SalesmanName,
			TotalSalesAmount: r.TotalSalesAmount,
			CashAmount:       r.CashAmount,
			CardAmount:       r.CardAmount,
			UpiAmount:        r.UpiAmount,
			CreditAmount:     r.CreditAmount,
			Status:           r.Status,
		}
	}

	return &SaleDetailsResponse{
		Sales:       sales,
		Total:       total,
		Limit:       limit,
		Offset:      offset,
		TotalAmount: totalAmount,
		DateRange: DateRangeInfo{
			StartDate:     startDate,
			EndDate:       endDate,
			FilterApplied: string(req.DateFilter),
		},
		ShopFilter: ShopFilterInfo{
			ShopID:   req.ShopID,
			ShopName: shopName,
		},
	}, nil
}

// GetExpenseDetails returns the detailed list of expenses
func (s *DashboardMetricsService) GetExpenseDetails(ctx context.Context, tenantID uuid.UUID, req DashboardMetricsRequest, limit, offset int) (*ExpenseDetailsResponse, error) {
	startDate, endDate := s.ResolveDateRange(req.DateFilter, req.StartDate, req.EndDate)
	shopName := s.GetShopName(ctx, tenantID, req.ShopID)

	// Get total count
	// Note: expenses table currently doesn't have a status column in the database
	// All expenses are treated as approved until workflow is implemented
	var total int64
	countQuery := s.db.WithContext(ctx).
		Model(&models.Expense{}).
		Where("tenant_id = ?", tenantID).
		Where("expense_date >= ? AND expense_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		countQuery = countQuery.Where("shop_id = ?", req.ShopID)
	}
	countQuery.Count(&total)

	// Get total amount
	var totalAmount float64
	totalQuery := s.db.WithContext(ctx).
		Model(&models.Expense{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("tenant_id = ?", tenantID).
		Where("expense_date >= ? AND expense_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		totalQuery = totalQuery.Where("shop_id = ?", req.ShopID)
	}
	totalQuery.Scan(&totalAmount)

	// Get paginated results - use GORM preload for relationships
	var expenseRecords []models.Expense
	query := s.db.WithContext(ctx).
		Preload("Shop").
		Where("tenant_id = ?", tenantID).
		Where("expense_date >= ? AND expense_date <= ?", startDate, endDate).
		Where("deleted_at IS NULL")

	if req.ShopID != nil {
		query = query.Where("shop_id = ?", req.ShopID)
	}

	err := query.
		Order("expense_date DESC").
		Limit(limit).
		Offset(offset).
		Find(&expenseRecords).Error
	if err != nil {
		return nil, err
	}

	// Convert to response format
	expenses := make([]ExpenseDetail, len(expenseRecords))
	for i, r := range expenseRecords {
		var categoryName string
		if r.Category != nil {
			categoryName = r.Category.Name
		}
		var expenseShopName string
		if r.Shop != nil {
			expenseShopName = r.Shop.Name
		}
		expenses[i] = ExpenseDetail{
			ID:            r.ID,
			ExpenseDate:   r.ExpenseDate,
			CategoryID:    r.CategoryID,
			CategoryName:  categoryName,
			ShopID:        r.ShopID,
			ShopName:      expenseShopName,
			Amount:        r.Amount,
			Description:   r.Description,
			PaymentMethod: r.PaymentMethod,
		}
	}

	return &ExpenseDetailsResponse{
		Expenses:    expenses,
		Total:       total,
		Limit:       limit,
		Offset:      offset,
		TotalAmount: totalAmount,
		DateRange: DateRangeInfo{
			StartDate:     startDate,
			EndDate:       endDate,
			FilterApplied: string(req.DateFilter),
		},
		ShopFilter: ShopFilterInfo{
			ShopID:   req.ShopID,
			ShopName: shopName,
		},
	}, nil
}
