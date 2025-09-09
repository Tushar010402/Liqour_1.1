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

// DailySalesService handles daily sales operations - the critical bulk entry workflow
type DailySalesService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewDailySalesService creates a new daily sales service
func NewDailySalesService(db *database.DB, cache *cache.Cache) *DailySalesService {
	return &DailySalesService{
		db:    db,
		cache: cache,
	}
}

// DailySalesRecordRequest represents daily sales record creation/update request
type DailySalesRecordRequest struct {
	RecordDate       time.Time              `json:"record_date" binding:"required"`
	ShopID           uuid.UUID              `json:"shop_id" binding:"required"`
	SalesmanID       *uuid.UUID             `json:"salesman_id"`
	TotalSalesAmount float64                `json:"total_sales_amount" binding:"required,gt=0"`
	TotalCashAmount  float64                `json:"total_cash_amount"`
	TotalCardAmount  float64                `json:"total_card_amount"`
	TotalUpiAmount   float64                `json:"total_upi_amount"`
	TotalCreditAmount float64               `json:"total_credit_amount"`
	Notes            string                 `json:"notes"`
	Items            []DailySalesItemRequest `json:"items" binding:"required,min=1"`
}

// DailySalesItemRequest represents individual product sales within daily record
type DailySalesItemRequest struct {
	ProductID     uuid.UUID `json:"product_id" binding:"required"`
	Quantity      int       `json:"quantity" binding:"required,gt=0"`
	UnitPrice     float64   `json:"unit_price" binding:"required,gt=0"`
	TotalAmount   float64   `json:"total_amount" binding:"required,gt=0"`
	CashAmount    float64   `json:"cash_amount"`
	CardAmount    float64   `json:"card_amount"`
	UpiAmount     float64   `json:"upi_amount"`
	CreditAmount  float64   `json:"credit_amount"`
}

// DailySalesRecordResponse represents daily sales record in responses
type DailySalesRecordResponse struct {
	ID                uuid.UUID               `json:"id"`
	RecordDate        time.Time               `json:"record_date"`
	ShopID            uuid.UUID               `json:"shop_id"`
	ShopName          string                  `json:"shop_name"`
	SalesmanID        *uuid.UUID              `json:"salesman_id"`
	SalesmanName      string                  `json:"salesman_name"`
	TotalSalesAmount  float64                 `json:"total_sales_amount"`
	TotalCashAmount   float64                 `json:"total_cash_amount"`
	TotalCardAmount   float64                 `json:"total_card_amount"`
	TotalUpiAmount    float64                 `json:"total_upi_amount"`
	TotalCreditAmount float64                 `json:"total_credit_amount"`
	Status            string                  `json:"status"`
	ApprovedAt        *time.Time              `json:"approved_at"`
	ApprovedByName    string                  `json:"approved_by_name"`
	CreatedByName     string                  `json:"created_by_name"`
	Notes             string                  `json:"notes"`
	CreatedAt         time.Time               `json:"created_at"`
	UpdatedAt         time.Time               `json:"updated_at"`
	Items             []DailySalesItemResponse `json:"items"`
	TotalItems        int                     `json:"total_items"`
}

// DailySalesItemResponse represents daily sales item in responses
type DailySalesItemResponse struct {
	ID            uuid.UUID `json:"id"`
	ProductID     uuid.UUID `json:"product_id"`
	ProductName   string    `json:"product_name"`
	BrandName     string    `json:"brand_name"`
	CategoryName  string    `json:"category_name"`
	Size          string    `json:"size"`
	Quantity      int       `json:"quantity"`
	UnitPrice     float64   `json:"unit_price"`
	TotalAmount   float64   `json:"total_amount"`
	CashAmount    float64   `json:"cash_amount"`
	CardAmount    float64   `json:"card_amount"`
	UpiAmount     float64   `json:"upi_amount"`
	CreditAmount  float64   `json:"credit_amount"`
}

// CreateDailySalesRecord creates a new daily sales record with bulk items
func (s *DailySalesService) CreateDailySalesRecord(ctx context.Context, req DailySalesRecordRequest, tenantID, createdByID uuid.UUID) (*DailySalesRecordResponse, error) {
	// Validate payment amounts sum up correctly
	totalPaymentAmount := req.TotalCashAmount + req.TotalCardAmount + req.TotalUpiAmount + req.TotalCreditAmount
	if utils.AbsFloat(totalPaymentAmount-req.TotalSalesAmount) > 0.01 {
		return nil, errors.New("total payment amounts do not match total sales amount")
	}

	// Check if record already exists for this date and shop
	var existingRecord models.DailySalesRecord
	if err := s.db.Where("record_date = ? AND shop_id = ? AND tenant_id = ?", 
		utils.StartOfDay(req.RecordDate), req.ShopID, tenantID).First(&existingRecord).Error; err == nil {
		return nil, errors.New("daily sales record already exists for this date and shop")
	}

	// Verify shop exists and belongs to tenant
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		return nil, errors.New("shop not found or doesn't belong to this tenant")
	}

	// Verify salesman if provided
	if req.SalesmanID != nil {
		var salesman models.Salesman
		if err := s.db.Where("id = ? AND tenant_id = ? AND shop_id = ?", 
			*req.SalesmanID, tenantID, req.ShopID).First(&salesman).Error; err != nil {
			return nil, errors.New("salesman not found or doesn't belong to this shop")
		}
	}

	// Start transaction for atomic creation
	var record *models.DailySalesRecord
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Create daily sales record
		record = &models.DailySalesRecord{
			TenantModel:       models.TenantModel{TenantID: tenantID},
			RecordDate:        utils.StartOfDay(req.RecordDate),
			ShopID:            req.ShopID,
			SalesmanID:        req.SalesmanID,
			TotalSalesAmount:  req.TotalSalesAmount,
			TotalCashAmount:   req.TotalCashAmount,
			TotalCardAmount:   req.TotalCardAmount,
			TotalUpiAmount:    req.TotalUpiAmount,
			TotalCreditAmount: req.TotalCreditAmount,
			Status:            models.StatusPending,
			CreatedByID:       createdByID,
			Notes:             req.Notes,
		}

		if err := tx.Create(&record).Error; err != nil {
			return fmt.Errorf("failed to create daily sales record: %w", err)
		}

		// Create daily sales items
		totalItemsAmount := 0.0
		for _, itemReq := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			// Validate item payment amounts
			itemPaymentTotal := itemReq.CashAmount + itemReq.CardAmount + itemReq.UpiAmount + itemReq.CreditAmount
			if utils.AbsFloat(itemPaymentTotal-itemReq.TotalAmount) > 0.01 {
				return fmt.Errorf("payment amounts for product %s do not match total amount", product.Name)
			}

			// Create item
			item := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: tenantID},
				DailySalesRecordID: record.ID,
				ProductID:          itemReq.ProductID,
				Quantity:           itemReq.Quantity,
				UnitPrice:          itemReq.UnitPrice,
				TotalAmount:        itemReq.TotalAmount,
				CashAmount:         itemReq.CashAmount,
				CardAmount:         itemReq.CardAmount,
				UpiAmount:          itemReq.UpiAmount,
				CreditAmount:       itemReq.CreditAmount,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create daily sales item: %w", err)
			}

			totalItemsAmount += itemReq.TotalAmount
		}

		// Verify total items amount matches record total
		if utils.AbsFloat(totalItemsAmount-req.TotalSalesAmount) > 0.01 {
			return errors.New("total items amount does not match record total sales amount")
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache for pending sales
	s.clearDailySalesCache(ctx, tenantID, req.ShopID)

	// Load and return complete record
	return s.GetDailySalesRecordByID(ctx, record.ID, tenantID)
}

// GetDailySalesRecords returns paginated list of daily sales records
func (s *DailySalesService) GetDailySalesRecords(ctx context.Context, tenantID uuid.UUID, filters DailySalesFilters) (*DailySalesListResponse, error) {
	var records []models.DailySalesRecord
	var totalCount int64

	query := s.db.Model(&models.DailySalesRecord{}).
		Where("tenant_id = ?", tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	// Apply filters
	if filters.ShopID != uuid.Nil {
		query = query.Where("shop_id = ?", filters.ShopID)
	}
	if filters.SalesmanID != uuid.Nil {
		query = query.Where("salesman_id = ?", filters.SalesmanID)
	}
	if filters.Status != "" {
		query = query.Where("status = ?", filters.Status)
	}
	if !filters.StartDate.IsZero() {
		query = query.Where("record_date >= ?", filters.StartDate)
	}
	if !filters.EndDate.IsZero() {
		query = query.Where("record_date <= ?", filters.EndDate)
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count daily sales records: %w", err)
	}

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("record_date DESC, created_at DESC").
		Find(&records).Error; err != nil {
		return nil, fmt.Errorf("failed to get daily sales records: %w", err)
	}

	// Convert to response format
	responses := make([]*DailySalesRecordResponse, len(records))
	for i, record := range records {
		responses[i] = s.mapDailySalesRecordToResponse(&record)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &DailySalesListResponse{
		Records:    responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
	}, nil
}

// GetDailySalesRecordByID returns daily sales record by ID
func (s *DailySalesService) GetDailySalesRecordByID(ctx context.Context, recordID, tenantID uuid.UUID) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord
	
	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category").
		First(&record).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to get daily sales record: %w", err)
	}

	return s.mapDailySalesRecordToResponse(&record), nil
}

// UpdateDailySalesRecord updates existing daily sales record
func (s *DailySalesService) UpdateDailySalesRecord(ctx context.Context, recordID, tenantID uuid.UUID, req DailySalesRecordRequest) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord
	
	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only pending records can be updated
	if record.Status != models.StatusPending {
		return nil, errors.New("only pending records can be updated")
	}

	// Validate payment amounts
	totalPaymentAmount := req.TotalCashAmount + req.TotalCardAmount + req.TotalUpiAmount + req.TotalCreditAmount
	if utils.AbsFloat(totalPaymentAmount-req.TotalSalesAmount) > 0.01 {
		return nil, errors.New("total payment amounts do not match total sales amount")
	}

	// Start transaction for atomic update
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Delete existing items
		if err := tx.Where("daily_sales_record_id = ?", recordID).Delete(&models.DailySalesItem{}).Error; err != nil {
			return fmt.Errorf("failed to delete existing items: %w", err)
		}

		// Update record
		updates := map[string]interface{}{
			"total_sales_amount":  req.TotalSalesAmount,
			"total_cash_amount":   req.TotalCashAmount,
			"total_card_amount":   req.TotalCardAmount,
			"total_upi_amount":    req.TotalUpiAmount,
			"total_credit_amount": req.TotalCreditAmount,
			"notes":               req.Notes,
		}

		if err := tx.Model(&record).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to update daily sales record: %w", err)
		}

		// Create new items
		totalItemsAmount := 0.0
		for _, itemReq := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			// Validate item payment amounts
			itemPaymentTotal := itemReq.CashAmount + itemReq.CardAmount + itemReq.UpiAmount + itemReq.CreditAmount
			if utils.AbsFloat(itemPaymentTotal-itemReq.TotalAmount) > 0.01 {
				return fmt.Errorf("payment amounts for product %s do not match total amount", product.Name)
			}

			// Create new item
			item := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: tenantID},
				DailySalesRecordID: recordID,
				ProductID:          itemReq.ProductID,
				Quantity:           itemReq.Quantity,
				UnitPrice:          itemReq.UnitPrice,
				TotalAmount:        itemReq.TotalAmount,
				CashAmount:         itemReq.CashAmount,
				CardAmount:         itemReq.CardAmount,
				UpiAmount:          itemReq.UpiAmount,
				CreditAmount:       itemReq.CreditAmount,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create daily sales item: %w", err)
			}

			totalItemsAmount += itemReq.TotalAmount
		}

		// Verify total items amount matches record total
		if utils.AbsFloat(totalItemsAmount-req.TotalSalesAmount) > 0.01 {
			return errors.New("total items amount does not match record total sales amount")
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// ApproveDailySalesRecord approves a daily sales record
func (s *DailySalesService) ApproveDailySalesRecord(ctx context.Context, recordID, tenantID, approvedByID uuid.UUID) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord
	
	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only pending records can be approved
	if record.Status != models.StatusPending {
		return nil, errors.New("only pending records can be approved")
	}

	// Update record status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusApproved,
		"approved_at":    now,
		"approved_by_id": approvedByID,
	}

	if err := s.db.Model(&record).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to approve daily sales record: %w", err)
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// RejectDailySalesRecord rejects a daily sales record
func (s *DailySalesService) RejectDailySalesRecord(ctx context.Context, recordID, tenantID, rejectedByID uuid.UUID, reason string) error {
	var record models.DailySalesRecord
	
	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("daily sales record not found")
		}
		return fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only pending records can be rejected
	if record.Status != models.StatusPending {
		return errors.New("only pending records can be rejected")
	}

	// Update record status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusRejected,
		"approved_at":    now,
		"approved_by_id": rejectedByID,
		"notes":          record.Notes + " | Rejection reason: " + reason,
	}

	if err := s.db.Model(&record).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to reject daily sales record: %w", err)
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	return nil
}

// Helper functions

// DailySalesFilters represents filters for daily sales records
type DailySalesFilters struct {
	ShopID     uuid.UUID `form:"shop_id"`
	SalesmanID uuid.UUID `form:"salesman_id"`
	Status     string    `form:"status"`
	StartDate  time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate    time.Time `form:"end_date" time_format:"2006-01-02"`
	Page       int       `form:"page"`
	PageSize   int       `form:"page_size"`
}

// DailySalesListResponse represents paginated daily sales response
type DailySalesListResponse struct {
	Records    []*DailySalesRecordResponse `json:"records"`
	TotalCount int64                       `json:"total_count"`
	Page       int                         `json:"page"`
	PageSize   int                         `json:"page_size"`
	TotalPages int                         `json:"total_pages"`
}

// mapDailySalesRecordToResponse converts model to response format
func (s *DailySalesService) mapDailySalesRecordToResponse(record *models.DailySalesRecord) *DailySalesRecordResponse {
	response := &DailySalesRecordResponse{
		ID:                record.ID,
		RecordDate:        record.RecordDate,
		ShopID:            record.ShopID,
		SalesmanID:        record.SalesmanID,
		TotalSalesAmount:  record.TotalSalesAmount,
		TotalCashAmount:   record.TotalCashAmount,
		TotalCardAmount:   record.TotalCardAmount,
		TotalUpiAmount:    record.TotalUpiAmount,
		TotalCreditAmount: record.TotalCreditAmount,
		Status:            record.Status,
		ApprovedAt:        record.ApprovedAt,
		Notes:             record.Notes,
		CreatedAt:         record.CreatedAt,
		UpdatedAt:         record.UpdatedAt,
		TotalItems:        len(record.Items),
	}

	// Add shop info
	if record.Shop != nil {
		response.ShopName = record.Shop.Name
	}

	// Add salesman info
	if record.Salesman != nil {
		response.SalesmanName = record.Salesman.Name
	}

	// Add created by info
	if record.CreatedBy != nil {
		response.CreatedByName = record.CreatedBy.FirstName + " " + record.CreatedBy.LastName
	}

	// Add approved by info
	if record.ApprovedBy != nil {
		response.ApprovedByName = record.ApprovedBy.FirstName + " " + record.ApprovedBy.LastName
	}

	// Add items
	if len(record.Items) > 0 {
		response.Items = make([]DailySalesItemResponse, len(record.Items))
		for i, item := range record.Items {
			response.Items[i] = DailySalesItemResponse{
				ID:           item.ID,
				ProductID:    item.ProductID,
				Quantity:     item.Quantity,
				UnitPrice:    item.UnitPrice,
				TotalAmount:  item.TotalAmount,
				CashAmount:   item.CashAmount,
				CardAmount:   item.CardAmount,
				UpiAmount:    item.UpiAmount,
				CreditAmount: item.CreditAmount,
			}

			// Add product info
			if item.Product != nil {
				response.Items[i].ProductName = item.Product.Name
				response.Items[i].Size = item.Product.Size
				
				if item.Product.Brand != nil {
					response.Items[i].BrandName = item.Product.Brand.Name
				}
				
				if item.Product.Category != nil {
					response.Items[i].CategoryName = item.Product.Category.Name
				}
			}
		}
	}

	return response
}

// clearDailySalesCache clears related cache entries
func (s *DailySalesService) clearDailySalesCache(ctx context.Context, tenantID, shopID uuid.UUID) {
	// Clear various cache patterns
	cacheKeys := []string{
		fmt.Sprintf(cache.DailySalesKey, shopID.String(), time.Now().Format("2006-01-02")),
		fmt.Sprintf(cache.PendingApprovalsKey, tenantID.String()),
	}
	
	for _, key := range cacheKeys {
		s.cache.Delete(ctx, key)
	}
}