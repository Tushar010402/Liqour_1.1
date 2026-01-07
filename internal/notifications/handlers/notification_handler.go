package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
)

type NotificationHandler struct {
	service *services.NotificationService
}

func NewNotificationHandler(service *services.NotificationService) *NotificationHandler {
	return &NotificationHandler{service: service}
}

// GetNotifications returns paginated notifications for current user
// @Summary Get user notifications
// @Tags Notifications
// @Security BearerAuth
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Param category query string false "Filter by category"
// @Param unread_only query bool false "Show only unread"
// @Success 200 {object} models.NotificationListResponse
// @Router /api/notifications [get]
func (h *NotificationHandler) GetNotifications(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	category := c.Query("category")
	unreadOnly := c.Query("unread_only") == "true"

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	result, err := h.service.GetUserNotifications(c.Request.Context(), tenantID, userID, page, pageSize, category, unreadOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetNotificationCounts returns notification counts
// @Summary Get notification counts
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} models.NotificationCountResponse
// @Router /api/notifications/counts [get]
func (h *NotificationHandler) GetNotificationCounts(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	counts, err := h.service.GetNotificationCounts(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, counts)
}

// MarkRead marks notifications as read
// @Summary Mark notifications as read
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.MarkReadRequest true "Notification IDs"
// @Success 200 {object} map[string]string
// @Router /api/notifications/read [post]
func (h *NotificationHandler) MarkRead(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.MarkReadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.MarkNotificationsRead(c.Request.Context(), tenantID, userID, req.NotificationIDs); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notifications marked as read"})
}

// MarkAllRead marks all notifications as read
// @Summary Mark all notifications as read
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} map[string]string
// @Router /api/notifications/read-all [post]
func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	if err := h.service.MarkAllRead(c.Request.Context(), tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All notifications marked as read"})
}

// GetPreferences returns user notification preferences
// @Summary Get notification preferences
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} map[string]interface{} "Notification preferences wrapped in response object"
// @Router /api/notifications/preferences [get]
func (h *NotificationHandler) GetPreferences(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	preferences, err := h.service.GetUserPreferences(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"preferences": preferences,
	})
}

// UpdatePreferences updates notification preferences
// @Summary Update notification preferences
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.UpdatePreferencesRequest true "Preferences"
// @Success 200 {object} models.NotificationPreference
// @Router /api/notifications/preferences [put]
func (h *NotificationHandler) UpdatePreferences(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.UpdatePreferencesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	pref, err := h.service.UpdateUserPreferences(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, pref)
}

// InitiateWhatsAppOptIn starts WhatsApp verification
// @Summary Start WhatsApp opt-in
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.WhatsAppOptInRequest true "Phone number"
// @Success 200 {object} map[string]string
// @Router /api/notifications/whatsapp/opt-in [post]
func (h *NotificationHandler) InitiateWhatsAppOptIn(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.WhatsAppOptInRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	subscription, err := h.service.InitiateWhatsAppOptIn(c.Request.Context(), tenantID, userID, req.PhoneNumber)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Verification code sent to WhatsApp",
		"id":      subscription.ID,
	})
}

// VerifyWhatsApp verifies WhatsApp number
// @Summary Verify WhatsApp number
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.WhatsAppVerifyRequest true "Verification code"
// @Success 200 {object} map[string]string
// @Router /api/notifications/whatsapp/verify [post]
func (h *NotificationHandler) VerifyWhatsApp(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.WhatsAppVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.VerifyWhatsAppOptIn(c.Request.Context(), tenantID, userID, req.Code); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "WhatsApp verified successfully"})
}

// OptOutWhatsApp opts out of WhatsApp notifications
// @Summary Opt out of WhatsApp
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} map[string]string
// @Router /api/notifications/whatsapp/opt-out [post]
func (h *NotificationHandler) OptOutWhatsApp(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	if err := h.service.OptOutWhatsApp(c.Request.Context(), tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Successfully opted out of WhatsApp notifications"})
}

// SendNotification sends a notification (admin only)
// @Summary Send notification
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.SendNotificationRequest true "Notification details"
// @Success 201 {object} models.Notification
// @Router /api/notifications/send [post]
func (h *NotificationHandler) SendNotification(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetUserRole(c)

	// Only admin and above can send notifications
	if !utils.HasMinRole(role, "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	var req models.SendNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notification, err := h.service.SendNotification(c.Request.Context(), tenantID, req.UserID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, notification)
}

// SendBulkNotification sends notifications to multiple users (admin only)
// @Summary Send bulk notification
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.BulkNotificationRequest true "Bulk notification details"
// @Success 200 {object} map[string]int
// @Router /api/notifications/send-bulk [post]
func (h *NotificationHandler) SendBulkNotification(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetUserRole(c)

	// Only admin and above can send bulk notifications
	if !utils.HasMinRole(role, "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	var req models.BulkNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	sent, err := h.service.SendBulkNotification(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"sent": sent})
}

// GetTemplates returns notification templates (admin only)
// @Summary Get notification templates
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {array} models.NotificationTemplate
// @Router /api/notifications/templates [get]
func (h *NotificationHandler) GetTemplates(c *gin.Context) {
	role := utils.GetUserRole(c)

	if !utils.HasMinRole(role, "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	// This would need implementation in the service
	c.JSON(http.StatusOK, []models.NotificationTemplate{})
}

// CreateTemplate creates a notification template (admin only)
// @Summary Create notification template
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.CreateTemplateRequest true "Template details"
// @Success 201 {object} models.NotificationTemplate
// @Router /api/notifications/templates [post]
func (h *NotificationHandler) CreateTemplate(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetUserRole(c)

	if !utils.HasMinRole(role, "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	var req models.CreateTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	template, err := h.service.CreateTemplate(c.Request.Context(), &tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, template)
}

// GetNotificationStats returns notification statistics (admin only)
// @Summary Get notification statistics
// @Tags Notifications
// @Security BearerAuth
// @Param start_date query string true "Start date (YYYY-MM-DD)"
// @Param end_date query string true "End date (YYYY-MM-DD)"
// @Success 200 {object} models.NotificationStats
// @Router /api/notifications/stats [get]
func (h *NotificationHandler) GetNotificationStats(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetUserRole(c)

	if !utils.HasMinRole(role, "admin") {
		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		return
	}

	startDate, err := utils.ParseDate(c.Query("start_date"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid start_date"})
		return
	}

	endDate, err := utils.ParseDate(c.Query("end_date"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid end_date"})
		return
	}

	stats, err := h.service.GetNotificationStats(c.Request.Context(), tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// =====================================================
// Device Management Handlers (Frontend Alignment)
// =====================================================

// RegisterDevice registers an FCM token for push notifications
// @Summary Register device for push notifications
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.RegisterDeviceRequest true "Device registration info"
// @Success 200 {object} models.DeviceRegistrationResponse
// @Router /api/notifications/register-device [post]
func (h *NotificationHandler) RegisterDevice(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.DeviceRegistrationResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	if err := h.service.RegisterDevice(c.Request.Context(), tenantID, userID, &req); err != nil {
		c.JSON(http.StatusInternalServerError, models.DeviceRegistrationResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.DeviceRegistrationResponse{
		Success: true,
		Message: "Device registered successfully",
	})
}

// UnregisterDevice removes an FCM token (called on logout)
// @Summary Unregister device from push notifications
// @Tags Notifications
// @Security BearerAuth
// @Param request body models.UnregisterDeviceRequest true "FCM token to unregister"
// @Success 200 {object} models.DeviceRegistrationResponse
// @Router /api/notifications/unregister-device [delete]
func (h *NotificationHandler) UnregisterDevice(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.UnregisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.DeviceRegistrationResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	if err := h.service.UnregisterDevice(c.Request.Context(), tenantID, userID, req.FCMToken); err != nil {
		c.JSON(http.StatusInternalServerError, models.DeviceRegistrationResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.DeviceRegistrationResponse{
		Success: true,
		Message: "Device unregistered successfully",
	})
}

// GetUnreadCount returns just the unread notification count
// @Summary Get unread notification count
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} models.UnreadCountResponse
// @Router /api/notifications/unread-count [get]
func (h *NotificationHandler) GetUnreadCount(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	count, err := h.service.GetUnreadCount(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	response := models.UnreadCountResponse{
		Success: true,
	}
	response.Data.Count = count
	c.JSON(http.StatusOK, response)
}

// MarkSingleRead marks a single notification as read
// @Summary Mark single notification as read
// @Tags Notifications
// @Security BearerAuth
// @Param id path string true "Notification ID"
// @Success 200 {object} models.APIResponse
// @Router /api/notifications/{id}/read [patch]
func (h *NotificationHandler) MarkSingleRead(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	notificationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Success: false,
			Error:   "Invalid notification ID",
		})
		return
	}

	if err := h.service.MarkSingleNotificationRead(c.Request.Context(), tenantID, userID, notificationID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Success: true,
		Message: "Notification marked as read",
	})
}

// DeleteNotification deletes a single notification
// @Summary Delete a notification
// @Tags Notifications
// @Security BearerAuth
// @Param id path string true "Notification ID"
// @Success 200 {object} models.APIResponse
// @Router /api/notifications/{id} [delete]
func (h *NotificationHandler) DeleteNotification(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	notificationID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Success: false,
			Error:   "Invalid notification ID",
		})
		return
	}

	if err := h.service.DeleteNotification(c.Request.Context(), tenantID, userID, notificationID); err != nil {
		c.JSON(http.StatusNotFound, models.APIResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Success: true,
		Message: "Notification deleted",
	})
}

// ClearAllNotifications deletes all notifications for the user
// @Summary Clear all notifications
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} models.APIResponse
// @Router /api/notifications [delete]
func (h *NotificationHandler) ClearAllNotifications(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	if err := h.service.ClearAllNotifications(c.Request.Context(), tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Success: true,
		Message: "All notifications cleared",
	})
}

// GetChannelStatus returns the status of all notification channels (admin only)
// @Summary Get notification channel status
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} models.ChannelStatusResponse
// @Router /api/notifications/channels [get]
func (h *NotificationHandler) GetChannelStatus(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetUserRole(c)

	if !utils.HasMinRole(role, "admin") {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Insufficient permissions"})
		return
	}

	statuses := h.service.GetChannelStatus(c.Request.Context(), tenantID)

	c.JSON(http.StatusOK, models.ChannelStatusResponse{
		Success: true,
		Data:    statuses,
	})
}

// TestPushNotification sends a test push notification to the current user
// @Summary Test push notification
// @Tags Notifications
// @Security BearerAuth
// @Success 200 {object} models.APIResponse
// @Router /api/notifications/channels/push/test [post]
func (h *NotificationHandler) TestPushNotification(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	// Send a test notification
	req := &models.SendNotificationRequest{
		UserID:   userID,
		Category: models.NotificationCategorySystem,
		Priority: models.NotificationPriorityNormal,
		Title:    "Test Push Notification",
		Body:     "This is a test notification to verify push is working.",
		Channels: []models.NotificationChannel{models.NotificationChannelPush},
	}

	_, err := h.service.SendNotification(c.Request.Context(), tenantID, userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Success: true,
		Message: "Test notification sent",
	})
}

// GetNotificationsV2 returns notifications in frontend-aligned format
// @Summary Get user notifications (v2 format)
// @Tags Notifications
// @Security BearerAuth
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(50)
// @Param type query string false "Filter by type"
// @Param unread_only query bool false "Show only unread"
// @Success 200 {object} models.NotificationListResponseV2
// @Router /api/notifications [get]
func (h *NotificationHandler) GetNotificationsV2(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	category := c.Query("type") // Frontend sends "type" parameter
	unreadOnly := c.Query("unread_only") == "true"

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}

	result, err := h.service.GetUserNotificationsV2(c.Request.Context(), tenantID, userID, page, pageSize, category, unreadOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// RegisterRoutes registers notification routes
func (h *NotificationHandler) RegisterRoutes(router *gin.RouterGroup) {
	notifications := router.Group("/notifications")
	{
		// Device management routes (Frontend Alignment)
		notifications.POST("/register-device", h.RegisterDevice)
		notifications.DELETE("/unregister-device", h.UnregisterDevice)

		// User routes
		notifications.GET("", h.GetNotificationsV2) // Use V2 for frontend alignment
		notifications.GET("/unread-count", h.GetUnreadCount)
		notifications.GET("/counts", h.GetNotificationCounts)
		notifications.POST("/read", h.MarkRead)
		notifications.PATCH("/:id/read", h.MarkSingleRead)
		notifications.POST("/read-all", h.MarkAllRead)
		notifications.DELETE("/:id", h.DeleteNotification)
		notifications.DELETE("", h.ClearAllNotifications)
		notifications.GET("/preferences", h.GetPreferences)
		notifications.PUT("/preferences", h.UpdatePreferences)

		// Channel status routes (Admin)
		channels := notifications.Group("/channels")
		{
			channels.GET("", h.GetChannelStatus)
			channels.POST("/push/test", h.TestPushNotification)
		}

		// WhatsApp routes
		whatsapp := notifications.Group("/whatsapp")
		{
			whatsapp.POST("/opt-in", h.InitiateWhatsAppOptIn)
			whatsapp.POST("/verify", h.VerifyWhatsApp)
			whatsapp.POST("/opt-out", h.OptOutWhatsApp)
		}

		// Admin routes
		notifications.POST("/send", h.SendNotification)
		notifications.POST("/send-bulk", h.SendBulkNotification)
		notifications.GET("/templates", h.GetTemplates)
		notifications.POST("/templates", h.CreateTemplate)
		notifications.GET("/stats", h.GetNotificationStats)
	}
}
