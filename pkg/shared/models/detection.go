package models

import (
	"time"

	"github.com/google/uuid"
)

// =====================================================
// Theft Detection Constants
// =====================================================

// DetectionType - Types of detected anomalies
type DetectionType string

const (
	DetectionTypeCashShortage     DetectionType = "cash_shortage"
	DetectionTypeCashOverage      DetectionType = "cash_overage"
	DetectionTypeInventoryShrink  DetectionType = "inventory_shrinkage"
	DetectionTypeDiscountAbuse    DetectionType = "discount_abuse"
	DetectionTypeVoidAbuse        DetectionType = "void_abuse"
	DetectionTypeReturnAbuse      DetectionType = "return_abuse"
	DetectionTypeTimingAnomaly    DetectionType = "timing_anomaly"
	DetectionTypePatternAnomaly   DetectionType = "pattern_anomaly"
)

// RiskLevel - Risk severity levels
type RiskLevel string

const (
	RiskLevelLow      RiskLevel = "low"
	RiskLevelMedium   RiskLevel = "medium"
	RiskLevelHigh     RiskLevel = "high"
	RiskLevelCritical RiskLevel = "critical"
)

// InvestigationStatus - Status of investigation
type InvestigationStatus string

const (
	InvestigationStatusOpen         InvestigationStatus = "open"
	InvestigationStatusInProgress   InvestigationStatus = "in_progress"
	InvestigationStatusPendingReview InvestigationStatus = "pending_review"
	InvestigationStatusClosedConfirmed InvestigationStatus = "closed_confirmed"
	InvestigationStatusClosedFalseAlarm InvestigationStatus = "closed_false_alarm"
	InvestigationStatusClosedInsufficient InvestigationStatus = "closed_insufficient"
)

// InvestigationPriority - Priority levels
type InvestigationPriority string

const (
	InvestigationPriorityLow    InvestigationPriority = "low"
	InvestigationPriorityMedium InvestigationPriority = "medium"
	InvestigationPriorityHigh   InvestigationPriority = "high"
	InvestigationPriorityUrgent InvestigationPriority = "urgent"
)

// AlertStatus - Status of detection alerts
type AlertStatus string

const (
	AlertStatusActive      AlertStatus = "active"
	AlertStatusAcknowledged AlertStatus = "acknowledged"
	AlertStatusResolved    AlertStatus = "resolved"
	AlertStatusEscalated   AlertStatus = "escalated"
	AlertStatusDismissed   AlertStatus = "dismissed"
)

// VarianceType - Types of cash variance
type VarianceType string

const (
	VarianceTypeShortage VarianceType = "shortage"
	VarianceTypeOverage  VarianceType = "overage"
)

// =====================================================
// Investigation Model
// =====================================================

// Investigation represents a theft/fraud investigation case
type Investigation struct {
	ID                  uuid.UUID             `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID            uuid.UUID             `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID              uuid.UUID             `json:"shop_id" gorm:"type:uuid;not null;index"`
	CaseNumber          string                `json:"case_number" gorm:"type:varchar(50);uniqueIndex;not null"`
	Title               string                `json:"title" gorm:"type:varchar(200);not null"`
	Description         string                `json:"description" gorm:"type:text"`
	DetectionType       DetectionType         `json:"detection_type" gorm:"type:varchar(50);not null"`
	RiskLevel           RiskLevel             `json:"risk_level" gorm:"type:varchar(20);not null"`
	Status              InvestigationStatus   `json:"status" gorm:"type:varchar(30);default:'open'"`
	Priority            InvestigationPriority `json:"priority" gorm:"type:varchar(20);default:'medium'"`
	EstimatedLoss       float64               `json:"estimated_loss" gorm:"type:decimal(15,2);default:0"`
	ConfirmedLoss       *float64              `json:"confirmed_loss" gorm:"type:decimal(15,2)"`
	SuspectUserID       *uuid.UUID            `json:"suspect_user_id" gorm:"type:uuid;index"`
	AssignedTo          *uuid.UUID            `json:"assigned_to" gorm:"type:uuid;index"`
	RelatedTransactions []uuid.UUID           `json:"related_transactions" gorm:"type:jsonb"`
	Evidence            interface{}           `json:"evidence" gorm:"type:jsonb"`
	DetectedAt          time.Time             `json:"detected_at" gorm:"not null"`
	StartedAt           *time.Time            `json:"started_at"`
	ResolvedAt          *time.Time            `json:"resolved_at"`
	Resolution          string                `json:"resolution" gorm:"type:text"`
	CreatedAt           time.Time             `json:"created_at"`
	UpdatedAt           time.Time             `json:"updated_at"`
	DeletedAt           *time.Time            `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop                *Shop                 `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	SuspectUser         *User                 `json:"suspect_user,omitempty" gorm:"foreignKey:SuspectUserID"`
	Assignee            *User                 `json:"assignee,omitempty" gorm:"foreignKey:AssignedTo"`
	Notes               []InvestigationNote   `json:"notes,omitempty" gorm:"foreignKey:InvestigationID"`
	Activities          []SuspiciousActivity  `json:"activities,omitempty" gorm:"foreignKey:InvestigationID"`
}

func (Investigation) TableName() string {
	return "investigations"
}

// =====================================================
// Investigation Note Model
// =====================================================

// InvestigationNote represents a note added to an investigation
type InvestigationNote struct {
	ID              uuid.UUID `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	InvestigationID uuid.UUID `json:"investigation_id" gorm:"type:uuid;not null;index"`
	AuthorID        uuid.UUID `json:"author_id" gorm:"type:uuid;not null"`
	NoteType        string    `json:"note_type" gorm:"type:varchar(30);default:'comment'"`
	Content         string    `json:"content" gorm:"type:text;not null"`
	Attachments     []string  `json:"attachments" gorm:"type:jsonb"`
	IsInternal      bool      `json:"is_internal" gorm:"default:true"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`

	// Relationships
	Investigation   *Investigation `json:"investigation,omitempty" gorm:"foreignKey:InvestigationID"`
	Author          *User          `json:"author,omitempty" gorm:"foreignKey:AuthorID"`
}

func (InvestigationNote) TableName() string {
	return "investigation_notes"
}

// =====================================================
// Cash Variance Model
// =====================================================

// CashVariance represents detected cash variance
type CashVariance struct {
	ID               uuid.UUID    `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID    `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID           uuid.UUID    `json:"shop_id" gorm:"type:uuid;not null;index"`
	VarianceDate     time.Time    `json:"variance_date" gorm:"type:date;not null"`
	VarianceType     VarianceType `json:"variance_type" gorm:"type:varchar(20);not null"`
	ExpectedAmount   float64      `json:"expected_amount" gorm:"type:decimal(15,2);not null"`
	ActualAmount     float64      `json:"actual_amount" gorm:"type:decimal(15,2);not null"`
	VarianceAmount   float64      `json:"variance_amount" gorm:"type:decimal(15,2);not null"`
	VariancePercent  float64      `json:"variance_percent" gorm:"type:decimal(5,2)"`
	ResponsibleStaff []uuid.UUID  `json:"responsible_staff" gorm:"type:jsonb"`
	Shift            string       `json:"shift" gorm:"type:varchar(20)"`
	RegisterID       string       `json:"register_id" gorm:"type:varchar(50)"`
	Status           string       `json:"status" gorm:"type:varchar(30);default:'detected'"`
	RiskLevel        RiskLevel    `json:"risk_level" gorm:"type:varchar(20)"`
	ZScore           *float64     `json:"z_score" gorm:"type:decimal(5,2)"`
	InvestigationID  *uuid.UUID   `json:"investigation_id" gorm:"type:uuid;index"`
	Notes            string       `json:"notes" gorm:"type:text"`
	ResolvedAt       *time.Time   `json:"resolved_at"`
	ResolvedBy       *uuid.UUID   `json:"resolved_by" gorm:"type:uuid"`
	CreatedAt        time.Time    `json:"created_at"`
	UpdatedAt        time.Time    `json:"updated_at"`
	DeletedAt        *time.Time   `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop           *Shop          `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Investigation  *Investigation `json:"investigation,omitempty" gorm:"foreignKey:InvestigationID"`
	Resolver       *User          `json:"resolver,omitempty" gorm:"foreignKey:ResolvedBy"`
}

func (CashVariance) TableName() string {
	return "cash_variances"
}

// =====================================================
// Suspicious Activity Model
// =====================================================

// SuspiciousActivity represents a detected suspicious activity
type SuspiciousActivity struct {
	ID                  uuid.UUID     `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID            uuid.UUID     `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID              uuid.UUID     `json:"shop_id" gorm:"type:uuid;not null;index"`
	UserID              uuid.UUID     `json:"user_id" gorm:"type:uuid;not null;index"`
	DetectionType       DetectionType `json:"detection_type" gorm:"type:varchar(50);not null"`
	RiskLevel           RiskLevel     `json:"risk_level" gorm:"type:varchar(20);not null"`
	ConfidenceScore     float64       `json:"confidence_score" gorm:"type:decimal(5,2);not null"`
	ZScore              *float64      `json:"z_score" gorm:"type:decimal(5,2)"`
	Description         string        `json:"description" gorm:"type:text;not null"`
	RelatedTransactions []uuid.UUID   `json:"related_transactions" gorm:"type:jsonb"`
	Metrics             interface{}   `json:"metrics" gorm:"type:jsonb"`
	TotalImpact         *float64      `json:"total_impact" gorm:"type:decimal(15,2)"`
	Status              string        `json:"status" gorm:"type:varchar(30);default:'detected'"`
	InvestigationID     *uuid.UUID    `json:"investigation_id" gorm:"type:uuid;index"`
	DetectedAt          time.Time     `json:"detected_at" gorm:"not null"`
	AcknowledgedAt      *time.Time    `json:"acknowledged_at"`
	AcknowledgedBy      *uuid.UUID    `json:"acknowledged_by" gorm:"type:uuid"`
	CreatedAt           time.Time     `json:"created_at"`
	UpdatedAt           time.Time     `json:"updated_at"`
	DeletedAt           *time.Time    `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop            *Shop          `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	User            *User          `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Investigation   *Investigation `json:"investigation,omitempty" gorm:"foreignKey:InvestigationID"`
	Acknowledger    *User          `json:"acknowledger,omitempty" gorm:"foreignKey:AcknowledgedBy"`
}

func (SuspiciousActivity) TableName() string {
	return "suspicious_activities"
}

// =====================================================
// Alert Configuration Model
// =====================================================

// AlertConfiguration defines thresholds for detection alerts
type AlertConfiguration struct {
	ID                 uuid.UUID     `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID           uuid.UUID     `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID             *uuid.UUID    `json:"shop_id" gorm:"type:uuid;index"`
	DetectionType      DetectionType `json:"detection_type" gorm:"type:varchar(50);not null"`
	IsEnabled          bool          `json:"is_enabled" gorm:"default:true"`
	ThresholdAmount    *float64      `json:"threshold_amount" gorm:"type:decimal(15,2)"`
	ThresholdPercent   *float64      `json:"threshold_percent" gorm:"type:decimal(5,2)"`
	ZScoreThreshold    float64       `json:"z_score_threshold" gorm:"type:decimal(5,2);default:2.5"`
	MinOccurrences     int           `json:"min_occurrences" gorm:"default:1"`
	TimeWindowMinutes  int           `json:"time_window_minutes" gorm:"default:60"`
	EscalationMinutes  int           `json:"escalation_minutes" gorm:"default:30"`
	NotifyRoles        []string      `json:"notify_roles" gorm:"type:jsonb"`
	AutoInvestigate    bool          `json:"auto_investigate" gorm:"default:false"`
	AutoInvestigateAt  RiskLevel     `json:"auto_investigate_at" gorm:"type:varchar(20);default:'high'"`
	CreatedAt          time.Time     `json:"created_at"`
	UpdatedAt          time.Time     `json:"updated_at"`

	// Relationships
	Shop               *Shop         `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
}

func (AlertConfiguration) TableName() string {
	return "alert_configurations"
}

// =====================================================
// Detection Alert Model
// =====================================================

// DetectionAlert represents an alert generated by detection system
type DetectionAlert struct {
	ID               uuid.UUID     `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID         uuid.UUID     `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID           uuid.UUID     `json:"shop_id" gorm:"type:uuid;not null;index"`
	ConfigID         *uuid.UUID    `json:"config_id" gorm:"type:uuid;index"`
	DetectionType    DetectionType `json:"detection_type" gorm:"type:varchar(50);not null"`
	RiskLevel        RiskLevel     `json:"risk_level" gorm:"type:varchar(20);not null"`
	Status           AlertStatus   `json:"status" gorm:"type:varchar(20);default:'active'"`
	Title            string        `json:"title" gorm:"type:varchar(200);not null"`
	Description      string        `json:"description" gorm:"type:text"`
	AffectedUserID   *uuid.UUID    `json:"affected_user_id" gorm:"type:uuid;index"`
	ImpactAmount     *float64      `json:"impact_amount" gorm:"type:decimal(15,2)"`
	RelatedEntityID  *uuid.UUID    `json:"related_entity_id" gorm:"type:uuid"`
	RelatedEntityType string       `json:"related_entity_type" gorm:"type:varchar(50)"`
	InvestigationID  *uuid.UUID    `json:"investigation_id" gorm:"type:uuid;index"`
	TriggeredAt      time.Time     `json:"triggered_at" gorm:"not null"`
	EscalateAt       *time.Time    `json:"escalate_at"`
	EscalatedAt      *time.Time    `json:"escalated_at"`
	AcknowledgedAt   *time.Time    `json:"acknowledged_at"`
	AcknowledgedBy   *uuid.UUID    `json:"acknowledged_by" gorm:"type:uuid"`
	ResolvedAt       *time.Time    `json:"resolved_at"`
	ResolvedBy       *uuid.UUID    `json:"resolved_by" gorm:"type:uuid"`
	Resolution       string        `json:"resolution" gorm:"type:text"`
	CreatedAt        time.Time     `json:"created_at"`
	UpdatedAt        time.Time     `json:"updated_at"`

	// Relationships
	Shop           *Shop               `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Config         *AlertConfiguration `json:"config,omitempty" gorm:"foreignKey:ConfigID"`
	AffectedUser   *User               `json:"affected_user,omitempty" gorm:"foreignKey:AffectedUserID"`
	Investigation  *Investigation      `json:"investigation,omitempty" gorm:"foreignKey:InvestigationID"`
	Acknowledger   *User               `json:"acknowledger,omitempty" gorm:"foreignKey:AcknowledgedBy"`
	Resolver       *User               `json:"resolver,omitempty" gorm:"foreignKey:ResolvedBy"`
}

func (DetectionAlert) TableName() string {
	return "detection_alerts"
}

// =====================================================
// Detection Metric Model
// =====================================================

// DetectionMetric stores computed metrics for anomaly detection
type DetectionMetric struct {
	ID              uuid.UUID     `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID        uuid.UUID     `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID          uuid.UUID     `json:"shop_id" gorm:"type:uuid;not null;index"`
	UserID          *uuid.UUID    `json:"user_id" gorm:"type:uuid;index"`
	MetricType      DetectionType `json:"metric_type" gorm:"type:varchar(50);not null"`
	MetricDate      time.Time     `json:"metric_date" gorm:"type:date;not null"`
	Value           float64       `json:"value" gorm:"type:decimal(15,4);not null"`
	RollingMean     *float64      `json:"rolling_mean" gorm:"type:decimal(15,4)"`
	RollingStdDev   *float64      `json:"rolling_std_dev" gorm:"type:decimal(15,4)"`
	ZScore          *float64      `json:"z_score" gorm:"type:decimal(5,2)"`
	SampleSize      int           `json:"sample_size" gorm:"default:0"`
	CreatedAt       time.Time     `json:"created_at"`
	UpdatedAt       time.Time     `json:"updated_at"`

	// Relationships
	Shop            *Shop         `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	User            *User         `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

func (DetectionMetric) TableName() string {
	return "detection_metrics"
}

// =====================================================
// Request/Response DTOs
// =====================================================

// CreateInvestigationRequest - Request to create investigation
type CreateInvestigationRequest struct {
	ShopID          uuid.UUID             `json:"shop_id" binding:"required"`
	Title           string                `json:"title" binding:"required,max=200"`
	Description     string                `json:"description"`
	DetectionType   DetectionType         `json:"detection_type" binding:"required"`
	RiskLevel       RiskLevel             `json:"risk_level" binding:"required"`
	Priority        InvestigationPriority `json:"priority"`
	EstimatedLoss   float64               `json:"estimated_loss"`
	SuspectUserID   *uuid.UUID            `json:"suspect_user_id"`
	AssignedTo      *uuid.UUID            `json:"assigned_to"`
	RelatedActivityIDs []uuid.UUID        `json:"related_activity_ids"`
}

// UpdateInvestigationRequest - Request to update investigation
type UpdateInvestigationRequest struct {
	Title         *string                `json:"title"`
	Description   *string                `json:"description"`
	Status        *InvestigationStatus   `json:"status"`
	Priority      *InvestigationPriority `json:"priority"`
	ConfirmedLoss *float64               `json:"confirmed_loss"`
	AssignedTo    *uuid.UUID             `json:"assigned_to"`
	Resolution    *string                `json:"resolution"`
}

// AddInvestigationNoteRequest - Request to add note
type AddInvestigationNoteRequest struct {
	NoteType    string   `json:"note_type"`
	Content     string   `json:"content" binding:"required"`
	Attachments []string `json:"attachments"`
	IsInternal  bool     `json:"is_internal"`
}

// ConfigureAlertRequest - Request to configure alert
type ConfigureAlertRequest struct {
	ShopID            *uuid.UUID    `json:"shop_id"`
	DetectionType     DetectionType `json:"detection_type" binding:"required"`
	IsEnabled         *bool         `json:"is_enabled"`
	ThresholdAmount   *float64      `json:"threshold_amount"`
	ThresholdPercent  *float64      `json:"threshold_percent"`
	ZScoreThreshold   *float64      `json:"z_score_threshold"`
	MinOccurrences    *int          `json:"min_occurrences"`
	TimeWindowMinutes *int          `json:"time_window_minutes"`
	EscalationMinutes *int          `json:"escalation_minutes"`
	NotifyRoles       []string      `json:"notify_roles"`
	AutoInvestigate   *bool         `json:"auto_investigate"`
	AutoInvestigateAt *RiskLevel    `json:"auto_investigate_at"`
}

// AcknowledgeAlertRequest - Request to acknowledge alert
type AcknowledgeAlertRequest struct {
	AlertID uuid.UUID `json:"alert_id" binding:"required"`
	Notes   string    `json:"notes"`
}

// ResolveAlertRequest - Request to resolve alert
type ResolveAlertRequest struct {
	AlertID    uuid.UUID `json:"alert_id" binding:"required"`
	Resolution string    `json:"resolution" binding:"required"`
}

// DetectionDashboardResponse - Dashboard summary for detection
type DetectionDashboardResponse struct {
	Summary            DetectionSummary           `json:"summary"`
	ActiveAlerts       []DetectionAlert           `json:"active_alerts"`
	OpenInvestigations []Investigation            `json:"open_investigations"`
	RecentActivities   []SuspiciousActivity       `json:"recent_activities"`
	RiskTrend          []DailyRiskStat            `json:"risk_trend"`
	TopRiskUsers       []UserRiskProfile          `json:"top_risk_users"`
}

// DetectionSummary - Summary statistics for detection
type DetectionSummary struct {
	TotalAlerts         int     `json:"total_alerts"`
	ActiveAlerts        int     `json:"active_alerts"`
	CriticalAlerts      int     `json:"critical_alerts"`
	OpenInvestigations  int     `json:"open_investigations"`
	ResolvedThisMonth   int     `json:"resolved_this_month"`
	EstimatedLossTotal  float64 `json:"estimated_loss_total"`
	ConfirmedLossTotal  float64 `json:"confirmed_loss_total"`
	AverageCaseTime     float64 `json:"average_case_time_hours"`
}

// DailyRiskStat - Daily risk statistics
type DailyRiskStat struct {
	Date           time.Time `json:"date"`
	AlertCount     int       `json:"alert_count"`
	CriticalCount  int       `json:"critical_count"`
	HighCount      int       `json:"high_count"`
	MediumCount    int       `json:"medium_count"`
	LowCount       int       `json:"low_count"`
	EstimatedLoss  float64   `json:"estimated_loss"`
}

// UserRiskProfile - Risk profile for a user
type UserRiskProfile struct {
	UserID           uuid.UUID       `json:"user_id"`
	UserName         string          `json:"user_name"`
	Role             string          `json:"role"`
	ShopName         string          `json:"shop_name"`
	TotalIncidents   int             `json:"total_incidents"`
	ConfirmedCount   int             `json:"confirmed_count"`
	FalsePositives   int             `json:"false_positives"`
	RiskScore        float64         `json:"risk_score"`
	TotalImpact      float64         `json:"total_impact"`
	LatestIncident   *time.Time      `json:"latest_incident"`
	PrimaryRiskType  DetectionType   `json:"primary_risk_type"`
}

// AnomalyDetectionResult - Result of anomaly detection
type AnomalyDetectionResult struct {
	IsAnomaly       bool          `json:"is_anomaly"`
	DetectionType   DetectionType `json:"detection_type"`
	ZScore          float64       `json:"z_score"`
	ConfidenceScore float64       `json:"confidence_score"`
	RiskLevel       RiskLevel     `json:"risk_level"`
	Description     string        `json:"description"`
	Value           float64       `json:"value"`
	ExpectedRange   [2]float64    `json:"expected_range"`
	Metrics         interface{}   `json:"metrics"`
}
