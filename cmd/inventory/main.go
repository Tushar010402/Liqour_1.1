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
	exciseRoutes "github.com/liquorpro/go-backend/internal/excise/routes"
	"github.com/liquorpro/go-backend/internal/inventory/handlers"
	"github.com/liquorpro/go-backend/internal/inventory/routes"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Set Gin mode
	if cfg.App.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	} else if cfg.App.Environment == "test" {
		gin.SetMode(gin.TestMode)
	}

	// Initialize database
	dbConfig := database.Config{
		Host:     cfg.Database.Host,
		Port:     cfg.Database.Port,
		User:     cfg.Database.User,
		Password: cfg.Database.Password,
		DBName:   cfg.Database.DBName,
		SSLMode:  cfg.Database.SSLMode,
		TimeZone: cfg.Database.TimeZone,
	}

	db, err := database.NewDatabase(dbConfig)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Initialize cache
	cacheConfig := cache.Config{
		Host:     cfg.Redis.Host,
		Port:     cfg.Redis.Port,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	}

	redisCache, err := cache.NewCache(cacheConfig)
	if err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	defer redisCache.Close()

	// Initialize notification services for workflow notifications
	notificationService := notifservices.NewNotificationService(db, redisCache)
	workflowNotificationService := notifservices.NewWorkflowNotificationService(db, notificationService)

	// Initialize services
	productService := services.NewProductService(db, redisCache)
	stockService := services.NewStockService(db, redisCache)
	purchaseService := services.NewPurchaseService(db, redisCache)
	categoryService := services.NewCategoryService(db, redisCache)
	tenantBrandService := services.NewTenantBrandService(db, redisCache, cfg)
	brandOnboardingService := services.NewBrandOnboardingService(db.DB, cfg, nil) // logger will be added
	enhancedProductService := services.NewEnhancedProductService(db, redisCache)

	// Set up SaaS client for ProductService to enable SaaS category lookups
	saasClient := services.NewSaaSBrandClient("http://saas:8095", nil)
	productService.SetSaaSClient(saasClient)

	// Wire up workflow notifications for purchase approval workflows
	purchaseService.SetWorkflowNotificationService(workflowNotificationService)
	log.Println("Workflow notifications initialized for inventory service")

	// Initialize purchase draft service
	purchaseDraftService := services.NewPurchaseDraftService(db, purchaseService)

	// Initialize handlers
	brandOnboardingHandler := handlers.NewBrandOnboardingHandler(brandOnboardingService)
	brandCreationHandler := handlers.NewBrandCreationHandler(enhancedProductService)
	draftHandlers := handlers.NewDraftHandlers(purchaseDraftService)
	inventoryHandlers := handlers.NewInventoryHandlers(
		productService,
		stockService,
		purchaseService,
		categoryService,
		tenantBrandService,
		brandOnboardingHandler,
		brandCreationHandler,
	)

	// Create router
	router := gin.New()

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware())
	router.Use(middleware.RequestIDMiddleware())
	router.Use(middleware.CORSMiddleware())

	// Setup routes (using protected routes for gateway-style deployment)
	routes.SetupProtectedRoutes(router, cfg, redisCache, inventoryHandlers, draftHandlers)
	log.Println("Stock purchase draft routes initialized")

	// Setup excise compliance routes with authentication (UP Excise integration)
	exciseRoutes.SetupExciseRoutes(router, db.DB, cfg.JWT, redisCache)
	log.Println("UP Excise compliance routes registered with authentication")

	// Start server
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Services.Inventory.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Inventory service starting on %s:%d", cfg.Server.Host, cfg.Services.Inventory.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Inventory service...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Inventory service stopped")
}
