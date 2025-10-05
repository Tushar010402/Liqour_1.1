package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// TenantBrandService handles tenant brand operations in the inventory service
type TenantBrandService struct {
	db     *database.DB
	cache  *cache.Cache
	config *config.Config
}

// NewTenantBrandService creates a new tenant brand service
func NewTenantBrandService(db *database.DB, cache *cache.Cache, config *config.Config) *TenantBrandService {
	return &TenantBrandService{
		db:     db,
		cache:  cache,
		config: config,
	}
}

// SaasBrandResponse represents a brand from the SaaS service
type SaasBrandResponse struct {
	ID            uuid.UUID                  `json:"id"`
	Name          string                     `json:"name"`
	Description   string                     `json:"description"`
	Picture       string                     `json:"picture"`
	IsActive      bool                       `json:"is_active"`
	SortOrder     int                        `json:"sort_order"`
	BrandVariants []SaasBrandVariantResponse `json:"brand_variants,omitempty"`
	CreatedAt     interface{}                `json:"created_at"`
	UpdatedAt     interface{}                `json:"updated_at"`
}

// SaasBrandVariantResponse represents a brand variant from the SaaS service
type SaasBrandVariantResponse struct {
	ID             uuid.UUID           `json:"id"`
	BrandID        uuid.UUID           `json:"brand_id"`
	CategoryID     uuid.UUID           `json:"category_id"`
	SubcategoryID  *uuid.UUID          `json:"subcategory_id"`
	Size           string              `json:"size"`
	AlcoholContent float64             `json:"alcohol_content"`
	Picture        string              `json:"picture"`
	GovernmentDuty float64             `json:"government_duty"`
	BuyingPrice    float64             `json:"buying_price"`
	SellingPrice   float64             `json:"selling_price"`
	MRP            float64             `json:"mrp"`
	Description    string              `json:"description"`
	Barcode        string              `json:"barcode"`
	HSNCode        string              `json:"hsn_code"`
	IsActive       bool                `json:"is_active"`
	SortOrder      int                 `json:"sort_order"`
	Category       *models.Category    `json:"category,omitempty"`
	Subcategory    *models.Subcategory `json:"subcategory,omitempty"`
	CreatedAt      interface{}         `json:"created_at"`
	UpdatedAt      interface{}         `json:"updated_at"`
}

// GetAvailableBrands gets all available brands from SaaS service
func (s *TenantBrandService) GetAvailableBrands() ([]SaasBrandResponse, error) {
	// Make HTTP request to SaaS service to get available brands (internal endpoint)
	saasURL := fmt.Sprintf("http://saas:8095/api/internal/brands?include_variants=true&active_only=true")

	resp, err := http.Get(saasURL)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch brands from SaaS service: %w", err)
	}
	defer resp.Body.Close()

	// Read body for debugging
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	// Try to unmarshal as direct array first
	var directBrands []SaasBrandResponse
	if err := json.Unmarshal(body, &directBrands); err == nil {
		return directBrands, nil
	}

	// Try with wrapped data structure (SaaS service returns data + pagination)
	var response struct {
		Message    string                `json:"message"`
		Data       []SaasBrandResponse   `json:"data"`
		Count      int                   `json:"count,omitempty"`
		Pagination map[string]interface{} `json:"pagination,omitempty"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		// Log the actual response for debugging
		return nil, fmt.Errorf("failed to decode brands response: %w (body: %s)", err, string(body[:min(len(body), 200)]))
	}

	return response.Data, nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// GetTenantBrands gets brands assigned to a specific tenant
func (s *TenantBrandService) GetTenantBrands(tenantID uuid.UUID) ([]SaasBrandResponse, error) {
	// Make HTTP request to SaaS service to get tenant brands (internal endpoint)
	saasURL := fmt.Sprintf("http://saas:8095/api/internal/tenants/%s/brands", tenantID.String())

	resp, err := http.Get(saasURL)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch tenant brands from SaaS service: %w", err)
	}
	defer resp.Body.Close()

	// Read body for debugging
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	// Try to unmarshal as direct array first
	var directBrands []SaasBrandResponse
	if err := json.Unmarshal(body, &directBrands); err == nil {
		return directBrands, nil
	}

	// Try with wrapped data structure (SaaS service returns data + count)
	var response struct {
		Message string               `json:"message"`
		Data    []SaasBrandResponse  `json:"data"`
		Count   int                  `json:"count,omitempty"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		// Log the actual response for debugging
		return nil, fmt.Errorf("failed to decode tenant brands response: %w (body: %s)", err, string(body[:min(len(body), 200)]))
	}

	return response.Data, nil
}

// CreateProductFromBrandVariant creates a product in the inventory from a brand variant
func (s *TenantBrandService) CreateProductFromBrandVariant(tenantID uuid.UUID, variantID uuid.UUID, shopID uuid.UUID) (*models.Product, error) {
	// Get available brands to find the variant
	availableBrands, err := s.GetAvailableBrands()
	if err != nil {
		return nil, fmt.Errorf("failed to get available brands: %w", err)
	}

	var selectedVariant *SaasBrandVariantResponse
	var selectedBrand *SaasBrandResponse

	// Find the specific variant
	for _, brand := range availableBrands {
		for _, variant := range brand.BrandVariants {
			if variant.ID == variantID {
				selectedVariant = &variant
				selectedBrand = &brand
				break
			}
		}
		if selectedVariant != nil {
			break
		}
	}

	if selectedVariant == nil {
		return nil, fmt.Errorf("brand variant not found")
	}

	// Create or get existing brand in the inventory system
	var inventoryBrand models.Brand
	if err := s.db.DB.Where("name = ? AND tenant_id = ?", selectedBrand.Name, tenantID).
		FirstOrCreate(&inventoryBrand, models.Brand{
			TenantModel: models.TenantModel{TenantID: &tenantID},
			Name:        selectedBrand.Name,
			Description: selectedBrand.Description,
			IsActive:    true,
		}).Error; err != nil {
		return nil, fmt.Errorf("failed to create/get brand: %w", err)
	}

	// Get or create category in tenant's inventory system based on SaaS category
	var localCategory models.Category
	var localCategoryID uuid.UUID

	if selectedVariant.Category != nil {
		// Try to find existing category by name for this tenant
		if err := s.db.DB.Where("name = ? AND tenant_id = ?", selectedVariant.Category.Name, tenantID).
			First(&localCategory).Error; err != nil {
			// Create new category if not found
			localCategory = models.Category{
				TenantModel: models.TenantModel{TenantID: &tenantID},
				Name:        selectedVariant.Category.Name,
				Description: selectedVariant.Category.Description,
				IsActive:    true,
			}
			if err := s.db.DB.Create(&localCategory).Error; err != nil {
				return nil, fmt.Errorf("failed to create category: %w", err)
			}
		}
		localCategoryID = localCategory.ID
	} else {
		// Use default category if no category provided by SaaS
		if err := s.db.DB.Where("name = ? AND tenant_id = ?", "General", tenantID).
			FirstOrCreate(&localCategory, models.Category{
				TenantModel: models.TenantModel{TenantID: &tenantID},
				Name:        "General",
				Description: "General category for products",
				IsActive:    true,
			}).Error; err != nil {
			return nil, fmt.Errorf("failed to create/get default category: %w", err)
		}
		localCategoryID = localCategory.ID
	}

	// Handle subcategory if present
	var localSubcategoryID *uuid.UUID
	if selectedVariant.Subcategory != nil {
		var localSubcategory models.Subcategory
		if err := s.db.DB.Where("name = ? AND category_id = ? AND tenant_id = ?",
			selectedVariant.Subcategory.Name, localCategoryID, tenantID).
			FirstOrCreate(&localSubcategory, models.Subcategory{
				TenantModel: models.TenantModel{TenantID: &tenantID},
				CategoryID:  localCategoryID,
				Name:        selectedVariant.Subcategory.Name,
				Description: selectedVariant.Subcategory.Description,
				IsActive:    true,
			}).Error; err != nil {
			return nil, fmt.Errorf("failed to create/get subcategory: %w", err)
		}
		localSubcategoryID = &localSubcategory.ID
	}

	// Check if product already exists for this variant
	var existingProduct models.Product
	err = s.db.DB.Where("brand_id = ? AND size = ? AND tenant_id = ?",
		inventoryBrand.ID, selectedVariant.Size, tenantID).First(&existingProduct).Error

	if err == nil {
		// Product already exists, return it instead of creating a duplicate
		s.db.DB.Preload("Category").Preload("Subcategory").Preload("Brand").First(&existingProduct, existingProduct.ID)
		return &existingProduct, nil
	}

	// Generate product name
	productName := fmt.Sprintf("%s - %s", selectedBrand.Name, selectedVariant.Size)

	// Generate unique SKU from brand name, size, and variant ID to ensure uniqueness
	sku := fmt.Sprintf("%s-%s-%s",
		strings.ToUpper(strings.ReplaceAll(selectedBrand.Name, " ", "")),
		selectedVariant.Size,
		selectedVariant.ID.String()[:8]) // Use first 8 chars of variant ID for uniqueness

	// Create product using local category and subcategory IDs
	product := models.Product{
		TenantModel:    models.TenantModel{TenantID: &tenantID},
		Name:           productName,
		SKU:            sku,
		CategoryID:     localCategoryID,
		SubcategoryID:  localSubcategoryID,
		BrandID:        inventoryBrand.ID,
		Size:           selectedVariant.Size,
		AlcoholContent: selectedVariant.AlcoholContent,
		Description:    selectedVariant.Description,
		Barcode:        selectedVariant.Barcode,
		ImageURL:       selectedVariant.Picture,
		IsActive:       true,
		CostPrice:      selectedVariant.BuyingPrice,
		DutyFee:        selectedVariant.GovernmentDuty,
		TotalCost:      selectedVariant.BuyingPrice + selectedVariant.GovernmentDuty,
		SellingPrice:   selectedVariant.SellingPrice,
		MRP:            selectedVariant.MRP,
	}

	if err := s.db.DB.Create(&product).Error; err != nil {
		return nil, fmt.Errorf("failed to create product: %w", err)
	}

	// Create initial stock record for the product
	stock := models.Stock{
		TenantModel:       models.TenantModel{TenantID: &tenantID},
		ShopID:            shopID,
		ProductID:         product.ID,
		Quantity:          0,
		ReservedQuantity:  0,
		MinimumLevel:      10,   // Default minimum level
		MaximumLevel:      1000, // Default maximum level
		CostingMethod:     "fifo",
		AverageCost:       selectedVariant.BuyingPrice + selectedVariant.GovernmentDuty,
		LastPurchasePrice: selectedVariant.BuyingPrice,
	}

	if err := s.db.DB.Create(&stock).Error; err != nil {
		return nil, fmt.Errorf("failed to create initial stock: %w", err)
	}

	// Load relationships for response
	s.db.DB.Preload("Category").Preload("Subcategory").Preload("Brand").First(&product, product.ID)

	return &product, nil
}

// GetProductsFromBrandVariants gets products created from specific brand variants
func (s *TenantBrandService) GetProductsFromBrandVariants(tenantID uuid.UUID) ([]models.Product, error) {
	var products []models.Product

	if err := s.db.DB.Where("tenant_id = ? AND is_active = ?", tenantID, true).
		Preload("Category").
		Preload("Subcategory").
		Preload("Brand").
		Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch products: %w", err)
	}

	return products, nil
}

// SyncBrandVariantPricing syncs pricing from SaaS brand variants to existing products
func (s *TenantBrandService) SyncBrandVariantPricing(tenantID uuid.UUID) error {
	// Get tenant brands from SaaS
	tenantBrands, err := s.GetTenantBrands(tenantID)
	if err != nil {
		return fmt.Errorf("failed to get tenant brands: %w", err)
	}

	// Get all products for this tenant
	var products []models.Product
	if err := s.db.DB.Where("tenant_id = ?", tenantID).
		Preload("Brand").Find(&products).Error; err != nil {
		return fmt.Errorf("failed to fetch tenant products: %w", err)
	}

	// Create a map of brand variants for quick lookup
	variantMap := make(map[string]*SaasBrandVariantResponse)
	for _, brand := range tenantBrands {
		for _, variant := range brand.BrandVariants {
			// Create key from brand name and size
			key := fmt.Sprintf("%s-%s", brand.Name, variant.Size)
			v := variant // Create local copy
			variantMap[key] = &v
		}
	}

	// Update product pricing based on brand variants
	for _, product := range products {
		if product.Brand != nil {
			key := fmt.Sprintf("%s-%s", product.Brand.Name, product.Size)
			if variant, exists := variantMap[key]; exists {
				// Update pricing
				product.CostPrice = variant.BuyingPrice
				product.DutyFee = variant.GovernmentDuty
				product.TotalCost = variant.BuyingPrice + variant.GovernmentDuty
				product.SellingPrice = variant.SellingPrice
				product.MRP = variant.MRP

				// Update barcode if available
				if variant.Barcode != "" && product.Barcode == "" {
					product.Barcode = variant.Barcode
				}

				// Update image if available
				if variant.Picture != "" && product.ImageURL == "" {
					product.ImageURL = variant.Picture
				}

				// Save updated product
				if err := s.db.DB.Save(&product).Error; err != nil {
					return fmt.Errorf("failed to update product %s: %w", product.Name, err)
				}
			}
		}
	}

	return nil
}

// SelectBrandsForTenant allows tenant to select specific brands from SaaS catalog
func (s *TenantBrandService) SelectBrandsForTenant(tenantID uuid.UUID, brandIDs []uuid.UUID) error {
	// Call SaaS service to assign brands to tenant
	assignmentRequest := struct {
		TenantID   uuid.UUID   `json:"tenant_id"`
		BrandIDs   []uuid.UUID `json:"brand_ids"`
		VariantIDs []uuid.UUID `json:"variant_ids"`
	}{
		TenantID:   tenantID,
		BrandIDs:   brandIDs,
		VariantIDs: []uuid.UUID{}, // Empty for now, can be enhanced later
	}

	reqBytes, err := json.Marshal(assignmentRequest)
	if err != nil {
		return fmt.Errorf("failed to encode assignment request: %w", err)
	}

	saasURL := "http://saas:8095/api/super-admin/brands/assign"
	resp, err := http.Post(saasURL, "application/json", bytes.NewReader(reqBytes))
	if err != nil {
		return fmt.Errorf("failed to call SaaS brand assignment API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("SaaS brand assignment failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// CustomizeBrandVariantPricing allows tenant to customize pricing for specific variants
func (s *TenantBrandService) CustomizeBrandVariantPricing(tenantID uuid.UUID, variantID uuid.UUID, customBuyingPrice, customSellingPrice, customMRP *float64) error {
	// Find existing product for this variant
	var product models.Product
	if err := s.db.DB.Where("brand_variant_id = ? AND tenant_id = ?", variantID, tenantID).First(&product).Error; err != nil {
		return fmt.Errorf("product for variant %s not found: %w", variantID.String(), err)
	}

	// Update custom pricing
	if customBuyingPrice != nil {
		product.CostPrice = *customBuyingPrice
		product.TotalCost = *customBuyingPrice + product.DutyFee
	}
	if customSellingPrice != nil {
		product.SellingPrice = *customSellingPrice
	}
	if customMRP != nil {
		product.MRP = *customMRP
	}

	// Save updated product
	if err := s.db.DB.Save(&product).Error; err != nil {
		return fmt.Errorf("failed to save customized pricing: %w", err)
	}

	return nil
}

// GetBrandCatalogWithFilters gets brands with filtering options
func (s *TenantBrandService) GetBrandCatalogWithFilters(categoryID *uuid.UUID, subcategoryID *uuid.UUID, searchTerm string, includeVariants bool) ([]SaasBrandResponse, error) {
	// Get all available brands
	brands, err := s.GetAvailableBrands()
	if err != nil {
		return nil, err
	}

	// Apply filters
	filteredBrands := []SaasBrandResponse{}
	for _, brand := range brands {
		shouldInclude := true

		// Search term filter
		if searchTerm != "" {
			// Simple case-insensitive search
			searchLower := strings.ToLower(searchTerm)
			brandNameLower := strings.ToLower(brand.Name)
			if !strings.Contains(brandNameLower, searchLower) {
				shouldInclude = false
			}
		}

		// Category filter
		if shouldInclude && categoryID != nil {
			hasMatchingCategory := false
			for _, variant := range brand.BrandVariants {
				if variant.CategoryID == *categoryID {
					hasMatchingCategory = true
					break
				}
			}
			if !hasMatchingCategory {
				shouldInclude = false
			}
		}

		// Subcategory filter
		if shouldInclude && subcategoryID != nil {
			hasMatchingSubcategory := false
			for _, variant := range brand.BrandVariants {
				if variant.SubcategoryID != nil && *variant.SubcategoryID == *subcategoryID {
					hasMatchingSubcategory = true
					break
				}
			}
			if !hasMatchingSubcategory {
				shouldInclude = false
			}
		}

		if shouldInclude {
			// Filter variants if needed
			if categoryID != nil || subcategoryID != nil {
				filteredVariants := []SaasBrandVariantResponse{}
				for _, variant := range brand.BrandVariants {
					variantMatches := true
					if categoryID != nil && variant.CategoryID != *categoryID {
						variantMatches = false
					}
					if subcategoryID != nil && (variant.SubcategoryID == nil || *variant.SubcategoryID != *subcategoryID) {
						variantMatches = false
					}
					if variantMatches {
						filteredVariants = append(filteredVariants, variant)
					}
				}
				brand.BrandVariants = filteredVariants
			}

			if !includeVariants {
				brand.BrandVariants = nil
			}

			filteredBrands = append(filteredBrands, brand)
		}
	}

	return filteredBrands, nil
}

// BulkImportBrandVariants imports multiple brand variants as products
func (s *TenantBrandService) BulkImportBrandVariants(tenantID uuid.UUID, shopID uuid.UUID, imports []BrandVariantImport) ([]models.Product, error) {
	var importedProducts []models.Product

	for _, importItem := range imports {
		// Create product from brand variant
		product, err := s.CreateProductFromBrandVariant(tenantID, importItem.VariantID, shopID)
		if err != nil {
			return nil, fmt.Errorf("failed to import variant %s: %w", importItem.VariantID.String(), err)
		}

		// Apply custom pricing if provided
		if importItem.CustomBuyingPrice != nil {
			product.CostPrice = *importItem.CustomBuyingPrice
			product.TotalCost = *importItem.CustomBuyingPrice + product.DutyFee
		}
		if importItem.CustomSellingPrice != nil {
			product.SellingPrice = *importItem.CustomSellingPrice
		}
		if importItem.CustomMRP != nil {
			product.MRP = *importItem.CustomMRP
		}

		// Save updated pricing
		if err := s.db.DB.Save(product).Error; err != nil {
			return nil, fmt.Errorf("failed to save custom pricing for variant %s: %w", importItem.VariantID.String(), err)
		}

		// Create initial stock if specified
		if importItem.InitialStock > 0 {
			stock := models.Stock{
				TenantModel:  models.TenantModel{TenantID: &tenantID},
				ProductID:    product.ID,
				ShopID:       shopID,
				Quantity:     importItem.InitialStock,
				MinimumLevel: 10,                          // Default reorder level
				MaximumLevel: importItem.InitialStock * 2, // Default max level
			}

			if err := s.db.DB.Create(&stock).Error; err != nil {
				return nil, fmt.Errorf("failed to create initial stock for variant %s: %w", importItem.VariantID.String(), err)
			}
		}

		importedProducts = append(importedProducts, *product)
	}

	return importedProducts, nil
}

// BrandVariantImport represents import configuration for a brand variant
type BrandVariantImport struct {
	VariantID          uuid.UUID `json:"variant_id"`
	InitialStock       int       `json:"initial_stock"`
	CustomBuyingPrice  *float64  `json:"custom_buying_price"`
	CustomSellingPrice *float64  `json:"custom_selling_price"`
	CustomMRP          *float64  `json:"custom_mrp"`
}
