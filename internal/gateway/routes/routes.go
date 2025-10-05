package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/gateway/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all gateway routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, gatewayHandlers *handlers.GatewayHandlers) {
	// Root-level health check for Docker healthcheck
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "gateway",
		})
	})

	// Gateway management endpoints
	gateway := router.Group("/gateway")
	{
		gateway.GET("/health", gatewayHandlers.HealthCheck)
		gateway.GET("/version", gatewayHandlers.GetVersion)
		gateway.GET("/services", gatewayHandlers.ServiceDiscovery)
	}

	// Authentication service routes (no auth required for login/register)
	authPublic := router.Group("/api/auth")
	{
		authPublic.POST("/check-user", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/login", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/register", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/send-otp", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/send-otp-registration", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/verify-otp", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/forgot-password", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/reset-password", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/verify-email", gatewayHandlers.ProxyRequest("auth"))
	}

	// Protected authentication routes
	authProtected := router.Group("/api/auth")
	authProtected.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	{
		authProtected.POST("/logout", gatewayHandlers.ProxyRequest("auth"))
		authProtected.POST("/refresh", gatewayHandlers.ProxyRequest("auth"))
		authProtected.GET("/profile", gatewayHandlers.ProxyRequest("auth"))
		authProtected.PUT("/profile", gatewayHandlers.ProxyRequest("auth"))
		authProtected.PUT("/change-password", gatewayHandlers.ProxyRequest("auth"))
	}

	// Sales service routes (protected)
	sales := router.Group("/api/sales")
	sales.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	sales.Use(middleware.TenantMiddleware())
	{
		// Daily sales (critical for current workflow)
		sales.GET("/daily-records", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/daily-records/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.PUT("/daily-records/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/daily-records/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records/:id/reject", gatewayHandlers.ProxyRequest("sales"))

		// Individual sales
		sales.GET("/sales", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.PUT("/sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales/:id/reject", gatewayHandlers.ProxyRequest("sales"))

		// Sale returns
		sales.GET("/returns", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/returns", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/returns/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/returns/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/returns/:id/reject", gatewayHandlers.ProxyRequest("sales"))

		// Pending sales and returns
		sales.GET("/pending", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/returns/pending", gatewayHandlers.ProxyRequest("sales"))

		// Sales summaries and reports
		sales.GET("/summaries", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/dashboard", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/dashboard/summary", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/uncollected", gatewayHandlers.ProxyRequest("sales"))

		// OCR and image processing
		sales.POST("/images/upload", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/images/process", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/images/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/images", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/images/extract-dynamic", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/extraction/edit", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/extraction/finalize", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/extraction/status/:id", gatewayHandlers.ProxyRequest("sales"))
	}

	// Inventory service routes (protected)
	inventory := router.Group("/api/inventory")
	inventory.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	inventory.Use(middleware.TenantMiddleware())
	{
		// Products
		inventory.GET("/products", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/products", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/products/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/products/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/products/:id", gatewayHandlers.ProxyRequest("inventory"))

		// Categories
		inventory.GET("/categories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/categories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/categories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/categories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/categories/:id", gatewayHandlers.ProxyRequest("inventory"))

		// Brands
		inventory.GET("/brands", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/brands/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/brands/:id", gatewayHandlers.ProxyRequest("inventory"))

		// SaaS Brand Integration
		inventory.GET("/brands/saas/available", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/saas/tenant", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/saas/select", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/saas/customize", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/saas/import-as-products", gatewayHandlers.ProxyRequest("inventory"))

		// Legacy compatibility endpoints
		inventory.GET("/brands/available", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/my-brands", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/create-product", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/products", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/sync-pricing", gatewayHandlers.ProxyRequest("inventory"))

		// Brand pricing
		inventory.GET("/brand-pricing", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brand-pricing", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brand-pricing/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/brand-pricing/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/brand-pricing/:id", gatewayHandlers.ProxyRequest("inventory"))

		// Stock management
		inventory.GET("/stocks", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/adjust", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/movements", gatewayHandlers.ProxyRequest("inventory"))

		// Stock purchases
		inventory.GET("/purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/:id/receive", gatewayHandlers.ProxyRequest("inventory"))

		// Stock transfers
		inventory.POST("/transfers", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/transfers", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/transfers/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/transfers/:id/approve", gatewayHandlers.ProxyRequest("inventory"))

		// Product catalog endpoints
		inventory.GET("/catalog/product-templates", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/catalog/product-templates", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/catalog/product-templates/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/catalog/product-templates/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/catalog/product-templates/:id", gatewayHandlers.ProxyRequest("inventory"))

		// Subcategories
		inventory.GET("/catalog/subcategories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/catalog/subcategories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/catalog/subcategories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/catalog/subcategories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/catalog/subcategories/:id", gatewayHandlers.ProxyRequest("inventory"))

		// SaaS Brand Onboarding (new architecture)
		inventory.GET("/saas-brands/available", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/saas-brands/onboard", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/saas-brands/onboarded", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/saas-brands/onboarded/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/custom", gatewayHandlers.ProxyRequest("inventory"))
	}

	// Finance service routes (protected)
	finance := router.Group("/api/finance")
	finance.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	finance.Use(middleware.TenantMiddleware())
	{
		// Vendors
		finance.GET("/vendors", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/vendors", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/vendors/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.PUT("/vendors/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.DELETE("/vendors/:id", gatewayHandlers.ProxyRequest("finance"))

		// Bank accounts
		finance.GET("/bank-accounts", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/bank-accounts", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-accounts/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.PUT("/bank-accounts/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.DELETE("/bank-accounts/:id", gatewayHandlers.ProxyRequest("finance"))

		// Expenses
		finance.GET("/expenses", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/expenses", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/expenses/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.PUT("/expenses/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/expenses/:id/approve", gatewayHandlers.ProxyRequest("finance"))

		// Executive finance
		finance.GET("/executive-finance", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/executive-finance", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/executive-finance/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/executive-finance/:id/approve", gatewayHandlers.ProxyRequest("finance"))

		// Assistant manager features (15-minute approval deadline)
		finance.POST("/money-collection", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/money-collection", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/money-collection/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/money-collection/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/money-collection/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Bank deposits
		finance.POST("/bank-deposits", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-deposits", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/bank-deposits/:id/approve", gatewayHandlers.ProxyRequest("finance"))

		// Stock verification
		finance.POST("/stock-verification", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/stock-verification", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/stock-verification/:id/approve", gatewayHandlers.ProxyRequest("finance"))

		// Dashboard
		finance.GET("/dashboard/summary", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/collections-due", gatewayHandlers.ProxyRequest("finance"))

		// Reports
		finance.GET("/reports/profit-loss", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/balance-sheet", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/cash-flow", gatewayHandlers.ProxyRequest("finance"))
	}

	// Tenant and user management (admin routes)
	admin := router.Group("/api/admin")
	admin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	admin.Use(middleware.RoleMiddleware("admin", "saas_admin"))
	{
		// Tenant management
		admin.GET("/tenants", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/tenants", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.PUT("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))

		// Shop management
		admin.GET("/shops", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/shops", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/shops/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.PUT("/shops/:id", gatewayHandlers.ProxyRequest("auth"))

		// User management
		admin.GET("/users", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/users", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/users/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.PUT("/users/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.DELETE("/users/:id", gatewayHandlers.ProxyRequest("auth"))

		// Salesman management
		admin.GET("/salesmen", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/salesmen", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/salesmen/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.PUT("/salesmen/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.DELETE("/salesmen/:id", gatewayHandlers.ProxyRequest("auth"))

		// Role and permission management
		admin.GET("/roles", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/roles", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/permissions", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/permissions", gatewayHandlers.ProxyRequest("auth"))
	}

	// SaaS Admin routes (super admin functionality)
	saasAdmin := router.Group("/api/saas-admin")
	saasAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	saasAdmin.Use(middleware.RoleMiddleware("saas_admin"))
	{
		// Tenant management
		saasAdmin.GET("/tenants", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.POST("/tenants", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.GET("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.PUT("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.DELETE("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))

		// Global user management (across all tenants)
		saasAdmin.GET("/all-users", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.GET("/all-shops", gatewayHandlers.ProxyRequest("auth"))

		// System statistics
		saasAdmin.GET("/stats", gatewayHandlers.ProxyRequest("auth"))

		// Rate limit management
		saasAdmin.GET("/rate-limits", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.POST("/rate-limits", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.GET("/rate-limits/stats", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.GET("/rate-limits/check/:name", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.POST("/rate-limits/reset/:name", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.GET("/rate-limits/:id", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.PUT("/rate-limits/:id", gatewayHandlers.ProxyRequest("auth"))
		saasAdmin.DELETE("/rate-limits/:id", gatewayHandlers.ProxyRequest("auth"))
	}

	// Super Admin Brand Management (accessible to all authenticated tenants for viewing)
	superAdmin := router.Group("/api/super-admin")
	superAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	{
		// Brand packages for tenant onboarding (read-only for tenants)
		superAdmin.GET("/brands/packages", gatewayHandlers.ProxyRequest("saas"))
	}

	// SaaS service routes (for brand catalog access)
	saas := router.Group("/api/saas")
	saas.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	saas.Use(middleware.TenantMiddleware())
	{
		// Public brand catalog for tenants
		saas.GET("/brands/public", gatewayHandlers.ProxyRequest("saas"))
		saas.GET("/brands/categories", gatewayHandlers.ProxyRequest("saas"))
		saas.GET("/brands/subcategories", gatewayHandlers.ProxyRequest("saas"))
		saas.GET("/brands/:id/variants", gatewayHandlers.ProxyRequest("saas"))

		// Brand selection and import for tenants
		saas.POST("/brands/select", gatewayHandlers.ProxyRequest("saas"))
		saas.POST("/brands/import-products", gatewayHandlers.ProxyRequest("saas"))

		// Subscription and tenant management
		saas.GET("/plans", gatewayHandlers.ProxyRequest("saas"))
		saas.GET("/subscription", gatewayHandlers.ProxyRequest("saas"))
	}

	// Default 404 handler for non-API routes
	router.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{"error": "Endpoint not found"})
	})
}

// SetupAPIRoutes sets up API-only routes (for API-only deployments)
func SetupAPIRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, gatewayHandlers *handlers.GatewayHandlers) {
	// This is a variant without frontend routes for pure API deployments
	// Copy all routes from SetupRoutes except the frontend group
	SetupRoutes(router, cfg, cache, gatewayHandlers)
}
