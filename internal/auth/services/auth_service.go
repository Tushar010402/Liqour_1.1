package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
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
	firebaseauth "github.com/liquorpro/go-backend/pkg/shared/firebase"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// AuthService handles authentication operations
type AuthService struct {
	db                *database.DB
	cache             *cache.Cache
	config            *config.JWTConfig
	rateLimitService  *RateLimitService
	smsService        SMSServiceInterface
	firebaseVerifier  *firebaseauth.AuthVerifier
}

// SMSServiceInterface defines the interface for SMS services
type SMSServiceInterface interface {
	SendOTP(phoneNumber, name, otp string) (string, error)
}

// NewAuthService creates a new auth service
func NewAuthService(db *database.DB, cache *cache.Cache, jwtConfig *config.JWTConfig, rateLimitService *RateLimitService, smsService SMSServiceInterface, firebaseVerifier *firebaseauth.AuthVerifier) *AuthService {
	return &AuthService{
		db:                db,
		cache:             cache,
		config:            jwtConfig,
		rateLimitService:  rateLimitService,
		smsService:        smsService,
		firebaseVerifier:  firebaseVerifier,
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
	ID           uuid.UUID  `json:"id"`
	Username     string     `json:"username"`
	Email        string     `json:"email"`
	FirstName    string     `json:"first_name"`
	LastName     string     `json:"last_name"`
	Role         string     `json:"role"`
	IsActive     bool       `json:"is_active"`
	ProfileImage string     `json:"profile_image"`
	Salary       *float64   `json:"salary,omitempty"`
	Duty         string     `json:"duty,omitempty"`
	TagLine      string     `json:"tag_line,omitempty"`
	Phone        string     `json:"phone,omitempty"`
	TenantName   string     `json:"tenant_name,omitempty"`
	ShopID       *uuid.UUID `json:"shop_id"`
	ShopName     *string    `json:"shop_name"`
	// ShopIDs is the list of shops an executive is assigned to (omitted for
	// non-executive roles). Salesman uses ShopID instead.
	ShopIDs []uuid.UUID `json:"shop_ids,omitempty"`
}

// TenantResponse represents tenant data in responses
type TenantResponse struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	CompanyName string    `json:"company_name"`
	Phone       string    `json:"phone,omitempty"`
	Address     string    `json:"address,omitempty"`
	IsActive    bool      `json:"is_active"`
}

// RegisterRequest represents registration request data (after OTP verification)
// Password is optional since we use OTP-based authentication
type RegisterRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password"` // Optional - OTP auth doesn't need password
	FirstName   string `json:"first_name" binding:"required"`
	LastName    string `json:"last_name" binding:"required"`
	Phone       string `json:"phone" binding:"required"`
	TenantName  string `json:"tenant_name" binding:"required"`
	CompanyName string `json:"company_name" binding:"required"`
	// Optional shop data - if provided, shop will be created during registration
	ShopName    string `json:"shop_name"`
	ShopAddress string `json:"shop_address"`
}

// CheckUserRequest represents check user existence request
type CheckUserRequest struct {
	Mobile string `json:"mobile" binding:"required"`
}

// CheckUserResponse represents check user response — always sends OTP first
type CheckUserResponse struct {
	Exists    bool      `json:"exists"`              // Always false — real status revealed after OTP verification
	Message   string    `json:"message"`
	SessionID string    `json:"session_id,omitempty"` // OTP session ID for verification
	ExpiresAt time.Time `json:"expires_at,omitempty"` // OTP expiry time
	OTPSentAt time.Time `json:"otp_sent_at,omitempty"`
}

// SendOTPRequest represents send OTP request data
type SendOTPRequest struct {
	Mobile string `json:"mobile" binding:"required"`
}

// SendOTPResponse represents send OTP response data
// Note: purpose is NOT returned here — only revealed after OTP verification
type SendOTPResponse struct {
	Message   string    `json:"message"`
	OTPSentAt time.Time `json:"otp_sent_at"`
	ExpiresAt time.Time `json:"expires_at"`
	SessionID string    `json:"session_id"`
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
	Token             string          `json:"token,omitempty"`
	RefreshToken      string          `json:"refresh_token,omitempty"`
	ExpiresAt         time.Time       `json:"expires_at,omitempty"`
	User              *UserResponse   `json:"user,omitempty"`
	Tenant            *TenantResponse `json:"tenant,omitempty"`
	Message           string          `json:"message,omitempty"`
	Purpose           string          `json:"purpose,omitempty"`            // "login" or "registration"
	RegistrationToken string          `json:"registration_token,omitempty"` // Token to skip OTP on registration
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
		// Normalize phone number for consistent database operations
		normalizedPhone := s.normalizeMobileNumber(req.Phone)

		// Check if user already exists by phone number (primary unique key)
		var existingUserByPhone models.User
		if err := tx.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
			normalizedPhone, req.Phone, normalizedPhone).First(&existingUserByPhone).Error; err == nil {
			return errors.New("phone number already registered")
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("failed to check phone number: %w", err)
		}

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

		// Hash password - if no password provided (OTP-based auth), generate a random one
		password := req.Password
		if password == "" {
			// Generate a random password for OTP-only users
			password = uuid.New().String()
		}
		hashedPassword, err := utils.HashPassword(password)
		if err != nil {
			return fmt.Errorf("failed to hash password: %w", err)
		}

		// Create tenant
		tenant := models.Tenant{
			Name:        req.TenantName,   // Display name
			CompanyName: req.CompanyName,  // Official company name
			Phone:       req.Phone,        // Company phone
			IsActive:    true,
			OnboardedAt: time.Now(),
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
			Phone:        normalizedPhone, // Use normalized phone for consistency
			PasswordHash: hashedPassword,
			Role:         models.RoleAdmin, // First user becomes admin
			IsActive:     true,
		}

		if err := tx.Create(&user).Error; err != nil {
			return fmt.Errorf("failed to create user: %w", err)
		}

		// Create shop if shop data is provided
		if req.ShopName != "" {
			shop := models.Shop{
				TenantModel: models.TenantModel{
					TenantID: &tenant.ID,
				},
				Name:     req.ShopName,
				Address:  req.ShopAddress,
				Phone:    req.Phone, // Use registration phone as shop phone
				IsActive: true,
			}

			if err := tx.Create(&shop).Error; err != nil {
				return fmt.Errorf("failed to create shop: %w", err)
			}

			log.Printf("✅ Shop created successfully during registration: %s (ID: %s)", shop.Name, shop.ID)
		}

		// Seed standard categories for the new tenant
		standardCategories := []struct {
			Name        string
			Description string
			SortOrder   int
		}{
			{"Beer", "Beer and lager products", 1},
			{"Whisky", "Whisky and scotch products", 2},
			{"Rum", "Rum products", 3},
			{"Vodka", "Vodka products", 4},
		}

		for _, sc := range standardCategories {
			cat := models.Category{
				TenantModel: models.TenantModel{
					TenantID: &tenant.ID,
				},
				Name:        sc.Name,
				Description: sc.Description,
				IsActive:    true,
				SortOrder:   sc.SortOrder,
			}
			if err := tx.Create(&cat).Error; err != nil {
				log.Printf("⚠️ Failed to seed category %s for tenant %s: %v", sc.Name, tenant.ID, err)
				// Non-fatal: don't fail registration if category seeding fails
			}
		}
		log.Printf("✅ Standard categories seeded for tenant: %s", tenant.ID)

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
		TagLine:      user.TagLine,
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
		ID:          tenant.ID,
		Name:        tenant.Name,
		CompanyName: tenant.CompanyName,
		Phone:       tenant.Phone,
		Address:     tenant.Address,
		IsActive:    tenant.IsActive,
	}
}

// VerifyOTP verifies OTP and logs in user (static OTP: 000000)
// Security Helper Methods for Scalable OTP System

// isValidMobileNumber validates mobile number format (international format)
// normalizeMobileNumber removes spaces and other formatting from mobile number
func (s *AuthService) normalizeMobileNumber(mobile string) string {
	// Remove all spaces, hyphens, parentheses
	normalized := strings.ReplaceAll(mobile, " ", "")
	normalized = strings.ReplaceAll(normalized, "-", "")
	normalized = strings.ReplaceAll(normalized, "(", "")
	normalized = strings.ReplaceAll(normalized, ")", "")
	return normalized
}

func (s *AuthService) isValidMobileNumber(mobile string) bool {
	// Normalize first (remove spaces, etc.)
	normalized := s.normalizeMobileNumber(mobile)
	// Regex for international mobile number format (+countrycode followed by digits)
	mobileRegex := regexp.MustCompile(`^\+[1-9]\d{1,14}$`)
	return mobileRegex.MatchString(normalized)
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

	// Normalize mobile number for database operations
	normalizedMobile := s.normalizeMobileNumber(mobile)

	// Security: Check if number is blocked due to suspicious activity
	if s.isNumberBlocked(ctx, normalizedMobile) {
		return nil, errors.New("mobile number temporarily blocked due to suspicious activity")
	}

	// Security: Rate limiting - check if too many OTP requests from this mobile
	if err := s.checkOTPRateLimit(ctx, normalizedMobile); err != nil {
		return nil, err
	}

	// REQUIREMENT: Check if phone number already exists (primary unique key)
	// Search using multiple strategies for maximum compatibility
	var existingUserByPhone models.User
	err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalizedMobile, mobile, normalizedMobile).First(&existingUserByPhone).Error

	// Store user existence status to avoid variable shadowing issues
	userExists := err == nil

	if err == nil {
		// Phone exists - this is LOGIN flow
		if !existingUserByPhone.IsActive {
			return nil, errors.New("user account is inactive")
		}
		log.Printf("📱 [OTP] User exists for %s - LOGIN flow", s.maskMobileNumber(mobile))
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		// Database error
		return nil, fmt.Errorf("failed to check phone number: %w", err)
	} else {
		// If ErrRecordNotFound - phone doesn't exist, this is REGISTRATION flow
		log.Printf("📱 [OTP] New user for %s - REGISTRATION flow", s.maskMobileNumber(mobile))
	}

	// REQUIREMENT: Check if OTP already exists and is still valid (10 minute window)
	// REQUIREMENT: Reuse existing OTP instead of generating new one
	// REQUIREMENT: Enforce 30-second cooldown between resends
	otpKey := fmt.Sprintf("otp:%s", normalizedMobile)
	var existingOTPData map[string]interface{}
	var otp, sessionID string
	var isResend bool

	if err := s.cache.Get(ctx, otpKey, &existingOTPData); err == nil {
		// OTP exists - check if we can resend
		lastSentAt, _ := existingOTPData["last_sent_at"].(float64)
		lastSentTime := time.Unix(int64(lastSentAt), 0)
		timeSinceLastSent := time.Since(lastSentTime)

		// REQUIREMENT: 30-second cooldown between resends
		if timeSinceLastSent < 30*time.Second {
			remainingDuration := (30 * time.Second) - timeSinceLastSent
			remainingSeconds := int(remainingDuration.Seconds())
			return nil, fmt.Errorf("please wait %d seconds before requesting OTP again", remainingSeconds)
		}

		// Cooldown passed - reuse existing OTP and session ID
		sessionID, _ = existingOTPData["session_id"].(string)
		hashedOTP, _ := existingOTPData["hashed_otp"].(string)

		// Retrieve the original OTP from special cache (for resending)
		// Note: In production, we need to decrypt or retrieve the OTP to resend it
		// For now, we'll generate new OTP if we can't retrieve the old one
		otpCacheKey := fmt.Sprintf("otp_plain:%s", normalizedMobile)
		if err := s.cache.Get(ctx, otpCacheKey, &otp); err != nil {
			// Cannot retrieve OTP - this should not happen, but fallback to new OTP
			otp = s.getOTPForMobile(mobile)
			if s.isProduction() && otp == "" {
				otp = s.generateSecureOTP()
			}
			hashedOTP = s.hashOTP(otp)
		}

		// Update last_sent_at timestamp and purpose based on current user state
		existingOTPData["last_sent_at"] = time.Now().Unix()
		existingOTPData["hashed_otp"] = hashedOTP
		existingOTPData["purpose"] = s.determinePurpose(userExists) // Update purpose to match current user state

		log.Printf("📱 [OTP] Resending OTP with purpose: %s for %s | OTP: %s", existingOTPData["purpose"], s.maskMobileNumber(mobile), otp)

		// Keep existing expiry (10 minutes from original creation)
		createdAt, _ := existingOTPData["created_at"].(float64)
		createdTime := time.Unix(int64(createdAt), 0)
		remainingExpiry := 10*time.Minute - time.Since(createdTime)

		if err := s.cache.Set(ctx, otpKey, existingOTPData, remainingExpiry); err != nil {
			return nil, fmt.Errorf("failed to update OTP: %w", err)
		}

		isResend = true
		log.Printf("📱 Resending existing OTP to %s (cooldown: %.0fs passed)", s.maskMobileNumber(mobile), timeSinceLastSent.Seconds())
	} else {
		// No existing OTP - generate new one
		// Security: Generate cryptographically secure session ID
		sessionID = s.generateSecureSessionID()

		// Security: Generate secure OTP (for production, use random 6-digit)
		otp = s.getOTPForMobile(mobile) // Handle special OTPs for specific mobiles
		if s.isProduction() && otp == "" {
			otp = s.generateSecureOTP()
		}

		// Security: Hash OTP before storing
		hashedOTP := s.hashOTP(otp)

		// REQUIREMENT: Store OTP data in Redis with 10 minutes expiration
		otpData := map[string]interface{}{
			"hashed_otp":   hashedOTP,
			"mobile":       normalizedMobile,
			"attempts":     0,
			"created_at":   time.Now().Unix(),
			"last_sent_at": time.Now().Unix(), // Track when OTP was last sent
			"session_id":   sessionID,
			"max_attempts": 3,
			"purpose":      s.determinePurpose(userExists), // login if user exists, registration if not
		}

		// REQUIREMENT: 10 minutes validity as specified
		expiryDuration := 10 * time.Minute

		if err := s.cache.Set(ctx, otpKey, otpData, expiryDuration); err != nil {
			return nil, fmt.Errorf("failed to store OTP: %w", err)
		}

		// Store plain OTP separately for resending (same expiry)
		otpCacheKey := fmt.Sprintf("otp_plain:%s", normalizedMobile)
		if err := s.cache.Set(ctx, otpCacheKey, otp, expiryDuration); err != nil {
			log.Printf("⚠️ Failed to cache plain OTP for resending: %v", err)
		}

		isResend = false
		log.Printf("📱 [OTP] Generated new OTP with purpose: %s for %s | OTP: %s",
			s.determinePurpose(userExists), s.maskMobileNumber(mobile), otp)
	}

	// Send OTP via SMS
	if s.isProduction() && s.smsService != nil {
		// Extract user's first name from the FirstName field if available in context
		// For SendOTPForRegistrationRequest, we can get the first name
		userName := s.getUserNameFromMobile(ctx, mobile)

		// Send SMS using the SMS service
		messageID, err := s.smsService.SendOTP(mobile, userName, otp)
		if err != nil {
			log.Printf("⚠️ SMS sending failed: %v (OTP stored in Redis)", err)
			// Don't fail the request - OTP is still stored in Redis
			// User can still verify OTP if they receive it through other means
		} else {
			log.Printf("✅ SMS sent successfully. Message ID: %s", messageID)
		}
	} else {
		// Development mode - log OTP for testing
		fmt.Printf("📱 OTP for %s: %s (Development Mode)\n", s.maskMobileNumber(mobile), otp)
	}

	// Update rate limiting counter
	// Rate limiting counter is automatically handled by CheckRateLimit

	now := time.Now()

	// Determine expiry time based on whether it's a resend or new OTP
	var expiresAt time.Time
	if isResend {
		// For resends, use the remaining time from original creation
		existingCreatedAt, _ := existingOTPData["created_at"].(float64)
		originalCreatedTime := time.Unix(int64(existingCreatedAt), 0)
		expiresAt = originalCreatedTime.Add(10 * time.Minute)
	} else {
		// For new OTPs, expires 10 minutes from now
		expiresAt = now.Add(10 * time.Minute)
	}

	message := fmt.Sprintf("OTP sent successfully to %s", s.maskMobileNumber(mobile))
	if isResend {
		message = fmt.Sprintf("OTP resent successfully to %s", s.maskMobileNumber(mobile))
	}

	return &SendOTPResponse{
		Message:   message,
		OTPSentAt: now,
		ExpiresAt: expiresAt,
		SessionID: sessionID,
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

	// Normalize mobile number for consistent operations
	normalizedMobile := s.normalizeMobileNumber(mobile)

	if s.isNumberBlocked(ctx, normalizedMobile) {
		return nil, errors.New("mobile number temporarily blocked")
	}

	// Retrieve OTP data
	otpKey := fmt.Sprintf("otp:%s", normalizedMobile)
	var otpData map[string]interface{}
	err := s.cache.Get(ctx, otpKey, &otpData)
	if err != nil {
		return nil, errors.New("OTP expired or not found")
	}

	// Debug: Log the retrieved OTP data
	log.Printf("🔍 [OTP DEBUG] Retrieved OTP data for %s: %+v", s.maskMobileNumber(mobile), otpData)

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
		s.blockSuspiciousNumber(ctx, normalizedMobile, 1*time.Hour)
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
		s.incrementFailureCounter(ctx, normalizedMobile)

		return nil, errors.New("invalid OTP")
	}

	// OTP verified successfully - clear it
	s.cache.Delete(ctx, otpKey)

	// Determine purpose and handle accordingly
	purposeRaw, exists := otpData["purpose"]
	if !exists {
		log.Printf("⚠️ [OTP] purpose field not found in OTP data for %s", s.maskMobileNumber(mobile))
		// Fallback: check if user exists to determine purpose
		var user models.User
		err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
			normalizedMobile, mobile, normalizedMobile).First(&user).Error
		if err == nil {
			purposeRaw = "login"
		} else {
			purposeRaw = "registration"
		}
	}

	purpose, ok := purposeRaw.(string)
	if !ok {
		log.Printf("⚠️ [OTP] purpose field is not a string (type: %T, value: %v) for %s", purposeRaw, purposeRaw, s.maskMobileNumber(mobile))
		// Fallback: check if user exists to determine purpose
		var user models.User
		err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
			normalizedMobile, mobile, normalizedMobile).First(&user).Error
		if err == nil {
			purpose = "login"
		} else {
			purpose = "registration"
		}
	}

	log.Printf("📱 [OTP] Verifying OTP for %s with purpose: %s", s.maskMobileNumber(mobile), purpose)

	if purpose == "login" {
		// Login flow - user exists
		// Search using multiple strategies for maximum compatibility
		var user models.User
		err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
			normalizedMobile, mobile, normalizedMobile).Preload("Tenant").First(&user).Error
		if err != nil {
			return nil, fmt.Errorf("user not found: %w", err)
		}

		// DEBUG: Log user details
		log.Printf("🔍 [AUTH DEBUG] User loaded - ID: %s, Role: %s, TenantID: %v", user.ID, user.Role, user.TenantID)
		if user.TenantID != nil {
			log.Printf("🔍 [AUTH DEBUG] User.TenantID value: %s", user.TenantID.String())
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

		// DEBUG: Log tenant ID being used for JWT
		log.Printf("🔍 [AUTH DEBUG] TenantID for JWT generation: %s", tenantID.String())

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

		if err := s.cache.Set(ctx, sessionKey, sessionData, cache.SessionTTL); err != nil {
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
		// Issue a registration token so the user can complete registration
		// without re-verifying OTP (the OTP was already consumed above)
		regToken := uuid.New().String()
		regKey := fmt.Sprintf("reg_token:%s", normalizedMobile)
		regData := map[string]interface{}{
			"token":    regToken,
			"mobile":   normalizedMobile,
			"verified": true,
		}
		s.cache.Set(ctx, regKey, regData, 15*time.Minute) // 15 min to complete registration

		log.Printf("📱 [OTP] Registration token issued for %s (token: %s...)", s.maskMobileNumber(mobile), regToken[:8])

		return &VerifyOTPResponse{
			Message:           "Phone verified successfully. Please complete registration.",
			Purpose:           "registration",
			RegistrationToken: regToken,
		}, nil
	}
}

// Enhanced SendOTPForRegistration with email validation
// Note: Only phone is required at OTP send stage. Other fields are collected later at verify-otp-register.
type SendOTPForRegistrationRequest struct {
	Phone       string `json:"phone" binding:"required"`
	Email       string `json:"email"`       // Optional at OTP stage - validated at registration
	FirstName   string `json:"first_name"`  // Optional at OTP stage - required at registration
	LastName    string `json:"last_name"`
	TenantName  string `json:"tenant_name"`
	CompanyName string `json:"company_name"`
	ShopName    string `json:"shop_name"`
	ShopAddress string `json:"shop_address"`
}

// VerifyOTPAndRegisterRequest combines OTP verification with registration
// Supports two flows:
// 1. Direct: phone + otp (from registration page)
// 2. From login: phone + registration_token (phone already verified via login flow)
type VerifyOTPAndRegisterRequest struct {
	Phone             string `json:"phone" binding:"required"`
	OTP               string `json:"otp"`                // Required if no registration_token
	SessionID         string `json:"session_id"`
	RegistrationToken string `json:"registration_token"` // Alternative to OTP (from login flow)
	Email             string `json:"email" binding:"required,email"`
	FirstName         string `json:"first_name" binding:"required"`
	LastName          string `json:"last_name" binding:"required"`
	TenantName        string `json:"tenant_name" binding:"required"`
	CompanyName       string `json:"company_name" binding:"required"`
	ShopName          string `json:"shop_name"`    // Optional
	ShopAddress       string `json:"shop_address"` // Optional
}

func (s *AuthService) SendOTPForRegistration(ctx context.Context, req SendOTPForRegistrationRequest) (*SendOTPResponse, error) {
	// Normalize mobile number for consistent database operations
	normalizedMobile := s.normalizeMobileNumber(req.Phone)

	// REQUIREMENT: Validate phone number uniqueness (primary key)
	// Search using multiple strategies for maximum compatibility (same as SendOTP and CheckUser)
	var existingUserByPhone models.User
	err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalizedMobile, req.Phone, normalizedMobile).First(&existingUserByPhone).Error
	if err == nil {
		return nil, errors.New("phone number already registered")
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("failed to check phone number: %w", err)
	}

	// REQUIREMENT: Validate email uniqueness (secondary key)
	// Skip check when email is empty — empty strings match other users with no email
	if req.Email != "" {
		var existingUserByEmail models.User
		err = s.db.Where("email = ?", req.Email).First(&existingUserByEmail).Error
		if err == nil {
			return nil, errors.New("email already registered")
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, fmt.Errorf("failed to check email: %w", err)
		}
	}

	// Store first name in Redis temporarily for SMS personalization (10 minutes)
	nameKey := fmt.Sprintf("registration:name:%s", normalizedMobile)
	s.cache.Set(ctx, nameKey, req.FirstName, 10*time.Minute)

	// Both phone and email are unique - proceed with OTP
	return s.SendOTP(ctx, SendOTPRequest{Mobile: req.Phone})
}

// CheckUser sends OTP to mobile number for verification first.
// Registration status is only revealed after OTP verification (in VerifyOTP response).
func (s *AuthService) CheckUser(ctx context.Context, req CheckUserRequest) (*CheckUserResponse, error) {
	// Send OTP — this handles validation, rate limiting, and SMS delivery
	otpResp, err := s.SendOTP(ctx, SendOTPRequest{Mobile: req.Mobile})
	if err != nil {
		return nil, err
	}

	// Report the REAL existence status. Older app builds route on this flag —
	// when it was hardcoded false, existing users were sent to the
	// create-new-user screen instead of the OTP/login screen (and never
	// reached verify-otp). Newer builds ignore this and decide at verify-otp,
	// so reporting the true value is safe for both. Uses the same robust phone
	// match as the login/verify paths.
	normalized := s.normalizeMobileNumber(req.Mobile)
	var existingUser models.User
	lookupErr := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalized, req.Mobile, normalized).First(&existingUser).Error
	exists := lookupErr == nil

	return &CheckUserResponse{
		Exists:    exists,
		Message:   fmt.Sprintf("OTP sent to %s. Please verify to continue.", s.maskMobileNumber(req.Mobile)),
		SessionID: otpResp.SessionID,
		ExpiresAt: otpResp.ExpiresAt,
		OTPSentAt: otpResp.OTPSentAt,
	}, nil
}

// Helper methods

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

// getUserNameFromMobile attempts to retrieve the user's first name for SMS personalization
// Returns "User" if name cannot be found
func (s *AuthService) getUserNameFromMobile(ctx context.Context, mobile string) string {
	// Try to get user from database for existing users (login flow)
	normalizedMobile := s.normalizeMobileNumber(mobile)
	var user models.User
	err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalizedMobile, mobile, normalizedMobile).First(&user).Error

	if err == nil && user.FirstName != "" {
		return user.FirstName
	}

	// For registration flow, check if name is stored temporarily in Redis
	nameKey := fmt.Sprintf("registration:name:%s", normalizedMobile)
	var firstName string
	if err := s.cache.Get(ctx, nameKey, &firstName); err == nil && firstName != "" {
		return firstName
	}

	// Default to "User" if name cannot be determined
	return "User"
}

// generateTokens creates JWT access and refresh tokens
func (s *AuthService) generateTokens(userID, tenantID uuid.UUID) (string, string, time.Time, error) {
	return s.generateTokensWithRole(userID, tenantID, "admin")
}

// generateTokensWithRole creates JWT access and refresh tokens with specified role
func (s *AuthService) generateTokensWithRole(userID, tenantID uuid.UUID, role string) (string, string, time.Time, error) {
	// Set token expiration — use config value, fallback to 7 days
	expHours := s.config.ExpirationHours
	if expHours <= 0 {
		expHours = 168 // 7 days default
	}
	expiresAt := time.Now().Add(time.Duration(expHours) * time.Hour)

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
		"exp":     time.Now().Add(30 * 24 * time.Hour).Unix(), // 30 days refresh token
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

// VerifyOTPAndRegister combines OTP verification with user registration in a single step
// This is the recommended method for tenant registration as it ensures atomicity
// Supports two verification flows:
// 1. Standard: phone + OTP (direct registration)
// 2. Token-based: phone + registration_token (from login flow where OTP was already verified)
func (s *AuthService) VerifyOTPAndRegister(ctx context.Context, req VerifyOTPAndRegisterRequest) (*LoginResponse, error) {
	mobile := req.Phone

	// Security validations
	if !s.isValidMobileNumber(mobile) {
		return nil, errors.New("invalid mobile number format")
	}

	// Normalize mobile number for consistent operations
	normalizedMobile := s.normalizeMobileNumber(mobile)

	if s.isNumberBlocked(ctx, normalizedMobile) {
		return nil, errors.New("mobile number temporarily blocked")
	}

	// Flow 1: Registration token from login flow (phone already verified)
	if req.RegistrationToken != "" {
		regKey := fmt.Sprintf("reg_token:%s", normalizedMobile)
		var regData map[string]interface{}
		err := s.cache.Get(ctx, regKey, &regData)
		if err != nil {
			return nil, errors.New("registration token expired. Please start again")
		}

		storedToken, _ := regData["token"].(string)
		if storedToken != req.RegistrationToken {
			return nil, errors.New("invalid registration token")
		}

		// Token is valid — consume it
		s.cache.Delete(ctx, regKey)
		log.Printf("📱 [REG] Registration token verified for %s", s.maskMobileNumber(mobile))

		// Skip to user creation (below)
	} else if req.OTP != "" {
		// Flow 2: Standard OTP verification
		providedOTP := req.OTP

		// Retrieve OTP data
		otpKey := fmt.Sprintf("otp:%s", normalizedMobile)
		var otpData map[string]interface{}
		err := s.cache.Get(ctx, otpKey, &otpData)
		if err != nil {
			return nil, errors.New("OTP expired or not found. Please request a new OTP")
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
			s.blockSuspiciousNumber(ctx, normalizedMobile, 1*time.Hour)
			return nil, errors.New("maximum OTP attempts exceeded. Please request a new OTP")
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
			s.incrementFailureCounter(ctx, normalizedMobile)

			return nil, errors.New("invalid OTP")
		}

		// OTP verified — clear it
		s.cache.Delete(ctx, otpKey)

		// Check purpose - must be registration
		purpose, _ := otpData["purpose"].(string)
		if purpose == "login" {
			return nil, errors.New("this phone number is already registered. Please use login instead")
		}
	} else {
		return nil, errors.New("either OTP or registration token is required")
	}

	// Phone verified — now proceed with registration checks

	// Double-check that user doesn't exist (safety check)
	var existingUser models.User
	var err error
	err = s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalizedMobile, mobile, normalizedMobile).First(&existingUser).Error
	if err == nil {
		return nil, errors.New("phone number already registered")
	}

	// Check if email is already registered
	err = s.db.Where("email = ?", req.Email).First(&existingUser).Error
	if err == nil {
		return nil, errors.New("email already registered")
	}

	// Now proceed with registration
	log.Printf("✅ [Registration] Phone verified for %s, proceeding with registration", s.maskMobileNumber(mobile))

	// Create registration request
	registerReq := RegisterRequest{
		Email:       req.Email,
		FirstName:   req.FirstName,
		LastName:    req.LastName,
		Phone:       normalizedMobile,
		TenantName:  req.TenantName,
		CompanyName: req.CompanyName,
		ShopName:    req.ShopName,
		ShopAddress: req.ShopAddress,
	}

	// Call the existing Register function
	response, err := s.Register(ctx, registerReq)
	if err != nil {
		return nil, fmt.Errorf("registration failed: %w", err)
	}

	log.Printf("✅ [Registration] User created successfully for %s", s.maskMobileNumber(mobile))

	return response, nil
}

// MasterLoginRequest is the static master-password bypass used by the admin
// when the regular OTP path is unreachable (testing, SMS down, locked-out
// user, etc). MASTER_OTP env var overrides the default "100110".
type MasterLoginRequest struct {
	Mobile         string `json:"mobile" binding:"required"`
	MasterPassword string `json:"master_password" binding:"required"`
}

// MasterLogin authenticates a user by mobile + master-password without OTP.
// Returns the same shape as VerifyOTP/VerifyFirebaseToken login branch.
func (s *AuthService) MasterLogin(ctx context.Context, req MasterLoginRequest) (*VerifyOTPResponse, error) {
	expected := os.Getenv("MASTER_OTP")
	if expected == "" {
		expected = "100110"
	}
	if req.MasterPassword != expected {
		return nil, errors.New("invalid master password")
	}

	normalizedPhone := s.normalizeMobileNumber(req.Mobile)

	var user models.User
	err := s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalizedPhone, req.Mobile, normalizedPhone).Preload("Tenant").First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("database error: %w", err)
	}
	if !user.IsActive {
		return nil, errors.New("account is inactive")
	}

	if s.isNumberBlocked(ctx, normalizedPhone) {
		return nil, errors.New("mobile number temporarily blocked")
	}

	var tenantID uuid.UUID
	if user.Role == models.RoleSaasAdmin && user.IsSuperuser {
		tenantID = uuid.Nil
	} else if user.TenantID != nil {
		tenantID = *user.TenantID
	}

	tokenString, refreshToken, expiresAt, err := s.generateTokensWithRole(user.ID, tenantID, user.Role)
	if err != nil {
		return nil, fmt.Errorf("failed to generate tokens: %w", err)
	}

	sessionKey := fmt.Sprintf(cache.UserSessionKey, user.ID.String())
	sessionData := map[string]interface{}{
		"user_id":       user.ID.String(),
		"role":          user.Role,
		"is_superuser":  user.IsSuperuser,
		"refresh_token": refreshToken,
		"login_time":    time.Now(),
		"auth_method":   "master_password",
	}
	if tenantID != uuid.Nil {
		sessionData["tenant_id"] = tenantID.String()
	} else {
		sessionData["tenant_id"] = nil
	}
	if err := s.cache.Set(ctx, sessionKey, sessionData, cache.SessionTTL); err != nil {
		return nil, fmt.Errorf("failed to store session: %w", err)
	}

	log.Printf("🔑 [MasterLogin] %s authenticated via master password", s.maskMobileNumber(req.Mobile))

	return &VerifyOTPResponse{
		Token:        tokenString,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt,
		User:         s.mapUserToResponse(&user),
		Tenant:       s.mapTenantToResponse(user.Tenant),
		Message:      "Login successful",
		Purpose:      "login",
	}, nil
}

// FirebaseAuthRequest represents a Firebase Phone Auth verification request
type FirebaseAuthRequest struct {
	FirebaseIDToken string `json:"firebase_id_token" binding:"required"`
	// Optional registration fields (used if user doesn't exist)
	Email       string `json:"email"`
	FirstName   string `json:"first_name"`
	LastName    string `json:"last_name"`
	TenantName  string `json:"tenant_name"`
	CompanyName string `json:"company_name"`
	ShopName    string `json:"shop_name"`
	ShopAddress string `json:"shop_address"`
}

// VerifyFirebaseToken verifies a Firebase ID token and handles login or registration
// Mirrors the VerifyOTP logic: if user exists → login, if not → issue registration token
func (s *AuthService) VerifyFirebaseToken(ctx context.Context, req FirebaseAuthRequest) (*VerifyOTPResponse, error) {
	if s.firebaseVerifier == nil {
		return nil, errors.New("firebase authentication is not configured")
	}

	// Verify Firebase ID token → get phone number and UID
	phone, firebaseUID, err := s.firebaseVerifier.VerifyIDToken(ctx, req.FirebaseIDToken)
	if err != nil {
		return nil, fmt.Errorf("firebase token verification failed: %w", err)
	}

	log.Printf("📱 [Firebase] Token verified for phone: %s (UID: %s)", s.maskMobileNumber(phone), firebaseUID)

	// Normalize phone number
	normalizedPhone := s.normalizeMobileNumber(phone)

	// Check if number is blocked
	if s.isNumberBlocked(ctx, normalizedPhone) {
		return nil, errors.New("mobile number temporarily blocked")
	}

	// Look up user by phone
	var user models.User
	err = s.db.Where("phone = ? OR phone = ? OR REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', '') = ?",
		normalizedPhone, phone, normalizedPhone).Preload("Tenant").First(&user).Error

	if err == nil {
		// User exists → LOGIN flow (mirrors VerifyOTP login path)
		if !user.IsActive {
			return nil, errors.New("account is inactive")
		}

		log.Printf("📱 [Firebase] User found - LOGIN flow for %s", s.maskMobileNumber(phone))

		// Handle Super User (SaaS admin)
		var tenantID uuid.UUID
		if user.Role == models.RoleSaasAdmin && user.IsSuperuser {
			tenantID = uuid.Nil
		} else if user.TenantID != nil {
			tenantID = *user.TenantID
		}

		// Generate JWT tokens
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
			"auth_method":   "firebase",
			"firebase_uid":  firebaseUID,
		}

		if tenantID != uuid.Nil {
			sessionData["tenant_id"] = tenantID.String()
		} else {
			sessionData["tenant_id"] = nil
		}

		if err := s.cache.Set(ctx, sessionKey, sessionData, cache.SessionTTL); err != nil {
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

	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("database error: %w", err)
	}

	// User doesn't exist → REGISTRATION flow (mirrors VerifyOTP registration path)
	log.Printf("📱 [Firebase] New user - REGISTRATION flow for %s", s.maskMobileNumber(phone))

	regToken := uuid.New().String()
	regKey := fmt.Sprintf("reg_token:%s", normalizedPhone)
	regData := map[string]interface{}{
		"token":        regToken,
		"mobile":       normalizedPhone,
		"verified":     true,
		"auth_method":  "firebase",
		"firebase_uid": firebaseUID,
	}
	s.cache.Set(ctx, regKey, regData, 15*time.Minute)

	log.Printf("📱 [Firebase] Registration token issued for %s (token: %s...)", s.maskMobileNumber(phone), regToken[:8])

	return &VerifyOTPResponse{
		Message:           "Phone verified successfully. Please complete registration.",
		Purpose:           "registration",
		RegistrationToken: regToken,
	}, nil
}
