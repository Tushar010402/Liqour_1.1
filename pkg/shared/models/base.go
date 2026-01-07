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
// TenantID can be NULL for Super Users (SaaS admins)
type TenantModel struct {
	BaseModel
	TenantID *uuid.UUID `json:"tenant_id" gorm:"type:uuid;index"`
	Tenant   *Tenant    `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`
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
	StatusReverted = "reverted"
	StatusActive   = "active"
	StatusInactive = "inactive"
)

// User roles - ordered by hierarchy level (lowest to highest)
// Shop access: salesman = assigned shop only, all others = all shops
const (
	RoleSalesman         = "salesman"          // Level 1 - restricted to assigned shop
	RoleExecutive        = "executive"         // Level 2 - all shops
	RoleAssistantManager = "assistant_manager" // Level 3 - all shops
	RoleManager          = "manager"           // Level 4 - all shops
	RoleAdmin            = "admin"             // Level 5 - all shops
	RoleOwner            = "owner"             // Level 6 - all shops (tenant owner)
	RoleSaasAdmin        = "saas_admin"        // Super user - all tenants, all shops
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
