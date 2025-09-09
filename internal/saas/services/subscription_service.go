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

type SubscriptionService struct {
	db            *gorm.DB
	config        *config.Config
	paymentClient *RazorpayClient
}

func NewSubscriptionService(db *gorm.DB, cfg *config.Config) *SubscriptionService {
	paymentClient := NewRazorpayClient(cfg)
	return &SubscriptionService{
		db:            db,
		config:        cfg,
		paymentClient: paymentClient,
	}
}

func (s *SubscriptionService) CreateSubscription(ctx context.Context, req *models.CreateSubscriptionRequest) (*models.SubscriptionResponse, error) {
	// Start transaction
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Get the pricing plan
	var plan models.PricingPlan
	if err := tx.First(&plan, req.PlanID).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("plan not found: %w", err)
	}

	// Check if tenant already has active subscription
	var existingSub models.Subscription
	err := tx.Where("tenant_id = ? AND status IN ?", req.TenantID, []string{"active", "trial"}).First(&existingSub).Error
	if err == nil {
		tx.Rollback()
		return nil, fmt.Errorf("tenant already has an active subscription")
	}

	// Calculate subscription details
	now := time.Now()
	trialEnd := now.AddDate(0, 0, plan.TrialDays)
	
	var periodEnd time.Time
	if req.BillingCycle == "yearly" {
		periodEnd = trialEnd.AddDate(1, 0, 0)
	} else {
		periodEnd = trialEnd.AddDate(0, 1, 0)
	}

	// Create subscription
	subscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           req.TenantID,
		PlanID:             req.PlanID,
		Status:             "trial",
		CurrentPeriodStart: now,
		CurrentPeriodEnd:   periodEnd,
		TrialStart:         &now,
		TrialEnd:           &trialEnd,
		BillingCycle:       req.BillingCycle,
		Amount:             plan.Price,
		Currency:           plan.Currency,
		NextBillingDate:    &trialEnd,
		AutoRenew:          req.AutoRenew,
	}

	// Apply yearly discount if applicable
	if req.BillingCycle == "yearly" {
		discountAmount := subscription.Amount * (plan.YearlyDiscount / 100)
		subscription.Amount = subscription.Amount - discountAmount
	}

	if err := tx.Create(&subscription).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create subscription: %w", err)
	}

	// Create Razorpay customer and subscription if not in trial
	if plan.TrialDays == 0 {
		razorpayCustomerID, razorpaySubID, err := s.createRazorpaySubscription(ctx, &subscription, &plan)
		if err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create razorpay subscription: %w", err)
		}
		
		subscription.RazorpayCustomerID = razorpayCustomerID
		subscription.RazorpaySubscriptionID = razorpaySubID
		subscription.Status = "active"
		
		if err := tx.Save(&subscription).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to update subscription with razorpay details: %w", err)
		}
	}

	// Create initial usage record
	usageRecord := models.UsageRecord{
		SubscriptionID: subscription.ID,
		TenantID:       req.TenantID,
		RecordDate:     now,
		Locations:      0,
		Users:          0,
		Products:       0,
		Sales:          0,
		APIRequests:    0,
		StorageUsed:    0,
	}

	if err := tx.Create(&usageRecord).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create usage record: %w", err)
	}

	tx.Commit()

	// Load plan for response
	if err := s.db.Preload("Plan").First(&subscription, subscription.ID).Error; err != nil {
		return nil, fmt.Errorf("failed to load subscription: %w", err)
	}

	return s.toSubscriptionResponse(&subscription), nil
}

func (s *SubscriptionService) GetSubscription(ctx context.Context, tenantID uuid.UUID) (*models.SubscriptionResponse, error) {
	var subscription models.Subscription
	
	err := s.db.Preload("Plan").
		Where("tenant_id = ? AND status IN ?", tenantID, []string{"active", "trial", "suspended"}).
		First(&subscription).Error
	
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("no active subscription found for tenant")
		}
		return nil, fmt.Errorf("failed to get subscription: %w", err)
	}

	return s.toSubscriptionResponse(&subscription), nil
}

func (s *SubscriptionService) UpdateSubscription(ctx context.Context, subID uuid.UUID, req *models.UpdateSubscriptionRequest) (*models.SubscriptionResponse, error) {
	var subscription models.Subscription
	
	if err := s.db.First(&subscription, subID).Error; err != nil {
		return nil, fmt.Errorf("subscription not found: %w", err)
	}

	// Update fields if provided
	if req.AutoRenew != nil {
		subscription.AutoRenew = *req.AutoRenew
	}
	
	if req.Status != "" {
		subscription.Status = req.Status
		if req.Status == "cancelled" {
			now := time.Now()
			subscription.CancelledAt = &now
			subscription.AutoRenew = false
		}
	}

	if err := s.db.Save(&subscription).Error; err != nil {
		return nil, fmt.Errorf("failed to update subscription: %w", err)
	}

	// Load plan for response
	if err := s.db.Preload("Plan").First(&subscription, subscription.ID).Error; err != nil {
		return nil, fmt.Errorf("failed to load subscription: %w", err)
	}

	return s.toSubscriptionResponse(&subscription), nil
}

func (s *SubscriptionService) CancelSubscription(ctx context.Context, subID uuid.UUID) error {
	var subscription models.Subscription
	
	if err := s.db.First(&subscription, subID).Error; err != nil {
		return fmt.Errorf("subscription not found: %w", err)
	}

	// Cancel in Razorpay if applicable
	if subscription.RazorpaySubscriptionID != "" {
		if err := s.paymentClient.CancelSubscription(subscription.RazorpaySubscriptionID); err != nil {
			return fmt.Errorf("failed to cancel razorpay subscription: %w", err)
		}
	}

	// Update subscription
	now := time.Now()
	subscription.Status = "cancelled"
	subscription.CancelledAt = &now
	subscription.AutoRenew = false

	if err := s.db.Save(&subscription).Error; err != nil {
		return fmt.Errorf("failed to cancel subscription: %w", err)
	}

	return nil
}

func (s *SubscriptionService) UpgradeSubscription(ctx context.Context, subID uuid.UUID, newPlanID uuid.UUID) (*models.SubscriptionResponse, error) {
	// Start transaction
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Get current subscription
	var subscription models.Subscription
	if err := tx.Preload("Plan").First(&subscription, subID).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("subscription not found: %w", err)
	}

	// Get new plan
	var newPlan models.PricingPlan
	if err := tx.First(&newPlan, newPlanID).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("new plan not found: %w", err)
	}

	// Validate upgrade (new plan should be higher tier)
	if newPlan.Price <= subscription.Plan.Price {
		tx.Rollback()
		return nil, fmt.Errorf("new plan must be a higher tier")
	}

	// Update subscription
	subscription.PlanID = newPlanID
	subscription.Amount = newPlan.Price
	
	// Apply yearly discount if applicable
	if subscription.BillingCycle == "yearly" {
		discountAmount := subscription.Amount * (newPlan.YearlyDiscount / 100)
		subscription.Amount = subscription.Amount - discountAmount
	}

	if err := tx.Save(&subscription).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update subscription: %w", err)
	}

	// TODO: Handle prorated billing with Razorpay

	tx.Commit()

	// Load updated subscription
	if err := s.db.Preload("Plan").First(&subscription, subscription.ID).Error; err != nil {
		return nil, fmt.Errorf("failed to load updated subscription: %w", err)
	}

	return s.toSubscriptionResponse(&subscription), nil
}

func (s *SubscriptionService) GetUsage(ctx context.Context, subID uuid.UUID) (*models.UsageRecord, error) {
	var usage models.UsageRecord
	
	err := s.db.Where("subscription_id = ?", subID).
		Order("record_date DESC").
		First(&usage).Error
	
	if err != nil {
		return nil, fmt.Errorf("failed to get usage: %w", err)
	}

	return &usage, nil
}

func (s *SubscriptionService) CheckLimits(ctx context.Context, tenantID uuid.UUID, resourceType string, currentCount int) error {
	subscription, err := s.GetSubscription(ctx, tenantID)
	if err != nil {
		return fmt.Errorf("failed to get subscription: %w", err)
	}

	var limit int
	switch resourceType {
	case "locations":
		limit = subscription.Plan.MaxLocations
	case "users":
		limit = subscription.Plan.MaxUsers
	case "products":
		limit = subscription.Plan.MaxProducts
	default:
		return fmt.Errorf("unknown resource type: %s", resourceType)
	}

	// -1 means unlimited
	if limit != -1 && currentCount >= limit {
		return fmt.Errorf("resource limit exceeded: %s limit is %d", resourceType, limit)
	}

	return nil
}

func (s *SubscriptionService) RecordUsage(ctx context.Context, tenantID uuid.UUID, metrics map[string]int) error {
	// Get active subscription
	var subscription models.Subscription
	err := s.db.Where("tenant_id = ? AND status IN ?", tenantID, []string{"active", "trial"}).First(&subscription).Error
	if err != nil {
		return fmt.Errorf("no active subscription found: %w", err)
	}

	// Create or update today's usage record
	today := time.Now().Truncate(24 * time.Hour)
	
	var usage models.UsageRecord
	err = s.db.Where("subscription_id = ? AND record_date = ?", subscription.ID, today).First(&usage).Error
	
	if err == gorm.ErrRecordNotFound {
		// Create new usage record
		usage = models.UsageRecord{
			SubscriptionID: subscription.ID,
			TenantID:       tenantID,
			RecordDate:     today,
		}
	}

	// Update metrics
	if val, ok := metrics["locations"]; ok {
		usage.Locations = val
	}
	if val, ok := metrics["users"]; ok {
		usage.Users = val
	}
	if val, ok := metrics["products"]; ok {
		usage.Products = val
	}
	if val, ok := metrics["sales"]; ok {
		usage.Sales = val
	}
	if val, ok := metrics["api_requests"]; ok {
		usage.APIRequests = val
	}

	// Save usage record
	if err := s.db.Save(&usage).Error; err != nil {
		return fmt.Errorf("failed to record usage: %w", err)
	}

	return nil
}

// Helper methods

func (s *SubscriptionService) createRazorpaySubscription(ctx context.Context, subscription *models.Subscription, plan *models.PricingPlan) (string, string, error) {
	// Create Razorpay customer
	customerID, err := s.paymentClient.CreateCustomer(fmt.Sprintf("tenant-%s", subscription.TenantID))
	if err != nil {
		return "", "", fmt.Errorf("failed to create razorpay customer: %w", err)
	}

	// Create Razorpay subscription
	subID, err := s.paymentClient.CreateSubscription(customerID, plan.RazorpayPlanID)
	if err != nil {
		return "", "", fmt.Errorf("failed to create razorpay subscription: %w", err)
	}

	return customerID, subID, nil
}

func (s *SubscriptionService) toSubscriptionResponse(subscription *models.Subscription) *models.SubscriptionResponse {
	return &models.SubscriptionResponse{
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
}