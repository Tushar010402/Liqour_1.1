package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/finance/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all finance service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, financeHandlers *handlers.FinanceHandlers, cashHandlers *handlers.CashHandlers, bankHandlers *handlers.BankAccountHandlers) {
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

		// Advanced Financial Reports
		reports.GET("/vendor-aging", financeHandlers.GetVendorAgingReport)
		reports.GET("/cash-flow", financeHandlers.GetCashFlowReport)
		reports.GET("/profit-loss", financeHandlers.GetProfitLossReport)
		reports.GET("/balance-sheet", financeHandlers.GetBalanceSheetReport)
	}

	// Dashboard Summary (Financial overview)
	dashboard := api.Group("/dashboard")
	{
		dashboard.GET("/summary", financeHandlers.GetFinancialDashboard)
		dashboard.GET("/metrics", financeHandlers.GetFinancialDashboard) // Alias for Flutter app
		dashboard.GET("/collections-due", financeHandlers.GetMoneyCollections) // Overdue collections
	}

	// Cash Management Routes (Hierarchical cash tracking and bank submissions)
	cash := api.Group("/finance/cash")
	{
		// Cash Balance Queries
		cash.GET("/balance", cashHandlers.GetCashBalance)             // Get current user's cash balance
		cash.GET("/holding", cashHandlers.GetCashHolding)             // Get detailed cash holding info
		cash.GET("/team-balances", cashHandlers.GetTeamBalances)      // Get subordinates' cash balances (hierarchical)
		cash.GET("/tenant-users", cashHandlers.GetTenantUsers)        // Get tenant users for cash requests (NO amounts shown)

		// Cash Collection (Manager, Assistant Manager, Executive from subordinates)
		cash.POST("/collect", middleware.RoleMiddleware("executive", "assistant_manager", "manager", "admin"), cashHandlers.CollectCash)
		cash.GET("/collections", cashHandlers.GetCollections)         // Get collection history
		cash.GET("/collections/pending", cashHandlers.GetPendingCollections) // Get pending approval requests
		cash.POST("/collections/:id/approve", cashHandlers.ApproveCollectionRequest) // Approve collection within 10-min deadline
		cash.POST("/collections/:id/reject", cashHandlers.RejectCollectionRequest)   // Reject collection request

		// Cash Request System (Any user can request cash from another user)
		cash.POST("/request", cashHandlers.CreateCashRequest)         // Create cash request
		cash.GET("/requests", cashHandlers.GetCashRequests)           // Get cash requests with filters
		cash.GET("/requests/pending", cashHandlers.GetPendingCashRequests) // Get pending requests to approve
		cash.POST("/requests/:id/approve", cashHandlers.ApproveCashRequestHandler) // Approve cash request
		cash.POST("/requests/:id/reject", cashHandlers.RejectCashRequestHandler)   // Reject cash request

		// Cash Submission to Bank (with denomination breakdown and photo evidence)
		cash.POST("/upload-receipt", cashHandlers.UploadReceiptPhoto) // Upload receipt photo (optional - returns placeholder URL)
		cash.POST("/submit", cashHandlers.SubmitCash)                 // Submit cash to bank
		cash.GET("/submissions", cashHandlers.GetSubmissions)         // Get submission history

		// Approval Workflow (Manager and above can approve)
		cash.POST("/submissions/:id/approve", middleware.RoleMiddleware("manager", "admin"), cashHandlers.ApproveSubmission)
		cash.POST("/submissions/:id/reject", middleware.RoleMiddleware("manager", "admin"), cashHandlers.RejectSubmission)

		// Complete Audit Trail
		cash.GET("/history", cashHandlers.GetCashHistory)             // Get complete cash transaction history
	}

	// Bank Account Management Routes (Tenant bank accounts with OD tracking)
	bankAccounts := api.Group("/finance/bank-accounts")
	{
		// Bank Account CRUD
		bankAccounts.GET("", bankHandlers.GetBankAccounts)                                            // List all bank accounts
		bankAccounts.GET("/default", bankHandlers.GetDefaultBankAccount)                             // Get default account
		bankAccounts.POST("", middleware.RoleMiddleware("manager", "admin"), bankHandlers.CreateBankAccount) // Create account
		bankAccounts.GET("/:id", bankHandlers.GetBankAccount)                                        // Get single account
		bankAccounts.PUT("/:id", middleware.RoleMiddleware("manager", "admin"), bankHandlers.UpdateBankAccount) // Update account
		bankAccounts.DELETE("/:id", middleware.RoleMiddleware("admin"), bankHandlers.DeleteBankAccount) // Delete account

		// Bank Transactions
		bankAccounts.POST("/:id/transactions", middleware.RoleMiddleware("manager", "admin"), bankHandlers.RecordBankTransaction) // Record transaction
		bankAccounts.GET("/:id/transactions", bankHandlers.GetBankTransactions)               // List transactions for account

		// All Transactions (across all accounts)
		bankAccounts.GET("/transactions", bankHandlers.GetBankTransactions)                   // List all transactions

		// Bank Reconciliations
		bankAccounts.POST("/:id/reconciliations", middleware.RoleMiddleware("manager", "admin"), bankHandlers.CreateReconciliation) // Create reconciliation
		bankAccounts.GET("/:id/reconciliations", bankHandlers.GetReconciliations)             // List reconciliations for account

		// Account Summary and Analytics
		bankAccounts.GET("/:id/summary", bankHandlers.GetAccountSummary)                      // Get account summary with stats
	}
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, financeHandlers *handlers.FinanceHandlers, cashHandlers *handlers.CashHandlers, bankHandlers *handlers.BankAccountHandlers) {
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

	// Gateway strips /api/finance, so routes are at root level
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
	router.GET("/reports/vendor-aging", financeHandlers.GetVendorAgingReport)
	router.GET("/reports/cash-flow", financeHandlers.GetCashFlowReport)
	router.GET("/reports/profit-loss", financeHandlers.GetProfitLossReport)
	router.GET("/reports/balance-sheet", financeHandlers.GetBalanceSheetReport)

	// Dashboard Routes
	router.GET("/dashboard/summary", financeHandlers.GetFinancialDashboard)
	router.GET("/dashboard/metrics", financeHandlers.GetFinancialDashboard) // Alias for Flutter app
	router.GET("/dashboard/collections-due", financeHandlers.GetMoneyCollections)

	// Cash Management Routes
	router.GET("/cash/balance", cashHandlers.GetCashBalance)
	router.GET("/cash/holding", cashHandlers.GetCashHolding)
	router.GET("/cash/team-balances", cashHandlers.GetTeamBalances)
	router.GET("/cash/tenant-users", cashHandlers.GetTenantUsers)
	router.POST("/cash/collect", cashHandlers.CollectCash)
	router.GET("/cash/collections", cashHandlers.GetCollections)
	router.GET("/cash/collections/pending", cashHandlers.GetPendingCollections)
	router.POST("/cash/collections/:id/approve", cashHandlers.ApproveCollectionRequest)
	router.POST("/cash/collections/:id/reject", cashHandlers.RejectCollectionRequest)
	router.POST("/cash/request", cashHandlers.CreateCashRequest)
	router.GET("/cash/requests", cashHandlers.GetCashRequests)
	router.GET("/cash/requests/pending", cashHandlers.GetPendingCashRequests)
	router.POST("/cash/requests/:id/approve", cashHandlers.ApproveCashRequestHandler)
	router.POST("/cash/requests/:id/reject", cashHandlers.RejectCashRequestHandler)
	router.POST("/cash/upload-receipt", cashHandlers.UploadReceiptPhoto)
	router.POST("/cash/submit", cashHandlers.SubmitCash)
	router.GET("/cash/submissions", cashHandlers.GetSubmissions)
	router.POST("/cash/submissions/:id/approve", cashHandlers.ApproveSubmission)
	router.POST("/cash/submissions/:id/reject", cashHandlers.RejectSubmission)
	router.GET("/cash/history", cashHandlers.GetCashHistory)

	// Bank Account Management Routes
	router.GET("/bank-accounts", bankHandlers.GetBankAccounts)
	router.GET("/bank-accounts/default", bankHandlers.GetDefaultBankAccount)
	router.POST("/bank-accounts", bankHandlers.CreateBankAccount)
	router.GET("/bank-accounts/:id", bankHandlers.GetBankAccount)
	router.PUT("/bank-accounts/:id", bankHandlers.UpdateBankAccount)
	router.DELETE("/bank-accounts/:id", bankHandlers.DeleteBankAccount)
	router.POST("/bank-accounts/:id/transactions", bankHandlers.RecordBankTransaction)
	router.GET("/bank-accounts/:id/transactions", bankHandlers.GetBankTransactions)
	router.GET("/bank-accounts/transactions", bankHandlers.GetBankTransactions)
	router.POST("/bank-accounts/:id/reconciliations", bankHandlers.CreateReconciliation)
	router.GET("/bank-accounts/:id/reconciliations", bankHandlers.GetReconciliations)
	router.GET("/bank-accounts/:id/summary", bankHandlers.GetAccountSummary)
}
