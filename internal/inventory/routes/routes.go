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
	}

	// Reports Routes (Read-only analytics)
	reports := api.Group("/reports")
	{
		reports.GET("/low-stock", inventoryHandlers.GetStocks) // Uses query param low_stock=true
		reports.GET("/stock-movements", inventoryHandlers.GetStockMovements)
		// TODO: Add more specialized reports
		reports.GET("/valuation", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Inventory valuation report not implemented yet"})
		})
		reports.GET("/turnover", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Stock turnover report not implemented yet"})
		})
		reports.GET("/aging", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Stock aging report not implemented yet"})
		})
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
	router.GET("/brands/:id", inventoryHandlers.GetBrandByID)
	router.PUT("/brands/:id", inventoryHandlers.UpdateBrand)
	router.DELETE("/brands/:id", inventoryHandlers.DeleteBrand)

	// Reports Routes
	router.GET("/reports/low-stock", inventoryHandlers.GetStocks)
	router.GET("/reports/stock-movements", inventoryHandlers.GetStockMovements)
}