package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

type DiscountService struct {
	db     *gorm.DB
	config *config.Config
}

func NewDiscountService(db *gorm.DB, cfg *config.Config) *DiscountService {
	return &DiscountService{
		db:     db,
		config: cfg,
	}
}

// Global Discount Config Management

func (s *DiscountService) CreateGlobalDiscountConfig(ctx context.Context, req *models.CreateGlobalDiscountConfigRequest) (*models.GlobalDiscountConfig, error) {
	// If setting as default, unset other defaults
	if req.IsDefault {
		if err := s.db.Model(&models.GlobalDiscountConfig{}).Where("is_default = true").Update("is_default", false).Error; err != nil {
			return nil, fmt.Errorf("failed to unset existing default: %w", err)
		}
	}

	config := models.GlobalDiscountConfig{
		ID:                uuid.New(),
		Name:              req.Name,
		Description:       req.Description,
		YearlyDiscount:    req.YearlyDiscount,
		TwoYearDiscount:   req.TwoYearDiscount,
		ThreeYearDiscount: req.ThreeYearDiscount,
		IsDefault:         req.IsDefault,
		IsActive:          true,
	}

	if err := s.db.Create(&config).Error; err != nil {
		return nil, fmt.Errorf("failed to create global discount config: %w", err)
	}

	return &config, nil
}

func (s *DiscountService) GetGlobalDiscountConfigs(ctx context.Context) ([]models.GlobalDiscountConfig, error) {
	var configs []models.GlobalDiscountConfig

	err := s.db.Where("is_active = true").Order("is_default DESC, created_at DESC").Find(&configs).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get global discount configs: %w", err)
	}

	return configs, nil
}

func (s *DiscountService) GetDefaultDiscountConfig(ctx context.Context) (*models.GlobalDiscountConfig, error) {
	var config models.GlobalDiscountConfig

	err := s.db.Where("is_default = true AND is_active = true").First(&config).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil // No default config found
		}
		return nil, fmt.Errorf("failed to get default discount config: %w", err)
	}

	return &config, nil
}

func (s *DiscountService) UpdateGlobalDiscountConfig(ctx context.Context, id uuid.UUID, req *models.UpdateGlobalDiscountConfigRequest) (*models.GlobalDiscountConfig, error) {
	var config models.GlobalDiscountConfig

	if err := s.db.First(&config, id).Error; err != nil {
		return nil, fmt.Errorf("global discount config not found: %w", err)
	}

	// If setting as default, unset other defaults
	if req.IsDefault != nil && *req.IsDefault {
		if err := s.db.Model(&models.GlobalDiscountConfig{}).Where("id != ? AND is_default = true", id).Update("is_default", false).Error; err != nil {
			return nil, fmt.Errorf("failed to unset existing default: %w", err)
		}
	}

	// Update fields
	updates := make(map[string]interface{})
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Description != nil {
		updates["description"] = *req.Description
	}
	if req.YearlyDiscount != nil {
		updates["yearly_discount"] = *req.YearlyDiscount
	}
	if req.TwoYearDiscount != nil {
		updates["two_year_discount"] = *req.TwoYearDiscount
	}
	if req.ThreeYearDiscount != nil {
		updates["three_year_discount"] = *req.ThreeYearDiscount
	}
	if req.IsDefault != nil {
		updates["is_default"] = *req.IsDefault
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}

	if err := s.db.Model(&config).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update global discount config: %w", err)
	}

	return &config, nil
}

func (s *DiscountService) DeleteGlobalDiscountConfig(ctx context.Context, id uuid.UUID) error {
	var config models.GlobalDiscountConfig

	if err := s.db.First(&config, id).Error; err != nil {
		return fmt.Errorf("global discount config not found: %w", err)
	}

	if config.IsDefault {
		return fmt.Errorf("cannot delete default discount config")
	}

	if err := s.db.Delete(&config).Error; err != nil {
		return fmt.Errorf("failed to delete global discount config: %w", err)
	}

	return nil
}

// Plan Discount Override Management

func (s *DiscountService) CreatePlanDiscountOverride(ctx context.Context, req *models.CreatePlanDiscountOverrideRequest, createdBy uuid.UUID) (*models.PlanDiscountOverride, error) {
	// Validate plan exists
	var plan models.PricingPlan
	if err := s.db.First(&plan, req.PlanID).Error; err != nil {
		return nil, fmt.Errorf("plan not found: %w", err)
	}

	// Deactivate existing active overrides for this plan
	if err := s.db.Model(&models.PlanDiscountOverride{}).
		Where("plan_id = ? AND is_active = true", req.PlanID).
		Update("is_active", false).Error; err != nil {
		return nil, fmt.Errorf("failed to deactivate existing overrides: %w", err)
	}

	override := models.PlanDiscountOverride{
		ID:                uuid.New(),
		PlanID:            req.PlanID,
		YearlyDiscount:    req.YearlyDiscount,
		TwoYearDiscount:   req.TwoYearDiscount,
		ThreeYearDiscount: req.ThreeYearDiscount,
		EffectiveFrom:     req.EffectiveFrom,
		EffectiveTo:       req.EffectiveTo,
		Reason:            req.Reason,
		IsActive:          true,
		CreatedBy:         createdBy,
	}

	if err := s.db.Create(&override).Error; err != nil {
		return nil, fmt.Errorf("failed to create plan discount override: %w", err)
	}

	return &override, nil
}

func (s *DiscountService) GetPlanDiscountOverrides(ctx context.Context, planID uuid.UUID) ([]models.PlanDiscountOverride, error) {
	var overrides []models.PlanDiscountOverride

	query := s.db.Where("plan_id = ?", planID).Order("created_at DESC")
	if err := query.Find(&overrides).Error; err != nil {
		return nil, fmt.Errorf("failed to get plan discount overrides: %w", err)
	}

	return overrides, nil
}

func (s *DiscountService) GetActivePlanDiscountOverride(ctx context.Context, planID uuid.UUID) (*models.PlanDiscountOverride, error) {
	var override models.PlanDiscountOverride

	now := time.Now()
	err := s.db.Where("plan_id = ? AND is_active = true AND effective_from <= ? AND (effective_to IS NULL OR effective_to > ?)",
		planID, now, now).First(&override).Error

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil // No active override found
		}
		return nil, fmt.Errorf("failed to get active plan discount override: %w", err)
	}

	return &override, nil
}

func (s *DiscountService) DeactivatePlanDiscountOverride(ctx context.Context, overrideID uuid.UUID) error {
	if err := s.db.Model(&models.PlanDiscountOverride{}).
		Where("id = ?", overrideID).
		Update("is_active", false).Error; err != nil {
		return fmt.Errorf("failed to deactivate plan discount override: %w", err)
	}

	return nil
}

// Billing Term Configuration Management

func (s *DiscountService) GetBillingTermConfigs(ctx context.Context) ([]models.BillingTermConfig, error) {
	var configs []models.BillingTermConfig

	err := s.db.Order("sort_order ASC, term_months ASC").Find(&configs).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get billing term configs: %w", err)
	}

	return configs, nil
}

func (s *DiscountService) UpdateBillingTermConfig(ctx context.Context, termMonths int, req *models.UpdateBillingTermConfigRequest) (*models.BillingTermConfig, error) {
	var config models.BillingTermConfig

	if err := s.db.Where("term_months = ?", termMonths).First(&config).Error; err != nil {
		return nil, fmt.Errorf("billing term config not found: %w", err)
	}

	// Update fields
	updates := make(map[string]interface{})
	if req.TermName != nil {
		updates["term_name"] = *req.TermName
	}
	if req.PaymentSchedule != nil {
		updates["payment_schedule"] = *req.PaymentSchedule
	}
	if req.IsEnabled != nil {
		updates["is_enabled"] = *req.IsEnabled
	}
	if req.SortOrder != nil {
		updates["sort_order"] = *req.SortOrder
	}
	if req.RecommendedTag != nil {
		updates["recommended_tag"] = *req.RecommendedTag
	}
	if req.MinDiscountPercent != nil {
		updates["min_discount_percent"] = *req.MinDiscountPercent
	}
	if req.MaxDiscountPercent != nil {
		updates["max_discount_percent"] = *req.MaxDiscountPercent
	}

	if err := s.db.Model(&config).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update billing term config: %w", err)
	}

	return &config, nil
}

// Bulk Operations

func (s *DiscountService) BulkUpdatePlanDiscounts(ctx context.Context, req *models.BulkDiscountUpdateRequest, createdBy uuid.UUID) error {
	// Validate all plans exist
	var count int64
	if err := s.db.Model(&models.PricingPlan{}).Where("id IN ?", req.PlanIDs).Count(&count).Error; err != nil {
		return fmt.Errorf("failed to validate plans: %w", err)
	}
	if int(count) != len(req.PlanIDs) {
		return fmt.Errorf("one or more plans not found")
	}

	// Start transaction
	tx := s.db.Begin()
	if tx.Error != nil {
		return fmt.Errorf("failed to start transaction: %w", tx.Error)
	}
	defer tx.Rollback()

	now := time.Now()
	effectiveFrom := now
	if !req.ApplyImmediately {
		// Apply from next day if not immediate
		effectiveFrom = now.AddDate(0, 0, 1)
	}

	// Create overrides for each plan
	for _, planID := range req.PlanIDs {
		// Deactivate existing active overrides
		if err := tx.Model(&models.PlanDiscountOverride{}).
			Where("plan_id = ? AND is_active = true", planID).
			Update("is_active", false).Error; err != nil {
			return fmt.Errorf("failed to deactivate existing overrides for plan %s: %w", planID, err)
		}

		// Create new override
		override := models.PlanDiscountOverride{
			ID:                uuid.New(),
			PlanID:            planID,
			YearlyDiscount:    req.YearlyDiscount,
			TwoYearDiscount:   req.TwoYearDiscount,
			ThreeYearDiscount: req.ThreeYearDiscount,
			EffectiveFrom:     effectiveFrom,
			EffectiveTo:       nil, // Indefinite
			Reason:            req.Reason,
			IsActive:          true,
			CreatedBy:         createdBy,
		}

		if err := tx.Create(&override).Error; err != nil {
			return fmt.Errorf("failed to create override for plan %s: %w", planID, err)
		}
	}

	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// Analytics

func (s *DiscountService) GetDiscountAnalytics(ctx context.Context) (*models.DiscountAnalyticsResponse, error) {
	var analytics models.DiscountAnalyticsResponse

	// Total plans
	var totalPlans int64
	if err := s.db.Model(&models.PricingPlan{}).Where("active = true").Count(&totalPlans).Error; err != nil {
		return nil, fmt.Errorf("failed to count total plans: %w", err)
	}
	analytics.TotalPlans = int(totalPlans)

	// Plans with discounts (any discount > 0)
	var plansWithDiscounts int64
	if err := s.db.Model(&models.PricingPlan{}).
		Where("active = true AND (yearly_discount > 0 OR two_year_discount > 0 OR three_year_discount > 0)").
		Count(&plansWithDiscounts).Error; err != nil {
		return nil, fmt.Errorf("failed to count plans with discounts: %w", err)
	}
	analytics.PlansWithDiscounts = int(plansWithDiscounts)

	// Average discounts
	var avgDiscounts struct {
		AvgYearly    float64
		AvgTwoYear   float64
		AvgThreeYear float64
	}

	if err := s.db.Model(&models.PricingPlan{}).
		Where("active = true").
		Select("AVG(yearly_discount) as avg_yearly, AVG(two_year_discount) as avg_two_year, AVG(three_year_discount) as avg_three_year").
		Scan(&avgDiscounts).Error; err != nil {
		return nil, fmt.Errorf("failed to calculate average discounts: %w", err)
	}

	analytics.AverageYearlyDiscount = avgDiscounts.AvgYearly
	analytics.AverageTwoYearDiscount = avgDiscounts.AvgTwoYear
	analytics.AverageThreeYearDiscount = avgDiscounts.AvgThreeYear

	// Calculate revenue impact
	revenueImpact, err := s.calculateRevenueImpact(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate revenue impact: %w", err)
	}
	analytics.RevenueImpact = *revenueImpact

	// Discount distribution (simplified)
	analytics.DiscountDistribution = map[string]int{
		"no_discount":    analytics.TotalPlans - analytics.PlansWithDiscounts,
		"with_discounts": analytics.PlansWithDiscounts,
	}

	return &analytics, nil
}

func (s *DiscountService) calculateRevenueImpact(ctx context.Context) (*models.DiscountRevenueImpact, error) {
	var plans []models.PricingPlan
	if err := s.db.Where("active = true").Find(&plans).Error; err != nil {
		return nil, fmt.Errorf("failed to get plans: %w", err)
	}

	var impact models.DiscountRevenueImpact

	for _, plan := range plans {
		basePrice := plan.Price

		// Monthly revenue (no discount)
		impact.MonthlyRevenue += basePrice

		// Yearly revenue with discount
		yearlyPrice := basePrice * 12 * (1 - plan.YearlyDiscount/100)
		impact.YearlyRevenue += yearlyPrice

		// Two-year revenue with discount
		twoYearPrice := basePrice * 24 * (1 - plan.TwoYearDiscount/100)
		impact.TwoYearRevenue += twoYearPrice

		// Three-year revenue with discount
		threeYearPrice := basePrice * 36 * (1 - plan.ThreeYearDiscount/100)
		impact.ThreeYearRevenue += threeYearPrice

		// Calculate total savings offered
		yearlySavings := (basePrice * 12) - yearlyPrice
		twoYearSavings := (basePrice * 24) - twoYearPrice
		threeYearSavings := (basePrice * 36) - threeYearPrice

		impact.TotalSavingsOffered += yearlySavings + twoYearSavings + threeYearSavings
	}

	// Estimated conversion boost (simplified calculation)
	if impact.MonthlyRevenue > 0 {
		impact.EstimatedConversionBoost = (impact.YearlyRevenue / (impact.MonthlyRevenue * 12)) * 100
	}

	return &impact, nil
}

// Helper method to get effective discount for a plan at a given time
func (s *DiscountService) GetEffectiveDiscounts(ctx context.Context, planID uuid.UUID, at time.Time) (yearly, twoYear, threeYear float64, err error) {
	// Get plan base discounts
	var plan models.PricingPlan
	if err = s.db.First(&plan, planID).Error; err != nil {
		return 0, 0, 0, fmt.Errorf("plan not found: %w", err)
	}

	yearly = plan.YearlyDiscount
	twoYear = plan.TwoYearDiscount
	threeYear = plan.ThreeYearDiscount

	// Check for active override
	var override models.PlanDiscountOverride
	err = s.db.Where("plan_id = ? AND is_active = true AND effective_from <= ? AND (effective_to IS NULL OR effective_to > ?)",
		planID, at, at).First(&override).Error

	if err == nil {
		// Override found, use override values where specified
		if override.YearlyDiscount != nil {
			yearly = *override.YearlyDiscount
		}
		if override.TwoYearDiscount != nil {
			twoYear = *override.TwoYearDiscount
		}
		if override.ThreeYearDiscount != nil {
			threeYear = *override.ThreeYearDiscount
		}
	} else if err != gorm.ErrRecordNotFound {
		return 0, 0, 0, fmt.Errorf("failed to check for overrides: %w", err)
	}

	return yearly, twoYear, threeYear, nil
}

// Initialize default discount configurations
func (s *DiscountService) InitializeDefaultConfigs(ctx context.Context) error {
	// Check if default configs already exist
	var count int64
	if err := s.db.Model(&models.GlobalDiscountConfig{}).Count(&count).Error; err != nil {
		return fmt.Errorf("failed to check existing configs: %w", err)
	}

	if count > 0 {
		return nil // Already initialized
	}

	// Create default discount templates
	defaultConfigs := []models.GlobalDiscountConfig{
		{
			ID:                uuid.New(),
			Name:              "Standard",
			Description:       "Standard discount structure for most plans",
			YearlyDiscount:    20,
			TwoYearDiscount:   30,
			ThreeYearDiscount: 40,
			IsDefault:         true,
			IsActive:          true,
		},
		{
			ID:                uuid.New(),
			Name:              "Aggressive",
			Description:       "Higher discounts to drive conversions",
			YearlyDiscount:    25,
			TwoYearDiscount:   35,
			ThreeYearDiscount: 45,
			IsDefault:         false,
			IsActive:          true,
		},
		{
			ID:                uuid.New(),
			Name:              "Conservative",
			Description:       "Lower discounts for premium positioning",
			YearlyDiscount:    15,
			TwoYearDiscount:   25,
			ThreeYearDiscount: 35,
			IsDefault:         false,
			IsActive:          true,
		},
	}

	// Create billing term configs
	billingTerms := []models.BillingTermConfig{
		{
			ID:                 uuid.New(),
			TermMonths:         1,
			TermName:           "Monthly",
			PaymentSchedule:    "Monthly",
			IsEnabled:          true,
			SortOrder:          1,
			RecommendedTag:     "",
			MinDiscountPercent: 0,
			MaxDiscountPercent: 0,
		},
		{
			ID:                 uuid.New(),
			TermMonths:         12,
			TermName:           "Yearly",
			PaymentSchedule:    "Annual",
			IsEnabled:          true,
			SortOrder:          2,
			RecommendedTag:     "Most Popular",
			MinDiscountPercent: 10,
			MaxDiscountPercent: 50,
		},
		{
			ID:                 uuid.New(),
			TermMonths:         24,
			TermName:           "2-Year",
			PaymentSchedule:    "One-time",
			IsEnabled:          true,
			SortOrder:          3,
			RecommendedTag:     "",
			MinDiscountPercent: 20,
			MaxDiscountPercent: 60,
		},
		{
			ID:                 uuid.New(),
			TermMonths:         36,
			TermName:           "3-Year",
			PaymentSchedule:    "One-time",
			IsEnabled:          true,
			SortOrder:          4,
			RecommendedTag:     "Best Value",
			MinDiscountPercent: 30,
			MaxDiscountPercent: 70,
		},
	}

	// Create default configs
	for _, config := range defaultConfigs {
		if err := s.db.Create(&config).Error; err != nil {
			return fmt.Errorf("failed to create default config %s: %w", config.Name, err)
		}
	}

	// Create billing term configs
	for _, term := range billingTerms {
		if err := s.db.Create(&term).Error; err != nil {
			return fmt.Errorf("failed to create billing term config %d: %w", term.TermMonths, err)
		}
	}

	return nil
}
