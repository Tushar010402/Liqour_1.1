package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/sales/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all sales service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, salesHandlers *handlers.SalesHandlers, ocrHandlers *handlers.OCRHandlers, smartSaleHandlers *handlers.SmartSaleHandlers, aiFeedbackHandlers *handlers.AIFeedbackHandlers) {
	// Health check
	router.GET("/health", salesHandlers.Health)

	// All routes require authentication and tenant isolation
	api := router.Group("/api")
	api.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	api.Use(middleware.TenantMiddleware())

	// Daily Sales Routes (Critical for bulk entry workflow)
	// All authenticated tenant users can create/update daily sales
	dailySales := api.Group("/daily-records")
	{
		dailySales.GET("", salesHandlers.GetDailySalesRecords)
		dailySales.POST("", salesHandlers.CreateDailySalesRecord) // All tenant users can create
		dailySales.GET("/:id", salesHandlers.GetDailySalesRecordByID)
		dailySales.PUT("/:id", salesHandlers.UpdateDailySalesRecord) // All tenant users can update
		// v1.0.121: dedicated date-only PATCH so admin can correct a wrong date
		// from the list page without re-submitting the entire record. Restricted
		// to admin/manager/owner because date drift affects reports + dashboards.
		dailySales.PATCH("/:id/record-date", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.UpdateDailySalesRecordDate)
		dailySales.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.ApproveDailySalesRecord)
		dailySales.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.RejectDailySalesRecord)
		// v1.0.133 — within-7-days reapply for approved sales. Snaps stock back
		// to the closing_stock recorded on each item, undoing any drift since
		// approval. Returns 410 Gone past the 7-day window.
		dailySales.POST("/:id/reapply", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.ReapplyDailySalesRecord)
		// v1.0.149 — operator-driven row reorder on Sales Summary. Bulk update
		// daily_sales_items.position so every other view (web admin, daily
		// entry summary, mobile sales history) renders the same order.
		dailySales.PATCH("/:id/items/reorder", salesHandlers.ReorderDailySalesItems)
	}

	// Alias: /daily-sales routes (for Flutter app compatibility)
	dailySalesAlias := api.Group("/daily-sales")
	{
		dailySalesAlias.GET("", salesHandlers.GetDailySalesRecords)
		dailySalesAlias.POST("", salesHandlers.CreateDailySalesRecord)
		dailySalesAlias.GET("/:id", salesHandlers.GetDailySalesRecordByID)
		dailySalesAlias.PUT("/:id", salesHandlers.UpdateDailySalesRecord)
		dailySalesAlias.PATCH("/:id/record-date", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.UpdateDailySalesRecordDate)
		dailySalesAlias.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.ApproveDailySalesRecord)
		dailySalesAlias.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.RejectDailySalesRecord)
		dailySalesAlias.POST("/:id/reapply", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.ReapplyDailySalesRecord)
		dailySalesAlias.PATCH("/:id/items/reorder", salesHandlers.ReorderDailySalesItems)
		dailySalesAlias.POST("/upload-image", salesHandlers.UploadDailySalesImage)
	}

	// v1.0.162 — admin-only data-heal endpoints.
	salesAdmin := api.Group("/sales/admin")
	salesAdmin.Use(middleware.RoleMiddleware("admin", "owner"))
	{
		salesAdmin.POST("/heal-approve-corruption", salesHandlers.HealApproveCorruption)
	}

	// v1.0.175 — Brand Shortcuts. Lets operators see / add / remove the
	// alias rows the Smart Sale + Stock Setup matchers already consume.
	// Same auth + tenant middleware as the rest of /api/sales (inherited
	// from the `api` group above). All authenticated tenant users can
	// list/create/delete; tenant_id scoping enforced server-side.
	aliases := api.Group("/sales/aliases")
	{
		aliases.GET("", salesHandlers.ListBrandAliases)
		aliases.POST("", salesHandlers.CreateBrandAlias)
		aliases.DELETE("/:id", salesHandlers.DeleteBrandAlias)
	}

	// Individual Sales Routes
	// All authenticated tenant users can create sales
	sales := api.Group("/sales")
	{
		sales.GET("", salesHandlers.GetSales)
		sales.POST("", salesHandlers.CreateSale) // All tenant users can create
		sales.GET("/:id", salesHandlers.GetSaleByID)
		sales.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.ApproveSale)
		sales.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.RejectSale)
	}

	// Sale Returns Routes
	// All authenticated tenant users can create returns
	returns := api.Group("/returns")
	{
		returns.GET("", salesHandlers.GetSaleReturns)
		returns.POST("", salesHandlers.CreateSaleReturn) // All tenant users can create
		returns.GET("/:id", salesHandlers.GetSaleReturnByID)
		returns.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.ApproveSaleReturn)
		returns.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.RejectSaleReturn)
	}

	// Pending Items (for approval workflows)
	pending := api.Group("/pending")
	{
		pending.GET("/sales", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.GetPendingSales)
		pending.GET("/returns", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.GetPendingReturns)
	}

	// Financial Reports
	financial := api.Group("/financial")
	{
		financial.GET("/uncollected", middleware.RoleMiddleware("executive", "manager", "admin", "owner"), salesHandlers.GetUncollectedSales)
	}

	// Dashboard and Summary Routes
	dashboard := api.Group("/dashboard")
	{
		dashboard.GET("/summary", salesHandlers.GetDashboardSummary)
	}

	// Day Closing Routes (end-of-day reconciliation)
	dayClosing := api.Group("/day-closing")
	{
		dayClosing.POST("", salesHandlers.SaveDayClosing)
		dayClosing.GET("", salesHandlers.GetDayClosing)
	}

	// OCR and Quick Sale Routes - Receipt Scanning for Automated Sales Entry
	ocr := api.Group("/ocr")
	{
		// Create and manage OCR sessions (all authenticated users can use)
		ocr.POST("/sessions", ocrHandlers.CreateOCRSession)
		ocr.GET("/sessions/:id", ocrHandlers.GetOCRSession)
		ocr.GET("/sessions/:id/status", ocrHandlers.GetOCRSessionStatus)

		// Batch OCR for multi-image processing (manager/admin only for stock initialization)
		ocr.POST("/batch/sessions", middleware.RoleMiddleware("manager", "admin"), ocrHandlers.CreateBatchOCRSession)
		ocr.GET("/batch/sessions/:id", middleware.RoleMiddleware("manager", "admin"), ocrHandlers.GetBatchOCRSession)
		ocr.POST("/batch/deduplicate", middleware.RoleMiddleware("manager", "admin"), ocrHandlers.GetDeduplicatedItems)

		// Stock initialization from OCR (manager/admin only)
		ocr.POST("/stock/initialize", middleware.RoleMiddleware("manager", "admin"), ocrHandlers.InitializeStockFromOCR)

		// Confirm extracted items and create sale
		ocr.POST("/sessions/confirm", ocrHandlers.ConfirmOCRItems)
		ocr.POST("/quick-sale", ocrHandlers.CreateQuickSaleFromOCR)

		// Brand alias management (manager/admin only)
		ocr.POST("/brand-aliases", middleware.RoleMiddleware("manager", "admin"), ocrHandlers.CreateBrandAlias)
		ocr.GET("/brands/:brand_id/aliases", ocrHandlers.GetBrandAliases)

		// OCR configuration and feedback
		ocr.GET("/config", ocrHandlers.GetOCRConfig)
		ocr.POST("/feedback", ocrHandlers.SubmitOCRFeedback)
	}

	// Smart Sale Routes - AI-powered automated sales entry from receipt images
	if smartSaleHandlers != nil {
		smartSale := api.Group("/smart-sale")
		{
			// Process images and create daily sales entries (all authenticated users)
			smartSale.POST("/process", smartSaleHandlers.ProcessSmartSale)
			smartSale.POST("/apply", smartSaleHandlers.ApplySmartSale)
			smartSale.GET("/history", smartSaleHandlers.GetSmartSaleHistory)
			smartSale.POST("/:id/retry", smartSaleHandlers.RetrySmartSale)
			smartSale.POST("/learn", smartSaleHandlers.LearnFromSmartSale)
			// v1.0.183 Track C2 — operator answers ONE doubted cell from the
			// popup queue. Captures (raw → corrected) into ocr_digit_corrections
			// immediately so the next extraction at this shop benefits even if
			// the apply later fails or is abandoned.
			smartSale.POST("/doubt/resolve", smartSaleHandlers.ResolveDoubt)
			// v1.0.147 — apple-to-apple page grid for the verification screen.
			// Returns per-cell crops + AI-suggested values so the operator
			// can verify the image→spreadsheet conversion BEFORE proceeding
			// to the Sales Summary. Order is preserved row-for-row to the
			// image (NOT MRP-sorted).
			smartSale.POST("/page-grid", smartSaleHandlers.GetPageGrid)
		}
	}

	// AI Feedback Routes
	if aiFeedbackHandlers != nil {
		api.POST("/ai-feedback", aiFeedbackHandlers.SubmitAIFeedback)
		api.GET("/ai-feedback", middleware.RoleMiddleware("manager", "admin", "owner"), aiFeedbackHandlers.GetAIFeedback)
	}
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling.
// smartSaleJobHandlers is optional (nil skips the async-job endpoints) so
// we can roll back the job flow without touching the sync handler wiring.
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, salesHandlers *handlers.SalesHandlers, ocrHandlers *handlers.OCRHandlers, smartSaleHandlers *handlers.SmartSaleHandlers, aiFeedbackHandlers *handlers.AIFeedbackHandlers, smartSaleJobHandlers *handlers.SmartSaleJobHandlers) {
	// Health check (no auth required)
	router.GET("/health", salesHandlers.Health)

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

	// Daily Sales Routes (Critical bulk entry endpoints)
	router.GET("/daily-records", salesHandlers.GetDailySalesRecords)
	router.POST("/daily-records", salesHandlers.CreateDailySalesRecord)
	router.GET("/daily-records/:id", salesHandlers.GetDailySalesRecordByID)
	router.PUT("/daily-records/:id", salesHandlers.UpdateDailySalesRecord)
	// v1.0.121: dedicated date-only PATCH so admin can correct a wrong sale
	// date from the list page without re-submitting items. Server-side
	// RoleMiddleware enforces admin/manager/owner — UI mirrors the same gate.
	router.PATCH("/daily-records/:id/record-date", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.UpdateDailySalesRecordDate)
	router.POST("/daily-records/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-records/:id/reject", salesHandlers.RejectDailySalesRecord)
	router.POST("/daily-records/:id/reapply", salesHandlers.ReapplyDailySalesRecord)

	// Alias: /daily-sales routes (for Flutter app compatibility)
	router.GET("/daily-sales", salesHandlers.GetDailySalesRecords)
	router.POST("/daily-sales", salesHandlers.CreateDailySalesRecord)
	router.GET("/daily-sales/:id", salesHandlers.GetDailySalesRecordByID)
	router.PUT("/daily-sales/:id", salesHandlers.UpdateDailySalesRecord)
	router.PATCH("/daily-sales/:id/record-date", middleware.RoleMiddleware("manager", "admin", "owner"), salesHandlers.UpdateDailySalesRecordDate)
	router.POST("/daily-sales/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-sales/:id/reject", salesHandlers.RejectDailySalesRecord)
	router.POST("/daily-sales/:id/reapply", salesHandlers.ReapplyDailySalesRecord)
	router.POST("/daily-sales/upload-image", salesHandlers.UploadDailySalesImage)

	// v1.0.162 — admin-only data-heal endpoints (gateway-stripped path).
	router.POST("/sales/admin/heal-approve-corruption", middleware.RoleMiddleware("admin", "owner"), salesHandlers.HealApproveCorruption)

	// v1.0.175 — Brand Shortcuts (gateway-stripped path).
	router.GET("/sales/aliases", salesHandlers.ListBrandAliases)
	router.POST("/sales/aliases", salesHandlers.CreateBrandAlias)
	router.DELETE("/sales/aliases/:id", salesHandlers.DeleteBrandAlias)
	// v1.0.182 — D2 suggested-aliases. OCR strings stuck on not_found in last
	// 30d that don't have a learned alias yet. Powers Brand Shortcuts'
	// "Recent OCR misses" panel.
	router.GET("/sales/aliases/suggested", salesHandlers.ListSuggestedAliases)
	// v1.0.256 — gateway strips /api/sales/ → /, so the web admin's
	// /api/sales/aliases/suggested arrives as /aliases/suggested. Register
	// that alias (same compat pattern as the /daily-sales alias routes
	// above) so the "Recent OCR misses" panel stops 404ing.
	router.GET("/aliases/suggested", salesHandlers.ListSuggestedAliases)

	// Individual Sales Routes
	router.GET("/sales", salesHandlers.GetSales)
	router.POST("/sales", salesHandlers.CreateSale)
	router.GET("/sales/:id", salesHandlers.GetSaleByID)
	router.POST("/sales/:id/approve", salesHandlers.ApproveSale)
	router.POST("/sales/:id/reject", salesHandlers.RejectSale)

	// Sale Returns Routes
	router.GET("/returns", salesHandlers.GetSaleReturns)
	router.POST("/returns", salesHandlers.CreateSaleReturn)
	router.GET("/returns/:id", salesHandlers.GetSaleReturnByID)
	router.POST("/returns/:id/approve", salesHandlers.ApproveSaleReturn)
	router.POST("/returns/:id/reject", salesHandlers.RejectSaleReturn)

	// Pending and Financial Routes
	router.GET("/pending/sales", salesHandlers.GetPendingSales)
	router.GET("/pending/returns", salesHandlers.GetPendingReturns)
	router.GET("/uncollected", salesHandlers.GetUncollectedSales)

	// Dashboard
	router.GET("/dashboard/summary", salesHandlers.GetDashboardSummary)

	// Day Closing (end-of-day reconciliation)
	router.POST("/day-closing", salesHandlers.SaveDayClosing)
	router.GET("/day-closing", salesHandlers.GetDayClosing)

	// OCR and Quick Sale Routes
	router.POST("/ocr/sessions", ocrHandlers.CreateOCRSession)
	router.GET("/ocr/sessions/:id", ocrHandlers.GetOCRSession)
	router.GET("/ocr/sessions/:id/status", ocrHandlers.GetOCRSessionStatus)

	// Batch OCR endpoints
	router.POST("/ocr/batch/sessions", ocrHandlers.CreateBatchOCRSession)
	router.GET("/ocr/batch/sessions/:id", ocrHandlers.GetBatchOCRSession)
	router.POST("/ocr/batch/deduplicate", ocrHandlers.GetDeduplicatedItems)

	// Stock initialization from OCR
	router.POST("/ocr/stock/initialize", ocrHandlers.InitializeStockFromOCR)

	router.POST("/ocr/sessions/confirm", ocrHandlers.ConfirmOCRItems)
	router.POST("/ocr/quick-sale", ocrHandlers.CreateQuickSaleFromOCR)
	router.POST("/ocr/brand-aliases", ocrHandlers.CreateBrandAlias)
	router.GET("/ocr/brands/:brand_id/aliases", ocrHandlers.GetBrandAliases)
	router.GET("/ocr/config", ocrHandlers.GetOCRConfig)
	router.POST("/ocr/feedback", ocrHandlers.SubmitOCRFeedback)

	// Smart Sale Routes - AI-powered automated sales entry
	if smartSaleHandlers != nil {
		router.POST("/smart-sale/process", smartSaleHandlers.ProcessSmartSale)
		router.POST("/smart-sale/apply", smartSaleHandlers.ApplySmartSale)
		router.GET("/smart-sale/history", smartSaleHandlers.GetSmartSaleHistory)
		router.POST("/smart-sale/:id/retry", smartSaleHandlers.RetrySmartSale)
		router.POST("/smart-sale/learn", smartSaleHandlers.LearnFromSmartSale)
		// v1.0.183 Track C2 — doubt resolution write
		router.POST("/smart-sale/doubt/resolve", smartSaleHandlers.ResolveDoubt)
		// v1.0.147 — apple-to-apple page grid for the verification screen
		router.POST("/smart-sale/page-grid", smartSaleHandlers.GetPageGrid)
		// v1.0.178 — image-quality preflight (Flutter calls before /process so
		// blurry/tilted photos hit the modal instead of the AI bill). Shared by
		// Smart Sale and AI Stock Setup; lives under /sales/* to keep the
		// cv-sidecar URL off the mobile client.
		router.POST("/smart-sale/preflight/quality-check", smartSaleHandlers.PreflightQualityCheck)
	}

	// Smart Sale Job Routes — async submit-and-poll flow that supplants
	// the blocking /smart-sale/process endpoint for the Flutter app. Clients
	// submit images, receive job_id, poll status, and apply the result once
	// the worker finishes. Order before the :id/retry route above would
	// conflict; the /jobs prefix keeps them separate. Registered LAST so
	// static paths ("jobs") are matched before the "/smart-sale/:id/retry"
	// wildcard-style route Gin registered above.
	if smartSaleJobHandlers != nil {
		router.POST("/smart-sale/jobs", smartSaleJobHandlers.SubmitJob)
		router.GET("/smart-sale/jobs", smartSaleJobHandlers.ListJobs)
		router.GET("/smart-sale/jobs/:id", smartSaleJobHandlers.GetJob)
		router.DELETE("/smart-sale/jobs/:id", smartSaleJobHandlers.CancelJob)
	}
	// A/B eval — replays a Smart Sale job through the current OCR pipeline and
	// returns fresh-vs-original. Tenant-scoped. Mirrors the Stock Setup eval.
	if smartSaleHandlers != nil {
		router.POST("/smart-sale/jobs/:id/eval", smartSaleHandlers.EvaluateJob)
		// v1.0.133 — admin replay-learning. Mirrors the Stock Setup endpoint;
		// re-runs alias / negative-alias / shop-rate learning against a job's
		// review-screen state without writing any sale rows. Used to recover
		// learning signal from past apply failures.
		router.POST("/smart-sale/jobs/:id/replay-learning", smartSaleHandlers.ReplayJobLearning)
		// v1.0.181 — per-shop accuracy aggregate. Tenant-scoped via auth
		// context; optional ?shop_id and ?days query params (days defaults
		// to 30, capped at 365). Operational health metrics for an admin
		// dashboard, NOT true accuracy — no ground truth available here.
		router.GET("/smart-sale/accuracy/shop", smartSaleHandlers.AccuracyShopSummary)
	}

	// AI Feedback Routes
	if aiFeedbackHandlers != nil {
		router.POST("/ai-feedback", aiFeedbackHandlers.SubmitAIFeedback)
		router.GET("/ai-feedback", aiFeedbackHandlers.GetAIFeedback)
	}
}
