package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

type PurchaseService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewPurchaseService(db *database.DB, cache *cache.Cache) *PurchaseService {
	return &PurchaseService{
		db:    db,
		cache: cache,
	}
}

type PurchaseRequest struct {
	VendorID    uuid.UUID                 `json:"vendor_id" binding:"required"`
	ShopID      uuid.UUID                 `json:"shop_id" binding:"required"`
	ReceiptNo   string                    `json:"receipt_no"`
	Items       []PurchaseItemRequest     `json:"items" binding:"required,min=1"`
	TotalAmount float64                   `json:"total_amount"`
	Notes       string                    `json:"notes"`
	Payments    []PurchasePaymentRequest  `json:"payments"`
}

type PurchaseItemRequest struct {
	ProductID    uuid.UUID `json:"product_id" binding:"required"`
	Quantity     float64   `json:"quantity" binding:"required,gt=0"`
	UnitPrice    float64   `json:"unit_price" binding:"required,gt=0"`
	TotalPrice   float64   `json:"total_price"`
	ExpiryDate   *time.Time `json:"expiry_date"`
	BatchNumber  string    `json:"batch_number"`
}

type PurchasePaymentRequest struct {
	Method string  `json:"method" binding:"required"`
	Amount float64 `json:"amount" binding:"required,gt=0"`
}

type PurchaseResponse struct {
	ID          uuid.UUID                  `json:"id"`
	PurchaseNo  string                     `json:"purchase_no"`
	VendorID    uuid.UUID                  `json:"vendor_id"`
	VendorName  string                     `json:"vendor_name"`
	ShopID      uuid.UUID                  `json:"shop_id"`
	ShopName    string                     `json:"shop_name"`
	ReceiptNo   string                     `json:"receipt_no"`
	Status      string                     `json:"status"`
	TotalAmount float64                    `json:"total_amount"`
	Items       []PurchaseItemResponse     `json:"items"`
	Payments    []PurchasePaymentResponse  `json:"payments"`
	Notes       string                     `json:"notes"`
	CreatedBy   uuid.UUID                  `json:"created_by"`
	CreatedAt   time.Time                  `json:"created_at"`
	UpdatedAt   time.Time                  `json:"updated_at"`
}

type PurchaseItemResponse struct {
	ID           uuid.UUID  `json:"id"`
	ProductID    uuid.UUID  `json:"product_id"`
	ProductName  string     `json:"product_name"`
	BrandName    string     `json:"brand_name"`
	Quantity     float64    `json:"quantity"`
	UnitPrice    float64    `json:"unit_price"`
	TotalPrice   float64    `json:"total_price"`
	ExpiryDate   *time.Time `json:"expiry_date"`
	BatchNumber  string     `json:"batch_number"`
	CreatedAt    time.Time  `json:"created_at"`
}

type PurchasePaymentResponse struct {
	ID        uuid.UUID `json:"id"`
	Method    string    `json:"method"`
	Amount    float64   `json:"amount"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *PurchaseService) CreatePurchase(ctx context.Context, req PurchaseRequest, tenantID, userID uuid.UUID) (*PurchaseResponse, error) {
	var purchase models.StockPurchase
	var totalCalculated float64

	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	if err := tx.Error; err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Generate purchase number
	purchaseNo, err := s.generatePurchaseNumber(ctx, tenantID)
	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to generate purchase number: %w", err)
	}

	// Validate vendor exists
	var vendor models.Vendor
	if err := tx.Where("id = ? AND tenant_id = ?", req.VendorID, tenantID).First(&vendor).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("vendor not found: %w", err)
	}

	// Validate shop exists
	var shop models.Shop
	if err := tx.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("shop not found: %w", err)
	}

	// Create purchase record
	purchase = models.StockPurchase{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  tenantID,
		},
		PurchaseNumber: purchaseNo,
		VendorID:       req.VendorID,
		PurchaseDate:   time.Now(),
		Status:         "pending",
		Notes:          req.Notes,
	}

	if err := tx.Create(&purchase).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create purchase: %w", err)
	}

	// Create purchase items
	var purchaseItems []models.StockPurchaseItem
	for _, itemReq := range req.Items {
		// Validate product exists
		var product models.Product
		if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("product not found: %w", err)
		}

		itemTotal := itemReq.Quantity * itemReq.UnitPrice
		if itemReq.TotalPrice > 0 {
			itemTotal = itemReq.TotalPrice
		}
		totalCalculated += itemTotal

		purchaseItem := models.StockPurchaseItem{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  tenantID,
			},
			StockPurchaseID: purchase.ID,
			ProductID:       itemReq.ProductID,
			Quantity:        int(itemReq.Quantity),
			UnitCost:        itemReq.UnitPrice,
			TotalCost:       itemTotal,
			ExpiryDate:      itemReq.ExpiryDate,
			BatchNumber:     itemReq.BatchNumber,
		}

		if err := tx.Create(&purchaseItem).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create purchase item: %w", err)
		}

		purchaseItems = append(purchaseItems, purchaseItem)
	}

	// Update purchase total amount
	finalTotal := totalCalculated
	if req.TotalAmount > 0 {
		finalTotal = req.TotalAmount
	}

	if err := tx.Model(&purchase).Update("total_amount", finalTotal).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update purchase total: %w", err)
	}

	// Create purchase payments
	var purchasePayments []models.StockPurchasePayment
	for _, paymentReq := range req.Payments {
		payment := models.StockPurchasePayment{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  tenantID,
			},
			StockPurchaseID: purchase.ID,
			PaymentMethod:   paymentReq.Method,
			Amount:          paymentReq.Amount,
			PaymentDate:     time.Now(),
		}

		if err := tx.Create(&payment).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create purchase payment: %w", err)
		}

		purchasePayments = append(purchasePayments, payment)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Build response
	response := s.buildPurchaseResponse(purchase, vendor, shop, purchaseItems, purchasePayments)

	// Clear relevant cache
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return response, nil
}

func (s *PurchaseService) GetPurchases(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, status string, limit, offset int) ([]PurchaseResponse, int64, error) {
	var purchases []models.StockPurchase
	var total int64

	query := s.db.Where("tenant_id = ?", tenantID)
	
	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}
	
	if status != "" {
		query = query.Where("status = ?", status)
	}

	// Get total count
	if err := query.Model(&models.StockPurchase{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count purchases: %w", err)
	}

	// Get purchases with pagination
	if err := query.
		Preload("Vendor").
		Preload("Shop").
		Preload("Items").
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		Preload("Payments").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&purchases).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get purchases: %w", err)
	}

	var responses []PurchaseResponse
	for _, purchase := range purchases {
		response := s.buildPurchaseResponseFromModel(purchase)
		responses = append(responses, *response)
	}

	return responses, total, nil
}

func (s *PurchaseService) GetPurchaseByID(ctx context.Context, id, tenantID uuid.UUID) (*PurchaseResponse, error) {
	var purchase models.StockPurchase

	if err := s.db.
		Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Vendor").
		Preload("Shop").
		Preload("Items").
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		Preload("Payments").
		First(&purchase).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("purchase not found")
		}
		return nil, fmt.Errorf("failed to get purchase: %w", err)
	}

	return s.buildPurchaseResponseFromModel(purchase), nil
}

func (s *PurchaseService) ReceivePurchase(ctx context.Context, id, tenantID, userID uuid.UUID) error {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	if err := tx.Error; err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Get purchase with items
	var purchase models.StockPurchase
	if err := tx.Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Items").
		First(&purchase).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("purchase not found: %w", err)
	}

	if purchase.Status != "pending" {
		tx.Rollback()
		return fmt.Errorf("purchase is not in pending status")
	}

	// Create or update stock for each item
	for _, item := range purchase.Items {
		// Check if stock exists for this product in this shop
		var stock models.Stock
		err := tx.Where("product_id = ? AND shop_id = ? AND tenant_id = ?", 
			item.ProductID, purchase.VendorID, tenantID).First(&stock).Error

		if err == gorm.ErrRecordNotFound {
			// Create new stock record
			stock = models.Stock{
				TenantModel: models.TenantModel{
					BaseModel: models.BaseModel{ID: uuid.New()},
					TenantID:  tenantID,
				},
				ProductID:      item.ProductID,
				ShopID:         purchase.VendorID,
				Quantity:       item.Quantity,
				MinimumLevel:   0,
				MaximumLevel:   0,
				AverageCost:    item.UnitCost,
				LastPurchaseDate: &time.Time{},
			}
			*stock.LastPurchaseDate = time.Now()

			if err := tx.Create(&stock).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create stock: %w", err)
			}
		} else if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to check stock: %w", err)
		} else {
			// Update existing stock
			newStock := stock.Quantity + item.Quantity
			now := time.Now()
			
			updates := map[string]interface{}{
				"quantity": newStock,
				"average_cost": item.UnitCost,
				"last_purchase_date": &now,
			}

			if err := tx.Model(&stock).Updates(updates).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to update stock: %w", err)
			}
		}

		// Create stock movement record
		purchaseID := purchase.ID
		movement := models.StockMovement{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  tenantID,
			},
			StockID:      stock.ID,
			MovementType: "purchase",
			Quantity:     item.Quantity,
			Reference:    "purchase",
			ReferenceID:  &purchaseID,
			Notes:        fmt.Sprintf("Stock received from purchase %s", purchase.PurchaseNumber),
		}

		if err := tx.Create(&movement).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create stock movement: %w", err)
		}
	}

	// Update purchase status
	if err := tx.Model(&purchase).Updates(map[string]interface{}{
		"status": "received",
		"received_at": time.Now(),
		"received_by": userID,
	}).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update purchase status: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)
	
	stockCacheKey := fmt.Sprintf("stocks:shop:%s:tenant:%s", purchase.VendorID.String(), tenantID.String())
	s.cache.Delete(ctx, stockCacheKey)

	return nil
}

func (s *PurchaseService) generatePurchaseNumber(ctx context.Context, tenantID uuid.UUID) (string, error) {
	year := time.Now().Year()
	
	var count int64
	if err := s.db.
		Model(&models.StockPurchase{}).
		Where("tenant_id = ? AND EXTRACT(YEAR FROM created_at) = ?", tenantID, year).
		Count(&count).Error; err != nil {
		return "", fmt.Errorf("failed to count purchases: %w", err)
	}

	return fmt.Sprintf("PUR-%d-%05d", year, count+1), nil
}

func (s *PurchaseService) buildPurchaseResponse(
	purchase models.StockPurchase,
	vendor models.Vendor,
	shop models.Shop,
	items []models.StockPurchaseItem,
	payments []models.StockPurchasePayment,
) *PurchaseResponse {
	response := &PurchaseResponse{
		ID:          purchase.ID,
		PurchaseNo:  purchase.PurchaseNumber,
		VendorID:    purchase.VendorID,
		VendorName:  vendor.Name,
		ShopID:      purchase.VendorID,
		ShopName:    shop.Name,
		ReceiptNo:   purchase.ReceiptNo,
		Status:      purchase.Status,
		TotalAmount: purchase.TotalAmount,
		Notes:       purchase.Notes,
		CreatedBy:   purchase.CreatedBy,
		CreatedAt:   purchase.CreatedAt,
		UpdatedAt:   purchase.UpdatedAt,
	}

	for _, item := range items {
		itemResponse := PurchaseItemResponse{
			ID:          item.ID,
			ProductID:   item.ProductID,
			Quantity:    float64(item.Quantity),
			UnitPrice:   item.UnitCost,
			TotalPrice:  item.TotalPrice,
			ExpiryDate:  item.ExpiryDate,
			BatchNumber: item.BatchNumber,
			CreatedAt:   item.CreatedAt,
		}
		response.Items = append(response.Items, itemResponse)
	}

	for _, payment := range payments {
		paymentResponse := PurchasePaymentResponse{
			ID:        payment.ID,
			Method:    payment.Method,
			Amount:    payment.Amount,
			CreatedAt: payment.CreatedAt,
		}
		response.Payments = append(response.Payments, paymentResponse)
	}

	return response
}

func (s *PurchaseService) buildPurchaseResponseFromModel(purchase models.StockPurchase) *PurchaseResponse {
	response := &PurchaseResponse{
		ID:          purchase.ID,
		PurchaseNo:  purchase.PurchaseNumber,
		VendorID:    purchase.VendorID,
		ShopID:      purchase.VendorID,
		ReceiptNo:   purchase.ReceiptNo,
		Status:      purchase.Status,
		TotalAmount: purchase.TotalAmount,
		Notes:       purchase.Notes,
		CreatedBy:   purchase.CreatedBy,
		CreatedAt:   purchase.CreatedAt,
		UpdatedAt:   purchase.UpdatedAt,
	}

	if purchase.Vendor != nil {
		response.VendorName = purchase.Vendor.Name
	}

	if purchase.Shop != nil {
		response.ShopName = purchase.Shop.Name
	}

	for _, item := range purchase.Items {
		itemResponse := PurchaseItemResponse{
			ID:          item.ID,
			ProductID:   item.ProductID,
			Quantity:    float64(item.Quantity),
			UnitPrice:   item.UnitCost,
			TotalPrice:  item.TotalPrice,
			ExpiryDate:  item.ExpiryDate,
			BatchNumber: item.BatchNumber,
			CreatedAt:   item.CreatedAt,
		}

		if item.Product != nil {
			itemResponse.ProductName = item.Product.Name
			if item.Product.Brand != nil {
				itemResponse.BrandName = item.Product.Brand.Name
			}
		}

		response.Items = append(response.Items, itemResponse)
	}

	for _, payment := range purchase.Payments {
		paymentResponse := PurchasePaymentResponse{
			ID:        payment.ID,
			Method:    payment.Method,
			Amount:    payment.Amount,
			CreatedAt: payment.CreatedAt,
		}
		response.Payments = append(response.Payments, paymentResponse)
	}

	return response
}