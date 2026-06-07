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
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	firebaseauth "github.com/liquorpro/go-backend/pkg/shared/firebase"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// PhoneConflictError is returned when a phone number is already registered to an active user
type PhoneConflictError struct {
	Message      string `json:"message"`
	ExistingUser struct {
		ID        uuid.UUID `json:"id"`
		FirstName string    `json:"first_name"`
		LastName  string    `json:"last_name"`
		Role      string    `json:"role"`
	} `json:"existing_user"`
}

func (e *PhoneConflictError) Error() string { return e.Message }

// normalizePhone ensures phone numbers are stored with +91 prefix
func normalizePhone(phone string) string {
	normalized := strings.ReplaceAll(phone, " ", "")
	normalized = strings.ReplaceAll(normalized, "-", "")
	normalized = strings.ReplaceAll(normalized, "(", "")
	normalized = strings.ReplaceAll(normalized, ")", "")
	if len(normalized) == 10 && !strings.HasPrefix(normalized, "+") {
		normalized = "+91" + normalized
	} else if strings.HasPrefix(normalized, "91") && len(normalized) == 12 {
		normalized = "+" + normalized
	}
	return normalized
}

// UserService handles user management operations
type UserService struct {
	db               *database.DB
	cache            *cache.Cache
	smsService       SMSServiceInterface
	firebaseVerifier *firebaseauth.AuthVerifier
}

// NewUserService creates a new user service
func NewUserService(db *database.DB, cache *cache.Cache, smsService SMSServiceInterface, firebaseVerifier *firebaseauth.AuthVerifier) *UserService {
	return &UserService{
		db:               db,
		cache:            cache,
		smsService:       smsService,
		firebaseVerifier: firebaseVerifier,
	}
}

// CreateUserRequest represents user creation request
type CreateUserRequest struct {
	Username         string      `json:"username" binding:"omitempty,min=3,max=50"`  // Optional - auto-generated if empty
	Email            string      `json:"email" binding:"omitempty,email"`
	Password         string      `json:"password" binding:"omitempty,min=8"`        // Optional - auto-generated if empty
	FirstName        string      `json:"first_name" binding:"required"`
	LastName         string      `json:"last_name" binding:"required"`
	Phone            string      `json:"phone"`
	Role             string      `json:"role" binding:"required"`
	IsActive         bool        `json:"is_active"`
	Salary           *float64    `json:"salary"`                  // Optional salary for all roles
	Duty             string      `json:"duty"`                    // Optional duty assignment
	ShopID           *uuid.UUID  `json:"shop_id"`                 // Required for salesman role
	ShopIDs          []uuid.UUID `json:"shop_ids"`                // Required for executive role (≥1)
	CertificateImage *string     `json:"certificate_image"`       // Optional certificate for salesman
	TransferOTP            string `json:"transfer_otp"`              // OTP for phone transfer verification (legacy Dr. Dangs flow)
	TransferSessionID      string `json:"transfer_session_id"`      // Session ID from phone transfer OTP (legacy)
	FirebaseTransferToken  string `json:"firebase_transfer_token"`  // Firebase ID token for phone transfer verification
}

// UpdateUserRequest represents user update request
type UpdateUserRequest struct {
	FirstName    *string     `json:"first_name"`
	LastName     *string     `json:"last_name"`
	Email        *string     `json:"email"`
	Phone        *string     `json:"phone"`
	Role         *string     `json:"role"`
	Duty         *string     `json:"duty"`
	ProfileImage *string     `json:"profile_image"`
	IsActive     *bool       `json:"is_active"`
	ShopID       *uuid.UUID  `json:"shop_id"`
	// ShopIDs replaces an executive's shop assignments. Pointer + slice so
	// callers can distinguish "do not change" (nil) from "clear all" (empty).
	ShopIDs      *[]uuid.UUID `json:"shop_ids"`
	Salary       *float64    `json:"salary"`
	Password     *string     `json:"password"`
	TagLine      *string     `json:"tag_line"`
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
		Preload("Salesman.Shop").
		Preload("ExecutiveShops").
		Offset(offset).
		Limit(pageSize).
		Order("created_at DESC").
		Find(&users).Error; err != nil {
		return nil, fmt.Errorf("failed to get users: %w", err)
	}

	// Convert to response format
	userResponses := make([]*UserResponse, len(users))
	for i, user := range users {
		resp := &UserResponse{
			ID:           user.ID,
			Username:     user.Username,
			Email:        user.Email,
			FirstName:    user.FirstName,
			LastName:     user.LastName,
			Role:         user.Role,
			IsActive:     user.IsActive,
			ProfileImage: user.ProfileImage,
			Salary:       user.Salary,
			Duty:         user.Duty,
			TagLine:      user.TagLine,
			Phone:        user.Phone,
		}

		// Populate shop info from Salesman relationship
		if user.Salesman != nil {
			resp.ShopID = &user.Salesman.ShopID
			if user.Salesman.Shop != nil {
				resp.ShopName = &user.Salesman.Shop.Name
			}
		}

		// Populate executive shop IDs
		if user.Role == models.RoleExecutive && len(user.ExecutiveShops) > 0 {
			ids := make([]uuid.UUID, len(user.ExecutiveShops))
			for j, es := range user.ExecutiveShops {
				ids[j] = es.ShopID
			}
			resp.ShopIDs = ids
		}

		userResponses[i] = resp
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
		Preload("Salesman.Shop").
		Preload("ExecutiveShops").
		First(&user).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	resp := &UserResponse{
		ID:           user.ID,
		Username:     user.Username,
		Email:        user.Email,
		FirstName:    user.FirstName,
		LastName:     user.LastName,
		Role:         user.Role,
		IsActive:     user.IsActive,
		ProfileImage: user.ProfileImage,
		Salary:       user.Salary,
		Duty:         user.Duty,
		TagLine:      user.TagLine,
		Phone:        user.Phone,
	}
	if user.Salesman != nil {
		resp.ShopID = &user.Salesman.ShopID
		if user.Salesman.Shop != nil {
			resp.ShopName = &user.Salesman.Shop.Name
		}
	}
	if user.Role == models.RoleExecutive && len(user.ExecutiveShops) > 0 {
		ids := make([]uuid.UUID, len(user.ExecutiveShops))
		for i, es := range user.ExecutiveShops {
			ids[i] = es.ShopID
		}
		resp.ShopIDs = ids
	}
	return resp, nil
}

// CreateUser creates a new user
func (s *UserService) CreateUser(ctx context.Context, req CreateUserRequest, tenantID uuid.UUID) (*UserResponse, error) {
	// Validate salesman-specific requirements
	if req.Role == "salesman" && req.ShopID == nil {
		return nil, errors.New("shop_id is required for salesman role")
	}
	// Executive must be assigned to at least one shop.
	if req.Role == models.RoleExecutive && len(req.ShopIDs) == 0 {
		return nil, errors.New("shop_ids is required for executive role")
	}

	// Check if username already exists (including soft-deleted records, since DB unique constraint covers all)
	var existingUser models.User
	if err := s.db.Unscoped().Where("username = ? AND tenant_id = ?", req.Username, tenantID).First(&existingUser).Error; err == nil {
		if existingUser.DeletedAt.Valid {
			// Soft-deleted user with same username — free up the username by renaming the old record
			s.db.Unscoped().Model(&existingUser).Update("username", fmt.Sprintf("%s_deleted_%d", existingUser.Username, time.Now().Unix()))
		} else {
			return nil, errors.New("username already taken - please choose another")
		}
	}

	// Check if email already exists (only if provided) — include soft-deleted
	if req.Email != "" {
		if err := s.db.Unscoped().Where("email = ? AND tenant_id = ?", req.Email, tenantID).First(&existingUser).Error; err == nil {
			if existingUser.DeletedAt.Valid {
				s.db.Unscoped().Model(&existingUser).Update("email", fmt.Sprintf("%s_deleted_%d", existingUser.Email, time.Now().Unix()))
			} else {
				return nil, errors.New("email address already registered - please use a different email")
			}
		}
	}

	// Normalize phone number
	if req.Phone != "" {
		req.Phone = normalizePhone(req.Phone)
	}

	// Check if phone already exists globally (if provided) — DB constraint uq_users_phone is global
	if req.Phone != "" {
		if err := s.db.Unscoped().Where("phone = ?", req.Phone).First(&existingUser).Error; err == nil {
			if existingUser.DeletedAt.Valid {
				s.db.Unscoped().Model(&existingUser).Update("phone", fmt.Sprintf("%s_deleted_%d", existingUser.Phone, time.Now().Unix()))
			} else if req.FirebaseTransferToken != "" {
				// Admin verified phone ownership via Firebase Phone Auth
				if s.firebaseVerifier == nil {
					return nil, errors.New("firebase authentication is not configured")
				}
				verifiedPhone, _, err := s.firebaseVerifier.VerifyIDToken(ctx, req.FirebaseTransferToken)
				if err != nil {
					return nil, fmt.Errorf("firebase transfer token verification failed: %w", err)
				}
				if normalizePhone(verifiedPhone) != req.Phone {
					return nil, errors.New("firebase verified phone does not match the requested phone number")
				}
				// Firebase verified — detach phone from old user and deactivate
				transferredPhone := fmt.Sprintf("xfr_%s", uuid.New().String()[:8])
				if err := s.db.Model(&existingUser).Updates(map[string]interface{}{
					"phone":     transferredPhone,
					"is_active": false,
				}).Error; err != nil {
					return nil, fmt.Errorf("failed to detach phone from existing user: %w", err)
				}
				s.db.Model(&models.Salesman{}).Where("user_id = ?", existingUser.ID).
					Update("phone", transferredPhone)
				log.Printf("📱 [TRANSFER-FIREBASE] Phone %s transferred from user %s to new user (old user deactivated)", req.Phone, existingUser.ID)
			} else if req.TransferOTP != "" {
				// Legacy: Admin provided OTP to transfer the phone number — verify it
				if err := s.verifyPhoneTransferOTP(ctx, req.Phone, req.TransferOTP, req.TransferSessionID); err != nil {
					return nil, err
				}
				// OTP verified — detach phone from old user and deactivate
				// Use short format to fit varchar(20): "xfr_" + 8 hex chars from UUID
				transferredPhone := fmt.Sprintf("xfr_%s", uuid.New().String()[:8])
				if err := s.db.Model(&existingUser).Updates(map[string]interface{}{
					"phone":     transferredPhone,
					"is_active": false,
				}).Error; err != nil {
					return nil, fmt.Errorf("failed to detach phone from existing user: %w", err)
				}
				// Also update salesman record if exists
				s.db.Model(&models.Salesman{}).Where("user_id = ?", existingUser.ID).
					Update("phone", transferredPhone)
				log.Printf("📱 [TRANSFER] Phone %s transferred from user %s to new user (old user deactivated)", req.Phone, existingUser.ID)
			} else {
				// No OTP provided — return conflict error with existing user info
				conflictErr := &PhoneConflictError{
					Message: "phone number already registered to another user",
				}
				conflictErr.ExistingUser.ID = existingUser.ID
				conflictErr.ExistingUser.FirstName = existingUser.FirstName
				conflictErr.ExistingUser.LastName = existingUser.LastName
				conflictErr.ExistingUser.Role = existingUser.Role
				return nil, conflictErr
			}
		}
	}

	// Hash password
	hashedPassword, err := utils.HashPassword(req.Password)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	// Use transaction to create user and salesman record atomically
	var user models.User
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Create user
		user = models.User{
			TenantID:     &tenantID,
			Username:     req.Username,
			Email:        req.Email,
			FirstName:    req.FirstName,
			LastName:     req.LastName,
			Phone:        req.Phone,
			PasswordHash: hashedPassword,
			Role:         req.Role,
			IsActive:     req.IsActive,
			Salary:       req.Salary,
			Duty:         req.Duty,
		}

		if err := tx.Create(&user).Error; err != nil {
			return fmt.Errorf("failed to create user: %w", err)
		}

		// If role is salesman, create salesman record
		if req.Role == "salesman" && req.ShopID != nil {
			// Verify shop exists and belongs to tenant
			var shop models.Shop
			if err := tx.Where("id = ? AND tenant_id = ?", *req.ShopID, tenantID).First(&shop).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return errors.New("shop not found or does not belong to your tenant")
				}
				return fmt.Errorf("failed to verify shop: %w", err)
			}

			// Create salesman record with unique employee_id
			salesman := models.Salesman{
				TenantModel: models.TenantModel{
					TenantID: &tenantID,
				},
				UserID:           user.ID,
				ShopID:           *req.ShopID,
				EmployeeID:       utils.GenerateEmployeeID(), // FIXED: Generate unique employee ID
				Name:             fmt.Sprintf("%s %s", req.FirstName, req.LastName),
				Phone:            req.Phone,
				CertificateImage: getStringValue(req.CertificateImage),
				JoinDate:         time.Now(), // FIXED: Add join date
				IsActive:         req.IsActive,
			}

			if err := tx.Create(&salesman).Error; err != nil {
				return fmt.Errorf("failed to create salesman record: %w", err)
			}
		}

		// Executive: replace executive_shops rows inside the same transaction
		// so user creation + shop mapping commit atomically.
		if req.Role == models.RoleExecutive {
			if err := replaceExecutiveShopsTx(tx, user.ID, tenantID, req.ShopIDs); err != nil {
				return err
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
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
		Salary:       user.Salary,
		Duty:         user.Duty,
			TagLine:      user.TagLine,
	}, nil
}

// Helper function to safely dereference string pointer
func getStringValue(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// replaceExecutiveShopsTx replaces an executive's shop assignments within an
// open transaction. All shopIDs must belong to tenantID; an empty slice clears
// every assignment. Used by CreateUser and UpdateUser so user + shop mapping
// commit atomically.
func replaceExecutiveShopsTx(tx *gorm.DB, userID, tenantID uuid.UUID, shopIDs []uuid.UUID) error {
	if len(shopIDs) > 0 {
		var count int64
		if err := tx.Model(&models.Shop{}).
			Where("id IN ? AND tenant_id = ?", shopIDs, tenantID).
			Count(&count).Error; err != nil {
			return fmt.Errorf("failed to validate shops: %w", err)
		}
		if int(count) != len(shopIDs) {
			return errors.New("one or more shops do not belong to this tenant")
		}
	}

	if err := tx.Unscoped().
		Where("user_id = ? AND tenant_id = ?", userID, tenantID).
		Delete(&models.ExecutiveShop{}).Error; err != nil {
		return fmt.Errorf("failed to clear executive shops: %w", err)
	}
	if len(shopIDs) == 0 {
		return nil
	}
	rows := make([]models.ExecutiveShop, len(shopIDs))
	tid := tenantID
	for i, sid := range shopIDs {
		rows[i] = models.ExecutiveShop{
			TenantModel: models.TenantModel{TenantID: &tid},
			UserID:      userID,
			ShopID:      sid,
		}
	}
	if err := tx.Create(&rows).Error; err != nil {
		return fmt.Errorf("failed to insert executive shops: %w", err)
	}
	return nil
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

	originalRole := user.Role

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
		phone := normalizePhone(*req.Phone)
		updates["phone"] = phone
		user.Phone = phone
	}
	if req.Email != nil {
		updates["email"] = *req.Email
		user.Email = *req.Email
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
	if req.Salary != nil {
		updates["salary"] = *req.Salary
		user.Salary = req.Salary
	}
	if req.Duty != nil {
		updates["duty"] = *req.Duty
		user.Duty = *req.Duty
	}
	if req.TagLine != nil {
		updates["tag_line"] = *req.TagLine
		user.TagLine = *req.TagLine
	}
	if req.Password != nil && *req.Password != "" {
		hashedPassword, hashErr := utils.HashPassword(*req.Password)
		if hashErr != nil {
			return nil, fmt.Errorf("failed to hash password: %w", hashErr)
		}
		updates["password_hash"] = hashedPassword
		user.PasswordHash = hashedPassword
	}

	if len(updates) > 0 {
		if err := s.db.Model(&user).Updates(updates).Error; err != nil {
			return nil, fmt.Errorf("failed to update user: %w", err)
		}

		// Invalidate cache if user becomes inactive or role changed
		if (req.IsActive != nil && !*req.IsActive) || req.Role != nil {
			sessionKey := fmt.Sprintf(cache.UserSessionKey, userID.String())
			s.cache.Delete(ctx, sessionKey)
		}
	}

	effectiveRole := user.Role
	if req.Role != nil {
		effectiveRole = *req.Role
	}

	// Update shop assignment if provided — create salesman record if needed
	if req.ShopID != nil && effectiveRole == models.RoleSalesman {
		var salesman models.Salesman
		if err := s.db.Where("user_id = ? AND tenant_id = ?", userID, tenantID).First(&salesman).Error; err == nil {
			// Update existing salesman record
			s.db.Model(&salesman).Updates(map[string]interface{}{
				"shop_id": *req.ShopID,
				"name":    user.FirstName + " " + user.LastName,
				"phone":   user.Phone,
			})
			log.Printf("Updated salesman shop assignment: user=%s shop=%s", userID, req.ShopID)
		} else {
			// Create new salesman record
			newSalesman := models.Salesman{
				TenantModel: models.TenantModel{TenantID: &tenantID},
				UserID:      userID,
				ShopID:      *req.ShopID,
				Name:        user.FirstName + " " + user.LastName,
				Phone:       user.Phone,
				IsActive:    true,
			}
			if err := s.db.Create(&newSalesman).Error; err != nil {
				log.Printf("Warning: Failed to create salesman record: %v", err)
			} else {
				log.Printf("Created salesman record: user=%s shop=%s", userID, req.ShopID)
			}
		}
	}

	// Executive multi-shop assignment. ShopIDs is a *[]uuid.UUID so callers
	// can omit it (no change) or send an empty slice (clear all). For
	// consistency with CreateUser, an empty slice on an active executive is
	// rejected — admins should change role first if the user no longer
	// operates any shop.
	if effectiveRole == models.RoleExecutive && req.ShopIDs != nil {
		if len(*req.ShopIDs) == 0 {
			return nil, errors.New("executive must be assigned to at least one shop")
		}
		err := s.db.Transaction(func(tx *gorm.DB) error {
			return replaceExecutiveShopsTx(tx, userID, tenantID, *req.ShopIDs)
		})
		if err != nil {
			return nil, err
		}
		log.Printf("Updated executive shops: user=%s count=%d", userID, len(*req.ShopIDs))
	}

	// Role transitioned away from executive — clean up stale assignments so
	// the user doesn't keep ghost shops if they later return to the role.
	if req.Role != nil && originalRole == models.RoleExecutive && effectiveRole != models.RoleExecutive {
		if delErr := s.db.Unscoped().
			Where("user_id = ? AND tenant_id = ?", userID, tenantID).
			Delete(&models.ExecutiveShop{}).Error; delErr != nil {
			log.Printf("Warning: failed to clear executive_shops for user %s on role change: %v", userID, delErr)
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
		Salary:       user.Salary,
		Duty:         user.Duty,
			TagLine:      user.TagLine,
		Phone:        user.Phone,
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

// PhoneCheckResult holds phone availability check result
type PhoneCheckResult struct {
	Available       bool
	ExistsInTenant  bool   // true if phone exists in caller's tenant
	ExistsGlobally  bool   // true if phone exists in another tenant (transfer needed)
	ExistingName    string // existing user's name (for UI display)
	ExistingRole    string // existing user's role
	ExistingTenant  string // existing user's tenant name
}

// ValidatePhoneAvailability checks if phone number is available for use
// Returns detailed info: available, exists in same tenant, or exists in other tenant (needs transfer)
func (s *UserService) ValidatePhoneAvailability(ctx context.Context, phone string, tenantID uuid.UUID) (*PhoneCheckResult, error) {
	result := &PhoneCheckResult{Available: true}

	// Check globally
	var user models.User
	err := s.db.Where("phone = ?", phone).Preload("Tenant").First(&user).Error

	if errors.Is(err, gorm.ErrRecordNotFound) {
		return result, nil // truly available
	}
	if err != nil {
		return nil, err
	}

	// Phone exists somewhere
	result.Available = false
	result.ExistingName = user.FirstName + " " + user.LastName
	result.ExistingRole = user.Role
	if user.Tenant != nil {
		result.ExistingTenant = user.Tenant.Name
	}

	if user.TenantID != nil && *user.TenantID == tenantID {
		result.ExistsInTenant = true
	} else {
		result.ExistsGlobally = true // different tenant — transfer flow needed
	}

	return result, nil
}

// ValidateEmailAvailability checks if email is available for use
func (s *UserService) ValidateEmailAvailability(ctx context.Context, email string, tenantID uuid.UUID) (bool, error) {
	var user models.User
	err := s.db.Where("email = ? AND tenant_id = ?", email, tenantID).First(&user).Error

	if err == nil {
		// Email exists
		return false, nil
	}

	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Email available
		return true, nil
	}

	// Database error
	return false, err
}

// SendPhoneTransferOTP sends an OTP to a phone number for transfer verification
type SendPhoneTransferOTPRequest struct {
	Phone string `json:"phone" binding:"required"`
}

type SendPhoneTransferOTPResponse struct {
	Message   string    `json:"message"`
	SessionID string    `json:"session_id"`
	ExpiresAt time.Time `json:"expires_at"`
}

func (s *UserService) SendPhoneTransferOTP(ctx context.Context, phone string) (*SendPhoneTransferOTPResponse, error) {
	normalized := normalizePhone(phone)
	if normalized == "" {
		return nil, errors.New("invalid phone number")
	}

	// Generate OTP
	otp := s.generateOTP()
	sessionID := s.generateSessionID()
	hashedOTP := s.hashOTP(otp)

	// Store in Redis with 10-minute expiry
	otpKey := fmt.Sprintf("otp_transfer:%s", normalized)
	otpData := map[string]interface{}{
		"hashed_otp": hashedOTP,
		"phone":      normalized,
		"session_id": sessionID,
		"created_at": time.Now().Unix(),
		"attempts":   0,
	}

	expiry := 10 * time.Minute
	if err := s.cache.Set(ctx, otpKey, otpData, expiry); err != nil {
		return nil, fmt.Errorf("failed to store transfer OTP: %w", err)
	}

	// Send via SMS
	if os.Getenv("APP_ENVIRONMENT") == "production" && s.smsService != nil {
		var user models.User
		userName := "User"
		if err := s.db.Where("phone = ?", normalized).First(&user).Error; err == nil {
			userName = user.FirstName
		}
		if _, err := s.smsService.SendOTP(phone, userName, otp); err != nil {
			log.Printf("⚠️ SMS sending failed for transfer OTP: %v", err)
		}
	} else {
		fmt.Printf("📱 Transfer OTP for %s: %s (Development Mode)\n", normalized, otp)
	}

	log.Printf("📱 [TRANSFER OTP] Generated transfer OTP for %s | OTP: %s", normalized, otp)

	return &SendPhoneTransferOTPResponse{
		Message:   fmt.Sprintf("OTP sent to %s for phone transfer verification", phone),
		SessionID: sessionID,
		ExpiresAt: time.Now().Add(expiry),
	}, nil
}

// verifyPhoneTransferOTP checks the transfer OTP from Redis
func (s *UserService) verifyPhoneTransferOTP(ctx context.Context, phone, otp, sessionID string) error {
	normalized := normalizePhone(phone)
	otpKey := fmt.Sprintf("otp_transfer:%s", normalized)

	var otpData map[string]interface{}
	if err := s.cache.Get(ctx, otpKey, &otpData); err != nil {
		return errors.New("transfer OTP expired or not found - please request a new OTP")
	}

	// Verify session ID
	storedSessionID, _ := otpData["session_id"].(string)
	if sessionID != "" && storedSessionID != sessionID {
		return errors.New("invalid session - please request a new OTP")
	}

	// Check attempts
	attempts, _ := otpData["attempts"].(float64)
	if int(attempts) >= 3 {
		s.cache.Delete(ctx, otpKey)
		return errors.New("too many failed attempts - please request a new OTP")
	}

	// Verify OTP hash
	storedHash, _ := otpData["hashed_otp"].(string)
	if s.hashOTP(otp) != storedHash {
		otpData["attempts"] = int(attempts) + 1
		s.cache.Set(ctx, otpKey, otpData, 10*time.Minute)
		return errors.New("invalid OTP")
	}

	// OTP verified — clean up
	s.cache.Delete(ctx, otpKey)
	return nil
}

// OTP helper methods for UserService

func (s *UserService) generateOTP() string {
	if os.Getenv("APP_ENVIRONMENT") != "production" {
		return "000000"
	}
	max := big.NewInt(999999)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return fmt.Sprintf("%06d", time.Now().Unix()%1000000)
	}
	return fmt.Sprintf("%06d", n.Int64())
}

func (s *UserService) generateSessionID() string {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return uuid.New().String()
	}
	return hex.EncodeToString(bytes)
}

func (s *UserService) hashOTP(otp string) string {
	hash := sha256.Sum256([]byte(otp))
	return hex.EncodeToString(hash[:])
}
