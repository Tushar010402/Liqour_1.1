package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/auth/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all auth service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, authHandlers *handlers.AuthHandlers, rateLimitHandlers *handlers.RateLimitHandlers) {
	// Health check
	router.GET("/health", authHandlers.Health)

	// Public authentication routes (no auth required)
	auth := router.Group("/api/auth")
	{
		auth.POST("/check-user", authHandlers.CheckUser)
		auth.POST("/login", authHandlers.Login)
		auth.POST("/register", authHandlers.Register)
		auth.POST("/send-otp", authHandlers.SendOTP)
		auth.POST("/send-otp-registration", authHandlers.SendOTPForRegistration)
		auth.POST("/verify-otp", authHandlers.VerifyOTP)
		auth.POST("/force-login-otp", authHandlers.ForceLoginWithOTP) // Swiggy/Zomato style force login
		// TODO: Add forgot-password, reset-password, verify-email endpoints
	}

	// Public admin routes (no auth required - for registration flow)
	publicAdmin := router.Group("/api/admin")
	{
		// Phone validation (called during registration before user has account)
		publicAdmin.GET("/validate/phone", authHandlers.ValidatePhone)
		// Email validation (called during registration before user has account)
		publicAdmin.GET("/validate/email", authHandlers.ValidateEmail)
		// Tenant name validation (called during registration before user has account)
		publicAdmin.GET("/validate/tenant", authHandlers.ValidateTenantName)
	}

	// Protected authentication routes
	authProtected := router.Group("/api/auth")
	authProtected.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	authProtected.Use(middleware.TenantMiddleware())
	{
		authProtected.POST("/logout", authHandlers.Logout)
		authProtected.POST("/refresh", authHandlers.RefreshToken)
		authProtected.GET("/profile", authHandlers.GetProfile)
		authProtected.PUT("/profile", authHandlers.UpdateProfile)
		authProtected.PUT("/change-password", authHandlers.ChangePassword)

		// Device Session Management (2-device limit like Swiggy/Zomato)
		authProtected.GET("/sessions", authHandlers.GetActiveSessions)           // Get all active sessions
		authProtected.DELETE("/sessions/:session_id", authHandlers.LogoutDevice) // Logout specific device
		authProtected.DELETE("/sessions", authHandlers.LogoutAllDevices)         // Logout all devices
		authProtected.POST("/sessions/force-login", authHandlers.ForceLogin)     // Force login by removing a session

		// Account Deletion (App Store Guideline 5.1.1(v) Compliance)
		authProtected.POST("/account/delete/request-otp", authHandlers.RequestDeleteAccountOTP) // Request OTP for deletion
		authProtected.POST("/account/delete/send-otp", authHandlers.RequestDeleteAccountOTP)    // Alias for Flutter app
		authProtected.DELETE("/account", authHandlers.DeleteAccount)                            // Delete account with OTP
		authProtected.POST("/account/delete", authHandlers.DeleteAccount)                       // POST alias for Flutter app
		authProtected.POST("/account/delete/cancel", authHandlers.CancelAccountDeletion)        // Cancel pending deletion
	}

	// Protected routes accessible to all authenticated users
	protected := router.Group("/api")
	protected.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	protected.Use(middleware.TenantMiddleware())
	{
		// Shops - all users can view shops in their tenant
		protected.GET("/shops", authHandlers.GetShops)
		protected.GET("/shops/:id", authHandlers.GetShopByID)
	}

	// Admin routes for user management
	admin := router.Group("/api/admin")
	admin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	admin.Use(middleware.TenantMiddleware())
	admin.Use(middleware.RoleMiddleware("admin", "manager")) // Admin and Manager can manage users
	{
		// User management
		admin.GET("/users", authHandlers.GetUsers)
		admin.POST("/users", authHandlers.CreateUser)
		admin.GET("/users/:id", authHandlers.GetUserByID)
		admin.PUT("/users/:id", authHandlers.UpdateUser)
		admin.DELETE("/users/:id", middleware.RoleMiddleware("admin"), authHandlers.DeleteUser) // Only admin can delete

		// Shop management
		admin.GET("/shops", authHandlers.GetShops)
		admin.POST("/shops", authHandlers.CreateShop)
		admin.GET("/shops/:id", authHandlers.GetShopByID)
		admin.PUT("/shops/:id", authHandlers.UpdateShop)

		// Salesman management
		admin.GET("/salesmen", authHandlers.GetSalesmen)
		admin.POST("/salesmen", authHandlers.CreateSalesman)
		admin.GET("/salesmen/:id", authHandlers.GetSalesmanByID)
		admin.PUT("/salesmen/:id", authHandlers.UpdateSalesman)
	}

	// SaaS Admin routes (super admin functionality)
	saasAdmin := router.Group("/api/saas-admin")
	saasAdmin.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	saasAdmin.Use(middleware.RoleMiddleware("saas_admin"))
	{
		// Tenant management
		saasAdmin.GET("/tenants", authHandlers.GetTenants)
		saasAdmin.POST("/tenants", authHandlers.CreateTenant)
		saasAdmin.GET("/tenants/:id", authHandlers.GetTenantByID)
		saasAdmin.PUT("/tenants/:id", authHandlers.UpdateTenant)
		saasAdmin.DELETE("/tenants/:id", authHandlers.DeleteTenant)

		// Global user management (across all tenants)
		saasAdmin.GET("/all-users", authHandlers.GetAllUsers)
		saasAdmin.GET("/all-shops", authHandlers.GetAllShops)

		// System statistics
		saasAdmin.GET("/stats", authHandlers.GetSystemStats)

		// Rate limit management
		saasAdmin.GET("/rate-limits", rateLimitHandlers.GetRateLimits)
		saasAdmin.POST("/rate-limits", rateLimitHandlers.CreateRateLimit)
		saasAdmin.GET("/rate-limits/stats", rateLimitHandlers.GetRateLimitStats)
		saasAdmin.GET("/rate-limits/check/:name", rateLimitHandlers.CheckRateLimit)
		saasAdmin.POST("/rate-limits/reset/:name", rateLimitHandlers.ResetRateLimit)
		saasAdmin.GET("/rate-limits/:id", rateLimitHandlers.GetRateLimit)
		saasAdmin.PUT("/rate-limits/:id", rateLimitHandlers.UpdateRateLimit)
		saasAdmin.DELETE("/rate-limits/:id", rateLimitHandlers.DeleteRateLimit)
	}
}

// SetupPublicRoutes sets up only public routes (for gateway routing)
func SetupPublicRoutes(router *gin.Engine, authHandlers *handlers.AuthHandlers) {
	// Health check
	router.GET("/health", authHandlers.Health)

	// Public authentication routes
	router.POST("/check-user", authHandlers.CheckUser)
	router.POST("/login", authHandlers.Login)
	router.POST("/register", authHandlers.Register)
	router.POST("/send-otp", authHandlers.SendOTP)
	router.POST("/send-otp-registration", authHandlers.SendOTPForRegistration)
	router.POST("/verify-otp", authHandlers.VerifyOTP)
	router.POST("/force-login-otp", authHandlers.ForceLoginWithOTP) // Swiggy/Zomato style force login

	// Public admin validation routes (for registration flow)
	router.GET("/admin/validate/phone", authHandlers.ValidatePhone)
	router.GET("/admin/validate/email", authHandlers.ValidateEmail)
	router.GET("/admin/validate/tenant", authHandlers.ValidateTenantName)
}

// SetupProtectedRoutes sets up only protected routes (for gateway routing)
func SetupProtectedRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, authHandlers *handlers.AuthHandlers) {
	// Apply auth middleware to all routes
	router.Use(middleware.AuthMiddleware(cfg.JWT, cache))
	router.Use(middleware.TenantMiddleware())

	// Authentication routes
	router.POST("/logout", authHandlers.Logout)
	router.POST("/refresh", authHandlers.RefreshToken)
	router.GET("/profile", authHandlers.GetProfile)
	router.PUT("/profile", authHandlers.UpdateProfile)
	router.PUT("/change-password", authHandlers.ChangePassword)

	// Device Session Management (2-device limit like Swiggy/Zomato)
	router.GET("/sessions", authHandlers.GetActiveSessions)
	router.DELETE("/sessions/:session_id", authHandlers.LogoutDevice)
	router.DELETE("/sessions", authHandlers.LogoutAllDevices)
	router.POST("/sessions/force-login", authHandlers.ForceLogin)

	// Account Deletion (App Store Guideline 5.1.1(v) Compliance)
	router.POST("/account/delete/request-otp", authHandlers.RequestDeleteAccountOTP)
	router.POST("/account/delete/send-otp", authHandlers.RequestDeleteAccountOTP) // Alias for Flutter app
	router.DELETE("/account", authHandlers.DeleteAccount)
	router.POST("/account/delete", authHandlers.DeleteAccount) // POST alias for Flutter app
	router.POST("/account/delete/cancel", authHandlers.CancelAccountDeletion)

	// Admin routes
	admin := router.Group("/admin")
	admin.Use(middleware.RoleMiddleware("admin", "manager"))
	{
		// User management
		admin.GET("/users", authHandlers.GetUsers)
		admin.POST("/users", authHandlers.CreateUser)
		admin.GET("/users/:id", authHandlers.GetUserByID)
		admin.PUT("/users/:id", authHandlers.UpdateUser)
		admin.DELETE("/users/:id", middleware.RoleMiddleware("admin"), authHandlers.DeleteUser)

		// Shop management
		admin.GET("/shops", authHandlers.GetShops)
		admin.POST("/shops", authHandlers.CreateShop)
		admin.GET("/shops/:id", authHandlers.GetShopByID)
		admin.PUT("/shops/:id", authHandlers.UpdateShop)

		// Salesman management
		admin.GET("/salesmen", authHandlers.GetSalesmen)
		admin.POST("/salesmen", authHandlers.CreateSalesman)
		admin.GET("/salesmen/:id", authHandlers.GetSalesmanByID)
		admin.PUT("/salesmen/:id", authHandlers.UpdateSalesman)
	}
}
