package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// DraftHandlers handles stock purchase draft API requests
type DraftHandlers struct {
	draftService *services.PurchaseDraftService
}

// NewDraftHandlers creates a new DraftHandlers instance
func NewDraftHandlers(draftService *services.PurchaseDraftService) *DraftHandlers {
	return &DraftHandlers{
		draftService: draftService,
	}
}

// GetDraft retrieves a user's draft for a specific shop
// GET /api/inventory/drafts/stock-purchase?shop_id=xxx&user_id=xxx
func (h *DraftHandlers) GetDraft(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid tenant ID"})
		return
	}

	// Get shop_id from query params
	shopIDStr := c.Query("shop_id")
	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "shop_id is required"})
		return
	}
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid shop_id"})
		return
	}

	// Get user_id from query params
	userIDStr := c.Query("user_id")
	if userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "user_id is required"})
		return
	}
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid user_id"})
		return
	}

	draft, err := h.draftService.GetDraft(c.Request.Context(), tenantUUID, userID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
		return
	}

	if draft == nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "message": "No draft found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    draft,
	})
}

// SaveDraft creates or updates a draft
// POST /api/inventory/drafts/stock-purchase
func (h *DraftHandlers) SaveDraft(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid tenant ID"})
		return
	}

	var req services.SavePurchaseDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": err.Error()})
		return
	}

	draft, err := h.draftService.SaveDraft(c.Request.Context(), tenantUUID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Draft saved successfully",
		"data": gin.H{
			"id":           draft.ID,
			"shop_id":      draft.ShopID,
			"user_id":      draft.UserID,
			"total_amount": draft.TotalAmount,
			"item_count":   draft.ItemCount,
			"version":      draft.Version,
			"updated_at":   draft.UpdatedAt,
		},
	})
}

// DeleteDraft deletes a draft
// DELETE /api/inventory/drafts/stock-purchase?shop_id=xxx&user_id=xxx
func (h *DraftHandlers) DeleteDraft(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid tenant ID"})
		return
	}

	// Get shop_id from query params
	shopIDStr := c.Query("shop_id")
	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "shop_id is required"})
		return
	}
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid shop_id"})
		return
	}

	// Get user_id from query params
	userIDStr := c.Query("user_id")
	if userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "user_id is required"})
		return
	}
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid user_id"})
		return
	}

	err = h.draftService.DeleteDraft(c.Request.Context(), tenantUUID, userID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Draft deleted successfully",
	})
}

// GetUserDrafts retrieves all drafts for a user
// GET /api/inventory/drafts/stock-purchase/all
func (h *DraftHandlers) GetUserDrafts(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid tenant ID"})
		return
	}

	// Get user_id from context (authenticated user)
	userIDRaw, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "User ID not found"})
		return
	}
	userID, err := uuid.Parse(userIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid user ID"})
		return
	}

	drafts, err := h.draftService.GetUserDrafts(c.Request.Context(), tenantUUID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
		return
	}

	// Build summary response for list view
	var summaries []gin.H
	for _, draft := range drafts {
		summaries = append(summaries, gin.H{
			"id":           draft.ID,
			"shop_id":      draft.ShopID,
			"shop_name":    draft.ShopName,
			"item_count":   draft.ItemCount,
			"total_amount": draft.TotalAmount,
			"updated_at":   draft.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    summaries,
	})
}
