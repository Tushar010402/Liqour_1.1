package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/liquorpro/go-backend/internal/auth/services"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/validators"
	"go.uber.org/zap"
)

// AuthHandlers handles HTTP requests for authentication
type AuthHandlers struct {
	authService      *services.AuthService
	userService      *services.UserService
	tenantService    *services.TenantService
	loginRateLimiter *middleware.LoginRateLimiter
}

// NewAuthHandlers creates new auth handlers
func NewAuthHandlers(authService *services.AuthService, userService *services.UserService, tenantService *services.TenantService) *AuthHandlers {
	return &AuthHandlers{
		authService:   authService,
		userService:   userService,
		tenantService: tenantService,
	}
}

// NewAuthHandlersWithRateLimiter creates new auth handlers with login rate limiting
func NewAuthHandlersWithRateLimiter(authService *services.AuthService, userService *services.UserService, tenantService *services.TenantService, redisClient *redis.Client, logger *zap.Logger) *AuthHandlers {
	var loginLimiter *middleware.LoginRateLimiter
	if redisClient != nil && logger != nil {
		loginLimiter = middleware.NewLoginRateLimiter(redisClient, logger)
	}
	return &AuthHandlers{
		authService:      authService,
		userService:      userService,
		tenantService:    tenantService,
		loginRateLimiter: loginLimiter,
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

	// Check for account/IP lockout before attempting login
	if h.loginRateLimiter != nil {
		if err := h.loginRateLimiter.CheckAndBlockLogin(c, req.Username); err != nil {
			// Response already sent by CheckAndBlockLogin
			return
		}
	}

	response, err := h.authService.Login(c.Request.Context(), req)
	if err != nil {
		// Check if it's a device limit error (2-device limit reached)
		if deviceLimitErr, ok := err.(*models.DeviceLimitError); ok {
			// Return 409 Conflict with active sessions for client to display
			var sessions []map[string]interface{}
			for _, session := range deviceLimitErr.ActiveSessions {
				sessionInfo := map[string]interface{}{
					"id":          session.ID.String(),
					"device_id":   session.DeviceID,
					"device_name": session.DeviceName,
					"device_type": session.DeviceType,
					"os_name":     session.OSName,
					"os_version":  session.OSVersion,
					"app_version": session.AppVersion,
					"ip_address":  session.IPAddress,
					"is_current":  session.IsCurrent,
					"created_at":  session.CreatedAt,
				}
				if session.LastActiveAt != nil {
					sessionInfo["last_active_at"] = session.LastActiveAt
				}
				sessions = append(sessions, sessionInfo)
			}

			c.JSON(http.StatusConflict, gin.H{
				"error":           "device_limit_reached",
				"message":         deviceLimitErr.Message,
				"max_devices":     deviceLimitErr.MaxDevices,
				"active_sessions": sessions,
				"action_required": "Select a device to logout before continuing",
			})
			return
		}

		// Track failed login attempt for lockout
		if h.loginRateLimiter != nil {
			remaining, wasLocked := h.loginRateLimiter.HandleFailedLogin(c, req.Username)
			if wasLocked {
				// Account was just locked - return 423 Locked
				ttl := h.loginRateLimiter.GetAccountLockoutTTL(context.Background(), req.Username)
				c.Header("Retry-After", fmt.Sprintf("%d", int(ttl.Seconds())))
				c.JSON(http.StatusLocked, gin.H{
					"error":                     "account_locked",
					"message":                   "Account temporarily locked due to too many failed login attempts.",
					"retry_after":               int(ttl.Seconds()),
					"remaining_lockout_seconds": int(ttl.Seconds()),
				})
				return
			}
			// Add remaining attempts info to error response
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":              err.Error(),
				"remaining_attempts": remaining,
			})
			return
		}

		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Clear failed attempts on successful login
	if h.loginRateLimiter != nil {
		h.loginRateLimiter.HandleSuccessfulLogin(context.Background(), req.Username)
	}

	c.JSON(http.StatusOK, response)
}

// CheckUser handles user existence check requests
func (h *AuthHandlers) CheckUser(c *gin.Context) {
	var req services.CheckUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Support both "mobile" and "phone" field names (Flutter app compatibility)
	phoneNumber := req.Mobile
	if phoneNumber == "" {
		phoneNumber = req.Phone
	}

	// Sanitize phone number (remove spaces) before validation
	phoneNumber = strings.ReplaceAll(phoneNumber, " ", "")

	// Validate request
	validator := validators.New()
	validator.Required(phoneNumber, "phone")
	validator.Phone(phoneNumber, "phone")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.CheckUser(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// SendOTP sends OTP to mobile number
func (h *AuthHandlers) SendOTP(c *gin.Context) {
	var req services.SendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Mobile, "mobile")
	validator.Phone(req.Mobile, "mobile")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.SendOTP(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// SendOTPForRegistration sends OTP for registration after validating phone/email uniqueness
func (h *AuthHandlers) SendOTPForRegistration(c *gin.Context) {
	var req services.SendOTPForRegistrationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Phone, "phone")
	validator.Phone(req.Phone, "phone")
	validator.Required(req.Email, "email")
	validator.Email(req.Email, "email")
	validator.Required(req.FirstName, "first_name")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.SendOTPForRegistration(c.Request.Context(), req)
	if err != nil {
		// Check for specific error types
		if err.Error() == "phone number already registered" || err.Error() == "email already registered" {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// VerifyOTP verifies OTP and logs in user
func (h *AuthHandlers) VerifyOTP(c *gin.Context) {
	var req services.VerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Mobile, "mobile")
	validator.Phone(req.Mobile, "mobile")
	validator.Required(req.OTP, "otp")
	validator.MinLength(req.OTP, 6, "otp")
	validator.MaxLength(req.OTP, 6, "otp")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	// Check for account/IP lockout before attempting OTP verification
	if h.loginRateLimiter != nil {
		if err := h.loginRateLimiter.CheckAndBlockLogin(c, req.Mobile); err != nil {
			// Response already sent by CheckAndBlockLogin
			return
		}
	}

	response, err := h.authService.VerifyOTP(c.Request.Context(), req)
	if err != nil {
		// Check if it's a device limit error (Swiggy/Zomato style - 409 Conflict)
		if deviceLimitErr, ok := err.(*models.DeviceLimitError); ok {
			// Return 409 with active sessions so Flutter can show device selection dialog
			sessions := make([]gin.H, len(deviceLimitErr.ActiveSessions))
			for i, s := range deviceLimitErr.ActiveSessions {
				lastActive := ""
				if s.LastActiveAt != nil {
					lastActive = s.LastActiveAt.Format("2006-01-02 15:04:05")
				}
				sessions[i] = gin.H{
					"session_id":     s.ID.String(),
					"device_id":      s.DeviceID,
					"device_name":    s.DeviceName,
					"device_type":    s.DeviceType,
					"os_name":        s.OSName,
					"os_version":     s.OSVersion,
					"app_version":    s.AppVersion,
					"last_active_at": lastActive,
					"is_current":     s.IsCurrent,
				}
			}
			c.JSON(http.StatusConflict, gin.H{
				"error":           "device_limit_reached",
				"message":         deviceLimitErr.Message,
				"max_devices":     deviceLimitErr.MaxDevices,
				"active_sessions": sessions,
			})
			return
		}

		// Track failed OTP verification attempt for lockout
		if h.loginRateLimiter != nil {
			remaining, wasLocked := h.loginRateLimiter.HandleFailedLogin(c, req.Mobile)
			if wasLocked {
				// Account was just locked - return 423 Locked
				ttl := h.loginRateLimiter.GetAccountLockoutTTL(context.Background(), req.Mobile)
				c.Header("Retry-After", fmt.Sprintf("%d", int(ttl.Seconds())))
				c.JSON(http.StatusLocked, gin.H{
					"error":                     "account_locked",
					"message":                   "Account temporarily locked due to too many failed verification attempts.",
					"retry_after":               int(ttl.Seconds()),
					"remaining_lockout_seconds": int(ttl.Seconds()),
				})
				return
			}
			// Add remaining attempts info to error response
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":              err.Error(),
				"remaining_attempts": remaining,
			})
			return
		}

		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Clear failed attempts on successful OTP verification
	if h.loginRateLimiter != nil {
		h.loginRateLimiter.HandleSuccessfulLogin(context.Background(), req.Mobile)
	}

	c.JSON(http.StatusOK, response)
}

// ForceLoginWithOTP handles Swiggy/Zomato style force login when device limit is reached
// POST /api/auth/force-login-otp (Public - no auth required)
// This is called when:
// 1. User tried to login via OTP
// 2. Got 409 with active sessions list
// 3. User selected a session to logout
// 4. Now calling this endpoint with same OTP + session_id_to_remove
func (h *AuthHandlers) ForceLoginWithOTP(c *gin.Context) {
	var req services.ForceLoginWithOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Mobile, "mobile")
	validator.Phone(req.Mobile, "mobile")
	validator.Required(req.OTP, "otp")
	validator.MinLength(req.OTP, 6, "otp")
	validator.MaxLength(req.OTP, 6, "otp")
	validator.Required(req.SessionIDToRemove, "session_id_to_remove")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.ForceLoginWithOTP(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// Register handles user registration (after OTP verification)
func (h *AuthHandlers) Register(c *gin.Context) {
	var req services.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Email, "email")
	validator.Email(req.Email, "email")
	// Password is optional for OTP-based registration
	if req.Password != "" {
		validator.Password(req.Password, "password")
	}
	validator.Required(req.FirstName, "first_name")
	validator.Required(req.LastName, "last_name")
	validator.Required(req.Phone, "phone")
	validator.Phone(req.Phone, "phone")
	validator.Required(req.TenantName, "tenant_name")
	validator.Required(req.CompanyName, "company_name")

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
	actorRole := c.GetString("role")
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

	// Get manageable roles based on actor's role (for hierarchy-based filtering)
	// Admins and saas_admin can see all users, managers only see users below their level
	var roleFilter []string
	if actorRole != "admin" && actorRole != "saas_admin" {
		roleFilter = middleware.GetManageableRoles(actorRole)
		// Also include the actor's own role so they can see peers
		roleFilter = append(roleFilter, actorRole)
	}

	users, err := h.userService.GetUsers(c.Request.Context(), tenantID, page, pageSize, roleFilter)
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
	// Email is optional, but must be valid format if provided
	if req.Email != "" {
		validator.Email(req.Email, "email")
	}
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

	// Check role hierarchy - user can only create users below their level
	actorRole := c.GetString("role")
	if !middleware.CanManageRole(actorRole, req.Role) {
		c.JSON(http.StatusForbidden, gin.H{
			"error": fmt.Sprintf("Cannot create user with role '%s'. You can only create users below your level.", req.Role),
		})
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
	actorRole := c.GetString("role")

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

	// Get the existing user to check role hierarchy
	existingUser, err := h.userService.GetUserByID(c.Request.Context(), userID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Check if actor can manage this user's current role
	if !middleware.CanManageRole(actorRole, existingUser.Role) {
		c.JSON(http.StatusForbidden, gin.H{
			"error": fmt.Sprintf("Cannot update user with role '%s'. You can only manage users below your level.", existingUser.Role),
		})
		return
	}

	var req services.UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// If role is being updated, check if actor can assign the new role
	if req.Role != nil && *req.Role != existingUser.Role {
		if !middleware.CanManageRole(actorRole, *req.Role) {
			c.JSON(http.StatusForbidden, gin.H{
				"error": fmt.Sprintf("Cannot assign role '%s'. You can only assign roles below your level.", *req.Role),
			})
			return
		}
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
	actorRole := c.GetString("role")

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

	// Get the user to check role hierarchy before deleting
	existingUser, err := h.userService.GetUserByID(c.Request.Context(), userID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Check if actor can manage this user's role
	if !middleware.CanManageRole(actorRole, existingUser.Role) {
		c.JSON(http.StatusForbidden, gin.H{
			"error": fmt.Sprintf("Cannot delete user with role '%s'. You can only delete users below your level.", existingUser.Role),
		})
		return
	}

	if err := h.userService.DeleteUser(c.Request.Context(), userID, tenantID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User deleted successfully"})
}

// Shop Management Endpoints

// GetShops returns shops based on user role
// - Salesmen see only their assigned shop
// - Other roles see all shops in the tenant
func (h *AuthHandlers) GetShops(c *gin.Context) {
	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	userRole := c.GetString("role")

	shops, err := h.tenantService.GetShopsByUser(c.Request.Context(), tenantID, userID, userRole)
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

	// Phone and license number are optional
	if req.Phone != "" {
		validator.Phone(req.Phone, "phone")
	}

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
	tenants, err := h.tenantService.GetAllTenants(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve tenants"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"tenants":     tenants,
		"total_count": len(tenants),
	})
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
	users, err := h.userService.GetAllUsersAcrossTenants(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve users"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"users":       users,
		"total_count": len(users),
	})
}

// GetAllShops returns shops across all tenants (SaaS Admin only)
func (h *AuthHandlers) GetAllShops(c *gin.Context) {
	shops, err := h.tenantService.GetAllShops(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve shops"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"shops":       shops,
		"total_count": len(shops),
	})
}

// GetSystemStats returns system statistics (SaaS Admin only)
func (h *AuthHandlers) GetSystemStats(c *gin.Context) {
	stats, err := h.tenantService.GetSystemStats(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve system statistics"})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// ValidatePhone validates if a phone number is available for registration
// This endpoint is called by the Flutter app during user registration
func (h *AuthHandlers) ValidatePhone(c *gin.Context) {
	phone := c.Query("phone")
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"available": false,
			"message":   "phone parameter is required",
		})
		return
	}

	// Sanitize phone number (remove spaces - Flutter app sends formatted numbers with spaces)
	phone = strings.ReplaceAll(phone, " ", "")

	// Validate phone format
	validator := validators.New()
	validator.Phone(phone, "phone")
	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{
			"available": false,
			"message":   "Invalid phone number format",
		})
		return
	}

	// Check if phone already exists using the CheckUser service
	checkReq := services.CheckUserRequest{
		Phone: phone,
	}

	response, err := h.authService.CheckUser(c.Request.Context(), checkReq)
	if err != nil {
		// Check if it's a validation error (invalid format)
		if strings.Contains(err.Error(), "invalid mobile number format") {
			c.JSON(http.StatusBadRequest, gin.H{
				"available": false,
				"message":   "Invalid phone number format. Please use international format (e.g., +919876543210)",
			})
			return
		}
		// Other errors
		c.JSON(http.StatusInternalServerError, gin.H{
			"available": false,
			"message":   "Failed to validate phone number",
		})
		return
	}

	// If user exists, phone is NOT available
	if response.Exists {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"message":   "Phone number already registered",
		})
		return
	}

	// Phone doesn't exist - available for registration
	c.JSON(http.StatusOK, gin.H{
		"available": true,
		"message":   "Phone number is available",
	})
}

// ValidateEmail validates if an email is available for registration
// This endpoint is called by the Flutter app during user registration
func (h *AuthHandlers) ValidateEmail(c *gin.Context) {
	email := c.Query("email")
	if email == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"available": false,
			"message":   "email parameter is required",
		})
		return
	}

	// Validate email format
	validator := validators.New()
	validator.Email(email, "email")
	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{
			"available": false,
			"message":   "Invalid email format",
		})
		return
	}

	// Check if email already exists using the CheckUser service
	checkReq := services.CheckUserRequest{
		Email: email,
	}

	response, err := h.authService.CheckUser(c.Request.Context(), checkReq)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"available": false,
			"message":   "Failed to validate email",
		})
		return
	}

	// If user exists, email is NOT available
	if response.Exists {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"message":   "Email already registered",
		})
		return
	}

	// Email doesn't exist - available for registration
	c.JSON(http.StatusOK, gin.H{
		"available": true,
		"message":   "Email is available",
	})
}

// ValidateTenantName validates if a tenant name is available for registration
// This endpoint is called by the Flutter app during user registration
func (h *AuthHandlers) ValidateTenantName(c *gin.Context) {
	name := c.Query("name")
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"available": false,
			"message":   "name parameter is required",
		})
		return
	}

	// Validate tenant name format (lowercase, alphanumeric with hyphens)
	validator := validators.New()
	validator.Required(name, "name")
	validator.MinLength(name, 3, "name")
	validator.MaxLength(name, 50, "name")

	// Check for valid tenant name format
	for _, char := range name {
		if !((char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char == '-') {
			c.JSON(http.StatusBadRequest, gin.H{
				"available": false,
				"message":   "Tenant name must contain only lowercase letters, numbers, and hyphens",
			})
			return
		}
	}

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{
			"available": false,
			"message":   "Tenant name must be 3-50 characters",
		})
		return
	}

	// Check if tenant name already exists
	available, err := h.tenantService.IsTenantNameAvailable(c.Request.Context(), name)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"available": false,
			"message":   "Failed to validate tenant name",
		})
		return
	}

	if !available {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"message":   "Tenant name is already taken",
		})
		return
	}

	// Tenant name is available
	c.JSON(http.StatusOK, gin.H{
		"available": true,
		"message":   "Tenant name is available",
	})
}

// =============================================================================
// Device Session Management Endpoints
// =============================================================================

// GetActiveSessions returns all active device sessions for the current user
// GET /api/auth/sessions
func (h *AuthHandlers) GetActiveSessions(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	sessions, err := h.authService.GetActiveSessions(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve sessions"})
		return
	}

	// Convert to response format (hide sensitive fields)
	var response []map[string]interface{}
	for _, session := range sessions {
		sessionResp := map[string]interface{}{
			"id":             session.ID.String(),
			"device_id":      session.DeviceID,
			"device_name":    session.DeviceName,
			"device_type":    session.DeviceType,
			"os_name":        session.OSName,
			"os_version":     session.OSVersion,
			"app_version":    session.AppVersion,
			"ip_address":     session.IPAddress,
			"login_location": session.LoginLocation,
			"is_current":     session.IsCurrent,
			"created_at":     session.CreatedAt,
		}
		if session.LastActiveAt != nil {
			sessionResp["last_active_at"] = session.LastActiveAt
		}
		response = append(response, sessionResp)
	}

	c.JSON(http.StatusOK, gin.H{
		"sessions":    response,
		"total":       len(response),
		"max_devices": 2, // models.MaxDevicesPerUser
	})
}

// LogoutDevice logs out a specific device session
// DELETE /api/auth/sessions/:session_id
func (h *AuthHandlers) LogoutDevice(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	sessionIDStr := c.Param("session_id")

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID"})
		return
	}

	if err := h.authService.LogoutDevice(c.Request.Context(), userID, sessionID); err != nil {
		if err.Error() == "session not found or already logged out" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to logout device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Device logged out successfully",
		"session_id": sessionIDStr,
	})
}

// LogoutAllDevices logs out all device sessions except optionally the current one
// DELETE /api/auth/sessions
func (h *AuthHandlers) LogoutAllDevices(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	// Check if we should keep the current session
	keepCurrent := c.Query("keep_current") == "true"

	var exceptSessionID *uuid.UUID
	if keepCurrent {
		// Get current session ID from query param or header
		currentSessionStr := c.Query("current_session_id")
		if currentSessionStr == "" {
			currentSessionStr = c.GetHeader("X-Session-ID")
		}
		if currentSessionStr != "" {
			if parsed, err := uuid.Parse(currentSessionStr); err == nil {
				exceptSessionID = &parsed
			}
		}
	}

	count, err := h.authService.LogoutAllDevices(c.Request.Context(), userID, exceptSessionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to logout devices"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":         "All devices logged out successfully",
		"devices_removed": count,
	})
}

// ForceLoginRequest represents the request body for force login
type ForceLoginRequest struct {
	SessionIDToRemove string `json:"session_id_to_remove" binding:"required"`
}

// ForceLogin allows login by removing an existing session when device limit is reached
// POST /api/auth/sessions/force-login
// This is called when user selects which device to logout during the "device limit reached" flow
func (h *AuthHandlers) ForceLogin(c *gin.Context) {
	var req ForceLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "session_id_to_remove is required"})
		return
	}

	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	sessionID, err := uuid.Parse(req.SessionIDToRemove)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid session ID format"})
		return
	}

	// Logout the specified device
	if err := h.authService.LogoutDevice(c.Request.Context(), userID, sessionID); err != nil {
		if err.Error() == "session not found or already logged out" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove session"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Session removed. You can now login from your new device.",
		"session_id": req.SessionIDToRemove,
	})
}

// ============================================================================
// Account Deletion Handlers (App Store Guideline 5.1.1(v) Compliance)
// ============================================================================

// RequestDeleteAccountOTP sends OTP for account deletion verification
// POST /api/auth/account/delete/request-otp (Protected)
func (h *AuthHandlers) RequestDeleteAccountOTP(c *gin.Context) {
	// Get user ID from JWT context
	userIDStr := c.GetString("user_id")
	if userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	response, err := h.authService.RequestDeleteAccountOTP(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// DeleteAccount processes account deletion after OTP verification
// DELETE /api/auth/account (Protected)
func (h *AuthHandlers) DeleteAccount(c *gin.Context) {
	// Get user ID from JWT context
	userIDStr := c.GetString("user_id")
	if userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	var req services.DeleteAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "OTP and session_id are required"})
		return
	}

	// Set user ID from JWT context
	req.UserID = userID

	response, err := h.authService.DeleteAccount(c.Request.Context(), req)
	if err != nil {
		// Check for specific error types
		errMsg := err.Error()
		if strings.Contains(errMsg, "OTP expired") || strings.Contains(errMsg, "invalid OTP") ||
			strings.Contains(errMsg, "invalid session") || strings.Contains(errMsg, "maximum OTP attempts") {
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		return
	}

	c.JSON(http.StatusOK, response)
}

// CancelAccountDeletion cancels a pending account deletion
// POST /api/auth/account/delete/cancel (Protected)
func (h *AuthHandlers) CancelAccountDeletion(c *gin.Context) {
	// Get user ID from JWT context
	userIDStr := c.GetString("user_id")
	if userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	response, err := h.authService.CancelAccountDeletion(c.Request.Context(), userID)
	if err != nil {
		errMsg := err.Error()
		if strings.Contains(errMsg, "no pending account deletion") {
			c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
			return
		}
		if strings.Contains(errMsg, "grace period has expired") {
			c.JSON(http.StatusGone, gin.H{"error": errMsg})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		return
	}

	c.JSON(http.StatusOK, response)
}
