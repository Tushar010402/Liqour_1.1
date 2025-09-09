package models

import (
	"time"
	"github.com/google/uuid"
)

// User represents system users with role-based access
type User struct {
	TenantModel
	Username     string `json:"username" gorm:"unique;not null"`
	Email        string `json:"email" gorm:"unique;not null"`
	FirstName    string `json:"first_name"`
	LastName     string `json:"last_name"`
	Phone        string `json:"phone"`
	PasswordHash string `json:"-" gorm:"not null"`
	Role         string `json:"role" gorm:"not null;default:'salesman'"`
	CustomRole   string `json:"custom_role"`
	IsActive     bool   `json:"is_active" gorm:"default:true"`
	IsStaff      bool   `json:"is_staff" gorm:"default:false"`
	IsSuperuser  bool   `json:"is_superuser" gorm:"default:false"`
	
	// Profile fields
	ProfileImage string `json:"profile_image"`
	
	// Relationships
	TenantRoles       []TenantRole       `json:"tenant_roles,omitempty" gorm:"foreignKey:UserID"`
	TenantPermissions []TenantPermission `json:"tenant_permissions,omitempty" gorm:"foreignKey:UserID"`
	Salesman          *Salesman          `json:"salesman,omitempty" gorm:"foreignKey:UserID"`
	
	// Sales and finance relationships
	CreatedSales       []Sale              `json:"created_sales,omitempty" gorm:"foreignKey:CreatedByID"`
	ApprovedSales      []Sale              `json:"approved_sales,omitempty" gorm:"foreignKey:ApprovedByID"`
	CreatedReturns     []SaleReturn        `json:"created_returns,omitempty" gorm:"foreignKey:CreatedByID"`
	ApprovedReturns    []SaleReturn        `json:"approved_returns,omitempty" gorm:"foreignKey:ApprovedByID"`
	ExecutiveFinances  []ExecutiveFinance  `json:"executive_finances,omitempty" gorm:"foreignKey:ExecutiveID"`
	MoneyCollections   []MoneyCollection   `json:"money_collections,omitempty" gorm:"foreignKey:AssistantManagerID"`
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

// UserSession represents active user sessions
type UserSession struct {
	BaseModel
	UserID    uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	User      *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Token     string    `json:"token" gorm:"unique;not null"`
	IPAddress string    `json:"ip_address"`
	UserAgent string    `json:"user_agent"`
	ExpiresAt *time.Time `json:"expires_at"`
	IsActive  bool      `json:"is_active" gorm:"default:true"`
}