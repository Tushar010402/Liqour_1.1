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
	"github.com/liquorpro/go-backend/internal/sales/backfill"
	"github.com/liquorpro/go-backend/internal/sales/handlers"
	"github.com/liquorpro/go-backend/internal/sales/routes"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
	"github.com/sirupsen/logrus"
)

func main() {
	// v1.0.140 — CLI subcommand for retrospective digit-training-data backfill.
	// Mines existing approved daily_sales_records into digit_training_samples
	// without booting the gin server. Idempotent + dry-run-safe.
	if len(os.Args) > 1 && os.Args[1] == "--backfill-training-data" {
		runBackfillSubcommand()
		return
	}

	// v1.0.165 — pipeline bench harness. Re-feeds historical job images
	// through alternative OCR pipelines (current cache, PaddleOCR cv-sidecar,
	// AWS Textract Tables when creds available) and emits a CSV diff against
	// the operator-confirmed truth. Zero prod impact: read-only, no writes.
	//
	// Usage: /root/sales --pipeline-bench --jobs <id1,id2,...> --out /tmp/x.csv
	if len(os.Args) > 1 && os.Args[1] == "--pipeline-bench" {
		runPipelineBench()
		return
	}

	// v1.0.165 — end-to-end Textract+matching bench. Same flag pattern.
	// Usage: /tmp/sales --textract-match --jobs <id1,id2,...> --out /tmp/x.csv
	if len(os.Args) > 1 && os.Args[1] == "--textract-match" {
		runTextractMatchBench()
		return
	}

	// v1.0.167 D4 — bootstrap alias table from approved daily_sales_items.
	// Usage: /tmp/sales-bench --alias-backfill --tenant <uuid> [--dry-run]
	if len(os.Args) > 1 && os.Args[1] == "--alias-backfill" {
		runAliasBackfill()
		return
	}

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

	// Initialize services
	dailySalesService := services.NewDailySalesService(db, redisCache)
	salesService := services.NewSalesService(db, redisCache)
	returnsService := services.NewReturnsService(db, redisCache)
	dashboardService := services.NewDashboardService(db, redisCache)
	dayClosingService := services.NewDayClosingService(db, redisCache)

	// Initialize OCR service with Vision API
	logger := logrus.New()
	logger.SetLevel(logrus.InfoLevel)

	ocrService, err := services.NewSimpleOCRService(db, redisCache, logger)
	if err != nil {
		log.Printf("Warning: OCR service initialization failed: %v", err)
		// Continue without OCR service - it will run in mock mode
	}

	// Initialize alias service for AI learning (with Redis cache for scale).
	// Created BEFORE salesHandlers so the v1.0.175 Brand Shortcuts CRUD can
	// share the same singleton — ensures cache invalidation is consistent
	// between manual operator edits and the auto-learning loop.
	aliasService := alias.NewAliasService(db, alias.WithRedis(redisCache.Client()))

	// Initialize handlers
	salesHandlers := handlers.NewSalesHandlers(
		dailySalesService,
		salesService,
		returnsService,
		dashboardService,
		dayClosingService,
		aliasService,
		db,
	)

	// Initialize OCR handlers if service is available
	var ocrHandlers *handlers.OCRHandlers
	if ocrService != nil {
		ocrHandlers = handlers.NewOCRHandlers(ocrService, logger)
	}

	// Initialize Smart Sale service and handlers.
	var smartSaleHandlers *handlers.SmartSaleHandlers
	var smartSaleJobHandlers *handlers.SmartSaleJobHandlers
	var smartSaleJobService *services.SmartSaleJobService
	if ocrService != nil && ocrService.GetGeminiService() != nil {
		smartSaleService := services.NewSmartSaleService(db, redisCache, ocrService.GetGeminiService(), logger, aliasService)
		smartSaleHandlers = handlers.NewSmartSaleHandlers(smartSaleService, aliasService, db, logger)

		// Smart Sale async job queue — mirrors the Smart Stock Setup pattern:
		// submit returns 202 + job_id, a Postgres-backed worker polls the
		// queue and runs ProcessSmartSale in the background, clients poll
		// for the result. Survives app backgrounding and transient vendor
		// failures (3x retry) that the sync handler can't recover from.
		smartSaleJobService = services.NewSmartSaleJobService(db, smartSaleService)
		smartSaleJobHandlers = handlers.NewSmartSaleJobHandlers(smartSaleJobService, logger)
		log.Println("Smart Sale service initialized successfully with AI learning (sync + async job queue)")
	} else {
		log.Println("Warning: Smart Sale service not available (Gemini API not configured)")
	}

	// Initialize AI Feedback handlers
	aiFeedbackHandlers := handlers.NewAIFeedbackHandlers(db)

	// Create router
	router := gin.New()

	// Configure max multipart memory for OCR and Smart Sale image uploads
	// Allow up to 64MB for image uploads (Smart Sale supports up to 5 images at 10MB each)
	router.MaxMultipartMemory = 64 << 20 // 64 MiB

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware())
	// router.Use(middleware.RequestIDMiddleware()) // Not implemented yet
	router.Use(middleware.CORSMiddleware())

	// Serve uploaded images (receipt photos, etc.)
	router.Static("/uploads", "/app/uploads")

	// Setup routes - Use SetupProtectedRoutes for gateway-style routing
	// Gateway strips /api/sales prefix, so we need routes without /api prefix
	routes.SetupProtectedRoutes(router, cfg, redisCache, salesHandlers, ocrHandlers, smartSaleHandlers, aiFeedbackHandlers, smartSaleJobHandlers)

	// Start server.
	// v1.0.131 — bump WriteTimeout to 600s. Smart Sale eval / Smart Sale full
	// pipeline (Claude main + voting + recovery + page-rescue + handwritten-
	// band) can take 90-180s end-to-end on dense multi-page handwritten
	// registers. Pre-v1.0.131 the 120s default truncated long requests with
	// "empty reply from server" — admin retried + thought the eval was broken.
	// Read timeout stays at config default (image upload size hasn't changed).
	writeTimeout := cfg.Server.WriteTimeout
	if writeTimeout < 600 {
		writeTimeout = 600
	}
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Services.Sales.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(writeTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Sales service starting on %s:%d", cfg.Server.Host, cfg.Services.Sales.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Start the Smart Sale background-job worker if wired. Worker context is
	// canceled on SIGINT/SIGTERM so an in-flight job can complete (or give
	// up at its own timeout) rather than being hard-killed mid-DB-write.
	workerCtx, workerCancel := context.WithCancel(context.Background())
	defer workerCancel()
	if smartSaleJobService != nil {
		smartSaleJobService.StartWorker(workerCtx)
	}

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Sales service...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Sales service stopped")
}

// runBackfillSubcommand wires up DB + cache + logger and hands off to the
// backfill package. Keeps main() lean and avoids a second binary target.
func runBackfillSubcommand() {
	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}
	db, err := database.NewDatabase(database.Config{
		Host: cfg.Database.Host, Port: cfg.Database.Port,
		User: cfg.Database.User, Password: cfg.Database.Password,
		DBName: cfg.Database.DBName, SSLMode: cfg.Database.SSLMode, TimeZone: cfg.Database.TimeZone,
	})
	if err != nil {
		log.Fatalf("backfill: db connect: %v", err)
	}
	defer db.Close()
	redisCache, err := cache.NewCache(cache.Config{
		Host: cfg.Redis.Host, Port: cfg.Redis.Port, Password: cfg.Redis.Password, DB: cfg.Redis.DB,
	})
	if err != nil {
		log.Fatalf("backfill: redis connect: %v", err)
	}
	defer redisCache.Close()
	logger := logrus.New()
	logger.SetLevel(logrus.InfoLevel)
	backfill.ParseFlagsAndRun(db, redisCache, logger)
}
