package services

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// PurchaseDraftService handles stock purchase draft persistence
type PurchaseDraftService struct {
	db              *database.DB
	purchaseService *PurchaseService
}

// NewPurchaseDraftService creates a new purchase draft service
func NewPurchaseDraftService(db *database.DB, purchaseService *PurchaseService) *PurchaseDraftService {
	return &PurchaseDraftService{
		db:              db,
		purchaseService: purchaseService,
	}
}

// DraftItem represents a single item in the draft
type DraftItem struct {
	ProductID   string  `json:"product_id"`
	ProductName string  `json:"product_name"`
	BrandName   string  `json:"brand_name,omitempty"`
	Size        string  `json:"size"`
	Quantity    int     `json:"quantity"`
	CostPrice   float64 `json:"cost_price"`
}

// SavePurchaseDraftRequest represents the request to save a draft
type SavePurchaseDraftRequest struct {
	ShopID        uuid.UUID   `json:"shop_id" binding:"required"`
	UserID        uuid.UUID   `json:"user_id" binding:"required"`
	ShopName      string      `json:"shop_name"`
	Items         []DraftItem `json:"items"`
	VendorID      *string     `json:"vendor_id,omitempty"`
	ReceiptURL    *string     `json:"receipt_url,omitempty"`
	ReceiptNumber *string     `json:"receipt_number,omitempty"`
	ReceiptDate   *time.Time  `json:"receipt_date,omitempty"`
	DeviceID      string      `json:"device_id,omitempty"`
	Version       int         `json:"version,omitempty"`
}

// PurchaseDraftResponse represents the draft response
type PurchaseDraftResponse struct {
	ID            uuid.UUID   `json:"id"`
	ShopID        uuid.UUID   `json:"shop_id"`
	UserID        uuid.UUID   `json:"user_id"`
	ShopName      string      `json:"shop_name,omitempty"`
	Items         []DraftItem `json:"items"`
	VendorID      *uuid.UUID  `json:"vendor_id,omitempty"`
	ReceiptURL    *string     `json:"receipt_url,omitempty"`
	ReceiptNumber *string     `json:"receipt_number,omitempty"`
	ReceiptDate   *time.Time  `json:"receipt_date,omitempty"`
	TotalAmount   float64     `json:"total_amount"`
	ItemCount     int         `json:"item_count"`
	DeviceID      string      `json:"device_id,omitempty"`
	Version       int         `json:"version"`
	CreatedAt     time.Time   `json:"created_at"`
	UpdatedAt     time.Time   `json:"updated_at"`
}

// GetDraft retrieves a user's draft for a specific shop
func (s *PurchaseDraftService) GetDraft(ctx context.Context, tenantID, userID, shopID uuid.UUID) (*PurchaseDraftResponse, error) {
	var draft models.StockPurchaseDraft

	err := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND shop_id = ?",
			tenantID, userID, shopID).
		First(&draft).Error

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil // No draft found, return nil
		}
		return nil, fmt.Errorf("failed to get draft: %w", err)
	}

	return s.buildDraftResponse(&draft)
}

// SaveDraft creates or updates a draft (upsert)
func (s *PurchaseDraftService) SaveDraft(ctx context.Context, tenantID uuid.UUID, req SavePurchaseDraftRequest) (*PurchaseDraftResponse, error) {
	// Validate shop exists and belongs to tenant
	var shop models.Shop
	if err := s.db.DB.WithContext(ctx).
		Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).
		First(&shop).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("shop not found or access denied")
		}
		return nil, fmt.Errorf("failed to validate shop: %w", err)
	}

	// Calculate totals
	var totalAmount float64
	for _, item := range req.Items {
		totalAmount += float64(item.Quantity) * item.CostPrice
	}
	itemCount := len(req.Items)

	// Marshal items to JSON
	draftData := map[string]interface{}{
		"items": req.Items,
	}
	draftDataJSON, err := json.Marshal(draftData)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal draft data: %w", err)
	}

	// Size limit check (1MB max)
	if len(draftDataJSON) > 1024*1024 {
		return nil, fmt.Errorf("draft data exceeds 1MB limit")
	}

	// Parse vendor ID if provided
	var vendorID *uuid.UUID
	if req.VendorID != nil && *req.VendorID != "" {
		parsedID, err := uuid.Parse(*req.VendorID)
		if err == nil {
			vendorID = &parsedID
		}
	}

	newVersion := req.Version + 1

	draft := models.StockPurchaseDraft{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		ShopID:        req.ShopID,
		UserID:        req.UserID,
		ShopName:      req.ShopName,
		DraftData:     string(draftDataJSON),
		VendorID:      vendorID,
		ReceiptURL:    req.ReceiptURL,
		ReceiptNumber: req.ReceiptNumber,
		ReceiptDate:   req.ReceiptDate,
		TotalAmount:   totalAmount,
		ItemCount:     itemCount,
		DeviceID:      req.DeviceID,
		Version:       newVersion,
	}

	// Upsert: Insert or update on conflict
	err = s.db.DB.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "tenant_id"},
			{Name: "shop_id"},
			{Name: "user_id"},
		},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"shop_name":      req.ShopName,
			"draft_data":     string(draftDataJSON),
			"vendor_id":      vendorID,
			"receipt_url":    req.ReceiptURL,
			"receipt_number": req.ReceiptNumber,
			"receipt_date":   req.ReceiptDate,
			"total_amount":   totalAmount,
			"item_count":     itemCount,
			"device_id":      req.DeviceID,
			"version":        newVersion,
			"updated_at":     time.Now(),
		}),
	}).Create(&draft).Error

	if err != nil {
		return nil, fmt.Errorf("failed to save draft: %w", err)
	}

	// Fetch the saved/updated draft to get correct timestamps
	var savedDraft models.StockPurchaseDraft
	err = s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND shop_id = ?",
			tenantID, req.UserID, req.ShopID).
		First(&savedDraft).Error

	if err != nil {
		return nil, fmt.Errorf("failed to fetch saved draft: %w", err)
	}

	return s.buildDraftResponse(&savedDraft)
}

// DeleteDraft deletes a draft
func (s *PurchaseDraftService) DeleteDraft(ctx context.Context, tenantID, userID, shopID uuid.UUID) error {
	result := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND shop_id = ?",
			tenantID, userID, shopID).
		Delete(&models.StockPurchaseDraft{})

	if result.Error != nil {
		return fmt.Errorf("failed to delete draft: %w", result.Error)
	}

	// Don't return error if no rows affected - draft might not exist which is fine
	return nil
}

// GetUserDrafts retrieves all drafts for a user (across all shops)
func (s *PurchaseDraftService) GetUserDrafts(ctx context.Context, tenantID, userID uuid.UUID) ([]PurchaseDraftResponse, error) {
	var drafts []models.StockPurchaseDraft

	err := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Order("updated_at DESC").
		Find(&drafts).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get user drafts: %w", err)
	}

	responses := make([]PurchaseDraftResponse, 0, len(drafts))
	for _, draft := range drafts {
		response, err := s.buildDraftResponse(&draft)
		if err != nil {
			continue // Skip drafts with invalid data
		}
		responses = append(responses, *response)
	}

	return responses, nil
}

// buildDraftResponse builds a response from a draft model
func (s *PurchaseDraftService) buildDraftResponse(draft *models.StockPurchaseDraft) (*PurchaseDraftResponse, error) {
	// Parse draft data from JSON
	var draftData map[string]interface{}
	if err := json.Unmarshal([]byte(draft.DraftData), &draftData); err != nil {
		return nil, fmt.Errorf("failed to parse draft data: %w", err)
	}

	// Parse items
	var items []DraftItem
	if itemsRaw, ok := draftData["items"]; ok {
		itemsJSON, _ := json.Marshal(itemsRaw)
		json.Unmarshal(itemsJSON, &items)
	}

	return &PurchaseDraftResponse{
		ID:            draft.ID,
		ShopID:        draft.ShopID,
		UserID:        draft.UserID,
		ShopName:      draft.ShopName,
		Items:         items,
		VendorID:      draft.VendorID,
		ReceiptURL:    draft.ReceiptURL,
		ReceiptNumber: draft.ReceiptNumber,
		ReceiptDate:   draft.ReceiptDate,
		TotalAmount:   draft.TotalAmount,
		ItemCount:     draft.ItemCount,
		DeviceID:      draft.DeviceID,
		Version:       draft.Version,
		CreatedAt:     draft.CreatedAt,
		UpdatedAt:     draft.UpdatedAt,
	}, nil
}

// CleanupOldDrafts removes drafts older than the specified duration
// Should be called by a background job
func (s *PurchaseDraftService) CleanupOldDrafts(ctx context.Context, olderThan time.Duration) (int64, error) {
	cutoffTime := time.Now().Add(-olderThan)

	result := s.db.DB.WithContext(ctx).
		Where("updated_at < ?", cutoffTime).
		Delete(&models.StockPurchaseDraft{})

	if result.Error != nil {
		return 0, fmt.Errorf("failed to cleanup old drafts: %w", result.Error)
	}

	return result.RowsAffected, nil
}
