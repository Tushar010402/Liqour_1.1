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
	"github.com/liquorpro/go-backend/internal/gateway/routes"
	"github.com/liquorpro/go-backend/pkg/graphql"
	"github.com/liquorpro/go-backend/pkg/messaging"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize logger
	var logger *zap.Logger
	if cfg.App.Environment == "production" {
		logger, err = zap.NewProduction()
	} else {
		logger, err = zap.NewDevelopment()
	}
	if err != nil {
		log.Fatalf("Failed to initialize logger: %v", err)
	}
	defer logger.Sync()

	logger.Info("Starting API Gateway",
		zap.String("environment", cfg.App.Environment),
		zap.String("version", cfg.App.Version))

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
		logger.Fatal("Failed to connect to database", zap.Error(err))
	}
	defer db.Close()

	logger.Info("Database connected successfully")

	// Skip migrations in Gateway - handled by individual services
	// Gateway only needs database connection for auth middleware
	logger.Info("Skipping migrations - handled by individual microservices")

	// Initialize cache
	cacheConfig := cache.Config{
		Host:     cfg.Redis.Host,
		Port:     cfg.Redis.Port,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	}

	redisCache, err := cache.NewCache(cacheConfig)
	if err != nil {
		logger.Fatal("Failed to connect to Redis", zap.Error(err))
	}
	defer redisCache.Close()

	logger.Info("Redis cache connected successfully")

	// Initialize Redis client for GraphQL (needs *redis.Client)
	redisClient := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", cfg.Redis.Host, cfg.Redis.Port),
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})
	defer redisClient.Close()

	// Initialize Kafka client (optional - graceful degradation if not available)
	var kafkaClient *messaging.KafkaClient
	if cfg.Kafka.Enabled {
		kafkaConfig := messaging.KafkaConfig{
			Brokers:       cfg.Kafka.Brokers,
			GroupID:       cfg.Kafka.GroupID,
			BatchSize:     cfg.Kafka.BatchSize,
			BatchTimeout:  cfg.Kafka.BatchTimeout,
			RetryAttempts: cfg.Kafka.RetryAttempts,
		}

		kafkaClient, err = messaging.NewKafkaClient(kafkaConfig, logger)
		if err != nil {
			logger.Warn("Failed to connect to Kafka - continuing without event streaming", zap.Error(err))
			kafkaClient = nil // Graceful degradation
		} else {
			defer kafkaClient.Close()
			logger.Info("Kafka client connected successfully")
		}
	} else {
		logger.Info("Kafka is disabled in configuration")
	}

	// Initialize HTTP client for service communication
	httpClient := &http.Client{
		Timeout: 30 * time.Second,
	}

	// Initialize handlers
	gatewayHandlers := handlers.NewGatewayHandlers(cfg, httpClient, kafkaClient, logger)

	// Create router
	router := gin.New()

	// Configure max multipart memory for OCR image uploads
	// Allow up to 32MB for image uploads (compressed images should be under 2MB)
	router.MaxMultipartMemory = 32 << 20 // 32 MiB

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware()) // Includes Request ID handling
	router.Use(middleware.CORSMiddleware())
	router.Use(middleware.VersionHeadersMiddleware(redisCache)) // X-Min-App-Version + X-Latest-App-Version on all responses
	// NOTE: GzipMiddleware NOT registered on gateway — would double-compress upstream
	// responses that already arrive with Content-Encoding: gzip from inventory/saas
	// services. Each upstream service applies its own GzipMiddleware; gateway forwards
	// the compressed body + Content-Encoding header through unchanged.

	// Initialize GraphQL server (if enabled)
	var graphqlServer *graphql.GraphQLServer
	if cfg.GraphQL.Enabled {
		graphqlConfig := &graphql.GraphQLConfig{
			EnablePlayground:    cfg.GraphQL.EnablePlayground,
			EnableIntrospection: cfg.GraphQL.EnableIntrospection,
			MaxComplexity:       cfg.GraphQL.MaxComplexity,
			MaxDepth:            cfg.GraphQL.MaxDepth,
			QueryCacheTTL:       5 * time.Minute,
			RateLimitPerMinute:  cfg.GraphQL.RateLimitPerMinute,
			UploadMaxSize:       32 << 20, // 32 MiB
			WebSocketEnabled:    cfg.GraphQL.WebSocketEnabled,
		}

		graphqlServer, err = graphql.NewGraphQLServer(db.DB, redisClient, logger, graphqlConfig)
		if err != nil {
			logger.Warn("Failed to initialize GraphQL server - continuing without GraphQL", zap.Error(err))
		} else {
			logger.Info("GraphQL server initialized successfully",
				zap.Bool("playground", cfg.GraphQL.EnablePlayground),
				zap.Bool("websocket", cfg.GraphQL.WebSocketEnabled))
		}
	} else {
		logger.Info("GraphQL is disabled in configuration")
	}

	// Setup routes
	routes.SetupRoutes(router, cfg, redisCache, gatewayHandlers)

	// SDUI (Server-Driven UI) routes
	sduiHandler := handlers.NewSDUIHandler(db.DB, redisCache, logger)

	// Auto-migrate SDUI tables + App Version Config
	db.DB.AutoMigrate(&handlers.AppBanner{}, &handlers.TenantTheme{}, &handlers.AppVersion{}, &handlers.SDUIScreenConfig{}, &handlers.HelpRequest{}, &handlers.AnalyticsEvent{}, &handlers.AppVersionConfig{})

	// Version Check handler (public — no auth required)
	versionCheckHandler := handlers.NewVersionCheckHandler(db.DB, redisCache, logger)
	router.GET("/api/app/version-check", versionCheckHandler.VersionCheck)

	// Public SDUI routes (legacy version check kept for backward compat)
	router.GET("/api/sdui/version-check", sduiHandler.VersionCheck)

	// Protected SDUI routes
	sduiGroup := router.Group("/api/sdui")
	sduiGroup.Use(middleware.AuthMiddleware(cfg.JWT, redisCache))
	sduiGroup.Use(middleware.TenantMiddleware())
	{
		sduiGroup.GET("/config", sduiHandler.GetAppConfig)
		sduiGroup.GET("/screen/:screen_id", sduiHandler.GetScreen)
		sduiGroup.GET("/banners", sduiHandler.GetBanners)

		// 1-click help
		sduiGroup.POST("/help/request", sduiHandler.RequestHelp)
		sduiGroup.GET("/help/requests", sduiHandler.GetHelpRequests)
		sduiGroup.PUT("/help/requests/:id", sduiHandler.UpdateHelpRequest)

		// User analytics & tracking
		sduiGroup.POST("/analytics/events", sduiHandler.TrackEvents)
	}

	// Protected app config routes (admin only)
	appGroup := router.Group("/api/app")
	appGroup.Use(middleware.AuthMiddleware(cfg.JWT, redisCache))
	{
		appGroup.PUT("/version-config", versionCheckHandler.UpdateVersionConfig)
		appGroup.GET("/version-config", versionCheckHandler.GetVersionConfig)
	}

	logger.Info("SDUI routes registered at /api/sdui/*")

	// Register GraphQL routes if enabled
	if graphqlServer != nil {
		apiGroup := router.Group("/api")
		graphqlServer.RegisterRoutes(apiGroup)
		logger.Info("GraphQL routes registered at /api/graphql")
	}

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
