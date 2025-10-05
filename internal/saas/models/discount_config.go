package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// GlobalDiscountConfig stores system-wide discount configuration templates
type GlobalDiscountConfig struct {
	ID                uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Name              string         `json:"name" gorm:"not null"`                  // e.g., "Standard", "Aggressive", "Conservative"
	Description       string         `json:"description"`                           // Description of the discount template
	YearlyDiscount    float64        `json:"yearly_discount" gorm:"default:20"`     // 12-month discount %
	TwoYearDiscount   float64        `json:"two_year_discount" gorm:"default:30"`   // 24-month discount %
	ThreeYearDiscount float64        `json:"three_year_discount" gorm:"default:40"` // 36-month discount %
	IsDefault         bool           `json:"is_default" gorm:"default:false"`       // Whether this is the default template
	IsActive          bool           `json:"is_active" gorm:"default:true"`         // Whether this template is active
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `json:"deleted_at" gorm:"index"`
}

// PlanDiscountOverride allows individual plans to override global discount settings
type PlanDiscountOverride struct {
	ID                uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	PlanID            uuid.UUID      `json:"plan_id" gorm:"type:uuid;not null;index"`
	YearlyDiscount    *float64       `json:"yearly_discount"`     // Override yearly discount (null = use plan default)
	TwoYearDiscount   *float64       `json:"two_year_discount"`   // Override 2-year discount (null = use plan default)
	ThreeYearDiscount *float64       `json:"three_year_discount"` // Override 3-year discount (null = use plan default)
	EffectiveFrom     time.Time      `json:"effective_from"`      // When this override becomes effective
	EffectiveTo       *time.Time     `json:"effective_to"`        // When this override expires (null = indefinite)
	Reason            string         `json:"reason"`              // Reason for the override (e.g., "Holiday Sale", "Promotion")
	IsActive          bool           `json:"is_active" gorm:"default:true"`
	CreatedBy         uuid.UUID      `json:"created_by" gorm:"type:uuid"` // Admin user who created the override
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	Plan PricingPlan `json:"plan,omitempty" gorm:"foreignKey:PlanID"`
}

// BillingTermConfig defines available billing terms and their properties
type BillingTermConfig struct {
	ID                 uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	TermMonths         int            `json:"term_months" gorm:"not null;unique"`      // Number of months (1, 12, 24, 36)
	TermName           string         `json:"term_name" gorm:"not null"`               // Display name (Monthly, Yearly, etc.)
	PaymentSchedule    string         `json:"payment_schedule" gorm:"not null"`        // Monthly, Annual, One-time
	IsEnabled          bool           `json:"is_enabled" gorm:"default:true"`          // Whether this term is available
	SortOrder          int            `json:"sort_order" gorm:"default:0"`             // Display order
	RecommendedTag     string         `json:"recommended_tag"`                         // Tag like "Most Popular", "Best Value"
	MinDiscountPercent float64        `json:"min_discount_percent" gorm:"default:0"`   // Minimum allowed discount
	MaxDiscountPercent float64        `json:"max_discount_percent" gorm:"default:100"` // Maximum allowed discount
	CreatedAt          time.Time      `json:"created_at"`
	UpdatedAt          time.Time      `json:"updated_at"`
	DeletedAt          gorm.DeletedAt `json:"deleted_at" gorm:"index"`
}

// Request/Response DTOs for discount management

// CreateGlobalDiscountConfigRequest creates a new discount template
type CreateGlobalDiscountConfigRequest struct {
	Name              string  `json:"name" binding:"required"`
	Description       string  `json:"description"`
	YearlyDiscount    float64 `json:"yearly_discount" binding:"min=0,max=100"`
	TwoYearDiscount   float64 `json:"two_year_discount" binding:"min=0,max=100"`
	ThreeYearDiscount float64 `json:"three_year_discount" binding:"min=0,max=100"`
	IsDefault         bool    `json:"is_default"`
}

// UpdateGlobalDiscountConfigRequest updates an existing discount template
type UpdateGlobalDiscountConfigRequest struct {
	Name              *string  `json:"name"`
	Description       *string  `json:"description"`
	YearlyDiscount    *float64 `json:"yearly_discount" binding:"omitempty,min=0,max=100"`
	TwoYearDiscount   *float64 `json:"two_year_discount" binding:"omitempty,min=0,max=100"`
	ThreeYearDiscount *float64 `json:"three_year_discount" binding:"omitempty,min=0,max=100"`
	IsDefault         *bool    `json:"is_default"`
	IsActive          *bool    `json:"is_active"`
}

// CreatePlanDiscountOverrideRequest creates a plan-specific discount override
type CreatePlanDiscountOverrideRequest struct {
	PlanID            uuid.UUID  `json:"plan_id" binding:"required"`
	YearlyDiscount    *float64   `json:"yearly_discount" binding:"omitempty,min=0,max=100"`
	TwoYearDiscount   *float64   `json:"two_year_discount" binding:"omitempty,min=0,max=100"`
	ThreeYearDiscount *float64   `json:"three_year_discount" binding:"omitempty,min=0,max=100"`
	EffectiveFrom     time.Time  `json:"effective_from"`
	EffectiveTo       *time.Time `json:"effective_to"`
	Reason            string     `json:"reason"`
}

// UpdateBillingTermConfigRequest updates billing term configuration
type UpdateBillingTermConfigRequest struct {
	TermName           *string  `json:"term_name"`
	PaymentSchedule    *string  `json:"payment_schedule"`
	IsEnabled          *bool    `json:"is_enabled"`
	SortOrder          *int     `json:"sort_order"`
	RecommendedTag     *string  `json:"recommended_tag"`
	MinDiscountPercent *float64 `json:"min_discount_percent" binding:"omitempty,min=0,max=100"`
	MaxDiscountPercent *float64 `json:"max_discount_percent" binding:"omitempty,min=0,max=100"`
}

// BulkDiscountUpdateRequest for applying discounts to multiple plans
type BulkDiscountUpdateRequest struct {
	PlanIDs           []uuid.UUID `json:"plan_ids" binding:"required"`
	YearlyDiscount    *float64    `json:"yearly_discount" binding:"omitempty,min=0,max=100"`
	TwoYearDiscount   *float64    `json:"two_year_discount" binding:"omitempty,min=0,max=100"`
	ThreeYearDiscount *float64    `json:"three_year_discount" binding:"omitempty,min=0,max=100"`
	Reason            string      `json:"reason"`
	ApplyImmediately  bool        `json:"apply_immediately"`
}

// DiscountAnalyticsResponse provides analytics on discount effectiveness
type DiscountAnalyticsResponse struct {
	TotalPlans               int                   `json:"total_plans"`
	PlansWithDiscounts       int                   `json:"plans_with_discounts"`
	AverageYearlyDiscount    float64               `json:"average_yearly_discount"`
	AverageTwoYearDiscount   float64               `json:"average_two_year_discount"`
	AverageThreeYearDiscount float64               `json:"average_three_year_discount"`
	DiscountDistribution     map[string]int        `json:"discount_distribution"`
	RevenueImpact            DiscountRevenueImpact `json:"revenue_impact"`
}

// DiscountRevenueImpact shows the financial impact of discounts
type DiscountRevenueImpact struct {
	MonthlyRevenue           float64 `json:"monthly_revenue"`
	YearlyRevenue            float64 `json:"yearly_revenue"`
	TwoYearRevenue           float64 `json:"two_year_revenue"`
	ThreeYearRevenue         float64 `json:"three_year_revenue"`
	TotalSavingsOffered      float64 `json:"total_savings_offered"`
	EstimatedConversionBoost float64 `json:"estimated_conversion_boost"`
}
