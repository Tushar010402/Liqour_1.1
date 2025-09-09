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
	"gorm.io/gorm"
)

// StockService handles stock management operations
type StockService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewStockService creates a new stock service
func NewStockService(db *database.DB, cache *cache.Cache) *StockService {
	return &StockService{
		db:    db,
		cache: cache,
	}
}

// StockAdjustmentRequest represents stock adjustment request
type StockAdjustmentRequest struct {
	ShopID       uuid.UUID `json:"shop_id" binding:"required"`
	ProductID    uuid.UUID `json:"product_id" binding:"required"`
	Quantity     int       `json:"quantity" binding:"required"`
	AdjustmentType string  `json:"adjustment_type" binding:"required"` // add, remove, set
	Reason       string    `json:"reason" binding:"required"`
	Notes        string    `json:"notes"`
}

// StockTransferRequest represents stock transfer between shops
type StockTransferRequest struct {
	FromShopID   uuid.UUID                `json:"from_shop_id" binding:"required"`
	ToShopID     uuid.UUID                `json:"to_shop_id" binding:"required"`
	TransferDate time.Time                `json:"transfer_date" binding:"required"`
	Notes        string                   `json:"notes"`
	Items        []StockTransferItemRequest `json:"items" binding:"required,min=1"`
}

// StockTransferItemRequest represents transfer item
type StockTransferItemRequest struct {
	ProductID uuid.UUID `json:"product_id" binding:"required"`
	Quantity  int       `json:"quantity" binding:"required,gt=0"`
}

// StockResponse represents stock in responses
type StockResponse struct {
	ID                uuid.UUID  `json:"id"`
	ShopID            uuid.UUID  `json:"shop_id"`
	ShopName          string     `json:"shop_name"`
	ProductID         uuid.UUID  `json:"product_id"`
	ProductName       string     `json:"product_name"`
	BrandName         string     `json:"brand_name"`
	CategoryName      string     `json:"category_name"`
	Size              string     `json:"size"`
	SKU               string     `json:"sku"`
	Quantity          int        `json:"quantity"`
	ReservedQuantity  int        `json:"reserved_quantity"`
	AvailableQuantity int        `json:"available_quantity"`
	MinimumLevel      int        `json:"minimum_level"`
	MaximumLevel      int        `json:"maximum_level"`
	CostingMethod     string     `json:"costing_method"`
	AverageCost       float64    `json:"average_cost"`
	LastPurchasePrice float64    `json:"last_purchase_price"`
	LastPurchaseDate  *time.Time `json:"last_purchase_date"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// StockHistoryResponse represents stock movement history
type StockHistoryResponse struct {
	ID               uuid.UUID `json:"id"`
	StockID          uuid.UUID `json:"stock_id"`
	ProductName      string    `json:"product_name"`
	ShopName         string    `json:"shop_name"`
	MovementType     string    `json:"movement_type"`
	Quantity         int       `json:"quantity"`
	PreviousQuantity int       `json:"previous_quantity"`
	NewQuantity      int       `json:"new_quantity"`
	UnitCost         float64   `json:"unit_cost"`
	TotalCost        float64   `json:"total_cost"`
	Reference        string    `json:"reference"`
	Notes            string    `json:"notes"`
	CreatedByName    string    `json:"created_by_name"`
	CreatedAt        time.Time `json:"created_at"`
}

// GetStockByShop returns stock levels for a shop
func (s *StockService) GetStockByShop(ctx context.Context, shopID, tenantID uuid.UUID, filters StockFilters) ([]*StockResponse, error) {
	// Verify shop exists and belongs to tenant
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", shopID, tenantID).First(&shop).Error; err != nil {
		return nil, errors.New("shop not found")
	}

	query := s.db.Model(&models.Stock{}).
		Where("shop_id = ? AND tenant_id = ?", shopID, tenantID).
		Preload("Shop").
		Preload("Product.Brand").
		Preload("Product.Category")

	// Apply filters
	if filters.ProductID != uuid.Nil {
		query = query.Where("product_id = ?", filters.ProductID)
	}
	if filters.CategoryID != uuid.Nil {
		query = query.Joins("JOIN products ON stocks.product_id = products.id").
			Where("products.category_id = ?", filters.CategoryID)
	}
	if filters.BrandID != uuid.Nil {
		query = query.Joins("JOIN products ON stocks.product_id = products.id").
			Where("products.brand_id = ?", filters.BrandID)
	}
	if filters.LowStock {
		query = query.Where("quantity <= minimum_level")
	}

	var stocks []models.Stock
	if err := query.Find(&stocks).Error; err != nil {
		return nil, fmt.Errorf("failed to get stock: %w", err)
	}

	// Convert to response format
	responses := make([]*StockResponse, len(stocks))
	for i, stock := range stocks {
		responses[i] = s.mapStockToResponse(&stock)
	}

	return responses, nil
}

// GetStockByProduct returns stock levels across all shops for a product
func (s *StockService) GetStockByProduct(ctx context.Context, productID, tenantID uuid.UUID) ([]*StockResponse, error) {
	// Verify product exists and belongs to tenant
	var product models.Product
	if err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error; err != nil {
		return nil, errors.New("product not found")
	}

	var stocks []models.Stock
	err := s.db.Where("product_id = ? AND tenant_id = ?", productID, tenantID).
		Preload("Shop").
		Preload("Product.Brand").
		Preload("Product.Category").
		Find(&stocks).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get stock: %w", err)
	}

	// Convert to response format
	responses := make([]*StockResponse, len(stocks))
	for i, stock := range stocks {
		responses[i] = s.mapStockToResponse(&stock)
	}

	return responses, nil
}

// AdjustStock adjusts stock levels
func (s *StockService) AdjustStock(ctx context.Context, req StockAdjustmentRequest, tenantID, userID uuid.UUID) (*StockResponse, error) {
	// Verify shop and product exist
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		return nil, errors.New("shop not found")
	}

	var product models.Product
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ProductID, tenantID).First(&product).Error; err != nil {
		return nil, errors.New("product not found")
	}

	// Validate adjustment type
	validTypes := []string{"add", "remove", "set"}
	isValid := false
	for _, t := range validTypes {
		if req.AdjustmentType == t {
			isValid = true
			break
		}
	}
	if !isValid {
		return nil, errors.New("invalid adjustment type")
	}

	var stock models.Stock
	var newQuantity int

	// Start transaction
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Get or create stock record
		err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", 
			req.ShopID, req.ProductID, tenantID).First(&stock).Error
		
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				// Create new stock record
				stock = models.Stock{
					TenantModel:   models.TenantModel{TenantID: tenantID},
					ShopID:        req.ShopID,
					ProductID:     req.ProductID,
					Quantity:      0,
					CostingMethod: models.CostingFIFO,
				}
				if err := tx.Create(&stock).Error; err != nil {
					return fmt.Errorf("failed to create stock record: %w", err)
				}
			} else {
				return fmt.Errorf("failed to get stock: %w", err)
			}
		}

		previousQuantity := stock.Quantity

		// Calculate new quantity
		switch req.AdjustmentType {
		case "add":
			newQuantity = stock.Quantity + req.Quantity
		case "remove":
			newQuantity = stock.Quantity - req.Quantity
			if newQuantity < 0 {
				return errors.New("insufficient stock")
			}
		case "set":
			newQuantity = req.Quantity
			if newQuantity < 0 {
				return errors.New("quantity cannot be negative")
			}
		}

		// Update stock
		stock.Quantity = newQuantity
		if err := tx.Save(&stock).Error; err != nil {
			return fmt.Errorf("failed to update stock: %w", err)
		}

		// Create stock history
		history := models.StockHistory{
			TenantModel:      models.TenantModel{TenantID: tenantID},
			StockID:          stock.ID,
			MovementType:     "adjustment",
			Quantity:         req.Quantity,
			PreviousQuantity: previousQuantity,
			NewQuantity:      newQuantity,
			Reference:        req.Reason,
			Notes:            req.Notes,
			CreatedByID:      userID,
		}

		if err := tx.Create(&history).Error; err != nil {
			return fmt.Errorf("failed to create stock history: %w", err)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearStockCache(ctx, tenantID, req.ShopID, req.ProductID)

	// Load related data and return
	s.db.Preload("Shop").Preload("Product.Brand").Preload("Product.Category").First(&stock, stock.ID)
	return s.mapStockToResponse(&stock), nil
}

// CreateStockTransfer creates a transfer between shops
func (s *StockService) CreateStockTransfer(ctx context.Context, req StockTransferRequest, tenantID, userID uuid.UUID) error {
	// Verify shops exist and belong to tenant
	var fromShop, toShop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.FromShopID, tenantID).First(&fromShop).Error; err != nil {
		return errors.New("source shop not found")
	}
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ToShopID, tenantID).First(&toShop).Error; err != nil {
		return errors.New("destination shop not found")
	}

	if req.FromShopID == req.ToShopID {
		return errors.New("cannot transfer to the same shop")
	}

	// Start transaction
	return s.db.Transaction(func(tx *gorm.DB) error {
		transferRef := fmt.Sprintf("TRANSFER-%s-%d", time.Now().Format("20060102"), time.Now().Unix()%10000)

		for _, item := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", item.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", item.ProductID)
			}

			// Get source stock
			var fromStock models.Stock
			err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", 
				req.FromShopID, item.ProductID, tenantID).First(&fromStock).Error
			
			if err != nil {
				return fmt.Errorf("stock not found for product %s in source shop", product.Name)
			}

			// Check available quantity
			availableQty := fromStock.Quantity - fromStock.ReservedQuantity
			if availableQty < item.Quantity {
				return fmt.Errorf("insufficient stock for product %s (available: %d, requested: %d)", 
					product.Name, availableQty, item.Quantity)
			}

			// Update source stock
			fromStock.Quantity -= item.Quantity
			if err := tx.Save(&fromStock).Error; err != nil {
				return fmt.Errorf("failed to update source stock: %w", err)
			}

			// Create source history
			fromHistory := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: tenantID},
				StockID:          fromStock.ID,
				MovementType:     "transfer_out",
				Quantity:         -item.Quantity,
				PreviousQuantity: fromStock.Quantity + item.Quantity,
				NewQuantity:      fromStock.Quantity,
				Reference:        transferRef,
				Notes:            fmt.Sprintf("Transfer to %s", toShop.Name),
				CreatedByID:      userID,
			}
			if err := tx.Create(&fromHistory).Error; err != nil {
				return fmt.Errorf("failed to create source history: %w", err)
			}

			// Get or create destination stock
			var toStock models.Stock
			err = tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", 
				req.ToShopID, item.ProductID, tenantID).First(&toStock).Error
			
			if err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					// Create new stock record
					toStock = models.Stock{
						TenantModel:   models.TenantModel{TenantID: tenantID},
						ShopID:        req.ToShopID,
						ProductID:     item.ProductID,
						Quantity:      0,
						CostingMethod: fromStock.CostingMethod,
						AverageCost:   fromStock.AverageCost,
					}
					if err := tx.Create(&toStock).Error; err != nil {
						return fmt.Errorf("failed to create destination stock: %w", err)
					}
				} else {
					return fmt.Errorf("failed to get destination stock: %w", err)
				}
			}

			// Update destination stock
			previousToQty := toStock.Quantity
			toStock.Quantity += item.Quantity
			if err := tx.Save(&toStock).Error; err != nil {
				return fmt.Errorf("failed to update destination stock: %w", err)
			}

			// Create destination history
			toHistory := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: tenantID},
				StockID:          toStock.ID,
				MovementType:     "transfer_in",
				Quantity:         item.Quantity,
				PreviousQuantity: previousToQty,
				NewQuantity:      toStock.Quantity,
				Reference:        transferRef,
				Notes:            fmt.Sprintf("Transfer from %s", fromShop.Name),
				CreatedByID:      userID,
			}
			if err := tx.Create(&toHistory).Error; err != nil {
				return fmt.Errorf("failed to create destination history: %w", err)
			}
		}

		// TODO: Create transfer document for approval workflow if needed

		return nil
	})
}

// GetStockHistory returns stock movement history
func (s *StockService) GetStockHistory(ctx context.Context, stockID, tenantID uuid.UUID) ([]*StockHistoryResponse, error) {
	var stock models.Stock
	if err := s.db.Where("id = ? AND tenant_id = ?", stockID, tenantID).First(&stock).Error; err != nil {
		return nil, errors.New("stock not found")
	}

	var histories []models.StockHistory
	err := s.db.Where("stock_id = ? AND tenant_id = ?", stockID, tenantID).
		Preload("Stock.Product").
		Preload("Stock.Shop").
		Preload("CreatedBy").
		Order("created_at DESC").
		Find(&histories).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get stock history: %w", err)
	}

	// Convert to response format
	responses := make([]*StockHistoryResponse, len(histories))
	for i, history := range histories {
		responses[i] = s.mapStockHistoryToResponse(&history)
	}

	return responses, nil
}

// GetLowStockItems returns items below minimum level
func (s *StockService) GetLowStockItems(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]*StockResponse, error) {
	query := s.db.Model(&models.Stock{}).
		Where("tenant_id = ? AND quantity <= minimum_level", tenantID).
		Preload("Shop").
		Preload("Product.Brand").
		Preload("Product.Category")

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var stocks []models.Stock
	if err := query.Find(&stocks).Error; err != nil {
		return nil, fmt.Errorf("failed to get low stock items: %w", err)
	}

	// Convert to response format
	responses := make([]*StockResponse, len(stocks))
	for i, stock := range stocks {
		responses[i] = s.mapStockToResponse(&stock)
	}

	return responses, nil
}

// UpdateStockMinMax updates minimum and maximum levels
func (s *StockService) UpdateStockMinMax(ctx context.Context, stockID, tenantID uuid.UUID, minLevel, maxLevel int) error {
	var stock models.Stock
	
	err := s.db.Where("id = ? AND tenant_id = ?", stockID, tenantID).First(&stock).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("stock not found")
		}
		return fmt.Errorf("failed to find stock: %w", err)
	}

	if minLevel < 0 || maxLevel < 0 {
		return errors.New("levels cannot be negative")
	}

	if maxLevel > 0 && minLevel > maxLevel {
		return errors.New("minimum level cannot be greater than maximum level")
	}

	updates := map[string]interface{}{
		"minimum_level": minLevel,
		"maximum_level": maxLevel,
	}

	if err := s.db.Model(&stock).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to update stock levels: %w", err)
	}

	// Clear cache
	s.clearStockCache(ctx, tenantID, stock.ShopID, stock.ProductID)

	return nil
}

// ProcessSale updates stock for a sale
func (s *StockService) ProcessSale(ctx context.Context, saleID uuid.UUID, items []models.SaleItem, shopID, tenantID, userID uuid.UUID, reverse bool) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		for _, item := range items {
			var stock models.Stock
			err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", 
				shopID, item.ProductID, tenantID).First(&stock).Error
			
			if err != nil {
				return fmt.Errorf("stock not found for product %s", item.ProductID)
			}

			previousQty := stock.Quantity
			var newQty int
			var movementType string

			if reverse {
				// Return - add back to stock
				newQty = stock.Quantity + item.Quantity
				movementType = "return"
			} else {
				// Sale - remove from stock
				if stock.Quantity < item.Quantity {
					return fmt.Errorf("insufficient stock for product %s", item.ProductID)
				}
				newQty = stock.Quantity - item.Quantity
				movementType = "sale"
			}

			// Update stock
			stock.Quantity = newQty
			if err := tx.Save(&stock).Error; err != nil {
				return fmt.Errorf("failed to update stock: %w", err)
			}

			// Create history
			history := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: tenantID},
				StockID:          stock.ID,
				MovementType:     movementType,
				Quantity:         item.Quantity,
				PreviousQuantity: previousQty,
				NewQuantity:      newQty,
				UnitCost:         item.UnitPrice,
				TotalCost:        item.TotalPrice,
				Reference:        fmt.Sprintf("SALE-%s", saleID),
				CreatedByID:      userID,
			}

			if err := tx.Create(&history).Error; err != nil {
				return fmt.Errorf("failed to create stock history: %w", err)
			}
		}

		return nil
	})
}

// Helper types and functions

// StockFilters represents filters for stock queries
type StockFilters struct {
	ProductID  uuid.UUID `form:"product_id"`
	CategoryID uuid.UUID `form:"category_id"`
	BrandID    uuid.UUID `form:"brand_id"`
	LowStock   bool      `form:"low_stock"`
}

// mapStockToResponse converts model to response format
func (s *StockService) mapStockToResponse(stock *models.Stock) *StockResponse {
	response := &StockResponse{
		ID:                stock.ID,
		ShopID:            stock.ShopID,
		ProductID:         stock.ProductID,
		Quantity:          stock.Quantity,
		ReservedQuantity:  stock.ReservedQuantity,
		AvailableQuantity: stock.Quantity - stock.ReservedQuantity,
		MinimumLevel:      stock.MinimumLevel,
		MaximumLevel:      stock.MaximumLevel,
		CostingMethod:     stock.CostingMethod,
		AverageCost:       stock.AverageCost,
		LastPurchasePrice: stock.LastPurchasePrice,
		LastPurchaseDate:  stock.LastPurchaseDate,
		UpdatedAt:         stock.UpdatedAt,
	}

	if stock.Shop != nil {
		response.ShopName = stock.Shop.Name
	}

	if stock.Product != nil {
		response.ProductName = stock.Product.Name
		response.Size = stock.Product.Size
		response.SKU = stock.Product.SKU
		
		if stock.Product.Brand != nil {
			response.BrandName = stock.Product.Brand.Name
		}
		
		if stock.Product.Category != nil {
			response.CategoryName = stock.Product.Category.Name
		}
	}

	return response
}

// mapStockHistoryToResponse converts model to response format
func (s *StockService) mapStockHistoryToResponse(history *models.StockHistory) *StockHistoryResponse {
	response := &StockHistoryResponse{
		ID:               history.ID,
		StockID:          history.StockID,
		MovementType:     history.MovementType,
		Quantity:         history.Quantity,
		PreviousQuantity: history.PreviousQuantity,
		NewQuantity:      history.NewQuantity,
		UnitCost:         history.UnitCost,
		TotalCost:        history.TotalCost,
		Reference:        history.Reference,
		Notes:            history.Notes,
		CreatedAt:        history.CreatedAt,
	}

	if history.Stock != nil {
		if history.Stock.Product != nil {
			response.ProductName = history.Stock.Product.Name
		}
		if history.Stock.Shop != nil {
			response.ShopName = history.Stock.Shop.Name
		}
	}

	if history.CreatedBy != nil {
		response.CreatedByName = history.CreatedBy.FirstName + " " + history.CreatedBy.LastName
	}

	return response
}

// clearStockCache clears stock-related cache
func (s *StockService) clearStockCache(ctx context.Context, tenantID, shopID, productID uuid.UUID) {
	cacheKeys := []string{
		fmt.Sprintf(cache.StockKey, shopID.String(), productID.String()),
		fmt.Sprintf("stock_levels:%s", tenantID.String()),
		fmt.Sprintf("low_stock:%s", tenantID.String()),
	}
	
	for _, key := range cacheKeys {
		s.cache.Delete(ctx, key)
	}
}