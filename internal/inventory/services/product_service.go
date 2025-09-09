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

// ProductService handles product management operations
type ProductService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewProductService creates a new product service
func NewProductService(db *database.DB, cache *cache.Cache) *ProductService {
	return &ProductService{
		db:    db,
		cache: cache,
	}
}

// ProductRequest represents product creation/update request
type ProductRequest struct {
	Name           string  `json:"name" binding:"required"`
	CategoryID     uuid.UUID `json:"category_id" binding:"required"`
	BrandID        uuid.UUID `json:"brand_id" binding:"required"`
	Size           string  `json:"size" binding:"required"`
	AlcoholContent float64 `json:"alcohol_content"`
	Description    string  `json:"description"`
	Barcode        string  `json:"barcode"`
	SKU            string  `json:"sku"`
	CostPrice      float64 `json:"cost_price" binding:"required,gt=0"`
	SellingPrice   float64 `json:"selling_price" binding:"required,gt=0"`
	MRP            float64 `json:"mrp" binding:"required,gt=0"`
	IsActive       bool    `json:"is_active"`
}

// ProductResponse represents product in responses
type ProductResponse struct {
	ID             uuid.UUID `json:"id"`
	Name           string    `json:"name"`
	CategoryID     uuid.UUID `json:"category_id"`
	CategoryName   string    `json:"category_name"`
	BrandID        uuid.UUID `json:"brand_id"`
	BrandName      string    `json:"brand_name"`
	Size           string    `json:"size"`
	AlcoholContent float64   `json:"alcohol_content"`
	Description    string    `json:"description"`
	Barcode        string    `json:"barcode"`
	SKU            string    `json:"sku"`
	CostPrice      float64   `json:"cost_price"`
	SellingPrice   float64   `json:"selling_price"`
	MRP            float64   `json:"mrp"`
	IsActive       bool      `json:"is_active"`
	CurrentStock   int       `json:"current_stock"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}


// BrandPricingRequest represents brand pricing request
type BrandPricingRequest struct {
	BrandID      uuid.UUID `json:"brand_id" binding:"required"`
	Size         string    `json:"size" binding:"required"`
	CostPrice    float64   `json:"cost_price" binding:"required,gt=0"`
	SellingPrice float64   `json:"selling_price" binding:"required,gt=0"`
	MRP          float64   `json:"mrp" binding:"required,gt=0"`
}

// CreateProduct creates a new product
func (s *ProductService) CreateProduct(ctx context.Context, req ProductRequest, tenantID uuid.UUID) (*ProductResponse, error) {
	// Verify category exists
	var category models.Category
	if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
		return nil, errors.New("category not found")
	}

	// Verify brand exists
	var brand models.Brand
	if err := s.db.Where("id = ? AND tenant_id = ?", req.BrandID, tenantID).First(&brand).Error; err != nil {
		return nil, errors.New("brand not found")
	}

	// Check for duplicate SKU if provided
	if req.SKU != "" {
		var existing models.Product
		if err := s.db.Where("sku = ? AND tenant_id = ?", req.SKU, tenantID).First(&existing).Error; err == nil {
			return nil, errors.New("product with this SKU already exists")
		}
	} else {
		// Generate SKU if not provided
		req.SKU = s.generateSKU(brand.Name, req.Size)
	}

	// Create product
	product := models.Product{
		TenantModel:    models.TenantModel{TenantID: tenantID},
		Name:           req.Name,
		CategoryID:     req.CategoryID,
		BrandID:        req.BrandID,
		Size:           req.Size,
		AlcoholContent: req.AlcoholContent,
		Description:    req.Description,
		Barcode:        req.Barcode,
		SKU:            req.SKU,
		CostPrice:      req.CostPrice,
		SellingPrice:   req.SellingPrice,
		MRP:            req.MRP,
		IsActive:       req.IsActive,
		Category:       &category,
		Brand:          &brand,
	}

	if err := s.db.Create(&product).Error; err != nil {
		return nil, fmt.Errorf("failed to create product: %w", err)
	}

	// Clear cache
	s.clearProductCache(ctx, tenantID)

	return s.mapProductToResponse(&product, 0), nil
}

// GetProducts returns paginated list of products
func (s *ProductService) GetProducts(ctx context.Context, tenantID uuid.UUID, filters ProductFilters) (*ProductListResponse, error) {
	var products []models.Product
	var totalCount int64

	query := s.db.Model(&models.Product{}).
		Where("tenant_id = ?", tenantID).
		Preload("Category").
		Preload("Brand")

	// Apply filters
	if filters.CategoryID != uuid.Nil {
		query = query.Where("category_id = ?", filters.CategoryID)
	}
	if filters.BrandID != uuid.Nil {
		query = query.Where("brand_id = ?", filters.BrandID)
	}
	if filters.IsActive != nil {
		query = query.Where("is_active = ?", *filters.IsActive)
	}
	if filters.Search != "" {
		searchPattern := "%" + filters.Search + "%"
		query = query.Where("name ILIKE ? OR sku ILIKE ? OR barcode ILIKE ?", 
			searchPattern, searchPattern, searchPattern)
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count products: %w", err)
	}

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("name ASC").
		Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to get products: %w", err)
	}

	// Get stock levels for products
	stockMap := s.getStockLevels(tenantID, products)

	// Convert to response format
	responses := make([]*ProductResponse, len(products))
	for i, product := range products {
		stock := stockMap[product.ID]
		responses[i] = s.mapProductToResponse(&product, stock)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &ProductListResponse{
		Products:   responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
	}, nil
}

// GetProductByID returns product by ID
func (s *ProductService) GetProductByID(ctx context.Context, productID, tenantID uuid.UUID) (*ProductResponse, error) {
	var product models.Product
	
	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).
		Preload("Category").
		Preload("Brand").
		First(&product).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("product not found")
		}
		return nil, fmt.Errorf("failed to get product: %w", err)
	}

	// Get stock level
	var totalStock int
	s.db.Model(&models.Stock{}).
		Where("product_id = ? AND tenant_id = ?", productID, tenantID).
		Select("COALESCE(SUM(quantity), 0)").
		Scan(&totalStock)

	return s.mapProductToResponse(&product, totalStock), nil
}

// UpdateProduct updates product information
func (s *ProductService) UpdateProduct(ctx context.Context, productID, tenantID uuid.UUID, req ProductRequest) (*ProductResponse, error) {
	var product models.Product
	
	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("product not found")
		}
		return nil, fmt.Errorf("failed to find product: %w", err)
	}

	// Verify category if changed
	if req.CategoryID != product.CategoryID {
		var category models.Category
		if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
			return nil, errors.New("category not found")
		}
	}

	// Verify brand if changed
	if req.BrandID != product.BrandID {
		var brand models.Brand
		if err := s.db.Where("id = ? AND tenant_id = ?", req.BrandID, tenantID).First(&brand).Error; err != nil {
			return nil, errors.New("brand not found")
		}
	}

	// Check SKU uniqueness if changed
	if req.SKU != "" && req.SKU != product.SKU {
		var existing models.Product
		if err := s.db.Where("sku = ? AND tenant_id = ? AND id != ?", req.SKU, tenantID, productID).First(&existing).Error; err == nil {
			return nil, errors.New("product with this SKU already exists")
		}
	}

	// Update product
	updates := map[string]interface{}{
		"name":            req.Name,
		"category_id":     req.CategoryID,
		"brand_id":        req.BrandID,
		"size":            req.Size,
		"alcohol_content": req.AlcoholContent,
		"description":     req.Description,
		"barcode":         req.Barcode,
		"sku":             req.SKU,
		"cost_price":      req.CostPrice,
		"selling_price":   req.SellingPrice,
		"mrp":             req.MRP,
		"is_active":       req.IsActive,
	}

	if err := s.db.Model(&product).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update product: %w", err)
	}

	// Clear cache
	s.clearProductCache(ctx, tenantID)

	// Get updated product
	return s.GetProductByID(ctx, productID, tenantID)
}

// DeleteProduct soft deletes a product
func (s *ProductService) DeleteProduct(ctx context.Context, productID, tenantID uuid.UUID) error {
	var product models.Product
	
	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("product not found")
		}
		return fmt.Errorf("failed to find product: %w", err)
	}

	// Check if product has stock
	var stockCount int64
	s.db.Model(&models.Stock{}).
		Where("product_id = ? AND quantity > 0", productID).
		Count(&stockCount)
	
	if stockCount > 0 {
		return errors.New("cannot delete product with existing stock")
	}

	// Soft delete product
	if err := s.db.Delete(&product).Error; err != nil {
		return fmt.Errorf("failed to delete product: %w", err)
	}

	// Clear cache
	s.clearProductCache(ctx, tenantID)

	return nil
}

// Brand Management

// CreateBrand creates a new brand
func (s *ProductService) CreateBrand(ctx context.Context, req BrandRequest, tenantID uuid.UUID) (*BrandResponse, error) {
	// Check for duplicate name
	var existing models.Brand
	if err := s.db.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existing).Error; err == nil {
		return nil, errors.New("brand with this name already exists")
	}

	// Create brand
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	
	brand := models.Brand{
		TenantModel: models.TenantModel{TenantID: tenantID},
		Name:        req.Name,
		Description: req.Description,
		IsActive:    isActive,
	}

	if err := s.db.Create(&brand).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand: %w", err)
	}

	// Clear cache
	s.clearBrandCache(ctx, tenantID)

	return s.mapBrandToResponse(&brand, 0), nil
}

// GetBrands returns all brands
func (s *ProductService) GetBrands(ctx context.Context, tenantID uuid.UUID) ([]*BrandResponse, error) {
	var brands []models.Brand
	
	err := s.db.Where("tenant_id = ?", tenantID).
		Order("name ASC").
		Find(&brands).Error
	
	if err != nil {
		return nil, fmt.Errorf("failed to get brands: %w", err)
	}

	// Get product counts for each brand
	var brandCounts []struct {
		BrandID uuid.UUID
		Count   int
	}
	s.db.Model(&models.Product{}).
		Select("brand_id, COUNT(*) as count").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
		Group("brand_id").
		Scan(&brandCounts)

	countMap := make(map[uuid.UUID]int)
	for _, bc := range brandCounts {
		countMap[bc.BrandID] = bc.Count
	}

	// Convert to response format
	responses := make([]*BrandResponse, len(brands))
	for i, brand := range brands {
		responses[i] = s.mapBrandToResponse(&brand, countMap[brand.ID])
	}

	return responses, nil
}

// GetBrandByID returns brand by ID
func (s *ProductService) GetBrandByID(ctx context.Context, brandID, tenantID uuid.UUID) (*BrandResponse, error) {
	var brand models.Brand
	
	err := s.db.Where("id = ? AND tenant_id = ?", brandID, tenantID).First(&brand).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("brand not found")
		}
		return nil, fmt.Errorf("failed to get brand: %w", err)
	}

	// Get product count
	var productCount int64
	s.db.Model(&models.Product{}).
		Where("brand_id = ? AND tenant_id = ? AND deleted_at IS NULL", brandID, tenantID).
		Count(&productCount)

	return s.mapBrandToResponse(&brand, int(productCount)), nil
}

// UpdateBrand updates brand information
func (s *ProductService) UpdateBrand(ctx context.Context, brandID, tenantID uuid.UUID, req BrandRequest) (*BrandResponse, error) {
	var brand models.Brand
	
	err := s.db.Where("id = ? AND tenant_id = ?", brandID, tenantID).First(&brand).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("brand not found")
		}
		return nil, fmt.Errorf("failed to find brand: %w", err)
	}

	// Check name uniqueness if changed
	if req.Name != brand.Name {
		var existing models.Brand
		if err := s.db.Where("name = ? AND tenant_id = ? AND id != ?", req.Name, tenantID, brandID).First(&existing).Error; err == nil {
			return nil, errors.New("brand with this name already exists")
		}
	}

	// Update brand
	updates := map[string]interface{}{
		"name":        req.Name,
		"description": req.Description,
		"is_active":   req.IsActive,
	}

	if err := s.db.Model(&brand).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand: %w", err)
	}

	// Clear cache
	s.clearBrandCache(ctx, tenantID)

	// Get updated brand
	return s.GetBrandByID(ctx, brandID, tenantID)
}

// DeleteBrand soft deletes a brand
func (s *ProductService) DeleteBrand(ctx context.Context, brandID, tenantID uuid.UUID) error {
	var brand models.Brand
	
	err := s.db.Where("id = ? AND tenant_id = ?", brandID, tenantID).First(&brand).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("brand not found")
		}
		return fmt.Errorf("failed to find brand: %w", err)
	}

	// Check if brand has products
	var productCount int64
	s.db.Model(&models.Product{}).
		Where("brand_id = ? AND deleted_at IS NULL", brandID).
		Count(&productCount)
	
	if productCount > 0 {
		return errors.New("cannot delete brand with existing products")
	}

	// Soft delete brand
	if err := s.db.Delete(&brand).Error; err != nil {
		return fmt.Errorf("failed to delete brand: %w", err)
	}

	// Clear cache
	s.clearBrandCache(ctx, tenantID)

	return nil
}

// Brand Pricing Management

// CreateBrandPricing creates brand-size pricing
func (s *ProductService) CreateBrandPricing(ctx context.Context, req BrandPricingRequest, tenantID uuid.UUID) error {
	// Verify brand exists
	var brand models.Brand
	if err := s.db.Where("id = ? AND tenant_id = ?", req.BrandID, tenantID).First(&brand).Error; err != nil {
		return errors.New("brand not found")
	}

	// Check for duplicate
	var existing models.BrandPricing
	if err := s.db.Where("brand_id = ? AND size = ? AND tenant_id = ?", 
		req.BrandID, req.Size, tenantID).First(&existing).Error; err == nil {
		// Update existing
		updates := map[string]interface{}{
			"cost_price":    req.CostPrice,
			"selling_price": req.SellingPrice,
			"mrp":           req.MRP,
		}
		return s.db.Model(&existing).Updates(updates).Error
	}

	// Create new pricing
	pricing := models.BrandPricing{
		TenantModel:  models.TenantModel{TenantID: tenantID},
		BrandID:      req.BrandID,
		Size:         req.Size,
		CostPrice:    req.CostPrice,
		SellingPrice: req.SellingPrice,
		MRP:          req.MRP,
	}

	if err := s.db.Create(&pricing).Error; err != nil {
		return fmt.Errorf("failed to create brand pricing: %w", err)
	}

	// Update all products with this brand and size
	s.db.Model(&models.Product{}).
		Where("brand_id = ? AND size = ? AND tenant_id = ?", req.BrandID, req.Size, tenantID).
		Updates(map[string]interface{}{
			"cost_price":    req.CostPrice,
			"selling_price": req.SellingPrice,
			"mrp":           req.MRP,
		})

	return nil
}

// Helper types and functions

// ProductFilters represents filters for products
type ProductFilters struct {
	CategoryID uuid.UUID `form:"category_id"`
	BrandID    uuid.UUID `form:"brand_id"`
	IsActive   *bool     `form:"is_active"`
	Search     string    `form:"search"`
	Page       int       `form:"page"`
	PageSize   int       `form:"page_size"`
}

// ProductListResponse represents paginated product response
type ProductListResponse struct {
	Products   []*ProductResponse `json:"products"`
	TotalCount int64              `json:"total_count"`
	Page       int                `json:"page"`
	PageSize   int                `json:"page_size"`
	TotalPages int                `json:"total_pages"`
}

// mapProductToResponse converts model to response format
func (s *ProductService) mapProductToResponse(product *models.Product, currentStock int) *ProductResponse {
	response := &ProductResponse{
		ID:             product.ID,
		Name:           product.Name,
		CategoryID:     product.CategoryID,
		BrandID:        product.BrandID,
		Size:           product.Size,
		AlcoholContent: product.AlcoholContent,
		Description:    product.Description,
		Barcode:        product.Barcode,
		SKU:            product.SKU,
		CostPrice:      product.CostPrice,
		SellingPrice:   product.SellingPrice,
		MRP:            product.MRP,
		IsActive:       product.IsActive,
		CurrentStock:   currentStock,
		CreatedAt:      product.CreatedAt,
		UpdatedAt:      product.UpdatedAt,
	}

	if product.Category != nil {
		response.CategoryName = product.Category.Name
	}

	if product.Brand != nil {
		response.BrandName = product.Brand.Name
	}

	return response
}

// mapBrandToResponse converts model to response format
func (s *ProductService) mapBrandToResponse(brand *models.Brand, productCount int) *BrandResponse {
	return &BrandResponse{
		ID:           brand.ID,
		Name:         brand.Name,
		Description:  brand.Description,
		IsActive:     brand.IsActive,
		ProductCount: int64(productCount),
	}
}

// generateSKU generates SKU for product
func (s *ProductService) generateSKU(brandName, size string) string {
	timestamp := time.Now().Format("060102")
	random, _ := utils.GenerateRandomString(4)
	brandCode := brandName[:3]
	if len(brandName) < 3 {
		brandCode = brandName
	}
	return fmt.Sprintf("%s-%s-%s-%s", brandCode, size, timestamp, random)
}

// getStockLevels gets stock levels for products
func (s *ProductService) getStockLevels(tenantID uuid.UUID, products []models.Product) map[uuid.UUID]int {
	stockMap := make(map[uuid.UUID]int)
	
	if len(products) == 0 {
		return stockMap
	}

	productIDs := make([]uuid.UUID, len(products))
	for i, p := range products {
		productIDs[i] = p.ID
	}

	var stockLevels []struct {
		ProductID uuid.UUID
		Total     int
	}

	s.db.Model(&models.Stock{}).
		Select("product_id, COALESCE(SUM(quantity), 0) as total").
		Where("product_id IN ? AND tenant_id = ?", productIDs, tenantID).
		Group("product_id").
		Scan(&stockLevels)

	for _, sl := range stockLevels {
		stockMap[sl.ProductID] = sl.Total
	}

	return stockMap
}

// clearProductCache clears product-related cache
func (s *ProductService) clearProductCache(ctx context.Context, tenantID uuid.UUID) {
	cacheKey := fmt.Sprintf("products:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)
}

// clearBrandCache clears brand-related cache
func (s *ProductService) clearBrandCache(ctx context.Context, tenantID uuid.UUID) {
	cacheKey := fmt.Sprintf("brands:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)
}