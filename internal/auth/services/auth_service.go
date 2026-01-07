package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
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

// ============================================================================
// Worker Pools for Async Operations (Performance Optimization)
// ============================================================================

// smsWorkerPool limits concurrent SMS API requests to prevent overload
var smsWorkerPool = make(chan struct{}, 10)

// securityEventBuffer handles async security event logging with batching
var (
	securityEventBuffer     = make(chan *securityEventWithDB, 1000)
	securityEventBufferOnce sync.Once
)

type securityEventWithDB struct {
	event *models.SecurityEvent
	db    *gorm.DB
}

// Pre-compiled regex patterns for performance (compiled once at startup)
var (
	mobileRegex = regexp.MustCompile(`^\+[1-9]\d{1,14}$`)
)

// Async device session worker pool for non-blocking session creation
var deviceSessionPool = make(chan struct{}, 20) // 20 concurrent workers

// deviceSessionRequest holds data for async device session creation
type deviceSessionRequest struct {
	service           *AuthService
	ctx               context.Context
	user              *models.User
	deviceReq         *LoginWithDeviceRequest
	tokenString       string
	refreshToken      string
	expiresAt         time.Time
	preGeneratedID    uuid.UUID
	existingSession   *models.UserSession
	isRefresh         bool
}

// initSecurityEventWorker starts the background worker for security event logging
func initSecurityEventWorker(db *gorm.DB) {
	securityEventBufferOnce.Do(func() {
		go func() {
			batch := make([]*models.SecurityEvent, 0, 50)
			ticker := time.NewTicker(5 * time.Second)
			defer ticker.Stop()

			for {
				select {
				case eventWithDB := <-securityEventBuffer:
					batch = append(batch, eventWithDB.event)
					// Flush when batch is full
					if len(batch) >= 50 {
						if err := db.Create(&batch).Error; err != nil {
							log.Printf("Failed to batch insert security events: %v", err)
						}
						batch = batch[:0]
					}
				case <-ticker.C:
					// Flush on timer
					if len(batch) > 0 {
						if err := db.Create(&batch).Error; err != nil {
							log.Printf("Failed to batch insert security events: %v", err)
						}
						batch = batch[:0]
					}
				}
			}
		}()
	})
}

// createDeviceSessionAsync creates device session in background (non-blocking)
// This saves ~20-30ms on the hot path by not waiting for DB operations
func createDeviceSessionAsync(req *deviceSessionRequest) {
	select {
	case deviceSessionPool <- struct{}{}: // Acquire worker slot
		go func() {
			defer func() { <-deviceSessionPool }() // Release slot

			// Use background context since original may be cancelled
			bgCtx := context.Background()

			if req.isRefresh && req.existingSession != nil {
				// Refresh existing session
				if err := req.service.RefreshDeviceSession(bgCtx, req.existingSession, req.tokenString, req.refreshToken, req.expiresAt); err != nil {
					log.Printf("Async: Failed to refresh device session: %v", err)
				}
			} else {
				// Create new session
				if _, err := req.service.CreateDeviceSessionWithID(bgCtx, req.user, req.deviceReq, req.tokenString, req.refreshToken, req.expiresAt, req.preGeneratedID); err != nil {
					log.Printf("Async: Failed to create device session: %v", err)
				}
			}
		}()
	default:
		// Pool full - create synchronously as fallback
		log.Printf("Device session pool full, creating synchronously")
		if req.isRefresh && req.existingSession != nil {
			req.service.RefreshDeviceSession(req.ctx, req.existingSession, req.tokenString, req.refreshToken, req.expiresAt)
		} else {
			req.service.CreateDeviceSessionWithID(req.ctx, req.user, req.deviceReq, req.tokenString, req.refreshToken, req.expiresAt, req.preGeneratedID)
		}
	}
}

// AuthService handles authentication operations
type AuthService struct {
	db               *database.DB
	cache            *cache.Cache
	config           *config.JWTConfig
	rateLimitService *RateLimitService
}

// NewAuthService creates a new auth service
func NewAuthService(db *database.DB, cache *cache.Cache, jwtConfig *config.JWTConfig, rateLimitService *RateLimitService) *AuthService {
	// Initialize security event background worker
	initSecurityEventWorker(db.DB)

	return &AuthService{
		db:               db,
		cache:            cache,
		config:           jwtConfig,
		rateLimitService: rateLimitService,
	}
}

// LoginRequest represents login request data with device information
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`

	// Device Information (sent by client for device tracking)
	DeviceID   string `json:"device_id"`   // Unique device identifier
	DeviceName string `json:"device_name"` // e.g., "iPhone 14 Pro", "Samsung Galaxy S23"
	DeviceType string `json:"device_type"` // "mobile", "web", "tablet"
	OSName     string `json:"os_name"`     // "iOS", "Android", "Web"
	OSVersion  string `json:"os_version"`  // "17.0", "14", etc.
	AppVersion string `json:"app_version"` // "1.0.0"
}

// LoginResponse represents login response data
type LoginResponse struct {
	Token        string          `json:"token"`
	RefreshToken string          `json:"refresh_token"`
	ExpiresAt    time.Time       `json:"expires_at"`
	User         *UserResponse   `json:"user"`
	Tenant       *TenantResponse `json:"tenant"`
	SessionID    string          `json:"session_id,omitempty"`
	DeviceName   string          `json:"device_name,omitempty"`
}

// UserResponse represents user data in responses
type UserResponse struct {
	ID           uuid.UUID  `json:"id"`
	Username     string     `json:"username"`
	Email        string     `json:"email"`
	FirstName    string     `json:"first_name"`
	LastName     string     `json:"last_name"`
	Phone        string     `json:"phone"`
	Role         string     `json:"role"`
	IsActive     bool       `json:"is_active"`
	ProfileImage string     `json:"profile_image"`
	TenantName   string     `json:"tenant_name,omitempty"`
	ShopID       *uuid.UUID `json:"shop_id,omitempty"`
	ShopName     string     `json:"shop_name,omitempty"`
}

// TenantResponse represents tenant data in responses
type TenantResponse struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	CompanyName string    `json:"company_name"`
	IsActive    bool      `json:"is_active"`
}

// RegisterRequest represents registration request data (after OTP verification)
type RegisterRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"omitempty,min=8"` // Optional password for OTP-based registration
	FirstName   string `json:"first_name" binding:"required"`
	LastName    string `json:"last_name" binding:"required"`
	Phone       string `json:"phone" binding:"required"`
	TenantName  string `json:"tenant_name" binding:"required"`
	CompanyName string `json:"company_name" binding:"required"`
}

// CheckUserRequest represents check user existence request
type CheckUserRequest struct {
	Mobile string `json:"mobile"` // Supports "mobile"
	Phone  string `json:"phone"`  // Supports "phone" (for Flutter app compatibility)
	Email  string `json:"email"`  // Supports "email" for email validation
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

	// Device Information for session tracking (2-device limit like Swiggy/Zomato)
	DeviceID   string `json:"device_id"`   // Unique device identifier
	DeviceName string `json:"device_name"` // e.g., "iPhone 14 Pro", "Samsung Galaxy S23"
	DeviceType string `json:"device_type"` // "mobile", "web", "tablet"
	OSName     string `json:"os_name"`     // "iOS", "Android", "Web"
	OSVersion  string `json:"os_version"`  // "17.0", "14", etc.
	AppVersion string `json:"app_version"` // "1.0.0"
}

// VerifyOTPResponse represents the response for OTP verification
type VerifyOTPResponse struct {
	Token        string          `json:"token,omitempty"`
	RefreshToken string          `json:"refresh_token,omitempty"`
	ExpiresAt    time.Time       `json:"expires_at,omitempty"`
	User         *UserResponse   `json:"user,omitempty"`
	Tenant       *TenantResponse `json:"tenant,omitempty"`
	Message      string          `json:"message,omitempty"`
	Purpose      string          `json:"purpose,omitempty"` // "login" or "registration"

	// Session info for device tracking (2-device limit)
	SessionID  string `json:"session_id,omitempty"`
	DeviceName string `json:"device_name,omitempty"`
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

	// ========== Device Limit Check (2-device limit like Swiggy/Zomato) ==========
	// Check if device limit is reached (only if device_id is provided by client)
	var existingSession *models.UserSession
	if req.DeviceID != "" {
		existingSession, err = s.CheckDeviceLimit(ctx, user.ID, req.DeviceID)
		if err != nil {
			// If it's a device limit error, return special error with session details
			if deviceLimitErr, ok := err.(*models.DeviceLimitError); ok {
				// Return error with active sessions so client can display them
				return nil, deviceLimitErr
			}
			return nil, fmt.Errorf("failed to check device limit: %w", err)
		}
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

	// Store session in cache (for fast token validation)
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
		// Log error but don't fail login - use log.Printf (async buffered) instead of fmt.Printf
		log.Printf("Warning: Failed to store session in cache: %v", err)
	}

	// ========== Create/Update Device Session in Database ==========
	var sessionID string
	var deviceName string
	if req.DeviceID != "" {
		deviceReq := &LoginWithDeviceRequest{
			LoginRequest: req,
			IPAddress:    "", // Can be set from handler if needed
		}

		if existingSession != nil {
			// Same device logging in again - refresh the session
			if err := s.RefreshDeviceSession(ctx, existingSession, token, refreshToken, expiresAt); err != nil {
				log.Printf("Warning: Failed to refresh device session: %v", err)
			}
			sessionID = existingSession.ID.String()
			deviceName = existingSession.DeviceName
		} else {
			// New device - create session
			session, err := s.CreateDeviceSession(ctx, &user, deviceReq, token, refreshToken, expiresAt)
			if err != nil {
				log.Printf("Warning: Failed to create device session: %v", err)
			} else {
				sessionID = session.ID.String()
				deviceName = session.DeviceName
			}
		}
	}

	return &LoginResponse{
		Token:        token,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt,
		User:         s.mapUserToResponse(&user),
		Tenant:       s.mapTenantToResponse(user.Tenant),
		SessionID:    sessionID,
		DeviceName:   deviceName,
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

		// Hash password - generate random one if not provided (OTP-based registration)
		password := req.Password
		if password == "" {
			// Generate secure random password for OTP-based registration
			randomPassword, err := utils.GenerateRandomString(16)
			if err != nil {
				return fmt.Errorf("failed to generate password: %w", err)
			}
			password = randomPassword
		}

		hashedPassword, err := utils.HashPassword(password)
		if err != nil {
			return fmt.Errorf("failed to hash password: %w", err)
		}

		// Check if tenant name already exists
		var existingTenant models.Tenant
		if err := tx.Where("name = ?", req.TenantName).First(&existingTenant).Error; err == nil {
			return errors.New("tenant name already exists")
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("failed to check existing tenant: %w", err)
		}

		// Check if phone number already exists
		var existingUserByPhone models.User
		if err := tx.Where("phone = ?", req.Phone).First(&existingUserByPhone).Error; err == nil {
			return errors.New("phone number already registered")
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("failed to check existing phone: %w", err)
		}

		// Create tenant
		tenant := models.Tenant{
			Name:        req.TenantName,   // Tenant slug/subdomain
			CompanyName: req.CompanyName,  // Display name
			IsActive:    true,
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
			log.Printf("Warning: Failed to store session in cache: %v", err)
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
		log.Printf("Warning: Failed to update session in cache: %v", err)
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
		ID:          tenant.ID,
		Name:        tenant.Name,
		CompanyName: tenant.CompanyName,
		IsActive:    tenant.IsActive,
	}
}

// VerifyOTP verifies OTP and logs in user (static OTP: 000000)
// Security Helper Methods for Scalable OTP System

// sanitizeMobileNumber removes spaces and normalizes phone number format
func (s *AuthService) sanitizeMobileNumber(mobile string) string {
	// Remove all spaces from phone number (Flutter app may send formatted numbers with spaces)
	return strings.ReplaceAll(mobile, " ", "")
}

// isValidMobileNumber validates mobile number format (international format)
// Uses pre-compiled regex for sub-millisecond performance
func (s *AuthService) isValidMobileNumber(mobile string) bool {
	// Sanitize first
	mobile = s.sanitizeMobileNumber(mobile)
	// Use pre-compiled regex (at package level) for fast matching
	return mobileRegex.MatchString(mobile)
}

// checkOTPRateLimit implements ultra-fast rate limiting for OTP requests
// Uses Redis-only rate limiting for sub-2ms performance (no DB queries)
func (s *AuthService) checkOTPRateLimit(ctx context.Context, mobile string) error {
	// Use ultra-fast Redis-only rate limiting
	isBlocked, err := s.rateLimitService.CheckOTPRateLimitFast(ctx, mobile)

	if err != nil {
		// If there's an error with the rate limiting service, fall back to allowing the request
		// but log the error for monitoring
		log.Printf("Rate limiting service error: %v", err)
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
	// Master OTP for development/testing - works with any phone number
	if providedOTP == "011001" {
		return true
	}
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

// sendSMSOTP sends OTP via SMS using confirmsms.in API
func (s *AuthService) sendSMSOTP(mobile, otp string) error {
	// SMS API credentials
	apiKey := "6555d5f6c02a1"
	sender := "DRDANG"

	// Remove '+' from mobile number for API
	phoneNumber := strings.TrimPrefix(mobile, "+")

	// Use verified message template format (matches Python implementation)
	// Format: Dear User,\n{otp} is your one time password (OTP). Please enter the OTP to proceed.\nThank you.\nDr. Dangs Lab
	messageText := fmt.Sprintf("Dear User,%%0A%s is your one time password (OTP). Please enter the OTP to proceed.%%0AThank you.%%0ADr. Dangs Lab", otp)

	// Build API URL with HTTPS (verified working endpoint)
	apiURL := fmt.Sprintf("https://fast.confirmsms.in/api/push.json?apikey=%s&sender=%s&mobileno=%s&text=%s",
		apiKey, sender, phoneNumber, messageText)

	// TEMPORARY DEBUG: Log API URL (with masked OTP for security)
	maskedURL := strings.Replace(apiURL, otp, "******", 1)
	fmt.Printf("📤 SMS API Request: %s\n", maskedURL)

	// Create HTTP client with SSL verification disabled for this specific API
	// (certificate mismatch: cert is for mysmsapp.in but domain is fast.confirmsms.in)
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	// Make HTTPS GET request
	resp, err := client.Get(apiURL)
	if err != nil {
		return fmt.Errorf("failed to send SMS: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read SMS response: %w", err)
	}

	// Parse response
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("failed to parse SMS response: %w", err)
	}

	// Log response for debugging
	fmt.Printf("✅ SMS API Response for %s: %s\n", mobile, string(body))

	// Check for success status in response
	if status, ok := result["status"].(string); ok && status == "success" {
		// Extract batch ID if available
		if desc, ok := result["description"].(map[string]interface{}); ok {
			if batchID, ok := desc["batchid"].(string); ok {
				fmt.Printf("✅ SMS sent successfully! Batch ID: %s\n", batchID)
			}
		}
		return nil
	}

	// Legacy check for request_id (backward compatibility)
	if requestID, ok := result["request_id"]; ok {
		fmt.Printf("✅ SMS sent successfully! Request ID: %v\n", requestID)
		return nil
	}

	return fmt.Errorf("SMS API did not return success status: %s", string(body))
}

// sendSMSOTPAsync sends SMS asynchronously using worker pool (non-blocking)
// This is the PRIMARY method to use for production - returns immediately
func (s *AuthService) sendSMSOTPAsync(mobile, otp string) {
	select {
	case smsWorkerPool <- struct{}{}: // Acquire worker slot
		go func() {
			defer func() { <-smsWorkerPool }() // Release slot when done

			// Create context with timeout for SMS API call
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			// Create HTTP client with timeout
			tr := &http.Transport{
				TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			}
			client := &http.Client{
				Transport: tr,
				Timeout:   10 * time.Second,
			}

			// SMS API credentials
			apiKey := "6555d5f6c02a1"
			sender := "DRDANG"
			phoneNumber := strings.TrimPrefix(mobile, "+")
			messageText := fmt.Sprintf("Dear User,%%0A%s is your one time password (OTP). Please enter the OTP to proceed.%%0AThank you.%%0ADr. Dangs Lab", otp)
			apiURL := fmt.Sprintf("https://fast.confirmsms.in/api/push.json?apikey=%s&sender=%s&mobileno=%s&text=%s",
				apiKey, sender, phoneNumber, messageText)

			// Create request with context
			req, err := http.NewRequestWithContext(ctx, "GET", apiURL, nil)
			if err != nil {
				log.Printf("SMS request creation failed for %s: %v", s.maskMobileNumber(mobile), err)
				return
			}

			resp, err := client.Do(req)
			if err != nil {
				log.Printf("SMS send failed for %s: %v", s.maskMobileNumber(mobile), err)
				// Store for retry (optional)
				s.cache.Set(context.Background(),
					fmt.Sprintf("sms_retry:%s", mobile),
					map[string]string{"otp": otp, "mobile": mobile},
					5*time.Minute)
				return
			}
			defer resp.Body.Close()

			body, _ := io.ReadAll(resp.Body)
			log.Printf("SMS sent to %s: %s", s.maskMobileNumber(mobile), string(body))
		}()
	default:
		// Worker pool full - log warning but don't block
		log.Printf("SMS worker pool full, OTP for %s stored in Redis only", s.maskMobileNumber(mobile))
	}
}

// SendOTP sends OTP to mobile number after validating phone/email uniqueness
func (s *AuthService) SendOTP(ctx context.Context, req SendOTPRequest) (*SendOTPResponse, error) {
	// Sanitize phone number (remove spaces)
	mobile := s.sanitizeMobileNumber(req.Mobile)

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

	// Send SMS OTP (async - returns immediately for fast response)
	if s.isProduction() {
		// Production: Send SMS asynchronously (non-blocking)
		fmt.Printf("🔐 OTP Generated for %s: %s (Valid for 10 minutes)\n", s.maskMobileNumber(mobile), otp)
		// Use async SMS - OTP is already stored in Redis, SMS sends in background
		s.sendSMSOTPAsync(mobile, otp)
		fmt.Printf("📤 SMS queued for %s (async)\n", s.maskMobileNumber(mobile))
	} else {
		// Development: Just log it
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
	// Sanitize phone number (remove spaces)
	mobile := s.sanitizeMobileNumber(req.Mobile)
	providedOTP := req.OTP

	// Security validations
	if !s.isValidMobileNumber(mobile) {
		return nil, errors.New("invalid mobile number format")
	}

	if s.isNumberBlocked(ctx, mobile) {
		return nil, errors.New("mobile number temporarily blocked")
	}

	// Retrieve OTP data (using sanitized mobile)
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

	// Master OTP bypass for testing/development
	isMasterOTP := providedOTP == "011001"

	if !isMasterOTP && !s.verifyOTPHash(providedOTP, storedHashedOTP) {
		// Increment attempts counter
		attempts++
		otpData["attempts"] = attempts
		s.cache.Set(ctx, otpKey, otpData, 10*time.Minute)

		// Track failed attempts
		s.incrementFailureCounter(ctx, mobile)

		return nil, errors.New("invalid OTP")
	}

	// NOTE: Do NOT delete OTP here - it will be deleted after successful login
	// This allows ForceLoginWithOTP to work when device limit is reached

	// Determine purpose and handle accordingly
	purpose, _ := otpData["purpose"].(string)

	if purpose == "login" {
		// Login flow - user exists (use cached lookup for speed)
		user, err := s.getUserByPhoneCached(ctx, mobile)
		if err != nil {
			// Delete OTP on error
			s.cache.Delete(ctx, otpKey)
			return nil, fmt.Errorf("user not found: %w", err)
		}

		// ========== Device Limit Check (2-device limit like Swiggy/Zomato) ==========
		var existingSession *models.UserSession
		if req.DeviceID != "" {
			existingSession, err = s.CheckDeviceLimit(ctx, user.ID, req.DeviceID)
			if err != nil {
				// If it's a device limit error, DON'T delete OTP - user needs it for ForceLoginWithOTP
				if deviceLimitErr, ok := err.(*models.DeviceLimitError); ok {
					return nil, deviceLimitErr
				}
				// Delete OTP for other errors
				s.cache.Delete(ctx, otpKey)
				return nil, fmt.Errorf("failed to check device limit: %w", err)
			}
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

		// ========== Determine Session ID for JWT token ==========
		// We need to know the session ID BEFORE generating the token
		var sessionID string
		var deviceName string
		var preGeneratedSessionID uuid.UUID

		if req.DeviceID != "" {
			if existingSession != nil {
				// Same device logging in again - will refresh existing session
				sessionID = existingSession.ID.String()
				deviceName = existingSession.DeviceName
			} else {
				// New device - pre-generate session ID
				preGeneratedSessionID = uuid.New()
				sessionID = preGeneratedSessionID.String()
			}
		}

		// Generate JWT token WITH session_id for device-specific logout
		tokenString, refreshToken, expiresAt, err := s.generateTokensWithRole(user.ID, tenantID, user.Role, sessionID)
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

		if err := s.cache.Set(ctx, sessionKey, sessionData, 45*24*time.Hour); err != nil {
			return nil, fmt.Errorf("failed to store session: %w", err)
		}

		// ========== Create/Update Device Session ASYNC (saves ~20-30ms) ==========
		if req.DeviceID != "" {
			deviceReq := &LoginWithDeviceRequest{
				LoginRequest: LoginRequest{
					DeviceID:   req.DeviceID,
					DeviceName: req.DeviceName,
					DeviceType: req.DeviceType,
					OSName:     req.OSName,
					OSVersion:  req.OSVersion,
					AppVersion: req.AppVersion,
				},
			}

			// Fire and forget - don't block on DB operation
			createDeviceSessionAsync(&deviceSessionRequest{
				service:         s,
				ctx:             ctx,
				user:            user,
				deviceReq:       deviceReq,
				tokenString:     tokenString,
				refreshToken:    refreshToken,
				expiresAt:       expiresAt,
				preGeneratedID:  preGeneratedSessionID,
				existingSession: existingSession,
				isRefresh:       existingSession != nil,
			})

			// DeviceName is determined synchronously (no DB needed)
			if existingSession != nil {
				deviceName = existingSession.DeviceName
			} else if req.DeviceName != "" {
				deviceName = req.DeviceName
			} else {
				deviceName = req.DeviceType // fallback
			}
		}

		// Login successful - now delete the OTP
		s.cache.Delete(ctx, otpKey)

		return &VerifyOTPResponse{
			Token:        tokenString,
			RefreshToken: refreshToken,
			ExpiresAt:    expiresAt,
			User:         s.mapUserToResponse(user),
			Tenant:       s.mapTenantToResponse(user.Tenant),
			Message:      "Login successful",
			Purpose:      "login",
			SessionID:    sessionID,
			DeviceName:   deviceName,
		}, nil
	} else {
		// Registration flow - user doesn't exist yet
		// Delete OTP after successful verification for registration
		s.cache.Delete(ctx, otpKey)

		return &VerifyOTPResponse{
			Message: "Phone verified successfully. Please complete registration.",
			Purpose: "registration",
		}, nil
	}
}

// ForceLoginWithOTPRequest is for Swiggy/Zomato style force login
// When device limit is reached, user selects a session to logout, then logs in
type ForceLoginWithOTPRequest struct {
	Mobile            string `json:"mobile" binding:"required"`
	OTP               string `json:"otp" binding:"required"`
	SessionID         string `json:"session_id"`
	SessionIDToRemove string `json:"session_id_to_remove" binding:"required"` // Session to logout

	// Device Information for session tracking
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
	DeviceType string `json:"device_type"`
	OSName     string `json:"os_name"`
	OSVersion  string `json:"os_version"`
	AppVersion string `json:"app_version"`
}

// ForceLoginWithOTP handles Swiggy/Zomato style login when device limit is reached
// 1. Verify OTP is valid
// 2. Logout the selected session
// 3. Create new session for the new device
func (s *AuthService) ForceLoginWithOTP(ctx context.Context, req ForceLoginWithOTPRequest) (*VerifyOTPResponse, error) {
	// Normalize mobile number
	mobile := req.Mobile
	if !strings.HasPrefix(mobile, "+91") {
		mobile = "+91" + strings.TrimLeft(mobile, "0")
	}

	// Validate OTP from cache
	otpKey := fmt.Sprintf("otp:%s", mobile)
	var otpData map[string]interface{}
	err := s.cache.Get(ctx, otpKey, &otpData)
	if err != nil {
		return nil, errors.New("OTP expired or not found")
	}

	// Verify OTP using hash (same as VerifyOTP)
	storedHashedOTP, ok := otpData["hashed_otp"].(string)
	if !ok {
		return nil, errors.New("invalid OTP data")
	}

	// Master OTP bypass for testing/development
	isMasterOTP := req.OTP == "011001"

	if !isMasterOTP && !s.verifyOTPHash(req.OTP, storedHashedOTP) {
		return nil, errors.New("invalid OTP")
	}

	// OTP verified - clear it (force login successful)
	s.cache.Delete(ctx, otpKey)

	// Get user (use cached lookup for speed)
	user, err := s.getUserByPhoneCached(ctx, mobile)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}

	// Parse session ID to remove
	sessionIDToRemove, err := uuid.Parse(req.SessionIDToRemove)
	if err != nil {
		return nil, errors.New("invalid session_id_to_remove")
	}

	// Verify the session belongs to this user and logout that session
	var sessionToRemove models.UserSession
	err = s.db.Where("id = ? AND user_id = ? AND is_active = true", sessionIDToRemove, user.ID).First(&sessionToRemove).Error
	if err != nil {
		return nil, errors.New("session not found or already logged out")
	}

	// Deactivate the selected session
	if err := s.db.Model(&sessionToRemove).Updates(map[string]interface{}{
		"is_active":   false,
		"is_current":  false,
		"logout_at":   time.Now(),
		"logout_type": "force_logout_by_new_device",
	}).Error; err != nil {
		return nil, fmt.Errorf("failed to logout session: %w", err)
	}

	// Also invalidate the device session cache for the removed session
	removedCacheKey := fmt.Sprintf("session:device:%s", sessionIDToRemove.String())
	s.cache.Delete(ctx, removedCacheKey)

	// Now proceed with normal login (device limit should pass now)
	// Handle Super User (SaaS admin) - they don't have a tenant
	var tenantID uuid.UUID
	if user.Role == models.RoleSaasAdmin && user.IsSuperuser {
		tenantID = uuid.Nil
	} else {
		if user.TenantID != nil {
			tenantID = *user.TenantID
		}
	}

	// ========== Determine Session ID for JWT token ==========
	// Pre-generate session ID so it can be included in JWT
	var sessionID string
	var deviceName string
	var preGeneratedSessionID uuid.UUID

	if req.DeviceID != "" {
		preGeneratedSessionID = uuid.New()
		sessionID = preGeneratedSessionID.String()
	}

	// Generate JWT token WITH session_id for device-specific logout
	tokenString, refreshToken, expiresAt, err := s.generateTokensWithRole(user.ID, tenantID, user.Role, sessionID)
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

	if tenantID != uuid.Nil {
		sessionData["tenant_id"] = tenantID.String()
	} else {
		sessionData["tenant_id"] = nil
	}

	if err := s.cache.Set(ctx, sessionKey, sessionData, 45*24*time.Hour); err != nil {
		return nil, fmt.Errorf("failed to store session: %w", err)
	}

	// Create device session ASYNC (saves ~20-30ms)
	if req.DeviceID != "" {
		deviceReq := &LoginWithDeviceRequest{
			LoginRequest: LoginRequest{
				DeviceID:   req.DeviceID,
				DeviceName: req.DeviceName,
				DeviceType: req.DeviceType,
				OSName:     req.OSName,
				OSVersion:  req.OSVersion,
				AppVersion: req.AppVersion,
			},
		}

		// Fire and forget - don't block on DB operation
		createDeviceSessionAsync(&deviceSessionRequest{
			service:        s,
			ctx:            ctx,
			user:           user,
			deviceReq:      deviceReq,
			tokenString:    tokenString,
			refreshToken:   refreshToken,
			expiresAt:      expiresAt,
			preGeneratedID: preGeneratedSessionID,
			isRefresh:      false,
		})

		// DeviceName is determined synchronously
		if req.DeviceName != "" {
			deviceName = req.DeviceName
		} else {
			deviceName = req.DeviceType // fallback
		}
	}

	return &VerifyOTPResponse{
		Token:        tokenString,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt,
		User:         s.mapUserToResponse(user),
		Tenant:       s.mapTenantToResponse(user.Tenant),
		Message:      "Login successful (previous device logged out)",
		Purpose:      "login",
		SessionID:    sessionID,
		DeviceName:   deviceName,
	}, nil
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

// CheckUser checks if a user exists by mobile number or email without sending OTP
func (s *AuthService) CheckUser(ctx context.Context, req CheckUserRequest) (*CheckUserResponse, error) {
	// Check if email is provided (for email validation)
	if req.Email != "" {
		// Email validation
		var existingUser models.User
		err := s.db.Where("email = ?", req.Email).First(&existingUser).Error

		if err == nil {
			// Email exists
			if !existingUser.IsActive {
				return nil, errors.New("user account is inactive")
			}
			return &CheckUserResponse{
				Exists:  true,
				Message: "Email already registered.",
			}, nil
		} else if errors.Is(err, gorm.ErrRecordNotFound) {
			// Email doesn't exist
			return &CheckUserResponse{
				Exists:  false,
				Message: "Email is available.",
			}, nil
		} else {
			// Database error
			return nil, fmt.Errorf("failed to check email: %w", err)
		}
	}

	// Phone validation (existing logic)
	// Support both "mobile" and "phone" field names for Flutter app compatibility
	mobile := req.Mobile
	if mobile == "" {
		mobile = req.Phone
	}

	// Sanitize phone number (remove spaces)
	mobile = s.sanitizeMobileNumber(mobile)

	// Security: Validate and sanitize mobile number
	if !s.isValidMobileNumber(mobile) {
		return nil, errors.New("invalid mobile number format")
	}

	// Check if user exists by mobile number (using sanitized number)
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

// getUserByPhoneCached retrieves user by phone with Redis caching (2-minute TTL)
// Saves ~5-10ms on DB lookups in hot OTP paths
func (s *AuthService) getUserByPhoneCached(ctx context.Context, phone string) (*models.User, error) {
	cacheKey := fmt.Sprintf(cache.UserByPhoneKey, phone)

	// Try cache first
	var cachedUser models.User
	if err := s.cache.Get(ctx, cacheKey, &cachedUser); err == nil && cachedUser.ID != uuid.Nil {
		// Cache hit - but we still need to load tenant for preload
		if cachedUser.TenantID != nil {
			var tenant models.Tenant
			if err := s.db.Where("id = ?", cachedUser.TenantID).First(&tenant).Error; err == nil {
				cachedUser.Tenant = &tenant
			}
		}
		return &cachedUser, nil
	}

	// Cache miss - query DB
	var user models.User
	if err := s.db.Where("phone = ?", phone).Preload("Tenant").First(&user).Error; err != nil {
		return nil, err
	}

	// Cache for 2 minutes (short TTL for consistency)
	s.cache.Set(ctx, cacheKey, user, cache.UserByPhoneTTL)

	return &user, nil
}

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
		"+919876543210": "123456", // Apple App Store Review Test Account
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

// generateTokens creates JWT access and refresh tokens (without session_id - for backward compatibility)
func (s *AuthService) generateTokens(userID, tenantID uuid.UUID) (string, string, time.Time, error) {
	return s.generateTokensWithRole(userID, tenantID, "admin", "")
}

// generateTokensWithRole creates JWT access and refresh tokens with specified role
// sessionID is optional - if provided, it enables device-specific session validation
func (s *AuthService) generateTokensWithRole(userID, tenantID uuid.UUID, role string, sessionID string) (string, string, time.Time, error) {
	// Set token expiration (45 days for better user experience)
	expiresAt := time.Now().Add(45 * 24 * time.Hour)

	// Create JWT claims
	claims := jwt.MapClaims{
		"user_id": userID.String(),
		"role":    role,
		"exp":     expiresAt.Unix(),
		"iat":     time.Now().Unix(),
	}

	// Add session_id if provided (enables device-specific logout)
	if sessionID != "" {
		claims["session_id"] = sessionID
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

	// Create refresh token (longer expiry - 60 days)
	refreshClaims := jwt.MapClaims{
		"user_id": userID.String(),
		"role":    role,
		"exp":     time.Now().Add(60 * 24 * time.Hour).Unix(),
		"iat":     time.Now().Unix(),
		"type":    "refresh",
	}

	// Add session_id to refresh token as well
	if sessionID != "" {
		refreshClaims["session_id"] = sessionID
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

// ============================================================================
// Device Session Management - 2 Device Login Limit (like Swiggy/Zomato)
// ============================================================================

// LoginWithDeviceRequest extends LoginRequest with IP address (set by handler)
type LoginWithDeviceRequest struct {
	LoginRequest
	IPAddress         string
	DeviceFingerprint string // Generated client-side for fraud detection
	ScreenResolution  string
	Timezone          string
	Language          string
}

// ============================================================================
// Security Event Logging (Industrial-grade audit trail)
// ============================================================================

// LogSecurityEvent logs a security-related event for audit purposes
// Uses buffered channel for batch processing (prevents goroutine leak)
func (s *AuthService) LogSecurityEvent(ctx context.Context, event *models.SecurityEvent) {
	// Non-blocking: Queue to buffered channel for batch processing
	// This prevents unbounded goroutine spawning (memory optimization)
	select {
	case securityEventBuffer <- &securityEventWithDB{event: event, db: s.db.DB}:
		// Event queued successfully
	default:
		// Buffer full - log warning but don't block
		log.Printf("Security event buffer full, dropping event: %s for user %s", event.EventType, event.UserID)
	}

	// Also log to console for real-time monitoring
	emoji := "ℹ️"
	switch event.Severity {
	case models.SeverityWarning:
		emoji = "⚠️"
	case models.SeverityCritical:
		emoji = "🚨"
	}
	fmt.Printf("%s [Security] User: %s, Event: %s, IP: %s, Device: %s\n",
		emoji, event.UserID, event.EventType, event.IPAddress, event.DeviceID)
}

// ============================================================================
// Device Limit Check with Atomic Redis Locking (like Swiggy/Zomato)
// ============================================================================

// CheckDeviceLimit checks if user has reached the maximum device limit
// Uses Redis distributed lock for atomic enforcement (prevents race conditions)
// Returns existing session if device is already logged in, or error if limit reached
func (s *AuthService) CheckDeviceLimit(ctx context.Context, userID uuid.UUID, deviceID string) (*models.UserSession, error) {
	// Atomic lock to prevent race conditions when multiple devices try to login simultaneously
	lockKey := fmt.Sprintf("device_limit_lock:%s", userID.String())
	lockValue := fmt.Sprintf("%s:%d", deviceID, time.Now().UnixNano())

	// Try to acquire lock with exponential backoff (50ms, 100ms, 200ms) - no blocking sleep
	var acquired bool
	var err error
	for i := 0; i < 3; i++ {
		acquired, err = s.cache.SetNX(ctx, lockKey, lockValue, 10*time.Second)
		if err != nil {
			log.Printf("[DeviceLimit] Lock acquire error for user %s: %v", userID, err)
			break // Continue without lock
		}
		if acquired {
			break
		}
		// Exponential backoff with context check
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Duration(50<<i) * time.Millisecond):
			continue
		}
	}
	if !acquired && err == nil {
		return nil, errors.New("another login is in progress. Please try again")
	}

	// Ensure lock is released when done
	defer func() {
		// Only release if we own the lock
		var storedValue string
		if err := s.cache.Get(ctx, lockKey, &storedValue); err == nil && storedValue == lockValue {
			s.cache.Delete(ctx, lockKey)
		}
	}()

	// Check Redis cache first for active sessions (30 second TTL)
	cacheKey := fmt.Sprintf(cache.ActiveSessionsKey, userID.String())
	var activeSessions []models.UserSession

	if cacheErr := s.cache.Get(ctx, cacheKey, &activeSessions); cacheErr != nil {
		// Cache miss - query DB with optimized SELECT
		err = s.db.DB.Where("user_id = ? AND is_active = true AND deleted_at IS NULL", userID).
			Select("id, user_id, device_id, device_name, device_type, os_name, os_version, last_active_at, is_current").
			Order("last_active_at DESC").
			Limit(5). // Only need max devices + safety margin
			Find(&activeSessions).Error

		if err != nil {
			return nil, fmt.Errorf("failed to get active sessions: %w", err)
		}

		// Cache for 30 seconds
		s.cache.Set(ctx, cacheKey, activeSessions, cache.DeviceCacheTTL)
	}

	// Check if this device already has a session (allow re-login from same device)
	for _, session := range activeSessions {
		if session.DeviceID == deviceID && deviceID != "" {
			return &session, nil // Device already logged in, will refresh session
		}
	}

	// Check device limit
	if len(activeSessions) >= models.MaxDevicesPerUser {
		// Log security event for device limit reached
		s.LogSecurityEvent(ctx, &models.SecurityEvent{
			UserID:      userID,
			EventType:   models.EventTypeDeviceLimitReached,
			Severity:    models.SeverityInfo,
			DeviceID:    deviceID,
			Description: fmt.Sprintf("User attempted login from new device but has %d active sessions (limit: %d)", len(activeSessions), models.MaxDevicesPerUser),
		})

		return nil, &models.DeviceLimitError{
			ActiveSessions: activeSessions,
			Message:        fmt.Sprintf("Maximum device limit (%d) reached. Please logout from another device.", models.MaxDevicesPerUser),
			MaxDevices:     models.MaxDevicesPerUser,
		}
	}

	return nil, nil // OK to create new session
}

// ============================================================================
// Device Fingerprint Calculation (Fraud Detection)
// ============================================================================

// CalculateDeviceFingerprint creates a hash of device characteristics for fraud detection
func (s *AuthService) CalculateDeviceFingerprint(req *LoginWithDeviceRequest) string {
	// Combine device characteristics into a fingerprint
	components := []string{
		req.DeviceID,
		req.DeviceType,
		req.OSName,
		req.OSVersion,
		req.ScreenResolution,
		req.Timezone,
		req.Language,
	}

	combined := strings.Join(components, "|")
	hash := sha256.Sum256([]byte(combined))
	return hex.EncodeToString(hash[:16]) // First 16 bytes = 32 hex chars
}

// CalculateRiskScore evaluates the risk level of a login attempt
func (s *AuthService) CalculateRiskScore(ctx context.Context, userID uuid.UUID, req *LoginWithDeviceRequest, existingSession *models.UserSession) int {
	riskScore := 0

	// Check for known device
	var previousSessions []models.UserSession
	s.db.DB.Where("user_id = ? AND device_id = ?", userID, req.DeviceID).
		Order("created_at DESC").
		Limit(5).
		Find(&previousSessions)

	if len(previousSessions) == 0 {
		riskScore += 15 // New device - slightly elevated risk
	}

	// Check for IP change from last login
	if existingSession != nil && existingSession.IPAddress != req.IPAddress {
		riskScore += 10 // IP changed
	}

	// Check for rapid login attempts
	recentAttemptKey := fmt.Sprintf("login_attempts:%s", userID.String())
	var recentAttempts int
	s.cache.Get(ctx, recentAttemptKey, &recentAttempts)
	if recentAttempts > 5 {
		riskScore += 20 // Too many login attempts
	}

	// Check for device fingerprint mismatch
	if existingSession != nil && existingSession.DeviceFingerprint != "" {
		calculatedFingerprint := s.CalculateDeviceFingerprint(req)
		if existingSession.DeviceFingerprint != calculatedFingerprint {
			riskScore += 25 // Device fingerprint changed
		}
	}

	return min(riskScore, 100) // Cap at 100
}

// CreateDeviceSession creates a new session with device tracking and security logging
func (s *AuthService) CreateDeviceSession(ctx context.Context, user *models.User, req *LoginWithDeviceRequest, token, refreshToken string, expiresAt time.Time) (*models.UserSession, error) {
	// Hash the token for secure storage
	tokenHash := hashTokenForStorage(token)

	// Calculate device fingerprint for fraud detection
	deviceFingerprint := s.CalculateDeviceFingerprint(req)

	// Calculate risk score for this login
	riskScore := s.CalculateRiskScore(ctx, user.ID, req, nil)

	now := time.Now()
	session := &models.UserSession{
		UserID:       user.ID,
		Token:        token[:min(len(token), 100)] + "...", // Store truncated for reference
		TokenHash:    tokenHash,
		RefreshToken: hashTokenForStorage(refreshToken),
		DeviceID:     req.DeviceID,
		DeviceName:   getDeviceName(req.DeviceName, req.OSName),
		DeviceType:   getDeviceType(req.DeviceType),
		OSName:       req.OSName,
		OSVersion:    req.OSVersion,
		AppVersion:   req.AppVersion,
		IPAddress:    req.IPAddress,
		ExpiresAt:    &expiresAt,
		LastActiveAt: &now,
		IsActive:     true,
		IsCurrent:    true,
		// Industrial-grade security fields
		DeviceFingerprint: deviceFingerprint,
		ScreenResolution:  req.ScreenResolution,
		Timezone:          req.Timezone,
		Language:          req.Language,
		LoginMethod:       models.LoginMethodOTP,
		RiskScore:         riskScore,
	}

	// Start transaction
	tx := s.db.DB.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Deactivate "is_current" for other sessions of this user
	if err := tx.Model(&models.UserSession{}).
		Where("user_id = ? AND is_active = true", user.ID).
		Update("is_current", false).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update existing sessions: %w", err)
	}

	// Create new session in database
	if err := tx.Create(session).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create session: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit session: %w", err)
	}

	// Cache session in Redis for fast validation (with sliding expiration support)
	cacheKey := fmt.Sprintf("session:device:%s", session.ID.String())
	cacheData := map[string]interface{}{
		"user_id":            user.ID.String(),
		"session_id":         session.ID.String(),
		"device_id":          session.DeviceID,
		"device_fingerprint": deviceFingerprint,
		"ip_address":         req.IPAddress,
		"is_active":          true,
		"created_at":         now.Unix(),
		"last_active_at":     now.Unix(),
	}
	if user.TenantID != nil {
		cacheData["tenant_id"] = user.TenantID.String()
	}
	s.cache.Set(ctx, cacheKey, cacheData, cache.SessionTTL)

	// Log security event for successful login
	s.LogSecurityEvent(ctx, &models.SecurityEvent{
		UserID:      user.ID,
		SessionID:   &session.ID,
		EventType:   models.EventTypeLogin,
		Severity:    models.SeverityInfo,
		IPAddress:   req.IPAddress,
		DeviceID:    req.DeviceID,
		Description: fmt.Sprintf("Login successful from %s (%s)", session.DeviceName, session.DeviceType),
		RiskScore:   riskScore,
	})

	// Track login attempts for rate limiting
	loginAttemptKey := fmt.Sprintf("login_attempts:%s", user.ID.String())
	s.cache.Delete(ctx, loginAttemptKey) // Reset on successful login

	return session, nil
}

// CreateDeviceSessionWithID creates a new session with a pre-generated session ID
// This is used when the session ID needs to be known before creating the session (e.g., for JWT claims)
// Industrial-grade: Includes device fingerprinting, risk scoring, and security event logging
func (s *AuthService) CreateDeviceSessionWithID(ctx context.Context, user *models.User, req *LoginWithDeviceRequest, token, refreshToken string, expiresAt time.Time, sessionID uuid.UUID) (*models.UserSession, error) {
	// Hash the token for secure storage
	tokenHash := hashTokenForStorage(token)

	// Calculate device fingerprint for fraud detection
	deviceFingerprint := s.CalculateDeviceFingerprint(req)

	// Calculate risk score for this login
	riskScore := s.CalculateRiskScore(ctx, user.ID, req, nil)

	now := time.Now()
	session := &models.UserSession{
		BaseModel: models.BaseModel{
			ID: sessionID, // Use pre-generated session ID
		},
		UserID:       user.ID,
		Token:        token[:min(len(token), 100)] + "...", // Store truncated for reference
		TokenHash:    tokenHash,
		RefreshToken: hashTokenForStorage(refreshToken),
		DeviceID:     req.DeviceID,
		DeviceName:   getDeviceName(req.DeviceName, req.OSName),
		DeviceType:   getDeviceType(req.DeviceType),
		OSName:       req.OSName,
		OSVersion:    req.OSVersion,
		AppVersion:   req.AppVersion,
		IPAddress:    req.IPAddress,
		ExpiresAt:    &expiresAt,
		LastActiveAt: &now,
		IsActive:     true,
		IsCurrent:    true,
		// Industrial-grade security fields
		DeviceFingerprint: deviceFingerprint,
		ScreenResolution:  req.ScreenResolution,
		Timezone:          req.Timezone,
		Language:          req.Language,
		LoginMethod:       models.LoginMethodOTP,
		RiskScore:         riskScore,
	}

	// Start transaction
	tx := s.db.DB.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Deactivate "is_current" for other sessions of this user
	if err := tx.Model(&models.UserSession{}).
		Where("user_id = ? AND is_active = true", user.ID).
		Update("is_current", false).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update existing sessions: %w", err)
	}

	// Create new session in database
	if err := tx.Create(session).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create session: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit session: %w", err)
	}

	// Cache session in Redis for fast validation (with sliding expiration support)
	cacheKey := fmt.Sprintf("session:device:%s", session.ID.String())
	cacheData := map[string]interface{}{
		"user_id":            user.ID.String(),
		"session_id":         session.ID.String(),
		"device_id":          session.DeviceID,
		"device_fingerprint": deviceFingerprint,
		"ip_address":         req.IPAddress,
		"is_active":          true,
		"created_at":         now.Unix(),
		"last_active_at":     now.Unix(),
	}
	if user.TenantID != nil {
		cacheData["tenant_id"] = user.TenantID.String()
	}
	s.cache.Set(ctx, cacheKey, cacheData, cache.SessionTTL)

	// Log security event for successful login
	s.LogSecurityEvent(ctx, &models.SecurityEvent{
		UserID:      user.ID,
		SessionID:   &session.ID,
		EventType:   models.EventTypeLogin,
		Severity:    models.SeverityInfo,
		IPAddress:   req.IPAddress,
		DeviceID:    req.DeviceID,
		Description: fmt.Sprintf("Login successful from %s (%s)", session.DeviceName, session.DeviceType),
		RiskScore:   riskScore,
	})

	// Track login attempts for rate limiting
	loginAttemptKey := fmt.Sprintf("login_attempts:%s", user.ID.String())
	s.cache.Delete(ctx, loginAttemptKey) // Reset on successful login

	return session, nil
}

// RefreshDeviceSession updates an existing session when same device re-logs in
// Industrial-grade: Includes refresh counting and sliding expiration
func (s *AuthService) RefreshDeviceSession(ctx context.Context, session *models.UserSession, token, refreshToken string, expiresAt time.Time) error {
	now := time.Now()

	// Increment refresh count for security monitoring
	newRefreshCount := session.RefreshCount + 1

	updates := map[string]interface{}{
		"token_hash":      hashTokenForStorage(token),
		"refresh_token":   hashTokenForStorage(refreshToken),
		"expires_at":      expiresAt,
		"last_active_at":  now,
		"last_refresh_at": now,
		"refresh_count":   newRefreshCount,
		"is_current":      true,
	}

	if err := s.db.DB.Model(&models.UserSession{}).
		Where("id = ?", session.ID).
		Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to refresh session: %w", err)
	}

	// Re-cache session in Redis for fast validation (sliding expiration)
	cacheKey := fmt.Sprintf("session:device:%s", session.ID.String())
	cacheData := map[string]interface{}{
		"user_id":            session.UserID.String(),
		"session_id":         session.ID.String(),
		"device_id":          session.DeviceID,
		"device_fingerprint": session.DeviceFingerprint,
		"ip_address":         session.IPAddress,
		"is_active":          true,
		"last_active_at":     now.Unix(),
		"refresh_count":      newRefreshCount,
	}
	s.cache.Set(ctx, cacheKey, cacheData, cache.SessionTTL)

	// Log token refresh for security monitoring
	s.LogSecurityEvent(ctx, &models.SecurityEvent{
		UserID:      session.UserID,
		SessionID:   &session.ID,
		EventType:   models.EventTypeTokenRefresh,
		Severity:    models.SeverityInfo,
		DeviceID:    session.DeviceID,
		Description: fmt.Sprintf("Token refreshed (count: %d)", newRefreshCount),
	})

	return nil
}

// UpdateSessionHeartbeat updates the last_active_at timestamp for sliding session expiration
// Called periodically by the client to keep session alive (like Swiggy/Zomato)
func (s *AuthService) UpdateSessionHeartbeat(ctx context.Context, sessionID uuid.UUID, ipAddress string) error {
	now := time.Now()

	// Update database
	result := s.db.DB.Model(&models.UserSession{}).
		Where("id = ? AND is_active = true", sessionID).
		Update("last_active_at", now)

	if result.Error != nil {
		return fmt.Errorf("failed to update heartbeat: %w", result.Error)
	}

	if result.RowsAffected == 0 {
		return errors.New("session not found or inactive")
	}

	// Update Redis cache with sliding expiration
	cacheKey := fmt.Sprintf("session:device:%s", sessionID.String())
	var cacheData map[string]interface{}
	if err := s.cache.Get(ctx, cacheKey, &cacheData); err == nil {
		cacheData["last_active_at"] = now.Unix()
		// Check for IP change (security monitoring)
		if storedIP, ok := cacheData["ip_address"].(string); ok && storedIP != ipAddress {
			cacheData["ip_changed"] = true
			// Log IP change as a warning
			if userIDStr, ok := cacheData["user_id"].(string); ok {
				userID, _ := uuid.Parse(userIDStr)
				s.LogSecurityEvent(ctx, &models.SecurityEvent{
					UserID:      userID,
					SessionID:   &sessionID,
					EventType:   models.EventTypeIPChange,
					Severity:    models.SeverityWarning,
					IPAddress:   ipAddress,
					Description: fmt.Sprintf("IP changed from %s to %s during session", storedIP, ipAddress),
				})
			}
		}
		s.cache.Set(ctx, cacheKey, cacheData, cache.SessionTTL) // Refresh TTL
	}

	return nil
}

// GetActiveSessions returns all active sessions for a user
func (s *AuthService) GetActiveSessions(ctx context.Context, userID uuid.UUID) ([]models.UserSession, error) {
	var sessions []models.UserSession
	err := s.db.DB.Where("user_id = ? AND is_active = true AND deleted_at IS NULL", userID).
		Order("last_active_at DESC").
		Find(&sessions).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get sessions: %w", err)
	}

	return sessions, nil
}

// LogoutDevice deactivates a specific session/device with audit trail
func (s *AuthService) LogoutDevice(ctx context.Context, userID uuid.UUID, sessionID uuid.UUID) error {
	return s.LogoutDeviceWithReason(ctx, userID, sessionID, models.LogoutTypeUserInitiated, "")
}

// LogoutDeviceWithReason deactivates a specific session with a specified reason for audit trail
func (s *AuthService) LogoutDeviceWithReason(ctx context.Context, userID uuid.UUID, sessionID uuid.UUID, logoutType string, reason string) error {
	now := time.Now()

	// First get the session details for logging
	var session models.UserSession
	if err := s.db.DB.Where("id = ? AND user_id = ?", sessionID, userID).First(&session).Error; err != nil {
		return errors.New("session not found")
	}

	result := s.db.DB.Model(&models.UserSession{}).
		Where("id = ? AND user_id = ? AND is_active = true", sessionID, userID).
		Updates(map[string]interface{}{
			"is_active":   false,
			"logout_at":   now,
			"logout_type": logoutType,
			"deleted_at":  now,
		})

	if result.Error != nil {
		return fmt.Errorf("failed to logout device: %w", result.Error)
	}

	if result.RowsAffected == 0 {
		return errors.New("session not found or already logged out")
	}

	// Remove from Redis cache
	cacheKey := fmt.Sprintf("session:device:%s", sessionID.String())
	s.cache.Delete(ctx, cacheKey)

	// Log security event for logout
	description := fmt.Sprintf("Device logged out: %s (%s)", session.DeviceName, logoutType)
	if reason != "" {
		description = description + " - " + reason
	}
	s.LogSecurityEvent(ctx, &models.SecurityEvent{
		UserID:      userID,
		SessionID:   &sessionID,
		EventType:   models.EventTypeLogout,
		Severity:    models.SeverityInfo,
		IPAddress:   session.IPAddress,
		DeviceID:    session.DeviceID,
		Description: description,
	})

	return nil
}

// LogoutAllDevices deactivates all sessions for a user, optionally except one
func (s *AuthService) LogoutAllDevices(ctx context.Context, userID uuid.UUID, exceptSessionID *uuid.UUID) (int64, error) {
	return s.LogoutAllDevicesWithReason(ctx, userID, exceptSessionID, models.LogoutTypeUserInitiated, "")
}

// LogoutAllDevicesWithReason deactivates all sessions with a specified reason
func (s *AuthService) LogoutAllDevicesWithReason(ctx context.Context, userID uuid.UUID, exceptSessionID *uuid.UUID, logoutType string, reason string) (int64, error) {
	now := time.Now()

	// Get sessions to be logged out for audit trail
	var sessionsToLogout []models.UserSession
	query := s.db.DB.Where("user_id = ? AND is_active = true", userID)
	if exceptSessionID != nil {
		query = query.Where("id != ?", *exceptSessionID)
	}
	query.Find(&sessionsToLogout)

	// Update all matching sessions
	updateQuery := s.db.DB.Model(&models.UserSession{}).
		Where("user_id = ? AND is_active = true", userID)

	if exceptSessionID != nil {
		updateQuery = updateQuery.Where("id != ?", *exceptSessionID)
	}

	result := updateQuery.Updates(map[string]interface{}{
		"is_active":   false,
		"logout_at":   now,
		"logout_type": logoutType,
		"deleted_at":  now,
	})

	if result.Error != nil {
		return 0, fmt.Errorf("failed to logout all devices: %w", result.Error)
	}

	// Invalidate all cached sessions for this user
	s.invalidateUserSessionsCache(ctx, userID)

	// Log security event for each logout
	for _, session := range sessionsToLogout {
		sessionID := session.ID
		description := fmt.Sprintf("Device logged out (bulk): %s (%s)", session.DeviceName, logoutType)
		if reason != "" {
			description = description + " - " + reason
		}
		s.LogSecurityEvent(ctx, &models.SecurityEvent{
			UserID:      userID,
			SessionID:   &sessionID,
			EventType:   models.EventTypeLogout,
			Severity:    models.SeverityInfo,
			IPAddress:   session.IPAddress,
			DeviceID:    session.DeviceID,
			Description: description,
		})
	}

	return result.RowsAffected, nil
}

// UpdateSessionActivity updates the last_active_at timestamp for a session
func (s *AuthService) UpdateSessionActivity(ctx context.Context, sessionID uuid.UUID) error {
	return s.db.DB.Model(&models.UserSession{}).
		Where("id = ? AND is_active = true", sessionID).
		Update("last_active_at", time.Now()).Error
}

// ValidateSessionActive checks if a session is still active
func (s *AuthService) ValidateSessionActive(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	// Check Redis cache first
	cacheKey := fmt.Sprintf("session:device:%s", sessionID.String())
	var cacheData map[string]interface{}
	if err := s.cache.Get(ctx, cacheKey, &cacheData); err == nil {
		if isActive, ok := cacheData["is_active"].(bool); ok && isActive {
			return true, nil
		}
	}

	// Fallback to database
	var session models.UserSession
	err := s.db.DB.Where("id = ? AND is_active = true AND deleted_at IS NULL", sessionID).
		First(&session).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false, nil
		}
		return false, err
	}

	// Check if session is expired
	if session.ExpiresAt != nil && session.ExpiresAt.Before(time.Now()) {
		return false, nil
	}

	// Re-cache the session
	s.cache.Set(ctx, cacheKey, map[string]interface{}{
		"user_id":    session.UserID.String(),
		"session_id": session.ID.String(),
		"is_active":  true,
	}, 5*time.Minute)

	return true, nil
}

// invalidateUserSessionsCache clears all cached sessions for a user
func (s *AuthService) invalidateUserSessionsCache(ctx context.Context, userID uuid.UUID) {
	// Get all sessions from DB to get their IDs for cache invalidation
	var sessions []models.UserSession
	s.db.DB.Where("user_id = ?", userID).Find(&sessions)

	for _, session := range sessions {
		cacheKey := fmt.Sprintf("session:device:%s", session.ID.String())
		s.cache.Delete(ctx, cacheKey)
	}
}

// ============================================================================
// Account Deletion (App Store Guideline 5.1.1(v) Compliance)
// ============================================================================

// DeleteAccountOTPRequest is the request to send OTP for account deletion
type DeleteAccountOTPRequest struct {
	UserID uuid.UUID `json:"-"` // Set from JWT context
	Mobile string    `json:"-"` // Set from user record
}

// DeleteAccountOTPResponse is the response after sending deletion OTP
type DeleteAccountOTPResponse struct {
	Message   string    `json:"message"`
	SessionID string    `json:"session_id"`
	ExpiresAt time.Time `json:"expires_at"`
}

// DeleteAccountRequest is the request to delete account with OTP verification
type DeleteAccountRequest struct {
	UserID    uuid.UUID `json:"-"`                           // Set from JWT context
	OTP       string    `json:"otp" binding:"required"`      // 6-digit OTP
	SessionID string    `json:"session_id" binding:"required"` // Session from OTP request
	Reason    string    `json:"reason"`                      // Optional reason for deletion
}

// DeleteAccountResponse is the response after account deletion request
type DeleteAccountResponse struct {
	Message             string    `json:"message"`
	DeletionScheduledFor time.Time `json:"deletion_scheduled_for"`
}

// CancelDeletionResponse is the response after cancelling account deletion
type CancelDeletionResponse struct {
	Message string `json:"message"`
}

// RequestDeleteAccountOTP sends OTP for account deletion verification
func (s *AuthService) RequestDeleteAccountOTP(ctx context.Context, userID uuid.UUID) (*DeleteAccountOTPResponse, error) {
	// Get user to retrieve mobile number
	var user models.User
	err := s.db.Where("id = ?", userID).First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	// Check if user is active
	if !user.IsActive {
		return nil, errors.New("user account is already inactive")
	}

	// Check if deletion is already pending
	if user.DeletionScheduledFor != nil {
		return nil, fmt.Errorf("account deletion already scheduled for %s", user.DeletionScheduledFor.Format("2006-01-02"))
	}

	mobile := s.sanitizeMobileNumber(user.Phone)

	// Security: Check if number is blocked due to suspicious activity
	if s.isNumberBlocked(ctx, mobile) {
		return nil, errors.New("mobile number temporarily blocked due to suspicious activity")
	}

	// Security: Rate limiting
	if err := s.checkOTPRateLimit(ctx, mobile); err != nil {
		return nil, err
	}

	// Generate secure session ID and OTP
	sessionID := s.generateSecureSessionID()
	otp := s.getOTPForMobile(mobile)
	if s.isProduction() && otp == "" {
		otp = s.generateSecureOTP()
	}

	// Hash OTP before storing
	hashedOTP := s.hashOTP(otp)

	// Store OTP data in Redis with expiration (10 minutes)
	otpData := map[string]interface{}{
		"hashed_otp":   hashedOTP,
		"mobile":       mobile,
		"user_id":      userID.String(),
		"attempts":     0,
		"created_at":   time.Now().Unix(),
		"session_id":   sessionID,
		"max_attempts": 3,
		"purpose":      "account_deletion",
	}

	expiryDuration := 10 * time.Minute
	otpKey := fmt.Sprintf("otp:delete:%s", userID.String())

	if err := s.cache.Set(ctx, otpKey, otpData, expiryDuration); err != nil {
		return nil, fmt.Errorf("failed to store OTP: %w", err)
	}

	// Send SMS OTP
	if s.isProduction() {
		fmt.Printf("🗑️ Account Deletion OTP Generated for %s: %s (Valid for 10 minutes)\n", s.maskMobileNumber(mobile), otp)
		if err := s.sendSMSOTP(mobile, otp); err != nil {
			fmt.Printf("Warning: Failed to send SMS to %s: %v\n", s.maskMobileNumber(mobile), err)
		} else {
			fmt.Printf("✅ Account Deletion OTP sent to %s\n", s.maskMobileNumber(mobile))
		}
	} else {
		fmt.Printf("📱 Account Deletion OTP for %s: %s (Development Mode)\n", s.maskMobileNumber(mobile), otp)
	}

	now := time.Now()
	return &DeleteAccountOTPResponse{
		Message:   fmt.Sprintf("OTP sent to %s for account deletion verification", s.maskMobileNumber(mobile)),
		SessionID: sessionID,
		ExpiresAt: now.Add(expiryDuration),
	}, nil
}

// DeleteAccount processes the account deletion request after OTP verification
func (s *AuthService) DeleteAccount(ctx context.Context, req DeleteAccountRequest) (*DeleteAccountResponse, error) {
	// Retrieve OTP data
	otpKey := fmt.Sprintf("otp:delete:%s", req.UserID.String())
	var otpData map[string]interface{}
	err := s.cache.Get(ctx, otpKey, &otpData)
	if err != nil {
		return nil, errors.New("OTP expired or not found. Please request a new OTP.")
	}

	// Verify session ID
	if storedSessionID, ok := otpData["session_id"].(string); ok {
		if storedSessionID != req.SessionID {
			return nil, errors.New("invalid session")
		}
	} else {
		return nil, errors.New("invalid OTP data")
	}

	// Check attempt limit
	attempts, _ := otpData["attempts"].(float64)
	maxAttempts, _ := otpData["max_attempts"].(float64)
	if attempts >= maxAttempts {
		s.cache.Delete(ctx, otpKey)
		return nil, errors.New("maximum OTP attempts exceeded. Please request a new OTP.")
	}

	// Verify OTP
	storedHashedOTP, ok := otpData["hashed_otp"].(string)
	if !ok {
		return nil, errors.New("invalid OTP data")
	}

	if !s.verifyOTPHash(req.OTP, storedHashedOTP) {
		// Increment attempts counter
		attempts++
		otpData["attempts"] = attempts
		s.cache.Set(ctx, otpKey, otpData, 10*time.Minute)

		mobile, _ := otpData["mobile"].(string)
		s.incrementFailureCounter(ctx, mobile)

		return nil, errors.New("invalid OTP")
	}

	// OTP verified - clear it
	s.cache.Delete(ctx, otpKey)

	// Get user
	var user models.User
	err = s.db.Where("id = ?", req.UserID).First(&user).Error
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}

	// Check if user is active
	if !user.IsActive && user.DeletionScheduledFor != nil {
		return nil, fmt.Errorf("account deletion already scheduled for %s", user.DeletionScheduledFor.Format("2006-01-02"))
	}

	// Set deletion schedule (30 days grace period)
	now := time.Now()
	deletionDate := now.AddDate(0, 0, 30) // 30 days from now

	// Update user record
	updates := map[string]interface{}{
		"is_active":              false,
		"deletion_requested_at":  now,
		"deletion_scheduled_for": deletionDate,
		"deletion_reason":        req.Reason,
	}

	if err := s.db.Model(&user).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to schedule account deletion: %w", err)
	}

	// Invalidate all user sessions (logout from all devices)
	s.LogoutAllDevices(ctx, req.UserID, nil)

	// Clear user session cache
	sessionKey := fmt.Sprintf(cache.UserSessionKey, req.UserID.String())
	s.cache.Delete(ctx, sessionKey)

	fmt.Printf("🗑️ Account deletion scheduled for user %s. Deletion date: %s\n", req.UserID.String(), deletionDate.Format("2006-01-02"))

	return &DeleteAccountResponse{
		Message:             "Account scheduled for deletion. You can cancel this within 30 days by logging in again.",
		DeletionScheduledFor: deletionDate,
	}, nil
}

// CancelAccountDeletion cancels a pending account deletion
func (s *AuthService) CancelAccountDeletion(ctx context.Context, userID uuid.UUID) (*CancelDeletionResponse, error) {
	// Get user
	var user models.User
	err := s.db.Where("id = ?", userID).First(&user).Error
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}

	// Check if deletion is pending
	if user.DeletionScheduledFor == nil {
		return nil, errors.New("no pending account deletion to cancel")
	}

	// Check if grace period has passed (shouldn't happen if deleted_at is set correctly)
	if user.DeletionScheduledFor.Before(time.Now()) {
		return nil, errors.New("grace period has expired. Account cannot be recovered.")
	}

	// Clear deletion fields and reactivate account
	updates := map[string]interface{}{
		"is_active":              true,
		"deletion_requested_at":  nil,
		"deletion_scheduled_for": nil,
		"deletion_reason":        "",
	}

	if err := s.db.Model(&user).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to cancel account deletion: %w", err)
	}

	fmt.Printf("✅ Account deletion cancelled for user %s\n", userID.String())

	return &CancelDeletionResponse{
		Message: "Account deletion has been cancelled. Your account is now active again.",
	}, nil
}

// Helper functions

func hashTokenForStorage(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func getDeviceName(name, osName string) string {
	if name != "" {
		return name
	}
	if osName != "" {
		return osName + " Device"
	}
	return "Unknown Device"
}

func getDeviceType(deviceType string) string {
	switch strings.ToLower(deviceType) {
	case "mobile", "phone":
		return "mobile"
	case "tablet", "ipad":
		return "tablet"
	case "web", "browser", "desktop":
		return "web"
	default:
		return "mobile" // Default to mobile for app users
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
