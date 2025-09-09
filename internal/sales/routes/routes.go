package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/sales/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all sales service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, salesHandlers *handlers.SalesHandlers) {
	// Health check
	router.GET("/health", salesHandlers.Health)

	// All routes require authentication and tenant isolation
	api := router.Group("/api")
	api.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	api.Use(middleware.TenantMiddleware())

	// Daily Sales Routes (Critical for bulk entry workflow)
	dailySales := api.Group("/daily-records")
	{
		dailySales.GET("", salesHandlers.GetDailySalesRecords)
		dailySales.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CreateDailySalesRecord)
		dailySales.GET("/:id", salesHandlers.GetDailySalesRecordByID)
		dailySales.PUT("/:id", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.UpdateDailySalesRecord)
		dailySales.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ApproveDailySalesRecord)
		dailySales.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), salesHandlers.RejectDailySalesRecord)
	}

	// Individual Sales Routes
	sales := api.Group("/sales")
	{
		sales.GET("", salesHandlers.GetSales)
		sales.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), salesHandlers.CreateSale)
		sales.GET("/:id", salesHandlers.GetSaleByID)
		sales.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), salesHandlers.ApproveSale)
		sales.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), salesHandlers.RejectSale)
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

	// OCR and Image Processing Routes (Placeholder for future implementation)
	ocr := api.Group("/ocr")
	ocr.Use(middleware.RoleMiddleware("salesman", "manager", "admin"))
	{
		// TODO: Implement OCR endpoints
		ocr.POST("/upload", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR upload not implemented yet"})
		})
		ocr.POST("/process", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR processing not implemented yet"})
		})
		ocr.GET("/images/:id", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR image retrieval not implemented yet"})
		})
		ocr.GET("/images", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR image listing not implemented yet"})
		})
		ocr.POST("/extract-dynamic", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Dynamic OCR extraction not implemented yet"})
		})
		ocr.POST("/extraction/edit", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR extraction editing not implemented yet"})
		})
		ocr.POST("/extraction/finalize", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR extraction finalization not implemented yet"})
		})
		ocr.GET("/extraction/status/:id", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "OCR extraction status not implemented yet"})
		})
	}
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, salesHandlers *handlers.SalesHandlers) {
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
	router.POST("/daily-records/:id/approve", salesHandlers.ApproveDailySalesRecord)
	router.POST("/daily-records/:id/reject", salesHandlers.RejectDailySalesRecord)

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

	// OCR Placeholder Routes
	router.POST("/ocr/upload", func(c *gin.Context) {
		c.JSON(501, gin.H{"message": "OCR upload not implemented yet"})
	})
	router.POST("/ocr/process", func(c *gin.Context) {
		c.JSON(501, gin.H{"message": "OCR processing not implemented yet"})
	})
}