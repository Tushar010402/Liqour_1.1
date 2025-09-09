package services

import (
	"context"
	"errors"
	"fmt"
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
	db     *database.DB
	cache  *cache.Cache
	config *config.JWTConfig
}

// NewAuthService creates a new auth service
func NewAuthService(db *database.DB, cache *cache.Cache, jwtConfig *config.JWTConfig) *AuthService {
	return &AuthService{
		db:     db,
		cache:  cache,
		config: jwtConfig,
	}
}

// LoginRequest represents login request data
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// LoginResponse represents login response data
type LoginResponse struct {
	Token        string           `json:"token"`
	RefreshToken string           `json:"refresh_token"`
	ExpiresAt    time.Time        `json:"expires_at"`
	User         *UserResponse    `json:"user"`
	Tenant       *TenantResponse  `json:"tenant"`
}

// UserResponse represents user data in responses
type UserResponse struct {
	ID          uuid.UUID `json:"id"`
	Username    string    `json:"username"`
	Email       string    `json:"email"`
	FirstName   string    `json:"first_name"`
	LastName    string    `json:"last_name"`
	Role        string    `json:"role"`
	IsActive    bool      `json:"is_active"`
	ProfileImage string   `json:"profile_image"`
}

// TenantResponse represents tenant data in responses
type TenantResponse struct {
	ID       uuid.UUID `json:"id"`
	Name     string    `json:"name"`
	Domain   string    `json:"domain"`
	IsActive bool      `json:"is_active"`
}

// RegisterRequest represents registration request data
type RegisterRequest struct {
	Username    string `json:"username" binding:"required,min=3,max=50"`
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required,min=8"`
	FirstName   string `json:"first_name" binding:"required"`
	LastName    string `json:"last_name" binding:"required"`
	Phone       string `json:"phone"`
	TenantName  string `json:"tenant_name" binding:"required"`
	CompanyName string `json:"company_name" binding:"required"`
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
		"tenant_id":     user.TenantID.String(),
		"role":          user.Role,
		"login_time":    time.Now(),
		"refresh_token": refreshToken,
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
func (s *AuthService) Register(ctx context.Context, req RegisterRequest) (*LoginResponse, error) {
	var result *LoginResponse
	
	// Start transaction
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Check if username or email already exists
		var existingUser models.User
		if err := tx.Where("username = ? OR email = ?", req.Username, req.Email).First(&existingUser).Error; err == nil {
			return errors.New("username or email already exists")
		}

		// Create tenant
		tenant := models.Tenant{
			Name:         req.CompanyName,
			Domain:       req.TenantName,
			IsActive:     true,
			SubscribedAt: time.Now(),
		}

		if err := tx.Create(&tenant).Error; err != nil {
			return fmt.Errorf("failed to create tenant: %w", err)
		}

		// Hash password
		hashedPassword, err := utils.HashPassword(req.Password)
		if err != nil {
			return fmt.Errorf("failed to hash password: %w", err)
		}

		// Create user
		user := models.User{
			TenantModel: models.TenantModel{TenantID: tenant.ID},
			Username:    req.Username,
			Email:       req.Email,
			FirstName:   req.FirstName,
			LastName:    req.LastName,
			Phone:       req.Phone,
			PasswordHash: hashedPassword,
			Role:        models.RoleAdmin, // First user becomes admin
			IsActive:    true,
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
			"tenant_id":     user.TenantID.String(),
			"role":          user.Role,
			"login_time":    time.Now(),
			"refresh_token": refreshToken,
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
	return &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}
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