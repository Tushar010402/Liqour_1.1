package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

type ExecutiveFinanceService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewExecutiveFinanceService(db *database.DB, cache *cache.Cache) *ExecutiveFinanceService {
	return &ExecutiveFinanceService{
		db:    db,
		cache: cache,
	}
}

// Request types
type CreateExecutiveFinanceRequest struct {
	ShopID            uuid.UUID  `json:"shop_id" binding:"required"`
	TransactionType   string     `json:"transaction_type" binding:"required,oneof=cash_handover expense_claim"`
	FromUserID        uuid.UUID  `json:"from_user_id" binding:"required"`
	ToUserID          uuid.UUID  `json:"to_user_id" binding:"required"`
	Amount            float64    `json:"amount" binding:"required,gt=0"`
	Description       string     `json:"description"`
	Notes             string     `json:"notes"`
	ExpenseCategoryID *uuid.UUID `json:"expense_category_id"`
	ReceiptURL        string     `json:"receipt_url"`
}

// Response types
type ExecutiveFinanceResponse struct {
	ID                  uuid.UUID  `json:"id"`
	ShopID              uuid.UUID  `json:"shop_id"`
	ShopName            string     `json:"shop_name"`
	TransactionType     string     `json:"transaction_type"`
	FromUserID          uuid.UUID  `json:"from_user_id"`
	FromUserName        string     `json:"from_user_name"`
	ToUserID            uuid.UUID  `json:"to_user_id"`
	ToUserName          string     `json:"to_user_name"`
	Amount              float64    `json:"amount"`
	Description         string     `json:"description"`
	Notes               string     `json:"notes"`
	ExpenseCategoryID   *uuid.UUID `json:"expense_category_id,omitempty"`
	ExpenseCategoryName string     `json:"expense_category_name,omitempty"`
	ReceiptURL          string     `json:"receipt_url,omitempty"`
	Status              string     `json:"status"`
	SubmittedAt         time.Time  `json:"submitted_at"`
	ApprovedAt          *time.Time `json:"approved_at,omitempty"`
	ApprovedByID        *uuid.UUID `json:"approved_by_id,omitempty"`
	ApprovedByName      string     `json:"approved_by_name,omitempty"`
	RejectionReason     string     `json:"rejection_reason,omitempty"`
	CreatedByID         uuid.UUID  `json:"created_by_id"`
	CreatedByName       string     `json:"created_by_name"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}

// Create creates a new executive finance record
func (s *ExecutiveFinanceService) Create(ctx context.Context, tenantID uuid.UUID, userID uuid.UUID, req *CreateExecutiveFinanceRequest) (*ExecutiveFinanceResponse, error) {
	ef := &models.ExecutiveFinance{
		TenantModel: models.TenantModel{
			TenantID: &tenantID,
		},
		ShopID:            req.ShopID,
		TransactionType:   req.TransactionType,
		FromUserID:        req.FromUserID,
		ToUserID:          req.ToUserID,
		Amount:            req.Amount,
		Description:       req.Description,
		Notes:             req.Notes,
		ExpenseCategoryID: req.ExpenseCategoryID,
		ReceiptURL:        req.ReceiptURL,
		Status:            "pending",
		SubmittedAt:       time.Now(),
		CreatedByID:       userID,
	}

	if err := s.db.WithContext(ctx).Create(ef).Error; err != nil {
		return nil, fmt.Errorf("failed to create executive finance record: %w", err)
	}

	return s.GetByID(ctx, tenantID, ef.ID)
}

// GetByID retrieves an executive finance record by ID
func (s *ExecutiveFinanceService) GetByID(ctx context.Context, tenantID uuid.UUID, id uuid.UUID) (*ExecutiveFinanceResponse, error) {
	var ef models.ExecutiveFinance
	err := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("FromUser").
		Preload("ToUser").
		Preload("ExpenseCategory").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&ef).Error

	if err != nil {
		return nil, fmt.Errorf("executive finance record not found: %w", err)
	}

	return s.toResponse(&ef), nil
}

// List retrieves executive finance records with filters
func (s *ExecutiveFinanceService) List(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]ExecutiveFinanceResponse, error) {
	var records []models.ExecutiveFinance

	query := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("FromUser").
		Preload("ToUser").
		Preload("ExpenseCategory").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	// Apply filters
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if transactionType, ok := filters["transaction_type"].(string); ok && transactionType != "" {
		query = query.Where("transaction_type = ?", transactionType)
	}
	if status, ok := filters["status"].(string); ok && status != "" {
		query = query.Where("status = ?", status)
	}
	if fromUserID, ok := filters["from_user_id"].(uuid.UUID); ok {
		query = query.Where("from_user_id = ?", fromUserID)
	}
	if toUserID, ok := filters["to_user_id"].(uuid.UUID); ok {
		query = query.Where("to_user_id = ?", toUserID)
	}

	// Pagination
	limit := 50
	offset := 0
	if l, ok := filters["limit"].(int); ok {
		limit = l
	}
	if o, ok := filters["offset"].(int); ok {
		offset = o
	}

	if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&records).Error; err != nil {
		return nil, fmt.Errorf("failed to list executive finance records: %w", err)
	}

	responses := make([]ExecutiveFinanceResponse, len(records))
	for i, ef := range records {
		responses[i] = *s.toResponse(&ef)
	}

	return responses, nil
}

// Approve approves an executive finance record
func (s *ExecutiveFinanceService) Approve(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID) (*ExecutiveFinanceResponse, error) {
	var ef models.ExecutiveFinance
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&ef).Error

	if err != nil {
		return nil, fmt.Errorf("executive finance record not found: %w", err)
	}

	if ef.Status != "pending" {
		return nil, fmt.Errorf("cannot approve: record is not in pending status (current: %s)", ef.Status)
	}

	now := time.Now()
	ef.Status = "approved"
	ef.ApprovedAt = &now
	ef.ApprovedByID = &approverID

	if err := s.db.WithContext(ctx).Save(&ef).Error; err != nil {
		return nil, fmt.Errorf("failed to approve executive finance record: %w", err)
	}

	return s.GetByID(ctx, tenantID, id)
}

// Reject rejects an executive finance record
func (s *ExecutiveFinanceService) Reject(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID, reason string) (*ExecutiveFinanceResponse, error) {
	var ef models.ExecutiveFinance
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&ef).Error

	if err != nil {
		return nil, fmt.Errorf("executive finance record not found: %w", err)
	}

	if ef.Status != "pending" {
		return nil, fmt.Errorf("cannot reject: record is not in pending status (current: %s)", ef.Status)
	}

	now := time.Now()
	ef.Status = "rejected"
	ef.ApprovedAt = &now
	ef.ApprovedByID = &approverID
	ef.RejectionReason = reason

	if err := s.db.WithContext(ctx).Save(&ef).Error; err != nil {
		return nil, fmt.Errorf("failed to reject executive finance record: %w", err)
	}

	return s.GetByID(ctx, tenantID, id)
}

// toResponse converts a model to response
func (s *ExecutiveFinanceService) toResponse(ef *models.ExecutiveFinance) *ExecutiveFinanceResponse {
	resp := &ExecutiveFinanceResponse{
		ID:              ef.ID,
		ShopID:          ef.ShopID,
		TransactionType: ef.TransactionType,
		FromUserID:      ef.FromUserID,
		ToUserID:        ef.ToUserID,
		Amount:          ef.Amount,
		Description:     ef.Description,
		Notes:           ef.Notes,
		ReceiptURL:      ef.ReceiptURL,
		Status:          ef.Status,
		SubmittedAt:     ef.SubmittedAt,
		ApprovedAt:      ef.ApprovedAt,
		ApprovedByID:    ef.ApprovedByID,
		RejectionReason: ef.RejectionReason,
		CreatedByID:     ef.CreatedByID,
		CreatedAt:       ef.CreatedAt,
		UpdatedAt:       ef.UpdatedAt,
	}

	if ef.Shop != nil {
		resp.ShopName = ef.Shop.Name
	}
	if ef.FromUser != nil {
		resp.FromUserName = ef.FromUser.FirstName + " " + ef.FromUser.LastName
	}
	if ef.ToUser != nil {
		resp.ToUserName = ef.ToUser.FirstName + " " + ef.ToUser.LastName
	}
	if ef.ExpenseCategoryID != nil {
		resp.ExpenseCategoryID = ef.ExpenseCategoryID
		if ef.ExpenseCategory != nil {
			resp.ExpenseCategoryName = ef.ExpenseCategory.Name
		}
	}
	if ef.ApprovedBy != nil {
		resp.ApprovedByName = ef.ApprovedBy.FirstName + " " + ef.ApprovedBy.LastName
	}
	if ef.CreatedBy != nil {
		resp.CreatedByName = ef.CreatedBy.FirstName + " " + ef.CreatedBy.LastName
	}

	return resp
}
