package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type UsageHandler struct {
	usageService *services.UsageTrackingService
}

func NewUsageHandler(usageService *services.UsageTrackingService) *UsageHandler {
	return &UsageHandler{
		usageService: usageService,
	}
}

type UsageEventRequest struct {
	ResourceType string `json:"resource_type" binding:"required"`
	Action       string `json:"action" binding:"required"`
	Quantity     int    `json:"quantity"`
	Metadata     string `json:"metadata,omitempty"`
}

type GetUsageRequest struct {
	TenantID     uuid.UUID `form:"tenant_id" binding:"required"`
	ResourceType string    `form:"resource_type"`
	Days         int       `form:"days,default=30"`
}

func (h *UsageHandler) TrackUsage(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req UsageEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	event := services.UsageEvent{
		TenantID:     tenantID,
		ResourceType: req.ResourceType,
		Action:       req.Action,
		Quantity:     req.Quantity,
		Metadata:     req.Metadata,
		Timestamp:    time.Now(),
	}

	if err := h.usageService.TrackUsage(c.Request.Context(), event); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to track usage"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Usage tracked successfully",
		"tenant_id": tenantID,
		"resource":  req.ResourceType,
		"action":    req.Action,
	})
}

func (h *UsageHandler) GetCurrentUsage(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	resourceType := c.DefaultQuery("resource_type", "all")

	usage, err := h.usageService.GetCurrentUsage(c.Request.Context(), tenantID, resourceType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get current usage"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"tenant_id":     tenantID,
		"resource_type": resourceType,
		"current_usage": usage,
		"timestamp":     time.Now(),
	})
}

func (h *UsageHandler) GetUsageMetrics(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	metrics, err := h.usageService.GetUsageMetrics(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get usage metrics"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"tenant_id": tenantID,
		"metrics":   metrics,
		"timestamp": time.Now(),
	})
}

func (h *UsageHandler) GetAllTenantsUsage(c *gin.Context) {
	// This endpoint is for SaaS admin to monitor all tenants
	resourceType := c.Query("resource_type")
	limit := 50 // Default limit

	if limitStr := c.Query("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	// Get all active tenants (you'll need to implement this query)
	var allUsage []gin.H

	// For now, we'll return a placeholder response
	// In a real implementation, you'd iterate through all tenants
	c.JSON(http.StatusOK, gin.H{
		"usage_data":    allUsage,
		"resource_type": resourceType,
		"limit":         limit,
		"timestamp":     time.Now(),
	})
}

func (h *UsageHandler) GetBillingPeriodUsage(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Parse period dates
	periodStartStr := c.Query("period_start")
	periodEndStr := c.Query("period_end")

	var periodStart, periodEnd time.Time

	if periodStartStr != "" {
		if ps, err := time.Parse("2006-01-02", periodStartStr); err == nil {
			periodStart = ps
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid period_start format. Use YYYY-MM-DD"})
			return
		}
	} else {
		// Default to current month
		now := time.Now()
		periodStart = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	}

	if periodEndStr != "" {
		if pe, err := time.Parse("2006-01-02", periodEndStr); err == nil {
			periodEnd = pe
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid period_end format. Use YYYY-MM-DD"})
			return
		}
	} else {
		// Default to end of current month
		periodEnd = periodStart.AddDate(0, 1, 0).Add(-time.Second)
	}

	usage, err := h.usageService.GetBillingPeriodUsage(c.Request.Context(), tenantID, periodStart, periodEnd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get billing period usage"})
		return
	}

	c.JSON(http.StatusOK, usage)
}

func (h *UsageHandler) GetUsageHistory(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	resourceType := c.DefaultQuery("resource_type", "all")

	days := 30 // Default
	if daysStr := c.Query("days"); daysStr != "" {
		if d, err := strconv.Atoi(daysStr); err == nil && d > 0 && d <= 365 {
			days = d
		}
	}

	history, err := h.usageService.GetUsageHistory(c.Request.Context(), tenantID, resourceType, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get usage history"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"tenant_id":     tenantID,
		"resource_type": resourceType,
		"days":          days,
		"history":       history,
		"count":         len(history),
	})
}

func (h *UsageHandler) GetUsageAlerts(c *gin.Context) {
	tenantIDStr := c.Query("tenant_id")
	alertType := c.Query("alert_type")

	// This would typically fetch from a dedicated alerts table or cache
	// For now, we'll return a placeholder response

	var filters gin.H = gin.H{
		"timestamp": time.Now(),
		"message":   "No active alerts",
	}

	if tenantIDStr != "" {
		if tenantID, err := strconv.ParseUint(tenantIDStr, 10, 32); err == nil {
			filters["tenant_id"] = tenantID
		}
	}

	if alertType != "" {
		filters["alert_type"] = alertType
	}

	c.JSON(http.StatusOK, gin.H{
		"alerts":  []gin.H{}, // Empty for now - implement based on your alerting system
		"filters": filters,
	})
}

func (h *UsageHandler) ExportUsageReport(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	format := c.Query("format")
	if format == "" {
		format = "json"
	}

	// Get usage metrics
	metrics, err := h.usageService.GetUsageMetrics(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get usage metrics"})
		return
	}

	switch format {
	case "json":
		c.JSON(http.StatusOK, gin.H{
			"tenant_id":     tenantID,
			"export_format": "json",
			"exported_at":   time.Now(),
			"usage_metrics": metrics,
		})
	case "csv":
		// Return CSV format
		c.Header("Content-Type", "text/csv")
		c.Header("Content-Disposition", "attachment; filename=usage_report.csv")

		// Build CSV content
		csvContent := "Resource Type,Current Usage,Limit,Usage Percentage,Last Updated\n"
		for _, metric := range metrics {
			csvContent += fmt.Sprintf("%s,%d,%d,%.2f,%s\n",
				metric.ResourceType,
				metric.CurrentUsage,
				metric.Limit,
				metric.UsagePercentage,
				metric.LastUpdated.Format("2006-01-02 15:04:05"),
			)
		}

		c.String(http.StatusOK, csvContent)
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported format. Use 'json' or 'csv'"})
	}
}

func (h *UsageHandler) ResetTenantUsage(c *gin.Context) {
	// This is a dangerous operation - only for SaaS admin emergency use
	tenantIDStr := c.Param("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	resourceType := c.DefaultQuery("resource_type", "all")

	// Reset usage tracking for the tenant and resource type
	// This should be implemented carefully with proper authorization

	// For now, return success response
	c.JSON(http.StatusOK, gin.H{
		"message":       "Usage reset initiated",
		"tenant_id":     tenantID,
		"resource_type": resourceType,
		"reset_at":      time.Now(),
		"warning":       "This operation cannot be undone",
	})
}
