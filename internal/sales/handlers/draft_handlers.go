package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/services"
)

// DraftHandlers handles HTTP requests for draft operations
type DraftHandlers struct {
	draftService *services.DraftService
}

// NewDraftHandlers creates new draft handlers
func NewDraftHandlers(draftService *services.DraftService) *DraftHandlers {
	return &DraftHandlers{
		draftService: draftService,
	}
}

// GetDraft retrieves a user's draft for a specific shop and date
// GET /api/daily-sales/draft?shop_id=xxx&record_date=2025-12-25
func (h *DraftHandlers) GetDraft(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse query parameters
	shopIDStr := c.Query("shop_id")
	recordDateStr := c.Query("record_date")

	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	if recordDateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "record_date is required"})
		return
	}

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id format"})
		return
	}

	recordDate, err := time.Parse("2006-01-02", recordDateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid record_date format, expected YYYY-MM-DD"})
		return
	}

	draft, err := h.draftService.GetDraft(c.Request.Context(), tenantID, userID, shopID, recordDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if draft == nil {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"draft":   nil,
			"message": "No draft found",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"draft":   draft,
	})
}

// SaveDraft creates or updates a draft
// POST /api/daily-sales/draft
func (h *DraftHandlers) SaveDraft(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var req services.SaveDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate required fields
	if req.ShopID == uuid.Nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	if req.RecordDate.IsZero() {
		c.JSON(http.StatusBadRequest, gin.H{"error": "record_date is required"})
		return
	}

	if req.DraftData == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "draft_data is required"})
		return
	}

	draft, err := h.draftService.SaveDraft(c.Request.Context(), tenantID, userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":    true,
		"draft_id":   draft.ID,
		"updated_at": draft.UpdatedAt,
		"message":    "Draft saved successfully",
	})
}

// DiscardDraft deletes a draft
// DELETE /api/daily-sales/draft?shop_id=xxx&record_date=2025-12-25
func (h *DraftHandlers) DiscardDraft(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Parse query parameters
	shopIDStr := c.Query("shop_id")
	recordDateStr := c.Query("record_date")

	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	if recordDateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "record_date is required"})
		return
	}

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id format"})
		return
	}

	recordDate, err := time.Parse("2006-01-02", recordDateStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid record_date format, expected YYYY-MM-DD"})
		return
	}

	err = h.draftService.DiscardDraft(c.Request.Context(), tenantID, userID, shopID, recordDate)
	if err != nil {
		if err.Error() == "draft not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Draft not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Draft discarded successfully",
	})
}

// SubmitDraft converts a draft to a pending daily sales record
// POST /api/daily-sales/draft/submit
func (h *DraftHandlers) SubmitDraft(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var req struct {
		ShopID     uuid.UUID `json:"shop_id" binding:"required"`
		RecordDate time.Time `json:"record_date" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	record, err := h.draftService.SubmitDraft(c.Request.Context(), tenantID, userID, req.ShopID, req.RecordDate)
	if err != nil {
		if err.Error() == "draft not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Draft not found"})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"record_id": record.ID,
		"status":    record.Status,
		"message":   "Draft submitted for approval",
	})
}

// GetUserDrafts retrieves all drafts for the current user
// GET /api/daily-sales/drafts
func (h *DraftHandlers) GetUserDrafts(c *gin.Context) {
	tenantID, userID, err := h.getTenantAndUserID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	drafts, err := h.draftService.GetUserDrafts(c.Request.Context(), tenantID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"drafts":  drafts,
		"count":   len(drafts),
	})
}

// getTenantAndUserID extracts tenant and user IDs from context
func (h *DraftHandlers) getTenantAndUserID(c *gin.Context) (uuid.UUID, uuid.UUID, error) {
	tenantIDValue, exists := c.Get("tenant_id")
	if !exists {
		return uuid.Nil, uuid.Nil, errTenantIDRequired
	}

	userIDValue, exists := c.Get("user_id")
	if !exists {
		return uuid.Nil, uuid.Nil, errUserIDRequired
	}

	var tenantID uuid.UUID
	var userID uuid.UUID
	var err error

	switch v := tenantIDValue.(type) {
	case uuid.UUID:
		tenantID = v
	case string:
		tenantID, err = uuid.Parse(v)
		if err != nil {
			return uuid.Nil, uuid.Nil, errInvalidTenantID
		}
	default:
		return uuid.Nil, uuid.Nil, errInvalidTenantID
	}

	switch v := userIDValue.(type) {
	case uuid.UUID:
		userID = v
	case string:
		userID, err = uuid.Parse(v)
		if err != nil {
			return uuid.Nil, uuid.Nil, errInvalidUserID
		}
	default:
		return uuid.Nil, uuid.Nil, errInvalidUserID
	}

	return tenantID, userID, nil
}

// Error constants
var (
	errTenantIDRequired = &handlerError{message: "tenant_id is required"}
	errUserIDRequired   = &handlerError{message: "user_id is required"}
	errInvalidTenantID  = &handlerError{message: "invalid tenant_id"}
	errInvalidUserID    = &handlerError{message: "invalid user_id"}
)

type handlerError struct {
	message string
}

func (e *handlerError) Error() string {
	return e.message
}
