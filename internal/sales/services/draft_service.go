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

// DraftService handles daily sales draft persistence
// Replaces Hive local storage for cross-device consistency
type DraftService struct {
	db                *database.DB
	dailySalesService *DailySalesService
}

// NewDraftService creates a new draft service
func NewDraftService(db *database.DB, dailySalesService *DailySalesService) *DraftService {
	return &DraftService{
		db:                db,
		dailySalesService: dailySalesService,
	}
}

// SaveDraftRequest represents the request to save a draft
type SaveDraftRequest struct {
	ShopID     uuid.UUID `json:"shop_id" binding:"required"`
	RecordDate time.Time `json:"record_date" binding:"required"`
	DraftData  any       `json:"draft_data" binding:"required"`
	DeviceID   string    `json:"device_id,omitempty"`
	AppVersion string    `json:"app_version,omitempty"`
}

// DraftResponse represents the draft response
type DraftResponse struct {
	ID             uuid.UUID   `json:"id"`
	ShopID         uuid.UUID   `json:"shop_id"`
	ShopName       string      `json:"shop_name,omitempty"`
	RecordDate     time.Time   `json:"record_date"`
	DraftData      interface{} `json:"draft_data"`
	CreatedAt      time.Time   `json:"created_at"`
	UpdatedAt      time.Time   `json:"updated_at"`
	LastAutoSaveAt *time.Time  `json:"last_auto_save_at,omitempty"`
}

// GetDraft retrieves a user's draft for a specific shop and date
func (s *DraftService) GetDraft(ctx context.Context, tenantID, userID, shopID uuid.UUID, recordDate time.Time) (*DraftResponse, error) {
	var draft models.DailySalesDraft

	// Normalize date to start of day
	recordDateOnly := time.Date(recordDate.Year(), recordDate.Month(), recordDate.Day(), 0, 0, 0, 0, time.UTC)

	err := s.db.DB.WithContext(ctx).
		Preload("Shop").
		Where("tenant_id = ? AND user_id = ? AND shop_id = ? AND record_date = ?",
			tenantID, userID, shopID, recordDateOnly).
		First(&draft).Error

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil // No draft found, return nil
		}
		return nil, fmt.Errorf("failed to get draft: %w", err)
	}

	// Parse draft data from JSON
	var draftData interface{}
	if err := json.Unmarshal([]byte(draft.DraftData), &draftData); err != nil {
		return nil, fmt.Errorf("failed to parse draft data: %w", err)
	}

	// Build response
	response := &DraftResponse{
		ID:             draft.ID,
		ShopID:         draft.ShopID,
		RecordDate:     draft.RecordDate,
		DraftData:      draftData,
		CreatedAt:      draft.CreatedAt,
		UpdatedAt:      draft.UpdatedAt,
		LastAutoSaveAt: draft.LastAutoSaveAt,
	}

	if draft.Shop != nil {
		response.ShopName = draft.Shop.Name
	}

	return response, nil
}

// SaveDraft creates or updates a draft (upsert)
func (s *DraftService) SaveDraft(ctx context.Context, tenantID, userID uuid.UUID, req SaveDraftRequest) (*DraftResponse, error) {
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

	// Normalize date to start of day
	recordDateOnly := time.Date(req.RecordDate.Year(), req.RecordDate.Month(), req.RecordDate.Day(), 0, 0, 0, 0, time.UTC)

	// Marshal draft data to JSON
	draftDataJSON, err := json.Marshal(req.DraftData)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal draft data: %w", err)
	}

	// Size limit check (1MB max)
	if len(draftDataJSON) > 1024*1024 {
		return nil, fmt.Errorf("draft data exceeds 1MB limit")
	}

	now := time.Now()
	draft := models.DailySalesDraft{
		ID:             uuid.New(),
		TenantID:       tenantID,
		UserID:         userID,
		ShopID:         req.ShopID,
		RecordDate:     recordDateOnly,
		DraftData:      string(draftDataJSON),
		LastAutoSaveAt: &now,
		DeviceID:       req.DeviceID,
		AppVersion:     req.AppVersion,
	}

	// Upsert: Insert or update on conflict
	err = s.db.DB.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "tenant_id"},
			{Name: "user_id"},
			{Name: "shop_id"},
			{Name: "record_date"},
		},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"draft_data":        string(draftDataJSON),
			"last_auto_save_at": now,
			"device_id":         req.DeviceID,
			"app_version":       req.AppVersion,
			"updated_at":        now,
		}),
	}).Create(&draft).Error

	if err != nil {
		return nil, fmt.Errorf("failed to save draft: %w", err)
	}

	// Fetch the saved/updated draft to get correct timestamps
	var savedDraft models.DailySalesDraft
	err = s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND shop_id = ? AND record_date = ?",
			tenantID, userID, req.ShopID, recordDateOnly).
		First(&savedDraft).Error

	if err != nil {
		return nil, fmt.Errorf("failed to fetch saved draft: %w", err)
	}

	// Parse draft data back for response
	var draftDataResponse interface{}
	json.Unmarshal([]byte(savedDraft.DraftData), &draftDataResponse)

	return &DraftResponse{
		ID:             savedDraft.ID,
		ShopID:         savedDraft.ShopID,
		ShopName:       shop.Name,
		RecordDate:     savedDraft.RecordDate,
		DraftData:      draftDataResponse,
		CreatedAt:      savedDraft.CreatedAt,
		UpdatedAt:      savedDraft.UpdatedAt,
		LastAutoSaveAt: savedDraft.LastAutoSaveAt,
	}, nil
}

// DiscardDraft deletes a draft
func (s *DraftService) DiscardDraft(ctx context.Context, tenantID, userID, shopID uuid.UUID, recordDate time.Time) error {
	// Normalize date to start of day
	recordDateOnly := time.Date(recordDate.Year(), recordDate.Month(), recordDate.Day(), 0, 0, 0, 0, time.UTC)

	result := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND shop_id = ? AND record_date = ?",
			tenantID, userID, shopID, recordDateOnly).
		Delete(&models.DailySalesDraft{})

	if result.Error != nil {
		return fmt.Errorf("failed to discard draft: %w", result.Error)
	}

	if result.RowsAffected == 0 {
		return fmt.Errorf("draft not found")
	}

	return nil
}

// SubmitDraft converts a draft to a pending daily sales record
func (s *DraftService) SubmitDraft(ctx context.Context, tenantID, userID, shopID uuid.UUID, recordDate time.Time) (*DailySalesRecordResponse, error) {
	// Normalize date to start of day
	recordDateOnly := time.Date(recordDate.Year(), recordDate.Month(), recordDate.Day(), 0, 0, 0, 0, time.UTC)

	// Fetch the draft
	var draft models.DailySalesDraft
	err := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND shop_id = ? AND record_date = ?",
			tenantID, userID, shopID, recordDateOnly).
		First(&draft).Error

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("draft not found")
		}
		return nil, fmt.Errorf("failed to get draft: %w", err)
	}

	// Parse draft data
	var draftData models.DraftDataContent
	if err := json.Unmarshal([]byte(draft.DraftData), &draftData); err != nil {
		return nil, fmt.Errorf("failed to parse draft data: %w", err)
	}

	// Validate draft has required data
	if len(draftData.Items) == 0 {
		return nil, fmt.Errorf("draft has no items, cannot submit")
	}

	if draftData.TotalSalesAmount <= 0 {
		return nil, fmt.Errorf("draft has invalid total sales amount")
	}

	// Convert draft to DailySalesRecordRequest
	var salesmanID *uuid.UUID
	if draftData.SalesmanID != nil && *draftData.SalesmanID != "" {
		parsedID, err := uuid.Parse(*draftData.SalesmanID)
		if err == nil {
			salesmanID = &parsedID
		}
	}

	// Convert items
	items := make([]DailySalesItemRequest, 0, len(draftData.Items))
	for _, item := range draftData.Items {
		productID, err := uuid.Parse(item.ProductID)
		if err != nil {
			return nil, fmt.Errorf("invalid product ID in draft item: %s", item.ProductID)
		}
		items = append(items, DailySalesItemRequest{
			ProductID:    productID,
			Quantity:     item.Quantity,
			UnitPrice:    item.UnitPrice,
			TotalAmount:  item.TotalAmount,
			CashAmount:   item.CashAmount,
			CardAmount:   item.CardAmount,
			UpiAmount:    item.UpiAmount,
			CreditAmount: item.CreditAmount,
		})
	}

	// Convert expenses
	expenses := make([]DailySalesExpenseRequest, 0, len(draftData.Expenses))
	for _, expense := range draftData.Expenses {
		expenses = append(expenses, DailySalesExpenseRequest{
			HeaderID:   expense.HeaderID,
			HeaderName: expense.HeaderName,
			Amount:     expense.Amount,
		})
	}

	// Build the request
	req := DailySalesRecordRequest{
		RecordDate:         recordDateOnly,
		ShopID:             shopID,
		SalesmanID:         salesmanID,
		TotalSalesAmount:   draftData.TotalSalesAmount,
		TotalCashAmount:    draftData.TotalCashAmount,
		TotalCardAmount:    draftData.TotalCardAmount,
		TotalUpiAmount:     draftData.TotalUpiAmount,
		TotalCreditAmount:  draftData.TotalCreditAmount,
		TotalExpenseAmount: draftData.TotalExpenseAmount,
		Notes:              draftData.Notes,
		Items:              items,
		Expenses:           expenses,
		Latitude:           draftData.Latitude,
		Longitude:          draftData.Longitude,
		ImageURLs:          draftData.ImageURLs,
	}

	// Set location accuracy if provided
	if draftData.LocationAccuracy != "" {
		req.LocationAccuracy = &draftData.LocationAccuracy
	}
	if draftData.LocationCapturedAt != "" {
		req.LocationCapturedAt = &draftData.LocationCapturedAt
	}

	// Create the daily sales record using the existing service
	record, err := s.dailySalesService.CreateDailySalesRecord(ctx, req, tenantID, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to create daily sales record from draft: %w", err)
	}

	// Delete the draft after successful submission
	s.db.DB.WithContext(ctx).
		Where("id = ?", draft.ID).
		Delete(&models.DailySalesDraft{})

	return record, nil
}

// GetUserDrafts retrieves all drafts for a user (across all shops)
func (s *DraftService) GetUserDrafts(ctx context.Context, tenantID, userID uuid.UUID) ([]DraftResponse, error) {
	var drafts []models.DailySalesDraft

	err := s.db.DB.WithContext(ctx).
		Preload("Shop").
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Order("updated_at DESC").
		Find(&drafts).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get user drafts: %w", err)
	}

	responses := make([]DraftResponse, 0, len(drafts))
	for _, draft := range drafts {
		var draftData interface{}
		json.Unmarshal([]byte(draft.DraftData), &draftData)

		response := DraftResponse{
			ID:             draft.ID,
			ShopID:         draft.ShopID,
			RecordDate:     draft.RecordDate,
			DraftData:      draftData,
			CreatedAt:      draft.CreatedAt,
			UpdatedAt:      draft.UpdatedAt,
			LastAutoSaveAt: draft.LastAutoSaveAt,
		}

		if draft.Shop != nil {
			response.ShopName = draft.Shop.Name
		}

		responses = append(responses, response)
	}

	return responses, nil
}

// CleanupOldDrafts removes drafts older than the specified duration
// Should be called by a background job
func (s *DraftService) CleanupOldDrafts(ctx context.Context, olderThan time.Duration) (int64, error) {
	cutoffTime := time.Now().Add(-olderThan)

	result := s.db.DB.WithContext(ctx).
		Where("updated_at < ?", cutoffTime).
		Delete(&models.DailySalesDraft{})

	if result.Error != nil {
		return 0, fmt.Errorf("failed to cleanup old drafts: %w", result.Error)
	}

	return result.RowsAffected, nil
}
