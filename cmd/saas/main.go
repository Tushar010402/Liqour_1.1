package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/handlers"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatal("Failed to load configuration:", err)
	}

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
	adminService := services.NewAdminService(db, cfg)
	analyticsService := services.NewAnalyticsService(db, cfg)

	// Initialize handlers
	subscriptionHandler := handlers.NewSubscriptionHandler(subscriptionService)
	planHandler := handlers.NewPlanHandler(planService)
	paymentHandler := handlers.NewPaymentHandler(paymentService)
	adminHandler := handlers.NewAdminHandler(adminService)
	analyticsHandler := handlers.NewAnalyticsHandler(analyticsService)

	// Setup routes
	router := setupRoutes(
		cfg,
		cacheClient,
		subscriptionHandler,
		planHandler,
		paymentHandler,
		adminHandler,
		analyticsHandler,
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
		&models.PricingPlan{},
		&models.Subscription{},
		&models.Payment{},
		&models.Invoice{},
		&models.UsageRecord{},
		&models.WebhookEvent{},
		&models.AdminUser{},
		&models.AuditLog{},
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
) *gin.Engine {
	router := gin.New()
	router.Use(gin.Logger())
	router.Use(gin.Recovery())
	router.Use(middleware.CORSMiddleware())

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
		}

		// Protected routes
		protected := api.Group("")
		protected.Use(middleware.AuthMiddleware(cfg.JWT, cacheClient))
		{
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
		}

		// Super Admin routes
		superAdmin := api.Group("/admin")
		superAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cacheClient))
		superAdmin.Use(middleware.RoleMiddleware("super_admin"))
		{
			// Plan management
			plans := superAdmin.Group("/plans")
			{
				plans.GET("", planHandler.GetPlans)
				plans.POST("", planHandler.CreatePlan)
				plans.PUT("/:id", planHandler.UpdatePlan)
				plans.DELETE("/:id", planHandler.DeletePlan)
			}

			// Subscription management
			subscriptions := superAdmin.Group("/subscriptions")
			{
				subscriptions.GET("", adminHandler.GetAllSubscriptions)
				subscriptions.GET("/:id", adminHandler.GetSubscriptionDetails)
				subscriptions.PUT("/:id/status", adminHandler.UpdateSubscriptionStatus)
			}

			// Analytics
			analytics := superAdmin.Group("/analytics")
			{
				analytics.GET("/dashboard", analyticsHandler.GetDashboard)
				analytics.GET("/revenue", analyticsHandler.GetRevenue)
				analytics.GET("/subscriptions", analyticsHandler.GetSubscriptionMetrics)
				analytics.GET("/tenants", analyticsHandler.GetTenantMetrics)
			}

			// System management
			system := superAdmin.Group("/system")
			{
				system.GET("/health", adminHandler.GetSystemHealth)
				system.GET("/audit-logs", adminHandler.GetAuditLogs)
				system.POST("/maintenance", adminHandler.ToggleMaintenanceMode)
			}
		}
	}

	return router
}