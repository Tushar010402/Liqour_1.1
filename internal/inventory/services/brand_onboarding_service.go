package services

import (
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// BrandOnboardingService handles brand onboarding from SaaS templates
type BrandOnboardingService struct {
	db              *gorm.DB
	saasClient      *SaaSBrandClient
	productService  *ProductService
	categoryService *CategoryService
	logger          *zap.Logger

	// In-memory cache for brand catalog
	brandCache      []SaaSBrandTemplate
	cacheMutex      sync.RWMutex
	cacheExpiry     time.Time
	cacheDuration   time.Duration
}

// NewBrandOnboardingService creates a new brand onboarding service
func NewBrandOnboardingService(db *gorm.DB, config *config.Config, logger *zap.Logger) *BrandOnboardingService {
	saasServiceURL := "http://saas:8095" // SaaS service URL (Docker internal network)

	// Use default logger if not provided
	if logger == nil {
		logger, _ = zap.NewProduction()
	}

	return &BrandOnboardingService{
		db:              db,
		saasClient:      NewSaaSBrandClient(saasServiceURL, logger),
		productService:  nil, // Not needed for onboarding
		categoryService: nil, // Not needed for onboarding
		logger:          logger,
		cacheDuration:   5 * time.Minute, // Cache brands for 5 minutes
	}
}

// OnboardBrandRequest represents a request to onboard SaaS brand templates
type OnboardBrandRequest struct {
	TenantID   uuid.UUID   `json:"tenant_id" binding:"required"`
	BrandIDs   []uuid.UUID `json:"brand_ids" binding:"required"`
	VariantIDs []uuid.UUID `json:"variant_ids,omitempty"` // Optional: specific variants to onboard
}

// OnboardBrandResponse represents the response after onboarding brands
type OnboardBrandResponse struct {
	TenantID          uuid.UUID              `json:"tenant_id"`
	OnboardedBrands   int                    `json:"onboarded_brands"`
	OnboardedProducts int                    `json:"onboarded_products"`
	CategoriesCreated int                    `json:"categories_created"`
	BrandDetails      []OnboardedBrandDetail `json:"brand_details"`
	Errors            []string               `json:"errors,omitempty"`
}

type OnboardedBrandDetail struct {
	SaaSBrandID      uuid.UUID   `json:"saas_brand_id"`
	SaaSBrandName    string      `json:"saas_brand_name"`
	ProductsCreated  int         `json:"products_created"`
	ProductIDs       []uuid.UUID `json:"product_ids"`
	Success          bool        `json:"success"`
	Error            string      `json:"error,omitempty"`
}

// GetAvailableBrandTemplates returns all available SaaS brand templates with caching
func (s *BrandOnboardingService) GetAvailableBrandTemplates() ([]SaaSBrandTemplate, error) {
	// Check cache first (read lock)
	s.cacheMutex.RLock()
	if time.Now().Before(s.cacheExpiry) && len(s.brandCache) > 0 {
		cached := s.brandCache
		s.cacheMutex.RUnlock()
		s.logger.Info("Returning cached brand templates", zap.Int("count", len(cached)))
		return cached, nil
	}
	s.cacheMutex.RUnlock()

	// Cache miss or expired - fetch from SaaS service
	s.logger.Info("Cache miss - fetching brand templates from SaaS service")
	brands, err := s.saasClient.GetAllBrandTemplates(true)
	if err != nil {
		return nil, err
	}

	// Update cache (write lock)
	s.cacheMutex.Lock()
	s.brandCache = brands
	s.cacheExpiry = time.Now().Add(s.cacheDuration)
	s.cacheMutex.Unlock()

	s.logger.Info("Updated brand cache",
		zap.Int("count", len(brands)),
		zap.Time("expiry", s.cacheExpiry))

	return brands, nil
}

// ClearCache clears the brand cache (useful for testing or when brands are updated)
func (s *BrandOnboardingService) ClearCache() {
	s.cacheMutex.Lock()
	defer s.cacheMutex.Unlock()

	s.brandCache = nil
	s.cacheExpiry = time.Time{}
	s.logger.Info("Brand cache cleared")
}

// OnboardBrandsToTenant creates products in tenant's inventory from SaaS brand templates
func (s *BrandOnboardingService) OnboardBrandsToTenant(req OnboardBrandRequest) (*OnboardBrandResponse, error) {
	fmt.Printf("🚀 OnboardBrandsToTenant called: tenant=%s, brands=%d, variants=%d\n",
		req.TenantID.String(), len(req.BrandIDs), len(req.VariantIDs))

	s.logger.Info("🚀 OnboardBrandsToTenant called",
		zap.String("tenant_id", req.TenantID.String()),
		zap.Int("brand_ids_count", len(req.BrandIDs)),
		zap.Int("variant_ids_count", len(req.VariantIDs)))

	response := &OnboardBrandResponse{
		TenantID:      req.TenantID,
		BrandDetails:  make([]OnboardedBrandDetail, 0),
		Errors:        make([]string, 0),
	}

	// Track unique categories created
	createdCategories := make(map[uuid.UUID]bool)

	// Determine which brands to process
	brandIDsToProcess := req.BrandIDs

	// If only variant IDs provided, find which brands contain those variants
	if len(req.VariantIDs) > 0 && len(req.BrandIDs) == 0 {
		s.logger.Info("Variant-only onboarding requested, fetching all brands to find variants",
			zap.Int("variant_count", len(req.VariantIDs)))

		allBrands, err := s.saasClient.GetAllBrandTemplates(true)
		if err != nil {
			return nil, fmt.Errorf("failed to fetch brands for variant lookup: %w", err)
		}

		s.logger.Info("Fetched SaaS brands for variant lookup",
			zap.Int("brands_count", len(allBrands)))

		// Build map of variant ID -> brand ID
		variantToBrand := make(map[uuid.UUID]uuid.UUID)
		for _, brand := range allBrands {
			s.logger.Debug("Checking brand for variants",
				zap.String("brand_id", brand.ID.String()),
				zap.String("brand_name", brand.Name),
				zap.Int("variant_count", len(brand.BrandVariants)))

			for _, variant := range brand.BrandVariants {
				for _, requestedVariantID := range req.VariantIDs {
					if variant.ID == requestedVariantID {
						variantToBrand[variant.ID] = brand.ID
						s.logger.Info("✅ Found variant in brand",
							zap.String("variant_id", variant.ID.String()),
							zap.String("brand_id", brand.ID.String()),
							zap.String("brand_name", brand.Name))
					}
				}
			}
		}

		s.logger.Info("Variant to brand mapping complete",
			zap.Int("variants_found", len(variantToBrand)))

		// Extract unique brand IDs
		uniqueBrands := make(map[uuid.UUID]bool)
		for _, brandID := range variantToBrand {
			uniqueBrands[brandID] = true
		}

		brandIDsToProcess = make([]uuid.UUID, 0, len(uniqueBrands))
		for brandID := range uniqueBrands {
			brandIDsToProcess = append(brandIDsToProcess, brandID)
		}

		s.logger.Info("Resolved variant IDs to brands",
			zap.Int("variants_requested", len(req.VariantIDs)),
			zap.Int("variants_found", len(variantToBrand)),
			zap.Int("brands_to_process", len(brandIDsToProcess)))

		// If no brands found containing the requested variants, return error
		if len(brandIDsToProcess) == 0 {
			s.logger.Warn("No brands found containing requested variant IDs",
				zap.Strings("requested_variant_ids", func() []string {
					ids := make([]string, len(req.VariantIDs))
					for i, id := range req.VariantIDs {
						ids[i] = id.String()
					}
					return ids
				}()))
			return response, nil // Return empty response
		}
	}

	// Fetch brand templates from SaaS service
	for _, brandID := range brandIDsToProcess {
		brandDetail := OnboardedBrandDetail{
			SaaSBrandID: brandID,
			ProductIDs:  make([]uuid.UUID, 0),
		}

		brand, err := s.saasClient.GetBrandTemplate(brandID)
		if err != nil {
			brandDetail.Success = false
			brandDetail.Error = fmt.Sprintf("Failed to fetch brand template: %v", err)
			response.Errors = append(response.Errors, brandDetail.Error)
			response.BrandDetails = append(response.BrandDetails, brandDetail)
			continue
		}

		brandDetail.SaaSBrandName = brand.Name

		// Determine which variants to onboard
		variantsToOnboard := brand.BrandVariants
		if len(req.VariantIDs) > 0 {
			// Filter to only requested variants
			variantsToOnboard = make([]SaaSBrandVariant, 0)
			for _, variant := range brand.BrandVariants {
				for _, requestedVariantID := range req.VariantIDs {
					if variant.ID == requestedVariantID {
						variantsToOnboard = append(variantsToOnboard, variant)
						break
					}
				}
			}
		}

		// Ensure brand exists for tenant
		tenantBrand, err := s.ensureBrandExists(req.TenantID, brand)
		if err != nil {
			brandDetail.Success = false
			brandDetail.Error = fmt.Sprintf("Failed to create brand: %v", err)
			response.Errors = append(response.Errors, brandDetail.Error)
			response.BrandDetails = append(response.BrandDetails, brandDetail)
			continue
		}

		// Create products from variants
		for _, variant := range variantsToOnboard {
			// Check if this variant has already been onboarded for this tenant
			var existingProduct models.Product
			err := s.db.Where("tenant_id = ? AND saas_variant_id = ?", req.TenantID, variant.ID).First(&existingProduct).Error
			if err == nil {
				// Product already exists, add it to response but don't create a new one
				s.logger.Info("Variant already onboarded, returning existing product",
					zap.String("tenant_id", req.TenantID.String()),
					zap.String("variant_id", variant.ID.String()),
					zap.String("product_id", existingProduct.ID.String()))

				// Add existing product to response
				brandDetail.ProductIDs = append(brandDetail.ProductIDs, existingProduct.ID)
				// Don't increment ProductsCreated since we didn't create a new one
				continue
			}

			// Ensure category exists in tenant's inventory
			category, err := s.ensureCategoryExists(req.TenantID, variant.Category)
			if err != nil {
				s.logger.Error("Failed to ensure category exists",
					zap.Error(err),
					zap.String("category_name", variant.Category.Name))
				continue
			}

			// Track category creation
			if !createdCategories[category.ID] {
				createdCategories[category.ID] = true
			}

			// Create product from variant with correct field mapping
			tenantIDPtr := &req.TenantID
			brandIDPtr := &brand.ID
			variantIDPtr := &variant.ID
			product := models.Product{
				TenantModel: models.TenantModel{
					TenantID: tenantIDPtr,
				},
				CategoryID:     category.ID,
				BrandID:        tenantBrand.ID,
				SaaSBrandID:    brandIDPtr,   // Track SaaS brand origin
				SaaSVariantID:  variantIDPtr, // Track SaaS variant origin for duplicate prevention
				Name:           fmt.Sprintf("%s - %s", brand.Name, variant.Size),
				Description:    variant.Description,
				Barcode:        variant.Barcode,
				ImageURL:       variant.Picture, // Picture -> ImageURL
				Size:           variant.Size,
				AlcoholContent: variant.AlcoholContent,
				DutyFee:        variant.GovernmentDuty, // GovernmentDuty -> DutyFee
				CostPrice:      variant.BuyingPrice,    // BuyingPrice -> CostPrice
				TotalCost:      variant.BuyingPrice + variant.GovernmentDuty,
				SellingPrice:   variant.SellingPrice,
				MRP:            variant.MRP,
				IsActive:       variant.IsActive,
				SKU:            fmt.Sprintf("SAAS-%s-%s", brand.ID.String()[:8], variant.ID.String()[:8]),
			}

			if err := s.db.Create(&product).Error; err != nil {
				s.logger.Error("Failed to create product from variant",
					zap.Error(err),
					zap.String("variant_id", variant.ID.String()))
				continue
			}

			brandDetail.ProductIDs = append(brandDetail.ProductIDs, product.ID)
			brandDetail.ProductsCreated++
			response.OnboardedProducts++
		}

		// Consider success if we have any products (newly created or existing)
		if len(brandDetail.ProductIDs) > 0 {
			brandDetail.Success = true
			if brandDetail.ProductsCreated > 0 {
				response.OnboardedBrands++
			}
		} else {
			brandDetail.Success = false
			brandDetail.Error = "No products were found or created from this brand"
			response.Errors = append(response.Errors, fmt.Sprintf("Brand %s: %s", brand.Name, brandDetail.Error))
		}

		response.BrandDetails = append(response.BrandDetails, brandDetail)
	}

	// Set total categories created
	response.CategoriesCreated = len(createdCategories)

	fmt.Printf("📊 Response Summary:\n")
	fmt.Printf("   - Onboarded Brands: %d\n", response.OnboardedBrands)
	fmt.Printf("   - Onboarded Products: %d\n", response.OnboardedProducts)
	fmt.Printf("   - Brand Details Count: %d\n", len(response.BrandDetails))
	for i, detail := range response.BrandDetails {
		fmt.Printf("   - Brand %d: %s, Products: %d, Success: %v\n",
			i, detail.SaaSBrandName, len(detail.ProductIDs), detail.Success)
	}

	s.logger.Info("OnboardBrandsToTenant completed",
		zap.Int("onboarded_brands", response.OnboardedBrands),
		zap.Int("onboarded_products", response.OnboardedProducts),
		zap.Int("brand_details_count", len(response.BrandDetails)))

	return response, nil
}

// ensureBrandExists ensures the brand exists in tenant's inventory, creates if not
func (s *BrandOnboardingService) ensureBrandExists(tenantID uuid.UUID, saasBrand *SaaSBrandTemplate) (*models.Brand, error) {
	if saasBrand == nil {
		return nil, errors.New("brand is required")
	}

	// Check if brand already exists for this tenant
	var existingBrand models.Brand
	err := s.db.Where("tenant_id = ? AND name = ?", tenantID, saasBrand.Name).First(&existingBrand).Error

	if err == nil {
		// Brand exists
		return &existingBrand, nil
	}

	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("failed to check brand: %w", err)
	}

	// Create new brand for tenant
	tenantIDPtr := &tenantID
	newBrand := models.Brand{
		TenantModel: models.TenantModel{
			TenantID: tenantIDPtr,
		},
		Name:        saasBrand.Name,
		Description: saasBrand.Description,
		IsActive:    true,
	}

	if err := s.db.Create(&newBrand).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand: %w", err)
	}

	return &newBrand, nil
}

// ensureCategoryExists ensures the category exists in tenant's inventory, creates if not
func (s *BrandOnboardingService) ensureCategoryExists(tenantID uuid.UUID, saasCategory *SaaSCategory) (*models.Category, error) {
	if saasCategory == nil {
		return nil, errors.New("category is required")
	}

	// Check if category already exists for this tenant
	var existingCategory models.Category
	err := s.db.Where("tenant_id = ? AND name = ?", tenantID, saasCategory.Name).First(&existingCategory).Error

	if err == nil {
		// Category exists
		return &existingCategory, nil
	}

	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("failed to check category: %w", err)
	}

	// Create new category for tenant
	tenantIDPtr := &tenantID
	newCategory := models.Category{
		TenantModel: models.TenantModel{
			TenantID: tenantIDPtr,
		},
		Name:        saasCategory.Name,
		Description: saasCategory.Description,
		IsActive:    true,
	}

	if err := s.db.Create(&newCategory).Error; err != nil {
		return nil, fmt.Errorf("failed to create category: %w", err)
	}

	return &newCategory, nil
}

// GetOnboardedBrands returns products that were onboarded from SaaS templates
func (s *BrandOnboardingService) GetOnboardedBrands(tenantID uuid.UUID) ([]models.Product, error) {
	var products []models.Product

	// Query products where SKU starts with "SAAS-" indicating SaaS template source
	err := s.db.Where("tenant_id = ? AND sku LIKE ?", tenantID, "SAAS-%").
		Preload("Category").
		Preload("Brand").
		Find(&products).Error

	if err != nil {
		return nil, fmt.Errorf("failed to fetch onboarded brands: %w", err)
	}

	return products, nil
}

// GetCustomBrands returns products created by the tenant (not from SaaS templates)
func (s *BrandOnboardingService) GetCustomBrands(tenantID uuid.UUID) ([]models.Product, error) {
	var products []models.Product

	// Query products where SKU doesn't start with "SAAS-"
	err := s.db.Where("tenant_id = ? AND (sku NOT LIKE ? OR sku IS NULL)",
		tenantID, "SAAS-%").
		Preload("Category").
		Preload("Brand").
		Find(&products).Error

	if err != nil {
		return nil, fmt.Errorf("failed to fetch custom brands: %w", err)
	}

	return products, nil
}

// UpdateOnboardedBrand allows tenant to customize an onboarded brand
func (s *BrandOnboardingService) UpdateOnboardedBrand(tenantID uuid.UUID, productID uuid.UUID, updates map[string]interface{}) error {
	var product models.Product

	if err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("product not found")
		}
		return fmt.Errorf("failed to fetch product: %w", err)
	}

	// Update the product with provided fields
	if err := s.db.Model(&product).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to update product: %w", err)
	}

	return nil
}
