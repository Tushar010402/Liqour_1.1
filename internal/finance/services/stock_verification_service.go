package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

type StockVerificationService struct {
	db                   *database.DB
	cache                *cache.Cache
	workflowNotification *notifservices.WorkflowNotificationService
}

func NewStockVerificationService(db *database.DB, cache *cache.Cache) *StockVerificationService {
	return &StockVerificationService{
		db:    db,
		cache: cache,
	}
}

// SetWorkflowNotificationService sets the workflow notification service
func (s *StockVerificationService) SetWorkflowNotificationService(wn *notifservices.WorkflowNotificationService) {
	s.workflowNotification = wn
}

// Request types
type CreateStockVerificationRequest struct {
	ShopID            uuid.UUID                        `json:"shop_id" binding:"required"`
	VerificationDate  string                           `json:"verification_date" binding:"required"`
	MoneyCollectionID *uuid.UUID                       `json:"money_collection_id"`
	Notes             string                           `json:"notes"`
	Items             []StockVerificationItemRequest   `json:"items" binding:"required,min=1"`
}

type StockVerificationItemRequest struct {
	ProductID        uuid.UUID `json:"product_id" binding:"required"`
	SystemQuantity   int       `json:"system_quantity"`
	PhysicalQuantity int       `json:"physical_quantity" binding:"required,gte=0"`
	UnitValue        float64   `json:"unit_value"`
	Reason           string    `json:"reason"`
}

// Response types
type StockVerificationResponse struct {
	ID                uuid.UUID                       `json:"id"`
	ShopID            uuid.UUID                       `json:"shop_id"`
	ShopName          string                          `json:"shop_name"`
	MoneyCollectionID *uuid.UUID                      `json:"money_collection_id,omitempty"`
	VerificationDate  time.Time                       `json:"verification_date"`
	TotalStockValue   float64                         `json:"total_stock_value"`
	DiscrepancyAmount float64                         `json:"discrepancy_amount"`
	Notes             string                          `json:"notes"`
	Status            string                          `json:"status"`
	ApprovedAt        *time.Time                      `json:"approved_at,omitempty"`
	ApprovedByID      *uuid.UUID                      `json:"approved_by_id,omitempty"`
	ApprovedByName    string                          `json:"approved_by_name,omitempty"`
	RejectionReason   string                          `json:"rejection_reason,omitempty"`
	CreatedByID       uuid.UUID                       `json:"created_by_id"`
	CreatedByName     string                          `json:"created_by_name"`
	CreatedAt         time.Time                       `json:"created_at"`
	Items             []StockVerificationItemResponse `json:"items,omitempty"`
}

type StockVerificationItemResponse struct {
	ID                  uuid.UUID `json:"id"`
	ProductID           uuid.UUID `json:"product_id"`
	ProductName         string    `json:"product_name"`
	ProductSKU          string    `json:"product_sku"`
	SystemQuantity      int       `json:"system_quantity"`
	PhysicalQuantity    int       `json:"physical_quantity"`
	DiscrepancyQuantity int       `json:"discrepancy_quantity"`
	UnitValue           float64   `json:"unit_value"`
	DiscrepancyValue    float64   `json:"discrepancy_value"`
	Reason              string    `json:"reason"`
}

type StockAuditLogResponse struct {
	ID                  uuid.UUID  `json:"id"`
	StockVerificationID *uuid.UUID `json:"stock_verification_id,omitempty"`
	ProductID           uuid.UUID  `json:"product_id"`
	ProductName         string     `json:"product_name"`
	ShopID              uuid.UUID  `json:"shop_id"`
	ShopName            string     `json:"shop_name"`
	Action              string     `json:"action"`
	PreviousQuantity    int        `json:"previous_quantity"`
	NewQuantity         int        `json:"new_quantity"`
	QuantityChange      int        `json:"quantity_change"`
	Reason              string     `json:"reason"`
	UnitValue           float64    `json:"unit_value,omitempty"`
	TotalValueChange    float64    `json:"total_value_change,omitempty"`
	PerformedByID       uuid.UUID  `json:"performed_by_id"`
	PerformedByName     string     `json:"performed_by_name"`
	PerformedAt         time.Time  `json:"performed_at"`
	ApprovedByID        *uuid.UUID `json:"approved_by_id,omitempty"`
	ApprovedByName      string     `json:"approved_by_name,omitempty"`
	ApprovedAt          *time.Time `json:"approved_at,omitempty"`
}

// Create creates a new stock verification
func (s *StockVerificationService) Create(ctx context.Context, tenantID uuid.UUID, userID uuid.UUID, req *CreateStockVerificationRequest) (*StockVerificationResponse, error) {
	verificationDate, err := time.Parse("2006-01-02", req.VerificationDate)
	if err != nil {
		return nil, fmt.Errorf("invalid verification_date format, use YYYY-MM-DD: %w", err)
	}

	// Start transaction
	tx := s.db.WithContext(ctx).Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Create verification header
	verification := &models.StockVerification{
		TenantModel: models.TenantModel{
			TenantID: &tenantID,
		},
		ShopID:            req.ShopID,
		MoneyCollectionID: req.MoneyCollectionID,
		VerificationDate:  verificationDate,
		Notes:             req.Notes,
		Status:            "pending",
		CreatedByID:       userID,
	}

	if err := tx.Create(verification).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create stock verification: %w", err)
	}

	// Process items and calculate totals
	var totalStockValue float64
	var totalDiscrepancy float64

	for _, itemReq := range req.Items {
		// Calculate discrepancy
		discrepancyQty := itemReq.PhysicalQuantity - itemReq.SystemQuantity
		discrepancyValue := float64(discrepancyQty) * itemReq.UnitValue
		totalStockValue += float64(itemReq.PhysicalQuantity) * itemReq.UnitValue
		totalDiscrepancy += discrepancyValue

		item := &models.StockVerificationItem{
			TenantModel: models.TenantModel{
				TenantID: &tenantID,
			},
			StockVerificationID: verification.ID,
			ProductID:           itemReq.ProductID,
			SystemQuantity:      itemReq.SystemQuantity,
			PhysicalQuantity:    itemReq.PhysicalQuantity,
			DiscrepancyQuantity: discrepancyQty,
			UnitValue:           itemReq.UnitValue,
			DiscrepancyValue:    discrepancyValue,
			Reason:              itemReq.Reason,
		}

		if err := tx.Create(item).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create verification item: %w", err)
		}

		// Create audit log entry
		auditLog := &models.StockAuditLog{
			TenantID:            tenantID,
			StockVerificationID: &verification.ID,
			ProductID:           itemReq.ProductID,
			ShopID:              req.ShopID,
			Action:              "verification",
			PreviousQuantity:    itemReq.SystemQuantity,
			NewQuantity:         itemReq.PhysicalQuantity,
			QuantityChange:      discrepancyQty,
			Reason:              itemReq.Reason,
			UnitValue:           itemReq.UnitValue,
			TotalValueChange:    discrepancyValue,
			PerformedByID:       userID,
			PerformedAt:         time.Now(),
		}

		if err := tx.Create(auditLog).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create audit log: %w", err)
		}
	}

	// Update verification totals
	verification.TotalStockValue = totalStockValue
	verification.DiscrepancyAmount = totalDiscrepancy

	if err := tx.Save(verification).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update verification totals: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return s.GetByID(ctx, tenantID, verification.ID)
}

// GetByID retrieves a stock verification by ID
func (s *StockVerificationService) GetByID(ctx context.Context, tenantID uuid.UUID, id uuid.UUID) (*StockVerificationResponse, error) {
	var verification models.StockVerification
	err := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Preload("Items.Product").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&verification).Error

	if err != nil {
		return nil, fmt.Errorf("stock verification not found: %w", err)
	}

	return s.toResponse(&verification), nil
}

// List retrieves stock verifications with filters
func (s *StockVerificationService) List(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]StockVerificationResponse, int64, error) {
	var verifications []models.StockVerification
	var total int64

	query := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("ApprovedBy").
		Preload("CreatedBy").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	// Apply filters
	if status, ok := filters["status"].(string); ok && status != "" {
		query = query.Where("status = ?", status)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}

	// Count total
	query.Model(&models.StockVerification{}).Count(&total)

	// Pagination
	limit := 50
	offset := 0
	if l, ok := filters["limit"].(int); ok {
		limit = l
	}
	if o, ok := filters["offset"].(int); ok {
		offset = o
	}

	if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&verifications).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to list stock verifications: %w", err)
	}

	responses := make([]StockVerificationResponse, len(verifications))
	for i, v := range verifications {
		responses[i] = *s.toResponse(&v)
	}

	return responses, total, nil
}

// Approve approves a stock verification and adjusts stock
func (s *StockVerificationService) Approve(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID) (*StockVerificationResponse, error) {
	tx := s.db.WithContext(ctx).Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	var verification models.StockVerification
	err := tx.Preload("Items").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&verification).Error

	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("stock verification not found: %w", err)
	}

	if verification.Status != "pending" && verification.Status != "completed" {
		tx.Rollback()
		return nil, fmt.Errorf("cannot approve: verification must be in pending or completed status (current: %s)", verification.Status)
	}

	// Apply stock adjustments
	for _, item := range verification.Items {
		if item.DiscrepancyQuantity != 0 {
			// Update the stock quantity
			if err := tx.Model(&models.Stock{}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
					verification.ShopID, item.ProductID, tenantID).
				UpdateColumn("current_quantity", item.PhysicalQuantity).Error; err != nil {
				tx.Rollback()
				return nil, fmt.Errorf("failed to adjust stock: %w", err)
			}

			// Update audit log with approval
			tx.Model(&models.StockAuditLog{}).
				Where("stock_verification_id = ? AND product_id = ?", id, item.ProductID).
				Updates(map[string]interface{}{
					"approved_by_id": approverID,
					"approved_at":    time.Now(),
				})
		}
	}

	now := time.Now()
	verification.Status = "approved"
	verification.ApprovedAt = &now
	verification.ApprovedByID = &approverID

	if err := tx.Save(&verification).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to approve verification: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Send notification to creator about approval
	if s.workflowNotification != nil && verification.CreatedByID != uuid.Nil {
		var approver models.User
		if err := s.db.WithContext(ctx).First(&approver, "id = ?", approverID).Error; err == nil {
			go func() {
				if err := s.workflowNotification.NotifyStockVerificationApproved(
					context.Background(), tenantID, verification.CreatedByID, approverID,
					verification.ID, approver.FullName(),
				); err != nil {
					// Log error but don't fail
				}
			}()
		}
	}

	return s.GetByID(ctx, tenantID, id)
}

// Reject rejects a stock verification
func (s *StockVerificationService) Reject(ctx context.Context, tenantID uuid.UUID, id uuid.UUID, approverID uuid.UUID, reason string) (*StockVerificationResponse, error) {
	var verification models.StockVerification
	err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", id, tenantID).
		First(&verification).Error

	if err != nil {
		return nil, fmt.Errorf("stock verification not found: %w", err)
	}

	if verification.Status != "pending" && verification.Status != "completed" {
		return nil, fmt.Errorf("cannot reject: verification must be in pending or completed status (current: %s)", verification.Status)
	}

	now := time.Now()
	verification.Status = "rejected"
	verification.ApprovedAt = &now
	verification.ApprovedByID = &approverID

	// Store rejection reason in a model field if available
	// For now, we'll update via raw SQL
	s.db.WithContext(ctx).Exec(
		"UPDATE stock_verifications SET rejection_reason = ? WHERE id = ?",
		reason, id)

	if err := s.db.WithContext(ctx).Save(&verification).Error; err != nil {
		return nil, fmt.Errorf("failed to reject verification: %w", err)
	}

	// Send notification to creator about rejection
	if s.workflowNotification != nil && verification.CreatedByID != uuid.Nil {
		var rejector models.User
		if err := s.db.WithContext(ctx).First(&rejector, "id = ?", approverID).Error; err == nil {
			go func() {
				if err := s.workflowNotification.NotifyStockVerificationRejected(
					context.Background(), tenantID, verification.CreatedByID, approverID,
					verification.ID, rejector.FullName(), reason,
				); err != nil {
					// Log error but don't fail
				}
			}()
		}
	}

	return s.GetByID(ctx, tenantID, id)
}

// GetAuditLogs retrieves audit logs
func (s *StockVerificationService) GetAuditLogs(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]StockAuditLogResponse, int64, error) {
	var logs []models.StockAuditLog
	var total int64

	query := s.db.WithContext(ctx).
		Preload("Product").
		Preload("Shop").
		Preload("PerformedBy").
		Preload("ApprovedBy").
		Where("tenant_id = ?", tenantID)

	// Apply filters
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if productID, ok := filters["product_id"].(uuid.UUID); ok {
		query = query.Where("product_id = ?", productID)
	}
	if action, ok := filters["action"].(string); ok && action != "" {
		query = query.Where("action = ?", action)
	}
	if verificationID, ok := filters["stock_verification_id"].(uuid.UUID); ok {
		query = query.Where("stock_verification_id = ?", verificationID)
	}

	// Count total
	query.Model(&models.StockAuditLog{}).Count(&total)

	// Pagination
	limit := 100
	offset := 0
	if l, ok := filters["limit"].(int); ok {
		limit = l
	}
	if o, ok := filters["offset"].(int); ok {
		offset = o
	}

	if err := query.Order("performed_at DESC").Limit(limit).Offset(offset).Find(&logs).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to list audit logs: %w", err)
	}

	responses := make([]StockAuditLogResponse, len(logs))
	for i, log := range logs {
		responses[i] = s.toAuditLogResponse(&log)
	}

	return responses, total, nil
}

func (s *StockVerificationService) toResponse(v *models.StockVerification) *StockVerificationResponse {
	resp := &StockVerificationResponse{
		ID:                v.ID,
		ShopID:            v.ShopID,
		MoneyCollectionID: v.MoneyCollectionID,
		VerificationDate:  v.VerificationDate,
		TotalStockValue:   v.TotalStockValue,
		DiscrepancyAmount: v.DiscrepancyAmount,
		Notes:             v.Notes,
		Status:            v.Status,
		ApprovedAt:        v.ApprovedAt,
		ApprovedByID:      v.ApprovedByID,
		CreatedByID:       v.CreatedByID,
		CreatedAt:         v.CreatedAt,
	}

	if v.Shop != nil {
		resp.ShopName = v.Shop.Name
	}
	if v.ApprovedBy != nil {
		resp.ApprovedByName = v.ApprovedBy.FirstName + " " + v.ApprovedBy.LastName
	}
	if v.CreatedBy != nil {
		resp.CreatedByName = v.CreatedBy.FirstName + " " + v.CreatedBy.LastName
	}

	// Convert items
	if len(v.Items) > 0 {
		resp.Items = make([]StockVerificationItemResponse, len(v.Items))
		for i, item := range v.Items {
			resp.Items[i] = StockVerificationItemResponse{
				ID:                  item.ID,
				ProductID:           item.ProductID,
				SystemQuantity:      item.SystemQuantity,
				PhysicalQuantity:    item.PhysicalQuantity,
				DiscrepancyQuantity: item.DiscrepancyQuantity,
				UnitValue:           item.UnitValue,
				DiscrepancyValue:    item.DiscrepancyValue,
				Reason:              item.Reason,
			}
			if item.Product != nil {
				resp.Items[i].ProductName = item.Product.Name
				resp.Items[i].ProductSKU = item.Product.SKU
			}
		}
	}

	return resp
}

func (s *StockVerificationService) toAuditLogResponse(log *models.StockAuditLog) StockAuditLogResponse {
	resp := StockAuditLogResponse{
		ID:                  log.ID,
		StockVerificationID: log.StockVerificationID,
		ProductID:           log.ProductID,
		ShopID:              log.ShopID,
		Action:              log.Action,
		PreviousQuantity:    log.PreviousQuantity,
		NewQuantity:         log.NewQuantity,
		QuantityChange:      log.QuantityChange,
		Reason:              log.Reason,
		UnitValue:           log.UnitValue,
		TotalValueChange:    log.TotalValueChange,
		PerformedByID:       log.PerformedByID,
		PerformedAt:         log.PerformedAt,
		ApprovedByID:        log.ApprovedByID,
		ApprovedAt:          log.ApprovedAt,
	}

	if log.Product != nil {
		resp.ProductName = log.Product.Name
	}
	if log.Shop != nil {
		resp.ShopName = log.Shop.Name
	}
	if log.PerformedBy != nil {
		resp.PerformedByName = log.PerformedBy.FirstName + " " + log.PerformedBy.LastName
	}
	if log.ApprovedBy != nil {
		resp.ApprovedByName = log.ApprovedBy.FirstName + " " + log.ApprovedBy.LastName
	}

	return resp
}
