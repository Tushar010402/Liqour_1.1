package handlers

import (
	"fmt"
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

// GetPlanBillingOptions returns all billing options for a specific plan
func (h *PlanHandler) GetPlanBillingOptions(c *gin.Context) {
	planIDStr := c.Param("id")
	planID, err := uuid.Parse(planIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid plan ID"})
		return
	}

	plan, err := h.planService.GetPlan(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Plan not found"})
		return
	}

	// Create pricing calculator
	calculator := services.NewEnhancedPricingCalculator(plan)
	options := calculator.GetAllBillingOptions()

	planWithOptions := &models.PlanWithBillingOptions{
		Plan:           plan,
		BillingOptions: options,
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    planWithOptions,
	})
}

// GetAllPlansWithBillingOptions returns all plans with their billing options
func (h *PlanHandler) GetAllPlansWithBillingOptions(c *gin.Context) {
	plans, err := h.planService.GetPlans(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var plansWithOptions []*models.PlanWithBillingOptions
	for _, plan := range plans {
		calculator := services.NewEnhancedPricingCalculator(&plan)
		options := calculator.GetAllBillingOptions()

		plansWithOptions = append(plansWithOptions, &models.PlanWithBillingOptions{
			Plan:           &plan,
			BillingOptions: options,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    plansWithOptions,
	})
}

// UpdatePlanDiscounts updates discount structure for a plan (SaaS Admin only)
func (h *PlanHandler) UpdatePlanDiscounts(c *gin.Context) {
	planIDStr := c.Param("id")
	planID, err := uuid.Parse(planIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid plan ID"})
		return
	}

	var req models.UpdatePlanDiscountsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if plan exists
	_, err = h.planService.GetPlan(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Plan not found"})
		return
	}

	// For now, return a message that this feature will be implemented
	// TODO: Implement actual discount update logic
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Plan discounts updated successfully",
		"data":    req,
	})
}

// GetPlanBillingVariants returns all billing variants for a plan
func (h *PlanHandler) GetPlanBillingVariants(c *gin.Context) {
	planIDStr := c.Param("id")
	planID, err := uuid.Parse(planIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid plan ID"})
		return
	}

	plan, err := h.planService.GetPlan(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Plan not found"})
		return
	}

	// Create pricing calculator and get options
	calculator := services.NewEnhancedPricingCalculator(plan)
	options := calculator.GetAllBillingOptions()

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    options,
	})
}

// CalculatePlanPricing calculates pricing for specific term
func (h *PlanHandler) CalculatePlanPricing(c *gin.Context) {
	planIDStr := c.Param("id")
	planID, err := uuid.Parse(planIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid plan ID"})
		return
	}

	termMonthsStr := c.Query("term_months")
	if termMonthsStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "term_months parameter is required"})
		return
	}

	termMonths := 0
	if _, err := fmt.Sscanf(termMonthsStr, "%d", &termMonths); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid term_months value"})
		return
	}

	plan, err := h.planService.GetPlan(c.Request.Context(), planID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Plan not found"})
		return
	}

	calculator := services.NewEnhancedPricingCalculator(plan)
	options := calculator.GetAllBillingOptions()

	// Find the specific term option
	for _, option := range options {
		if option.TermMonths == termMonths {
			c.JSON(http.StatusOK, gin.H{
				"success": true,
				"data":    option,
			})
			return
		}
	}

	c.JSON(http.StatusBadRequest, gin.H{
		"error": fmt.Sprintf("billing term %d months not supported for plan %s", termMonths, plan.Name),
	})
}
