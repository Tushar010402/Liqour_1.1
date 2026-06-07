package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// BrandOnboardingHandler handles brand onboarding from SaaS templates
type BrandOnboardingHandler struct {
	brandOnboardingService *services.BrandOnboardingService
}

// NewBrandOnboardingHandler creates a new brand onboarding handler
func NewBrandOnboardingHandler(brandOnboardingService *services.BrandOnboardingService) *BrandOnboardingHandler {
	return &BrandOnboardingHandler{
		brandOnboardingService: brandOnboardingService,
	}
}

// GetAvailableBrandTemplates returns all SaaS brand templates available for onboarding
// @Summary Get available SaaS brand templates
// @Description Get all active brand templates from SaaS admin for onboarding
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/available [get]
func (h *BrandOnboardingHandler) GetAvailableBrandTemplates(c *gin.Context) {
	templates, err := h.brandOnboardingService.GetAvailableBrandTemplates()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand templates",
			"details": err.Error(),
		})
		return
	}

	// Get tenant ID to check which brands are already onboarded
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		// Try header directly as fallback
		tenantIDStr = c.GetHeader("X-Tenant-ID")
	}

	if tenantIDStr != "" {
		tenantID, err := uuid.Parse(tenantIDStr)
		if err == nil {
			// Parse shop_id for shop-scoped onboarding status
			var shopID *uuid.UUID
			if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
				if parsed, err := uuid.Parse(shopIDStr); err == nil {
					shopID = &parsed
				}
			}
			// Mark already onboarded brands/variants for this tenant+shop
			templates = h.brandOnboardingService.MarkOnboardedBrands(templates, tenantID, shopID)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Brand templates retrieved successfully",
		"data":      templates,
		"count":     len(templates),
	})
}

// OnboardBrands onboards selected SaaS brand templates to tenant's inventory
// @Summary Onboard SaaS brand templates
// @Description Onboard selected SaaS brand templates to create products in tenant inventory
// @Tags Brand Onboarding
// @Accept json
// @Produce json
// @Param request body services.OnboardBrandRequest true "Onboard brand request"
// @Success 200 {object} services.OnboardBrandResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/onboard [post]
func (h *BrandOnboardingHandler) OnboardBrands(c *gin.Context) {
	var req services.OnboardBrandRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	// Get tenant ID from context (set by auth middleware)
	if tenantID := c.GetString("tenant_id"); tenantID != "" {
		parsedTenantID, err := uuid.Parse(tenantID)
		if err == nil {
			req.TenantID = parsedTenantID
		}
	}

	response, err := h.brandOnboardingService.OnboardBrandsToTenant(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to onboard brands",
			"details": err.Error(),
		})
		return
	}

	// Return 206 Partial Content if there were errors during onboarding
	statusCode := http.StatusOK
	if len(response.Errors) > 0 {
		statusCode = http.StatusPartialContent
	}

	// Set cache-control headers to prevent client-side caching
	c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
	c.Header("Pragma", "no-cache")
	c.Header("Expires", "0")

	c.JSON(statusCode, gin.H{
		"message": "Brand onboarding completed",
		"data":    response,
	})
}

// GetOnboardedBrands returns products onboarded from SaaS templates
// @Summary Get onboarded SaaS brands
// @Description Get all products that were onboarded from SaaS brand templates
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/onboarded [get]
func (h *BrandOnboardingHandler) GetOnboardedBrands(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Tenant ID not found in context",
		})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid tenant ID",
			"details": err.Error(),
		})
		return
	}

	products, err := h.brandOnboardingService.GetOnboardedBrands(tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch onboarded brands",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Onboarded brands retrieved successfully",
		"data":    products,
		"count":   len(products),
	})
}

// GetCustomBrands returns products created by tenant (not from SaaS templates)
// @Summary Get custom brands
// @Description Get all products created by tenant (not from SaaS templates)
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/brands/custom [get]
func (h *BrandOnboardingHandler) GetCustomBrands(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Tenant ID not found in context",
		})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid tenant ID",
			"details": err.Error(),
		})
		return
	}

	products, err := h.brandOnboardingService.GetCustomBrands(tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch custom brands",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Custom brands retrieved successfully",
		"data":    products,
		"count":   len(products),
	})
}

// CreateCustomBrand creates a new custom brand for items that don't match SaaS brands
// @Summary Create custom brand
// @Description Create a new custom brand when OCR item doesn't match any SaaS brand
// @Tags Brand Onboarding
// @Accept json
// @Produce json
// @Param request body services.CreateCustomBrandRequest true "Custom brand request"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/brands/custom [post]
func (h *BrandOnboardingHandler) CreateCustomBrand(c *gin.Context) {
	var req services.CreateCustomBrandRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	// Get tenant ID from context (set by auth middleware)
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Tenant ID not found in context",
		})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid tenant ID",
			"details": err.Error(),
		})
		return
	}
	req.TenantID = tenantID

	// Get user ID for audit trail
	if userIDStr := c.GetString("user_id"); userIDStr != "" {
		if userID, err := uuid.Parse(userIDStr); err == nil {
			req.CreatedBy = &userID
		}
	}

	response, err := h.brandOnboardingService.CreateCustomBrand(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create custom brand",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Custom brand created successfully",
		"data":    response,
	})
}

// GetBrandCategories returns all categories with brand counts
// @Summary Get brand categories
// @Description Get all categories with brand counts for category-first navigation
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/categories [get]
func (h *BrandOnboardingHandler) GetBrandCategories(c *gin.Context) {
	categories, err := h.brandOnboardingService.GetBrandCategories()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand categories",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand categories retrieved successfully",
		"data":    categories,
		"count":   len(categories),
	})
}

// GetBrandsByCategory returns brands paginated by category
// @Summary Get brands by category with pagination
// @Description Get brands filtered by category with pagination support
// @Tags Brand Onboarding
// @Produce json
// @Param category_id query string false "Category ID to filter by"
// @Param page query int false "Page number (default: 1)"
// @Param limit query int false "Items per page (default: 30)"
// @Param search query string false "Search query"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/paginated [get]
func (h *BrandOnboardingHandler) GetBrandsByCategory(c *gin.Context) {
	var req services.PaginatedBrandRequest

	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid query parameters",
			"details": err.Error(),
		})
		return
	}

	// Set defaults
	if req.Page < 1 {
		req.Page = 1
	}
	if req.Limit < 1 || req.Limit > 100 {
		req.Limit = 30
	}

	response, err := h.brandOnboardingService.GetBrandsPaginated(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brands",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brands retrieved successfully",
		"data":    response,
	})
}

// UpdateOnboardedBrand allows tenant to customize an onboarded brand
// @Summary Update/customize onboarded brand
// @Description Update an onboarded brand to customize it for tenant needs
// @Tags Brand Onboarding
// @Accept json
// @Produce json
// @Param id path string true "Product ID"
// @Param updates body map[string]interface{} true "Fields to update"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/onboarded/{id} [put]
func (h *BrandOnboardingHandler) UpdateOnboardedBrand(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Tenant ID not found in context",
		})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid tenant ID",
			"details": err.Error(),
		})
		return
	}

	productID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid product ID",
			"details": err.Error(),
		})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	if err := h.brandOnboardingService.UpdateOnboardedBrand(tenantID, productID, updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to update onboarded brand",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Onboarded brand updated successfully",
	})
}

// GetBrandMetadata returns all metadata (categories, subcategories, sizes) for creating custom brands
// @Summary Get brand metadata
// @Description Get all categories, subcategories, and common sizes for brand creation
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/metadata [get]
func (h *BrandOnboardingHandler) GetBrandMetadata(c *gin.Context) {
	metadata, err := h.brandOnboardingService.GetBrandMetadata()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand metadata",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand metadata retrieved successfully",
		"data":    metadata,
	})
}

// GetSubcategoriesByCategory returns subcategories for a specific category
// @Summary Get subcategories by category
// @Description Get all subcategories for a specific category ID
// @Tags Brand Onboarding
// @Produce json
// @Param category_id query string true "Category ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/subcategories [get]
func (h *BrandOnboardingHandler) GetSubcategoriesByCategory(c *gin.Context) {
	categoryID := c.Query("category_id")
	if categoryID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "category_id query parameter is required",
		})
		return
	}

	subcategories, err := h.brandOnboardingService.GetSubcategoriesByCategory(categoryID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch subcategories",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Subcategories retrieved successfully",
		"data":        subcategories,
		"count":       len(subcategories),
		"category_id": categoryID,
	})
}

// GetSaaSBrandCategories returns all SaaS brand categories (for editing)
// @Summary Get brand categories for editing
// @Description Get all active brand categories from SaaS admin for editing products
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/brand-categories [get]
func (h *BrandOnboardingHandler) GetSaaSBrandCategories(c *gin.Context) {
	categories, err := h.brandOnboardingService.GetSaaSCategories()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch brand categories",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Brand categories retrieved successfully",
		"data":    categories,
	})
}

// GetSaaSBrandSubcategories returns all SaaS brand subcategories or filtered by category (for editing)
// @Summary Get brand subcategories for editing
// @Description Get all brand subcategories from SaaS admin, optionally filtered by category, for editing products
// @Tags Brand Onboarding
// @Produce json
// @Param category_id query string false "Filter by Category ID"
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/brand-subcategories [get]
func (h *BrandOnboardingHandler) GetSaaSBrandSubcategories(c *gin.Context) {
	categoryIDStr := c.Query("category_id")

	var categoryID *uuid.UUID
	if categoryIDStr != "" {
		parsed, err := uuid.Parse(categoryIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "Invalid category_id format",
			})
			return
		}
		categoryID = &parsed
	}

	subcategories, err := h.brandOnboardingService.GetSaaSSubcategories(categoryID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch brand subcategories",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Brand subcategories retrieved successfully",
		"data":    subcategories,
	})
}

// GetSaaSCategorySizes returns category sizes, optionally filtered by category (for editing)
// @Summary Get category sizes for editing
// @Description Get all category sizes from SaaS admin, optionally filtered by category, for editing products
// @Tags Brand Onboarding
// @Produce json
// @Param category_id query string false "Filter by Category ID"
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/category-sizes [get]
func (h *BrandOnboardingHandler) GetSaaSCategorySizes(c *gin.Context) {
	categoryIDStr := c.Query("category_id")

	var categoryID *uuid.UUID
	if categoryIDStr != "" {
		parsed, err := uuid.Parse(categoryIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"success": false,
				"error":   "Invalid category_id format",
			})
			return
		}
		categoryID = &parsed
	}

	sizes, err := h.brandOnboardingService.GetSaaSCategorySizes(categoryID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch category sizes",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Category sizes retrieved successfully",
		"data":    sizes,
	})
}
