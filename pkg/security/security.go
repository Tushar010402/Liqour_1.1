package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"html"
	"regexp"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/time/rate"
	"go.uber.org/zap"
)

var (
	ErrInvalidInput       = errors.New("invalid input")
	ErrSQLInjection       = errors.New("potential SQL injection detected")
	ErrXSSAttempt         = errors.New("potential XSS attempt detected")
	ErrPathTraversal      = errors.New("potential path traversal detected")
	ErrCommandInjection   = errors.New("potential command injection detected")
	ErrWeakPassword       = errors.New("password does not meet security requirements")
	ErrRateLimitExceeded  = errors.New("rate limit exceeded")
	ErrSessionExpired     = errors.New("session expired")
	ErrInvalidToken       = errors.New("invalid token")
)

// SecurityConfig contains security configuration
type SecurityConfig struct {
	PasswordMinLength      int
	PasswordRequireUpper   bool
	PasswordRequireLower   bool
	PasswordRequireNumber  bool
	PasswordRequireSpecial bool
	MaxLoginAttempts       int
	LockoutDuration        time.Duration
	SessionTimeout         time.Duration
	TokenExpiry            time.Duration
	CSRFTokenLength        int
	Logger                 *zap.Logger
}

// SecurityManager manages application security
type SecurityManager struct {
	config        SecurityConfig
	loginAttempts map[string]int
	lockouts      map[string]time.Time
	rateLimiters  map[string]*rate.Limiter
	mu            sync.RWMutex
	logger        *zap.Logger
}

// NewSecurityManager creates a new security manager
func NewSecurityManager(config SecurityConfig) *SecurityManager {
	return &SecurityManager{
		config:        config,
		loginAttempts: make(map[string]int),
		lockouts:      make(map[string]time.Time),
		rateLimiters:  make(map[string]*rate.Limiter),
		logger:        config.Logger,
	}
}

// Input Validation and Sanitization

// SanitizeHTML sanitizes HTML to prevent XSS
func (sm *SecurityManager) SanitizeHTML(input string) string {
	// HTML escape
	sanitized := html.EscapeString(input)

	// Remove potentially dangerous attributes
	dangerousPatterns := []string{
		`javascript:`,
		`on\w+=`,
		`<script`,
		`</script>`,
		`<iframe`,
		`</iframe>`,
		`<object`,
		`</object>`,
		`<embed`,
		`</embed>`,
		`<applet`,
		`</applet>`,
	}

	for _, pattern := range dangerousPatterns {
		re := regexp.MustCompile(`(?i)` + pattern)
		sanitized = re.ReplaceAllString(sanitized, "")
	}

	return sanitized
}

// ValidateInput validates input against common injection attacks
func (sm *SecurityManager) ValidateInput(input string, inputType InputType) error {
	// Check for SQL injection patterns
	if sm.hasSQLInjectionPattern(input) {
		sm.logger.Warn("SQL injection attempt detected", zap.String("input", input))
		return ErrSQLInjection
	}

	// Check for XSS patterns
	if sm.hasXSSPattern(input) {
		sm.logger.Warn("XSS attempt detected", zap.String("input", input))
		return ErrXSSAttempt
	}

	// Check for path traversal
	if sm.hasPathTraversalPattern(input) {
		sm.logger.Warn("Path traversal attempt detected", zap.String("input", input))
		return ErrPathTraversal
	}

	// Check for command injection
	if sm.hasCommandInjectionPattern(input) {
		sm.logger.Warn("Command injection attempt detected", zap.String("input", input))
		return ErrCommandInjection
	}

	// Type-specific validation
	switch inputType {
	case InputTypeEmail:
		return sm.validateEmail(input)
	case InputTypePhone:
		return sm.validatePhone(input)
	case InputTypeAlphanumeric:
		return sm.validateAlphanumeric(input)
	case InputTypeNumeric:
		return sm.validateNumeric(input)
	case InputTypeURL:
		return sm.validateURL(input)
	}

	return nil
}

// InputType represents the type of input
type InputType int

const (
	InputTypeGeneral InputType = iota
	InputTypeEmail
	InputTypePhone
	InputTypeAlphanumeric
	InputTypeNumeric
	InputTypeURL
)

// hasSQLInjectionPattern checks for SQL injection patterns
func (sm *SecurityManager) hasSQLInjectionPattern(input string) bool {
	patterns := []string{
		`(?i)(union|select|insert|update|delete|drop|create|alter|exec|execute|script|javascript|eval)`,
		`(?i)(--|#|\/\*|\*\/|xp_|sp_|0x)`,
		`(?i)(having|group by|order by).*[^\w]`,
		`(?i)(waitfor|delay|benchmark|sleep)`,
		`['";].*?(or|and).*?['";]?\s*?['";]?\d`,
		`\w*'\s*?(or|and)\s*?'?\d`,
	}

	for _, pattern := range patterns {
		if match, _ := regexp.MatchString(pattern, input); match {
			return true
		}
	}
	return false
}

// hasXSSPattern checks for XSS patterns
func (sm *SecurityManager) hasXSSPattern(input string) bool {
	patterns := []string{
		`<script[^>]*>.*?</script>`,
		`javascript:`,
		`on\w+\s*=`,
		`<iframe[^>]*>`,
		`<object[^>]*>`,
		`<embed[^>]*>`,
		`<applet[^>]*>`,
		`<meta[^>]*>`,
		`<link[^>]*>`,
		`<style[^>]*>.*?</style>`,
	}

	for _, pattern := range patterns {
		if match, _ := regexp.MatchString(`(?i)`+pattern, input); match {
			return true
		}
	}
	return false
}

// hasPathTraversalPattern checks for path traversal patterns
func (sm *SecurityManager) hasPathTraversalPattern(input string) bool {
	patterns := []string{
		`\.\.\/`,
		`\.\.\\`,
		`\.\.`,
		`%2e%2e%2f`,
		`%2e%2e%5c`,
		`\.%2e`,
		`%00`,
	}

	for _, pattern := range patterns {
		if strings.Contains(strings.ToLower(input), pattern) {
			return true
		}
	}
	return false
}

// hasCommandInjectionPattern checks for command injection patterns
func (sm *SecurityManager) hasCommandInjectionPattern(input string) bool {
	patterns := []string{
		`;`,
		`|`,
		`&`,
		`$`,
		`\n`,
		`\r`,
		"`",
		`$(`,
		`&&`,
		`||`,
		`>`,
		`<`,
	}

	for _, pattern := range patterns {
		if strings.Contains(input, pattern) {
			return true
		}
	}
	return false
}

// Password Security

// HashPassword hashes a password using Argon2id
func (sm *SecurityManager) HashPassword(password string) (string, error) {
	// Validate password strength
	if err := sm.ValidatePasswordStrength(password); err != nil {
		return "", err
	}

	// Generate salt
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}

	// Hash with Argon2id
	hash := argon2.IDKey([]byte(password), salt, 3, 64*1024, 4, 32)

	// Encode
	encoded := fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, 64*1024, 3, 4,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash))

	return encoded, nil
}

// VerifyPassword verifies a password against a hash
func (sm *SecurityManager) VerifyPassword(password, hash string) bool {
	// Try Argon2id first
	if strings.HasPrefix(hash, "$argon2id$") {
		return sm.verifyArgon2id(password, hash)
	}

	// Fallback to bcrypt for backward compatibility
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// verifyArgon2id verifies an Argon2id hash
func (sm *SecurityManager) verifyArgon2id(password, encodedHash string) bool {
	// Parse the encoded hash
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 {
		return false
	}

	// Decode salt and hash
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}

	expectedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false
	}

	// Compute hash
	actualHash := argon2.IDKey([]byte(password), salt, 3, 64*1024, 4, 32)

	// Constant time comparison
	return subtle.ConstantTimeCompare(expectedHash, actualHash) == 1
}

// ValidatePasswordStrength validates password strength
func (sm *SecurityManager) ValidatePasswordStrength(password string) error {
	if len(password) < sm.config.PasswordMinLength {
		return fmt.Errorf("%w: minimum length is %d", ErrWeakPassword, sm.config.PasswordMinLength)
	}

	if sm.config.PasswordRequireUpper {
		if !regexp.MustCompile(`[A-Z]`).MatchString(password) {
			return fmt.Errorf("%w: must contain uppercase letter", ErrWeakPassword)
		}
	}

	if sm.config.PasswordRequireLower {
		if !regexp.MustCompile(`[a-z]`).MatchString(password) {
			return fmt.Errorf("%w: must contain lowercase letter", ErrWeakPassword)
		}
	}

	if sm.config.PasswordRequireNumber {
		if !regexp.MustCompile(`[0-9]`).MatchString(password) {
			return fmt.Errorf("%w: must contain number", ErrWeakPassword)
		}
	}

	if sm.config.PasswordRequireSpecial {
		if !regexp.MustCompile(`[!@#$%^&*(),.?":{}|<>]`).MatchString(password) {
			return fmt.Errorf("%w: must contain special character", ErrWeakPassword)
		}
	}

	// Check for common weak passwords
	weakPasswords := []string{
		"password", "123456", "12345678", "qwerty", "abc123",
		"monkey", "1234567", "letmein", "trustno1", "dragon",
		"baseball", "111111", "iloveyou", "master", "sunshine",
	}

	lowerPassword := strings.ToLower(password)
	for _, weak := range weakPasswords {
		if lowerPassword == weak {
			return fmt.Errorf("%w: password is too common", ErrWeakPassword)
		}
	}

	return nil
}

// Authentication & Session Management

// CheckLoginAttempts checks if user is locked out
func (sm *SecurityManager) CheckLoginAttempts(identifier string) error {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	// Check if locked out
	if lockoutTime, exists := sm.lockouts[identifier]; exists {
		if time.Since(lockoutTime) < sm.config.LockoutDuration {
			return fmt.Errorf("account locked until %v", lockoutTime.Add(sm.config.LockoutDuration))
		}
		// Lockout expired, remove it
		delete(sm.lockouts, identifier)
		delete(sm.loginAttempts, identifier)
	}

	return nil
}

// RecordLoginAttempt records a login attempt
func (sm *SecurityManager) RecordLoginAttempt(identifier string, success bool) {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if success {
		// Reset attempts on success
		delete(sm.loginAttempts, identifier)
		delete(sm.lockouts, identifier)
		return
	}

	// Increment failed attempts
	sm.loginAttempts[identifier]++

	// Check if should lock out
	if sm.loginAttempts[identifier] >= sm.config.MaxLoginAttempts {
		sm.lockouts[identifier] = time.Now()
		sm.logger.Warn("Account locked due to failed login attempts",
			zap.String("identifier", identifier),
			zap.Int("attempts", sm.loginAttempts[identifier]))
	}
}

// GenerateSecureToken generates a secure random token
func (sm *SecurityManager) GenerateSecureToken(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(bytes), nil
}

// GenerateCSRFToken generates a CSRF token
func (sm *SecurityManager) GenerateCSRFToken() (string, error) {
	return sm.GenerateSecureToken(sm.config.CSRFTokenLength)
}

// Rate Limiting

// GetRateLimiter gets or creates a rate limiter for an identifier
func (sm *SecurityManager) GetRateLimiter(identifier string, rps int, burst int) *rate.Limiter {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if limiter, exists := sm.rateLimiters[identifier]; exists {
		return limiter
	}

	limiter := rate.NewLimiter(rate.Limit(rps), burst)
	sm.rateLimiters[identifier] = limiter
	return limiter
}

// CheckRateLimit checks if request is rate limited
func (sm *SecurityManager) CheckRateLimit(identifier string, rps int, burst int) error {
	limiter := sm.GetRateLimiter(identifier, rps, burst)
	if !limiter.Allow() {
		return ErrRateLimitExceeded
	}
	return nil
}

// Input validation helpers

func (sm *SecurityManager) validateEmail(email string) error {
	pattern := `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`
	if !regexp.MustCompile(pattern).MatchString(email) {
		return fmt.Errorf("%w: invalid email format", ErrInvalidInput)
	}
	return nil
}

func (sm *SecurityManager) validatePhone(phone string) error {
	pattern := `^\+?[1-9]\d{1,14}$`
	if !regexp.MustCompile(pattern).MatchString(phone) {
		return fmt.Errorf("%w: invalid phone format", ErrInvalidInput)
	}
	return nil
}

func (sm *SecurityManager) validateAlphanumeric(input string) error {
	pattern := `^[a-zA-Z0-9]+$`
	if !regexp.MustCompile(pattern).MatchString(input) {
		return fmt.Errorf("%w: must be alphanumeric", ErrInvalidInput)
	}
	return nil
}

func (sm *SecurityManager) validateNumeric(input string) error {
	pattern := `^[0-9]+$`
	if !regexp.MustCompile(pattern).MatchString(input) {
		return fmt.Errorf("%w: must be numeric", ErrInvalidInput)
	}
	return nil
}

func (sm *SecurityManager) validateURL(url string) error {
	pattern := `^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$`
	if !regexp.MustCompile(pattern).MatchString(url) {
		return fmt.Errorf("%w: invalid URL format", ErrInvalidInput)
	}
	return nil
}

// SecurityHeaders returns security-related HTTP headers
func (sm *SecurityManager) SecurityHeaders() map[string]string {
	return map[string]string{
		"X-Content-Type-Options":    "nosniff",
		"X-Frame-Options":           "DENY",
		"X-XSS-Protection":          "1; mode=block",
		"Strict-Transport-Security": "max-age=31536000; includeSubDomains",
		"Content-Security-Policy":   "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'",
		"Referrer-Policy":           "strict-origin-when-cross-origin",
		"Permissions-Policy":        "geolocation=(), microphone=(), camera=()",
	}
}