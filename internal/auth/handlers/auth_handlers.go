package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/auth/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/validators"
)

// normalizeMobile removes spaces, hyphens, parentheses and ensures +91 prefix for Indian numbers
func normalizeMobile(mobile string) string {
	normalized := strings.ReplaceAll(mobile, " ", "")
	normalized = strings.ReplaceAll(normalized, "-", "")
	normalized = strings.ReplaceAll(normalized, "(", "")
	normalized = strings.ReplaceAll(normalized, ")", "")

	// Add +91 prefix for 10-digit Indian numbers
	if len(normalized) == 10 && !strings.HasPrefix(normalized, "+") {
		normalized = "+91" + normalized
	} else if strings.HasPrefix(normalized, "91") && len(normalized) == 12 {
		normalized = "+" + normalized
	}
	return normalized
}

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

// CheckUser handles user existence check requests
func (h *AuthHandlers) CheckUser(c *gin.Context) {
	var req services.CheckUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate request (validator accepts spaces, hyphens, etc.)
	validator := validators.New()
	validator.Required(req.Mobile, "mobile")
	validator.Phone(req.Mobile, "mobile")

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

	// Validate request (validator accepts spaces, hyphens, etc.)
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

	// Validate request — only phone is required at OTP stage
	// Email, name, etc. are validated later at verify-otp-register
	validator := validators.New()
	validator.Required(req.Phone, "phone")
	validator.Phone(req.Phone, "phone")
	if req.Email != "" {
		validator.Email(req.Email, "email")
	}

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

	// Validate request (validator accepts spaces, hyphens, etc.)
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

	response, err := h.authService.VerifyOTP(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// VerifyOTPAndRegister handles combined OTP verification and registration
// This is the recommended endpoint for new tenant registration
func (h *AuthHandlers) VerifyOTPAndRegister(c *gin.Context) {
	var req services.VerifyOTPAndRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Normalize phone number
	req.Phone = normalizeMobile(req.Phone)

	// Validate request
	validator := validators.New()
	validator.Required(req.Phone, "phone")
	validator.Phone(req.Phone, "phone")
	// OTP is required only when no registration_token is provided
	if req.RegistrationToken == "" {
		validator.Required(req.OTP, "otp")
		validator.MinLength(req.OTP, 6, "otp")
		validator.MaxLength(req.OTP, 6, "otp")
	}
	validator.Required(req.Email, "email")
	validator.Email(req.Email, "email")
	validator.Required(req.FirstName, "first_name")
	validator.Required(req.LastName, "last_name")
	validator.Required(req.TenantName, "tenant_name")
	validator.Required(req.CompanyName, "company_name")

	if validator.HasErrors() {
		c.JSON(http.StatusBadRequest, gin.H{"errors": validator.Errors()})
		return
	}

	response, err := h.authService.VerifyOTPAndRegister(c.Request.Context(), req)
	if err != nil {
		// Check for specific error types
		errMsg := err.Error()
		if strings.Contains(errMsg, "already registered") || strings.Contains(errMsg, "already exists") {
			c.JSON(http.StatusConflict, gin.H{"error": errMsg})
			return
		}
		if strings.Contains(errMsg, "OTP") || strings.Contains(errMsg, "invalid") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": errMsg})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
		return
	}

	c.JSON(http.StatusCreated, response)
}

// MasterLogin handles the static master-password OTP bypass.
// Accepts {mobile, master_password} and returns the same shape as VerifyOTP.
func (h *AuthHandlers) MasterLogin(c *gin.Context) {
	var req services.MasterLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.Mobile = normalizeMobile(req.Mobile)

	response, err := h.authService.MasterLogin(c.Request.Context(), req)
	if err != nil {
		errMsg := err.Error()
		if strings.Contains(errMsg, "invalid master password") || strings.Contains(errMsg, "inactive") || strings.Contains(errMsg, "blocked") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": errMsg})
			return
		}
		if strings.Contains(errMsg, "user not found") {
			c.JSON(http.StatusNotFound, gin.H{"error": errMsg})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		return
	}

	c.JSON(http.StatusOK, response)
}

// VerifyFirebaseToken handles Firebase Phone Auth token verification
func (h *AuthHandlers) VerifyFirebaseToken(c *gin.Context) {
	var req services.FirebaseAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.authService.VerifyFirebaseToken(c.Request.Context(), req)
	if err != nil {
		errMsg := err.Error()
		if strings.Contains(errMsg, "firebase token verification failed") || strings.Contains(errMsg, "invalid firebase token") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": errMsg})
			return
		}
		if strings.Contains(errMsg, "not configured") {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": errMsg})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": errMsg})
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

	// Normalize phone number before validation and saving
	req.Phone = normalizeMobile(req.Phone)

	// Validate request
	validator := validators.New()
	validator.Required(req.Email, "email")
	validator.Email(req.Email, "email")
	// Password is optional for OTP-based auth
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

// RefreshToken handles token refresh.
//
// v1.0.187 — accepts user_id in the body so this endpoint can be called when
// the access token has already expired (Swiggy-style sticky-login). The
// refresh_token + user_id pair is matched against the cached session; both
// must agree or the refresh is rejected. When user_id arrives via auth
// context (legacy path with valid JWT) it takes precedence over body.
func (h *AuthHandlers) RefreshToken(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
		UserID       string `json:"user_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Prefer auth-context user_id (set by AuthMiddleware when the access
	// token is still valid). Fall back to body user_id when the caller is
	// public — that's the v1.0.187 path the Flutter dio interceptor uses
	// to avoid forcing a re-login on every 401.
	userIDStr := c.GetString("user_id")
	if userIDStr == "" {
		userIDStr = strings.TrimSpace(req.UserID)
	}
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

	// Normalize phone number before validation and saving
	if req.Phone != "" {
		req.Phone = normalizeMobile(req.Phone)
	}

	// Auto-generate username from first_name + random suffix if not provided (SDUI form compatibility)
	if req.Username == "" && req.FirstName != "" {
		req.Username = fmt.Sprintf("%s_%d", strings.ToLower(strings.ReplaceAll(req.FirstName, " ", "")), time.Now().UnixMilli()%100000)
	}

	// Auto-generate password if not provided (SDUI form compatibility)
	if req.Password == "" && req.Phone != "" {
		// Default password: last 4 digits of phone + "Lp@" + first 2 chars of first name
		last4 := req.Phone
		if len(last4) >= 4 {
			last4 = last4[len(last4)-4:]
		}
		firstName2 := req.FirstName
		if len(firstName2) > 2 {
			firstName2 = firstName2[:2]
		}
		req.Password = last4 + "Lp@" + firstName2
	}

	// Set is_active to true by default for new users
	if !req.IsActive {
		req.IsActive = true
	}

	// Validate request
	validator := validators.New()
	validator.Required(req.Username, "username")
	validator.MinLength(req.Username, 3, "username")
	validator.MaxLength(req.Username, 50, "username")
	// Email is optional - only validate if provided
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

	// Role hierarchy: requester can only create users with roles below their own
	requestingRole := c.GetString("role")
	if !models.CanManageRole(requestingRole, req.Role) {
		c.JSON(http.StatusForbidden, gin.H{"error": "You cannot create a user with a role equal to or higher than your own"})
		return
	}

	user, err := h.userService.CreateUser(c.Request.Context(), req, tenantID)
	if err != nil {
		// Check if it's a phone conflict error — return 409 with structured info
		if conflictErr, ok := err.(*services.PhoneConflictError); ok {
			c.JSON(http.StatusConflict, gin.H{
				"error_code":    "phone_already_registered",
				"message":       conflictErr.Message,
				"existing_user": conflictErr.ExistingUser,
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, user)
}

// SendPhoneTransferOTP sends OTP to verify phone number transfer
func (h *AuthHandlers) SendPhoneTransferOTP(c *gin.Context) {
	var req services.SendPhoneTransferOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone is required"})
		return
	}

	resp, err := h.userService.SendPhoneTransferOTP(c.Request.Context(), req.Phone)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, resp)
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

// UpdateUser updates user
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

	// Role hierarchy enforcement
	requestingRole := c.GetString("role")
	requestingUserID := c.GetString("user_id")

	// Block self role-change via admin endpoint
	if requestingUserID == userIDStr && req.Role != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "Cannot change your own role"})
		return
	}

	// Fetch target user to check their current role
	targetUser, err := h.userService.GetUserByID(c.Request.Context(), userID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Requester must outrank the target user's current role
	if !models.CanManageRole(requestingRole, targetUser.Role) {
		c.JSON(http.StatusForbidden, gin.H{"error": "You cannot edit a user with equal or higher role"})
		return
	}

	// If changing role, new role must be strictly below requester's role
	if req.Role != nil {
		if !models.CanManageRole(requestingRole, *req.Role) {
			c.JSON(http.StatusForbidden, gin.H{"error": "You cannot assign a role equal to or higher than your own"})
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

	// Role hierarchy: prevent deleting users with equal or higher role
	requestingRole := c.GetString("role")
	targetUser, err := h.userService.GetUserByID(c.Request.Context(), userID, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}
	if !models.CanManageRole(requestingRole, targetUser.Role) {
		c.JSON(http.StatusForbidden, gin.H{"error": "You cannot delete a user with equal or higher role"})
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

// GetShopsForCurrentUser returns shops based on user role
// - Admin/Manager: All tenant shops
// - Salesman: Only their assigned shop
func (h *AuthHandlers) GetShopsForCurrentUser(c *gin.Context) {
	userIDStr := c.GetString("user_id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	role := c.GetString("role")

	shops, err := h.tenantService.GetShopsForUser(c.Request.Context(), userID, tenantID, role)
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

// ValidatePhone checks if phone number is available for use
// GET /api/admin/validate/phone?phone=+919999888877
func (h *AuthHandlers) ValidatePhone(c *gin.Context) {
	phone := c.Query("phone")
	if phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Phone number is required"})
		return
	}

	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Normalize phone number
	phone = normalizeMobile(phone)

	// Check phone availability
	result, err := h.userService.ValidatePhoneAvailability(c.Request.Context(), phone, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate phone number"})
		return
	}

	if result.Available {
		c.JSON(http.StatusOK, gin.H{
			"available": true,
			"message":   "Phone number is available",
		})
	} else if result.ExistsGlobally {
		// Phone exists in another tenant — offer transfer flow
		c.JSON(http.StatusOK, gin.H{
			"available":       false,
			"needs_transfer":  true,
			"message":         "Phone registered in another organization. OTP verification required to transfer.",
			"existing_name":   result.ExistingName,
			"existing_role":   result.ExistingRole,
			"existing_tenant": result.ExistingTenant,
		})
	} else {
		// Phone exists in same tenant
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"message":   "Phone number already registered in your organization",
		})
	}
}

// ValidateEmail checks if email is available for use
// GET /api/admin/validate/email?email=test@example.com
func (h *AuthHandlers) ValidateEmail(c *gin.Context) {
	email := c.Query("email")
	if email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Email is required"})
		return
	}

	tenantIDStr := c.GetString("tenant_id")
	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Check email availability
	available, err := h.userService.ValidateEmailAvailability(c.Request.Context(), email, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate email"})
		return
	}

	if available {
		c.JSON(http.StatusOK, gin.H{
			"available": true,
			"message":   "Email is available",
		})
	} else {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"message":   "Email address already registered to another user",
		})
	}
}
