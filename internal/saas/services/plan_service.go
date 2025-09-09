package services

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

type PlanService struct {
	db            *gorm.DB
	config        *config.Config
	paymentClient *RazorpayClient
}

func NewPlanService(db *gorm.DB, cfg *config.Config) *PlanService {
	paymentClient := NewRazorpayClient(cfg)
	return &PlanService{
		db:            db,
		config:        cfg,
		paymentClient: paymentClient,
	}
}

func (s *PlanService) CreatePlan(ctx context.Context, req *models.CreatePlanRequest) (*models.PricingPlan, error) {
	plan := models.PricingPlan{
		ID:             uuid.New(),
		Name:           req.Name,
		DisplayName:    req.DisplayName,
		Description:    req.Description,
		Price:          req.Price,
		Currency:       "INR",
		BillingCycle:   req.BillingCycle,
		TrialDays:      req.TrialDays,
		MaxLocations:   req.MaxLocations,
		MaxUsers:       req.MaxUsers,
		MaxProducts:    req.MaxProducts,
		Features:       req.Features,
		AIFeatures:     req.AIFeatures,
		Popular:        req.Popular,
		Enterprise:     req.Enterprise,
		Active:         req.Active,
		SortOrder:      req.SortOrder,
		YearlyDiscount: req.YearlyDiscount,
	}

	if req.Currency != "" {
		plan.Currency = req.Currency
	}

	// Create plan in database
	if err := s.db.Create(&plan).Error; err != nil {
		return nil, fmt.Errorf("failed to create plan: %w", err)
	}

	// TODO: Create corresponding Razorpay plan
	// razorpayPlanID, err := s.createRazorpayPlan(&plan)
	// if err != nil {
	//     return nil, fmt.Errorf("failed to create razorpay plan: %w", err)
	// }
	// plan.RazorpayPlanID = razorpayPlanID

	return &plan, nil
}

func (s *PlanService) GetPlan(ctx context.Context, id uuid.UUID) (*models.PricingPlan, error) {
	var plan models.PricingPlan
	
	err := s.db.Where("id = ? AND active = true", id).First(&plan).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("plan not found")
		}
		return nil, fmt.Errorf("failed to get plan: %w", err)
	}

	return &plan, nil
}

func (s *PlanService) GetPlans(ctx context.Context) ([]models.PricingPlan, error) {
	var plans []models.PricingPlan
	
	err := s.db.Where("active = true").
		Order("sort_order ASC, price ASC").
		Find(&plans).Error
	
	if err != nil {
		return nil, fmt.Errorf("failed to get plans: %w", err)
	}

	return plans, nil
}

func (s *PlanService) GetPublicPlans(ctx context.Context) ([]models.PricingPlan, error) {
	var plans []models.PricingPlan
	
	err := s.db.Where("active = true").
		Order("sort_order ASC, price ASC").
		Find(&plans).Error
	
	if err != nil {
		return nil, fmt.Errorf("failed to get public plans: %w", err)
	}

	return plans, nil
}

func (s *PlanService) UpdatePlan(ctx context.Context, id uuid.UUID, req *models.CreatePlanRequest) (*models.PricingPlan, error) {
	var plan models.PricingPlan
	
	if err := s.db.First(&plan, id).Error; err != nil {
		return nil, fmt.Errorf("plan not found: %w", err)
	}

	// Update fields
	plan.Name = req.Name
	plan.DisplayName = req.DisplayName
	plan.Description = req.Description
	plan.Price = req.Price
	plan.BillingCycle = req.BillingCycle
	plan.TrialDays = req.TrialDays
	plan.MaxLocations = req.MaxLocations
	plan.MaxUsers = req.MaxUsers
	plan.MaxProducts = req.MaxProducts
	plan.Features = req.Features
	plan.AIFeatures = req.AIFeatures
	plan.Popular = req.Popular
	plan.Enterprise = req.Enterprise
	plan.Active = req.Active
	plan.SortOrder = req.SortOrder
	plan.YearlyDiscount = req.YearlyDiscount

	if req.Currency != "" {
		plan.Currency = req.Currency
	}

	if err := s.db.Save(&plan).Error; err != nil {
		return nil, fmt.Errorf("failed to update plan: %w", err)
	}

	return &plan, nil
}

func (s *PlanService) DeletePlan(ctx context.Context, id uuid.UUID) error {
	// Check if plan has active subscriptions
	var count int64
	err := s.db.Model(&models.Subscription{}).
		Where("plan_id = ? AND status IN ?", id, []string{"active", "trial"}).
		Count(&count).Error
	
	if err != nil {
		return fmt.Errorf("failed to check subscriptions: %w", err)
	}
	
	if count > 0 {
		return fmt.Errorf("cannot delete plan with active subscriptions")
	}

	// Soft delete the plan
	if err := s.db.Delete(&models.PricingPlan{}, id).Error; err != nil {
		return fmt.Errorf("failed to delete plan: %w", err)
	}

	return nil
}

func (s *PlanService) InitializeDefaultPlans(ctx context.Context) error {
	// Check if plans already exist
	var count int64
	if err := s.db.Model(&models.PricingPlan{}).Count(&count).Error; err != nil {
		return fmt.Errorf("failed to count plans: %w", err)
	}

	if count > 0 {
		return nil // Plans already exist
	}

	// Create default plans based on website pricing
	defaultPlans := []models.PricingPlan{
		{
			ID:          uuid.New(),
			Name:        "smart_starter",
			DisplayName: "Smart Starter",
			Description: "Perfect for small businesses getting started with AI-powered liquor inventory management",
			Price:       49.0,
			Currency:    "INR",
			BillingCycle: "monthly",
			TrialDays:   60, // 2 months free trial
			MaxLocations: 1,
			MaxUsers:    10,
			MaxProducts: 1000,
			Features: []string{
				"Basic inventory management",
				"Sales tracking",
				"Simple reports",
				"Mobile app access",
				"Email support",
			},
			AIFeatures: []string{
				"Smart stock alerts",
				"Basic demand forecasting",
			},
			Popular:        false,
			Enterprise:     false,
			Active:         true,
			SortOrder:      1,
			YearlyDiscount: 20.0,
		},
		{
			ID:          uuid.New(),
			Name:        "pro_intelligence",
			DisplayName: "Pro Intelligence",
			Description: "Advanced features for growing businesses with AI-powered insights and analytics",
			Price:       149.0,
			Currency:    "INR",
			BillingCycle: "monthly",
			TrialDays:   60, // 2 months free trial
			MaxLocations: 5,
			MaxUsers:    25,
			MaxProducts: 5000,
			Features: []string{
				"Advanced inventory management",
				"Multi-location support",
				"Comprehensive sales analytics",
				"Custom reports",
				"Priority support",
				"API access",
			},
			AIFeatures: []string{
				"Advanced demand forecasting",
				"Price optimization suggestions",
				"Automated reordering",
				"Trend analysis",
				"Customer behavior insights",
			},
			Popular:        true,
			Enterprise:     false,
			Active:         true,
			SortOrder:      2,
			YearlyDiscount: 20.0,
		},
		{
			ID:          uuid.New(),
			Name:        "enterprise_ai",
			DisplayName: "Enterprise AI",
			Description: "Complete enterprise solution with full AI capabilities and dedicated support",
			Price:       399.0,
			Currency:    "INR",
			BillingCycle: "monthly",
			TrialDays:   60, // 2 months free trial
			MaxLocations: -1, // Unlimited
			MaxUsers:    -1,  // Unlimited
			MaxProducts: -1,  // Unlimited
			Features: []string{
				"Enterprise inventory management",
				"Unlimited locations & users",
				"Advanced analytics & BI",
				"Custom integrations",
				"Dedicated account manager",
				"24/7 phone support",
				"On-premise deployment option",
			},
			AIFeatures: []string{
				"Complete AI suite",
				"Predictive analytics",
				"Custom AI models",
				"Real-time insights",
				"Automated workflows",
				"Advanced forecasting",
				"Market intelligence",
			},
			Popular:        false,
			Enterprise:     true,
			Active:         true,
			SortOrder:      3,
			YearlyDiscount: 20.0,
		},
	}

	// Create plans in database
	for _, plan := range defaultPlans {
		if err := s.db.Create(&plan).Error; err != nil {
			return fmt.Errorf("failed to create default plan %s: %w", plan.Name, err)
		}
	}

	return nil
}

func (s *PlanService) GetPlanFeatures(ctx context.Context, planID uuid.UUID) ([]string, []string, error) {
	var plan models.PricingPlan
	
	err := s.db.Select("features, ai_features").Where("id = ?", planID).First(&plan).Error
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get plan features: %w", err)
	}

	return plan.Features, plan.AIFeatures, nil
}

func (s *PlanService) ValidatePlanLimits(ctx context.Context, planID uuid.UUID, resourceType string, currentCount int) error {
	plan, err := s.GetPlan(ctx, planID)
	if err != nil {
		return fmt.Errorf("failed to get plan: %w", err)
	}

	var limit int
	switch resourceType {
	case "locations":
		limit = plan.MaxLocations
	case "users":
		limit = plan.MaxUsers
	case "products":
		limit = plan.MaxProducts
	default:
		return fmt.Errorf("unknown resource type: %s", resourceType)
	}

	// -1 means unlimited
	if limit != -1 && currentCount >= limit {
		return fmt.Errorf("plan limit exceeded: %s limit is %d, current count is %d", resourceType, limit, currentCount)
	}

	return nil
}

// Helper method to create Razorpay plan (placeholder for future implementation)
func (s *PlanService) createRazorpayPlan(plan *models.PricingPlan) (string, error) {
	// TODO: Implement Razorpay plan creation
	// This would involve creating a plan in Razorpay with the pricing details
	return fmt.Sprintf("rzp_plan_%s", plan.ID.String()), nil
}