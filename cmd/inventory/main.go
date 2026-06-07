package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/liquorpro/go-backend/internal/inventory/handlers"
	"github.com/liquorpro/go-backend/internal/inventory/routes"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	exciseRoutes "github.com/liquorpro/go-backend/internal/excise/routes"
	grpcInventory "github.com/liquorpro/go-backend/pkg/grpc/inventory"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
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

	// Run database migrations
	log.Println("Running database migrations...")
	if err := db.Migrate(); err != nil {
		log.Printf("Migration warning: %v", err)
		// Continue anyway as some migrations might be optional
	}

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

	// Initialize logrus logger
	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{})
	if cfg.App.Environment == "production" {
		logger.SetLevel(logrus.InfoLevel)
	} else {
		logger.SetLevel(logrus.DebugLevel)
	}
	logger.SetOutput(os.Stdout)

	// Initialize zap logger for gRPC
	var zapLogger *zap.Logger
	if cfg.App.Environment == "production" {
		zapLogger, err = zap.NewProduction()
	} else {
		zapLogger, err = zap.NewDevelopment()
	}
	if err != nil {
		log.Fatalf("Failed to initialize zap logger: %v", err)
	}
	defer zapLogger.Sync()

	// Initialize services
	productService := services.NewProductService(db, redisCache)
	stockService := services.NewStockService(db, redisCache)
	purchaseService := services.NewPurchaseService(db, redisCache)
	categoryService := services.NewCategoryService(db, redisCache)
	tenantBrandService := services.NewTenantBrandService(db, redisCache, cfg)
	brandOnboardingService := services.NewBrandOnboardingService(db.DB, cfg, nil) // zap logger - use nil for now
	enhancedProductService := services.NewEnhancedProductService(db, redisCache)

	// Initialize SaaS brand client for bulk import
	// Use localhost:8091 as default SaaS service URL (can be configured later)
	saaSServiceURL := "http://localhost:8091"
	saaSBrandClient := services.NewSaaSBrandClient(saaSServiceURL, nil) // zap logger can be nil for now

	// Initialize bulk import services
	bulkImportService := services.NewBulkImportService(db.DB, logger, brandOnboardingService, stockService, saaSBrandClient)
	importTemplateService := services.NewImportTemplateService(db.DB, logger)

	// Initialize Smart Purchase OCR service
	smartPurchaseOCR := services.NewSmartPurchaseOCR()
	smartPurchaseService := services.NewSmartPurchaseService(db, smartPurchaseOCR)

	// Initialize alias service for AI learning (with Redis cache for scale)
	aliasService := alias.NewAliasService(db, alias.WithRedis(redisCache.Client()))

	// Initialize Smart Stock Setup service
	smartStockSetupService := services.NewSmartStockSetupService(db, smartPurchaseOCR, stockService, smartPurchaseService, aliasService)

	// Initialize Smart Stock Setup background-job service. The worker
	// goroutine is started below with a context tied to the process lifetime
	// so graceful shutdown drains the current job before exiting.
	smartStockJobService := services.NewSmartStockJobService(db, smartStockSetupService)

	// v1.0.188 — Smart Purchase background-job service. Mirror of the Smart
	// Sale job pattern: submit returns a job_id immediately, a worker
	// drains the queue, clients poll for the result. Replaces the legacy
	// synchronous /smart-purchase/extract path that timed out at the nginx
	// gateway on multi-page invoices (chhotu's class of failure).
	smartPurchaseJobService := services.NewSmartPurchaseJobService(db, smartPurchaseService)

	// v1.0.216 — banking-grade nightly reconciliation. Walks every stock,
	// asserts stocks.quantity == latest stock_history.new_quantity, and
	// writes an audit_heal_v1 row for any divergence. Boot-time sweep + 24h
	// interval (override via STOCK_RECONCILE_INTERVAL). The trigger that
	// gates new history writes (stock_histories_insert_guard) makes drift
	// structurally impossible going forward; this worker is the second line
	// of defense against manual DB pokes and bugs in unmigrated code paths.
	stockReconcileService := services.NewStockReconciliationService(db, redisCache)

	// Read-only data-integrity watchdog (post FM Tower 8PM Tetra/PET incident,
	// 2026-05-29): detects sale-math mismatches, stock↔ledger drift, and stock
	// rows soft-deleted while still holding units, recording data_integrity_alerts
	// + loud logs so problems surface to ops automatically rather than being
	// spotted by a customer. Never mutates business data.
	dataIntegrityWatchdog := services.NewDataIntegrityWatchdog(db, redisCache)

	// Initialize handlers
	brandOnboardingHandler := handlers.NewBrandOnboardingHandler(brandOnboardingService)
	brandCreationHandler := handlers.NewBrandCreationHandler(enhancedProductService)
	bulkImportHandler := handlers.NewBulkImportHandler(bulkImportService, importTemplateService, logger)

	inventoryHandlers := handlers.NewInventoryHandlers(
		productService,
		stockService,
		purchaseService,
		categoryService,
		tenantBrandService,
		brandOnboardingHandler,
		brandCreationHandler,
		bulkImportHandler,
		smartPurchaseService,
		smartStockSetupService,
		smartStockJobService,
	)

	// Create router
	router := gin.New()

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware()) // Includes Request ID handling
	router.Use(middleware.CORSMiddleware())
	router.Use(middleware.GzipMiddleware()) // Compress JSON responses (large brand/product lists save 4-5x bandwidth)

	// Setup routes (using protected routes for gateway-style deployment)
	// v1.0.133-r8 — alias hygiene + missing-SKU sweep admin handlers.
	// Both take only *database.DB so they're independent of the main
	// inventory handler's heavy dep graph.
	aliasHygieneHandler := handlers.NewAliasHygieneHandler(db)
	productMergeHandler := handlers.NewProductMergeHandler(db)
	missingSkuHandler := handlers.NewMissingSkuHandler(db)
	smartPurchaseJobHandlers := handlers.NewSmartPurchaseJobHandlers(smartPurchaseJobService, logger)
	// v1.0.193 — vendor auto-create from Smart Purchase review screen.
	smartPurchaseVendorHandler := handlers.NewSmartPurchaseVendorHandler(db, logger)
	// v1.0.193 — apply endpoint that wraps create-purchase + 4-signal learning.
	smartPurchaseApplyHandler := handlers.NewSmartPurchaseApplyHandler(smartPurchaseService, logger)
	// v1.0.193 — brand-photo OCR fallback (cv-sidecar 3-tier cascade).
	brandPhotoClient := services.NewBrandPhotoClient(logger)
	smartPurchaseBrandPhotoHandler := handlers.NewSmartPurchaseBrandPhotoHandler(brandPhotoClient, logger)
	// v1.0.193 — Tier 3 + Tier 4 onboarding endpoints.
	smartPurchaseOnboardHandler := handlers.NewSmartPurchaseOnboardHandler(db, logger)
	// v1.0.193 W4.1 — replay-matcher diagnostic endpoint.
	smartPurchaseReplayHandler := handlers.NewSmartPurchaseReplayHandler(smartPurchaseService, logger)
	// v1.0.222 — past-purchase disambiguation endpoint.
	smartPurchaseDisambigHandler := handlers.NewSmartPurchaseDisambigHandler(smartPurchaseService, logger)
	// v1.0.243 — Brand-image verification gate for AI Stock Setup. Initialised
	// even when Gemini key is missing; verifier will return gemini_unavailable
	// and the handler will surface that to the operator.
	brandVerifier, _ := services.NewGeminiBrandVerifier(db.DB, logger)
	smartStockSetupVerifyHandler := handlers.NewSmartStockSetupVerifyHandler(brandVerifier, aliasService, db, logger, smartStockSetupService)
	routes.SetupProtectedRoutes(router, cfg, redisCache, inventoryHandlers, aliasHygieneHandler, missingSkuHandler, smartPurchaseJobHandlers, smartPurchaseVendorHandler, smartPurchaseApplyHandler, smartPurchaseBrandPhotoHandler, smartPurchaseOnboardHandler, smartPurchaseReplayHandler, smartPurchaseDisambigHandler, smartStockSetupVerifyHandler, productMergeHandler)

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

	// Initialize gRPC server
	grpcPort := cfg.Services.Inventory.Port + 1000 // Use port 9082 for gRPC (8082 + 1000)
	grpcServer := grpc.NewServer()
	inventoryGRPCServer := grpcInventory.NewServer(db.DB, zapLogger)
	grpcInventory.RegisterInventoryServiceServer(grpcServer, inventoryGRPCServer)

	// Enable gRPC reflection for easier debugging (optional in production)
	if cfg.App.Environment != "production" {
		reflection.Register(grpcServer)
	}

	// Start gRPC server in goroutine
	go func() {
		lis, err := net.Listen("tcp", fmt.Sprintf("%s:%d", cfg.Server.Host, grpcPort))
		if err != nil {
			log.Fatalf("Failed to listen for gRPC: %v", err)
		}
		log.Printf("Inventory gRPC service starting on %s:%d", cfg.Server.Host, grpcPort)
		zapLogger.Info("gRPC server started",
			zap.String("host", cfg.Server.Host),
			zap.Int("port", grpcPort))

		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("Failed to start gRPC server: %v", err)
		}
	}()

	// Start HTTP server in goroutine
	go func() {
		log.Printf("Inventory HTTP service starting on %s:%d", cfg.Server.Host, cfg.Services.Inventory.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start HTTP server: %v", err)
		}
	}()

	// Start the Smart Stock Setup background-job worker. Worker context is
	// canceled on SIGINT/SIGTERM so an in-flight job can complete (or give up
	// at its own timeout) rather than being hard-killed mid-DB-write.
	workerCtx, workerCancel := context.WithCancel(context.Background())
	defer workerCancel()
	smartStockJobService.StartWorker(workerCtx)
	smartPurchaseJobService.StartWorker(workerCtx)
	stockReconcileService.StartWorker(workerCtx)
	dataIntegrityWatchdog.StartWorker(workerCtx)

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Inventory service...")
	zapLogger.Info("Shutting down Inventory service...")

	// Signal the background worker to stop BEFORE the HTTP server drains so
	// no new jobs can be claimed while existing ones are finishing.
	workerCancel()

	// Graceful shutdown for both servers
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Shutdown HTTP server
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("HTTP server forced to shutdown: %v", err)
	}

	// Shutdown gRPC server
	grpcServer.GracefulStop()

	log.Println("Inventory service stopped")
	zapLogger.Info("Inventory service stopped")
}
