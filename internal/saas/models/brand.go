package models

import (
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// SaasBrand represents predefined brands managed by SaaS Admin
type SaasBrand struct {
	models.BaseModel
	Name        string `json:"name" gorm:"not null;uniqueIndex"`
	DisplayName string `json:"display_name"`
	// DisplayNameBoldStart + DisplayNameBoldLength define an arbitrary
	// [start, start+length) character range that the client renders in
	// big/bold. Start defaults to 0 (prefix); length 0/NULL = no styling.
	DisplayNameBoldStart  *int   `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int   `json:"display_name_bold_length,omitempty"`
	Description           string `json:"description"`
	Picture               string `json:"picture"` // URL to brand image/logo
	IsActive              bool   `json:"is_active" gorm:"default:true"`
	SortOrder             int    `json:"sort_order" gorm:"default:0"`

	// Relationships
	BrandVariants []BrandVariant `json:"brand_variants,omitempty" gorm:"foreignKey:BrandID"`
	TenantBrands  []TenantBrand  `json:"tenant_brands,omitempty" gorm:"foreignKey:BrandID"`
}

// BrandVariant represents different variants of a brand (sizes, types, etc.)
type BrandVariant struct {
	models.BaseModel
	BrandID       uuid.UUID         `json:"brand_id" gorm:"type:uuid;not null"`
	Brand         *SaasBrand        `json:"brand,omitempty" gorm:"foreignKey:BrandID"`
	CategoryID    uuid.UUID         `json:"category_id" gorm:"type:uuid;not null"`
	Category      *BrandCategory    `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	SubcategoryID *uuid.UUID        `json:"subcategory_id" gorm:"type:uuid"`
	Subcategory   *BrandSubcategory `json:"subcategory,omitempty" gorm:"foreignKey:SubcategoryID"`

	// Product specifications
	Size           string  `json:"size" gorm:"not null"` // e.g., "750ml", "1L", "180ml"
	AlcoholContent float64 `json:"alcohol_content"`      // Alcohol percentage
	Picture        string  `json:"picture"`              // Specific variant image

	// Pricing information
	GovernmentDuty float64 `json:"government_duty" gorm:"default:0"` // Government duty per piece
	BuyingPrice    float64 `json:"buying_price" gorm:"default:0"`    // Suggested buying price
	SellingPrice   float64 `json:"selling_price" gorm:"default:0"`   // Suggested selling price
	MRP            float64 `json:"mrp" gorm:"default:0"`             // Maximum Retail Price

	// Additional attributes
	Description string `json:"description"`
	Barcode     string `json:"barcode"`  // Standard barcode
	HSNCode     string `json:"hsn_code"` // HSN code for tax purposes
	IsActive    bool   `json:"is_active" gorm:"default:true"`
	SortOrder   int    `json:"sort_order" gorm:"default:0"`
}

// TenantBrand represents brands selected by tenants
type TenantBrand struct {
	models.BaseModel
	TenantID uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null"`
	// Tenant relationship handled by TenantID only - no foreign key constraint to avoid circular dependency
	BrandID uuid.UUID  `json:"brand_id" gorm:"type:uuid;not null"`
	Brand   *SaasBrand `json:"brand,omitempty" gorm:"foreignKey:BrandID"`

	// Tenant-specific customizations
	CustomName  *string   `json:"custom_name"` // Tenant can customize brand name
	IsActive    bool      `json:"is_active" gorm:"default:true"`
	ActivatedAt time.Time `json:"activated_at" gorm:"default:CURRENT_TIMESTAMP"`

	// Tenant brand variants (selected variants)
	TenantBrandVariants []TenantBrandVariant `json:"tenant_brand_variants,omitempty" gorm:"foreignKey:TenantBrandID"`
}

// TenantBrandVariant represents specific brand variants selected by tenant
type TenantBrandVariant struct {
	models.BaseModel
	TenantBrandID  uuid.UUID     `json:"tenant_brand_id" gorm:"type:uuid;not null"`
	TenantBrand    *TenantBrand  `json:"tenant_brand,omitempty" gorm:"foreignKey:TenantBrandID"`
	BrandVariantID uuid.UUID     `json:"brand_variant_id" gorm:"type:uuid;not null"`
	BrandVariant   *BrandVariant `json:"brand_variant,omitempty" gorm:"foreignKey:BrandVariantID"`

	// Tenant-specific pricing overrides
	CustomBuyingPrice  *float64 `json:"custom_buying_price"`  // Tenant can override buying price
	CustomSellingPrice *float64 `json:"custom_selling_price"` // Tenant can override selling price
	CustomMRP          *float64 `json:"custom_mrp"`           // Tenant can override MRP

	IsActive    bool      `json:"is_active" gorm:"default:true"`
	ActivatedAt time.Time `json:"activated_at" gorm:"default:CURRENT_TIMESTAMP"`
}

// BrandCategory represents predefined categories for brands
type BrandCategory struct {
	models.BaseModel
	Name        string `json:"name" gorm:"not null;uniqueIndex"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active" gorm:"default:true"`
	SortOrder   int    `json:"sort_order" gorm:"default:0"`

	// Relationships
	BrandVariants []BrandVariant `json:"brand_variants,omitempty" gorm:"foreignKey:CategoryID"`
}

// TableName specifies the table name for BrandCategory
func (BrandCategory) TableName() string {
	return "brand_categories"
}

// BrandSubcategory represents predefined subcategories for brands
// UPDATED: Added CategoryID to link subcategories to categories (industrial-grade relationship)
type BrandSubcategory struct {
	models.BaseModel
	CategoryID  *uuid.UUID     `json:"category_id" gorm:"type:uuid;index"` // ADDED: Link to parent category (nullable for backwards compatibility)
	Category    *BrandCategory `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	Name        string         `json:"name" gorm:"not null"` // CHANGED: Removed uniqueIndex to allow same name in different categories
	Description string         `json:"description"`
	IsActive    bool           `json:"is_active" gorm:"default:true"`
	SortOrder   int            `json:"sort_order" gorm:"default:0"`

	// Relationships
	BrandVariants []BrandVariant `json:"brand_variants,omitempty" gorm:"foreignKey:SubcategoryID"`
}

// TableName specifies the table name for BrandSubcategory
func (BrandSubcategory) TableName() string {
	return "brand_subcategories"
}
