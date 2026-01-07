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
	alarmServices "github.com/liquorpro/go-backend/internal/alarms/services"
	auditServices "github.com/liquorpro/go-backend/internal/audit/services"
	detectionServices "github.com/liquorpro/go-backend/internal/detection/services"
	"github.com/liquorpro/go-backend/internal/finance/handlers"
	"github.com/liquorpro/go-backend/internal/finance/routes"
	financeServices "github.com/liquorpro/go-backend/internal/finance/services"
	notificationServices "github.com/liquorpro/go-backend/internal/notifications/services"
	tipsServices "github.com/liquorpro/go-backend/internal/tips/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
	"go.uber.org/zap"
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

	// Initialize core finance services
	vendorService := financeServices.NewVendorService(db, redisCache)
	expenseService := financeServices.NewExpenseService(db, redisCache)
	assistantManagerService := financeServices.NewAssistantManagerService(db, redisCache)
	executiveFinanceService := financeServices.NewExecutiveFinanceService(db, redisCache)
	bankService := financeServices.NewBankService(db, redisCache)
	stockVerificationService := financeServices.NewStockVerificationService(db, redisCache)
	dashboardMetricsService := financeServices.NewDashboardMetricsService(db, redisCache)

	// Initialize extended services (tips, detection, audit, notifications)
	tipsService := tipsServices.NewTipsService(db, redisCache)
	detectionService := detectionServices.NewDetectionService(db, redisCache)
	auditService := auditServices.NewAuditService(db, redisCache)
	notificationService := notificationServices.NewNotificationService(db, redisCache)
	workflowNotificationService := notificationServices.NewWorkflowNotificationService(db, notificationService)

	// Wire up workflow notifications for finance approval workflows
	assistantManagerService.SetWorkflowNotificationService(workflowNotificationService)
	expenseService.SetWorkflowNotificationService(workflowNotificationService)
	stockVerificationService.SetWorkflowNotificationService(workflowNotificationService)
	log.Println("✅ Workflow notifications initialized for finance service")

	// Initialize alarm services
	alarmService := alarmServices.NewAlarmService(db, redisCache, notificationService)
	alarmScheduler := alarmServices.NewAlarmSchedulerService(db, alarmService)
	reminderScheduler := alarmServices.NewReminderSchedulerService(db, alarmService)

	// Initialize logger for app logging service
	logger, _ := zap.NewProduction()
	if cfg.App.Environment != "production" {
		logger, _ = zap.NewDevelopment()
	}
	defer logger.Sync()

	// Initialize app logging service (Industrial-Grade Monitoring)
	appLoggingService := financeServices.NewAppLoggingService(db, logger)
	appLoggingHandlers := handlers.NewAppLoggingHandlers(appLoggingService, logger)

	// Log service initialization
	log.Println("✅ Initialized core finance services")
	log.Println("✅ Initialized app logging service (Industrial-Grade Monitoring)")
	log.Println("✅ Initialized dashboard metrics service")
	log.Println("✅ Initialized tips service")
	log.Println("✅ Initialized detection service")
	log.Println("✅ Initialized audit service")
	log.Println("✅ Initialized notification service")
	log.Println("✅ Initialized alarm services")

	// Initialize handlers with all services including extended modules
	financeHandlers := handlers.NewFinanceHandlersWithExtended(
		vendorService,
		expenseService,
		assistantManagerService,
		executiveFinanceService,
		bankService,
		stockVerificationService,
		tipsService,
		detectionService,
		auditService,
		notificationService,
	)

	// Set dashboard metrics service
	financeHandlers.SetDashboardMetricsService(dashboardMetricsService)

	// Set alarm services
	financeHandlers.SetAlarmServices(alarmService, alarmScheduler)

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
	routes.SetupProtectedRoutes(router, cfg, redisCache, financeHandlers)

	// Setup app logging routes (Industrial-Grade Monitoring)
	routes.SetupAppLoggingRoutes(router, appLoggingHandlers)
	log.Println("✅ App logging routes configured")

	// Start server
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Services.Finance.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start auto-expiry scheduler for overdue money collections
	go func() {
		ticker := time.NewTicker(1 * time.Minute)
		defer ticker.Stop()
		log.Println("Auto-expiry scheduler started - checking for overdue collections every minute")
		for range ticker.C {
			count, err := assistantManagerService.MarkAllOverdueCollections(context.Background())
			if err != nil {
				log.Printf("Error marking overdue collections: %v", err)
			} else if count > 0 {
				log.Printf("Marked %d overdue collections", count)
			}
		}
	}()

	// Start alarm scheduler
	alarmScheduler.Start()
	log.Println("✅ Alarm scheduler started")

	// Start reminder scheduler for user-configured reminders
	reminderScheduler.Start()
	log.Println("✅ Reminder scheduler started")

	// Start app log cleanup scheduler (daily at 3 AM)
	go func() {
		// Calculate time until next 3 AM
		now := time.Now()
		next3AM := time.Date(now.Year(), now.Month(), now.Day(), 3, 0, 0, 0, now.Location())
		if now.After(next3AM) {
			next3AM = next3AM.Add(24 * time.Hour)
		}
		waitDuration := next3AM.Sub(now)
		log.Printf("📋 App log cleanup scheduler started - first run in %v", waitDuration.Round(time.Minute))

		// Wait until 3 AM
		time.Sleep(waitDuration)

		// Run cleanup and then every 24 hours
		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()

		for {
			deletedCount, err := appLoggingService.CleanupOldLogs(context.Background(), 30)
			if err != nil {
				log.Printf("Error cleaning up old app logs: %v", err)
			} else if deletedCount > 0 {
				log.Printf("📋 Cleaned up %d old app logs (retention: 30 days)", deletedCount)
			}
			<-ticker.C
		}
	}()

	// Start server in goroutine
	go func() {
		log.Printf("Finance service starting on %s:%d", cfg.Server.Host, cfg.Services.Finance.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Finance service...")

	// Stop reminder scheduler
	reminderScheduler.Stop()
	log.Println("✅ Reminder scheduler stopped")

	// Stop alarm scheduler
	alarmScheduler.Stop()
	log.Println("✅ Alarm scheduler stopped")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Finance service stopped")
}
