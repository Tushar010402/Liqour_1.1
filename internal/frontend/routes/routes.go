package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/frontend/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

// SetupRoutes configures all frontend web routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, frontendHandlers *handlers.FrontendHandlers) {
	// Root redirect
	router.GET("/", func(c *gin.Context) {
		c.Redirect(http.StatusFound, "/dashboard")
	})

	// Authentication routes
	auth := router.Group("/")
	{
		auth.GET("/login", frontendHandlers.ShowLogin)
		auth.POST("/login", frontendHandlers.HandleLogin)
		auth.GET("/logout", frontendHandlers.HandleLogout)
		auth.POST("/logout", frontendHandlers.HandleLogout)
	}

	// Dashboard routes
	router.GET("/dashboard", frontendHandlers.ShowDashboard)

	// Sales routes
	sales := router.Group("/sales")
	{
		// Daily Sales Management (Critical bulk entry feature)
		sales.GET("/daily", frontendHandlers.ShowDailySales)
		sales.GET("/daily/entry", frontendHandlers.ShowDailySalesEntry)
		
		// Individual Sales
		sales.GET("/", frontendHandlers.ShowSales)
		sales.GET("/list", frontendHandlers.ShowSales)
		
		// TODO: Add more sales routes
		sales.GET("/returns", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Sales Returns - Coming Soon",
				"message": "Sales returns functionality is under development",
			})
		})
		
		sales.GET("/reports", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Sales Reports - Coming Soon",
				"message": "Sales reports functionality is under development",
			})
		})
	}

	// Inventory routes
	inventory := router.Group("/inventory")
	{
		// Products
		inventory.GET("/products", frontendHandlers.ShowProducts)
		inventory.GET("/", frontendHandlers.ShowProducts) // Default to products
		
		// Stock Management
		inventory.GET("/stock", frontendHandlers.ShowStock)
		inventory.GET("/stocks", frontendHandlers.ShowStock)
		
		// TODO: Add more inventory routes
		inventory.GET("/categories", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Categories - Coming Soon",
				"message": "Category management interface is under development",
			})
		})
		
		inventory.GET("/brands", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Brands - Coming Soon",
				"message": "Brand management interface is under development",
			})
		})
		
		inventory.GET("/purchases", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Purchases - Coming Soon",
				"message": "Purchase management interface is under development",
			})
		})
	}

	// Finance routes
	finance := router.Group("/finance")
	{
		// Expenses
		finance.GET("/expenses", frontendHandlers.ShowExpenses)
		finance.GET("/", frontendHandlers.ShowExpenses) // Default to expenses
		
		// Money Collections (Critical: Assistant Manager 15-minute deadline)
		finance.GET("/collections", frontendHandlers.ShowMoneyCollections)
		finance.GET("/money-collections", frontendHandlers.ShowMoneyCollections)
		
		// TODO: Add more finance routes
		finance.GET("/vendors", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Vendors - Coming Soon",
				"message": "Vendor management interface is under development",
			})
		})
		
		finance.GET("/reports", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Finance Reports - Coming Soon",
				"message": "Financial reports interface is under development",
			})
		})
		
		finance.GET("/dashboard", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Finance Dashboard - Coming Soon",
				"message": "Finance dashboard interface is under development",
			})
		})
	}

	// Admin/Management routes
	admin := router.Group("/admin")
	{
		admin.GET("/", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Admin Panel - Coming Soon",
				"message": "Admin panel interface is under development",
			})
		})
		
		admin.GET("/users", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "User Management - Coming Soon",
				"message": "User management interface is under development",
			})
		})
		
		admin.GET("/shops", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Shop Management - Coming Soon",
				"message": "Shop management interface is under development",
			})
		})
		
		admin.GET("/settings", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Settings - Coming Soon",
				"message": "Settings interface is under development",
			})
		})
	}

	// Reports routes (Global reporting)
	reports := router.Group("/reports")
	{
		reports.GET("/", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Reports - Coming Soon",
				"message": "Comprehensive reporting interface is under development",
			})
		})
		
		reports.GET("/dashboard", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Reports Dashboard - Coming Soon",
				"message": "Reports dashboard is under development",
			})
		})
		
		reports.GET("/analytics", func(c *gin.Context) {
			c.HTML(http.StatusOK, "construction.html", gin.H{
				"title": "Analytics - Coming Soon",
				"message": "Analytics interface is under development",
			})
		})
	}

	// API routes for AJAX calls
	api := router.Group("/api")
	{
		// Health check
		api.GET("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status": "healthy",
				"service": "frontend",
			})
		})
		
		// TODO: Add AJAX endpoints for dynamic content loading
		api.GET("/products/search", func(c *gin.Context) {
			c.JSON(http.StatusNotImplemented, gin.H{
				"message": "Product search API endpoint not implemented yet",
			})
		})
		
		api.POST("/sales/daily", func(c *gin.Context) {
			c.JSON(http.StatusNotImplemented, gin.H{
				"message": "Daily sales creation API endpoint not implemented yet",
			})
		})
	}

	// Error handling
	router.NoRoute(func(c *gin.Context) {
		c.HTML(http.StatusNotFound, "404.html", gin.H{
			"title": "Page Not Found",
		})
	})

	// Handle method not allowed
	router.NoMethod(func(c *gin.Context) {
		c.HTML(http.StatusMethodNotAllowed, "error.html", gin.H{
			"title": "Method Not Allowed",
			"error": "The requested method is not allowed for this resource",
		})
	})
}