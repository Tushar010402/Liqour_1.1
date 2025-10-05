package services

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
)

// EnhancedPricingCalculator handles multi-term pricing calculations
type EnhancedPricingCalculator struct {
	basePlan *models.PricingPlan
}

// NewEnhancedPricingCalculator creates a new pricing calculator
func NewEnhancedPricingCalculator(plan *models.PricingPlan) *EnhancedPricingCalculator {
	return &EnhancedPricingCalculator{
		basePlan: plan,
	}
}

// GetAllBillingOptions returns all available billing options for a plan
func (calc *EnhancedPricingCalculator) GetAllBillingOptions() []models.BillingOption {
	baseMonthlyPrice := calc.basePlan.Price

	options := []models.BillingOption{
		{
			TermMonths:        1,
			TermName:          "Monthly",
			BasePrice:         baseMonthlyPrice,
			DiscountPercent:   0,
			EffectivePrice:    baseMonthlyPrice,
			TotalSavings:      0,
			PaymentSchedule:   "Monthly",
			MonthlyEquivalent: baseMonthlyPrice,
		},
		{
			TermMonths:      12,
			TermName:        "Yearly",
			BasePrice:       baseMonthlyPrice * 12,
			DiscountPercent: calc.basePlan.YearlyDiscount,
			EffectivePrice:  calc.calculateDiscountedPrice(baseMonthlyPrice*12, calc.basePlan.YearlyDiscount),
			PaymentSchedule: "Annual",
			RecommendedTag:  "Most Popular",
		},
		{
			TermMonths:      24,
			TermName:        "2-Year",
			BasePrice:       baseMonthlyPrice * 24,
			DiscountPercent: calc.basePlan.TwoYearDiscount,
			EffectivePrice:  calc.calculateDiscountedPrice(baseMonthlyPrice*24, calc.basePlan.TwoYearDiscount),
			PaymentSchedule: "One-time",
		},
		{
			TermMonths:      36,
			TermName:        "3-Year",
			BasePrice:       baseMonthlyPrice * 36,
			DiscountPercent: calc.basePlan.ThreeYearDiscount,
			EffectivePrice:  calc.calculateDiscountedPrice(baseMonthlyPrice*36, calc.basePlan.ThreeYearDiscount),
			PaymentSchedule: "One-time",
			RecommendedTag:  "Best Value",
		},
	}

	// Calculate savings and monthly equivalent for each option
	for i := range options {
		if options[i].TermMonths > 1 {
			monthlyEquivalent := options[i].EffectivePrice / float64(options[i].TermMonths)
			options[i].MonthlyEquivalent = monthlyEquivalent
			options[i].TotalSavings = (baseMonthlyPrice - monthlyEquivalent) * float64(options[i].TermMonths)
		}
	}

	return options
}

// calculateDiscountedPrice applies discount percentage to base price
func (calc *EnhancedPricingCalculator) calculateDiscountedPrice(basePrice, discountPercent float64) float64 {
	return basePrice * (1 - discountPercent/100)
}

// Enhanced plan service methods
func (s *PlanService) GetPlanWithBillingOptions(ctx context.Context, planID uuid.UUID) (*models.PlanWithBillingOptions, error) {
	plan, err := s.GetPlan(ctx, planID)
	if err != nil {
		return nil, err
	}

	calculator := NewEnhancedPricingCalculator(plan)
	options := calculator.GetAllBillingOptions()

	return &models.PlanWithBillingOptions{
		Plan:           plan,
		BillingOptions: options,
	}, nil
}

// GetAllPlansWithBillingOptions returns all plans with their billing options
func (s *PlanService) GetAllPlansWithBillingOptions(ctx context.Context) ([]*models.PlanWithBillingOptions, error) {
	plans, err := s.GetPlans(ctx)
	if err != nil {
		return nil, err
	}

	var plansBilling []*models.PlanWithBillingOptions
	for _, plan := range plans {
		calculator := NewEnhancedPricingCalculator(&plan)
		options := calculator.GetAllBillingOptions()

		plansBilling = append(plansBilling, &models.PlanWithBillingOptions{
			Plan:           &plan,
			BillingOptions: options,
		})
	}

	return plansBilling, nil
}

// UpdatePlanDiscounts updates discount structure for a plan
func (s *PlanService) UpdatePlanDiscounts(ctx context.Context, planID uuid.UUID, req models.UpdatePlanDiscountsRequest) error {
	// Check if plan exists
	_, err := s.GetPlan(ctx, planID)
	if err != nil {
		return err
	}

	// Update discount fields
	updates := map[string]interface{}{
		"yearly_discount":      req.YearlyDiscount,
		"two_year_discount":    req.TwoYearDiscount,
		"three_year_discount":  req.ThreeYearDiscount,
		"auto_create_variants": req.AutoCreateVariants,
		"updated_at":           "NOW()",
	}

	err = s.db.Model(&models.PricingPlan{}).Where("id = ?", planID).Updates(updates).Error
	if err != nil {
		return fmt.Errorf("failed to update plan discounts: %w", err)
	}

	// Auto-create/update billing variants if enabled
	if req.AutoCreateVariants {
		return s.createOrUpdateBillingVariants(ctx, planID)
	}

	return nil
}

// createOrUpdateBillingVariants creates or updates billing variants for a plan
func (s *PlanService) createOrUpdateBillingVariants(ctx context.Context, planID uuid.UUID) error {
	// Get updated plan
	var plan models.PricingPlan
	err := s.db.Where("id = ?", planID).First(&plan).Error
	if err != nil {
		return fmt.Errorf("failed to get plan: %w", err)
	}

	calculator := NewEnhancedPricingCalculator(&plan)
	options := calculator.GetAllBillingOptions()

	// Create or update billing variants
	for _, option := range options {
		variant := models.PlanBillingVariant{
			BasePlanID:         planID,
			BillingTermMonths:  option.TermMonths,
			DiscountPercentage: option.DiscountPercent,
			EffectivePrice:     option.EffectivePrice,
			IsActive:           true,
		}

		// Use ON CONFLICT DO UPDATE equivalent for GORM
		err = s.db.Where("base_plan_id = ? AND billing_term_months = ?", planID, option.TermMonths).
			Assign(map[string]interface{}{
				"discount_percentage": option.DiscountPercent,
				"effective_price":     option.EffectivePrice,
				"is_active":           true,
				"updated_at":          "NOW()",
			}).
			FirstOrCreate(&variant).Error

		if err != nil {
			return fmt.Errorf("failed to create/update billing variant for %d months: %w", option.TermMonths, err)
		}
	}

	return nil
}

// GetPlanBillingVariants returns all billing variants for a plan
func (s *PlanService) GetPlanBillingVariants(ctx context.Context, planID uuid.UUID) ([]models.PlanBillingVariant, error) {
	var variants []models.PlanBillingVariant

	err := s.db.Where("base_plan_id = ? AND is_active = true", planID).
		Order("billing_term_months ASC").
		Find(&variants).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get plan billing variants: %w", err)
	}

	return variants, nil
}

// CalculatePlanPricing calculates pricing for specific term
func (s *PlanService) CalculatePlanPricing(ctx context.Context, planID uuid.UUID, termMonths int) (*models.BillingOption, error) {
	plan, err := s.GetPlan(ctx, planID)
	if err != nil {
		return nil, err
	}

	calculator := NewEnhancedPricingCalculator(plan)
	options := calculator.GetAllBillingOptions()

	// Find the specific term option
	for _, option := range options {
		if option.TermMonths == termMonths {
			return &option, nil
		}
	}

	return nil, fmt.Errorf("billing term %d months not supported for plan %s", termMonths, plan.Name)
}

// ValidateBillingTerm checks if a billing term is valid for a plan
func (s *PlanService) ValidateBillingTerm(ctx context.Context, planID uuid.UUID, termMonths int) error {
	supportedTerms := []int{1, 12, 24, 36}

	for _, term := range supportedTerms {
		if term == termMonths {
			return nil
		}
	}

	return fmt.Errorf("unsupported billing term: %d months. Supported terms: 1, 12, 24, 36", termMonths)
}
