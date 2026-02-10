package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
)

// =====================================================
// Notification Constants
// =====================================================

// NotificationChannel - Delivery channels
type NotificationChannel string

const (
	NotificationChannelInApp    NotificationChannel = "in_app"
	NotificationChannelPush     NotificationChannel = "push"
	NotificationChannelEmail    NotificationChannel = "email"
	NotificationChannelSMS      NotificationChannel = "sms"
	NotificationChannelWhatsApp NotificationChannel = "whatsapp"
)

// NotificationCategory - Categories for notifications
type NotificationCategory string

const (
	NotificationCategoryAlert      NotificationCategory = "alert"
	NotificationCategoryAudit      NotificationCategory = "audit"
	NotificationCategorySales      NotificationCategory = "sales"
	NotificationCategoryInventory  NotificationCategory = "inventory"
	NotificationCategoryFinance    NotificationCategory = "finance"
	NotificationCategoryTips       NotificationCategory = "tips"
	NotificationCategorySystem     NotificationCategory = "system"
	NotificationCategoryApproval   NotificationCategory = "approval"
)

// NotificationPriority - Priority levels
type NotificationPriority string

const (
	NotificationPriorityLow      NotificationPriority = "low"
	NotificationPriorityNormal   NotificationPriority = "normal"
	NotificationPriorityHigh     NotificationPriority = "high"
	NotificationPriorityCritical NotificationPriority = "critical"
)

// NotificationStatus - Status of notification
type NotificationStatus string

const (
	NotificationStatusPending   NotificationStatus = "pending"
	NotificationStatusSent      NotificationStatus = "sent"
	NotificationStatusDelivered NotificationStatus = "delivered"
	NotificationStatusRead      NotificationStatus = "read"
	NotificationStatusFailed    NotificationStatus = "failed"
)

// DeliveryStatus - Status of delivery attempt
type DeliveryStatus string

const (
	DeliveryStatusPending   DeliveryStatus = "pending"
	DeliveryStatusSent      DeliveryStatus = "sent"
	DeliveryStatusDelivered DeliveryStatus = "delivered"
	DeliveryStatusFailed    DeliveryStatus = "failed"
	DeliveryStatusBounced   DeliveryStatus = "bounced"
)

// DigestFrequency - Frequency of digest notifications
type DigestFrequency string

const (
	DigestFrequencyHourly  DigestFrequency = "hourly"
	DigestFrequencyDaily   DigestFrequency = "daily"
	DigestFrequencyWeekly  DigestFrequency = "weekly"
)

// =====================================================
// Notification Preference Model
// =====================================================

// ChannelSettings stores channel preferences as JSONB
type ChannelSettings struct {
	InApp    bool `json:"in_app"`
	Push     bool `json:"push"`
	Email    bool `json:"email"`
	SMS      bool `json:"sms"`
	WhatsApp bool `json:"whatsapp"`
}

// Scan implements sql.Scanner for ChannelSettings
func (c *ChannelSettings) Scan(value interface{}) error {
	if value == nil {
		*c = ChannelSettings{InApp: true, Push: true, Email: true}
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed for ChannelSettings")
	}
	return json.Unmarshal(bytes, c)
}

// Value implements driver.Valuer for ChannelSettings
func (c ChannelSettings) Value() (driver.Value, error) {
	return json.Marshal(c)
}

// AlertTypeSettings stores alert type preferences as JSONB
type AlertTypeSettings struct {
	LowStock            bool `json:"low_stock"`
	CashShortage        bool `json:"cash_shortage"`
	AuditReminder       bool `json:"audit_reminder"`
	BudgetExceeded      bool `json:"budget_exceeded"`
	CollectionOverdue   bool `json:"collection_overdue"`
	InventoryShrinkage  bool `json:"inventory_shrinkage"`
	SuspiciousActivity  bool `json:"suspicious_activity"`
}

// Scan implements sql.Scanner for AlertTypeSettings
func (a *AlertTypeSettings) Scan(value interface{}) error {
	if value == nil {
		*a = AlertTypeSettings{LowStock: true, CashShortage: true, AuditReminder: true, BudgetExceeded: true, CollectionOverdue: true, InventoryShrinkage: true, SuspiciousActivity: true}
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed for AlertTypeSettings")
	}
	return json.Unmarshal(bytes, a)
}

// Value implements driver.Valuer for AlertTypeSettings
func (a AlertTypeSettings) Value() (driver.Value, error) {
	return json.Marshal(a)
}

// CategorySettings stores category preferences as JSONB
type CategorySettings struct {
	Sales     bool `json:"sales"`
	Inventory bool `json:"inventory"`
	Finance   bool `json:"finance"`
	Security  bool `json:"security"`
	System    bool `json:"system"`
}

// Scan implements sql.Scanner for CategorySettings
func (c *CategorySettings) Scan(value interface{}) error {
	if value == nil {
		*c = CategorySettings{Sales: true, Inventory: true, Finance: true, Security: true, System: true}
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed for CategorySettings")
	}
	return json.Unmarshal(bytes, c)
}

// Value implements driver.Valuer for CategorySettings
func (c CategorySettings) Value() (driver.Value, error) {
	return json.Marshal(c)
}

// Reminder represents a user-configurable reminder
type Reminder struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Category    string   `json:"category"`
	Enabled     bool     `json:"enabled"`
	Time        string   `json:"time"`
	Days        []string `json:"days"`
}

// ReminderSlice is a helper type for JSONB reminder arrays
type ReminderSlice []Reminder

// Scan implements sql.Scanner for ReminderSlice
func (r *ReminderSlice) Scan(value interface{}) error {
	if value == nil {
		*r = ReminderSlice{}
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed for ReminderSlice")
	}
	return json.Unmarshal(bytes, r)
}

// Value implements driver.Valuer for ReminderSlice
func (r ReminderSlice) Value() (driver.Value, error) {
	if r == nil {
		return json.Marshal([]Reminder{})
	}
	return json.Marshal(r)
}

// StringSlice is a helper type for JSONB string arrays
type StringSlice []string

// Scan implements sql.Scanner for StringSlice
func (s *StringSlice) Scan(value interface{}) error {
	if value == nil {
		*s = StringSlice{}
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed for StringSlice")
	}
	return json.Unmarshal(bytes, s)
}

// Value implements driver.Valuer for StringSlice
func (s StringSlice) Value() (driver.Value, error) {
	if s == nil {
		return json.Marshal([]string{})
	}
	return json.Marshal(s)
}

// NotificationPreference stores user notification preferences
// Matches the actual database schema with JSONB fields
type NotificationPreference struct {
	ID                      uuid.UUID         `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID                uuid.UUID         `json:"tenant_id" gorm:"type:uuid;not null;index:idx_notification_prefs_tenant"`
	UserID                  uuid.UUID         `json:"user_id" gorm:"type:uuid;not null;uniqueIndex:uq_notification_preferences;index:idx_notification_prefs_user"`
	Channels                ChannelSettings   `json:"channels" gorm:"type:jsonb"`
	AlertTypes              AlertTypeSettings `json:"alert_types" gorm:"type:jsonb"`
	Categories              CategorySettings  `json:"categories" gorm:"type:jsonb"`
	Reminders               ReminderSlice     `json:"reminders" gorm:"type:jsonb"`
	MinimumSeverity         string            `json:"minimum_severity" gorm:"type:varchar(20);default:'info'"`
	QuietHoursEnabled       bool              `json:"quiet_hours_enabled" gorm:"default:false"`
	QuietHoursStart         string            `json:"quiet_hours_start" gorm:"type:time;default:'22:00:00'"`
	QuietHoursEnd           string            `json:"quiet_hours_end" gorm:"type:time;default:'07:00:00'"`
	QuietHoursExceptions    StringSlice       `json:"quiet_hours_exceptions" gorm:"type:jsonb"`
	DigestMode              bool              `json:"digest_mode" gorm:"default:false"`
	DigestFrequency         string            `json:"digest_frequency" gorm:"type:varchar(20);default:'daily'"`
	MaxNotificationsPerHour int               `json:"max_notifications_per_hour" gorm:"default:10"`
	PushTokens              StringSlice       `json:"push_tokens" gorm:"type:jsonb"`
	CreatedAt               time.Time         `json:"created_at" gorm:"default:CURRENT_TIMESTAMP"`
	UpdatedAt               time.Time         `json:"updated_at" gorm:"default:CURRENT_TIMESTAMP"`

	// Relationships
	User *User `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

func (NotificationPreference) TableName() string {
	return "notification_preferences"
}

// Helper methods for backward compatibility
func (p *NotificationPreference) InAppEnabled() bool    { return p.Channels.InApp }
func (p *NotificationPreference) PushEnabled() bool     { return p.Channels.Push }
func (p *NotificationPreference) EmailEnabled() bool    { return p.Channels.Email }
func (p *NotificationPreference) SMSEnabled() bool      { return p.Channels.SMS }
func (p *NotificationPreference) WhatsAppEnabled() bool { return p.Channels.WhatsApp }

// =====================================================
// WhatsApp Subscription Model
// =====================================================

// WhatsAppSubscription stores WhatsApp opt-in status
type WhatsAppSubscription struct {
	ID               uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	UserID           uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;index"`
	PhoneNumber      string     `json:"phone_number" gorm:"type:varchar(20);not null"`
	IsVerified       bool       `json:"is_verified" gorm:"default:false"`
	OptInAt          *time.Time `json:"opt_in_at"`
	OptOutAt         *time.Time `json:"opt_out_at"`
	VerificationCode string     `json:"verification_code" gorm:"type:varchar(10)"`
	VerificationExpiry *time.Time `json:"verification_expiry"`
	LastMessageAt    *time.Time `json:"last_message_at"`
	MessageCount     int        `json:"message_count" gorm:"default:0"`
	Status           string     `json:"status" gorm:"type:varchar(20);default:'pending'"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`

	// Relationships
	User             *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

func (WhatsAppSubscription) TableName() string {
	return "whatsapp_subscriptions"
}

// =====================================================
// Notification Model
// =====================================================

// Notification represents a notification to be sent
type Notification struct {
	ID               uuid.UUID            `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID            `json:"tenant_id" gorm:"type:uuid;not null;index"`
	UserID           uuid.UUID            `json:"user_id" gorm:"type:uuid;not null;index"`
	TemplateID       *uuid.UUID           `json:"template_id" gorm:"type:uuid;index"`
	Category         NotificationCategory `json:"category" gorm:"type:varchar(30);not null"`
	Priority         NotificationPriority `json:"priority" gorm:"type:varchar(20);default:'normal'"`
	Title            string               `json:"title" gorm:"type:varchar(200);not null"`
	Body             string               `json:"body" gorm:"type:text;not null"`
	Data             interface{}          `json:"data" gorm:"type:jsonb"`
	ActionURL        string               `json:"action_url" gorm:"type:varchar(500)"`
	ActionLabel      string               `json:"action_label" gorm:"type:varchar(50)"`
	ImageURL         string               `json:"image_url" gorm:"type:varchar(500)"`
	Status           NotificationStatus   `json:"status" gorm:"type:varchar(20);default:'pending'"`
	ReadAt           *time.Time           `json:"read_at"`
	ExpiresAt        *time.Time           `json:"expires_at"`
	GroupID          string               `json:"group_id" gorm:"type:varchar(100);index"`
	DigestID         *uuid.UUID           `json:"digest_id" gorm:"type:uuid;index"`
	CreatedAt        time.Time            `json:"created_at"`
	UpdatedAt        time.Time            `json:"updated_at"`

	// Relationships
	User             *User                `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Template         *NotificationTemplate `json:"template,omitempty" gorm:"foreignKey:TemplateID"`
	Deliveries       []NotificationDelivery `json:"deliveries,omitempty" gorm:"foreignKey:NotificationID"`
}

func (Notification) TableName() string {
	return "notifications"
}

// =====================================================
// Notification Delivery Model
// =====================================================

// NotificationDelivery tracks delivery attempts per channel
type NotificationDelivery struct {
	ID               uuid.UUID           `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID           `json:"tenant_id" gorm:"type:uuid;not null;index"`
	NotificationID   uuid.UUID           `json:"notification_id" gorm:"type:uuid;not null;index"`
	Channel          NotificationChannel `json:"channel" gorm:"type:varchar(20);not null"`
	Status           DeliveryStatus      `json:"status" gorm:"type:varchar(20);default:'pending'"`
	Recipient        string              `json:"recipient" gorm:"type:varchar(200)"`
	ExternalID       string              `json:"external_id" gorm:"type:varchar(100)"`
	Provider         string              `json:"provider" gorm:"type:varchar(50)"`
	AttemptCount     int                 `json:"attempt_count" gorm:"default:0"`
	LastAttemptAt    *time.Time          `json:"last_attempt_at"`
	SentAt           *time.Time          `json:"sent_at"`
	DeliveredAt      *time.Time          `json:"delivered_at"`
	FailedAt         *time.Time          `json:"failed_at"`
	ErrorMessage     string              `json:"error_message" gorm:"type:text"`
	Metadata         interface{}         `json:"metadata" gorm:"type:jsonb"`
	CreatedAt        time.Time           `json:"created_at"`
	UpdatedAt        time.Time           `json:"updated_at"`

	// Relationships
	Notification     *Notification       `json:"notification,omitempty" gorm:"foreignKey:NotificationID"`
}

func (NotificationDelivery) TableName() string {
	return "notification_deliveries"
}

// =====================================================
// Notification Template Model
// =====================================================

// NotificationTemplate stores reusable notification templates
type NotificationTemplate struct {
	ID                uuid.UUID            `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          *uuid.UUID           `json:"tenant_id" gorm:"type:uuid;index"`
	Name              string               `json:"name" gorm:"type:varchar(100);not null"`
	Code              string               `json:"code" gorm:"type:varchar(50);uniqueIndex;not null"`
	Category          NotificationCategory `json:"category" gorm:"type:varchar(30);not null"`
	DefaultPriority   NotificationPriority `json:"default_priority" gorm:"type:varchar(20);default:'normal'"`
	TitleTemplate     string               `json:"title_template" gorm:"type:text;not null"`
	BodyTemplate      string               `json:"body_template" gorm:"type:text;not null"`
	EmailSubject      string               `json:"email_subject" gorm:"type:varchar(200)"`
	EmailBody         string               `json:"email_body" gorm:"type:text"`
	SMSTemplate       string               `json:"sms_template" gorm:"type:text"`
	WhatsAppTemplate  string               `json:"whatsapp_template" gorm:"type:text"`
	WhatsAppTemplateID string              `json:"whatsapp_template_id" gorm:"type:varchar(100)"`
	Variables         []string             `json:"variables" gorm:"type:jsonb"`
	IsSystem          bool                 `json:"is_system" gorm:"default:false"`
	IsActive          bool                 `json:"is_active" gorm:"default:true"`
	CreatedAt         time.Time            `json:"created_at"`
	UpdatedAt         time.Time            `json:"updated_at"`
}

func (NotificationTemplate) TableName() string {
	return "notification_templates"
}

// =====================================================
// Notification Digest Model
// =====================================================

// NotificationDigest stores batched notifications
type NotificationDigest struct {
	ID                uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	UserID            uuid.UUID       `json:"user_id" gorm:"type:uuid;not null;index"`
	DigestFrequency   DigestFrequency `json:"digest_frequency" gorm:"type:varchar(20);not null"`
	PeriodStart       time.Time       `json:"period_start" gorm:"not null"`
	PeriodEnd         time.Time       `json:"period_end" gorm:"not null"`
	NotificationCount int             `json:"notification_count" gorm:"default:0"`
	Categories        interface{}     `json:"categories" gorm:"type:jsonb"`
	Status            string          `json:"status" gorm:"type:varchar(20);default:'pending'"`
	SentAt            *time.Time      `json:"sent_at"`
	CreatedAt         time.Time       `json:"created_at"`

	// Relationships
	User              *User           `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Notifications     []Notification  `json:"notifications,omitempty" gorm:"foreignKey:DigestID"`
}

func (NotificationDigest) TableName() string {
	return "notification_digests"
}

// =====================================================
// Notification Rate Limit Model
// =====================================================

// NotificationRateLimit tracks rate limiting
type NotificationRateLimit struct {
	ID               uuid.UUID           `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID           `json:"tenant_id" gorm:"type:uuid;not null;index"`
	UserID           uuid.UUID           `json:"user_id" gorm:"type:uuid;not null;index"`
	Channel          NotificationChannel `json:"channel" gorm:"type:varchar(20);not null"`
	WindowStart      time.Time           `json:"window_start" gorm:"not null"`
	WindowEnd        time.Time           `json:"window_end" gorm:"not null"`
	Count            int                 `json:"count" gorm:"default:0"`
	Limit            int                 `json:"limit" gorm:"not null"`
	CreatedAt        time.Time           `json:"created_at"`
	UpdatedAt        time.Time           `json:"updated_at"`

	// Relationships
	User             *User               `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

func (NotificationRateLimit) TableName() string {
	return "notification_rate_limits"
}

// =====================================================
// Notification Device Model (FCM Token Storage)
// =====================================================

// NotificationDevice stores FCM tokens per device for push notifications
type NotificationDevice struct {
	ID         uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID     uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;index"`
	TenantID   uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	FCMToken   string     `json:"fcm_token" gorm:"type:text;not null;uniqueIndex"`
	DeviceID   string     `json:"device_id" gorm:"type:text;not null"`
	Platform   string     `json:"platform" gorm:"type:varchar(10);not null"` // ios, android, web
	DeviceName string     `json:"device_name" gorm:"type:text"`
	AppVersion string     `json:"app_version" gorm:"type:text"`
	IsActive   bool       `json:"is_active" gorm:"default:true"`
	LastUsedAt *time.Time `json:"last_used_at"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`

	// Relationships
	User *User `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

func (NotificationDevice) TableName() string {
	return "notification_devices"
}

// =====================================================
// Request/Response DTOs
// =====================================================

// UpdatePreferencesRequest - Update notification preferences
// All fields are optional - only provided fields will be updated
type UpdatePreferencesRequest struct {
	// Channel settings
	Channels *ChannelSettings `json:"channels"`

	// Alert type settings
	AlertTypes *AlertTypeSettings `json:"alert_types"`

	// Category settings
	Categories *CategorySettings `json:"categories"`

	// User-configurable reminders
	Reminders *ReminderSlice `json:"reminders"`

	// Individual channel toggles (backward compatibility)
	InAppEnabled    *bool `json:"in_app_enabled"`
	PushEnabled     *bool `json:"push_enabled"`
	EmailEnabled    *bool `json:"email_enabled"`
	SMSEnabled      *bool `json:"sms_enabled"`
	WhatsAppEnabled *bool `json:"whatsapp_enabled"`

	// Severity and quiet hours
	MinimumSeverity      *string  `json:"minimum_severity"`
	QuietHoursEnabled    *bool    `json:"quiet_hours_enabled"`
	QuietHoursStart      *string  `json:"quiet_hours_start"`
	QuietHoursEnd        *string  `json:"quiet_hours_end"`
	QuietHoursExceptions []string `json:"quiet_hours_exceptions"`

	// Digest settings
	DigestMode      *bool   `json:"digest_mode"`
	DigestFrequency *string `json:"digest_frequency"`

	// Rate limiting
	MaxNotificationsPerHour *int `json:"max_notifications_per_hour"`
}

// NotificationAction represents an actionable button in notifications
type NotificationAction struct {
	Action string `json:"action"`          // Action identifier: "approve", "reject", "view", "dismiss"
	Label  string `json:"label"`           // Display text: "Approve", "Reject", "View Details"
	Icon   string `json:"icon,omitempty"`  // Icon name: "ic_approve", "ic_reject"
	Style  string `json:"style,omitempty"` // Button style: "primary", "destructive", "default"
	URL    string `json:"url,omitempty"`   // Deep link URL when action is tapped
}

// SendNotificationRequest - Send a notification
type SendNotificationRequest struct {
	UserID       uuid.UUID             `json:"user_id" binding:"required"`
	TemplateCode string                `json:"template_code"`
	Category     NotificationCategory  `json:"category"`
	Priority     NotificationPriority  `json:"priority"`
	Title        string                `json:"title"`
	Body         string                `json:"body"`
	Data         map[string]interface{} `json:"data"`
	ActionURL    string                `json:"action_url"`
	ActionLabel  string                `json:"action_label"`
	Channels     []NotificationChannel `json:"channels"`
	GroupID      string                `json:"group_id"`
	// Modern notification features
	Actions      []NotificationAction  `json:"actions,omitempty"`       // Action buttons (max 3)
	ThreadID     string                `json:"thread_id,omitempty"`     // iOS threading - groups related notifications
	ChannelID    string                `json:"channel_id,omitempty"`    // Android channel ID for categorization
	ImageURL     string                `json:"image_url,omitempty"`     // Rich media image
	CollapseKey  string                `json:"collapse_key,omitempty"`  // Replace previous notification with same key
}

// BulkNotificationRequest - Send to multiple users
type BulkNotificationRequest struct {
	UserIDs      []uuid.UUID            `json:"user_ids" binding:"required,min=1"`
	RoleFilter   []string               `json:"role_filter"`
	ShopFilter   []uuid.UUID            `json:"shop_filter"`
	TemplateCode string                 `json:"template_code"`
	Category     NotificationCategory   `json:"category"`
	Priority     NotificationPriority   `json:"priority"`
	Title        string                 `json:"title"`
	Body         string                 `json:"body"`
	Data         map[string]interface{} `json:"data"`
	ActionURL    string                 `json:"action_url"`
	Channels     []NotificationChannel  `json:"channels"`
}

// WhatsAppOptInRequest - Request WhatsApp opt-in
type WhatsAppOptInRequest struct {
	PhoneNumber string `json:"phone_number" binding:"required"`
}

// WhatsAppVerifyRequest - Verify WhatsApp number
type WhatsAppVerifyRequest struct {
	Code string `json:"code" binding:"required"`
}

// MarkReadRequest - Mark notifications as read
type MarkReadRequest struct {
	NotificationIDs []uuid.UUID `json:"notification_ids" binding:"required,min=1"`
}

// NotificationListResponse - Paginated notification list
type NotificationListResponse struct {
	Notifications []Notification `json:"notifications"`
	Total         int64          `json:"total"`
	Page          int            `json:"page"`
	PageSize      int            `json:"page_size"`
	UnreadCount   int64          `json:"unread_count"`
}

// NotificationCountResponse - Notification counts
type NotificationCountResponse struct {
	Total    int64                        `json:"total"`
	Unread   int64                        `json:"unread"`
	ByCategory map[NotificationCategory]int64 `json:"by_category"`
	ByPriority map[NotificationPriority]int64 `json:"by_priority"`
}

// PreferenceSummaryResponse - User preference summary
type PreferenceSummaryResponse struct {
	Preferences []NotificationPreference `json:"preferences"`
	WhatsApp    *WhatsAppSubscription    `json:"whatsapp"`
	PushTokens  []PushTokenInfo          `json:"push_tokens"`
}

// PushTokenInfo - Push token information
type PushTokenInfo struct {
	DeviceID   string    `json:"device_id"`
	Platform   string    `json:"platform"`
	RegisteredAt time.Time `json:"registered_at"`
	LastUsedAt *time.Time `json:"last_used_at"`
}

// CreateTemplateRequest - Create notification template
type CreateTemplateRequest struct {
	Name              string               `json:"name" binding:"required,max=100"`
	Code              string               `json:"code" binding:"required,max=50"`
	Category          NotificationCategory `json:"category" binding:"required"`
	DefaultPriority   NotificationPriority `json:"default_priority"`
	TitleTemplate     string               `json:"title_template" binding:"required"`
	BodyTemplate      string               `json:"body_template" binding:"required"`
	EmailSubject      string               `json:"email_subject"`
	EmailBody         string               `json:"email_body"`
	SMSTemplate       string               `json:"sms_template"`
	WhatsAppTemplate  string               `json:"whatsapp_template"`
	WhatsAppTemplateID string              `json:"whatsapp_template_id"`
	Variables         []string             `json:"variables"`
}

// NotificationStats - Statistics for notifications
type NotificationStats struct {
	TotalSent       int64                              `json:"total_sent"`
	TotalDelivered  int64                              `json:"total_delivered"`
	TotalRead       int64                              `json:"total_read"`
	TotalFailed     int64                              `json:"total_failed"`
	DeliveryRate    float64                            `json:"delivery_rate"`
	ReadRate        float64                            `json:"read_rate"`
	ByChannel       map[NotificationChannel]ChannelStats `json:"by_channel"`
	ByCategory      map[NotificationCategory]int64      `json:"by_category"`
	DailyTrend      []DailyNotificationStat            `json:"daily_trend"`
}

// ChannelStats - Statistics per channel
type ChannelStats struct {
	Sent        int64   `json:"sent"`
	Delivered   int64   `json:"delivered"`
	Failed      int64   `json:"failed"`
	AvgDeliveryTime float64 `json:"avg_delivery_time_seconds"`
}

// DailyNotificationStat - Daily notification statistics
type DailyNotificationStat struct {
	Date      time.Time `json:"date"`
	Sent      int64     `json:"sent"`
	Delivered int64     `json:"delivered"`
	Read      int64     `json:"read"`
	Failed    int64     `json:"failed"`
}

// =====================================================
// Device Registration DTOs (Frontend Alignment)
// =====================================================

// RegisterDeviceRequest - Frontend sends this on login to register FCM token
type RegisterDeviceRequest struct {
	FCMToken   string `json:"token" binding:"required"`
	DeviceID   string `json:"device_id" binding:"required"`
	Platform   string `json:"platform" binding:"required,oneof=ios android web"`
	DeviceName string `json:"device_name"`
	AppVersion string `json:"app_version"`
}

// UnregisterDeviceRequest - Frontend sends this on logout
type UnregisterDeviceRequest struct {
	FCMToken string `json:"token" binding:"required"`
}

// DeviceRegistrationResponse - Response for device registration
type DeviceRegistrationResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// UnreadCountResponse - Simple unread count response for frontend
type UnreadCountResponse struct {
	Success bool `json:"success"`
	Data    struct {
		Count int64 `json:"count"`
	} `json:"data"`
}

// ChannelStatusInfo - Status of a notification channel
type ChannelStatusInfo struct {
	Name          string     `json:"name"`
	Description   string     `json:"description"`
	IsConfigured  bool       `json:"is_configured"`
	IsEnabled     bool       `json:"is_enabled"`
	LastError     *string    `json:"last_error"`
	LastSuccessAt *time.Time `json:"last_success_at"`
	SuccessCount  int64      `json:"success_count"`
	FailureCount  int64      `json:"failure_count"`
}

// ChannelStatusResponse - Response for channel status endpoint
type ChannelStatusResponse struct {
	Success bool                `json:"success"`
	Data    []ChannelStatusInfo `json:"data"`
}

// APIResponse - Generic API response wrapper for frontend alignment
type APIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// NotificationListResponseV2 - Updated response format for frontend alignment
type NotificationListResponseV2 struct {
	Success bool `json:"success"`
	Data    struct {
		Notifications []Notification `json:"notifications"`
		TotalCount    int64          `json:"total_count"`
		UnreadCount   int64          `json:"unread_count"`
		Page          int            `json:"page"`
		PageSize      int            `json:"page_size"`
		HasMore       bool           `json:"has_more"`
	} `json:"data"`
}

// ReminderSentLog tracks which reminders have been sent to prevent duplicate notifications
type ReminderSentLog struct {
	ID           uuid.UUID `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID     uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null"`
	UserID       uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	ReminderType string    `json:"reminder_type" gorm:"type:varchar(100);not null"`
	ReminderDate time.Time `json:"reminder_date" gorm:"type:date;not null"`
	SentAt       time.Time `json:"sent_at" gorm:"not null;default:now()"`
}
