package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// AuthService handles authentication operations
type AuthService struct {
	db               *database.DB
	cache            *cache.Cache
	config           *config.JWTConfig
	rateLimitService *RateLimitService
}

// NewAuthService creates a new auth service
func NewAuthService(db *database.DB, cache *cache.Cache, jwtConfig *config.JWTConfig, rateLimitService *RateLimitService) *AuthService {
	return &AuthService{
		db:               db,
		cache:            cache,
		config:           jwtConfig,
		rateLimitService: rateLimitService,
	}
}

// LoginRequest represents login request data
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// LoginResponse represents login response data
type LoginResponse struct {
	Token        string          `json:"token"`
	RefreshToken string          `json:"refresh_token"`
	ExpiresAt    time.Time       `json:"expires_at"`
	User         *UserResponse   `json:"user"`
	Tenant       *TenantResponse `json:"tenant"`
}

// UserResponse represents user data in responses
type UserResponse struct {
	ID           uuid.UUID `json:"id"`
	Username     string    `json:"username"`
	Email        string    `json:"email"`
	FirstName    string    `json:"first_name"`
	LastName     string    `json:"last_name"`
	Role         string    `json:"role"`
	IsActive     bool      `json:"is_active"`
	ProfileImage string    `json:"profile_image"`
	TenantName   string    `json:"tenant_name,omitempty"`
}

// TenantResponse represents tenant data in responses
type TenantResponse struct {
	ID       uuid.UUID `json:"id"`
	Name     string    `json:"name"`
	Domain   string    `json:"domain"`
	IsActive bool      `json:"is_active"`
}

// RegisterRequest represents registration request data (after OTP verification)
type RegisterRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required,min=8"`
	FirstName   string `json:"first_name" binding:"required"`
	LastName    string `json:"last_name" binding:"required"`
	Phone       string `json:"phone" binding:"required"`
	TenantName  string `json:"tenant_name" binding:"required"`
	CompanyName string `json:"company_name" binding:"required"`
}

// CheckUserRequest represents check user existence request
type CheckUserRequest struct {
	Mobile string `json:"mobile" binding:"required"`
}

// CheckUserResponse represents check user existence response
type CheckUserResponse struct {
	Exists  bool   `json:"exists"`
	Message string `json:"message"`
}

// SendOTPRequest represents send OTP request data
type SendOTPRequest struct {
	Mobile string `json:"mobile" binding:"required"`
}

// SendOTPResponse represents send OTP response data
type SendOTPResponse struct {
	Message   string    `json:"message"`
	OTPSentAt time.Time `json:"otp_sent_at"`
	ExpiresAt time.Time `json:"expires_at"`
	SessionID string    `json:"session_id"`
	Purpose   string    `json:"purpose"` // "login" or "registration"
}

// VerifyOTPRequest represents verify OTP request data
type VerifyOTPRequest struct {
	Mobile    string `json:"mobile" binding:"required"`
	OTP       string `json:"otp" binding:"required"`
	SessionID string `json:"session_id"`
}

// VerifyOTPResponse represents verify OTP response data (same as LoginResponse)
// VerifyOTPResponse represents the response for OTP verification
type VerifyOTPResponse struct {
	Token        string          `json:"token,omitempty"`
	RefreshToken string          `json:"refresh_token,omitempty"`
	ExpiresAt    time.Time       `json:"expires_at,omitempty"`
	User         *UserResponse   `json:"user,omitempty"`
	Tenant       *TenantResponse `json:"tenant,omitempty"`
	Message      string          `json:"message,omitempty"`
	Purpose      string          `json:"purpose,omitempty"` // "login" or "registration"
}

// Login authenticates user and returns JWT token
func (s *AuthService) Login(ctx context.Context, req LoginRequest) (*LoginResponse, error) {
	// Find user by username or email
	var user models.User
	err := s.db.Where("username = ? OR email = ?", req.Username, req.Username).
		Preload("Tenant").
		First(&user).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("invalid credentials")
		}
		return nil, fmt.Errorf("failed to find user: %w", err)
	}

	// Check if user is active
	if !user.IsActive {
		return nil, errors.New("account is inactive")
	}

	// Verify password
	if !utils.CheckPassword(req.Password, user.PasswordHash) {
		return nil, errors.New("invalid credentials")
	}

	// Check if tenant is active
	if user.Tenant != nil && !user.Tenant.IsActive {
		return nil, errors.New("tenant account is inactive")
	}

	// Generate JWT token
	token, expiresAt, err := s.generateJWTToken(&user)
	if err != nil {
		return nil, fmt.Errorf("failed to generate token: %w", err)
	}

	// Generate refresh token
	refreshToken, err := s.generateRefreshToken(&user)
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}

	// Store session in cache
	sessionKey := fmt.Sprintf(cache.UserSessionKey, user.ID.String())
	sessionData := map[string]interface{}{
		"user_id":       user.ID.String(),
		"role":          user.Role,
		"login_time":    time.Now(),
		"refresh_token": refreshToken,
	}

	// Add tenant_id only if user has a tenant
	if user.TenantID != nil {
		sessionData["tenant_id"] = user.TenantID.String()
	}

	if err := s.cache.Set(ctx, sessionKey, sessionData, cache.SessionTTL); err != nil {
		// Log error but don't fail login
		fmt.Printf("Warning: Failed to store session in cache: %v\n", err)
	}

	return &LoginResponse{
		Token:        token,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt,
		User:         s.mapUserToResponse(&user),
		Tenant:       s.mapTenantToResponse(user.Tenant),
	}, nil
}

// Register creates a new user and tenant
// Register handles user registration (after OTP verification)
func (s *AuthService) Register(ctx context.Context, req RegisterRequest) (*LoginResponse, error) {
	var result *LoginResponse

	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Check if user already exists by email
		var existingUser models.User
		if err := tx.Where("email = ?", req.Email).First(&existingUser).Error; err == nil {
			return errors.New("email already exists")
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("failed to check existing user: %w", err)
		}

		// Generate username from email (part before @)
		username := req.Email[:strings.Index(req.Email, "@")]

		// Ensure username is unique by appending numbers if needed
		originalUsername := username
		counter := 1
		for {
			var existingUserByUsername models.User
			if err := tx.Where("username = ?", username).First(&existingUserByUsername).Error; errors.Is(err, gorm.ErrRecordNotFound) {
				break // Username is available
			} else if err != nil {
				return fmt.Errorf("failed to check username: %w", err)
			}
			username = fmt.Sprintf("%s%d", originalUsername, counter)
			counter++
		}

		// Hash password
		hashedPassword, err := utils.HashPassword(req.Password)
		if err != nil {
			return fmt.Errorf("failed to hash password: %w", err)
		}

		// Create tenant
		tenant := models.Tenant{
			Name:     req.CompanyName,
			Domain:   req.TenantName,
			IsActive: true,
		}

		if err := tx.Create(&tenant).Error; err != nil {
			return fmt.Errorf("failed to create tenant: %w", err)
		}

		// Create user
		user := models.User{
			TenantID:     &tenant.ID,
			Username:     username, // Auto-generated username
			Email:        req.Email,
			FirstName:    req.FirstName,
			LastName:     req.LastName,
			Phone:        req.Phone,
			PasswordHash: hashedPassword,
			Role:         models.RoleAdmin, // First user becomes admin
			IsActive:     true,
		}

		if err := tx.Create(&user).Error; err != nil {
			return fmt.Errorf("failed to create user: %w", err)
		}

		// Generate tokens
		token, expiresAt, err := s.generateJWTToken(&user)
		if err != nil {
			return fmt.Errorf("failed to generate token: %w", err)
		}

		refreshToken, err := s.generateRefreshToken(&user)
		if err != nil {
			return fmt.Errorf("failed to generate refresh token: %w", err)
		}

		// Store session in cache
		sessionKey := fmt.Sprintf(cache.UserSessionKey, user.ID.String())
		sessionData := map[string]interface{}{
			"user_id":       user.ID.String(),
			"role":          user.Role,
			"login_time":    time.Now(),
			"refresh_token": refreshToken,
		}

		// Add tenant_id only if user has a tenant
		if user.TenantID != nil {
			sessionData["tenant_id"] = user.TenantID.String()
		}

		if err := s.cache.Set(ctx, sessionKey, sessionData, cache.SessionTTL); err != nil {
			fmt.Printf("Warning: Failed to store session in cache: %v\n", err)
		}

		result = &LoginResponse{
			Token:        token,
			RefreshToken: refreshToken,
			ExpiresAt:    expiresAt,
			User:         s.mapUserToResponse(&user),
			Tenant:       s.mapTenantToResponse(&tenant),
		}
		return nil
	})

	if err != nil {
		return nil, err
	}

	return result, nil
}

// Logout invalidates user session
func (s *AuthService) Logout(ctx context.Context, userID uuid.UUID) error {
	sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
	return s.cache.Delete(ctx, sessionKey)
}

// RefreshToken generates a new access token using refresh token
func (s *AuthService) RefreshToken(ctx context.Context, refreshToken string, userID uuid.UUID) (*LoginResponse, error) {
	// Verify refresh token from cache
	sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
	var sessionData map[string]interface{}

	if err := s.cache.Get(ctx, sessionKey, &sessionData); err != nil {
		return nil, errors.New("invalid refresh token")
	}

	storedRefreshToken, ok := sessionData["refresh_token"].(string)
	if !ok || storedRefreshToken != refreshToken {
		return nil, errors.New("invalid refresh token")
	}

	// Get user from database
	var user models.User
	err := s.db.Where("id = ?", userID).Preload("Tenant").First(&user).Error
	if err != nil {
		return nil, fmt.Errorf("failed to find user: %w", err)
	}

	// Generate new tokens
	newToken, expiresAt, err := s.generateJWTToken(&user)
	if err != nil {
		return nil, fmt.Errorf("failed to generate token: %w", err)
	}

	newRefreshToken, err := s.generateRefreshToken(&user)
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}

	// Update session in cache
	sessionData["refresh_token"] = newRefreshToken
	sessionData["login_time"] = time.Now()

	if err := s.cache.Set(ctx, sessionKey, sessionData, cache.SessionTTL); err != nil {
		fmt.Printf("Warning: Failed to update session in cache: %v\n", err)
	}

	return &LoginResponse{
		Token:        newToken,
		RefreshToken: newRefreshToken,
		ExpiresAt:    expiresAt,
		User:         s.mapUserToResponse(&user),
		Tenant:       s.mapTenantToResponse(user.Tenant),
	}, nil
}

// ValidateToken validates JWT token
func (s *AuthService) ValidateToken(tokenString string) (*jwt.MapClaims, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(s.config.Secret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return &claims, nil
	}

	return nil, errors.New("invalid token")
}

// generateJWTToken creates a JWT token for the user
func (s *AuthService) generateJWTToken(user *models.User) (string, time.Time, error) {
	expiresAt := time.Now().Add(time.Duration(s.config.ExpirationHours) * time.Hour)

	claims := jwt.MapClaims{
		"user_id":   user.ID.String(),
		"tenant_id": user.TenantID.String(),
		"username":  user.Username,
		"email":     user.Email,
		"role":      user.Role,
		"iat":       time.Now().Unix(),
		"exp":       expiresAt.Unix(),
		"iss":       s.config.Issuer,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(s.config.Secret))
	if err != nil {
		return "", time.Time{}, err
	}

	return tokenString, expiresAt, nil
}

// generateRefreshToken creates a refresh token
func (s *AuthService) generateRefreshToken(user *models.User) (string, error) {
	refreshToken, err := utils.GenerateRandomString(64)
	if err != nil {
		return "", err
	}
	return refreshToken, nil
}

// mapUserToResponse converts user model to response format
func (s *AuthService) mapUserToResponse(user *models.User) *UserResponse {
	response := &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}

	// Add tenant information if available
	if user.Tenant != nil {
		response.TenantName = user.Tenant.Name
	} else if user.Role == models.RoleSaasAdmin {
		// This is a Super User (SaaS Admin)
		response.TenantName = "System Admin"
	}

	return response
}

// mapTenantToResponse converts tenant model to response format
func (s *AuthService) mapTenantToResponse(tenant *models.Tenant) *TenantResponse {
	if tenant == nil {
		return nil
	}
	return &TenantResponse{
		ID:       tenant.ID,
		Name:     tenant.Name,
		Domain:   tenant.Domain,
		IsActive: tenant.IsActive,
	}
}

// VerifyOTP verifies OTP and logs in user (static OTP: 000000)
// Security Helper Methods for Scalable OTP System

// isValidMobileNumber validates mobile number format (international format)
func (s *AuthService) isValidMobileNumber(mobile string) bool {
	// Regex for international mobile number format (+countrycode followed by digits)
	mobileRegex := regexp.MustCompile(`^\+[1-9]\d{1,14}$`)
	return mobileRegex.MatchString(mobile)
}

// checkOTPRateLimit implements rate limiting for OTP requests using dynamic rate limiting
func (s *AuthService) checkOTPRateLimit(ctx context.Context, mobile string) error {
	// Use dynamic rate limiting system
	isBlocked, err := s.rateLimitService.CheckRateLimit(
		"otp_requests", // rate limit name
		mobile,         // identifier (mobile number)
		nil,            // tenant ID (nil for global)
		nil,            // user ID (nil for OTP requests)
		"",             // request IP (not available in this context)
		"",             // user agent (not available in this context)
	)

	if err != nil {
		// If there's an error with the rate limiting service, fall back to allowing the request
		// but log the error for monitoring
		fmt.Printf("Rate limiting service error: %v\n", err)
		return nil
	}

	if isBlocked {
		return errors.New("too many OTP requests. Please try again later")
	}

	return nil
}

// incrementOTPCounter is handled by the dynamic rate limiting system
// This function is no longer needed as CheckRateLimit automatically handles counting

// generateSecureSessionID creates a cryptographically secure session ID
func (s *AuthService) generateSecureSessionID() string {
	// Generate 32 random bytes and encode as hex (64 characters)
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		// Fallback to UUID if crypto/rand fails
		return uuid.New().String()
	}
	return hex.EncodeToString(bytes)
}

// generateSecureOTP generates a cryptographically secure 6-digit OTP
func (s *AuthService) generateSecureOTP() string {
	// Generate secure random 6-digit number
	max := big.NewInt(999999)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		// Fallback to time-based if crypto/rand fails
		return fmt.Sprintf("%06d", time.Now().Unix()%1000000)
	}

	// Ensure it's always 6 digits (pad with leading zeros)
	return fmt.Sprintf("%06d", n.Int64())
}

// hashOTP creates a SHA-256 hash of the OTP for secure storage
func (s *AuthService) hashOTP(otp string) string {
	hash := sha256.Sum256([]byte(otp))
	return hex.EncodeToString(hash[:])
}

// verifyOTPHash compares provided OTP with stored hash
func (s *AuthService) verifyOTPHash(providedOTP, storedHash string) bool {
	providedHash := s.hashOTP(providedOTP)
	return providedHash == storedHash
}

// determinePurpose determines if OTP is for login or registration
func (s *AuthService) determinePurpose(userExists bool) string {
	if userExists {
		return "login"
	}
	return "registration"
}

// logOTPRequest logs OTP requests for monitoring and security analysis
func (s *AuthService) logOTPRequest(ctx context.Context, mobile string, userExists bool, sessionID string) {
	// Log for monitoring (without sensitive data)
	logData := map[string]interface{}{
		"event":      "otp_requested",
		"mobile":     s.maskMobileNumber(mobile), // Mask for privacy
		"purpose":    s.determinePurpose(userExists),
		"session_id": sessionID,
		"timestamp":  time.Now().Unix(),
	}

	// Store log in Redis for analysis (with 7 days retention)
	logKey := fmt.Sprintf("audit:otp_request:%s:%d", sessionID, time.Now().Unix())
	s.cache.Set(ctx, logKey, logData, 7*24*time.Hour)
}

// maskMobileNumber masks mobile number for privacy (keep country code + last 4 digits)
func (s *AuthService) maskMobileNumber(mobile string) string {
	if len(mobile) <= 7 {
		return mobile // Too short to mask meaningfully
	}

	// Show country code and last 4 digits: +91****1234
	countryCodeEnd := 3 // Assume +XX format
	if len(mobile) > 4 {
		lastFour := mobile[len(mobile)-4:]
		prefix := mobile[:countryCodeEnd]
		stars := strings.Repeat("*", len(mobile)-countryCodeEnd-4)
		return prefix + stars + lastFour
	}

	return mobile
}

// Additional security methods for monitoring suspicious activities

// detectSuspiciousActivity analyzes patterns for potential abuse
func (s *AuthService) detectSuspiciousActivity(ctx context.Context, mobile string) bool {
	// Check for multiple failed OTP attempts in short time
	failureKey := fmt.Sprintf("otp_failures:%s", mobile)
	var failureCount int
	s.cache.Get(ctx, failureKey, &failureCount)

	// Flag as suspicious if more than 10 failures in 1 hour
	return failureCount > 10
}

// blockSuspiciousNumber temporarily blocks a mobile number
func (s *AuthService) blockSuspiciousNumber(ctx context.Context, mobile string, duration time.Duration) {
	blockKey := fmt.Sprintf("blocked:mobile:%s", mobile)
	blockData := map[string]interface{}{
		"blocked_at": time.Now().Unix(),
		"reason":     "suspicious_activity",
	}
	s.cache.Set(ctx, blockKey, blockData, duration)
}

// isNumberBlocked checks if a mobile number is temporarily blocked
func (s *AuthService) isNumberBlocked(ctx context.Context, mobile string) bool {
	blockKey := fmt.Sprintf("blocked:mobile:%s", mobile)
	var blockData map[string]interface{}
	err := s.cache.Get(ctx, blockKey, &blockData)
	return err == nil // If key exists, number is blocked
}

// SendOTP sends OTP to mobile number after validating phone/email uniqueness
func (s *AuthService) SendOTP(ctx context.Context, req SendOTPRequest) (*SendOTPResponse, error) {
	mobile := req.Mobile

	// Security: Validate and sanitize mobile number
	if !s.isValidMobileNumber(mobile) {
		return nil, errors.New("invalid mobile number format")
	}

	// Security: Check if number is blocked due to suspicious activity
	if s.isNumberBlocked(ctx, mobile) {
		return nil, errors.New("mobile number temporarily blocked due to suspicious activity")
	}

	// Security: Rate limiting - check if too many OTP requests from this mobile
	if err := s.checkOTPRateLimit(ctx, mobile); err != nil {
		return nil, err
	}

	// REQUIREMENT: Check if phone number already exists (primary unique key)
	var existingUserByPhone models.User
	err := s.db.Where("phone = ?", mobile).First(&existingUserByPhone).Error

	if err == nil {
		// Phone exists - this is LOGIN flow
		if !existingUserByPhone.IsActive {
			return nil, errors.New("user account is inactive")
		}
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		// Database error
		return nil, fmt.Errorf("failed to check phone number: %w", err)
	}
	// If ErrRecordNotFound - phone doesn't exist, this is REGISTRATION flow

	// Security: Generate cryptographically secure session ID
	sessionID := s.generateSecureSessionID()

	// Security: Generate secure OTP (for production, use random 6-digit)
	otp := s.getOTPForMobile(mobile) // Handle special OTPs for specific mobiles
	if s.isProduction() && otp == "" {
		otp = s.generateSecureOTP()
	}

	// Security: Hash OTP before storing
	hashedOTP := s.hashOTP(otp)

	// Store OTP data in Redis with expiration (10 minutes as requested)
	otpData := map[string]interface{}{
		"hashed_otp":   hashedOTP,
		"mobile":       mobile,
		"attempts":     0,
		"created_at":   time.Now().Unix(),
		"session_id":   sessionID,
		"max_attempts": 3,
		"purpose":      s.determineOTPPurpose(err == nil), // login if user exists, registration if not
	}

	// REQUIREMENT: 10 minutes validity as specified
	expiryDuration := 10 * time.Minute
	otpKey := fmt.Sprintf("otp:%s", mobile)

	if err := s.cache.Set(ctx, otpKey, otpData, expiryDuration); err != nil {
		return nil, fmt.Errorf("failed to store OTP: %w", err)
	}

	// In production, send actual SMS here
	// For development, we'll just log it (remove in production)
	if !s.isProduction() {
		fmt.Printf("📱 OTP for %s: %s (Development Mode)\n", s.maskMobileNumber(mobile), otp)
	}

	// Update rate limiting counter
	// Rate limiting counter is automatically handled by CheckRateLimit

	now := time.Now()
	return &SendOTPResponse{
		Message:   fmt.Sprintf("OTP sent successfully to %s", s.maskMobileNumber(mobile)),
		OTPSentAt: now,
		ExpiresAt: now.Add(expiryDuration),
		SessionID: sessionID,
		Purpose:   s.determineOTPPurpose(err == nil), // login if user exists, registration if not
	}, nil
}

// Enhanced VerifyOTP with proper validation
func (s *AuthService) VerifyOTP(ctx context.Context, req VerifyOTPRequest) (*VerifyOTPResponse, error) {
	mobile := req.Mobile
	providedOTP := req.OTP

	// Security validations
	if !s.isValidMobileNumber(mobile) {
		return nil, errors.New("invalid mobile number format")
	}

	if s.isNumberBlocked(ctx, mobile) {
		return nil, errors.New("mobile number temporarily blocked")
	}

	// Retrieve OTP data
	otpKey := fmt.Sprintf("otp:%s", mobile)
	var otpData map[string]interface{}
	err := s.cache.Get(ctx, otpKey, &otpData)
	if err != nil {
		return nil, errors.New("OTP expired or not found")
	}

	// Verify session ID if provided
	if req.SessionID != "" {
		if storedSessionID, ok := otpData["session_id"].(string); ok {
			if storedSessionID != req.SessionID {
				return nil, errors.New("invalid session")
			}
		}
	}

	// Check attempt limit
	attempts, _ := otpData["attempts"].(float64)
	maxAttempts, _ := otpData["max_attempts"].(float64)
	if attempts >= maxAttempts {
		s.cache.Delete(ctx, otpKey)
		s.blockSuspiciousNumber(ctx, mobile, 1*time.Hour)
		return nil, errors.New("maximum OTP attempts exceeded")
	}

	// Verify OTP
	storedHashedOTP, ok := otpData["hashed_otp"].(string)
	if !ok {
		return nil, errors.New("invalid OTP data")
	}

	if !s.verifyOTPHash(providedOTP, storedHashedOTP) {
		// Increment attempts counter
		attempts++
		otpData["attempts"] = attempts
		s.cache.Set(ctx, otpKey, otpData, 10*time.Minute)

		// Track failed attempts
		s.incrementFailureCounter(ctx, mobile)

		return nil, errors.New("invalid OTP")
	}

	// OTP verified successfully - clear it
	s.cache.Delete(ctx, otpKey)

	// Determine purpose and handle accordingly
	purpose, _ := otpData["purpose"].(string)

	if purpose == "login" {
		// Login flow - user exists
		var user models.User
		err := s.db.Where("phone = ?", mobile).Preload("Tenant").First(&user).Error
		if err != nil {
			return nil, fmt.Errorf("user not found: %w", err)
		}

		// Handle Super User (SaaS admin) - they don't have a tenant
		var tenantID uuid.UUID
		if user.Role == models.RoleSaasAdmin && user.IsSuperuser {
			tenantID = uuid.Nil // Super users have no tenant restriction
		} else {
			if user.TenantID != nil {
				tenantID = *user.TenantID
			}
		}

		// Generate JWT token
		tokenString, refreshToken, expiresAt, err := s.generateTokensWithRole(user.ID, tenantID, user.Role)
		if err != nil {
			return nil, fmt.Errorf("failed to generate tokens: %w", err)
		}

		// Store session in cache
		sessionKey := fmt.Sprintf(cache.UserSessionKey, user.ID.String())
		sessionData := map[string]interface{}{
			"user_id":       user.ID.String(),
			"role":          user.Role,
			"is_superuser":  user.IsSuperuser,
			"refresh_token": refreshToken,
			"login_time":    time.Now(),
		}

		// Add tenant_id only if user has a tenant (not for Super Users)
		if tenantID != uuid.Nil {
			sessionData["tenant_id"] = tenantID.String()
		} else {
			sessionData["tenant_id"] = nil // Explicitly set to nil for Super Users
		}

		if err := s.cache.Set(ctx, sessionKey, sessionData, 24*time.Hour); err != nil {
			return nil, fmt.Errorf("failed to store session: %w", err)
		}

		return &VerifyOTPResponse{
			Token:        tokenString,
			RefreshToken: refreshToken,
			ExpiresAt:    expiresAt,
			User:         s.mapUserToResponse(&user),
			Tenant:       s.mapTenantToResponse(user.Tenant),
			Message:      "Login successful",
			Purpose:      "login",
		}, nil
	} else {
		// Registration flow - user doesn't exist yet
		return &VerifyOTPResponse{
			Message: "Phone verified successfully. Please complete registration.",
			Purpose: "registration",
		}, nil
	}
}

// Enhanced SendOTPForRegistration with email validation
type SendOTPForRegistrationRequest struct {
	Phone     string `json:"phone" binding:"required"`
	Email     string `json:"email" binding:"required,email"`
	FirstName string `json:"first_name" binding:"required"`
}

func (s *AuthService) SendOTPForRegistration(ctx context.Context, req SendOTPForRegistrationRequest) (*SendOTPResponse, error) {
	// REQUIREMENT: Validate phone number uniqueness (primary key)
	var existingUserByPhone models.User
	err := s.db.Where("phone = ?", req.Phone).First(&existingUserByPhone).Error
	if err == nil {
		return nil, errors.New("phone number already registered")
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("failed to check phone number: %w", err)
	}

	// REQUIREMENT: Validate email uniqueness (secondary key)
	var existingUserByEmail models.User
	err = s.db.Where("email = ?", req.Email).First(&existingUserByEmail).Error
	if err == nil {
		return nil, errors.New("email already registered")
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("failed to check email: %w", err)
	}

	// Both phone and email are unique - proceed with OTP
	return s.SendOTP(ctx, SendOTPRequest{Mobile: req.Phone})
}

// CheckUser checks if a user exists by mobile number without sending OTP
func (s *AuthService) CheckUser(ctx context.Context, req CheckUserRequest) (*CheckUserResponse, error) {
	mobile := req.Mobile

	// Security: Validate and sanitize mobile number
	if !s.isValidMobileNumber(mobile) {
		return nil, errors.New("invalid mobile number format")
	}

	// Check if user exists by mobile number
	var existingUser models.User
	err := s.db.Where("phone = ?", mobile).First(&existingUser).Error

	if err == nil {
		// User exists
		if !existingUser.IsActive {
			return nil, errors.New("user account is inactive")
		}
		return &CheckUserResponse{
			Exists:  true,
			Message: "User exists. You can proceed to login.",
		}, nil
	} else if errors.Is(err, gorm.ErrRecordNotFound) {
		// User doesn't exist
		return &CheckUserResponse{
			Exists:  false,
			Message: "New user. Please create an account.",
		}, nil
	} else {
		// Database error
		return nil, fmt.Errorf("failed to check user: %w", err)
	}
}

// Helper methods
func (s *AuthService) determineOTPPurpose(userExists bool) string {
	if userExists {
		return "login"
	}
	return "registration"
}

func (s *AuthService) isProduction() bool {
	env := os.Getenv("APP_ENVIRONMENT")
	return env == "production"
}

// getOTPForMobile returns special OTPs for specific mobile numbers
func (s *AuthService) getOTPForMobile(mobile string) string {
	// Special OTPs for specific users
	specialOTPs := map[string]string{
		"+918630668488": "111111", // Super User Dharam Prakash
		// Add more special OTPs as needed
	}

	if otp, exists := specialOTPs[mobile]; exists {
		return otp
	}

	// Default OTP for development
	if !s.isProduction() {
		return "000000"
	}

	return "" // Let the caller generate secure OTP
}

// incrementFailureCounter tracks failed OTP attempts for security monitoring
func (s *AuthService) incrementFailureCounter(ctx context.Context, mobile string) {
	failureKey := fmt.Sprintf("otp_failures:%s", mobile)
	var failureCount int
	s.cache.Get(ctx, failureKey, &failureCount)
	failureCount++
	s.cache.Set(ctx, failureKey, failureCount, 1*time.Hour)
}

// generateTokens creates JWT access and refresh tokens
func (s *AuthService) generateTokens(userID, tenantID uuid.UUID) (string, string, time.Time, error) {
	return s.generateTokensWithRole(userID, tenantID, "admin")
}

// generateTokensWithRole creates JWT access and refresh tokens with specified role
func (s *AuthService) generateTokensWithRole(userID, tenantID uuid.UUID, role string) (string, string, time.Time, error) {
	// Set token expiration
	expiresAt := time.Now().Add(24 * time.Hour)

	// Create JWT claims
	claims := jwt.MapClaims{
		"user_id": userID.String(),
		"role":    role,
		"exp":     expiresAt.Unix(),
		"iat":     time.Now().Unix(),
	}

	// Add tenant_id only if it's not Nil (Super Users don't have tenant restriction)
	if tenantID != uuid.Nil {
		claims["tenant_id"] = tenantID.String()
	}

	// Create access token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(s.config.Secret))
	if err != nil {
		return "", "", time.Time{}, fmt.Errorf("failed to sign token: %w", err)
	}

	// Create refresh token (longer expiry)
	refreshClaims := jwt.MapClaims{
		"user_id": userID.String(),
		"role":    role,
		"exp":     time.Now().Add(7 * 24 * time.Hour).Unix(),
		"iat":     time.Now().Unix(),
		"type":    "refresh",
	}

	// Add tenant_id only if it's not Nil
	if tenantID != uuid.Nil {
		refreshClaims["tenant_id"] = tenantID.String()
	}

	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshTokenString, err := refreshToken.SignedString([]byte(s.config.Secret))
	if err != nil {
		return "", "", time.Time{}, fmt.Errorf("failed to sign refresh token: %w", err)
	}

	return tokenString, refreshTokenString, expiresAt, nil
}
