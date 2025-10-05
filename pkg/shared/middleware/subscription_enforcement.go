package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
)

// SubscriptionEnforcementMiddleware enforces subscription limits in real-time
type SubscriptionEnforcementMiddleware struct {
	db    *gorm.DB
	cache *cache.Cache
}

// ResourceType defines the type of resource being checked
type ResourceType string

const (
	ResourceUsers    ResourceType = "users"
	ResourceShops    ResourceType = "shops"
	ResourceProducts ResourceType = "products"
	ResourceSales    ResourceType = "sales"
	ResourceStorage  ResourceType = "storage"
)

// UsageLimits represents current usage vs plan limits
type UsageLimits struct {
	TenantID         uuid.UUID `json:"tenant_id"`
	PlanID           uuid.UUID `json:"plan_id"`
	MaxUsers         int       `json:"max_users"`
	MaxShops         int       `json:"max_shops"`
	MaxProducts      int       `json:"max_products"`
	CurrentUsers     int       `json:"current_users"`
	CurrentShops     int       `json:"current_shops"`
	CurrentProducts  int       `json:"current_products"`
	StorageUsed      int64     `json:"storage_used"`  // in bytes
	StorageLimit     int64     `json:"storage_limit"` // in bytes
	APIRequestsToday int       `json:"api_requests_today"`
	APIRequestLimit  int       `json:"api_request_limit"`
	LastUpdated      time.Time `json:"last_updated"`
}

// SubscriptionStatus represents the current subscription state
type SubscriptionStatus struct {
	ID                 uuid.UUID  `json:"id"`
	TenantID           uuid.UUID  `json:"tenant_id"`
	PlanID             uuid.UUID  `json:"plan_id"`
	Status             string     `json:"status"`
	CurrentPeriodStart time.Time  `json:"current_period_start"`
	CurrentPeriodEnd   time.Time  `json:"current_period_end"`
	TrialEnd           *time.Time `json:"trial_end"`
	IsActive           bool       `json:"is_active"`
	IsExpired          bool       `json:"is_expired"`
	DaysRemaining      int        `json:"days_remaining"`
	GracePeriodEnd     *time.Time `json:"grace_period_end"`
}

func NewSubscriptionEnforcementMiddleware(db *gorm.DB, cache *cache.Cache) *SubscriptionEnforcementMiddleware {
	return &SubscriptionEnforcementMiddleware{
		db:    db,
		cache: cache,
	}
}

// EnforceSubscriptionLimits creates middleware that enforces subscription limits
func (s *SubscriptionEnforcementMiddleware) EnforceSubscriptionLimits(resourceType ResourceType) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip enforcement for SaaS admins
		userRole := c.GetString("role")
		if userRole == "saas_admin" {
			c.Next()
			return
		}

		// Get tenant ID
		tenantIDStr := c.GetString("tenant_id")
		if tenantIDStr == "" {
			utils.HandleUnauthorized(c, "Tenant ID required")
			c.Abort()
			return
		}

		tenantID, err := uuid.Parse(tenantIDStr)
		if err != nil {
			utils.HandleBadRequest(c, "Invalid tenant ID")
			c.Abort()
			return
		}

		// Check subscription status
		status, err := s.getSubscriptionStatus(c.Request.Context(), tenantID)
		if err != nil {
			utils.HandleInternalError(c, "Failed to check subscription status")
			c.Abort()
			return
		}

		// Enforce subscription validity
		if !status.IsActive {
			s.handleInactiveSubscription(c, status)
			c.Abort()
			return
		}

		// Check resource-specific limits
		if err := s.checkResourceLimits(c.Request.Context(), tenantID, resourceType, c); err != nil {
			s.handleLimitExceeded(c, resourceType, err)
			c.Abort()
			return
		}

		// Set subscription context for downstream services
		c.Set("subscription_status", status)
		c.Set("subscription_active", status.IsActive)
		c.Set("plan_id", status.PlanID.String())

		c.Next()
	}
}

// EnforceAPILimits creates middleware specifically for API rate limiting based on subscription
func (s *SubscriptionEnforcementMiddleware) EnforceAPILimits() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip for SaaS admins
		userRole := c.GetString("role")
		if userRole == "saas_admin" {
			c.Next()
			return
		}

		tenantIDStr := c.GetString("tenant_id")
		if tenantIDStr == "" {
			c.Next()
			return
		}

		tenantID, err := uuid.Parse(tenantIDStr)
		if err != nil {
			c.Next()
			return
		}

		// Check and increment API usage
		if err := s.checkAndIncrementAPIUsage(c.Request.Context(), tenantID); err != nil {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":   "API request limit exceeded",
				"message": err.Error(),
				"code":    "API_LIMIT_EXCEEDED",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// getSubscriptionStatus retrieves current subscription status with caching
func (s *SubscriptionEnforcementMiddleware) getSubscriptionStatus(ctx context.Context, tenantID uuid.UUID) (*SubscriptionStatus, error) {
	cacheKey := fmt.Sprintf("subscription_status:%s", tenantID.String())

	// Try cache first
	var status SubscriptionStatus
	var cached interface{}
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		if cachedStr, ok := cached.(string); ok {
			if err := json.Unmarshal([]byte(cachedStr), &status); err == nil {
				// Check if cache is still valid (5 minutes)
				if time.Since(status.CurrentPeriodStart) < 5*time.Minute {
					return &status, nil
				}
			}
		}
	}

	// Query database
	var subscription struct {
		ID                 uuid.UUID  `json:"id"`
		TenantID           uuid.UUID  `json:"tenant_id"`
		PlanID             uuid.UUID  `json:"plan_id"`
		Status             string     `json:"status"`
		CurrentPeriodStart time.Time  `json:"current_period_start"`
		CurrentPeriodEnd   time.Time  `json:"current_period_end"`
		TrialEnd           *time.Time `json:"trial_end"`
	}

	query := `
		SELECT id, tenant_id, plan_id, status, current_period_start, current_period_end, trial_end
		FROM subscriptions 
		WHERE tenant_id = ? AND deleted_at IS NULL
		ORDER BY created_at DESC 
		LIMIT 1
	`

	if err := s.db.Raw(query, tenantID).Scan(&subscription).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return &SubscriptionStatus{
				TenantID:      tenantID,
				Status:        "no_subscription",
				IsActive:      false,
				IsExpired:     true,
				DaysRemaining: 0,
			}, nil
		}
		return nil, err
	}

	// Calculate status
	now := time.Now()
	status = SubscriptionStatus{
		ID:                 subscription.ID,
		TenantID:           subscription.TenantID,
		PlanID:             subscription.PlanID,
		Status:             subscription.Status,
		CurrentPeriodStart: subscription.CurrentPeriodStart,
		CurrentPeriodEnd:   subscription.CurrentPeriodEnd,
		TrialEnd:           subscription.TrialEnd,
	}

	// Determine if subscription is active
	switch subscription.Status {
	case "active":
		status.IsActive = now.Before(subscription.CurrentPeriodEnd)
		status.IsExpired = now.After(subscription.CurrentPeriodEnd)
	case "trial":
		if subscription.TrialEnd != nil {
			status.IsActive = now.Before(*subscription.TrialEnd)
			status.IsExpired = now.After(*subscription.TrialEnd)
		} else {
			status.IsActive = now.Before(subscription.CurrentPeriodEnd)
			status.IsExpired = now.After(subscription.CurrentPeriodEnd)
		}
	case "suspended", "cancelled", "expired":
		status.IsActive = false
		status.IsExpired = true
	default:
		status.IsActive = false
		status.IsExpired = true
	}

	// Calculate days remaining
	endDate := subscription.CurrentPeriodEnd
	if subscription.TrialEnd != nil && subscription.Status == "trial" {
		endDate = *subscription.TrialEnd
	}

	if now.Before(endDate) {
		status.DaysRemaining = int(endDate.Sub(now).Hours() / 24)
	} else {
		status.DaysRemaining = 0
		// Set grace period (7 days after expiration)
		gracePeriodEnd := endDate.AddDate(0, 0, 7)
		status.GracePeriodEnd = &gracePeriodEnd
	}

	// Cache the result
	if statusData, err := json.Marshal(status); err == nil {
		s.cache.Set(ctx, cacheKey, string(statusData), 5*time.Minute)
	}

	return &status, nil
}

// checkResourceLimits checks if the current action would exceed plan limits
func (s *SubscriptionEnforcementMiddleware) checkResourceLimits(ctx context.Context, tenantID uuid.UUID, resourceType ResourceType, c *gin.Context) error {
	limits, err := s.getUsageLimits(ctx, tenantID)
	if err != nil {
		return err
	}

	switch resourceType {
	case ResourceUsers:
		if c.Request.Method == "POST" && limits.MaxUsers > 0 && limits.CurrentUsers >= limits.MaxUsers {
			return fmt.Errorf("user limit exceeded: %d/%d", limits.CurrentUsers, limits.MaxUsers)
		}
	case ResourceShops:
		if c.Request.Method == "POST" && limits.MaxShops > 0 && limits.CurrentShops >= limits.MaxShops {
			return fmt.Errorf("shop limit exceeded: %d/%d", limits.CurrentShops, limits.MaxShops)
		}
	case ResourceProducts:
		if c.Request.Method == "POST" && limits.MaxProducts > 0 && limits.CurrentProducts >= limits.MaxProducts {
			return fmt.Errorf("product limit exceeded: %d/%d", limits.CurrentProducts, limits.MaxProducts)
		}
	case ResourceStorage:
		// Check storage limits for file uploads
		if contentLength := c.Request.Header.Get("Content-Length"); contentLength != "" {
			if size, err := strconv.ParseInt(contentLength, 10, 64); err == nil {
				if limits.StorageLimit > 0 && (limits.StorageUsed+size) > limits.StorageLimit {
					return fmt.Errorf("storage limit exceeded: %d/%d bytes", limits.StorageUsed, limits.StorageLimit)
				}
			}
		}
	}

	return nil
}

// getUsageLimits retrieves current usage limits with caching
func (s *SubscriptionEnforcementMiddleware) getUsageLimits(ctx context.Context, tenantID uuid.UUID) (*UsageLimits, error) {
	cacheKey := fmt.Sprintf("usage_limits:%s", tenantID.String())

	// Try cache first
	var limits UsageLimits
	var cached interface{}
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		if cachedStr, ok := cached.(string); ok {
			if err := json.Unmarshal([]byte(cachedStr), &limits); err == nil {
				// Check if cache is still valid (1 minute for usage data)
				if time.Since(limits.LastUpdated) < 1*time.Minute {
					return &limits, nil
				}
			}
		}
	}

	// Query current usage and limits
	query := `
		SELECT 
			s.plan_id,
			p.max_users,
			p.max_locations as max_shops,
			p.max_products,
			COALESCE(users_count.count, 0) as current_users,
			COALESCE(shops_count.count, 0) as current_shops,
			COALESCE(products_count.count, 0) as current_products,
			COALESCE(ur.storage_used, 0) as storage_used,
			COALESCE(ur.api_requests, 0) as api_requests_today
		FROM subscriptions s
		JOIN pricing_plans p ON s.plan_id = p.id
		LEFT JOIN (
			SELECT tenant_id, COUNT(*) as count 
			FROM users 
			WHERE deleted_at IS NULL 
			GROUP BY tenant_id
		) users_count ON s.tenant_id = users_count.tenant_id
		LEFT JOIN (
			SELECT tenant_id, COUNT(*) as count 
			FROM shops 
			WHERE deleted_at IS NULL 
			GROUP BY tenant_id
		) shops_count ON s.tenant_id = shops_count.tenant_id
		LEFT JOIN (
			SELECT tenant_id, COUNT(*) as count 
			FROM products 
			WHERE deleted_at IS NULL 
			GROUP BY tenant_id
		) products_count ON s.tenant_id = products_count.tenant_id
		LEFT JOIN (
			SELECT 
				tenant_id, 
				storage_used,
				api_requests
			FROM usage_records 
			WHERE tenant_id = ? AND record_date = CURRENT_DATE
			ORDER BY created_at DESC 
			LIMIT 1
		) ur ON s.tenant_id = ur.tenant_id
		WHERE s.tenant_id = ? AND s.deleted_at IS NULL
		ORDER BY s.created_at DESC 
		LIMIT 1
	`

	var result struct {
		PlanID           uuid.UUID `json:"plan_id"`
		MaxUsers         int       `json:"max_users"`
		MaxShops         int       `json:"max_shops"`
		MaxProducts      int       `json:"max_products"`
		CurrentUsers     int       `json:"current_users"`
		CurrentShops     int       `json:"current_shops"`
		CurrentProducts  int       `json:"current_products"`
		StorageUsed      int64     `json:"storage_used"`
		APIRequestsToday int       `json:"api_requests_today"`
	}

	if err := s.db.Raw(query, tenantID, tenantID).Scan(&result).Error; err != nil {
		return nil, err
	}

	limits = UsageLimits{
		TenantID:         tenantID,
		PlanID:           result.PlanID,
		MaxUsers:         result.MaxUsers,
		MaxShops:         result.MaxShops,
		MaxProducts:      result.MaxProducts,
		CurrentUsers:     result.CurrentUsers,
		CurrentShops:     result.CurrentShops,
		CurrentProducts:  result.CurrentProducts,
		StorageUsed:      result.StorageUsed,
		StorageLimit:     10 * 1024 * 1024 * 1024, // 10GB default, should come from plan
		APIRequestsToday: result.APIRequestsToday,
		APIRequestLimit:  10000, // Default 10k requests/day, should come from plan
		LastUpdated:      time.Now(),
	}

	// Cache the result
	if limitsData, err := json.Marshal(limits); err == nil {
		s.cache.Set(ctx, cacheKey, string(limitsData), 1*time.Minute)
	}

	return &limits, nil
}

// checkAndIncrementAPIUsage checks API limits and increments usage
func (s *SubscriptionEnforcementMiddleware) checkAndIncrementAPIUsage(ctx context.Context, tenantID uuid.UUID) error {
	today := time.Now().Format("2006-01-02")
	cacheKey := fmt.Sprintf("api_usage:%s:%s", tenantID.String(), today)

	// Get current usage
	currentUsage := 0
	var cached interface{}
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		if cachedStr, ok := cached.(string); ok {
			if usage, err := strconv.Atoi(cachedStr); err == nil {
				currentUsage = usage
			}
		}
	}

	// Get limit from subscription
	limits, err := s.getUsageLimits(ctx, tenantID)
	if err != nil {
		return err
	}

	// Check limit
	if limits.APIRequestLimit > 0 && currentUsage >= limits.APIRequestLimit {
		return fmt.Errorf("daily API request limit exceeded: %d/%d", currentUsage, limits.APIRequestLimit)
	}

	// Increment usage
	newUsage := currentUsage + 1

	// Set with expiration at end of day
	now := time.Now()
	endOfDay := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, now.Location())
	expiration := endOfDay.Sub(now)

	s.cache.Set(ctx, cacheKey, strconv.Itoa(newUsage), expiration)

	return nil
}

// handleInactiveSubscription handles requests for inactive subscriptions
func (s *SubscriptionEnforcementMiddleware) handleInactiveSubscription(c *gin.Context, status *SubscriptionStatus) {
	var message string
	var code string

	switch status.Status {
	case "trial":
		if status.IsExpired {
			message = "Trial period has expired. Please upgrade to continue using the service."
			code = "TRIAL_EXPIRED"
		} else {
			message = fmt.Sprintf("Trial period ends in %d days.", status.DaysRemaining)
			code = "TRIAL_ENDING"
		}
	case "suspended":
		message = "Your subscription has been suspended. Please contact support."
		code = "SUBSCRIPTION_SUSPENDED"
	case "cancelled":
		message = "Your subscription has been cancelled."
		code = "SUBSCRIPTION_CANCELLED"
	case "expired":
		if status.GracePeriodEnd != nil && time.Now().Before(*status.GracePeriodEnd) {
			message = "Your subscription has expired but is in grace period. Please renew to continue."
			code = "SUBSCRIPTION_GRACE_PERIOD"
		} else {
			message = "Your subscription has expired. Please renew to continue using the service."
			code = "SUBSCRIPTION_EXPIRED"
		}
	default:
		message = "No active subscription found. Please subscribe to continue."
		code = "NO_SUBSCRIPTION"
	}

	c.JSON(http.StatusPaymentRequired, gin.H{
		"error":               "Subscription required",
		"message":             message,
		"code":                code,
		"subscription_status": status,
		"upgrade_url":         "/subscription/upgrade",
	})
}

// handleLimitExceeded handles requests that exceed plan limits
func (s *SubscriptionEnforcementMiddleware) handleLimitExceeded(c *gin.Context, resourceType ResourceType, err error) {
	c.JSON(http.StatusForbidden, gin.H{
		"error":         "Plan limit exceeded",
		"message":       err.Error(),
		"resource_type": string(resourceType),
		"code":          "PLAN_LIMIT_EXCEEDED",
		"upgrade_url":   "/subscription/upgrade",
	})
}

// GetUsageDashboard returns usage dashboard data for tenant
func (s *SubscriptionEnforcementMiddleware) GetUsageDashboard(c *gin.Context) {
	tenantIDStr := c.Param("tenant_id")
	if tenantIDStr == "" {
		tenantIDStr = c.GetString("tenant_id")
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		utils.HandleBadRequest(c, "Invalid tenant ID")
		return
	}

	// Get subscription status
	status, err := s.getSubscriptionStatus(c.Request.Context(), tenantID)
	if err != nil {
		utils.HandleInternalError(c, "Failed to get subscription status")
		return
	}

	// Get usage limits
	limits, err := s.getUsageLimits(c.Request.Context(), tenantID)
	if err != nil {
		utils.HandleInternalError(c, "Failed to get usage limits")
		return
	}

	// Calculate usage percentages
	userUsagePercent := float64(0)
	if limits.MaxUsers > 0 {
		userUsagePercent = float64(limits.CurrentUsers) / float64(limits.MaxUsers) * 100
	}

	shopUsagePercent := float64(0)
	if limits.MaxShops > 0 {
		shopUsagePercent = float64(limits.CurrentShops) / float64(limits.MaxShops) * 100
	}

	productUsagePercent := float64(0)
	if limits.MaxProducts > 0 {
		productUsagePercent = float64(limits.CurrentProducts) / float64(limits.MaxProducts) * 100
	}

	storageUsagePercent := float64(0)
	if limits.StorageLimit > 0 {
		storageUsagePercent = float64(limits.StorageUsed) / float64(limits.StorageLimit) * 100
	}

	apiUsagePercent := float64(0)
	if limits.APIRequestLimit > 0 {
		apiUsagePercent = float64(limits.APIRequestsToday) / float64(limits.APIRequestLimit) * 100
	}

	response := gin.H{
		"subscription_status": status,
		"usage_limits":        limits,
		"usage_percentages": gin.H{
			"users":        userUsagePercent,
			"shops":        shopUsagePercent,
			"products":     productUsagePercent,
			"storage":      storageUsagePercent,
			"api_requests": apiUsagePercent,
		},
		"warnings": s.generateUsageWarnings(limits),
	}

	c.JSON(http.StatusOK, response)
}

// generateUsageWarnings generates warnings for high usage
func (s *SubscriptionEnforcementMiddleware) generateUsageWarnings(limits *UsageLimits) []string {
	var warnings []string

	// Check for usage above 80%
	if limits.MaxUsers > 0 {
		usagePercent := float64(limits.CurrentUsers) / float64(limits.MaxUsers) * 100
		if usagePercent >= 80 {
			warnings = append(warnings, fmt.Sprintf("User limit at %.1f%% capacity", usagePercent))
		}
	}

	if limits.MaxShops > 0 {
		usagePercent := float64(limits.CurrentShops) / float64(limits.MaxShops) * 100
		if usagePercent >= 80 {
			warnings = append(warnings, fmt.Sprintf("Shop limit at %.1f%% capacity", usagePercent))
		}
	}

	if limits.MaxProducts > 0 {
		usagePercent := float64(limits.CurrentProducts) / float64(limits.MaxProducts) * 100
		if usagePercent >= 80 {
			warnings = append(warnings, fmt.Sprintf("Product limit at %.1f%% capacity", usagePercent))
		}
	}

	if limits.StorageLimit > 0 {
		usagePercent := float64(limits.StorageUsed) / float64(limits.StorageLimit) * 100
		if usagePercent >= 80 {
			warnings = append(warnings, fmt.Sprintf("Storage at %.1f%% capacity", usagePercent))
		}
	}

	if limits.APIRequestLimit > 0 {
		usagePercent := float64(limits.APIRequestsToday) / float64(limits.APIRequestLimit) * 100
		if usagePercent >= 80 {
			warnings = append(warnings, fmt.Sprintf("Daily API requests at %.1f%% capacity", usagePercent))
		}
	}

	return warnings
}
