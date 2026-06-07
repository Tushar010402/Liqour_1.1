package firebase

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/api/option"
)

// AuthVerifier verifies Firebase ID tokens and extracts phone number + UID
type AuthVerifier struct {
	client *auth.Client
}

// NewAuthVerifier creates a new Firebase auth verifier
// Follows the same credential loading pattern as FCM service
func NewAuthVerifier() (*AuthVerifier, error) {
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

	client, err := app.Auth(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get auth client: %w", err)
	}

	log.Println("✅ Firebase Auth Verifier initialized successfully")

	return &AuthVerifier{
		client: client,
	}, nil
}

// VerifyIDToken verifies a Firebase ID token and extracts the phone number and Firebase UID
func (v *AuthVerifier) VerifyIDToken(ctx context.Context, idToken string) (phone string, uid string, err error) {
	token, err := v.client.VerifyIDToken(ctx, idToken)
	if err != nil {
		return "", "", fmt.Errorf("invalid firebase token: %w", err)
	}

	uid = token.UID

	// Extract phone number from claims
	if phoneNumber, ok := token.Claims["phone_number"].(string); ok && phoneNumber != "" {
		phone = phoneNumber
	} else {
		// Fallback: fetch user record to get phone
		userRecord, err := v.client.GetUser(ctx, uid)
		if err != nil {
			return "", "", fmt.Errorf("failed to get firebase user: %w", err)
		}
		phone = userRecord.PhoneNumber
	}

	if phone == "" {
		return "", "", fmt.Errorf("no phone number associated with firebase account")
	}

	// Normalize: ensure +91 prefix for Indian numbers
	phone = normalizePhone(phone)

	return phone, uid, nil
}

// normalizePhone ensures consistent phone format
func normalizePhone(phone string) string {
	// Remove spaces, hyphens, parentheses
	phone = strings.ReplaceAll(phone, " ", "")
	phone = strings.ReplaceAll(phone, "-", "")
	phone = strings.ReplaceAll(phone, "(", "")
	phone = strings.ReplaceAll(phone, ")", "")
	return phone
}
