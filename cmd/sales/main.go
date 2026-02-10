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
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/internal/sales/handlers"
	"github.com/liquorpro/go-backend/internal/sales/routes"
	"github.com/liquorpro/go-backend/internal/sales/services"
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
	dailySalesService := services.NewDailySalesService(db, redisCache)
	salesService := services.NewSalesService(db, redisCache)
	returnsService := services.NewReturnsService(db, redisCache)
	dashboardService := services.NewDashboardService(db, redisCache)

	// Wire up workflow notifications for sales approval workflows
	salesService.SetWorkflowNotificationService(workflowNotificationService)
	dailySalesService.SetWorkflowNotificationService(workflowNotificationService)
	log.Println("Workflow notifications initialized for sales service")

	// Initialize and start pending sales reminder scheduler
	pendingSalesScheduler := services.NewPendingSalesScheduler(db, workflowNotificationService)
	pendingSalesScheduler.Start()
	defer pendingSalesScheduler.Stop()

	// Initialize OCR service with Gemini AI
	ocrService, err := services.NewOCRService(db)
	if err != nil {
		log.Printf("Warning: Failed to initialize OCR service: %v", err)
		log.Println("OCR endpoints will not be available")
	}
	if ocrService != nil {
		defer ocrService.Close()
	}

	// Initialize AI Validation service (requires OCR service for auto-validation)
	var validationService *services.ValidationService
	if ocrService != nil {
		validationService = services.NewValidationService(db, redisCache, ocrService)
		log.Println("AI Validation service initialized for daily sales records")
	} else {
		log.Println("Warning: AI Validation service not available (OCR service required)")
	}

	// Initialize handlers
	salesHandlers := handlers.NewSalesHandlers(
		dailySalesService,
		salesService,
		returnsService,
		dashboardService,
	)

	// Wire up validation service for AI-powered validation
	if validationService != nil {
		salesHandlers.SetValidationService(validationService)
	}

	// Initialize OCR handlers (nil-safe)
	var ocrHandlers *handlers.OCRHandlers
	if ocrService != nil {
		ocrHandlers = handlers.NewOCRHandlers(ocrService)
	}

	// Initialize draft service and handlers (backend-based draft persistence)
	draftService := services.NewDraftService(db, dailySalesService)
	draftHandlers := handlers.NewDraftHandlers(draftService)
	log.Println("Draft persistence service initialized for daily sales")

	// Initialize purcha report service and handlers (daily sales register)
	purchaReportService := services.NewPurchaReportService(db, redisCache)
	purchaReportHandler := handlers.NewPurchaReportHandler(purchaReportService)
	log.Println("Purcha report service initialized for daily sales register")

	// Initialize training image service and handlers (AI training data preparation)
	trainingImageService := services.NewTrainingImageService(db)
	trainingHandlers := handlers.NewTrainingHandlers(trainingImageService)
	log.Println("Training image service initialized for AI training data preparation")

	// Initialize AI Training V2 service and handlers (generic document extraction training)
	var aiTrainingHandlers *handlers.AITrainingHandlers
	aiTrainingService, err := services.NewAITrainingService(db)
	if err != nil {
		log.Printf("Warning: Failed to initialize AI Training V2 service: %v", err)
		log.Println("AI Training V2 endpoints will not be available")
	} else {
		aiTrainingHandlers = handlers.NewAITrainingHandlers(aiTrainingService)
		log.Println("AI Training V2 service initialized for generic document extraction training")
	}

	// Create router
	router := gin.New()

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware())
	router.Use(middleware.RequestIDMiddleware())
	router.Use(middleware.CORSMiddleware())

	// Setup routes
	// Use SetupProtectedRoutes since this service is behind the API Gateway
	// The gateway handles authentication and forwards user context via headers
	routes.SetupProtectedRoutes(router, cfg, redisCache, salesHandlers, ocrHandlers, draftHandlers, purchaReportHandler, trainingHandlers, aiTrainingHandlers)

	// Start server
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Services.Sales.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Sales service starting on %s:%d", cfg.Server.Host, cfg.Services.Sales.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

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
