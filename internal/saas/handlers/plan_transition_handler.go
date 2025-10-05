package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type PlanTransitionHandler struct {
	transitionService *services.PlanTransitionService
}

func NewPlanTransitionHandler(transitionService *services.PlanTransitionService) *PlanTransitionHandler {
	return &PlanTransitionHandler{
		transitionService: transitionService,
	}
}

func (h *PlanTransitionHandler) InitiatePlanTransition(c *gin.Context) {
	var req services.PlanTransitionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.transitionService.InitiatePlanTransition(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to initiate plan transition", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Plan transition initiated successfully",
		"transition": result,
	})
}

func (h *PlanTransitionHandler) GetTransitionHistory(c *gin.Context) {
	subscriptionIDStr := c.Param("subscription_id")
	subscriptionID, err := uuid.Parse(subscriptionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid subscription ID"})
		return
	}

	history, err := h.transitionService.GetTransitionHistory(c.Request.Context(), subscriptionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get transition history"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"subscription_id": subscriptionID,
		"history":         history,
		"count":           len(history),
	})
}

func (h *PlanTransitionHandler) CancelPendingTransition(c *gin.Context) {
	transitionIDStr := c.Param("transition_id")
	transitionID, err := uuid.Parse(transitionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid transition ID"})
		return
	}

	if err := h.transitionService.CancelPendingTransition(c.Request.Context(), transitionID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to cancel transition", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "Transition cancelled successfully",
		"transition_id": transitionID,
		"cancelled_at":  time.Now(),
	})
}

func (h *PlanTransitionHandler) PreviewPlanTransition(c *gin.Context) {
	var req services.PlanTransitionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// This would be a preview-only version that calculates costs without executing
	// For now, return a placeholder response
	c.JSON(http.StatusOK, gin.H{
		"preview": gin.H{
			"transition_type":   req.TransitionType,
			"effective_date":    req.EffectiveDate,
			"proration_mode":    req.ProrationMode,
			"estimated_charge":  0.0, // Calculate this based on the request
			"estimated_credit":  0.0,
			"next_billing_date": time.Now().AddDate(0, 1, 0),
		},
		"message": "This is a preview. Use the initiate endpoint to execute the transition.",
	})
}

func (h *PlanTransitionHandler) GetAvailableTransitions(c *gin.Context) {
	subscriptionIDStr := c.Param("subscription_id")
	subscriptionID, err := uuid.Parse(subscriptionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid subscription ID"})
		return
	}

	// This would analyze the current subscription and return available upgrade/downgrade options
	// For now, return a placeholder response
	c.JSON(http.StatusOK, gin.H{
		"subscription_id":      subscriptionID,
		"available_upgrades":   []gin.H{},
		"available_downgrades": []gin.H{},
		"lateral_moves":        []gin.H{},
		"message":              "Feature in development - shows available plan transitions",
	})
}

func (h *PlanTransitionHandler) GetTransitionStatus(c *gin.Context) {
	transitionIDStr := c.Param("transition_id")
	transitionID, err := uuid.Parse(transitionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid transition ID"})
		return
	}

	// This would get the current status of a transition
	// For now, return a placeholder response
	c.JSON(http.StatusOK, gin.H{
		"transition_id": transitionID,
		"status":        "PENDING",
		"message":       "Transition status tracking in development",
	})
}
