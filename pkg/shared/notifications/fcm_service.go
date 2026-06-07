package notifications

import (
	"context"
	"fmt"
	"log"
	"os"
	"sync"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// FCMService handles Firebase Cloud Messaging for push notifications
type FCMService struct {
	client *messaging.Client
	mu     sync.RWMutex
}

// NotificationPayload represents a push notification
type NotificationPayload struct {
	Title    string            `json:"title"`
	Body     string            `json:"body"`
	ImageURL string            `json:"image_url,omitempty"`
	Data     map[string]string `json:"data,omitempty"`
	Sound    string            `json:"sound,omitempty"`
	Badge    int               `json:"badge,omitempty"`
}

// NewFCMService creates a new FCM service instance
func NewFCMService() (*FCMService, error) {
	ctx := context.Background()

	// Get credentials path from environment
	credentialsPath := os.Getenv("FIREBASE_CREDENTIALS_PATH")
	if credentialsPath == "" {
		credentialsPath = os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
	}

	if credentialsPath == "" {
		return nil, fmt.Errorf("firebase credentials not configured")
	}

	// Check if file exists
	if _, err := os.Stat(credentialsPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("firebase credentials file not found: %s", credentialsPath)
	}

	opt := option.WithCredentialsFile(credentialsPath)
	app, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize firebase app: %w", err)
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get messaging client: %w", err)
	}

	log.Println("✅ FCM Service initialized successfully")

	return &FCMService{
		client: client,
	}, nil
}

// SendToDevice sends a push notification to a specific device token
func (s *FCMService) SendToDevice(ctx context.Context, token string, payload NotificationPayload) error {
	if token == "" {
		return fmt.Errorf("device token is empty")
	}

	// Build notification
	notification := &messaging.Notification{
		Title: payload.Title,
		Body:  payload.Body,
	}

	if payload.ImageURL != "" {
		notification.ImageURL = payload.ImageURL
	}

	// Build Android config
	androidConfig := &messaging.AndroidConfig{
		Priority: "high",
		Notification: &messaging.AndroidNotification{
			Sound:            getSound(payload.Sound),
			ChannelID:        "liquorpro_notifications",
			DefaultSound:     payload.Sound == "",
			DefaultVibrateTimings: true,
			Priority:         messaging.PriorityHigh,
		},
	}

	// Build APNS (iOS) config
	apnsConfig := &messaging.APNSConfig{
		Headers: map[string]string{
			"apns-priority": "10",
		},
		Payload: &messaging.APNSPayload{
			Aps: &messaging.Aps{
				Alert: &messaging.ApsAlert{
					Title: payload.Title,
					Body:  payload.Body,
				},
				Sound:    getSound(payload.Sound),
				Badge:    &payload.Badge,
				MutableContent: true,
			},
		},
	}

	// Build message
	message := &messaging.Message{
		Token:        token,
		Notification: notification,
		Android:      androidConfig,
		APNS:         apnsConfig,
		Data:         payload.Data,
	}

	// Send message
	response, err := s.client.Send(ctx, message)
	if err != nil {
		log.Printf("❌ [FCM] Failed to send notification to token %s: %v", maskToken(token), err)
		return fmt.Errorf("failed to send notification: %w", err)
	}

	log.Printf("✅ [FCM] Notification sent successfully. Message ID: %s", response)
	return nil
}

// SendToMultipleDevices sends a notification to multiple device tokens
func (s *FCMService) SendToMultipleDevices(ctx context.Context, tokens []string, payload NotificationPayload) (int, int, error) {
	if len(tokens) == 0 {
		return 0, 0, fmt.Errorf("no tokens provided")
	}

	// Build notification
	notification := &messaging.Notification{
		Title: payload.Title,
		Body:  payload.Body,
	}

	if payload.ImageURL != "" {
		notification.ImageURL = payload.ImageURL
	}

	// Build Android config
	androidConfig := &messaging.AndroidConfig{
		Priority: "high",
		Notification: &messaging.AndroidNotification{
			Sound:            getSound(payload.Sound),
			ChannelID:        "liquorpro_notifications",
			DefaultSound:     payload.Sound == "",
			Priority:         messaging.PriorityHigh,
		},
	}

	// Build multicast message
	message := &messaging.MulticastMessage{
		Tokens:       tokens,
		Notification: notification,
		Android:      androidConfig,
		Data:         payload.Data,
	}

	// Send multicast
	response, err := s.client.SendEachForMulticast(ctx, message)
	if err != nil {
		return 0, len(tokens), fmt.Errorf("failed to send multicast notification: %w", err)
	}

	log.Printf("✅ [FCM] Multicast sent. Success: %d, Failure: %d", response.SuccessCount, response.FailureCount)
	return response.SuccessCount, response.FailureCount, nil
}

// SendToTopic sends a notification to all subscribers of a topic
func (s *FCMService) SendToTopic(ctx context.Context, topic string, payload NotificationPayload) error {
	if topic == "" {
		return fmt.Errorf("topic is empty")
	}

	message := &messaging.Message{
		Topic: topic,
		Notification: &messaging.Notification{
			Title: payload.Title,
			Body:  payload.Body,
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Sound:     getSound(payload.Sound),
				ChannelID: "liquorpro_notifications",
			},
		},
		Data: payload.Data,
	}

	response, err := s.client.Send(ctx, message)
	if err != nil {
		return fmt.Errorf("failed to send topic notification: %w", err)
	}

	log.Printf("✅ [FCM] Topic notification sent. Topic: %s, Message ID: %s", topic, response)
	return nil
}

// Helper functions

func getSound(sound string) string {
	if sound == "" {
		return "default"
	}
	return sound
}

func maskToken(token string) string {
	if len(token) <= 10 {
		return "***"
	}
	return token[:5] + "..." + token[len(token)-5:]
}

// NotificationType represents different types of notifications
type NotificationType string

const (
	NotificationTypeCashApproved     NotificationType = "cash_approved"
	NotificationTypeCashRejected     NotificationType = "cash_rejected"
	NotificationTypeCashRequest      NotificationType = "cash_request"
	NotificationTypeSaleApproved     NotificationType = "sale_approved"
	NotificationTypeSaleRejected     NotificationType = "sale_rejected"
	NotificationTypeCollectionDue    NotificationType = "collection_due"
	NotificationTypeNewSaleSubmitted NotificationType = "new_sale_submitted"
)

// BuildNotificationPayload creates a standard notification payload for different event types
func BuildNotificationPayload(notifType NotificationType, data map[string]string) NotificationPayload {
	var title, body string

	switch notifType {
	case NotificationTypeCashApproved:
		amount := data["amount"]
		title = "Cash Submission Approved"
		body = fmt.Sprintf("Your cash submission of ₹%s has been approved", amount)
	case NotificationTypeCashRejected:
		reason := data["reason"]
		title = "Cash Submission Rejected"
		body = fmt.Sprintf("Your cash submission was rejected. Reason: %s", reason)
	case NotificationTypeCashRequest:
		amount := data["amount"]
		requester := data["requester_name"]
		title = "Cash Request"
		body = fmt.Sprintf("%s has requested ₹%s from you", requester, amount)
	case NotificationTypeSaleApproved:
		title = "Sale Record Approved"
		body = "Your daily sale record has been approved"
	case NotificationTypeSaleRejected:
		reason := data["reason"]
		title = "Sale Record Rejected"
		body = fmt.Sprintf("Your sale record was rejected. Reason: %s", reason)
	case NotificationTypeCollectionDue:
		amount := data["amount"]
		title = "Collection Reminder"
		body = fmt.Sprintf("You have ₹%s pending for collection", amount)
	case NotificationTypeNewSaleSubmitted:
		salesman := data["salesman_name"]
		title = "New Sale Submitted"
		body = fmt.Sprintf("%s has submitted a new sale record for approval", salesman)
	default:
		title = "LiquorPro"
		body = "You have a new notification"
	}

	// Add notification type to data for app routing
	if data == nil {
		data = make(map[string]string)
	}
	data["notification_type"] = string(notifType)

	return NotificationPayload{
		Title: title,
		Body:  body,
		Data:  data,
		Sound: "default",
	}
}
