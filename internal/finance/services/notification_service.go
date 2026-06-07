package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/notifications"
	"gorm.io/gorm"
)

// NotificationService handles sending push notifications for finance events
type NotificationService struct {
	db         *database.DB
	fcmService *notifications.FCMService
}

// NewNotificationService creates a new notification service
func NewNotificationService(db *database.DB) *NotificationService {
	// Initialize FCM service
	fcmService, err := notifications.NewFCMService()
	if err != nil {
		log.Printf("⚠️ [NotificationService] FCM initialization failed: %v - push notifications disabled", err)
		return &NotificationService{
			db:         db,
			fcmService: nil,
		}
	}

	log.Println("✅ [NotificationService] FCM service initialized successfully")
	return &NotificationService{
		db:         db,
		fcmService: fcmService,
	}
}

// IsEnabled returns true if FCM service is available
func (s *NotificationService) IsEnabled() bool {
	return s.fcmService != nil
}

// SendCashSubmissionApproved sends notification when cash submission is approved
func (s *NotificationService) SendCashSubmissionApproved(ctx context.Context, userID, tenantID uuid.UUID, amount float64, submissionID uuid.UUID) error {
	if !s.IsEnabled() {
		log.Printf("⚠️ [Notification] FCM disabled, skipping cash submission approved notification")
		return nil
	}

	// Get user's FCM tokens
	tokens, err := s.getUserFCMTokens(ctx, userID)
	if err != nil {
		log.Printf("❌ [Notification] Failed to get FCM tokens for user %s: %v", userID, err)
		return err
	}

	if len(tokens) == 0 {
		log.Printf("⚠️ [Notification] No FCM tokens for user %s", userID)
		return nil
	}

	// Build notification
	payload := notifications.BuildNotificationPayload(
		notifications.NotificationTypeCashApproved,
		map[string]string{
			"amount":        fmt.Sprintf("%.2f", amount),
			"submission_id": submissionID.String(),
			"user_id":       userID.String(),
			"tenant_id":     tenantID.String(),
		},
	)

	// Send to all devices
	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Cash submission approved - sent to user %s: success=%d, failure=%d", userID, success, failure)

	// Log the notification
	s.logNotification(ctx, userID, tenantID, "cash_submission_approved", payload, success, failure)

	return err
}

// SendCashSubmissionRejected sends notification when cash submission is rejected
func (s *NotificationService) SendCashSubmissionRejected(ctx context.Context, userID, tenantID uuid.UUID, reason string, submissionID uuid.UUID) error {
	if !s.IsEnabled() {
		log.Printf("⚠️ [Notification] FCM disabled, skipping cash submission rejected notification")
		return nil
	}

	tokens, err := s.getUserFCMTokens(ctx, userID)
	if err != nil {
		return err
	}

	if len(tokens) == 0 {
		return nil
	}

	payload := notifications.BuildNotificationPayload(
		notifications.NotificationTypeCashRejected,
		map[string]string{
			"reason":        reason,
			"submission_id": submissionID.String(),
			"user_id":       userID.String(),
			"tenant_id":     tenantID.String(),
		},
	)

	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Cash submission rejected - sent to user %s: success=%d, failure=%d", userID, success, failure)

	s.logNotification(ctx, userID, tenantID, "cash_submission_rejected", payload, success, failure)

	return err
}

// SendCashRequestReceived sends notification when user receives a cash request
func (s *NotificationService) SendCashRequestReceived(ctx context.Context, toUserID, fromUserID, tenantID uuid.UUID, amount float64, requesterName string, requestID uuid.UUID) error {
	if !s.IsEnabled() {
		return nil
	}

	tokens, err := s.getUserFCMTokens(ctx, toUserID)
	if err != nil {
		return err
	}

	if len(tokens) == 0 {
		return nil
	}

	payload := notifications.BuildNotificationPayload(
		notifications.NotificationTypeCashRequest,
		map[string]string{
			"amount":         fmt.Sprintf("%.2f", amount),
			"requester_name": requesterName,
			"requester_id":   fromUserID.String(),
			"request_id":     requestID.String(),
			"tenant_id":      tenantID.String(),
		},
	)

	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Cash request - sent to user %s: success=%d, failure=%d", toUserID, success, failure)

	s.logNotification(ctx, toUserID, tenantID, "cash_request_received", payload, success, failure)

	return err
}

// SendCashRequestApproved sends notification when cash request is approved
func (s *NotificationService) SendCashRequestApproved(ctx context.Context, userID, tenantID uuid.UUID, amount float64, requestID uuid.UUID) error {
	if !s.IsEnabled() {
		return nil
	}

	tokens, err := s.getUserFCMTokens(ctx, userID)
	if err != nil {
		return err
	}

	if len(tokens) == 0 {
		return nil
	}

	payload := notifications.NotificationPayload{
		Title: "Cash Request Approved",
		Body:  fmt.Sprintf("Your cash request for ₹%.2f has been approved", amount),
		Data: map[string]string{
			"notification_type": "cash_request_approved",
			"amount":            fmt.Sprintf("%.2f", amount),
			"request_id":        requestID.String(),
		},
		Sound: "default",
	}

	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Cash request approved - sent to user %s: success=%d, failure=%d", userID, success, failure)

	s.logNotification(ctx, userID, tenantID, "cash_request_approved", payload, success, failure)

	return err
}

// SendCashRequestRejected sends notification when cash request is rejected
func (s *NotificationService) SendCashRequestRejected(ctx context.Context, userID, tenantID uuid.UUID, reason string, requestID uuid.UUID) error {
	if !s.IsEnabled() {
		return nil
	}

	tokens, err := s.getUserFCMTokens(ctx, userID)
	if err != nil {
		return err
	}

	if len(tokens) == 0 {
		return nil
	}

	payload := notifications.NotificationPayload{
		Title: "Cash Request Rejected",
		Body:  fmt.Sprintf("Your cash request was rejected. Reason: %s", reason),
		Data: map[string]string{
			"notification_type": "cash_request_rejected",
			"reason":            reason,
			"request_id":        requestID.String(),
		},
		Sound: "default",
	}

	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Cash request rejected - sent to user %s: success=%d, failure=%d", userID, success, failure)

	s.logNotification(ctx, userID, tenantID, "cash_request_rejected", payload, success, failure)

	return err
}

// SendCollectionApproved sends notification when collection is approved
func (s *NotificationService) SendCollectionApproved(ctx context.Context, userID, tenantID uuid.UUID, amount float64, collectionID uuid.UUID) error {
	if !s.IsEnabled() {
		return nil
	}

	tokens, err := s.getUserFCMTokens(ctx, userID)
	if err != nil {
		return err
	}

	if len(tokens) == 0 {
		return nil
	}

	payload := notifications.NotificationPayload{
		Title: "Collection Approved",
		Body:  fmt.Sprintf("Your cash collection of ₹%.2f has been approved", amount),
		Data: map[string]string{
			"notification_type": "collection_approved",
			"amount":            fmt.Sprintf("%.2f", amount),
			"collection_id":     collectionID.String(),
		},
		Sound: "default",
	}

	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Collection approved - sent to user %s: success=%d, failure=%d", userID, success, failure)

	s.logNotification(ctx, userID, tenantID, "collection_approved", payload, success, failure)

	return err
}

// SendCollectionRejected sends notification when collection is rejected
func (s *NotificationService) SendCollectionRejected(ctx context.Context, userID, tenantID uuid.UUID, reason string, collectionID uuid.UUID) error {
	if !s.IsEnabled() {
		return nil
	}

	tokens, err := s.getUserFCMTokens(ctx, userID)
	if err != nil {
		return err
	}

	if len(tokens) == 0 {
		return nil
	}

	payload := notifications.NotificationPayload{
		Title: "Collection Rejected",
		Body:  fmt.Sprintf("Your cash collection was rejected. Reason: %s", reason),
		Data: map[string]string{
			"notification_type": "collection_rejected",
			"reason":            reason,
			"collection_id":     collectionID.String(),
		},
		Sound: "default",
	}

	success, failure, err := s.fcmService.SendToMultipleDevices(ctx, tokens, payload)
	log.Printf("✅ [Notification] Collection rejected - sent to user %s: success=%d, failure=%d", userID, success, failure)

	s.logNotification(ctx, userID, tenantID, "collection_rejected", payload, success, failure)

	return err
}

// getUserFCMTokens retrieves active FCM tokens for a user
func (s *NotificationService) getUserFCMTokens(ctx context.Context, userID uuid.UUID) ([]string, error) {
	var tokens []string

	err := s.db.DB.WithContext(ctx).
		Table("notification_devices").
		Where("user_id = ? AND is_active = ?", userID, true).
		Pluck("fcm_token", &tokens).Error

	if err != nil && err != gorm.ErrRecordNotFound {
		return nil, fmt.Errorf("failed to get FCM tokens: %w", err)
	}

	return tokens, nil
}

// logNotification logs the notification to the database
func (s *NotificationService) logNotification(ctx context.Context, userID, tenantID uuid.UUID, notifType string, payload notifications.NotificationPayload, success, failure int) {
	dataJSON, _ := json.Marshal(payload.Data)

	// Insert into notification_deliveries table
	err := s.db.DB.WithContext(ctx).Exec(`
		INSERT INTO notification_deliveries (
			id, notification_id, user_id, tenant_id, channel, status,
			sent_at, success_count, failure_count, created_at, updated_at
		) VALUES (
			gen_random_uuid(), gen_random_uuid(), ?, ?, 'push',
			CASE WHEN ? > 0 THEN 'sent' ELSE 'failed' END,
			?, ?, ?, NOW(), NOW()
		)
	`, userID, tenantID, success, time.Now(), success, failure).Error

	if err != nil {
		log.Printf("⚠️ [Notification] Failed to log notification: %v", err)
	}

	// Also create notification record for in-app display
	err = s.db.DB.WithContext(ctx).Exec(`
		INSERT INTO notifications (
			id, tenant_id, user_id, notification_type, title, message,
			data, status, created_at, updated_at
		) VALUES (
			gen_random_uuid(), ?, ?, ?, ?, ?, ?, 'unread', NOW(), NOW()
		)
	`, tenantID, userID, notifType, payload.Title, payload.Body, string(dataJSON)).Error

	if err != nil {
		log.Printf("⚠️ [Notification] Failed to create notification record: %v", err)
	}
}
