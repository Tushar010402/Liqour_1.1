package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type DiscountHandler struct {
	discountService *services.DiscountService
}

func NewDiscountHandler(discountService *services.DiscountService) *DiscountHandler {
	return &DiscountHandler{
		discountService: discountService,
	}
}

// Global Discount Configuration Endpoints

// GetGlobalDiscountConfigs returns all global discount configuration templates
func (h *DiscountHandler) GetGlobalDiscountConfigs(c *gin.Context) {
	configs, err := h.discountService.GetGlobalDiscountConfigs(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    configs,
	})
}

// CreateGlobalDiscountConfig creates a new global discount configuration template
func (h *DiscountHandler) CreateGlobalDiscountConfig(c *gin.Context) {
	var req models.CreateGlobalDiscountConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.discountService.CreateGlobalDiscountConfig(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"data":    config,
	})
}

// UpdateGlobalDiscountConfig updates an existing global discount configuration
func (h *DiscountHandler) UpdateGlobalDiscountConfig(c *gin.Context) {
	configID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid config ID"})
		return
	}

	var req models.UpdateGlobalDiscountConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.discountService.UpdateGlobalDiscountConfig(c.Request.Context(), configID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    config,
	})
}

// DeleteGlobalDiscountConfig deletes a global discount configuration
func (h *DiscountHandler) DeleteGlobalDiscountConfig(c *gin.Context) {
	configID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid config ID"})
		return
	}

	err = h.discountService.DeleteGlobalDiscountConfig(c.Request.Context(), configID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Global discount configuration deleted successfully",
	})
}

// GetDefaultDiscountConfig returns the default discount configuration
func (h *DiscountHandler) GetDefaultDiscountConfig(c *gin.Context) {
	config, err := h.discountService.GetDefaultDiscountConfig(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if config == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no default discount configuration found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    config,
	})
}

// Plan Discount Override Endpoints

// CreatePlanDiscountOverride creates a plan-specific discount override
func (h *DiscountHandler) CreatePlanDiscountOverride(c *gin.Context) {
	var req models.CreatePlanDiscountOverrideRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get admin user ID from context (set by auth middleware)
	adminUserID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	userID, err := uuid.Parse(adminUserID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user ID"})
		return
	}

	override, err := h.discountService.CreatePlanDiscountOverride(c.Request.Context(), &req, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"data":    override,
	})
}

// GetPlanDiscountOverrides returns all discount overrides for a specific plan
func (h *DiscountHandler) GetPlanDiscountOverrides(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("planId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	overrides, err := h.discountService.GetPlanDiscountOverrides(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    overrides,
	})
}

// GetActivePlanDiscountOverride returns the currently active discount override for a plan
func (h *DiscountHandler) GetActivePlanDiscountOverride(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("planId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	override, err := h.discountService.GetActivePlanDiscountOverride(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if override == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no active discount override found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    override,
	})
}

// DeactivatePlanDiscountOverride deactivates a specific discount override
func (h *DiscountHandler) DeactivatePlanDiscountOverride(c *gin.Context) {
	overrideID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid override ID"})
		return
	}

	err = h.discountService.DeactivatePlanDiscountOverride(c.Request.Context(), overrideID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Discount override deactivated successfully",
	})
}

// Billing Term Configuration Endpoints

// GetBillingTermConfigs returns all billing term configurations
func (h *DiscountHandler) GetBillingTermConfigs(c *gin.Context) {
	configs, err := h.discountService.GetBillingTermConfigs(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    configs,
	})
}

// UpdateBillingTermConfig updates a billing term configuration
func (h *DiscountHandler) UpdateBillingTermConfig(c *gin.Context) {
	termMonthsStr := c.Param("termMonths")
	termMonths, err := strconv.Atoi(termMonthsStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid term months"})
		return
	}

	var req models.UpdateBillingTermConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.discountService.UpdateBillingTermConfig(c.Request.Context(), termMonths, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    config,
	})
}

// Bulk Operations

// BulkUpdatePlanDiscounts applies discount changes to multiple plans
func (h *DiscountHandler) BulkUpdatePlanDiscounts(c *gin.Context) {
	var req models.BulkDiscountUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get admin user ID from context
	adminUserID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	userID, err := uuid.Parse(adminUserID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user ID"})
		return
	}

	err = h.discountService.BulkUpdatePlanDiscounts(c.Request.Context(), &req, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Bulk discount update completed successfully",
	})
}

// Analytics and Reporting

// GetDiscountAnalytics returns analytics on discount effectiveness
func (h *DiscountHandler) GetDiscountAnalytics(c *gin.Context) {
	analytics, err := h.discountService.GetDiscountAnalytics(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    analytics,
	})
}

// GetEffectiveDiscounts returns the effective discounts for a plan at a specific time
func (h *DiscountHandler) GetEffectiveDiscounts(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("planId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	// Parse optional 'at' query parameter for historical lookup
	at := time.Now()
	if atStr := c.Query("at"); atStr != "" {
		parsedAt, err := time.Parse(time.RFC3339, atStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid 'at' timestamp format"})
			return
		}
		at = parsedAt
	}

	yearly, twoYear, threeYear, err := h.discountService.GetEffectiveDiscounts(c.Request.Context(), planID, at)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"plan_id":             planID,
			"effective_at":        at,
			"yearly_discount":     yearly,
			"two_year_discount":   twoYear,
			"three_year_discount": threeYear,
		},
	})
}

// Advanced Features

// ApplyDiscountTemplate applies a global discount template to selected plans
func (h *DiscountHandler) ApplyDiscountTemplate(c *gin.Context) {
	templateID, err := uuid.Parse(c.Param("templateId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid template ID"})
		return
	}

	var req struct {
		PlanIDs          []uuid.UUID `json:"plan_ids" binding:"required"`
		ApplyImmediately bool        `json:"apply_immediately"`
		Reason           string      `json:"reason"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get the template
	configs, err := h.discountService.GetGlobalDiscountConfigs(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var template *models.GlobalDiscountConfig
	for _, config := range configs {
		if config.ID == templateID {
			template = &config
			break
		}
	}

	if template == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "discount template not found"})
		return
	}

	// Apply template to plans
	bulkReq := models.BulkDiscountUpdateRequest{
		PlanIDs:           req.PlanIDs,
		YearlyDiscount:    &template.YearlyDiscount,
		TwoYearDiscount:   &template.TwoYearDiscount,
		ThreeYearDiscount: &template.ThreeYearDiscount,
		Reason:            req.Reason,
		ApplyImmediately:  req.ApplyImmediately,
	}

	// Get admin user ID from context
	adminUserID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	userID, err := uuid.Parse(adminUserID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user ID"})
		return
	}

	err = h.discountService.BulkUpdatePlanDiscounts(c.Request.Context(), &bulkReq, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":        true,
		"message":        "Discount template applied successfully",
		"template":       template.Name,
		"affected_plans": len(req.PlanIDs),
	})
}

// InitializeDiscountConfigs initializes default discount configurations
func (h *DiscountHandler) InitializeDiscountConfigs(c *gin.Context) {
	err := h.discountService.InitializeDefaultConfigs(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Default discount configurations initialized successfully",
	})
}

// GetDiscountHistory returns historical discount changes for a plan
func (h *DiscountHandler) GetDiscountHistory(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("planId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	overrides, err := h.discountService.GetPlanDiscountOverrides(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Transform to a more readable history format
	var history []gin.H
	for _, override := range overrides {
		historyItem := gin.H{
			"id":                  override.ID,
			"effective_from":      override.EffectiveFrom,
			"effective_to":        override.EffectiveTo,
			"yearly_discount":     override.YearlyDiscount,
			"two_year_discount":   override.TwoYearDiscount,
			"three_year_discount": override.ThreeYearDiscount,
			"reason":              override.Reason,
			"is_active":           override.IsActive,
			"created_at":          override.CreatedAt,
			"created_by":          override.CreatedBy,
		}
		history = append(history, historyItem)
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"plan_id": planID,
			"history": history,
		},
	})
}
