package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/auth/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// RateLimitHandlers handles rate limit-related HTTP requests
type RateLimitHandlers struct {
	rateLimitService *services.RateLimitService
}

// NewRateLimitHandlers creates a new rate limit handlers instance
func NewRateLimitHandlers(rateLimitService *services.RateLimitService) *RateLimitHandlers {
	return &RateLimitHandlers{
		rateLimitService: rateLimitService,
	}
}

// CreateRateLimitRequest represents the request body for creating a rate limit
type CreateRateLimitRequest struct {
	Name              string     `json:"name" binding:"required"`
	Description       string     `json:"description"`
	MaxAttempts       int        `json:"max_attempts" binding:"required,min=1"`
	TimeWindowSecs    int        `json:"time_window_seconds" binding:"required,min=1"`
	BlockDurationSecs int        `json:"block_duration_seconds" binding:"required,min=1"`
	TenantID          *uuid.UUID `json:"tenant_id"`
	IsGlobal          bool       `json:"is_global"`
	Priority          int        `json:"priority"`
	Settings          string     `json:"settings"`
}

// UpdateRateLimitRequest represents the request body for updating a rate limit
type UpdateRateLimitRequest struct {
	Description       string `json:"description"`
	MaxAttempts       int    `json:"max_attempts" binding:"min=1"`
	TimeWindowSecs    int    `json:"time_window_seconds" binding:"min=1"`
	BlockDurationSecs int    `json:"block_duration_seconds" binding:"min=1"`
	IsActive          *bool  `json:"is_active"`
	Priority          int    `json:"priority"`
	Settings          string `json:"settings"`
}

// RateLimitResponse represents the response format for rate limits
type RateLimitResponse struct {
	ID                   uuid.UUID  `json:"id"`
	Name                 string     `json:"name"`
	Description          string     `json:"description"`
	MaxAttempts          int        `json:"max_attempts"`
	TimeWindowSeconds    int        `json:"time_window_seconds"`
	BlockDurationSeconds int        `json:"block_duration_seconds"`
	TenantID             *uuid.UUID `json:"tenant_id"`
	IsActive             bool       `json:"is_active"`
	IsGlobal             bool       `json:"is_global"`
	Priority             int        `json:"priority"`
	Settings             string     `json:"settings"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

// GetRateLimits retrieves all rate limits
func (h *RateLimitHandlers) GetRateLimits(c *gin.Context) {
	// Get query parameters
	globalOnlyStr := c.Query("global_only")
	globalOnly := globalOnlyStr == "true"

	// Get tenant ID from context if not global only
	var tenantID *uuid.UUID
	if !globalOnly {
		if tenantIDStr := c.GetString("tenant_id"); tenantIDStr != "" {
			if tid, err := uuid.Parse(tenantIDStr); err == nil {
				tenantID = &tid
			}
		}
	}

	rateLimits, err := h.rateLimitService.GetRateLimits(tenantID, globalOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to retrieve rate limits",
			"details": err.Error(),
		})
		return
	}

	// Convert to response format
	response := make([]RateLimitResponse, len(rateLimits))
	for i, rl := range rateLimits {
		response[i] = RateLimitResponse{
			ID:                   rl.ID,
			Name:                 rl.Name,
			Description:          rl.Description,
			MaxAttempts:          rl.MaxAttempts,
			TimeWindowSeconds:    int(rl.TimeWindow.Seconds()),
			BlockDurationSeconds: int(rl.BlockDuration.Seconds()),
			TenantID:             rl.TenantID,
			IsActive:             rl.IsActive,
			IsGlobal:             rl.IsGlobal,
			Priority:             rl.Priority,
			Settings:             rl.Settings,
			CreatedAt:            rl.CreatedAt,
			UpdatedAt:            rl.UpdatedAt,
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    response,
	})
}

// GetRateLimit retrieves a specific rate limit by ID
func (h *RateLimitHandlers) GetRateLimit(c *gin.Context) {
	rateLimitID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid rate limit ID",
		})
		return
	}

	rateLimit, err := h.rateLimitService.GetRateLimitByID(rateLimitID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "Rate limit not found",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": RateLimitResponse{
			ID:                   rateLimit.ID,
			Name:                 rateLimit.Name,
			Description:          rateLimit.Description,
			MaxAttempts:          rateLimit.MaxAttempts,
			TimeWindowSeconds:    int(rateLimit.TimeWindow.Seconds()),
			BlockDurationSeconds: int(rateLimit.BlockDuration.Seconds()),
			TenantID:             rateLimit.TenantID,
			IsActive:             rateLimit.IsActive,
			IsGlobal:             rateLimit.IsGlobal,
			Priority:             rateLimit.Priority,
			Settings:             rateLimit.Settings,
			CreatedAt:            rateLimit.CreatedAt,
			UpdatedAt:            rateLimit.UpdatedAt,
		},
	})
}

// CreateRateLimit creates a new rate limit configuration
func (h *RateLimitHandlers) CreateRateLimit(c *gin.Context) {
	var req CreateRateLimitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request body",
			"details": err.Error(),
		})
		return
	}

	// Get user ID from context
	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": "Invalid user ID",
		})
		return
	}

	// Create rate limit model
	rateLimit := &models.RateLimit{
		Name:          req.Name,
		Description:   req.Description,
		MaxAttempts:   req.MaxAttempts,
		TimeWindow:    time.Duration(req.TimeWindowSecs) * time.Second,
		BlockDuration: time.Duration(req.BlockDurationSecs) * time.Second,
		TenantID:      req.TenantID,
		IsActive:      true,
		IsGlobal:      req.IsGlobal,
		Priority:      req.Priority,
		Settings:      req.Settings,
		CreatedByID:   userID,
	}

	if err := h.rateLimitService.CreateRateLimit(rateLimit); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to create rate limit",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"message": "Rate limit created successfully",
		"data": RateLimitResponse{
			ID:                   rateLimit.ID,
			Name:                 rateLimit.Name,
			Description:          rateLimit.Description,
			MaxAttempts:          rateLimit.MaxAttempts,
			TimeWindowSeconds:    int(rateLimit.TimeWindow.Seconds()),
			BlockDurationSeconds: int(rateLimit.BlockDuration.Seconds()),
			TenantID:             rateLimit.TenantID,
			IsActive:             rateLimit.IsActive,
			IsGlobal:             rateLimit.IsGlobal,
			Priority:             rateLimit.Priority,
			Settings:             rateLimit.Settings,
			CreatedAt:            rateLimit.CreatedAt,
			UpdatedAt:            rateLimit.UpdatedAt,
		},
	})
}

// UpdateRateLimit updates an existing rate limit configuration
func (h *RateLimitHandlers) UpdateRateLimit(c *gin.Context) {
	rateLimitID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid rate limit ID",
		})
		return
	}

	var req UpdateRateLimitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request body",
			"details": err.Error(),
		})
		return
	}

	// Get user ID from context
	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error": "Invalid user ID",
		})
		return
	}

	// Create update model
	updates := &models.RateLimit{
		Description:   req.Description,
		MaxAttempts:   req.MaxAttempts,
		TimeWindow:    time.Duration(req.TimeWindowSecs) * time.Second,
		BlockDuration: time.Duration(req.BlockDurationSecs) * time.Second,
		Priority:      req.Priority,
		Settings:      req.Settings,
		UpdatedByID:   &userID,
	}

	if req.IsActive != nil {
		updates.IsActive = *req.IsActive
	}

	if err := h.rateLimitService.UpdateRateLimit(rateLimitID, updates); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to update rate limit",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Rate limit updated successfully",
	})
}

// DeleteRateLimit deletes a rate limit configuration
func (h *RateLimitHandlers) DeleteRateLimit(c *gin.Context) {
	rateLimitID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid rate limit ID",
		})
		return
	}

	if err := h.rateLimitService.DeleteRateLimit(rateLimitID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to delete rate limit",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Rate limit deleted successfully",
	})
}

// GetRateLimitStats returns rate limiting statistics
func (h *RateLimitHandlers) GetRateLimitStats(c *gin.Context) {
	// Get query parameters
	hoursStr := c.DefaultQuery("hours", "24")
	hours, err := strconv.Atoi(hoursStr)
	if err != nil || hours < 1 {
		hours = 24
	}

	// Get tenant ID from context
	var tenantID *uuid.UUID
	if tenantIDStr := c.GetString("tenant_id"); tenantIDStr != "" {
		if tid, err := uuid.Parse(tenantIDStr); err == nil {
			tenantID = &tid
		}
	}

	stats, err := h.rateLimitService.GetRateLimitStats(tenantID, hours)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to retrieve rate limit statistics",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    stats,
	})
}

// CheckRateLimit manually checks if an identifier is rate limited
func (h *RateLimitHandlers) CheckRateLimit(c *gin.Context) {
	rateLimitName := c.Param("name")
	identifier := c.Query("identifier")

	if identifier == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Identifier is required",
		})
		return
	}

	// Get tenant ID from context
	var tenantID *uuid.UUID
	if tenantIDStr := c.GetString("tenant_id"); tenantIDStr != "" {
		if tid, err := uuid.Parse(tenantIDStr); err == nil {
			tenantID = &tid
		}
	}

	// Get user ID if available
	var userID *uuid.UUID
	if userIDStr := c.GetString("user_id"); userIDStr != "" {
		if uid, err := uuid.Parse(userIDStr); err == nil {
			userID = &uid
		}
	}

	isBlocked, err := h.rateLimitService.CheckRateLimit(
		rateLimitName,
		identifier,
		tenantID,
		userID,
		c.ClientIP(),
		c.GetHeader("User-Agent"),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to check rate limit",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"is_blocked":      isBlocked,
			"rate_limit_name": rateLimitName,
			"identifier":      identifier,
		},
	})
}

// ResetRateLimit resets the rate limit for a specific identifier
func (h *RateLimitHandlers) ResetRateLimit(c *gin.Context) {
	rateLimitName := c.Param("name")
	identifier := c.Query("identifier")

	if identifier == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Identifier is required",
		})
		return
	}

	// Get tenant ID from context
	var tenantID *uuid.UUID
	if tenantIDStr := c.GetString("tenant_id"); tenantIDStr != "" {
		if tid, err := uuid.Parse(tenantIDStr); err == nil {
			tenantID = &tid
		}
	}

	if err := h.rateLimitService.ResetRateLimit(rateLimitName, identifier, tenantID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to reset rate limit",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Rate limit reset successfully",
	})
}
