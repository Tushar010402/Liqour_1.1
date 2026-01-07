package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/audit/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// AuditHandler handles audit log HTTP endpoints
type AuditHandler struct {
	service *services.AuditService
}

// NewAuditHandler creates a new audit handler
func NewAuditHandler(service *services.AuditService) *AuditHandler {
	return &AuditHandler{service: service}
}

// RegisterRoutes registers audit routes with the router
func (h *AuditHandler) RegisterRoutes(router *gin.RouterGroup) {
	audit := router.Group("/audit")
	{
		// Audit log queries
		audit.GET("/logs", h.GetAuditLogs)
		audit.GET("/logs/:id", h.GetAuditLog)
		audit.GET("/logs/entity/:entity_type/:entity_id", h.GetEntityHistory)

		// Analytics and reporting
		audit.GET("/analytics/summary", h.GetAnalyticsSummary)
		audit.GET("/analytics/by-user", h.GetByUser)
		audit.GET("/analytics/by-action", h.GetByAction)
		audit.GET("/analytics/by-entity", h.GetByEntity)
		audit.GET("/analytics/timeline", h.GetTimeline)

		// Export
		audit.GET("/export", h.ExportAuditLogs)

		// Compliance reports
		audit.GET("/compliance/report", h.GetComplianceReport)
		audit.GET("/compliance/user-activity/:user_id", h.GetUserActivityReport)
	}
}

// GetAuditLogsRequest defines the request parameters for listing audit logs
type GetAuditLogsRequest struct {
	Action     string    `form:"action"`
	EntityType string    `form:"entity_type"`
	EntityID   string    `form:"entity_id"`
	UserID     string    `form:"user_id"`
	StartDate  time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate    time.Time `form:"end_date" time_format:"2006-01-02"`
	Search     string    `form:"search"`
	Page       int       `form:"page,default=1"`
	PageSize   int       `form:"page_size,default=50"`
}

// GetAuditLogs retrieves audit logs with filtering
// @Summary Get audit logs
// @Description Retrieves a paginated list of audit logs with optional filtering
// @Tags Audit
// @Accept json
// @Produce json
// @Param action query string false "Action filter (create, update, delete, view, login, etc.)"
// @Param entity_type query string false "Entity type filter (sale, product, user, etc.)"
// @Param entity_id query string false "Entity ID filter"
// @Param user_id query string false "User ID filter"
// @Param start_date query string false "Start date filter (YYYY-MM-DD)"
// @Param end_date query string false "End date filter (YYYY-MM-DD)"
// @Param search query string false "Search in description"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(50)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/logs [get]
func (h *AuditHandler) GetAuditLogs(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	var req GetAuditLogsRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid query parameters", "details": err.Error()})
		return
	}

	// Validate pagination
	if req.Page < 1 {
		req.Page = 1
	}
	if req.PageSize < 1 || req.PageSize > 500 {
		req.PageSize = 50
	}

	// Build filter
	filter := services.AuditFilter{
		TenantID:   tenantID.(uuid.UUID),
		Action:     req.Action,
		EntityType: req.EntityType,
		Search:     req.Search,
		Page:       req.Page,
		PageSize:   req.PageSize,
	}

	if req.UserID != "" {
		userID, err := uuid.Parse(req.UserID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user_id format"})
			return
		}
		filter.UserID = &userID
	}

	if req.EntityID != "" {
		entityID, err := uuid.Parse(req.EntityID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid entity_id format"})
			return
		}
		filter.EntityID = &entityID
	}

	if !req.StartDate.IsZero() {
		filter.StartDate = &req.StartDate
	}
	if !req.EndDate.IsZero() {
		filter.EndDate = &req.EndDate
	}

	logs, total, err := h.service.GetAuditLogs(c.Request.Context(), filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve audit logs", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": logs,
		"pagination": gin.H{
			"page":        req.Page,
			"page_size":   req.PageSize,
			"total":       total,
			"total_pages": (total + int64(req.PageSize) - 1) / int64(req.PageSize),
		},
	})
}

// GetAuditLog retrieves a single audit log entry
// @Summary Get an audit log entry
// @Description Retrieves a single audit log entry by ID
// @Tags Audit
// @Accept json
// @Produce json
// @Param id path string true "Audit Log ID"
// @Success 200 {object} models.AuditLog
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/logs/{id} [get]
func (h *AuditHandler) GetAuditLog(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	logID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid audit log ID format"})
		return
	}

	log, err := h.service.GetAuditLogByID(c.Request.Context(), tenantID.(uuid.UUID), logID)
	if err != nil {
		if err.Error() == "audit log not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Audit log not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve audit log", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": log})
}

// GetEntityHistory retrieves the audit history for a specific entity
// @Summary Get entity audit history
// @Description Retrieves the complete audit history for a specific entity
// @Tags Audit
// @Accept json
// @Produce json
// @Param entity_type path string true "Entity type"
// @Param entity_id path string true "Entity ID"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(50)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/logs/entity/{entity_type}/{entity_id} [get]
func (h *AuditHandler) GetEntityHistory(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	entityType := c.Param("entity_type")
	if entityType == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Entity type is required"})
		return
	}

	entityID, err := uuid.Parse(c.Param("entity_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid entity ID format"})
		return
	}

	page := 1
	pageSize := 50
	if p := c.Query("page"); p != "" {
		if parsed, err := parseIntParam(p); err == nil && parsed > 0 {
			page = parsed
		}
	}
	if ps := c.Query("page_size"); ps != "" {
		if parsed, err := parseIntParam(ps); err == nil && parsed > 0 && parsed <= 500 {
			pageSize = parsed
		}
	}

	history, total, err := h.service.GetEntityHistory(c.Request.Context(), tenantID.(uuid.UUID), entityType, entityID, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve entity history", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":        history,
		"entity_type": entityType,
		"entity_id":   entityID,
		"pagination": gin.H{
			"page":        page,
			"page_size":   pageSize,
			"total":       total,
			"total_pages": (total + int64(pageSize) - 1) / int64(pageSize),
		},
	})
}

// GetAnalyticsSummary retrieves audit analytics summary
// @Summary Get audit analytics summary
// @Description Retrieves summary analytics for audit logs
// @Tags Audit
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month, quarter)" default(month)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/analytics/summary [get]
func (h *AuditHandler) GetAnalyticsSummary(c *gin.Context) {
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

// GetByUser retrieves audit metrics grouped by user
// @Summary Get audit metrics by user
// @Description Retrieves audit metrics grouped by user
// @Tags Audit
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month)" default(month)
// @Param limit query int false "Number of users to return" default(10)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/analytics/by-user [get]
func (h *AuditHandler) GetByUser(c *gin.Context) {
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

	data, err := h.service.GetByUser(c.Request.Context(), tenantID.(uuid.UUID), period, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve user metrics", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": data})
}

// GetByAction retrieves audit metrics grouped by action
// @Summary Get audit metrics by action
// @Description Retrieves audit metrics grouped by action type
// @Tags Audit
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month)" default(month)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/analytics/by-action [get]
func (h *AuditHandler) GetByAction(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")

	data, err := h.service.GetByAction(c.Request.Context(), tenantID.(uuid.UUID), period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve action metrics", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": data})
}

// GetByEntity retrieves audit metrics grouped by entity type
// @Summary Get audit metrics by entity
// @Description Retrieves audit metrics grouped by entity type
// @Tags Audit
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month)" default(month)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/analytics/by-entity [get]
func (h *AuditHandler) GetByEntity(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")

	data, err := h.service.GetByEntity(c.Request.Context(), tenantID.(uuid.UUID), period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve entity metrics", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": data})
}

// GetTimeline retrieves audit activity timeline
// @Summary Get audit activity timeline
// @Description Retrieves audit activity over time
// @Tags Audit
// @Accept json
// @Produce json
// @Param period query string false "Time period (day, week, month)" default(month)
// @Param group_by query string false "Grouping (hour, day, week)" default(day)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/analytics/timeline [get]
func (h *AuditHandler) GetTimeline(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	period := c.DefaultQuery("period", "month")
	groupBy := c.DefaultQuery("group_by", "day")

	timeline, err := h.service.GetTimeline(c.Request.Context(), tenantID.(uuid.UUID), period, groupBy)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve timeline", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": timeline})
}

// ExportAuditLogs exports audit logs in various formats
// @Summary Export audit logs
// @Description Exports audit logs in CSV or JSON format
// @Tags Audit
// @Accept json
// @Produce json
// @Param format query string false "Export format (csv, json)" default(csv)
// @Param action query string false "Action filter"
// @Param entity_type query string false "Entity type filter"
// @Param user_id query string false "User ID filter"
// @Param start_date query string false "Start date filter (YYYY-MM-DD)"
// @Param end_date query string false "End date filter (YYYY-MM-DD)"
// @Success 200 {file} file
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/export [get]
func (h *AuditHandler) ExportAuditLogs(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	// Check role - only admin/owner can export
	role, exists := c.Get("role")
	if !exists || (role != "admin" && role != "owner") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin or owner can export audit logs"})
		return
	}

	format := c.DefaultQuery("format", "csv")
	if format != "csv" && format != "json" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid format. Use 'csv' or 'json'"})
		return
	}

	// Build filter
	filter := services.AuditFilter{
		TenantID:   tenantID.(uuid.UUID),
		Action:     c.Query("action"),
		EntityType: c.Query("entity_type"),
		Page:       1,
		PageSize:   10000, // Max export limit
	}

	if userID := c.Query("user_id"); userID != "" {
		parsed, err := uuid.Parse(userID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user_id format"})
			return
		}
		filter.UserID = &parsed
	}

	if startDate := c.Query("start_date"); startDate != "" {
		parsed, err := time.Parse("2006-01-02", startDate)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid start_date format. Use YYYY-MM-DD"})
			return
		}
		filter.StartDate = &parsed
	}

	if endDate := c.Query("end_date"); endDate != "" {
		parsed, err := time.Parse("2006-01-02", endDate)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid end_date format. Use YYYY-MM-DD"})
			return
		}
		filter.EndDate = &parsed
	}

	data, filename, err := h.service.ExportAuditLogs(c.Request.Context(), filter, format)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to export audit logs", "details": err.Error()})
		return
	}

	// Set appropriate headers
	contentType := "text/csv"
	if format == "json" {
		contentType = "application/json"
	}

	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Content-Type", contentType)
	c.Data(http.StatusOK, contentType, data)
}

// GetComplianceReport generates a compliance report
// @Summary Get compliance report
// @Description Generates a compliance report for audit purposes
// @Tags Audit
// @Accept json
// @Produce json
// @Param start_date query string true "Report start date (YYYY-MM-DD)"
// @Param end_date query string true "Report end date (YYYY-MM-DD)"
// @Param report_type query string false "Report type (full, summary, access)" default(full)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/compliance/report [get]
func (h *AuditHandler) GetComplianceReport(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	// Check role - only admin/owner can view compliance reports
	role, exists := c.Get("role")
	if !exists || (role != "admin" && role != "owner") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin or owner can view compliance reports"})
		return
	}

	startDateStr := c.Query("start_date")
	endDateStr := c.Query("end_date")

	if startDateStr == "" || endDateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "start_date and end_date are required"})
		return
	}

	startDate, err := time.Parse("2006-01-02", startDateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid start_date format. Use YYYY-MM-DD"})
		return
	}

	endDate, err := time.Parse("2006-01-02", endDateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid end_date format. Use YYYY-MM-DD"})
		return
	}

	reportType := c.DefaultQuery("report_type", "full")

	report, err := h.service.GetComplianceReport(c.Request.Context(), tenantID.(uuid.UUID), startDate, endDate, reportType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate compliance report", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": report})
}

// GetUserActivityReport generates an activity report for a specific user
// @Summary Get user activity report
// @Description Generates a detailed activity report for a specific user
// @Tags Audit
// @Accept json
// @Produce json
// @Param user_id path string true "User ID"
// @Param start_date query string false "Report start date (YYYY-MM-DD)"
// @Param end_date query string false "Report end date (YYYY-MM-DD)"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/audit/compliance/user-activity/{user_id} [get]
func (h *AuditHandler) GetUserActivityReport(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "tenant_id not found in context"})
		return
	}

	// Check role - only admin/owner can view user activity reports
	role, exists := c.Get("role")
	if !exists || (role != "admin" && role != "owner") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admin or owner can view user activity reports"})
		return
	}

	userID, err := uuid.Parse(c.Param("user_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID format"})
		return
	}

	// Default to last 30 days
	endDate := time.Now()
	startDate := endDate.AddDate(0, 0, -30)

	if sd := c.Query("start_date"); sd != "" {
		parsed, err := time.Parse("2006-01-02", sd)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid start_date format. Use YYYY-MM-DD"})
			return
		}
		startDate = parsed
	}

	if ed := c.Query("end_date"); ed != "" {
		parsed, err := time.Parse("2006-01-02", ed)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid end_date format. Use YYYY-MM-DD"})
			return
		}
		endDate = parsed
	}

	report, err := h.service.GetUserActivityReport(c.Request.Context(), tenantID.(uuid.UUID), userID, startDate, endDate)
	if err != nil {
		if err.Error() == "user not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate user activity report", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": report})
}

// Helper function to parse int parameters
func parseIntParam(s string) (int, error) {
	var result int
	_, err := fmt.Sscanf(s, "%d", &result)
	return result, err
}

// Ensure models import is used
var _ models.AuditLog
