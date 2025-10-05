package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

// EnhancedPlanManagementService provides comprehensive plan management with industrial best practices
type EnhancedPlanManagementService struct {
	db            *gorm.DB
	config        *config.Config
	cache         *cache.Cache
	paymentClient *RazorpayClient
	// auditService  *AuditService
}

// PlanLimits defines comprehensive resource limits for a plan
type PlanLimits struct {
	// Core Limits
	MaxUsers         int   `json:"max_users"`           // -1 for unlimited
	MaxShops         int   `json:"max_shops"`           // -1 for unlimited
	MaxProducts      int   `json:"max_products"`        // -1 for unlimited
	MaxSalesPerMonth int   `json:"max_sales_per_month"` // -1 for unlimited
	MaxStorageGB     int64 `json:"max_storage_gb"`      // -1 for unlimited

	// API Limits
	APIRequestsPerDay    int `json:"api_requests_per_day"`    // Daily API request limit
	APIRequestsPerMinute int `json:"api_requests_per_minute"` // Rate limiting
	WebhookEndpoints     int `json:"webhook_endpoints"`       // Max webhook URLs

	// Feature Limits
	MaxReports        int  `json:"max_reports"`        // Monthly reports
	MaxExports        int  `json:"max_exports"`        // Monthly data exports
	MaxIntegrations   int  `json:"max_integrations"`   // Third-party integrations
	AdvancedAnalytics bool `json:"advanced_analytics"` // Advanced analytics access
	CustomBranding    bool `json:"custom_branding"`    // White-label capabilities
	PrioritySupport   bool `json:"priority_support"`   // 24/7 support access
	APIAccess         bool `json:"api_access"`         // REST API access
	WebhookAccess     bool `json:"webhook_access"`     // Webhook notifications

	// Business Features
	MultiLocationSupport bool `json:"multi_location_support"` // Multiple shop management
	InventoryManagement  bool `json:"inventory_management"`   // Advanced inventory
	FinancialReporting   bool `json:"financial_reporting"`    // Financial modules
	UserRoleManagement   bool `json:"user_role_management"`   // Role-based access
	AuditLogs            bool `json:"audit_logs"`             // Activity tracking
	DataBackups          bool `json:"data_backups"`           // Automated backups
}

// PlanFeatures defines feature availability
type PlanFeatures struct {
	CoreFeatures       []string `json:"core_features"`
	AdvancedFeatures   []string `json:"advanced_features"`
	EnterpriseFeatures []string `json:"enterprise_features"`
	AIFeatures         []string `json:"ai_features"`
}

// PlanPricing defines comprehensive pricing structure
type PlanPricing struct {
	BasePrice         float64            `json:"base_price"`
	Currency          string             `json:"currency"`
	BillingCycle      string             `json:"billing_cycle"`
	DiscountStructure map[string]float64 `json:"discount_structure"` // term -> discount %
	SetupFee          float64            `json:"setup_fee"`
	OverageRates      map[string]float64 `json:"overage_rates"` // resource -> rate per unit
}

// ComprehensivePlan represents a complete plan definition
type ComprehensivePlan struct {
	models.PricingPlan
	Limits        PlanLimits             `json:"limits"`
	Features      PlanFeatures           `json:"features"`
	Pricing       PlanPricing            `json:"pricing"`
	Metadata      map[string]interface{} `json:"metadata"`
	EffectiveDate time.Time              `json:"effective_date"`
	ExpiryDate    *time.Time             `json:"expiry_date"`
}

// PlanUsageStats represents current usage statistics
type PlanUsageStats struct {
	TenantID       uuid.UUID          `json:"tenant_id"`
	PlanID         uuid.UUID          `json:"plan_id"`
	BillingPeriod  string             `json:"billing_period"`
	UsageData      map[string]int     `json:"usage_data"`
	OverageCharges map[string]float64 `json:"overage_charges"`
	LastUpdated    time.Time          `json:"last_updated"`
}

// PlanChangeRequest represents a plan change request
type PlanChangeRequest struct {
	TenantID        uuid.UUID `json:"tenant_id"`
	CurrentPlanID   uuid.UUID `json:"current_plan_id"`
	NewPlanID       uuid.UUID `json:"new_plan_id"`
	ChangeType      string    `json:"change_type"` // upgrade, downgrade, change
	EffectiveDate   time.Time `json:"effective_date"`
	ProrationMethod string    `json:"proration_method"` // immediate, next_cycle, custom
	PreserveTrial   bool      `json:"preserve_trial"`
	Reason          string    `json:"reason"`
	RequestedBy     uuid.UUID `json:"requested_by"`
}

func NewEnhancedPlanManagementService(db *gorm.DB, cfg *config.Config, cache *cache.Cache) *EnhancedPlanManagementService {
	return &EnhancedPlanManagementService{
		db:            db,
		config:        cfg,
		cache:         cache,
		paymentClient: NewRazorpayClient(cfg),
		// auditService:  NewAuditService(db),
	}
}

// CreateComprehensivePlan creates a new plan with full feature set
func (s *EnhancedPlanManagementService) CreateComprehensivePlan(ctx context.Context, req *ComprehensivePlan) (*ComprehensivePlan, error) {
	// Start transaction
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Validate plan data
	if err := s.validatePlanData(req); err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("plan validation failed: %w", err)
	}

	// Create base plan
	basePlan := req.PricingPlan
	basePlan.ID = uuid.New()
	basePlan.CreatedAt = time.Now()
	basePlan.UpdatedAt = time.Now()

	if err := tx.Create(&basePlan).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create base plan: %w", err)
	}

	// Store extended plan data
	planData := map[string]interface{}{
		"limits":         req.Limits,
		"features":       req.Features,
		"pricing":        req.Pricing,
		"metadata":       req.Metadata,
		"effective_date": req.EffectiveDate,
		"expiry_date":    req.ExpiryDate,
	}

	planDataJSON, err := json.Marshal(planData)
	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to serialize plan data: %w", err)
	}

	// Store in extended plan metadata table
	extendedPlan := struct {
		ID        uuid.UUID `gorm:"type:uuid;primary_key"`
		PlanID    uuid.UUID `gorm:"type:uuid;not null"`
		Data      string    `gorm:"type:jsonb"`
		Version   int       `gorm:"default:1"`
		CreatedAt time.Time
		UpdatedAt time.Time
	}{
		ID:        uuid.New(),
		PlanID:    basePlan.ID,
		Data:      string(planDataJSON),
		Version:   1,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	if err := tx.Table("plan_extended_data").Create(&extendedPlan).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to store extended plan data: %w", err)
	}

	// Create billing variants automatically
	if basePlan.AutoCreateVariants {
		if err := s.createBillingVariants(tx, basePlan.ID, req.Pricing); err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create billing variants: %w", err)
		}
	}

	// Create Razorpay plan (commented out for testing)
	// razorpayPlanID, err := s.createRazorpayPlan(ctx, &basePlan, req.Pricing)
	// if err != nil {
	//	   // Log error but don't fail the transaction
	//	   fmt.Printf("Warning: Failed to create Razorpay plan: %v\n", err)
	// } else {
	//	   basePlan.RazorpayPlanID = razorpayPlanID
	//	   tx.Save(&basePlan)
	// }

	// Audit log (would be implemented with proper audit service)
	log.Printf("Plan created: %s (%s)", basePlan.Name, basePlan.ID.String())

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Clear cache
	s.clearPlanCache()

	// Return comprehensive plan
	result := *req
	result.PricingPlan = basePlan
	return &result, nil
}

// GetComprehensivePlan retrieves a plan with full data
func (s *EnhancedPlanManagementService) GetComprehensivePlan(ctx context.Context, planID uuid.UUID) (*ComprehensivePlan, error) {
	cacheKey := fmt.Sprintf("comprehensive_plan:%s", planID.String())

	// Try cache first
	var cached interface{}
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		var plan ComprehensivePlan
		if cachedBytes, ok := cached.([]byte); ok {
			if err := json.Unmarshal(cachedBytes, &plan); err == nil {
				return &plan, nil
			}
		} else if cachedStr, ok := cached.(string); ok {
			if err := json.Unmarshal([]byte(cachedStr), &plan); err == nil {
				return &plan, nil
			}
		}
	}

	// Query base plan
	var basePlan models.PricingPlan
	if err := s.db.First(&basePlan, planID).Error; err != nil {
		return nil, fmt.Errorf("plan not found: %w", err)
	}

	// Query extended data
	var extendedData struct {
		Data string `json:"data"`
	}

	err := s.db.Table("plan_extended_data").
		Select("data").
		Where("plan_id = ?", planID).
		Order("version DESC").
		First(&extendedData).Error

	if err != nil && err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to get extended plan data: %w", err)
	}

	// Build comprehensive plan
	plan := ComprehensivePlan{
		PricingPlan: basePlan,
	}

	// Parse extended data if available
	if extendedData.Data != "" {
		var planData map[string]interface{}
		if err := json.Unmarshal([]byte(extendedData.Data), &planData); err == nil {
			// Extract structured data
			if limits, ok := planData["limits"]; ok {
				if limitsJSON, err := json.Marshal(limits); err == nil {
					json.Unmarshal(limitsJSON, &plan.Limits)
				}
			}
			if features, ok := planData["features"]; ok {
				if featuresJSON, err := json.Marshal(features); err == nil {
					json.Unmarshal(featuresJSON, &plan.Features)
				}
			}
			if pricing, ok := planData["pricing"]; ok {
				if pricingJSON, err := json.Marshal(pricing); err == nil {
					json.Unmarshal(pricingJSON, &plan.Pricing)
				}
			}
			if metadata, ok := planData["metadata"]; ok {
				plan.Metadata = metadata.(map[string]interface{})
			}
		}
	} else {
		// Provide defaults for legacy plans
		plan.Limits = PlanLimits{
			MaxUsers:          basePlan.MaxUsers,
			MaxShops:          basePlan.MaxLocations,
			MaxProducts:       basePlan.MaxProducts,
			APIRequestsPerDay: 10000,
			APIAccess:         true,
		}

		plan.Features = PlanFeatures{
			CoreFeatures: basePlan.Features,
			AIFeatures:   basePlan.AIFeatures,
		}

		plan.Pricing = PlanPricing{
			BasePrice:    basePlan.Price,
			Currency:     basePlan.Currency,
			BillingCycle: basePlan.BillingCycle,
			DiscountStructure: map[string]float64{
				"12": basePlan.YearlyDiscount,
				"24": basePlan.TwoYearDiscount,
				"36": basePlan.ThreeYearDiscount,
			},
		}
	}

	// Cache result
	if planJSON, err := json.Marshal(plan); err == nil {
		s.cache.Set(ctx, cacheKey, string(planJSON), 15*time.Minute)
	}

	return &plan, nil
}

// GetPlanUsageStats returns current usage statistics for a tenant
func (s *EnhancedPlanManagementService) GetPlanUsageStats(ctx context.Context, tenantID uuid.UUID) (*PlanUsageStats, error) {
	cacheKey := fmt.Sprintf("plan_usage:%s", tenantID.String())

	// Try cache first
	var cached interface{}
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		var stats PlanUsageStats
		if cachedBytes, ok := cached.([]byte); ok {
			if err := json.Unmarshal(cachedBytes, &stats); err == nil {
				return &stats, nil
			}
		} else if cachedStr, ok := cached.(string); ok {
			if err := json.Unmarshal([]byte(cachedStr), &stats); err == nil {
				return &stats, nil
			}
		}
	}

	// Get current subscription
	var subscription models.Subscription
	err := s.db.Where("tenant_id = ? AND status IN ?", tenantID, []string{"active", "trial"}).
		Preload("Plan").
		First(&subscription).Error

	if err != nil {
		return nil, fmt.Errorf("no active subscription found: %w", err)
	}

	// Calculate current usage
	usageData := make(map[string]int)

	// Users count
	var userCount int64
	s.db.Model(&struct{}{}).Table("users").Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Count(&userCount)
	usageData["users"] = int(userCount)

	// Shops count
	var shopCount int64
	s.db.Model(&struct{}{}).Table("shops").Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Count(&shopCount)
	usageData["shops"] = int(shopCount)

	// Products count
	var productCount int64
	s.db.Model(&struct{}{}).Table("products").Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Count(&productCount)
	usageData["products"] = int(productCount)

	// API requests today
	today := time.Now().Format("2006-01-02")
	apiKey := fmt.Sprintf("api_usage:%s:%s", tenantID.String(), today)
	apiUsage := 0
	var apiCached interface{}
	if err := s.cache.Get(ctx, apiKey, &apiCached); err == nil {
		if cachedBytes, ok := apiCached.([]byte); ok {
			if err := json.Unmarshal(cachedBytes, &apiUsage); err == nil {
				usageData["api_requests"] = apiUsage
			}
		} else if cachedStr, ok := apiCached.(string); ok {
			if err := json.Unmarshal([]byte(cachedStr), &apiUsage); err == nil {
				usageData["api_requests"] = apiUsage
			}
		}
	}

	// Calculate overage charges
	plan, err := s.GetComprehensivePlan(ctx, subscription.PlanID)
	if err != nil {
		return nil, fmt.Errorf("failed to get plan details: %w", err)
	}

	overageCharges := make(map[string]float64)

	// Check for overages and calculate charges
	if plan.Limits.MaxUsers > 0 && usageData["users"] > plan.Limits.MaxUsers {
		overage := usageData["users"] - plan.Limits.MaxUsers
		if rate, exists := plan.Pricing.OverageRates["users"]; exists {
			overageCharges["users"] = float64(overage) * rate
		}
	}

	if plan.Limits.MaxShops > 0 && usageData["shops"] > plan.Limits.MaxShops {
		overage := usageData["shops"] - plan.Limits.MaxShops
		if rate, exists := plan.Pricing.OverageRates["shops"]; exists {
			overageCharges["shops"] = float64(overage) * rate
		}
	}

	if plan.Limits.MaxProducts > 0 && usageData["products"] > plan.Limits.MaxProducts {
		overage := usageData["products"] - plan.Limits.MaxProducts
		if rate, exists := plan.Pricing.OverageRates["products"]; exists {
			overageCharges["products"] = float64(overage) * rate
		}
	}

	stats := &PlanUsageStats{
		TenantID:       tenantID,
		PlanID:         subscription.PlanID,
		BillingPeriod:  subscription.BillingCycle,
		UsageData:      usageData,
		OverageCharges: overageCharges,
		LastUpdated:    time.Now(),
	}

	// Cache result
	if statsJSON, err := json.Marshal(stats); err == nil {
		s.cache.Set(ctx, cacheKey, string(statsJSON), 5*time.Minute)
	}

	return stats, nil
}

// ProcessPlanChange handles plan upgrades/downgrades with proration
func (s *EnhancedPlanManagementService) ProcessPlanChange(ctx context.Context, req *PlanChangeRequest) error {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Get current subscription
	var currentSub models.Subscription
	err := tx.Where("tenant_id = ? AND plan_id = ? AND status IN ?",
		req.TenantID, req.CurrentPlanID, []string{"active", "trial"}).
		First(&currentSub).Error

	if err != nil {
		tx.Rollback()
		return fmt.Errorf("current subscription not found: %w", err)
	}

	// Get new plan
	newPlan, err := s.GetComprehensivePlan(ctx, req.NewPlanID)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("new plan not found: %w", err)
	}

	// Validate plan change
	if err := s.validatePlanChange(ctx, &currentSub, newPlan, req); err != nil {
		tx.Rollback()
		return fmt.Errorf("plan change validation failed: %w", err)
	}

	// Calculate proration
	prorationAmount, err := s.calculateProration(ctx, &currentSub, newPlan, req)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("proration calculation failed: %w", err)
	}

	// Update subscription
	now := time.Now()
	switch req.ProrationMethod {
	case "immediate":
		currentSub.PlanID = req.NewPlanID
		currentSub.Amount = newPlan.Price
		currentSub.UpdatedAt = now

		// If there's a proration charge, create an invoice
		if prorationAmount != 0 {
			invoice := s.createProrationInvoice(&currentSub, prorationAmount)
			if err := tx.Create(&invoice).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create proration invoice: %w", err)
			}
		}

	case "next_cycle":
		// Schedule change for next billing cycle
		changeRecord := struct {
			ID             uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
			SubscriptionID uuid.UUID `gorm:"type:uuid;not null"`
			NewPlanID      uuid.UUID `gorm:"type:uuid;not null"`
			EffectiveDate  time.Time `gorm:"not null"`
			CreatedAt      time.Time
		}{
			SubscriptionID: currentSub.ID,
			NewPlanID:      req.NewPlanID,
			EffectiveDate:  currentSub.CurrentPeriodEnd,
			CreatedAt:      now,
		}

		if err := tx.Table("scheduled_plan_changes").Create(&changeRecord).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to schedule plan change: %w", err)
		}
	}

	if err := tx.Save(&currentSub).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update subscription: %w", err)
	}

	// Audit log for plan change
	log.Printf("Plan changed for subscription %s: old_plan=%s, new_plan=%s, type=%s, proration=%.2f",
		currentSub.ID.String(), req.CurrentPlanID.String(), req.NewPlanID.String(), req.ChangeType, prorationAmount)

	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit plan change: %w", err)
	}

	// Clear cache
	s.clearSubscriptionCache(req.TenantID)

	return nil
}

// Helper methods

func (s *EnhancedPlanManagementService) validatePlanData(plan *ComprehensivePlan) error {
	if plan.Name == "" {
		return fmt.Errorf("plan name is required")
	}
	if plan.Price < 0 {
		return fmt.Errorf("plan price cannot be negative")
	}
	if plan.Limits.MaxUsers < -1 {
		return fmt.Errorf("invalid user limit")
	}
	return nil
}

func (s *EnhancedPlanManagementService) createBillingVariants(tx *gorm.DB, planID uuid.UUID, pricing PlanPricing) error {
	for termStr, discount := range pricing.DiscountStructure {
		termMonths := 1
		if termStr == "12" {
			termMonths = 12
		} else if termStr == "24" {
			termMonths = 24
		} else if termStr == "36" {
			termMonths = 36
		}

		effectivePrice := pricing.BasePrice * (1 - discount/100)

		variant := models.PlanBillingVariant{
			ID:                 uuid.New(),
			BasePlanID:         planID,
			BillingTermMonths:  termMonths,
			DiscountPercentage: discount,
			EffectivePrice:     effectivePrice,
			IsActive:           true,
			CreatedAt:          time.Now(),
			UpdatedAt:          time.Now(),
		}

		if err := tx.Create(&variant).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *EnhancedPlanManagementService) createRazorpayPlan(ctx context.Context, plan *models.PricingPlan, pricing PlanPricing) (string, error) {
	// Implementation would integrate with Razorpay API
	// For now, return a mock plan ID
	return fmt.Sprintf("plan_%s", plan.ID.String()[:8]), nil
}

func (s *EnhancedPlanManagementService) validatePlanChange(ctx context.Context, currentSub *models.Subscription, newPlan *ComprehensivePlan, req *PlanChangeRequest) error {
	// Get current usage
	stats, err := s.GetPlanUsageStats(ctx, req.TenantID)
	if err != nil {
		return fmt.Errorf("failed to get usage stats: %w", err)
	}

	// Check if downgrading and usage exceeds new limits
	if req.ChangeType == "downgrade" {
		if newPlan.Limits.MaxUsers > 0 && stats.UsageData["users"] > newPlan.Limits.MaxUsers {
			return fmt.Errorf("cannot downgrade: current users (%d) exceed new plan limit (%d)",
				stats.UsageData["users"], newPlan.Limits.MaxUsers)
		}
		if newPlan.Limits.MaxShops > 0 && stats.UsageData["shops"] > newPlan.Limits.MaxShops {
			return fmt.Errorf("cannot downgrade: current shops (%d) exceed new plan limit (%d)",
				stats.UsageData["shops"], newPlan.Limits.MaxShops)
		}
		if newPlan.Limits.MaxProducts > 0 && stats.UsageData["products"] > newPlan.Limits.MaxProducts {
			return fmt.Errorf("cannot downgrade: current products (%d) exceed new plan limit (%d)",
				stats.UsageData["products"], newPlan.Limits.MaxProducts)
		}
	}

	return nil
}

func (s *EnhancedPlanManagementService) calculateProration(ctx context.Context, currentSub *models.Subscription, newPlan *ComprehensivePlan, req *PlanChangeRequest) (float64, error) {
	if req.ProrationMethod == "next_cycle" {
		return 0, nil // No immediate proration
	}

	// Calculate remaining time in current period
	now := time.Now()
	totalPeriod := currentSub.CurrentPeriodEnd.Sub(currentSub.CurrentPeriodStart)
	remainingTime := currentSub.CurrentPeriodEnd.Sub(now)

	if remainingTime <= 0 {
		return 0, nil // Period already ended
	}

	// Calculate proration factor
	prorationFactor := float64(remainingTime) / float64(totalPeriod)

	// Calculate amounts
	currentPeriodValue := currentSub.Amount * prorationFactor
	newPeriodValue := newPlan.Price * prorationFactor

	return newPeriodValue - currentPeriodValue, nil
}

func (s *EnhancedPlanManagementService) createProrationInvoice(subscription *models.Subscription, amount float64) models.Invoice {
	now := time.Now()

	return models.Invoice{
		ID:             uuid.New(),
		SubscriptionID: subscription.ID,
		InvoiceNumber:  fmt.Sprintf("PRO-%d", now.Unix()),
		Status:         "open",
		Amount:         amount,
		Currency:       subscription.Currency,
		Total:          amount,
		PeriodStart:    now,
		PeriodEnd:      subscription.CurrentPeriodEnd,
		DueDate:        now.AddDate(0, 0, 7), // 7 days to pay
		CreatedAt:      now,
		UpdatedAt:      now,
	}
}

func (s *EnhancedPlanManagementService) clearPlanCache() {
	// Implementation to clear plan-related cache keys
}

func (s *EnhancedPlanManagementService) clearSubscriptionCache(tenantID uuid.UUID) {
	// Implementation to clear subscription-related cache keys
}
