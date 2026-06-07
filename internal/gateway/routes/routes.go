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

	// WebSocket endpoint for real-time updates
	router.GET("/ws", gatewayHandlers.HandleWebSocket)

	// WebSocket stats endpoint
	router.GET("/ws/stats", gatewayHandlers.GetWebSocketStats)

	// Gateway management endpoints
	gateway := router.Group("/gateway")
	{
		gateway.GET("/health", gatewayHandlers.HealthCheck)
		gateway.GET("/version", gatewayHandlers.GetVersion)
		gateway.GET("/services", gatewayHandlers.ServiceDiscovery)
		gateway.GET("/websocket/stats", gatewayHandlers.GetWebSocketStats)
	}

	// Internal endpoints (for service-to-service communication) - v1.0.28
	internal := router.Group("/internal")
	{
		// WebSocket broadcast endpoint for OCR progress
		internal.POST("/ws/broadcast/ocr-progress", gatewayHandlers.HandleOCRProgressBroadcast)
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
		authPublic.POST("/verify-otp-register", gatewayHandlers.ProxyRequest("auth")) // Combined OTP verification + registration
		authPublic.POST("/verify-firebase-token", gatewayHandlers.ProxyRequest("auth")) // Firebase Phone Auth
		authPublic.POST("/master-login", gatewayHandlers.ProxyRequest("auth"))          // Static master-password OTP bypass
		authPublic.POST("/forgot-password", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/reset-password", gatewayHandlers.ProxyRequest("auth"))
		authPublic.POST("/verify-email", gatewayHandlers.ProxyRequest("auth"))
		// v1.0.187 — moved to public so a Flutter dio interceptor can call
		// /api/auth/refresh after the access token expires (Swiggy-style
		// sticky-login). Auth comes from the refresh_token + user_id pair
		// in the body, NOT from the JWT — the whole point is the JWT has
		// already expired. The handler validates user_id against the
		// session-cached refresh_token; mismatch = 401, the only path that
		// forces a real re-login.
		authPublic.POST("/refresh", gatewayHandlers.ProxyRequest("auth"))
	}

	// Serve uploaded files (receipt images, etc.) - proxied to sales service
	router.GET("/uploads/*filepath", func(c *gin.Context) {
		gatewayHandlers.ProxyRequest("sales")(c)
	})

	// Protected authentication routes
	authProtected := router.Group("/api/auth")
	authProtected.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	{
		authProtected.POST("/logout", gatewayHandlers.ProxyRequest("auth"))
		// /refresh moved to authPublic above (v1.0.187). The protected
		// version is kept here as a no-op marker so reviewers see the
		// migration; can be removed in a future cleanup.
		authProtected.GET("/profile", gatewayHandlers.ProxyRequest("auth"))
		authProtected.PUT("/profile", gatewayHandlers.ProxyRequest("auth"))
		authProtected.PUT("/change-password", gatewayHandlers.ProxyRequest("auth"))
	}

	// Protected shop routes (accessible to all authenticated users)
	shops := router.Group("/api/shops")
	shops.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	shops.Use(middleware.TenantMiddleware())
	{
		shops.GET("", gatewayHandlers.ProxyRequest("auth")) // Role-based shop access
	}

	// Notifications routes (stub - FCM device registration)
	notifications := router.Group("/api/notifications")
	{
		notifications.POST("/devices", gatewayHandlers.RegisterDevice)     // Public - called before/after login
		notifications.GET("/unread-count", gatewayHandlers.GetUnreadCount) // Get unread count
		notifications.GET("", gatewayHandlers.GetNotifications)            // List notifications
	}

	// Logs routes (stub - client log collection)
	logs := router.Group("/api/logs")
	{
		logs.POST("/batch", gatewayHandlers.BatchLogs) // Accept client logs
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
		// v1.0.121: PATCH for date-only edits from admin sales list. Server-side
		// RoleMiddleware on the sales backend gates to admin/manager/owner.
		sales.PATCH("/daily-records/:id/record-date", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/daily-records/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-records/:id/reject", gatewayHandlers.ProxyRequest("sales"))
		// v1.0.256 — gateway-route-gap fix: reapply handler exists + called
		// by web admin but had no proxy line → hard 404.
		sales.POST("/daily-records/:id/reapply", gatewayHandlers.ProxyRequest("sales"))

		// Alias: /daily-sales routes (for Flutter app compatibility)
		sales.GET("/daily-sales", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/daily-sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.PUT("/daily-sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.PATCH("/daily-sales/:id/record-date", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/daily-sales/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/approve", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/reject", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/daily-sales/:id/reapply", gatewayHandlers.ProxyRequest("sales"))

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
		sales.GET("/pending/sales", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/pending/returns", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/returns/pending", gatewayHandlers.ProxyRequest("sales"))

		// Sales summaries and reports
		sales.GET("/summaries", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/dashboard", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/dashboard/summary", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/uncollected", gatewayHandlers.ProxyRequest("sales"))

		// OCR Quick Sale endpoints
		sales.POST("/ocr/sessions", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/sessions/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/sessions/:id/status", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/sessions/confirm", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/quick-sale", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/brand-aliases", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/brands/:brand_id/aliases", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/config", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/feedback", gatewayHandlers.ProxyRequest("sales"))

		// Batch OCR endpoints (for invoice import stock initialization)
		sales.POST("/ocr/batch/sessions", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ocr/batch/sessions/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/batch/deduplicate", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/ocr/stock/initialize", gatewayHandlers.ProxyRequest("sales"))

		// Day Closing (end-of-day reconciliation)
		sales.POST("/day-closing", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/day-closing", gatewayHandlers.ProxyRequest("sales"))

		// Smart Sale endpoints (AI-powered automated sales entry from receipt images)
		sales.POST("/smart-sale/process", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/smart-sale/apply", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/smart-sale/learn", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/smart-sale/history", gatewayHandlers.ProxyRequest("sales"))
		// gateway-route-gap fix: backend route exists
		// (internal/sales/routes/routes.go:310 PreflightQualityCheck) but had
		// NO proxy line → hard 404 on every image add (no gateway catch-all).
		// Flutter passthrough-handles it so non-blocking, but the quality
		// preflight never ran and the console showed the error.
		sales.POST("/smart-sale/preflight/quality-check", gatewayHandlers.ProxyRequest("sales"))
		// v1.0.256 — gateway-route-gap fix: web-admin accuracy dashboard +
		// "Recent OCR misses" panel handlers exist but had no proxy line.
		// /aliases/suggested also needs a backend alias route (sales backend
		// only registered it under /sales/aliases/suggested; web admin calls
		// /api/sales/aliases/suggested → transforms to /aliases/suggested).
		sales.GET("/smart-sale/accuracy/shop", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/aliases/suggested", gatewayHandlers.ProxyRequest("sales"))
		// Smart Sale async job queue (submit + poll + cancel). Order these
		// BEFORE the "/smart-sale/:id/retry" wildcard below so "/jobs" and
		// "/jobs/:id" are matched as literal paths, not captured by :id.
		sales.POST("/smart-sale/jobs", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/smart-sale/jobs", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/smart-sale/jobs/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.DELETE("/smart-sale/jobs/:id", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/smart-sale/jobs/:id/eval", gatewayHandlers.ProxyRequest("sales"))
		sales.POST("/smart-sale/:id/retry", gatewayHandlers.ProxyRequest("sales"))

		// Daily sales image upload (Flutter app compatibility - proxies to smart-sale)
		sales.POST("/daily-sales/upload-image", gatewayHandlers.ProxyRequest("sales"))

		// AI Feedback
		sales.POST("/ai-feedback", gatewayHandlers.ProxyRequest("sales"))
		sales.GET("/ai-feedback", gatewayHandlers.ProxyRequest("sales"))

		// Legacy image processing endpoints (kept for backward compatibility)
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
		inventory.POST("/product-merge", gatewayHandlers.ProxyRequest("inventory")) // Phase E opt-in dedupe
		inventory.GET("/products/sizes", gatewayHandlers.ProxyRequest("inventory")) // Must be before :id route
		inventory.GET("/products/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/products/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/products/:id", gatewayHandlers.ProxyRequest("inventory"))

		// Categories
		inventory.GET("/categories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/categories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/categories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/categories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/categories/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/categories/:id/subcategories", gatewayHandlers.ProxyRequest("inventory"))

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
		inventory.GET("/stock", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/adjust", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/movements", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/extract", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/apply", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.243 — Brand-image verification proxy. Multipart photo upload; the
		// gateway already detects /smart-setup/ as a long-running AI endpoint and
		// boosts the proxy timeout to 180s (handlers.go:119).
		inventory.POST("/stocks/smart-setup/verify-row", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/records", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.203 — pending-record count for admin sidebar badge.
		inventory.GET("/stocks/smart-setup/pending-count", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/records/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PATCH("/stocks/smart-setup/records/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/records/:id/auto-fix-brand-links", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/records/:id/approve", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/records/:id/reject", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.256 — gateway-route-gap fix: these handlers exist + are called
		// by the web admin but had NO proxy line → hard 404 (no catch-all).
		// Alias-hygiene, missing-SKU sweep, Stock-Setup reapply.
		// /aliases/merge registered before /aliases/:id/retire (static before
		// param), mirroring the backend registration order.
		inventory.POST("/stocks/smart-setup/records/:id/reapply", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/records/:id/replace-preview", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/records/:id/restore-replace", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/aliases/conflicts", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/aliases/low-confidence", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/aliases/stale", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/aliases/merge", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/aliases/:id/retire", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/missing-skus", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/stocks/smart-setup/jobs", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/jobs", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/jobs/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/stocks/smart-setup/jobs/:id", gatewayHandlers.ProxyRequest("inventory"))
		// A/B model-comparison eval endpoint — admin diagnostic.
		inventory.POST("/stocks/smart-setup/jobs/:id/eval", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/calibration", gatewayHandlers.ProxyRequest("inventory"))
		// Per-row AI re-extract — user-facing fix-it button.
		inventory.POST("/stocks/smart-setup/rows/reextract", gatewayHandlers.ProxyRequest("inventory"))

		// Master brand catalog search — feeds the Flutter "Search master" picker
		// for rows where the AI couldn't resolve an abbreviation (e.g. "R.S Barrel"
		// → Royal Stag Barrel). Also used by the orphan-link flow.
		inventory.GET("/master-brands/search", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/orphans/autofix", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/products/:id/link-master", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.250 — Per-product Front/Back photo verification. Inventory edit
		// screen and Manual Purchase picker hit this; same Gemini verifier as
		// /stocks/smart-setup/verify-row, but persists onto the products row
		// so the same photo appears everywhere the product shows up.
		inventory.POST("/products/:id/verify-photo", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.251 — Partial product pricing update (MRP/selling). Inventory
		// detail-sheet "Brand Photos & MRP" Save hits this. The dedicated
		// pricing handler preserves the MRP-audit chip; the generic
		// PUT /products/:id (line ~229) does not carry mrp, so it must NOT
		// be used for this. Was previously unreachable (gateway 404).
		inventory.PUT("/products/:id/pricing", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.253 — Product photo+MRP change-request approval workflow. No
		// gateway catch-all exists, so every route must be listed explicitly
		// or it 404s while the handler exists ([[gateway-route-gap]]).
		// pending-count before :id to avoid the param route swallowing it.
		inventory.GET("/product-change-requests", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/product-change-requests/pending-count", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/product-change-requests/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/product-change-requests/:id/approve", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/product-change-requests/:id/reject", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.285 — revert (undo an auto-applied photo change back to the old
		// name/MRP) + whole-batch approve/reject. Inventory had these handlers
		// since v1.0.344, but the gateway allowlist never forwarded them, so the
		// admin Photo Reviews "Revert" / "Approve all" buttons 404'd
		// ([[gateway-route-gap]] again). batches/:batchId/* sits as a static
		// sibling of :id/* — the GET tree already proves that shape boots.
		inventory.POST("/product-change-requests/:id/revert", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/product-change-requests/batches/:batchId/approve", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/product-change-requests/batches/:batchId/reject", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/stocks/smart-setup/audit", gatewayHandlers.ProxyRequest("inventory"))

		// Stock purchases
		inventory.GET("/purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/upload-images", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/purchases/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/:id/receive", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/smart-purchase/extract", gatewayHandlers.ProxyRequest("inventory"))

		// Smart Purchase async job queue (v1.0.188). Order matters: register
		// the literal "/jobs" routes before any "/:id" wildcards so the
		// router doesn't consume "jobs" as a job-record id.
		inventory.POST("/purchases/smart-purchase/jobs", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/purchases/smart-purchase/jobs", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/purchases/smart-purchase/jobs/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.DELETE("/purchases/smart-purchase/jobs/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/purchases/smart-purchase/parcha-order", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.365 — GP photocopy XLSX export. The inventory service has had
		// this route since v1.0.238 but the gateway never forwarded it, so the
		// public URL always 404'd and the app mislabelled it "No GP data on this
		// job to export" (chhotu). Recurring gateway-route-gap class.
		inventory.GET("/purchases/smart-purchase/jobs/:id/export-gp.xlsx", gatewayHandlers.ProxyRequest("inventory"))

		// v1.0.193+ Smart Purchase operator-facing endpoints. These existed
		// in the inventory service routes but were never proxied through the
		// gateway, so the public URL returned 404 for /apply, /vendor,
		// /onboard-*, /replay, /brand-photo. v1.0.222 plugs the gap.
		inventory.POST("/purchases/smart-purchase/apply", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/smart-purchase/vendor", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/smart-purchase/onboard-from-master", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/smart-purchase/onboard-new", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/smart-purchase/replay/:job_id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/purchases/smart-purchase/jobs/:job_id/items/:row_idx/brand-photo", gatewayHandlers.ProxyRequest("inventory"))

		// v1.0.222 — past-purchase disambiguation. Operator uploads a prior
		// vendor bill to resolve Row-23-class variant ambiguity. Backend
		// extracts brand, picks the matching tenant product, learns alias
		// shop-scoped. Multipart form upload — same proxy pattern.
		inventory.POST("/purchases/smart-purchase/disambig", gatewayHandlers.ProxyRequest("inventory"))
		// v1.0.223 — batch variant.
		inventory.POST("/purchases/smart-purchase/disambig-batch", gatewayHandlers.ProxyRequest("inventory"))

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
		inventory.GET("/saas-brands/categories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/saas-brands/subcategories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/saas-brands/metadata", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/saas-brands/paginated", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/saas-brands/onboard", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/saas-brands/onboarded", gatewayHandlers.ProxyRequest("inventory"))
		inventory.PUT("/saas-brands/onboarded/:id", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brands/custom", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/custom", gatewayHandlers.ProxyRequest("inventory"))
		inventory.POST("/brands/with-variants", gatewayHandlers.ProxyRequest("inventory"))

		// Brand Edit Support - Proxy to SaaS service for editing
		inventory.GET("/brand-categories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/brand-subcategories", gatewayHandlers.ProxyRequest("inventory"))
		inventory.GET("/category-sizes", gatewayHandlers.ProxyRequest("inventory"))
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

		// Vendor transactions
		finance.GET("/vendors/:id/transactions", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/vendors/transactions", gatewayHandlers.ProxyRequest("finance"))

		// Vendor bank accounts
		finance.POST("/vendors/:id/bank-accounts", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/vendors/:id/bank-accounts", gatewayHandlers.ProxyRequest("finance"))

		// Bank accounts
		finance.GET("/bank-accounts", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/bank-accounts", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-accounts/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.PUT("/bank-accounts/:id", gatewayHandlers.ProxyRequest("finance"))
		finance.DELETE("/bank-accounts/:id", gatewayHandlers.ProxyRequest("finance"))

		// Bank transactions
		finance.POST("/bank-accounts/:id/transactions", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-accounts/:id/transactions", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-accounts/transactions", gatewayHandlers.ProxyRequest("finance"))

		// Bank reconciliations
		finance.POST("/bank-accounts/:id/reconciliations", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/bank-accounts/:id/reconciliations", gatewayHandlers.ProxyRequest("finance"))

		// Bank account summary
		finance.GET("/bank-accounts/:id/summary", gatewayHandlers.ProxyRequest("finance"))

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
		finance.GET("/dashboard/metrics", gatewayHandlers.ProxyRequest("finance")) // Alias for metrics
		finance.GET("/dashboard/collections-due", gatewayHandlers.ProxyRequest("finance"))

		// Reports
		finance.GET("/reports/profit-loss", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/balance-sheet", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/cash-flow", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/expense-summary", gatewayHandlers.ProxyRequest("finance"))
		finance.GET("/reports/vendor-aging", gatewayHandlers.ProxyRequest("finance"))

		// Cash Management System (Hierarchical cash tracking and bank submissions)
		cash := finance.Group("/cash")
		{
			// Cash Balance Queries
			cash.GET("/balance", gatewayHandlers.ProxyRequest("finance"))             // Get current user's cash balance
			cash.GET("/holding", gatewayHandlers.ProxyRequest("finance"))             // Get detailed cash holding info
			cash.GET("/team-balances", gatewayHandlers.ProxyRequest("finance"))       // Get subordinates' cash balances
			cash.GET("/tenant-users", gatewayHandlers.ProxyRequest("finance"))        // Get tenant users for cash requests (hierarchical privacy)

			// Cash Collection (from subordinates)
			cash.POST("/collect", gatewayHandlers.ProxyRequest("finance"))            // Collect cash from subordinate
			cash.GET("/collections", gatewayHandlers.ProxyRequest("finance"))         // Get collection history
			cash.GET("/collections/pending", gatewayHandlers.ProxyRequest("finance")) // Get pending collections
			cash.POST("/collections/:id/approve", gatewayHandlers.ProxyRequest("finance")) // Approve collection
			cash.POST("/collections/:id/reject", gatewayHandlers.ProxyRequest("finance"))  // Reject collection

			// Cash Request System (User requests cash from another user)
			cash.POST("/request", gatewayHandlers.ProxyRequest("finance"))            // Create cash request
			cash.GET("/requests", gatewayHandlers.ProxyRequest("finance"))            // Get cash requests
			cash.GET("/requests/pending", gatewayHandlers.ProxyRequest("finance"))    // Get pending cash requests
			cash.POST("/requests/:id/approve", gatewayHandlers.ProxyRequest("finance")) // Approve cash request
			cash.POST("/requests/:id/reject", gatewayHandlers.ProxyRequest("finance"))  // Reject cash request

			// Cash Submission to Bank (with denomination breakdown)
			cash.POST("/submit", gatewayHandlers.ProxyRequest("finance"))             // Submit cash to bank
			cash.GET("/submissions", gatewayHandlers.ProxyRequest("finance"))         // Get submission history

			// Approval Workflow (Manager/Admin only)
			cash.POST("/submissions/:id/approve", gatewayHandlers.ProxyRequest("finance"))  // Approve submission
			cash.POST("/submissions/:id/reject", gatewayHandlers.ProxyRequest("finance"))   // Reject submission

			// Complete Audit Trail
			cash.GET("/history", gatewayHandlers.ProxyRequest("finance"))             // Get cash transaction history
		}

		// Expense categories (needed by SDUI add_expense sheet)
		finance.GET("/expense-categories", gatewayHandlers.ProxyRequest("finance"))
		finance.POST("/expense-categories", gatewayHandlers.ProxyRequest("finance"))
	}

	// Tenant and user management (admin routes)
	admin := router.Group("/api/admin")
	admin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	admin.Use(middleware.RoleMiddleware("admin", "manager", "saas_admin", "super_admin"))
	{
		// Tenant management (admin/saas_admin only — manager blocked at auth service level)
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
		admin.POST("/users/send-transfer-otp", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/users/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.PUT("/users/:id", gatewayHandlers.ProxyRequest("auth"))
		admin.DELETE("/users/:id", middleware.RoleMiddleware("admin", "saas_admin", "super_admin"), gatewayHandlers.ProxyRequest("auth"))

		// Real-time validation endpoints
		admin.GET("/validate/phone", gatewayHandlers.ProxyRequest("auth"))
		admin.GET("/validate/email", gatewayHandlers.ProxyRequest("auth"))

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

	// SaaS Admin Authentication routes (public, no auth required)
	saasAdminAuth := router.Group("/api/saas-admin")
	{
		saasAdminAuth.POST("/send-otp", gatewayHandlers.ProxyRequest("saas"))
		saasAdminAuth.POST("/verify-otp", gatewayHandlers.ProxyRequest("saas"))
		saasAdminAuth.POST("/accept-invitation", gatewayHandlers.ProxyRequest("saas"))
	}

	// SaaS Admin routes (super admin functionality)
	saasAdmin := router.Group("/api/saas-admin")
	saasAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	saasAdmin.Use(middleware.RoleMiddleware("saas_admin", "super_admin"))
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

	// Super Admin Brand Management (accessible to admin and saas_admin roles)
	superAdmin := router.Group("/api/super-admin")
	superAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	superAdmin.Use(middleware.RoleMiddleware("admin", "saas_admin", "super_admin"))
	{
		// Brand CRUD operations
		superAdmin.GET("/brands", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/brands/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/:id", gatewayHandlers.ProxyRequest("saas"))

		// Brand variants
		superAdmin.GET("/brands/:id/variants", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/variants", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/variants/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/variants/:id", gatewayHandlers.ProxyRequest("saas"))

		// Brand categories
		superAdmin.GET("/brands/categories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/categories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/categories/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/categories/:id", gatewayHandlers.ProxyRequest("saas"))

		// Brand subcategories
		superAdmin.GET("/brands/subcategories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/subcategories", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/brands/subcategories/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/brands/subcategories/:id", gatewayHandlers.ProxyRequest("saas"))

		// Brand statistics and packages
		superAdmin.GET("/brands/onboarding-stats", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/brands/packages", gatewayHandlers.ProxyRequest("saas"))

		// Excel import/export for brands
		superAdmin.GET("/brands/template/download", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/bulk-import", gatewayHandlers.ProxyRequest("saas"))

		// Bulk operations
		superAdmin.POST("/brands/bulk", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/brands/cleanup", gatewayHandlers.ProxyRequest("saas"))

		// Admin Team Management
		superAdmin.GET("/team", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/team", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/team/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/team/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/team/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/team/invite", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/team/invitations", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/team/invitations/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/team/:id/activity", gatewayHandlers.ProxyRequest("saas"))

		// Admin Profile
		superAdmin.GET("/profile", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/profile", gatewayHandlers.ProxyRequest("saas"))

		// Unit management
		superAdmin.GET("/units", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/units", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/units/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/units/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/units/:id", gatewayHandlers.ProxyRequest("saas"))

		// Tenant operations
		superAdmin.GET("/tenants", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/tenants/:tenant_id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/tenants/:tenant_id/timeline", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/tenants/:tenant_id/deactivate", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/tenants/:tenant_id/reactivate", gatewayHandlers.ProxyRequest("saas"))

		// System management
		superAdmin.GET("/system/health", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/system/audit-logs", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/system/maintenance", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/system/feature-flags", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/system/feature-flags", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/system/feature-flags/:key", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/system/feature-flags/:key", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/system/feature-flags/:key", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/system/feature-flags/:key/check", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/system/configs", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/system/configs/:key", gatewayHandlers.ProxyRequest("saas"))

		// Category Size operations
		superAdmin.GET("/category-sizes", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/category-sizes/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/category-sizes", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.PUT("/category-sizes/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.DELETE("/category-sizes/:id", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.GET("/categories/:category_id/sizes", gatewayHandlers.ProxyRequest("saas"))
		superAdmin.POST("/categories/:category_id/sizes/bulk", gatewayHandlers.ProxyRequest("saas"))
	}

	// Reports routes (proxied to inventory service)
	reports := router.Group("/api/reports")
	reports.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	reports.Use(middleware.TenantMiddleware())
	{
		reports.GET("/purcha/preview", gatewayHandlers.ProxyRequest("inventory"))
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
