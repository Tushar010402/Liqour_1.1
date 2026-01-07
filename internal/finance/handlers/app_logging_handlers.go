package handlers

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/finance/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"go.uber.org/zap"
)

// AppLoggingHandlers handles app logging endpoints
type AppLoggingHandlers struct {
	loggingService *services.AppLoggingService
	logger         *zap.Logger
}

// NewAppLoggingHandlers creates a new app logging handlers instance
func NewAppLoggingHandlers(loggingService *services.AppLoggingService, logger *zap.Logger) *AppLoggingHandlers {
	return &AppLoggingHandlers{
		loggingService: loggingService,
		logger:         logger,
	}
}

// ============================================================================
// ACCESS CONTROL HELPERS
// ============================================================================

// extractLogAccessParams extracts role-based access parameters from the request context
func (h *AppLoggingHandlers) extractLogAccessParams(c *gin.Context) (*services.LogAccessParams, error) {
	userIDStr := c.GetString("user_id")
	tenantIDStr := c.GetString("tenant_id")
	role := c.GetString("role")

	if userIDStr == "" {
		return nil, fmt.Errorf("user ID not found in context")
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		return nil, fmt.Errorf("invalid user ID format")
	}

	params := &services.LogAccessParams{
		UserID: userID,
		Role:   role,
	}

	// Parse tenant ID (may be empty for saas_admin)
	if tenantIDStr != "" {
		if tenantID, err := uuid.Parse(tenantIDStr); err == nil {
			params.TenantID = tenantID
		}
	}

	// Parse optional filter parameters from query string
	if filterUserID := c.Query("user_id"); filterUserID != "" {
		if uid, err := uuid.Parse(filterUserID); err == nil {
			params.FilterUserID = &uid
		}
	}

	if filterTenantID := c.Query("tenant_id"); filterTenantID != "" {
		if tid, err := uuid.Parse(filterTenantID); err == nil {
			params.FilterTenantID = &tid
		}
	}

	return params, nil
}

// GetViewableUsers handles GET /api/logs/users
// @Summary Get users whose logs the current user can view
// @Description Returns list of users for dropdown based on role-based access control
// @Tags App Logging
// @Accept json
// @Produce json
// @Param tenant_id query string false "Filter by tenant ID (saas_admin only)"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs/users [get]
func (h *AppLoggingHandlers) GetViewableUsers(c *gin.Context) {
	accessParams, err := h.extractLogAccessParams(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   err.Error(),
			"code":    "AUTH_ERROR",
			"success": false,
		})
		return
	}

	users, err := h.loggingService.GetViewableUsers(c.Request.Context(), accessParams)
	if err != nil {
		h.logger.Error("Failed to get viewable users",
			zap.Error(err),
			zap.String("user_id", accessParams.UserID.String()),
			zap.String("role", accessParams.Role),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get users: " + err.Error(),
			"code":    "FETCH_FAILED",
			"success": false,
		})
		return
	}

	// Include access metadata for frontend UI decisions
	c.JSON(http.StatusOK, gin.H{
		"success":              true,
		"users":                users,
		"can_view_all_tenants": accessParams.CanViewAllTenants(),
		"can_view_all_users":   accessParams.CanViewAllUsersInTenant(),
		"can_filter_users":     !accessParams.MustViewOwnLogsOnly(),
		"current_user_id":      accessParams.UserID,
		"current_role":         accessParams.Role,
	})
}

// ============================================================================
// BATCH LOG PROCESSING
// ============================================================================

// ReceiveBatchLogs handles POST /api/logs/batch
// @Summary Receive batch logs from Flutter app
// @Description Receives a batch of logs from the Flutter app for storage and analysis
// @Tags App Logging
// @Accept json
// @Produce json
// @Param request body models.LogBatchRequest true "Log batch request"
// @Success 200 {object} models.LogBatchResponse
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs/batch [post]
func (h *AppLoggingHandlers) ReceiveBatchLogs(c *gin.Context) {
	// Get tenant ID from context (set by auth middleware)
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "tenant_id is required",
			"code":    "TENANT_REQUIRED",
			"success": false,
		})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid tenant_id format",
			"code":    "INVALID_TENANT",
			"success": false,
		})
		return
	}

	// Get authenticated user ID from context (to use if session doesn't specify one)
	authUserIDStr := c.GetString("user_id")
	var authUserID *uuid.UUID
	if authUserIDStr != "" {
		if uid, err := uuid.Parse(authUserIDStr); err == nil {
			authUserID = &uid
		}
	}

	// Parse request body
	var req models.LogBatchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		h.logger.Warn("Invalid log batch request",
			zap.Error(err),
			zap.String("tenant_id", tenantIDStr),
		)
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request body: " + err.Error(),
			"code":    "INVALID_REQUEST",
			"success": false,
		})
		return
	}

	// Validate batch ID
	if req.BatchID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "batch_id is required",
			"code":    "BATCH_ID_REQUIRED",
			"success": false,
		})
		return
	}

	// Process the batch (pass auth user ID for session association)
	response, err := h.loggingService.ProcessLogBatch(c.Request.Context(), &req, tenantID, authUserID)
	if err != nil {
		h.logger.Error("Failed to process log batch",
			zap.Error(err),
			zap.String("tenant_id", tenantIDStr),
			zap.String("batch_id", req.BatchID),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to process log batch: " + err.Error(),
			"code":    "PROCESSING_FAILED",
			"success": false,
		})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetSessions handles GET /api/logs/sessions
// @Summary Get app log sessions
// @Description Retrieves app log sessions with role-based access control
// @Tags App Logging
// @Accept json
// @Produce json
// @Param tenant_id query string false "Filter by tenant ID (saas_admin only)"
// @Param user_id query string false "Filter by user ID"
// @Param from query string false "Filter from date (RFC3339)"
// @Param to query string false "Filter to date (RFC3339)"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(50)
// @Success 200 {object} models.LogSessionsResponse
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs/sessions [get]
func (h *AppLoggingHandlers) GetSessions(c *gin.Context) {
	var params models.LogQueryParams
	if err := c.ShouldBindQuery(&params); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid query parameters: " + err.Error(),
			"code":    "INVALID_PARAMS",
			"success": false,
		})
		return
	}

	// Extract role-based access parameters
	accessParams, err := h.extractLogAccessParams(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   err.Error(),
			"code":    "AUTH_ERROR",
			"success": false,
		})
		return
	}

	// Validate user_id filter permission
	if accessParams.FilterUserID != nil && accessParams.MustViewOwnLogsOnly() {
		if *accessParams.FilterUserID != accessParams.UserID {
			c.JSON(http.StatusForbidden, gin.H{
				"error":   "You can only view your own logs",
				"code":    "ACCESS_DENIED",
				"success": false,
			})
			return
		}
	}

	response, err := h.loggingService.GetSessions(c.Request.Context(), &params, accessParams)
	if err != nil {
		h.logger.Error("Failed to get sessions",
			zap.Error(err),
			zap.String("user_id", accessParams.UserID.String()),
			zap.String("role", accessParams.Role),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get sessions: " + err.Error(),
			"code":    "FETCH_FAILED",
			"success": false,
		})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetLogs handles GET /api/logs
// @Summary Get app log entries
// @Description Retrieves app log entries with role-based access control
// @Tags App Logging
// @Accept json
// @Produce json
// @Param tenant_id query string false "Filter by tenant ID (saas_admin only)"
// @Param user_id query string false "Filter by user ID"
// @Param session_id query string false "Filter by session ID"
// @Param level query string false "Filter by log level (debug, info, warning, error, success)"
// @Param tag query string false "Filter by tag (API, Navigation, Error, etc.)"
// @Param search query string false "Search in message and tag"
// @Param from query string false "Filter from date (RFC3339)"
// @Param to query string false "Filter to date (RFC3339)"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(50)
// @Success 200 {object} models.LogEntriesResponse
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs [get]
func (h *AppLoggingHandlers) GetLogs(c *gin.Context) {
	var params models.LogQueryParams
	if err := c.ShouldBindQuery(&params); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid query parameters: " + err.Error(),
			"code":    "INVALID_PARAMS",
			"success": false,
		})
		return
	}

	// Extract role-based access parameters
	accessParams, err := h.extractLogAccessParams(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   err.Error(),
			"code":    "AUTH_ERROR",
			"success": false,
		})
		return
	}

	// Validate user_id filter permission
	if accessParams.FilterUserID != nil && accessParams.MustViewOwnLogsOnly() {
		if *accessParams.FilterUserID != accessParams.UserID {
			c.JSON(http.StatusForbidden, gin.H{
				"error":   "You can only view your own logs",
				"code":    "ACCESS_DENIED",
				"success": false,
			})
			return
		}
	}

	// Check if grouped view is requested
	if params.Grouped {
		response, err := h.loggingService.GetGroupedLogs(c.Request.Context(), &params, accessParams)
		if err != nil {
			h.logger.Error("Failed to get grouped logs",
				zap.Error(err),
				zap.String("user_id", accessParams.UserID.String()),
				zap.String("role", accessParams.Role),
			)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "Failed to get grouped logs: " + err.Error(),
				"code":    "FETCH_FAILED",
				"success": false,
			})
			return
		}
		c.JSON(http.StatusOK, response)
		return
	}

	response, err := h.loggingService.GetLogs(c.Request.Context(), &params, accessParams)
	if err != nil {
		h.logger.Error("Failed to get logs",
			zap.Error(err),
			zap.String("user_id", accessParams.UserID.String()),
			zap.String("role", accessParams.Role),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get logs: " + err.Error(),
			"code":    "FETCH_FAILED",
			"success": false,
		})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetLogStats handles GET /api/logs/stats
// @Summary Get app log statistics
// @Description Retrieves log statistics with role-based access control
// @Tags App Logging
// @Accept json
// @Produce json
// @Param tenant_id query string false "Filter by tenant ID (saas_admin only)"
// @Param user_id query string false "Filter by user ID"
// @Param period query string false "Time period (1h, 6h, 24h, 7d, 30d)" default("24h")
// @Success 200 {object} models.LogStatsResponse
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs/stats [get]
func (h *AppLoggingHandlers) GetLogStats(c *gin.Context) {
	period := c.DefaultQuery("period", "24h")

	// Extract role-based access parameters
	accessParams, err := h.extractLogAccessParams(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   err.Error(),
			"code":    "AUTH_ERROR",
			"success": false,
		})
		return
	}

	response, err := h.loggingService.GetLogStats(c.Request.Context(), accessParams, period)
	if err != nil {
		h.logger.Error("Failed to get log stats",
			zap.Error(err),
			zap.String("user_id", accessParams.UserID.String()),
			zap.String("role", accessParams.Role),
			zap.String("period", period),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get log stats: " + err.Error(),
			"code":    "FETCH_FAILED",
			"success": false,
		})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetNetworkRequests handles GET /api/logs/network
// @Summary Get network request logs
// @Description Retrieves network request logs with role-based access control
// @Tags App Logging
// @Accept json
// @Produce json
// @Param tenant_id query string false "Filter by tenant ID (saas_admin only)"
// @Param user_id query string false "Filter by user ID"
// @Param session_id query string false "Filter by session ID"
// @Param from query string false "Filter from date (RFC3339)"
// @Param to query string false "Filter to date (RFC3339)"
// @Param page query int false "Page number" default(1)
// @Param page_size query int false "Page size" default(50)
// @Success 200 {object} models.NetworkRequestsResponse
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs/network [get]
func (h *AppLoggingHandlers) GetNetworkRequests(c *gin.Context) {
	var params models.LogQueryParams
	if err := c.ShouldBindQuery(&params); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid query parameters: " + err.Error(),
			"code":    "INVALID_PARAMS",
			"success": false,
		})
		return
	}

	// Extract role-based access parameters
	accessParams, err := h.extractLogAccessParams(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   err.Error(),
			"code":    "AUTH_ERROR",
			"success": false,
		})
		return
	}

	// Validate user_id filter permission
	if accessParams.FilterUserID != nil && accessParams.MustViewOwnLogsOnly() {
		if *accessParams.FilterUserID != accessParams.UserID {
			c.JSON(http.StatusForbidden, gin.H{
				"error":   "You can only view your own logs",
				"code":    "ACCESS_DENIED",
				"success": false,
			})
			return
		}
	}

	// Check if grouped view is requested
	if params.Grouped {
		response, err := h.loggingService.GetGroupedNetworkRequests(c.Request.Context(), &params, accessParams)
		if err != nil {
			h.logger.Error("Failed to get grouped network requests",
				zap.Error(err),
				zap.String("user_id", accessParams.UserID.String()),
				zap.String("role", accessParams.Role),
			)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "Failed to get grouped network requests: " + err.Error(),
				"code":    "FETCH_FAILED",
				"success": false,
			})
			return
		}
		c.JSON(http.StatusOK, response)
		return
	}

	response, err := h.loggingService.GetNetworkRequests(c.Request.Context(), &params, accessParams)
	if err != nil {
		h.logger.Error("Failed to get network requests",
			zap.Error(err),
			zap.String("user_id", accessParams.UserID.String()),
			zap.String("role", accessParams.Role),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to get network requests: " + err.Error(),
			"code":    "FETCH_FAILED",
			"success": false,
		})
		return
	}

	c.JSON(http.StatusOK, response)
}

// CleanupOldLogs handles DELETE /api/logs/cleanup
// @Summary Cleanup old logs
// @Description Deletes logs older than specified retention days (admin only)
// @Tags App Logging
// @Accept json
// @Produce json
// @Param retention_days query int false "Number of days to retain" default(30)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/logs/cleanup [delete]
func (h *AppLoggingHandlers) CleanupOldLogs(c *gin.Context) {
	// Only SaaS admin can cleanup logs
	role := c.GetString("role")
	if role != models.RoleSaasAdmin && role != "super_admin" {
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "Only SaaS admin can cleanup logs",
			"code":    "FORBIDDEN",
			"success": false,
		})
		return
	}

	retentionDaysStr := c.DefaultQuery("retention_days", "30")
	retentionDays := 30
	if days, err := parsePositiveInt(retentionDaysStr); err == nil && days > 0 {
		retentionDays = days
	}

	deletedCount, err := h.loggingService.CleanupOldLogs(c.Request.Context(), retentionDays)
	if err != nil {
		h.logger.Error("Failed to cleanup logs",
			zap.Error(err),
			zap.Int("retention_days", retentionDays),
		)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to cleanup logs: " + err.Error(),
			"code":    "CLEANUP_FAILED",
			"success": false,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"deleted_count":  deletedCount,
		"retention_days": retentionDays,
	})
}

// parsePositiveInt parses a string as a positive integer
func parsePositiveInt(s string) (int, error) {
	var i int
	_, err := parseIntFromString(s, &i)
	if err != nil || i <= 0 {
		return 0, err
	}
	return i, nil
}

func parseIntFromString(s string, result *int) (bool, error) {
	if s == "" {
		return false, nil
	}
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return false, nil
		}
		n = n*10 + int(c-'0')
	}
	*result = n
	return true, nil
}
