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
	"github.com/go-redis/redis/v8"
	"go.uber.org/zap"
	"gorm.io/gorm"

	"github.com/liquorpro/config"
	"github.com/liquorpro/internal/gateway/handlers"
	"github.com/liquorpro/internal/gateway/routes"
	"github.com/liquorpro/pkg/database"
	"github.com/liquorpro/pkg/middleware"
	"github.com/liquorpro/pkg/monitoring"
	"github.com/liquorpro/pkg/queue"
	"github.com/liquorpro/pkg/shared/logger"
	"github.com/liquorpro/pkg/versioning"
	"github.com/liquorpro/pkg/webhook"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize logger
	zapLogger, err := logger.NewLogger(cfg.Log.Level, cfg.Log.Format == "json")
	if err != nil {
		log.Fatalf("Failed to initialize logger: %v", err)
	}
	defer zapLogger.Sync()

	// Initialize distributed tracing
	if err := monitoring.InitTracing("gateway", cfg.Jaeger.Endpoint); err != nil {
		zapLogger.Error("Failed to initialize tracing", zap.Error(err))
	}
	defer monitoring.CloseTracing()

	// Initialize database with connection pooling
	dbManager, err := database.NewDatabaseManager(database.ConnectionConfig{
		Host:            cfg.Database.Host,
		Port:            cfg.Database.Port,
		User:            cfg.Database.User,
		Password:        cfg.Database.Password,
		DBName:          cfg.Database.Name,
		SSLMode:         cfg.Database.SSLMode,
		MaxOpenConns:    25,
		MaxIdleConns:    10,
		ConnMaxLifetime: time.Hour,
		ConnMaxIdleTime: 30 * time.Minute,
		SlowThreshold:   200 * time.Millisecond,
		LogLevel:        "warn",
	}, "gateway", zapLogger)
	if err != nil {
		zapLogger.Fatal("Failed to initialize database", zap.Error(err))
	}
	defer dbManager.Close()

	// Initialize Redis client
	redisClient := redis.NewClient(&redis.Options{
		Addr:         fmt.Sprintf("%s:%d", cfg.Redis.Host, cfg.Redis.Port),
		Password:     cfg.Redis.Password,
		DB:           0,
		MaxRetries:   3,
		PoolSize:     10,
		MinIdleConns: 5,
		PoolTimeout:  4 * time.Second,
	})
	defer redisClient.Close()

	// Test Redis connection
	if err := redisClient.Ping(context.Background()).Err(); err != nil {
		zapLogger.Error("Failed to connect to Redis", zap.Error(err))
	}

	// Initialize circuit breaker manager
	circuitBreakerManager := middleware.NewCircuitBreakerManager(zapLogger)
	
	// Register circuit breakers for external services
	circuitBreakerManager.Register("database", middleware.CircuitBreakerConfig{
		MaxFailures:      5,
		ResetTimeout:     30 * time.Second,
		SuccessThreshold: 3,
		Timeout:          5 * time.Second,
	}, zapLogger)
	
	circuitBreakerManager.Register("redis", middleware.CircuitBreakerConfig{
		MaxFailures:      3,
		ResetTimeout:     15 * time.Second,
		SuccessThreshold: 2,
		Timeout:          3 * time.Second,
	}, zapLogger)

	// Initialize queue manager
	queueManager := queue.NewQueueManager(redisClient, zapLogger)
	
	// Register message handlers
	if err := queueManager.RegisterStream(queue.StreamConfig{
		StreamName:    "user_events",
		ConsumerGroup: "gateway_consumers",
		ConsumerName:  "gateway_worker",
		MaxRetries:    3,
		RetryDelay:    30 * time.Second,
		BatchSize:     10,
	}, handleUserEvents); err != nil {
		zapLogger.Error("Failed to register user events stream", zap.Error(err))
	}

	// Start queue consumers
	if err := queueManager.StartAllConsumers(); err != nil {
		zapLogger.Error("Failed to start queue consumers", zap.Error(err))
	}
	defer queueManager.Stop()

	// Initialize webhook manager
	webhookManager := webhook.NewWebhookManager(dbManager.GetDB(), zapLogger, 5)

	// Initialize API versioning
	versionManager, err := versioning.NewVersionManager(
		"v1.0.0",
		[]string{"v1.0.0", "v1.1.0"},
		zapLogger,
	)
	if err != nil {
		zapLogger.Fatal("Failed to initialize version manager", zap.Error(err))
	}

	// Deprecate old versions if needed
	versionManager.DeprecateVersion("v1.0.0", "Please upgrade to v1.1.0. This version will be removed in 3 months.")

	// Set Gin mode based on environment
	if cfg.App.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize Gin router
	router := gin.New()

	// Add middleware stack
	router.Use(gin.Recovery())
	
	// Custom request ID middleware
	router.Use(func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = fmt.Sprintf("req_%d", time.Now().UnixNano())
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	})

	// Monitoring middleware
	router.Use(monitoring.PrometheusMiddleware("gateway"))
	router.Use(monitoring.TracingMiddleware("gateway"))

	// API versioning middleware
	router.Use(versionManager.VersioningMiddleware())
	router.Use(versionManager.ContentNegotiation())

	// Rate limiting middleware
	rateLimitConfig := middleware.RateLimitConfig{
		Global: struct {
			Enabled bool   `yaml:"enabled" json:"enabled"`
			Limit   int    `yaml:"limit" json:"limit"`
			Window  string `yaml:"window" json:"window"`
		}{
			Enabled: true,
			Limit:   1000,
			Window:  "1m",
		},
		PerIP: struct {
			Enabled bool   `yaml:"enabled" json:"enabled"`
			Limit   int    `yaml:"limit" json:"limit"`
			Window  string `yaml:"window" json:"window"`
		}{
			Enabled: true,
			Limit:   100,
			Window:  "1m",
		},
		PerUser: struct {
			Enabled bool   `yaml:"enabled" json:"enabled"`
			Limit   int    `yaml:"limit" json:"limit"`
			Window  string `yaml:"window" json:"window"`
		}{
			Enabled: true,
			Limit:   1000,
			Window:  "1m",
		},
		PerTenant: struct {
			Enabled bool   `yaml:"enabled" json:"enabled"`
			Limit   int    `yaml:"limit" json:"limit"`
			Window  string `yaml:"window" json:"window"`
		}{
			Enabled: true,
			Limit:   5000,
			Window:  "1m",
		},
	}
	router.Use(middleware.RateLimitMiddleware(redisClient, rateLimitConfig, zapLogger))

	// Circuit breaker middleware for critical paths
	router.Use(middleware.CircuitBreakerMiddleware(circuitBreakerManager, "gateway"))

	// Security headers
	router.Use(func(c *gin.Context) {
		c.Header("X-Frame-Options", "DENY")
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-XSS-Protection", "1; mode=block")
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Content-Security-Policy", "default-src 'self'")
		c.Next()
	})

	// Initialize handlers with all dependencies
	gatewayHandlers := handlers.NewGatewayHandlers(
		cfg,
		zapLogger,
		dbManager.GetDB(),
		redisClient,
		circuitBreakerManager,
		queueManager,
		webhookManager,
	)

	// Setup routes
	routes.SetupGatewayRoutes(router, gatewayHandlers, versionManager)

	// Setup monitoring endpoints
	router.GET("/metrics", monitoring.PrometheusHandler())
	router.GET("/health", func(c *gin.Context) {
		// Comprehensive health check
		health := map[string]interface{}{
			"service":   "gateway",
			"status":    "healthy",
			"timestamp": time.Now().ISO8601(),
			"version":   cfg.App.Version,
			"checks": map[string]interface{}{
				"database": checkDatabaseHealth(dbManager),
				"redis":    checkRedisHealth(redisClient),
			},
		}
		
		// Check if any dependency is unhealthy
		checks := health["checks"].(map[string]interface{})
		overallHealthy := true
		for _, check := range checks {
			if checkMap, ok := check.(map[string]interface{}); ok {
				if status, exists := checkMap["status"]; exists && status != "healthy" {
					overallHealthy = false
					break
				}
			}
		}
		
		if !overallHealthy {
			health["status"] = "degraded"
			c.JSON(503, health)
		} else {
			c.JSON(200, health)
		}
	})

	// Setup webhook management routes
	webhookGroup := router.Group("/api/v1")
	webhookManager.SetupRoutes(webhookGroup)

	// Setup versioning routes
	versionManager.SetupVersioningRoutes(router)

	// Start metrics server on separate port
	monitoring.StartMetricsServer("9091", "gateway")

	// Create HTTP server
	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start server in goroutine
	go func() {
		zapLogger.Info("Starting gateway server",
			zap.String("environment", cfg.App.Environment),
			zap.Int("port", cfg.Server.Port),
			zap.String("version", cfg.App.Version),
		)
		
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			zapLogger.Fatal("Failed to start server", zap.Error(err))
		}
	}()

	// Wait for interrupt signal for graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	zapLogger.Info("Shutting down server...")

	// Create shutdown context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Shutdown server
	if err := srv.Shutdown(ctx); err != nil {
		zapLogger.Error("Server forced to shutdown", zap.Error(err))
	}

	zapLogger.Info("Server exited")
}

// handleUserEvents handles user-related events from the queue
func handleUserEvents(ctx context.Context, message *queue.Message) error {
	log.Printf("Processing user event: %s", message.Data)
	// Process the event...
	return nil
}

// checkDatabaseHealth checks database connectivity
func checkDatabaseHealth(dbManager *database.DatabaseManager) map[string]interface{} {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	if err := dbManager.HealthCheck(ctx); err != nil {
		return map[string]interface{}{
			"status": "unhealthy",
			"error":  err.Error(),
		}
	}
	
	stats := dbManager.GetStats()
	return map[string]interface{}{
		"status":           "healthy",
		"open_connections": stats.OpenConnections,
		"in_use":          stats.InUse,
		"idle":            stats.Idle,
	}
}

// checkRedisHealth checks Redis connectivity
func checkRedisHealth(client *redis.Client) map[string]interface{} {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	if err := client.Ping(ctx).Err(); err != nil {
		return map[string]interface{}{
			"status": "unhealthy",
			"error":  err.Error(),
		}
	}
	
	poolStats := client.PoolStats()
	return map[string]interface{}{
		"status":        "healthy",
		"total_conns":   poolStats.TotalConns,
		"idle_conns":    poolStats.IdleConns,
		"stale_conns":   poolStats.StaleConns,
	}
}