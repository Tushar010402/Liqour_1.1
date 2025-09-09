package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type SubscriptionHandler struct {
	subscriptionService *services.SubscriptionService
}

func NewSubscriptionHandler(subscriptionService *services.SubscriptionService) *SubscriptionHandler {
	return &SubscriptionHandler{
		subscriptionService: subscriptionService,
	}
}

func (h *SubscriptionHandler) CreateSubscription(c *gin.Context) {
	var req models.CreateSubscriptionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	subscription, err := h.subscriptionService.CreateSubscription(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, subscription)
}

func (h *SubscriptionHandler) GetSubscription(c *gin.Context) {
	// Get tenant ID from JWT token context
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant_id is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id format"})
		return
	}

	subscription, err := h.subscriptionService.GetSubscription(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	// Get usage data
	usage, err := h.subscriptionService.GetUsage(c.Request.Context(), subscription.ID)
	if err == nil {
		subscription.Usage = usage
	}

	c.JSON(http.StatusOK, subscription)
}

func (h *SubscriptionHandler) UpdateSubscription(c *gin.Context) {
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	var req models.UpdateSubscriptionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	subscription, err := h.subscriptionService.UpdateSubscription(c.Request.Context(), subscriptionID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, subscription)
}

func (h *SubscriptionHandler) CancelSubscription(c *gin.Context) {
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	err = h.subscriptionService.CancelSubscription(c.Request.Context(), subscriptionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "subscription cancelled successfully"})
}

func (h *SubscriptionHandler) UpgradeSubscription(c *gin.Context) {
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	var req struct {
		NewPlanID uuid.UUID `json:"new_plan_id" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	subscription, err := h.subscriptionService.UpgradeSubscription(c.Request.Context(), subscriptionID, req.NewPlanID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, subscription)
}

func (h *SubscriptionHandler) DowngradeSubscription(c *gin.Context) {
	// For now, downgrade works similar to upgrade but with validation
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	var req struct {
		NewPlanID uuid.UUID `json:"new_plan_id" binding:"required"`
		Reason    string    `json:"reason"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// TODO: Implement proper downgrade logic with plan validation
	subscription, err := h.subscriptionService.UpgradeSubscription(c.Request.Context(), subscriptionID, req.NewPlanID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, subscription)
}

func (h *SubscriptionHandler) GetUsage(c *gin.Context) {
	subscriptionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription ID"})
		return
	}

	usage, err := h.subscriptionService.GetUsage(c.Request.Context(), subscriptionID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, usage)
}

func (h *SubscriptionHandler) CheckLimits(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant_id is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id format"})
		return
	}

	resourceType := c.Query("resource_type")
	if resourceType == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "resource_type is required"})
		return
	}

	currentCountStr := c.Query("current_count")
	currentCount, err := strconv.Atoi(currentCountStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid current_count"})
		return
	}

	err = h.subscriptionService.CheckLimits(c.Request.Context(), tenantID, resourceType, currentCount)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error(), "limit_exceeded": true})
		return
	}

	c.JSON(http.StatusOK, gin.H{"within_limits": true})
}

func (h *SubscriptionHandler) RecordUsage(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant_id is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id format"})
		return
	}

	var req struct {
		Metrics map[string]int `json:"metrics" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.subscriptionService.RecordUsage(c.Request.Context(), tenantID, req.Metrics)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "usage recorded successfully"})
}