package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

type AnalyticsService struct {
	db     *gorm.DB
	config *config.Config
}

func NewAnalyticsService(db *gorm.DB, cfg *config.Config) *AnalyticsService {
	return &AnalyticsService{
		db:     db,
		config: cfg,
	}
}

func (s *AnalyticsService) GetDashboardMetrics(ctx context.Context) (*models.DashboardMetrics, error) {
	metrics := &models.DashboardMetrics{
		PlanDistribution: make(map[string]int),
		RevenueByPlan:    make(map[string]float64),
		MonthlyGrowth:    make(map[string]float64),
	}

	// Total subscriptions
	var totalSubs int64
	if err := s.db.Model(&models.Subscription{}).Count(&totalSubs); err != nil {
		return nil, fmt.Errorf("failed to get total subscriptions: %w", err)
	}
	metrics.TotalSubscriptions = int(totalSubs)

	// Active subscriptions
	var activeSubs int64
	if err := s.db.Model(&models.Subscription{}).
		Where("status = 'active'").
		Count(&activeSubs); err != nil {
		return nil, fmt.Errorf("failed to get active subscriptions: %w", err)
	}
	metrics.ActiveSubscriptions = int(activeSubs)

	// Trial subscriptions
	var trialSubs int64
	if err := s.db.Model(&models.Subscription{}).
		Where("status = 'trial'").
		Count(&trialSubs); err != nil {
		return nil, fmt.Errorf("failed to get trial subscriptions: %w", err)
	}
	metrics.TrialSubscriptions = int(trialSubs)

	// Total revenue
	var totalRevenue float64
	if err := s.db.Model(&models.Payment{}).
		Where("status = 'succeeded'").
		Select("COALESCE(SUM(amount), 0)").
		Scan(&totalRevenue).Error; err != nil {
		return nil, fmt.Errorf("failed to get total revenue: %w", err)
	}
	metrics.TotalRevenue = totalRevenue

	// Monthly revenue (current month)
	currentMonth := time.Now().Truncate(24 * time.Hour).AddDate(0, 0, -time.Now().Day()+1)
	var monthlyRevenue float64
	if err := s.db.Model(&models.Payment{}).
		Where("status = 'succeeded' AND created_at >= ?", currentMonth).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&monthlyRevenue).Error; err != nil {
		return nil, fmt.Errorf("failed to get monthly revenue: %w", err)
	}
	metrics.MonthlyRevenue = monthlyRevenue

	// Total tenants (unique tenant IDs from subscriptions)
	var totalTenants int64
	if err := s.db.Model(&models.Subscription{}).
		Distinct("tenant_id").
		Count(&totalTenants); err != nil {
		return nil, fmt.Errorf("failed to get total tenants: %w", err)
	}
	metrics.TotalTenants = int(totalTenants)

	// New tenants (this month)
	var newTenants int64
	if err := s.db.Model(&models.Subscription{}).
		Where("created_at >= ?", currentMonth).
		Distinct("tenant_id").
		Count(&newTenants); err != nil {
		return nil, fmt.Errorf("failed to get new tenants: %w", err)
	}
	metrics.NewTenants = int(newTenants)

	// Calculate churn rate (simplified - cancelled this month vs active last month)
	churnRate, err := s.calculateChurnRate(currentMonth)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate churn rate: %w", err)
	}
	metrics.ChurnRate = churnRate

	// Plan distribution
	planDist, err := s.getPlanDistribution()
	if err != nil {
		return nil, fmt.Errorf("failed to get plan distribution: %w", err)
	}
	metrics.PlanDistribution = planDist

	// Revenue by plan
	revenueByPlan, err := s.getRevenueByPlan()
	if err != nil {
		return nil, fmt.Errorf("failed to get revenue by plan: %w", err)
	}
	metrics.RevenueByPlan = revenueByPlan

	// Monthly growth
	monthlyGrowth, err := s.getMonthlyGrowth()
	if err != nil {
		return nil, fmt.Errorf("failed to get monthly growth: %w", err)
	}
	metrics.MonthlyGrowth = monthlyGrowth

	return metrics, nil
}

func (s *AnalyticsService) GetRevenueAnalytics(ctx context.Context, period string, startDate, endDate time.Time) (*RevenueAnalytics, error) {
	analytics := &RevenueAnalytics{
		Period:           period,
		StartDate:        startDate,
		EndDate:          endDate,
		DailyRevenue:     make([]DailyRevenue, 0),
		PaymentMethods:   make(map[string]float64),
		TopPlans:         make([]PlanRevenue, 0),
		RevenueByStatus:  make(map[string]float64),
	}

	// Total revenue in period
	var totalRevenue float64
	if err := s.db.Model(&models.Payment{}).
		Where("status = 'succeeded' AND created_at BETWEEN ? AND ?", startDate, endDate).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&totalRevenue).Error; err != nil {
		return nil, fmt.Errorf("failed to get total revenue: %w", err)
	}
	analytics.TotalRevenue = totalRevenue

	// Daily revenue breakdown
	dailyRevenue, err := s.getDailyRevenue(startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get daily revenue: %w", err)
	}
	analytics.DailyRevenue = dailyRevenue

	// Payment methods breakdown
	paymentMethods, err := s.getPaymentMethodsBreakdown(startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get payment methods: %w", err)
	}
	analytics.PaymentMethods = paymentMethods

	// Top plans by revenue
	topPlans, err := s.getTopPlansByRevenue(startDate, endDate, 10)
	if err != nil {
		return nil, fmt.Errorf("failed to get top plans: %w", err)
	}
	analytics.TopPlans = topPlans

	// Revenue by payment status
	revenueByStatus, err := s.getRevenueByStatus(startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get revenue by status: %w", err)
	}
	analytics.RevenueByStatus = revenueByStatus

	return analytics, nil
}

func (s *AnalyticsService) GetSubscriptionMetrics(ctx context.Context, period string) (*SubscriptionMetrics, error) {
	metrics := &SubscriptionMetrics{
		Period:                period,
		StatusDistribution:    make(map[string]int),
		BillingCycleBreakdown: make(map[string]int),
		PlanPopularity:        make([]PlanPopularity, 0),
		ConversionRates:       make(map[string]float64),
	}

	// Total subscriptions
	if err := s.db.Model(&models.Subscription{}).Count(&metrics.TotalSubscriptions); err != nil {
		return nil, fmt.Errorf("failed to get total subscriptions: %w", err)
	}

	// Status distribution
	statusDist, err := s.getSubscriptionStatusDistribution()
	if err != nil {
		return nil, fmt.Errorf("failed to get status distribution: %w", err)
	}
	metrics.StatusDistribution = statusDist

	// Billing cycle breakdown
	billingCycle, err := s.getBillingCycleBreakdown()
	if err != nil {
		return nil, fmt.Errorf("failed to get billing cycle breakdown: %w", err)
	}
	metrics.BillingCycleBreakdown = billingCycle

	// Plan popularity
	planPopularity, err := s.getPlanPopularity()
	if err != nil {
		return nil, fmt.Errorf("failed to get plan popularity: %w", err)
	}
	metrics.PlanPopularity = planPopularity

	// Conversion rates
	conversionRates, err := s.getConversionRates()
	if err != nil {
		return nil, fmt.Errorf("failed to get conversion rates: %w", err)
	}
	metrics.ConversionRates = conversionRates

	// Average subscription value
	var avgValue float64
	if err := s.db.Model(&models.Subscription{}).
		Where("status IN ?", []string{"active", "trial"}).
		Select("COALESCE(AVG(amount), 0)").
		Scan(&avgValue).Error; err != nil {
		return nil, fmt.Errorf("failed to get average subscription value: %w", err)
	}
	metrics.AverageSubscriptionValue = avgValue

	return metrics, nil
}

func (s *AnalyticsService) GetTenantMetrics(ctx context.Context) (*TenantMetrics, error) {
	metrics := &TenantMetrics{
		UsageByPlan: make(map[string]TenantUsage),
	}

	// Total tenants
	if err := s.db.Model(&models.Subscription{}).
		Distinct("tenant_id").
		Count(&metrics.TotalTenants); err != nil {
		return nil, fmt.Errorf("failed to get total tenants: %w", err)
	}

	// Active tenants
	if err := s.db.Model(&models.Subscription{}).
		Where("status IN ?", []string{"active", "trial"}).
		Distinct("tenant_id").
		Count(&metrics.ActiveTenants); err != nil {
		return nil, fmt.Errorf("failed to get active tenants: %w", err)
	}

	// Average usage metrics
	avgUsage, err := s.getAverageUsageMetrics()
	if err != nil {
		return nil, fmt.Errorf("failed to get average usage: %w", err)
	}
	metrics.AverageLocations = avgUsage.Locations
	metrics.AverageUsers = avgUsage.Users
	metrics.AverageProducts = avgUsage.Products

	// Usage by plan
	usageByPlan, err := s.getUsageByPlan()
	if err != nil {
		return nil, fmt.Errorf("failed to get usage by plan: %w", err)
	}
	metrics.UsageByPlan = usageByPlan

	// Top tenants by usage
	topTenants, err := s.getTopTenantsByUsage(10)
	if err != nil {
		return nil, fmt.Errorf("failed to get top tenants: %w", err)
	}
	metrics.TopTenants = topTenants

	return metrics, nil
}

// Helper methods

func (s *AnalyticsService) calculateChurnRate(currentMonth time.Time) (float64, error) {
	// Active subscriptions last month
	var activeLastMonth int64
	if err := s.db.Model(&models.Subscription{}).
		Where("status = 'active' AND created_at < ?", currentMonth).
		Count(&activeLastMonth).Error; err != nil {
		return 0, err
	}

	// Cancelled this month
	var cancelledThisMonth int64
	if err := s.db.Model(&models.Subscription{}).
		Where("status = 'cancelled' AND cancelled_at >= ? AND cancelled_at < ?", currentMonth, currentMonth.AddDate(0, 1, 0)).
		Count(&cancelledThisMonth).Error; err != nil {
		return 0, err
	}

	if activeLastMonth == 0 {
		return 0, nil
	}

	return float64(cancelledThisMonth) / float64(activeLastMonth) * 100, nil
}

func (s *AnalyticsService) getPlanDistribution() (map[string]int, error) {
	var results []struct {
		PlanName string `json:"plan_name"`
		Count    int    `json:"count"`
	}

	err := s.db.Table("subscriptions").
		Select("pricing_plans.display_name as plan_name, COUNT(*) as count").
		Joins("JOIN pricing_plans ON subscriptions.plan_id = pricing_plans.id").
		Where("subscriptions.status IN ?", []string{"active", "trial"}).
		Group("pricing_plans.display_name").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	distribution := make(map[string]int)
	for _, result := range results {
		distribution[result.PlanName] = result.Count
	}

	return distribution, nil
}

func (s *AnalyticsService) getRevenueByPlan() (map[string]float64, error) {
	var results []struct {
		PlanName string  `json:"plan_name"`
		Revenue  float64 `json:"revenue"`
	}

	err := s.db.Table("payments").
		Select("pricing_plans.display_name as plan_name, COALESCE(SUM(payments.amount), 0) as revenue").
		Joins("JOIN subscriptions ON payments.subscription_id = subscriptions.id").
		Joins("JOIN pricing_plans ON subscriptions.plan_id = pricing_plans.id").
		Where("payments.status = 'succeeded'").
		Group("pricing_plans.display_name").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	revenue := make(map[string]float64)
	for _, result := range results {
		revenue[result.PlanName] = result.Revenue
	}

	return revenue, nil
}

func (s *AnalyticsService) getMonthlyGrowth() (map[string]float64, error) {
	// Simplified monthly growth calculation
	growth := make(map[string]float64)
	
	// Calculate subscription growth
	currentMonth := time.Now().Truncate(24 * time.Hour).AddDate(0, 0, -time.Now().Day()+1)
	lastMonth := currentMonth.AddDate(0, -1, 0)

	var currentMonthSubs, lastMonthSubs int64
	
	if err := s.db.Model(&models.Subscription{}).
		Where("created_at >= ?", currentMonth).
		Count(&currentMonthSubs).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Subscription{}).
		Where("created_at >= ? AND created_at < ?", lastMonth, currentMonth).
		Count(&lastMonthSubs).Error; err != nil {
		return nil, err
	}

	if lastMonthSubs > 0 {
		growth["subscriptions"] = float64(currentMonthSubs-lastMonthSubs) / float64(lastMonthSubs) * 100
	}

	// Calculate revenue growth
	var currentMonthRevenue, lastMonthRevenue float64
	
	if err := s.db.Model(&models.Payment{}).
		Where("status = 'succeeded' AND created_at >= ?", currentMonth).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&currentMonthRevenue).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Payment{}).
		Where("status = 'succeeded' AND created_at >= ? AND created_at < ?", lastMonth, currentMonth).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&lastMonthRevenue).Error; err != nil {
		return nil, err
	}

	if lastMonthRevenue > 0 {
		growth["revenue"] = (currentMonthRevenue - lastMonthRevenue) / lastMonthRevenue * 100
	}

	return growth, nil
}

func (s *AnalyticsService) getDailyRevenue(startDate, endDate time.Time) ([]DailyRevenue, error) {
	var results []DailyRevenue

	err := s.db.Table("payments").
		Select("DATE(created_at) as date, COALESCE(SUM(amount), 0) as revenue, COUNT(*) as transactions").
		Where("status = 'succeeded' AND created_at BETWEEN ? AND ?", startDate, endDate).
		Group("DATE(created_at)").
		Order("date").
		Scan(&results).Error

	return results, err
}

func (s *AnalyticsService) getPaymentMethodsBreakdown(startDate, endDate time.Time) (map[string]float64, error) {
	var results []struct {
		PaymentMethod string  `json:"payment_method"`
		Revenue       float64 `json:"revenue"`
	}

	err := s.db.Table("payments").
		Select("COALESCE(payment_method, 'unknown') as payment_method, COALESCE(SUM(amount), 0) as revenue").
		Where("status = 'succeeded' AND created_at BETWEEN ? AND ?", startDate, endDate).
		Group("payment_method").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	methods := make(map[string]float64)
	for _, result := range results {
		methods[result.PaymentMethod] = result.Revenue
	}

	return methods, nil
}

func (s *AnalyticsService) getTopPlansByRevenue(startDate, endDate time.Time, limit int) ([]PlanRevenue, error) {
	var results []PlanRevenue

	err := s.db.Table("payments").
		Select("pricing_plans.display_name as plan_name, COALESCE(SUM(payments.amount), 0) as revenue, COUNT(payments.id) as transactions").
		Joins("JOIN subscriptions ON payments.subscription_id = subscriptions.id").
		Joins("JOIN pricing_plans ON subscriptions.plan_id = pricing_plans.id").
		Where("payments.status = 'succeeded' AND payments.created_at BETWEEN ? AND ?", startDate, endDate).
		Group("pricing_plans.id, pricing_plans.display_name").
		Order("revenue DESC").
		Limit(limit).
		Scan(&results).Error

	return results, err
}

func (s *AnalyticsService) getRevenueByStatus(startDate, endDate time.Time) (map[string]float64, error) {
	var results []struct {
		Status  string  `json:"status"`
		Revenue float64 `json:"revenue"`
	}

	err := s.db.Table("payments").
		Select("status, COALESCE(SUM(amount), 0) as revenue").
		Where("created_at BETWEEN ? AND ?", startDate, endDate).
		Group("status").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	revenue := make(map[string]float64)
	for _, result := range results {
		revenue[result.Status] = result.Revenue
	}

	return revenue, nil
}

func (s *AnalyticsService) getSubscriptionStatusDistribution() (map[string]int, error) {
	var results []struct {
		Status string `json:"status"`
		Count  int    `json:"count"`
	}

	err := s.db.Table("subscriptions").
		Select("status, COUNT(*) as count").
		Group("status").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	distribution := make(map[string]int)
	for _, result := range results {
		distribution[result.Status] = result.Count
	}

	return distribution, nil
}

func (s *AnalyticsService) getBillingCycleBreakdown() (map[string]int, error) {
	var results []struct {
		BillingCycle string `json:"billing_cycle"`
		Count        int    `json:"count"`
	}

	err := s.db.Table("subscriptions").
		Select("billing_cycle, COUNT(*) as count").
		Where("status IN ?", []string{"active", "trial"}).
		Group("billing_cycle").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	breakdown := make(map[string]int)
	for _, result := range results {
		breakdown[result.BillingCycle] = result.Count
	}

	return breakdown, nil
}

func (s *AnalyticsService) getPlanPopularity() ([]PlanPopularity, error) {
	var results []PlanPopularity

	err := s.db.Table("subscriptions").
		Select("pricing_plans.display_name as plan_name, COUNT(subscriptions.id) as subscriptions, COALESCE(AVG(subscriptions.amount), 0) as average_revenue").
		Joins("JOIN pricing_plans ON subscriptions.plan_id = pricing_plans.id").
		Where("subscriptions.status IN ?", []string{"active", "trial"}).
		Group("pricing_plans.id, pricing_plans.display_name").
		Order("subscriptions DESC").
		Scan(&results).Error

	return results, err
}

func (s *AnalyticsService) getConversionRates() (map[string]float64, error) {
	rates := make(map[string]float64)
	
	// Trial to active conversion
	var trialCount, activeFromTrialCount int64
	
	if err := s.db.Model(&models.Subscription{}).Where("status = 'trial'").Count(&trialCount).Error; err != nil {
		return nil, err
	}
	
	// Simplified: count active subscriptions that had a trial period
	if err := s.db.Model(&models.Subscription{}).
		Where("status = 'active' AND trial_start IS NOT NULL").
		Count(&activeFromTrialCount).Error; err != nil {
		return nil, err
	}

	if trialCount+activeFromTrialCount > 0 {
		rates["trial_to_active"] = float64(activeFromTrialCount) / float64(trialCount+activeFromTrialCount) * 100
	}

	return rates, nil
}

func (s *AnalyticsService) getAverageUsageMetrics() (*TenantUsage, error) {
	var usage TenantUsage

	err := s.db.Table("usage_records").
		Select("COALESCE(AVG(locations), 0) as locations, COALESCE(AVG(users), 0) as users, COALESCE(AVG(products), 0) as products").
		Where("record_date >= ?", time.Now().AddDate(0, 0, -30)). // Last 30 days
		Scan(&usage).Error

	return &usage, err
}

func (s *AnalyticsService) getUsageByPlan() (map[string]TenantUsage, error) {
	var results []struct {
		PlanName  string  `json:"plan_name"`
		Locations float64 `json:"avg_locations"`
		Users     float64 `json:"avg_users"`
		Products  float64 `json:"avg_products"`
	}

	err := s.db.Table("usage_records").
		Select("pricing_plans.display_name as plan_name, COALESCE(AVG(usage_records.locations), 0) as avg_locations, COALESCE(AVG(usage_records.users), 0) as avg_users, COALESCE(AVG(usage_records.products), 0) as avg_products").
		Joins("JOIN subscriptions ON usage_records.subscription_id = subscriptions.id").
		Joins("JOIN pricing_plans ON subscriptions.plan_id = pricing_plans.id").
		Where("usage_records.record_date >= ?", time.Now().AddDate(0, 0, -30)).
		Group("pricing_plans.id, pricing_plans.display_name").
		Scan(&results).Error

	if err != nil {
		return nil, err
	}

	usage := make(map[string]TenantUsage)
	for _, result := range results {
		usage[result.PlanName] = TenantUsage{
			Locations: result.Locations,
			Users:     result.Users,
			Products:  result.Products,
		}
	}

	return usage, nil
}

func (s *AnalyticsService) getTopTenantsByUsage(limit int) ([]TopTenant, error) {
	var results []TopTenant

	err := s.db.Table("usage_records").
		Select("tenant_id, COALESCE(AVG(locations + users + products), 0) as total_usage").
		Where("record_date >= ?", time.Now().AddDate(0, 0, -30)).
		Group("tenant_id").
		Order("total_usage DESC").
		Limit(limit).
		Scan(&results).Error

	return results, err
}

// Analytics structs

type RevenueAnalytics struct {
	Period          string                 `json:"period"`
	StartDate       time.Time              `json:"start_date"`
	EndDate         time.Time              `json:"end_date"`
	TotalRevenue    float64                `json:"total_revenue"`
	DailyRevenue    []DailyRevenue         `json:"daily_revenue"`
	PaymentMethods  map[string]float64     `json:"payment_methods"`
	TopPlans        []PlanRevenue          `json:"top_plans"`
	RevenueByStatus map[string]float64     `json:"revenue_by_status"`
}

type DailyRevenue struct {
	Date         string  `json:"date"`
	Revenue      float64 `json:"revenue"`
	Transactions int     `json:"transactions"`
}

type PlanRevenue struct {
	PlanName     string  `json:"plan_name"`
	Revenue      float64 `json:"revenue"`
	Transactions int     `json:"transactions"`
}

type SubscriptionMetrics struct {
	Period                    string                  `json:"period"`
	TotalSubscriptions        int64                   `json:"total_subscriptions"`
	StatusDistribution        map[string]int          `json:"status_distribution"`
	BillingCycleBreakdown     map[string]int          `json:"billing_cycle_breakdown"`
	PlanPopularity            []PlanPopularity        `json:"plan_popularity"`
	ConversionRates           map[string]float64      `json:"conversion_rates"`
	AverageSubscriptionValue  float64                 `json:"average_subscription_value"`
}

type PlanPopularity struct {
	PlanName        string  `json:"plan_name"`
	Subscriptions   int     `json:"subscriptions"`
	AverageRevenue  float64 `json:"average_revenue"`
}

type TenantMetrics struct {
	TotalTenants     int64                   `json:"total_tenants"`
	ActiveTenants    int64                   `json:"active_tenants"`
	AverageLocations float64                 `json:"average_locations"`
	AverageUsers     float64                 `json:"average_users"`
	AverageProducts  float64                 `json:"average_products"`
	UsageByPlan      map[string]TenantUsage  `json:"usage_by_plan"`
	TopTenants       []TopTenant             `json:"top_tenants"`
}

type TenantUsage struct {
	Locations float64 `json:"locations"`
	Users     float64 `json:"users"`
	Products  float64 `json:"products"`
}

type TopTenant struct {
	TenantID   uuid.UUID `json:"tenant_id"`
	TotalUsage float64   `json:"total_usage"`
}