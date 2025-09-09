package services

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// ReturnsService handles sale return operations
type ReturnsService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewReturnsService creates a new returns service
func NewReturnsService(db *database.DB, cache *cache.Cache) *ReturnsService {
	return &ReturnsService{
		db:    db,
		cache: cache,
	}
}

// SaleReturnRequest represents sale return creation request
type SaleReturnRequest struct {
	SaleID       uuid.UUID               `json:"sale_id" binding:"required"`
	ReturnDate   time.Time               `json:"return_date" binding:"required"`
	Reason       string                  `json:"reason" binding:"required"`
	Notes        string                  `json:"notes"`
	Items        []SaleReturnItemRequest `json:"items" binding:"required,min=1"`
}

// SaleReturnItemRequest represents return item request
type SaleReturnItemRequest struct {
	SaleItemID  uuid.UUID `json:"sale_item_id" binding:"required"`
	Quantity    int       `json:"quantity" binding:"required,gt=0"`
	UnitPrice   float64   `json:"unit_price" binding:"required,gt=0"`
	Reason      string    `json:"reason"`
}

// SaleReturnResponse represents sale return in responses
type SaleReturnResponse struct {
	ID            uuid.UUID                `json:"id"`
	ReturnNumber  string                   `json:"return_number"`
	SaleID        uuid.UUID                `json:"sale_id"`
	SaleNumber    string                   `json:"sale_number"`
	ReturnDate    time.Time                `json:"return_date"`
	ReturnAmount  float64                  `json:"return_amount"`
	Reason        string                   `json:"reason"`
	Status        string                   `json:"status"`
	ApprovedAt    *time.Time               `json:"approved_at"`
	ApprovedByName string                  `json:"approved_by_name"`
	CreatedByName string                   `json:"created_by_name"`
	Notes         string                   `json:"notes"`
	CreatedAt     time.Time                `json:"created_at"`
	UpdatedAt     time.Time                `json:"updated_at"`
	Items         []SaleReturnItemResponse `json:"items"`
	TotalItems    int                      `json:"total_items"`
}

// SaleReturnItemResponse represents return item in responses
type SaleReturnItemResponse struct {
	ID           uuid.UUID `json:"id"`
	SaleItemID   uuid.UUID `json:"sale_item_id"`
	ProductID    uuid.UUID `json:"product_id"`
	ProductName  string    `json:"product_name"`
	BrandName    string    `json:"brand_name"`
	CategoryName string    `json:"category_name"`
	Size         string    `json:"size"`
	Quantity     int       `json:"quantity"`
	UnitPrice    float64   `json:"unit_price"`
	TotalAmount  float64   `json:"total_amount"`
	Reason       string    `json:"reason"`
}

// CreateSaleReturn creates a new sale return
func (s *ReturnsService) CreateSaleReturn(ctx context.Context, req SaleReturnRequest, tenantID, createdByID uuid.UUID) (*SaleReturnResponse, error) {
	// Verify sale exists and belongs to tenant
	var sale models.Sale
	err := s.db.Where("id = ? AND tenant_id = ?", req.SaleID, tenantID).
		Preload("Items").
		First(&sale).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to find sale: %w", err)
	}

	// Only approved sales can have returns
	if sale.Status != models.StatusApproved {
		return nil, errors.New("can only return items from approved sales")
	}

	// Create map of sale items for validation
	saleItemsMap := make(map[uuid.UUID]*models.SaleItem)
	for _, item := range sale.Items {
		saleItemsMap[item.ID] = &item
	}

	// Validate return items and calculate total
	var totalReturnAmount float64
	for _, returnItem := range req.Items {
		saleItem, exists := saleItemsMap[returnItem.SaleItemID]
		if !exists {
			return nil, fmt.Errorf("sale item %s not found in the sale", returnItem.SaleItemID)
		}

		// Check if return quantity doesn't exceed sold quantity
		// TODO: Check previously returned quantities
		if returnItem.Quantity > saleItem.Quantity {
			return nil, fmt.Errorf("return quantity (%d) exceeds sold quantity (%d) for product", 
				returnItem.Quantity, saleItem.Quantity)
		}

		totalReturnAmount += float64(returnItem.Quantity) * returnItem.UnitPrice
	}

	// Start transaction
	var saleReturn *models.SaleReturn
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Create sale return
		saleReturn = &models.SaleReturn{
			TenantModel:  models.TenantModel{TenantID: tenantID},
			ReturnNumber: utils.GenerateReturnNumber(),
			SaleID:       req.SaleID,
			ReturnDate:   req.ReturnDate,
			ReturnAmount: totalReturnAmount,
			Reason:       req.Reason,
			Status:       models.StatusPending,
			CreatedByID:  createdByID,
			Notes:        req.Notes,
		}

		if err := tx.Create(&saleReturn).Error; err != nil {
			return fmt.Errorf("failed to create sale return: %w", err)
		}

		// Create return items
		for _, itemReq := range req.Items {
			totalAmount := float64(itemReq.Quantity) * itemReq.UnitPrice

			returnItem := models.SaleReturnItem{
				TenantModel:  models.TenantModel{TenantID: tenantID},
				SaleReturnID: saleReturn.ID,
				SaleItemID:   itemReq.SaleItemID,
				Quantity:     itemReq.Quantity,
				UnitPrice:    itemReq.UnitPrice,
				TotalAmount:  totalAmount,
				Reason:       itemReq.Reason,
			}

			if err := tx.Create(&returnItem).Error; err != nil {
				return fmt.Errorf("failed to create return item: %w", err)
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearReturnsCache(ctx, tenantID, sale.ShopID)

	// Return created return
	return s.GetSaleReturnByID(ctx, saleReturn.ID, tenantID)
}

// GetSaleReturns returns paginated list of sale returns
func (s *ReturnsService) GetSaleReturns(ctx context.Context, tenantID uuid.UUID, filters ReturnsFilters) (*ReturnsListResponse, error) {
	var returns []models.SaleReturn
	var totalCount int64

	query := s.db.Model(&models.SaleReturn{}).
		Where("tenant_id = ?", tenantID).
		Preload("Sale.Shop").
		Preload("Sale.Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items.SaleItem.Product.Brand").
		Preload("Items.SaleItem.Product.Category")

	// Apply filters
	if filters.SaleID != uuid.Nil {
		query = query.Where("sale_id = ?", filters.SaleID)
	}
	if filters.ShopID != uuid.Nil {
		query = query.Joins("JOIN sales ON sale_returns.sale_id = sales.id").
			Where("sales.shop_id = ?", filters.ShopID)
	}
	if filters.Status != "" {
		query = query.Where("status = ?", filters.Status)
	}
	if !filters.StartDate.IsZero() {
		query = query.Where("return_date >= ?", filters.StartDate)
	}
	if !filters.EndDate.IsZero() {
		query = query.Where("return_date <= ?", filters.EndDate)
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count returns: %w", err)
	}

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("return_date DESC, created_at DESC").
		Find(&returns).Error; err != nil {
		return nil, fmt.Errorf("failed to get returns: %w", err)
	}

	// Convert to response format
	responses := make([]*SaleReturnResponse, len(returns))
	for i, ret := range returns {
		responses[i] = s.mapSaleReturnToResponse(&ret)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &ReturnsListResponse{
		Returns:    responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
	}, nil
}

// GetSaleReturnByID returns sale return by ID
func (s *ReturnsService) GetSaleReturnByID(ctx context.Context, returnID, tenantID uuid.UUID) (*SaleReturnResponse, error) {
	var saleReturn models.SaleReturn
	
	err := s.db.Where("id = ? AND tenant_id = ?", returnID, tenantID).
		Preload("Sale.Shop").
		Preload("Sale.Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items.SaleItem.Product.Brand").
		Preload("Items.SaleItem.Product.Category").
		First(&saleReturn).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale return not found")
		}
		return nil, fmt.Errorf("failed to get sale return: %w", err)
	}

	return s.mapSaleReturnToResponse(&saleReturn), nil
}

// ApproveSaleReturn approves a sale return
func (s *ReturnsService) ApproveSaleReturn(ctx context.Context, returnID, tenantID, approvedByID uuid.UUID) (*SaleReturnResponse, error) {
	var saleReturn models.SaleReturn
	
	err := s.db.Where("id = ? AND tenant_id = ?", returnID, tenantID).
		Preload("Sale").
		First(&saleReturn).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale return not found")
		}
		return nil, fmt.Errorf("failed to find sale return: %w", err)
	}

	// Only pending returns can be approved
	if saleReturn.Status != models.StatusPending {
		return nil, errors.New("only pending returns can be approved")
	}

	// Start transaction for approval
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Update return status
		now := time.Now()
		updates := map[string]interface{}{
			"status":         models.StatusApproved,
			"approved_at":    now,
			"approved_by_id": approvedByID,
		}

		if err := tx.Model(&saleReturn).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to approve return: %w", err)
		}

		// TODO: Update stock quantities (add returned items back to stock)
		// TODO: Process refund if needed
		// TODO: Update sale's due amount if partial refund

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearReturnsCache(ctx, tenantID, saleReturn.Sale.ShopID)

	// Return updated return
	return s.GetSaleReturnByID(ctx, returnID, tenantID)
}

// RejectSaleReturn rejects a sale return
func (s *ReturnsService) RejectSaleReturn(ctx context.Context, returnID, tenantID, rejectedByID uuid.UUID, reason string) error {
	var saleReturn models.SaleReturn
	
	err := s.db.Where("id = ? AND tenant_id = ?", returnID, tenantID).
		Preload("Sale").
		First(&saleReturn).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("sale return not found")
		}
		return fmt.Errorf("failed to find sale return: %w", err)
	}

	// Only pending returns can be rejected
	if saleReturn.Status != models.StatusPending {
		return errors.New("only pending returns can be rejected")
	}

	// Update return status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusRejected,
		"approved_at":    now,
		"approved_by_id": rejectedByID,
		"notes":          saleReturn.Notes + " | Rejection reason: " + reason,
	}

	if err := s.db.Model(&saleReturn).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to reject return: %w", err)
	}

	// Clear cache
	s.clearReturnsCache(ctx, tenantID, saleReturn.Sale.ShopID)

	return nil
}

// GetPendingReturns returns pending returns requiring approval
func (s *ReturnsService) GetPendingReturns(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]*SaleReturnResponse, error) {
	query := s.db.Model(&models.SaleReturn{}).
		Where("tenant_id = ? AND status = ?", tenantID, models.StatusPending).
		Preload("Sale.Shop").
		Preload("Sale.Salesman").
		Preload("CreatedBy").
		Preload("Items.SaleItem.Product.Brand").
		Preload("Items.SaleItem.Product.Category")

	if shopID != nil {
		query = query.Joins("JOIN sales ON sale_returns.sale_id = sales.id").
			Where("sales.shop_id = ?", *shopID)
	}

	var returns []models.SaleReturn
	if err := query.Order("created_at ASC").Find(&returns).Error; err != nil {
		return nil, fmt.Errorf("failed to get pending returns: %w", err)
	}

	responses := make([]*SaleReturnResponse, len(returns))
	for i, ret := range returns {
		responses[i] = s.mapSaleReturnToResponse(&ret)
	}

	return responses, nil
}

// Helper types and functions

// ReturnsFilters represents filters for returns
type ReturnsFilters struct {
	SaleID    uuid.UUID `form:"sale_id"`
	ShopID    uuid.UUID `form:"shop_id"`
	Status    string    `form:"status"`
	StartDate time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate   time.Time `form:"end_date" time_format:"2006-01-02"`
	Page      int       `form:"page"`
	PageSize  int       `form:"page_size"`
}

// ReturnsListResponse represents paginated returns response
type ReturnsListResponse struct {
	Returns    []*SaleReturnResponse `json:"returns"`
	TotalCount int64                 `json:"total_count"`
	Page       int                   `json:"page"`
	PageSize   int                   `json:"page_size"`
	TotalPages int                   `json:"total_pages"`
}

// mapSaleReturnToResponse converts model to response format
func (s *ReturnsService) mapSaleReturnToResponse(saleReturn *models.SaleReturn) *SaleReturnResponse {
	response := &SaleReturnResponse{
		ID:           saleReturn.ID,
		ReturnNumber: saleReturn.ReturnNumber,
		SaleID:       saleReturn.SaleID,
		ReturnDate:   saleReturn.ReturnDate,
		ReturnAmount: saleReturn.ReturnAmount,
		Reason:       saleReturn.Reason,
		Status:       saleReturn.Status,
		ApprovedAt:   saleReturn.ApprovedAt,
		Notes:        saleReturn.Notes,
		CreatedAt:    saleReturn.CreatedAt,
		UpdatedAt:    saleReturn.UpdatedAt,
		TotalItems:   len(saleReturn.Items),
	}

	// Add sale info
	if saleReturn.Sale != nil {
		response.SaleNumber = saleReturn.Sale.SaleNumber
	}

	// Add created by info
	if saleReturn.CreatedBy != nil {
		response.CreatedByName = saleReturn.CreatedBy.FirstName + " " + saleReturn.CreatedBy.LastName
	}

	// Add approved by info
	if saleReturn.ApprovedBy != nil {
		response.ApprovedByName = saleReturn.ApprovedBy.FirstName + " " + saleReturn.ApprovedBy.LastName
	}

	// Add items
	if len(saleReturn.Items) > 0 {
		response.Items = make([]SaleReturnItemResponse, len(saleReturn.Items))
		for i, item := range saleReturn.Items {
			response.Items[i] = SaleReturnItemResponse{
				ID:          item.ID,
				SaleItemID:  item.SaleItemID,
				Quantity:    item.Quantity,
				UnitPrice:   item.UnitPrice,
				TotalAmount: item.TotalAmount,
				Reason:      item.Reason,
			}

			// Add product info from sale item
			if item.SaleItem != nil && item.SaleItem.Product != nil {
				response.Items[i].ProductID = item.SaleItem.Product.ID
				response.Items[i].ProductName = item.SaleItem.Product.Name
				response.Items[i].Size = item.SaleItem.Product.Size
				
				if item.SaleItem.Product.Brand != nil {
					response.Items[i].BrandName = item.SaleItem.Product.Brand.Name
				}
				
				if item.SaleItem.Product.Category != nil {
					response.Items[i].CategoryName = item.SaleItem.Product.Category.Name
				}
			}
		}
	}

	return response
}

// clearReturnsCache clears related cache entries
func (s *ReturnsService) clearReturnsCache(ctx context.Context, tenantID, shopID uuid.UUID) {
	cacheKeys := []string{
		fmt.Sprintf(cache.PendingApprovalsKey, tenantID.String()),
		fmt.Sprintf("pending_returns:%s", shopID.String()),
		fmt.Sprintf("returns_summary:%s:%s", shopID.String(), time.Now().Format("2006-01-02")),
	}
	
	for _, key := range cacheKeys {
		s.cache.Delete(ctx, key)
	}
}