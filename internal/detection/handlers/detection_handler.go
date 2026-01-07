package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/detection/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// DetectionHandler handles fraud detection HTTP endpoints
type DetectionHandler struct {
	service *services.DetectionService
}

// NewDetectionHandler creates a new detection handler
func NewDetectionHandler(service *services.DetectionService) *DetectionHandler {
	return &DetectionHandler{service: service}
}

// RegisterRoutes registers detection routes with the router
func (h *DetectionHandler) RegisterRoutes(router *gin.RouterGroup) {
	detection := router.Group("/detection")
	{
		// Alerts management
		detection.GET("/alerts", h.GetAlerts)
		detection.GET("/alerts/:id", h.GetAlert)
		detection.POST("/alerts/:id/acknowledge", h.AcknowledgeAlert)
		detection.POST("/alerts/:id/resolve", h.ResolveAlert)
		detection.POST("/alerts/:id/false-positive", h.MarkFalsePositive)

		// Analytics and reporting
		detection.GET("/analytics/summary", h.GetAnalyticsSummary)
		detection.GET("/analytics/trends", h.GetTrends)
		detection.GET("/analytics/by-employee", h.GetByEmployee)
		detection.GET("/analytics/by-type", h.GetByType)

		// Configuration
		detection.GET("/config/thresholds", h.GetThresholds)
		detection.PUT("/config/thresholds", h.UpdateThresholds)

		// Manual analysis triggers
		detection.POST("/analyze/transaction/:id", h.AnalyzeTransaction)
		detection.POST("/analyze/employee/:id", h.AnalyzeEmployee)
		detection.POST("/analyze/batch", h.BatchAnalyze)
	}
}

// GetAlertsRequest defines the request parameters for listing alerts
type GetAlertsRequest struct {
	Status     string    `form:"status"`
	AlertType  string    `form:"alert_type"`
	Severity   string    `form:"severity"`
	EmployeeID string    `form:"employee_id"`
	StartDate  time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate    time.Time `form:"end_date" time_format:"2006-01-02"`
	Page       int       `form:"page,default=1"`
	PageSize   int       `form:"page_size,default=20"`
}

// GetAlerts retrieves fraud detection alerts with filtering
// @Summary Get fraud detection alerts
// @Description Retrieves a paginated list of fraud detection alerts with optional filtering
// @Tags Detection
// @Accept json
// @Produce json
// @Param status query string false "Alert status filter (open, acknowledged, resolved, false_positive)"
// @Param alert_type query string false "Alert type filter"
// @Param severity query string false "Severity filter (low, medium, high, critical)"
// @Param employee_id query string false "Employee ID filter"
// @Param start_date query string false "Start date filter (YYYY-MM-DD)"
// @Param end_date query string false "End date filter (YYYY-MM-DD)"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/alerts [get]
func (h *DetectionHandler) GetAlerts(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	var req GetAlertsRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid query parameters", "details": err.Error()})
		return
	}

	// Validate pagination
	if req.Page < 1 {
		req.Page = 1
	}
	if req.PageSize < 1 || req.PageSize > 100 {
		req.PageSize = 20
	}

	// Build filter
	filter := services.AlertFilter{
		TenantID: tenantID.(uuid.UUID),
		Status:   req.Status,
		Type:     req.AlertType,
		Severity: req.Severity,
		Page:     req.Page,
		PageSize: req.PageSize,
	}

	if req.EmployeeID != "" {
		empID, err := uuid.Parse(req.EmployeeID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid employee_id format"})
			return
		}
		filter.EmployeeID = &empID
	}

	if !req.StartDate.IsZero() {
		filter.StartDate = &req.StartDate
	}
	if !req.EndDate.IsZero() {
		filter.EndDate = &req.EndDate
	}

	alerts, total, err := h.service.GetAlerts(c.Request.Context(), filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve alerts", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": alerts,
		"pagination": gin.H{
			"page":        req.Page,
			"page_size":   req.PageSize,
			"total":       total,
			"total_pages": (total + int64(req.PageSize) - 1) / int64(req.PageSize),
		},
	})
}

// GetAlert retrieves a single fraud detection alert
// @Summary Get a fraud detection alert
// @Description Retrieves a single fraud detection alert by ID
// @Tags Detection
// @Accept json
// @Produce json
// @Param id path string true "Alert ID"
// @Success 200 {object} models.FraudAlert
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/alerts/{id} [get]
func (h *DetectionHandler) GetAlert(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID format"})
		return
	}

	alert, err := h.service.GetAlertByID(c.Request.Context(), tenantID.(uuid.UUID), alertID)
	if err != nil {
		if err.Error() == "alert not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Alert not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve alert", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alert})
}

// AcknowledgeAlert marks an alert as acknowledged
// @Summary Acknowledge a fraud detection alert
// @Description Marks an alert as acknowledged by the current user
// @Tags Detection
// @Accept json
// @Produce json
// @Param id path string true "Alert ID"
// @Param body body map[string]string false "Acknowledgement notes"
// @Success 200 {object} models.FraudAlert
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/alerts/{id}/acknowledge [post]
func (h *DetectionHandler) AcknowledgeAlert(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID format"})
		return
	}

	var req struct {
		Notes string `json:"notes"`
	}
	c.ShouldBindJSON(&req)

	alert, err := h.service.AcknowledgeAlert(c.Request.Context(), tenantID.(uuid.UUID), alertID, userID.(uuid.UUID), req.Notes)
	if err != nil {
		if err.Error() == "alert not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Alert not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to acknowledge alert", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alert, "message": "Alert acknowledged successfully"})
}

// ResolveAlertRequest defines the request body for resolving an alert
type ResolveAlertRequest struct {
	Resolution string `json:"resolution" binding:"required"`
	Notes      string `json:"notes"`
}

// ResolveAlert marks an alert as resolved
// @Summary Resolve a fraud detection alert
// @Description Marks an alert as resolved with a resolution description
// @Tags Detection
// @Accept json
// @Produce json
// @Param id path string true "Alert ID"
// @Param body body ResolveAlertRequest true "Resolution details"
// @Success 200 {object} models.FraudAlert
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/alerts/{id}/resolve [post]
func (h *DetectionHandler) ResolveAlert(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID format"})
		return
	}

	var req ResolveAlertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	alert, err := h.service.ResolveAlert(c.Request.Context(), tenantID.(uuid.UUID), alertID, userID.(uuid.UUID), req.Resolution, req.Notes)
	if err != nil {
		if err.Error() == "alert not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Alert not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to resolve alert", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alert, "message": "Alert resolved successfully"})
}

// MarkFalsePositive marks an alert as a false positive
// @Summary Mark alert as false positive
// @Description Marks an alert as a false positive with a reason
// @Tags Detection
// @Accept json
// @Produce json
// @Param id path string true "Alert ID"
// @Param body body map[string]string true "Reason for marking as false positive"
// @Success 200 {object} models.FraudAlert
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/alerts/{id}/false-positive [post]
func (h *DetectionHandler) MarkFalsePositive(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	alertID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid alert ID format"})
		return
	}

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Reason is required"})
		return
	}

	alert, err := h.service.MarkFalsePositive(c.Request.Context(), tenantID.(uuid.UUID), alertID, userID.(uuid.UUID), req.Reason)
	if err != nil {
		if err.Error() == "alert not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Alert not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark as false positive", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": alert, "message": "Alert marked as false positive"})
}

// GetAnalyticsSummary retrieves fraud detection analytics summary
// @Summary Get fraud detection analytics summary
// @Description Retrieves summary analytics for fraud detection
// @Tags Detection
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month, quarter, year)" default(month)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analytics/summary [get]
func (h *DetectionHandler) GetAnalyticsSummary(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")

	summary, err := h.service.GetAnalyticsSummary(c.Request.Context(), tenantID.(uuid.UUID), period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve analytics summary", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": summary})
}

// GetTrends retrieves fraud detection trend data
// @Summary Get fraud detection trends
// @Description Retrieves trend data for fraud detection over time
// @Tags Detection
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month)" default(month)
// @Param group_by query string false "Grouping (day, week, month)" default(day)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analytics/trends [get]
func (h *DetectionHandler) GetTrends(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")
	groupBy := c.DefaultQuery("group_by", "day")

	trends, err := h.service.GetTrends(c.Request.Context(), tenantID.(uuid.UUID), period, groupBy)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve trends", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": trends})
}

// GetByEmployee retrieves fraud detection metrics grouped by employee
// @Summary Get fraud detection by employee
// @Description Retrieves fraud detection metrics grouped by employee
// @Tags Detection
// @Accept json
// @Produce json
// @Param period query string false "Time period (week, month, quarter)" default(month)
// @Param limit query int false "Number of employees to return" default(10)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analytics/by-employee [get]
func (h *DetectionHandler) GetByEmployee(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")
	limit := 10
	if l := c.Query("limit"); l != "" {
		if parsed, err := parseIntParam(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}

	data, err := h.service.GetByEmployee(c.Request.Context(), tenantID.(uuid.UUID), period, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve employee metrics", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": data})
}

// GetByType retrieves fraud detection metrics grouped by alert type
// @Summary Get fraud detection by type
// @Description Retrieves fraud detection metrics grouped by alert type
// @Tags Detection
// @Accept json
// @Produce json
// @Param period query string false "Time period (week, month, quarter)" default(month)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analytics/by-type [get]
func (h *DetectionHandler) GetByType(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")

	data, err := h.service.GetByType(c.Request.Context(), tenantID.(uuid.UUID), period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve type metrics", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": data})
}

// GetThresholds retrieves the current detection thresholds
// @Summary Get detection thresholds
// @Description Retrieves the current fraud detection threshold configuration
// @Tags Detection
// @Accept json
// @Produce json
// @Success 200 {object} models.DetectionThresholds
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/config/thresholds [get]
func (h *DetectionHandler) GetThresholds(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	thresholds, err := h.service.GetThresholds(c.Request.Context(), tenantID.(uuid.UUID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve thresholds", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": thresholds})
}

// UpdateThresholdsRequest defines the request body for updating thresholds
type UpdateThresholdsRequest struct {
	VoidThreshold           *float64 `json:"void_threshold"`
	RefundThreshold         *float64 `json:"refund_threshold"`
	DiscountThreshold       *float64 `json:"discount_threshold"`
	CashVarianceThreshold   *float64 `json:"cash_variance_threshold"`
	ShortageThreshold       *float64 `json:"shortage_threshold"`
	HighValueTransaction    *float64 `json:"high_value_transaction"`
	RapidTransactionMinutes *int     `json:"rapid_transaction_minutes"`
	RapidTransactionCount   *int     `json:"rapid_transaction_count"`
}

// UpdateThresholds updates the detection thresholds
// @Summary Update detection thresholds
// @Description Updates the fraud detection threshold configuration
// @Tags Detection
// @Accept json
// @Produce json
// @Param body body UpdateThresholdsRequest true "Threshold updates"
// @Success 200 {object} models.DetectionThresholds
// @Failure 400 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/config/thresholds [put]
func (h *DetectionHandler) UpdateThresholds(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	// Check role - only admin/owner can update thresholds
	role, exists := c.Get("role")
	if !exists || (role != "admin" && role != "owner") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin or owner can update detection thresholds"})
		return
	}

	var req UpdateThresholdsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	// Build update map
	updates := make(map[string]interface{})
	if req.VoidThreshold != nil {
		updates["void_threshold"] = *req.VoidThreshold
	}
	if req.RefundThreshold != nil {
		updates["refund_threshold"] = *req.RefundThreshold
	}
	if req.DiscountThreshold != nil {
		updates["discount_threshold"] = *req.DiscountThreshold
	}
	if req.CashVarianceThreshold != nil {
		updates["cash_variance_threshold"] = *req.CashVarianceThreshold
	}
	if req.ShortageThreshold != nil {
		updates["shortage_threshold"] = *req.ShortageThreshold
	}
	if req.HighValueTransaction != nil {
		updates["high_value_transaction"] = *req.HighValueTransaction
	}
	if req.RapidTransactionMinutes != nil {
		updates["rapid_transaction_minutes"] = *req.RapidTransactionMinutes
	}
	if req.RapidTransactionCount != nil {
		updates["rapid_transaction_count"] = *req.RapidTransactionCount
	}

	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No threshold updates provided"})
		return
	}

	thresholds, err := h.service.UpdateThresholds(c.Request.Context(), tenantID.(uuid.UUID), updates)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update thresholds", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": thresholds, "message": "Thresholds updated successfully"})
}

// AnalyzeTransaction triggers fraud analysis for a specific transaction
// @Summary Analyze a transaction for fraud
// @Description Triggers fraud analysis for a specific transaction
// @Tags Detection
// @Accept json
// @Produce json
// @Param id path string true "Transaction ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analyze/transaction/{id} [post]
func (h *DetectionHandler) AnalyzeTransaction(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	transactionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid transaction ID format"})
		return
	}

	result, err := h.service.AnalyzeTransaction(c.Request.Context(), tenantID.(uuid.UUID), transactionID)
	if err != nil {
		if err.Error() == "transaction not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Transaction not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to analyze transaction", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": result})
}

// AnalyzeEmployee triggers fraud analysis for a specific employee
// @Summary Analyze an employee for fraud patterns
// @Description Triggers comprehensive fraud analysis for a specific employee
// @Tags Detection
// @Accept json
// @Produce json
// @Param id path string true "Employee ID"
// @Param period query string false "Analysis period (week, month, quarter)" default(month)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analyze/employee/{id} [post]
func (h *DetectionHandler) AnalyzeEmployee(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	employeeID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid employee ID format"})
		return
	}

	period := c.DefaultQuery("period", "month")

	result, err := h.service.AnalyzeEmployee(c.Request.Context(), tenantID.(uuid.UUID), employeeID, period)
	if err != nil {
		if err.Error() == "employee not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Employee not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to analyze employee", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": result})
}

// BatchAnalyzeRequest defines the request body for batch analysis
type BatchAnalyzeRequest struct {
	TransactionIDs []string `json:"transaction_ids"`
	EmployeeIDs    []string `json:"employee_ids"`
	Period         string   `json:"period"`
}

// BatchAnalyze triggers batch fraud analysis
// @Summary Batch analyze for fraud
// @Description Triggers fraud analysis for multiple transactions or employees
// @Tags Detection
// @Accept json
// @Produce json
// @Param body body BatchAnalyzeRequest true "Batch analysis request"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/detection/analyze/batch [post]
func (h *DetectionHandler) BatchAnalyze(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	var req BatchAnalyzeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body", "details": err.Error()})
		return
	}

	if len(req.TransactionIDs) == 0 && len(req.EmployeeIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one transaction_id or employee_id is required"})
		return
	}

	// Limit batch size
	if len(req.TransactionIDs) > 100 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 100 transactions per batch"})
		return
	}
	if len(req.EmployeeIDs) > 50 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 50 employees per batch"})
		return
	}

	// Parse UUIDs
	var transactionIDs []uuid.UUID
	for _, id := range req.TransactionIDs {
		parsed, err := uuid.Parse(id)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid transaction ID: " + id})
			return
		}
		transactionIDs = append(transactionIDs, parsed)
	}

	var employeeIDs []uuid.UUID
	for _, id := range req.EmployeeIDs {
		parsed, err := uuid.Parse(id)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid employee ID: " + id})
			return
		}
		employeeIDs = append(employeeIDs, parsed)
	}

	period := req.Period
	if period == "" {
		period = "month"
	}

	result, err := h.service.BatchAnalyze(c.Request.Context(), tenantID.(uuid.UUID), transactionIDs, employeeIDs, period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to perform batch analysis", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": result, "message": "Batch analysis completed"})
}

// Helper function to parse int parameters
func parseIntParam(s string) (int, error) {
	var result int
	_, err := fmt.Sscanf(s, "%d", &result)
	return result, err
}

// Ensure fmt import is used
var _ = fmt.Sprintf
