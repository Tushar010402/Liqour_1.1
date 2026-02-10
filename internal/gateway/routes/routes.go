package routes

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/gateway/handlers"
	"github.com/liquorpro/go-backend/pkg/monitoring"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// corsPreflightHandler returns a handler for CORS preflight requests
func corsPreflightHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", c.GetHeader("Origin"))
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-Request-ID, X-Tenant-ID")
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Max-Age", "86400")
		c.Status(204)
	}
}

// SetupRoutes configures all gateway routes
// rateLimiter parameter is used for role-based rate limiting AFTER authentication
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, db *database.DB, gatewayHandlers *handlers.GatewayHandlers, rateLimiter *middleware.RedisRateLimiter) {
	// Prometheus metrics
	router.Use(monitoring.PrometheusMiddleware("gateway"))
	router.GET("/metrics", monitoring.PrometheusHandler())

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

	// Documentation endpoints - with authentication integration
	docsHandler := handlers.NewDocsHandler(db)

	// Public docs routes (with optional auth for access check)
	docsPublic := router.Group("/api/docs")
	docsPublic.Use(middleware.OptionalAuthMiddleware(cfg.JWT, cache))
	{
		docsPublic.GET("/access/check", docsHandler.CheckDocsAccess)
		docsPublic.GET("/comments", docsHandler.GetComments)
	}

	// Protected docs routes (requires auth + docs access)
	docsProtected := router.Group("/api/docs")
	docsProtected.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	{
		docsProtected.POST("/comments", docsHandler.AddComment)
		docsProtected.DELETE("/comments/:id", docsHandler.DeleteComment)
		docsProtected.POST("/comments/:id/resolve", docsHandler.ResolveComment)
		docsProtected.POST("/edits", docsHandler.SaveEdit)
		docsProtected.GET("/edits", docsHandler.GetEdits)
	}

	// Admin docs routes (requires admin role)
	docsAdmin := router.Group("/api/docs/admin")
	docsAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	{
		docsAdmin.POST("/access", docsHandler.GrantAccess)
		docsAdmin.GET("/access", docsHandler.ListAccess)
		docsAdmin.DELETE("/access/:user_id", docsHandler.RevokeAccess)
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

	// Public admin routes (no auth required - for registration flow)
	adminPublic := router.Group("/api/admin")
	{
		// Validation endpoints (called during registration before user has account)
		adminPublic.GET("/validate/phone", gatewayHandlers.ProxyRequest("auth"))
		adminPublic.GET("/validate/email", gatewayHandlers.ProxyRequest("auth"))
		adminPublic.GET("/validate/tenant", gatewayHandlers.ProxyRequest("auth"))
	}

	// Protected authentication routes
	authProtected := router.Group("/api/auth")
	authProtected.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	authProtected.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	{
		// Debug endpoint to test auth headers
		authProtected.GET("/test", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"success": true,
				"message": "Authentication successful - headers are working correctly",
				"user_id": c.GetString("user_id"),
				"tenant_id": c.GetString("tenant_id"),
				"role": c.GetString("role"),
				"headers_received": c.Request.Header,
			})
		})

		authProtected.POST("/logout", gatewayHandlers.ProxyRequest("auth"))
		authProtected.POST("/refresh", gatewayHandlers.ProxyRequest("auth"))
		authProtected.GET("/profile", gatewayHandlers.ProxyRequest("auth"))
		authProtected.PUT("/profile", gatewayHandlers.ProxyRequest("auth"))
		authProtected.PUT("/change-password", gatewayHandlers.ProxyRequest("auth"))

		// Device Session Management (2-device limit like Swiggy/Zomato)
		authProtected.GET("/sessions", gatewayHandlers.ProxyRequest("auth"))
		authProtected.DELETE("/sessions/:session_id", gatewayHandlers.ProxyRequest("auth"))
		authProtected.DELETE("/sessions", gatewayHandlers.ProxyRequest("auth"))
		authProtected.POST("/sessions/force-login", gatewayHandlers.ProxyRequest("auth"))

		// Account Deletion (App Store Guideline 5.1.1(v) Compliance)
		authProtected.POST("/account/delete/request-otp", gatewayHandlers.ProxyRequest("auth"))
		authProtected.POST("/account/delete/send-otp", gatewayHandlers.ProxyRequest("auth")) // Alias for Flutter app
		authProtected.DELETE("/account", gatewayHandlers.ProxyRequest("auth"))
		authProtected.POST("/account/delete", gatewayHandlers.ProxyRequest("auth")) // POST alias for Flutter app
		authProtected.POST("/account/delete/cancel", gatewayHandlers.ProxyRequest("auth"))
	}

	// Protected shop routes (accessible to all authenticated users)
	shops := router.Group("/api")
	shops.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	shops.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	shops.Use(middleware.TenantMiddleware())
	{
		shops.GET("/shops", gatewayHandlers.ProxyRequest("auth"))
		shops.GET("/shops/:id", gatewayHandlers.ProxyRequest("auth"))
	}

	// Sales service routes (protected)
	sales := router.Group("/api/sales")
	sales.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	sales.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
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
		sales.PATCH("/daily-records/:id/change-date", gatewayHandlers.ProxyRequest("sales")) // Change date only
		sales.POST("/daily-records/:id/copy", gatewayHandlers.ProxyRequest("sales"))         // Copy for rejected record recovery
		sales.POST("/daily-records/upload-image", gatewayHandlers.ProxyRequest("sales"))     // Image upload for daily sales
		// AI Validation endpoints for daily-records
		sales.GET("/daily-records/:id/validation", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records/:id/validation/trigger", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records/:id/validation/confirm", gatewayHandlers.ProxyRequest("sales"))

		// Alias: daily-sales routes (for Flutter app compatibility)
		sales.GET("/daily-sales", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/daily-sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.PUT("/daily-sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/daily-sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/reject", gatewayHandlers.ProxyRequest("sales"))
		sales.PATCH("/daily-sales/:id/change-date", gatewayHandlers.ProxyRequest("sales")) // Change date only
		sales.POST("/daily-sales/:id/copy", gatewayHandlers.ProxyRequest("sales"))         // Copy for rejected record recovery
		sales.POST("/daily-sales/upload-image", gatewayHandlers.ProxyRequest("sales"))     // Image upload for daily sales
		// AI Validation endpoints for daily-sales (alias)
		sales.GET("/daily-sales/:id/validation", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/validation/trigger", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/validation/confirm", gatewayHandlers.ProxyRequest("sales"))

		// Daily Sales Revert with dual OTP verification (admin/owner only)
		sales.POST("/daily-sales/:id/revert/request-otp", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/revert", gatewayHandlers.ProxyRequest("sales"))

		// Draft persistence endpoints (backend-based, replaces Hive local storage)
		sales.GET("/daily-sales/draft", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/draft", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/daily-sales/draft", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/draft/submit", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/daily-sales/drafts", gatewayHandlers.ProxyRequest("sales"))

		// Validation accuracy dashboard
		sales.GET("/validation/accuracy", gatewayHandlers.ProxyRequest("sales"))

		// Individual sales
		sales.GET("/sales", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.PUT("/sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales/:id/reject", gatewayHandlers.ProxyRequest("sales"))
		// Sale Revert with dual OTP verification (admin/owner only)
		sales.POST("/sales/:id/revert/request-otp", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/sales/:id/revert", gatewayHandlers.ProxyRequest("sales"))

		// Sale returns
		sales.GET("/returns", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/returns", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/returns/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/returns/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/returns/:id/reject", gatewayHandlers.ProxyRequest("sales"))

		// Pending sales and returns
		sales.GET("/pending", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/pending/sales", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/pending/returns", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/returns/pending", gatewayHandlers.ProxyRequest("sales"))

		// Sales summaries and reports
		sales.GET("/summaries", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/dashboard", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/dashboard/summary", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/uncollected", gatewayHandlers.ProxyRequest("sales"))

		// OCR and image processing with Gemini AI
		sales.POST("/ocr/batch/sessions", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/batch/sessions/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/batch/deduplicate", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/batch/import", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/brands/match", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/brands/create", gatewayHandlers.ProxyRequest("sales"))

		// OCR Metrics and Validation (Phase 5)
		sales.GET("/ocr/metrics", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/metrics/reset", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/batch/validate/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/batch/validate-row", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/accuracy/dashboard", gatewayHandlers.ProxyRequest("sales"))

		// Smart Sale (AI-assisted sale creation from images)
		sales.POST("/smart-sale/process", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/smart-sale/finalize", gatewayHandlers.ProxyRequest("sales"))
	}

	// Reports service routes (protected) - proxied to sales service
	reports := router.Group("/api/reports")
	reports.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	reports.Use(rateLimiter.RoleBasedMiddleware())
	reports.Use(middleware.TenantMiddleware())
	{
		// Purcha Report (Daily Sales Register)
		reports.GET("/purcha/preview", gatewayHandlers.ProxyRequest("sales"))
		reports.GET("/purcha/pdf", gatewayHandlers.ProxyRequest("sales"))
	}

	// AI Training Data routes (internal tool - public for static page access)
	// Security: Restrict access at nginx level to internal IPs only
	training := router.Group("/api/training")
	{
		// V1 routes
		training.GET("/images", gatewayHandlers.ProxyRequest("sales"))
		training.GET("/images/export", gatewayHandlers.ProxyRequest("sales"))
		training.GET("/images/:filename", gatewayHandlers.ProxyRequest("sales"))
		training.GET("/debug/records", gatewayHandlers.ProxyRequest("sales"))

		// V2 routes - Size detection and processing
		training.GET("/images/v2", gatewayHandlers.ProxyRequest("sales"))
		training.GET("/images/export-v2", gatewayHandlers.ProxyRequest("sales"))
		training.POST("/images/process/:filename", gatewayHandlers.ProxyRequest("sales"))
		training.POST("/images/process-all", gatewayHandlers.ProxyRequest("sales"))
		training.POST("/images/detect-size/:filename", gatewayHandlers.ProxyRequest("sales"))
		training.GET("/mappings/:record_id", gatewayHandlers.ProxyRequest("sales"))
		training.POST("/mappings/:id/verify", gatewayHandlers.ProxyRequest("sales"))
		training.GET("/items/:record_id/:size", gatewayHandlers.ProxyRequest("sales"))
	}

	// AI Training V2 routes - Generic document extraction training (any logged-in user)
	aiTraining := router.Group("/api/ai-training")
	aiTraining.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	aiTraining.Use(rateLimiter.RoleBasedMiddleware())
	aiTraining.Use(middleware.TenantMiddleware())
	{
		aiTraining.POST("/upload", gatewayHandlers.ProxyRequest("sales"))
		aiTraining.GET("/images", gatewayHandlers.ProxyRequest("sales"))
		aiTraining.GET("/images/:id", gatewayHandlers.ProxyRequest("sales"))
		aiTraining.PUT("/images/:id/verify", gatewayHandlers.ProxyRequest("sales"))
		aiTraining.DELETE("/images/:id", gatewayHandlers.ProxyRequest("sales"))
		aiTraining.GET("/export", gatewayHandlers.ProxyRequest("sales"))
	}

	// Inventory service routes (protected)
	inventory := router.Group("/api/inventory")
	inventory.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	inventory.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	inventory.Use(middleware.TenantMiddleware())
	{
		// Products
		inventory.GET("/products", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/products", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/products/sizes", gatewayHandlers.ProxyRequest("inventory"))   // Must be before :id route
		inventory.POST("/products/by-ids", gatewayHandlers.ProxyRequest("inventory")) // Fetch multiple products by IDs - reduces N calls to 1
		inventory.GET("/products/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/products/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/products/:id/pricing", gatewayHandlers.ProxyRequest("inventory"))
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

		// Brand categories from SaaS service (for Flutter app brand editing)
		inventory.GET("/brand-categories", gatewayHandlers.ProxyRequest("saas"))
		inventory.GET("/brand-subcategories", gatewayHandlers.ProxyRequest("saas"))

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

		// Legacy compatibility - singular "stock" endpoint
		inventory.GET("/stock", gatewayHandlers.ProxyRequest("inventory"))

		// Stock purchases
		inventory.GET("/purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/:id/receive", gatewayHandlers.ProxyRequest("inventory"))
		// Receipt upload for purchases
		inventory.POST("/purchases/upload-receipt", gatewayHandlers.ProxyRequest("inventory"))
		// Purchase approval workflow
		inventory.GET("/purchases/pending", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/:id/approve", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/:id/reject", gatewayHandlers.ProxyRequest("inventory"))

		// Stock purchases - alias routes for Flutter app compatibility
		inventory.GET("/stock-purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stock-purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stock-purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/stock-purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stock-purchases/:id/receive", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stock-purchases/upload-receipt", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stock-purchases/pending", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stock-purchases/:id/approve", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stock-purchases/:id/reject", gatewayHandlers.ProxyRequest("inventory"))

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
		inventory.GET("/saas-brands/metadata", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/custom", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/custom", gatewayHandlers.ProxyRequest("inventory"))
	}

	// Finance service routes (protected)
	log.Println("🔧 [Routes] Setting up finance routes...")
	finance := router.Group("/api/finance")
	log.Println("🔧 [Routes] Created finance group at /api/finance")
	finance.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	log.Println("🔧 [Routes] Added AuthMiddleware to finance")
	finance.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	finance.Use(middleware.TenantMiddleware())
	log.Println("🔧 [Routes] Added TenantMiddleware to finance")
	{
		// Debug test endpoint
		finance.GET("/test-route", func(c *gin.Context) {
			log.Println("🎯 [Finance] Test route handler called!")
			c.JSON(http.StatusOK, gin.H{"message": "Finance test route works!"})
		})
		log.Println("🔧 [Routes] Registered GET /api/finance/test-route")

		// Test proxy endpoint
		finance.GET("/test-proxy", gatewayHandlers.ProxyRequest("finance"))
		log.Println("🔧 [Routes] Registered GET /api/finance/test-proxy")

		// Vendors
		finance.GET("/vendors", gatewayHandlers.ProxyRequest("finance"))
		log.Println("🔧 [Routes] Registered GET /api/finance/vendors")
		finance.POST("/vendors", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/vendors/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.PUT("/vendors/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.DELETE("/vendors/:id", gatewayHandlers.ProxyRequest("finance"))

		// Vendor bank accounts
		finance.POST("/vendors/:id/bank-accounts", gatewayHandlers.ProxyRequest("finance"))

		// Vendor transactions (purchases/payments ledger)
		finance.POST("/vendors/transactions", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/vendors/:id/transactions", gatewayHandlers.ProxyRequest("finance"))

		// Vendor ledger with running balance
		finance.GET("/vendors/:id/ledger", gatewayHandlers.ProxyRequest("finance"))

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

		// Executive finance (cash handovers & expense claims)
		finance.GET("/executive-finance", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/executive-finance", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/executive-finance/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/executive-finance/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/executive-finance/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Assistant Manager Routes (15-minute approval deadline, proper plural naming)
		// Money Collections - full CRUD with approval workflow
		finance.GET("/assistant-manager/money-collections", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/assistant-manager/money-collections", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/assistant-manager/money-collections/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/assistant-manager/money-collections/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/assistant-manager/money-collections/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Assistant Manager Expenses
		finance.GET("/assistant-manager/expenses", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/assistant-manager/expenses", gatewayHandlers.ProxyRequest("finance"))

		// Assistant Manager Finance Records
		finance.GET("/assistant-manager/finance", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/assistant-manager/finance", gatewayHandlers.ProxyRequest("finance"))

		// Tenant Settings (configurable deadline)
		finance.GET("/tenant-settings", gatewayHandlers.ProxyRequest("finance"))
		finance.PUT("/tenant-settings", gatewayHandlers.ProxyRequest("finance"))

		// Legacy money-collection routes (singular, for backward compatibility)
		finance.POST("/money-collection", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/money-collection", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/money-collection/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/money-collection/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/money-collection/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Collections aliases (Flutter app compatibility)
		finance.GET("/collections", gatewayHandlers.ProxyRequest("finance")) // Alias to GetMoneyCollections
		finance.GET("/cash-requests", gatewayHandlers.ProxyRequest("finance")) // Alias to GetMoneyCollections
		finance.GET("/pending-requests", gatewayHandlers.ProxyRequest("finance")) // Alias to GetMoneyCollections

		// Cash requests aliases (Flutter app expects /cash/requests/:id/approve)
		finance.GET("/cash/requests/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/cash/requests/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/cash/requests/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Bank deposits (cash deposits)
		finance.GET("/bank-deposits", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/bank-deposits", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-deposits/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/bank-deposits/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/bank-deposits/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Bank Reconciliation
		finance.GET("/reconciliations", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/reconciliations", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reconciliations/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/reconciliations/:id/complete", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/reconciliations/:id/approve", gatewayHandlers.ProxyRequest("finance"))

		// Stock verification with full audit trail
		finance.GET("/stock-verification", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/stock-verification", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/stock-verification/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/stock-verification/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/stock-verification/:id/reject", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/stock-audit-logs", gatewayHandlers.ProxyRequest("finance"))

		// Dashboard
		finance.GET("/dashboard/summary", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/collections-due", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/cash-balance", gatewayHandlers.ProxyRequest("finance")) // Alias to dashboard summary
		finance.GET("/cash-balance", gatewayHandlers.ProxyRequest("finance")) // Shortcut alias

		// Reports
		finance.GET("/reports/profit-loss", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/balance-sheet", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/cash-flow", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/cash-history", gatewayHandlers.ProxyRequest("finance")) // Alias to cash-flow
		finance.GET("/cash-history", gatewayHandlers.ProxyRequest("finance")) // Shortcut alias

		// Flutter app compatibility - support both dash and slash formats
		finance.GET("/cash/balance", gatewayHandlers.ProxyRequest("finance")) // Alias for /cash-balance
		finance.GET("/cash/history", gatewayHandlers.ProxyRequest("finance")) // Alias for /cash-history
		finance.GET("/cash/requests/pending", gatewayHandlers.ProxyRequest("finance")) // Pending cash requests
		finance.GET("/cash/requests", gatewayHandlers.ProxyRequest("finance"))         // All cash requests
		finance.POST("/cash/request", gatewayHandlers.ProxyRequest("finance"))         // Create cash request
		finance.GET("/cash/collections", gatewayHandlers.ProxyRequest("finance"))      // Cash collections
		finance.GET("/cash/team-balances", gatewayHandlers.ProxyRequest("finance"))    // Team member balances
		finance.GET("/cash/tenant-users", gatewayHandlers.ProxyRequest("finance"))     // Tenant users for cash management
		finance.GET("/cash/users", gatewayHandlers.ProxyRequest("finance"))            // Alias for tenant-users
		finance.POST("/cash/reconcile-balances", gatewayHandlers.ProxyRequest("finance")) // Admin: recalculate all balances

		// Cash deposit submission (Flutter app compatibility - submit cash to bank account)
		finance.POST("/cash/submit", gatewayHandlers.ProxyRequest("finance"))                      // Submit cash deposit
		finance.GET("/cash/deposits", gatewayHandlers.ProxyRequest("finance"))                     // List cash deposits
		finance.GET("/cash/deposits/pending/count", gatewayHandlers.ProxyRequest("finance"))       // Pending count for dashboard badge
		finance.GET("/cash/deposits/:id", gatewayHandlers.ProxyRequest("finance"))                 // Get specific deposit
		finance.POST("/cash/deposits/:id/approve", gatewayHandlers.ProxyRequest("finance"))        // Approve deposit
		finance.POST("/cash/deposits/:id/reject", gatewayHandlers.ProxyRequest("finance"))         // Reject deposit

		// Alias routes for Flutter app compatibility (/submissions -> /deposits)
		finance.GET("/cash/submissions", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/cash/submissions/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/cash/submissions/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/cash/submissions/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Expense categories
		finance.GET("/expense-categories", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/expense-categories", gatewayHandlers.ProxyRequest("finance"))

		// Additional reports
		finance.GET("/reports/expense-summary", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/vendor-aging", gatewayHandlers.ProxyRequest("finance"))

		// Receipt image upload
		finance.POST("/upload/receipt", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/cash/upload-receipt", gatewayHandlers.ProxyRequest("finance")) // Flutter app compatibility

		// Admin Cash Balance Management (admin/owner only - role checked in handler)
		finance.POST("/cash/admin/set-balance", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/cash/admin/bulk-reset", gatewayHandlers.ProxyRequest("finance"))

		// ==========================================
		// Finance Matrix - Analytics Dashboard
		// ==========================================
		// Base matrix endpoint (Flutter app compatibility)
		finance.GET("/matrix", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/dashboard", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/daily-metrics", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/cash-holdings", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/credit-aging", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/expense-breakdown", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/sales-trend", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/top-products", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/salesman-performance", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/stock-turnover", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/insights", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/matrix/alerts", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/matrix/alerts/:id/acknowledge", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/matrix/alerts/:id/resolve", gatewayHandlers.ProxyRequest("finance"))

		// Dashboard Metrics (manager, assistant_manager, admin only)
		// These routes provide aggregated metrics for the dashboard with date and shop filters
		finance.GET("/dashboard/metrics", middleware.RoleMiddleware("manager", "assistant_manager", "admin"), gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/metrics/payment/details", middleware.RoleMiddleware("manager", "assistant_manager", "admin"), gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/metrics/purchase/details", middleware.RoleMiddleware("manager", "assistant_manager", "admin"), gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/metrics/sale/details", middleware.RoleMiddleware("manager", "assistant_manager", "admin"), gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/dashboard/metrics/expense/details", middleware.RoleMiddleware("manager", "assistant_manager", "admin"), gatewayHandlers.ProxyRequest("finance"))
	}

	// ==========================================
	// Notifications Service Routes
	// ==========================================
	notifications := router.Group("/api/notifications")
	notifications.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	notifications.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	notifications.Use(middleware.TenantMiddleware())
	{
		// User notifications
		notifications.GET("", gatewayHandlers.ProxyRequest("finance"))
		notifications.GET("/unread-count", gatewayHandlers.ProxyRequest("finance")) // Get unread count only
		notifications.GET("/counts", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/read", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/read-all", gatewayHandlers.ProxyRequest("finance"))
		notifications.PATCH("/:id/read", gatewayHandlers.ProxyRequest("finance")) // Mark single notification as read
		notifications.DELETE("/:id", gatewayHandlers.ProxyRequest("finance"))     // Delete single notification
		notifications.DELETE("", gatewayHandlers.ProxyRequest("finance"))         // Clear all notifications

		// Device management (FCM token registration)
		notifications.POST("/register-device", gatewayHandlers.ProxyRequest("finance"))
		notifications.DELETE("/unregister-device", gatewayHandlers.ProxyRequest("finance"))
		// Alias endpoints for frontend compatibility (Flutter app uses /devices)
		notifications.POST("/devices", gatewayHandlers.ProxyRequest("finance"))
		notifications.DELETE("/devices", gatewayHandlers.ProxyRequest("finance"))

		// Preferences
		notifications.GET("/preferences", gatewayHandlers.ProxyRequest("finance"))
		notifications.PUT("/preferences", gatewayHandlers.ProxyRequest("finance"))

		// WhatsApp opt-in
		notifications.POST("/whatsapp/opt-in", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/whatsapp/verify", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/whatsapp/opt-out", gatewayHandlers.ProxyRequest("finance"))

		// Admin notification sending
		notifications.POST("/send", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/send-bulk", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/broadcast", gatewayHandlers.ProxyRequest("finance"))
		notifications.GET("/templates", gatewayHandlers.ProxyRequest("finance"))
		notifications.POST("/templates", gatewayHandlers.ProxyRequest("finance"))
		notifications.GET("/stats", gatewayHandlers.ProxyRequest("finance"))
	}

	// ==========================================
	// Alarm System Routes
	// ==========================================
	alarms := router.Group("/api/alarms")
	alarms.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	alarms.Use(rateLimiter.RoleBasedMiddleware())
	alarms.Use(middleware.TenantMiddleware())
	{
		// Alarm definitions (read-only)
		alarms.GET("/definitions", gatewayHandlers.ProxyRequest("finance"))
		alarms.GET("/definitions/:code", gatewayHandlers.ProxyRequest("finance"))

		// Alarm configurations
		alarms.GET("/configurations", gatewayHandlers.ProxyRequest("finance"))
		alarms.GET("/configurations/:code", gatewayHandlers.ProxyRequest("finance"))
		alarms.PUT("/configurations", gatewayHandlers.ProxyRequest("finance"))

		// Alarm instances
		alarms.GET("", gatewayHandlers.ProxyRequest("finance"))
		alarms.GET("/:id", gatewayHandlers.ProxyRequest("finance"))
		alarms.POST("/:id/acknowledge", gatewayHandlers.ProxyRequest("finance"))
		alarms.POST("/:id/resolve", gatewayHandlers.ProxyRequest("finance"))
		alarms.POST("/:id/snooze", gatewayHandlers.ProxyRequest("finance"))
		alarms.POST("/:id/notes", gatewayHandlers.ProxyRequest("finance"))

		// Alarm counts and stats (dashboard)
		alarms.GET("/counts", gatewayHandlers.ProxyRequest("finance"))
		alarms.GET("/stats", gatewayHandlers.ProxyRequest("finance"))

		// User alarm subscriptions
		alarms.GET("/subscriptions", gatewayHandlers.ProxyRequest("finance"))
		alarms.PUT("/subscriptions", gatewayHandlers.ProxyRequest("finance"))

		// Bulk actions
		alarms.POST("/bulk/acknowledge", gatewayHandlers.ProxyRequest("finance"))
		alarms.POST("/bulk/resolve", gatewayHandlers.ProxyRequest("finance"))

		// Admin actions
		alarms.POST("/admin/trigger", gatewayHandlers.ProxyRequest("finance"))
		alarms.POST("/admin/run-checks", gatewayHandlers.ProxyRequest("finance"))
	}

	// ==========================================
	// App Logging Routes (Industrial-Grade Monitoring)
	// Receives logs from Flutter app for centralized monitoring
	// ==========================================
	// CORS preflight handlers for logs endpoints
	router.OPTIONS("/api/logs", corsPreflightHandler())
	router.OPTIONS("/api/logs/batch", corsPreflightHandler())
	router.OPTIONS("/api/logs/sessions", corsPreflightHandler())
	router.OPTIONS("/api/logs/stats", corsPreflightHandler())
	router.OPTIONS("/api/logs/network", corsPreflightHandler())
	router.OPTIONS("/api/logs/users", corsPreflightHandler())

	logs := router.Group("/api/logs")
	logs.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	logs.Use(rateLimiter.RoleBasedMiddleware())
	logs.Use(middleware.TenantMiddleware())
	{
		// Receive logs from Flutter app (all authenticated users)
		logs.POST("/batch", gatewayHandlers.ProxyRequest("finance"))

		// View logs (role-based access control)
		logs.GET("", gatewayHandlers.ProxyRequest("finance"))
		logs.GET("/sessions", gatewayHandlers.ProxyRequest("finance"))
		logs.GET("/stats", gatewayHandlers.ProxyRequest("finance"))
		logs.GET("/network", gatewayHandlers.ProxyRequest("finance"))

		// Get viewable users for dropdown (role-based)
		logs.GET("/users", gatewayHandlers.ProxyRequest("finance"))

		// Cleanup old logs (super admin only)
		logs.DELETE("/cleanup", gatewayHandlers.ProxyRequest("finance"))
	}

	// ==========================================
	// Tips Management Routes
	// ==========================================
	tips := router.Group("/api/tips")
	tips.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	tips.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	tips.Use(middleware.TenantMiddleware())
	{
		// Individual tips
		tips.POST("", gatewayHandlers.ProxyRequest("finance"))
		tips.GET("", gatewayHandlers.ProxyRequest("finance"))
		tips.GET("/my-tips", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Tip pools
		tips.GET("/pools", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/pools", gatewayHandlers.ProxyRequest("finance"))
		tips.GET("/pools/:id", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/pools/:id/add", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/pools/:id/distribute", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/pools/:id/close", gatewayHandlers.ProxyRequest("finance"))

		// Payouts
		tips.GET("/payouts", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/payouts", gatewayHandlers.ProxyRequest("finance"))
		tips.GET("/payouts/:id", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/payouts/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		tips.POST("/payouts/:id/process", gatewayHandlers.ProxyRequest("finance"))

		// Summary and reports
		tips.GET("/summary", gatewayHandlers.ProxyRequest("finance"))
		tips.GET("/reports/salesman", gatewayHandlers.ProxyRequest("finance"))
		tips.GET("/reports/daily", gatewayHandlers.ProxyRequest("finance"))
	}

	// ==========================================
	// Theft Detection Routes
	// ==========================================
	detection := router.Group("/api/detection")
	detection.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	detection.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	detection.Use(middleware.TenantMiddleware())
	detection.Use(middleware.RoleMiddleware("admin", "manager", "assistant_manager", "owner", "saas_admin"))
	{
		// Dashboard
		detection.GET("/dashboard", gatewayHandlers.ProxyRequest("finance"))

		// Alerts
		detection.GET("/alerts", gatewayHandlers.ProxyRequest("finance"))
		detection.GET("/alerts/active", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/alerts/:id/acknowledge", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/alerts/:id/resolve", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/alerts/:id/escalate", gatewayHandlers.ProxyRequest("finance"))

		// Alert configuration
		detection.GET("/config", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/config", gatewayHandlers.ProxyRequest("finance"))
		detection.PUT("/config/:id", gatewayHandlers.ProxyRequest("finance"))

		// Investigations
		detection.GET("/investigations", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/investigations", gatewayHandlers.ProxyRequest("finance"))
		detection.GET("/investigations/:id", gatewayHandlers.ProxyRequest("finance"))
		detection.PUT("/investigations/:id", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/investigations/:id/assign", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/investigations/:id/close", gatewayHandlers.ProxyRequest("finance"))

		// Investigation notes
		detection.GET("/investigations/:id/notes", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/investigations/:id/notes", gatewayHandlers.ProxyRequest("finance"))

		// Suspicious activities
		detection.GET("/activities", gatewayHandlers.ProxyRequest("finance"))
		detection.GET("/activities/:id", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/activities/:id/acknowledge", gatewayHandlers.ProxyRequest("finance"))

		// Cash variances
		detection.GET("/variances/cash", gatewayHandlers.ProxyRequest("finance"))
		detection.GET("/variances/cash/:id", gatewayHandlers.ProxyRequest("finance"))
		detection.POST("/variances/cash/:id/resolve", gatewayHandlers.ProxyRequest("finance"))

		// Risk analytics
		detection.GET("/analytics/users", gatewayHandlers.ProxyRequest("finance"))
		detection.GET("/analytics/trends", gatewayHandlers.ProxyRequest("finance"))
		detection.GET("/analytics/risk-score", gatewayHandlers.ProxyRequest("finance"))
	}

	// ==========================================
	// Physical Audit Routes
	// ==========================================
	audit := router.Group("/api/audits")
	audit.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	audit.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	audit.Use(middleware.TenantMiddleware())
	{
		// Dashboard
		audit.GET("/dashboard", gatewayHandlers.ProxyRequest("finance"))

		// Pending audits
		audit.GET("/pending", gatewayHandlers.ProxyRequest("finance"))

		// Schedules (admin/manager only for modification)
		audit.GET("/schedules", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/schedules", gatewayHandlers.ProxyRequest("finance"))
		audit.GET("/schedules/:id", gatewayHandlers.ProxyRequest("finance"))
		audit.PUT("/schedules/:id", gatewayHandlers.ProxyRequest("finance"))
		audit.DELETE("/schedules/:id", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/schedules/:id/enable", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/schedules/:id/disable", gatewayHandlers.ProxyRequest("finance"))

		// Audit sessions
		audit.GET("/sessions", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions", gatewayHandlers.ProxyRequest("finance"))
		audit.GET("/sessions/:id", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/start", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/submit", gatewayHandlers.ProxyRequest("finance"))

		// Cash audit
		audit.GET("/sessions/:id/cash", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/cash/count", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/cash/verify", gatewayHandlers.ProxyRequest("finance"))

		// Inventory audit
		audit.GET("/sessions/:id/inventory", gatewayHandlers.ProxyRequest("finance"))
		audit.GET("/sessions/:id/inventory/items", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/inventory/count", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/inventory/complete", gatewayHandlers.ProxyRequest("finance"))

		// Review and approval
		audit.POST("/sessions/:id/review", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/approve", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/sessions/:id/reject", gatewayHandlers.ProxyRequest("finance"))

		// Variances
		audit.GET("/variances", gatewayHandlers.ProxyRequest("finance"))
		audit.GET("/variances/:id", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/variances/:id/resolve", gatewayHandlers.ProxyRequest("finance"))
		audit.POST("/variances/:id/investigate", gatewayHandlers.ProxyRequest("finance"))

		// Reports
		audit.GET("/reports/summary", gatewayHandlers.ProxyRequest("finance"))
		audit.GET("/reports/completion", gatewayHandlers.ProxyRequest("finance"))
		audit.GET("/reports/variances", gatewayHandlers.ProxyRequest("finance"))
	}

	// Tenant management (admin and saas_admin only - managers cannot access)
	adminTenants := router.Group("/api/admin")
	adminTenants.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	adminTenants.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	adminTenants.Use(middleware.RoleMiddleware("admin", "saas_admin"))
	{
		adminTenants.GET("/tenants", gatewayHandlers.ProxyRequest("auth"))
		adminTenants.POST("/tenants", gatewayHandlers.ProxyRequest("auth"))
		adminTenants.GET("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))
		adminTenants.PUT("/tenants/:id", gatewayHandlers.ProxyRequest("auth"))
	}

	// User, shop, and other management (admin, manager, and saas_admin)
	// Managers can access these routes but with hierarchy restrictions enforced at handler level
	admin := router.Group("/api/admin")
	admin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	admin.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	admin.Use(middleware.RoleMiddleware("admin", "manager", "saas_admin"))
	{
		// Shop management
		admin.GET("/shops", gatewayHandlers.ProxyRequest("auth"))
		admin.POST("/shops", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/shops/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.PUT("/shops/:id", gatewayHandlers.ProxyRequest("auth"))

		// User management (hierarchy enforced at handler level)
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

	// SaaS Admin PUBLIC routes (authentication - no auth required)
	saasAdminPublic := router.Group("/api/saas-admin")
	{
		// Actual endpoints - CORS middleware handles OPTIONS automatically
		saasAdminPublic.POST("/is-admin", gatewayHandlers.ProxyRequest("saas"))
		saasAdminPublic.POST("/send-otp", gatewayHandlers.ProxyRequest("saas"))
		saasAdminPublic.POST("/verify-otp", gatewayHandlers.ProxyRequest("saas"))
	}

	// Explicit CORS preflight handlers for saas-admin (ensure headers are set)
	router.OPTIONS("/api/saas-admin/is-admin", corsPreflightHandler())
	router.OPTIONS("/api/saas-admin/send-otp", corsPreflightHandler())
	router.OPTIONS("/api/saas-admin/verify-otp", corsPreflightHandler())

	// SaaS Admin PROTECTED routes (super admin functionality)
	saasAdmin := router.Group("/api/saas-admin")
	saasAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	saasAdmin.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
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
	// CORS preflight handlers for super-admin endpoints
	router.OPTIONS("/api/super-admin/brands", corsPreflightHandler())
	router.OPTIONS("/api/super-admin/brands/:id", corsPreflightHandler())
	router.OPTIONS("/api/super-admin/brands/:id/variants", corsPreflightHandler())
	router.OPTIONS("/api/super-admin/brands/categories", corsPreflightHandler())
	router.OPTIONS("/api/super-admin/brands/subcategories", corsPreflightHandler())
	router.OPTIONS("/api/super-admin/tenants", corsPreflightHandler())

	superAdmin := router.Group("/api/super-admin")
	superAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	superAdmin.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
	{
		// Tenant management
		superAdmin.GET("/tenants", gatewayHandlers.ProxyRequest("saas"))

		// Brand packages for tenant onboarding
		superAdmin.GET("/brands/packages", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/assign-package", gatewayHandlers.ProxyRequest("saas"))

		// Brand management endpoints (full CRUD)
		superAdmin.GET("/brands", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/brands/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/:id", gatewayHandlers.ProxyRequest("saas"))

		// Brand variants management
		superAdmin.GET("/brands/:id/variants", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/variants", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/variants/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/variants/:id", gatewayHandlers.ProxyRequest("saas"))

		// Brand categories and subcategories
		superAdmin.GET("/brands/categories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/categories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/categories/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/categories/:id", gatewayHandlers.ProxyRequest("saas"))

		superAdmin.GET("/brands/subcategories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/subcategories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/subcategories/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/subcategories/:id", gatewayHandlers.ProxyRequest("saas"))

		// Bulk operations
		superAdmin.POST("/brands/bulk", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/bulk-assign", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/assign", gatewayHandlers.ProxyRequest("saas"))

		// Stats and cleanup
		superAdmin.GET("/brands/onboarding-stats", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/cleanup", gatewayHandlers.ProxyRequest("saas"))

		// Tenant brand assignments
		superAdmin.GET("/tenants/:tenant_id/brands", gatewayHandlers.ProxyRequest("saas"))
	}

	// SaaS service routes (for brand catalog access)
	saas := router.Group("/api/saas")
	saas.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	saas.Use(rateLimiter.RoleBasedMiddleware()) // Role-based rate limiting AFTER auth
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

	// Static file serving for uploaded images (daily sales, receipts, etc.)
	router.Static("/uploads", "/var/www/liquorpro/uploads")

	// Default 404 handler for non-API routes
	router.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{"error": "Endpoint not found"})
	})
}

// SetupAPIRoutes sets up API-only routes (for API-only deployments)
func SetupAPIRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, db *database.DB, gatewayHandlers *handlers.GatewayHandlers, rateLimiter *middleware.RedisRateLimiter) {
	// This is a variant without frontend routes for pure API deployments
	// Copy all routes from SetupRoutes except the frontend group
	SetupRoutes(router, cfg, cache, db, gatewayHandlers, rateLimiter)
}
