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

// SalesService handles individual sale transactions
type SalesService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewSalesService creates a new sales service
func NewSalesService(db *database.DB, cache *cache.Cache) *SalesService {
	return &SalesService{
		db:    db,
		cache: cache,
	}
}

// SaleRequest represents sale creation/update request
type SaleRequest struct {
	SaleDate      time.Time        `json:"sale_date" binding:"required"`
	ShopID        uuid.UUID        `json:"shop_id" binding:"required"`
	SalesmanID    *uuid.UUID       `json:"salesman_id"`
	CustomerName  string           `json:"customer_name"`
	CustomerPhone string           `json:"customer_phone"`
	PaymentMethod string           `json:"payment_method" binding:"required"`
	PaymentStatus string           `json:"payment_status"`
	PaidAmount    float64          `json:"paid_amount" binding:"min=0"`
	Notes         string           `json:"notes"`
	Items         []SaleItemRequest `json:"items" binding:"required,min=1"`
}

// SaleItemRequest represents sale item request
type SaleItemRequest struct {
	ProductID      uuid.UUID `json:"product_id" binding:"required"`
	Quantity       int       `json:"quantity" binding:"required,gt=0"`
	UnitPrice      float64   `json:"unit_price" binding:"required,gt=0"`
	DiscountAmount float64   `json:"discount_amount" binding:"min=0"`
	DiscountReason string    `json:"discount_reason"`
}

// SaleResponse represents sale in responses
type SaleResponse struct {
	ID            uuid.UUID         `json:"id"`
	SaleNumber    string            `json:"sale_number"`
	SaleDate      time.Time         `json:"sale_date"`
	ShopID        uuid.UUID         `json:"shop_id"`
	ShopName      string            `json:"shop_name"`
	SalesmanID    *uuid.UUID        `json:"salesman_id"`
	SalesmanName  string            `json:"salesman_name"`
	CustomerName  string            `json:"customer_name"`
	CustomerPhone string            `json:"customer_phone"`
	SubTotal      float64           `json:"sub_total"`
	DiscountAmount float64          `json:"discount_amount"`
	TaxAmount     float64           `json:"tax_amount"`
	TotalAmount   float64           `json:"total_amount"`
	PaidAmount    float64           `json:"paid_amount"`
	DueAmount     float64           `json:"due_amount"`
	PaymentMethod string            `json:"payment_method"`
	PaymentStatus string            `json:"payment_status"`
	Status        string            `json:"status"`
	ApprovedAt    *time.Time        `json:"approved_at"`
	ApprovedByName string           `json:"approved_by_name"`
	CreatedByName string            `json:"created_by_name"`
	Notes         string            `json:"notes"`
	CreatedAt     time.Time         `json:"created_at"`
	UpdatedAt     time.Time         `json:"updated_at"`
	Items         []SaleItemResponse `json:"items"`
	TotalItems    int               `json:"total_items"`
}

// SaleItemResponse represents sale item in responses
type SaleItemResponse struct {
	ID             uuid.UUID `json:"id"`
	ProductID      uuid.UUID `json:"product_id"`
	ProductName    string    `json:"product_name"`
	BrandName      string    `json:"brand_name"`
	CategoryName   string    `json:"category_name"`
	Size           string    `json:"size"`
	Quantity       int       `json:"quantity"`
	UnitPrice      float64   `json:"unit_price"`
	DiscountAmount float64   `json:"discount_amount"`
	DiscountReason string    `json:"discount_reason"`
	TotalPrice     float64   `json:"total_price"`
}

// CreateSale creates a new individual sale
func (s *SalesService) CreateSale(ctx context.Context, req SaleRequest, tenantID, createdByID uuid.UUID) (*SaleResponse, error) {
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

	// Validate payment method
	validPaymentMethods := []string{models.PaymentCash, models.PaymentCard, models.PaymentUPI, models.PaymentCredit}
	if !utils.Contains(validPaymentMethods, req.PaymentMethod) {
		return nil, errors.New("invalid payment method")
	}

	// Start transaction
	var sale *models.Sale
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Calculate totals
		var subTotal, totalDiscount float64
		for _, itemReq := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			itemTotal := float64(itemReq.Quantity) * itemReq.UnitPrice
			subTotal += itemTotal
			totalDiscount += itemReq.DiscountAmount
		}

		totalAmount := subTotal - totalDiscount
		dueAmount := totalAmount - req.PaidAmount

		// Determine payment status
		paymentStatus := req.PaymentStatus
		if paymentStatus == "" {
			if req.PaidAmount >= totalAmount {
				paymentStatus = "paid"
			} else if req.PaidAmount > 0 {
				paymentStatus = "partial"
			} else {
				paymentStatus = "pending"
			}
		}

		// Create sale
		sale = &models.Sale{
			TenantModel:    models.TenantModel{TenantID: tenantID},
			SaleNumber:     utils.GenerateSaleNumber(),
			SaleDate:       req.SaleDate,
			ShopID:         req.ShopID,
			SalesmanID:     req.SalesmanID,
			CustomerName:   req.CustomerName,
			CustomerPhone:  req.CustomerPhone,
			SubTotal:       subTotal,
			DiscountAmount: totalDiscount,
			TotalAmount:    totalAmount,
			PaidAmount:     req.PaidAmount,
			DueAmount:      dueAmount,
			PaymentMethod:  req.PaymentMethod,
			PaymentStatus:  paymentStatus,
			Status:         models.StatusPending,
			CreatedByID:    createdByID,
			Notes:          req.Notes,
		}

		if err := tx.Create(&sale).Error; err != nil {
			return fmt.Errorf("failed to create sale: %w", err)
		}

		// Create sale items
		for _, itemReq := range req.Items {
			totalPrice := (float64(itemReq.Quantity) * itemReq.UnitPrice) - itemReq.DiscountAmount

			item := models.SaleItem{
				TenantModel:    models.TenantModel{TenantID: tenantID},
				SaleID:         sale.ID,
				ProductID:      itemReq.ProductID,
				Quantity:       itemReq.Quantity,
				UnitPrice:      itemReq.UnitPrice,
				DiscountAmount: itemReq.DiscountAmount,
				DiscountReason: itemReq.DiscountReason,
				TotalPrice:     totalPrice,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create sale item: %w", err)
			}
		}

		// Create payment record if amount paid
		if req.PaidAmount > 0 {
			payment := models.SalePayment{
				TenantModel:   models.TenantModel{TenantID: tenantID},
				SaleID:        sale.ID,
				Amount:        req.PaidAmount,
				PaymentMethod: req.PaymentMethod,
				PaymentDate:   req.SaleDate,
				CreatedByID:   createdByID,
			}

			if err := tx.Create(&payment).Error; err != nil {
				return fmt.Errorf("failed to create payment record: %w", err)
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, req.ShopID)

	// Return created sale
	return s.GetSaleByID(ctx, sale.ID, tenantID)
}

// GetSales returns paginated list of sales
func (s *SalesService) GetSales(ctx context.Context, tenantID uuid.UUID, filters SalesFilters) (*SalesListResponse, error) {
	var sales []models.Sale
	var totalCount int64

	query := s.db.Model(&models.Sale{}).
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
	if filters.PaymentStatus != "" {
		query = query.Where("payment_status = ?", filters.PaymentStatus)
	}
	if !filters.StartDate.IsZero() {
		query = query.Where("sale_date >= ?", filters.StartDate)
	}
	if !filters.EndDate.IsZero() {
		query = query.Where("sale_date <= ?", filters.EndDate)
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count sales: %w", err)
	}

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("sale_date DESC, created_at DESC").
		Find(&sales).Error; err != nil {
		return nil, fmt.Errorf("failed to get sales: %w", err)
	}

	// Convert to response format
	responses := make([]*SaleResponse, len(sales))
	for i, sale := range sales {
		responses[i] = s.mapSaleToResponse(&sale)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &SalesListResponse{
		Sales:      responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
	}, nil
}

// GetSaleByID returns sale by ID
func (s *SalesService) GetSaleByID(ctx context.Context, saleID, tenantID uuid.UUID) (*SaleResponse, error) {
	var sale models.Sale
	
	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category").
		Preload("Payments").
		First(&sale).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to get sale: %w", err)
	}

	return s.mapSaleToResponse(&sale), nil
}

// ApproveSale approves a sale
func (s *SalesService) ApproveSale(ctx context.Context, saleID, tenantID, approvedByID uuid.UUID) (*SaleResponse, error) {
	var sale models.Sale
	
	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).First(&sale).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to find sale: %w", err)
	}

	// Only pending sales can be approved
	if sale.Status != models.StatusPending {
		return nil, errors.New("only pending sales can be approved")
	}

	// Update sale status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusApproved,
		"approved_at":    now,
		"approved_by_id": approvedByID,
	}

	if err := s.db.Model(&sale).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to approve sale: %w", err)
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, sale.ShopID)

	// Return updated sale
	return s.GetSaleByID(ctx, saleID, tenantID)
}

// RejectSale rejects a sale
func (s *SalesService) RejectSale(ctx context.Context, saleID, tenantID, rejectedByID uuid.UUID, reason string) error {
	var sale models.Sale
	
	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).First(&sale).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("sale not found")
		}
		return fmt.Errorf("failed to find sale: %w", err)
	}

	// Only pending sales can be rejected
	if sale.Status != models.StatusPending {
		return errors.New("only pending sales can be rejected")
	}

	// Update sale status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusRejected,
		"approved_at":    now,
		"approved_by_id": rejectedByID,
		"notes":          sale.Notes + " | Rejection reason: " + reason,
	}

	if err := s.db.Model(&sale).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to reject sale: %w", err)
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, sale.ShopID)

	return nil
}

// GetPendingSales returns pending sales requiring approval
func (s *SalesService) GetPendingSales(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]*SaleResponse, error) {
	query := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND status = ?", tenantID, models.StatusPending).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var sales []models.Sale
	if err := query.Order("created_at ASC").Find(&sales).Error; err != nil {
		return nil, fmt.Errorf("failed to get pending sales: %w", err)
	}

	responses := make([]*SaleResponse, len(sales))
	for i, sale := range sales {
		responses[i] = s.mapSaleToResponse(&sale)
	}

	return responses, nil
}

// GetUncollectedSales returns sales with due amounts
func (s *SalesService) GetUncollectedSales(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]*SaleResponse, error) {
	query := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND due_amount > 0 AND status = ?", tenantID, models.StatusApproved).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var sales []models.Sale
	if err := query.Order("sale_date ASC").Find(&sales).Error; err != nil {
		return nil, fmt.Errorf("failed to get uncollected sales: %w", err)
	}

	responses := make([]*SaleResponse, len(sales))
	for i, sale := range sales {
		responses[i] = s.mapSaleToResponse(&sale)
	}

	return responses, nil
}

// Helper types and functions

// SalesFilters represents filters for sales
type SalesFilters struct {
	ShopID        uuid.UUID `form:"shop_id"`
	SalesmanID    uuid.UUID `form:"salesman_id"`
	Status        string    `form:"status"`
	PaymentStatus string    `form:"payment_status"`
	StartDate     time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate       time.Time `form:"end_date" time_format:"2006-01-02"`
	Page          int       `form:"page"`
	PageSize      int       `form:"page_size"`
}

// SalesListResponse represents paginated sales response
type SalesListResponse struct {
	Sales      []*SaleResponse `json:"sales"`
	TotalCount int64           `json:"total_count"`
	Page       int             `json:"page"`
	PageSize   int             `json:"page_size"`
	TotalPages int             `json:"total_pages"`
}

// mapSaleToResponse converts model to response format
func (s *SalesService) mapSaleToResponse(sale *models.Sale) *SaleResponse {
	response := &SaleResponse{
		ID:            sale.ID,
		SaleNumber:    sale.SaleNumber,
		SaleDate:      sale.SaleDate,
		ShopID:        sale.ShopID,
		SalesmanID:    sale.SalesmanID,
		CustomerName:  sale.CustomerName,
		CustomerPhone: sale.CustomerPhone,
		SubTotal:      sale.SubTotal,
		DiscountAmount: sale.DiscountAmount,
		TaxAmount:     sale.TaxAmount,
		TotalAmount:   sale.TotalAmount,
		PaidAmount:    sale.PaidAmount,
		DueAmount:     sale.DueAmount,
		PaymentMethod: sale.PaymentMethod,
		PaymentStatus: sale.PaymentStatus,
		Status:        sale.Status,
		ApprovedAt:    sale.ApprovedAt,
		Notes:         sale.Notes,
		CreatedAt:     sale.CreatedAt,
		UpdatedAt:     sale.UpdatedAt,
		TotalItems:    len(sale.Items),
	}

	// Add shop info
	if sale.Shop != nil {
		response.ShopName = sale.Shop.Name
	}

	// Add salesman info
	if sale.Salesman != nil {
		response.SalesmanName = sale.Salesman.Name
	}

	// Add created by info
	if sale.CreatedBy != nil {
		response.CreatedByName = sale.CreatedBy.FirstName + " " + sale.CreatedBy.LastName
	}

	// Add approved by info
	if sale.ApprovedBy != nil {
		response.ApprovedByName = sale.ApprovedBy.FirstName + " " + sale.ApprovedBy.LastName
	}

	// Add items
	if len(sale.Items) > 0 {
		response.Items = make([]SaleItemResponse, len(sale.Items))
		for i, item := range sale.Items {
			response.Items[i] = SaleItemResponse{
				ID:             item.ID,
				ProductID:      item.ProductID,
				Quantity:       item.Quantity,
				UnitPrice:      item.UnitPrice,
				DiscountAmount: item.DiscountAmount,
				DiscountReason: item.DiscountReason,
				TotalPrice:     item.TotalPrice,
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

// clearSalesCache clears related cache entries
func (s *SalesService) clearSalesCache(ctx context.Context, tenantID, shopID uuid.UUID) {
	cacheKeys := []string{
		fmt.Sprintf(cache.PendingApprovalsKey, tenantID.String()),
		fmt.Sprintf("uncollected_sales:%s", shopID.String()),
		fmt.Sprintf("sales_summary:%s:%s", shopID.String(), time.Now().Format("2006-01-02")),
	}
	
	for _, key := range cacheKeys {
		s.cache.Delete(ctx, key)
	}
}