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
		products.GET("/sizes", inventoryHandlers.GetProductSizes) // Must be before :id
		products.POST("", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreateProduct)
		products.GET("/:id", inventoryHandlers.GetProductByID)
		products.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.UpdateProduct)
		products.DELETE("/:id", middleware.RoleMiddleware("admin"), inventoryHandlers.DeleteProduct)
	}

	// Stock Management Routes (Critical for inventory tracking)
	// Support both /stock (singular) and /stocks (plural) for compatibility
	api.GET("/stock", inventoryHandlers.GetStocks) // Singular endpoint for compatibility

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
		purchases.GET("/summary", inventoryHandlers.GetPurchasesSummary)
		purchases.POST("", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.CreatePurchase)
		purchases.GET("/:id", inventoryHandlers.GetPurchaseByID)
		purchases.GET("/:id/print", inventoryHandlers.PrintPurchaseRegister)
		purchases.POST("/:id/receive", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.ReceivePurchase)
		purchases.POST("/upload-images", middleware.RoleMiddleware("manager", "admin"), inventoryHandlers.UploadPurchaseImages)
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
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, inventoryHandlers *handlers.InventoryHandlers, aliasHygieneHandler *handlers.AliasHygieneHandler, missingSkuHandler *handlers.MissingSkuHandler, smartPurchaseJobHandlers *handlers.SmartPurchaseJobHandlers, smartPurchaseVendorHandler *handlers.SmartPurchaseVendorHandler, smartPurchaseApplyHandler *handlers.SmartPurchaseApplyHandler, smartPurchaseBrandPhotoHandler *handlers.SmartPurchaseBrandPhotoHandler, smartPurchaseOnboardHandler *handlers.SmartPurchaseOnboardHandler, smartPurchaseReplayHandler *handlers.SmartPurchaseReplayHandler, smartPurchaseDisambigHandler *handlers.SmartPurchaseDisambigHandler, smartStockSetupVerifyHandler *handlers.SmartStockSetupVerifyHandler, productMergeHandler *handlers.ProductMergeHandler) {
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
	router.GET("/products/sizes", inventoryHandlers.GetProductSizes) // Must be before :id
	router.POST("/products", inventoryHandlers.CreateProduct)

	// Product-specific routes (before :id to avoid conflicts)
	router.PUT("/products/:id/pricing", inventoryHandlers.UpdateProductPricing)

	// v1.0.344 — AI-Purchase photo-completeness precondition (drives the
	// hard-gated home Purchase Entry button + the shop-wide onboarding screen).
	// MUST be before /products/:id so "photo-status" isn't captured as an :id.
	router.GET("/products/photo-status", smartStockSetupVerifyHandler.ProductPhotoStatus)

	// Standard product CRUD routes
	router.GET("/products/:id", inventoryHandlers.GetProductByID)
	router.PUT("/products/:id", inventoryHandlers.UpdateProduct)
	router.DELETE("/products/:id", inventoryHandlers.DeleteProduct)

	// Stock Management Routes
	// Support both /stock (singular) and /stocks (plural) for compatibility
	router.GET("/stock", inventoryHandlers.GetStocks) // Singular endpoint for compatibility
	router.GET("/stocks", inventoryHandlers.GetStocks)
	router.POST("/stocks/adjust", inventoryHandlers.AdjustStock)
	router.POST("/stocks/transfer", inventoryHandlers.TransferStock)
	router.GET("/stocks/movements", inventoryHandlers.GetStockMovements)

	// Smart Stock Setup (AI-powered opening stock from register images)
	// /extract + /apply are the legacy synchronous flow (kept for compatibility).
	router.POST("/stocks/smart-setup/extract", inventoryHandlers.SmartStockSetupExtract)
	router.POST("/stocks/smart-setup/apply", inventoryHandlers.SmartStockSetupApply)

	// v1.0.243 — Per-row brand-image verification. Operator uploads one bottle/
	// case photo per row; Gemini Flash 2.0 returns canonical brand + variant.
	// Apply endpoint rejects rows that haven't passed this gate.
	router.POST("/stocks/smart-setup/verify-row", smartStockSetupVerifyHandler.VerifyRow)

	// v1.0.250 — Per-product photo verification. Used by inventory edit
	// screen, Manual Purchase product picker, and the Stock Setup "Add
	// Missing Brands" manual entries. Persists onto products table so the
	// same photo appears everywhere the product is shown.
	router.POST("/products/:id/verify-photo", smartStockSetupVerifyHandler.VerifyProduct)

	// Background-job flow — submit returns a job_id immediately; clients poll
	// GET /jobs/:id for status and eventual result. Decouples the extraction
	// from the client's connection so a network drop / app close doesn't lose
	// work. The /jobs list feeds the "active jobs" banner in Flutter.
	router.POST("/stocks/smart-setup/jobs", inventoryHandlers.SubmitStockSetupJob)
	router.GET("/stocks/smart-setup/jobs", inventoryHandlers.ListStockSetupJobs)
	router.GET("/stocks/smart-setup/jobs/:id", inventoryHandlers.GetStockSetupJob)
	router.DELETE("/stocks/smart-setup/jobs/:id", inventoryHandlers.CancelStockSetupJob)
	// A/B eval — replays a job through ["claude", "gemini", ...] and returns a
	// row-by-row diff. Tenant-scoped. Used to measure model / prompt / vote
	// changes against real production register images without re-upload.
	router.POST("/stocks/smart-setup/jobs/:id/eval", inventoryHandlers.EvaluateStockSetupJob)
	// v1.0.132 — replay alias-learning + correction-outcome capture for a
	// job whose apply silently failed (SQLSTATE 42703 incident). Body =
	// the user's review-screen items (same shape as /apply). Idempotent —
	// safe to call multiple times. Tenant + user scoped.
	router.POST("/stocks/smart-setup/jobs/:id/replay-learning", inventoryHandlers.ReplayStockSetupJobLearning)
	// Calibrated low-confidence threshold for the per-tenant amber-underline
	// UI. Returns 0.7 default when sample count < 100.
	router.GET("/stocks/smart-setup/calibration", inventoryHandlers.GetSmartSetupCalibration)

	// Per-row AI re-extract — Flutter "re-extract this row" button calls this
	// when a specific row's brand or numbers look wrong. Constrained master-brand
	// prompt prevents the AI from inventing brands (fixes the hallucinated
	// "Smoke Lab Classic" case on row 43 of the 2026-04-20 failure job).
	router.POST("/stocks/smart-setup/rows/reextract", inventoryHandlers.ReextractRow)

	// v1.0.185 Track S5 — Stock Setup doubt-popup queue resolve. Flutter
	// posts ONE operator answer per cell from the StockSetupDoubtModal walker
	// before the review screen renders. Captures (raw → corrected) into
	// ocr_digit_corrections (source='stock_setup') so the next extraction at
	// this shop benefits regardless of whether apply later succeeds. "Ask
	// once, learn forever".
	router.POST("/stocks/smart-setup/doubt/resolve", inventoryHandlers.ResolveStockSetupDoubt)

	// Orphan product → master brand linking (surfaced from the Smart Stock Setup
	// audit banner so the user can clean up data hygiene without leaving the app).
	// Autofix defaults to dry-run — mutation requires explicit ?dry_run=false.
	router.POST("/products/:id/link-master", inventoryHandlers.LinkProductToMaster)
	router.GET("/master-brands/search", inventoryHandlers.SearchMasterBrands)
	router.POST("/orphans/autofix", inventoryHandlers.OrphansAutofix)
	router.GET("/stocks/smart-setup/audit", inventoryHandlers.GetStockSetupAudit)

	// Stock Setup Approval (manager/admin review of salesman submissions)
	router.GET("/stocks/smart-setup/records", inventoryHandlers.ListStockSetupRecords)
	// v1.0.203 — pending-record count for the admin sidebar badge. Cheap
	// COUNT query, polled every ~60s by the web admin layout.
	router.GET("/stocks/smart-setup/pending-count", inventoryHandlers.GetStockSetupPendingCount)
	router.GET("/stocks/smart-setup/records/:id", inventoryHandlers.GetStockSetupRecordByID)
	router.PATCH("/stocks/smart-setup/records/:id", inventoryHandlers.UpdateStockSetupRecord)
	router.POST("/stocks/smart-setup/records/:id/auto-fix-brand-links", inventoryHandlers.AutoFixBrandLinks)
	router.POST("/stocks/smart-setup/records/:id/approve", inventoryHandlers.ApproveStockSetup)
	router.POST("/stocks/smart-setup/records/:id/reject", inventoryHandlers.RejectStockSetup)
	// v1.0.253 — Product photo+MRP change-request approval. Non-admin/manager
	// MRP edits land here as pending; admin/manager approve/reject (mirrors
	// the Stock Setup approval routes above). pending-count before :id.
	router.GET("/product-change-requests", inventoryHandlers.ListProductChangeRequests)
	router.GET("/product-change-requests/pending-count", inventoryHandlers.GetProductChangePendingCount)
	// v1.0.344 — combined photo/name/MRP requests grouped by capture batch
	// (one batch = one reviewable request: bulk + per-item approve/reject).
	// Static "batches" registered before "/:id" so it isn't captured as an id.
	router.GET("/product-change-requests/batches", inventoryHandlers.ListPhotoChangeBatches)
	router.POST("/product-change-requests/batches/:batchId/approve", inventoryHandlers.ApproveBatch)
	router.POST("/product-change-requests/batches/:batchId/reject", inventoryHandlers.RejectBatch)
	router.GET("/product-change-requests/:id", inventoryHandlers.GetProductChangeRequest)
	router.POST("/product-change-requests/:id/approve", inventoryHandlers.ApproveProductChange)
	router.POST("/product-change-requests/:id/reject", inventoryHandlers.RejectProductChange)
	router.POST("/product-change-requests/:id/revert", inventoryHandlers.RevertProductChange)
	// v1.0.133 — within-7-days reapply. Snaps current stock back to the
	// approved baseline for shops that want to undo sales/receipts without
	// redoing the AI Stock Setup. Returns 410 Gone past 7 days.
	router.POST("/stocks/smart-setup/records/:id/reapply", inventoryHandlers.ReapplyStockSetup)
	// 2026-05-19 — reversible snapshot-replace. replace-preview is a read-only
	// dry-run of what an approval would deactivate; restore-replace fully
	// reverses a record's deactivations + restores still-zeroed stock.
	router.GET("/stocks/smart-setup/records/:id/replace-preview", inventoryHandlers.PreviewStockSetupReplace)
	router.POST("/stocks/smart-setup/records/:id/restore-replace", inventoryHandlers.RestoreStockSetupReplace)

	// v1.0.133-r8 — alias hygiene admin endpoints. Operator-only surface to
	// inspect + retire dirty entries in ocr_brand_aliases. Closes the gap
	// where wrong canonical picks (e.g. `100 strokes royal → Royal Challenge
	// Select Premium`) silently mis-routed every future extraction.
	if aliasHygieneHandler != nil {
		aliasGroup := router.Group("/aliases", middleware.RoleMiddleware("manager", "admin", "owner"))
		aliasGroup.GET("/conflicts", aliasHygieneHandler.ListConflicts)
		aliasGroup.GET("/low-confidence", aliasHygieneHandler.ListLowConfidence)
		aliasGroup.GET("/stale", aliasHygieneHandler.ListStale)
		aliasGroup.POST("/:id/retire", aliasHygieneHandler.RetireAlias)
		aliasGroup.POST("/merge", aliasHygieneHandler.MergeCluster)
	}

	// Phase E — opt-in, audited product-duplicate consolidation. Manager+
	// only. Dry-run preview + atomic commit; never automatic. Backs the
	// Inventory "⧉ N" badge → Options popup "Merge duplicates" action.
	if productMergeHandler != nil {
		router.POST("/product-merge",
			middleware.RoleMiddleware("manager", "admin", "owner"),
			productMergeHandler.MergeProducts)
	}

	// v1.0.133-r8 — missing-SKU sweep. Walks recent extraction history,
	// surfaces top OCR texts that came back as `not_found` ranked by
	// occurrence × shop count. Operator one-clicks to add to master catalog.
	if missingSkuHandler != nil {
		skuGroup := router.Group("/missing-skus", middleware.RoleMiddleware("manager", "admin", "owner"))
		skuGroup.GET("", missingSkuHandler.List)
	}

	// Stock adjustment by brand name and size (for OCR flows)
	router.POST("/api/inventory/stock/adjustment", inventoryHandlers.UpdateStockByBrand)

	// Purchase Routes
	router.GET("/purchases", inventoryHandlers.GetPurchases)
	router.GET("/purchases/summary", inventoryHandlers.GetPurchasesSummary)
	router.POST("/purchases", inventoryHandlers.CreatePurchase)
	router.GET("/purchases/:id", inventoryHandlers.GetPurchaseByID)
	router.GET("/purchases/:id/print", inventoryHandlers.PrintPurchaseRegister)
	router.POST("/purchases/:id/receive", inventoryHandlers.ReceivePurchase)

	// Smart Purchase (AI-powered extraction from vendor invoice images)
	router.POST("/purchases/smart-purchase/extract", inventoryHandlers.ProcessSmartPurchase)

	// Smart Purchase async job queue (v1.0.188). Submit returns 202 +
	// {job_id}; client polls GET /jobs/:id until status terminal. Replaces
	// the synchronous /extract path on the Flutter side because nginx kills
	// the gateway connection at 60s while Gemini takes 50-60s on each of 6+
	// images. Worker has its own per-job timeout (8 min) so a slow run no
	// longer pins a request thread.
	if smartPurchaseJobHandlers != nil {
		router.POST("/purchases/smart-purchase/jobs", smartPurchaseJobHandlers.SubmitJob)
		router.GET("/purchases/smart-purchase/jobs", smartPurchaseJobHandlers.ListJobs)
		router.GET("/purchases/smart-purchase/jobs/:id", smartPurchaseJobHandlers.GetJob)
		router.GET("/purchases/smart-purchase/parcha-order", smartPurchaseJobHandlers.GetParchaOrder)
		router.DELETE("/purchases/smart-purchase/jobs/:id", smartPurchaseJobHandlers.CancelJob)
		// v1.0.238 Track E — Excel "photocopy" of the GP rows for the operator's records.
		router.GET("/purchases/smart-purchase/jobs/:id/export-gp.xlsx", smartPurchaseJobHandlers.ExportGPXLSX)
	}

	// v1.0.193 — vendor auto-create from review screen. Operator taps
	// "Create vendor" when extraction's detected_vendor wasn't in the
	// existing vendor list. Idempotent — re-tap returns matched_existing.
	if smartPurchaseVendorHandler != nil {
		// v1.0.348 — include executive + assistant_manager. AI Purchase is
		// operated end-to-end by executive users (every smart_purchase job is
		// submitted by one), and /apply + /disambig already trust those roles.
		// Excluding them here only on vendor/onboard meant the operator hit
		// "insufficient permission" mid-flow (create vendor / Add Missing Item).
		router.POST("/purchases/smart-purchase/vendor",
			middleware.RoleMiddleware("manager", "admin", "owner", "executive", "assistant_manager"),
			smartPurchaseVendorHandler.CreateOrMatchVendor)
	}

	// v1.0.193 — apply endpoint that wraps stock-purchase create + the
	// 4-signal learning loop (alias / negative-alias / shop rate / digit
	// corrections). Distinct from /purchases POST which is pre-AI legacy.
	if smartPurchaseApplyHandler != nil {
		router.POST("/purchases/smart-purchase/apply",
			middleware.RoleMiddleware("manager", "admin", "owner", "executive", "assistant_manager"),
			smartPurchaseApplyHandler.Apply)
	}

	// v1.0.238 — brand-photo route REMOVED. Purcha photo flow is gone;
	// AI Purchase relies on Bill+GP reconciliation instead. The handler
	// parameter stays in this function's signature for ABI stability with
	// main.go's call site, but it's no longer wired to a route.
	_ = smartPurchaseBrandPhotoHandler

	// v1.0.193 — onboarding tiers 3 + 4. Tier 3 wires a shop product to an
	// existing master saas_brand (auto-fills MRP / size / category). Tier 4
	// is full-form for genuinely new brands. Both are idempotent on
	// (tenant, shop, name, size).
	if smartPurchaseOnboardHandler != nil {
		// v1.0.348 — executive + assistant_manager added (see vendor note). The
		// v353 "Add Missing Item → create new product" flow calls onboard-new;
		// without these roles the executive operator was blocked with 403.
		router.POST("/purchases/smart-purchase/onboard-from-master",
			middleware.RoleMiddleware("manager", "admin", "owner", "executive", "assistant_manager"),
			smartPurchaseOnboardHandler.OnboardFromMaster)
		router.POST("/purchases/smart-purchase/onboard-new",
			middleware.RoleMiddleware("manager", "admin", "owner", "executive", "assistant_manager"),
			smartPurchaseOnboardHandler.OnboardNew)
	}

	// v1.0.222 — past-purchase disambiguation. Operator uploads a previous
	// purchase bill to resolve Row-23-class variant ambiguity (same brand
	// root, different flavour suffixes among tenant products). Result is
	// returned to Flutter to patch the row's product pick + alias learned
	// shop-scoped so next bill resolves silently.
	if smartPurchaseDisambigHandler != nil {
		router.POST("/purchases/smart-purchase/disambig",
			middleware.RoleMiddleware("manager", "admin", "owner", "executive", "assistant_manager"),
			smartPurchaseDisambigHandler.Resolve)
		// v1.0.223 — batch variant: one image, many rows resolved per size.
		router.POST("/purchases/smart-purchase/disambig-batch",
			middleware.RoleMiddleware("manager", "admin", "owner", "executive", "assistant_manager"),
			smartPurchaseDisambigHandler.ResolveBatch)
	}

	// v1.0.193 W4.1 — replay-matcher diagnostic endpoint. Re-runs the matcher
	// against a persisted SmartPurchaseResult with current alias / shop-rate /
	// shop-bias state and returns diff counts. Read-only; admin-only. Useful
	// for validating "did the corrections we taught actually move the needle?".
	if smartPurchaseReplayHandler != nil {
		router.POST("/purchases/smart-purchase/replay/:job_id",
			middleware.RoleMiddleware("manager", "admin", "owner"),
			smartPurchaseReplayHandler.Replay)
	}

	// Purchase image upload (for manual purchase flow)
	router.POST("/purchases/upload-images", inventoryHandlers.UploadPurchaseImages)

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
	router.GET("/api/inventory/saas-brands/categories", inventoryHandlers.GetBrandCategories)
	router.GET("/api/inventory/saas-brands/subcategories", inventoryHandlers.GetSubcategoriesByCategory)
	router.GET("/api/inventory/saas-brands/metadata", inventoryHandlers.GetBrandMetadata)
	router.GET("/api/inventory/saas-brands/paginated", inventoryHandlers.GetBrandsByCategory)
	router.POST("/api/inventory/saas-brands/onboard", inventoryHandlers.OnboardBrands)
	router.GET("/api/inventory/saas-brands/onboarded", inventoryHandlers.GetOnboardedBrands)
	router.PUT("/api/inventory/saas-brands/onboarded/:id", inventoryHandlers.UpdateOnboardedBrand)
	router.GET("/api/inventory/brands/custom", inventoryHandlers.GetCustomBrands)
	router.POST("/api/inventory/brands/custom", inventoryHandlers.CreateBrandWithVariants)

	// Brand Edit Support - Proxy to SaaS service for editing
	router.GET("/api/inventory/brand-categories", inventoryHandlers.GetSaaSBrandCategories)
	router.GET("/api/inventory/brand-subcategories", inventoryHandlers.GetSaaSBrandSubcategories)
	router.GET("/api/inventory/category-sizes", inventoryHandlers.GetSaaSCategorySizes)

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

	// Bulk Import Routes (Excel/CSV/Image import with smart matching)
	router.GET("/api/inventory/import/template", inventoryHandlers.DownloadImportTemplate)
	router.POST("/api/inventory/import/upload", inventoryHandlers.UploadAndValidateImport)
	router.POST("/api/inventory/import/confirm", inventoryHandlers.ConfirmImport)
	router.GET("/api/inventory/import/history", inventoryHandlers.GetImportHistory)
	router.GET("/api/inventory/import/:import_id/status", inventoryHandlers.GetImportStatus)
	router.POST("/api/inventory/import/:import_id/cancel", inventoryHandlers.CancelImport)

	// OCR Auto-onboarding Routes
	router.POST("/api/inventory/ocr/auto-onboard", inventoryHandlers.AutoOnboardFromOCR)
	router.GET("/api/inventory/ocr/:session_id/summary", inventoryHandlers.GetOCROnboardingSummary)

	// Reports Routes
	router.GET("/reports/low-stock", inventoryHandlers.GetStocks)
	router.GET("/reports/stock-movements", inventoryHandlers.GetStockMovements)

	// Purchase Report (called as /api/reports/purcha/preview from gateway)
	router.GET("/api/reports/purcha/preview", inventoryHandlers.GetPurchaReportPreview)
}
