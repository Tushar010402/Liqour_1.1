package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/alarms/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
)

// AlarmHandler handles alarm-related HTTP requests
type AlarmHandler struct {
	service          *services.AlarmService
	schedulerService *services.AlarmSchedulerService
}

// NewAlarmHandler creates a new alarm handler
func NewAlarmHandler(service *services.AlarmService, schedulerService *services.AlarmSchedulerService) *AlarmHandler {
	return &AlarmHandler{
		service:          service,
		schedulerService: schedulerService,
	}
}

// ========================================
// Alarm Definition Endpoints
// ========================================

// GetAlarmDefinitions returns all alarm definitions
// @Summary Get alarm definitions
// @Tags Alarms
// @Security BearerAuth
// @Param category query string false "Filter by category (business, scheduled, system)"
// @Success 200 {array} models.AlarmDefinition
// @Router /api/alarms/definitions [get]
func (h *AlarmHandler) GetAlarmDefinitions(c *gin.Context) {
	category := c.Query("category")

	definitions, err := h.service.GetAlarmDefinitions(c.Request.Context(), category)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    definitions,
	})
}

// GetAlarmDefinition returns a specific alarm definition
// @Summary Get alarm definition by code
// @Tags Alarms
// @Security BearerAuth
// @Param code path string true "Alarm code"
// @Success 200 {object} models.AlarmDefinition
// @Router /api/alarms/definitions/{code} [get]
func (h *AlarmHandler) GetAlarmDefinition(c *gin.Context) {
	code := c.Param("code")

	definition, err := h.service.GetAlarmDefinitionByCode(c.Request.Context(), code)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Alarm definition not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    definition,
	})
}

// ========================================
// Tenant Alarm Configuration Endpoints
// ========================================

// GetAlarmConfigurations returns tenant alarm configurations
// @Summary Get alarm configurations
// @Tags Alarms
// @Security BearerAuth
// @Param shop_id query string false "Filter by shop ID"
// @Success 200 {array} models.TenantAlarmConfig
// @Router /api/alarms/configurations [get]
func (h *AlarmHandler) GetAlarmConfigurations(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	var shopID *uuid.UUID

	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid shop ID"})
			return
		}
		shopID = &id
	}

	configs, err := h.service.GetTenantAlarmConfigurations(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    configs,
	})
}

// GetAlarmConfiguration returns a specific alarm configuration
// @Summary Get alarm configuration
// @Tags Alarms
// @Security BearerAuth
// @Param code path string true "Alarm code"
// @Param shop_id query string false "Shop ID"
// @Success 200 {object} models.TenantAlarmConfig
// @Router /api/alarms/configurations/{code} [get]
func (h *AlarmHandler) GetAlarmConfiguration(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	code := c.Param("code")
	var shopID *uuid.UUID

	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid shop ID"})
			return
		}
		shopID = &id
	}

	config, err := h.service.GetTenantAlarmConfig(c.Request.Context(), tenantID, code, shopID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Configuration not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    config,
	})
}

// UpdateAlarmConfiguration updates an alarm configuration
// @Summary Update alarm configuration
// @Tags Alarms
// @Security BearerAuth
// @Param request body models.UpdateAlarmConfigRequest true "Configuration"
// @Success 200 {object} models.TenantAlarmConfig
// @Router /api/alarms/configurations [put]
func (h *AlarmHandler) UpdateAlarmConfiguration(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetRole(c)

	// Only admin and owner can update alarm configurations
	if role != "admin" && role != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Permission denied"})
		return
	}

	var req models.UpdateAlarmConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	config, err := h.service.UpdateTenantAlarmConfig(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    config,
		"message": "Alarm configuration updated successfully",
	})
}

// ========================================
// Alarm Instance Endpoints
// ========================================

// GetAlarms returns alarm instances
// @Summary Get alarms
// @Tags Alarms
// @Security BearerAuth
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(20)
// @Param status query string false "Filter by status"
// @Param priority query string false "Filter by priority"
// @Param alarm_code query string false "Filter by alarm code"
// @Param shop_id query string false "Filter by shop ID"
// @Param active_only query bool false "Show only active alarms"
// @Param start_date query string false "Start date (YYYY-MM-DD)"
// @Param end_date query string false "End date (YYYY-MM-DD)"
// @Success 200 {object} models.AlarmInstanceListResponse
// @Router /api/alarms [get]
func (h *AlarmHandler) GetAlarms(c *gin.Context) {
	tenantID := utils.GetTenantID(c)

	filter := &models.AlarmInstanceFilter{
		Page:       1,
		PageSize:   20,
		ActiveOnly: c.Query("active_only") == "true",
	}

	if page, err := strconv.Atoi(c.Query("page")); err == nil && page > 0 {
		filter.Page = page
	}
	if pageSize, err := strconv.Atoi(c.Query("page_size")); err == nil && pageSize > 0 && pageSize <= 100 {
		filter.PageSize = pageSize
	}

	filter.Status = c.Query("status")
	filter.Priority = c.Query("priority")
	filter.AlarmCode = c.Query("alarm_code")

	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err == nil {
			filter.ShopID = &id
		}
	}

	if startDate := c.Query("start_date"); startDate != "" {
		if t, err := time.Parse("2006-01-02", startDate); err == nil {
			filter.StartDate = t
		}
	}

	if endDate := c.Query("end_date"); endDate != "" {
		if t, err := time.Parse("2006-01-02", endDate); err == nil {
			filter.EndDate = t.Add(24*time.Hour - time.Second)
		}
	}

	result, err := h.service.GetAlarmInstances(c.Request.Context(), tenantID, filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}

// GetAlarm returns a specific alarm instance
// @Summary Get alarm by ID
// @Tags Alarms
// @Security BearerAuth
// @Param id path string true "Alarm ID"
// @Success 200 {object} models.AlarmInstance
// @Router /api/alarms/{id} [get]
func (h *AlarmHandler) GetAlarm(c *gin.Context) {
	tenantID := utils.GetTenantID(c)

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	alarm, err := h.service.GetAlarmInstance(c.Request.Context(), tenantID, alarmID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Alarm not found"})
		return
	}

	// Get alarm history
	history, _ := h.service.GetAlarmHistory(c.Request.Context(), tenantID, alarmID)

	// Get alarm notes
	notes, _ := h.service.GetAlarmNotes(c.Request.Context(), tenantID, alarmID)

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"alarm":   alarm,
			"history": history,
			"notes":   notes,
		},
	})
}

// TriggerAlarm manually triggers an alarm (admin only)
// @Summary Trigger alarm manually
// @Tags Alarms
// @Security BearerAuth
// @Param request body models.TriggerAlarmRequest true "Alarm trigger request"
// @Success 201 {object} models.AlarmInstance
// @Router /api/alarms/trigger [post]
func (h *AlarmHandler) TriggerAlarm(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetRole(c)

	// Only admin can manually trigger alarms
	if role != "admin" && role != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Permission denied"})
		return
	}

	var req models.TriggerAlarmRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarm, err := h.service.TriggerAlarm(c.Request.Context(), tenantID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"data":    alarm,
		"message": "Alarm triggered successfully",
	})
}

// AcknowledgeAlarm acknowledges an alarm
// @Summary Acknowledge alarm
// @Tags Alarms
// @Security BearerAuth
// @Param id path string true "Alarm ID"
// @Param request body models.AcknowledgeAlarmRequest true "Acknowledgment"
// @Success 200 {object} models.AlarmInstance
// @Router /api/alarms/{id}/acknowledge [post]
func (h *AlarmHandler) AcknowledgeAlarm(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Note string `json:"note"`
	}
	c.ShouldBindJSON(&req)

	alarm, err := h.service.AcknowledgeAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Note)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    alarm,
		"message": "Alarm acknowledged successfully",
	})
}

// ResolveAlarm resolves an alarm
// @Summary Resolve alarm
// @Tags Alarms
// @Security BearerAuth
// @Param id path string true "Alarm ID"
// @Param request body models.ResolveAlarmRequest true "Resolution"
// @Success 200 {object} models.AlarmInstance
// @Router /api/alarms/{id}/resolve [post]
func (h *AlarmHandler) ResolveAlarm(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Resolution string `json:"resolution" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarm, err := h.service.ResolveAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Resolution)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    alarm,
		"message": "Alarm resolved successfully",
	})
}

// SnoozeAlarm snoozes an alarm
// @Summary Snooze alarm
// @Tags Alarms
// @Security BearerAuth
// @Param id path string true "Alarm ID"
// @Param request body models.SnoozeAlarmRequest true "Snooze request"
// @Success 200 {object} models.AlarmInstance
// @Router /api/alarms/{id}/snooze [post]
func (h *AlarmHandler) SnoozeAlarm(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Minutes int    `json:"minutes" binding:"required,min=5,max=1440"`
		Reason  string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	alarm, err := h.service.SnoozeAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Minutes, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    alarm,
		"message": "Alarm snoozed successfully",
	})
}

// AddAlarmNote adds a note to an alarm
// @Summary Add note to alarm
// @Tags Alarms
// @Security BearerAuth
// @Param id path string true "Alarm ID"
// @Param request body models.AddAlarmNoteRequest true "Note"
// @Success 200 {object} map[string]interface{}
// @Router /api/alarms/{id}/notes [post]
func (h *AlarmHandler) AddAlarmNote(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	alarmID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "Invalid alarm ID"})
		return
	}

	var req struct {
		Note string `json:"note" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	if err := h.service.AddAlarmNote(c.Request.Context(), tenantID, userID, alarmID, req.Note); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Note added successfully",
	})
}

// ========================================
// Alarm Counts and Stats Endpoints
// ========================================

// GetAlarmCounts returns alarm counts for dashboard
// @Summary Get alarm counts
// @Tags Alarms
// @Security BearerAuth
// @Param shop_id query string false "Filter by shop ID"
// @Success 200 {object} models.AlarmCountsResponse
// @Router /api/alarms/counts [get]
func (h *AlarmHandler) GetAlarmCounts(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	var shopID *uuid.UUID

	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err == nil {
			shopID = &id
		}
	}

	counts, err := h.service.GetAlarmCounts(c.Request.Context(), tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    counts,
	})
}

// GetAlarmStats returns alarm statistics
// @Summary Get alarm statistics
// @Tags Alarms
// @Security BearerAuth
// @Param start_date query string false "Start date (YYYY-MM-DD)"
// @Param end_date query string false "End date (YYYY-MM-DD)"
// @Success 200 {object} models.AlarmStatsResponse
// @Router /api/alarms/stats [get]
func (h *AlarmHandler) GetAlarmStats(c *gin.Context) {
	tenantID := utils.GetTenantID(c)

	startDate := time.Now().AddDate(0, 0, -30).Truncate(24 * time.Hour)
	endDate := time.Now()

	if s := c.Query("start_date"); s != "" {
		if t, err := time.Parse("2006-01-02", s); err == nil {
			startDate = t
		}
	}
	if e := c.Query("end_date"); e != "" {
		if t, err := time.Parse("2006-01-02", e); err == nil {
			endDate = t.Add(24*time.Hour - time.Second)
		}
	}

	stats, err := h.service.GetAlarmStats(c.Request.Context(), tenantID, startDate, endDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    stats,
	})
}

// ========================================
// User Subscription Endpoints
// ========================================

// GetUserSubscriptions returns user's alarm subscriptions
// @Summary Get user alarm subscriptions
// @Tags Alarms
// @Security BearerAuth
// @Success 200 {array} models.UserAlarmSubscription
// @Router /api/alarms/subscriptions [get]
func (h *AlarmHandler) GetUserSubscriptions(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	subscriptions, err := h.service.GetUserAlarmSubscriptions(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    subscriptions,
	})
}

// UpdateUserSubscription updates a user's alarm subscription
// @Summary Update alarm subscription
// @Tags Alarms
// @Security BearerAuth
// @Param request body models.UpdateAlarmSubscriptionRequest true "Subscription"
// @Success 200 {object} models.UserAlarmSubscription
// @Router /api/alarms/subscriptions [put]
func (h *AlarmHandler) UpdateUserSubscription(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req models.UpdateAlarmSubscriptionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	subscription, err := h.service.UpdateUserAlarmSubscription(c.Request.Context(), tenantID, userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    subscription,
		"message": "Subscription updated successfully",
	})
}

// ========================================
// Admin Endpoints
// ========================================

// RunAlarmChecks manually triggers alarm checks (admin only)
// @Summary Run alarm checks
// @Tags Alarms
// @Security BearerAuth
// @Param alarm_code query string false "Specific alarm code to check"
// @Param shop_id query string false "Specific shop to check"
// @Success 200 {object} map[string]interface{}
// @Router /api/alarms/admin/run-checks [post]
func (h *AlarmHandler) RunAlarmChecks(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	role := utils.GetRole(c)

	if role != "admin" && role != "owner" {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "error": "Permission denied"})
		return
	}

	alarmCode := c.Query("alarm_code")
	var shopID *uuid.UUID

	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		id, err := uuid.Parse(shopIDStr)
		if err == nil {
			shopID = &id
		}
	}

	var err error
	if alarmCode != "" {
		err = h.schedulerService.RunSpecificCheckForTenant(c.Request.Context(), tenantID, alarmCode, shopID)
	} else {
		err = h.schedulerService.RunAllChecksForTenant(c.Request.Context(), tenantID)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Alarm checks completed",
	})
}

// BulkAcknowledge acknowledges multiple alarms
// @Summary Bulk acknowledge alarms
// @Tags Alarms
// @Security BearerAuth
// @Param request body models.BulkAlarmActionRequest true "Alarm IDs"
// @Success 200 {object} map[string]interface{}
// @Router /api/alarms/bulk/acknowledge [post]
func (h *AlarmHandler) BulkAcknowledge(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req struct {
		AlarmIDs []uuid.UUID `json:"alarm_ids" binding:"required"`
		Note     string      `json:"note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	successCount := 0
	for _, alarmID := range req.AlarmIDs {
		if _, err := h.service.AcknowledgeAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Note); err == nil {
			successCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"acknowledged":  successCount,
		"total":         len(req.AlarmIDs),
		"message":       "Bulk acknowledge completed",
	})
}

// BulkResolve resolves multiple alarms
// @Summary Bulk resolve alarms
// @Tags Alarms
// @Security BearerAuth
// @Param request body models.BulkAlarmActionRequest true "Alarm IDs"
// @Success 200 {object} map[string]interface{}
// @Router /api/alarms/bulk/resolve [post]
func (h *AlarmHandler) BulkResolve(c *gin.Context) {
	tenantID := utils.GetTenantID(c)
	userID := utils.GetUserID(c)

	var req struct {
		AlarmIDs   []uuid.UUID `json:"alarm_ids" binding:"required"`
		Resolution string      `json:"resolution" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": err.Error()})
		return
	}

	successCount := 0
	for _, alarmID := range req.AlarmIDs {
		if _, err := h.service.ResolveAlarm(c.Request.Context(), tenantID, userID, alarmID, req.Resolution); err == nil {
			successCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":  true,
		"resolved": successCount,
		"total":    len(req.AlarmIDs),
		"message":  "Bulk resolve completed",
	})
}
