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
	"github.com/liquorpro/go-backend/internal/gateway/handlers"
	gatewayMiddleware "github.com/liquorpro/go-backend/internal/gateway/middleware"
	"github.com/liquorpro/go-backend/internal/gateway/routes"
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
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Set Gin mode based on configuration
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

	// Skip migrations in Gateway - handled by individual services
	// Gateway only needs database connection for auth middleware
	log.Println("Skipping migrations - handled by individual microservices")

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

	// Initialize HTTP client for service communication
	// Extended timeout for OCR batch processing (Vision API + Gemini extraction)
	httpClient := &http.Client{
		Timeout: 300 * time.Second,
	}

	// Initialize handlers
	gatewayHandlers := handlers.NewGatewayHandlers(cfg, httpClient)

	// Create router
	router := gin.New()

	// Set max multipart memory to 100MB (for large file uploads like OCR images)
	router.MaxMultipartMemory = 100 << 20 // 100 MB

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware())
	router.Use(middleware.RequestIDMiddleware())
	router.Use(middleware.CORSMiddleware())

	// Initialize logger for rate limiter
	zapLogger, err := logger.NewLogger(cfg.App.Environment)
	if err != nil {
		log.Printf("Warning: Failed to initialize logger for rate limiter: %v", err)
	}

	// Initialize Redis-based rate limiter (distributed across gateway instances)
	redisRateLimiter := middleware.NewRedisRateLimiter(redisCache.Client(), zapLogger)

	// Register endpoint-specific limits (validation, auth, OCR, finance, etc.)
	gatewayMiddleware.RegisterEndpointLimits(redisRateLimiter)

	// Apply endpoint-specific rate limits globally (runs BEFORE auth for public endpoints)
	// This protects against enumeration attacks on /api/admin/validate/* and OTP bombing
	router.Use(redisRateLimiter.EndpointMiddleware())

	// Setup routes - pass rate limiter for role-based limiting on protected routes
	routes.SetupRoutes(router, cfg, redisCache, gatewayHandlers, redisRateLimiter)

	// Start server
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start server in a goroutine
	go func() {
		log.Printf("API Gateway starting on %s:%d", cfg.Server.Host, cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down API Gateway...")

	// Give outstanding requests 30 seconds to complete
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("API Gateway stopped")
}
