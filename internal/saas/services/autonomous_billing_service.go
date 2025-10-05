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

// AutonomousBillingService handles automated billing operations following industry best practices
type AutonomousBillingService struct {
	db             *gorm.DB
	config         *config.Config
	cache          *cache.Cache
	paymentClient  *RazorpayClient
	emailService   *EmailService
	planService    *EnhancedPlanManagementService
	auditService   *AuditService
	webhookService *WebhookService
}

// BillingEvent represents a billing event
type BillingEvent struct {
	ID             uuid.UUID              `json:"id"`
	Type           string                 `json:"type"` // invoice_created, payment_succeeded, subscription_renewed, etc.
	TenantID       uuid.UUID              `json:"tenant_id"`
	SubscriptionID uuid.UUID              `json:"subscription_id"`
	Data           map[string]interface{} `json:"data"`
	ProcessedAt    time.Time              `json:"processed_at"`
	Status         string                 `json:"status"` // pending, processed, failed
}

// BillingCycleJob represents a scheduled billing operation
type BillingCycleJob struct {
	ID             uuid.UUID `json:"id"`
	Type           string    `json:"type"` // renewal, trial_ending, grace_period, suspension
	SubscriptionID uuid.UUID `json:"subscription_id"`
	ScheduledFor   time.Time `json:"scheduled_for"`
	Status         string    `json:"status"`
	RetryCount     int       `json:"retry_count"`
	MaxRetries     int       `json:"max_retries"`
	LastError      string    `json:"last_error"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// BillingConfiguration holds billing system configuration
type BillingConfiguration struct {
	GracePeriodDays             int   `json:"grace_period_days"`              // Days after failed payment
	DunningEmailDays            []int `json:"dunning_email_days"`             // Days to send dunning emails
	TrialEndingNotificationDays []int `json:"trial_ending_notification_days"` // Days before trial ends
	AutoRetryFailedPayments     bool  `json:"auto_retry_failed_payments"`
	MaxPaymentRetries           int   `json:"max_payment_retries"`
	RetryIntervalHours          []int `json:"retry_interval_hours"` // Hours between retries
	AutoSuspendOnFailure        bool  `json:"auto_suspend_on_failure"`
	InvoiceTermsDays            int   `json:"invoice_terms_days"` // Payment terms
	ProrationEnabled            bool  `json:"proration_enabled"`
	TaxCalculationEnabled       bool  `json:"tax_calculation_enabled"`
	WebhookRetryCount           int   `json:"webhook_retry_count"`
}

// PaymentAttempt tracks payment retry attempts
type PaymentAttempt struct {
	ID            uuid.UUID  `json:"id"`
	PaymentID     uuid.UUID  `json:"payment_id"`
	AttemptNumber int        `json:"attempt_number"`
	Status        string     `json:"status"`
	FailureReason string     `json:"failure_reason"`
	AttemptedAt   time.Time  `json:"attempted_at"`
	NextRetryAt   *time.Time `json:"next_retry_at"`
}

func NewAutonomousBillingService(db *gorm.DB, cfg *config.Config, cache *cache.Cache) *AutonomousBillingService {
	return &AutonomousBillingService{
		db:             db,
		config:         cfg,
		cache:          cache,
		paymentClient:  NewRazorpayClient(cfg),
		emailService:   NewEmailService(cfg),
		planService:    NewEnhancedPlanManagementService(db, cfg, cache),
		auditService:   NewAuditService(db),
		webhookService: NewWebhookService(db, cfg),
	}
}

// StartBillingEngine starts the autonomous billing engine
func (s *AutonomousBillingService) StartBillingEngine(ctx context.Context) {
	log.Println("Starting Autonomous Billing Engine...")

	// Start billing cycle processor
	go s.processBillingCycles(ctx)

	// Start payment retry processor
	go s.processPaymentRetries(ctx)

	// Start subscription status updater
	go s.updateSubscriptionStatuses(ctx)

	// Start dunning email processor
	go s.processDunningEmails(ctx)

	// Start usage tracking
	go s.trackUsageMetrics(ctx)

	log.Println("Autonomous Billing Engine started successfully")
}

// processBillingCycles handles subscription renewals and lifecycle events
func (s *AutonomousBillingService) processBillingCycles(ctx context.Context) {
	ticker := time.NewTicker(1 * time.Hour) // Check every hour
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.processScheduledBillingJobs(ctx)
		}
	}
}

// processScheduledBillingJobs processes jobs that are due
func (s *AutonomousBillingService) processScheduledBillingJobs(ctx context.Context) {
	log.Println("Processing scheduled billing jobs...")

	var jobs []BillingCycleJob
	now := time.Now()

	// Get jobs that are due to be processed
	err := s.db.Table("billing_cycle_jobs").
		Where("scheduled_for <= ? AND status = 'pending' AND retry_count < max_retries", now).
		Order("scheduled_for ASC").
		Limit(100). // Process in batches
		Find(&jobs).Error

	if err != nil {
		log.Printf("Error fetching billing jobs: %v", err)
		return
	}

	for _, job := range jobs {
		if err := s.processBillingJob(ctx, &job); err != nil {
			log.Printf("Error processing billing job %s: %v", job.ID, err)
			s.markJobAsFailed(ctx, &job, err.Error())
		} else {
			s.markJobAsCompleted(ctx, &job)
		}
	}

	// Schedule upcoming billing events
	s.scheduleUpcomingBillingEvents(ctx)
}

// processBillingJob processes a single billing job
func (s *AutonomousBillingService) processBillingJob(ctx context.Context, job *BillingCycleJob) error {
	switch job.Type {
	case "subscription_renewal":
		return s.processSubscriptionRenewal(ctx, job.SubscriptionID)
	case "trial_ending_notification":
		return s.sendTrialEndingNotification(ctx, job.SubscriptionID)
	case "grace_period_notification":
		return s.sendGracePeriodNotification(ctx, job.SubscriptionID)
	case "subscription_suspension":
		return s.suspendSubscription(ctx, job.SubscriptionID)
	case "usage_overage_billing":
		return s.processUsageOverageBilling(ctx, job.SubscriptionID)
	default:
		return fmt.Errorf("unknown job type: %s", job.Type)
	}
}

// processSubscriptionRenewal handles subscription renewal
func (s *AutonomousBillingService) processSubscriptionRenewal(ctx context.Context, subscriptionID uuid.UUID) error {
	var subscription models.Subscription
	if err := s.db.Preload("Plan").First(&subscription, subscriptionID).Error; err != nil {
		return fmt.Errorf("subscription not found: %w", err)
	}

	// Calculate renewal amount
	renewalAmount := subscription.Amount

	// Get usage stats for overage calculation
	usageStats, err := s.planService.GetPlanUsageStats(ctx, subscription.TenantID)
	if err != nil {
		log.Printf("Warning: Could not get usage stats for renewal: %v", err)
	}

	// Add overage charges
	overageAmount := float64(0)
	if usageStats != nil {
		for _, charge := range usageStats.OverageCharges {
			overageAmount += charge
		}
	}

	totalAmount := renewalAmount + overageAmount

	// Create invoice
	invoice := s.createRenewalInvoice(&subscription, renewalAmount, overageAmount)
	if err := s.db.Create(&invoice).Error; err != nil {
		return fmt.Errorf("failed to create renewal invoice: %w", err)
	}

	// Attempt payment
	payment, err := s.attemptSubscriptionPayment(ctx, &subscription, &invoice, totalAmount)
	if err != nil {
		// Payment failed - start dunning process
		s.startDunningProcess(ctx, &subscription, &invoice)
		return fmt.Errorf("payment failed for renewal: %w", err)
	}

	// Payment successful - update subscription
	if err := s.renewSubscription(ctx, &subscription, payment); err != nil {
		return fmt.Errorf("failed to renew subscription: %w", err)
	}

	// Send success notification
	s.sendRenewalSuccessNotification(ctx, &subscription, &invoice)

	// Generate billing event
	s.generateBillingEvent(ctx, "subscription_renewed", subscription.TenantID, subscriptionID, map[string]interface{}{
		"invoice_id": invoice.ID,
		"payment_id": payment.ID,
		"amount":     totalAmount,
	})

	return nil
}

// attemptSubscriptionPayment attempts to charge for a subscription
func (s *AutonomousBillingService) attemptSubscriptionPayment(ctx context.Context, subscription *models.Subscription, invoice *models.Invoice, amount float64) (*models.Payment, error) {
	// Create payment record
	payment := models.Payment{
		ID:             uuid.New(),
		SubscriptionID: subscription.ID,
		InvoiceID:      &invoice.ID,
		Amount:         amount,
		Currency:       subscription.Currency,
		Status:         "pending",
		Description:    fmt.Sprintf("Subscription renewal for %s", subscription.Plan.Name),
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}

	if err := s.db.Create(&payment).Error; err != nil {
		return nil, fmt.Errorf("failed to create payment record: %w", err)
	}

	// Attempt payment through payment gateway
	if subscription.RazorpayCustomerID != "" && subscription.RazorpaySubscriptionID != "" {
		// Use stored payment method
		paymentResult, err := s.paymentClient.ChargeCustomer(ctx, subscription.RazorpayCustomerID, amount, subscription.Currency)
		if err != nil {
			payment.Status = "failed"
			payment.FailureReason = err.Error()
			s.db.Save(&payment)
			return nil, err
		}

		// Update payment with success details
		payment.Status = "succeeded"
		payment.RazorpayPaymentID = paymentResult
		payment.ProcessedAt = &[]time.Time{time.Now()}[0]
		s.db.Save(&payment)

		// Update invoice
		invoice.Status = "paid"
		invoice.PaidAt = payment.ProcessedAt
		s.db.Save(&invoice)

		return &payment, nil
	}

	// No stored payment method - mark as requiring manual payment
	payment.Status = "requires_action"
	payment.FailureReason = "No payment method on file"
	s.db.Save(&payment)

	return nil, fmt.Errorf("no payment method on file for customer")
}

// renewSubscription updates subscription for successful renewal
func (s *AutonomousBillingService) renewSubscription(ctx context.Context, subscription *models.Subscription, payment *models.Payment) error {
	now := time.Now()

	// Calculate next period
	var nextPeriodEnd time.Time
	switch subscription.BillingCycle {
	case "monthly":
		nextPeriodEnd = subscription.CurrentPeriodEnd.AddDate(0, 1, 0)
	case "yearly":
		nextPeriodEnd = subscription.CurrentPeriodEnd.AddDate(1, 0, 0)
	default:
		nextPeriodEnd = subscription.CurrentPeriodEnd.AddDate(0, 1, 0)
	}

	// Update subscription
	subscription.CurrentPeriodStart = subscription.CurrentPeriodEnd
	subscription.CurrentPeriodEnd = nextPeriodEnd
	subscription.Status = "active"
	subscription.NextBillingDate = &nextPeriodEnd
	subscription.UpdatedAt = now

	if err := s.db.Save(subscription).Error; err != nil {
		return err
	}

	// Schedule next renewal
	s.scheduleSubscriptionRenewal(ctx, subscription.ID, nextPeriodEnd)

	return nil
}

// startDunningProcess initiates the dunning process for failed payments
func (s *AutonomousBillingService) startDunningProcess(ctx context.Context, subscription *models.Subscription, invoice *models.Invoice) {
	config := s.getBillingConfiguration()

	// Schedule grace period
	gracePeriodEnd := time.Now().AddDate(0, 0, config.GracePeriodDays)

	// Update subscription status
	subscription.Status = "past_due"
	s.db.Save(subscription)

	// Schedule dunning emails
	for _, days := range config.DunningEmailDays {
		emailDate := time.Now().AddDate(0, 0, days)
		if emailDate.Before(gracePeriodEnd) {
			s.scheduleBillingJob(ctx, "grace_period_notification", subscription.ID, emailDate)
		}
	}

	// Schedule suspension
	s.scheduleBillingJob(ctx, "subscription_suspension", subscription.ID, gracePeriodEnd)

	// Send immediate failed payment notification
	s.sendPaymentFailedNotification(ctx, subscription, invoice)
}

// processPaymentRetries handles automatic payment retries
func (s *AutonomousBillingService) processPaymentRetries(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Minute) // Check every 30 minutes
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.retryFailedPayments(ctx)
		}
	}
}

// retryFailedPayments attempts to retry failed payments
func (s *AutonomousBillingService) retryFailedPayments(ctx context.Context) {
	config := s.getBillingConfiguration()
	if !config.AutoRetryFailedPayments {
		return
	}

	var attempts []PaymentAttempt
	now := time.Now()

	// Get payment attempts that are due for retry
	err := s.db.Table("payment_attempts").
		Where("next_retry_at <= ? AND attempt_number < ? AND status = 'failed'",
			now, config.MaxPaymentRetries).
		Find(&attempts).Error

	if err != nil {
		log.Printf("Error fetching payment retry attempts: %v", err)
		return
	}

	for _, attempt := range attempts {
		s.retryPaymentAttempt(ctx, &attempt)
	}
}

// trackUsageMetrics tracks usage for billing purposes
func (s *AutonomousBillingService) trackUsageMetrics(ctx context.Context) {
	ticker := time.NewTicker(24 * time.Hour) // Track daily
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.recordDailyUsage(ctx)
		}
	}
}

// recordDailyUsage records daily usage for all active subscriptions
func (s *AutonomousBillingService) recordDailyUsage(ctx context.Context) {
	log.Println("Recording daily usage metrics...")

	var subscriptions []models.Subscription
	err := s.db.Where("status IN ?", []string{"active", "trial"}).Find(&subscriptions).Error
	if err != nil {
		log.Printf("Error fetching active subscriptions: %v", err)
		return
	}

	for _, subscription := range subscriptions {
		usageRecord := s.calculateDailyUsage(ctx, subscription.TenantID)
		usageRecord.SubscriptionID = subscription.ID
		usageRecord.RecordDate = time.Now().Truncate(24 * time.Hour) // Start of day

		// Insert or update usage record
		if err := s.db.Create(&usageRecord).Error; err != nil {
			log.Printf("Error recording usage for tenant %s: %v", subscription.TenantID, err)
		}
	}
}

// calculateDailyUsage calculates current usage metrics
func (s *AutonomousBillingService) calculateDailyUsage(ctx context.Context, tenantID uuid.UUID) models.UsageRecord {
	var userCount, shopCount, productCount, salesCount int64

	// Count users
	s.db.Model(&struct{}{}).Table("users").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Count(&userCount)

	// Count shops
	s.db.Model(&struct{}{}).Table("shops").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Count(&shopCount)

	// Count products
	s.db.Model(&struct{}{}).Table("products").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Count(&productCount)

	// Count sales today
	today := time.Now().Truncate(24 * time.Hour)
	s.db.Model(&struct{}{}).Table("sales").
		Where("tenant_id = ? AND created_at >= ? AND deleted_at IS NULL", tenantID, today).Count(&salesCount)

	// Get API usage from cache
	apiUsage := 0
	todayStr := today.Format("2006-01-02")
	cacheKey := fmt.Sprintf("api_usage:%s:%s", tenantID.String(), todayStr)
	var cached interface{}
	if err := s.cache.Get(ctx, cacheKey, &cached); err == nil {
		if cachedStr, ok := cached.(string); ok {
			if err := json.Unmarshal([]byte(cachedStr), &apiUsage); err == nil {
				// Successfully got cached API usage
			}
		}
	}

	return models.UsageRecord{
		ID:          uuid.New(),
		TenantID:    tenantID,
		RecordDate:  today,
		Locations:   int(shopCount),
		Users:       int(userCount),
		Products:    int(productCount),
		Sales:       int(salesCount),
		APIRequests: apiUsage,
		StorageUsed: 0, // Would calculate actual storage usage
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
}

// Helper methods

func (s *AutonomousBillingService) getBillingConfiguration() BillingConfiguration {
	// Return default configuration - in production, this would be configurable
	return BillingConfiguration{
		GracePeriodDays:             7,
		DunningEmailDays:            []int{1, 3, 5, 7},
		TrialEndingNotificationDays: []int{7, 3, 1},
		AutoRetryFailedPayments:     true,
		MaxPaymentRetries:           3,
		RetryIntervalHours:          []int{24, 72, 168}, // 1 day, 3 days, 1 week
		AutoSuspendOnFailure:        true,
		InvoiceTermsDays:            7,
		ProrationEnabled:            true,
		TaxCalculationEnabled:       false,
		WebhookRetryCount:           3,
	}
}

func (s *AutonomousBillingService) createRenewalInvoice(subscription *models.Subscription, baseAmount, overageAmount float64) models.Invoice {
	now := time.Now()
	total := baseAmount + overageAmount

	return models.Invoice{
		ID:             uuid.New(),
		SubscriptionID: subscription.ID,
		InvoiceNumber:  fmt.Sprintf("INV-%d", now.Unix()),
		Status:         "open",
		Amount:         baseAmount,
		Currency:       subscription.Currency,
		Tax:            0, // Calculate tax if enabled
		Discount:       0,
		Total:          total,
		PeriodStart:    subscription.CurrentPeriodEnd,
		PeriodEnd:      subscription.CurrentPeriodEnd.AddDate(0, 1, 0), // Next month
		DueDate:        now.AddDate(0, 0, s.getBillingConfiguration().InvoiceTermsDays),
		Notes:          fmt.Sprintf("Subscription renewal for %s", subscription.Plan.Name),
		CreatedAt:      now,
		UpdatedAt:      now,
	}
}

func (s *AutonomousBillingService) scheduleSubscriptionRenewal(ctx context.Context, subscriptionID uuid.UUID, renewalDate time.Time) {
	s.scheduleBillingJob(ctx, "subscription_renewal", subscriptionID, renewalDate)
}

func (s *AutonomousBillingService) scheduleBillingJob(ctx context.Context, jobType string, subscriptionID uuid.UUID, scheduledFor time.Time) {
	job := BillingCycleJob{
		ID:             uuid.New(),
		Type:           jobType,
		SubscriptionID: subscriptionID,
		ScheduledFor:   scheduledFor,
		Status:         "pending",
		RetryCount:     0,
		MaxRetries:     3,
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}

	s.db.Table("billing_cycle_jobs").Create(&job)
}

func (s *AutonomousBillingService) markJobAsCompleted(ctx context.Context, job *BillingCycleJob) {
	job.Status = "completed"
	job.UpdatedAt = time.Now()
	s.db.Table("billing_cycle_jobs").Save(job)
}

func (s *AutonomousBillingService) markJobAsFailed(ctx context.Context, job *BillingCycleJob, errorMsg string) {
	job.Status = "failed"
	job.LastError = errorMsg
	job.RetryCount++
	job.UpdatedAt = time.Now()
	s.db.Table("billing_cycle_jobs").Save(job)
}

func (s *AutonomousBillingService) generateBillingEvent(ctx context.Context, eventType string, tenantID, subscriptionID uuid.UUID, data map[string]interface{}) {
	event := BillingEvent{
		ID:             uuid.New(),
		Type:           eventType,
		TenantID:       tenantID,
		SubscriptionID: subscriptionID,
		Data:           data,
		ProcessedAt:    time.Now(),
		Status:         "processed",
	}

	// Store event
	eventJSON, _ := json.Marshal(event)
	s.db.Table("billing_events").Create(map[string]interface{}{
		"id":              event.ID,
		"type":            event.Type,
		"tenant_id":       event.TenantID,
		"subscription_id": event.SubscriptionID,
		"data":            string(eventJSON),
		"processed_at":    event.ProcessedAt,
		"status":          event.Status,
	})

	// Send webhooks
	s.webhookService.SendWebhook(eventType, data)
}

// Notification methods (would integrate with email service)
func (s *AutonomousBillingService) sendTrialEndingNotification(ctx context.Context, subscriptionID uuid.UUID) error {
	// Implementation for trial ending notification
	return nil
}

func (s *AutonomousBillingService) sendGracePeriodNotification(ctx context.Context, subscriptionID uuid.UUID) error {
	// Implementation for grace period notification
	return nil
}

func (s *AutonomousBillingService) sendRenewalSuccessNotification(ctx context.Context, subscription *models.Subscription, invoice *models.Invoice) {
	// Implementation for renewal success notification
}

func (s *AutonomousBillingService) sendPaymentFailedNotification(ctx context.Context, subscription *models.Subscription, invoice *models.Invoice) {
	// Implementation for payment failed notification
}

func (s *AutonomousBillingService) suspendSubscription(ctx context.Context, subscriptionID uuid.UUID) error {
	return s.db.Model(&models.Subscription{}).
		Where("id = ?", subscriptionID).
		Update("status", "suspended").Error
}

func (s *AutonomousBillingService) processUsageOverageBilling(ctx context.Context, subscriptionID uuid.UUID) error {
	// Implementation for usage overage billing
	return nil
}

func (s *AutonomousBillingService) updateSubscriptionStatuses(ctx context.Context) {
	ticker := time.NewTicker(6 * time.Hour) // Update every 6 hours
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.updateExpiredSubscriptions(ctx)
		}
	}
}

func (s *AutonomousBillingService) updateExpiredSubscriptions(ctx context.Context) {
	now := time.Now()

	// Update expired subscriptions
	s.db.Model(&models.Subscription{}).
		Where("status IN ? AND current_period_end < ?", []string{"active", "trial"}, now).
		Update("status", "expired")
}

func (s *AutonomousBillingService) processDunningEmails(ctx context.Context) {
	// Process dunning email sequence
	ticker := time.NewTicker(2 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Implementation for dunning email processing
		}
	}
}

func (s *AutonomousBillingService) retryPaymentAttempt(ctx context.Context, attempt *PaymentAttempt) {
	// Implementation for payment retry logic
}

func (s *AutonomousBillingService) scheduleUpcomingBillingEvents(ctx context.Context) {
	// Schedule upcoming renewals, trial endings, etc.
	var subscriptions []models.Subscription
	futureDate := time.Now().AddDate(0, 0, 30) // Look 30 days ahead

	err := s.db.Where("status IN ? AND current_period_end BETWEEN ? AND ?",
		[]string{"active", "trial"}, time.Now(), futureDate).Find(&subscriptions).Error

	if err != nil {
		log.Printf("Error fetching upcoming subscriptions: %v", err)
		return
	}

	for _, sub := range subscriptions {
		// Check if renewal job already exists
		var existingJob BillingCycleJob
		err := s.db.Table("billing_cycle_jobs").
			Where("subscription_id = ? AND type = 'subscription_renewal' AND status = 'pending'", sub.ID).
			First(&existingJob).Error

		if err == gorm.ErrRecordNotFound {
			// Schedule renewal
			s.scheduleSubscriptionRenewal(ctx, sub.ID, sub.CurrentPeriodEnd)
		}

		// Schedule trial ending notifications if in trial
		if sub.Status == "trial" && sub.TrialEnd != nil {
			config := s.getBillingConfiguration()
			for _, days := range config.TrialEndingNotificationDays {
				notificationDate := sub.TrialEnd.AddDate(0, 0, -days)
				if notificationDate.After(time.Now()) {
					s.scheduleBillingJob(ctx, "trial_ending_notification", sub.ID, notificationDate)
				}
			}
		}
	}
}
