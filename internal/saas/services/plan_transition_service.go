package services

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"gorm.io/gorm"
)

type PlanTransitionService struct {
	db             *gorm.DB
	cache          *cache.Cache
	cfg            *config.Config
	billingService *AutonomousBillingService
	usageService   *UsageTrackingService
}

type PlanTransitionRequest struct {
	SubscriptionID uuid.UUID  `json:"subscription_id" binding:"required"`
	NewPlanID      uuid.UUID  `json:"new_plan_id" binding:"required"`
	TransitionType string     `json:"transition_type"` // UPGRADE, DOWNGRADE, LATERAL
	EffectiveDate  *time.Time `json:"effective_date,omitempty"`
	ProrationMode  string     `json:"proration_mode"` // IMMEDIATE, END_OF_PERIOD, CUSTOM
	Reason         string     `json:"reason,omitempty"`
}

type PlanTransitionResult struct {
	TransitionID       uuid.UUID              `json:"transition_id"`
	SubscriptionID     uuid.UUID              `json:"subscription_id"`
	OldPlanID          uuid.UUID              `json:"old_plan_id"`
	NewPlanID          uuid.UUID              `json:"new_plan_id"`
	TransitionType     string                 `json:"transition_type"`
	ProrationAmount    float64                `json:"proration_amount"`
	CreditAmount       float64                `json:"credit_amount"`
	NextBillingDate    time.Time              `json:"next_billing_date"`
	EffectiveDate      time.Time              `json:"effective_date"`
	Status             string                 `json:"status"`
	BillingAdjustments []BillingAdjustment    `json:"billing_adjustments"`
	ResourceChanges    ResourceChangesSummary `json:"resource_changes"`
}

type BillingAdjustment struct {
	Type        string    `json:"type"` // PRORATION, CREDIT, CHARGE
	Amount      float64   `json:"amount"`
	Description string    `json:"description"`
	AppliedAt   time.Time `json:"applied_at"`
}

type ResourceChangesSummary struct {
	OldLimits map[string]interface{}  `json:"old_limits"`
	NewLimits map[string]interface{}  `json:"new_limits"`
	Changes   map[string]ChangeDetail `json:"changes"`
}

type ChangeDetail struct {
	OldValue  interface{} `json:"old_value"`
	NewValue  interface{} `json:"new_value"`
	Direction string      `json:"direction"` // INCREASE, DECREASE, UNCHANGED
}

type ProrationCalculation struct {
	DaysUsed         int     `json:"days_used"`
	DaysInPeriod     int     `json:"days_in_period"`
	RemainingDays    int     `json:"remaining_days"`
	OldPlanDailyRate float64 `json:"old_plan_daily_rate"`
	NewPlanDailyRate float64 `json:"new_plan_daily_rate"`
	ProrationAmount  float64 `json:"proration_amount"`
	CreditAmount     float64 `json:"credit_amount"`
}

func NewPlanTransitionService(db *gorm.DB, cache *cache.Cache, cfg *config.Config, billingService *AutonomousBillingService, usageService *UsageTrackingService) *PlanTransitionService {
	return &PlanTransitionService{
		db:             db,
		cache:          cache,
		cfg:            cfg,
		billingService: billingService,
		usageService:   usageService,
	}
}

func (s *PlanTransitionService) InitiatePlanTransition(ctx context.Context, req PlanTransitionRequest) (*PlanTransitionResult, error) {
	// Validate request
	if err := s.validateTransitionRequest(req); err != nil {
		return nil, fmt.Errorf("invalid transition request: %w", err)
	}

	// Get current subscription
	var subscription models.Subscription
	if err := s.db.Where("id = ?", req.SubscriptionID).
		Preload("Plan").
		Preload("Tenant").
		First(&subscription).Error; err != nil {
		return nil, fmt.Errorf("subscription not found: %w", err)
	}

	// Get new plan
	var newPlan models.PricingPlan
	if err := s.db.Where("id = ?", req.NewPlanID).First(&newPlan).Error; err != nil {
		return nil, fmt.Errorf("new plan not found: %w", err)
	}

	// Determine transition type if not provided
	transitionType := req.TransitionType
	if transitionType == "" {
		transitionType = s.determineTransitionType(subscription.Plan, newPlan)
	}

	// Set effective date
	effectiveDate := time.Now()
	if req.EffectiveDate != nil {
		effectiveDate = *req.EffectiveDate
	}

	// Check for usage violations before downgrade
	if transitionType == "DOWNGRADE" {
		if err := s.validateDowngradeEligibility(ctx, subscription.TenantID, newPlan); err != nil {
			return nil, fmt.Errorf("downgrade not eligible: %w", err)
		}
	}

	// Calculate proration
	prorationMode := req.ProrationMode
	if prorationMode == "" {
		prorationMode = "IMMEDIATE"
	}

	proration, err := s.calculateProration(subscription, newPlan, effectiveDate, prorationMode)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate proration: %w", err)
	}

	// Create transition record
	transition := &models.PlanTransition{
		SubscriptionID:  req.SubscriptionID,
		TenantID:        subscription.TenantID,
		OldPlanID:       subscription.PlanID,
		NewPlanID:       req.NewPlanID,
		TransitionType:  transitionType,
		ProrationAmount: proration.ProrationAmount,
		CreditAmount:    proration.CreditAmount,
		EffectiveDate:   effectiveDate,
		Status:          "PENDING",
		Reason:          req.Reason,
		RequestedAt:     time.Now(),
	}

	if err := s.db.Create(transition).Error; err != nil {
		return nil, fmt.Errorf("failed to create transition record: %w", err)
	}

	// Execute the transition
	result, err := s.executePlanTransition(ctx, transition, subscription, newPlan, proration)
	if err != nil {
		// Mark transition as failed
		s.db.Model(transition).Update("status", "FAILED")
		return nil, fmt.Errorf("failed to execute transition: %w", err)
	}

	return result, nil
}

func (s *PlanTransitionService) validateTransitionRequest(req PlanTransitionRequest) error {
	if req.SubscriptionID == uuid.Nil {
		return fmt.Errorf("subscription_id is required")
	}
	if req.NewPlanID == uuid.Nil {
		return fmt.Errorf("new_plan_id is required")
	}

	validTransitionTypes := []string{"UPGRADE", "DOWNGRADE", "LATERAL", ""}
	isValidType := false
	for _, validType := range validTransitionTypes {
		if req.TransitionType == validType {
			isValidType = true
			break
		}
	}
	if !isValidType {
		return fmt.Errorf("invalid transition_type")
	}

	validProrationModes := []string{"IMMEDIATE", "END_OF_PERIOD", "CUSTOM", ""}
	isValidMode := false
	for _, validMode := range validProrationModes {
		if req.ProrationMode == validMode {
			isValidMode = true
			break
		}
	}
	if !isValidMode {
		return fmt.Errorf("invalid proration_mode")
	}

	return nil
}

func (s *PlanTransitionService) determineTransitionType(oldPlan, newPlan models.PricingPlan) string {
	if newPlan.Price > oldPlan.Price {
		return "UPGRADE"
	} else if newPlan.Price < oldPlan.Price {
		return "DOWNGRADE"
	}
	return "LATERAL"
}

func (s *PlanTransitionService) validateDowngradeEligibility(ctx context.Context, tenantID uuid.UUID, newPlan models.PricingPlan) error {
	// Check current usage against new plan limits
	resourceTypes := []string{"users", "shops", "products"}

	for _, resourceType := range resourceTypes {
		currentUsage, err := s.usageService.GetCurrentUsage(ctx, tenantID, resourceType)
		if err != nil {
			log.Printf("Failed to get current usage for %s: %v", resourceType, err)
			continue
		}

		var newLimit int
		switch resourceType {
		case "users":
			newLimit = newPlan.MaxUsers
		case "shops":
			newLimit = newPlan.MaxLocations // shops are locations in this model
		case "products":
			newLimit = newPlan.MaxProducts
		}

		if newLimit > 0 && currentUsage > newLimit {
			return fmt.Errorf("current %s usage (%d) exceeds new plan limit (%d)", resourceType, currentUsage, newLimit)
		}
	}

	return nil
}

func (s *PlanTransitionService) calculateProration(subscription models.Subscription, newPlan models.PricingPlan, effectiveDate time.Time, prorationMode string) (*ProrationCalculation, error) {
	// Get billing cycle information
	var nextBilling time.Time
	if subscription.NextBillingDate != nil {
		nextBilling = *subscription.NextBillingDate
	} else {
		nextBilling = subscription.CurrentPeriodEnd
	}

	currentPeriodStart := subscription.CurrentPeriodStart

	daysInPeriod := int(nextBilling.Sub(currentPeriodStart).Hours() / 24)
	daysUsed := int(effectiveDate.Sub(currentPeriodStart).Hours() / 24)
	remainingDays := daysInPeriod - daysUsed

	if remainingDays < 0 {
		remainingDays = 0
	}

	oldPlanDailyRate := subscription.Amount / float64(daysInPeriod)
	newPlanDailyRate := newPlan.Price / float64(daysInPeriod)

	var prorationAmount, creditAmount float64

	switch prorationMode {
	case "IMMEDIATE":
		// Credit for unused time on old plan
		creditAmount = oldPlanDailyRate * float64(remainingDays)
		// Charge for remaining time on new plan
		prorationAmount = newPlanDailyRate * float64(remainingDays)
		// Net amount to charge/credit
		prorationAmount = prorationAmount - creditAmount

	case "END_OF_PERIOD":
		// No immediate proration, change takes effect at next billing cycle
		prorationAmount = 0
		creditAmount = 0

	case "CUSTOM":
		// Custom proration logic could be implemented here
		// For now, default to immediate
		creditAmount = oldPlanDailyRate * float64(remainingDays)
		prorationAmount = newPlanDailyRate * float64(remainingDays)
		prorationAmount = prorationAmount - creditAmount
	}

	return &ProrationCalculation{
		DaysUsed:         daysUsed,
		DaysInPeriod:     daysInPeriod,
		RemainingDays:    remainingDays,
		OldPlanDailyRate: oldPlanDailyRate,
		NewPlanDailyRate: newPlanDailyRate,
		ProrationAmount:  math.Round(prorationAmount*100) / 100, // Round to 2 decimal places
		CreditAmount:     math.Round(creditAmount*100) / 100,
	}, nil
}

func (s *PlanTransitionService) executePlanTransition(ctx context.Context, transition *models.PlanTransition, subscription models.Subscription, newPlan models.PricingPlan, proration *ProrationCalculation) (*PlanTransitionResult, error) {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// Update subscription
	updateData := map[string]interface{}{
		"plan_id":    newPlan.ID,
		"updated_at": time.Now(),
	}

	// Update pricing if it's an immediate transition
	if transition.EffectiveDate.Before(time.Now().Add(time.Hour)) {
		updateData["price"] = newPlan.Price
	}

	if err := tx.Model(&subscription).Updates(updateData).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update subscription: %w", err)
	}

	// Create billing adjustments if needed
	var adjustments []BillingAdjustment

	if proration.ProrationAmount != 0 {
		adjustmentType := "PRORATION"
		description := fmt.Sprintf("Plan transition proration from plan %s to plan %s", subscription.PlanID.String(), newPlan.ID.String())

		if proration.ProrationAmount < 0 {
			adjustmentType = "CREDIT"
			description = fmt.Sprintf("Credit for plan downgrade from plan %s to plan %s", subscription.PlanID.String(), newPlan.ID.String())
		}

		// Create payment/credit record
		invoice := &models.Invoice{
			SubscriptionID: subscription.ID,
			Amount:         math.Abs(proration.ProrationAmount),
			Status:         "PENDING",
			DueDate:        time.Now().AddDate(0, 0, 7), // 7 days to pay
			Notes:          description,
		}

		if err := tx.Create(invoice).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create invoice: %w", err)
		}

		adjustments = append(adjustments, BillingAdjustment{
			Type:        adjustmentType,
			Amount:      proration.ProrationAmount,
			Description: description,
			AppliedAt:   time.Now(),
		})
	}

	// Update resource limits in cache
	if err := s.updateResourceLimitsCache(subscription.TenantID, newPlan); err != nil {
		log.Printf("Failed to update resource limits cache: %v", err)
		// Don't fail the transaction for cache issues
	}

	// Create transition history record
	transitionHistory := &models.PlanTransitionHistory{
		TransitionID:    transition.ID,
		SubscriptionID:  subscription.ID,
		TenantID:        subscription.TenantID,
		OldPlanID:       subscription.PlanID,
		NewPlanID:       newPlan.ID,
		TransitionType:  transition.TransitionType,
		ProrationAmount: proration.ProrationAmount,
		EffectiveDate:   transition.EffectiveDate,
		ProcessedAt:     time.Now(),
		Status:          "COMPLETED",
	}

	if err := tx.Create(transitionHistory).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create transition history: %w", err)
	}

	// Update transition status
	if err := tx.Model(transition).Updates(map[string]interface{}{
		"status":      "COMPLETED",
		"executed_at": time.Now(),
	}).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update transition status: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Prepare resource changes summary
	resourceChanges, err := s.buildResourceChangesSummary(subscription.Plan, newPlan)
	if err != nil {
		log.Printf("Failed to build resource changes summary: %v", err)
	}

	// Calculate next billing date
	var nextBillingDate time.Time
	if subscription.NextBillingDate != nil {
		nextBillingDate = *subscription.NextBillingDate
	} else {
		nextBillingDate = subscription.CurrentPeriodEnd
	}

	if transition.EffectiveDate.Before(time.Now().Add(time.Hour)) {
		// Immediate transition - keep the same billing date
		// The proration handles the billing adjustment
	}

	result := &PlanTransitionResult{
		TransitionID:       transition.ID,
		SubscriptionID:     subscription.ID,
		OldPlanID:          subscription.PlanID,
		NewPlanID:          newPlan.ID,
		TransitionType:     transition.TransitionType,
		ProrationAmount:    proration.ProrationAmount,
		CreditAmount:       proration.CreditAmount,
		NextBillingDate:    nextBillingDate,
		EffectiveDate:      transition.EffectiveDate,
		Status:             "COMPLETED",
		BillingAdjustments: adjustments,
		ResourceChanges:    *resourceChanges,
	}

	// Trigger post-transition hooks
	go s.triggerPostTransitionHooks(ctx, result)

	return result, nil
}

func (s *PlanTransitionService) buildResourceChangesSummary(oldPlan, newPlan models.PricingPlan) (*ResourceChangesSummary, error) {
	// Build limits maps from plan fields
	oldLimits := map[string]interface{}{
		"max_users":     oldPlan.MaxUsers,
		"max_locations": oldPlan.MaxLocations,
		"max_products":  oldPlan.MaxProducts,
	}

	newLimits := map[string]interface{}{
		"max_users":     newPlan.MaxUsers,
		"max_locations": newPlan.MaxLocations,
		"max_products":  newPlan.MaxProducts,
	}

	changes := make(map[string]ChangeDetail)

	// Compare limits
	resourceFields := []string{"max_users", "max_locations", "max_products"}

	for _, field := range resourceFields {
		oldVal := oldLimits[field]
		newVal := newLimits[field]

		var direction string
		if oldVal == newVal {
			direction = "UNCHANGED"
		} else if newVal != nil && oldVal != nil {
			if newVal.(float64) > oldVal.(float64) {
				direction = "INCREASE"
			} else {
				direction = "DECREASE"
			}
		}

		changes[field] = ChangeDetail{
			OldValue:  oldVal,
			NewValue:  newVal,
			Direction: direction,
		}
	}

	return &ResourceChangesSummary{
		OldLimits: oldLimits,
		NewLimits: newLimits,
		Changes:   changes,
	}, nil
}

func (s *PlanTransitionService) updateResourceLimitsCache(tenantID uuid.UUID, newPlan models.PricingPlan) error {
	cacheKey := fmt.Sprintf("plan_limits:%s", tenantID.String())

	limits := map[string]interface{}{
		"max_users":     newPlan.MaxUsers,
		"max_locations": newPlan.MaxLocations,
		"max_products":  newPlan.MaxProducts,
	}

	// Cache for 24 hours
	return s.cache.Set(context.Background(), cacheKey, limits, 24*time.Hour)
}

func (s *PlanTransitionService) triggerPostTransitionHooks(ctx context.Context, result *PlanTransitionResult) {
	// Send notification emails
	log.Printf("Plan transition completed for subscription %s", result.SubscriptionID.String())

	// Update usage quotas
	// Trigger analytics events
	// Send webhooks to external systems
	// etc.
}

func (s *PlanTransitionService) GetTransitionHistory(ctx context.Context, subscriptionID uuid.UUID) ([]models.PlanTransitionHistory, error) {
	var history []models.PlanTransitionHistory

	if err := s.db.Where("subscription_id = ?", subscriptionID).
		Order("processed_at DESC").
		Find(&history).Error; err != nil {
		return nil, fmt.Errorf("failed to get transition history: %w", err)
	}

	return history, nil
}

func (s *PlanTransitionService) CancelPendingTransition(ctx context.Context, transitionID uuid.UUID) error {
	var transition models.PlanTransition
	if err := s.db.Where("id = ? AND status = ?", transitionID, "PENDING").First(&transition).Error; err != nil {
		return fmt.Errorf("pending transition not found: %w", err)
	}

	return s.db.Model(&transition).Updates(map[string]interface{}{
		"status":      "CANCELLED",
		"executed_at": time.Now(),
	}).Error
}
