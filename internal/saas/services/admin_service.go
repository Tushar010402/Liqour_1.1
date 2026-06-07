package services

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

type AdminService struct {
	db     *gorm.DB
	config *config.Config
	cache  *cache.Cache
}

func NewAdminService(db *gorm.DB, cfg *config.Config, cache *cache.Cache) *AdminService {
	return &AdminService{
		db:     db,
		config: cfg,
		cache:  cache,
	}
}

func (s *AdminService) GetAllSubscriptions(ctx context.Context, page, limit int, status string) ([]models.Subscription, int64, error) {
	var subscriptions []models.Subscription
	var total int64

	query := s.db.Model(&models.Subscription{})

	// Filter by status if provided
	if status != "" && status != "all" {
		query = query.Where("status = ?", status)
	}

	// Get total count
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count subscriptions: %w", err)
	}

	// Get subscriptions with pagination
	offset := (page - 1) * limit
	err := query.Preload("Plan").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&subscriptions).Error

	if err != nil {
		return nil, 0, fmt.Errorf("failed to get subscriptions: %w", err)
	}

	return subscriptions, total, nil
}

func (s *AdminService) GetSubscriptionDetails(ctx context.Context, subscriptionID uuid.UUID) (*models.Subscription, []models.Payment, []models.UsageRecord, error) {
	var subscription models.Subscription
	var payments []models.Payment
	var usageRecords []models.UsageRecord

	// Get subscription with plan details
	if err := s.db.Preload("Plan").First(&subscription, subscriptionID).Error; err != nil {
		return nil, nil, nil, fmt.Errorf("subscription not found: %w", err)
	}

	// Get recent payments
	if err := s.db.Where("subscription_id = ?", subscriptionID).
		Order("created_at DESC").
		Limit(10).
		Find(&payments).Error; err != nil {
		return nil, nil, nil, fmt.Errorf("failed to get payments: %w", err)
	}

	// Get recent usage records
	if err := s.db.Where("subscription_id = ?", subscriptionID).
		Order("record_date DESC").
		Limit(30). // Last 30 days
		Find(&usageRecords).Error; err != nil {
		return nil, nil, nil, fmt.Errorf("failed to get usage records: %w", err)
	}

	return &subscription, payments, usageRecords, nil
}

func (s *AdminService) UpdateSubscriptionStatus(ctx context.Context, subscriptionID uuid.UUID, status string, adminUserID uuid.UUID, reason string) error {
	// Start transaction
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Get current subscription
	var subscription models.Subscription
	if err := tx.First(&subscription, subscriptionID).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("subscription not found: %w", err)
	}

	oldStatus := subscription.Status
	subscription.Status = status

	// Handle status-specific updates
	switch status {
	case "cancelled":
		now := time.Now()
		subscription.CancelledAt = &now
		subscription.AutoRenew = false
	case "suspended":
		// Keep existing fields
	case "active":
		// Clear cancelled date if reactivating
		subscription.CancelledAt = nil
	}

	// Update subscription
	if err := tx.Save(&subscription).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update subscription: %w", err)
	}

	// Create audit log
	oldValues, _ := json.Marshal(map[string]interface{}{"status": oldStatus})
	newValues, _ := json.Marshal(map[string]interface{}{"status": status, "reason": reason})

	auditLog := models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &adminUserID,
		TenantID:    &subscription.TenantID,
		Action:      "update",
		Resource:    "subscription",
		ResourceID:  subscription.ID.String(),
		OldValues:   string(oldValues),
		NewValues:   string(newValues),
		IPAddress:   "unknown", // TODO: Get from context
		UserAgent:   "admin-panel",
	}

	if err := tx.Create(&auditLog).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to create audit log: %w", err)
	}

	tx.Commit()
	return nil
}

func (s *AdminService) GetAuditLogs(ctx context.Context, page, limit int, resource string, tenantID *uuid.UUID) ([]models.AuditLog, int64, error) {
	var auditLogs []models.AuditLog
	var total int64

	query := s.db.Model(&models.AuditLog{})

	// Filter by resource if provided
	if resource != "" && resource != "all" {
		query = query.Where("resource = ?", resource)
	}

	// Filter by tenant if provided
	if tenantID != nil {
		query = query.Where("tenant_id = ?", *tenantID)
	}

	// Get total count
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count audit logs: %w", err)
	}

	// Get audit logs with pagination
	offset := (page - 1) * limit
	err := query.Preload("AdminUser").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&auditLogs).Error

	if err != nil {
		return nil, 0, fmt.Errorf("failed to get audit logs: %w", err)
	}

	return auditLogs, total, nil
}

func (s *AdminService) GetSystemHealth(ctx context.Context) (*SystemHealth, error) {
	health := &SystemHealth{
		Status:    "healthy",
		Services:  make(map[string]ServiceStatus),
		Timestamp: time.Now(),
	}

	// Check database connection
	sqlDB, err := s.db.DB()
	if err != nil {
		health.Status = "unhealthy"
		health.Services["database"] = ServiceStatus{
			Status: "down",
			Error:  err.Error(),
		}
	} else {
		if err := sqlDB.Ping(); err != nil {
			health.Status = "degraded"
			health.Services["database"] = ServiceStatus{
				Status: "down",
				Error:  err.Error(),
			}
		} else {
			health.Services["database"] = ServiceStatus{
				Status: "up",
			}
		}
	}

	// Check subscription service health
	var activeSubscriptions int64
	if err := s.db.Model(&models.Subscription{}).Where("status = 'active'").Count(&activeSubscriptions).Error; err != nil {
		health.Status = "degraded"
		errMsg := fmt.Sprintf("%v", err)
		health.Services["subscriptions"] = ServiceStatus{
			Status: "degraded",
			Error:  errMsg,
		}
	} else {
		health.Services["subscriptions"] = ServiceStatus{
			Status: "up",
			Metrics: map[string]interface{}{
				"active_subscriptions": activeSubscriptions,
			},
		}
	}

	// Check payment service health
	var recentPayments int64
	if err := s.db.Model(&models.Payment{}).
		Where("created_at > ?", time.Now().Add(-24*time.Hour)).
		Count(&recentPayments).Error; err != nil {
		health.Status = "degraded"
		errMsg := fmt.Sprintf("%v", err)
		health.Services["payments"] = ServiceStatus{
			Status: "degraded",
			Error:  errMsg,
		}
	} else {
		health.Services["payments"] = ServiceStatus{
			Status: "up",
			Metrics: map[string]interface{}{
				"payments_24h": recentPayments,
			},
		}
	}

	return health, nil
}

func (s *AdminService) ToggleMaintenanceMode(ctx context.Context, enabled bool, adminUserID uuid.UUID, message string) error {
	// Create audit log for maintenance mode change
	oldValues, _ := json.Marshal(map[string]interface{}{"maintenance_mode": !enabled})
	newValues, _ := json.Marshal(map[string]interface{}{"maintenance_mode": enabled, "message": message})

	auditLog := models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &adminUserID,
		Action:      "update",
		Resource:    "system",
		ResourceID:  "maintenance_mode",
		OldValues:   string(oldValues),
		NewValues:   string(newValues),
		IPAddress:   "unknown", // TODO: Get from context
		UserAgent:   "admin-panel",
	}

	if err := s.db.Create(&auditLog).Error; err != nil {
		return fmt.Errorf("failed to create audit log: %w", err)
	}

	// TODO: Implement actual maintenance mode logic
	// This could involve setting a flag in Redis or config
	fmt.Printf("Maintenance mode %s: %s\n", map[bool]string{true: "enabled", false: "disabled"}[enabled], message)

	return nil
}

func (s *AdminService) GetTenantUsage(ctx context.Context, tenantID uuid.UUID) (*TenantUsageStats, error) {
	var subscription models.Subscription
	if err := s.db.Preload("Plan").Where("tenant_id = ? AND status IN ?", tenantID, []string{"active", "trial"}).First(&subscription).Error; err != nil {
		return nil, fmt.Errorf("no active subscription found for tenant: %w", err)
	}

	// Get latest usage record
	var usage models.UsageRecord
	if err := s.db.Where("tenant_id = ?", tenantID).Order("record_date DESC").First(&usage).Error; err != nil {
		// Create empty usage record if none exists
		usage = models.UsageRecord{
			TenantID: tenantID,
		}
	}

	// Calculate usage percentages
	var locationUsage, userUsage, productUsage float64

	if subscription.Plan.MaxLocations > 0 {
		locationUsage = float64(usage.Locations) / float64(subscription.Plan.MaxLocations) * 100
	}
	if subscription.Plan.MaxUsers > 0 {
		userUsage = float64(usage.Users) / float64(subscription.Plan.MaxUsers) * 100
	}
	if subscription.Plan.MaxProducts > 0 {
		productUsage = float64(usage.Products) / float64(subscription.Plan.MaxProducts) * 100
	}

	stats := &TenantUsageStats{
		TenantID:      tenantID,
		PlanName:      subscription.Plan.DisplayName,
		Locations:     usage.Locations,
		MaxLocations:  subscription.Plan.MaxLocations,
		LocationUsage: locationUsage,
		Users:         usage.Users,
		MaxUsers:      subscription.Plan.MaxUsers,
		UserUsage:     userUsage,
		Products:      usage.Products,
		MaxProducts:   subscription.Plan.MaxProducts,
		ProductUsage:  productUsage,
		Sales:         usage.Sales,
		APIRequests:   usage.APIRequests,
		StorageUsed:   usage.StorageUsed,
		LastUpdated:   usage.UpdatedAt,
	}

	return stats, nil
}

func (s *AdminService) BulkUpdateSubscriptions(ctx context.Context, subscriptionIDs []uuid.UUID, updates map[string]interface{}, adminUserID uuid.UUID) error {
	// Start transaction
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	for _, subscriptionID := range subscriptionIDs {
		var subscription models.Subscription
		if err := tx.First(&subscription, subscriptionID).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("subscription %s not found: %w", subscriptionID, err)
		}

		// Create audit log before updating
		oldValues, _ := json.Marshal(subscription)
		newValues, _ := json.Marshal(updates)

		auditLog := models.AuditLog{
			ID:          uuid.New(),
			AdminUserID: &adminUserID,
			TenantID:    &subscription.TenantID,
			Action:      "bulk_update",
			Resource:    "subscription",
			ResourceID:  subscription.ID.String(),
			OldValues:   string(oldValues),
			NewValues:   string(newValues),
			IPAddress:   "unknown", // TODO: Get from context
			UserAgent:   "admin-panel",
		}

		if err := tx.Create(&auditLog).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create audit log: %w", err)
		}
	}

	// Perform bulk update
	if err := tx.Model(&models.Subscription{}).Where("id IN ?", subscriptionIDs).Updates(updates).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to bulk update subscriptions: %w", err)
	}

	tx.Commit()
	return nil
}

// Helper structs

type SystemHealth struct {
	Status    string                   `json:"status"`
	Services  map[string]ServiceStatus `json:"services"`
	Timestamp time.Time                `json:"timestamp"`
}

type ServiceStatus struct {
	Status  string                 `json:"status"`
	Error   string                 `json:"error,omitempty"`
	Metrics map[string]interface{} `json:"metrics,omitempty"`
}

type TenantUsageStats struct {
	TenantID      uuid.UUID `json:"tenant_id"`
	PlanName      string    `json:"plan_name"`
	Locations     int       `json:"locations"`
	MaxLocations  int       `json:"max_locations"`
	LocationUsage float64   `json:"location_usage_percent"`
	Users         int       `json:"users"`
	MaxUsers      int       `json:"max_users"`
	UserUsage     float64   `json:"user_usage_percent"`
	Products      int       `json:"products"`
	MaxProducts   int       `json:"max_products"`
	ProductUsage  float64   `json:"product_usage_percent"`
	Sales         int       `json:"sales"`
	APIRequests   int       `json:"api_requests"`
	StorageUsed   int64     `json:"storage_used"`
	LastUpdated   time.Time `json:"last_updated"`
}

// Admin Team Management methods

func (s *AdminService) CreateAdminUser(ctx context.Context, req models.CreateAdminUserRequest, invitedBy uuid.UUID) (*models.AdminUser, error) {
	// Check email uniqueness
	var count int64
	if err := s.db.Model(&models.AdminUser{}).Where("email = ?", req.Email).Count(&count).Error; err != nil {
		return nil, fmt.Errorf("failed to check email uniqueness: %w", err)
	}
	if count > 0 {
		return nil, fmt.Errorf("email already in use")
	}

	// Check mobile uniqueness
	if err := s.db.Model(&models.AdminUser{}).Where("mobile = ?", req.Mobile).Count(&count).Error; err != nil {
		return nil, fmt.Errorf("failed to check mobile uniqueness: %w", err)
	}
	if count > 0 {
		return nil, fmt.Errorf("mobile number already in use")
	}

	department := req.Department
	if department == "" {
		department = "general"
	}

	adminUser := &models.AdminUser{
		ID:          uuid.New(),
		Email:       req.Email,
		Mobile:      req.Mobile,
		FirstName:   req.FirstName,
		LastName:    req.LastName,
		Name:        req.FirstName + " " + req.LastName,
		Role:        req.Role,
		Permissions: req.Permissions,
		Department:  department,
		InvitedBy:   &invitedBy,
		Active:      true,
	}

	tx := s.db.Begin()

	if err := tx.Create(adminUser).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create admin user: %w", err)
	}

	// Audit log
	newValues, _ := json.Marshal(map[string]interface{}{
		"email": req.Email, "role": req.Role, "department": department,
	})
	auditLog := models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &invitedBy,
		Action:      "create",
		Resource:    "admin_user",
		ResourceID:  adminUser.ID.String(),
		NewValues:   string(newValues),
		IPAddress:   "unknown",
		UserAgent:   "admin-panel",
	}
	if err := tx.Create(&auditLog).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create audit log: %w", err)
	}

	tx.Commit()
	return adminUser, nil
}

func (s *AdminService) GetAdminUsers(ctx context.Context, page, limit int, search, role, department string) ([]models.AdminUser, int64, error) {
	var admins []models.AdminUser
	var total int64

	query := s.db.Model(&models.AdminUser{})

	if search != "" {
		searchPattern := "%" + search + "%"
		query = query.Where("name ILIKE ? OR email ILIKE ? OR mobile ILIKE ?", searchPattern, searchPattern, searchPattern)
	}
	if role != "" && role != "all" {
		query = query.Where("role = ?", role)
	}
	if department != "" && department != "all" {
		query = query.Where("department = ?", department)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count admin users: %w", err)
	}

	offset := (page - 1) * limit
	if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&admins).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get admin users: %w", err)
	}

	return admins, total, nil
}

func (s *AdminService) GetAdminUserByID(ctx context.Context, id uuid.UUID) (*models.AdminUser, error) {
	var admin models.AdminUser
	if err := s.db.First(&admin, id).Error; err != nil {
		return nil, fmt.Errorf("admin user not found: %w", err)
	}
	return &admin, nil
}

func (s *AdminService) UpdateAdminUser(ctx context.Context, id uuid.UUID, req models.UpdateAdminUserRequest, updatedBy uuid.UUID) (*models.AdminUser, error) {
	var admin models.AdminUser
	if err := s.db.First(&admin, id).Error; err != nil {
		return nil, fmt.Errorf("admin user not found: %w", err)
	}

	// Prevent self-demotion from super_admin
	if id == updatedBy && req.Role != nil && *req.Role != admin.Role && admin.Role == "super_admin" {
		return nil, fmt.Errorf("cannot demote your own super_admin role")
	}

	oldValues, _ := json.Marshal(map[string]interface{}{
		"role": admin.Role, "active": admin.Active, "department": admin.Department,
	})

	if req.FirstName != nil {
		admin.FirstName = *req.FirstName
	}
	if req.LastName != nil {
		admin.LastName = *req.LastName
	}
	if req.FirstName != nil || req.LastName != nil {
		admin.Name = admin.FirstName + " " + admin.LastName
	}
	if req.Email != nil {
		// Check uniqueness
		var count int64
		s.db.Model(&models.AdminUser{}).Where("email = ? AND id != ?", *req.Email, id).Count(&count)
		if count > 0 {
			return nil, fmt.Errorf("email already in use")
		}
		admin.Email = *req.Email
	}
	if req.Role != nil {
		admin.Role = *req.Role
	}
	if req.Permissions != nil {
		admin.Permissions = req.Permissions
	}
	if req.Department != nil {
		admin.Department = *req.Department
	}
	if req.Active != nil {
		admin.Active = *req.Active
	}
	if req.AvatarURL != nil {
		admin.AvatarURL = *req.AvatarURL
	}

	tx := s.db.Begin()

	if err := tx.Save(&admin).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update admin user: %w", err)
	}

	newValues, _ := json.Marshal(map[string]interface{}{
		"role": admin.Role, "active": admin.Active, "department": admin.Department,
	})
	auditLog := models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &updatedBy,
		Action:      "update",
		Resource:    "admin_user",
		ResourceID:  admin.ID.String(),
		OldValues:   string(oldValues),
		NewValues:   string(newValues),
		IPAddress:   "unknown",
		UserAgent:   "admin-panel",
	}
	tx.Create(&auditLog)
	tx.Commit()

	return &admin, nil
}

func (s *AdminService) DeactivateAdminUser(ctx context.Context, id uuid.UUID, deactivatedBy uuid.UUID) error {
	var admin models.AdminUser
	if err := s.db.First(&admin, id).Error; err != nil {
		return fmt.Errorf("admin user not found: %w", err)
	}

	if id == deactivatedBy {
		return fmt.Errorf("cannot deactivate your own account")
	}

	admin.Active = false
	if err := s.db.Save(&admin).Error; err != nil {
		return fmt.Errorf("failed to deactivate admin user: %w", err)
	}

	// Invalidate session in cache
	sessionKey := fmt.Sprintf(cache.UserSessionKey, id.String())
	s.cache.Delete(ctx, sessionKey)

	// Audit log
	newValues, _ := json.Marshal(map[string]interface{}{"active": false})
	s.db.Create(&models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &deactivatedBy,
		Action:      "deactivate",
		Resource:    "admin_user",
		ResourceID:  admin.ID.String(),
		NewValues:   string(newValues),
	})

	return nil
}

func (s *AdminService) DeleteAdminUser(ctx context.Context, id uuid.UUID, deletedBy uuid.UUID) error {
	if id == deletedBy {
		return fmt.Errorf("cannot delete your own account")
	}

	result := s.db.Delete(&models.AdminUser{}, id)
	if result.Error != nil {
		return fmt.Errorf("failed to delete admin user: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("admin user not found")
	}

	// Invalidate session
	sessionKey := fmt.Sprintf(cache.UserSessionKey, id.String())
	s.cache.Delete(ctx, sessionKey)

	s.db.Create(&models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &deletedBy,
		Action:      "delete",
		Resource:    "admin_user",
		ResourceID:  id.String(),
	})

	return nil
}

func (s *AdminService) InviteAdminUser(ctx context.Context, req models.InviteAdminRequest, invitedBy uuid.UUID) (*models.AdminInvitation, error) {
	// Check if email already exists as admin
	var count int64
	s.db.Model(&models.AdminUser{}).Where("email = ?", req.Email).Count(&count)
	if count > 0 {
		return nil, fmt.Errorf("email already registered as admin user")
	}

	// Check if there's already a pending invitation for this email
	s.db.Model(&models.AdminInvitation{}).Where("email = ? AND status = 'pending' AND expires_at > ?", req.Email, time.Now()).Count(&count)
	if count > 0 {
		return nil, fmt.Errorf("pending invitation already exists for this email")
	}

	// Generate secure token
	token, err := generateSecureToken(32)
	if err != nil {
		return nil, fmt.Errorf("failed to generate invitation token: %w", err)
	}

	department := req.Department
	if department == "" {
		department = "general"
	}

	invitation := &models.AdminInvitation{
		ID:          uuid.New(),
		Email:       req.Email,
		Mobile:      req.Mobile,
		Name:        req.Name,
		Role:        req.Role,
		Permissions: req.Permissions,
		Department:  department,
		InvitedByID: invitedBy,
		Token:       token,
		ExpiresAt:   time.Now().Add(72 * time.Hour), // 3 days
		Status:      "pending",
	}

	if err := s.db.Create(invitation).Error; err != nil {
		return nil, fmt.Errorf("failed to create invitation: %w", err)
	}

	// Audit log
	s.db.Create(&models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &invitedBy,
		Action:      "invite",
		Resource:    "admin_invitation",
		ResourceID:  invitation.ID.String(),
		NewValues:   fmt.Sprintf(`{"email":"%s","role":"%s"}`, req.Email, req.Role),
	})

	return invitation, nil
}

func (s *AdminService) AcceptInvitation(ctx context.Context, token, mobile string) (*models.AdminUser, string, error) {
	var invitation models.AdminInvitation
	if err := s.db.Where("token = ? AND status = 'pending'", token).First(&invitation).Error; err != nil {
		return nil, "", fmt.Errorf("invitation not found or already used")
	}

	if time.Now().After(invitation.ExpiresAt) {
		s.db.Model(&invitation).Update("status", "expired")
		return nil, "", fmt.Errorf("invitation has expired")
	}

	// Create admin user from invitation
	adminUser := &models.AdminUser{
		ID:          uuid.New(),
		Email:       invitation.Email,
		Mobile:      mobile,
		FirstName:   invitation.Name,
		LastName:    "",
		Name:        invitation.Name,
		Role:        invitation.Role,
		Permissions: invitation.Permissions,
		Department:  invitation.Department,
		InvitedBy:   &invitation.InvitedByID,
		Active:      true,
	}

	// Split name if possible
	parts := splitName(invitation.Name)
	adminUser.FirstName = parts[0]
	if len(parts) > 1 {
		adminUser.LastName = parts[1]
	}

	tx := s.db.Begin()

	if err := tx.Create(adminUser).Error; err != nil {
		tx.Rollback()
		return nil, "", fmt.Errorf("failed to create admin user: %w", err)
	}

	// Mark invitation as accepted
	now := time.Now()
	if err := tx.Model(&invitation).Updates(map[string]interface{}{
		"status":      "accepted",
		"accepted_at": &now,
	}).Error; err != nil {
		tx.Rollback()
		return nil, "", fmt.Errorf("failed to update invitation: %w", err)
	}

	tx.Commit()

	// Generate JWT token
	jwtToken, err := s.GenerateAdminToken(ctx, mobile)
	if err != nil {
		return adminUser, "", fmt.Errorf("user created but failed to generate token: %w", err)
	}

	return adminUser, jwtToken, nil
}

func (s *AdminService) RevokeInvitation(ctx context.Context, invitationID uuid.UUID, revokedBy uuid.UUID) error {
	result := s.db.Model(&models.AdminInvitation{}).Where("id = ? AND status = 'pending'", invitationID).Update("status", "revoked")
	if result.Error != nil {
		return fmt.Errorf("failed to revoke invitation: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("invitation not found or not in pending status")
	}

	s.db.Create(&models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &revokedBy,
		Action:      "revoke",
		Resource:    "admin_invitation",
		ResourceID:  invitationID.String(),
	})

	return nil
}

func (s *AdminService) GetPendingInvitations(ctx context.Context, page, limit int) ([]models.AdminInvitation, int64, error) {
	var invitations []models.AdminInvitation
	var total int64

	query := s.db.Model(&models.AdminInvitation{}).Where("status = 'pending' AND expires_at > ?", time.Now())

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count invitations: %w", err)
	}

	offset := (page - 1) * limit
	if err := query.Preload("InvitedBy").Order("created_at DESC").Limit(limit).Offset(offset).Find(&invitations).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get invitations: %w", err)
	}

	return invitations, total, nil
}

func (s *AdminService) LogAdminActivity(ctx context.Context, adminID uuid.UUID, activityType, description, ip, userAgent string, metadata map[string]interface{}) error {
	metadataJSON := ""
	if metadata != nil {
		bytes, _ := json.Marshal(metadata)
		metadataJSON = string(bytes)
	}

	activity := &models.AdminActivityLog{
		ID:           uuid.New(),
		AdminUserID:  adminID,
		ActivityType: activityType,
		Description:  description,
		IPAddress:    ip,
		UserAgent:    userAgent,
		Metadata:     metadataJSON,
	}

	return s.db.Create(activity).Error
}

func (s *AdminService) GetAdminActivity(ctx context.Context, adminID uuid.UUID, page, limit int) ([]models.AdminActivityLog, int64, error) {
	var activities []models.AdminActivityLog
	var total int64

	query := s.db.Model(&models.AdminActivityLog{}).Where("admin_user_id = ?", adminID)

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count activities: %w", err)
	}

	offset := (page - 1) * limit
	if err := query.Order("created_at DESC").Limit(limit).Offset(offset).Find(&activities).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get activities: %w", err)
	}

	return activities, total, nil
}

func (s *AdminService) GetMyProfile(ctx context.Context, adminID uuid.UUID) (*models.AdminUser, error) {
	var admin models.AdminUser
	if err := s.db.First(&admin, adminID).Error; err != nil {
		return nil, fmt.Errorf("admin user not found: %w", err)
	}
	return &admin, nil
}

func (s *AdminService) UpdateMyProfile(ctx context.Context, adminID uuid.UUID, req models.UpdateProfileRequest) (*models.AdminUser, error) {
	var admin models.AdminUser
	if err := s.db.First(&admin, adminID).Error; err != nil {
		return nil, fmt.Errorf("admin user not found: %w", err)
	}

	if req.FirstName != nil {
		admin.FirstName = *req.FirstName
	}
	if req.LastName != nil {
		admin.LastName = *req.LastName
	}
	if req.FirstName != nil || req.LastName != nil {
		admin.Name = admin.FirstName + " " + admin.LastName
	}
	if req.AvatarURL != nil {
		admin.AvatarURL = *req.AvatarURL
	}

	if err := s.db.Save(&admin).Error; err != nil {
		return nil, fmt.Errorf("failed to update profile: %w", err)
	}

	return &admin, nil
}

// Helper functions

func generateSecureToken(length int) (string, error) {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	token := make([]byte, length)
	for i := range token {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return "", err
		}
		token[i] = charset[num.Int64()]
	}
	return string(token), nil
}

func splitName(name string) []string {
	parts := make([]string, 0, 2)
	for i, r := range name {
		if r == ' ' && i > 0 {
			parts = append(parts, name[:i])
			parts = append(parts, name[i+1:])
			return parts
		}
	}
	return []string{name}
}

// SaaS Admin Authentication methods

type OTPRecord struct {
	Mobile    string    `json:"mobile"`
	OTP       string    `json:"otp"`
	ExpiresAt time.Time `json:"expires_at"`
	Attempts  int       `json:"attempts"`
}

// In-memory OTP storage (in production, use Redis)
var otpStore = make(map[string]*OTPRecord)

func (s *AdminService) IsSaaSAdmin(ctx context.Context, mobile string) (bool, error) {
	// Check if mobile number exists in AdminUser table
	var count int64
	err := s.db.Model(&models.AdminUser{}).Where("mobile = ? AND active = true", mobile).Count(&count).Error
	if err != nil {
		return false, fmt.Errorf("failed to check admin status: %w", err)
	}

	return count > 0, nil
}

func (s *AdminService) SendOTP(ctx context.Context, mobile string) error {
	// Generate 6-digit OTP
	otp, err := generateOTP(6)
	if err != nil {
		return fmt.Errorf("failed to generate OTP: %w", err)
	}

	// Store OTP with 5-minute expiration
	otpRecord := &OTPRecord{
		Mobile:    mobile,
		OTP:       otp,
		ExpiresAt: time.Now().Add(5 * time.Minute),
		Attempts:  0,
	}

	otpStore[mobile] = otpRecord

	// In production, send SMS here
	fmt.Printf("OTP for %s: %s (expires in 5 minutes)\n", mobile, otp)

	return nil
}

func (s *AdminService) VerifyOTP(ctx context.Context, mobile, otp string) (bool, error) {
	record, exists := otpStore[mobile]
	if !exists {
		return false, fmt.Errorf("no OTP found for mobile number")
	}

	// Check if OTP is expired
	if time.Now().After(record.ExpiresAt) {
		delete(otpStore, mobile)
		return false, fmt.Errorf("OTP has expired")
	}

	// Check attempts limit
	if record.Attempts >= 3 {
		delete(otpStore, mobile)
		return false, fmt.Errorf("maximum OTP attempts exceeded")
	}

	// Increment attempts
	record.Attempts++

	// Verify OTP
	if record.OTP != otp {
		return false, nil
	}

	// OTP is valid, remove from store
	delete(otpStore, mobile)
	return true, nil
}

func (s *AdminService) GenerateAdminToken(ctx context.Context, mobile string) (string, error) {
	// Find or create admin user
	var adminUser models.AdminUser
	err := s.db.Where("mobile = ?", mobile).First(&adminUser).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			// Auto-create admin user on first login
			adminUser = models.AdminUser{
				ID:          uuid.New(),
				Mobile:      mobile,
				FirstName:   "Admin",
				LastName:    "User",
				Name:        "Admin User",
				Role:        "super_admin",
				Permissions: models.GetDefaultPermissions("super_admin"),
				Active:      true,
			}
			if err := s.db.Create(&adminUser).Error; err != nil {
				return "", fmt.Errorf("failed to create admin user: %w", err)
			}
		} else {
			return "", fmt.Errorf("failed to find admin user: %w", err)
		}
	}

	userID := adminUser.ID.String()

	// Ensure permissions are populated — assign role defaults if empty
	permissions := adminUser.Permissions
	if len(permissions) == 0 {
		permissions = models.GetDefaultPermissions(adminUser.Role)
		adminUser.Permissions = permissions
		s.db.Model(&adminUser).Update("permissions", permissions)
	}

	// Update last login
	now := time.Now()
	s.db.Model(&adminUser).Update("last_login_at", &now)

	// Create JWT claims
	claims := jwt.MapClaims{
		"mobile":      mobile,
		"role":        adminUser.Role,
		"user_id":     userID,
		"permissions": permissions,
		"department":  adminUser.Department,
		"exp":         time.Now().Add(24 * time.Hour).Unix(),
		"iat":         time.Now().Unix(),
		"iss":         "saas-admin-service",
	}

	// Create token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// Sign token with secret
	jwtSecret := s.config.JWT.Secret
	if jwtSecret == "" {
		jwtSecret = "default-secret-key-change-in-production"
	}

	tokenString, err := token.SignedString([]byte(jwtSecret))
	if err != nil {
		return "", fmt.Errorf("failed to sign token: %w", err)
	}

	// Store session in cache
	sessionKey := fmt.Sprintf(cache.UserSessionKey, userID)
	sessionData := map[string]interface{}{
		"mobile":     mobile,
		"role":       "saas_admin",
		"user_id":    userID,
		"created_at": time.Now(),
	}

	sessionExpiry := 24 * time.Hour
	err = s.cache.Set(ctx, sessionKey, sessionData, sessionExpiry)
	if err != nil {
		return "", fmt.Errorf("failed to store session: %w", err)
	}

	return tokenString, nil
}

func (s *AdminService) GetAdminByMobile(ctx context.Context, mobile string) (map[string]interface{}, error) {
	// Get from database
	var adminUser models.AdminUser
	err := s.db.Where("mobile = ? AND active = true", mobile).First(&adminUser).Error
	if err != nil {
		// Fallback for demo admin if not yet in DB
		if mobile == "+918630668488" {
			return map[string]interface{}{
				"mobile":      mobile,
				"first_name":  "Tushar",
				"last_name":   "Agrawal",
				"email":       "tusharagrawal0104@gmail.com",
				"name":        "Tushar Agrawal",
				"role":        "super_admin",
				"permissions": models.GetDefaultPermissions("super_admin"),
				"department":  "general",
				"active":      true,
			}, nil
		}
		return nil, fmt.Errorf("admin user not found: %w", err)
	}

	return map[string]interface{}{
		"id":          adminUser.ID,
		"mobile":      adminUser.Mobile,
		"first_name":  adminUser.FirstName,
		"last_name":   adminUser.LastName,
		"email":       adminUser.Email,
		"name":        adminUser.Name,
		"role":        adminUser.Role,
		"permissions": adminUser.Permissions,
		"department":  adminUser.Department,
		"avatar_url":  adminUser.AvatarURL,
		"active":      adminUser.Active,
	}, nil
}

// Helper function to generate OTP
func (s *AdminService) GetAllTenants(ctx context.Context) ([]map[string]interface{}, error) {
	type TenantData struct {
		ID               string     `json:"id"`
		Name             string     `json:"name"`
		Email            string     `json:"email"`
		Status           string     `json:"status"`
		SubscriptionPlan string     `json:"subscription_plan"`
		LocationsCount   int        `json:"locations_count"`
		UsersCount       int        `json:"users_count"`
		ProductsCount    int        `json:"products_count"`
		CreatedAt        time.Time  `json:"created_at"`
		LastActive       *time.Time `json:"last_active"`
	}

	var tenants []TenantData

	// Get all tenants with their latest subscription and usage info
	query := `
		SELECT DISTINCT
			t.id as id,
			t.name as name,
			COALESCE(t.phone, '') as email,
			COALESCE(latest_sub.status, 'no_subscription') as status,
			COALESCE(p.display_name, 'No Plan') as subscription_plan,
			COALESCE(ur.locations, 0) as locations_count,
			COALESCE(ur.users, 0) as users_count,
			COALESCE(ur.products, 0) as products_count,
			t.created_at,
			COALESCE(ur.updated_at, latest_sub.updated_at, t.updated_at) as last_active
		FROM tenants t
		LEFT JOIN (
			SELECT DISTINCT ON (tenant_id)
				tenant_id, id, status, plan_id, created_at, updated_at
			FROM subscriptions
			WHERE deleted_at IS NULL
			ORDER BY tenant_id, created_at DESC
		) latest_sub ON t.id = latest_sub.tenant_id
		LEFT JOIN pricing_plans p ON latest_sub.plan_id = p.id
		LEFT JOIN (
			SELECT
				subscription_id,
				locations,
				users,
				products,
				updated_at,
				ROW_NUMBER() OVER (PARTITION BY subscription_id ORDER BY updated_at DESC) as rn
			FROM usage_records
		) ur ON latest_sub.id = ur.subscription_id AND ur.rn = 1
		WHERE t.deleted_at IS NULL
		ORDER BY t.created_at DESC
	`

	if err := s.db.Raw(query).Scan(&tenants).Error; err != nil {
		return nil, fmt.Errorf("failed to get tenants: %w", err)
	}

	// Convert to interface{} slice for JSON response
	result := make([]map[string]interface{}, len(tenants))
	for i, tenant := range tenants {
		result[i] = map[string]interface{}{
			"id":                tenant.ID,
			"name":              tenant.Name,
			"email":             tenant.Email,
			"status":            tenant.Status,
			"subscription_plan": tenant.SubscriptionPlan,
			"locations_count":   tenant.LocationsCount,
			"users_count":       tenant.UsersCount,
			"products_count":    tenant.ProductsCount,
			"created_at":        tenant.CreatedAt,
			"last_active":       tenant.LastActive,
		}
	}

	return result, nil
}

// Tenant Detail methods

func (s *AdminService) GetTenantDetail(ctx context.Context, tenantID uuid.UUID) (*models.TenantDetailResponse, error) {
	// Get basic tenant info
	type TenantBasic struct {
		ID        uuid.UUID  `json:"id"`
		Name      string     `json:"name"`
		Domain    string     `json:"domain"`
		IsActive  bool       `json:"is_active"`
		CreatedAt time.Time  `json:"created_at"`
		UpdatedAt time.Time  `json:"updated_at"`
	}

	var tenant TenantBasic
	if err := s.db.Raw("SELECT id, name, COALESCE(phone, '') as domain, COALESCE(is_active, true) as is_active, created_at, updated_at FROM tenants WHERE id = ? AND deleted_at IS NULL", tenantID).Scan(&tenant).Error; err != nil {
		return nil, fmt.Errorf("tenant not found: %w", err)
	}

	detail := &models.TenantDetailResponse{
		ID:       tenant.ID,
		Name:     tenant.Name,
		Email:    tenant.Domain,
		IsActive: tenant.IsActive,
		CreatedAt: tenant.CreatedAt,
	}

	// Get subscription
	var subscription models.Subscription
	err := s.db.Preload("Plan").Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Order("created_at DESC").First(&subscription).Error
	if err == nil {
		detail.Status = subscription.Status
		detail.SubscriptionPlan = subscription.Plan.DisplayName
		detail.Subscription = &models.SubscriptionResponse{
			ID:                 subscription.ID,
			TenantID:           subscription.TenantID,
			Plan:               subscription.Plan,
			Status:             subscription.Status,
			CurrentPeriodStart: subscription.CurrentPeriodStart,
			CurrentPeriodEnd:   subscription.CurrentPeriodEnd,
			TrialStart:         subscription.TrialStart,
			TrialEnd:           subscription.TrialEnd,
			BillingCycle:       subscription.BillingCycle,
			Amount:             subscription.Amount,
			Currency:           subscription.Currency,
			NextBillingDate:    subscription.NextBillingDate,
			CreatedAt:          subscription.CreatedAt,
			UpdatedAt:          subscription.UpdatedAt,
		}

		// Get usage
		var usage models.UsageRecord
		if err := s.db.Where("tenant_id = ?", tenantID).Order("record_date DESC").First(&usage).Error; err == nil {
			var locationUsage, userUsage, productUsage float64
			if subscription.Plan.MaxLocations > 0 {
				locationUsage = float64(usage.Locations) / float64(subscription.Plan.MaxLocations) * 100
			}
			if subscription.Plan.MaxUsers > 0 {
				userUsage = float64(usage.Users) / float64(subscription.Plan.MaxUsers) * 100
			}
			if subscription.Plan.MaxProducts > 0 {
				productUsage = float64(usage.Products) / float64(subscription.Plan.MaxProducts) * 100
			}
			detail.Usage = &models.TenantUsageResponse{
				Locations:     usage.Locations,
				MaxLocations:  subscription.Plan.MaxLocations,
				LocationUsage: locationUsage,
				Users:         usage.Users,
				MaxUsers:      subscription.Plan.MaxUsers,
				UserUsage:     userUsage,
				Products:      usage.Products,
				MaxProducts:   subscription.Plan.MaxProducts,
				ProductUsage:  productUsage,
			}
		}

		// Recent payments
		s.db.Where("subscription_id = ?", subscription.ID).Order("created_at DESC").Limit(5).Find(&detail.RecentPayments)
	} else {
		detail.Status = "no_subscription"
		detail.SubscriptionPlan = "No Plan"
	}

	// Counts from shared tables
	s.db.Raw("SELECT COUNT(*) FROM users WHERE tenant_id = ? AND deleted_at IS NULL", tenantID).Scan(&detail.UserCount)
	s.db.Raw("SELECT COUNT(*) FROM shops WHERE tenant_id = ? AND deleted_at IS NULL", tenantID).Scan(&detail.ShopCount)
	s.db.Raw("SELECT COUNT(*) FROM products WHERE tenant_id = ? AND deleted_at IS NULL", tenantID).Scan(&detail.ProductCount)

	// Recent audit logs
	s.db.Where("tenant_id = ?", tenantID).Order("created_at DESC").Limit(10).Find(&detail.RecentAuditLogs)

	return detail, nil
}

func (s *AdminService) GetTenantTimeline(ctx context.Context, tenantID uuid.UUID, page, limit int) ([]models.TimelineEvent, int64, error) {
	var events []models.TimelineEvent

	// Gather events from multiple sources
	// 1. Audit logs for this tenant
	var auditLogs []models.AuditLog
	s.db.Where("tenant_id = ?", tenantID).Order("created_at DESC").Limit(limit).Find(&auditLogs)

	for _, log := range auditLogs {
		events = append(events, models.TimelineEvent{
			ID:        log.ID,
			Type:      "audit",
			Title:     fmt.Sprintf("%s %s", log.Action, log.Resource),
			Details:   map[string]interface{}{"resource_id": log.ResourceID, "action": log.Action},
			CreatedAt: log.CreatedAt,
		})
	}

	// 2. Subscription changes
	var subscriptions []models.Subscription
	s.db.Preload("Plan").Where("tenant_id = ?", tenantID).Order("created_at DESC").Find(&subscriptions)

	for _, sub := range subscriptions {
		events = append(events, models.TimelineEvent{
			ID:        sub.ID,
			Type:      "subscription_change",
			Title:     fmt.Sprintf("Subscription %s - %s", sub.Status, sub.Plan.DisplayName),
			Details:   map[string]interface{}{"plan": sub.Plan.DisplayName, "status": sub.Status, "amount": sub.Amount},
			CreatedAt: sub.CreatedAt,
		})
	}

	// 3. Payments
	var payments []models.Payment
	s.db.Joins("JOIN subscriptions ON subscriptions.id = payments.subscription_id").
		Where("subscriptions.tenant_id = ?", tenantID).
		Order("payments.created_at DESC").Limit(limit).Find(&payments)

	for _, pay := range payments {
		events = append(events, models.TimelineEvent{
			ID:        pay.ID,
			Type:      "payment",
			Title:     fmt.Sprintf("Payment %s - ₹%.2f", pay.Status, pay.Amount),
			Details:   map[string]interface{}{"amount": pay.Amount, "status": pay.Status, "method": pay.PaymentMethod},
			CreatedAt: pay.CreatedAt,
		})
	}

	// Sort by created_at DESC
	for i := 0; i < len(events); i++ {
		for j := i + 1; j < len(events); j++ {
			if events[j].CreatedAt.After(events[i].CreatedAt) {
				events[i], events[j] = events[j], events[i]
			}
		}
	}

	total := int64(len(events))

	// Paginate
	offset := (page - 1) * limit
	if offset >= len(events) {
		return []models.TimelineEvent{}, total, nil
	}
	end := offset + limit
	if end > len(events) {
		end = len(events)
	}

	return events[offset:end], total, nil
}

func (s *AdminService) DeactivateTenant(ctx context.Context, tenantID uuid.UUID, adminID uuid.UUID, reason string) error {
	tx := s.db.Begin()

	// Deactivate tenant
	if err := tx.Exec("UPDATE tenants SET is_active = false, updated_at = ? WHERE id = ?", time.Now(), tenantID).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to deactivate tenant: %w", err)
	}

	// Suspend active subscription
	tx.Model(&models.Subscription{}).Where("tenant_id = ? AND status IN ?", tenantID, []string{"active", "trial"}).Updates(map[string]interface{}{
		"status": "suspended",
	})

	// Audit log
	newValues, _ := json.Marshal(map[string]interface{}{"is_active": false, "reason": reason})
	tx.Create(&models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &adminID,
		TenantID:    &tenantID,
		Action:      "deactivate",
		Resource:    "tenant",
		ResourceID:  tenantID.String(),
		NewValues:   string(newValues),
	})

	tx.Commit()
	return nil
}

func (s *AdminService) ReactivateTenant(ctx context.Context, tenantID uuid.UUID, adminID uuid.UUID) error {
	tx := s.db.Begin()

	// Reactivate tenant
	if err := tx.Exec("UPDATE tenants SET is_active = true, updated_at = ? WHERE id = ?", time.Now(), tenantID).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to reactivate tenant: %w", err)
	}

	// Reactivate suspended subscription
	tx.Model(&models.Subscription{}).Where("tenant_id = ? AND status = 'suspended'", tenantID).Updates(map[string]interface{}{
		"status": "active",
	})

	// Audit log
	tx.Create(&models.AuditLog{
		ID:          uuid.New(),
		AdminUserID: &adminID,
		TenantID:    &tenantID,
		Action:      "reactivate",
		Resource:    "tenant",
		ResourceID:  tenantID.String(),
		NewValues:   `{"is_active":true}`,
	})

	tx.Commit()
	return nil
}

func generateOTP(length int) (string, error) {
	const digits = "0123456789"
	otp := make([]byte, length)
	for i := range otp {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			return "", err
		}
		otp[i] = digits[num.Int64()]
	}
	return string(otp), nil
}
