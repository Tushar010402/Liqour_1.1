package models

import (
	"time"

	"github.com/google/uuid"
)

// Tenant represents a company/organization in the multi-tenant system
type Tenant struct {
	BaseModel
	Name        string    `json:"name" gorm:"type:text;not null"`
	CompanyName string    `json:"company_name" gorm:"type:varchar(255);not null"`
	Logo        string    `json:"logo,omitempty" gorm:"type:varchar(255)"`
	Phone       string    `json:"phone,omitempty" gorm:"type:varchar(20)"`
	Address     string    `json:"address,omitempty" gorm:"type:text"`
	City        string    `json:"city,omitempty" gorm:"type:varchar(100)"`
	State       string    `json:"state,omitempty" gorm:"type:varchar(100)"`
	Country     string    `json:"country,omitempty" gorm:"type:varchar(100)"`
	PostalCode  string    `json:"postal_code,omitempty" gorm:"type:varchar(20)"`
	IsActive    bool      `json:"is_active" gorm:"default:true"`
	OnboardedAt time.Time `json:"onboarded_at" gorm:"default:now()"`

	// Relationships
	Shops []Shop `json:"shops,omitempty" gorm:"foreignKey:TenantID"`
	Users []User `json:"users,omitempty" gorm:"foreignKey:TenantID"`
}

// Shop represents a physical store location within a tenant
type Shop struct {
	TenantModel
	Name          string  `json:"name" gorm:"not null"`
	Address       string  `json:"address"`
	Phone         string  `json:"phone"`
	LicenseNumber string  `json:"license_number"`
	LicenseFile   string  `json:"license_file"`
	Latitude      float64 `json:"latitude"`
	Longitude     float64 `json:"longitude"`
	IsActive      bool    `json:"is_active" gorm:"default:true"`

	// Relationships
	Stocks     []Stock            `json:"stocks,omitempty" gorm:"foreignKey:ShopID"`
	Sales      []Sale             `json:"sales,omitempty" gorm:"foreignKey:ShopID"`
	DailySales []DailySalesRecord `json:"daily_sales,omitempty" gorm:"foreignKey:ShopID"`
	Salesmen   []Salesman         `json:"salesmen,omitempty" gorm:"foreignKey:ShopID"`
}

// Salesman represents sales personnel associated with a shop
type Salesman struct {
	TenantModel
	UserID           uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	User             *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`
	ShopID           uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop             *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	EmployeeID       string    `json:"employee_id"`
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
