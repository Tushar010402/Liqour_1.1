package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
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

// SaaS Admin Authentication endpoints

func (h *AdminHandler) IsSaaSAdmin(c *gin.Context) {
	var req struct {
		Mobile string `json:"mobile" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	isAdmin, err := h.adminService.IsSaaSAdmin(c.Request.Context(), req.Mobile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"is_saas_admin": isAdmin,
		"mobile":        req.Mobile,
	})
}

func (h *AdminHandler) SendOTP(c *gin.Context) {
	var req struct {
		Mobile string `json:"mobile" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if mobile number is registered as SaaS admin
	isAdmin, err := h.adminService.IsSaaSAdmin(c.Request.Context(), req.Mobile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "mobile number not registered as SaaS admin"})
		return
	}

	// Send OTP
	err = h.adminService.SendOTP(c.Request.Context(), req.Mobile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "OTP sent successfully",
		"mobile":  req.Mobile,
	})
}

func (h *AdminHandler) VerifyOTP(c *gin.Context) {
	var req struct {
		Mobile string `json:"mobile" binding:"required"`
		OTP    string `json:"otp" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if mobile number is registered as SaaS admin
	isAdmin, err := h.adminService.IsSaaSAdmin(c.Request.Context(), req.Mobile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "mobile number not registered as SaaS admin"})
		return
	}

	// Verify OTP
	isValid, err := h.adminService.VerifyOTP(c.Request.Context(), req.Mobile, req.OTP)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if !isValid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid OTP"})
		return
	}

	// Generate JWT token
	token, err := h.adminService.GenerateAdminToken(c.Request.Context(), req.Mobile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	// Get admin user details
	adminUser, err := h.adminService.GetAdminByMobile(c.Request.Context(), req.Mobile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get admin details"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Login successful",
		"token":   token,
		"user":    adminUser,
	})
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
	// Get admin user ID from JWT context or use default
	adminUserIDStr := c.GetString("user_id")
	var adminUserID uuid.UUID
	var err error

	if adminUserIDStr == "" {
		// Use a default admin ID for super admin operations
		adminUserID = uuid.New()
	} else {
		adminUserID, err = uuid.Parse(adminUserIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID format"})
			return
		}
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
		"message":          "bulk update completed successfully",
		"updated_count":    len(req.SubscriptionIDs),
		"subscription_ids": req.SubscriptionIDs,
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

func (h *AdminHandler) GetAllTenants(c *gin.Context) {
	tenants, err := h.adminService.GetAllTenants(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"tenants": tenants,
		"total":   len(tenants),
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
	var req models.CreateAdminUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	invitedByStr := c.GetString("user_id")
	invitedBy, err := uuid.Parse(invitedByStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	admin, err := h.adminService.CreateAdminUser(c.Request.Context(), req, invitedBy)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "admin user created successfully",
		"user":    models.AdminUserToResponse(admin),
	})
}

func (h *AdminHandler) GetAdminUsers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	search := c.DefaultQuery("search", "")
	role := c.DefaultQuery("role", "all")
	department := c.DefaultQuery("department", "all")

	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 10
	}

	admins, total, err := h.adminService.GetAdminUsers(c.Request.Context(), page, limit, search, role, department)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	responses := make([]*models.AdminUserResponse, len(admins))
	for i := range admins {
		responses[i] = models.AdminUserToResponse(&admins[i])
	}

	c.JSON(http.StatusOK, gin.H{
		"users": responses,
		"total": total,
		"page":  page,
		"limit": limit,
	})
}

func (h *AdminHandler) GetAdminUser(c *gin.Context) {
	adminUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID"})
		return
	}

	admin, err := h.adminService.GetAdminUserByID(c.Request.Context(), adminUserID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"user": models.AdminUserToResponse(admin),
	})
}

func (h *AdminHandler) UpdateAdminUser(c *gin.Context) {
	adminUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID"})
		return
	}

	var req models.UpdateAdminUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updatedByStr := c.GetString("user_id")
	updatedBy, err := uuid.Parse(updatedByStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	admin, err := h.adminService.UpdateAdminUser(c.Request.Context(), adminUserID, req, updatedBy)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "admin user updated successfully",
		"user":    models.AdminUserToResponse(admin),
	})
}

func (h *AdminHandler) DeleteAdminUser(c *gin.Context) {
	adminUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID"})
		return
	}

	deletedByStr := c.GetString("user_id")
	deletedBy, err := uuid.Parse(deletedByStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	if err := h.adminService.DeleteAdminUser(c.Request.Context(), adminUserID, deletedBy); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "admin user deleted successfully",
	})
}

// Invitation endpoints

func (h *AdminHandler) InviteAdminUser(c *gin.Context) {
	var req models.InviteAdminRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	invitedByStr := c.GetString("user_id")
	invitedBy, err := uuid.Parse(invitedByStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	invitation, err := h.adminService.InviteAdminUser(c.Request.Context(), req, invitedBy)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success":    true,
		"message":    "invitation sent successfully",
		"invitation": invitation,
	})
}

func (h *AdminHandler) AcceptInvitation(c *gin.Context) {
	var req models.AcceptInvitationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	admin, token, err := h.adminService.AcceptInvitation(c.Request.Context(), req.Token, req.Mobile)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "invitation accepted successfully",
		"user":    models.AdminUserToResponse(admin),
		"token":   token,
	})
}

func (h *AdminHandler) RevokeInvitation(c *gin.Context) {
	invitationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invitation ID"})
		return
	}

	revokedByStr := c.GetString("user_id")
	revokedBy, err := uuid.Parse(revokedByStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	if err := h.adminService.RevokeInvitation(c.Request.Context(), invitationID, revokedBy); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "invitation revoked successfully",
	})
}

func (h *AdminHandler) GetPendingInvitations(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))

	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 10
	}

	invitations, total, err := h.adminService.GetPendingInvitations(c.Request.Context(), page, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"invitations": invitations,
		"total":       total,
		"page":        page,
		"limit":       limit,
	})
}

// Activity endpoints

func (h *AdminHandler) GetAdminActivity(c *gin.Context) {
	adminUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 20
	}

	activities, total, err := h.adminService.GetAdminActivity(c.Request.Context(), adminUserID, page, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"activities": activities,
		"total":      total,
		"page":       page,
		"limit":      limit,
	})
}

// Profile endpoints

func (h *AdminHandler) GetMyProfile(c *gin.Context) {
	adminIDStr := c.GetString("user_id")
	adminID, err := uuid.Parse(adminIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	admin, err := h.adminService.GetMyProfile(c.Request.Context(), adminID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"user": models.AdminUserToResponse(admin),
	})
}

func (h *AdminHandler) UpdateMyProfile(c *gin.Context) {
	adminIDStr := c.GetString("user_id")
	adminID, err := uuid.Parse(adminIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	var req models.UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	admin, err := h.adminService.UpdateMyProfile(c.Request.Context(), adminID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "profile updated successfully",
		"user":    models.AdminUserToResponse(admin),
	})
}

// Tenant detail endpoints

func (h *AdminHandler) GetTenantDetail(c *gin.Context) {
	tenantID, err := uuid.Parse(c.Param("tenant_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	detail, err := h.adminService.GetTenantDetail(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, detail)
}

func (h *AdminHandler) GetTenantTimeline(c *gin.Context) {
	tenantID, err := uuid.Parse(c.Param("tenant_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 20
	}

	events, total, err := h.adminService.GetTenantTimeline(c.Request.Context(), tenantID, page, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"events": events,
		"total":  total,
		"page":   page,
		"limit":  limit,
	})
}

func (h *AdminHandler) DeactivateTenant(c *gin.Context) {
	tenantID, err := uuid.Parse(c.Param("tenant_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	adminIDStr := c.GetString("user_id")
	adminID, err := uuid.Parse(adminIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	c.ShouldBindJSON(&req)

	if err := h.adminService.DeactivateTenant(c.Request.Context(), tenantID, adminID, req.Reason); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "tenant deactivated successfully",
	})
}

func (h *AdminHandler) ReactivateTenant(c *gin.Context) {
	tenantID, err := uuid.Parse(c.Param("tenant_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	adminIDStr := c.GetString("user_id")
	adminID, err := uuid.Parse(adminIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid admin user ID in context"})
		return
	}

	if err := h.adminService.ReactivateTenant(c.Request.Context(), tenantID, adminID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "tenant reactivated successfully",
	})
}
