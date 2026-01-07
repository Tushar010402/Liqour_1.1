package services

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// EnhancedProductService handles advanced product and brand management
type EnhancedProductService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewEnhancedProductService creates a new enhanced product service
func NewEnhancedProductService(db *database.DB, cache *cache.Cache) *EnhancedProductService {
	return &EnhancedProductService{
		db:    db,
		cache: cache,
	}
}

// CreateBrandWithVariantsRequest represents request to create brand with multiple size variants
type CreateBrandWithVariantsRequest struct {
	BrandName     string           `json:"brand_name" binding:"required"`
	Description   string           `json:"description"`
	CategoryID    uuid.UUID        `json:"category_id" binding:"required"`
	CategoryName  string           `json:"category_name"`  // Optional: used to auto-create category if needed
	SubcategoryID *uuid.UUID       `json:"subcategory_id"` // Optional: subcategory for the products
	Variants      []ProductVariant `json:"variants" binding:"required,min=1"`
	State         string           `json:"state"` // For state-specific pricing rules (e.g., "UP" for Uttar Pradesh)
}

// ProductVariant represents a product variant with size and pricing
type ProductVariant struct {
	Size           string  `json:"size" binding:"required"`           // e.g., "180ml", "350ml", "750ml", "1L"
	AlcoholContent float64 `json:"alcohol_content"`                   // Alcohol percentage
	CostPrice      float64 `json:"cost_price" binding:"required,gt=0"`
	GovernmentDuty float64 `json:"government_duty"`                   // Will be calculated if not provided
	SellingPrice   float64 `json:"selling_price" binding:"required,gt=0"`
	MRP            float64 `json:"mrp" binding:"required,gt=0"`
	Barcode        string  `json:"barcode"`
	ImageURL       string  `json:"image_url"`
	InitialStock   int     `json:"initial_stock"` // Initial stock quantity
}

// EnhancedBrandResponse represents brand with product count
type EnhancedBrandResponse struct {
	ID           uuid.UUID `json:"id"`
	Name         string    `json:"name"`
	Description  string    `json:"description"`
	IsActive     bool      `json:"is_active"`
	ProductCount int64     `json:"product_count"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// EnhancedBrandRequest represents brand creation/update request
type EnhancedBrandRequest struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	IsActive    *bool  `json:"is_active"`
}

// CreateBrandWithVariants creates a brand with multiple size variants
// Implements business logic:
// 1. Prevents duplicate Brand + Size combinations
// 2. Applies state-specific duty calculations (Uttar Pradesh logic)
// 3. Auto-generates SKU with brand name + size
// 4. Creates stock records for each variant
func (s *EnhancedProductService) CreateBrandWithVariants(ctx context.Context, req CreateBrandWithVariantsRequest, tenantID uuid.UUID, shopID uuid.UUID) (*BrandWithVariantsResponse, error) {
	// Step 1: Check if brand exists, create if not
	var brand models.Brand
	err := s.db.Where("name = ? AND tenant_id = ?", req.BrandName, tenantID).First(&brand).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// Create new brand
			brand = models.Brand{
				TenantModel: models.TenantModel{TenantID: &tenantID},
				Name:        req.BrandName,
				Description: req.Description,
				IsActive:    true,
			}

			if err := s.db.Create(&brand).Error; err != nil {
				return nil, fmt.Errorf("failed to create brand: %w", err)
			}
		} else {
			return nil, fmt.Errorf("failed to check brand existence: %w", err)
		}
	}

	// Step 2: Map SaaS category ID to tenant's local category
	var resolvedCategoryID uuid.UUID = req.CategoryID

	// First, check if this category already exists in tenant's categories
	var existingCategory models.Category
	if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&existingCategory).Error; err != nil {
		// Category not found with this ID - it's likely a SaaS category
		// Look up the SaaS category name from brand_categories table
		var saasCategoryName string
		if err := s.db.Table("brand_categories").
			Select("name").
			Where("id = ?", req.CategoryID).
			Scan(&saasCategoryName).Error; err == nil && saasCategoryName != "" {

			// Find matching tenant category by name
			var tenantCategory models.Category
			if err := s.db.Where("LOWER(name) = LOWER(?) AND tenant_id = ?", saasCategoryName, tenantID).
				First(&tenantCategory).Error; err == nil {
				resolvedCategoryID = tenantCategory.ID
			} else {
				// Create the category for this tenant
				tenantCategory = models.Category{
					TenantModel: models.TenantModel{TenantID: &tenantID},
					Name:        saasCategoryName,
					Description: "Auto-created from SaaS category",
					IsActive:    true,
				}
				if err := s.db.Create(&tenantCategory).Error; err == nil {
					resolvedCategoryID = tenantCategory.ID
				}
			}
		}
	} else {
		resolvedCategoryID = existingCategory.ID
	}

	// Step 3: Create products for each variant
	createdProducts := []models.Product{}
	duplicates := []string{}
	errors := []string{}

	for _, variant := range req.Variants {
		// Check for duplicate Brand + Size combination
		var existingProduct models.Product
		err := s.db.Where("brand_id = ? AND size = ? AND tenant_id = ?", brand.ID, variant.Size, tenantID).
			First(&existingProduct).Error

		if err == nil {
			// Duplicate found
			duplicates = append(duplicates, fmt.Sprintf("%s - %s", req.BrandName, variant.Size))
			continue
		}

		// Apply duty calculation - use provided value or calculate based on size/cost
		dutyFee := variant.GovernmentDuty
		if dutyFee == 0 {
			// Auto-calculate duty based on size and cost price (UP excise duty structure)
			dutyFee = s.calculateUttarPradeshDuty(variant.Size, variant.AlcoholContent, variant.CostPrice)
		}

		// Total cost equals cost price (cost price already includes duty)
		// duty_fee is stored for display/breakdown purposes only
		totalCost := variant.CostPrice

		// Validate pricing logic - selling price must be greater than cost price for profit
		if variant.SellingPrice < totalCost {
			errors = append(errors, fmt.Sprintf("Selling price for %s must be greater than cost price (%.2f)", variant.Size, totalCost))
			continue
		}

		// Generate SKU: BRAND-SIZE-RANDOM
		sku := s.generateProductSKU(req.BrandName, variant.Size)

		// Create product name
		productName := fmt.Sprintf("%s - %s", req.BrandName, variant.Size)

		// Set MRP equal to selling price if not explicitly provided or if MRP is 0
		mrp := variant.MRP
		if mrp == 0 {
			mrp = variant.SellingPrice
		}

		// Create product
		product := models.Product{
			TenantModel:    models.TenantModel{TenantID: &tenantID},
			Name:           productName,
			CategoryID:     resolvedCategoryID, // Use resolved tenant category ID
			SubcategoryID:  req.SubcategoryID,
			BrandID:        brand.ID,
			Size:           variant.Size,
			AlcoholContent: variant.AlcoholContent,
			Description:    req.Description,
			Barcode:        variant.Barcode,
			SKU:            sku,
			ImageURL:       variant.ImageURL,
			IsActive:       true,
			CostPrice:      variant.CostPrice,
			DutyFee:        dutyFee,
			TotalCost:      totalCost,
			SellingPrice:   variant.SellingPrice,
			MRP:            mrp,
		}

		if err := s.db.Create(&product).Error; err != nil {
			errors = append(errors, fmt.Sprintf("Failed to create product for size %s: %v", variant.Size, err))
			continue
		}

		// Create stock records for ALL tenant shops (ensures product appears in inventory)
		var shops []models.Shop
		if err := s.db.Where("tenant_id = ? AND is_active = ?", tenantID, true).Find(&shops).Error; err == nil {
			for _, shop := range shops {
				// Use InitialStock for all shops (typically 0 for new products)
				stock := models.Stock{
					TenantModel:       models.TenantModel{TenantID: &tenantID},
					ShopID:            shop.ID,
					ProductID:         product.ID,
					Quantity:          variant.InitialStock,
					ReservedQuantity:  0,
					MinimumLevel:      10,
					MaximumLevel:      1000,
					CostingMethod:     "fifo",
					AverageCost:       totalCost,
					LastPurchasePrice: variant.CostPrice,
				}
				s.db.Create(&stock) // Ignore individual errors - stock creation is non-critical
			}
		}

		createdProducts = append(createdProducts, product)
	}

	// Step 4: Load relationships for response
	for i := range createdProducts {
		s.db.Preload("Category").Preload("Brand").First(&createdProducts[i], createdProducts[i].ID)
	}

	return &BrandWithVariantsResponse{
		Brand:            &brand,
		ProductsCreated:  len(createdProducts),
		Products:         createdProducts,
		DuplicatesFound:  duplicates,
		Errors:           errors,
	}, nil
}

// calculateUttarPradeshDuty calculates government duty for Uttar Pradesh
// Business logic based on Uttar Pradesh excise duty structure:
// - 180ml: 25% of cost price (minimum ₹50)
// - 350ml: 30% of cost price (minimum ₹100)
// - 750ml: 35% of cost price (minimum ₹200)
// - 1L: 40% of cost price (minimum ₹300)
func (s *EnhancedProductService) calculateUttarPradeshDuty(size string, alcoholContent float64, costPrice float64) float64 {
	sizeLower := strings.ToLower(size)

	var dutyRate float64
	var minimumDuty float64

	// Determine duty rate and minimum based on size
	if strings.Contains(sizeLower, "180") || strings.Contains(sizeLower, "200") {
		dutyRate = 0.25      // 25%
		minimumDuty = 50.0   // ₹50 minimum
	} else if strings.Contains(sizeLower, "350") || strings.Contains(sizeLower, "375") {
		dutyRate = 0.30      // 30%
		minimumDuty = 100.0  // ₹100 minimum
	} else if strings.Contains(sizeLower, "750") {
		dutyRate = 0.35      // 35%
		minimumDuty = 200.0  // ₹200 minimum
	} else if strings.Contains(sizeLower, "1l") || strings.Contains(sizeLower, "1000") {
		dutyRate = 0.40      // 40%
		minimumDuty = 300.0  // ₹300 minimum
	} else {
		// Default for unknown sizes
		dutyRate = 0.30
		minimumDuty = 100.0
	}

	// Calculate duty
	calculatedDuty := costPrice * dutyRate

	// Apply minimum duty
	if calculatedDuty < minimumDuty {
		return minimumDuty
	}

	return calculatedDuty
}

// generateProductSKU generates unique SKU for product
func (s *EnhancedProductService) generateProductSKU(brandName, size string) string {
	// Clean brand name (remove spaces, special characters)
	cleanBrand := strings.ToUpper(strings.ReplaceAll(brandName, " ", ""))
	if len(cleanBrand) > 6 {
		cleanBrand = cleanBrand[:6]
	}

	// Clean size
	cleanSize := strings.ToUpper(strings.ReplaceAll(size, " ", ""))

	// Generate timestamp-based unique code
	timestamp := time.Now().Format("0601021504")

	return fmt.Sprintf("%s-%s-%s", cleanBrand, cleanSize, timestamp)
}

// CheckDuplicateProduct checks if a product with Brand + Size already exists
func (s *EnhancedProductService) CheckDuplicateProduct(ctx context.Context, tenantID, brandID uuid.UUID, size string) (bool, *models.Product, error) {
	var existingProduct models.Product

	err := s.db.Where("brand_id = ? AND size = ? AND tenant_id = ?", brandID, size, tenantID).
		Preload("Brand").
		Preload("Category").
		First(&existingProduct).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false, nil, nil
		}
		return false, nil, fmt.Errorf("failed to check for duplicate: %w", err)
	}

	return true, &existingProduct, nil
}

// UpdateProductPricing updates product pricing (for tenant customization)
func (s *EnhancedProductService) UpdateProductPricing(ctx context.Context, productID, tenantID uuid.UUID, req UpdatePricingRequest) (*models.Product, error) {
	var product models.Product

	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("product not found")
		}
		return nil, fmt.Errorf("failed to find product: %w", err)
	}

	// Update pricing
	if req.CostPrice != nil {
		product.CostPrice = *req.CostPrice
	}
	if req.DutyFee != nil {
		product.DutyFee = *req.DutyFee
	}

	// Total cost equals cost price (cost price already includes duty)
	// duty_fee is stored for display/breakdown purposes only
	product.TotalCost = product.CostPrice

	if req.SellingPrice != nil {
		// Validate selling price - must be greater than cost price for profit
		if *req.SellingPrice < product.TotalCost {
			return nil, fmt.Errorf("selling price (%.2f) must be greater than cost price (%.2f)", *req.SellingPrice, product.TotalCost)
		}
		product.SellingPrice = *req.SellingPrice
	}

	if req.MRP != nil {
		product.MRP = *req.MRP
	}

	if req.Description != nil {
		product.Description = *req.Description
	}

	// Save updates
	if err := s.db.Save(&product).Error; err != nil {
		return nil, fmt.Errorf("failed to update product: %w", err)
	}

	// Load relationships
	s.db.Preload("Category").Preload("Brand").First(&product, product.ID)

	return &product, nil
}

// GetProductsByBrand returns all products for a specific brand
func (s *EnhancedProductService) GetProductsByBrand(ctx context.Context, tenantID, brandID uuid.UUID) ([]models.Product, error) {
	var products []models.Product

	err := s.db.Where("brand_id = ? AND tenant_id = ?", brandID, tenantID).
		Preload("Category").
		Preload("Brand").
		Preload("Stocks").
		Order("size ASC").
		Find(&products).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get products by brand: %w", err)
	}

	return products, nil
}

// GetProductsGroupedByBrand returns products grouped by brand
func (s *EnhancedProductService) GetProductsGroupedByBrand(ctx context.Context, tenantID uuid.UUID) (map[string][]models.Product, error) {
	var products []models.Product

	err := s.db.Where("tenant_id = ?", tenantID).
		Preload("Category").
		Preload("Brand").
		Order("brand_id, size ASC").
		Find(&products).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get products: %w", err)
	}

	// Group by brand
	grouped := make(map[string][]models.Product)
	for _, product := range products {
		if product.Brand != nil {
			brandName := product.Brand.Name
			grouped[brandName] = append(grouped[brandName], product)
		}
	}

	return grouped, nil
}

// Response structures

// BrandWithVariantsResponse represents response when creating brand with variants
type BrandWithVariantsResponse struct {
	Brand           *models.Brand     `json:"brand"`
	ProductsCreated int               `json:"products_created"`
	Products        []models.Product  `json:"products"`
	DuplicatesFound []string          `json:"duplicates_found,omitempty"`
	Errors          []string          `json:"errors,omitempty"`
}

// UpdatePricingRequest represents pricing update request
type UpdatePricingRequest struct {
	CostPrice    *float64 `json:"cost_price"`
	DutyFee      *float64 `json:"duty_fee"`
	SellingPrice *float64 `json:"selling_price"`
	MRP          *float64 `json:"mrp"`
	Description  *string  `json:"description"`
}
