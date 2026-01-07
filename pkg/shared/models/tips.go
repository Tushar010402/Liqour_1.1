package models

import (
	"time"

	"github.com/google/uuid"
)

// =====================================================
// Tips Management Constants
// =====================================================

// TipType - Types of tips
type TipType string

const (
	TipTypeIndividual TipType = "individual"
	TipTypePooled     TipType = "pooled"
)

// TipSource - Source of tip income
type TipSource string

const (
	TipSourceCash   TipSource = "cash"
	TipSourceCard   TipSource = "card"
	TipSourceUPI    TipSource = "upi"
	TipSourceOther  TipSource = "other"
)

// TipPayoutStatus - Status of tip payout
type TipPayoutStatus string

const (
	TipPayoutStatusPending   TipPayoutStatus = "pending"
	TipPayoutStatusApproved  TipPayoutStatus = "approved"
	TipPayoutStatusPaid      TipPayoutStatus = "paid"
	TipPayoutStatusRejected  TipPayoutStatus = "rejected"
)

// TipPoolStatus - Status of tip pool
type TipPoolStatus string

const (
	TipPoolStatusPending     TipPoolStatus = "pending"
	TipPoolStatusDistributed TipPoolStatus = "distributed"
	TipPoolStatusClosed      TipPoolStatus = "closed"
)

// TipDistributionMethod - Method of pool distribution
type TipDistributionMethod string

const (
	TipDistributionEqual          TipDistributionMethod = "equal"
	TipDistributionHoursWorked    TipDistributionMethod = "hours_worked"
	TipDistributionSalesProportional TipDistributionMethod = "sales_proportional"
	TipDistributionCustom         TipDistributionMethod = "custom"
)

// =====================================================
// Tip Pool Model
// =====================================================

// TipPool represents a pooled tip collection for a specific period
type TipPool struct {
	ID                uuid.UUID             `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID             `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID            uuid.UUID             `json:"shop_id" gorm:"type:uuid;not null;index"`
	PoolDate          time.Time             `json:"pool_date" gorm:"type:date;not null"`
	TotalAmount       float64               `json:"total_amount" gorm:"type:decimal(15,2);default:0"`
	DistributionMethod TipDistributionMethod `json:"distribution_method" gorm:"type:varchar(30);default:'equal'"`
	Status            TipPoolStatus         `json:"status" gorm:"type:varchar(20);default:'pending'"`
	ParticipantCount  int                   `json:"participant_count" gorm:"default:0"`
	Notes             string                `json:"notes" gorm:"type:text"`
	DistributedAt     *time.Time            `json:"distributed_at"`
	DistributedBy     *uuid.UUID            `json:"distributed_by" gorm:"type:uuid"`
	CreatedAt         time.Time             `json:"created_at"`
	UpdatedAt         time.Time             `json:"updated_at"`
	DeletedAt         *time.Time            `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop              *Shop                 `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Distributor       *User                 `json:"distributor,omitempty" gorm:"foreignKey:DistributedBy"`
	Distributions     []TipDistribution     `json:"distributions,omitempty" gorm:"foreignKey:PoolID"`
}

func (TipPool) TableName() string {
	return "tip_pools"
}

// =====================================================
// Tip Transaction Model
// =====================================================

// TipTransaction represents an individual tip record
type TipTransaction struct {
	ID                uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID            uuid.UUID       `json:"shop_id" gorm:"type:uuid;not null;index"`
	SalesmanID        uuid.UUID       `json:"salesman_id" gorm:"type:uuid;not null;index"`
	DailySalesID      *uuid.UUID      `json:"daily_sales_id" gorm:"type:uuid;index"`
	PoolID            *uuid.UUID      `json:"pool_id" gorm:"type:uuid;index"`
	TipType           TipType         `json:"tip_type" gorm:"type:varchar(20);not null"`
	Amount            float64         `json:"amount" gorm:"type:decimal(10,2);not null"`
	Source            TipSource       `json:"source" gorm:"type:varchar(20);default:'cash'"`
	PayoutStatus      TipPayoutStatus `json:"payout_status" gorm:"type:varchar(20);default:'pending'"`
	CustomerName      string          `json:"customer_name" gorm:"type:varchar(100)"`
	Description       string          `json:"description" gorm:"type:text"`
	RecordedAt        time.Time       `json:"recorded_at" gorm:"not null"`
	RecordedBy        uuid.UUID       `json:"recorded_by" gorm:"type:uuid;not null"`
	ApprovedAt        *time.Time      `json:"approved_at"`
	ApprovedBy        *uuid.UUID      `json:"approved_by" gorm:"type:uuid"`
	PaidAt            *time.Time      `json:"paid_at"`
	PayoutBatchID     *uuid.UUID      `json:"payout_batch_id" gorm:"type:uuid;index"`
	CreatedAt         time.Time       `json:"created_at"`
	UpdatedAt         time.Time       `json:"updated_at"`
	DeletedAt         *time.Time      `json:"deleted_at" gorm:"index"`

	// Relationships
	Shop              *Shop           `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Salesman          *User           `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`
	Pool              *TipPool        `json:"pool,omitempty" gorm:"foreignKey:PoolID"`
	Recorder          *User           `json:"recorder,omitempty" gorm:"foreignKey:RecordedBy"`
	Approver          *User           `json:"approver,omitempty" gorm:"foreignKey:ApprovedBy"`
	PayoutBatch       *TipPayoutBatch `json:"payout_batch,omitempty" gorm:"foreignKey:PayoutBatchID"`
}

func (TipTransaction) TableName() string {
	return "tip_transactions"
}

// =====================================================
// Tip Distribution Model
// =====================================================

// TipDistribution represents distribution from a pool to a salesman
type TipDistribution struct {
	ID                uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	PoolID            uuid.UUID       `json:"pool_id" gorm:"type:uuid;not null;index"`
	SalesmanID        uuid.UUID       `json:"salesman_id" gorm:"type:uuid;not null;index"`
	Amount            float64         `json:"amount" gorm:"type:decimal(10,2);not null"`
	HoursWorked       *float64        `json:"hours_worked" gorm:"type:decimal(5,2)"`
	SalesAmount       *float64        `json:"sales_amount" gorm:"type:decimal(15,2)"`
	CustomPercentage  *float64        `json:"custom_percentage" gorm:"type:decimal(5,2)"`
	PayoutStatus      TipPayoutStatus `json:"payout_status" gorm:"type:varchar(20);default:'pending'"`
	PayoutBatchID     *uuid.UUID      `json:"payout_batch_id" gorm:"type:uuid;index"`
	PaidAt            *time.Time      `json:"paid_at"`
	Notes             string          `json:"notes" gorm:"type:text"`
	CreatedAt         time.Time       `json:"created_at"`
	UpdatedAt         time.Time       `json:"updated_at"`

	// Relationships
	Pool              *TipPool        `json:"pool,omitempty" gorm:"foreignKey:PoolID"`
	Salesman          *User           `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`
	PayoutBatch       *TipPayoutBatch `json:"payout_batch,omitempty" gorm:"foreignKey:PayoutBatchID"`
}

func (TipDistribution) TableName() string {
	return "tip_distributions"
}

// =====================================================
// Tip Payout Batch Model
// =====================================================

// TipPayoutBatch represents a batch payout of tips
type TipPayoutBatch struct {
	ID                uuid.UUID       `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID            *uuid.UUID      `json:"shop_id" gorm:"type:uuid;index"`
	BatchNumber       string          `json:"batch_number" gorm:"type:varchar(50);uniqueIndex;not null"`
	TotalAmount       float64         `json:"total_amount" gorm:"type:decimal(15,2);not null"`
	TransactionCount  int             `json:"transaction_count" gorm:"default:0"`
	Status            TipPayoutStatus `json:"status" gorm:"type:varchar(20);default:'pending'"`
	PaymentMethod     string          `json:"payment_method" gorm:"type:varchar(30)"`
	PaymentReference  string          `json:"payment_reference" gorm:"type:varchar(100)"`
	PeriodStart       time.Time       `json:"period_start" gorm:"type:date;not null"`
	PeriodEnd         time.Time       `json:"period_end" gorm:"type:date;not null"`
	ProcessedAt       *time.Time      `json:"processed_at"`
	ProcessedBy       *uuid.UUID      `json:"processed_by" gorm:"type:uuid"`
	ApprovedAt        *time.Time      `json:"approved_at"`
	ApprovedBy        *uuid.UUID      `json:"approved_by" gorm:"type:uuid"`
	Notes             string          `json:"notes" gorm:"type:text"`
	CreatedAt         time.Time       `json:"created_at"`
	UpdatedAt         time.Time       `json:"updated_at"`

	// Relationships
	Shop              *Shop           `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Processor         *User           `json:"processor,omitempty" gorm:"foreignKey:ProcessedBy"`
	Approver          *User           `json:"approver,omitempty" gorm:"foreignKey:ApprovedBy"`
	Transactions      []TipTransaction   `json:"transactions,omitempty" gorm:"foreignKey:PayoutBatchID"`
	Distributions     []TipDistribution  `json:"distributions,omitempty" gorm:"foreignKey:PayoutBatchID"`
}

func (TipPayoutBatch) TableName() string {
	return "tip_payout_batches"
}

// =====================================================
// Tip Report Cache Model
// =====================================================

// TipReportCache stores pre-computed tip reports
type TipReportCache struct {
	ID                uuid.UUID   `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID          uuid.UUID   `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID            *uuid.UUID  `json:"shop_id" gorm:"type:uuid;index"`
	ReportType        string      `json:"report_type" gorm:"type:varchar(50);not null"`
	PeriodStart       time.Time   `json:"period_start" gorm:"type:date;not null"`
	PeriodEnd         time.Time   `json:"period_end" gorm:"type:date;not null"`
	ReportData        interface{} `json:"report_data" gorm:"type:jsonb"`
	GeneratedAt       time.Time   `json:"generated_at" gorm:"not null"`
	ExpiresAt         *time.Time  `json:"expires_at"`
	CreatedAt         time.Time   `json:"created_at"`
}

func (TipReportCache) TableName() string {
	return "tip_reports_cache"
}

// =====================================================
// Request/Response DTOs
// =====================================================

// CreateTipRequest - Request to create a tip transaction
type CreateTipRequest struct {
	ShopID       uuid.UUID `json:"shop_id" binding:"required"`
	SalesmanID   uuid.UUID `json:"salesman_id" binding:"required"`
	DailySalesID *uuid.UUID `json:"daily_sales_id"`
	TipType      TipType   `json:"tip_type" binding:"required"`
	Amount       float64   `json:"amount" binding:"required,gt=0"`
	Source       TipSource `json:"source"`
	CustomerName string    `json:"customer_name"`
	Description  string    `json:"description"`
}

// CreateTipPoolRequest - Request to create a tip pool
type CreateTipPoolRequest struct {
	ShopID             uuid.UUID             `json:"shop_id" binding:"required"`
	PoolDate           time.Time             `json:"pool_date" binding:"required"`
	DistributionMethod TipDistributionMethod `json:"distribution_method" binding:"required"`
	Notes              string                `json:"notes"`
}

// AddToPoolRequest - Request to add tip to pool
type AddToPoolRequest struct {
	PoolID  uuid.UUID `json:"pool_id" binding:"required"`
	Amount  float64   `json:"amount" binding:"required,gt=0"`
	Source  TipSource `json:"source"`
}

// DistributePoolRequest - Request to distribute pool tips
type DistributePoolRequest struct {
	PoolID       uuid.UUID                 `json:"pool_id" binding:"required"`
	Distributions []DistributionAllocation `json:"distributions" binding:"required,min=1"`
}

// DistributionAllocation - Allocation for pool distribution
type DistributionAllocation struct {
	SalesmanID       uuid.UUID `json:"salesman_id" binding:"required"`
	HoursWorked      *float64  `json:"hours_worked"`
	SalesAmount      *float64  `json:"sales_amount"`
	CustomPercentage *float64  `json:"custom_percentage"`
}

// TipPayoutRequest - Request to create payout batch
type TipPayoutRequest struct {
	ShopID           *uuid.UUID  `json:"shop_id"`
	PeriodStart      time.Time   `json:"period_start" binding:"required"`
	PeriodEnd        time.Time   `json:"period_end" binding:"required"`
	PaymentMethod    string      `json:"payment_method"`
	PaymentReference string      `json:"payment_reference"`
	Notes            string      `json:"notes"`
}

// TipSummaryResponse - Tip summary for a period
type TipSummaryResponse struct {
	TotalTips          float64                    `json:"total_tips"`
	IndividualTips     float64                    `json:"individual_tips"`
	PooledTips         float64                    `json:"pooled_tips"`
	PendingPayout      float64                    `json:"pending_payout"`
	PaidAmount         float64                    `json:"paid_amount"`
	TipCount           int                        `json:"tip_count"`
	SalesmanBreakdown  []SalesmanTipSummary       `json:"salesman_breakdown"`
	SourceBreakdown    map[TipSource]float64      `json:"source_breakdown"`
	DailyTrend         []DailyTipStat             `json:"daily_trend"`
}

// SalesmanTipSummary - Tip summary per salesman
type SalesmanTipSummary struct {
	SalesmanID      uuid.UUID `json:"salesman_id"`
	SalesmanName    string    `json:"salesman_name"`
	IndividualTips  float64   `json:"individual_tips"`
	PooledShare     float64   `json:"pooled_share"`
	TotalTips       float64   `json:"total_tips"`
	PendingPayout   float64   `json:"pending_payout"`
	PaidAmount      float64   `json:"paid_amount"`
	TipCount        int       `json:"tip_count"`
}

// DailyTipStat - Daily tip statistics
type DailyTipStat struct {
	Date           time.Time `json:"date"`
	TotalAmount    float64   `json:"total_amount"`
	IndividualTips float64   `json:"individual_tips"`
	PooledTips     float64   `json:"pooled_tips"`
	TipCount       int       `json:"tip_count"`
}

// PoolDetailResponse - Detailed pool information
type PoolDetailResponse struct {
	Pool          TipPool                `json:"pool"`
	Contributions []TipTransaction       `json:"contributions"`
	Distributions []TipDistribution      `json:"distributions"`
	Summary       PoolSummary            `json:"summary"`
}

// PoolSummary - Summary of pool distribution
type PoolSummary struct {
	TotalContributions int     `json:"total_contributions"`
	TotalAmount        float64 `json:"total_amount"`
	ParticipantCount   int     `json:"participant_count"`
	DistributedAmount  float64 `json:"distributed_amount"`
	PendingAmount      float64 `json:"pending_amount"`
}
