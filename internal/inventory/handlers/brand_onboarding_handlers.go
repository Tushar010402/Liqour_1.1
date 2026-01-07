package handlers

import (
	"net/http"
	"strings"

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
// @Description Get all active brand templates from SaaS admin for onboarding, with is_onboarded status
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/available [get]
func (h *BrandOnboardingHandler) GetAvailableBrandTemplates(c *gin.Context) {
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

	templates, err := h.brandOnboardingService.GetAvailableBrandTemplates(tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch brand templates",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand templates retrieved successfully",
		"data":    templates,
		"count":   len(templates),
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

	// DEBUG: Log request details
	println("🔍 OnboardBrands handler called")
	println("   Tenant ID:", req.TenantID.String())
	println("   Brand IDs count:", len(req.BrandIDs))
	println("   Variant IDs count:", len(req.VariantIDs))
	if len(req.VariantIDs) > 0 {
		println("   First variant ID:", req.VariantIDs[0].String())
	}

	response, err := h.brandOnboardingService.OnboardBrandsToTenant(req)
	if err != nil {
		println("❌ OnboardBrands error:", err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to onboard brands",
			"details": err.Error(),
		})
		return
	}

	println("✅ OnboardBrands success:")
	println("   Onboarded brands:", response.OnboardedBrands)
	println("   Onboarded products:", response.OnboardedProducts)
	println("   Brand details count:", len(response.BrandDetails))

	statusCode := http.StatusOK
	if response.OnboardedBrands == 0 {
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
			"code":  "MISSING_TENANT_ID",
		})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid tenant ID",
			"code":    "INVALID_TENANT_ID",
			"details": err.Error(),
		})
		return
	}

	productID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid product ID",
			"code":    "INVALID_PRODUCT_ID",
			"details": err.Error(),
		})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"code":    "INVALID_REQUEST",
			"details": err.Error(),
		})
		return
	}

	if err := h.brandOnboardingService.UpdateOnboardedBrand(tenantID, productID, updates); err != nil {
		statusCode := http.StatusBadRequest
		errorCode := "UPDATE_FAILED"

		if strings.Contains(err.Error(), "not found") {
			statusCode = http.StatusNotFound
			errorCode = "PRODUCT_NOT_FOUND"
		} else if strings.Contains(err.Error(), "deleted") {
			statusCode = http.StatusGone
			errorCode = "PRODUCT_DELETED"
		}

		c.JSON(statusCode, gin.H{
			"error":      "Failed to update onboarded brand",
			"code":       errorCode,
			"details":    err.Error(),
			"tenant_id":  tenantID.String(),
			"product_id": productID.String(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Onboarded brand updated successfully",
		"product_id": productID.String(),
	})
}

// GetBrandMetadata returns categories and subcategories for brand creation
// @Summary Get brand metadata (categories and subcategories)
// @Description Fetches categories and subcategories from SaaS service for brand creation forms
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/metadata [get]
func (h *BrandOnboardingHandler) GetBrandMetadata(c *gin.Context) {
	metadata, err := h.brandOnboardingService.GetBrandMetadata()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Failed to fetch brand metadata",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    metadata,
	})
}

// RefreshBrandCache clears the brand template cache to fetch fresh data from SaaS
// @Summary Refresh brand cache
// @Description Clears the cached brand templates to force fresh fetch from SaaS service
// @Tags Brand Onboarding
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Router /api/inventory/saas-brands/refresh-cache [post]
func (h *BrandOnboardingHandler) RefreshBrandCache(c *gin.Context) {
	h.brandOnboardingService.ClearCache()
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Brand cache cleared successfully. Next request will fetch fresh data from SaaS.",
	})
}
