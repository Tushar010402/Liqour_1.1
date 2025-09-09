package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/auth/services"
	"github.com/liquorpro/go-backend/pkg/shared/validators"
)

// AuthHandlers handles HTTP requests for authentication
type AuthHandlers struct {
	authService   *services.AuthService
	userService   *services.UserService
	tenantService *services.TenantService
}

// NewAuthHandlers creates new auth handlers
func NewAuthHandlers(authService *services.AuthService, userService *services.UserService, tenantService *services.TenantService) *AuthHandlers {
	return &AuthHandlers{
		authService:   authService,
		userService:   userService,
		tenantService: tenantService,
	}
}

// Health check endpoint
func (h *AuthHandlers) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"service": "auth",
	})
}

// Login handles user login
func (h *AuthHandlers) Login(c *gin.Context) {
	var req services.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Username, "username")
	validator.Required(req.Password, "password")
	
	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.Login(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// Register handles user registration
func (h *AuthHandlers) Register(c *gin.Context) {
	var req services.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Username, "username")
	validator.MinLength(req.Username, 3, "username")
	validator.MaxLength(req.Username, 50, "username")
	validator.Required(req.Email, "email")
	validator.Email(req.Email, "email")
	validator.Required(req.Password, "password")
	validator.Password(req.Password, "password")
	validator.Required(req.FirstName, "first_name")
	validator.Required(req.LastName, "last_name")
	validator.Required(req.TenantName, "tenant_name")
	validator.Required(req.CompanyName, "company_name")
	
	if req.Phone != "" {
		validator.Phone(req.Phone, "phone")
	}

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.Register(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, response)
}

// Logout handles user logout
func (h *AuthHandlers) Logout(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	if err := h.authService.Logout(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to logout"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Successfully logged out"})
}

// RefreshToken handles token refresh
func (h *AuthHandlers) RefreshToken(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	response, err := h.authService.RefreshToken(c.Request.Context(), req.RefreshToken, userID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetProfile returns current user profile
func (h *AuthHandlers) GetProfile(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	tenantIDStr := c.GetString("tenant_id")

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	user, err := h.userService.GetUserByID(c.Request.Context(), userID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, user)
}

// UpdateProfile updates current user profile
func (h *AuthHandlers) UpdateProfile(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	tenantIDStr := c.GetString("tenant_id")

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req services.UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate phone if provided
	if req.Phone != nil && *req.Phone != "" {
		validator := validators.New()
		validator.Phone(*req.Phone, "phone")
		if validator.HasErrors() {
			c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
			return
		}
	}

	user, err := h.userService.UpdateUser(c.Request.Context(), userID, tenantID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, user)
}

// ChangePassword handles password change
func (h *AuthHandlers) ChangePassword(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	tenantIDStr := c.GetString("tenant_id")

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req services.ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate passwords
	validator := validators.New()
	validator.Required(req.CurrentPassword, "current_password")
	validator.Required(req.NewPassword, "new_password")
	validator.Password(req.NewPassword, "new_password")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	if err := h.userService.ChangePassword(c.Request.Context(), userID, tenantID, req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Password changed successfully"})
}

// User Management Endpoints (Admin only)

// GetUsers returns paginated list of users
func (h *AuthHandlers) GetUsers(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Parse pagination parameters
	page := 1
	pageSize := 20

	if p := c.Query("page"); p != "" {
		if parsed, err := strconv.Atoi(p); err == nil && parsed > 0 {
			page = parsed
		}
	}

	if ps := c.Query("page_size"); ps != "" {
		if parsed, err := strconv.Atoi(ps); err == nil && parsed > 0 && parsed <= 100 {
			pageSize = parsed
		}
	}

	users, err := h.userService.GetUsers(c.Request.Context(), tenantID, page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, users)
}

// CreateUser creates a new user (Admin only)
func (h *AuthHandlers) CreateUser(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req services.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Username, "username")
	validator.MinLength(req.Username, 3, "username")
	validator.MaxLength(req.Username, 50, "username")
	validator.Required(req.Email, "email")
	validator.Email(req.Email, "email")
	validator.Required(req.Password, "password")
	validator.Password(req.Password, "password")
	validator.Required(req.FirstName, "first_name")
	validator.Required(req.LastName, "last_name")
	validator.Required(req.Role, "role")
	validator.ValidRole(req.Role, "role")
	
	if req.Phone != "" {
		validator.Phone(req.Phone, "phone")
	}

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	user, err := h.userService.CreateUser(c.Request.Context(), req, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, user)
}

// GetUserByID returns user by ID
func (h *AuthHandlers) GetUserByID(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	user, err := h.userService.GetUserByID(c.Request.Context(), userID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, user)
}

// UpdateUser updates user (Admin only)
func (h *AuthHandlers) UpdateUser(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var req services.UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate phone if provided
	if req.Phone != nil && *req.Phone != "" {
		validator := validators.New()
		validator.Phone(*req.Phone, "phone")
		if validator.HasErrors() {
			c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
			return
		}
	}

	user, err := h.userService.UpdateUser(c.Request.Context(), userID, tenantID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, user)
}

// DeleteUser deletes user (Admin only)
func (h *AuthHandlers) DeleteUser(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	if err := h.userService.DeleteUser(c.Request.Context(), userID, tenantID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User deleted successfully"})
}

// Shop Management Endpoints

// GetShops returns all shops
func (h *AuthHandlers) GetShops(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	shops, err := h.tenantService.GetShops(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, shops)
}

// CreateShop creates a new shop
func (h *AuthHandlers) CreateShop(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req services.CreateShopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Name, "name")
	validator.Required(req.Address, "address")
	validator.Required(req.Phone, "phone")
	validator.Phone(req.Phone, "phone")
	validator.Required(req.LicenseNumber, "license_number")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	shop, err := h.tenantService.CreateShop(c.Request.Context(), req, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, shop)
}

// GetShopByID returns shop by ID
func (h *AuthHandlers) GetShopByID(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	shopIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
		return
	}

	shop, err := h.tenantService.GetShopByID(c.Request.Context(), shopID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, shop)
}

// UpdateShop updates shop information
func (h *AuthHandlers) UpdateShop(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	shopIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
		return
	}

	var req services.UpdateShopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate phone if provided
	if req.Phone != nil && *req.Phone != "" {
		validator := validators.New()
		validator.Phone(*req.Phone, "phone")
		if validator.HasErrors() {
			c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
			return
		}
	}

	shop, err := h.tenantService.UpdateShop(c.Request.Context(), shopID, tenantID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, shop)
}

// Salesman Management Endpoints

// GetSalesmen returns all salesmen
func (h *AuthHandlers) GetSalesmen(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	salesmen, err := h.tenantService.GetSalesmen(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, salesmen)
}

// CreateSalesman creates a new salesman
func (h *AuthHandlers) CreateSalesman(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	var req services.CreateSalesmanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.UserID.String(), "user_id")
	validator.Required(req.ShopID.String(), "shop_id")
	validator.Required(req.Name, "name")
	validator.Required(req.Phone, "phone")
	validator.Phone(req.Phone, "phone")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	salesman, err := h.tenantService.CreateSalesman(c.Request.Context(), req, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, salesman)
}

// GetSalesmanByID returns salesman by ID
func (h *AuthHandlers) GetSalesmanByID(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	salesmanIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	salesmanID, err := uuid.Parse(salesmanIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid salesman ID"})
		return
	}

	salesman, err := h.tenantService.GetSalesmanByID(c.Request.Context(), salesmanID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, salesman)
}

// UpdateSalesman updates salesman information
func (h *AuthHandlers) UpdateSalesman(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	salesmanIDStr := c.Param("id")

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	salesmanID, err := uuid.Parse(salesmanIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid salesman ID"})
		return
	}

	var req services.UpdateSalesmanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate phone if provided
	if req.Phone != nil && *req.Phone != "" {
		validator := validators.New()
		validator.Phone(*req.Phone, "phone")
		if validator.HasErrors() {
			c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
			return
		}
	}

	salesman, err := h.tenantService.UpdateSalesman(c.Request.Context(), salesmanID, tenantID, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, salesman)
}

// SaaS Admin Endpoints (placeholder implementations)

// GetTenants returns all tenants (SaaS Admin only)
func (h *AuthHandlers) GetTenants(c *gin.Context) {
	// TODO: Implement tenant listing for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// CreateTenant creates a new tenant (SaaS Admin only)
func (h *AuthHandlers) CreateTenant(c *gin.Context) {
	// TODO: Implement tenant creation for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// GetTenantByID returns tenant by ID (SaaS Admin only)
func (h *AuthHandlers) GetTenantByID(c *gin.Context) {
	// TODO: Implement tenant retrieval for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// UpdateTenant updates tenant (SaaS Admin only)
func (h *AuthHandlers) UpdateTenant(c *gin.Context) {
	// TODO: Implement tenant updates for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// DeleteTenant deletes tenant (SaaS Admin only)
func (h *AuthHandlers) DeleteTenant(c *gin.Context) {
	// TODO: Implement tenant deletion for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// GetAllUsers returns users across all tenants (SaaS Admin only)
func (h *AuthHandlers) GetAllUsers(c *gin.Context) {
	// TODO: Implement global user listing for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// GetAllShops returns shops across all tenants (SaaS Admin only)
func (h *AuthHandlers) GetAllShops(c *gin.Context) {
	// TODO: Implement global shop listing for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}

// GetSystemStats returns system statistics (SaaS Admin only)
func (h *AuthHandlers) GetSystemStats(c *gin.Context) {
	// TODO: Implement system statistics for SaaS admins
	c.JSON(http.StatusNotImplemented, gin.H{"message": "Not implemented yet"})
}