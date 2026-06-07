package handlers

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// AIFeedbackHandlers handles AI feedback HTTP requests
type AIFeedbackHandlers struct {
	db *database.DB
}

// NewAIFeedbackHandlers creates a new AI feedback handlers instance
func NewAIFeedbackHandlers(db *database.DB) *AIFeedbackHandlers {
	return &AIFeedbackHandlers{db: db}
}

// SubmitAIFeedback handles POST /ai-feedback
func (h *AIFeedbackHandlers) SubmitAIFeedback(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.GetString("user_id")

	if userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user ID not found in context"})
		return
	}
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant ID not found in context"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant ID"})
		return
	}

	var req struct {
		FlowType        string               `json:"flow_type" binding:"required"`
		Rating          int                  `json:"rating" binding:"required"`
		Tags            models.JSONStringList `json:"tags"`
		Comment         *string              `json:"comment"`
		AppVersion      string               `json:"app_version"`
		Platform        string               `json:"platform"`
		DeviceModel     string               `json:"device_model"`
		ScreenName      string               `json:"screen_name"`
		SessionDuration *int                 `json:"session_duration"`
		ItemsProcessed  *int                 `json:"items_processed"`
		Metadata        models.JSONMap       `json:"metadata"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid request: %v", err)})
		return
	}

	if req.Rating < 1 || req.Rating > 5 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "rating must be between 1 and 5"})
		return
	}

	validFlows := map[string]bool{
		"stock_setup": true, "daily_sales": true, "purchase_entry": true,
		"smart_sale": true, "ocr_scan": true,
	}
	if !validFlows[req.FlowType] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "flow_type must be one of: stock_setup, daily_sales, purchase_entry, smart_sale, ocr_scan"})
		return
	}

	feedback := models.AIFeedback{
		ID:              uuid.New(),
		TenantID:        tenantID,
		UserID:          userID,
		FlowType:        req.FlowType,
		Rating:          req.Rating,
		Tags:            req.Tags,
		Comment:         req.Comment,
		AppVersion:      req.AppVersion,
		Platform:        req.Platform,
		DeviceModel:     req.DeviceModel,
		ScreenName:      req.ScreenName,
		SessionDuration: req.SessionDuration,
		ItemsProcessed:  req.ItemsProcessed,
		Metadata:        req.Metadata,
	}

	if err := h.db.WithContext(c.Request.Context()).Create(&feedback).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save feedback"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success": true,
		"id":      feedback.ID,
	})
}

// GetAIFeedback handles GET /ai-feedback (admin/manager — view all feedback for UX analysis)
func (h *AIFeedbackHandlers) GetAIFeedback(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant ID not found"})
		return
	}

	flowType := c.Query("flow_type")
	rating := c.Query("rating")

	query := h.db.WithContext(c.Request.Context()).
		Where("tenant_id = ?", tenantIDStr).
		Order("created_at DESC").
		Limit(100)

	if flowType != "" {
		query = query.Where("flow_type = ?", flowType)
	}
	if rating != "" {
		query = query.Where("rating = ?", rating)
	}

	var feedbacks []models.AIFeedback
	if err := query.Find(&feedbacks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch feedback"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"feedbacks": feedbacks,
		"count":     len(feedbacks),
	})
}
