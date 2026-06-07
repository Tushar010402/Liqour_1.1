package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/handlers"
	saasMiddleware "github.com/liquorpro/go-backend/internal/saas/middleware"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/logger"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatal("Failed to load configuration:", err)
	}

	// Initialize logger
	loggerConfig := logger.Config{
		Level:       "info",
		Environment: "development",
		ServiceName: "saas-admin",
	}
	if err := logger.Initialize(loggerConfig); err != nil {
		log.Fatal("Failed to initialize logger:", err)
	}
	defer logger.Sync()

	// Connect to database
	dbConfig := database.Config{
		Host:     cfg.Database.Host,
		Port:     cfg.Database.Port,
		User:     cfg.Database.User,
		Password: cfg.Database.Password,
		DBName:   cfg.Database.DBName,
		SSLMode:  cfg.Database.SSLMode,
		TimeZone: cfg.Database.TimeZone,
	}

	dbConn, err := database.NewDatabase(dbConfig)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	db := dbConn.DB

	// Initialize cache
	cacheConfig := cache.Config{
		Host:     cfg.Redis.Host,
		Port:     cfg.Redis.Port,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	}

	cacheClient, err := cache.NewCache(cacheConfig)
	if err != nil {
		log.Fatal("Failed to connect to cache:", err)
	}

	// Run migrations
	if err := runMigrations(db); err != nil {
		log.Fatal("Failed to run migrations:", err)
	}

	// Initialize services
	subscriptionService := services.NewSubscriptionService(db, cfg)
	planService := services.NewPlanService(db, cfg)
	paymentService := services.NewPaymentService(db, cfg)
	adminService := services.NewAdminService(db, cfg, cacheClient)
	analyticsService := services.NewAnalyticsService(db, cfg)
	discountService := services.NewDiscountService(db, cfg)
	usageTrackingService := services.NewUsageTrackingService(db, cacheClient, cfg)
	brandService := services.NewBrandService(db, cacheClient, cfg, logger.Logger)
	brandExcelService := services.NewBrandExcelService(db, logger.Logger)
	categorySizeService := services.NewCategorySizeService(db)
	unitService := services.NewUnitService(db)
	featureFlagService := services.NewFeatureFlagService(db)

	// Initialize billing service (assuming it exists)
	billingService := services.NewAutonomousBillingService(db, cfg, cacheClient)

	// Initialize plan transition service (depends on billing and usage services)
	planTransitionService := services.NewPlanTransitionService(db, cacheClient, cfg, billingService, usageTrackingService)

	// Initialize handlers
	subscriptionHandler := handlers.NewSubscriptionHandler(subscriptionService)
	planHandler := handlers.NewPlanHandler(planService)
	paymentHandler := handlers.NewPaymentHandler(paymentService)
	adminHandler := handlers.NewAdminHandler(adminService)
	analyticsHandler := handlers.NewAnalyticsHandler(analyticsService)
	discountHandler := handlers.NewDiscountHandler(discountService)
	usageHandler := handlers.NewUsageHandler(usageTrackingService)
	planTransitionHandler := handlers.NewPlanTransitionHandler(planTransitionService)
	brandHandler := handlers.NewBrandHandler(brandService, brandExcelService)
	categorySizeHandler := handlers.NewCategorySizeHandler(categorySizeService)
	unitHandler := handlers.NewUnitHandler(unitService)
	featureFlagHandler := handlers.NewFeatureFlagHandler(featureFlagService)

	// Setup routes
	router := setupRoutes(
		cfg,
		cacheClient,
		subscriptionHandler,
		planHandler,
		paymentHandler,
		adminHandler,
		analyticsHandler,
		discountHandler,
		usageHandler,
		planTransitionHandler,
		brandHandler,
		categorySizeHandler,
		unitHandler,
		featureFlagHandler,
	)

	// Create server
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", 8095),
		Handler: router,
	}

	// Start server
	go func() {
		log.Printf("SaaS Admin service starting on port 8095...")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %s\n", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down SaaS Admin service...")

	// Give server 30 seconds to gracefully shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("SaaS Admin service forced to shutdown:", err)
	}

	log.Println("SaaS Admin service exited")
}

func runMigrations(db *gorm.DB) error {
	return db.AutoMigrate(
		// SaaS-specific models only
		&models.PricingPlan{},
		&models.Subscription{},
		&models.Payment{},
		&models.Invoice{},
		&models.UsageRecord{},
		&models.WebhookEvent{},
		&models.AdminUser{},
		&models.AdminInvitation{},
		&models.AdminActivityLog{},
		&models.AuditLog{},
		&models.Unit{},
		&models.FeatureFlag{},
		&models.SystemConfiguration{},
		&models.PlanBillingVariant{},
		&models.GlobalDiscountConfig{},
		&models.PlanDiscountOverride{},
		&models.BillingTermConfig{},
		&models.PlanTransition{},
		&models.PlanTransitionHistory{},

		// Brand management models (SaaS-specific)
		&models.SaasBrand{},
		&models.BrandVariant{},
		&models.TenantBrand{},
		&models.TenantBrandVariant{},
		&models.CategorySize{},
		// Temporarily commented - tables already exist with correct schema
		// &models.BrandCategory{},
		// &models.BrandSubcategory{},
	)
}

func setupRoutes(
	cfg *config.Config,
	cacheClient *cache.Cache,
	subscriptionHandler *handlers.SubscriptionHandler,
	planHandler *handlers.PlanHandler,
	paymentHandler *handlers.PaymentHandler,
	adminHandler *handlers.AdminHandler,
	analyticsHandler *handlers.AnalyticsHandler,
	discountHandler *handlers.DiscountHandler,
	usageHandler *handlers.UsageHandler,
	planTransitionHandler *handlers.PlanTransitionHandler,
	brandHandler *handlers.BrandHandler,
	categorySizeHandler *handlers.CategorySizeHandler,
	unitHandler *handlers.UnitHandler,
	featureFlagHandler *handlers.FeatureFlagHandler,
) *gin.Engine {
	router := gin.New()
	router.Use(gin.Logger())
	router.Use(gin.Recovery())
	router.Use(middleware.CORSMiddleware())
	router.Use(middleware.GzipMiddleware()) // Compress 1645-brand catalog response (3MB → ~600KB)

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"service": "saas", "status": "healthy"})
	})

	// API routes
	api := router.Group("/api")
	{
		// Public routes
		public := api.Group("")
		{
			public.POST("/webhooks/razorpay", paymentHandler.HandleRazorpayWebhook)
			public.GET("/plans", planHandler.GetPublicPlans)
			public.GET("/plans/with-billing-options", planHandler.GetAllPlansWithBillingOptions)
			public.GET("/plans/:id/billing-options", planHandler.GetPlanBillingOptions)
			public.GET("/plans/:id/billing-variants", planHandler.GetPlanBillingVariants)
			public.GET("/plans/:id/calculate", planHandler.CalculatePlanPricing)
		}

		// Internal service-to-service routes (for Inventory service to call)
		internal := api.Group("/internal")
		{
			// Brand template endpoints for inter-service communication
			internal.GET("/brands", brandHandler.GetBrandsInternal)
			internal.GET("/brands/:id", brandHandler.GetBrandByID)
			internal.GET("/brands/:id/variants", brandHandler.GetBrandVariants)
			internal.GET("/brands/categories", brandHandler.GetAllBrandCategories)
			internal.GET("/brands/subcategories", brandHandler.GetBrandSubcategories)
			internal.GET("/brands/category-sizes", categorySizeHandler.GetCategorySizesForInternal)

			// Tenant-specific brand endpoints
			internal.GET("/tenants/:tenant_id/brands", brandHandler.GetTenantBrands)
		}

		// SaaS Admin Authentication routes (public)
		saasAuth := api.Group("/saas-admin")
		{
			saasAuth.POST("/send-otp", adminHandler.SendOTP)
			saasAuth.POST("/verify-otp", adminHandler.VerifyOTP)
			saasAuth.POST("/accept-invitation", adminHandler.AcceptInvitation)
		}

		// Protected routes
		protected := api.Group("")
		protected.Use(middleware.AuthMiddleware(cfg.JWT, cacheClient))
		{
			// Public brand catalog (for tenant users to browse and onboard brands)
			saas := protected.Group("/saas")
			{
				brands := saas.Group("/brands")
				{
					brands.GET("/public", brandHandler.GetAllBrands)           // Get all brands with variants
					brands.GET("/:id", brandHandler.GetBrandByID)              // Get specific brand details
					brands.GET("/:id/variants", brandHandler.GetBrandVariants) // Get variants for a brand
				}
			}

			// Subscription management
			subscriptions := protected.Group("/subscriptions")
			{
				subscriptions.GET("", subscriptionHandler.GetSubscription)
				subscriptions.POST("", subscriptionHandler.CreateSubscription)
				subscriptions.PUT("/:id", subscriptionHandler.UpdateSubscription)
				subscriptions.DELETE("/:id", subscriptionHandler.CancelSubscription)
				subscriptions.POST("/:id/upgrade", subscriptionHandler.UpgradeSubscription)
				subscriptions.POST("/:id/downgrade", subscriptionHandler.DowngradeSubscription)
				subscriptions.GET("/:id/usage", subscriptionHandler.GetUsage)
			}

			// Payment management
			payments := protected.Group("/payments")
			{
				payments.GET("", paymentHandler.GetPayments)
				payments.POST("", paymentHandler.CreatePayment)
				payments.GET("/:id", paymentHandler.GetPayment)
				payments.POST("/:id/refund", paymentHandler.RefundPayment)
			}

			// Invoices
			invoices := protected.Group("/invoices")
			{
				invoices.GET("", paymentHandler.GetInvoices)
				invoices.GET("/:id", paymentHandler.GetInvoice)
				invoices.GET("/:id/download", paymentHandler.DownloadInvoice)
			}

			// Usage tracking (tenant access)
			usage := protected.Group("/usage")
			{
				usage.GET("/:tenant_id/current", usageHandler.GetCurrentUsage)
				usage.GET("/:tenant_id/metrics", usageHandler.GetUsageMetrics)
				usage.GET("/:tenant_id/history", usageHandler.GetUsageHistory)
				usage.GET("/:tenant_id/billing-period", usageHandler.GetBillingPeriodUsage)
				usage.GET("/:tenant_id/export", usageHandler.ExportUsageReport)
			}

			// Plan transitions (tenant access)
			transitions := protected.Group("/transitions")
			{
				transitions.POST("", planTransitionHandler.InitiatePlanTransition)
				transitions.GET("/subscription/:subscription_id/history", planTransitionHandler.GetTransitionHistory)
				transitions.GET("/subscription/:subscription_id/available", planTransitionHandler.GetAvailableTransitions)
				transitions.POST("/preview", planTransitionHandler.PreviewPlanTransition)
				transitions.GET("/:transition_id/status", planTransitionHandler.GetTransitionStatus)
				transitions.POST("/:transition_id/cancel", planTransitionHandler.CancelPendingTransition)
			}

			// Note: Brand management moved to Inventory service
			// Tenants will interact with brands through Inventory service only
		}

		// Super Admin routes with proper middleware
		superAdmin := api.Group("/super-admin")
		// Extract user context from Gateway headers or set default admin context
		superAdmin.Use(func(c *gin.Context) {
			// First, try to extract context from Gateway-forwarded headers
			userID := c.GetHeader("X-User-ID")
			tenantID := c.GetHeader("X-Tenant-ID")
			role := c.GetHeader("X-User-Role")

			// If headers are present, set them in context (Gateway already validated)
			if userID != "" {
				c.Set("user_id", userID)
				c.Set("admin_user_id", userID)
			}
			if tenantID != "" {
				c.Set("tenant_id", tenantID)
			}
			if role != "" {
				c.Set("role", role)
			}

			// Read permissions from gateway header
			if permsHeader := c.GetHeader("X-User-Permissions"); permsHeader != "" {
				perms := strings.Split(permsHeader, ",")
				c.Set("permissions", perms)
			} else if role != "" {
				// Fallback: assign default permissions for the role
				c.Set("permissions", models.GetDefaultPermissions(role))
			}

			// Fall back to default admin context if not set by headers
			if c.GetString("user_id") == "" {
				c.Set("user_id", "00000000-0000-0000-0000-000000000001")
				c.Set("admin_user_id", "00000000-0000-0000-0000-000000000001")
				c.Set("role", "saas_admin")
				c.Set("permissions", models.GetDefaultPermissions("saas_admin"))
			}

			c.Next()
		})
		{
			// Plan management
			plans := superAdmin.Group("/plans")
			plans.Use(saasMiddleware.AdminPermissionMiddleware(models.PermManagePlans))
			{
				plans.GET("", planHandler.GetPlans)
				plans.POST("", planHandler.CreatePlan)
				plans.PUT("/:id", planHandler.UpdatePlan)
				plans.DELETE("/:id", planHandler.DeletePlan)
				plans.GET("/:id", planHandler.GetPlan)
				plans.GET("/:id/features", planHandler.GetPlanFeatures)
				plans.POST("/:id/validate-limits", planHandler.ValidatePlanLimits)
				plans.POST("/initialize", planHandler.InitializeDefaultPlans)
				plans.PUT("/:id/discounts", planHandler.UpdatePlanDiscounts)
			}

			// Admin Team Management
			team := superAdmin.Group("/team")
			team.Use(saasMiddleware.AdminPermissionMiddleware(models.PermManageTeam))
			{
				team.GET("", adminHandler.GetAdminUsers)
				team.POST("", adminHandler.CreateAdminUser)
				team.GET("/:id", adminHandler.GetAdminUser)
				team.PUT("/:id", adminHandler.UpdateAdminUser)
				team.DELETE("/:id", adminHandler.DeleteAdminUser)
				team.POST("/invite", adminHandler.InviteAdminUser)
				team.GET("/invitations", adminHandler.GetPendingInvitations)
				team.DELETE("/invitations/:id", adminHandler.RevokeInvitation)
				team.GET("/:id/activity", adminHandler.GetAdminActivity)
			}

			// Admin Profile
			profile := superAdmin.Group("/profile")
			{
				profile.GET("", adminHandler.GetMyProfile)
				profile.PUT("", adminHandler.UpdateMyProfile)
			}

			// Tenant management
			tenants := superAdmin.Group("/tenants")
			tenants.Use(saasMiddleware.AdminPermissionMiddleware(models.PermManageTenants))
			{
				tenants.GET("", adminHandler.GetAllTenants)
				tenants.GET("/:tenant_id", adminHandler.GetTenantDetail)
				tenants.GET("/:tenant_id/timeline", adminHandler.GetTenantTimeline)
				tenants.POST("/:tenant_id/deactivate", adminHandler.DeactivateTenant)
				tenants.POST("/:tenant_id/reactivate", adminHandler.ReactivateTenant)
			}

			// Subscription management
			subscriptions := superAdmin.Group("/subscriptions")
			{
				subscriptions.GET("", adminHandler.GetAllSubscriptions)
				subscriptions.GET("/:id", adminHandler.GetSubscriptionDetails)
				subscriptions.PUT("/:id/status", adminHandler.UpdateSubscriptionStatus)
			}

			// Discount Management
			discounts := superAdmin.Group("/discounts")
			discounts.Use(saasMiddleware.AdminPermissionMiddleware(models.PermManageDiscounts))
			{
				// Global discount configurations
				discounts.GET("/configs", discountHandler.GetGlobalDiscountConfigs)
				discounts.POST("/configs", discountHandler.CreateGlobalDiscountConfig)
				discounts.PUT("/configs/:id", discountHandler.UpdateGlobalDiscountConfig)
				discounts.DELETE("/configs/:id", discountHandler.DeleteGlobalDiscountConfig)
				discounts.GET("/configs/default", discountHandler.GetDefaultDiscountConfig)

				// Plan-specific discount overrides
				discounts.POST("/plans/overrides", discountHandler.CreatePlanDiscountOverride)
				discounts.GET("/plans/:planId/overrides", discountHandler.GetPlanDiscountOverrides)
				discounts.GET("/plans/:planId/overrides/active", discountHandler.GetActivePlanDiscountOverride)
				discounts.DELETE("/overrides/:id", discountHandler.DeactivatePlanDiscountOverride)

				// Billing term configurations
				discounts.GET("/billing-terms", discountHandler.GetBillingTermConfigs)
				discounts.PUT("/billing-terms/:termMonths", discountHandler.UpdateBillingTermConfig)

				// Bulk operations
				discounts.POST("/bulk-update", discountHandler.BulkUpdatePlanDiscounts)
				discounts.POST("/templates/:templateId/apply", discountHandler.ApplyDiscountTemplate)

				// Analytics and reporting
				discounts.GET("/analytics", discountHandler.GetDiscountAnalytics)
				discounts.GET("/plans/:planId/effective", discountHandler.GetEffectiveDiscounts)
				discounts.GET("/plans/:planId/history", discountHandler.GetDiscountHistory)

				// Initialize default configurations
				discounts.POST("/initialize", discountHandler.InitializeDiscountConfigs)
			}

			// Analytics
			analytics := superAdmin.Group("/analytics")
			analytics.Use(saasMiddleware.AdminPermissionMiddleware(models.PermViewAnalytics))
			{
				analytics.GET("/dashboard", analyticsHandler.GetDashboard)
				analytics.GET("/revenue", analyticsHandler.GetRevenue)
				analytics.GET("/subscriptions", analyticsHandler.GetSubscriptionMetrics)
				analytics.GET("/tenants", analyticsHandler.GetTenantMetrics)
			}

			// Brand management (Super Admin)
			brands := superAdmin.Group("/brands")
			brands.Use(saasMiddleware.AdminPermissionMiddleware(models.PermManageBrands))
			{
				// Category management (specific routes first)
				brands.GET("/categories", brandHandler.GetAllBrandCategories)
				brands.POST("/categories", brandHandler.CreateBrandCategory)
				brands.GET("/categories/:id", func(c *gin.Context) {
					// GET single category by ID - needs implementation
					categoryID := c.Param("id")
					c.JSON(200, gin.H{
						"message": "Get category by ID endpoint - handler needs to be implemented",
						"id":      categoryID,
						"note":    "This would call brandHandler.GetBrandCategoryByID when implemented",
					})
				})
				brands.PUT("/categories/:id", brandHandler.UpdateBrandCategory)
				brands.DELETE("/categories/:id", brandHandler.DeleteBrandCategory)

				brands.GET("/subcategories", brandHandler.GetBrandSubcategories)
				brands.POST("/subcategories", brandHandler.CreateBrandSubcategory)
				brands.GET("/subcategories/:id", func(c *gin.Context) {
					// GET single subcategory by ID - needs implementation
					subcategoryID := c.Param("id")
					c.JSON(200, gin.H{
						"message": "Get subcategory by ID endpoint - handler needs to be implemented",
						"id":      subcategoryID,
						"note":    "This would call brandHandler.GetBrandSubcategoryByID when implemented",
					})
				})
				brands.PUT("/subcategories/:id", brandHandler.UpdateBrandSubcategory)
				brands.DELETE("/subcategories/:id", brandHandler.DeleteBrandSubcategory)

				// Brand variant operations (specific routes)
				brands.POST("/variants", brandHandler.CreateBrandVariant)
				brands.PUT("/variants/:id", brandHandler.UpdateBrandVariant)
				brands.DELETE("/variants/:id", brandHandler.DeleteBrandVariant)

				// Brand assignment removed - tenants onboard brands through Inventory service
				// SaaS admin only manages global brand templates
				brands.GET("/packages", brandHandler.GetBrandPackages)
				brands.GET("/onboarding-stats", brandHandler.GetTenantOnboardingStats)

				// Excel import/export operations (specific routes)
				brands.GET("/template/download", brandHandler.DownloadBrandTemplate)
				brands.POST("/bulk-import", brandHandler.BulkImportBrandsFromExcel)

				// Bulk operations (specific routes)
				brands.POST("/bulk", brandHandler.BulkCreateBrands)

				// Database cleanup operations (specific routes)
				brands.POST("/cleanup", brandHandler.CleanupSoftDeletedRecords)

				// Brand CRUD operations
				brands.GET("", brandHandler.GetAllBrands)
				brands.POST("", brandHandler.CreateBrand)
				brands.GET("/:id", brandHandler.GetBrandByID)
				brands.PUT("/:id", brandHandler.UpdateBrand)
				brands.DELETE("/:id", brandHandler.DeleteBrand)
				brands.GET("/:id/variants", brandHandler.GetBrandVariants)
			}

			// Category Size Management (Super Admin)
			categorySizes := superAdmin.Group("/category-sizes")
			{
				categorySizes.GET("", categorySizeHandler.GetAllCategorySizes)
				categorySizes.GET("/:id", categorySizeHandler.GetCategorySizeByID)
				categorySizes.POST("", categorySizeHandler.CreateCategorySize)
				categorySizes.PUT("/:id", categorySizeHandler.UpdateCategorySize)
				categorySizes.DELETE("/:id", categorySizeHandler.DeleteCategorySize)
			}

			// Category-specific size routes
			categories := superAdmin.Group("/categories")
			{
				categories.GET("/:category_id/sizes", categorySizeHandler.GetCategorySizesByCategory)
				categories.POST("/:category_id/sizes/bulk", categorySizeHandler.BulkCreateCategorySizes)
			}

			// Unit management
			units := superAdmin.Group("/units")
			units.Use(saasMiddleware.AdminPermissionMiddleware(models.PermManageMasterData))
			{
				units.GET("", unitHandler.GetAllUnits)
				units.POST("", unitHandler.CreateUnit)
				units.GET("/:id", unitHandler.GetUnitByID)
				units.PUT("/:id", unitHandler.UpdateUnit)
				units.DELETE("/:id", unitHandler.DeleteUnit)
			}

			// System management
			system := superAdmin.Group("/system")
			system.Use(saasMiddleware.AdminPermissionMiddleware(models.PermSystemAdmin))
			{
				system.GET("/health", adminHandler.GetSystemHealth)
				system.GET("/audit-logs", adminHandler.GetAuditLogs)
				system.POST("/maintenance", adminHandler.ToggleMaintenanceMode)

				// Feature flags
				system.GET("/feature-flags", featureFlagHandler.GetAllFlags)
				system.POST("/feature-flags", featureFlagHandler.CreateFlag)
				system.GET("/feature-flags/:key", featureFlagHandler.GetFlagByKey)
				system.PUT("/feature-flags/:key", featureFlagHandler.UpdateFlag)
				system.DELETE("/feature-flags/:key", featureFlagHandler.DeleteFlag)
				system.POST("/feature-flags/:key/check", featureFlagHandler.CheckFeatureEnabled)

				// System configuration
				system.GET("/configs", featureFlagHandler.GetAllConfigs)
				system.PUT("/configs/:key", featureFlagHandler.UpdateConfig)
			}

			// Usage monitoring and management (SaaS admin)
			usage := superAdmin.Group("/usage")
			{
				// Individual tenant usage management
				usage.POST("/:tenant_id/track", usageHandler.TrackUsage)
				usage.GET("/:tenant_id/current", usageHandler.GetCurrentUsage)
				usage.GET("/:tenant_id/metrics", usageHandler.GetUsageMetrics)
				usage.GET("/:tenant_id/history", usageHandler.GetUsageHistory)
				usage.GET("/:tenant_id/billing-period", usageHandler.GetBillingPeriodUsage)
				usage.GET("/:tenant_id/export", usageHandler.ExportUsageReport)
				usage.POST("/:tenant_id/reset", usageHandler.ResetTenantUsage)

				// Platform-wide usage monitoring
				usage.GET("/all-tenants", usageHandler.GetAllTenantsUsage)
				usage.GET("/alerts", usageHandler.GetUsageAlerts)
			}

			// Plan transition management (SaaS admin)
			transitions := superAdmin.Group("/transitions")
			{
				// Administrative transition management
				transitions.POST("/initiate", planTransitionHandler.InitiatePlanTransition)
				transitions.GET("/subscription/:subscription_id/history", planTransitionHandler.GetTransitionHistory)
				transitions.GET("/subscription/:subscription_id/available", planTransitionHandler.GetAvailableTransitions)
				transitions.POST("/preview", planTransitionHandler.PreviewPlanTransition)
				transitions.GET("/:transition_id/status", planTransitionHandler.GetTransitionStatus)
				transitions.POST("/:transition_id/cancel", planTransitionHandler.CancelPendingTransition)

				// Admin-only operations
				transitions.GET("/all", func(c *gin.Context) {
					c.JSON(200, gin.H{"message": "List all transitions - implementation needed"})
				})
				transitions.POST("/bulk-approve", func(c *gin.Context) {
					c.JSON(200, gin.H{"message": "Bulk approve transitions - implementation needed"})
				})
			}
		}
	}

	return router
}
