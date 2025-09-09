package main

import (
	"context"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/frontend/handlers"
	"github.com/liquorpro/go-backend/internal/frontend/routes"
	"github.com/liquorpro/go-backend/internal/frontend/services"
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

	// Initialize services
	frontendService := services.NewFrontendService(db, redisCache, cfg)

	// Initialize handlers
	frontendHandlers := handlers.NewFrontendHandlers(frontendService)

	// Create router
	router := gin.New()

	// Add middleware
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware())
	router.Use(middleware.RequestIDMiddleware())
	router.Use(middleware.CORSMiddleware())

	// Setup custom template functions
	router.SetFuncMap(template.FuncMap{
		"formatDate": func(t time.Time) string {
			return t.Format("2006-01-02")
		},
		"formatDateTime": func(t time.Time) string {
			return t.Format("2006-01-02 15:04:05")
		},
		"formatCurrency": func(amount float64) string {
			return fmt.Sprintf("₹%.2f", amount)
		},
		"add": func(a, b int) int {
			return a + b
		},
		"upper": strings.ToUpper,
		"lower": strings.ToLower,
		"title": strings.Title,
	})

	// Load HTML templates
	templatesPath := filepath.Join("web", "templates", "**", "*.html")
	router.LoadHTMLGlob(templatesPath)

	// Serve static files
	router.Static("/static", "./web/static")
	router.Static("/assets", "./web/assets")

	// Setup routes
	routes.SetupRoutes(router, cfg, redisCache, frontendHandlers)

	// Start server
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Services.Frontend.Host, cfg.Services.Frontend.Port),
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
		IdleTimeout:  time.Duration(cfg.Server.IdleTimeout) * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Frontend service starting on %s:%d", cfg.Services.Frontend.Host, cfg.Services.Frontend.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Frontend service...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Frontend service stopped")
}