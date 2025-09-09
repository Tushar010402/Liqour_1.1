package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/finance/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all finance service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, financeHandlers *handlers.FinanceHandlers) {
	// Health check
	router.GET("/health", financeHandlers.Health)

	// All routes require authentication and tenant isolation
	api := router.Group("/api")
	api.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	api.Use(middleware.TenantMiddleware())

	// Vendor Management Routes (Core supplier management)
	vendors := api.Group("/vendors")
	{
		vendors.GET("", financeHandlers.GetVendors)
		vendors.POST("", middleware.RoleMiddleware("manager", "admin"), financeHandlers.CreateVendor)
		vendors.GET("/:id", financeHandlers.GetVendorByID)
		vendors.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), financeHandlers.UpdateVendor)
		vendors.DELETE("/:id", middleware.RoleMiddleware("admin"), financeHandlers.DeleteVendor)
		
		// Vendor bank accounts
		vendors.POST("/:id/bank-accounts", middleware.RoleMiddleware("manager", "admin"), financeHandlers.AddVendorBankAccount)
		
		// Vendor transactions (payments/purchases)
		vendors.POST("/transactions", middleware.RoleMiddleware("manager", "admin"), financeHandlers.CreateVendorTransaction)
		vendors.GET("/:id/transactions", financeHandlers.GetVendorTransactions)
	}

	// Expense Management Routes (Business expenses)
	expenses := api.Group("/expenses")
	{
		expenses.GET("", financeHandlers.GetExpenses)
		expenses.POST("", middleware.RoleMiddleware("salesman", "manager", "admin"), financeHandlers.CreateExpense)
		expenses.GET("/:id", financeHandlers.GetExpenseByID)
		expenses.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), financeHandlers.UpdateExpense)
		expenses.DELETE("/:id", middleware.RoleMiddleware("admin"), financeHandlers.DeleteExpense)
	}

	// Expense Category Routes
	expenseCategories := api.Group("/expense-categories")
	{
		expenseCategories.GET("", financeHandlers.GetExpenseCategories)
		expenseCategories.POST("", middleware.RoleMiddleware("manager", "admin"), financeHandlers.CreateExpenseCategory)
	}

	// Assistant Manager Routes (Critical: 15-minute money collection approval)
	assistantManager := api.Group("/assistant-manager")
	assistantManager.Use(middleware.RoleMiddleware("assistant_manager", "manager", "admin"))
	{
		// Money Collection (15-minute deadline critical business logic)
		collections := assistantManager.Group("/money-collections")
		{
			collections.GET("", financeHandlers.GetMoneyCollections)
			collections.POST("", financeHandlers.CreateMoneyCollection)
			collections.GET("/:id", financeHandlers.GetMoneyCollectionByID)
			collections.POST("/:id/approve", middleware.RoleMiddleware("manager", "admin"), financeHandlers.ApproveMoneyCollection)
			collections.POST("/:id/reject", middleware.RoleMiddleware("manager", "admin"), financeHandlers.RejectMoneyCollection)
		}

		// Assistant Manager Expenses
		assistantExpenses := assistantManager.Group("/expenses")
		{
			assistantExpenses.POST("", financeHandlers.CreateAssistantManagerExpense)
		}

		// Assistant Manager Finance Records
		assistantFinance := assistantManager.Group("/finance")
		{
			assistantFinance.POST("", financeHandlers.CreateAssistantManagerFinance)
		}
	}

	// Financial Reports and Analytics
	reports := api.Group("/reports")
	{
		reports.GET("/expense-summary", financeHandlers.GetExpenseSummary)
		
		// TODO: Add more financial reports
		reports.GET("/vendor-aging", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Vendor aging report not implemented yet"})
		})
		reports.GET("/cash-flow", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Cash flow report not implemented yet"})
		})
		reports.GET("/profit-loss", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Profit & Loss report not implemented yet"})
		})
		reports.GET("/balance-sheet", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Balance sheet not implemented yet"})
		})
	}

	// Dashboard Summary (Financial overview)
	dashboard := api.Group("/dashboard")
	{
		dashboard.GET("/summary", func(c *gin.Context) {
			c.JSON(501, gin.H{"message": "Financial dashboard summary not implemented yet"})
		})
		dashboard.GET("/collections-due", financeHandlers.GetMoneyCollections) // Overdue collections
	}
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, financeHandlers *handlers.FinanceHandlers) {
	// Health check (no auth required)
	router.GET("/health", financeHandlers.Health)

	// Extract user context from headers (set by API Gateway)
	router.Use(func(c *gin.Context) {
		if userID := c.GetHeader("X-User-ID"); userID != "" {
			c.Set("user_id", userID)
		}
		if tenantID := c.GetHeader("X-Tenant-ID"); tenantID != "" {
			c.Set("tenant_id", tenantID)
		}
		if role := c.GetHeader("X-User-Role"); role != "" {
			c.Set("role", role)
		}
		c.Next()
	})

	// Vendor Routes
	router.GET("/vendors", financeHandlers.GetVendors)
	router.POST("/vendors", financeHandlers.CreateVendor)
	router.GET("/vendors/:id", financeHandlers.GetVendorByID)
	router.PUT("/vendors/:id", financeHandlers.UpdateVendor)
	router.DELETE("/vendors/:id", financeHandlers.DeleteVendor)
	router.POST("/vendors/:id/bank-accounts", financeHandlers.AddVendorBankAccount)
	router.POST("/vendors/transactions", financeHandlers.CreateVendorTransaction)
	router.GET("/vendors/:id/transactions", financeHandlers.GetVendorTransactions)

	// Expense Routes
	router.GET("/expenses", financeHandlers.GetExpenses)
	router.POST("/expenses", financeHandlers.CreateExpense)
	router.GET("/expenses/:id", financeHandlers.GetExpenseByID)
	router.PUT("/expenses/:id", financeHandlers.UpdateExpense)
	router.DELETE("/expenses/:id", financeHandlers.DeleteExpense)

	// Expense Category Routes
	router.GET("/expense-categories", financeHandlers.GetExpenseCategories)
	router.POST("/expense-categories", financeHandlers.CreateExpenseCategory)

	// Assistant Manager Routes
	router.GET("/assistant-manager/money-collections", financeHandlers.GetMoneyCollections)
	router.POST("/assistant-manager/money-collections", financeHandlers.CreateMoneyCollection)
	router.GET("/assistant-manager/money-collections/:id", financeHandlers.GetMoneyCollectionByID)
	router.POST("/assistant-manager/money-collections/:id/approve", financeHandlers.ApproveMoneyCollection)
	router.POST("/assistant-manager/money-collections/:id/reject", financeHandlers.RejectMoneyCollection)
	router.POST("/assistant-manager/expenses", financeHandlers.CreateAssistantManagerExpense)
	router.POST("/assistant-manager/finance", financeHandlers.CreateAssistantManagerFinance)

	// Reports Routes
	router.GET("/reports/expense-summary", financeHandlers.GetExpenseSummary)
}