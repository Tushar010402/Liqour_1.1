package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/auth/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
)

// SetupRoutes configures all auth service routes
func SetupRoutes(router *gin.Engine, cfg *config.Config, cache *cache.Cache, authHandlers *handlers.AuthHandlers) {
	// Health check
	router.GET("/health", authHandlers.Health)

	// Public authentication routes (no auth required)
	auth := router.Group("/api/auth")
	{
		auth.POST("/login", authHandlers.Login)
		auth.POST("/register", authHandlers.Register)
		// TODO: Add forgot-password, reset-password, verify-email endpoints
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
	}
}

// SetupPublicRoutes sets up only public routes (for gateway routing)
func SetupPublicRoutes(router *gin.Engine, authHandlers *handlers.AuthHandlers) {
	// Health check
	router.GET("/health", authHandlers.Health)

	// Public authentication routes
	router.POST("/login", authHandlers.Login)
	router.POST("/register", authHandlers.Register)
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