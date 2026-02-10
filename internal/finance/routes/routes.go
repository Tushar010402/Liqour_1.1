package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/finance/handlers"
	"github.com/liquorpro/go-backend/pkg/monitoring"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all finance service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, financeHandlers *handlers.FinanceHandlers) {
	// Prometheus metrics
	router.Use(monitoring.PrometheusMiddleware("finance"))
	router.GET("/metrics", monitoring.PrometheusHandler())

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

		// Vendor ledger with running balance (full ledger view)
		vendors.GET("/:id/ledger", financeHandlers.GetVendorLedger)
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

	// Executive Finance Routes (Cash handovers and expense claims)
	executiveFinance := api.Group("/executive-finance")
	executiveFinance.Use(middleware.RoleMiddleware("salesman", "executive", "manager", "admin"))
	{
		executiveFinance.GET("", financeHandlers.ListExecutiveFinance)
		executiveFinance.POST("", financeHandlers.CreateExecutiveFinance)
		executiveFinance.GET("/:id", financeHandlers.GetExecutiveFinanceByID)
		executiveFinance.POST("/:id/approve", middleware.RoleMiddleware("executive", "manager", "admin"), financeHandlers.ApproveExecutiveFinance)
		executiveFinance.POST("/:id/reject", middleware.RoleMiddleware("executive", "manager", "admin"), financeHandlers.RejectExecutiveFinance)
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
		reports.GET("/cash-history", financeHandlers.GetCashFlowReport) // Alias to cash-flow
	}

	// Dashboard Summary (Financial overview)
	dashboard := api.Group("/dashboard")
	{
		dashboard.GET("/summary", financeHandlers.GetFinancialDashboard)
		dashboard.GET("/collections-due", financeHandlers.GetMoneyCollections) // Overdue collections
		dashboard.GET("/cash-balance", financeHandlers.GetFinancialDashboard) // Alias to dashboard summary
	}

	// Collections aliases (Flutter app compatibility) - outside groups for direct access
	api.GET("/collections", financeHandlers.GetMoneyCollections)
	api.GET("/cash-requests", financeHandlers.GetMoneyCollections)
	api.GET("/pending-requests", financeHandlers.GetMoneyCollections)
	api.GET("/cash-balance", financeHandlers.GetFinancialDashboard) // Shortcut alias
	api.GET("/cash-history", financeHandlers.GetCashFlowReport) // Shortcut alias

	// Bank Account Routes (Placeholder for future implementation)
	api.GET("/bank-accounts", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"bank_accounts": []interface{}{},
			"total":         0,
		})
	})
	api.POST("/bank-accounts", func(c *gin.Context) {
		c.JSON(501, gin.H{"message": "Bank account creation not implemented yet"})
	})
	api.GET("/bank-accounts/:id", func(c *gin.Context) {
		c.JSON(501, gin.H{"message": "Bank account retrieval not implemented yet"})
	})
	api.PUT("/bank-accounts/:id", func(c *gin.Context) {
		c.JSON(501, gin.H{"message": "Bank account update not implemented yet"})
	})
	api.DELETE("/bank-accounts/:id", func(c *gin.Context) {
		c.JSON(501, gin.H{"message": "Bank account deletion not implemented yet"})
	})
}

// SetupProtectedRoutes sets up routes with gateway-style auth handling
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, financeHandlers *handlers.FinanceHandlers) {
	// Prometheus metrics
	router.Use(monitoring.PrometheusMiddleware("finance"))
	router.GET("/metrics", monitoring.PrometheusHandler())

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
	router.GET("/vendors/:id/ledger", financeHandlers.GetVendorLedger)

	// Expense Routes
	router.GET("/expenses", financeHandlers.GetExpenses)
	router.POST("/expenses", financeHandlers.CreateExpense)
	router.GET("/expenses/:id", financeHandlers.GetExpenseByID)
	router.PUT("/expenses/:id", financeHandlers.UpdateExpense)
	router.DELETE("/expenses/:id", financeHandlers.DeleteExpense)

	// Expense Category Routes
	router.GET("/expense-categories", financeHandlers.GetExpenseCategories)
	router.POST("/expense-categories", financeHandlers.CreateExpenseCategory)

	// Assistant Manager Routes (with full CRUD)
	router.GET("/assistant-manager/money-collections", financeHandlers.GetMoneyCollections)
	router.POST("/assistant-manager/money-collections", financeHandlers.CreateMoneyCollection)
	router.GET("/assistant-manager/money-collections/:id", financeHandlers.GetMoneyCollectionByID)
	router.POST("/assistant-manager/money-collections/:id/approve", financeHandlers.ApproveMoneyCollection)
	router.POST("/assistant-manager/money-collections/:id/reject", financeHandlers.RejectMoneyCollection)

	// Assistant Manager Expenses (GET added for listing)
	router.GET("/assistant-manager/expenses", financeHandlers.GetAssistantManagerExpenses)
	router.POST("/assistant-manager/expenses", financeHandlers.CreateAssistantManagerExpense)

	// Assistant Manager Finance Records (GET added for listing)
	router.GET("/assistant-manager/finance", financeHandlers.GetAssistantManagerFinanceRecords)
	router.POST("/assistant-manager/finance", financeHandlers.CreateAssistantManagerFinance)

	// Tenant Settings (deadline configuration)
	router.GET("/tenant-settings", financeHandlers.GetTenantSettings)
	router.PUT("/tenant-settings", financeHandlers.UpdateTenantSettings)

	// Collections aliases (Flutter app compatibility)
	router.GET("/collections", financeHandlers.GetMoneyCollections)
	router.GET("/cash-requests", financeHandlers.GetMoneyCollections)
	router.GET("/pending-requests", financeHandlers.GetMoneyCollections)

	// Reports Routes
	router.GET("/reports/expense-summary", financeHandlers.GetExpenseSummary)
	router.GET("/reports/vendor-aging", financeHandlers.GetVendorAgingReport)
	router.GET("/reports/cash-flow", financeHandlers.GetCashFlowReport)
	router.GET("/reports/profit-loss", financeHandlers.GetProfitLossReport)
	router.GET("/reports/balance-sheet", financeHandlers.GetBalanceSheetReport)
	router.GET("/reports/cash-history", financeHandlers.GetCashFlowReport) // Alias to cash-flow
	router.GET("/cash-history", financeHandlers.GetCashFlowReport) // Shortcut alias

	// Dashboard Routes
	router.GET("/dashboard/summary", financeHandlers.GetFinancialDashboard)
	router.GET("/dashboard/collections-due", financeHandlers.GetMoneyCollections)
	router.GET("/dashboard/cash-balance", financeHandlers.GetCashBalance) // Return cash balance only
	router.GET("/cash-balance", financeHandlers.GetCashBalance) // Shortcut alias

	// Flutter app compatibility - support both dash and slash formats
	router.GET("/cash/balance", financeHandlers.GetCashBalance) // Slash format for Flutter
	router.GET("/cash/history", financeHandlers.GetCashFlowReport) // Slash format for Flutter
	router.GET("/cash/requests/pending", financeHandlers.GetMoneyCollections) // Pending cash requests
	router.GET("/cash/requests", financeHandlers.GetMoneyCollections) // All cash requests
	router.POST("/cash/request", financeHandlers.CreateMoneyCollection) // Create cash request
	router.GET("/cash/collections", financeHandlers.GetMoneyCollections) // Cash collections
	router.GET("/cash/team-balances", financeHandlers.GetTeamBalances) // Team member balances
	router.GET("/cash/tenant-users", financeHandlers.GetTenantUsers) // Tenant users for cash management
	router.GET("/cash/users", financeHandlers.GetTenantUsers)        // Alias for tenant-users
	router.POST("/cash/reconcile-balances", financeHandlers.ReconcileBalances) // Admin: recalculate all balances

	// Cash request approve/reject aliases (Flutter app expects /cash/requests/:id/approve)
	router.GET("/cash/requests/:id", financeHandlers.GetMoneyCollectionByID)
	router.POST("/cash/requests/:id/approve", financeHandlers.ApproveMoneyCollection)
	router.POST("/cash/requests/:id/reject", financeHandlers.RejectMoneyCollection)

	// Cash deposit submission (Flutter app compatibility - submit cash to bank account)
	router.POST("/cash/submit", financeHandlers.CreateCashDeposit)
	router.GET("/cash/deposits", financeHandlers.ListCashDeposits)                      // List cash deposits
	router.GET("/cash/deposits/pending/count", financeHandlers.GetPendingDepositsCount) // Pending count for dashboard badge
	router.GET("/cash/deposits/:id", financeHandlers.GetCashDepositByID)                // Get specific deposit
	router.POST("/cash/deposits/:id/approve", financeHandlers.ApproveCashDeposit)       // Approve deposit
	router.POST("/cash/deposits/:id/reject", financeHandlers.RejectCashDeposit)         // Reject deposit

	// Alias routes for Flutter app compatibility (/submissions -> /deposits)
	router.GET("/cash/submissions", financeHandlers.ListCashDeposits)
	router.GET("/cash/submissions/:id", financeHandlers.GetCashDepositByID)
	router.POST("/cash/submissions/:id/approve", financeHandlers.ApproveCashDeposit)
	router.POST("/cash/submissions/:id/reject", financeHandlers.RejectCashDeposit)

	// Executive Finance Routes (Cash handovers and expense claims)
	router.GET("/executive-finance", financeHandlers.ListExecutiveFinance)
	router.POST("/executive-finance", financeHandlers.CreateExecutiveFinance)
	router.GET("/executive-finance/:id", financeHandlers.GetExecutiveFinanceByID)
	router.POST("/executive-finance/:id/approve", financeHandlers.ApproveExecutiveFinance)
	router.POST("/executive-finance/:id/reject", financeHandlers.RejectExecutiveFinance)

	// Bank Account Routes
	router.GET("/bank-accounts", financeHandlers.ListBankAccounts)
	router.POST("/bank-accounts", financeHandlers.CreateBankAccount)
	router.GET("/bank-accounts/:id", financeHandlers.GetBankAccountByID)

	// Cash Deposit Routes
	router.GET("/bank-deposits", financeHandlers.ListCashDeposits)
	router.POST("/bank-deposits", financeHandlers.CreateCashDeposit)
	router.GET("/bank-deposits/:id", financeHandlers.GetCashDepositByID)
	router.POST("/bank-deposits/:id/approve", financeHandlers.ApproveCashDeposit)
	router.POST("/bank-deposits/:id/reject", financeHandlers.RejectCashDeposit)

	// Bank Reconciliation Routes
	router.GET("/reconciliations", financeHandlers.ListReconciliations)
	router.POST("/reconciliations", financeHandlers.CreateReconciliation)
	router.GET("/reconciliations/:id", financeHandlers.GetReconciliationByID)
	router.POST("/reconciliations/:id/complete", financeHandlers.CompleteReconciliation)
	router.POST("/reconciliations/:id/approve", financeHandlers.ApproveReconciliation)

	// Stock Verification Routes
	router.GET("/stock-verification", financeHandlers.ListStockVerifications)
	router.POST("/stock-verification", financeHandlers.CreateStockVerification)
	router.GET("/stock-verification/:id", financeHandlers.GetStockVerificationByID)
	router.POST("/stock-verification/:id/approve", financeHandlers.ApproveStockVerification)
	router.POST("/stock-verification/:id/reject", financeHandlers.RejectStockVerification)

	// Stock Audit Logs Route
	router.GET("/stock-audit-logs", financeHandlers.GetStockAuditLogs)

	// Receipt Image Upload Route
	router.POST("/upload/receipt", financeHandlers.UploadReceipt)
	router.POST("/cash/upload-receipt", financeHandlers.UploadReceipt) // Flutter app compatibility

	// Admin Cash Balance Management Routes (admin/owner only)
	// These routes allow admin to set individual user balances or bulk reset multiple users
	router.POST("/cash/admin/set-balance", financeHandlers.SetBalance)
	router.POST("/cash/admin/bulk-reset", financeHandlers.BulkReset)

	// =============================================================================
	// TIPS MODULE ROUTES
	// =============================================================================
	// Record and manage employee tips with pool distribution
	router.POST("/tips", financeHandlers.RecordTip)
	router.GET("/tips", financeHandlers.GetTips)
	router.GET("/tips/my", financeHandlers.GetMyTips)
	router.GET("/tips/:id", financeHandlers.GetTipByID)
	router.PUT("/tips/:id", financeHandlers.UpdateTip)
	router.DELETE("/tips/:id", financeHandlers.DeleteTip)
	router.POST("/tips/:id/approve", financeHandlers.ApproveTip)
	router.POST("/tips/:id/reject", financeHandlers.RejectTip)

	// Tip Pools - shared tip distribution
	router.GET("/tips/pools", financeHandlers.GetTipPools)
	router.POST("/tips/pools", financeHandlers.CreateTipPool)
	router.GET("/tips/pools/:id", financeHandlers.GetTipPoolByID)
	router.PUT("/tips/pools/:id", financeHandlers.UpdateTipPool)
	router.DELETE("/tips/pools/:id", financeHandlers.DeleteTipPool)

	// Tip Payouts - process tip payments
	router.GET("/tips/payouts", financeHandlers.GetTipPayouts)
	router.POST("/tips/payouts", financeHandlers.CreateTipPayout)
	router.GET("/tips/payouts/:id", financeHandlers.GetTipPayoutByID)
	router.POST("/tips/payouts/:id/complete", financeHandlers.CompleteTipPayout)

	// Tips Dashboard and Analytics
	router.GET("/tips/dashboard", financeHandlers.GetTipsDashboard)
	router.GET("/tips/analytics", financeHandlers.GetTipsAnalytics)
	router.GET("/tips/summary", financeHandlers.GetTipsSummary)

	// =============================================================================
	// DETECTION MODULE ROUTES (Fraud Detection & Anomaly Alerts)
	// =============================================================================
	// Dashboard and Overview
	router.GET("/detection/dashboard", financeHandlers.GetDetectionDashboard)
	router.GET("/detection/analytics", financeHandlers.GetDetectionAnalytics)

	// Detection Alerts
	router.GET("/detection/alerts", financeHandlers.GetDetectionAlerts)
	router.GET("/detection/alerts/:id", financeHandlers.GetDetectionAlertByID)
	router.POST("/detection/alerts/:id/acknowledge", financeHandlers.AcknowledgeDetectionAlert)
	router.POST("/detection/alerts/:id/resolve", financeHandlers.ResolveDetectionAlert)
	router.POST("/detection/alerts/:id/escalate", financeHandlers.EscalateDetectionAlert)

	// Detection Investigations
	router.GET("/detection/investigations", financeHandlers.GetInvestigations)
	router.POST("/detection/investigations", financeHandlers.CreateInvestigation)
	router.GET("/detection/investigations/:id", financeHandlers.GetInvestigationByID)
	router.PUT("/detection/investigations/:id", financeHandlers.UpdateInvestigation)
	router.POST("/detection/investigations/:id/close", financeHandlers.CloseInvestigation)

	// Detection Thresholds (Admin configuration)
	router.GET("/detection/thresholds", financeHandlers.GetDetectionThresholds)
	router.PUT("/detection/thresholds", financeHandlers.UpdateDetectionThresholds)
	router.POST("/detection/thresholds/reset", financeHandlers.ResetDetectionThresholds)

	// Manual Detection Triggers
	router.POST("/detection/analyze", financeHandlers.TriggerDetectionAnalysis)
	router.POST("/detection/batch-analyze", financeHandlers.BatchDetectionAnalysis)

	// Detection Reports
	router.GET("/detection/reports/trends", financeHandlers.GetDetectionTrends)
	router.GET("/detection/reports/user-risk", financeHandlers.GetUserRiskReport)

	// =============================================================================
	// AUDIT MODULE ROUTES (Cash Counts & Compliance)
	// =============================================================================
	// Dashboard and Overview
	router.GET("/audit/dashboard", financeHandlers.GetAuditDashboard)

	// Audit Schedules - planned audits
	router.GET("/audit/schedules", financeHandlers.GetAuditSchedules)
	router.POST("/audit/schedules", financeHandlers.CreateAuditSchedule)
	router.GET("/audit/schedules/:id", financeHandlers.GetAuditScheduleByID)
	router.PUT("/audit/schedules/:id", financeHandlers.UpdateAuditSchedule)
	router.DELETE("/audit/schedules/:id", financeHandlers.DeleteAuditSchedule)

	// Audit Sessions - actual audit execution
	router.GET("/audit/sessions", financeHandlers.GetAuditSessions)
	router.POST("/audit/sessions", financeHandlers.CreateAuditSession)
	router.GET("/audit/sessions/:id", financeHandlers.GetAuditSessionByID)
	router.PUT("/audit/sessions/:id", financeHandlers.UpdateAuditSession)
	router.POST("/audit/sessions/:id/complete", financeHandlers.CompleteAuditSession)
	router.POST("/audit/sessions/:id/approve", financeHandlers.ApproveAuditSession)
	router.POST("/audit/sessions/:id/reject", financeHandlers.RejectAuditSession)

	// Cash Count Records within audit sessions
	router.POST("/audit/sessions/:id/cash-count", financeHandlers.RecordCashCount)
	router.GET("/audit/sessions/:id/cash-counts", financeHandlers.GetAuditCashCounts)

	// Audit Findings and Discrepancies
	router.GET("/audit/findings", financeHandlers.GetAuditFindings)
	router.POST("/audit/findings", financeHandlers.CreateAuditFinding)
	router.GET("/audit/findings/:id", financeHandlers.GetAuditFindingByID)
	router.PUT("/audit/findings/:id", financeHandlers.UpdateAuditFinding)
	router.POST("/audit/findings/:id/resolve", financeHandlers.ResolveAuditFinding)

	// Audit Reports
	router.GET("/audit/reports/compliance", financeHandlers.GetComplianceReport)
	router.GET("/audit/reports/history", financeHandlers.GetAuditHistory)
	router.GET("/audit/reports/trends", financeHandlers.GetAuditTrends)

	// Quick Audit Actions
	router.POST("/audit/quick-count", financeHandlers.QuickCashCount)
	router.GET("/audit/due-today", financeHandlers.GetAuditsDueToday)

	// =============================================================================
	// NOTIFICATIONS MODULE ROUTES
	// =============================================================================
	// Device Management (FCM token registration)
	router.POST("/notifications/register-device", financeHandlers.RegisterDevice)
	router.DELETE("/notifications/unregister-device", financeHandlers.UnregisterDevice)
	// Alias endpoints for frontend compatibility (Flutter app uses /devices)
	router.POST("/notifications/devices", financeHandlers.RegisterDevice)
	router.DELETE("/notifications/devices", financeHandlers.UnregisterDevice)

	// User Notifications
	router.GET("/notifications", financeHandlers.GetNotifications)
	router.GET("/notifications/unread-count", financeHandlers.GetUnreadCount)         // Unread count only (used by Flutter app badge)
	router.GET("/notifications/counts", financeHandlers.GetNotificationCounts)
	router.GET("/notifications/unread", financeHandlers.GetUnreadNotifications)
	router.POST("/notifications/mark-read", financeHandlers.MarkNotificationsRead)
	router.POST("/notifications/read", financeHandlers.MarkNotificationsRead)         // Gateway compatibility alias
	router.POST("/notifications/mark-all-read", financeHandlers.MarkAllNotificationsRead)
	router.POST("/notifications/read-all", financeHandlers.MarkAllNotificationsRead) // Gateway compatibility alias
	router.PATCH("/notifications/:id/read", financeHandlers.MarkSingleNotificationRead) // Mark single notification as read
	router.DELETE("/notifications/:id", financeHandlers.DeleteNotification)
	router.DELETE("/notifications", financeHandlers.ClearAllNotifications)             // Clear all notifications

	// Notification Preferences
	router.GET("/notifications/preferences", financeHandlers.GetNotificationPreferences)
	router.PUT("/notifications/preferences", financeHandlers.UpdateNotificationPreferences)

	// WhatsApp Integration
	router.POST("/notifications/whatsapp/opt-in", financeHandlers.WhatsAppOptIn)
	router.POST("/notifications/whatsapp/opt-out", financeHandlers.WhatsAppOptOut)
	router.GET("/notifications/whatsapp/status", financeHandlers.GetWhatsAppStatus)

	// Admin Notification Management
	router.POST("/notifications/send", financeHandlers.SendNotification)
	router.POST("/notifications/send-bulk", financeHandlers.SendBulkNotification)
	router.POST("/notifications/broadcast", financeHandlers.BroadcastNotification)
	router.GET("/notifications/templates", financeHandlers.GetNotificationTemplates)
	router.POST("/notifications/templates", financeHandlers.CreateNotificationTemplate)
	router.PUT("/notifications/templates/:id", financeHandlers.UpdateNotificationTemplate)
	router.DELETE("/notifications/templates/:id", financeHandlers.DeleteNotificationTemplate)
	router.GET("/notifications/stats", financeHandlers.GetNotificationStats) // Admin notification statistics

	// =============================================================================
	// FINANCE MATRIX ROUTES (Executive Dashboard & Cross-Module Analytics)
	// =============================================================================
	// Base matrix endpoint (Flutter app compatibility)
	router.GET("/matrix", financeHandlers.GetFinanceMatrix)

	// Matrix insights and alerts
	router.GET("/matrix/insights", financeHandlers.GetMatrixInsights)
	router.GET("/matrix/alerts", financeHandlers.GetMatrixAlerts)
	router.POST("/matrix/alerts/:id/acknowledge", financeHandlers.AcknowledgeMatrixAlert)
	router.POST("/matrix/alerts/:id/resolve", financeHandlers.ResolveMatrixAlert)

	// Matrix Dashboard - comprehensive financial overview
	router.GET("/matrix/dashboard", financeHandlers.GetMatrixDashboard)

	// Daily Financial Metrics
	router.GET("/matrix/daily-metrics", financeHandlers.GetDailyMetrics)
	router.GET("/matrix/daily-metrics/history", financeHandlers.GetDailyMetricsHistory)

	// Cash Holdings across all locations/users
	router.GET("/matrix/cash-holdings", financeHandlers.GetCashHoldings)
	router.GET("/matrix/cash-holdings/by-user", financeHandlers.GetCashHoldingsByUser)
	router.GET("/matrix/cash-holdings/by-location", financeHandlers.GetCashHoldingsByLocation)

	// Cash Flow Analysis
	router.GET("/matrix/cash-flow", financeHandlers.GetMatrixCashFlow)
	router.GET("/matrix/cash-flow/forecast", financeHandlers.GetCashFlowForecast)

	// Tips Analytics Integration
	router.GET("/matrix/tips-overview", financeHandlers.GetTipsOverview)

	// Risk Metrics from Detection Module
	router.GET("/matrix/risk-metrics", financeHandlers.GetRiskMetrics)
	router.GET("/matrix/risk-score", financeHandlers.GetOverallRiskScore)

	// Compliance Metrics from Audit Module
	router.GET("/matrix/compliance-metrics", financeHandlers.GetComplianceMetrics)

	// Team Performance Analytics
	router.GET("/matrix/team-performance", financeHandlers.GetTeamPerformance)
	router.GET("/matrix/user-performance/:user_id", financeHandlers.GetUserPerformance)

	// Trend Analysis
	router.GET("/matrix/trends/weekly", financeHandlers.GetWeeklyTrends)
	router.GET("/matrix/trends/monthly", financeHandlers.GetMonthlyTrends)

	// Export and Reporting
	router.GET("/matrix/export", financeHandlers.ExportMatrixData)
	router.POST("/matrix/generate-report", financeHandlers.GenerateMatrixReport)

	// =============================================================================
	// DASHBOARD METRICS ROUTES (Manager/Assistant Manager/Admin only)
	// Role restriction is enforced at the gateway level
	// =============================================================================
	router.GET("/dashboard/metrics", financeHandlers.GetDashboardMetrics)
	router.GET("/dashboard/metrics/payment/details", financeHandlers.GetDashboardPaymentDetails)
	router.GET("/dashboard/metrics/purchase/details", financeHandlers.GetDashboardPurchaseDetails)
	router.GET("/dashboard/metrics/sale/details", financeHandlers.GetDashboardSaleDetails)
	router.GET("/dashboard/metrics/expense/details", financeHandlers.GetDashboardExpenseDetails)

	// =============================================================================
	// ALARM SYSTEM ROUTES
	// =============================================================================
	// Alarm Definitions (read-only)
	router.GET("/alarms/definitions", financeHandlers.GetAlarmDefinitions)
	router.GET("/alarms/definitions/:code", financeHandlers.GetAlarmDefinitionByCode)

	// Alarm Configurations
	router.GET("/alarms/configurations", financeHandlers.GetAlarmConfigurations)
	router.GET("/alarms/configurations/:code", financeHandlers.GetAlarmConfigurationByCode)
	router.PUT("/alarms/configurations", financeHandlers.UpdateAlarmConfiguration)

	// Alarm Instances
	router.GET("/alarms", financeHandlers.GetAlarms)
	router.GET("/alarms/:id", financeHandlers.GetAlarmByID)
	router.POST("/alarms/:id/acknowledge", financeHandlers.AcknowledgeAlarm)
	router.POST("/alarms/:id/resolve", financeHandlers.ResolveAlarm)
	router.POST("/alarms/:id/snooze", financeHandlers.SnoozeAlarm)
	router.POST("/alarms/:id/notes", financeHandlers.AddAlarmNote)

	// Alarm Counts and Stats
	router.GET("/alarms/counts", financeHandlers.GetAlarmCounts)
	router.GET("/alarms/stats", financeHandlers.GetAlarmStats)

	// User Alarm Subscriptions
	router.GET("/alarms/subscriptions", financeHandlers.GetAlarmSubscriptions)
	router.PUT("/alarms/subscriptions", financeHandlers.UpdateAlarmSubscription)

	// Bulk Actions
	router.POST("/alarms/bulk/acknowledge", financeHandlers.BulkAcknowledgeAlarms)
	router.POST("/alarms/bulk/resolve", financeHandlers.BulkResolveAlarms)

	// Admin Actions
	router.POST("/alarms/admin/trigger", financeHandlers.TriggerAlarm)
	router.POST("/alarms/admin/run-checks", financeHandlers.RunAlarmChecks)
}

// =============================================================================
// APP LOGGING ROUTES (Industrial-Grade Logging System)
// =============================================================================

// SetupAppLoggingRoutes configures app logging endpoints
// This is a separate function to allow independent initialization of app logging
func SetupAppLoggingRoutes(router *gin.Engine, appLoggingHandlers *handlers.AppLoggingHandlers) {
	// App Logging Routes - receive logs from Flutter app
	// POST /api/logs/batch - Receive batch logs (authenticated users)
	router.POST("/logs/batch", appLoggingHandlers.ReceiveBatchLogs)

	// GET endpoints for viewing logs (role-based access control)
	router.GET("/logs", appLoggingHandlers.GetLogs)
	router.GET("/logs/sessions", appLoggingHandlers.GetSessions)
	router.GET("/logs/stats", appLoggingHandlers.GetLogStats)
	router.GET("/logs/network", appLoggingHandlers.GetNetworkRequests)

	// GET /logs/users - Get viewable users for dropdown (role-based)
	router.GET("/logs/users", appLoggingHandlers.GetViewableUsers)

	// Cleanup endpoint (super admin only)
	router.DELETE("/logs/cleanup", appLoggingHandlers.CleanupOldLogs)
}
