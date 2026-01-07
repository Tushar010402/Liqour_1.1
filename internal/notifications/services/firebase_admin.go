package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/option"
)

// FirebaseClient wraps the Firebase Admin SDK for push notifications
type FirebaseClient struct {
	app        *firebase.App
	messaging  *messaging.Client
	enabled    bool
	mu         sync.RWMutex
	projectID  string
	credBytes  []byte
	httpClient *http.Client
}

// Global Firebase client instance
var (
	firebaseClient *FirebaseClient
	firebaseOnce   sync.Once
)

// GetFirebaseClient returns the singleton Firebase client
func GetFirebaseClient() *FirebaseClient {
	firebaseOnce.Do(func() {
		client, err := NewFirebaseClient()
		if err != nil {
			log.Printf("[FIREBASE] Failed to initialize Firebase Admin SDK: %v", err)
			firebaseClient = &FirebaseClient{enabled: false}
		} else if client == nil {
			log.Println("[FIREBASE] Firebase Admin SDK not configured, falling back to legacy FCM")
			firebaseClient = &FirebaseClient{enabled: false}
		} else {
			firebaseClient = client
			log.Println("[FIREBASE] Firebase Admin SDK initialized successfully")
		}
	})
	return firebaseClient
}

// NewFirebaseClient creates a new Firebase Admin SDK client
func NewFirebaseClient() (*FirebaseClient, error) {
	credPath := os.Getenv("FIREBASE_CREDENTIALS_PATH")
	if credPath == "" {
		// No credentials path set, Firebase Admin SDK disabled
		return nil, nil
	}

	// Check if file exists
	if _, err := os.Stat(credPath); os.IsNotExist(err) {
		log.Printf("[FIREBASE] Credentials file not found at %s", credPath)
		return nil, nil
	}

	// Read the credentials file
	credBytes, err := os.ReadFile(credPath)
	if err != nil {
		log.Printf("[FIREBASE] Failed to read credentials file: %v", err)
		return nil, err
	}

	var credData struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(credBytes, &credData); err != nil {
		log.Printf("[FIREBASE] Failed to parse credentials file: %v", err)
		return nil, err
	}

	log.Printf("[FIREBASE] Initializing with project: %s", credData.ProjectID)

	// Create Firebase config with explicit project ID
	config := &firebase.Config{
		ProjectID: credData.ProjectID,
	}

	// Use credentials JSON directly instead of file path
	opt := option.WithCredentialsJSON(credBytes)
	app, err := firebase.NewApp(context.Background(), config, opt)
	if err != nil {
		log.Printf("[FIREBASE] Failed to create Firebase app: %v", err)
		return nil, err
	}

	msgClient, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("[FIREBASE] Failed to get messaging client: %v", err)
		return nil, err
	}

	return &FirebaseClient{
		app:        app,
		messaging:  msgClient,
		enabled:    true,
		projectID:  credData.ProjectID,
		credBytes:  credBytes,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}, nil
}

// IsEnabled returns whether Firebase Admin SDK is enabled
func (f *FirebaseClient) IsEnabled() bool {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.enabled
}

// SendPush sends a push notification using Firebase Admin SDK first, then falls back to HTTP API
func (f *FirebaseClient) SendPush(ctx context.Context, token, title, body string, data map[string]string) (string, error) {
	if !f.IsEnabled() {
		return "", nil
	}

	// Try Firebase Admin SDK first
	log.Printf("[FIREBASE] Trying Firebase Admin SDK Send...")
	result, err := f.SendPushSDK(ctx, token, title, body, data)
	if err == nil {
		log.Printf("[FIREBASE] SDK Send succeeded: %s", result)
		return result, nil
	}
	log.Printf("[FIREBASE] SDK Send failed: %v, trying HTTP API...", err)

	// Fall back to direct HTTP API
	return f.sendPushHTTP(ctx, token, title, body, data)
}

// getNotificationSoundConfig returns channel_id, android sound, and iOS sound based on priority
func getNotificationSoundConfig(priority string) (channelID, androidSound, iosSound string) {
	switch priority {
	case "critical", "urgent":
		return "liquorpro_critical_channel_v2", "critical_alert", "critical_alert.aiff"
	case "high":
		return "liquorpro_alert_channel_v2", "alert_sound", "alert_sound.aiff"
	case "low", "background":
		return "liquorpro_silent_channel_v2", "", "" // Silent
	default: // normal, info, etc.
		return "liquorpro_standard_channel_v2", "notification_sound", "notification_sound.aiff"
	}
}

// sendPushHTTP sends push notification using FCM HTTP v1 API directly
func (f *FirebaseClient) sendPushHTTP(ctx context.Context, token, title, body string, data map[string]string) (string, error) {
	// Get OAuth2 token
	accessToken, err := f.getAccessToken(ctx)
	if err != nil {
		log.Printf("[FIREBASE] Failed to get access token: %v", err)
		return "", fmt.Errorf("failed to get access token: %w", err)
	}

	// Get sound configuration based on priority
	priority := data["priority"]
	channelID, androidSound, iosSound := getNotificationSoundConfig(priority)
	log.Printf("[FIREBASE] Using notification channel: %s, sound: %s (priority: %s)", channelID, androidSound, priority)

	// Build Android notification config
	androidNotification := map[string]interface{}{
		"channel_id":   channelID,
		"click_action": "FLUTTER_NOTIFICATION_CLICK",
	}
	if androidSound != "" {
		androidNotification["sound"] = androidSound
	}

	// Build iOS APS config
	apsConfig := map[string]interface{}{
		"content-available": 1,
		"mutable-content":   1,
	}
	if iosSound != "" {
		apsConfig["sound"] = iosSound
	}

	// Build FCM message
	fcmMessage := map[string]interface{}{
		"message": map[string]interface{}{
			"token": token,
			"notification": map[string]interface{}{
				"title": title,
				"body":  body,
			},
			"data": data,
			"android": map[string]interface{}{
				"priority":     "high",
				"notification": androidNotification,
			},
			"apns": map[string]interface{}{
				"headers": map[string]string{
					"apns-priority": "10",
				},
				"payload": map[string]interface{}{
					"aps": apsConfig,
				},
			},
		},
	}

	jsonBody, err := json.Marshal(fcmMessage)
	if err != nil {
		return "", fmt.Errorf("failed to marshal message: %w", err)
	}

	// Send request to FCM v1 API
	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", f.projectID)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	log.Printf("[FIREBASE] Sending to URL: %s", url)
	log.Printf("[FIREBASE] Auth header prefix: Bearer %s...", accessToken[:50])
	log.Printf("[FIREBASE] Request body: %s", string(jsonBody))

	resp, err := f.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		log.Printf("[FIREBASE] FCM API error: status=%d, body=%s", resp.StatusCode, string(respBody))
		return "", fmt.Errorf("FCM API error: %s", string(respBody))
	}

	// Parse response to get message ID
	var result struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", nil // Still successful, just couldn't parse ID
	}

	log.Printf("[FIREBASE] Push sent successfully: %s", result.Name)
	return result.Name, nil
}

// getAccessToken gets an OAuth2 access token using service account credentials
func (f *FirebaseClient) getAccessToken(ctx context.Context) (string, error) {
	log.Printf("[FIREBASE] Getting OAuth2 token using project: %s", f.projectID)
	creds, err := google.CredentialsFromJSON(ctx, f.credBytes,
		"https://www.googleapis.com/auth/firebase.messaging",
	)
	if err != nil {
		log.Printf("[FIREBASE] Failed to parse credentials JSON: %v", err)
		return "", fmt.Errorf("failed to parse credentials: %w", err)
	}

	token, err := creds.TokenSource.Token()
	if err != nil {
		log.Printf("[FIREBASE] Failed to get OAuth2 token: %v", err)
		return "", fmt.Errorf("failed to get token: %w", err)
	}

	log.Printf("[FIREBASE] OAuth2 token obtained, length: %d, expires: %v", len(token.AccessToken), token.Expiry)
	return token.AccessToken, nil
}

// SendPushSDK sends a push notification using Firebase Admin SDK (fallback)
func (f *FirebaseClient) SendPushSDK(ctx context.Context, token, title, body string, data map[string]string) (string, error) {
	if !f.IsEnabled() || f.messaging == nil {
		return "", nil
	}

	// Get sound configuration based on priority
	priority := data["priority"]
	channelID, androidSound, iosSound := getNotificationSoundConfig(priority)
	log.Printf("[FIREBASE SDK] Using notification channel: %s, sound: %s (priority: %s)", channelID, androidSound, priority)

	// Build Android notification
	androidNotification := &messaging.AndroidNotification{
		ChannelID:   channelID,
		ClickAction: "FLUTTER_NOTIFICATION_CLICK",
	}
	if androidSound != "" {
		androidNotification.Sound = androidSound
	}

	// Build iOS APS
	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
	}
	if iosSound != "" {
		aps.Sound = iosSound
	}

	message := &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority:     "high",
			Notification: androidNotification,
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority": "10",
			},
			Payload: &messaging.APNSPayload{
				Aps: aps,
			},
		},
	}

	return f.messaging.Send(ctx, message)
}

// SendPushToNotification sends a push notification from a Notification model
func (f *FirebaseClient) SendPushToNotification(ctx context.Context, token string, notification *models.Notification) (string, error) {
	if !f.IsEnabled() {
		return "", nil
	}

	// Convert notification data to string map
	dataMap := make(map[string]string)
	if notification.Data != nil {
		var rawData map[string]interface{}
		// Handle different types that notification.Data could be
		switch v := notification.Data.(type) {
		case map[string]interface{}:
			rawData = v
		case []byte:
			json.Unmarshal(v, &rawData)
		case string:
			json.Unmarshal([]byte(v), &rawData)
		default:
			// Try to marshal and unmarshal to get map
			if bytes, err := json.Marshal(v); err == nil {
				json.Unmarshal(bytes, &rawData)
			}
		}
		// Convert interface{} values to strings
		for k, v := range rawData {
			switch val := v.(type) {
			case string:
				dataMap[k] = val
			case float64:
				dataMap[k] = fmt.Sprintf("%v", val)
			default:
				if bytes, err := json.Marshal(v); err == nil {
					dataMap[k] = string(bytes)
				}
			}
		}
	}

	// Add standard notification fields to data
	dataMap["notification_id"] = notification.ID.String()
	dataMap["category"] = string(notification.Category)
	dataMap["priority"] = string(notification.Priority)
	if notification.ActionURL != "" {
		dataMap["action_url"] = notification.ActionURL
	}

	return f.SendPush(ctx, token, notification.Title, notification.Body, dataMap)
}

// SendMulticast sends a push notification to multiple tokens
func (f *FirebaseClient) SendMulticast(ctx context.Context, tokens []string, title, body string, data map[string]string) (*messaging.BatchResponse, error) {
	if !f.IsEnabled() || len(tokens) == 0 {
		return nil, nil
	}

	// Get sound configuration based on priority
	priority := data["priority"]
	channelID, androidSound, iosSound := getNotificationSoundConfig(priority)
	log.Printf("[FIREBASE Multicast] Using notification channel: %s, sound: %s (priority: %s)", channelID, androidSound, priority)

	// Build Android notification
	androidNotification := &messaging.AndroidNotification{
		ChannelID:   channelID,
		ClickAction: "FLUTTER_NOTIFICATION_CLICK",
	}
	if androidSound != "" {
		androidNotification.Sound = androidSound
	}

	// Build iOS APS
	aps := &messaging.Aps{
		ContentAvailable: true,
		MutableContent:   true,
	}
	if iosSound != "" {
		aps.Sound = iosSound
	}

	message := &messaging.MulticastMessage{
		Tokens: tokens,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority:     "high",
			Notification: androidNotification,
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority": "10",
			},
			Payload: &messaging.APNSPayload{
				Aps: aps,
			},
		},
	}

	return f.messaging.SendEachForMulticast(ctx, message)
}

// ValidateToken checks if a registration token is valid
func (f *FirebaseClient) ValidateToken(ctx context.Context, token string) bool {
	if !f.IsEnabled() {
		return true // Assume valid if Firebase not configured
	}

	// Send a dry-run message to validate the token
	message := &messaging.Message{
		Token: token,
		Data: map[string]string{
			"validation": "true",
		},
	}

	_, err := f.messaging.SendDryRun(ctx, message)
	return err == nil
}

// SubscribeToTopic subscribes tokens to a topic
func (f *FirebaseClient) SubscribeToTopic(ctx context.Context, tokens []string, topic string) error {
	if !f.IsEnabled() || len(tokens) == 0 {
		return nil
	}

	_, err := f.messaging.SubscribeToTopic(ctx, tokens, topic)
	return err
}

// UnsubscribeFromTopic unsubscribes tokens from a topic
func (f *FirebaseClient) UnsubscribeFromTopic(ctx context.Context, tokens []string, topic string) error {
	if !f.IsEnabled() || len(tokens) == 0 {
		return nil
	}

	_, err := f.messaging.UnsubscribeFromTopic(ctx, tokens, topic)
	return err
}

// SendToTopic sends a push notification to all devices subscribed to a topic
func (f *FirebaseClient) SendToTopic(ctx context.Context, topic, title, body string, data map[string]string) (string, error) {
	if !f.IsEnabled() {
		return "", nil
	}

	message := &messaging.Message{
		Topic: topic,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{
				"apns-priority": "10",
			},
		},
	}

	return f.messaging.Send(ctx, message)
}
