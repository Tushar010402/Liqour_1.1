package models

import (
	"github.com/google/uuid"
	"time"
)

// User represents system users with role-based access
// Note: TenantID can be NULL for Super Users (SaaS admins)
type User struct {
	BaseModel
	TenantID     *uuid.UUID `json:"tenant_id" gorm:"type:uuid;index"` // NULL for Super Users
	Tenant       *Tenant    `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`
	Username     string     `json:"username" gorm:"unique;not null"`
	Email        string     `json:"email" gorm:"unique;not null"`
	FirstName    string     `json:"first_name"`
	LastName     string     `json:"last_name"`
	Phone        string     `json:"phone" gorm:"not null;index"` // Primary unique key for OTP-based auth - uniqueness handled at app level
	PasswordHash string     `json:"-" gorm:"not null"`
	Role         string     `json:"role" gorm:"not null;default:'salesman'"`
	CustomRole   string     `json:"custom_role"`
	IsActive     bool       `json:"is_active" gorm:"default:true"`
	IsStaff      bool       `json:"is_staff" gorm:"default:false"`
	IsSuperuser  bool       `json:"is_superuser" gorm:"default:false"`

	// Profile fields
	ProfileImage string `json:"profile_image"`

	// Account deletion grace period (30 days)
	DeletionRequestedAt  *time.Time `json:"deletion_requested_at,omitempty" gorm:"column:deletion_requested_at"`
	DeletionScheduledFor *time.Time `json:"deletion_scheduled_for,omitempty" gorm:"column:deletion_scheduled_for"`
	DeletionReason       string     `json:"deletion_reason,omitempty" gorm:"column:deletion_reason"`

	// Relationships
	TenantRoles       []TenantRole       `json:"tenant_roles,omitempty" gorm:"foreignKey:UserID"`
	TenantPermissions []TenantPermission `json:"tenant_permissions,omitempty" gorm:"foreignKey:UserID"`
	Salesman          *Salesman          `json:"salesman,omitempty" gorm:"foreignKey:UserID"`

	// Sales and finance relationships
	CreatedSales      []Sale             `json:"created_sales,omitempty" gorm:"foreignKey:CreatedByID"`
	ApprovedSales     []Sale             `json:"approved_sales,omitempty" gorm:"foreignKey:ApprovedByID"`
	CreatedReturns    []SaleReturn       `json:"created_returns,omitempty" gorm:"foreignKey:CreatedByID"`
	ApprovedReturns   []SaleReturn       `json:"approved_returns,omitempty" gorm:"foreignKey:ApprovedByID"`
	ExecutiveFinances []ExecutiveFinance `json:"executive_finances,omitempty" gorm:"foreignKey:CreatedByID"`
	MoneyCollections  []MoneyCollection  `json:"money_collections,omitempty" gorm:"foreignKey:AssistantManagerID"`
}

// FullName returns the user's full name
func (u *User) FullName() string {
	if u.FirstName != "" && u.LastName != "" {
		return u.FirstName + " " + u.LastName
	}
	if u.FirstName != "" {
		return u.FirstName
	}
	if u.LastName != "" {
		return u.LastName
	}
	return u.Username
}

// TenantRole represents user roles within a specific tenant
type TenantRole struct {
	TenantModel
	UserID      uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	User        *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Role        string    `json:"role" gorm:"not null"`
	Permissions []string  `json:"permissions" gorm:"type:text[]"`
}

// TenantPermission represents specific permissions granted to users
type TenantPermission struct {
	TenantModel
	UserID     uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	User       *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Permission string    `json:"permission" gorm:"not null"`
	Resource   string    `json:"resource"`
	Action     string    `json:"action"`
}

// UserSession represents active user sessions with device tracking
// Supports 2-device login limit like Swiggy/Zomato with industrial-grade security
type UserSession struct {
	BaseModel
	UserID uuid.UUID `json:"user_id" gorm:"type:uuid;not null;index"`
	User   *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`

	// Token management (hashed for security)
	Token        string `json:"-" gorm:"type:varchar(500);uniqueIndex"`
	TokenHash    string `json:"-" gorm:"type:varchar(255);index"`
	RefreshToken string `json:"-" gorm:"type:varchar(500)"`

	// Device identification
	DeviceID   string `json:"device_id" gorm:"type:varchar(255);index"`
	DeviceName string `json:"device_name" gorm:"type:varchar(255)"`
	DeviceType string `json:"device_type" gorm:"type:varchar(50)"` // mobile, web, tablet

	// Device environment
	OSName     string `json:"os_name" gorm:"type:varchar(100)"`
	OSVersion  string `json:"os_version" gorm:"type:varchar(50)"`
	AppVersion string `json:"app_version" gorm:"type:varchar(50)"`

	// Device fingerprinting (fraud detection - like Swiggy/Zomato)
	DeviceFingerprint string `json:"device_fingerprint,omitempty" gorm:"type:varchar(255);index"`
	ScreenResolution  string `json:"screen_resolution,omitempty" gorm:"type:varchar(50)"`
	Timezone          string `json:"timezone,omitempty" gorm:"type:varchar(100)"`
	Language          string `json:"language,omitempty" gorm:"type:varchar(20)"`

	// Network/Location info
	IPAddress     string `json:"ip_address" gorm:"type:varchar(45)"`
	UserAgent     string `json:"-" gorm:"type:text"`
	LoginLocation string `json:"login_location" gorm:"type:varchar(255)"`

	// Session timing
	LastActiveAt *time.Time `json:"last_active_at"`
	ExpiresAt    *time.Time `json:"expires_at"`

	// Logout tracking (for audit trail)
	LogoutAt   *time.Time `json:"logout_at,omitempty"`
	LogoutType string     `json:"logout_type,omitempty" gorm:"type:varchar(50)"` // user_initiated, force_logout_by_new_device, admin_logout, token_expired, security_logout

	// Session state
	IsActive  bool `json:"is_active" gorm:"default:true"`
	IsCurrent bool `json:"is_current" gorm:"default:false"` // Most recently used session

	// Trust and security
	IsTrusted      bool   `json:"is_trusted" gorm:"default:false"`        // User marked device as trusted
	TrustToken     string `json:"-" gorm:"type:varchar(255)"`             // For "Remember this device" feature
	SecurityFlags  int    `json:"security_flags" gorm:"default:0"`        // Bitmap for security events
	RiskScore      int    `json:"risk_score" gorm:"default:0"`            // 0-100, higher = more suspicious
	FailedAttempts int    `json:"failed_attempts" gorm:"default:0"`       // Failed auth attempts on this session
	LoginMethod    string `json:"login_method" gorm:"type:varchar(50)"`   // otp, password, biometric, social
	RefreshCount   int    `json:"refresh_count" gorm:"default:0"`         // Number of token refreshes
	LastRefreshAt  *time.Time `json:"last_refresh_at,omitempty"`          // Last token refresh time
}

// MaxDevicesPerUser is the global limit for concurrent device logins
const MaxDevicesPerUser = 2

// Logout types for audit trail
const (
	LogoutTypeUserInitiated      = "user_initiated"
	LogoutTypeForceByNewDevice   = "force_logout_by_new_device"
	LogoutTypeAdminLogout        = "admin_logout"
	LogoutTypeTokenExpired       = "token_expired"
	LogoutTypeSecurityLogout     = "security_logout"
	LogoutTypeAccountDeletion    = "account_deletion"
	LogoutTypePasswordChange     = "password_change"
	LogoutTypeSessionHijackAlert = "session_hijack_alert"
)

// Login methods
const (
	LoginMethodOTP       = "otp"
	LoginMethodPassword  = "password"
	LoginMethodBiometric = "biometric"
	LoginMethodSocial    = "social"
	LoginMethodTrusted   = "trusted_device"
)

// Security flags (bitmap)
const (
	SecurityFlagNone              = 0
	SecurityFlagIPChanged         = 1 << 0  // 1 - IP address changed mid-session
	SecurityFlagDeviceMismatch    = 1 << 1  // 2 - Device fingerprint mismatch
	SecurityFlagMultipleFailures  = 1 << 2  // 4 - Multiple failed auth attempts
	SecurityFlagSuspiciousPattern = 1 << 3  // 8 - Unusual usage pattern
	SecurityFlagGeoAnomaly        = 1 << 4  // 16 - Impossible travel detected
	SecurityFlagTokenReuse        = 1 << 5  // 32 - Same token used from different device
	SecurityFlagRapidRefresh      = 1 << 6  // 64 - Token refreshed too frequently
)

// Risk score thresholds
const (
	RiskScoreLow      = 25  // Normal operation
	RiskScoreMedium   = 50  // Monitor closely
	RiskScoreHigh     = 75  // Require re-authentication
	RiskScoreCritical = 90  // Force logout
)

// DeviceLimitError is returned when user tries to login from too many devices
type DeviceLimitError struct {
	ActiveSessions []UserSession
	Message        string
	MaxDevices     int
}

func (e *DeviceLimitError) Error() string {
	return e.Message
}

// SessionResponse is the API response format for session data
type SessionResponse struct {
	ID            string    `json:"id"`
	DeviceID      string    `json:"device_id"`
	DeviceName    string    `json:"device_name"`
	DeviceType    string    `json:"device_type"`
	OSName        string    `json:"os_name"`
	OSVersion     string    `json:"os_version"`
	AppVersion    string    `json:"app_version"`
	IPAddress     string    `json:"ip_address"`
	LoginLocation string    `json:"login_location"`
	LastActiveAt  time.Time `json:"last_active_at"`
	LoginAt       time.Time `json:"login_at"`
	IsCurrent     bool      `json:"is_current"`
	IsTrusted     bool      `json:"is_trusted"`
	LoginMethod   string    `json:"login_method,omitempty"`
}

// SecurityEvent represents a security-related event for audit logging
type SecurityEvent struct {
	BaseModel
	UserID      uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;index"`
	SessionID   *uuid.UUID `json:"session_id,omitempty" gorm:"type:uuid;index"`
	EventType   string     `json:"event_type" gorm:"type:varchar(50);not null;index"`
	Severity    string     `json:"severity" gorm:"type:varchar(20);not null"` // info, warning, critical
	IPAddress   string     `json:"ip_address" gorm:"type:varchar(45)"`
	UserAgent   string     `json:"user_agent" gorm:"type:text"`
	DeviceID    string     `json:"device_id" gorm:"type:varchar(255)"`
	Description string     `json:"description" gorm:"type:text"`
	Metadata    string     `json:"metadata" gorm:"type:jsonb"` // Additional context as JSON
	RiskScore   int        `json:"risk_score" gorm:"default:0"`
}

// Security event types
const (
	EventTypeLogin                = "login"
	EventTypeLogout               = "logout"
	EventTypeLoginFailed          = "login_failed"
	EventTypeDeviceLimitReached   = "device_limit_reached"
	EventTypeForceLogout          = "force_logout"
	EventTypeTokenRefresh         = "token_refresh"
	EventTypePasswordChange       = "password_change"
	EventTypeSuspiciousActivity   = "suspicious_activity"
	EventTypeIPChange             = "ip_change"
	EventTypeDeviceChange         = "device_change"
	EventTypeTrustedDeviceAdded   = "trusted_device_added"
	EventTypeTrustedDeviceRemoved = "trusted_device_removed"
	EventTypeOTPSent              = "otp_sent"
	EventTypeOTPVerified          = "otp_verified"
	EventTypeOTPFailed            = "otp_failed"
	EventTypeAccountLocked        = "account_locked"
	EventTypeAccountUnlocked      = "account_unlocked"
)

// Severity levels (defined in finance_matrix.go)
// SeverityInfo, SeverityWarning, SeverityCritical are declared there
