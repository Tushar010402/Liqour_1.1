package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

// OCRSecurityService provides security features for OCR operations
type OCRSecurityService struct {
	logger    *logrus.Logger
	secretKey []byte
}

// NewOCRSecurityService creates a new security service
func NewOCRSecurityService(logger *logrus.Logger, secretKey string) *OCRSecurityService {
	return &OCRSecurityService{
		logger:    logger,
		secretKey: []byte(secretKey),
	}
}

// ValidateImageData validates and sanitizes image data
func (s *OCRSecurityService) ValidateImageData(imageData string) error {
	// Check if base64 encoded
	if _, err := base64.StdEncoding.DecodeString(imageData); err != nil {
		s.logger.Warnf("Invalid base64 image data: %v", err)
		return errors.New("image data must be valid base64")
	}

	// Check for suspicious patterns
	suspicious := []string{
		"<script",
		"javascript:",
		"data:text/html",
		"onclick",
		"onerror",
	}

	lowerData := strings.ToLower(imageData)
	for _, pattern := range suspicious {
		if strings.Contains(lowerData, pattern) {
			s.logger.Warnf("Suspicious pattern detected in image data: %s", pattern)
			return fmt.Errorf("suspicious content detected")
		}
	}

	return nil
}

// SanitizeExtractedText sanitizes text extracted from OCR
func (s *OCRSecurityService) SanitizeExtractedText(text string) string {
	// Remove potential SQL injection attempts
	sqlPatterns := []string{
		"'; DROP",
		"1=1",
		"OR 1=1",
		"UNION SELECT",
		"/*",
		"*/",
		"xp_",
		"sp_",
	}

	sanitized := text
	for _, pattern := range sqlPatterns {
		sanitized = strings.ReplaceAll(strings.ToUpper(sanitized), pattern, "")
	}

	// Remove HTML/JavaScript
	htmlPattern := regexp.MustCompile(`<[^>]*>`)
	sanitized = htmlPattern.ReplaceAllString(sanitized, "")

	// Remove non-printable characters
	printablePattern := regexp.MustCompile(`[^\x20-\x7E\n\r\t]`)
	sanitized = printablePattern.ReplaceAllString(sanitized, "")

	// Limit length
	const maxLength = 10000
	if len(sanitized) > maxLength {
		sanitized = sanitized[:maxLength]
	}

	return strings.TrimSpace(sanitized)
}

// ValidateBrandName validates brand name input
func (s *OCRSecurityService) ValidateBrandName(brand string) error {
	// Check length
	if len(brand) < 2 || len(brand) > 100 {
		return errors.New("brand name must be between 2 and 100 characters")
	}

	// Allow only alphanumeric, spaces, and common punctuation
	validPattern := regexp.MustCompile(`^[a-zA-Z0-9\s\-'.&]+$`)
	if !validPattern.MatchString(brand) {
		return errors.New("brand name contains invalid characters")
	}

	return nil
}

// ValidateQuantity validates quantity input
func (s *OCRSecurityService) ValidateQuantity(quantity int) error {
	if quantity < 0 {
		return errors.New("quantity cannot be negative")
	}

	if quantity > 10000 {
		return errors.New("quantity exceeds maximum allowed (10000)")
	}

	return nil
}

// ValidatePrice validates price input
func (s *OCRSecurityService) ValidatePrice(price float64) error {
	if price < 0 {
		return errors.New("price cannot be negative")
	}

	if price > 1000000 {
		return errors.New("price exceeds maximum allowed")
	}

	// Check for reasonable decimal places
	priceStr := fmt.Sprintf("%.2f", price)
	if _, err := fmt.Sscanf(priceStr, "%f", &price); err != nil {
		return errors.New("invalid price format")
	}

	return nil
}

// GenerateSessionToken generates a secure token for OCR session
func (s *OCRSecurityService) GenerateSessionToken(sessionID uuid.UUID) string {
	timestamp := time.Now().Unix()
	data := fmt.Sprintf("%s:%d", sessionID.String(), timestamp)

	h := hmac.New(sha256.New, s.secretKey)
	h.Write([]byte(data))
	signature := hex.EncodeToString(h.Sum(nil))

	token := base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("%s:%s", data, signature)))
	return token
}

// ValidateSessionToken validates a session token
func (s *OCRSecurityService) ValidateSessionToken(token string) (uuid.UUID, error) {
	// Decode token
	decoded, err := base64.StdEncoding.DecodeString(token)
	if err != nil {
		return uuid.Nil, errors.New("invalid token format")
	}

	parts := strings.Split(string(decoded), ":")
	if len(parts) != 3 {
		return uuid.Nil, errors.New("invalid token structure")
	}

	sessionID, err := uuid.Parse(parts[0])
	if err != nil {
		return uuid.Nil, errors.New("invalid session ID in token")
	}

	// Verify signature
	data := fmt.Sprintf("%s:%s", parts[0], parts[1])
	h := hmac.New(sha256.New, s.secretKey)
	h.Write([]byte(data))
	expectedSignature := hex.EncodeToString(h.Sum(nil))

	if parts[2] != expectedSignature {
		return uuid.Nil, errors.New("invalid token signature")
	}

	// Check timestamp (token expires after 1 hour)
	var timestamp int64
	fmt.Sscanf(parts[1], "%d", &timestamp)
	if time.Now().Unix()-timestamp > 3600 {
		return uuid.Nil, errors.New("token expired")
	}

	return sessionID, nil
}

// AuditLog represents an audit log entry
type AuditLog struct {
	Timestamp time.Time
	UserID    uuid.UUID
	SessionID uuid.UUID
	Action    string
	Details   map[string]interface{}
	IPAddress string
}

// OCRAuditLogger handles audit logging for OCR operations
type OCRAuditLogger struct {
	logger *logrus.Logger
	logs   []AuditLog
}

// NewOCRAuditLogger creates a new audit logger
func NewOCRAuditLogger(logger *logrus.Logger) *OCRAuditLogger {
	return &OCRAuditLogger{
		logger: logger,
		logs:   make([]AuditLog, 0),
	}
}

// LogSessionCreation logs OCR session creation
func (a *OCRAuditLogger) LogSessionCreation(userID, sessionID uuid.UUID, ipAddress string) {
	entry := AuditLog{
		Timestamp: time.Now(),
		UserID:    userID,
		SessionID: sessionID,
		Action:    "OCR_SESSION_CREATED",
		IPAddress: ipAddress,
		Details: map[string]interface{}{
			"event": "session_created",
		},
	}

	a.logs = append(a.logs, entry)

	a.logger.WithFields(logrus.Fields{
		"user_id":    userID,
		"session_id": sessionID,
		"ip_address": ipAddress,
		"action":     "OCR_SESSION_CREATED",
	}).Info("OCR audit log")
}

// LogDataExtraction logs data extraction
func (a *OCRAuditLogger) LogDataExtraction(userID, sessionID uuid.UUID, itemCount int, confidence float64) {
	entry := AuditLog{
		Timestamp: time.Now(),
		UserID:    userID,
		SessionID: sessionID,
		Action:    "OCR_DATA_EXTRACTED",
		Details: map[string]interface{}{
			"item_count": itemCount,
			"confidence": confidence,
		},
	}

	a.logs = append(a.logs, entry)

	a.logger.WithFields(logrus.Fields{
		"user_id":    userID,
		"session_id": sessionID,
		"item_count": itemCount,
		"confidence": confidence,
		"action":     "OCR_DATA_EXTRACTED",
	}).Info("OCR audit log")
}

// LogStockUpdate logs stock updates from OCR
func (a *OCRAuditLogger) LogStockUpdate(userID, sessionID uuid.UUID, productID uuid.UUID, quantityChange int) {
	entry := AuditLog{
		Timestamp: time.Now(),
		UserID:    userID,
		SessionID: sessionID,
		Action:    "OCR_STOCK_UPDATED",
		Details: map[string]interface{}{
			"product_id":      productID,
			"quantity_change": quantityChange,
		},
	}

	a.logs = append(a.logs, entry)

	a.logger.WithFields(logrus.Fields{
		"user_id":         userID,
		"session_id":      sessionID,
		"product_id":      productID,
		"quantity_change": quantityChange,
		"action":          "OCR_STOCK_UPDATED",
	}).Info("OCR audit log")
}

// GetAuditTrail returns audit logs for a session
func (a *OCRAuditLogger) GetAuditTrail(sessionID uuid.UUID) []AuditLog {
	trail := []AuditLog{}
	for _, log := range a.logs {
		if log.SessionID == sessionID {
			trail = append(trail, log)
		}
	}
	return trail
}

// InputSanitizer provides input sanitization utilities
type InputSanitizer struct {
	logger *logrus.Logger
}

// NewInputSanitizer creates a new input sanitizer
func NewInputSanitizer(logger *logrus.Logger) *InputSanitizer {
	return &InputSanitizer{
		logger: logger,
	}
}

// SanitizeJSON sanitizes JSON input
func (s *InputSanitizer) SanitizeJSON(input map[string]interface{}) map[string]interface{} {
	sanitized := make(map[string]interface{})

	for key, value := range input {
		// Sanitize key
		sanitizedKey := s.sanitizeString(key)

		// Sanitize value based on type
		switch v := value.(type) {
		case string:
			sanitized[sanitizedKey] = s.sanitizeString(v)
		case []interface{}:
			sanitized[sanitizedKey] = s.sanitizeArray(v)
		case map[string]interface{}:
			sanitized[sanitizedKey] = s.SanitizeJSON(v)
		default:
			sanitized[sanitizedKey] = value
		}
	}

	return sanitized
}

// sanitizeString sanitizes a string value
func (s *InputSanitizer) sanitizeString(str string) string {
	// Remove null bytes
	str = strings.ReplaceAll(str, "\x00", "")

	// Trim whitespace
	str = strings.TrimSpace(str)

	// Escape special characters
	replacements := map[string]string{
		"<":  "&lt;",
		">":  "&gt;",
		"&":  "&amp;",
		"\"": "&quot;",
		"'":  "&#x27;",
		"/":  "&#x2F;",
	}

	for old, new := range replacements {
		str = strings.ReplaceAll(str, old, new)
	}

	return str
}

// sanitizeArray sanitizes an array
func (s *InputSanitizer) sanitizeArray(arr []interface{}) []interface{} {
	sanitized := make([]interface{}, len(arr))

	for i, value := range arr {
		switch v := value.(type) {
		case string:
			sanitized[i] = s.sanitizeString(v)
		case map[string]interface{}:
			sanitized[i] = s.SanitizeJSON(v)
		default:
			sanitized[i] = value
		}
	}

	return sanitized
}