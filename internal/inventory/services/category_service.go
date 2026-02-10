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

type CategoryService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewCategoryService(db *database.DB, cache *cache.Cache) *CategoryService {
	return &CategoryService{
		db:    db,
		cache: cache,
	}
}

type CategoryRequest struct {
	Name        string `json:"name" binding:"required,max=255"`
	Description string `json:"description"`
	IsActive    *bool  `json:"is_active"`
}

type CategoryResponse struct {
	ID           uuid.UUID          `json:"id"`
	Name         string             `json:"name"`
	Description  string             `json:"description"`
	IsActive     bool               `json:"is_active"`
	ProductCount int64              `json:"product_count"`
	Children     []CategoryResponse `json:"children,omitempty"`
}

type BrandRequest struct {
	Name        string `json:"name" binding:"required,max=255"`
	Description string `json:"description"`
	IsActive    *bool  `json:"is_active"`
}

type BrandResponse struct {
	ID           uuid.UUID `json:"id"`
	Name         string    `json:"name"`
	Description  string    `json:"description"`
	IsActive     bool      `json:"is_active"`
	ProductCount int64     `json:"product_count"`
}

// Category operations
func (s *CategoryService) CreateCategory(ctx context.Context, req CategoryRequest, tenantID, userID uuid.UUID) (*CategoryResponse, error) {
	// No parent category validation needed

	// Check if category name already exists
	var existingCategory models.Category
	err := s.db.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existingCategory).Error
	if err == nil {
		return nil, fmt.Errorf("category with this name already exists at this level")
	} else if err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to check existing category: %w", err)
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	category := models.Category{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		Name:        req.Name,
		Description: req.Description,
		IsActive:    isActive,
	}

	if err := s.db.Create(&category).Error; err != nil {
		return nil, fmt.Errorf("failed to create category: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("categories:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.buildCategoryResponse(category, "", 0), nil
}

func (s *CategoryService) GetCategories(ctx context.Context, tenantID uuid.UUID, includeInactive bool) ([]CategoryResponse, error) {
	return s.GetCategoriesWithShopFilter(ctx, tenantID, includeInactive, nil)
}

// GetCategoriesWithShopFilter returns categories, optionally filtered by shop (only categories with products that have stock in that shop)
func (s *CategoryService) GetCategoriesWithShopFilter(ctx context.Context, tenantID uuid.UUID, includeInactive bool, shopID *uuid.UUID) ([]CategoryResponse, error) {
	// Build cache key
	cacheKey := fmt.Sprintf("categories:tenant:%s:inactive:%t", tenantID.String(), includeInactive)
	if shopID != nil {
		cacheKey = fmt.Sprintf("categories:tenant:%s:inactive:%t:shop:%s", tenantID.String(), includeInactive, shopID.String())
	}

	// Try to get from cache
	var cachedCategories []CategoryResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedCategories); err == nil {
		return cachedCategories, nil
	}

	var categories []models.Category

	if shopID != nil {
		// Filter to only categories that have products (regardless of stock)
		query := s.db.Model(&models.Category{}).
			Select("DISTINCT categories.*").
			Joins("INNER JOIN products ON products.category_id = categories.id AND products.tenant_id = categories.tenant_id").
			Where("categories.tenant_id = ?", tenantID)

		if !includeInactive {
			query = query.Where("categories.is_active = ?", true)
		}

		if err := query.Order("categories.name ASC").Find(&categories).Error; err != nil {
			return nil, fmt.Errorf("failed to get categories with shop filter: %w", err)
		}
	} else {
		// Return all categories (existing behavior)
		query := s.db.Where("tenant_id = ?", tenantID)

		if !includeInactive {
			query = query.Where("is_active = ?", true)
		}

		if err := query.Order("name ASC").Find(&categories).Error; err != nil {
			return nil, fmt.Errorf("failed to get categories: %w", err)
		}
	}

	// Get product counts for all categories in one query (eliminates N+1)
	productCounts := make(map[uuid.UUID]int64)
	var countResults []struct {
		CategoryID uuid.UUID `gorm:"column:category_id"`
		Count      int64     `gorm:"column:count"`
	}
	s.db.Model(&models.Product{}).
		Select("category_id, COUNT(*) as count").
		Where("tenant_id = ?", tenantID).
		Group("category_id").
		Scan(&countResults)
	for _, cr := range countResults {
		productCounts[cr.CategoryID] = cr.Count
	}

	// Build hierarchical response
	categoryMap := make(map[uuid.UUID]*CategoryResponse)
	var rootCategories []CategoryResponse

	// First pass: create all category responses
	for _, category := range categories {
		parentName := ""

		categoryResponse := s.buildCategoryResponse(category, parentName, productCounts[category.ID])
		categoryMap[category.ID] = categoryResponse

		// All categories are root since we don't support hierarchy
		rootCategories = append(rootCategories, *categoryResponse)
	}

	// No hierarchy support needed for now

	// Update root categories with their children
	for i, rootCategory := range rootCategories {
		if categoryWithChildren, exists := categoryMap[rootCategory.ID]; exists {
			rootCategories[i] = *categoryWithChildren
		}
	}

	// Cache the result (shorter cache for shop-filtered results)
	cacheDuration := time.Duration(300) * time.Second // 5 minutes
	if shopID != nil {
		cacheDuration = time.Duration(60) * time.Second // 1 minute for shop-specific cache
	}
	s.cache.Set(ctx, cacheKey, rootCategories, cacheDuration)

	return rootCategories, nil
}

func (s *CategoryService) GetCategoryByID(ctx context.Context, id, tenantID uuid.UUID) (*CategoryResponse, error) {
	var category models.Category
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).First(&category).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("category not found")
		}
		return nil, fmt.Errorf("failed to get category: %w", err)
	}

	// Get parent name if exists
	parentName := ""

	// Get product count
	var productCount int64
	s.db.Model(&models.Product{}).Where("category_id = ? AND tenant_id = ?", id, tenantID).Count(&productCount)

	return s.buildCategoryResponse(category, parentName, productCount), nil
}

func (s *CategoryService) UpdateCategory(ctx context.Context, id uuid.UUID, req CategoryRequest, tenantID, userID uuid.UUID) (*CategoryResponse, error) {
	var category models.Category
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).First(&category).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("category not found")
		}
		return nil, fmt.Errorf("failed to get category: %w", err)
	}

	// Check if updating name would create duplicate
	if req.Name != category.Name {
		var existingCategory models.Category
		err := s.db.Where("name = ? AND tenant_id = ? AND id != ?", req.Name, tenantID, id).First(&existingCategory).Error
		if err == nil {
			return nil, fmt.Errorf("category with this name already exists at this level")
		} else if err != gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("failed to check existing category: %w", err)
		}
	}

	// No parent category validation needed

	// Update category
	updates := map[string]interface{}{
		"name":        req.Name,
		"description": req.Description,
		"updated_by":  userID,
	}

	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}

	if err := s.db.Model(&category).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update category: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("categories:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Return updated category
	return s.GetCategoryByID(ctx, id, tenantID)
}

func (s *CategoryService) DeleteCategory(ctx context.Context, id, tenantID uuid.UUID) error {
	// Check if category has products
	var productCount int64
	if err := s.db.Model(&models.Product{}).Where("category_id = ? AND tenant_id = ?", id, tenantID).Count(&productCount).Error; err != nil {
		return fmt.Errorf("failed to check products: %w", err)
	}

	if productCount > 0 {
		return fmt.Errorf("cannot delete category: %d products are assigned to this category", productCount)
	}

	// No hierarchy support - skip subcategory check

	// Delete category
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).Delete(&models.Category{}).Error; err != nil {
		return fmt.Errorf("failed to delete category: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("categories:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return nil
}

// Brand operations
func (s *CategoryService) CreateBrand(ctx context.Context, req BrandRequest, tenantID, userID uuid.UUID) (*BrandResponse, error) {
	// Check if brand name already exists
	var existingBrand models.Brand
	err := s.db.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existingBrand).Error
	if err == nil {
		return nil, fmt.Errorf("brand with this name already exists")
	} else if err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to check existing brand: %w", err)
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	brand := models.Brand{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		Name:        req.Name,
		Description: req.Description,
		IsActive:    isActive,
	}

	if err := s.db.Create(&brand).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("brands:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.buildBrandResponse(brand, 0), nil
}

func (s *CategoryService) GetBrands(ctx context.Context, tenantID uuid.UUID, includeInactive bool) ([]BrandResponse, error) {
	cacheKey := fmt.Sprintf("brands:tenant:%s:inactive:%t", tenantID.String(), includeInactive)

	// Try to get from cache
	var cachedBrands []BrandResponse
	if err := s.cache.Get(ctx, cacheKey, &cachedBrands); err == nil {
		return cachedBrands, nil
	}

	var brands []models.Brand
	query := s.db.Where("tenant_id = ?", tenantID)

	if !includeInactive {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Order("name ASC").Find(&brands).Error; err != nil {
		return nil, fmt.Errorf("failed to get brands: %w", err)
	}

	// Get product counts for all brands in one query (eliminates N+1)
	productCounts := make(map[uuid.UUID]int64)
	var countResults []struct {
		BrandID uuid.UUID `gorm:"column:brand_id"`
		Count   int64     `gorm:"column:count"`
	}
	s.db.Model(&models.Product{}).
		Select("brand_id, COUNT(*) as count").
		Where("tenant_id = ?", tenantID).
		Group("brand_id").
		Scan(&countResults)
	for _, cr := range countResults {
		productCounts[cr.BrandID] = cr.Count
	}

	var responses []BrandResponse
	for _, brand := range brands {
		response := s.buildBrandResponse(brand, productCounts[brand.ID])
		responses = append(responses, *response)
	}

	// Cache the result
	s.cache.Set(ctx, cacheKey, responses, 300) // Cache for 5 minutes

	return responses, nil
}

func (s *CategoryService) GetBrandByID(ctx context.Context, id, tenantID uuid.UUID) (*BrandResponse, error) {
	var brand models.Brand
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).First(&brand).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("brand not found")
		}
		return nil, fmt.Errorf("failed to get brand: %w", err)
	}

	// Get product count
	var productCount int64
	s.db.Model(&models.Product{}).Where("brand_id = ? AND tenant_id = ?", id, tenantID).Count(&productCount)

	return s.buildBrandResponse(brand, productCount), nil
}

func (s *CategoryService) UpdateBrand(ctx context.Context, id uuid.UUID, req BrandRequest, tenantID, userID uuid.UUID) (*BrandResponse, error) {
	var brand models.Brand
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).First(&brand).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("brand not found")
		}
		return nil, fmt.Errorf("failed to get brand: %w", err)
	}

	// Check if updating name would create duplicate
	if req.Name != brand.Name {
		var existingBrand models.Brand
		err := s.db.Where("name = ? AND tenant_id = ? AND id != ?", req.Name, tenantID, id).First(&existingBrand).Error
		if err == nil {
			return nil, fmt.Errorf("brand with this name already exists")
		} else if err != gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("failed to check existing brand: %w", err)
		}
	}

	// Update brand
	updates := map[string]interface{}{
		"name":        req.Name,
		"description": req.Description,
	}

	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}

	if err := s.db.Model(&brand).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("brands:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Return updated brand
	return s.GetBrandByID(ctx, id, tenantID)
}

func (s *CategoryService) DeleteBrand(ctx context.Context, id, tenantID uuid.UUID) error {
	// Check if brand has products
	var productCount int64
	if err := s.db.Model(&models.Product{}).Where("brand_id = ? AND tenant_id = ?", id, tenantID).Count(&productCount).Error; err != nil {
		return fmt.Errorf("failed to check products: %w", err)
	}

	if productCount > 0 {
		return fmt.Errorf("cannot delete brand: %d products are assigned to this brand", productCount)
	}

	// Delete brand
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).Delete(&models.Brand{}).Error; err != nil {
		return fmt.Errorf("failed to delete brand: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("brands:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return nil
}

// Helper functions
func (s *CategoryService) buildCategoryResponse(category models.Category, parentName string, productCount int64) *CategoryResponse {
	return &CategoryResponse{
		ID:           category.ID,
		Name:         category.Name,
		Description:  category.Description,
		IsActive:     category.IsActive,
		ProductCount: productCount,
		Children:     []CategoryResponse{},
	}
}

func (s *CategoryService) buildBrandResponse(brand models.Brand, productCount int64) *BrandResponse {
	return &BrandResponse{
		ID:           brand.ID,
		Name:         brand.Name,
		Description:  brand.Description,
		IsActive:     brand.IsActive,
		ProductCount: productCount,
	}
}
