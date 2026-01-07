package models

import (
	"time"

	"github.com/google/uuid"
)

// =====================================================
// Physical Audit Constants
// =====================================================

// AuditType - Types of audits
type AuditType string

const (
	AuditTypeDailyClosing  AuditType = "daily_closing"
	AuditTypeWeekly        AuditType = "weekly"
	AuditTypeMonthly       AuditType = "monthly"
	AuditTypeSpotCheck     AuditType = "spot_check"
	AuditTypeIncident      AuditType = "incident"
)

// AuditTriggerType - What triggered the audit
type AuditTriggerType string

const (
	AuditTriggerScheduled   AuditTriggerType = "scheduled"
	AuditTriggerManual      AuditTriggerType = "manual"
	AuditTriggerAlert       AuditTriggerType = "alert"
	AuditTriggerRandom      AuditTriggerType = "random"
	AuditTriggerInvestigation AuditTriggerType = "investigation"
)

// AuditStatus - Status of audit
type AuditStatus string

const (
	AuditStatusScheduled     AuditStatus = "scheduled"
	AuditStatusInProgress    AuditStatus = "in_progress"
	AuditStatusPendingReview AuditStatus = "pending_review"
	AuditStatusApproved      AuditStatus = "approved"
	AuditStatusRejected      AuditStatus = "rejected"
	AuditStatusExpired       AuditStatus = "expired"
)

// VarianceSeverity - Severity of audit variance
type VarianceSeverity string

const (
	VarianceSeverityMinor    VarianceSeverity = "minor"
	VarianceSeverityModerate VarianceSeverity = "moderate"
	VarianceSeverityMajor    VarianceSeverity = "major"
	VarianceSeverityCritical VarianceSeverity = "critical"
)

// VarianceResolutionStatus - Status of variance resolution
type VarianceResolutionStatus string

const (
	VarianceStatusOpen         VarianceResolutionStatus = "open"
	VarianceStatusInvestigating VarianceResolutionStatus = "investigating"
	VarianceStatusResolved     VarianceResolutionStatus = "resolved"
	VarianceStatusWrittenOff   VarianceResolutionStatus = "written_off"
	VarianceStatusAccepted     VarianceResolutionStatus = "accepted"
)

// ResolutionType - How variance was resolved
type ResolutionType string

const (
	ResolutionTypeAdjustment    ResolutionType = "adjustment"
	ResolutionTypeWriteOff      ResolutionType = "write_off"
	ResolutionTypeRecovery      ResolutionType = "recovery"
	ResolutionTypeCorrection    ResolutionType = "correction"
	ResolutionTypeFalseAlarm    ResolutionType = "false_alarm"
)

// =====================================================
// Audit Schedule Model
// =====================================================

// AuditSchedule defines recurring audit schedules
type AuditSchedule struct {
	ID                uuid.UUID        `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID        `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID            *uuid.UUID       `json:"shop_id" gorm:"type:uuid;index"`
	AuditType         AuditType        `json:"audit_type" gorm:"type:varchar(30);not null"`
	Name              string           `json:"name" gorm:"type:varchar(100);not null"`
	Description       string           `json:"description" gorm:"type:text"`
	IsEnabled         bool             `json:"is_enabled" gorm:"default:true"`
	CronExpression    string           `json:"cron_expression" gorm:"type:varchar(50)"`
	ScheduledTime     string           `json:"scheduled_time" gorm:"type:time"`
	DaysOfWeek        []int            `json:"days_of_week" gorm:"type:jsonb"`
	DaysOfMonth       []int            `json:"days_of_month" gorm:"type:jsonb"`
	IncludeCashAudit  bool             `json:"include_cash_audit" gorm:"default:true"`
	IncludeInventory  bool             `json:"include_inventory" gorm:"default:false"`
	InventoryScope    string           `json:"inventory_scope" gorm:"type:varchar(30)"`
	AssignedCounters  []string         `json:"assigned_counters" gorm:"type:jsonb"`
	AssignedAuditors  []uuid.UUID      `json:"assigned_auditors" gorm:"type:jsonb"`
	NotifyBefore      int              `json:"notify_before_minutes" gorm:"default:30"`
	ExpiresAfter      int              `json:"expires_after_minutes" gorm:"default:60"`
	RequiresApproval  bool             `json:"requires_approval" gorm:"default:true"`
	ApprovalRoles     []string         `json:"approval_roles" gorm:"type:jsonb"`
	LastRunAt         *time.Time       `json:"last_run_at"`
	NextRunAt         *time.Time       `json:"next_run_at"`
	CreatedBy         uuid.UUID        `json:"created_by" gorm:"type:uuid;not null"`
	CreatedAt         time.Time        `json:"created_at"`
	UpdatedAt         time.Time        `json:"updated_at"`
	DeletedAt         *time.Time       `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop              *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Creator           *User            `json:"creator,omitempty" gorm:"foreignKey:CreatedBy"`
}

func (AuditSchedule) TableName() string {
	return "audit_schedules"
}

// =====================================================
// Audit Session Model
// =====================================================

// AuditSession represents an individual audit session
type AuditSession struct {
	ID                 uuid.UUID         `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID           uuid.UUID         `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID             uuid.UUID         `json:"shop_id" gorm:"type:uuid;not null;index"`
	ScheduleID         *uuid.UUID        `json:"schedule_id" gorm:"type:uuid;index"`
	SessionNumber      string            `json:"session_number" gorm:"type:varchar(50);uniqueIndex;not null"`
	AuditType          AuditType         `json:"audit_type" gorm:"type:varchar(30);not null"`
	TriggerType        AuditTriggerType  `json:"trigger_type" gorm:"type:varchar(30);not null"`
	Status             AuditStatus       `json:"status" gorm:"type:varchar(30);default:'scheduled'"`
	AuditDate          time.Time         `json:"audit_date" gorm:"type:date;not null"`
	ScheduledAt        time.Time         `json:"scheduled_at" gorm:"not null"`
	StartedAt          *time.Time        `json:"started_at"`
	CompletedAt        *time.Time        `json:"completed_at"`
	ExpiresAt          *time.Time        `json:"expires_at"`
	AuditorID          *uuid.UUID        `json:"auditor_id" gorm:"type:uuid;index"`
	ReviewerID         *uuid.UUID        `json:"reviewer_id" gorm:"type:uuid"`
	ReviewedAt         *time.Time        `json:"reviewed_at"`
	AssignedCounters   []string          `json:"assigned_counters" gorm:"type:jsonb"`
	IncludeCashAudit   bool              `json:"include_cash_audit" gorm:"default:true"`
	IncludeInventory   bool              `json:"include_inventory" gorm:"default:false"`
	InventoryScope     string            `json:"inventory_scope" gorm:"type:varchar(30)"`
	TotalVarianceValue float64           `json:"total_variance_value" gorm:"type:decimal(15,2);default:0"`
	VarianceCount      int               `json:"variance_count" gorm:"default:0"`
	Notes              string            `json:"notes" gorm:"type:text"`
	ReviewNotes        string            `json:"review_notes" gorm:"type:text"`
	CreatedAt          time.Time         `json:"created_at"`
	UpdatedAt          time.Time         `json:"updated_at"`
	DeletedAt          *time.Time        `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop               *Shop             `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Schedule           *AuditSchedule    `json:"schedule,omitempty" gorm:"foreignKey:ScheduleID"`
	Auditor            *User             `json:"auditor,omitempty" gorm:"foreignKey:AuditorID"`
	Reviewer           *User             `json:"reviewer,omitempty" gorm:"foreignKey:ReviewerID"`
	CashAudit          *CashAudit        `json:"cash_audit,omitempty" gorm:"foreignKey:SessionID"`
	InventoryAudit     *InventoryAudit   `json:"inventory_audit,omitempty" gorm:"foreignKey:SessionID"`
	Variances          []AuditVariance   `json:"variances,omitempty" gorm:"foreignKey:SessionID"`
}

func (AuditSession) TableName() string {
	return "audit_sessions"
}

// =====================================================
// Cash Audit Model
// =====================================================

// DenominationCount represents count of each denomination
type DenominationCount struct {
	D2000 int `json:"d_2000"`
	D500  int `json:"d_500"`
	D200  int `json:"d_200"`
	D100  int `json:"d_100"`
	D50   int `json:"d_50"`
	D20   int `json:"d_20"`
	D10   int `json:"d_10"`
	D5    int `json:"d_5"`
	D2    int `json:"d_2"`
	D1    int `json:"d_1"`
}

// CashAudit represents a cash counting audit
type CashAudit struct {
	ID                  uuid.UUID          `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID            uuid.UUID          `json:"tenant_id" gorm:"type:uuid;not null;index"`
	SessionID           uuid.UUID          `json:"session_id" gorm:"type:uuid;not null;uniqueIndex"`
	ShopID              uuid.UUID          `json:"shop_id" gorm:"type:uuid;not null;index"`
	CounterID           string             `json:"counter_id" gorm:"type:varchar(50)"`
	ExpectedAmount      float64            `json:"expected_amount" gorm:"type:decimal(15,2);not null"`
	SystemAmount        float64            `json:"system_amount" gorm:"type:decimal(15,2);not null"`
	CountedAmount       float64            `json:"counted_amount" gorm:"type:decimal(15,2)"`
	VarianceAmount      float64            `json:"variance_amount" gorm:"type:decimal(15,2);default:0"`
	Denominations       *DenominationCount `json:"denominations" gorm:"type:jsonb"`
	CoinTotal           float64            `json:"coin_total" gorm:"type:decimal(10,2);default:0"`
	IsBlindCount        bool               `json:"is_blind_count" gorm:"default:false"`
	CountedAt           *time.Time         `json:"counted_at"`
	CountedBy           *uuid.UUID         `json:"counted_by" gorm:"type:uuid"`
	VerifiedAt          *time.Time         `json:"verified_at"`
	VerifiedBy          *uuid.UUID         `json:"verified_by" gorm:"type:uuid"`
	Notes               string             `json:"notes" gorm:"type:text"`
	Photos              []string           `json:"photos" gorm:"type:jsonb"`
	CreatedAt           time.Time          `json:"created_at"`
	UpdatedAt           time.Time          `json:"updated_at"`

	// Relationships
	Session             *AuditSession      `json:"session,omitempty" gorm:"foreignKey:SessionID"`
	Shop                *Shop              `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Counter             *User              `json:"counter,omitempty" gorm:"foreignKey:CountedBy"`
	Verifier            *User              `json:"verifier,omitempty" gorm:"foreignKey:VerifiedBy"`
}

func (CashAudit) TableName() string {
	return "cash_audits"
}

// CalculateDenominationTotal calculates total from denomination count
func (d *DenominationCount) Total() float64 {
	if d == nil {
		return 0
	}
	return float64(d.D2000*2000 + d.D500*500 + d.D200*200 + d.D100*100 +
		d.D50*50 + d.D20*20 + d.D10*10 + d.D5*5 + d.D2*2 + d.D1*1)
}

// =====================================================
// Inventory Audit Model
// =====================================================

// InventoryAudit represents an inventory audit
type InventoryAudit struct {
	ID                uuid.UUID            `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID            `json:"tenant_id" gorm:"type:uuid;not null;index"`
	SessionID         uuid.UUID            `json:"session_id" gorm:"type:uuid;not null;uniqueIndex"`
	ShopID            uuid.UUID            `json:"shop_id" gorm:"type:uuid;not null;index"`
	Scope             string               `json:"scope" gorm:"type:varchar(30);not null"`
	CategoryIDs       []uuid.UUID          `json:"category_ids" gorm:"type:jsonb"`
	ProductIDs        []uuid.UUID          `json:"product_ids" gorm:"type:jsonb"`
	TotalSKUs         int                  `json:"total_skus" gorm:"default:0"`
	CountedSKUs       int                  `json:"counted_skus" gorm:"default:0"`
	VarianceSKUs      int                  `json:"variance_skus" gorm:"default:0"`
	TotalVarianceValue float64             `json:"total_variance_value" gorm:"type:decimal(15,2);default:0"`
	TotalVarianceQty  int                  `json:"total_variance_qty" gorm:"default:0"`
	StartedAt         *time.Time           `json:"started_at"`
	CompletedAt       *time.Time           `json:"completed_at"`
	Notes             string               `json:"notes" gorm:"type:text"`
	CreatedAt         time.Time            `json:"created_at"`
	UpdatedAt         time.Time            `json:"updated_at"`

	// Relationships
	Session           *AuditSession        `json:"session,omitempty" gorm:"foreignKey:SessionID"`
	Shop              *Shop                `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Items             []InventoryAuditItem `json:"items,omitempty" gorm:"foreignKey:InventoryAuditID"`
}

func (InventoryAudit) TableName() string {
	return "inventory_audits"
}

// =====================================================
// Inventory Audit Item Model
// =====================================================

// InventoryAuditItem represents a single product count in audit
type InventoryAuditItem struct {
	ID                uuid.UUID `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null;index"`
	InventoryAuditID  uuid.UUID `json:"inventory_audit_id" gorm:"type:uuid;not null;index"`
	ProductID         uuid.UUID `json:"product_id" gorm:"type:uuid;not null;index"`
	LocationCode      string    `json:"location_code" gorm:"type:varchar(50)"`
	SystemQuantity    int       `json:"system_quantity" gorm:"not null"`
	CountedQuantity   *int      `json:"counted_quantity"`
	VarianceQuantity  int       `json:"variance_quantity" gorm:"default:0"`
	UnitCost          float64   `json:"unit_cost" gorm:"type:decimal(10,2);not null"`
	VarianceValue     float64   `json:"variance_value" gorm:"type:decimal(15,2);default:0"`
	BatchNumber       string    `json:"batch_number" gorm:"type:varchar(50)"`
	ExpiryDate        *time.Time `json:"expiry_date" gorm:"type:date"`
	CountedAt         *time.Time `json:"counted_at"`
	CountedBy         *uuid.UUID `json:"counted_by" gorm:"type:uuid"`
	Notes             string    `json:"notes" gorm:"type:text"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`

	// Relationships
	InventoryAudit    *InventoryAudit `json:"inventory_audit,omitempty" gorm:"foreignKey:InventoryAuditID"`
	Product           *Product        `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	Counter           *User           `json:"counter,omitempty" gorm:"foreignKey:CountedBy"`
}

func (InventoryAuditItem) TableName() string {
	return "inventory_audit_items"
}

// =====================================================
// Audit Variance Model
// =====================================================

// AuditVariance represents a variance found during audit
type AuditVariance struct {
	ID                uuid.UUID                `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID                `json:"tenant_id" gorm:"type:uuid;not null;index"`
	SessionID         uuid.UUID                `json:"session_id" gorm:"type:uuid;not null;index"`
	ShopID            uuid.UUID                `json:"shop_id" gorm:"type:uuid;not null;index"`
	VarianceType      string                   `json:"variance_type" gorm:"type:varchar(30);not null"`
	ProductID         *uuid.UUID               `json:"product_id" gorm:"type:uuid;index"`
	CounterID         string                   `json:"counter_id" gorm:"type:varchar(50)"`
	ExpectedValue     float64                  `json:"expected_value" gorm:"type:decimal(15,2);not null"`
	ActualValue       float64                  `json:"actual_value" gorm:"type:decimal(15,2);not null"`
	VarianceValue     float64                  `json:"variance_value" gorm:"type:decimal(15,2);not null"`
	VariancePercent   float64                  `json:"variance_percent" gorm:"type:decimal(5,2)"`
	Severity          VarianceSeverity         `json:"severity" gorm:"type:varchar(20);not null"`
	Status            VarianceResolutionStatus `json:"status" gorm:"type:varchar(30);default:'open'"`
	ResponsibleUserID *uuid.UUID               `json:"responsible_user_id" gorm:"type:uuid;index"`
	InvestigationID   *uuid.UUID               `json:"investigation_id" gorm:"type:uuid;index"`
	Notes             string                   `json:"notes" gorm:"type:text"`
	CreatedAt         time.Time                `json:"created_at"`
	UpdatedAt         time.Time                `json:"updated_at"`

	// Relationships
	Session           *AuditSession    `json:"session,omitempty" gorm:"foreignKey:SessionID"`
	Shop              *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Product           *Product         `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	ResponsibleUser   *User            `json:"responsible_user,omitempty" gorm:"foreignKey:ResponsibleUserID"`
	Investigation     *Investigation   `json:"investigation,omitempty" gorm:"foreignKey:InvestigationID"`
	Resolutions       []AuditResolution `json:"resolutions,omitempty" gorm:"foreignKey:VarianceID"`
}

func (AuditVariance) TableName() string {
	return "audit_variances"
}

// =====================================================
// Audit Resolution Model
// =====================================================

// AuditResolution represents resolution of audit variance
type AuditResolution struct {
	ID               uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	VarianceID       uuid.UUID       `json:"variance_id" gorm:"type:uuid;not null;index"`
	ResolutionType   ResolutionType  `json:"resolution_type" gorm:"type:varchar(30);not null"`
	Amount           float64         `json:"amount" gorm:"type:decimal(15,2);not null"`
	Description      string          `json:"description" gorm:"type:text;not null"`
	ApprovedBy       *uuid.UUID      `json:"approved_by" gorm:"type:uuid"`
	ApprovedAt       *time.Time      `json:"approved_at"`
	Attachments      []string        `json:"attachments" gorm:"type:jsonb"`
	CreatedBy        uuid.UUID       `json:"created_by" gorm:"type:uuid;not null"`
	CreatedAt        time.Time       `json:"created_at"`

	// Relationships
	Variance         *AuditVariance  `json:"variance,omitempty" gorm:"foreignKey:VarianceID"`
	Approver         *User           `json:"approver,omitempty" gorm:"foreignKey:ApprovedBy"`
	Creator          *User           `json:"creator,omitempty" gorm:"foreignKey:CreatedBy"`
}

func (AuditResolution) TableName() string {
	return "audit_resolutions"
}

// =====================================================
// Audit Notification Model
// =====================================================

// AuditNotification tracks notifications sent for audits
type AuditNotification struct {
	ID               uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	SessionID        uuid.UUID  `json:"session_id" gorm:"type:uuid;not null;index"`
	NotificationType string     `json:"notification_type" gorm:"type:varchar(30);not null"`
	RecipientID      uuid.UUID  `json:"recipient_id" gorm:"type:uuid;not null"`
	Channel          string     `json:"channel" gorm:"type:varchar(20);not null"`
	Status           string     `json:"status" gorm:"type:varchar(20);default:'pending'"`
	SentAt           *time.Time `json:"sent_at"`
	ReadAt           *time.Time `json:"read_at"`
	CreatedAt        time.Time  `json:"created_at"`

	// Relationships
	Session          *AuditSession `json:"session,omitempty" gorm:"foreignKey:SessionID"`
	Recipient        *User         `json:"recipient,omitempty" gorm:"foreignKey:RecipientID"`
}

func (AuditNotification) TableName() string {
	return "audit_notifications"
}

// =====================================================
// Request/Response DTOs
// =====================================================

// CreateAuditScheduleRequest - Request to create audit schedule
type CreateAuditScheduleRequest struct {
	ShopID           *uuid.UUID   `json:"shop_id"`
	AuditType        AuditType    `json:"audit_type" binding:"required"`
	Name             string       `json:"name" binding:"required,max=100"`
	Description      string       `json:"description"`
	CronExpression   string       `json:"cron_expression"`
	ScheduledTime    string       `json:"scheduled_time"`
	DaysOfWeek       []int        `json:"days_of_week"`
	DaysOfMonth      []int        `json:"days_of_month"`
	IncludeCashAudit bool         `json:"include_cash_audit"`
	IncludeInventory bool         `json:"include_inventory"`
	InventoryScope   string       `json:"inventory_scope"`
	AssignedCounters []string     `json:"assigned_counters"`
	AssignedAuditors []uuid.UUID  `json:"assigned_auditors"`
	NotifyBefore     int          `json:"notify_before_minutes"`
	ExpiresAfter     int          `json:"expires_after_minutes"`
	RequiresApproval bool         `json:"requires_approval"`
	ApprovalRoles    []string     `json:"approval_roles"`
}

// CreateAuditSessionRequest - Request to create ad-hoc audit
type CreateAuditSessionRequest struct {
	ShopID           uuid.UUID        `json:"shop_id" binding:"required"`
	AuditType        AuditType        `json:"audit_type" binding:"required"`
	TriggerType      AuditTriggerType `json:"trigger_type"`
	ScheduledAt      time.Time        `json:"scheduled_at"`
	AuditorID        *uuid.UUID       `json:"auditor_id"`
	AssignedCounters []string         `json:"assigned_counters"`
	IncludeCashAudit bool             `json:"include_cash_audit"`
	IncludeInventory bool             `json:"include_inventory"`
	InventoryScope   string           `json:"inventory_scope"`
	CategoryIDs      []uuid.UUID      `json:"category_ids"`
	ProductIDs       []uuid.UUID      `json:"product_ids"`
	Notes            string           `json:"notes"`
}

// StartAuditRequest - Request to start audit session
type StartAuditRequest struct {
	SessionID uuid.UUID `json:"session_id" binding:"required"`
	Notes     string    `json:"notes"`
}

// SubmitCashCountRequest - Request to submit cash count
type SubmitCashCountRequest struct {
	SessionID     uuid.UUID          `json:"session_id" binding:"required"`
	CounterID     string             `json:"counter_id"`
	Denominations *DenominationCount `json:"denominations"`
	CoinTotal     float64            `json:"coin_total"`
	IsBlindCount  bool               `json:"is_blind_count"`
	Notes         string             `json:"notes"`
	Photos        []string           `json:"photos"`
}

// SubmitInventoryCountRequest - Request to submit inventory count
type SubmitInventoryCountRequest struct {
	SessionID uuid.UUID                  `json:"session_id" binding:"required"`
	Items     []InventoryCountItemInput  `json:"items" binding:"required,min=1"`
	Notes     string                     `json:"notes"`
}

// InventoryCountItemInput - Input for inventory count item
type InventoryCountItemInput struct {
	ProductID       uuid.UUID  `json:"product_id" binding:"required"`
	LocationCode    string     `json:"location_code"`
	CountedQuantity int        `json:"counted_quantity" binding:"required,min=0"`
	BatchNumber     string     `json:"batch_number"`
	ExpiryDate      *time.Time `json:"expiry_date"`
	Notes           string     `json:"notes"`
}

// ReviewAuditRequest - Request to review/approve audit
type ReviewAuditRequest struct {
	SessionID   uuid.UUID   `json:"session_id" binding:"required"`
	Status      AuditStatus `json:"status" binding:"required"`
	ReviewNotes string      `json:"review_notes"`
}

// ResolveVarianceRequest - Request to resolve variance
type ResolveVarianceRequest struct {
	VarianceID     uuid.UUID      `json:"variance_id" binding:"required"`
	ResolutionType ResolutionType `json:"resolution_type" binding:"required"`
	Amount         float64        `json:"amount" binding:"required"`
	Description    string         `json:"description" binding:"required"`
	Attachments    []string       `json:"attachments"`
}

// AuditDashboardResponse - Dashboard for audit module
type AuditDashboardResponse struct {
	Summary           AuditSummary         `json:"summary"`
	ScheduledAudits   []AuditSession       `json:"scheduled_audits"`
	PendingReview     []AuditSession       `json:"pending_review"`
	OpenVariances     []AuditVariance      `json:"open_variances"`
	CompletionTrend   []DailyAuditStat     `json:"completion_trend"`
	VarianceTrend     []DailyVarianceStat  `json:"variance_trend"`
}

// AuditSummary - Summary statistics
type AuditSummary struct {
	ScheduledToday     int     `json:"scheduled_today"`
	CompletedToday     int     `json:"completed_today"`
	PendingReview      int     `json:"pending_review"`
	OverdueAudits      int     `json:"overdue_audits"`
	OpenVariances      int     `json:"open_variances"`
	TotalVarianceValue float64 `json:"total_variance_value"`
	CompletionRate     float64 `json:"completion_rate"`
	AvgVariancePercent float64 `json:"avg_variance_percent"`
}

// DailyAuditStat - Daily audit statistics
type DailyAuditStat struct {
	Date           time.Time `json:"date"`
	ScheduledCount int       `json:"scheduled_count"`
	CompletedCount int       `json:"completed_count"`
	ExpiredCount   int       `json:"expired_count"`
	ApprovedCount  int       `json:"approved_count"`
	RejectedCount  int       `json:"rejected_count"`
}

// DailyVarianceStat - Daily variance statistics
type DailyVarianceStat struct {
	Date          time.Time `json:"date"`
	CashVariance  float64   `json:"cash_variance"`
	InvVariance   float64   `json:"inventory_variance"`
	TotalVariance float64   `json:"total_variance"`
	VarianceCount int       `json:"variance_count"`
}

// AuditSessionDetailResponse - Detailed audit session response
type AuditSessionDetailResponse struct {
	Session        AuditSession      `json:"session"`
	CashAudit      *CashAudit        `json:"cash_audit"`
	InventoryAudit *InventoryAudit   `json:"inventory_audit"`
	Variances      []AuditVariance   `json:"variances"`
	Timeline       []AuditTimelineEvent `json:"timeline"`
}

// AuditTimelineEvent - Timeline event for audit
type AuditTimelineEvent struct {
	Timestamp   time.Time `json:"timestamp"`
	EventType   string    `json:"event_type"`
	Description string    `json:"description"`
	UserID      *uuid.UUID `json:"user_id"`
	UserName    string    `json:"user_name"`
}
