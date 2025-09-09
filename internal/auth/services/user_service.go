package services

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// UserService handles user management operations
type UserService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewUserService creates a new user service
func NewUserService(db *database.DB, cache *cache.Cache) *UserService {
	return &UserService{
		db:    db,
		cache: cache,
	}
}

// CreateUserRequest represents user creation request
type CreateUserRequest struct {
	Username    string `json:"username" binding:"required,min=3,max=50"`
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required,min=8"`
	FirstName   string `json:"first_name" binding:"required"`
	LastName    string `json:"last_name" binding:"required"`
	Phone       string `json:"phone"`
	Role        string `json:"role" binding:"required"`
	IsActive    bool   `json:"is_active"`
}

// UpdateUserRequest represents user update request
type UpdateUserRequest struct {
	FirstName    *string `json:"first_name"`
	LastName     *string `json:"last_name"`
	Phone        *string `json:"phone"`
	ProfileImage *string `json:"profile_image"`
	IsActive     *bool   `json:"is_active"`
}

// ChangePasswordRequest represents password change request
type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password" binding:"required,min=8"`
}

// UserListResponse represents paginated user list
type UserListResponse struct {
	Users      []*UserResponse `json:"users"`
	TotalCount int64           `json:"total_count"`
	Page       int             `json:"page"`
	PageSize   int             `json:"page_size"`
	TotalPages int             `json:"total_pages"`
}

// GetUsers returns paginated list of users for a tenant
func (s *UserService) GetUsers(ctx context.Context, tenantID uuid.UUID, page, pageSize int) (*UserListResponse, error) {
	var users []models.User
	var totalCount int64

	offset := (page - 1) * pageSize

	// Count total users
	if err := s.db.Model(&models.User{}).
		Where("tenant_id = ?", tenantID).
		Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count users: %w", err)
	}

	// Get users with pagination
	if err := s.db.Where("tenant_id = ?", tenantID).
		Preload("Salesman").
		Offset(offset).
		Limit(pageSize).
		Order("created_at DESC").
		Find(&users).Error; err != nil {
		return nil, fmt.Errorf("failed to get users: %w", err)
	}

	// Convert to response format
	userResponses := make([]*UserResponse, len(users))
	for i, user := range users {
		userResponses[i] = &UserResponse{
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

	totalPages := int((totalCount + int64(pageSize) - 1) / int64(pageSize))

	return &UserListResponse{
		Users:      userResponses,
		TotalCount: totalCount,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}, nil
}

// GetUserByID returns user by ID
func (s *UserService) GetUserByID(ctx context.Context, userID, tenantID uuid.UUID) (*UserResponse, error) {
	var user models.User
	
	err := s.db.Where("id = ? AND tenant_id = ?", userID, tenantID).
		Preload("Salesman").
		First(&user).Error
	
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	return &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}, nil
}

// CreateUser creates a new user
func (s *UserService) CreateUser(ctx context.Context, req CreateUserRequest, tenantID uuid.UUID) (*UserResponse, error) {
	// Check if username or email already exists
	var existingUser models.User
	if err := s.db.Where("(username = ? OR email = ?) AND tenant_id = ?", 
		req.Username, req.Email, tenantID).First(&existingUser).Error; err == nil {
		return nil, errors.New("username or email already exists")
	}

	// Hash password
	hashedPassword, err := utils.HashPassword(req.Password)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	// Create user
	user := models.User{
		TenantModel:  models.TenantModel{TenantID: tenantID},
		Username:     req.Username,
		Email:        req.Email,
		FirstName:    req.FirstName,
		LastName:     req.LastName,
		Phone:        req.Phone,
		PasswordHash: hashedPassword,
		Role:         req.Role,
		IsActive:     req.IsActive,
	}

	if err := s.db.Create(&user).Error; err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	return &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}, nil
}

// UpdateUser updates user information
func (s *UserService) UpdateUser(ctx context.Context, userID, tenantID uuid.UUID, req UpdateUserRequest) (*UserResponse, error) {
	var user models.User
	
	err := s.db.Where("id = ? AND tenant_id = ?", userID, tenantID).First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to find user: %w", err)
	}

	// Update fields if provided
	updates := make(map[string]interface{})
	
	if req.FirstName != nil {
		updates["first_name"] = *req.FirstName
		user.FirstName = *req.FirstName
	}
	if req.LastName != nil {
		updates["last_name"] = *req.LastName
		user.LastName = *req.LastName
	}
	if req.Phone != nil {
		updates["phone"] = *req.Phone
		user.Phone = *req.Phone
	}
	if req.ProfileImage != nil {
		updates["profile_image"] = *req.ProfileImage
		user.ProfileImage = *req.ProfileImage
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
		user.IsActive = *req.IsActive
	}

	if len(updates) > 0 {
		if err := s.db.Model(&user).Updates(updates).Error; err != nil {
			return nil, fmt.Errorf("failed to update user: %w", err)
		}

		// Invalidate cache if user becomes inactive
		if req.IsActive != nil && !*req.IsActive {
			sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
			s.cache.Delete(ctx, sessionKey)
		}
	}

	return &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}, nil
}

// ChangePassword changes user password
func (s *UserService) ChangePassword(ctx context.Context, userID, tenantID uuid.UUID, req ChangePasswordRequest) error {
	var user models.User
	
	err := s.db.Where("id = ? AND tenant_id = ?", userID, tenantID).First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("user not found")
		}
		return fmt.Errorf("failed to find user: %w", err)
	}

	// Verify current password
	if !utils.CheckPassword(req.CurrentPassword, user.PasswordHash) {
		return errors.New("current password is incorrect")
	}

	// Hash new password
	hashedPassword, err := utils.HashPassword(req.NewPassword)
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	// Update password
	if err := s.db.Model(&user).Update("password_hash", hashedPassword).Error; err != nil {
		return fmt.Errorf("failed to update password: %w", err)
	}

	// Invalidate all sessions for this user (force re-login)
	sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
	s.cache.Delete(ctx, sessionKey)

	return nil
}

// DeleteUser soft deletes a user
func (s *UserService) DeleteUser(ctx context.Context, userID, tenantID uuid.UUID) error {
	var user models.User
	
	err := s.db.Where("id = ? AND tenant_id = ?", userID, tenantID).First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("user not found")
		}
		return fmt.Errorf("failed to find user: %w", err)
	}

	// Prevent deleting admin users if they're the last admin
	if user.Role == models.RoleAdmin {
		var adminCount int64
		s.db.Model(&models.User{}).
			Where("tenant_id = ? AND role = ? AND is_active = ?", tenantID, models.RoleAdmin, true).
			Count(&adminCount)
		
		if adminCount <= 1 {
			return errors.New("cannot delete the last active admin user")
		}
	}

	// Soft delete user
	if err := s.db.Delete(&user).Error; err != nil {
		return fmt.Errorf("failed to delete user: %w", err)
	}

	// Invalidate user session
	sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
	s.cache.Delete(ctx, sessionKey)

	return nil
}

// GetUsersByRole returns users by role
func (s *UserService) GetUsersByRole(ctx context.Context, tenantID uuid.UUID, role string) ([]*UserResponse, error) {
	var users []models.User
	
	err := s.db.Where("tenant_id = ? AND role = ? AND is_active = ?", tenantID, role, true).
		Order("first_name, last_name").
		Find(&users).Error
	
	if err != nil {
		return nil, fmt.Errorf("failed to get users by role: %w", err)
	}

	userResponses := make([]*UserResponse, len(users))
	for i, user := range users {
		userResponses[i] = &UserResponse{
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

	return userResponses, nil
}

// ActivateUser activates a user account
func (s *UserService) ActivateUser(ctx context.Context, userID, tenantID uuid.UUID) error {
	return s.db.Model(&models.User{}).
		Where("id = ? AND tenant_id = ?", userID, tenantID).
		Update("is_active", true).Error
}

// DeactivateUser deactivates a user account
func (s *UserService) DeactivateUser(ctx context.Context, userID, tenantID uuid.UUID) error {
	// Update user
	err := s.db.Model(&models.User{}).
		Where("id = ? AND tenant_id = ?", userID, tenantID).
		Update("is_active", false).Error
	
	if err != nil {
		return err
	}

	// Invalidate user session
	sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
	s.cache.Delete(ctx, sessionKey)

	return nil
}