package services

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

type PaymentService struct {
	db            *gorm.DB
	config        *config.Config
	paymentClient *RazorpayClient
}

func NewPaymentService(db *gorm.DB, cfg *config.Config) *PaymentService {
	paymentClient := NewRazorpayClient(cfg)
	return &PaymentService{
		db:            db,
		config:        cfg,
		paymentClient: paymentClient,
	}
}

func (s *PaymentService) CreatePayment(ctx context.Context, req *models.CreatePaymentRequest) (*models.Payment, error) {
	// Get subscription details
	var subscription models.Subscription
	if err := s.db.First(&subscription, req.SubscriptionID).Error; err != nil {
		return nil, fmt.Errorf("subscription not found: %w", err)
	}

	// Create Razorpay order
	amountInPaise := int64(req.Amount * 100) // Convert to paise
	receipt := fmt.Sprintf("payment_%s_%d", req.SubscriptionID.String()[:8], time.Now().Unix())
	
	orderID, err := s.paymentClient.CreateOrder(amountInPaise, req.Currency, receipt)
	if err != nil {
		return nil, fmt.Errorf("failed to create razorpay order: %w", err)
	}

	// Create payment record
	payment := models.Payment{
		ID:                uuid.New(),
		SubscriptionID:    req.SubscriptionID,
		Amount:            req.Amount,
		Currency:          req.Currency,
		Status:            "pending",
		PaymentMethod:     req.PaymentMethod,
		RazorpayOrderID:   orderID,
		Description:       req.Description,
	}

	if req.Currency == "" {
		payment.Currency = "INR"
	}

	if err := s.db.Create(&payment).Error; err != nil {
		return nil, fmt.Errorf("failed to create payment: %w", err)
	}

	return &payment, nil
}

func (s *PaymentService) GetPayment(ctx context.Context, id uuid.UUID) (*models.Payment, error) {
	var payment models.Payment
	
	err := s.db.Preload("Subscription").Preload("Invoice").First(&payment, id).Error
	if err != nil {
		return nil, fmt.Errorf("payment not found: %w", err)
	}

	return &payment, nil
}

func (s *PaymentService) GetPaymentsBySubscription(ctx context.Context, subscriptionID uuid.UUID, limit, offset int) ([]models.Payment, int64, error) {
	var payments []models.Payment
	var total int64

	// Get total count
	if err := s.db.Model(&models.Payment{}).Where("subscription_id = ?", subscriptionID).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count payments: %w", err)
	}

	// Get payments with pagination
	err := s.db.Where("subscription_id = ?", subscriptionID).
		Preload("Invoice").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&payments).Error

	if err != nil {
		return nil, 0, fmt.Errorf("failed to get payments: %w", err)
	}

	return payments, total, nil
}

func (s *PaymentService) UpdatePaymentStatus(ctx context.Context, paymentID uuid.UUID, status string, razorpayPaymentID string) error {
	var payment models.Payment
	
	if err := s.db.First(&payment, paymentID).Error; err != nil {
		return fmt.Errorf("payment not found: %w", err)
	}

	payment.Status = status
	payment.RazorpayPaymentID = razorpayPaymentID

	if status == "succeeded" {
		now := time.Now()
		payment.ProcessedAt = &now
	}

	if err := s.db.Save(&payment).Error; err != nil {
		return fmt.Errorf("failed to update payment: %w", err)
	}

	// If payment succeeded, update subscription status
	if status == "succeeded" {
		if err := s.handleSuccessfulPayment(&payment); err != nil {
			return fmt.Errorf("failed to handle successful payment: %w", err)
		}
	}

	return nil
}

func (s *PaymentService) RefundPayment(ctx context.Context, paymentID uuid.UUID, amount float64, reason string) (*models.Payment, error) {
	var payment models.Payment
	
	if err := s.db.First(&payment, paymentID).Error; err != nil {
		return nil, fmt.Errorf("payment not found: %w", err)
	}

	if payment.Status != "succeeded" {
		return nil, fmt.Errorf("can only refund successful payments")
	}

	if payment.RazorpayPaymentID == "" {
		return nil, fmt.Errorf("no razorpay payment ID found")
	}

	// Process refund with Razorpay
	amountInPaise := int64(amount * 100)
	refundData, err := s.paymentClient.RefundPayment(payment.RazorpayPaymentID, amountInPaise)
	if err != nil {
		return nil, fmt.Errorf("failed to process refund with razorpay: %w", err)
	}

	// Update payment record
	payment.Status = "refunded"
	payment.RefundAmount = amount
	payment.RefundReason = reason
	now := time.Now()
	payment.RefundedAt = &now

	if refundID, ok := refundData["id"].(string); ok {
		// Store refund ID in notes or create separate refund table if needed
		payment.Description += fmt.Sprintf(" (Refund ID: %s)", refundID)
	}

	if err := s.db.Save(&payment).Error; err != nil {
		return nil, fmt.Errorf("failed to update payment: %w", err)
	}

	return &payment, nil
}

func (s *PaymentService) HandleWebhook(ctx context.Context, eventType string, payload []byte) error {
	// Parse webhook payload
	var webhookPayload models.RazorpayWebhookPayload
	if err := json.Unmarshal(payload, &webhookPayload); err != nil {
		return fmt.Errorf("failed to parse webhook payload: %w", err)
	}

	// Create webhook event record
	webhookEvent := models.WebhookEvent{
		ID:        uuid.New(),
		Provider:  "razorpay",
		EventType: eventType,
		EventID:   fmt.Sprintf("evt_%d", time.Now().Unix()),
		Status:    "pending",
		Payload:   string(payload),
	}

	if err := s.db.Create(&webhookEvent).Error; err != nil {
		return fmt.Errorf("failed to create webhook event: %w", err)
	}

	// Process webhook based on event type
	switch eventType {
	case "payment.captured":
		err := s.handlePaymentCaptured(&webhookPayload)
		if err != nil {
			webhookEvent.Status = "failed"
			webhookEvent.ErrorMessage = err.Error()
		} else {
			webhookEvent.Status = "processed"
			now := time.Now()
			webhookEvent.ProcessedAt = &now
		}

	case "payment.failed":
		err := s.handlePaymentFailed(&webhookPayload)
		if err != nil {
			webhookEvent.Status = "failed"
			webhookEvent.ErrorMessage = err.Error()
		} else {
			webhookEvent.Status = "processed"
			now := time.Now()
			webhookEvent.ProcessedAt = &now
		}

	case "subscription.charged":
		err := s.handleSubscriptionCharged(&webhookPayload)
		if err != nil {
			webhookEvent.Status = "failed"
			webhookEvent.ErrorMessage = err.Error()
		} else {
			webhookEvent.Status = "processed"
			now := time.Now()
			webhookEvent.ProcessedAt = &now
		}

	default:
		// Unknown event type, mark as processed but don't handle
		webhookEvent.Status = "processed"
		now := time.Now()
		webhookEvent.ProcessedAt = &now
	}

	// Update webhook event status
	if err := s.db.Save(&webhookEvent).Error; err != nil {
		return fmt.Errorf("failed to update webhook event: %w", err)
	}

	return nil
}

func (s *PaymentService) handlePaymentCaptured(payload *models.RazorpayWebhookPayload) error {
	// Find payment by Razorpay payment ID
	var payment models.Payment
	err := s.db.Where("razorpay_payment_id = ?", payload.Payload.Payment.ID).First(&payment).Error
	if err != nil {
		return fmt.Errorf("payment not found for razorpay ID %s: %w", payload.Payload.Payment.ID, err)
	}

	// Update payment status
	payment.Status = "succeeded"
	payment.PaymentMethod = payload.Payload.Payment.Method
	now := time.Now()
	payment.ProcessedAt = &now

	if err := s.db.Save(&payment).Error; err != nil {
		return fmt.Errorf("failed to update payment status: %w", err)
	}

	// Handle successful payment
	return s.handleSuccessfulPayment(&payment)
}

func (s *PaymentService) handlePaymentFailed(payload *models.RazorpayWebhookPayload) error {
	// Find payment by Razorpay payment ID
	var payment models.Payment
	err := s.db.Where("razorpay_payment_id = ?", payload.Payload.Payment.ID).First(&payment).Error
	if err != nil {
		return fmt.Errorf("payment not found for razorpay ID %s: %w", payload.Payload.Payment.ID, err)
	}

	// Update payment status
	payment.Status = "failed"
	payment.FailureReason = "Payment failed via webhook"

	if err := s.db.Save(&payment).Error; err != nil {
		return fmt.Errorf("failed to update payment status: %w", err)
	}

	return nil
}

func (s *PaymentService) handleSubscriptionCharged(payload *models.RazorpayWebhookPayload) error {
	// Find subscription by Razorpay subscription ID
	var subscription models.Subscription
	err := s.db.Where("razorpay_subscription_id = ?", payload.Payload.Subscription.ID).First(&subscription).Error
	if err != nil {
		return fmt.Errorf("subscription not found for razorpay ID %s: %w", payload.Payload.Subscription.ID, err)
	}

	// Create payment record for the charge
	amountInRupees := float64(payload.Payload.Payment.Amount) / 100 // Convert from paise
	payment := models.Payment{
		ID:                uuid.New(),
		SubscriptionID:    subscription.ID,
		Amount:            amountInRupees,
		Currency:          "INR",
		Status:            "succeeded",
		PaymentMethod:     payload.Payload.Payment.Method,
		RazorpayPaymentID: payload.Payload.Payment.ID,
		Description:       "Subscription renewal",
	}

	now := time.Now()
	payment.ProcessedAt = &now

	if err := s.db.Create(&payment).Error; err != nil {
		return fmt.Errorf("failed to create payment record: %w", err)
	}

	// Handle successful payment
	return s.handleSuccessfulPayment(&payment)
}

func (s *PaymentService) handleSuccessfulPayment(payment *models.Payment) error {
	// Get subscription
	var subscription models.Subscription
	if err := s.db.First(&subscription, payment.SubscriptionID).Error; err != nil {
		return fmt.Errorf("subscription not found: %w", err)
	}

	// If subscription is in trial, activate it
	if subscription.Status == "trial" {
		subscription.Status = "active"
		if err := s.db.Save(&subscription).Error; err != nil {
			return fmt.Errorf("failed to activate subscription: %w", err)
		}
	}

	// Create invoice if needed
	if payment.InvoiceID == nil {
		invoice, err := s.createInvoice(&subscription, payment)
		if err != nil {
			return fmt.Errorf("failed to create invoice: %w", err)
		}
		payment.InvoiceID = &invoice.ID
		if err := s.db.Save(payment).Error; err != nil {
			return fmt.Errorf("failed to update payment with invoice ID: %w", err)
		}
	}

	return nil
}

func (s *PaymentService) createInvoice(subscription *models.Subscription, payment *models.Payment) (*models.Invoice, error) {
	invoiceNumber := fmt.Sprintf("INV-%s-%d", subscription.ID.String()[:8], time.Now().Unix())
	
	invoice := models.Invoice{
		ID:             uuid.New(),
		SubscriptionID: subscription.ID,
		InvoiceNumber:  invoiceNumber,
		Status:         "paid",
		Amount:         payment.Amount,
		Currency:       payment.Currency,
		Tax:            0, // TODO: Calculate tax based on location
		Discount:       0,
		Total:          payment.Amount,
		PeriodStart:    subscription.CurrentPeriodStart,
		PeriodEnd:      subscription.CurrentPeriodEnd,
		DueDate:        time.Now(),
		BillingName:    fmt.Sprintf("Tenant %s", subscription.TenantID),
		BillingEmail:   fmt.Sprintf("billing@tenant-%s.liquorpro.com", subscription.TenantID),
		Notes:          "Generated automatically on payment success",
	}

	now := time.Now()
	invoice.PaidAt = &now

	if err := s.db.Create(&invoice).Error; err != nil {
		return nil, fmt.Errorf("failed to create invoice: %w", err)
	}

	return &invoice, nil
}

func (s *PaymentService) GetInvoices(ctx context.Context, subscriptionID uuid.UUID, limit, offset int) ([]models.Invoice, int64, error) {
	var invoices []models.Invoice
	var total int64

	// Get total count
	if err := s.db.Model(&models.Invoice{}).Where("subscription_id = ?", subscriptionID).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count invoices: %w", err)
	}

	// Get invoices with pagination
	err := s.db.Where("subscription_id = ?", subscriptionID).
		Preload("Payments").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&invoices).Error

	if err != nil {
		return nil, 0, fmt.Errorf("failed to get invoices: %w", err)
	}

	return invoices, total, nil
}

func (s *PaymentService) GetInvoice(ctx context.Context, id uuid.UUID) (*models.Invoice, error) {
	var invoice models.Invoice
	
	err := s.db.Preload("Subscription").Preload("Payments").First(&invoice, id).Error
	if err != nil {
		return nil, fmt.Errorf("invoice not found: %w", err)
	}

	return &invoice, nil
}