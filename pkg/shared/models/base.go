package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// BaseModel provides common fields for all models
type BaseModel struct {
	ID        uuid.UUID      `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	CreatedAt time.Time      `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt time.Time      `json:"updated_at" gorm:"autoUpdateTime"`
	DeletedAt gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
}

// TenantModel provides tenant isolation for multi-tenant models
type TenantModel struct {
	BaseModel
	TenantID uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null;index"`
	Tenant   *Tenant   `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`
}

// TimestampModel provides only timestamp fields without ID
type TimestampModel struct {
	CreatedAt time.Time      `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt time.Time      `json:"updated_at" gorm:"autoUpdateTime"`
	DeletedAt gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
}

// Status constants
const (
	StatusPending  = "pending"
	StatusApproved = "approved"
	StatusRejected = "rejected"
	StatusActive   = "active"
	StatusInactive = "inactive"
)

// User roles
const (
	RoleAdmin            = "admin"
	RoleManager          = "manager"
	RoleExecutive        = "executive"
	RoleSalesman         = "salesman"
	RoleAssistantManager = "assistant_manager"
	RoleSaasAdmin        = "saas_admin"
)

// Payment methods
const (
	PaymentCash   = "cash"
	PaymentCard   = "card"
	PaymentUPI    = "upi"
	PaymentCredit = "credit"
)

// Stock costing methods
const (
	CostingFIFO    = "fifo"
	CostingLIFO    = "lifo"
	CostingAverage = "average"
)