package services

import (
	"context"
	"errors"
	"fmt"
	"log"

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
	Username  string     `json:"username" binding:"required,min=3,max=50"`
	Email     string     `json:"email" binding:"omitempty,email"` // Optional, but must be valid email format if provided
	Password  string     `json:"password" binding:"required,min=8"`
	FirstName string     `json:"first_name" binding:"required"`
	LastName  string     `json:"last_name" binding:"required"`
	Phone     string     `json:"phone"`
	Role      string     `json:"role" binding:"required"`
	IsActive  bool       `json:"is_active"`
	ShopID    *uuid.UUID `json:"shop_id"`
}

// UpdateUserRequest represents user update request
type UpdateUserRequest struct {
	FirstName    *string    `json:"first_name"`
	LastName     *string    `json:"last_name"`
	Phone        *string    `json:"phone"`
	ProfileImage *string    `json:"profile_image"`
	IsActive     *bool      `json:"is_active"`
	Role         *string    `json:"role"`
	ShopID       *uuid.UUID `json:"shop_id"`
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
func (s *UserService) GetUsers(ctx context.Context, tenantID uuid.UUID, page, pageSize int, roleFilter []string) (*UserListResponse, error) {
	var users []models.User
	var totalCount int64

	offset := (page - 1) * pageSize

	// Build query with optional role filter
	query := s.db.Model(&models.User{}).Where("tenant_id = ?", tenantID)
	if len(roleFilter) > 0 {
		query = query.Where("role IN ?", roleFilter)
	}

	// Count total users
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count users: %w", err)
	}

	// Get users with pagination
	dataQuery := s.db.Where("tenant_id = ?", tenantID)
	if len(roleFilter) > 0 {
		dataQuery = dataQuery.Where("role IN ?", roleFilter)
	}
	if err := dataQuery.Preload("Salesman.Shop").
		Offset(offset).
		Limit(pageSize).
		Order("created_at DESC").
		Find(&users).Error; err != nil {
		return nil, fmt.Errorf("failed to get users: %w", err)
	}

	// Convert to response format
	userResponses := make([]*UserResponse, len(users))
	for i, user := range users {
		response := &UserResponse{
			ID:           user.ID,
			Username:     user.Username,
			Email:        user.Email,
			FirstName:    user.FirstName,
			LastName:     user.LastName,
			Phone:        user.Phone,
			Role:         user.Role,
			IsActive:     user.IsActive,
			ProfileImage: user.ProfileImage,
		}

		if user.Salesman != nil {
			response.ShopID = &user.Salesman.ShopID
			if user.Salesman.Shop != nil {
				response.ShopName = user.Salesman.Shop.Name
			}
		}

		userResponses[i] = response
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
		Preload("Salesman.Shop").
		First(&user).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	response := &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Phone:        user.Phone,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}

	if user.Salesman != nil {
		response.ShopID = &user.Salesman.ShopID
		if user.Salesman.Shop != nil {
			response.ShopName = user.Salesman.Shop.Name
		}
	}

	return response, nil
}

// CreateUser creates a new user
func (s *UserService) CreateUser(ctx context.Context, req CreateUserRequest, tenantID uuid.UUID) (*UserResponse, error) {
	// Check if username already exists
	var existingUser models.User
	if err := s.db.Where("username = ? AND tenant_id = ?", req.Username, tenantID).First(&existingUser).Error; err == nil {
		return nil, errors.New("username already exists")
	}

	// If email is provided, check if it already exists
	if req.Email != "" {
		if err := s.db.Where("email = ? AND tenant_id = ?", req.Email, tenantID).First(&existingUser).Error; err == nil {
			return nil, errors.New("email already exists")
		}
	}

	// Check if phone already exists (GLOBAL - across all tenants)
	// Phone numbers must be unique across the entire system for OTP-based login
	if req.Phone != "" {
		var existingUserByPhone models.User
		if err := s.db.Where("phone = ?", req.Phone).First(&existingUserByPhone).Error; err == nil {
			return nil, errors.New("phone number already registered")
		}
	}

	// Hash password
	hashedPassword, err := utils.HashPassword(req.Password)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	// Create user
	user := models.User{
		TenantID:     &tenantID,
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

	// Handle shop assignment - create Salesman record if shop_id is provided
	response := &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Phone:        user.Phone,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}

	if req.ShopID != nil && *req.ShopID != uuid.Nil {
		log.Printf("[CreateUser] Creating Salesman record for user %s with shop %s", user.ID, *req.ShopID)
		salesman := &models.Salesman{
			UserID:   user.ID,
			ShopID:   *req.ShopID,
			Name:     user.FirstName + " " + user.LastName,
			Phone:    user.Phone,
			IsActive: user.IsActive,
		}
		salesman.TenantID = &tenantID

		if err := s.db.Create(salesman).Error; err != nil {
			log.Printf("[CreateUser] Warning: failed to create salesman record: %v", err)
			// Don't fail the user creation, just log the warning
		} else {
			response.ShopID = &salesman.ShopID
			// Load the shop name
			var shop models.Shop
			if err := s.db.Where("id = ?", *req.ShopID).First(&shop).Error; err == nil {
				response.ShopName = shop.Name
			}
		}
	}

	return response, nil
}

// UpdateUser updates user information
func (s *UserService) UpdateUser(ctx context.Context, userID, tenantID uuid.UUID, req UpdateUserRequest) (*UserResponse, error) {
	var user models.User

	err := s.db.Where("id = ? AND tenant_id = ?", userID, tenantID).
		Preload("Salesman.Shop").
		First(&user).Error
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
	if req.Role != nil {
		updates["role"] = *req.Role
		user.Role = *req.Role
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

	// Handle shop assignment via Salesman record
	if req.ShopID != nil {
		if *req.ShopID == uuid.Nil {
			// Remove shop assignment - delete Salesman record if exists
			if user.Salesman != nil {
				if err := s.db.Delete(&models.Salesman{}, "user_id = ?", userID).Error; err != nil {
					return nil, fmt.Errorf("failed to remove shop assignment: %w", err)
				}
				user.Salesman = nil
			}
		} else {
			// Assign or update shop
			if user.Salesman != nil {
				// Update existing Salesman record
				if err := s.db.Model(&models.Salesman{}).Where("user_id = ?", userID).
					Update("shop_id", *req.ShopID).Error; err != nil {
					return nil, fmt.Errorf("failed to update shop assignment: %w", err)
				}
				user.Salesman.ShopID = *req.ShopID
			} else {
				// Create new Salesman record
				salesman := &models.Salesman{
					UserID:   userID,
					ShopID:   *req.ShopID,
					Name:     user.FirstName + " " + user.LastName,
					Phone:    user.Phone,
					IsActive: user.IsActive,
				}
				salesman.TenantID = &tenantID
				if err := s.db.Create(salesman).Error; err != nil {
					return nil, fmt.Errorf("failed to create shop assignment: %w", err)
				}
				user.Salesman = salesman
			}

			// Reload the shop data
			var shop models.Shop
			if err := s.db.Where("id = ?", *req.ShopID).First(&shop).Error; err == nil {
				user.Salesman.Shop = &shop
			}
		}
	}

	response := &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Phone:        user.Phone,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
	}

	if user.Salesman != nil {
		response.ShopID = &user.Salesman.ShopID
		if user.Salesman.Shop != nil {
			response.ShopName = user.Salesman.Shop.Name
		}
	}

	return response, nil
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

// SaaS Admin Methods

// GetAllUsersAcrossTenants returns all users across all tenants (SaaS Admin only)
func (s *UserService) GetAllUsersAcrossTenants(ctx context.Context) ([]*UserResponse, error) {
	var users []models.User

	err := s.db.Preload("Tenant").Order("created_at DESC").Find(&users).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get all users: %w", err)
	}

	// Convert to response format
	userResponses := make([]*UserResponse, len(users))
	for i, user := range users {
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
		} else {
			// This is a Super User (SaaS Admin)
			response.TenantName = "System Admin"
		}

		userResponses[i] = response
	}

	return userResponses, nil
}
