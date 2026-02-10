package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/sales/handlers"
	"github.com/liquorpro/go-backend/pkg/monitoring"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/logger"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all sales service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, salesHandlers *handlers.SalesHandlers, ocrHandlers *handlers.OCRHandlers, draftHandlers *handlers.DraftHandlers, purchaReportHandler *handlers.PurchaReportHandler, trainingHandlers *handlers.TrainingHandlers, aiTrainingHandlers *handlers.AITrainingHandlers) {
	// Prometheus metrics
	router.Use(monitoring.PrometheusMiddleware("sales"))
	router.GET("/metrics", monitoring.PrometheusHandler())

	// Health check
	router.GET("/health", salesHandlers.Health)

	// WebSocket endpoint for real-time updates (handles auth via query params)
	router.GET("/ws", handlers.HandleWebSocket(logger.Logger, cfg.JWT.Secret))

	// All routes require authentication and tenant isolation
	api := router.Group("/api")
	api.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	api.Use(middleware.TenantMiddleware())

	// Daily Sales Routes (Critical for bulk entry workflow)
	dailySales := api.Group("/daily-records")
	{
		dailySales.GET("", salesHandlers.GetDailySalesRecords)
		dailySales.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CreateDailySalesRecord)
		dailySales.GET("/exists", salesHandlers.CheckDailySalesRecordExists) // Check record existence (SINGLE SOURCE OF TRUTH for drafts)
		dailySales.GET("/:id", salesHandlers.GetDailySalesRecordByID)
		dailySales.PUT("/:id", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.UpdateDailySalesRecord)
		dailySales.PATCH("/:id/change-date", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.ChangeDailySalesRecordDate) // Change date only
		dailySales.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ApproveDailySalesRecord)
		dailySales.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), salesHandlers.RejectDailySalesRecord)
		dailySales.POST("/:id/copy", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CopyDailySalesRecord) // Copy for rejected record recovery
		dailySales.POST("/upload-image", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.UploadDailySalesImages)

		// AI Validation endpoints
		dailySales.GET("/:id/validation", salesHandlers.GetValidation)
		dailySales.POST("/:id/validation/trigger", middleware.RoleMiddleware("manager", "admin"), salesHandlers.TriggerValidation)
		dailySales.POST("/:id/validation/confirm", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ConfirmValidation)
	}

	// Validation accuracy dashboard (global endpoint)
	api.GET("/sales/validation/accuracy", middleware.RoleMiddleware("manager", "admin"), salesHandlers.GetAccuracyDashboard)

	// Industrial-grade Learning & Analytics endpoints
	learning := api.Group("/sales/learning")
	{
		learning.GET("/stats", middleware.RoleMiddleware("manager", "admin"), salesHandlers.GetLearningStats)
		learning.GET("/accuracy-trend", middleware.RoleMiddleware("manager", "admin"), salesHandlers.GetAccuracyTrend)
		learning.POST("/batch-process", middleware.RoleMiddleware("admin"), salesHandlers.TriggerBatchLearning)
	}

	// Alias: daily-sales routes (for Flutter app compatibility)
	dailySalesAlias := api.Group("/daily-sales")
	{
		dailySalesAlias.GET("", salesHandlers.GetDailySalesRecords)
		dailySalesAlias.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CreateDailySalesRecord)
		dailySalesAlias.GET("/exists", salesHandlers.CheckDailySalesRecordExists) // Check record existence (SINGLE SOURCE OF TRUTH for drafts)
		dailySalesAlias.GET("/:id", salesHandlers.GetDailySalesRecordByID)
		dailySalesAlias.PUT("/:id", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.UpdateDailySalesRecord)
		dailySalesAlias.PATCH("/:id/change-date", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.ChangeDailySalesRecordDate) // Change date only
		dailySalesAlias.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ApproveDailySalesRecord)
		dailySalesAlias.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), salesHandlers.RejectDailySalesRecord)
		dailySalesAlias.POST("/:id/copy", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CopyDailySalesRecord) // Copy for rejected record recovery
		dailySalesAlias.POST("/upload-image", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.UploadDailySalesImages)

		// AI Validation endpoints (alias)
		dailySalesAlias.GET("/:id/validation", salesHandlers.GetValidation)
		dailySalesAlias.POST("/:id/validation/trigger", middleware.RoleMiddleware("manager", "admin"), salesHandlers.TriggerValidation)
		dailySalesAlias.POST("/:id/validation/confirm", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ConfirmValidation)

		// Daily Sales Revert with dual OTP verification (admin/owner only)
		dailySalesAlias.POST("/:id/revert/request-otp", middleware.RoleMiddleware("admin", "owner"), salesHandlers.RequestDailySalesRevertOTP)
		dailySalesAlias.POST("/:id/revert", middleware.RoleMiddleware("admin", "owner"), salesHandlers.RevertDailySalesRecordWithOTP)

		// Draft persistence endpoints (backend-based, replaces Hive local storage)
		if draftHandlers != nil {
			dailySalesAlias.GET("/draft", middleware.RoleMiddleware("salesman", "manager", "admin"), draftHandlers.GetDraft)
			dailySalesAlias.POST("/draft", middleware.RoleMiddleware("salesman", "manager", "admin"), draftHandlers.SaveDraft)
			dailySalesAlias.DELETE("/draft", middleware.RoleMiddleware("salesman", "manager", "admin"), draftHandlers.DiscardDraft)
			dailySalesAlias.POST("/draft/submit", middleware.RoleMiddleware("salesman", "manager", "admin"), draftHandlers.SubmitDraft)
			dailySalesAlias.GET("/drafts", middleware.RoleMiddleware("salesman", "manager", "admin"), draftHandlers.GetUserDrafts)
		}
	}

	// Individual Sales Routes
	sales := api.Group("/sales")
	{
		sales.GET("", salesHandlers.GetSales)
		sales.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CreateSale)
		sales.GET("/:id", salesHandlers.GetSaleByID)
		sales.PUT("/:id", middleware.RoleMiddleware("salesman", "manager", "assistant_manager", "admin"), salesHandlers.UpdateSale)
		sales.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ApproveSale)
		sales.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), salesHandlers.RejectSale)
		// Sale Revert with dual OTP verification (admin/owner only)
		sales.POST("/:id/revert/request-otp", middleware.RoleMiddleware("admin", "owner"), salesHandlers.RequestRevertOTP)
		sales.POST("/:id/revert", middleware.RoleMiddleware("admin", "owner"), salesHandlers.RevertSaleWithOTP)
	}

	// Sale Returns Routes
	returns := api.Group("/returns")
	{
		returns.GET("", salesHandlers.GetSaleReturns)
		returns.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CreateSaleReturn)
		returns.GET("/:id", salesHandlers.GetSaleReturnByID)
		returns.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ApproveSaleReturn)
		returns.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), salesHandlers.RejectSaleReturn)
	}

	// Pending Items (for approval workflows)
	pending := api.Group("/pending")
	{
		pending.GET("/sales", middleware.RoleMiddleware("manager", "admin"), salesHandlers.GetPendingSales)
		pending.GET("/returns", middleware.RoleMiddleware("manager", "admin"), salesHandlers.GetPendingReturns)
	}

	// Financial Reports
	financial := api.Group("/financial")
	{
		financial.GET("/uncollected", middleware.RoleMiddleware("executive", "manager", "admin"), salesHandlers.GetUncollectedSales)
	}

	// Dashboard and Summary Routes
	dashboard := api.Group("/dashboard")
	{
		dashboard.GET("/summary", salesHandlers.GetDashboardSummary)
	}

	// Purcha Report Routes (Daily Sales Register)
	if purchaReportHandler != nil {
		reports := api.Group("/reports")
		{
			reports.GET("/purcha/preview", purchaReportHandler.GetPurchaReportPreview)
			reports.GET("/purcha/pdf", purchaReportHandler.GetPurchaReportPDF)
		}
	}

	// OCR and Image Processing Routes with Gemini AI Integration
	if ocrHandlers != nil {
		ocr := api.Group("/ocr")
		ocr.Use(middleware.RoleMiddleware("owner", "saas_admin", "salesman", "manager", "admin"))
		{
			// Batch OCR Processing
			ocr.POST("/batch/sessions", ocrHandlers.CreateBatchSession)
			ocr.GET("/batch/sessions/:id", ocrHandlers.GetBatchSession)
			ocr.POST("/batch/deduplicate", ocrHandlers.DeduplicateItems)
			ocr.POST("/batch/import", ocrHandlers.ImportReviewedItems)

			// Brand Matching with Gemini AI
			ocr.POST("/brands/match", ocrHandlers.FindBrandMatches)
			ocr.POST("/brands/create", ocrHandlers.AutoCreateBrand)

			// Metrics endpoints
			ocr.GET("/metrics", ocrHandlers.GetOCRMetrics)
			ocr.POST("/metrics/reset", ocrHandlers.ResetOCRMetrics)

			// Phase 5: Comprehensive Validation Endpoints
			ocr.POST("/batch/validate/:id", ocrHandlers.ValidateBatchSession)
			ocr.POST("/batch/validate-row", ocrHandlers.ValidateRow)
			ocr.POST("/batch/validate-comprehensive/:id", ocrHandlers.ValidateBatchComprehensive)
			ocr.GET("/accuracy/dashboard", ocrHandlers.GetAccuracyDashboard)
		}
	}

	// Smart Sale Routes (AI-assisted sale creation from images)
	// - POST /process → ProcessSmartSaleV2 (GPT-5.2, DEFAULT)
	// - POST /v2/process → ProcessSmartSaleV2 (explicit V2)
	// - POST /v1/process → ProcessSmartSale (legacy, Vision API - DEPRECATED)
	smartSale := api.Group("/smart-sale")
	smartSale.Use(middleware.RoleMiddleware("owner", "saas_admin", "salesman", "manager", "admin"))
	{
		if ocrHandlers != nil {
			smartSale.POST("/process", ocrHandlers.ProcessSmartSaleV2)      // Default: GPT-5.2
			smartSale.POST("/v2/process", ocrHandlers.ProcessSmartSaleV2)   // Explicit V2
			smartSale.POST("/v1/process", ocrHandlers.ProcessSmartSale)     // Legacy (deprecated)
		}
		smartSale.POST("/finalize", salesHandlers.FinalizeSmartSale)
	}

	// AI Training Data Routes - for preparing ground truth training data
	if trainingHandlers != nil {
		training := api.Group("/training")
		training.Use(middleware.RoleMiddleware("owner", "saas_admin", "manager", "admin"))
		{
			// V1 endpoints (backward compatibility)
			training.GET("/images", trainingHandlers.GetTrainingImages)
			training.GET("/images/export", trainingHandlers.ExportTrainingData)
			training.GET("/images/:filename", trainingHandlers.GetImageSaleData)
			training.GET("/debug/records", trainingHandlers.GetRecordsWithImages)

			// V2 endpoints - Size-based training images
			training.GET("/images/v2", trainingHandlers.GetTrainingImagesV2)
			training.GET("/images/export-v2", trainingHandlers.ExportTrainingDataV2)
			training.POST("/images/process/:filename", trainingHandlers.ProcessImage)
			training.POST("/images/process-all", trainingHandlers.ProcessAllImages)
			training.POST("/images/detect-size/:filename", trainingHandlers.DetectImageSize)

			// Size mappings
			training.GET("/mappings/:record_id", trainingHandlers.GetSizeMappings)
			training.POST("/mappings/:id/verify", trainingHandlers.VerifySizeMapping)

			// Size-filtered items
			training.GET("/items/:record_id/:size", trainingHandlers.GetSizeFilteredItems)
		}
	}

	// AI Training V2 Routes - Generic document training (any logged-in user)
	if aiTrainingHandlers != nil {
		aiTraining := api.Group("/ai-training")
		// Any logged-in user can access (already authenticated via api group middleware)
		{
			aiTraining.POST("/upload", aiTrainingHandlers.Upload)
			aiTraining.GET("/images", aiTrainingHandlers.ListImages)
			aiTraining.GET("/images/:id", aiTrainingHandlers.GetImage)
			aiTraining.PUT("/images/:id/verify", aiTrainingHandlers.VerifyImage)
			aiTraining.DELETE("/images/:id", aiTrainingHandlers.DeleteImage)
			aiTraining.GET("/export", aiTrainingHandlers.ExportTraining)
		}
	}

	// Gateway-compatible routes (without /api prefix for proxy forwarding)
	// These routes are needed when requests come through the Gateway proxy
	router.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	router.Use(middleware.TenantMiddleware())

	router.GET("/daily-records", salesHandlers.GetDailySalesRecords)
	router.POST("/daily-records", salesHandlers.CreateDailySalesRecord)
	router.GET("/daily-records/exists", salesHandlers.CheckDailySalesRecordExists) // Check record existence
	router.GET("/daily-records/:id", salesHandlers.GetDailySalesRecordByID)
	router.PUT("/daily-records/:id", salesHandlers.UpdateDailySalesRecord)
	router.PATCH("/daily-records/:id/change-date", salesHandlers.ChangeDailySalesRecordDate) // Change date only
	router.POST("/daily-records/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-records/:id/reject", salesHandlers.RejectDailySalesRecord)
	router.POST("/daily-records/:id/copy", salesHandlers.CopyDailySalesRecord) // Copy for rejected record recovery
	router.POST("/daily-records/upload-image", salesHandlers.UploadDailySalesImages)

	// Alias: daily-sales routes (for Flutter app compatibility)
	router.GET("/daily-sales", salesHandlers.GetDailySalesRecords)
	router.POST("/daily-sales", salesHandlers.CreateDailySalesRecord)
	router.GET("/daily-sales/exists", salesHandlers.CheckDailySalesRecordExists) // Check record existence
	router.GET("/daily-sales/:id", salesHandlers.GetDailySalesRecordByID)
	router.PUT("/daily-sales/:id", salesHandlers.UpdateDailySalesRecord)
	router.PATCH("/daily-sales/:id/change-date", salesHandlers.ChangeDailySalesRecordDate) // Change date only
	router.POST("/daily-sales/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-sales/:id/reject", salesHandlers.RejectDailySalesRecord)
	router.POST("/daily-sales/:id/copy", salesHandlers.CopyDailySalesRecord) // Copy for rejected record recovery
	router.POST("/daily-sales/upload-image", salesHandlers.UploadDailySalesImages)
	// Daily Sales Revert with dual OTP verification (gateway-compatible)
	router.POST("/daily-sales/:id/revert/request-otp", salesHandlers.RequestDailySalesRevertOTP)
	router.POST("/daily-sales/:id/revert", salesHandlers.RevertDailySalesRecordWithOTP)

	// Draft persistence routes (gateway-compatible)
	if draftHandlers != nil {
		router.GET("/daily-sales/draft", draftHandlers.GetDraft)
		router.POST("/daily-sales/draft", draftHandlers.SaveDraft)
		router.DELETE("/daily-sales/draft", draftHandlers.DiscardDraft)
		router.POST("/daily-sales/draft/submit", draftHandlers.SubmitDraft)
		router.GET("/daily-sales/drafts", draftHandlers.GetUserDrafts)
	}

	router.GET("/sales", salesHandlers.GetSales)
	router.POST("/sales", salesHandlers.CreateSale)
	router.GET("/sales/:id", salesHandlers.GetSaleByID)
	router.POST("/sales/:id/approve", salesHandlers.ApproveSale)
	router.POST("/sales/:id/reject", salesHandlers.RejectSale)

	router.GET("/returns", salesHandlers.GetSaleReturns)
	router.POST("/returns", salesHandlers.CreateSaleReturn)
	router.GET("/returns/:id", salesHandlers.GetSaleReturnByID)
	router.POST("/returns/:id/approve", salesHandlers.ApproveSaleReturn)
	router.POST("/returns/:id/reject", salesHandlers.RejectSaleReturn)

	router.GET("/pending/sales", salesHandlers.GetPendingSales)
	router.GET("/pending/returns", salesHandlers.GetPendingReturns)
	router.GET("/uncollected", salesHandlers.GetUncollectedSales)
	router.GET("/dashboard/summary", salesHandlers.GetDashboardSummary)

	// OCR Routes (gateway-compatible, without /api prefix)
	if ocrHandlers != nil {
		ocrGroup := router.Group("/ocr")
		ocrGroup.Use(middleware.RoleMiddleware("owner", "saas_admin", "salesman", "manager", "admin"))
		{
			// Batch OCR Processing
			ocrGroup.POST("/batch/sessions", ocrHandlers.CreateBatchSession)
			ocrGroup.GET("/batch/sessions/:id", ocrHandlers.GetBatchSession)
			ocrGroup.POST("/batch/deduplicate", ocrHandlers.DeduplicateItems)
			ocrGroup.POST("/batch/import", ocrHandlers.ImportReviewedItems)

			// Brand Matching with Gemini AI
			ocrGroup.POST("/brands/match", ocrHandlers.FindBrandMatches)
			ocrGroup.POST("/brands/create", ocrHandlers.AutoCreateBrand)

			// Metrics endpoints
			ocrGroup.GET("/metrics", ocrHandlers.GetOCRMetrics)
			ocrGroup.POST("/metrics/reset", ocrHandlers.ResetOCRMetrics)

			// Phase 5: Comprehensive Validation Endpoints
			ocrGroup.POST("/batch/validate/:id", ocrHandlers.ValidateBatchSession)
			ocrGroup.POST("/batch/validate-row", ocrHandlers.ValidateRow)
			ocrGroup.POST("/batch/validate-comprehensive/:id", ocrHandlers.ValidateBatchComprehensive)
			ocrGroup.GET("/accuracy/dashboard", ocrHandlers.GetAccuracyDashboard)
		}
	}
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, salesHandlers *handlers.SalesHandlers, ocrHandlers *handlers.OCRHandlers, draftHandlers *handlers.DraftHandlers, purchaReportHandler *handlers.PurchaReportHandler, trainingHandlers *handlers.TrainingHandlers, aiTrainingHandlers *handlers.AITrainingHandlers) {
	// Prometheus metrics
	router.Use(monitoring.PrometheusMiddleware("sales"))
	router.GET("/metrics", monitoring.PrometheusHandler())

	// Health check (no auth required)
	router.GET("/health", salesHandlers.Health)

	// Debug endpoint for database diagnostics (temporary)
	router.GET("/debug/database", salesHandlers.DebugDatabase)

	// WebSocket endpoint for real-time updates (handles auth via query params)
	router.GET("/ws", handlers.HandleWebSocket(logger.Logger, cfg.JWT.Secret))

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
	router.GET("/daily-records/exists", salesHandlers.CheckDailySalesRecordExists) // Check record existence
	router.GET("/daily-records/:id", salesHandlers.GetDailySalesRecordByID)
	router.PUT("/daily-records/:id", salesHandlers.UpdateDailySalesRecord)
	router.PATCH("/daily-records/:id/change-date", salesHandlers.ChangeDailySalesRecordDate) // Change date only
	router.POST("/daily-records/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-records/:id/reject", salesHandlers.RejectDailySalesRecord)
	router.POST("/daily-records/:id/copy", salesHandlers.CopyDailySalesRecord) // Copy for rejected record recovery
	router.POST("/daily-records/upload-image", salesHandlers.UploadDailySalesImages)
	// AI Validation endpoints (daily-records)
	router.GET("/daily-records/:id/validation", salesHandlers.GetValidation)
	router.POST("/daily-records/:id/validation/trigger", salesHandlers.TriggerValidation)
	router.POST("/daily-records/:id/validation/confirm", salesHandlers.ConfirmValidation)

	// Alias: daily-sales routes (for Flutter app compatibility)
	router.GET("/daily-sales", salesHandlers.GetDailySalesRecords)
	router.POST("/daily-sales", salesHandlers.CreateDailySalesRecord)
	router.GET("/daily-sales/exists", salesHandlers.CheckDailySalesRecordExists) // Check record existence
	router.GET("/daily-sales/:id", salesHandlers.GetDailySalesRecordByID)
	router.PUT("/daily-sales/:id", salesHandlers.UpdateDailySalesRecord)
	router.PATCH("/daily-sales/:id/change-date", salesHandlers.ChangeDailySalesRecordDate) // Change date only
	router.POST("/daily-sales/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-sales/:id/reject", salesHandlers.RejectDailySalesRecord)
	router.POST("/daily-sales/:id/copy", salesHandlers.CopyDailySalesRecord) // Copy for rejected record recovery
	router.POST("/daily-sales/upload-image", salesHandlers.UploadDailySalesImages)
	// AI Validation endpoints (daily-sales alias)
	router.GET("/daily-sales/:id/validation", salesHandlers.GetValidation)
	router.POST("/daily-sales/:id/validation/trigger", salesHandlers.TriggerValidation)
	router.POST("/daily-sales/:id/validation/confirm", salesHandlers.ConfirmValidation)
	// Daily Sales Revert with dual OTP verification (protected routes)
	router.POST("/daily-sales/:id/revert/request-otp", salesHandlers.RequestDailySalesRevertOTP)
	router.POST("/daily-sales/:id/revert", salesHandlers.RevertDailySalesRecordWithOTP)

	// Draft persistence routes (protected, for Flutter app)
	if draftHandlers != nil {
		router.GET("/daily-sales/draft", draftHandlers.GetDraft)
		router.POST("/daily-sales/draft", draftHandlers.SaveDraft)
		router.DELETE("/daily-sales/draft", draftHandlers.DiscardDraft)
		router.POST("/daily-sales/draft/submit", draftHandlers.SubmitDraft)
		router.GET("/daily-sales/drafts", draftHandlers.GetUserDrafts)
	}

	// Validation accuracy dashboard
	router.GET("/sales/validation/accuracy", salesHandlers.GetAccuracyDashboard)

	// Industrial-grade Learning & Analytics endpoints (legacy routes)
	router.GET("/sales/learning/stats", salesHandlers.GetLearningStats)
	router.GET("/sales/learning/accuracy-trend", salesHandlers.GetAccuracyTrend)
	router.POST("/sales/learning/batch-process", salesHandlers.TriggerBatchLearning)

	// Individual Sales Routes
	router.GET("/sales", salesHandlers.GetSales)
	router.POST("/sales", salesHandlers.CreateSale)
	router.GET("/sales/:id", salesHandlers.GetSaleByID)
	router.PUT("/sales/:id", salesHandlers.UpdateSale)
	router.POST("/sales/:id/approve", salesHandlers.ApproveSale)
	router.POST("/sales/:id/reject", salesHandlers.RejectSale)
	// Sale Revert with dual OTP verification (admin/owner only)
	router.POST("/sales/:id/revert/request-otp", salesHandlers.RequestRevertOTP)
	router.POST("/sales/:id/revert", salesHandlers.RevertSaleWithOTP)

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

	// Purcha Report Routes (Daily Sales Register)
	if purchaReportHandler != nil {
		router.GET("/reports/purcha/preview", purchaReportHandler.GetPurchaReportPreview)
		router.GET("/reports/purcha/pdf", purchaReportHandler.GetPurchaReportPDF)
	}

	// OCR Routes (if OCR handlers are available)
	if ocrHandlers != nil {
		ocrGroup := router.Group("/ocr")
		ocrGroup.Use(middleware.RoleMiddleware("owner", "saas_admin", "salesman", "manager", "admin"))
		{
			// Batch OCR Processing
			ocrGroup.POST("/batch/sessions", ocrHandlers.CreateBatchSession)
			ocrGroup.GET("/batch/sessions/:id", ocrHandlers.GetBatchSession)
			ocrGroup.POST("/batch/deduplicate", ocrHandlers.DeduplicateItems)
			ocrGroup.POST("/batch/import", ocrHandlers.ImportReviewedItems)

			// Brand Matching with Gemini AI
			ocrGroup.POST("/brands/match", ocrHandlers.FindBrandMatches)
			ocrGroup.POST("/brands/create", ocrHandlers.AutoCreateBrand)

			// Metrics endpoints
			ocrGroup.GET("/metrics", ocrHandlers.GetOCRMetrics)
			ocrGroup.POST("/metrics/reset", ocrHandlers.ResetOCRMetrics)

			// Phase 5: Comprehensive Validation Endpoints
			ocrGroup.POST("/batch/validate/:id", ocrHandlers.ValidateBatchSession)
			ocrGroup.POST("/batch/validate-row", ocrHandlers.ValidateRow)
			ocrGroup.POST("/batch/validate-comprehensive/:id", ocrHandlers.ValidateBatchComprehensive)
			ocrGroup.GET("/accuracy/dashboard", ocrHandlers.GetAccuracyDashboard)
		}
	}

	// Smart Sale Routes (AI-assisted sale creation - gateway compatible)
	// All routes use GPT-5.2 by default. V1 is deprecated but kept for backward compatibility.
	// - POST /process → ProcessSmartSaleV2 (GPT-5.2, DEFAULT)
	// - POST /v2/process → ProcessSmartSaleV2 (explicit V2)
	// - POST /v1/process → ProcessSmartSale (legacy, Vision API - DEPRECATED)
	smartSaleGroup := router.Group("/smart-sale")
	smartSaleGroup.Use(middleware.RoleMiddleware("owner", "saas_admin", "salesman", "manager", "admin"))
	{
		if ocrHandlers != nil {
			smartSaleGroup.POST("/process", ocrHandlers.ProcessSmartSaleV2)      // Default: GPT-5.2
			smartSaleGroup.POST("/v2/process", ocrHandlers.ProcessSmartSaleV2)   // Explicit V2
			smartSaleGroup.POST("/v1/process", ocrHandlers.ProcessSmartSale)     // Legacy (deprecated)
		}
		smartSaleGroup.POST("/finalize", salesHandlers.FinalizeSmartSale)
	}

	// AI Training Data Routes (internal tool - no auth, secured at nginx level)
	// Uses /api/training path to match gateway proxy path
	if trainingHandlers != nil {
		trainingGroup := router.Group("/api/training")
		{
			// V1 endpoints (backward compatibility)
			trainingGroup.GET("/images", trainingHandlers.GetTrainingImages)
			trainingGroup.GET("/images/export", trainingHandlers.ExportTrainingData)
			trainingGroup.GET("/images/:filename", trainingHandlers.GetImageSaleData)
			trainingGroup.GET("/debug/records", trainingHandlers.GetRecordsWithImages)

			// V2 endpoints - Size-based training images
			trainingGroup.GET("/images/v2", trainingHandlers.GetTrainingImagesV2)
			trainingGroup.GET("/images/export-v2", trainingHandlers.ExportTrainingDataV2)
			trainingGroup.POST("/images/process/:filename", trainingHandlers.ProcessImage)
			trainingGroup.POST("/images/process-all", trainingHandlers.ProcessAllImages)
			trainingGroup.POST("/images/detect-size/:filename", trainingHandlers.DetectImageSize)

			// Size mappings
			trainingGroup.GET("/mappings/:record_id", trainingHandlers.GetSizeMappings)
			trainingGroup.POST("/mappings/:id/verify", trainingHandlers.VerifySizeMapping)

			// Size-filtered items
			trainingGroup.GET("/items/:record_id/:size", trainingHandlers.GetSizeFilteredItems)
		}
	}

	// AI Training V2 Routes - Generic document training (protected routes)
	if aiTrainingHandlers != nil {
		aiTrainingGroup := router.Group("/api/ai-training")
		{
			aiTrainingGroup.POST("/upload", aiTrainingHandlers.Upload)
			aiTrainingGroup.GET("/images", aiTrainingHandlers.ListImages)
			aiTrainingGroup.GET("/images/:id", aiTrainingHandlers.GetImage)
			aiTrainingGroup.PUT("/images/:id/verify", aiTrainingHandlers.VerifyImage)
			aiTrainingGroup.DELETE("/images/:id", aiTrainingHandlers.DeleteImage)
			aiTrainingGroup.GET("/export", aiTrainingHandlers.ExportTraining)
		}
	}
}
