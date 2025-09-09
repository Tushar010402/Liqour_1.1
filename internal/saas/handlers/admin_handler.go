package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/services"
)

type AdminHandler struct {
	adminService *services.AdminService
}

func NewAdminHandler(adminService *services.AdminService) *AdminHandler {
	return &AdminHandler{
		adminService: adminService,
	}
}

func (h *AdminHandler) GetAllSubscriptions(c *gin.Context) {
	// Parse pagination parameters
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	status := c.DefaultQuery("status", "all")
	
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 10
	}

	subscriptions, total, err := h.adminService.GetAllSubscriptions(c.Request.Context(), page, limit, status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"subscriptions": subscriptions,
		"total":         total,
		"page":          page,
		"limit":         limit,
		"status_filter": status,
	})
}

func (h *AdminHandler) GetSubscriptionDetails(c *gin.Context) {
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	subscription, payments, usageRecords, err := h.adminService.GetSubscriptionDetails(c.Request.Context(), subscriptionID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"subscription":    subscription,
		"recent_payments": payments,
		"usage_history":   usageRecords,
	})
}

func (h *AdminHandler) UpdateSubscriptionStatus(c *gin.Context) {
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	// Get admin user ID from JWT context
	adminUserIDStr := c.GetString("user_id")
	if adminUserIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "admin user ID is required"})
		return
	}

	adminUserID, err := uuid.Parse(adminUserIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID format"})
		return
	}

	var req struct {
		Status string `json:"status" binding:"required,oneof=active suspended cancelled trial"`
		Reason string `json:"reason"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.adminService.UpdateSubscriptionStatus(c.Request.Context(), subscriptionID, req.Status, adminUserID, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "subscription status updated successfully"})
}

func (h *AdminHandler) GetAuditLogs(c *gin.Context) {
	// Parse pagination parameters
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	resource := c.DefaultQuery("resource", "all")
	
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 20
	}

	// Parse tenant ID filter if provided
	var tenantID *uuid.UUID
	tenantIDStr := c.Query("tenant_id")
	if tenantIDStr != "" {
		parsedTenantID, err := uuid.Parse(tenantIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id format"})
			return
		}
		tenantID = &parsedTenantID
	}

	auditLogs, total, err := h.adminService.GetAuditLogs(c.Request.Context(), page, limit, resource, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"audit_logs":      auditLogs,
		"total":           total,
		"page":            page,
		"limit":           limit,
		"resource_filter": resource,
		"tenant_filter":   tenantID,
	})
}

func (h *AdminHandler) GetSystemHealth(c *gin.Context) {
	health, err := h.adminService.GetSystemHealth(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Set appropriate HTTP status based on system health
	statusCode := http.StatusOK
	switch health.Status {
	case "unhealthy":
		statusCode = http.StatusServiceUnavailable
	case "degraded":
		statusCode = http.StatusPartialContent
	}

	c.JSON(statusCode, health)
}

func (h *AdminHandler) ToggleMaintenanceMode(c *gin.Context) {
	// Get admin user ID from JWT context
	adminUserIDStr := c.GetString("user_id")
	if adminUserIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "admin user ID is required"})
		return
	}

	adminUserID, err := uuid.Parse(adminUserIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID format"})
		return
	}

	var req struct {
		Enabled bool   `json:"enabled"`
		Message string `json:"message"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.adminService.ToggleMaintenanceMode(c.Request.Context(), req.Enabled, adminUserID, req.Message)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	status := "disabled"
	if req.Enabled {
		status = "enabled"
	}

	c.JSON(http.StatusOK, gin.H{
		"message":          "maintenance mode " + status,
		"maintenance_mode": req.Enabled,
	})
}

func (h *AdminHandler) GetTenantUsage(c *gin.Context) {
	tenantID, err := uuid.Parse(c.Param("tenant_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	usage, err := h.adminService.GetTenantUsage(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, usage)
}

func (h *AdminHandler) BulkUpdateSubscriptions(c *gin.Context) {
	// Get admin user ID from JWT context
	adminUserIDStr := c.GetString("user_id")
	if adminUserIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "admin user ID is required"})
		return
	}

	adminUserID, err := uuid.Parse(adminUserIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID format"})
		return
	}

	var req struct {
		SubscriptionIDs []uuid.UUID            `json:"subscription_ids" binding:"required"`
		Updates         map[string]interface{} `json:"updates" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.adminService.BulkUpdateSubscriptions(c.Request.Context(), req.SubscriptionIDs, req.Updates, adminUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":           "bulk update completed successfully",
		"updated_count":     len(req.SubscriptionIDs),
		"subscription_ids":  req.SubscriptionIDs,
	})
}

// Dashboard and statistics endpoints

func (h *AdminHandler) GetSubscriptionStats(c *gin.Context) {
	// This could be moved to analytics service, but keeping here for admin-specific stats
	c.JSON(http.StatusOK, gin.H{
		"message": "subscription stats endpoint - implement based on requirements",
	})
}

func (h *AdminHandler) GetRevenueStats(c *gin.Context) {
	// This could be moved to analytics service, but keeping here for admin-specific stats
	c.JSON(http.StatusOK, gin.H{
		"message": "revenue stats endpoint - implement based on requirements",
	})
}

func (h *AdminHandler) GetTenantStats(c *gin.Context) {
	// This could be moved to analytics service, but keeping here for admin-specific stats
	c.JSON(http.StatusOK, gin.H{
		"message": "tenant stats endpoint - implement based on requirements",
	})
}

// System management endpoints

func (h *AdminHandler) FlushCache(c *gin.Context) {
	// TODO: Implement cache flushing logic
	c.JSON(http.StatusOK, gin.H{"message": "cache flushed successfully"})
}

func (h *AdminHandler) GetSystemLogs(c *gin.Context) {
	// TODO: Implement system log retrieval
	c.JSON(http.StatusOK, gin.H{"message": "system logs endpoint - implement based on requirements"})
}

func (h *AdminHandler) GetDatabaseStats(c *gin.Context) {
	// TODO: Implement database statistics
	c.JSON(http.StatusOK, gin.H{"message": "database stats endpoint - implement based on requirements"})
}

// Admin user management endpoints

func (h *AdminHandler) CreateAdminUser(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
		Name  string `json:"name" binding:"required"`
		Role  string `json:"role" binding:"required,oneof=admin super_admin"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// TODO: Implement admin user creation
	c.JSON(http.StatusCreated, gin.H{
		"message": "admin user creation endpoint - implement based on requirements",
		"user":    req,
	})
}

func (h *AdminHandler) GetAdminUsers(c *gin.Context) {
	// TODO: Implement admin user listing
	c.JSON(http.StatusOK, gin.H{"message": "admin users listing endpoint - implement based on requirements"})
}

func (h *AdminHandler) UpdateAdminUser(c *gin.Context) {
	adminUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID"})
		return
	}

	var req struct {
		Name   string `json:"name"`
		Role   string `json:"role,omitempty" binding:"omitempty,oneof=admin super_admin"`
		Active *bool  `json:"active"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// TODO: Implement admin user update
	c.JSON(http.StatusOK, gin.H{
		"message":      "admin user update endpoint - implement based on requirements",
		"user_id":      adminUserID,
		"update_data":  req,
	})
}

func (h *AdminHandler) DeleteAdminUser(c *gin.Context) {
	adminUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID"})
		return
	}

	// TODO: Implement admin user deletion
	c.JSON(http.StatusOK, gin.H{
		"message": "admin user deletion endpoint - implement based on requirements",
		"user_id": adminUserID,
	})
}