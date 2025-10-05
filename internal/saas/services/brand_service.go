package services

import (
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	sharedModels "github.com/liquorpro/go-backend/pkg/shared/models"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// BrandService handles brand management for SaaS admin
type BrandService struct {
	db              *gorm.DB
	cache           *cache.Cache
	config          *config.Config
	inventoryClient *InventoryClient
	logger          *zap.Logger
}

// NewBrandService creates a new brand service
func NewBrandService(db *gorm.DB, cache *cache.Cache, config *config.Config, logger *zap.Logger) *BrandService {
	inventoryClient := NewInventoryClient(config, logger)

	return &BrandService{
		db:              db,
		cache:           cache,
		config:          config,
		inventoryClient: inventoryClient,
		logger:          logger,
	}
}

// GetDB returns the database connection for use in handlers
func (s *BrandService) GetDB() *gorm.DB {
	return s.db
}

// Brand request/response structures
type CreateBrandRequest struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	Picture     string `json:"picture"`
	IsActive    bool   `json:"is_active"`
	SortOrder   int    `json:"sort_order"`
}

type CreateBrandVariantRequest struct {
	BrandID        uuid.UUID  `json:"brand_id" binding:"required"`
	CategoryID     uuid.UUID  `json:"category_id" binding:"required"`
	SubcategoryID  *uuid.UUID `json:"subcategory_id"`
	Size           string     `json:"size" binding:"required"`
	AlcoholContent float64    `json:"alcohol_content"`
	Picture        string     `json:"picture"`
	GovernmentDuty float64    `json:"government_duty"`
	BuyingPrice    float64    `json:"buying_price"`
	SellingPrice   float64    `json:"selling_price"`
	MRP            float64    `json:"mrp"`
	Description    string     `json:"description"`
	Barcode        string     `json:"barcode"`
	HSNCode        string     `json:"hsn_code"`
	IsActive       bool       `json:"is_active"`
	SortOrder      int        `json:"sort_order"`
}

type BrandResponse struct {
	ID            uuid.UUID              `json:"id"`
	Name          string                 `json:"name"`
	Description   string                 `json:"description"`
	Picture       string                 `json:"picture"`
	IsActive      bool                   `json:"is_active"`
	SortOrder     int                    `json:"sort_order"`
	BrandVariants []BrandVariantResponse `json:"brand_variants,omitempty"`
	CreatedAt     interface{}            `json:"created_at"`
	UpdatedAt     interface{}            `json:"updated_at"`
}

type BrandVariantResponse struct {
	ID             uuid.UUID                `json:"id"`
	BrandID        uuid.UUID                `json:"brand_id"`
	CategoryID     uuid.UUID                `json:"category_id"`
	SubcategoryID  *uuid.UUID               `json:"subcategory_id"`
	Size           string                   `json:"size"`
	AlcoholContent float64                  `json:"alcohol_content"`
	Picture        string                   `json:"picture"`
	GovernmentDuty float64                  `json:"government_duty"`
	BuyingPrice    float64                  `json:"buying_price"`
	SellingPrice   float64                  `json:"selling_price"`
	MRP            float64                  `json:"mrp"`
	Description    string                   `json:"description"`
	Barcode        string                   `json:"barcode"`
	HSNCode        string                   `json:"hsn_code"`
	IsActive       bool                     `json:"is_active"`
	SortOrder      int                      `json:"sort_order"`
	Category       *models.BrandCategory    `json:"category,omitempty"`
	Subcategory    *models.BrandSubcategory `json:"subcategory,omitempty"`
	CreatedAt      interface{}              `json:"created_at"`
	UpdatedAt      interface{}              `json:"updated_at"`
}

type TenantBrandSelectionRequest struct {
	TenantID   uuid.UUID   `json:"tenant_id" binding:"required"`
	BrandIDs   []uuid.UUID `json:"brand_ids" binding:"required"`
	VariantIDs []uuid.UUID `json:"variant_ids"`
}

type CreateBrandCategoryRequest struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active"`
	SortOrder   int    `json:"sort_order"`
}

type CreateBrandSubcategoryRequest struct {
	Name        string    `json:"name" binding:"required"`
	CategoryID  uuid.UUID `json:"category_id" binding:"required"`
	Description string    `json:"description"`
	IsActive    bool      `json:"is_active"`
	SortOrder   int       `json:"sort_order"`
}

type BrandCategoryResponse struct {
	ID          uuid.UUID   `json:"id"`
	Name        string      `json:"name"`
	Description string      `json:"description"`
	IsActive    bool        `json:"is_active"`
	SortOrder   int         `json:"sort_order"`
	CreatedAt   interface{} `json:"created_at"`
	UpdatedAt   interface{} `json:"updated_at"`
}

type BrandSubcategoryResponse struct {
	ID          uuid.UUID   `json:"id"`
	Name        string      `json:"name"`
	CategoryID  uuid.UUID   `json:"category_id"`
	Description string      `json:"description"`
	IsActive    bool        `json:"is_active"`
	SortOrder   int         `json:"sort_order"`
	CreatedAt   interface{} `json:"created_at"`
	UpdatedAt   interface{} `json:"updated_at"`
}

// Bulk tenant brand assignment structures
type BulkTenantBrandAssignmentRequest struct {
	TenantIDs  []uuid.UUID `json:"tenant_ids" binding:"required"`
	BrandIDs   []uuid.UUID `json:"brand_ids" binding:"required"`
	VariantIDs []uuid.UUID `json:"variant_ids"`
}

type BulkAssignmentResult struct {
	SuccessfulAssignments int                      `json:"successful_assignments"`
	FailedAssignments     int                      `json:"failed_assignments"`
	Errors                []string                 `json:"errors,omitempty"`
	TenantResults         []TenantAssignmentResult `json:"tenant_results"`
}

type TenantAssignmentResult struct {
	TenantID       uuid.UUID `json:"tenant_id"`
	Success        bool      `json:"success"`
	Error          string    `json:"error,omitempty"`
	BrandsAssigned int       `json:"brands_assigned"`
}

// Brand package structures
type TenantBrandPackageRequest struct {
	TenantID    uuid.UUID `json:"tenant_id" binding:"required"`
	PackageType string    `json:"package_type" binding:"required"` // "starter", "premium", "full"
}

type BrandPackageResponse struct {
	PackageType  string          `json:"package_type"`
	Name         string          `json:"name"`
	Description  string          `json:"description"`
	BrandCount   int             `json:"brand_count"`
	VariantCount int             `json:"variant_count"`
	BrandIDs     []uuid.UUID     `json:"brand_ids"`
	VariantIDs   []uuid.UUID     `json:"variant_ids"`
	Brands       []BrandResponse `json:"brands,omitempty"`
}

// Tenant onboarding statistics
type TenantOnboardingStatsResponse struct {
	TotalTenants           int                    `json:"total_tenants"`
	TenantsWithBrands      int                    `json:"tenants_with_brands"`
	TenantsWithoutBrands   int                    `json:"tenants_without_brands"`
	AverageBrandsPerTenant float64                `json:"average_brands_per_tenant"`
	MostPopularBrands      []BrandPopularityStats `json:"most_popular_brands"`
	PackageUsageStats      []PackageUsageStats    `json:"package_usage_stats"`
}

type BrandPopularityStats struct {
	BrandID     uuid.UUID `json:"brand_id"`
	BrandName   string    `json:"brand_name"`
	TenantCount int       `json:"tenant_count"`
	Percentage  float64   `json:"percentage"`
}

type PackageUsageStats struct {
	PackageType string  `json:"package_type"`
	UsageCount  int     `json:"usage_count"`
	Percentage  float64 `json:"percentage"`
}

// CreateBrand creates a new SaaS brand
func (s *BrandService) CreateBrand(req CreateBrandRequest) (*BrandResponse, error) {
	// Check if brand name already exists among active brands
	var existing models.SaasBrand
	if err := s.db.Where("name = ? AND is_active = ?", req.Name, true).First(&existing).Error; err == nil {
		return nil, errors.New("brand name already exists")
	}

	brand := models.SaasBrand{
		Name:        req.Name,
		Description: req.Description,
		Picture:     req.Picture,
		IsActive:    req.IsActive,
		SortOrder:   req.SortOrder,
	}

	if err := s.db.Create(&brand).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand: %w", err)
	}

	return s.toBrandResponse(brand), nil
}

// CreateBrandVariant creates a new brand variant
func (s *BrandService) CreateBrandVariant(req CreateBrandVariantRequest) (*BrandVariantResponse, error) {
	// Verify brand exists
	var brand models.SaasBrand
	if err := s.db.First(&brand, req.BrandID).Error; err != nil {
		return nil, errors.New("brand not found")
	}

	// Verify category exists
	var category models.BrandCategory
	if err := s.db.First(&category, req.CategoryID).Error; err != nil {
		return nil, errors.New("category not found")
	}

	// Verify subcategory if provided
	if req.SubcategoryID != nil {
		var subcategory models.BrandSubcategory
		if err := s.db.First(&subcategory, *req.SubcategoryID).Error; err != nil {
			return nil, errors.New("subcategory not found")
		}
	}

	variant := models.BrandVariant{
		BrandID:        req.BrandID,
		CategoryID:     req.CategoryID,
		SubcategoryID:  req.SubcategoryID,
		Size:           req.Size,
		AlcoholContent: req.AlcoholContent,
		Picture:        req.Picture,
		GovernmentDuty: req.GovernmentDuty,
		BuyingPrice:    req.BuyingPrice,
		SellingPrice:   req.SellingPrice,
		MRP:            req.MRP,
		Description:    req.Description,
		Barcode:        req.Barcode,
		HSNCode:        req.HSNCode,
		IsActive:       req.IsActive,
		SortOrder:      req.SortOrder,
	}

	if err := s.db.Create(&variant).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand variant: %w", err)
	}

	// Load relationships
	s.db.Preload("Category").Preload("Subcategory").First(&variant, variant.ID)

	return s.toBrandVariantResponse(variant), nil
}

// GetAllBrands gets all SaaS brands with variants
func (s *BrandService) GetAllBrands(includeVariants bool) ([]BrandResponse, error) {
	return s.GetAllBrandsWithFilter(includeVariants, true) // Default to active only for backward compatibility
}

// GetAllBrandsWithFilter gets SaaS brands with variants and filtering options
func (s *BrandService) GetAllBrandsWithFilter(includeVariants bool, activeOnly bool) ([]BrandResponse, error) {
	var brands []models.SaasBrand
	var query *gorm.DB

	if activeOnly {
		query = s.db.Where("is_active = ?", true)
	} else {
		// Get all brands (both active and inactive)
		query = s.db
	}

	query = query.Order("is_active DESC, sort_order ASC, name ASC")

	if includeVariants {
		if activeOnly {
			query = query.Preload("BrandVariants", "is_active = ?", true)
		} else {
			query = query.Preload("BrandVariants") // Get all variants
		}
		query = query.Preload("BrandVariants.Category").
			Preload("BrandVariants.Subcategory")
	}

	if err := query.Find(&brands).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch brands: %w", err)
	}

	var response []BrandResponse
	for _, brand := range brands {
		response = append(response, *s.toBrandResponse(brand))
	}

	return response, nil
}

// GetBrandByID gets a specific brand with variants
func (s *BrandService) GetBrandByID(brandID uuid.UUID) (*BrandResponse, error) {
	var brand models.SaasBrand
	if err := s.db.Preload("BrandVariants", "is_active = ?", true).
		Preload("BrandVariants.Category").
		Preload("BrandVariants.Subcategory").
		First(&brand, brandID).Error; err != nil {
		return nil, fmt.Errorf("brand not found: %w", err)
	}

	return s.toBrandResponse(brand), nil
}

// GetBrandVariants gets variants for a specific brand
func (s *BrandService) GetBrandVariants(brandID uuid.UUID) ([]BrandVariantResponse, error) {
	var variants []models.BrandVariant
	if err := s.db.Where("brand_id = ? AND is_active = ?", brandID, true).
		Preload("Category").
		Preload("Subcategory").
		Order("sort_order ASC, size ASC").
		Find(&variants).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch brand variants: %w", err)
	}

	var response []BrandVariantResponse
	for _, variant := range variants {
		response = append(response, *s.toBrandVariantResponse(variant))
	}

	return response, nil
}

// UpdateBrand updates a SaaS brand
func (s *BrandService) UpdateBrand(brandID uuid.UUID, req CreateBrandRequest) (*BrandResponse, error) {
	var brand models.SaasBrand
	if err := s.db.First(&brand, brandID).Error; err != nil {
		return nil, errors.New("brand not found")
	}

	// Check name uniqueness if name is changed
	if brand.Name != req.Name {
		var existing models.SaasBrand
		if err := s.db.Where("name = ? AND id != ? AND is_active = ?", req.Name, brandID, true).First(&existing).Error; err == nil {
			return nil, errors.New("brand name already exists")
		}
	}

	brand.Name = req.Name
	brand.Description = req.Description
	brand.Picture = req.Picture
	brand.IsActive = req.IsActive
	brand.SortOrder = req.SortOrder

	if err := s.db.Save(&brand).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand: %w", err)
	}

	return s.toBrandResponse(brand), nil
}

// UpdateBrandVariant updates a brand variant
func (s *BrandService) UpdateBrandVariant(variantID uuid.UUID, req CreateBrandVariantRequest) (*BrandVariantResponse, error) {
	var variant models.BrandVariant
	if err := s.db.First(&variant, variantID).Error; err != nil {
		return nil, errors.New("brand variant not found")
	}

	variant.CategoryID = req.CategoryID
	variant.SubcategoryID = req.SubcategoryID
	variant.Size = req.Size
	variant.AlcoholContent = req.AlcoholContent
	variant.Picture = req.Picture
	variant.GovernmentDuty = req.GovernmentDuty
	variant.BuyingPrice = req.BuyingPrice
	variant.SellingPrice = req.SellingPrice
	variant.MRP = req.MRP
	variant.Description = req.Description
	variant.Barcode = req.Barcode
	variant.HSNCode = req.HSNCode
	variant.IsActive = req.IsActive
	variant.SortOrder = req.SortOrder

	if err := s.db.Save(&variant).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand variant: %w", err)
	}

	// Reload with relationships
	s.db.Preload("Category").Preload("Subcategory").First(&variant, variant.ID)

	return s.toBrandVariantResponse(variant), nil
}

// DeleteBrand permanently deletes a brand from the database
func (s *BrandService) DeleteBrand(brandID uuid.UUID) error {
	var brand models.SaasBrand
	if err := s.db.First(&brand, brandID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("brand not found")
		}
		return fmt.Errorf("failed to find brand: %w", err)
	}

	// Perform cascading hard delete of related records
	// First delete all brand variants associated with this brand
	if err := s.db.Unscoped().Where("brand_id = ?", brandID).Delete(&models.BrandVariant{}).Error; err != nil {
		return fmt.Errorf("failed to delete brand variants: %w", err)
	}

	// Delete any tenant brand assignments
	if err := s.db.Unscoped().Where("brand_id = ?", brandID).Delete(&models.TenantBrand{}).Error; err != nil {
		return fmt.Errorf("failed to delete tenant brand assignments: %w", err)
	}

	// Finally delete the brand itself - permanently remove from database (using Unscoped to bypass GORM soft delete)
	if err := s.db.Unscoped().Delete(&brand).Error; err != nil {
		return fmt.Errorf("failed to delete brand: %w", err)
	}

	return nil
}

// AssignBrandsToTenant assigns selected brands to a tenant
func (s *BrandService) AssignBrandsToTenant(req TenantBrandSelectionRequest) error {
	// Verify tenant exists
	var tenant sharedModels.Tenant
	if err := s.db.First(&tenant, req.TenantID).Error; err != nil {
		return errors.New("tenant not found")
	}

	// Remove existing assignments
	if err := s.db.Where("tenant_id = ?", req.TenantID).Delete(&models.TenantBrand{}).Error; err != nil {
		return fmt.Errorf("failed to remove existing brand assignments: %w", err)
	}

	// Create new brand assignments
	for _, brandID := range req.BrandIDs {
		tenantBrand := models.TenantBrand{
			TenantID: req.TenantID,
			BrandID:  brandID,
			IsActive: true,
		}

		if err := s.db.Create(&tenantBrand).Error; err != nil {
			return fmt.Errorf("failed to assign brand %s to tenant: %w", brandID, err)
		}

		// Assign specific variants if provided
		if len(req.VariantIDs) > 0 {
			for _, variantID := range req.VariantIDs {
				// Check if this variant belongs to the current brand
				var variant models.BrandVariant
				if err := s.db.Where("id = ? AND brand_id = ?", variantID, brandID).First(&variant).Error; err == nil {
					tenantVariant := models.TenantBrandVariant{
						TenantBrandID:  tenantBrand.ID,
						BrandVariantID: variantID,
						IsActive:       true,
					}
					s.db.Create(&tenantVariant)
				}
			}
		}
	}

	// Sync assigned brands to inventory service
	if err := s.syncBrandsToInventory(req.TenantID, req.BrandIDs, req.VariantIDs); err != nil {
		// Log warning but don't fail brand assignment if inventory sync fails
		// The brands are already assigned successfully to the tenant
		s.logger.Warn("Failed to sync brands to inventory service",
			zap.Error(err),
			zap.String("tenant_id", req.TenantID.String()))
	}

	return nil
}

// syncBrandsToInventory syncs assigned brands to the inventory service
func (s *BrandService) syncBrandsToInventory(tenantID uuid.UUID, brandIDs []uuid.UUID, variantIDs []uuid.UUID) error {
	// Fetch the assigned brands with their variants
	var brands []models.SaasBrand
	if err := s.db.Where("id IN ?", brandIDs).
		Preload("BrandVariants", "is_active = ?", true).
		Preload("BrandVariants.Category").
		Find(&brands).Error; err != nil {
		return fmt.Errorf("failed to fetch assigned brands: %w", err)
	}

	// If specific variant IDs were provided, filter variants
	var filteredVariants []models.BrandVariant
	if len(variantIDs) > 0 {
		for _, brand := range brands {
			for _, variant := range brand.BrandVariants {
				for _, variantID := range variantIDs {
					if variant.ID == variantID {
						filteredVariants = append(filteredVariants, variant)
						break
					}
				}
			}
		}
	} else {
		// Use all variants from assigned brands
		for _, brand := range brands {
			filteredVariants = append(filteredVariants, brand.BrandVariants...)
		}
	}

	// Prepare sync data
	syncRequest := s.inventoryClient.PrepareBrandSyncData(tenantID, brands, filteredVariants)

	// Sync to inventory service
	if err := s.inventoryClient.SyncBrandsToInventory(syncRequest); err != nil {
		return fmt.Errorf("failed to sync brands to inventory: %w", err)
	}

	return nil
}

// GetTenantBrands gets brands assigned to a tenant
func (s *BrandService) GetTenantBrands(tenantID uuid.UUID) ([]BrandResponse, error) {
	var tenantBrands []models.TenantBrand
	if err := s.db.Where("tenant_id = ? AND is_active = ?", tenantID, true).
		Preload("Brand").
		Preload("Brand.BrandVariants", "is_active = ?", true).
		Preload("Brand.BrandVariants.Category").
		Preload("Brand.BrandVariants.Subcategory").
		Preload("TenantBrandVariants.BrandVariant").
		Find(&tenantBrands).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch tenant brands: %w", err)
	}

	var response []BrandResponse
	for _, tenantBrand := range tenantBrands {
		if tenantBrand.Brand != nil {
			response = append(response, *s.toBrandResponse(*tenantBrand.Brand))
		}
	}

	return response, nil
}

// CreateBrandCategory creates a new brand category
func (s *BrandService) CreateBrandCategory(req CreateBrandCategoryRequest) (*BrandCategoryResponse, error) {
	// Check if category name already exists among active categories
	var existing models.BrandCategory
	if err := s.db.Where("name = ? AND is_active = ?", req.Name, true).First(&existing).Error; err == nil {
		return nil, errors.New("category name already exists")
	}

	category := models.BrandCategory{
		Name:        req.Name,
		Description: req.Description,
		IsActive:    req.IsActive,
		SortOrder:   req.SortOrder,
	}

	if err := s.db.Create(&category).Error; err != nil {
		return nil, fmt.Errorf("failed to create category: %w", err)
	}

	return &BrandCategoryResponse{
		ID:          category.ID,
		Name:        category.Name,
		Description: category.Description,
		IsActive:    category.IsActive,
		SortOrder:   category.SortOrder,
		CreatedAt:   category.CreatedAt,
		UpdatedAt:   category.UpdatedAt,
	}, nil
}

// CreateBrandSubcategory creates a new brand subcategory
func (s *BrandService) CreateBrandSubcategory(req CreateBrandSubcategoryRequest) (*BrandSubcategoryResponse, error) {
	// Verify category exists
	var category models.BrandCategory
	if err := s.db.First(&category, req.CategoryID).Error; err != nil {
		return nil, errors.New("category not found")
	}

	// Check if subcategory name already exists for this category among active subcategories
	var existing models.BrandSubcategory
	if err := s.db.Where("name = ? AND category_id = ? AND is_active = ?", req.Name, req.CategoryID, true).First(&existing).Error; err == nil {
		return nil, errors.New("subcategory name already exists for this category")
	}

	subcategory := models.BrandSubcategory{
		Name:        req.Name,
		CategoryID:  req.CategoryID,
		Description: req.Description,
		IsActive:    req.IsActive,
		SortOrder:   req.SortOrder,
	}

	if err := s.db.Create(&subcategory).Error; err != nil {
		return nil, fmt.Errorf("failed to create subcategory: %w", err)
	}

	return &BrandSubcategoryResponse{
		ID:          subcategory.ID,
		Name:        subcategory.Name,
		CategoryID:  subcategory.CategoryID,
		Description: subcategory.Description,
		IsActive:    subcategory.IsActive,
		SortOrder:   subcategory.SortOrder,
		CreatedAt:   subcategory.CreatedAt,
		UpdatedAt:   subcategory.UpdatedAt,
	}, nil
}

// Helper functions
func (s *BrandService) toBrandResponse(brand models.SaasBrand) *BrandResponse {
	resp := &BrandResponse{
		ID:          brand.ID,
		Name:        brand.Name,
		Description: brand.Description,
		Picture:     brand.Picture,
		IsActive:    brand.IsActive,
		SortOrder:   brand.SortOrder,
		CreatedAt:   brand.CreatedAt,
		UpdatedAt:   brand.UpdatedAt,
	}

	for _, variant := range brand.BrandVariants {
		resp.BrandVariants = append(resp.BrandVariants, *s.toBrandVariantResponse(variant))
	}

	return resp
}

func (s *BrandService) toBrandVariantResponse(variant models.BrandVariant) *BrandVariantResponse {
	return &BrandVariantResponse{
		ID:             variant.ID,
		BrandID:        variant.BrandID,
		CategoryID:     variant.CategoryID,
		SubcategoryID:  variant.SubcategoryID,
		Size:           variant.Size,
		AlcoholContent: variant.AlcoholContent,
		Picture:        variant.Picture,
		GovernmentDuty: variant.GovernmentDuty,
		BuyingPrice:    variant.BuyingPrice,
		SellingPrice:   variant.SellingPrice,
		MRP:            variant.MRP,
		Description:    variant.Description,
		Barcode:        variant.Barcode,
		HSNCode:        variant.HSNCode,
		IsActive:       variant.IsActive,
		SortOrder:      variant.SortOrder,
		Category:       variant.Category,
		Subcategory:    variant.Subcategory,
		CreatedAt:      variant.CreatedAt,
		UpdatedAt:      variant.UpdatedAt,
	}
}

// GetAllBrandCategories retrieves all brand categories
func (s *BrandService) GetAllBrandCategories() ([]BrandCategoryResponse, error) {
	var categories []models.BrandCategory

	if err := s.db.Where("is_active = ?", true).Order("sort_order ASC, name ASC").Find(&categories).Error; err != nil {
		return nil, fmt.Errorf("failed to get brand categories: %w", err)
	}

	var responses []BrandCategoryResponse
	for _, category := range categories {
		responses = append(responses, *s.toBrandCategoryResponse(category))
	}

	return responses, nil
}

// GetBrandSubcategories retrieves brand subcategories, optionally filtered by category
func (s *BrandService) GetBrandSubcategories(categoryID string) ([]BrandSubcategoryResponse, error) {
	var subcategories []models.BrandSubcategory

	query := s.db.Where("is_active = ?", true)
	if categoryID != "" {
		if _, err := uuid.Parse(categoryID); err != nil {
			return nil, fmt.Errorf("invalid category ID format: %w", err)
		}
		query = query.Where("category_id = ?", categoryID)
	}

	if err := query.Order("sort_order ASC, name ASC").Find(&subcategories).Error; err != nil {
		return nil, fmt.Errorf("failed to get brand subcategories: %w", err)
	}

	var responses []BrandSubcategoryResponse
	for _, subcategory := range subcategories {
		responses = append(responses, *s.toBrandSubcategoryResponse(subcategory))
	}

	return responses, nil
}

// toBrandCategoryResponse converts a models.BrandCategory to BrandCategoryResponse
func (s *BrandService) toBrandCategoryResponse(category models.BrandCategory) *BrandCategoryResponse {
	return &BrandCategoryResponse{
		ID:          category.ID,
		Name:        category.Name,
		Description: category.Description,
		IsActive:    category.IsActive,
		SortOrder:   category.SortOrder,
		CreatedAt:   category.CreatedAt,
		UpdatedAt:   category.UpdatedAt,
	}
}

// toBrandSubcategoryResponse converts a models.BrandSubcategory to BrandSubcategoryResponse
func (s *BrandService) toBrandSubcategoryResponse(subcategory models.BrandSubcategory) *BrandSubcategoryResponse {
	return &BrandSubcategoryResponse{
		ID:          subcategory.ID,
		CategoryID:  subcategory.CategoryID,
		Name:        subcategory.Name,
		Description: subcategory.Description,
		IsActive:    subcategory.IsActive,
		SortOrder:   subcategory.SortOrder,
		CreatedAt:   subcategory.CreatedAt,
		UpdatedAt:   subcategory.UpdatedAt,
	}
}

// DeleteBrandVariant soft deletes a brand variant by setting is_active to false
func (s *BrandService) DeleteBrandVariant(variantID uuid.UUID) error {
	var variant models.BrandVariant
	if err := s.db.First(&variant, variantID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("brand variant not found")
		}
		return fmt.Errorf("failed to find brand variant: %w", err)
	}

	// Soft delete by setting is_active to false
	if err := s.db.Model(&variant).Update("is_active", false).Error; err != nil {
		return fmt.Errorf("failed to delete brand variant: %w", err)
	}

	return nil
}

// UpdateBrandCategory updates an existing brand category
func (s *BrandService) UpdateBrandCategory(categoryID uuid.UUID, req CreateBrandCategoryRequest) (*BrandCategoryResponse, error) {
	var category models.BrandCategory
	if err := s.db.First(&category, categoryID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("brand category not found")
		}
		return nil, fmt.Errorf("failed to find brand category: %w", err)
	}

	// Check if another active category with the same name exists (excluding current one)
	var existing models.BrandCategory
	if err := s.db.Where("name = ? AND id != ? AND is_active = ?", req.Name, categoryID, true).First(&existing).Error; err == nil {
		return nil, errors.New("category name already exists")
	}

	// Update category
	category.Name = req.Name
	category.Description = req.Description
	category.IsActive = req.IsActive
	category.SortOrder = req.SortOrder

	if err := s.db.Save(&category).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand category: %w", err)
	}

	return s.toBrandCategoryResponse(category), nil
}

// DeleteBrandCategory permanently deletes a brand category from the database
func (s *BrandService) DeleteBrandCategory(categoryID uuid.UUID) error {
	var category models.BrandCategory
	if err := s.db.First(&category, categoryID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("brand category not found")
		}
		return fmt.Errorf("failed to find brand category: %w", err)
	}

	// Perform cascading hard delete of related records in correct order
	// First delete brand variants that reference subcategories of this category
	if err := s.db.Unscoped().Where("subcategory_id IN (SELECT id FROM brand_subcategories WHERE category_id = ?)", categoryID).Delete(&models.BrandVariant{}).Error; err != nil {
		return fmt.Errorf("failed to delete brand variants referencing subcategories: %w", err)
	}

	// Then delete brand variants directly associated with this category
	if err := s.db.Unscoped().Where("category_id = ?", categoryID).Delete(&models.BrandVariant{}).Error; err != nil {
		return fmt.Errorf("failed to delete brand variants: %w", err)
	}

	// Then delete all subcategories associated with this category
	if err := s.db.Unscoped().Where("category_id = ?", categoryID).Delete(&models.BrandSubcategory{}).Error; err != nil {
		return fmt.Errorf("failed to delete brand subcategories: %w", err)
	}

	// Finally delete the category itself - permanently remove from database (using Unscoped to bypass GORM soft delete)
	if err := s.db.Unscoped().Delete(&category).Error; err != nil {
		return fmt.Errorf("failed to delete brand category: %w", err)
	}

	return nil
}

// UpdateBrandSubcategory updates an existing brand subcategory
func (s *BrandService) UpdateBrandSubcategory(subcategoryID uuid.UUID, req CreateBrandSubcategoryRequest) (*BrandSubcategoryResponse, error) {
	var subcategory models.BrandSubcategory
	if err := s.db.First(&subcategory, subcategoryID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("brand subcategory not found")
		}
		return nil, fmt.Errorf("failed to find brand subcategory: %w", err)
	}

	// Verify category exists
	var category models.BrandCategory
	if err := s.db.First(&category, req.CategoryID).Error; err != nil {
		return nil, errors.New("category not found")
	}

	// Check if another active subcategory with the same name exists in the same category (excluding current one)
	var existing models.BrandSubcategory
	if err := s.db.Where("name = ? AND category_id = ? AND id != ? AND is_active = ?", req.Name, req.CategoryID, subcategoryID, true).First(&existing).Error; err == nil {
		return nil, errors.New("subcategory name already exists in this category")
	}

	// Update subcategory
	subcategory.Name = req.Name
	subcategory.CategoryID = req.CategoryID
	subcategory.Description = req.Description
	subcategory.IsActive = req.IsActive
	subcategory.SortOrder = req.SortOrder

	if err := s.db.Save(&subcategory).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand subcategory: %w", err)
	}

	return s.toBrandSubcategoryResponse(subcategory), nil
}

// DeleteBrandSubcategory soft deletes a brand subcategory by setting is_active to false
func (s *BrandService) DeleteBrandSubcategory(subcategoryID uuid.UUID) error {
	var subcategory models.BrandSubcategory
	if err := s.db.First(&subcategory, subcategoryID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("brand subcategory not found")
		}
		return fmt.Errorf("failed to find brand subcategory: %w", err)
	}

	// Check if subcategory has active variants
	var variantCount int64
	if err := s.db.Model(&models.BrandVariant{}).Where("subcategory_id = ? AND is_active = ?", subcategoryID, true).Count(&variantCount).Error; err != nil {
		return fmt.Errorf("failed to check brand variants: %w", err)
	}

	if variantCount > 0 {
		return errors.New("cannot delete subcategory with active brand variants")
	}

	// Soft delete by setting is_active to false
	if err := s.db.Model(&subcategory).Update("is_active", false).Error; err != nil {
		return fmt.Errorf("failed to delete brand subcategory: %w", err)
	}

	return nil
}

// CleanupSoftDeletedRecords permanently removes all soft-deleted brand-related records
// This function helps clean up legacy soft-deleted records that may cause unique constraint issues
func (s *BrandService) CleanupSoftDeletedRecords() error {
	// Delete in correct order to respect foreign key constraints

	// First delete tenant brand variants (leaf nodes)
	if err := s.db.Unscoped().Delete(&models.TenantBrandVariant{}, "1=1").Error; err != nil {
		return fmt.Errorf("failed to cleanup tenant brand variants: %w", err)
	}

	// Then delete tenant brands
	if err := s.db.Unscoped().Delete(&models.TenantBrand{}, "1=1").Error; err != nil {
		return fmt.Errorf("failed to cleanup tenant brands: %w", err)
	}

	// Then delete brand variants (they reference subcategories and categories)
	if err := s.db.Unscoped().Delete(&models.BrandVariant{}, "1=1").Error; err != nil {
		return fmt.Errorf("failed to cleanup brand variants: %w", err)
	}

	// Then delete brands
	if err := s.db.Unscoped().Delete(&models.SaasBrand{}, "1=1").Error; err != nil {
		return fmt.Errorf("failed to cleanup brands: %w", err)
	}

	// Then delete brand subcategories (they reference categories)
	if err := s.db.Unscoped().Delete(&models.BrandSubcategory{}, "1=1").Error; err != nil {
		return fmt.Errorf("failed to cleanup brand subcategories: %w", err)
	}

	// Finally delete brand categories (no dependencies)
	if err := s.db.Unscoped().Delete(&models.BrandCategory{}, "1=1").Error; err != nil {
		return fmt.Errorf("failed to cleanup brand categories: %w", err)
	}

	return nil
}

// BulkAssignBrandsToTenants assigns brands to multiple tenants for easier onboarding
func (s *BrandService) BulkAssignBrandsToTenants(req BulkTenantBrandAssignmentRequest) (*BulkAssignmentResult, error) {
	result := &BulkAssignmentResult{
		TenantResults: make([]TenantAssignmentResult, 0, len(req.TenantIDs)),
	}

	for _, tenantID := range req.TenantIDs {
		tenantResult := TenantAssignmentResult{
			TenantID: tenantID,
			Success:  false,
		}

		// Create individual assignment request
		assignmentReq := TenantBrandSelectionRequest{
			TenantID:   tenantID,
			BrandIDs:   req.BrandIDs,
			VariantIDs: req.VariantIDs,
		}

		// Attempt assignment
		err := s.AssignBrandsToTenant(assignmentReq)
		if err != nil {
			tenantResult.Error = err.Error()
			result.FailedAssignments++
			result.Errors = append(result.Errors, fmt.Sprintf("Tenant %s: %s", tenantID, err.Error()))
		} else {
			tenantResult.Success = true
			tenantResult.BrandsAssigned = len(req.BrandIDs)
			result.SuccessfulAssignments++
		}

		result.TenantResults = append(result.TenantResults, tenantResult)
	}

	return result, nil
}

// GetBrandPackages returns predefined brand packages for tenant onboarding
func (s *BrandService) GetBrandPackages() ([]BrandPackageResponse, error) {
	// Get all active brands and variants to create packages
	brands, err := s.GetAllBrandsWithFilter(true, true) // Include variants, active only
	if err != nil {
		return nil, fmt.Errorf("failed to fetch brands for packages: %w", err)
	}

	if len(brands) == 0 {
		return []BrandPackageResponse{}, nil
	}

	packages := []BrandPackageResponse{}

	// Starter Package (first 3 brands)
	starterBrands := brands[:min(3, len(brands))]
	starterBrandIDs := make([]uuid.UUID, 0)
	starterVariantIDs := make([]uuid.UUID, 0)
	starterVariantCount := 0

	for _, brand := range starterBrands {
		starterBrandIDs = append(starterBrandIDs, brand.ID)
		for _, variant := range brand.BrandVariants {
			starterVariantIDs = append(starterVariantIDs, variant.ID)
			starterVariantCount++
		}
	}

	packages = append(packages, BrandPackageResponse{
		PackageType:  "starter",
		Name:         "Starter Package",
		Description:  "Essential brands for new liquor stores to get started quickly",
		BrandCount:   len(starterBrands),
		VariantCount: starterVariantCount,
		BrandIDs:     starterBrandIDs,
		VariantIDs:   starterVariantIDs,
		Brands:       starterBrands,
	})

	// Premium Package (first 6 brands)
	if len(brands) > 3 {
		premiumBrands := brands[:min(6, len(brands))]
		premiumBrandIDs := make([]uuid.UUID, 0)
		premiumVariantIDs := make([]uuid.UUID, 0)
		premiumVariantCount := 0

		for _, brand := range premiumBrands {
			premiumBrandIDs = append(premiumBrandIDs, brand.ID)
			for _, variant := range brand.BrandVariants {
				premiumVariantIDs = append(premiumVariantIDs, variant.ID)
				premiumVariantCount++
			}
		}

		packages = append(packages, BrandPackageResponse{
			PackageType:  "premium",
			Name:         "Premium Package",
			Description:  "Popular brands for established stores looking to expand inventory",
			BrandCount:   len(premiumBrands),
			VariantCount: premiumVariantCount,
			BrandIDs:     premiumBrandIDs,
			VariantIDs:   premiumVariantIDs,
			Brands:       premiumBrands,
		})
	}

	// Full Package (all brands)
	allBrandIDs := make([]uuid.UUID, 0)
	allVariantIDs := make([]uuid.UUID, 0)
	allVariantCount := 0

	for _, brand := range brands {
		allBrandIDs = append(allBrandIDs, brand.ID)
		for _, variant := range brand.BrandVariants {
			allVariantIDs = append(allVariantIDs, variant.ID)
			allVariantCount++
		}
	}

	packages = append(packages, BrandPackageResponse{
		PackageType:  "full",
		Name:         "Complete Package",
		Description:  "All available brands for comprehensive inventory management",
		BrandCount:   len(brands),
		VariantCount: allVariantCount,
		BrandIDs:     allBrandIDs,
		VariantIDs:   allVariantIDs,
		Brands:       brands,
	})

	return packages, nil
}

// AssignBrandPackageToTenant assigns a preset brand package to a tenant
func (s *BrandService) AssignBrandPackageToTenant(req TenantBrandPackageRequest) error {
	packages, err := s.GetBrandPackages()
	if err != nil {
		return fmt.Errorf("failed to get brand packages: %w", err)
	}

	var selectedPackage *BrandPackageResponse
	for _, pkg := range packages {
		if pkg.PackageType == req.PackageType {
			selectedPackage = &pkg
			break
		}
	}

	if selectedPackage == nil {
		return fmt.Errorf("package type '%s' not found", req.PackageType)
	}

	// Create assignment request
	assignmentReq := TenantBrandSelectionRequest{
		TenantID:   req.TenantID,
		BrandIDs:   selectedPackage.BrandIDs,
		VariantIDs: selectedPackage.VariantIDs,
	}

	return s.AssignBrandsToTenant(assignmentReq)
}

// GetTenantOnboardingStats returns statistics about tenant brand assignments
func (s *BrandService) GetTenantOnboardingStats() (*TenantOnboardingStatsResponse, error) {
	stats := &TenantOnboardingStatsResponse{}

	// Count total tenants
	var totalTenants int64
	if err := s.db.Model(&sharedModels.Tenant{}).Count(&totalTenants).Error; err != nil {
		return nil, fmt.Errorf("failed to count total tenants: %w", err)
	}
	stats.TotalTenants = int(totalTenants)

	// Count tenants with brands
	var tenantsWithBrands int64
	if err := s.db.Model(&models.TenantBrand{}).
		Select("DISTINCT tenant_id").
		Where("is_active = ?", true).
		Count(&tenantsWithBrands).Error; err != nil {
		return nil, fmt.Errorf("failed to count tenants with brands: %w", err)
	}
	stats.TenantsWithBrands = int(tenantsWithBrands)
	stats.TenantsWithoutBrands = stats.TotalTenants - stats.TenantsWithBrands

	// Calculate average brands per tenant
	if stats.TenantsWithBrands > 0 {
		var totalBrandAssignments int64
		if err := s.db.Model(&models.TenantBrand{}).
			Where("is_active = ?", true).
			Count(&totalBrandAssignments).Error; err != nil {
			return nil, fmt.Errorf("failed to count brand assignments: %w", err)
		}
		stats.AverageBrandsPerTenant = float64(totalBrandAssignments) / float64(stats.TenantsWithBrands)
	}

	// Get most popular brands
	type BrandPopularity struct {
		BrandID     uuid.UUID `json:"brand_id"`
		BrandName   string    `json:"brand_name"`
		TenantCount int64     `json:"tenant_count"`
	}

	var popularBrands []BrandPopularity
	if err := s.db.Table("tenant_brands tb").
		Select("tb.brand_id, sb.name as brand_name, COUNT(DISTINCT tb.tenant_id) as tenant_count").
		Joins("JOIN saas_brands sb ON tb.brand_id = sb.id").
		Where("tb.is_active = ? AND sb.is_active = ?", true, true).
		Group("tb.brand_id, sb.name").
		Order("tenant_count DESC").
		Limit(5).
		Scan(&popularBrands).Error; err != nil {
		return nil, fmt.Errorf("failed to get popular brands: %w", err)
	}

	stats.MostPopularBrands = make([]BrandPopularityStats, len(popularBrands))
	for i, brand := range popularBrands {
		percentage := 0.0
		if stats.TotalTenants > 0 {
			percentage = (float64(brand.TenantCount) / float64(stats.TotalTenants)) * 100
		}
		stats.MostPopularBrands[i] = BrandPopularityStats{
			BrandID:     brand.BrandID,
			BrandName:   brand.BrandName,
			TenantCount: int(brand.TenantCount),
			Percentage:  percentage,
		}
	}

	// Package usage stats (simulated based on tenant brand counts)
	// In a real implementation, you might track which package was used for each tenant
	packageStats := []PackageUsageStats{
		{PackageType: "starter", UsageCount: 0, Percentage: 0},
		{PackageType: "premium", UsageCount: 0, Percentage: 0},
		{PackageType: "full", UsageCount: 0, Percentage: 0},
	}

	// Estimate package usage based on number of brands per tenant
	type TenantBrandCount struct {
		TenantID   uuid.UUID `json:"tenant_id"`
		BrandCount int64     `json:"brand_count"`
	}

	var tenantBrandCounts []TenantBrandCount
	if err := s.db.Table("tenant_brands").
		Select("tenant_id, COUNT(*) as brand_count").
		Where("is_active = ?", true).
		Group("tenant_id").
		Scan(&tenantBrandCounts).Error; err != nil {
		return nil, fmt.Errorf("failed to get tenant brand counts: %w", err)
	}

	for _, tbc := range tenantBrandCounts {
		if tbc.BrandCount <= 3 {
			packageStats[0].UsageCount++ // starter
		} else if tbc.BrandCount <= 6 {
			packageStats[1].UsageCount++ // premium
		} else {
			packageStats[2].UsageCount++ // full
		}
	}

	// Calculate percentages
	for i := range packageStats {
		if stats.TenantsWithBrands > 0 {
			packageStats[i].Percentage = (float64(packageStats[i].UsageCount) / float64(stats.TenantsWithBrands)) * 100
		}
	}

	stats.PackageUsageStats = packageStats

	return stats, nil
}

// Helper function for min
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
