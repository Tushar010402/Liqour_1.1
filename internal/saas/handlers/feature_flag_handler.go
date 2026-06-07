package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type FeatureFlagHandler struct {
	featureFlagService *services.FeatureFlagService
}

func NewFeatureFlagHandler(featureFlagService *services.FeatureFlagService) *FeatureFlagHandler {
	return &FeatureFlagHandler{featureFlagService: featureFlagService}
}

func (h *FeatureFlagHandler) GetAllFlags(c *gin.Context) {
	flags, err := h.featureFlagService.GetAllFlags()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"feature_flags": flags})
}

func (h *FeatureFlagHandler) GetFlagByKey(c *gin.Context) {
	key := c.Param("key")
	flag, err := h.featureFlagService.GetFlagByKey(key)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"feature_flag": flag})
}

func (h *FeatureFlagHandler) CreateFlag(c *gin.Context) {
	var req models.CreateFeatureFlagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	flag, err := h.featureFlagService.CreateFlag(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success":      true,
		"message":      "feature flag created successfully",
		"feature_flag": flag,
	})
}

func (h *FeatureFlagHandler) UpdateFlag(c *gin.Context) {
	key := c.Param("key")
	var req models.UpdateFeatureFlagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	flag, err := h.featureFlagService.UpdateFlag(key, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"message":      "feature flag updated successfully",
		"feature_flag": flag,
	})
}

func (h *FeatureFlagHandler) DeleteFlag(c *gin.Context) {
	key := c.Param("key")
	if err := h.featureFlagService.DeleteFlag(key); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "feature flag deleted successfully",
	})
}

func (h *FeatureFlagHandler) CheckFeatureEnabled(c *gin.Context) {
	key := c.Param("key")
	var req struct {
		TenantID string `json:"tenant_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, err := uuid.Parse(req.TenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	enabled, err := h.featureFlagService.IsFeatureEnabled(key, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"key":     key,
		"enabled": enabled,
	})
}

func (h *FeatureFlagHandler) GetAllConfigs(c *gin.Context) {
	category := c.Query("category")
	configs, err := h.featureFlagService.GetAllConfigs(category)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"configs": configs})
}

func (h *FeatureFlagHandler) UpdateConfig(c *gin.Context) {
	key := c.Param("key")
	var req models.UpdateConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config, err := h.featureFlagService.UpdateConfig(key, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "config updated successfully",
		"config":  config,
	})
}
