package services

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/sizing"
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
	// Get SaaS service URL from environment or use default
	saasServiceURL := os.Getenv("SAAS_SERVICE_URL")
	if saasServiceURL == "" {
		saasServiceURL = "http://localhost:8095" // Default for local development
	}

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
		cacheDuration:   30 * time.Second, // Cache brands for 30 seconds (reduced from 5 minutes for better UX)
	}
}

// BrandVariantStock represents initial stock for a variant
type BrandVariantStock struct {
	VariantID    uuid.UUID `json:"saas_brand_variant_id"`
	InitialStock int       `json:"initial_stock"`
}

// OnboardBrandRequest represents a request to onboard SaaS brand templates
type OnboardBrandRequest struct {
	TenantID      uuid.UUID            `json:"tenant_id" binding:"required"`
	ShopID        *uuid.UUID           `json:"shop_id,omitempty"` // Optional: for stock creation
	BrandIDs      []uuid.UUID          `json:"brand_ids" binding:"required"`
	VariantIDs    []uuid.UUID          `json:"variant_ids,omitempty"`    // Optional: specific variants to onboard
	BrandVariants []BrandVariantStock  `json:"brand_variants,omitempty"` // Optional: with initial stock
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
		s.logger.Info("Returning cached brand templates",
			zap.Int("count", len(cached)),
			zap.Time("cache_expiry", s.cacheExpiry),
			zap.Duration("time_until_expiry", time.Until(s.cacheExpiry)))
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

// MarkOnboardedBrands marks which brands/variants are already onboarded for a tenant+shop
func (s *BrandOnboardingService) MarkOnboardedBrands(templates []SaaSBrandTemplate, tenantID uuid.UUID, shopID *uuid.UUID) []SaaSBrandTemplate {
	s.logger.Info("Marking onboarded brands for tenant",
		zap.String("tenant_id", tenantID.String()),
		zap.Int("total_brands", len(templates)))

	// Get products that were onboarded from SaaS templates AND have stock in the specified shop
	var products []models.Product
	query := s.db.Where("tenant_id = ? AND saas_brand_id IS NOT NULL", tenantID).
		Select("saas_brand_id, saas_variant_id")

	// If shop_id provided, only count products that have stock in that shop
	if shopID != nil {
		query = query.Where("id IN (SELECT product_id FROM stocks WHERE shop_id = ? AND deleted_at IS NULL)", *shopID)
	}

	if err := query.Find(&products).Error; err != nil {
		s.logger.Error("Failed to fetch onboarded products", zap.Error(err))
		return templates // Return unchanged on error
	}

	// Build maps of onboarded brand IDs and variant IDs
	onboardedBrands := make(map[uuid.UUID]bool)
	onboardedVariants := make(map[uuid.UUID]bool)

	for _, product := range products {
		if product.SaaSBrandID != nil {
			onboardedBrands[*product.SaaSBrandID] = true
		}
		if product.SaaSVariantID != nil {
			onboardedVariants[*product.SaaSVariantID] = true
		}
	}

	s.logger.Info("Found onboarded items",
		zap.Int("onboarded_brands", len(onboardedBrands)),
		zap.Int("onboarded_variants", len(onboardedVariants)))

	// Mark brands and variants as onboarded
	for i := range templates {
		// Check if brand is onboarded
		if onboardedBrands[templates[i].ID] {
			templates[i].IsOnboarded = true
		}

		// Check variants
		for j := range templates[i].BrandVariants {
			if onboardedVariants[templates[i].BrandVariants[j].ID] {
				templates[i].BrandVariants[j].IsOnboarded = true
			}
		}
	}

	return templates
}

// OnboardBrandsToTenant creates products in tenant's inventory from SaaS brand templates
func (s *BrandOnboardingService) OnboardBrandsToTenant(req OnboardBrandRequest) (*OnboardBrandResponse, error) {
	s.logger.Info("OnboardBrandsToTenant called",
		zap.String("tenant_id", req.TenantID.String()),
		zap.Int("brand_ids_count", len(req.BrandIDs)),
		zap.Int("variant_ids_count", len(req.VariantIDs)))

	response := &OnboardBrandResponse{
		TenantID:      req.TenantID,
		BrandDetails:  make([]OnboardedBrandDetail, 0),
		Errors:        make([]string, 0),
	}

	// 🏪 Auto-fetch first shop if shop_id not provided (for automatic stock initialization)
	if req.ShopID == nil {
		var shop models.Shop
		err := s.db.Where("tenant_id = ? AND deleted_at IS NULL", req.TenantID).
			Order("created_at ASC").First(&shop).Error

		if err == nil {
			req.ShopID = &shop.ID
			s.logger.Info("✅ Auto-selected tenant's first shop for stock initialization",
				zap.String("shop_id", shop.ID.String()),
				zap.String("shop_name", shop.Name))
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			s.logger.Error("Failed to fetch tenant's shop",
				zap.Error(err),
				zap.String("tenant_id", req.TenantID.String()))
		} else {
			s.logger.Warn("⚠️  No shops found for tenant - products will be created without stock",
				zap.String("tenant_id", req.TenantID.String()))
		}
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

			s.logger.Info("🔍 Filtering variants for brand",
				zap.String("brand_id", brand.ID.String()),
				zap.String("brand_name", brand.Name),
				zap.Int("total_variants_in_brand", len(brand.BrandVariants)),
				zap.Int("requested_variant_ids_count", len(req.VariantIDs)))

			// Log all available variant IDs in this brand
			for i, variant := range brand.BrandVariants {
				s.logger.Debug("Available variant in brand",
					zap.Int("index", i),
					zap.String("variant_id", variant.ID.String()),
					zap.String("size", variant.Size))
			}

			// Log all requested variant IDs
			for i, reqVariantID := range req.VariantIDs {
				s.logger.Debug("Requested variant ID",
					zap.Int("index", i),
					zap.String("variant_id", reqVariantID.String()))
			}

			for _, variant := range brand.BrandVariants {
				for _, requestedVariantID := range req.VariantIDs {
					if variant.ID == requestedVariantID {
						variantsToOnboard = append(variantsToOnboard, variant)
						s.logger.Info("✅ Matched variant for onboarding",
							zap.String("variant_id", variant.ID.String()),
							zap.String("size", variant.Size))
						break
					}
				}
			}

			s.logger.Info("📊 Variant filtering complete",
				zap.Int("variants_to_onboard", len(variantsToOnboard)),
				zap.Int("requested", len(req.VariantIDs)))
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
		s.logger.Info("🎯 Starting product creation from variants",
			zap.Int("variants_to_process", len(variantsToOnboard)))

		for i, variant := range variantsToOnboard {
			s.logger.Info("Processing variant",
				zap.Int("index", i+1),
				zap.Int("total", len(variantsToOnboard)),
				zap.String("variant_id", variant.ID.String()),
				zap.String("size", variant.Size))

			// Check if this variant has already been onboarded for this tenant
			var existingProduct models.Product
			err := s.db.Where("tenant_id = ? AND saas_variant_id = ?", req.TenantID, variant.ID).First(&existingProduct).Error
			if err == nil {
				// Product already exists, add it to response but don't create a new one
				s.logger.Info("✅ Variant already onboarded, returning existing product",
					zap.String("tenant_id", req.TenantID.String()),
					zap.String("variant_id", variant.ID.String()),
					zap.String("product_id", existingProduct.ID.String()),
					zap.String("size", variant.Size))

				// Create stock record if initial stock is provided (even for existing products)
				if req.ShopID != nil && len(req.BrandVariants) > 0 {
					for _, bv := range req.BrandVariants {
						if bv.VariantID == variant.ID && bv.InitialStock > 0 {
							// Check if stock record already exists for this product+shop
							var existingStock models.Stock
							stockErr := s.db.Where("product_id = ? AND shop_id = ?", existingProduct.ID, *req.ShopID).First(&existingStock).Error

							if stockErr == nil {
								// Stock exists, update quantity. v1.0.216 —
								// audit row written via the centralized
								// system-actor heal lookup so onboarding
								// doesn't leave a silent +N drift for the
								// reconciler to catch later.
								prevQty := existingStock.Quantity
								existingStock.Quantity = bv.InitialStock
								if err := s.db.Save(&existingStock).Error; err != nil {
									s.logger.Error("Failed to update stock record",
										zap.Error(err),
										zap.String("product_id", existingProduct.ID.String()),
										zap.Int("quantity", bv.InitialStock))
								} else {
									actorID := s.resolveSystemActor(req.TenantID)
									if actorID != uuid.Nil {
										boShopRef, boProdRef := existingStock.ShopID, existingStock.ProductID
										hist := models.StockHistory{
											TenantModel:      models.TenantModel{TenantID: &req.TenantID},
											StockID:          existingStock.ID,
											ShopID:           &boShopRef,
											ProductID:        &boProdRef,
											MovementType:     "brand_onboarding",
											Quantity:         bv.InitialStock - prevQty,
											PreviousQuantity: prevQty,
											NewQuantity:      bv.InitialStock,
											Reference:        "Brand onboarding initial stock",
											CreatedByID:      actorID,
										}
										_ = s.db.Create(&hist).Error
									}
									s.logger.Info("✅ Stock record updated",
										zap.String("product_id", existingProduct.ID.String()),
										zap.String("shop_id", req.ShopID.String()),
										zap.Int("quantity", bv.InitialStock))
								}
							} else {
								// Stock doesn't exist, create new
								stock := models.Stock{
									TenantModel: models.TenantModel{
										TenantID: &req.TenantID,
									},
									ShopID:    *req.ShopID,
									ProductID: existingProduct.ID,
									Quantity:  bv.InitialStock,
								}

								if err := s.db.Create(&stock).Error; err != nil {
									s.logger.Error("Failed to create stock record for existing product",
										zap.Error(err),
										zap.String("product_id", existingProduct.ID.String()),
										zap.Int("quantity", bv.InitialStock))
								} else {
									s.logger.Info("✅ Stock record created for existing product",
										zap.String("product_id", existingProduct.ID.String()),
										zap.String("shop_id", req.ShopID.String()),
										zap.Int("quantity", bv.InitialStock))
								}
							}
							break
						}
					}
				}

				// Add existing product to response
				brandDetail.ProductIDs = append(brandDetail.ProductIDs, existingProduct.ID)
				// Don't increment ProductsCreated since we didn't create a new one
				continue
			}

			s.logger.Info("Variant not found in tenant inventory, will create new product",
				zap.String("variant_id", variant.ID.String()),
				zap.String("size", variant.Size))

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

			// Use display name with fallback to official name
			productDisplayName := brand.DisplayName
			if productDisplayName == "" {
				productDisplayName = brand.Name
			}

			product := models.Product{
				TenantModel: models.TenantModel{
					TenantID: tenantIDPtr,
				},
				CategoryID:     category.ID,
				BrandID:        tenantBrand.ID,
				SaaSBrandID:    brandIDPtr,   // Track SaaS brand origin
				SaaSVariantID:  variantIDPtr, // Track SaaS variant origin for duplicate prevention
				Name:           fmt.Sprintf("%s - %s", productDisplayName, variant.Size),
				DisplayName:    productDisplayName, // Clean consumer display name from SaaS catalog
				Description:    variant.Description,
				Barcode:        variant.Barcode,
				ImageURL:       variant.Picture, // Picture -> ImageURL
				Size:           normalizeSizeLabel(variant.Size),
				AlcoholContent: variant.AlcoholContent,
				DutyFee:        variant.GovernmentDuty, // GovernmentDuty -> DutyFee
				CostPrice:      variant.BuyingPrice,    // BuyingPrice -> CostPrice
				TotalCost:      variant.BuyingPrice + variant.GovernmentDuty,
				SellingPrice:   variant.SellingPrice,
				MRP:            variant.MRP,
				IsActive:       variant.IsActive,
				SKU:            fmt.Sprintf("SAAS-%s-%s-%s", req.TenantID.String()[:8], brand.ID.String()[:8], variant.ID.String()[:8]),
				CreatedVia:     "catalog", // 2026-05-18 — provenance (exempt from AI-Purchase image gate)
			}

			if err := s.db.Create(&product).Error; err != nil {
				s.logger.Error("Failed to create product from variant",
					zap.Error(err),
					zap.String("variant_id", variant.ID.String()))
				continue
			}

			s.logger.Info("✅ Product created successfully",
				zap.String("product_id", product.ID.String()),
				zap.String("variant_id", variant.ID.String()))

			// 📦 Create stock records for ALL active shops in the tenant
			// This ensures product is visible in every shop's inventory
			initialStock := 0
			for _, bv := range req.BrandVariants {
				if bv.VariantID == variant.ID {
					initialStock = bv.InitialStock
					break
				}
			}

			var shops []models.Shop
			if err := s.db.Where("tenant_id = ? AND is_active = true AND deleted_at IS NULL", req.TenantID).Find(&shops).Error; err != nil {
				s.logger.Error("Failed to fetch shops for stock creation", zap.Error(err))
			} else {
				for _, shop := range shops {
					// Check if stock already exists for this product+shop
					var existingStock models.Stock
					if s.db.Where("product_id = ? AND shop_id = ? AND deleted_at IS NULL", product.ID, shop.ID).First(&existingStock).Error == nil {
						continue // Stock already exists
					}

					// Use initial stock only for the requested shop, 0 for others
					qty := 0
					if req.ShopID != nil && shop.ID == *req.ShopID {
						qty = initialStock
					}

					stock := models.Stock{
						TenantModel: models.TenantModel{
							TenantID: &req.TenantID,
						},
						ShopID:       shop.ID,
						ProductID:    product.ID,
						Quantity:     qty,
						MinimumLevel: 10,
					}

					if err := s.db.Create(&stock).Error; err != nil {
						s.logger.Error("Failed to create stock record",
							zap.Error(err),
							zap.String("shop_id", shop.ID.String()))
					} else {
						s.logger.Info("Stock record created",
							zap.String("product_id", product.ID.String()),
							zap.String("shop_id", shop.ID.String()),
							zap.Int("quantity", qty))
					}
				}
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

	// Clear cache so that newly onboarded brands are immediately reflected
	// This ensures the brand catalog shows updated onboarded status without waiting for cache expiry
	if response.OnboardedProducts > 0 {
		s.ClearCache()
		s.logger.Info("Cleared brand cache after successful onboarding",
			zap.Int("onboarded_products", response.OnboardedProducts))
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

// CategorySummary represents category with brand count
type CategorySummary struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Icon       string `json:"icon"`
	BrandCount int    `json:"brand_count"`
	IsPopular  bool   `json:"is_popular"`
	SortOrder  int    `json:"sort_order"`
}

// GetBrandCategories returns all categories with brand counts
func (s *BrandOnboardingService) GetBrandCategories() ([]CategorySummary, error) {
	// Get all brand templates
	brands, err := s.GetAvailableBrandTemplates()
	if err != nil {
		return nil, err
	}

	// Count brands per category
	// Note: Category info is in variants, not in brand directly
	categoryMap := make(map[string]*CategorySummary)

	for _, brand := range brands {
		// Get category from first variant (if any)
		if len(brand.BrandVariants) > 0 && brand.BrandVariants[0].Category != nil {
			categoryName := brand.BrandVariants[0].Category.Name
			categoryID := brand.BrandVariants[0].Category.ID

			if categoryName != "" {
				if _, exists := categoryMap[categoryName]; !exists {
					// Popular categories based on common liquor types
					isPopular := isPopularCategory(categoryName)

					categoryMap[categoryName] = &CategorySummary{
						ID:         categoryID.String(),
						Name:       categoryName,
						Icon:       getCategoryIcon(categoryName),
						BrandCount: 0,
						IsPopular:  isPopular,
						SortOrder:  getCategorySortOrder(categoryName),
					}
				}
				categoryMap[categoryName].BrandCount++
			}
		}
	}

	// Convert map to slice and sort
	categories := make([]CategorySummary, 0, len(categoryMap))
	for _, cat := range categoryMap {
		categories = append(categories, *cat)
	}

	// Sort by: popular first, then by sort order, then alphabetically
	// (implement custom sorting if needed)

	return categories, nil
}

// PaginatedBrandRequest represents pagination request
type PaginatedBrandRequest struct {
	CategoryID string `form:"category_id"`
	Search     string `form:"search"`
	Page       int    `form:"page"`
	Limit      int    `form:"limit"`
}

// PaginatedBrandResponse represents paginated response
type PaginatedBrandResponse struct {
	Brands   []SaaSBrandTemplate `json:"brands"`
	Total    int                 `json:"total"`
	Page     int                 `json:"page"`
	Limit    int                 `json:"limit"`
	HasMore  bool                `json:"has_more"`
}

// GetBrandsPaginated returns paginated brands with filtering
func (s *BrandOnboardingService) GetBrandsPaginated(req PaginatedBrandRequest) (*PaginatedBrandResponse, error) {
	// Get all brands (from cache if available)
	allBrands, err := s.GetAvailableBrandTemplates()
	if err != nil {
		return nil, err
	}

	// Filter by category if specified
	filteredBrands := make([]SaaSBrandTemplate, 0)
	for _, brand := range allBrands {
		// Category filter - check first variant's category
		if req.CategoryID != "" {
			if len(brand.BrandVariants) == 0 || brand.BrandVariants[0].Category == nil {
				continue
			}
			if brand.BrandVariants[0].Category.ID.String() != req.CategoryID {
				continue
			}
		}

		// Search filter — match name, display_name, and description
		if req.Search != "" {
			searchLower := toLower(req.Search)
			nameLower := toLower(brand.Name)
			displayNameLower := toLower(brand.DisplayName)
			descLower := toLower(brand.Description)

			if !contains(nameLower, searchLower) && !contains(displayNameLower, searchLower) && !contains(descLower, searchLower) {
				continue
			}
		}

		filteredBrands = append(filteredBrands, brand)
	}

	total := len(filteredBrands)

	// Calculate pagination
	offset := (req.Page - 1) * req.Limit
	end := offset + req.Limit

	if offset > total {
		offset = total
	}
	if end > total {
		end = total
	}

	// Slice for current page
	pagedBrands := filteredBrands[offset:end]

	// Check if there are more pages
	hasMore := end < total

	return &PaginatedBrandResponse{
		Brands:  pagedBrands,
		Total:   total,
		Page:    req.Page,
		Limit:   req.Limit,
		HasMore: hasMore,
	}, nil
}

// Helper functions

func isPopularCategory(category string) bool {
	popularCategories := map[string]bool{
		"Whiskey":    true,
		"Whisky":     true,
		"Vodka":      true,
		"Rum":        true,
		"Beer":       true,
		"Wine":       true,
		"Champagne":  true,
		"Gin":        true,
	}
	return popularCategories[category]
}

func getCategoryIcon(category string) string {
	icons := map[string]string{
		"Whiskey":    "🥃",
		"Whisky":     "🥃",
		"Vodka":      "🍾",
		"Rum":        "🍹",
		"Beer":       "🍺",
		"Wine":       "🍷",
		"Champagne":  "🥂",
		"Gin":        "🍸",
		"Brandy":     "🥃",
		"Tequila":    "🍹",
		"Cognac":     "🥃",
	}
	if icon, exists := icons[category]; exists {
		return icon
	}
	return "🍾" // Default icon
}

func getCategorySortOrder(category string) int {
	order := map[string]int{
		"Whiskey":    1,
		"Whisky":     1,
		"Vodka":      2,
		"Rum":        3,
		"Beer":       4,
		"Wine":       5,
		"Gin":        6,
		"Champagne":  7,
		"Brandy":     8,
		"Tequila":    9,
	}
	if sortOrder, exists := order[category]; exists {
		return sortOrder
	}
	return 999 // Put unknown categories at the end
}

func toLower(s string) string {
	return strings.ToLower(s)
}

func contains(s, substr string) bool {
	return strings.Contains(s, substr)
}

// normalizeSizeLabel normalizes size strings to uppercase with ML suffix
// "180ml" → "180ML", "750" → "750ML", "1L" → "1000ML", "quarter" → "180ML"
func normalizeSizeLabel(size string) string {
	size = strings.TrimSpace(size)
	if size == "" {
		return size
	}

	upper := strings.ToUpper(size)

	// Handle common name aliases
	switch upper {
	case "QUARTER", "QTR":
		return "180ML"
	case "HALF", "PINT":
		return "375ML"
	case "FULL":
		return "750ML"
	}

	// Handle "1L", "1.5L" etc
	if strings.HasSuffix(upper, "L") && !strings.HasSuffix(upper, "ML") {
		numStr := strings.TrimSuffix(upper, "L")
		numStr = strings.TrimSpace(numStr)
		// Try parsing as float (handles "1.5L")
		if val, err := strconv.ParseFloat(numStr, 64); err == nil {
			return fmt.Sprintf("%dML", int(val*1000))
		}
	}

	// Already has ML suffix
	if strings.HasSuffix(upper, "ML") {
		return upper
	}

	// Pure number — add ML suffix
	cleaned := strings.TrimSpace(upper)
	if _, err := strconv.Atoi(cleaned); err == nil {
		return cleaned + "ML"
	}

	return upper
}

// BrandMetadata contains all metadata for creating custom brands
type BrandMetadata struct {
	Categories    []CategoryDetail    `json:"categories"`
	Subcategories []SubcategoryDetail `json:"subcategories"`
	CommonSizes   []SizeOption        `json:"common_sizes"`
}

// CategoryDetail represents category with its subcategories
type CategoryDetail struct {
	ID               string   `json:"id"`
	Name             string   `json:"name"`
	Description      string   `json:"description"`
	Icon             string   `json:"icon"`
	SubcategoryCount int      `json:"subcategory_count"`
	IsActive         bool     `json:"is_active"`
	SortOrder        int      `json:"sort_order"`
}

// SubcategoryDetail represents subcategory information
type SubcategoryDetail struct {
	ID          string `json:"id"`
	CategoryID  string `json:"category_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active"`
	SortOrder   int    `json:"sort_order"`
}

// SizeOption represents common bottle sizes
type SizeOption struct {
	Value       string `json:"value"`
	Label       string `json:"label"`
	Category    string `json:"category"`
	IsCommon    bool   `json:"is_common"`
}

// GetBrandMetadata returns all metadata (categories, subcategories, sizes) for brand creation
func (s *BrandOnboardingService) GetBrandMetadata() (*BrandMetadata, error) {
	// Load ALL categories from SaaS service
	saasCategories, err := s.saasClient.GetCategories()
	if err != nil {
		return nil, fmt.Errorf("failed to load categories: %w", err)
	}

	// Load ALL subcategories from SaaS service
	saasSubcategories, err := s.saasClient.GetSubcategories()
	if err != nil {
		return nil, fmt.Errorf("failed to load subcategories: %w", err)
	}

	// Count subcategories for each category
	subcategoryCountMap := make(map[string]int)
	for _, sub := range saasSubcategories {
		subcategoryCountMap[sub.CategoryID.String()]++
	}

	// Convert categories to CategoryDetail
	categories := make([]CategoryDetail, 0, len(saasCategories))
	for _, cat := range saasCategories {
		catID := cat.ID.String()
		categories = append(categories, CategoryDetail{
			ID:               catID,
			Name:             cat.Name,
			Description:      cat.Description,
			Icon:             getCategoryIcon(cat.Name),
			SubcategoryCount: subcategoryCountMap[catID],
			IsActive:         cat.IsActive,
			SortOrder:        cat.SortOrder,
		})
	}

	// Convert subcategories to SubcategoryDetail
	subcategories := make([]SubcategoryDetail, 0, len(saasSubcategories))
	for _, sub := range saasSubcategories {
		subcategories = append(subcategories, SubcategoryDetail{
			ID:          sub.ID.String(),
			CategoryID:  sub.CategoryID.String(),
			Name:        sub.Name,
			Description: sub.Description,
			IsActive:    sub.IsActive,
			SortOrder:   sub.SortOrder,
		})
	}

	// Define common bottle sizes
	commonSizes := []SizeOption{
		// Spirits (Whiskey, Vodka, Rum, Gin, etc.)
		{Value: "180ml", Label: "180ml (Nip/Quarter)", Category: "Spirits", IsCommon: true},
		{Value: "375ml", Label: "375ml (Half Bottle)", Category: "Spirits", IsCommon: true},
		{Value: "750ml", Label: "750ml (Standard)", Category: "Spirits", IsCommon: true},
		{Value: "1L", Label: "1 Liter", Category: "Spirits", IsCommon: true},
		{Value: "1.75L", Label: "1.75 Liter (Half Gallon)", Category: "Spirits", IsCommon: true},

		// Beer
		{Value: "330ml", Label: "330ml (Bottle)", Category: "Beer", IsCommon: true},
		{Value: "500ml", Label: "500ml (Pint)", Category: "Beer", IsCommon: true},
		{Value: "650ml", Label: "650ml (Large)", Category: "Beer", IsCommon: true},

		// Wine
		{Value: "750ml", Label: "750ml (Standard Wine)", Category: "Wine", IsCommon: true},
		{Value: "1.5L", Label: "1.5 Liter (Magnum)", Category: "Wine", IsCommon: false},

		// Other common sizes
		{Value: "50ml", Label: "50ml (Miniature)", Category: "Spirits", IsCommon: false},
		{Value: "100ml", Label: "100ml", Category: "Spirits", IsCommon: false},
		{Value: "200ml", Label: "200ml", Category: "Spirits", IsCommon: false},
		{Value: "250ml", Label: "250ml", Category: "Spirits", IsCommon: false},
		{Value: "300ml", Label: "300ml", Category: "Beer", IsCommon: false},
		{Value: "700ml", Label: "700ml", Category: "Spirits", IsCommon: false},
	}

	return &BrandMetadata{
		Categories:    categories,
		Subcategories: subcategories,
		CommonSizes:   commonSizes,
	}, nil
}

// GetSubcategoriesByCategory returns subcategories for a specific category
func (s *BrandOnboardingService) GetSubcategoriesByCategory(categoryID string) ([]SubcategoryDetail, error) {
	// Get all brands to extract subcategories
	brands, err := s.GetAvailableBrandTemplates()
	if err != nil {
		return nil, err
	}

	subcategoryMap := make(map[string]*SubcategoryDetail)

	for _, brand := range brands {
		for _, variant := range brand.BrandVariants {
			// Check if variant belongs to the requested category
			if variant.Category != nil && variant.Category.ID.String() == categoryID {
				if variant.Subcategory != nil {
					subID := variant.Subcategory.ID.String()
					if _, exists := subcategoryMap[subID]; !exists {
						subcategoryMap[subID] = &SubcategoryDetail{
							ID:          subID,
							CategoryID:  categoryID,
							Name:        variant.Subcategory.Name,
							Description: variant.Subcategory.Description,
							IsActive:    variant.Subcategory.IsActive,
							SortOrder:   variant.Subcategory.SortOrder,
						}
					}
				}
			}
		}
	}

	// Convert map to slice
	subcategories := make([]SubcategoryDetail, 0, len(subcategoryMap))
	for _, sub := range subcategoryMap {
		subcategories = append(subcategories, *sub)
	}

	return subcategories, nil
}

// GetSaaSCategories returns all SaaS brand categories (for editing)
func (s *BrandOnboardingService) GetSaaSCategories() ([]SaaSCategory, error) {
	s.logger.Info("Fetching SaaS brand categories for editing")

	categories, err := s.saasClient.GetCategories()
	if err != nil {
		s.logger.Error("Failed to fetch SaaS brand categories", zap.Error(err))
		return nil, err
	}

	s.logger.Info("Successfully fetched SaaS brand categories", zap.Int("count", len(categories)))
	return categories, nil
}

// GetSaaSSubcategories returns all SaaS brand subcategories, optionally filtered by category (for editing)
func (s *BrandOnboardingService) GetSaaSSubcategories(categoryID *uuid.UUID) ([]SaaSSubcategory, error) {
	s.logger.Info("Fetching SaaS brand subcategories for editing", zap.Any("category_id", categoryID))

	subcategories, err := s.saasClient.GetSubcategories()
	if err != nil {
		s.logger.Error("Failed to fetch SaaS brand subcategories", zap.Error(err))
		return nil, err
	}

	// Filter by category if provided
	if categoryID != nil {
		filtered := make([]SaaSSubcategory, 0)
		for _, sub := range subcategories {
			if sub.CategoryID == *categoryID {
				filtered = append(filtered, sub)
			}
		}
		subcategories = filtered
	}

	s.logger.Info("Successfully fetched SaaS brand subcategories", zap.Int("count", len(subcategories)))
	return subcategories, nil
}

// GetSaaSCategorySizes returns category sizes, optionally filtered by category (for editing)
func (s *BrandOnboardingService) GetSaaSCategorySizes(categoryID *uuid.UUID) ([]SaaSCategorySize, error) {
	s.logger.Info("Fetching category sizes for editing", zap.Any("category_id", categoryID))

	sizes, err := s.saasClient.GetCategorySizes(categoryID)
	if err != nil {
		s.logger.Error("Failed to fetch category sizes", zap.Error(err))
		return nil, err
	}

	s.logger.Info("Successfully fetched category sizes", zap.Int("count", len(sizes)))
	return sizes, nil
}

// CreateCustomBrandRequest represents a request to create a custom brand from OCR
type CreateCustomBrandRequest struct {
	TenantID      uuid.UUID  `json:"tenant_id"`
	ShopID        *uuid.UUID `json:"shop_id,omitempty"`
	BrandName     string     `json:"brand_name" binding:"required"`
	CategoryID    uuid.UUID  `json:"category_id" binding:"required"`
	SubcategoryID *uuid.UUID `json:"subcategory_id,omitempty"`
	Size          string     `json:"size" binding:"required"`
	Barcode       string     `json:"barcode,omitempty"`
	Description   string     `json:"description,omitempty"`
	BuyingPrice   float64    `json:"buying_price" binding:"required,gt=0"`
	GovernmentDuty float64   `json:"government_duty" binding:"required,gte=0"`
	SellingPrice  float64    `json:"selling_price" binding:"required,gt=0"`
	MRP           float64    `json:"mrp" binding:"required,gt=0"`
	InitialStock  int        `json:"initial_stock,omitempty"`
	ImageURL      string     `json:"image_url,omitempty"`
	CreatedBy     *uuid.UUID `json:"created_by,omitempty"`
}

// CreateCustomBrandResponse represents the response after creating a custom brand
type CreateCustomBrandResponse struct {
	ProductID   uuid.UUID `json:"product_id"`
	BrandID     uuid.UUID `json:"brand_id"`
	BrandName   string    `json:"brand_name"`
	ProductName string    `json:"product_name"`
	SKU         string    `json:"sku"`
	StockCreated bool     `json:"stock_created"`
	Message     string    `json:"message"`
}

// CreateCustomBrand creates a new custom brand and product when no SaaS match is found
func (s *BrandOnboardingService) CreateCustomBrand(req CreateCustomBrandRequest) (*CreateCustomBrandResponse, error) {
	s.logger.Info("Creating custom brand from OCR",
		zap.String("tenant_id", req.TenantID.String()),
		zap.String("brand_name", req.BrandName),
		zap.String("size", req.Size))

	// Validate pricing logic
	if req.SellingPrice <= req.BuyingPrice {
		return nil, errors.New("selling price must be greater than buying price")
	}
	if req.MRP < req.SellingPrice {
		return nil, errors.New("MRP must be greater than or equal to selling price")
	}

	// v1.0.219 — canonicalise size at the brand-onboarding write boundary.
	// CreateCustomBrand is the path operators hit when they pick "Add new brand"
	// from a manual purchase row that has no master match — historically a
	// hot source of garbage like "180ML1" / "8375" because the OCR layer
	// passed raw extracted text straight through. (Category-aware: we don't
	// know beer-vs-non-beer until we resolve the category below, so default
	// to non-beer ranges; beer onboarding goes through a different path.)
	if req.Size != "" {
		canonical, _, _, ok := sizing.Canonicalize(req.Size, false)
		if !ok {
			return nil, fmt.Errorf("invalid size '%s' — must be one of: 90ml, 180ml, 375ml, 750ml, 1000ml", req.Size)
		}
		req.Size = canonical
	}

	// Check if category exists in tenant's categories, or map from SaaS category
	var category models.Category
	var resolvedCategoryID uuid.UUID = req.CategoryID

	if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, req.TenantID).First(&category).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// Category doesn't exist in tenant DB - this is likely a SaaS category ID
			// Try to find the SaaS category name and map to tenant's local category
			var saasCategoryName string
			if err := s.db.Table("brand_categories").
				Select("name").
				Where("id = ?", req.CategoryID).
				Scan(&saasCategoryName).Error; err == nil && saasCategoryName != "" {

				// Look for matching category in tenant's categories by name
				var tenantCategory models.Category
				if err := s.db.Where("LOWER(name) = LOWER(?) AND tenant_id = ?", saasCategoryName, req.TenantID).
					First(&tenantCategory).Error; err == nil {
					// Found matching tenant category - use it
					resolvedCategoryID = tenantCategory.ID
					category = tenantCategory
					s.logger.Info("Mapped SaaS category to tenant category",
						zap.String("saas_category_id", req.CategoryID.String()),
						zap.String("saas_category_name", saasCategoryName),
						zap.String("tenant_category_id", tenantCategory.ID.String()))
				} else {
					// No matching tenant category - create one
					tenantIDPtr := &req.TenantID
					tenantCategory = models.Category{
						TenantModel: models.TenantModel{TenantID: tenantIDPtr},
						Name:        saasCategoryName,
						Description: fmt.Sprintf("Auto-created from SaaS category %s", saasCategoryName),
						IsActive:    true,
					}
					if err := s.db.Create(&tenantCategory).Error; err == nil {
						resolvedCategoryID = tenantCategory.ID
						category = tenantCategory
						s.logger.Info("Created tenant category from SaaS category",
							zap.String("saas_category_id", req.CategoryID.String()),
							zap.String("new_category_id", tenantCategory.ID.String()),
							zap.String("category_name", saasCategoryName))
					} else {
						return nil, fmt.Errorf("failed to create category: %w", err)
					}
				}
			} else {
				return nil, fmt.Errorf("category not found: %s", req.CategoryID)
			}
		} else {
			return nil, fmt.Errorf("failed to verify category: %w", err)
		}
	} else {
		resolvedCategoryID = category.ID
	}

	// Check if subcategory exists (if provided) - skip validation for SaaS subcategories
	if req.SubcategoryID != nil {
		var subcategory models.Subcategory
		// Just check if subcategory exists (don't enforce category_id match for SaaS subcategories)
		if err := s.db.Where("id = ?", req.SubcategoryID).First(&subcategory).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				// Subcategory not found - this is OK for custom brands, just log it
				s.logger.Warn("Subcategory not found, proceeding without it",
					zap.String("subcategory_id", req.SubcategoryID.String()))
			}
		}
	}

	// Begin transaction for atomic creation
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// 1. Ensure brand exists (or create it)
	var brand models.Brand
	err := tx.Where("tenant_id = ? AND name = ?", req.TenantID, req.BrandName).First(&brand).Error

	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Create new brand
		tenantIDPtr := &req.TenantID
		brand = models.Brand{
			TenantModel: models.TenantModel{
				TenantID: tenantIDPtr,
			},
			Name:        req.BrandName,
			Description: fmt.Sprintf("Custom brand created from OCR: %s", req.Description),
			IsActive:    true,
		}

		if err := tx.Create(&brand).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create brand: %w", err)
		}

		s.logger.Info("Created new custom brand",
			zap.String("brand_id", brand.ID.String()),
			zap.String("brand_name", brand.Name))
	} else if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to check brand: %w", err)
	} else {
		s.logger.Info("Using existing brand",
			zap.String("brand_id", brand.ID.String()),
			zap.String("brand_name", brand.Name))
	}

	// 2. Check for duplicate product (same brand + size)
	var existingProduct models.Product
	err = tx.Where("tenant_id = ? AND brand_id = ? AND size = ?",
		req.TenantID, brand.ID, req.Size).First(&existingProduct).Error

	if err == nil {
		// Product already exists
		tx.Rollback()
		return nil, fmt.Errorf("product already exists: %s - %s (SKU: %s)",
			req.BrandName, req.Size, existingProduct.SKU)
	}

	if !errors.Is(err, gorm.ErrRecordNotFound) {
		tx.Rollback()
		return nil, fmt.Errorf("failed to check for duplicates: %w", err)
	}

	// 3. Create product
	tenantIDPtr := &req.TenantID
	totalCost := req.BuyingPrice + req.GovernmentDuty
	// Opportunistic master-brand link at creation time — so every new
	// tenant product lines up with the excise catalog from day one, without
	// needing a background autofix pass to clean up later. Matches the user's
	// requirement that "everything should be like master data format for
	// consistency" across Smart Purchase / Sale / Stock Setup.
	saasBrandID, saasVariantID := s.findMasterLinkForNewProduct(req.BrandName, req.Size, req.MRP)

	product := models.Product{
		TenantModel: models.TenantModel{
			TenantID: tenantIDPtr,
		},
		CategoryID:     resolvedCategoryID, // Use resolved tenant category ID (not SaaS category ID)
		SubcategoryID:  req.SubcategoryID,
		BrandID:        brand.ID,
		Name:           fmt.Sprintf("%s - %s", req.BrandName, req.Size),
		Description:    req.Description,
		Barcode:        req.Barcode,
		ImageURL:       req.ImageURL,
		Size:           req.Size,
		DutyFee:        req.GovernmentDuty,
		CostPrice:      req.BuyingPrice,
		TotalCost:      totalCost,
		SellingPrice:   req.SellingPrice,
		MRP:            req.MRP,
		IsActive:       true,
		SKU:            fmt.Sprintf("CUSTOM-%s-%s", req.TenantID.String()[:8], uuid.New().String()[:8]),
		SaaSBrandID:    saasBrandID,
		SaaSVariantID:  saasVariantID,
		CreatedVia:     "ai_purchase", // 2026-05-18 — provenance (exempt from AI-Purchase image gate)
	}

	if err := tx.Create(&product).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create product: %w", err)
	}

	if saasBrandID != nil {
		s.logger.Info("Linked new product to master brand at creation",
			zap.String("product_id", product.ID.String()),
			zap.String("saas_brand_id", saasBrandID.String()))
	}

	s.logger.Info("Created custom product",
		zap.String("product_id", product.ID.String()),
		zap.String("sku", product.SKU),
		zap.String("name", product.Name))

	// 4. Create stock entries for ALL tenant shops (ensures product appears in inventory)
	stockCreated := false
	var shops []models.Shop
	if err := tx.Where("tenant_id = ? AND is_active = ?", req.TenantID, true).Find(&shops).Error; err != nil {
		s.logger.Warn("Failed to get shops for stock creation", zap.Error(err))
	} else {
		for _, shop := range shops {
			// Use InitialStock for the specified shop, 0 for others
			quantity := 0
			if req.ShopID != nil && shop.ID == *req.ShopID {
				quantity = req.InitialStock
			}

			stock := models.Stock{
				TenantModel: models.TenantModel{
					TenantID: tenantIDPtr,
				},
				ShopID:           shop.ID,
				ProductID:        product.ID,
				Quantity:         quantity,
				ReservedQuantity: 0,
				MinimumLevel:     10,
				MaximumLevel:     1000,
				CostingMethod:    "fifo",
				AverageCost:      totalCost,
				LastPurchasePrice: req.BuyingPrice,
			}

			if err := tx.Create(&stock).Error; err != nil {
				s.logger.Warn("Failed to create stock for shop",
					zap.String("shop_id", shop.ID.String()),
					zap.Error(err))
			} else {
				stockCreated = true
				s.logger.Info("Created stock record for custom product",
					zap.String("product_id", product.ID.String()),
					zap.String("shop_id", shop.ID.String()),
					zap.String("shop_name", shop.Name),
					zap.Int("quantity", quantity))
			}
		}
	}

	// Commit transaction
	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Clear cache to reflect new custom brand
	s.ClearCache()

	response := &CreateCustomBrandResponse{
		ProductID:    product.ID,
		BrandID:      brand.ID,
		BrandName:    brand.Name,
		ProductName:  product.Name,
		SKU:          product.SKU,
		StockCreated: stockCreated,
		Message:      fmt.Sprintf("Custom brand '%s' created successfully with product '%s'", brand.Name, product.Name),
	}

	s.logger.Info("Custom brand creation completed",
		zap.String("product_id", product.ID.String()),
		zap.String("brand_id", brand.ID.String()),
		zap.Bool("stock_created", stockCreated))

	return response, nil
}

// findMasterLinkForNewProduct looks up a master brand + variant that matches
// the name/size/MRP triple being created. Returns (nil, nil) when no safe
// match is found — the product gets created as orphan and can still be
// linked later by the autofix pass.
//
// Match strategy is deliberately conservative:
//   - size must match exactly (case-insensitive)
//   - MRP within ±₹30 of a variant's price
//   - brand name normalized-equality match against saas_brands.name OR
//     saas_brands.display_name (no fuzzy here — fuzzy happens in
//     scoreMasterBrand when the brand came from AI OCR)
//
// Returning the brand_variant's saas_brand_id + variant ID so the new
// product aligns with the master-data index that every consumer
// (Smart Purchase / Smart Sale / Smart Stock Setup) already queries.
func (s *BrandOnboardingService) findMasterLinkForNewProduct(brandName, size string, mrp float64) (*uuid.UUID, *uuid.UUID) {
	if strings.TrimSpace(brandName) == "" || strings.TrimSpace(size) == "" || mrp <= 0 {
		return nil, nil
	}

	type row struct {
		VariantID string
		BrandID   string
	}
	var r row
	err := s.db.Raw(`
		SELECT bv.id::text AS variant_id, sb.id::text AS brand_id
		FROM brand_variants bv
		JOIN saas_brands sb ON bv.brand_id = sb.id
		WHERE bv.deleted_at IS NULL AND sb.deleted_at IS NULL
		  AND UPPER(bv.size) = UPPER(?)
		  AND bv.mrp BETWEEN ? AND ?
		  AND (
			LOWER(sb.name) = LOWER(?)
			OR LOWER(COALESCE(NULLIF(sb.display_name, ''), sb.name)) = LOWER(?)
		  )
		ORDER BY ABS(bv.mrp - ?) ASC
		LIMIT 1
	`, size, mrp-30, mrp+30, brandName, brandName, mrp).Scan(&r).Error

	if err != nil || r.BrandID == "" {
		return nil, nil
	}
	brandID, bErr := uuid.Parse(r.BrandID)
	if bErr != nil {
		return nil, nil
	}
	var variantIDPtr *uuid.UUID
	if r.VariantID != "" {
		if vID, vErr := uuid.Parse(r.VariantID); vErr == nil {
			variantIDPtr = &vID
		}
	}
	return &brandID, variantIDPtr
}

// resolveSystemActor returns the first admin/manager user for a tenant — used
// as a synthetic actor on audit rows written by API paths that don't carry a
// real user context (brand onboarding, bulk import without explicit caller).
// Returns uuid.Nil if no eligible user exists; callers MUST skip the audit
// write in that case rather than insert with all-zero CreatedByID (the FK
// to users would fail).
func (s *BrandOnboardingService) resolveSystemActor(tenantID uuid.UUID) uuid.UUID {
	var u struct{ ID uuid.UUID }
	s.db.Raw(`
		SELECT id FROM users
		WHERE tenant_id = ? AND is_active = true AND role IN ('saas_admin','admin','manager','owner')
		ORDER BY CASE role WHEN 'saas_admin' THEN 0 WHEN 'admin' THEN 1 WHEN 'owner' THEN 2 ELSE 3 END,
		         created_at ASC
		LIMIT 1
	`, tenantID).Scan(&u)
	return u.ID
}
