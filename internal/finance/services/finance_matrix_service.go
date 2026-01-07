package services

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// FinanceMatrixService provides comprehensive financial analytics
type FinanceMatrixService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewFinanceMatrixService creates a new finance matrix service
func NewFinanceMatrixService(db *database.DB, cache *cache.Cache) *FinanceMatrixService {
	return &FinanceMatrixService{
		db:    db,
		cache: cache,
	}
}

// GetDashboardSummary returns comprehensive dashboard data
func (s *FinanceMatrixService) GetDashboardSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (*models.DashboardSummaryResponse, error) {
	response := &models.DashboardSummaryResponse{}

	// Build base query conditions
	conditions := "tenant_id = ? AND metric_date BETWEEN ? AND ?"
	args := []interface{}{tenantID, startDate, endDate}
	if shopID != nil {
		conditions += " AND shop_id = ?"
		args = append(args, *shopID)
	}

	// Get aggregated metrics from finance_metrics_daily
	var metricsResult struct {
		TotalSales           float64
		TotalCash            float64
		TotalCard            float64
		TotalUPI             float64
		TotalCredit          float64
		TotalExpenses        float64
		TotalTransactions    int64
		TotalItems           int64
		TotalRefunds         float64
		TotalDiscounts       float64
		OpeningCashTotal     float64
		ClosingCashTotal     float64
		TotalVariance        float64
		VarianceCount        int64
	}

	s.db.WithContext(ctx).Model(&models.FinanceMetricsDaily{}).
		Select(`
			SUM(total_sales) as total_sales,
			SUM(cash_amount) as total_cash,
			SUM(card_amount) as total_card,
			SUM(upi_amount) as total_upi,
			SUM(credit_amount) as total_credit,
			SUM(total_expenses) as total_expenses,
			SUM(transaction_count) as total_transactions,
			SUM(items_sold) as total_items,
			SUM(refund_amount) as total_refunds,
			SUM(discount_amount) as total_discounts,
			SUM(opening_cash) as opening_cash_total,
			SUM(closing_cash) as closing_cash_total,
			SUM(cash_variance) as total_variance,
			COUNT(CASE WHEN cash_variance != 0 THEN 1 END) as variance_count
		`).
		Where(conditions, args...).
		Scan(&metricsResult)

	// Populate response - using nested struct fields
	response.Sales.TotalSales = metricsResult.TotalSales
	response.Sales.CashSales = metricsResult.TotalCash
	response.Sales.CardSales = metricsResult.TotalCard
	response.Sales.UPISales = metricsResult.TotalUPI
	response.Sales.CreditSales = metricsResult.TotalCredit
	response.Sales.SalesCount = int(metricsResult.TotalTransactions)
	response.Sales.ItemsSold = int(metricsResult.TotalItems)
	response.Expenses.TotalExpenses = metricsResult.TotalExpenses

	// Calculate average transaction value
	if metricsResult.TotalTransactions > 0 {
		response.Sales.AvgTransactionValue = metricsResult.TotalSales / float64(metricsResult.TotalTransactions)
	}

	// Get cash holdings summary
	cashHoldings, err := s.GetCashHoldingsSummary(ctx, tenantID, shopID)
	if err == nil && len(cashHoldings) > 0 {
		var totalHoldings float64
		for _, h := range cashHoldings {
			totalHoldings += h.CurrentBalance
		}
		response.CashHoldings = &models.CashHoldingsSummary{
			TotalUserHoldings: totalHoldings,
			UserBreakdown:     cashHoldings,
		}
		response.CashFlow.TeamCashHoldings = cashHoldings
	}

	// Get credit aging summary
	creditAging, err := s.GetCreditAgingSummary(ctx, tenantID, shopID)
	if err == nil && len(creditAging) > 0 {
		var totalOutstanding float64
		var customerCount int
		for _, a := range creditAging {
			totalOutstanding += a.TotalAmount
			customerCount += a.CustomerCount
		}
		response.CreditAging = &models.CreditAgingSummary{
			TotalOutstanding: totalOutstanding,
			CustomerCount:    customerCount,
			AgingBuckets:     creditAging,
		}
		response.Credit.TotalOutstanding = totalOutstanding
		response.Credit.CustomerCount = customerCount
		response.Credit.AgingBuckets = creditAging
	}

	// Get expense breakdown by category
	expenseBreakdown, err := s.GetExpenseBreakdown(ctx, tenantID, shopID, startDate, endDate)
	if err == nil {
		response.ExpensesByCategory = expenseBreakdown
		response.Expenses.TopCategories = expenseBreakdown
	}

	// Get daily sales trend
	dailyTrend, err := s.GetDailySalesTrend(ctx, tenantID, shopID, startDate, endDate)
	if err == nil {
		response.DailySalesTrend = dailyTrend
	}

	// Get payment method breakdown
	response.PaymentMethodBreakdown = map[string]float64{
		"cash":   metricsResult.TotalCash,
		"card":   metricsResult.TotalCard,
		"upi":    metricsResult.TotalUPI,
		"credit": metricsResult.TotalCredit,
	}

	// Get top products
	topProducts, err := s.GetTopProducts(ctx, tenantID, shopID, startDate, endDate, 10)
	if err == nil {
		response.TopProducts = topProducts
	}

	// Get alerts
	alerts, err := s.GetActiveAlerts(ctx, tenantID, shopID, 10)
	if err == nil {
		response.Alerts.RecentAlerts = alerts
		var criticalCount int
		for _, a := range alerts {
			if a.Severity == "critical" {
				criticalCount++
			}
		}
		response.Alerts.UnreadCount = len(alerts)
		response.Alerts.CriticalCount = criticalCount
	}

	// Get insights
	insights, err := s.GenerateInsights(ctx, tenantID, shopID, startDate, endDate)
	if err == nil {
		response.Insights = insights
	}

	return response, nil
}

// GetCashHoldingsSummary returns cash holdings by user
func (s *FinanceMatrixService) GetCashHoldingsSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]models.UserCashHolding, error) {
	var holdings []models.UserCashHolding

	query := s.db.WithContext(ctx).
		Table("v_cash_holding_summary").
		Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Order("current_balance DESC").Scan(&holdings).Error
	return holdings, err
}

// GetCreditAgingSummary returns credit aging buckets
func (s *FinanceMatrixService) GetCreditAgingSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]models.AgingBucketStat, error) {
	var aging []models.AgingBucketStat

	query := s.db.WithContext(ctx).
		Table("v_credit_aging_summary").
		Select("aging_bucket, SUM(customer_count) as customer_count, SUM(total_outstanding) as total_amount, AVG(avg_days_outstanding) as avg_days").
		Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Group("aging_bucket").Order("aging_bucket").Scan(&aging).Error
	return aging, err
}

// GetExpenseBreakdown returns expenses by category
func (s *FinanceMatrixService) GetExpenseBreakdown(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) ([]models.ExpenseCategoryStat, error) {
	var breakdown []models.ExpenseCategoryStat

	query := s.db.WithContext(ctx).
		Table("v_expense_summary").
		Select("category_name, SUM(total_amount) as total_amount, SUM(expense_count) as count").
		Where("tenant_id = ? AND month BETWEEN ? AND ?", tenantID, startDate, endDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Group("category_name").Order("total_amount DESC").Scan(&breakdown).Error
	return breakdown, err
}

// GetDailySalesTrend returns daily sales data
func (s *FinanceMatrixService) GetDailySalesTrend(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) ([]models.DailySalesStat, error) {
	var trend []models.DailySalesStat

	query := s.db.WithContext(ctx).Model(&models.FinanceMetricsDaily{}).
		Select(`
			metric_date as date,
			SUM(total_sales) as total_sales,
			SUM(cash_amount) as cash_sales,
			SUM(card_amount) as card_sales,
			SUM(upi_amount) as upi_sales,
			SUM(credit_amount) as credit_sales,
			SUM(total_expenses) as expenses,
			SUM(transaction_count) as transactions
		`).
		Where("tenant_id = ? AND metric_date BETWEEN ? AND ?", tenantID, startDate, endDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Group("metric_date").Order("metric_date").Scan(&trend).Error
	return trend, err
}

// GetTopProducts returns top selling products
func (s *FinanceMatrixService) GetTopProducts(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time, limit int) ([]models.TopProductStat, error) {
	var products []models.TopProductStat

	query := s.db.WithContext(ctx).
		Table("daily_sales_items dsi").
		Select(`
			dsi.product_id,
			p.name as product_name,
			p.sku,
			SUM(dsi.quantity) as quantity_sold,
			SUM(dsi.total_amount) as total_revenue,
			COUNT(DISTINCT dsi.daily_sales_record_id) as transaction_count
		`).
		Joins("JOIN daily_sales_records dsr ON dsi.daily_sales_record_id = dsr.id").
		Joins("JOIN products p ON dsi.product_id = p.id").
		Where("dsr.tenant_id = ? AND dsr.record_date BETWEEN ? AND ? AND dsr.status = 'approved'", tenantID, startDate, endDate)

	if shopID != nil {
		query = query.Where("dsr.shop_id = ?", *shopID)
	}

	err := query.Group("dsi.product_id, p.name, p.sku").
		Order("total_revenue DESC").
		Limit(limit).
		Scan(&products).Error

	return products, err
}

// GetActiveAlerts returns active finance alerts
func (s *FinanceMatrixService) GetActiveAlerts(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, limit int) ([]models.FinanceAlert, error) {
	var alerts []models.FinanceAlert

	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND status IN ('active', 'escalated')", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Order("severity DESC, created_at DESC").
		Limit(limit).
		Find(&alerts).Error

	return alerts, err
}

// GenerateInsights generates smart insights based on data analysis
func (s *FinanceMatrixService) GenerateInsights(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) ([]models.FinanceInsight, error) {
	var insights []models.FinanceInsight

	// Calculate date ranges for comparison
	duration := endDate.Sub(startDate)
	prevStartDate := startDate.Add(-duration)
	prevEndDate := startDate.Add(-24 * time.Hour)

	// Get current period metrics
	currentMetrics, _ := s.getAggregatedMetrics(ctx, tenantID, shopID, startDate, endDate)
	prevMetrics, _ := s.getAggregatedMetrics(ctx, tenantID, shopID, prevStartDate, prevEndDate)

	// Sales trend insight
	if prevMetrics.TotalSales > 0 {
		salesChange := ((currentMetrics.TotalSales - prevMetrics.TotalSales) / prevMetrics.TotalSales) * 100
		if math.Abs(salesChange) > 10 {
			direction := "increased"
			if salesChange < 0 {
				direction = "decreased"
			}
			insights = append(insights, models.FinanceInsight{
				Type:        "sales_trend",
				Title:       "Sales Trend Alert",
				Description: fmt.Sprintf("Sales have %s by %.1f%% compared to previous period", direction, math.Abs(salesChange)),
				Severity:    getSeverityFromChange(salesChange),
				Value:       salesChange,
				Trend:       getTrendDirection(salesChange),
			})
		}
	}

	// Cash variance insight
	if currentMetrics.CashVariance != 0 {
		insights = append(insights, models.FinanceInsight{
			Type:        "cash_variance",
			Title:       "Cash Variance Detected",
			Description: fmt.Sprintf("Total cash variance of ₹%.2f detected in the period", currentMetrics.CashVariance),
			Severity:    getSeverityFromAmount(math.Abs(currentMetrics.CashVariance)),
			Value:       currentMetrics.CashVariance,
		})
	}

	// Credit utilization insight
	if currentMetrics.TotalSales > 0 {
		creditRatio := (currentMetrics.CreditSales / currentMetrics.TotalSales) * 100
		if creditRatio > 30 {
			insights = append(insights, models.FinanceInsight{
				Type:        "credit_utilization",
				Title:       "High Credit Sales",
				Description: fmt.Sprintf("%.1f%% of sales are on credit. Consider reviewing credit policy.", creditRatio),
				Severity:    "warning",
				Value:       creditRatio,
			})
		}
	}

	// Expense ratio insight
	if currentMetrics.TotalSales > 0 {
		expenseRatio := (currentMetrics.TotalExpenses / currentMetrics.TotalSales) * 100
		if expenseRatio > 20 {
			insights = append(insights, models.FinanceInsight{
				Type:        "expense_ratio",
				Title:       "High Expense Ratio",
				Description: fmt.Sprintf("Expenses are %.1f%% of sales. Review expense categories.", expenseRatio),
				Severity:    "warning",
				Value:       expenseRatio,
			})
		}
	}

	// Average transaction value insight
	if currentMetrics.TransactionCount > 0 && prevMetrics.TransactionCount > 0 {
		currentATV := currentMetrics.TotalSales / float64(currentMetrics.TransactionCount)
		prevATV := prevMetrics.TotalSales / float64(prevMetrics.TransactionCount)
		atvChange := ((currentATV - prevATV) / prevATV) * 100
		if math.Abs(atvChange) > 15 {
			direction := "increased"
			if atvChange < 0 {
				direction = "decreased"
			}
			insights = append(insights, models.FinanceInsight{
				Type:        "avg_transaction",
				Title:       "Transaction Value Change",
				Description: fmt.Sprintf("Average transaction value has %s by %.1f%% to ₹%.2f", direction, math.Abs(atvChange), currentATV),
				Severity:    getSeverityFromChange(atvChange),
				Value:       currentATV,
				Trend:       getTrendDirection(atvChange),
			})
		}
	}

	// Low stock alert
	var lowStockCount int64
	s.db.WithContext(ctx).Model(&models.Stock{}).
		Where("tenant_id = ? AND quantity <= minimum_level AND deleted_at IS NULL", tenantID).
		Count(&lowStockCount)
	if lowStockCount > 0 {
		insights = append(insights, models.FinanceInsight{
			Type:        "low_stock",
			Title:       "Low Stock Alert",
			Description: fmt.Sprintf("%d products are at or below minimum stock level", lowStockCount),
			Severity:    "warning",
			Value:       float64(lowStockCount),
		})
	}

	// Pending collections insight
	var pendingCollections float64
	s.db.WithContext(ctx).Model(&models.MoneyCollection{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("tenant_id = ? AND status = 'pending' AND deleted_at IS NULL", tenantID).
		Scan(&pendingCollections)
	if pendingCollections > 10000 {
		insights = append(insights, models.FinanceInsight{
			Type:        "pending_collections",
			Title:       "Pending Collections",
			Description: fmt.Sprintf("₹%.2f in pending cash collections need attention", pendingCollections),
			Severity:    "info",
			Value:       pendingCollections,
		})
	}

	return insights, nil
}

// AggregatedMetrics helper struct
type AggregatedMetrics struct {
	TotalSales       float64
	CashSales        float64
	CardSales        float64
	UPISales         float64
	CreditSales      float64
	TotalExpenses    float64
	TransactionCount int64
	CashVariance     float64
}

func (s *FinanceMatrixService) getAggregatedMetrics(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (*AggregatedMetrics, error) {
	var result AggregatedMetrics

	query := s.db.WithContext(ctx).Model(&models.FinanceMetricsDaily{}).
		Select(`
			COALESCE(SUM(total_sales), 0) as total_sales,
			COALESCE(SUM(cash_amount), 0) as cash_sales,
			COALESCE(SUM(card_amount), 0) as card_sales,
			COALESCE(SUM(upi_amount), 0) as upi_sales,
			COALESCE(SUM(credit_amount), 0) as credit_sales,
			COALESCE(SUM(total_expenses), 0) as total_expenses,
			COALESCE(SUM(transaction_count), 0) as transaction_count,
			COALESCE(SUM(cash_variance), 0) as cash_variance
		`).
		Where("tenant_id = ? AND metric_date BETWEEN ? AND ?", tenantID, startDate, endDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Scan(&result).Error
	return &result, err
}

// ComputeDailyMetrics computes and stores daily metrics (called by scheduler)
func (s *FinanceMatrixService) ComputeDailyMetrics(ctx context.Context, tenantID uuid.UUID, shopID uuid.UUID, date time.Time) error {
	// Check if metrics already exist
	var existing models.FinanceMetricsDaily
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND shop_id = ? AND metric_date = ?", tenantID, shopID, date).
		First(&existing).Error

	if err == nil {
		// Update existing
		return s.updateDailyMetrics(ctx, &existing, date)
	} else if err != gorm.ErrRecordNotFound {
		return err
	}

	// Create new metrics
	metrics := &models.FinanceMetricsDaily{
		TenantID:   tenantID,
		ShopID:     &shopID,
		MetricDate: date,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	return s.updateDailyMetrics(ctx, metrics, date)
}

func (s *FinanceMatrixService) updateDailyMetrics(ctx context.Context, metrics *models.FinanceMetricsDaily, date time.Time) error {
	// Get sales data
	var salesData struct {
		TotalSales    float64
		CashAmount    float64
		CardAmount    float64
		UPIAmount     float64
		CreditAmount  float64
		ItemsSold     int
		TransCount    int64
		RefundAmount  float64
		DiscountAmount float64
	}

	s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select(`
			COALESCE(SUM(total_sales_amount), 0) as total_sales,
			COALESCE(SUM(total_cash_amount), 0) as cash_amount,
			COALESCE(SUM(total_card_amount), 0) as card_amount,
			COALESCE(SUM(total_upi_amount), 0) as upi_amount,
			COALESCE(SUM(total_credit_amount), 0) as credit_amount,
			COUNT(*) as trans_count
		`).
		Where("tenant_id = ? AND shop_id = ? AND record_date = ? AND status = 'approved' AND deleted_at IS NULL",
			metrics.TenantID, *metrics.ShopID, date).
		Scan(&salesData)

	// Get items sold
	s.db.WithContext(ctx).
		Table("daily_sales_items dsi").
		Select("COALESCE(SUM(dsi.quantity), 0)").
		Joins("JOIN daily_sales_records dsr ON dsi.daily_sales_record_id = dsr.id").
		Where("dsr.tenant_id = ? AND dsr.shop_id = ? AND dsr.record_date = ? AND dsr.status = 'approved'",
			metrics.TenantID, *metrics.ShopID, date).
		Scan(&salesData.ItemsSold)

	// Get expense data
	var expenseTotal float64
	s.db.WithContext(ctx).Model(&models.Expense{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("tenant_id = ? AND shop_id = ? AND expense_date = ? AND deleted_at IS NULL",
			metrics.TenantID, *metrics.ShopID, date).
		Scan(&expenseTotal)

	// Get cash data (opening/closing)
	var cashData struct {
		OpeningCash  float64
		ClosingCash  float64
		CashVariance float64
	}
	// This would come from cash audit or daily closing records
	// Placeholder for now

	// Update metrics
	metrics.TotalSales = salesData.TotalSales
	metrics.CashAmount = salesData.CashAmount
	metrics.CardAmount = salesData.CardAmount
	metrics.UPIAmount = salesData.UPIAmount
	metrics.CreditAmount = salesData.CreditAmount
	metrics.TotalExpenses = expenseTotal
	metrics.TransactionCount = int(salesData.TransCount)
	metrics.ItemsSold = salesData.ItemsSold
	metrics.RefundAmount = salesData.RefundAmount
	metrics.DiscountAmount = salesData.DiscountAmount
	metrics.GrossProfit = salesData.TotalSales - expenseTotal
	if salesData.TotalSales > 0 {
		metrics.GrossMargin = (metrics.GrossProfit / salesData.TotalSales) * 100
	}
	metrics.OpeningCash = cashData.OpeningCash
	metrics.ClosingCash = cashData.ClosingCash
	metrics.CashVariance = cashData.CashVariance
	metrics.UpdatedAt = time.Now()

	return s.db.WithContext(ctx).Save(metrics).Error
}

// GetSalesmanPerformance returns salesman performance metrics
func (s *FinanceMatrixService) GetSalesmanPerformance(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) ([]models.SalesmanPerformance, error) {
	var performance []models.SalesmanPerformance

	query := s.db.WithContext(ctx).
		Table("v_salesman_performance").
		Select(`
			salesman_id,
			salesman_name,
			SUM(sales_count) as total_sales_count,
			SUM(total_sales) as total_sales_amount,
			SUM(cash_collected) as cash_collected,
			SUM(credit_given) as credit_given,
			AVG(avg_sale_value) as avg_sale_value,
			SUM(items_sold) as items_sold
		`).
		Where("tenant_id = ? AND month BETWEEN ? AND ?", tenantID, startDate, endDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.Group("salesman_id, salesman_name").
		Order("total_sales_amount DESC").
		Scan(&performance).Error

	return performance, err
}

// GetStockTurnover returns stock turnover analysis
func (s *FinanceMatrixService) GetStockTurnover(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, velocity string) ([]models.StockTurnoverStat, error) {
	var turnover []models.StockTurnoverStat

	query := s.db.WithContext(ctx).
		Table("v_stock_turnover").
		Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	if velocity != "" {
		query = query.Where("stock_velocity = ?", velocity)
	}

	err := query.Order("stock_value DESC").Scan(&turnover).Error
	return turnover, err
}

// CreateFinanceAlert creates a new finance alert
func (s *FinanceMatrixService) CreateFinanceAlert(ctx context.Context, alert *models.FinanceAlert) error {
	alert.CreatedAt = time.Now()
	alert.UpdatedAt = time.Now()
	return s.db.WithContext(ctx).Create(alert).Error
}

// AcknowledgeAlert acknowledges an alert
func (s *FinanceMatrixService) AcknowledgeAlert(ctx context.Context, alertID uuid.UUID, userID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.FinanceAlert{}).
		Where("id = ?", alertID).
		Updates(map[string]interface{}{
			"status":          models.AlertStatusAcknowledged,
			"acknowledged_by": userID,
			"acknowledged_at": now,
			"updated_at":      now,
		}).Error
}

// ResolveAlert resolves an alert
func (s *FinanceMatrixService) ResolveAlert(ctx context.Context, alertID uuid.UUID, userID uuid.UUID, resolution string) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.FinanceAlert{}).
		Where("id = ?", alertID).
		Updates(map[string]interface{}{
			"status":      models.AlertStatusResolved,
			"resolved_by": userID,
			"resolved_at": now,
			"resolution":  resolution,
			"updated_at":  now,
		}).Error
}

// Helper functions

func getSeverityFromChange(change float64) string {
	absChange := math.Abs(change)
	if absChange > 50 {
		return "critical"
	} else if absChange > 30 {
		return "high"
	} else if absChange > 15 {
		return "warning"
	}
	return "info"
}

func getSeverityFromAmount(amount float64) string {
	if amount > 10000 {
		return "critical"
	} else if amount > 5000 {
		return "high"
	} else if amount > 1000 {
		return "warning"
	}
	return "info"
}

func getTrendDirection(change float64) string {
	if change > 0 {
		return "up"
	} else if change < 0 {
		return "down"
	}
	return "stable"
}
