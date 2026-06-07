package inventory

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"gorm.io/gorm"
)

// Server implements the gRPC InventoryService
type Server struct {
	UnimplementedInventoryServiceServer
	DB     *gorm.DB
	Logger *zap.Logger
}

// NewServer creates a new gRPC inventory server
func NewServer(db *gorm.DB, logger *zap.Logger) *Server {
	return &Server{
		DB:     db,
		Logger: logger,
	}
}

// GetProduct retrieves a single product by ID
func (s *Server) GetProduct(ctx context.Context, req *GetProductRequest) (*ProductResponse, error) {
	s.Logger.Info("gRPC GetProduct called",
		zap.String("product_id", req.Id),
		zap.String("tenant_id", req.TenantId))

	var product models.Product
	result := s.DB.Where("id = ? AND tenant_id = ?", req.Id, req.TenantId).First(&product)
	if result.Error != nil {
		if result.Error == gorm.ErrRecordNotFound {
			return nil, status.Error(codes.NotFound, "product not found")
		}
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	return productToProto(&product), nil
}

// ListProducts retrieves products with pagination
func (s *Server) ListProducts(ctx context.Context, req *ListProductsRequest) (*ListProductsResponse, error) {
	s.Logger.Info("gRPC ListProducts called",
		zap.String("tenant_id", req.TenantId))

	tenantID, _ := uuid.Parse(req.TenantId)
	var products []models.Product
	var total int64

	query := s.DB.Where("tenant_id = ?", tenantID)

	if req.CategoryId != "" {
		categoryID, _ := uuid.Parse(req.CategoryId)
		query = query.Where("category_id = ?", categoryID)
	}
	if req.Search != "" {
		query = query.Where("name ILIKE ?", "%"+req.Search+"%")
	}

	// Count total
	query.Model(&models.Product{}).Count(&total)

	// Pagination
	pageSize := req.PageSize
	if pageSize == 0 {
		pageSize = 20
	}
	page := req.Page
	if page == 0 {
		page = 1
	}
	offset := (page - 1) * pageSize

	result := query.Limit(int(pageSize)).Offset(int(offset)).Find(&products)
	if result.Error != nil {
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	protoProducts := make([]*ProductResponse, len(products))
	for i, product := range products {
		protoProducts[i] = productToProto(&product)
	}

	return &ListProductsResponse{
		Products: protoProducts,
		Total:    int32(total),
		Page:     page,
		PageSize: pageSize,
	}, nil
}

// CreateProduct creates a new product
func (s *Server) CreateProduct(ctx context.Context, req *CreateProductRequest) (*ProductResponse, error) {
	s.Logger.Info("gRPC CreateProduct called",
		zap.String("tenant_id", req.TenantId),
		zap.String("name", req.Name))

	categoryID, _ := uuid.Parse(req.CategoryId)
	brandID, _ := uuid.Parse(req.BrandId)
	tenantID, _ := uuid.Parse(req.TenantId)

	product := &models.Product{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{
				ID: uuid.New(),
			},
			TenantID: &tenantID,
		},
		Name:           req.Name,
		CategoryID:     categoryID,
		BrandID:        brandID,
		SellingPrice:   req.Price,
		CostPrice:      req.Cost,
		Barcode:        req.Barcode,
		SKU:            req.Sku,
		Description:    req.Description,
		Size:           req.Size,
		AlcoholContent: req.AlcoholContent,
		IsActive:       true,
	}

	result := s.DB.Create(product)
	if result.Error != nil {
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	return productToProto(product), nil
}

// UpdateProduct updates an existing product
func (s *Server) UpdateProduct(ctx context.Context, req *UpdateProductRequest) (*ProductResponse, error) {
	s.Logger.Info("gRPC UpdateProduct called",
		zap.String("product_id", req.Id),
		zap.String("tenant_id", req.TenantId))

	var product models.Product
	result := s.DB.Where("id = ? AND tenant_id = ?", req.Id, req.TenantId).First(&product)
	if result.Error != nil {
		if result.Error == gorm.ErrRecordNotFound {
			return nil, status.Error(codes.NotFound, "product not found")
		}
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	// Update fields
	if req.Name != "" {
		product.Name = req.Name
	}
	if req.CategoryId != "" {
		categoryID, _ := uuid.Parse(req.CategoryId)
		product.CategoryID = categoryID
	}
	if req.Price > 0 {
		product.SellingPrice = req.Price
	}
	if req.Cost > 0 {
		product.CostPrice = req.Cost
	}
	if req.Description != "" {
		product.Description = req.Description
	}

	result = s.DB.Save(&product)
	if result.Error != nil {
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	return productToProto(&product), nil
}

// DeleteProduct deletes a product
func (s *Server) DeleteProduct(ctx context.Context, req *DeleteProductRequest) (*DeleteResponse, error) {
	s.Logger.Info("gRPC DeleteProduct called",
		zap.String("product_id", req.Id),
		zap.String("tenant_id", req.TenantId))

	result := s.DB.Where("id = ? AND tenant_id = ?", req.Id, req.TenantId).Delete(&models.Product{})
	if result.Error != nil {
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	if result.RowsAffected == 0 {
		return &DeleteResponse{
			Success: false,
			Message: "product not found",
		}, nil
	}

	return &DeleteResponse{
		Success: true,
		Message: "product deleted successfully",
	}, nil
}

// GetStock retrieves stock information for a product
func (s *Server) GetStock(ctx context.Context, req *GetStockRequest) (*StockResponse, error) {
	s.Logger.Info("gRPC GetStock called",
		zap.String("product_id", req.ProductId),
		zap.String("shop_id", req.ShopId))

	productID, _ := uuid.Parse(req.ProductId)
	shopID, _ := uuid.Parse(req.ShopId)
	tenantID, _ := uuid.Parse(req.TenantId)

	var stock models.Stock
	result := s.DB.Where("product_id = ? AND shop_id = ? AND tenant_id = ?",
		productID, shopID, tenantID).First(&stock)

	if result.Error != nil {
		if result.Error == gorm.ErrRecordNotFound {
			// Return zero stock if not found
			return &StockResponse{
				ProductId:         req.ProductId,
				ShopId:            req.ShopId,
				Quantity:          0,
				ReservedQuantity:  0,
				AvailableQuantity: 0,
				LastUpdated:       time.Now().Format(time.RFC3339),
			}, nil
		}
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	return stockToProto(&stock), nil
}

// AdjustStock adjusts stock quantity for a product
func (s *Server) AdjustStock(ctx context.Context, req *AdjustStockRequest) (*StockResponse, error) {
	s.Logger.Info("gRPC AdjustStock called",
		zap.String("product_id", req.ProductId),
		zap.Int32("quantity", req.Quantity))

	productID, _ := uuid.Parse(req.ProductId)
	shopID, _ := uuid.Parse(req.ShopId)
	tenantID, _ := uuid.Parse(req.TenantId)

	var stock models.Stock
	result := s.DB.Where("product_id = ? AND shop_id = ? AND tenant_id = ?",
		productID, shopID, &tenantID).First(&stock)

	if result.Error != nil && result.Error != gorm.ErrRecordNotFound {
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	if result.Error == gorm.ErrRecordNotFound {
		// Create new stock record
		stock = models.Stock{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			ShopID:    shopID,
			ProductID: productID,
			Quantity:  int(req.Quantity),
		}
		result = s.DB.Create(&stock)
	} else {
		// Update existing stock
		stock.Quantity += int(req.Quantity)
		result = s.DB.Save(&stock)
	}

	if result.Error != nil {
		return nil, status.Error(codes.Internal, result.Error.Error())
	}

	return stockToProto(&stock), nil
}

// BulkStockUpdate updates multiple stock items in a single transaction
func (s *Server) BulkStockUpdate(ctx context.Context, req *BulkStockUpdateRequest) (*BulkStockUpdateResponse, error) {
	s.Logger.Info("gRPC BulkStockUpdate called",
		zap.String("tenant_id", req.TenantId),
		zap.Int("updates_count", len(req.Updates)))

	var updatedCount int32
	var failedCount int32
	var errors []string

	shopID, _ := uuid.Parse(req.ShopId)
	tenantID, _ := uuid.Parse(req.TenantId)

	// Use transaction for bulk updates
	err := s.DB.Transaction(func(tx *gorm.DB) error {
		for _, update := range req.Updates {
			productID, _ := uuid.Parse(update.ProductId)

			var stock models.Stock
			result := tx.Where("product_id = ? AND shop_id = ? AND tenant_id = ?",
				productID, shopID, &tenantID).First(&stock)

			if result.Error != nil && result.Error != gorm.ErrRecordNotFound {
				errors = append(errors, fmt.Sprintf("product %s: %v", update.ProductId, result.Error))
				failedCount++
				continue
			}

			if result.Error == gorm.ErrRecordNotFound {
				stock = models.Stock{
					TenantModel: models.TenantModel{
						BaseModel: models.BaseModel{ID: uuid.New()},
						TenantID:  &tenantID,
					},
					ShopID:    shopID,
					ProductID: productID,
					Quantity:  int(update.Quantity),
				}
				if err := tx.Create(&stock).Error; err != nil {
					errors = append(errors, fmt.Sprintf("product %s: %v", update.ProductId, err))
					failedCount++
					continue
				}
			} else {
				stock.Quantity += int(update.Quantity)
				if err := tx.Save(&stock).Error; err != nil {
					errors = append(errors, fmt.Sprintf("product %s: %v", update.ProductId, err))
					failedCount++
					continue
				}
			}

			updatedCount++
		}
		return nil
	})

	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}

	return &BulkStockUpdateResponse{
		UpdatedCount: updatedCount,
		FailedCount:  failedCount,
		Errors:       errors,
	}, nil
}

// StreamStockUpdates streams real-time stock updates (stub for now)
func (s *Server) StreamStockUpdates(req *StreamStockRequest, stream InventoryService_StreamStockUpdatesServer) error {
	s.Logger.Info("gRPC StreamStockUpdates called",
		zap.String("tenant_id", req.TenantId))

	// TODO: Implement real-time streaming with Kafka or Redis pub/sub
	// For now, return a simple message
	return status.Error(codes.Unimplemented, "streaming not yet implemented")
}

// StreamProductChanges streams real-time product changes (stub for now)
func (s *Server) StreamProductChanges(req *StreamProductRequest, stream InventoryService_StreamProductChangesServer) error {
	s.Logger.Info("gRPC StreamProductChanges called",
		zap.String("tenant_id", req.TenantId))

	// TODO: Implement real-time streaming with Kafka or Redis pub/sub
	return status.Error(codes.Unimplemented, "streaming not yet implemented")
}

// Helper functions

func productToProto(product *models.Product) *ProductResponse {
	tenantID := ""
	if product.TenantID != nil {
		tenantID = product.TenantID.String()
	}

	return &ProductResponse{
		Id:             product.ID.String(),
		TenantId:       tenantID,
		Name:           product.Name,
		CategoryId:     product.CategoryID.String(),
		BrandId:        product.BrandID.String(),
		Price:          product.SellingPrice,
		Cost:           product.CostPrice,
		Barcode:        product.Barcode,
		Sku:            product.SKU,
		Description:    product.Description,
		Size:           product.Size,
		AlcoholContent: product.AlcoholContent,
		Mrp:            product.MRP,
		CreatedAt:      product.CreatedAt.Format(time.RFC3339),
		UpdatedAt:      product.UpdatedAt.Format(time.RFC3339),
	}
}

func stockToProto(stock *models.Stock) *StockResponse {
	available := stock.Quantity - stock.ReservedQuantity
	if available < 0 {
		available = 0
	}

	return &StockResponse{
		ProductId:         stock.ProductID.String(),
		ShopId:            stock.ShopID.String(),
		Quantity:          int32(stock.Quantity),
		ReservedQuantity:  int32(stock.ReservedQuantity),
		AvailableQuantity: int32(available),
		LastUpdated:       stock.UpdatedAt.Format(time.RFC3339),
	}
}
