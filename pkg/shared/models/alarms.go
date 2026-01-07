package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// ========================================
// Constants
// ========================================

// Alarm Categories
const (
	AlarmCategoryBusiness  = "business"
	AlarmCategoryScheduled = "scheduled"
	AlarmCategorySystem    = "system"
)

// Alarm Trigger Types
const (
	AlarmTriggerScheduled = "scheduled"
	AlarmTriggerEvent     = "event"
	AlarmTriggerBoth      = "both"
)

// Alarm Priorities
const (
	AlarmPriorityLow      = "low"
	AlarmPriorityNormal   = "normal"
	AlarmPriorityHigh     = "high"
	AlarmPriorityCritical = "critical"
)

// Alarm Instance Statuses
const (
	AlarmStatusActive       = "active"
	AlarmStatusAcknowledged = "acknowledged"
	AlarmStatusResolved     = "resolved"
	AlarmStatusExpired      = "expired"
	AlarmStatusSnoozed      = "snoozed"
)

// Alarm Schedule Types
const (
	AlarmScheduleCron      = "cron"
	AlarmSchedulePreset    = "preset"
	AlarmScheduleEventOnly = "event_only"
)

// Schedule Run Statuses
const (
	ScheduleRunPending   = "pending"
	ScheduleRunRunning   = "running"
	ScheduleRunCompleted = "completed"
	ScheduleRunFailed    = "failed"
	ScheduleRunSkipped   = "skipped"
)

// Alarm Actions (for history)
const (
	AlarmActionTriggered    = "triggered"
	AlarmActionAcknowledged = "acknowledged"
	AlarmActionResolved     = "resolved"
	AlarmActionSnoozed      = "snoozed"
	AlarmActionEscalated    = "escalated"
	AlarmActionExpired      = "expired"
	AlarmActionNoteAdded    = "note_added"
)

// Alarm Codes
const (
	AlarmCodeLowStock               = "low_stock"
	AlarmCodeCashShortage           = "cash_shortage"
	AlarmCodeCollectionOverdue      = "collection_overdue"
	AlarmCodeHighDiscountUsage      = "high_discount_usage"
	AlarmCodeSalesAnomaly           = "sales_anomaly"
	AlarmCodeDailySalesSummary      = "daily_sales_summary"
	AlarmCodeWeeklyReport           = "weekly_report"
	AlarmCodeAuditReminder          = "audit_reminder"
	AlarmCodeEndOfDayReport         = "end_of_day_report"
	AlarmCodeUsageLimitApproaching  = "usage_limit_approaching"
	AlarmCodeSubscriptionExpiry     = "subscription_expiry"
	AlarmCodeSystemMaintenance      = "system_maintenance"
	AlarmCodeDailySalesNotSubmitted = "daily_sales_not_submitted"
)

// Preset Schedules
var PresetSchedules = map[string]string{
	"daily_8am":      "0 0 8 * * *",
	"daily_9am":      "0 0 9 * * *",
	"daily_9pm":      "0 0 21 * * *",
	"daily_10pm":     "0 0 22 * * *",
	"weekly_monday":  "0 0 9 * * 1",
	"weekly_friday":  "0 0 17 * * 5",
	"end_of_day":     "0 0 22 * * *",
	"hourly":         "0 0 * * * *",
	"every_6_hours":  "0 0 */6 * * *",
	"every_12_hours": "0 0 */12 * * *",
}

// ========================================
// Database Models
// ========================================

// AlarmDefinition represents a system alarm type definition
type AlarmDefinition struct {
	ID                    uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	Code                  string          `json:"code" gorm:"type:varchar(50);uniqueIndex;not null"`
	Name                  string          `json:"name" gorm:"type:varchar(100);not null"`
	Description           string          `json:"description" gorm:"type:text"`
	Category              string          `json:"category" gorm:"type:varchar(50);not null"`
	TriggerType           string          `json:"trigger_type" gorm:"type:varchar(20);not null"`
	DefaultPriority       string          `json:"default_priority" gorm:"type:varchar(20);default:'normal'"`
	ThresholdSchema       json.RawMessage `json:"threshold_schema" gorm:"type:jsonb;default:'{}'"`
	CheckService          string          `json:"check_service" gorm:"type:varchar(100)"`
	CheckMethod           string          `json:"check_method" gorm:"type:varchar(100)"`
	DefaultChannels       json.RawMessage `json:"default_channels" gorm:"type:jsonb;default:'[\"push\"]'"`
	DefaultCooldownMinutes int            `json:"default_cooldown_minutes" gorm:"default:60"`
	SupportsShopScope     bool            `json:"supports_shop_scope" gorm:"default:true"`
	IsActive              bool            `json:"is_active" gorm:"default:true"`
	IsSystem              bool            `json:"is_system" gorm:"default:true"`
	CreatedAt             time.Time       `json:"created_at"`
	UpdatedAt             time.Time       `json:"updated_at"`
}

// TableName sets the table name for AlarmDefinition
func (AlarmDefinition) TableName() string {
	return "alarm_definitions"
}

// AlarmConfiguration represents tenant-specific alarm configuration
type AlarmConfiguration struct {
	ID                  uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	TenantID            uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null"`
	ShopID              *uuid.UUID      `json:"shop_id" gorm:"type:uuid"`
	AlarmDefinitionID   uuid.UUID       `json:"alarm_definition_id" gorm:"type:uuid;not null"`
	AlarmCode           string          `json:"alarm_code" gorm:"type:varchar(50);not null"`
	IsEnabled           bool            `json:"is_enabled" gorm:"default:true"`
	Priority            string          `json:"priority" gorm:"type:varchar(20);default:'normal'"`
	Thresholds          json.RawMessage `json:"thresholds" gorm:"type:jsonb;default:'{}'"`
	ScheduleType        string          `json:"schedule_type" gorm:"type:varchar(20)"`
	CronExpression      string          `json:"cron_expression" gorm:"type:varchar(50)"`
	PresetSchedule      string          `json:"preset_schedule" gorm:"type:varchar(50)"`
	Timezone            string          `json:"timezone" gorm:"type:varchar(50);default:'Asia/Kolkata'"`
	Channels            json.RawMessage `json:"channels" gorm:"type:jsonb;default:'[\"push\"]'"`
	Recipients          json.RawMessage `json:"recipients" gorm:"type:jsonb;default:'{}'"`
	CooldownMinutes     int             `json:"cooldown_minutes" gorm:"default:60"`
	MaxAlertsPerDay     int             `json:"max_alerts_per_day" gorm:"default:100"`
	QuietHoursStart     *string         `json:"quiet_hours_start" gorm:"type:time"`
	QuietHoursEnd       *string         `json:"quiet_hours_end" gorm:"type:time"`
	BypassQuietForCritical bool         `json:"bypass_quiet_for_critical" gorm:"default:true"`
	CustomTitleTemplate string          `json:"custom_title_template" gorm:"type:text"`
	CustomMessageTemplate string        `json:"custom_message_template" gorm:"type:text"`
	CreatedBy           *uuid.UUID      `json:"created_by" gorm:"type:uuid"`
	CreatedAt           time.Time       `json:"created_at"`
	UpdatedAt           time.Time       `json:"updated_at"`

	// Relationships
	AlarmDefinition *AlarmDefinition `json:"alarm_definition,omitempty" gorm:"foreignKey:AlarmDefinitionID"`
	Shop            *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
}

// TableName sets the table name for AlarmConfiguration
func (AlarmConfiguration) TableName() string {
	return "alarm_configurations"
}

// AlarmInstance represents a generated alarm record
type AlarmInstance struct {
	ID                uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	TenantID          uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null"`
	ShopID            *uuid.UUID      `json:"shop_id" gorm:"type:uuid"`
	AlarmConfigID     *uuid.UUID      `json:"alarm_config_id" gorm:"type:uuid"`
	AlarmCode         string          `json:"alarm_code" gorm:"type:varchar(50);not null"`
	Title             string          `json:"title" gorm:"type:varchar(255);not null"`
	Message           string          `json:"message" gorm:"type:text;not null"`
	Priority          string          `json:"priority" gorm:"type:varchar(20);not null;default:'normal'"`
	Status            string          `json:"status" gorm:"type:varchar(20);not null;default:'active'"`
	TriggerData       json.RawMessage `json:"trigger_data" gorm:"type:jsonb;default:'{}'"`
	RelatedEntityType string          `json:"related_entity_type" gorm:"type:varchar(50)"`
	RelatedEntityID   *uuid.UUID      `json:"related_entity_id" gorm:"type:uuid"`
	TriggeredAt       time.Time       `json:"triggered_at" gorm:"default:CURRENT_TIMESTAMP"`
	AcknowledgedAt    *time.Time      `json:"acknowledged_at"`
	AcknowledgedBy    *uuid.UUID      `json:"acknowledged_by" gorm:"type:uuid"`
	ResolvedAt        *time.Time      `json:"resolved_at"`
	ResolvedBy        *uuid.UUID      `json:"resolved_by" gorm:"type:uuid"`
	ResolutionNotes   string          `json:"resolution_notes" gorm:"type:text"`
	ExpiresAt         *time.Time      `json:"expires_at"`
	SnoozedUntil      *time.Time      `json:"snoozed_until"`
	NotificationID    *uuid.UUID      `json:"notification_id" gorm:"type:uuid"`
	ChannelsSent      json.RawMessage `json:"channels_sent" gorm:"type:jsonb;default:'[]'"`
	DeliveryStatus    json.RawMessage `json:"delivery_status" gorm:"type:jsonb;default:'{}'"`
	EscalationLevel   int             `json:"escalation_level" gorm:"default:0"`
	EscalatedAt       *time.Time      `json:"escalated_at"`
	CreatedAt         time.Time       `json:"created_at"`
	UpdatedAt         time.Time       `json:"updated_at"`

	// Relationships
	AlarmConfig      *AlarmConfiguration `json:"alarm_config,omitempty" gorm:"foreignKey:AlarmConfigID"`
	Shop             *Shop               `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	AcknowledgedByUser *User             `json:"acknowledged_by_user,omitempty" gorm:"foreignKey:AcknowledgedBy"`
	ResolvedByUser   *User               `json:"resolved_by_user,omitempty" gorm:"foreignKey:ResolvedBy"`
}

// TableName sets the table name for AlarmInstance
func (AlarmInstance) TableName() string {
	return "alarm_instances"
}

// AlarmScheduleRun tracks scheduled check executions
type AlarmScheduleRun struct {
	ID              uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	AlarmConfigID   uuid.UUID       `json:"alarm_config_id" gorm:"type:uuid;not null"`
	TenantID        uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null"`
	ScheduledFor    time.Time       `json:"scheduled_for" gorm:"not null"`
	StartedAt       *time.Time      `json:"started_at"`
	CompletedAt     *time.Time      `json:"completed_at"`
	Status          string          `json:"status" gorm:"type:varchar(20);not null;default:'pending'"`
	ItemsChecked    int             `json:"items_checked" gorm:"default:0"`
	AlarmsTriggered int             `json:"alarms_triggered" gorm:"default:0"`
	ErrorMessage    string          `json:"error_message" gorm:"type:text"`
	RunMetadata     json.RawMessage `json:"run_metadata" gorm:"type:jsonb;default:'{}'"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`

	// Relationships
	AlarmConfig *AlarmConfiguration `json:"alarm_config,omitempty" gorm:"foreignKey:AlarmConfigID"`
}

// TableName sets the table name for AlarmScheduleRun
func (AlarmScheduleRun) TableName() string {
	return "alarm_schedule_runs"
}

// AlarmRecipient stores pre-computed recipients for alarm configs
type AlarmRecipient struct {
	ID            uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	AlarmConfigID uuid.UUID       `json:"alarm_config_id" gorm:"type:uuid;not null"`
	UserID        uuid.UUID       `json:"user_id" gorm:"type:uuid;not null"`
	Email         string          `json:"email" gorm:"type:varchar(255)"`
	Phone         string          `json:"phone" gorm:"type:varchar(20)"`
	Channels      json.RawMessage `json:"channels" gorm:"type:jsonb;default:'[\"push\"]'"`
	CreatedAt     time.Time       `json:"created_at"`

	// Relationships
	User *User `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

// TableName sets the table name for AlarmRecipient
func (AlarmRecipient) TableName() string {
	return "alarm_recipients"
}

// ========================================
// Request/Response DTOs
// ========================================

// CreateAlarmConfigRequest represents a request to create an alarm configuration
type CreateAlarmConfigRequest struct {
	AlarmCode             string          `json:"alarm_code" binding:"required"`
	ShopID                *uuid.UUID      `json:"shop_id"`
	IsEnabled             *bool           `json:"is_enabled"`
	Priority              string          `json:"priority"`
	Thresholds            json.RawMessage `json:"thresholds"`
	ScheduleType          string          `json:"schedule_type" binding:"omitempty,oneof=cron preset event_only"`
	CronExpression        string          `json:"cron_expression"`
	PresetSchedule        string          `json:"preset_schedule"`
	Timezone              string          `json:"timezone"`
	Channels              []string        `json:"channels"`
	Recipients            *RecipientsConfig `json:"recipients"`
	CooldownMinutes       *int            `json:"cooldown_minutes"`
	MaxAlertsPerDay       *int            `json:"max_alerts_per_day"`
	QuietHoursStart       *string         `json:"quiet_hours_start"`
	QuietHoursEnd         *string         `json:"quiet_hours_end"`
	BypassQuietForCritical *bool          `json:"bypass_quiet_for_critical"`
	CustomTitleTemplate   string          `json:"custom_title_template"`
	CustomMessageTemplate string          `json:"custom_message_template"`
}

// UpdateAlarmConfigRequest represents a request to update an alarm configuration
type UpdateAlarmConfigRequest struct {
	IsEnabled             *bool           `json:"is_enabled"`
	Priority              string          `json:"priority"`
	Thresholds            json.RawMessage `json:"thresholds"`
	ScheduleType          string          `json:"schedule_type"`
	CronExpression        string          `json:"cron_expression"`
	PresetSchedule        string          `json:"preset_schedule"`
	Timezone              string          `json:"timezone"`
	Channels              []string        `json:"channels"`
	Recipients            *RecipientsConfig `json:"recipients"`
	CooldownMinutes       *int            `json:"cooldown_minutes"`
	MaxAlertsPerDay       *int            `json:"max_alerts_per_day"`
	QuietHoursStart       *string         `json:"quiet_hours_start"`
	QuietHoursEnd         *string         `json:"quiet_hours_end"`
	BypassQuietForCritical *bool          `json:"bypass_quiet_for_critical"`
	CustomTitleTemplate   string          `json:"custom_title_template"`
	CustomMessageTemplate string          `json:"custom_message_template"`
}

// RecipientsConfig defines who receives alarm notifications
type RecipientsConfig struct {
	Roles         []string    `json:"roles"`
	UserIDs       []uuid.UUID `json:"user_ids"`
	NotifyCreator bool        `json:"notify_creator"`
}

// ThresholdConfig represents configurable threshold values
type ThresholdConfig struct {
	MinQuantity           *float64 `json:"min_quantity,omitempty"`
	MaxVariancePercent    *float64 `json:"max_variance_percent,omitempty"`
	MaxVarianceAmount     *float64 `json:"max_variance_amount,omitempty"`
	DaysOverdue           *int     `json:"days_overdue,omitempty"`
	MinAmount             *float64 `json:"min_amount,omitempty"`
	MaxDiscountPercent    *float64 `json:"max_discount_percent,omitempty"`
	CheckPeriodHours      *int     `json:"check_period_hours,omitempty"`
	DeviationThresholdPercent *float64 `json:"deviation_threshold_percent,omitempty"`
	IncludeComparison     *bool    `json:"include_comparison,omitempty"`
	IncludeCharts         *bool    `json:"include_charts,omitempty"`
	DaysBefore            *int     `json:"days_before,omitempty"`
	IncludeInventory      *bool    `json:"include_inventory,omitempty"`
	IncludeCash           *bool    `json:"include_cash,omitempty"`
	ThresholdPercent      *float64 `json:"threshold_percent,omitempty"`
	Products              []uuid.UUID `json:"products,omitempty"`
}

// TriggerAlarmRequest represents a request to manually trigger an alarm
type TriggerAlarmRequest struct {
	AlarmCode         string          `json:"alarm_code" binding:"required"`
	ShopID            *uuid.UUID      `json:"shop_id"`
	Title             string          `json:"title"`
	Message           string          `json:"message"`
	Priority          string          `json:"priority"`
	TriggerData       json.RawMessage `json:"trigger_data"`
	RelatedEntityType string          `json:"related_entity_type"`
	RelatedEntityID   *uuid.UUID      `json:"related_entity_id"`
}

// AcknowledgeAlarmRequest represents a request to acknowledge an alarm
type AcknowledgeAlarmRequest struct {
	Notes string `json:"notes"`
}

// ResolveAlarmRequest represents a request to resolve an alarm
type ResolveAlarmRequest struct {
	Notes string `json:"notes" binding:"required"`
}

// SnoozeAlarmRequest represents a request to snooze an alarm
type SnoozeAlarmRequest struct {
	SnoozeMinutes int `json:"snooze_minutes" binding:"required,min=5,max=1440"`
}

// ListAlarmInstancesRequest represents filter parameters for listing alarms
type ListAlarmInstancesRequest struct {
	ShopID     *uuid.UUID `form:"shop_id"`
	AlarmCode  string     `form:"alarm_code"`
	Status     string     `form:"status"`
	Priority   string     `form:"priority"`
	StartDate  *time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate    *time.Time `form:"end_date" time_format:"2006-01-02"`
	Page       int        `form:"page,default=1"`
	PageSize   int        `form:"page_size,default=20"`
}

// AlarmDashboardResponse represents alarm dashboard summary
type AlarmDashboardResponse struct {
	ActiveAlarms      int64 `json:"active_alarms"`
	AcknowledgedAlarms int64 `json:"acknowledged_alarms"`
	ResolvedToday     int64 `json:"resolved_today"`
	CriticalAlarms    int64 `json:"critical_alarms"`
	HighPriorityAlarms int64 `json:"high_priority_alarms"`
	AlarmsByCategory  map[string]int64 `json:"alarms_by_category"`
	RecentAlarms      []AlarmInstance  `json:"recent_alarms"`
}

// AlarmConfigListResponse represents paginated alarm configurations
type AlarmConfigListResponse struct {
	Configurations []AlarmConfiguration `json:"configurations"`
	Total          int64                `json:"total"`
	Page           int                  `json:"page"`
	PageSize       int                  `json:"page_size"`
}

// AlarmInstanceListResponse represents paginated alarm instances
type AlarmInstanceListResponse struct {
	Alarms   []AlarmInstance `json:"alarms"`
	Total    int64           `json:"total"`
	Page     int             `json:"page"`
	PageSize int             `json:"page_size"`
}

// TestAlarmRequest represents a request to test an alarm configuration
type TestAlarmRequest struct {
	SendNotification bool `json:"send_notification"`
}

// TestAlarmResponse represents the result of testing an alarm
type TestAlarmResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	AlarmID *uuid.UUID `json:"alarm_id,omitempty"`
}

// ========================================
// Helper Methods
// ========================================

// GetChannels returns the channels as a string slice
func (c *AlarmConfiguration) GetChannels() []string {
	var channels []string
	if c.Channels != nil {
		json.Unmarshal(c.Channels, &channels)
	}
	return channels
}

// SetChannels sets the channels from a string slice
func (c *AlarmConfiguration) SetChannels(channels []string) {
	data, _ := json.Marshal(channels)
	c.Channels = data
}

// GetRecipients returns the recipients configuration
func (c *AlarmConfiguration) GetRecipients() *RecipientsConfig {
	var recipients RecipientsConfig
	if c.Recipients != nil {
		json.Unmarshal(c.Recipients, &recipients)
	}
	return &recipients
}

// SetRecipients sets the recipients from a config struct
func (c *AlarmConfiguration) SetRecipients(recipients *RecipientsConfig) {
	data, _ := json.Marshal(recipients)
	c.Recipients = data
}

// GetThresholds returns the thresholds configuration
func (c *AlarmConfiguration) GetThresholds() *ThresholdConfig {
	var thresholds ThresholdConfig
	if c.Thresholds != nil {
		json.Unmarshal(c.Thresholds, &thresholds)
	}
	return &thresholds
}

// SetThresholds sets the thresholds from a config struct
func (c *AlarmConfiguration) SetThresholds(thresholds *ThresholdConfig) {
	data, _ := json.Marshal(thresholds)
	c.Thresholds = data
}

// GetCronExpression returns the effective cron expression
func (c *AlarmConfiguration) GetCronExpression() string {
	if c.CronExpression != "" {
		return c.CronExpression
	}
	if c.PresetSchedule != "" {
		if expr, ok := PresetSchedules[c.PresetSchedule]; ok {
			return expr
		}
	}
	return ""
}

// GetTriggerData returns the trigger data as a map
func (a *AlarmInstance) GetTriggerData() map[string]interface{} {
	var data map[string]interface{}
	if a.TriggerData != nil {
		json.Unmarshal(a.TriggerData, &data)
	}
	return data
}

// SetTriggerData sets the trigger data from a map
func (a *AlarmInstance) SetTriggerData(data map[string]interface{}) {
	jsonData, _ := json.Marshal(data)
	a.TriggerData = jsonData
}

// IsCritical returns true if the alarm is critical priority
func (a *AlarmInstance) IsCritical() bool {
	return a.Priority == AlarmPriorityCritical
}

// IsActive returns true if the alarm is in active status
func (a *AlarmInstance) IsActive() bool {
	return a.Status == AlarmStatusActive
}

// CanAcknowledge returns true if the alarm can be acknowledged
func (a *AlarmInstance) CanAcknowledge() bool {
	return a.Status == AlarmStatusActive
}

// CanResolve returns true if the alarm can be resolved
func (a *AlarmInstance) CanResolve() bool {
	return a.Status == AlarmStatusActive || a.Status == AlarmStatusAcknowledged
}

// ========================================
// Additional Models for Alarm Service
// ========================================

// AlarmInstanceFilter represents filter parameters for listing alarms
type AlarmInstanceFilter struct {
	TenantID   uuid.UUID  `json:"-"`
	ShopID     *uuid.UUID `json:"shop_id"`
	AlarmCode  string     `json:"alarm_code"`
	Status     string     `json:"status"`
	Priority   string     `json:"priority"`
	StartDate  *time.Time `json:"start_date"`
	EndDate    *time.Time `json:"end_date"`
	Page       int        `json:"page"`
	PageSize   int        `json:"page_size"`
}

// AlarmNote represents a note added to an alarm
type AlarmNote struct {
	ID        uuid.UUID `json:"id" gorm:"type:uuid;primaryKey"`
	AlarmID   uuid.UUID `json:"alarm_id" gorm:"type:uuid;not null"`
	UserID    uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	Note      string    `json:"note" gorm:"type:text;not null"`
	CreatedAt time.Time `json:"created_at"`

	// Relationships
	User *User `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

// TableName sets the table name for AlarmNote
func (AlarmNote) TableName() string {
	return "alarm_notes"
}

// AlarmHistory represents a history entry for alarm state changes
type AlarmHistory struct {
	ID           uuid.UUID `json:"id" gorm:"type:uuid;primaryKey"`
	AlarmID      uuid.UUID `json:"alarm_id" gorm:"type:uuid;not null"`
	UserID       *uuid.UUID `json:"user_id" gorm:"type:uuid"`
	Action       string    `json:"action" gorm:"type:varchar(50);not null"`
	OldStatus    string    `json:"old_status" gorm:"type:varchar(20)"`
	NewStatus    string    `json:"new_status" gorm:"type:varchar(20)"`
	Notes        string    `json:"notes" gorm:"type:text"`
	CreatedAt    time.Time `json:"created_at"`

	// Relationships
	User *User `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

// TableName sets the table name for AlarmHistory
func (AlarmHistory) TableName() string {
	return "alarm_history"
}

// AlarmCountsResponse represents alarm counts by status/priority
type AlarmCountsResponse struct {
	TotalActive       int64            `json:"total_active"`
	TotalAcknowledged int64            `json:"total_acknowledged"`
	TotalSnoozed      int64            `json:"total_snoozed"`
	TotalResolved     int64            `json:"total_resolved"`
	ByPriority        map[string]int64 `json:"by_priority"`
	ByCategory        map[string]int64 `json:"by_category"`
	ByShop            map[string]int64 `json:"by_shop"`
}

// AlarmStatsResponse represents alarm statistics
type AlarmStatsResponse struct {
	Period            string           `json:"period"`
	TotalTriggered    int64            `json:"total_triggered"`
	TotalResolved     int64            `json:"total_resolved"`
	AverageResolutionMinutes float64  `json:"average_resolution_minutes"`
	ByAlarmCode       map[string]int64 `json:"by_alarm_code"`
	ByPriority        map[string]int64 `json:"by_priority"`
	TrendData         []AlarmTrendPoint `json:"trend_data"`
}

// AlarmTrendPoint represents a single data point in alarm trends
type AlarmTrendPoint struct {
	Date     string `json:"date"`
	Count    int64  `json:"count"`
	Resolved int64  `json:"resolved"`
}

// UserAlarmSubscription represents a user's subscription preferences for alarms
type UserAlarmSubscription struct {
	ID            uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	TenantID      uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null"`
	UserID        uuid.UUID       `json:"user_id" gorm:"type:uuid;not null"`
	AlarmCode     string          `json:"alarm_code" gorm:"type:varchar(50);not null"`
	IsSubscribed  bool            `json:"is_subscribed" gorm:"default:true"`
	Channels      json.RawMessage `json:"channels" gorm:"type:jsonb;default:'[\"push\"]'"`
	MinPriority   string          `json:"min_priority" gorm:"type:varchar(20);default:'normal'"`
	QuietHoursEnabled bool        `json:"quiet_hours_enabled" gorm:"default:false"`
	QuietHoursStart *string       `json:"quiet_hours_start" gorm:"type:time"`
	QuietHoursEnd   *string       `json:"quiet_hours_end" gorm:"type:time"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
}

// TableName sets the table name for UserAlarmSubscription
func (UserAlarmSubscription) TableName() string {
	return "user_alarm_subscriptions"
}

// UpdateAlarmSubscriptionRequest represents a request to update subscription settings
type UpdateAlarmSubscriptionRequest struct {
	AlarmCode         string   `json:"alarm_code" binding:"required"`
	IsSubscribed      *bool    `json:"is_subscribed"`
	Channels          []string `json:"channels"`
	MinPriority       string   `json:"min_priority"`
	QuietHoursEnabled *bool    `json:"quiet_hours_enabled"`
	QuietHoursStart   *string  `json:"quiet_hours_start"`
	QuietHoursEnd     *string  `json:"quiet_hours_end"`
}

// AddAlarmNoteRequest represents a request to add a note to an alarm
type AddAlarmNoteRequest struct {
	Note string `json:"note" binding:"required"`
}
