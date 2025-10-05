package handlers

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

// BrandHandler handles brand management API endpoints
type BrandHandler struct {
	brandService *services.BrandService
}

// NewBrandHandler creates a new brand handler
func NewBrandHandler(brandService *services.BrandService) *BrandHandler {
	return &BrandHandler{
		brandService: brandService,
	}
}

// CreateBrand creates a new SaaS brand
// @Summary Create a new brand
// @Description Create a new brand in the SaaS system
// @Tags Brands
// @Accept json
// @Produce json
// @Param brand body services.CreateBrandRequest true "Brand data"
// @Success 201 {object} services.BrandResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands [post]
func (h *BrandHandler) CreateBrand(c *gin.Context) {
	var req services.CreateBrandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	brand, err := h.brandService.CreateBrand(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create brand",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Brand created successfully",
		"data":    brand,
	})
}

// CreateBrandVariant creates a new brand variant
// @Summary Create a new brand variant
// @Description Create a new variant for an existing brand
// @Tags Brands
// @Accept json
// @Produce json
// @Param variant body services.CreateBrandVariantRequest true "Brand variant data"
// @Success 201 {object} services.BrandVariantResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/variants [post]
func (h *BrandHandler) CreateBrandVariant(c *gin.Context) {
	var req services.CreateBrandVariantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	variant, err := h.brandService.CreateBrandVariant(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create brand variant",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Brand variant created successfully",
		"data":    variant,
	})
}

// GetAllBrands gets all SaaS brands
// @Summary Get all brands
// @Description Get brands with optional filtering and variants
// @Tags Brands
// @Produce json
// @Param include_variants query bool false "Include variants in response"
// @Param active_only query bool false "Show only active brands (default: false for admin management)"
// @Success 200 {array} services.BrandResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/brands [get]
func (h *BrandHandler) GetAllBrands(c *gin.Context) {
	includeVariants := c.Query("include_variants") == "true"
	// For admin dashboard, default to showing all brands (active + inactive) for management
	activeOnly := c.Query("active_only") == "true"

	brands, err := h.brandService.GetAllBrandsWithFilter(includeVariants, activeOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brands",
			"details": err.Error(),
		})
		return
	}

	// Count active and inactive brands
	activeCount := 0
	inactiveCount := 0
	for _, brand := range brands {
		if brand.IsActive {
			activeCount++
		} else {
			inactiveCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":        "Brands retrieved successfully",
		"data":           brands,
		"count":          len(brands),
		"active_count":   activeCount,
		"inactive_count": inactiveCount,
	})
}

// GetBrandsInternal is an internal API for service-to-service communication
// Used by inventory service to fetch brand templates
// @Summary Get brands for internal service communication
// @Description Internal endpoint for inventory service to fetch brand templates
// @Tags Internal
// @Produce json
// @Param include_variants query bool false "Include variants in response"
// @Param active_only query bool false "Show only active brands"
// @Success 200 {array} services.BrandResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/internal/brands [get]
func (h *BrandHandler) GetBrandsInternal(c *gin.Context) {
	includeVariants := c.Query("include_variants") == "true"
	activeOnly := c.Query("active_only") == "true"

	brands, err := h.brandService.GetAllBrandsWithFilter(includeVariants, activeOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brands",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand templates retrieved successfully",
		"data":    brands,
		"count":   len(brands),
	})
}

// GetBrandByID gets a specific brand by ID
// @Summary Get brand by ID
// @Description Get a specific brand with its variants
// @Tags Brands
// @Produce json
// @Param id path string true "Brand ID"
// @Success 200 {object} services.BrandResponse
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Router /api/super-admin/brands/{id} [get]
func (h *BrandHandler) GetBrandByID(c *gin.Context) {
	brandID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid brand ID",
		})
		return
	}

	brand, err := h.brandService.GetBrandByID(brandID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "Brand not found",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand retrieved successfully",
		"data":    brand,
	})
}

// GetBrandVariants gets variants for a specific brand
// @Summary Get brand variants
// @Description Get all variants for a specific brand
// @Tags Brands
// @Produce json
// @Param id path string true "Brand ID"
// @Success 200 {array} services.BrandVariantResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/{id}/variants [get]
func (h *BrandHandler) GetBrandVariants(c *gin.Context) {
	brandID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid brand ID",
		})
		return
	}

	variants, err := h.brandService.GetBrandVariants(brandID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand variants",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand variants retrieved successfully",
		"data":    variants,
		"count":   len(variants),
	})
}

// UpdateBrand updates an existing brand
// @Summary Update brand
// @Description Update an existing brand
// @Tags Brands
// @Accept json
// @Produce json
// @Param id path string true "Brand ID"
// @Param brand body services.CreateBrandRequest true "Updated brand data"
// @Success 200 {object} services.BrandResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/{id} [put]
func (h *BrandHandler) UpdateBrand(c *gin.Context) {
	brandID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid brand ID",
		})
		return
	}

	var req services.CreateBrandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	brand, err := h.brandService.UpdateBrand(brandID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to update brand",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand updated successfully",
		"data":    brand,
	})
}

// UpdateBrandVariant updates an existing brand variant
// @Summary Update brand variant
// @Description Update an existing brand variant
// @Tags Brands
// @Accept json
// @Produce json
// @Param id path string true "Variant ID"
// @Param variant body services.CreateBrandVariantRequest true "Updated variant data"
// @Success 200 {object} services.BrandVariantResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/variants/{id} [put]
func (h *BrandHandler) UpdateBrandVariant(c *gin.Context) {
	variantID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid variant ID",
		})
		return
	}

	var req services.CreateBrandVariantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	variant, err := h.brandService.UpdateBrandVariant(variantID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to update brand variant",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand variant updated successfully",
		"data":    variant,
	})
}

// DeleteBrand deletes a brand (soft delete)
// @Summary Delete brand
// @Description Soft delete a brand by setting is_active to false
// @Tags Brands
// @Produce json
// @Param id path string true "Brand ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/{id} [delete]
func (h *BrandHandler) DeleteBrand(c *gin.Context) {
	brandID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid brand ID",
		})
		return
	}

	err = h.brandService.DeleteBrand(brandID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to delete brand",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand deleted successfully",
	})
}

// AssignBrandsToTenant assigns selected brands to a tenant
// @Summary Assign brands to tenant
// @Description Assign selected brands and variants to a specific tenant
// @Tags Brands
// @Accept json
// @Produce json
// @Param assignment body services.TenantBrandSelectionRequest true "Brand assignment data"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/assign [post]
func (h *BrandHandler) AssignBrandsToTenant(c *gin.Context) {
	var req services.TenantBrandSelectionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	err := h.brandService.AssignBrandsToTenant(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to assign brands to tenant",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brands assigned to tenant successfully",
	})
}

// GetTenantBrands gets brands assigned to a tenant
// @Summary Get tenant brands
// @Description Get brands assigned to a specific tenant
// @Tags Brands
// @Produce json
// @Param tenant_id path string true "Tenant ID"
// @Success 200 {array} services.BrandResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/tenants/{tenant_id}/brands [get]
func (h *BrandHandler) GetTenantBrands(c *gin.Context) {
	tenantID, err := uuid.Parse(c.Param("tenant_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid tenant ID",
		})
		return
	}

	brands, err := h.brandService.GetTenantBrands(tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch tenant brands",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Tenant brands retrieved successfully",
		"data":    brands,
		"count":   len(brands),
	})
}

// GetPublicBrands gets all brands available for tenant selection
// @Summary Get public brands
// @Description Get all active brands available for tenant selection
// @Tags Public
// @Produce json
// @Param include_variants query bool false "Include variants in response"
// @Param category_id query string false "Filter by category ID"
// @Param page query int false "Page number" default(1)
// @Param limit query int false "Items per page" default(20)
// @Success 200 {array} services.BrandResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/brands/public [get]
func (h *BrandHandler) GetPublicBrands(c *gin.Context) {
	includeVariants := c.Query("include_variants") == "true"

	// For now, just return all brands - can be enhanced with filtering later
	brands, err := h.brandService.GetAllBrands(includeVariants)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brands",
			"details": err.Error(),
		})
		return
	}

	// Basic pagination
	page := 1
	limit := 20
	if pageStr := c.Query("page"); pageStr != "" {
		if p, err := strconv.Atoi(pageStr); err == nil && p > 0 {
			page = p
		}
	}
	if limitStr := c.Query("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	start := (page - 1) * limit
	end := start + limit
	total := len(brands)

	if start >= total {
		brands = []services.BrandResponse{}
	} else {
		if end > total {
			end = total
		}
		brands = brands[start:end]
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Public brands retrieved successfully",
		"data":    brands,
		"pagination": gin.H{
			"page":  page,
			"limit": limit,
			"total": total,
			"pages": (total + limit - 1) / limit,
		},
	})
}

// BulkCreateBrands creates multiple brands with variants
// @Summary Bulk create brands
// @Description Create multiple brands with their variants in one request
// @Tags Brands
// @Accept json
// @Produce json
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/bulk [post]
func (h *BrandHandler) BulkCreateBrands(c *gin.Context) {
	type BulkBrandRequest struct {
		Brand    services.CreateBrandRequest          `json:"brand"`
		Variants []services.CreateBrandVariantRequest `json:"variants"`
	}

	var req []BulkBrandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	var createdBrands []services.BrandResponse
	var errors []string

	for i, brandReq := range req {
		// Create brand
		brand, err := h.brandService.CreateBrand(brandReq.Brand)
		if err != nil {
			errors = append(errors, fmt.Sprintf("Brand %d: %s", i+1, err.Error()))
			continue
		}

		// Create variants for this brand
		for j, variantReq := range brandReq.Variants {
			variantReq.BrandID = brand.ID
			_, err := h.brandService.CreateBrandVariant(variantReq)
			if err != nil {
				errors = append(errors, fmt.Sprintf("Brand %d, Variant %d: %s", i+1, j+1, err.Error()))
			}
		}

		createdBrands = append(createdBrands, *brand)
	}

	response := gin.H{
		"message":        "Bulk brand creation completed",
		"created_brands": createdBrands,
		"total_created":  len(createdBrands),
	}

	if len(errors) > 0 {
		response["errors"] = errors
		response["error_count"] = len(errors)
	}

	statusCode := http.StatusCreated
	if len(errors) > 0 && len(createdBrands) == 0 {
		statusCode = http.StatusBadRequest
	}

	c.JSON(statusCode, response)
}

// CreateBrandCategory creates a new brand category
func (h *BrandHandler) CreateBrandCategory(c *gin.Context) {
	var req services.CreateBrandCategoryRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	category, err := h.brandService.CreateBrandCategory(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create category",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Brand category created successfully",
		"data":    category,
	})
}

// CreateBrandSubcategory creates a new brand subcategory
func (h *BrandHandler) CreateBrandSubcategory(c *gin.Context) {
	var req services.CreateBrandSubcategoryRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	subcategory, err := h.brandService.CreateBrandSubcategory(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create subcategory",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Brand subcategory created successfully",
		"data":    subcategory,
	})
}

// GetAllBrandCategories gets all brand categories
// @Summary Get all brand categories
// @Description Get all active brand categories
// @Tags Brands
// @Produce json
// @Success 200 {array} services.BrandCategoryResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/brands/categories [get]
func (h *BrandHandler) GetAllBrandCategories(c *gin.Context) {
	categories, err := h.brandService.GetAllBrandCategories()
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

// GetBrandSubcategories gets brand subcategories
// @Summary Get brand subcategories
// @Description Get brand subcategories, optionally filtered by category
// @Tags Brands
// @Produce json
// @Param category_id query string false "Filter by category ID"
// @Success 200 {array} services.BrandSubcategoryResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/brands/subcategories [get]
func (h *BrandHandler) GetBrandSubcategories(c *gin.Context) {
	categoryID := c.Query("category_id")

	subcategories, err := h.brandService.GetBrandSubcategories(categoryID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand subcategories",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand subcategories retrieved successfully",
		"data":    subcategories,
		"count":   len(subcategories),
	})
}

// DeleteBrandVariant deletes a brand variant (soft delete)
// @Summary Delete brand variant
// @Description Soft delete a brand variant by setting is_active to false
// @Tags Brands
// @Produce json
// @Param id path string true "Variant ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/variants/{id} [delete]
func (h *BrandHandler) DeleteBrandVariant(c *gin.Context) {
	variantID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid variant ID",
		})
		return
	}

	err = h.brandService.DeleteBrandVariant(variantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to delete brand variant",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand variant deleted successfully",
	})
}

// UpdateBrandCategory updates an existing brand category
// @Summary Update brand category
// @Description Update an existing brand category
// @Tags Brands
// @Accept json
// @Produce json
// @Param id path string true "Category ID"
// @Param category body services.CreateBrandCategoryRequest true "Updated category data"
// @Success 200 {object} services.BrandCategoryResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/categories/{id} [put]
func (h *BrandHandler) UpdateBrandCategory(c *gin.Context) {
	categoryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid category ID",
		})
		return
	}

	var req services.CreateBrandCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	category, err := h.brandService.UpdateBrandCategory(categoryID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to update brand category",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand category updated successfully",
		"data":    category,
	})
}

// DeleteBrandCategory deletes a brand category (soft delete)
// @Summary Delete brand category
// @Description Soft delete a brand category by setting is_active to false
// @Tags Brands
// @Produce json
// @Param id path string true "Category ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/categories/{id} [delete]
func (h *BrandHandler) DeleteBrandCategory(c *gin.Context) {
	categoryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid category ID",
		})
		return
	}

	err = h.brandService.DeleteBrandCategory(categoryID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to delete brand category",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand category deleted successfully",
	})
}

// UpdateBrandSubcategory updates an existing brand subcategory
// @Summary Update brand subcategory
// @Description Update an existing brand subcategory
// @Tags Brands
// @Accept json
// @Produce json
// @Param id path string true "Subcategory ID"
// @Param subcategory body services.CreateBrandSubcategoryRequest true "Updated subcategory data"
// @Success 200 {object} services.BrandSubcategoryResponse
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/subcategories/{id} [put]
func (h *BrandHandler) UpdateBrandSubcategory(c *gin.Context) {
	subcategoryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid subcategory ID",
		})
		return
	}

	var req services.CreateBrandSubcategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	subcategory, err := h.brandService.UpdateBrandSubcategory(subcategoryID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to update brand subcategory",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand subcategory updated successfully",
		"data":    subcategory,
	})
}

// DeleteBrandSubcategory deletes a brand subcategory (soft delete)
// @Summary Delete brand subcategory
// @Description Soft delete a brand subcategory by setting is_active to false
// @Tags Brands
// @Produce json
// @Param id path string true "Subcategory ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/subcategories/{id} [delete]
func (h *BrandHandler) DeleteBrandSubcategory(c *gin.Context) {
	subcategoryID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid subcategory ID",
		})
		return
	}

	err = h.brandService.DeleteBrandSubcategory(subcategoryID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to delete brand subcategory",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand subcategory deleted successfully",
	})
}

// BulkAssignBrandsToTenants assigns brands to multiple tenants at once
// @Summary Bulk assign brands to tenants
// @Description Assign selected brands to multiple tenants for easier onboarding
// @Tags Brands
// @Accept json
// @Produce json
// @Param assignment body services.BulkTenantBrandAssignmentRequest true "Bulk brand assignment data"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/bulk-assign [post]
func (h *BrandHandler) BulkAssignBrandsToTenants(c *gin.Context) {
	var req services.BulkTenantBrandAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	result, err := h.brandService.BulkAssignBrandsToTenants(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to bulk assign brands to tenants",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brands assigned to tenants successfully",
		"data":    result,
	})
}

// AssignBrandPackageToTenant assigns a preset brand package to a tenant
// @Summary Assign brand package to tenant
// @Description Assign a preset brand package for quick tenant onboarding
// @Tags Brands
// @Accept json
// @Produce json
// @Param assignment body services.TenantBrandPackageRequest true "Brand package assignment data"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/brands/assign-package [post]
func (h *BrandHandler) AssignBrandPackageToTenant(c *gin.Context) {
	var req services.TenantBrandPackageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	err := h.brandService.AssignBrandPackageToTenant(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to assign brand package to tenant",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand package assigned to tenant successfully",
	})
}

// GetBrandPackages gets available brand packages for tenant onboarding
// @Summary Get brand packages
// @Description Get available brand packages for quick tenant setup
// @Tags Brands
// @Produce json
// @Success 200 {array} services.BrandPackageResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/brands/packages [get]
func (h *BrandHandler) GetBrandPackages(c *gin.Context) {
	packages, err := h.brandService.GetBrandPackages()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand packages",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand packages retrieved successfully",
		"data":    packages,
		"count":   len(packages),
	})
}

// GetTenantOnboardingStats gets tenant onboarding statistics
// @Summary Get tenant onboarding stats
// @Description Get statistics about tenant brand assignments for onboarding tracking
// @Tags Brands
// @Produce json
// @Success 200 {object} services.TenantOnboardingStatsResponse
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/brands/onboarding-stats [get]
func (h *BrandHandler) GetTenantOnboardingStats(c *gin.Context) {
	stats, err := h.brandService.GetTenantOnboardingStats()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch onboarding stats",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Tenant onboarding stats retrieved successfully",
		"data":    stats,
	})
}

// CleanupSoftDeletedRecords permanently removes all soft-deleted brand-related records
// @Summary Cleanup soft-deleted records
// @Description Permanently removes all soft-deleted brand-related records from the database
// @Tags Brands
// @Produce json
// @Success 200 {object} map[string]interface{} "Success response"
// @Failure 500 {object} map[string]interface{} "Internal server error"
// @Router /api/super-admin/brands/cleanup [post]
func (h *BrandHandler) CleanupSoftDeletedRecords(c *gin.Context) {
	err := h.brandService.CleanupSoftDeletedRecords()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to cleanup soft-deleted records",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Soft-deleted records cleaned up successfully",
	})
}
