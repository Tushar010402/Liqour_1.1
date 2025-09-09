package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/liquorpro/go-backend/internal/saas/services"
)

type AnalyticsHandler struct {
	analyticsService *services.AnalyticsService
}

func NewAnalyticsHandler(analyticsService *services.AnalyticsService) *AnalyticsHandler {
	return &AnalyticsHandler{
		analyticsService: analyticsService,
	}
}

func (h *AnalyticsHandler) GetDashboard(c *gin.Context) {
	metrics, err := h.analyticsService.GetDashboardMetrics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

func (h *AnalyticsHandler) GetRevenue(c *gin.Context) {
	// Parse period and date range
	period := c.DefaultQuery("period", "monthly")
	startDateStr := c.Query("start_date")
	endDateStr := c.Query("end_date")

	// Default to current month if no dates provided
	var startDate, endDate time.Time
	var err error

	if startDateStr != "" && endDateStr != "" {
		startDate, err = time.Parse("2006-01-02", startDateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start_date format (use YYYY-MM-DD)"})
			return
		}

		endDate, err = time.Parse("2006-01-02", endDateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end_date format (use YYYY-MM-DD)"})
			return
		}
	} else {
		// Default to current month
		now := time.Now()
		startDate = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
		endDate = startDate.AddDate(0, 1, 0).Add(-time.Second)
	}

	analytics, err := h.analyticsService.GetRevenueAnalytics(c.Request.Context(), period, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, analytics)
}

func (h *AnalyticsHandler) GetSubscriptionMetrics(c *gin.Context) {
	period := c.DefaultQuery("period", "monthly")

	metrics, err := h.analyticsService.GetSubscriptionMetrics(c.Request.Context(), period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

func (h *AnalyticsHandler) GetTenantMetrics(c *gin.Context) {
	metrics, err := h.analyticsService.GetTenantMetrics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

func (h *AnalyticsHandler) GetRevenueChart(c *gin.Context) {
	// Parse chart parameters
	chartType := c.DefaultQuery("type", "daily") // daily, weekly, monthly
	period := c.DefaultQuery("period", "30")     // number of days/weeks/months
	
	var startDate, endDate time.Time
	now := time.Now()

	switch chartType {
	case "daily":
		// Last N days
		if period == "" {
			period = "30"
		}
		days := 30 // default
		if p, err := time.ParseDuration(period + "h"); err == nil {
			days = int(p.Hours() / 24)
		}
		startDate = now.AddDate(0, 0, -days)
		endDate = now
	case "weekly":
		// Last N weeks
		weeks := 12 // default
		startDate = now.AddDate(0, 0, -weeks*7)
		endDate = now
	case "monthly":
		// Last N months
		months := 12 // default
		startDate = now.AddDate(0, -months, 0)
		endDate = now
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid chart type"})
		return
	}

	analytics, err := h.analyticsService.GetRevenueAnalytics(c.Request.Context(), chartType, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Format response for charting
	chartData := gin.H{
		"type":         chartType,
		"period":       period,
		"start_date":   startDate.Format("2006-01-02"),
		"end_date":     endDate.Format("2006-01-02"),
		"total_revenue": analytics.TotalRevenue,
		"data_points":  analytics.DailyRevenue,
	}

	c.JSON(http.StatusOK, chartData)
}

func (h *AnalyticsHandler) GetSubscriptionChart(c *gin.Context) {
	chartType := c.DefaultQuery("type", "status") // status, plans, billing_cycle
	
	metrics, err := h.analyticsService.GetSubscriptionMetrics(c.Request.Context(), "current")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var chartData gin.H

	switch chartType {
	case "status":
		chartData = gin.H{
			"type":   "pie",
			"title":  "Subscriptions by Status",
			"data":   metrics.StatusDistribution,
			"total":  metrics.TotalSubscriptions,
		}
	case "plans":
		planData := make(map[string]interface{})
		for _, plan := range metrics.PlanPopularity {
			planData[plan.PlanName] = plan.Subscriptions
		}
		chartData = gin.H{
			"type":   "bar",
			"title":  "Subscriptions by Plan",
			"data":   planData,
			"total":  metrics.TotalSubscriptions,
		}
	case "billing_cycle":
		chartData = gin.H{
			"type":   "pie",
			"title":  "Subscriptions by Billing Cycle",
			"data":   metrics.BillingCycleBreakdown,
			"total":  metrics.TotalSubscriptions,
		}
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid chart type"})
		return
	}

	c.JSON(http.StatusOK, chartData)
}

func (h *AnalyticsHandler) GetTenantChart(c *gin.Context) {
	chartType := c.DefaultQuery("type", "usage") // usage, plans
	
	metrics, err := h.analyticsService.GetTenantMetrics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var chartData gin.H

	switch chartType {
	case "usage":
		usageData := gin.H{
			"locations": metrics.AverageLocations,
			"users":     metrics.AverageUsers,
			"products":  metrics.AverageProducts,
		}
		chartData = gin.H{
			"type":  "bar",
			"title": "Average Resource Usage",
			"data":  usageData,
		}
	case "plans":
		planUsage := make(map[string]interface{})
		for plan, usage := range metrics.UsageByPlan {
			planUsage[plan] = gin.H{
				"locations": usage.Locations,
				"users":     usage.Users,
				"products":  usage.Products,
			}
		}
		chartData = gin.H{
			"type":  "grouped_bar",
			"title": "Usage by Plan",
			"data":  planUsage,
		}
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid chart type"})
		return
	}

	c.JSON(http.StatusOK, chartData)
}

func (h *AnalyticsHandler) GetGrowthMetrics(c *gin.Context) {
	// Get growth metrics for different time periods
	periods := []string{"weekly", "monthly", "quarterly"}
	growthData := make(map[string]interface{})

	for _, period := range periods {
		metrics, err := h.analyticsService.GetSubscriptionMetrics(c.Request.Context(), period)
		if err != nil {
			continue // Skip this period if there's an error
		}

		// Calculate growth rates (simplified)
		growthData[period] = gin.H{
			"subscriptions": metrics.TotalSubscriptions,
			"conversion_rates": metrics.ConversionRates,
		}
	}

	// Get dashboard metrics for overall growth
	dashboard, err := h.analyticsService.GetDashboardMetrics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	response := gin.H{
		"monthly_growth": dashboard.MonthlyGrowth,
		"churn_rate":     dashboard.ChurnRate,
		"new_tenants":    dashboard.NewTenants,
		"periods":        growthData,
	}

	c.JSON(http.StatusOK, response)
}

func (h *AnalyticsHandler) GetTopPerformers(c *gin.Context) {
	category := c.DefaultQuery("category", "plans") // plans, tenants, regions

	switch category {
	case "plans":
		// Get revenue analytics to find top performing plans
		now := time.Now()
		startDate := now.AddDate(0, -1, 0) // Last month
		endDate := now

		analytics, err := h.analyticsService.GetRevenueAnalytics(c.Request.Context(), "monthly", startDate, endDate)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"category":      "plans",
			"top_plans":     analytics.TopPlans,
			"revenue_total": analytics.TotalRevenue,
		})

	case "tenants":
		metrics, err := h.analyticsService.GetTenantMetrics(c.Request.Context())
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"category":     "tenants",
			"top_tenants":  metrics.TopTenants,
			"total_tenants": metrics.TotalTenants,
		})

	case "regions":
		// TODO: Implement regional analytics when location data is available
		c.JSON(http.StatusOK, gin.H{
			"category": "regions",
			"message":  "regional analytics not yet implemented",
		})

	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category"})
		return
	}
}

func (h *AnalyticsHandler) ExportAnalytics(c *gin.Context) {
	format := c.DefaultQuery("format", "json") // json, csv, xlsx
	reportType := c.DefaultQuery("type", "dashboard")

	if format != "json" {
		c.JSON(http.StatusNotImplemented, gin.H{
			"error": "only JSON export is currently supported",
		})
		return
	}

	var data interface{}
	var err error
	var filename string

	switch reportType {
	case "dashboard":
		data, err = h.analyticsService.GetDashboardMetrics(c.Request.Context())
		filename = "dashboard_metrics"
	case "revenue":
		now := time.Now()
		startDate := now.AddDate(0, -1, 0)
		endDate := now
		data, err = h.analyticsService.GetRevenueAnalytics(c.Request.Context(), "monthly", startDate, endDate)
		filename = "revenue_analytics"
	case "subscriptions":
		data, err = h.analyticsService.GetSubscriptionMetrics(c.Request.Context(), "current")
		filename = "subscription_metrics"
	case "tenants":
		data, err = h.analyticsService.GetTenantMetrics(c.Request.Context())
		filename = "tenant_metrics"
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid report type"})
		return
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Set headers for file download
	timestamp := time.Now().Format("20060102_150405")
	c.Header("Content-Type", "application/json")
	c.Header("Content-Disposition", "attachment; filename="+filename+"_"+timestamp+".json")

	c.JSON(http.StatusOK, gin.H{
		"exported_at": time.Now(),
		"report_type": reportType,
		"format":      format,
		"data":        data,
	})
}

// Real-time analytics endpoints

func (h *AnalyticsHandler) GetRealTimeStats(c *gin.Context) {
	// TODO: Implement real-time statistics using WebSocket or Server-Sent Events
	// For now, return current metrics with a timestamp
	metrics, err := h.analyticsService.GetDashboardMetrics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"timestamp": time.Now(),
		"realtime":  true,
		"metrics":   metrics,
	})
}

func (h *AnalyticsHandler) GetLiveTransactions(c *gin.Context) {
	// TODO: Implement live transaction feed
	c.JSON(http.StatusOK, gin.H{
		"message":   "live transactions endpoint - implement with WebSocket",
		"timestamp": time.Now(),
	})
}

// Custom analytics endpoints

func (h *AnalyticsHandler) CreateCustomReport(c *gin.Context) {
	var req struct {
		Name        string                 `json:"name" binding:"required"`
		Description string                 `json:"description"`
		Filters     map[string]interface{} `json:"filters"`
		Metrics     []string               `json:"metrics" binding:"required"`
		Period      string                 `json:"period"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// TODO: Implement custom report generation
	c.JSON(http.StatusCreated, gin.H{
		"message":     "custom report created",
		"report_name": req.Name,
		"report_id":   "custom_" + time.Now().Format("20060102150405"),
		"request":     req,
	})
}

func (h *AnalyticsHandler) GetCustomReport(c *gin.Context) {
	reportID := c.Param("id")

	// TODO: Implement custom report retrieval
	c.JSON(http.StatusOK, gin.H{
		"message":   "custom report retrieval - implement based on requirements",
		"report_id": reportID,
	})
}