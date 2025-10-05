package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/inventory/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all inventory service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, inventoryHandlers *handlers.InventoryHandlers) {
	// Health check
	router.GET("/health", inventoryHandlers.Health)

	// All routes require authentication and tenant isolation
	api := router.Group("/api")
	api.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	api.Use(middleware.TenantMiddleware())

	// Product Routes (Core inventory items)
	products := api.Group("/products")
	{
		products.GET("", inventoryHandlers.GetProducts)
		products.POST("", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreateProduct)
		products.GET("/:id", inventoryHandlers.GetProductByID)
		products.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.UpdateProduct)
		products.DELETE("/:id", middleware.RoleMiddleware("admin"), inventoryHandlers.DeleteProduct)
	}

	// Stock Management Routes (Critical for inventory tracking)
	stocks := api.Group("/stocks")
	{
		stocks.GET("", inventoryHandlers.GetStocks)
		stocks.POST("/adjust", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.AdjustStock)
		stocks.POST("/transfer", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.TransferStock)
		stocks.GET("/movements", inventoryHandlers.GetStockMovements)
	}

	// Purchase/Receiving Routes (Stock intake)
	purchases := api.Group("/purchases")
	{
		purchases.GET("", inventoryHandlers.GetPurchases)
		purchases.POST("", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreatePurchase)
		purchases.GET("/:id", inventoryHandlers.GetPurchaseByID)
		purchases.POST("/:id/receive", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.ReceivePurchase)
	}

	// Category Management Routes
	categories := api.Group("/categories")
	{
		categories.GET("", inventoryHandlers.GetCategories)
		categories.POST("", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreateCategory)
		categories.GET("/:id", inventoryHandlers.GetCategoryByID)
		categories.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.UpdateCategory)
		categories.DELETE("/:id", middleware.RoleMiddleware("admin"), inventoryHandlers.DeleteCategory)
	}

	// Brand Management Routes
	brands := api.Group("/brands")
	{
		brands.GET("", inventoryHandlers.GetBrands)
		brands.POST("", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreateBrand)
		brands.GET("/:id", inventoryHandlers.GetBrandByID)
		brands.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.UpdateBrand)
		brands.DELETE("/:id", middleware.RoleMiddleware("admin"), inventoryHandlers.DeleteBrand)

		// SaaS Brand Integration
		brands.GET("/saas/available", inventoryHandlers.GetAvailableBrands)
		brands.GET("/saas/tenant", inventoryHandlers.GetTenantBrands)
		brands.POST("/saas/select", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.SelectBrandsFromCatalog)
		brands.POST("/saas/customize", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CustomizeBrandVariant)
		brands.POST("/saas/import-as-products", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.ImportBrandsAsProducts)

		// Legacy compatibility endpoints
		brands.GET("/available", inventoryHandlers.GetAvailableBrands)
		brands.GET("/my-brands", inventoryHandlers.GetTenantBrands)
		brands.POST("/create-product", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreateProductFromBrand)
		brands.GET("/products", inventoryHandlers.GetProductsFromBrands)
		brands.POST("/sync-pricing", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.SyncBrandPricing)
	}

	// Product Catalog Routes (Templates for stock creation)
	catalog := api.Group("/catalog")
	{
		catalog.GET("/product-templates", inventoryHandlers.GetProductTemplates)
		catalog.GET("/subcategories", inventoryHandlers.GetSubcategories)
	}

	// Reports Routes (Read-only analytics)
	reports := api.Group("/reports")
	{
		reports.GET("/low-stock", inventoryHandlers.GetStocks) // Uses query param low_stock=true
		reports.GET("/stock-movements", inventoryHandlers.GetStockMovements)
		// Advanced Inventory Reports
		reports.GET("/valuation", inventoryHandlers.GetInventoryValuationReport)
		reports.GET("/turnover", inventoryHandlers.GetStockTurnoverReport)
		reports.GET("/aging", inventoryHandlers.GetStockAgingReport)
	}
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, inventoryHandlers *handlers.InventoryHandlers) {
	// Health check (no auth required)
	router.GET("/health", inventoryHandlers.Health)

	// Extract user context from headers (set by API Gateway)
	router.Use(func(c *gin.Context) {
		if userID := c.GetHeader("X-User-ID"); userID != "" {
			c.Set("user_id", userID)
		}
		if tenantID := c.GetHeader("X-Tenant-ID"); tenantID != "" {
			c.Set("tenant_id", tenantID)
		}
		if role := c.GetHeader("X-User-Role"); role != "" {
			c.Set("role", role)
		}
		c.Next()
	})

	// Product Routes
	router.GET("/products", inventoryHandlers.GetProducts)
	router.POST("/products", inventoryHandlers.CreateProduct)

	// Product-specific routes (before :id to avoid conflicts)
	router.PUT("/products/:id/pricing", inventoryHandlers.UpdateProductPricing)

	// Standard product CRUD routes
	router.GET("/products/:id", inventoryHandlers.GetProductByID)
	router.PUT("/products/:id", inventoryHandlers.UpdateProduct)
	router.DELETE("/products/:id", inventoryHandlers.DeleteProduct)

	// Stock Management Routes
	router.GET("/stocks", inventoryHandlers.GetStocks)
	router.POST("/stocks/adjust", inventoryHandlers.AdjustStock)
	router.POST("/stocks/transfer", inventoryHandlers.TransferStock)
	router.GET("/stocks/movements", inventoryHandlers.GetStockMovements)

	// Purchase Routes
	router.GET("/purchases", inventoryHandlers.GetPurchases)
	router.POST("/purchases", inventoryHandlers.CreatePurchase)
	router.GET("/purchases/:id", inventoryHandlers.GetPurchaseByID)
	router.POST("/purchases/:id/receive", inventoryHandlers.ReceivePurchase)

	// Category Routes
	router.GET("/categories", inventoryHandlers.GetCategories)
	router.POST("/categories", inventoryHandlers.CreateCategory)
	router.GET("/categories/:id", inventoryHandlers.GetCategoryByID)
	router.PUT("/categories/:id", inventoryHandlers.UpdateCategory)
	router.DELETE("/categories/:id", inventoryHandlers.DeleteCategory)

	// Brand Routes
	router.GET("/brands", inventoryHandlers.GetBrands)
	router.POST("/brands", inventoryHandlers.CreateBrand)

	// Enhanced Brand Creation Routes (Tenant Custom Brands with Variants)
	// Place these BEFORE the :id routes to avoid conflicts
	router.POST("/brands/with-variants", inventoryHandlers.CreateBrandWithVariants)
	router.GET("/brands/products/grouped", inventoryHandlers.GetProductsGroupedByBrand)

	// Standard brand CRUD routes (with :id parameter)
	router.GET("/brands/:id", inventoryHandlers.GetBrandByID)
	router.PUT("/brands/:id", inventoryHandlers.UpdateBrand)
	router.DELETE("/brands/:id", inventoryHandlers.DeleteBrand)
	router.GET("/brands/:id/check-duplicate", inventoryHandlers.CheckDuplicateProduct)
	router.GET("/brands/:id/products", inventoryHandlers.GetProductsByBrand)

	// Pricing utilities
	router.POST("/pricing/calculate-up-duty", inventoryHandlers.CalculateUPDuty)

	// SaaS Brand Onboarding (new architecture - service-to-service communication)
	// Using /api/inventory prefix to match Flutter app expectations
	router.GET("/api/inventory/saas-brands/available", inventoryHandlers.GetAvailableBrandTemplates)
	router.POST("/api/inventory/saas-brands/onboard", inventoryHandlers.OnboardBrands)
	router.GET("/api/inventory/saas-brands/onboarded", inventoryHandlers.GetOnboardedBrands)
	router.PUT("/api/inventory/saas-brands/onboarded/:id", inventoryHandlers.UpdateOnboardedBrand)
	router.GET("/api/inventory/brands/custom", inventoryHandlers.GetCustomBrands)

	// Legacy SaaS Brand Integration (keeping for backward compatibility)
	router.GET("/brands/saas/available", inventoryHandlers.GetAvailableBrands)
	router.GET("/brands/saas/tenant", inventoryHandlers.GetTenantBrands)
	router.POST("/brands/saas/select", inventoryHandlers.SelectBrandsFromCatalog)
	router.POST("/brands/saas/customize", inventoryHandlers.CustomizeBrandVariant)
	router.POST("/brands/saas/import-as-products", inventoryHandlers.ImportBrandsAsProducts)

	// Legacy compatibility endpoints
	router.GET("/brands/available", inventoryHandlers.GetAvailableBrands)
	router.GET("/brands/my-brands", inventoryHandlers.GetTenantBrands)
	router.POST("/brands/create-product", inventoryHandlers.CreateProductFromBrand)
	router.GET("/brands/products", inventoryHandlers.GetProductsFromBrands)
	router.POST("/brands/sync-pricing", inventoryHandlers.SyncBrandPricing)

	// Product Catalog Routes
	router.GET("/api/catalog/product-templates", inventoryHandlers.GetProductTemplates)
	router.GET("/api/catalog/subcategories", inventoryHandlers.GetSubcategories)

	// Reports Routes
	router.GET("/reports/low-stock", inventoryHandlers.GetStocks)
	router.GET("/reports/stock-movements", inventoryHandlers.GetStockMovements)
}
