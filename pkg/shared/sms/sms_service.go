package sms

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// normalizeForGateway strips the +91 country-code prefix expected by
// fast.confirmsms.in, which returns "Not Found" for numbers sent in
// +<countrycode><10-digits> form. Non-Indian or already-10-digit numbers
// are returned unchanged.
func normalizeForGateway(phoneNumber string) string {
	n := strings.TrimSpace(phoneNumber)
	n = strings.ReplaceAll(n, " ", "")
	n = strings.ReplaceAll(n, "-", "")
	switch {
	case strings.HasPrefix(n, "+91") && len(n) == 13:
		return n[3:]
	case strings.HasPrefix(n, "91") && len(n) == 12:
		return n[2:]
	case strings.HasPrefix(n, "0") && len(n) == 11:
		return n[1:]
	default:
		return n
	}
}

// SMSService handles sending SMS messages
type SMSService struct {
	APIKey   string
	SenderID string
	APIURL   string
	client   *http.Client
}

// SMSResponse represents the API response structure
type SMSResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	Description struct {
		BatchID  string `json:"batchid"`
		BatchDtl []struct {
			MsgID string `json:"msgid"`
		} `json:"batch_dtl"`
	} `json:"description"`
}

// NewSMSService creates a new SMS service instance
func NewSMSService(apiKey, senderID, apiURL string) *SMSService {
	return &SMSService{
		APIKey:   apiKey,
		SenderID: senderID,
		APIURL:   apiURL,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// SendOTP sends an OTP via SMS using the government-approved template
// Template: "Dear {name}, {otp} is your one time password (OTP). Please enter the OTP to proceed. Thank you. Dr. Dangs Lab"
func (s *SMSService) SendOTP(phoneNumber, name, otp string) (string, error) {
	// Use 'User' if name is not provided
	recipientName := name
	if recipientName == "" {
		recipientName = "User"
	}

	// Create message with government-approved template
	message := fmt.Sprintf(
		"Dear %s, %s is your one time password (OTP). Please enter the OTP to proceed. Thank you. Dr. Dangs Lab",
		recipientName,
		otp,
	)

	gatewayMobile := normalizeForGateway(phoneNumber)

	// Build URL with properly encoded parameters
	params := url.Values{}
	params.Set("apikey", s.APIKey)
	params.Set("sender", s.SenderID)
	params.Set("mobileno", gatewayMobile)
	params.Set("text", message)

	requestURL := fmt.Sprintf("%s?%s", s.APIURL, params.Encode())

	fmt.Printf("[SMS] Sending OTP to: %s (gateway: %s), Name: %s\n", phoneNumber, gatewayMobile, recipientName)

	// Make HTTP GET request
	resp, err := s.client.Get(requestURL)
	if err != nil {
		return "", fmt.Errorf("SMS API request failed: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read SMS API response: %w", err)
	}

	fmt.Printf("[SMS] API Response Status: %d\n", resp.StatusCode)
	fmt.Printf("[SMS] API Response: %s\n", string(body))

	// Check HTTP status code
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("SMS API returned status code %d: %s", resp.StatusCode, string(body))
	}

	// Parse JSON response
	var smsResp SMSResponse
	if err := json.Unmarshal(body, &smsResp); err != nil {
		return "", fmt.Errorf("failed to parse SMS API response: %w", err)
	}

	// Check for success status
	if smsResp.Status != "success" {
		return "", fmt.Errorf("SMS API error: %s", smsResp.Message)
	}

	// Get batch ID or message ID
	messageID := smsResp.Description.BatchID
	if messageID == "" && len(smsResp.Description.BatchDtl) > 0 {
		messageID = smsResp.Description.BatchDtl[0].MsgID
	}

	if messageID == "" {
		messageID = "success" // Fallback if no ID is provided
	}

	fmt.Printf("[SMS] ✅ SMS sent successfully. Message ID: %s\n", messageID)
	return messageID, nil
}

// SendMessage sends a generic SMS message (for future use)
func (s *SMSService) SendMessage(phoneNumber, message string) (string, error) {
	gatewayMobile := normalizeForGateway(phoneNumber)

	// Build URL with properly encoded parameters
	params := url.Values{}
	params.Set("apikey", s.APIKey)
	params.Set("sender", s.SenderID)
	params.Set("mobileno", gatewayMobile)
	params.Set("text", message)

	requestURL := fmt.Sprintf("%s?%s", s.APIURL, params.Encode())

	fmt.Printf("[SMS] Sending message to: %s (gateway: %s)\n", phoneNumber, gatewayMobile)

	// Make HTTP GET request
	resp, err := s.client.Get(requestURL)
	if err != nil {
		return "", fmt.Errorf("SMS API request failed: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read SMS API response: %w", err)
	}

	// Check HTTP status code
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("SMS API returned status code %d: %s", resp.StatusCode, string(body))
	}

	// Parse JSON response
	var smsResp SMSResponse
	if err := json.Unmarshal(body, &smsResp); err != nil {
		return "", fmt.Errorf("failed to parse SMS API response: %w", err)
	}

	// Check for success status
	if smsResp.Status != "success" {
		return "", fmt.Errorf("SMS API error: %s", smsResp.Message)
	}

	// Get batch ID or message ID
	messageID := smsResp.Description.BatchID
	if messageID == "" && len(smsResp.Description.BatchDtl) > 0 {
		messageID = smsResp.Description.BatchDtl[0].MsgID
	}

	return messageID, nil
}
