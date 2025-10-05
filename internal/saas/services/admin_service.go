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
	// For demo purposes, allow the demo mobile number
	if mobile == "+918630668488" {
		return true, nil
	}

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
			// Create new admin user with specific details for +918630668488
			if mobile == "+918630668488" {
				adminUser = models.AdminUser{
					ID:        uuid.New(),
					Mobile:    mobile,
					FirstName: "Tushar",
					LastName:  "Agrawal",
					Name:      "Tushar Agrawal",
					Email:     "tusharagrawal0104@gmail.com",
					Role:      "saas_admin",
					Active:    true,
				}
			} else {
				adminUser = models.AdminUser{
					ID:        uuid.New(),
					Mobile:    mobile,
					FirstName: "Admin",
					LastName:  "User",
					Name:      "Admin User",
					Role:      "saas_admin",
					Active:    true,
				}
			}
			if err := s.db.Create(&adminUser).Error; err != nil {
				return "", fmt.Errorf("failed to create admin user: %w", err)
			}
		} else {
			return "", fmt.Errorf("failed to find admin user: %w", err)
		}
	}

	userID := adminUser.ID.String()

	// Create JWT claims
	claims := jwt.MapClaims{
		"mobile":  mobile,
		"role":    "saas_admin",
		"user_id": userID,
		"exp":     time.Now().Add(24 * time.Hour).Unix(),
		"iat":     time.Now().Unix(),
		"iss":     "saas-admin-service",
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
	// For specific SaaS admin mobile number
	if mobile == "+918630668488" {
		return map[string]interface{}{
			"mobile":     mobile,
			"first_name": "Tushar",
			"last_name":  "Agrawal",
			"email":      "tusharagrawal0104@gmail.com",
			"name":       "Tushar Agrawal",
			"role":       "saas_admin",
			"active":     true,
		}, nil
	}

	// Get from database for real mobile numbers
	var adminUser models.AdminUser
	err := s.db.Where("mobile = ? AND active = true", mobile).First(&adminUser).Error
	if err != nil {
		return nil, fmt.Errorf("admin user not found: %w", err)
	}

	return map[string]interface{}{
		"id":         adminUser.ID,
		"mobile":     adminUser.Mobile,
		"first_name": adminUser.FirstName,
		"last_name":  adminUser.LastName,
		"email":      adminUser.Email,
		"role":       adminUser.Role,
		"active":     adminUser.Active,
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
			COALESCE(t.domain, 'no-domain.com') as email,
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
