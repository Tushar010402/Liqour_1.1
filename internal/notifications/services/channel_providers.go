package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// =====================================================
// In-App Notification Provider
// =====================================================

type InAppProvider struct {
	enabled bool
}

func NewInAppProvider() *InAppProvider {
	return &InAppProvider{enabled: true}
}

func (p *InAppProvider) Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	// In-app notifications are just stored in DB
	// They'll be fetched via API
	return &models.NotificationDelivery{
		Status: models.DeliveryStatusDelivered,
	}, nil
}

func (p *InAppProvider) GetName() string {
	return "in_app"
}

func (p *InAppProvider) IsEnabled() bool {
	return p.enabled
}

// =====================================================
// Push Notification Provider (Firebase)
// Uses Firebase Admin SDK if available, falls back to legacy FCM
// =====================================================

type PushProvider struct {
	enabled        bool
	useAdminSDK    bool
	firebaseClient *FirebaseClient
	fcmKey         string
	fcmEndpoint    string
}

func NewPushProvider() *PushProvider {
	// Try Firebase Admin SDK first
	firebaseClient := GetFirebaseClient()
	if firebaseClient != nil && firebaseClient.IsEnabled() {
		return &PushProvider{
			enabled:        true,
			useAdminSDK:    true,
			firebaseClient: firebaseClient,
		}
	}

	// Fall back to legacy FCM server key
	key := os.Getenv("FCM_SERVER_KEY")
	return &PushProvider{
		enabled:     key != "",
		useAdminSDK: false,
		fcmKey:      key,
		fcmEndpoint: "https://fcm.googleapis.com/fcm/send",
	}
}

func (p *PushProvider) Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	if !p.enabled {
		return nil, fmt.Errorf("push notifications not configured")
	}

	// Use Firebase Admin SDK if available
	if p.useAdminSDK && p.firebaseClient != nil {
		messageID, err := p.firebaseClient.SendPushToNotification(ctx, recipient, notification)
		if err != nil {
			return nil, fmt.Errorf("Firebase Admin SDK error: %w", err)
		}
		return &models.NotificationDelivery{
			Status:     models.DeliveryStatusSent,
			ExternalID: messageID,
			Metadata:   map[string]interface{}{"provider": "firebase_admin_sdk"},
		}, nil
	}

	// Fall back to legacy FCM HTTP API
	return p.sendLegacyFCM(ctx, notification, recipient)
}

func (p *PushProvider) sendLegacyFCM(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	// Parse notification data for FCM payload
	var dataMap map[string]interface{}
	if notification.Data != nil {
		// Handle different types that notification.Data could be
		switch v := notification.Data.(type) {
		case map[string]interface{}:
			dataMap = v
		case []byte:
			json.Unmarshal(v, &dataMap)
		case string:
			json.Unmarshal([]byte(v), &dataMap)
		default:
			// Try to marshal and unmarshal to get map
			if bytes, err := json.Marshal(v); err == nil {
				json.Unmarshal(bytes, &dataMap)
			}
		}
	}
	if dataMap == nil {
		dataMap = make(map[string]interface{})
	}
	dataMap["notification_id"] = notification.ID.String()
	dataMap["category"] = string(notification.Category)
	dataMap["priority"] = string(notification.Priority)
	if notification.ActionURL != "" {
		dataMap["action_url"] = notification.ActionURL
	}

	// Build FCM payload
	payload := map[string]interface{}{
		"to": recipient, // FCM token
		"notification": map[string]interface{}{
			"title":        notification.Title,
			"body":         notification.Body,
			"sound":        "default",
			"click_action": "FLUTTER_NOTIFICATION_CLICK",
		},
		"data": dataMap,
		"android": map[string]interface{}{
			"priority": "high",
		},
		"apns": map[string]interface{}{
			"headers": map[string]string{
				"apns-priority": "10",
			},
			"payload": map[string]interface{}{
				"aps": map[string]interface{}{
					"sound":             "default",
					"content-available": 1,
					"mutable-content":   1,
				},
			},
		},
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", p.fcmEndpoint, bytes.NewBuffer(jsonPayload))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "key="+p.fcmKey)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	// Check for FCM errors
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("FCM returned status %d: %v", resp.StatusCode, result)
	}

	// Check for individual message errors
	if failure, ok := result["failure"].(float64); ok && failure > 0 {
		if results, ok := result["results"].([]interface{}); ok && len(results) > 0 {
			if r, ok := results[0].(map[string]interface{}); ok {
				if errStr, ok := r["error"].(string); ok {
					return nil, fmt.Errorf("FCM error: %s", errStr)
				}
			}
		}
	}

	result["provider"] = "fcm_legacy"
	return &models.NotificationDelivery{
		Status:     models.DeliveryStatusSent,
		ExternalID: fmt.Sprintf("%v", result["message_id"]),
		Metadata:   result,
	}, nil
}

func (p *PushProvider) GetName() string {
	if p.useAdminSDK {
		return "firebase_admin_sdk"
	}
	return "firebase_fcm_legacy"
}

func (p *PushProvider) IsEnabled() bool {
	return p.enabled
}

// =====================================================
// Email Provider (SMTP/SendGrid/etc)
// =====================================================

type EmailProvider struct {
	enabled      bool
	providerType string
	apiKey       string
	fromAddress  string
	fromName     string
}

func NewEmailProvider() *EmailProvider {
	apiKey := os.Getenv("EMAIL_API_KEY")
	providerType := os.Getenv("EMAIL_PROVIDER") // sendgrid, mailgun, smtp
	fromAddress := os.Getenv("EMAIL_FROM_ADDRESS")
	fromName := os.Getenv("EMAIL_FROM_NAME")

	if fromAddress == "" {
		fromAddress = "noreply@liquorpro.in"
	}
	if fromName == "" {
		fromName = "LiquorPro"
	}

	return &EmailProvider{
		enabled:      apiKey != "",
		providerType: providerType,
		apiKey:       apiKey,
		fromAddress:  fromAddress,
		fromName:     fromName,
	}
}

func (p *EmailProvider) Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	if !p.enabled {
		return nil, fmt.Errorf("email provider not configured")
	}

	switch p.providerType {
	case "sendgrid":
		return p.sendViaSendGrid(ctx, notification, recipient)
	default:
		return nil, fmt.Errorf("unknown email provider: %s", p.providerType)
	}
}

func (p *EmailProvider) sendViaSendGrid(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	// Build SendGrid payload
	payload := map[string]interface{}{
		"personalizations": []map[string]interface{}{
			{
				"to": []map[string]string{
					{"email": recipient},
				},
			},
		},
		"from": map[string]string{
			"email": p.fromAddress,
			"name":  p.fromName,
		},
		"subject": notification.Title,
		"content": []map[string]string{
			{
				"type":  "text/html",
				"value": buildEmailHTML(notification),
			},
		},
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.sendgrid.com/v3/mail/send", bytes.NewBuffer(jsonPayload))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+p.apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("SendGrid returned status %d", resp.StatusCode)
	}

	messageID := resp.Header.Get("X-Message-Id")

	return &models.NotificationDelivery{
		Status:     models.DeliveryStatusSent,
		ExternalID: messageID,
	}, nil
}

func (p *EmailProvider) GetName() string {
	return p.providerType
}

func (p *EmailProvider) IsEnabled() bool {
	return p.enabled
}

func buildEmailHTML(notification *models.Notification) string {
	actionButton := ""
	if notification.ActionURL != "" {
		label := notification.ActionLabel
		if label == "" {
			label = "View Details"
		}
		actionButton = fmt.Sprintf(`
			<div style="margin-top: 20px;">
				<a href="%s" style="background-color: #4CAF50; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">%s</a>
			</div>
		`, notification.ActionURL, label)
	}

	return fmt.Sprintf(`
		<!DOCTYPE html>
		<html>
		<head>
			<meta charset="utf-8">
			<meta name="viewport" content="width=device-width, initial-scale=1">
		</head>
		<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
			<div style="background-color: #f8f9fa; padding: 20px; border-radius: 10px;">
				<h2 style="color: #2c3e50; margin-bottom: 15px;">%s</h2>
				<p style="color: #555;">%s</p>
				%s
			</div>
			<div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #999;">
				<p>This is an automated notification from LiquorPro.</p>
			</div>
		</body>
		</html>
	`, notification.Title, notification.Body, actionButton)
}

// =====================================================
// SMS Provider (Twilio/MSG91/etc)
// =====================================================

type SMSProvider struct {
	enabled      bool
	providerType string
	accountSID   string
	authToken    string
	fromNumber   string
}

func NewSMSProvider() *SMSProvider {
	providerType := os.Getenv("SMS_PROVIDER") // twilio, msg91
	accountSID := os.Getenv("SMS_ACCOUNT_SID")
	authToken := os.Getenv("SMS_AUTH_TOKEN")
	fromNumber := os.Getenv("SMS_FROM_NUMBER")

	return &SMSProvider{
		enabled:      accountSID != "" && authToken != "",
		providerType: providerType,
		accountSID:   accountSID,
		authToken:    authToken,
		fromNumber:   fromNumber,
	}
}

func (p *SMSProvider) Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	if !p.enabled {
		return nil, fmt.Errorf("SMS provider not configured")
	}

	switch p.providerType {
	case "twilio":
		return p.sendViaTwilio(ctx, notification, recipient)
	case "msg91":
		return p.sendViaMSG91(ctx, notification, recipient)
	default:
		return nil, fmt.Errorf("unknown SMS provider: %s", p.providerType)
	}
}

func (p *SMSProvider) sendViaTwilio(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	endpoint := fmt.Sprintf("https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json", p.accountSID)

	// Truncate message for SMS
	message := notification.Title + ": " + notification.Body
	if len(message) > 160 {
		message = message[:157] + "..."
	}

	formData := fmt.Sprintf("To=%s&From=%s&Body=%s", recipient, p.fromNumber, message)

	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBufferString(formData))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth(p.accountSID, p.authToken)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("Twilio returned status %d", resp.StatusCode)
	}

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	return &models.NotificationDelivery{
		Status:     models.DeliveryStatusSent,
		ExternalID: fmt.Sprintf("%v", result["sid"]),
		Metadata:   result,
	}, nil
}

func (p *SMSProvider) sendViaMSG91(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	// MSG91 implementation for Indian SMS
	message := notification.Title + ": " + notification.Body
	if len(message) > 160 {
		message = message[:157] + "..."
	}

	payload := map[string]interface{}{
		"flow_id": os.Getenv("MSG91_FLOW_ID"),
		"mobiles": recipient,
		"message": message,
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.msg91.com/api/v5/flow/", bytes.NewBuffer(jsonPayload))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("authkey", p.authToken)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("MSG91 returned status %d", resp.StatusCode)
	}

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	return &models.NotificationDelivery{
		Status:     models.DeliveryStatusSent,
		ExternalID: fmt.Sprintf("%v", result["request_id"]),
		Metadata:   result,
	}, nil
}

func (p *SMSProvider) GetName() string {
	return p.providerType
}

func (p *SMSProvider) IsEnabled() bool {
	return p.enabled
}

// =====================================================
// WhatsApp Business API Provider
// =====================================================

type WhatsAppProvider struct {
	enabled          bool
	accessToken      string
	phoneNumberID    string
	businessAccountID string
}

func NewWhatsAppProvider() *WhatsAppProvider {
	accessToken := os.Getenv("WHATSAPP_ACCESS_TOKEN")
	phoneNumberID := os.Getenv("WHATSAPP_PHONE_NUMBER_ID")
	businessAccountID := os.Getenv("WHATSAPP_BUSINESS_ACCOUNT_ID")

	return &WhatsAppProvider{
		enabled:          accessToken != "" && phoneNumberID != "",
		accessToken:      accessToken,
		phoneNumberID:    phoneNumberID,
		businessAccountID: businessAccountID,
	}
}

func (p *WhatsAppProvider) Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	if !p.enabled {
		return nil, fmt.Errorf("WhatsApp provider not configured")
	}

	// Get template from notification or use default
	template, templateParams := p.getWhatsAppTemplate(notification)

	payload := map[string]interface{}{
		"messaging_product": "whatsapp",
		"to":                recipient,
		"type":              "template",
		"template": map[string]interface{}{
			"name": template,
			"language": map[string]string{
				"code": "en",
			},
			"components": []map[string]interface{}{
				{
					"type":       "body",
					"parameters": templateParams,
				},
			},
		},
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	endpoint := fmt.Sprintf("https://graph.facebook.com/v18.0/%s/messages", p.phoneNumberID)
	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(jsonPayload))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+p.accessToken)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		var errResp map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&errResp)
		return nil, fmt.Errorf("WhatsApp API error: %v", errResp)
	}

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	messageID := ""
	if messages, ok := result["messages"].([]interface{}); ok && len(messages) > 0 {
		if msg, ok := messages[0].(map[string]interface{}); ok {
			messageID = fmt.Sprintf("%v", msg["id"])
		}
	}

	return &models.NotificationDelivery{
		Status:     models.DeliveryStatusSent,
		ExternalID: messageID,
		Metadata:   result,
	}, nil
}

func (p *WhatsAppProvider) getWhatsAppTemplate(notification *models.Notification) (string, []map[string]interface{}) {
	// Map notification category to WhatsApp template
	templateMap := map[models.NotificationCategory]string{
		models.NotificationCategoryAlert:     "alert_notification",
		models.NotificationCategoryAudit:     "audit_reminder",
		models.NotificationCategorySales:     "sales_update",
		models.NotificationCategoryInventory: "inventory_alert",
		models.NotificationCategoryFinance:   "finance_alert",
		models.NotificationCategoryTips:      "tips_update",
		models.NotificationCategorySystem:    "general_notification",
	}

	templateName := templateMap[notification.Category]
	if templateName == "" {
		templateName = "general_notification"
	}

	// Build parameters
	params := []map[string]interface{}{
		{
			"type": "text",
			"text": notification.Title,
		},
		{
			"type": "text",
			"text": notification.Body,
		},
	}

	return templateName, params
}

func (p *WhatsAppProvider) GetName() string {
	return "whatsapp_business"
}

func (p *WhatsAppProvider) IsEnabled() bool {
	return p.enabled
}

// SendVerificationCode sends WhatsApp OTP
func (p *WhatsAppProvider) SendVerificationCode(ctx context.Context, phoneNumber, code string) error {
	if !p.enabled {
		return fmt.Errorf("WhatsApp provider not configured")
	}

	payload := map[string]interface{}{
		"messaging_product": "whatsapp",
		"to":                phoneNumber,
		"type":              "template",
		"template": map[string]interface{}{
			"name": "verification_code",
			"language": map[string]string{
				"code": "en",
			},
			"components": []map[string]interface{}{
				{
					"type": "body",
					"parameters": []map[string]interface{}{
						{
							"type": "text",
							"text": code,
						},
					},
				},
			},
		},
	}

	jsonPayload, _ := json.Marshal(payload)
	endpoint := fmt.Sprintf("https://graph.facebook.com/v18.0/%s/messages", p.phoneNumberID)
	req, _ := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(jsonPayload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+p.accessToken)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("WhatsApp API returned status %d", resp.StatusCode)
	}

	return nil
}

// =====================================================
// Provider Factory
// =====================================================

// InitializeChannelProviders creates and registers all channel providers
func InitializeChannelProviders(service *NotificationService) {
	service.RegisterChannel(models.NotificationChannelInApp, NewInAppProvider())
	service.RegisterChannel(models.NotificationChannelPush, NewPushProvider())
	service.RegisterChannel(models.NotificationChannelEmail, NewEmailProvider())
	service.RegisterChannel(models.NotificationChannelSMS, NewSMSProvider())
	service.RegisterChannel(models.NotificationChannelWhatsApp, NewWhatsAppProvider())
}
