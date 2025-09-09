package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type PlanHandler struct {
	planService *services.PlanService
}

func NewPlanHandler(planService *services.PlanService) *PlanHandler {
	return &PlanHandler{
		planService: planService,
	}
}

// Public endpoint - no authentication required
func (h *PlanHandler) GetPublicPlans(c *gin.Context) {
	plans, err := h.planService.GetPublicPlans(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Remove sensitive information from public response
	publicPlans := make([]gin.H, len(plans))
	for i, plan := range plans {
		publicPlans[i] = gin.H{
			"id":              plan.ID,
			"name":            plan.Name,
			"display_name":    plan.DisplayName,
			"description":     plan.Description,
			"price":           plan.Price,
			"currency":        plan.Currency,
			"billing_cycle":   plan.BillingCycle,
			"trial_days":      plan.TrialDays,
			"max_locations":   plan.MaxLocations,
			"max_users":       plan.MaxUsers,
			"max_products":    plan.MaxProducts,
			"features":        plan.Features,
			"ai_features":     plan.AIFeatures,
			"popular":         plan.Popular,
			"enterprise":      plan.Enterprise,
			"sort_order":      plan.SortOrder,
			"yearly_discount": plan.YearlyDiscount,
		}
	}

	c.JSON(http.StatusOK, gin.H{"plans": publicPlans})
}

// Admin endpoints - require super admin authentication

func (h *PlanHandler) GetPlans(c *gin.Context) {
	plans, err := h.planService.GetPlans(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"plans": plans})
}

func (h *PlanHandler) CreatePlan(c *gin.Context) {
	var req models.CreatePlanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	plan, err := h.planService.CreatePlan(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, plan)
}

func (h *PlanHandler) GetPlan(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	plan, err := h.planService.GetPlan(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, plan)
}

func (h *PlanHandler) UpdatePlan(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	var req models.CreatePlanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	plan, err := h.planService.UpdatePlan(c.Request.Context(), planID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, plan)
}

func (h *PlanHandler) DeletePlan(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	err = h.planService.DeletePlan(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "plan deleted successfully"})
}

func (h *PlanHandler) GetPlanFeatures(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	features, aiFeatures, err := h.planService.GetPlanFeatures(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"features":    features,
		"ai_features": aiFeatures,
	})
}

func (h *PlanHandler) ValidatePlanLimits(c *gin.Context) {
	planID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid plan ID"})
		return
	}

	var req struct {
		ResourceType string `json:"resource_type" binding:"required"`
		CurrentCount int    `json:"current_count" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.planService.ValidatePlanLimits(c.Request.Context(), planID, req.ResourceType, req.CurrentCount)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{
			"error":          err.Error(),
			"limit_exceeded": true,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"within_limits": true})
}

func (h *PlanHandler) InitializeDefaultPlans(c *gin.Context) {
	err := h.planService.InitializeDefaultPlans(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "default plans initialized successfully"})
}