package models

import (
	"time"

	"github.com/google/uuid"
)

// Tenant represents a company/organization in the multi-tenant system
type Tenant struct {
	BaseModel
	Name         string    `json:"name" gorm:"not null"`
	Domain       string    `json:"domain" gorm:"unique"`
	IsActive     bool      `json:"is_active" gorm:"default:true"`
	SubscribedAt time.Time `json:"subscribed_at"`
	ExpiresAt    *time.Time `json:"expires_at"`
	
	// Relationships
	Shops []Shop `json:"shops,omitempty" gorm:"foreignKey:TenantID"`
	Users []User `json:"users,omitempty" gorm:"foreignKey:TenantID"`
}

// Shop represents a physical store location within a tenant
type Shop struct {
	TenantModel
	Name           string  `json:"name" gorm:"not null"`
	Address        string  `json:"address"`
	Phone          string  `json:"phone"`
	LicenseNumber  string  `json:"license_number"`
	LicenseFile    string  `json:"license_file"`
	Latitude       float64 `json:"latitude"`
	Longitude      float64 `json:"longitude"`
	IsActive       bool    `json:"is_active" gorm:"default:true"`
	
	// Relationships
	Stocks      []Stock      `json:"stocks,omitempty" gorm:"foreignKey:ShopID"`
	Sales       []Sale       `json:"sales,omitempty" gorm:"foreignKey:ShopID"`
	DailySales  []DailySalesRecord `json:"daily_sales,omitempty" gorm:"foreignKey:ShopID"`
	Salesmen    []Salesman   `json:"salesmen,omitempty" gorm:"foreignKey:ShopID"`
}

// Salesman represents sales personnel associated with a shop
type Salesman struct {
	TenantModel
	UserID           uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	User             *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`
	ShopID           uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop             *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	EmployeeID       string    `json:"employee_id" gorm:"unique"`
	Name             string    `json:"name" gorm:"not null"`
	Phone            string    `json:"phone"`
	Address          string    `json:"address"`
	CertificateImage string    `json:"certificate_image"`
	JoinDate         time.Time `json:"join_date"`
	IsActive         bool      `json:"is_active" gorm:"default:true"`
	
	// Relationships
	Sales      []Sale             `json:"sales,omitempty" gorm:"foreignKey:SalesmanID"`
	DailySales []DailySalesRecord `json:"daily_sales,omitempty" gorm:"foreignKey:SalesmanID"`
}