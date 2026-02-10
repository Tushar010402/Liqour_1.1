package services

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
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
	db         *database.DB
	cache      *cache.Cache
	saasClient *SaaSBrandClient
}

// NewProductService creates a new product service
func NewProductService(db *database.DB, cache *cache.Cache) *ProductService {
	return &ProductService{
		db:    db,
		cache: cache,
	}
}

// SetSaaSClient sets the SaaS client for category lookups
func (s *ProductService) SetSaaSClient(client *SaaSBrandClient) {
	s.saasClient = client
}

// ProductRequest represents product creation/update request
type ProductRequest struct {
	Name           string    `json:"name" binding:"required"`
	CategoryID     uuid.UUID `json:"category_id" binding:"required"`
	BrandID        uuid.UUID `json:"brand_id" binding:"required"`
	Size           string    `json:"size" binding:"required"`
	AlcoholContent float64   `json:"alcohol_content"`
	Description    string    `json:"description"`
	Barcode        string    `json:"barcode"`
	SKU            string    `json:"sku"`
	ImageURL       string    `json:"image_url"`
	ImageBase64    string    `json:"image_base64"`
	CostPrice      float64   `json:"cost_price" binding:"required,gte=0"`
	DutyFee        float64   `json:"duty_fee"`
	TotalCost      float64   `json:"total_cost"`
	SellingPrice   float64   `json:"selling_price" binding:"required,gte=0"`
	MRP            float64   `json:"mrp"`
	IsActive       bool      `json:"is_active"`
}

// ProductResponse represents product in responses
type ProductResponse struct {
	ID              uuid.UUID  `json:"id"`
	Name            string     `json:"name"`
	CategoryID      uuid.UUID  `json:"category_id"`
	CategoryName    string     `json:"category_name"`
	SubcategoryID   *uuid.UUID `json:"subcategory_id,omitempty"`
	SubcategoryName string     `json:"subcategory_name,omitempty"`
	BrandID         uuid.UUID  `json:"brand_id"`
	BrandName       string     `json:"brand_name"`
	Size            string     `json:"size"`
	AlcoholContent  float64    `json:"alcohol_content"`
	Description     string     `json:"description"`
	Barcode         string     `json:"barcode"`
	SKU             string     `json:"sku"`
	ImageURL        string     `json:"image_url"`
	CostPrice       float64    `json:"cost_price"`
	DutyFee         float64    `json:"duty_fee"`
	SellingPrice    float64    `json:"selling_price"`
	MRP             float64    `json:"mrp"`
	IsActive        bool       `json:"is_active"`
	CurrentStock    int        `json:"current_stock"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
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

	// Normalize size to uppercase for consistency (prevents "500ml" and "500ML" duplicates)
	normalizedSize := normalizeSize(req.Size)

	// Process product image (base64 decode and save)
	imageURL, err := s.processProductImage(tenantID, req.ImageBase64, req.ImageURL)
	if err != nil {
		return nil, fmt.Errorf("failed to process product image: %w", err)
	}

	// Create product
	product := models.Product{
		TenantModel:    models.TenantModel{TenantID: &tenantID},
		Name:           req.Name,
		CategoryID:     req.CategoryID,
		BrandID:        req.BrandID,
		Size:           normalizedSize,
		AlcoholContent: req.AlcoholContent,
		Description:    req.Description,
		Barcode:        req.Barcode,
		SKU:            req.SKU,
		ImageURL:       imageURL,
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
		Where("products.tenant_id = ?", tenantID).
		Preload("Category").
		Preload("Subcategory").
		Preload("Brand")

	// Note: shop_id filter is used for stock levels only, not for filtering products
	// All tenant products are shown, with shop-specific stock quantities

	// Apply filters
	if len(filters.CategoryIDs) > 0 {
		// Multiple categories filter (takes precedence over single CategoryID)
		query = query.Where("products.category_id IN ?", filters.CategoryIDs)
	} else if filters.CategoryID != uuid.Nil {
		query = query.Where("products.category_id = ?", filters.CategoryID)
	}
	if filters.BrandID != uuid.Nil {
		query = query.Where("products.brand_id = ?", filters.BrandID)
	}
	if filters.IsActive != nil {
		query = query.Where("products.is_active = ?", *filters.IsActive)
	}
	if filters.Search != "" {
		searchPattern := "%" + filters.Search + "%"
		query = query.Where("products.name ILIKE ? OR products.sku ILIKE ? OR products.barcode ILIKE ?",
			searchPattern, searchPattern, searchPattern)
	}
	if filters.Size != "" {
		query = query.Where("UPPER(products.size) = UPPER(?)", filters.Size)
	}

	// Count total records
	countQuery := query.Session(&gorm.Session{})
	if err := countQuery.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count products: %w", err)
	}

	// Get paginated records
	// Use consistent multi-column sort order to prevent products "jumping" during pagination
	// Sort by: size DESC (750ML first), selling_price ASC, product ID (for tie-breaking)
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("products.size DESC, products.selling_price ASC, products.id ASC").
		Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to get products: %w", err)
	}

	// Get stock levels for products (shop-specific if shop_id provided)
	stockMap := s.getStockLevelsForShop(tenantID, filters.ShopID, products)

	// Build SaaS category/subcategory lookup maps for products with missing local categories
	saasCategoryMap, saasSubcategoryMap := s.getSaaSCategoryMaps()

	// Convert to response format
	responses := make([]*ProductResponse, len(products))
	for i, product := range products {
		stock := stockMap[product.ID]
		responses[i] = s.mapProductToResponseWithSaaS(&product, stock, saasCategoryMap, saasSubcategoryMap)
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
			// Check if product exists at all (for better error messaging)
			var anyProduct models.Product
			if checkErr := s.db.Unscoped().Where("id = ?", productID).First(&anyProduct).Error; checkErr == nil {
				if anyProduct.TenantID != nil && *anyProduct.TenantID != tenantID {
					return nil, errors.New("product not found for this tenant")
				}
				if anyProduct.DeletedAt.Valid {
					return nil, errors.New("product has been deleted")
				}
			}
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

	// Process product image
	// If ImageBase64 is provided, decode and save; otherwise use ImageURL from request
	// If neither is provided, keep existing product.ImageURL
	imageURL := req.ImageURL
	if req.ImageBase64 != "" {
		processedURL, err := s.processProductImage(tenantID, req.ImageBase64, "")
		if err != nil {
			return nil, fmt.Errorf("failed to process product image: %w", err)
		}
		imageURL = processedURL
	} else if imageURL == "" {
		// Keep existing image if no new image or URL provided
		imageURL = product.ImageURL
	}

	// Normalize size to uppercase for consistency
	normalizedSize := normalizeSize(req.Size)

	// Update product
	updates := map[string]interface{}{
		"name":            req.Name,
		"category_id":     req.CategoryID,
		"brand_id":        req.BrandID,
		"size":            normalizedSize,
		"alcohol_content": req.AlcoholContent,
		"description":     req.Description,
		"barcode":         req.Barcode,
		"sku":             req.SKU,
		"image_url":       imageURL,
		"cost_price":      req.CostPrice,
		"duty_fee":        req.DutyFee,
		"total_cost":      req.TotalCost,
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
		TenantModel: models.TenantModel{TenantID: &tenantID},
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

// Cache TTL for brands list (5 minutes)
const brandsCacheTTL = 5 * time.Minute

// GetBrands returns all brands (cached for 5 minutes)
func (s *ProductService) GetBrands(ctx context.Context, tenantID uuid.UUID) ([]*BrandResponse, error) {
	cacheKey := fmt.Sprintf("brands:%s", tenantID.String())

	// Try to get from cache first
	var cachedBrands []*BrandResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedBrands); err == nil {
		return cachedBrands, nil
	}

	var brands []models.Brand

	err := s.db.Where("tenant_id = ?", tenantID).
		Order("name ASC").
		Find(&brands).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get brands: %w", err)
	}

	// Get product counts for each brand in a single query
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

	// Cache the result
	_ = s.cache.Set(ctx, cacheKey, responses, brandsCacheTTL)

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
		TenantModel:  models.TenantModel{TenantID: &tenantID},
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
	if err := s.db.Model(&models.Product{}).
		Where("brand_id = ? AND size = ? AND tenant_id = ?", req.BrandID, req.Size, tenantID).
		Updates(map[string]interface{}{
			"cost_price":    req.CostPrice,
			"selling_price": req.SellingPrice,
			"mrp":           req.MRP,
		}).Error; err != nil {
		return fmt.Errorf("failed to update product pricing: %w", err)
	}

	return nil
}

// Helper types and functions

// ProductFilters represents filters for products
type ProductFilters struct {
	CategoryID  uuid.UUID   `form:"category_id"`
	CategoryIDs []uuid.UUID `form:"-"` // Multiple category IDs for filtering (comma-separated in query)
	BrandID     uuid.UUID   `form:"brand_id"`
	ShopID      uuid.UUID   `form:"shop_id"`
	Size        string      `form:"size"`
	IsActive    *bool       `form:"is_active"`
	Search      string      `form:"search"`
	Page        int         `form:"page"`
	PageSize    int         `form:"page_size"`
}

// ProductListResponse represents paginated product response
type ProductListResponse struct {
	Products   []*ProductResponse `json:"products"`
	TotalCount int64              `json:"total_count"`
	Page       int                `json:"page"`
	PageSize   int                `json:"page_size"`
	TotalPages int                `json:"total_pages"`
}

// Cache TTL for SaaS category maps (10 minutes - rarely change)
const saasCategoryMapCacheTTL = 10 * time.Minute

// CachedCategoryMaps holds cached category and subcategory name maps
type CachedCategoryMaps struct {
	Categories    map[string]string `json:"categories"`    // UUID string -> name
	Subcategories map[string]string `json:"subcategories"` // UUID string -> name
}

// getSaaSCategoryMaps fetches SaaS categories and subcategories and returns lookup maps
// Results are cached for 10 minutes to reduce SaaS API calls
func (s *ProductService) getSaaSCategoryMaps() (map[uuid.UUID]string, map[uuid.UUID]string) {
	categoryMap := make(map[uuid.UUID]string)
	subcategoryMap := make(map[uuid.UUID]string)

	if s.saasClient == nil {
		return categoryMap, subcategoryMap
	}

	ctx := context.Background()
	cacheKey := "saas_category_maps"

	// Try to get from cache first
	var cached CachedCategoryMaps
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		// Convert string keys back to UUIDs
		for idStr, name := range cached.Categories {
			if id, err := uuid.Parse(idStr); err == nil {
				categoryMap[id] = name
			}
		}
		for idStr, name := range cached.Subcategories {
			if id, err := uuid.Parse(idStr); err == nil {
				subcategoryMap[id] = name
			}
		}
		return categoryMap, subcategoryMap
	}

	// Fetch SaaS categories
	categories, err := s.saasClient.GetCategories()
	if err == nil {
		for _, cat := range categories {
			categoryMap[cat.ID] = cat.Name
		}
	}

	// Fetch SaaS subcategories
	subcategories, err := s.saasClient.GetSubcategories()
	if err == nil {
		for _, subcat := range subcategories {
			subcategoryMap[subcat.ID] = subcat.Name
		}
	}

	// Cache the result (convert UUID keys to strings for JSON serialization)
	toCache := CachedCategoryMaps{
		Categories:    make(map[string]string),
		Subcategories: make(map[string]string),
	}
	for id, name := range categoryMap {
		toCache.Categories[id.String()] = name
	}
	for id, name := range subcategoryMap {
		toCache.Subcategories[id.String()] = name
	}
	_ = s.cache.Set(ctx, cacheKey, toCache, saasCategoryMapCacheTTL)

	return categoryMap, subcategoryMap
}

// mapProductToResponseWithSaaS converts model to response format with SaaS category fallback
func (s *ProductService) mapProductToResponseWithSaaS(product *models.Product, currentStock int, saasCategoryMap map[uuid.UUID]string, saasSubcategoryMap map[uuid.UUID]string) *ProductResponse {
	response := &ProductResponse{
		ID:             product.ID,
		Name:           product.Name,
		CategoryID:     product.CategoryID,
		SubcategoryID:  product.SubcategoryID,
		BrandID:        product.BrandID,
		Size:           product.Size,
		AlcoholContent: product.AlcoholContent,
		Description:    product.Description,
		Barcode:        product.Barcode,
		SKU:            product.SKU,
		ImageURL:       product.ImageURL,
		CostPrice:      product.CostPrice,
		DutyFee:        product.DutyFee,
		SellingPrice:   product.SellingPrice,
		MRP:            product.MRP,
		IsActive:       product.IsActive,
		CurrentStock:   currentStock,
		CreatedAt:      product.CreatedAt,
		UpdatedAt:      product.UpdatedAt,
	}

	// Try local category first, then fall back to SaaS category
	if product.Category != nil {
		response.CategoryName = product.Category.Name
	} else if name, ok := saasCategoryMap[product.CategoryID]; ok {
		response.CategoryName = name
	}

	// Try local subcategory first, then fall back to SaaS subcategory
	if product.Subcategory != nil {
		response.SubcategoryName = product.Subcategory.Name
	} else if product.SubcategoryID != nil {
		if name, ok := saasSubcategoryMap[*product.SubcategoryID]; ok {
			response.SubcategoryName = name
		}
	}

	if product.Brand != nil {
		response.BrandName = product.Brand.Name
	}

	return response
}

// mapProductToResponse converts model to response format
func (s *ProductService) mapProductToResponse(product *models.Product, currentStock int) *ProductResponse {
	return s.mapProductToResponseWithSaaS(product, currentStock, nil, nil)
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

// normalizeSize normalizes size to uppercase for consistency
// This ensures "500ml" and "500ML" are treated as the same size
func normalizeSize(size string) string {
	return strings.ToUpper(strings.TrimSpace(size))
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

// processProductImage processes base64 image data and saves it to disk
// Returns the URL for the saved image or error
// If imageBase64 is empty but imageURL is provided, returns imageURL unchanged
func (s *ProductService) processProductImage(tenantID uuid.UUID, imageBase64, existingImageURL string) (string, error) {
	// If no base64 image provided, use existing URL (passthrough)
	if imageBase64 == "" {
		return existingImageURL, nil
	}

	// Decode base64 data
	imageBytes, err := base64.StdEncoding.DecodeString(imageBase64)
	if err != nil {
		return "", fmt.Errorf("invalid base64 image data: %w", err)
	}

	// Validate image size (max 5MB for product images)
	const maxImageSize = 5 * 1024 * 1024 // 5MB
	if len(imageBytes) > maxImageSize {
		return "", fmt.Errorf("image too large: %d bytes (max %d bytes)", len(imageBytes), maxImageSize)
	}

	// Minimum size check to detect corrupted data
	if len(imageBytes) < 100 {
		return "", fmt.Errorf("image too small: %d bytes (likely corrupted or invalid)", len(imageBytes))
	}

	// Detect content type from image bytes
	contentType := http.DetectContentType(imageBytes)

	// Validate content type and determine extension
	var ext string
	switch contentType {
	case "image/jpeg":
		ext = ".jpg"
	case "image/png":
		ext = ".png"
	default:
		return "", fmt.Errorf("unsupported image type: %s (allowed: image/jpeg, image/png)", contentType)
	}

	// Generate unique filename with UUID
	fileUUID := uuid.New().String()
	yearMonth := time.Now().Format("2006-01")
	filename := fileUUID + ext

	// Create directory path: /var/www/liquorpro/uploads/product-images/{tenant_id}/{YYYY-MM}/
	uploadDir := filepath.Join("/var/www/liquorpro/uploads/product-images", tenantID.String(), yearMonth)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create upload directory: %w", err)
	}

	// Save file to disk
	destPath := filepath.Join(uploadDir, filename)
	if err := os.WriteFile(destPath, imageBytes, 0644); err != nil {
		return "", fmt.Errorf("failed to save image file: %w", err)
	}

	// Generate URL for the saved image
	relativePath := fmt.Sprintf("/uploads/product-images/%s/%s/%s", tenantID.String(), yearMonth, filename)
	imageURL := fmt.Sprintf("https://new.v2.floelife.in%s", relativePath)

	return imageURL, nil
}

// getStockLevels gets stock levels for products (all shops)
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

// getStockLevelsForShop gets stock levels for products filtered by shop
func (s *ProductService) getStockLevelsForShop(tenantID uuid.UUID, shopID uuid.UUID, products []models.Product) map[uuid.UUID]int {
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

	query := s.db.Model(&models.Stock{}).
		Select("product_id, COALESCE(SUM(quantity), 0) as total").
		Where("product_id IN ? AND tenant_id = ?", productIDs, tenantID)

	// Filter by shop if provided
	if shopID != uuid.Nil {
		query = query.Where("shop_id = ?", shopID)
	}

	query.Group("product_id").Scan(&stockLevels)

	for _, sl := range stockLevels {
		stockMap[sl.ProductID] = sl.Total
	}

	return stockMap
}

// clearProductCache clears product-related cache including sizes cache
func (s *ProductService) clearProductCache(ctx context.Context, tenantID uuid.UUID) {
	// Clear main products cache
	cacheKey := fmt.Sprintf("products:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Clear sizes cache (products change affects sizes)
	sizesKey := fmt.Sprintf("sizes:%s", tenantID.String())
	s.cache.Delete(ctx, sizesKey)

	// Note: Category-specific sizes caches (sizes:{tenant}:{category}) will expire naturally
	// A full cache clear would require tracking all category IDs, which adds complexity
}

// clearBrandCache clears brand-related cache
func (s *ProductService) clearBrandCache(ctx context.Context, tenantID uuid.UUID) {
	cacheKey := fmt.Sprintf("brands:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)
}

// Product Template Management

// GetProductTemplates returns filtered product templates for the catalog
func (s *ProductService) GetProductTemplates(ctx context.Context, tenantID uuid.UUID, categoryID, subcategoryID, brandID, search string) ([]*models.ProductTemplate, error) {
	query := s.db.Model(&models.ProductTemplate{})

	// Filter by tenant through category relationship
	query = query.Joins("JOIN categories ON product_templates.category_id = categories.id").
		Where("categories.tenant_id = ?", tenantID)

	// Apply filters
	if categoryID != "" {
		if catUUID, err := uuid.Parse(categoryID); err == nil {
			query = query.Where("product_templates.category_id = ?", catUUID)
		}
	}

	if subcategoryID != "" {
		if subUUID, err := uuid.Parse(subcategoryID); err == nil {
			query = query.Where("product_templates.subcategory_id = ?", subUUID)
		}
	}

	if brandID != "" {
		if brandUUID, err := uuid.Parse(brandID); err == nil {
			query = query.Where("product_templates.brand_id = ?", brandUUID)
		}
	}

	if search != "" {
		query = query.Where("product_templates.name ILIKE ?", "%"+search+"%")
	}

	// Only active templates
	query = query.Where("product_templates.is_active = ?", true)

	// Include relationships
	query = query.Preload("Category").Preload("Subcategory").Preload("Brand")

	// Order by sort order and name
	query = query.Order("product_templates.sort_order ASC, product_templates.name ASC")

	var templates []*models.ProductTemplate
	if err := query.Find(&templates).Error; err != nil {
		return nil, fmt.Errorf("failed to get product templates: %w", err)
	}

	return templates, nil
}

// GetSubcategories returns subcategories for a category
func (s *ProductService) GetSubcategories(ctx context.Context, tenantID, categoryID uuid.UUID) ([]*models.Subcategory, error) {
	var subcategories []*models.Subcategory

	err := s.db.Where("tenant_id = ? AND category_id = ? AND is_active = ?", tenantID, categoryID, true).
		Order("sort_order ASC, name ASC").
		Find(&subcategories).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get subcategories: %w", err)
	}

	return subcategories, nil
}

// BatchValidateItem represents a single item to validate
type BatchValidateItem struct {
	ProductID uuid.UUID `json:"product_id"`
	Quantity  int       `json:"quantity"`
}

// BatchValidateRequest represents a batch validation request
type BatchValidateRequest struct {
	ShopID uuid.UUID           `json:"shop_id" binding:"required"`
	Items  []BatchValidateItem `json:"items" binding:"required,min=1"`
}

// ValidatedItem represents a validated product item
type ValidatedItem struct {
	ProductID    uuid.UUID `json:"product_id"`
	ProductName  string    `json:"product_name"`
	BrandName    string    `json:"brand_name"`
	Size         string    `json:"size"`
	UnitPrice    float64   `json:"unit_price"`
	CurrentStock int       `json:"current_stock"`
	IsValid      bool      `json:"is_valid"`
	Error        string    `json:"error,omitempty"`
}

// BatchValidateResponse represents the batch validation response
type BatchValidateResponse struct {
	Valid  bool            `json:"valid"`
	Items  []ValidatedItem `json:"items"`
	Errors []string        `json:"errors,omitempty"`
}

// BatchValidateProducts validates multiple products and their stock levels in a single call
// This reduces API calls from N (one per product) to 1 (batch validation)
func (s *ProductService) BatchValidateProducts(ctx context.Context, tenantID uuid.UUID, req BatchValidateRequest) (*BatchValidateResponse, error) {
	response := &BatchValidateResponse{
		Valid:  true,
		Items:  make([]ValidatedItem, 0, len(req.Items)),
		Errors: make([]string, 0),
	}

	if len(req.Items) == 0 {
		return response, nil
	}

	// Collect all product IDs
	productIDs := make([]uuid.UUID, len(req.Items))
	quantityMap := make(map[uuid.UUID]int)
	for i, item := range req.Items {
		productIDs[i] = item.ProductID
		quantityMap[item.ProductID] = item.Quantity
	}

	// Fetch all products in a single query
	var products []models.Product
	if err := s.db.Where("id IN ? AND tenant_id = ?", productIDs, tenantID).
		Preload("Brand").
		Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch products: %w", err)
	}

	// Create a map of found products
	productMap := make(map[uuid.UUID]models.Product)
	for _, p := range products {
		productMap[p.ID] = p
	}

	// Fetch all stock levels for these products in the specified shop in a single query
	var stockLevels []struct {
		ProductID uuid.UUID
		Quantity  int
	}
	s.db.Model(&models.Stock{}).
		Select("product_id, COALESCE(quantity, 0) as quantity").
		Where("product_id IN ? AND shop_id = ? AND tenant_id = ?", productIDs, req.ShopID, tenantID).
		Scan(&stockLevels)

	// Create stock map
	stockMap := make(map[uuid.UUID]int)
	for _, sl := range stockLevels {
		stockMap[sl.ProductID] = sl.Quantity
	}

	// Validate each item
	for _, item := range req.Items {
		validatedItem := ValidatedItem{
			ProductID: item.ProductID,
			IsValid:   true,
		}

		// Check if product exists
		product, exists := productMap[item.ProductID]
		if !exists {
			validatedItem.IsValid = false
			validatedItem.Error = "Product not found"
			response.Valid = false
			response.Errors = append(response.Errors, fmt.Sprintf("Product %s not found", item.ProductID))
		} else {
			validatedItem.ProductName = product.Name
			validatedItem.Size = product.Size
			validatedItem.UnitPrice = product.SellingPrice
			if product.Brand != nil {
				validatedItem.BrandName = product.Brand.Name
			}

			// Check if product is active
			if !product.IsActive {
				validatedItem.IsValid = false
				validatedItem.Error = "Product is inactive"
				response.Valid = false
				response.Errors = append(response.Errors, fmt.Sprintf("Product %s is inactive", product.Name))
			}
		}

		// Check stock level
		currentStock := stockMap[item.ProductID]
		validatedItem.CurrentStock = currentStock

		if item.Quantity > currentStock {
			validatedItem.IsValid = false
			if validatedItem.Error != "" {
				validatedItem.Error += "; "
			}
			validatedItem.Error += fmt.Sprintf("Insufficient stock: requested %d, available %d", item.Quantity, currentStock)
			response.Valid = false
			response.Errors = append(response.Errors, fmt.Sprintf("Insufficient stock for %s: requested %d, available %d",
				validatedItem.ProductName, item.Quantity, currentStock))
		}

		response.Items = append(response.Items, validatedItem)
	}

	return response, nil
}

// SizeInfo represents a size option with product count and total stock
type SizeInfo struct {
	Size         string `json:"size"`
	ProductCount int64  `json:"product_count"`
	TotalStock   int64  `json:"total_stock"`
}

// GetProductsByIDsRequest represents the request for fetching products by IDs
type GetProductsByIDsRequest struct {
	IDs    []uuid.UUID `json:"ids" binding:"required"`
	ShopID *uuid.UUID  `json:"shop_id"`
}

// ProductWithStockResponse represents a product with optional stock data
type ProductWithStockResponse struct {
	*ProductResponse
	Stock *StockInfo `json:"stock,omitempty"`
}

// StockInfo represents stock information for a product
type StockInfo struct {
	Quantity int       `json:"quantity"`
	ShopID   uuid.UUID `json:"shop_id"`
}

// GetProductsByIDs fetches multiple products by their IDs in a single query
// This is more efficient than multiple individual GetProductByID calls
func (s *ProductService) GetProductsByIDs(ctx context.Context, tenantID uuid.UUID, productIDs []uuid.UUID, shopID *uuid.UUID) ([]*ProductWithStockResponse, error) {
	if len(productIDs) == 0 {
		return []*ProductWithStockResponse{}, nil
	}

	// Fetch all products in a single query
	var products []models.Product
	if err := s.db.Where("id IN ? AND tenant_id = ? AND is_active = true", productIDs, tenantID).
		Preload("Category").
		Preload("Subcategory").
		Preload("Brand").
		Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch products: %w", err)
	}

	// Get stock levels - either for specific shop or all shops
	var stockMap map[uuid.UUID]int
	var shopStockMap map[uuid.UUID]uuid.UUID // maps productID to shopID

	if shopID != nil && *shopID != uuid.Nil {
		// Get shop-specific stock
		var stockLevels []struct {
			ProductID uuid.UUID
			Quantity  int
			ShopID    uuid.UUID
		}
		s.db.Model(&models.Stock{}).
			Select("product_id, COALESCE(quantity, 0) as quantity, shop_id").
			Where("product_id IN ? AND shop_id = ? AND tenant_id = ?", productIDs, *shopID, tenantID).
			Scan(&stockLevels)

		stockMap = make(map[uuid.UUID]int)
		shopStockMap = make(map[uuid.UUID]uuid.UUID)
		for _, sl := range stockLevels {
			stockMap[sl.ProductID] = sl.Quantity
			shopStockMap[sl.ProductID] = sl.ShopID
		}
	} else {
		// Get total stock across all shops
		stockMap = s.getStockLevels(tenantID, products)
	}

	// Build SaaS category/subcategory lookup maps
	saasCategoryMap, saasSubcategoryMap := s.getSaaSCategoryMaps()

	// Convert to response format
	responses := make([]*ProductWithStockResponse, len(products))
	for i, product := range products {
		stock := stockMap[product.ID]
		productResponse := s.mapProductToResponseWithSaaS(&product, stock, saasCategoryMap, saasSubcategoryMap)

		response := &ProductWithStockResponse{
			ProductResponse: productResponse,
		}

		// Add shop-specific stock info if shop was provided
		if shopID != nil && *shopID != uuid.Nil {
			response.Stock = &StockInfo{
				Quantity: stockMap[product.ID],
				ShopID:   *shopID,
			}
		}

		responses[i] = response
	}

	return responses, nil
}

// Cache TTL for sizes (5 minutes - sizes rarely change)
const sizesCacheTTL = 5 * time.Minute

// GetDistinctSizes returns all distinct sizes for a tenant, filtered by category
// Shows ALL sizes in catalog regardless of stock status, so users can add stock to products with 0 stock
// If shopID is provided, returns total_stock for that specific shop; otherwise returns total across all shops
// Results are cached for 5 minutes to reduce database load
func (s *ProductService) GetDistinctSizes(ctx context.Context, tenantID uuid.UUID, categoryID *uuid.UUID, shopID *uuid.UUID) ([]SizeInfo, error) {
	// Build cache key including shopID
	cacheKey := fmt.Sprintf("sizes:%s", tenantID.String())
	if categoryID != nil {
		cacheKey = fmt.Sprintf("%s:cat:%s", cacheKey, categoryID.String())
	}
	if shopID != nil {
		cacheKey = fmt.Sprintf("%s:shop:%s", cacheKey, shopID.String())
	}

	// Try to get from cache first
	var cachedSizes []SizeInfo
	if err := s.cache.Get(ctx, cacheKey, &cachedSizes); err == nil {
		return cachedSizes, nil
	}

	var sizes []SizeInfo

	// Build query to get ALL sizes in catalog with stock totals
	// Join with stocks table to get total quantity
	query := s.db.Model(&models.Product{}).
		Select("UPPER(products.size) as size, COUNT(DISTINCT products.id) as product_count, COALESCE(SUM(stocks.quantity), 0) as total_stock").
		Joins("LEFT JOIN stocks ON stocks.product_id = products.id AND stocks.deleted_at IS NULL").
		Where("products.tenant_id = ? AND products.deleted_at IS NULL AND products.size IS NOT NULL AND products.size <> ''", tenantID)

	// Filter by category if provided
	if categoryID != nil {
		query = query.Where("products.category_id = ?", *categoryID)
	}

	// Filter stocks by shop if provided
	if shopID != nil {
		query = query.Where("(stocks.shop_id = ? OR stocks.shop_id IS NULL)", *shopID)
	}

	// Get all sizes in catalog with stock totals
	err := query.Group("UPPER(products.size)").
		Order("size ASC").
		Scan(&sizes).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get distinct sizes: %w", err)
	}

	// Cache the result
	_ = s.cache.Set(ctx, cacheKey, sizes, sizesCacheTTL)

	return sizes, nil
}

// GetDistinctSizesMultiCategory returns all distinct sizes for a tenant, filtered by multiple categories
// Shows ALL sizes in catalog regardless of stock status, so users can add stock to products with 0 stock
// If shopID is provided, returns total_stock for that specific shop; otherwise returns total across all shops
// Results are cached for 5 minutes to reduce database load
func (s *ProductService) GetDistinctSizesMultiCategory(ctx context.Context, tenantID uuid.UUID, categoryIDs []uuid.UUID, shopID *uuid.UUID) ([]SizeInfo, error) {
	// Build cache key including all category IDs and shopID
	cacheKey := fmt.Sprintf("sizes:%s", tenantID.String())
	if len(categoryIDs) > 0 {
		catIDStrs := make([]string, len(categoryIDs))
		for i, catID := range categoryIDs {
			catIDStrs[i] = catID.String()
		}
		cacheKey = fmt.Sprintf("%s:cats:%s", cacheKey, strings.Join(catIDStrs, "_"))
	}
	if shopID != nil {
		cacheKey = fmt.Sprintf("%s:shop:%s", cacheKey, shopID.String())
	}

	// Try to get from cache first
	var cachedSizes []SizeInfo
	if err := s.cache.Get(ctx, cacheKey, &cachedSizes); err == nil {
		return cachedSizes, nil
	}

	var sizes []SizeInfo

	// Build query to get ALL sizes in catalog with stock totals
	// Join with stocks table to get total quantity
	// IMPORTANT: Shop filter must be in JOIN condition (not WHERE) to preserve LEFT JOIN behavior
	// Otherwise products with stock in other shops but not the requested shop would be excluded
	var query *gorm.DB
	if shopID != nil {
		// Filter stocks by shop IN the JOIN condition to preserve all products
		query = s.db.Model(&models.Product{}).
			Select("UPPER(products.size) as size, COUNT(DISTINCT products.id) as product_count, COALESCE(SUM(stocks.quantity), 0) as total_stock").
			Joins("LEFT JOIN stocks ON stocks.product_id = products.id AND stocks.deleted_at IS NULL AND stocks.shop_id = ?", *shopID).
			Where("products.tenant_id = ? AND products.deleted_at IS NULL AND products.size IS NOT NULL AND products.size <> ''", tenantID)
	} else {
		query = s.db.Model(&models.Product{}).
			Select("UPPER(products.size) as size, COUNT(DISTINCT products.id) as product_count, COALESCE(SUM(stocks.quantity), 0) as total_stock").
			Joins("LEFT JOIN stocks ON stocks.product_id = products.id AND stocks.deleted_at IS NULL").
			Where("products.tenant_id = ? AND products.deleted_at IS NULL AND products.size IS NOT NULL AND products.size <> ''", tenantID)
	}

	// Filter by multiple categories if provided (using IN clause)
	if len(categoryIDs) > 0 {
		query = query.Where("products.category_id IN ?", categoryIDs)
	}

	// Get all sizes in catalog with stock totals
	err := query.Group("UPPER(products.size)").
		Order("size ASC").
		Scan(&sizes).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get distinct sizes: %w", err)
	}

	// Cache the result
	_ = s.cache.Set(ctx, cacheKey, sizes, sizesCacheTTL)

	return sizes, nil
}
