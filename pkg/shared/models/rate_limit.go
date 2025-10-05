package models

import (
	"time"

	"github.com/google/uuid"
)

// RateLimit represents dynamic rate limiting configuration
type RateLimit struct {
	BaseModel

	// Rate limit identification
	Name        string `json:"name" gorm:"unique;not null"` // e.g., "otp_requests", "login_attempts"
	Description string `json:"description"`

	// Rate limit configuration
	MaxAttempts   int           `json:"max_attempts" gorm:"not null"`   // Maximum attempts allowed
	TimeWindow    time.Duration `json:"time_window" gorm:"not null"`    // Time window in seconds
	BlockDuration time.Duration `json:"block_duration" gorm:"not null"` // How long to block after exceeding limit

	// Tenant-specific configuration (NULL for global limits)
	TenantID *uuid.UUID `json:"tenant_id" gorm:"type:uuid;index"`
	Tenant   *Tenant    `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`

	// Configuration metadata
	IsActive bool `json:"is_active" gorm:"default:true"`
	IsGlobal bool `json:"is_global" gorm:"default:false"` // If true, applies to all tenants
	Priority int  `json:"priority" gorm:"default:100"`    // Higher priority overrides lower

	// Additional settings as JSON
	Settings string `json:"settings"` // JSON field for additional configurations

	// Management fields
	CreatedByID uuid.UUID  `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User      `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	UpdatedByID *uuid.UUID `json:"updated_by_id" gorm:"type:uuid"`
	UpdatedBy   *User      `json:"updated_by,omitempty" gorm:"foreignKey:UpdatedByID"`
}

// RateLimitLog tracks rate limit violations and usage
type RateLimitLog struct {
	BaseModel

	RateLimitID uuid.UUID  `json:"rate_limit_id" gorm:"type:uuid;not null"`
	RateLimit   *RateLimit `json:"rate_limit,omitempty" gorm:"foreignKey:RateLimitID"`

	// Request details
	Identifier string `json:"identifier" gorm:"not null;index"` // IP, phone, user_id, etc.
	RequestIP  string `json:"request_ip"`
	UserAgent  string `json:"user_agent"`

	// Tenant context
	TenantID *uuid.UUID `json:"tenant_id" gorm:"type:uuid;index"`
	Tenant   *Tenant    `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`

	// Rate limit status
	AttemptCount int        `json:"attempt_count" gorm:"not null"`
	IsBlocked    bool       `json:"is_blocked" gorm:"default:false"`
	BlockedUntil *time.Time `json:"blocked_until"`
	WindowStart  time.Time  `json:"window_start" gorm:"not null"`
	WindowEnd    time.Time  `json:"window_end" gorm:"not null"`

	// Additional context
	RequestPath   string `json:"request_path"`
	RequestMethod string `json:"request_method"`
	ResponseCode  int    `json:"response_code"`

	// Associated user if applicable
	UserID *uuid.UUID `json:"user_id" gorm:"type:uuid"`
	User   *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

// Rate limit types constants
const (
	RateLimitOTPRequest    = "otp_requests"
	RateLimitLoginAttempt  = "login_attempts"
	RateLimitAPIRequest    = "api_requests"
	RateLimitPasswordReset = "password_reset"
	RateLimitRegistration  = "registration"
)

// Default rate limit configurations
var DefaultRateLimits = []RateLimit{
	{
		Name:          RateLimitOTPRequest,
		Description:   "OTP request rate limiting",
		MaxAttempts:   5,
		TimeWindow:    time.Minute * 15, // 15 minutes
		BlockDuration: time.Hour * 1,    // 1 hour block
		IsActive:      true,
		IsGlobal:      true,
		Priority:      100,
	},
	{
		Name:          RateLimitLoginAttempt,
		Description:   "Login attempt rate limiting",
		MaxAttempts:   10,
		TimeWindow:    time.Minute * 30, // 30 minutes
		BlockDuration: time.Hour * 2,    // 2 hour block
		IsActive:      true,
		IsGlobal:      true,
		Priority:      100,
	},
	{
		Name:          RateLimitAPIRequest,
		Description:   "General API request rate limiting",
		MaxAttempts:   1000,
		TimeWindow:    time.Hour * 1,    // 1 hour
		BlockDuration: time.Minute * 15, // 15 minute block
		IsActive:      true,
		IsGlobal:      true,
		Priority:      50,
	},
	{
		Name:          RateLimitPasswordReset,
		Description:   "Password reset request rate limiting",
		MaxAttempts:   3,
		TimeWindow:    time.Hour * 24, // 24 hours
		BlockDuration: time.Hour * 24, // 24 hour block
		IsActive:      true,
		IsGlobal:      true,
		Priority:      100,
	},
	{
		Name:          RateLimitRegistration,
		Description:   "User registration rate limiting",
		MaxAttempts:   5,
		TimeWindow:    time.Hour * 24, // 24 hours
		BlockDuration: time.Hour * 24, // 24 hour block
		IsActive:      true,
		IsGlobal:      true,
		Priority:      100,
	},
}
