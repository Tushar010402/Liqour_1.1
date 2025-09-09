package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// PricingPlan represents a pricing plan in the system
type PricingPlan struct {
	ID                uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Name              string         `json:"name" gorm:"not null;unique" binding:"required"`
	DisplayName       string         `json:"display_name" gorm:"not null"`
	Description       string         `json:"description"`
	Price             float64        `json:"price" gorm:"not null" binding:"required,min=0"`
	Currency          string         `json:"currency" gorm:"not null;default:'INR'"`
	BillingCycle      string         `json:"billing_cycle" gorm:"not null;default:'monthly'"` // monthly, yearly
	TrialDays         int            `json:"trial_days" gorm:"default:60"`                    // 2 months = 60 days
	MaxLocations      int            `json:"max_locations" gorm:"default:1"`                  // -1 for unlimited
	MaxUsers          int            `json:"max_users" gorm:"default:10"`                     // -1 for unlimited
	MaxProducts       int            `json:"max_products" gorm:"default:1000"`                // -1 for unlimited
	Features          []string       `json:"features" gorm:"serializer:json"`
	AIFeatures        []string       `json:"ai_features" gorm:"serializer:json"`
	Popular           bool           `json:"popular" gorm:"default:false"`
	Enterprise        bool           `json:"enterprise" gorm:"default:false"`
	Active            bool           `json:"active" gorm:"default:true"`
	SortOrder         int            `json:"sort_order" gorm:"default:0"`
	RazorpayPlanID    string         `json:"razorpay_plan_id"`
	YearlyDiscount    float64        `json:"yearly_discount" gorm:"default:20"` // 20% discount for yearly
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
	DeletedAt         gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	Subscriptions []Subscription `json:"subscriptions,omitempty" gorm:"foreignKey:PlanID"`
}

// Subscription represents a tenant's subscription to a pricing plan
type Subscription struct {
	ID                   uuid.UUID       `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	TenantID             uuid.UUID       `json:"tenant_id" gorm:"type:uuid;not null;index"`
	PlanID               uuid.UUID       `json:"plan_id" gorm:"type:uuid;not null"`
	Status               string          `json:"status" gorm:"not null;default:'trial'"` // trial, active, suspended, cancelled, expired
	CurrentPeriodStart   time.Time       `json:"current_period_start"`
	CurrentPeriodEnd     time.Time       `json:"current_period_end"`
	TrialStart           *time.Time      `json:"trial_start"`
	TrialEnd             *time.Time      `json:"trial_end"`
	CancelledAt          *time.Time      `json:"cancelled_at"`
	EndedAt              *time.Time      `json:"ended_at"`
	RazorpayCustomerID   string          `json:"razorpay_customer_id"`
	RazorpaySubscriptionID string        `json:"razorpay_subscription_id"`
	AutoRenew            bool            `json:"auto_renew" gorm:"default:true"`
	BillingCycle         string          `json:"billing_cycle" gorm:"not null;default:'monthly'"`
	Amount               float64         `json:"amount" gorm:"not null"`
	Currency             string          `json:"currency" gorm:"not null;default:'INR'"`
	NextBillingDate     *time.Time      `json:"next_billing_date"`
	CreatedAt            time.Time       `json:"created_at"`
	UpdatedAt            time.Time       `json:"updated_at"`
	DeletedAt            gorm.DeletedAt  `json:"deleted_at" gorm:"index"`

	// Relations
	Plan         PricingPlan    `json:"plan,omitempty" gorm:"foreignKey:PlanID"`
	Payments     []Payment      `json:"payments,omitempty" gorm:"foreignKey:SubscriptionID"`
	Invoices     []Invoice      `json:"invoices,omitempty" gorm:"foreignKey:SubscriptionID"`
	UsageRecords []UsageRecord  `json:"usage_records,omitempty" gorm:"foreignKey:SubscriptionID"`
}

// Payment represents a payment transaction
type Payment struct {
	ID                   uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	SubscriptionID       uuid.UUID      `json:"subscription_id" gorm:"type:uuid;not null"`
	InvoiceID            *uuid.UUID     `json:"invoice_id" gorm:"type:uuid"`
	Amount               float64        `json:"amount" gorm:"not null"`
	Currency             string         `json:"currency" gorm:"not null;default:'INR'"`
	Status               string         `json:"status" gorm:"not null"` // pending, processing, succeeded, failed, cancelled, refunded
	PaymentMethod        string         `json:"payment_method"`         // card, netbanking, wallet, upi
	RazorpayPaymentID    string         `json:"razorpay_payment_id"`
	RazorpayOrderID      string         `json:"razorpay_order_id"`
	RazorpaySignature    string         `json:"razorpay_signature"`
	FailureReason        string         `json:"failure_reason"`
	ProcessedAt          *time.Time     `json:"processed_at"`
	RefundedAt           *time.Time     `json:"refunded_at"`
	RefundAmount         float64        `json:"refund_amount" gorm:"default:0"`
	RefundReason         string         `json:"refund_reason"`
	Description          string         `json:"description"`
	CreatedAt            time.Time      `json:"created_at"`
	UpdatedAt            time.Time      `json:"updated_at"`
	DeletedAt            gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	Subscription Subscription `json:"subscription,omitempty" gorm:"foreignKey:SubscriptionID"`
	Invoice      *Invoice     `json:"invoice,omitempty" gorm:"foreignKey:InvoiceID"`
}

// Invoice represents an invoice for a subscription
type Invoice struct {
	ID              uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	SubscriptionID  uuid.UUID      `json:"subscription_id" gorm:"type:uuid;not null"`
	InvoiceNumber   string         `json:"invoice_number" gorm:"unique;not null"`
	Status          string         `json:"status" gorm:"not null;default:'draft'"` // draft, open, paid, void, uncollectible
	Amount          float64        `json:"amount" gorm:"not null"`
	Currency        string         `json:"currency" gorm:"not null;default:'INR'"`
	Tax             float64        `json:"tax" gorm:"default:0"`
	Discount        float64        `json:"discount" gorm:"default:0"`
	Total           float64        `json:"total" gorm:"not null"`
	PeriodStart     time.Time      `json:"period_start"`
	PeriodEnd       time.Time      `json:"period_end"`
	DueDate         time.Time      `json:"due_date"`
	PaidAt          *time.Time     `json:"paid_at"`
	VoidedAt        *time.Time     `json:"voided_at"`
	BillingName     string         `json:"billing_name"`
	BillingEmail    string         `json:"billing_email"`
	BillingAddress  string         `json:"billing_address"`
	Notes           string         `json:"notes"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	Subscription Subscription `json:"subscription,omitempty" gorm:"foreignKey:SubscriptionID"`
	Payments     []Payment    `json:"payments,omitempty" gorm:"foreignKey:InvoiceID"`
}

// UsageRecord tracks usage metrics for each subscription
type UsageRecord struct {
	ID             uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	SubscriptionID uuid.UUID      `json:"subscription_id" gorm:"type:uuid;not null"`
	TenantID       uuid.UUID      `json:"tenant_id" gorm:"type:uuid;not null"`
	RecordDate     time.Time      `json:"record_date" gorm:"not null;index"`
	Locations      int            `json:"locations" gorm:"default:0"`
	Users          int            `json:"users" gorm:"default:0"`
	Products       int            `json:"products" gorm:"default:0"`
	Sales          int            `json:"sales" gorm:"default:0"`
	APIRequests    int            `json:"api_requests" gorm:"default:0"`
	StorageUsed    int64          `json:"storage_used" gorm:"default:0"` // in bytes
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	Subscription Subscription `json:"subscription,omitempty" gorm:"foreignKey:SubscriptionID"`
}

// WebhookEvent represents incoming webhook events
type WebhookEvent struct {
	ID           uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Provider     string         `json:"provider" gorm:"not null"` // razorpay, stripe, etc.
	EventType    string         `json:"event_type" gorm:"not null"`
	EventID      string         `json:"event_id" gorm:"unique"`
	Status       string         `json:"status" gorm:"not null;default:'pending'"` // pending, processed, failed
	Payload      string         `json:"payload" gorm:"type:text"`
	ProcessedAt  *time.Time     `json:"processed_at"`
	ErrorMessage string         `json:"error_message"`
	Retries      int            `json:"retries" gorm:"default:0"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `json:"deleted_at" gorm:"index"`
}

// AdminUser represents super admin users
type AdminUser struct {
	ID          uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Email       string         `json:"email" gorm:"unique;not null"`
	Name        string         `json:"name" gorm:"not null"`
	Role        string         `json:"role" gorm:"not null;default:'admin'"` // admin, super_admin
	Active      bool           `json:"active" gorm:"default:true"`
	LastLoginAt *time.Time     `json:"last_login_at"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	AuditLogs []AuditLog `json:"audit_logs,omitempty" gorm:"foreignKey:AdminUserID"`
}

// AuditLog represents audit trail for admin actions
type AuditLog struct {
	ID           uuid.UUID      `json:"id" gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	AdminUserID  *uuid.UUID     `json:"admin_user_id" gorm:"type:uuid"`
	TenantID     *uuid.UUID     `json:"tenant_id" gorm:"type:uuid"`
	Action       string         `json:"action" gorm:"not null"`        // create, update, delete, etc.
	Resource     string         `json:"resource" gorm:"not null"`      // plan, subscription, payment, etc.
	ResourceID   string         `json:"resource_id"`                   // ID of the affected resource
	OldValues    string         `json:"old_values" gorm:"type:text"`   // JSON of old values
	NewValues    string         `json:"new_values" gorm:"type:text"`   // JSON of new values
	IPAddress    string         `json:"ip_address"`
	UserAgent    string         `json:"user_agent"`
	CreatedAt    time.Time      `json:"created_at"`
	DeletedAt    gorm.DeletedAt `json:"deleted_at" gorm:"index"`

	// Relations
	AdminUser *AdminUser `json:"admin_user,omitempty" gorm:"foreignKey:AdminUserID"`
}

// Request/Response DTOs

type CreateSubscriptionRequest struct {
	TenantID     uuid.UUID `json:"tenant_id" binding:"required"`
	PlanID       uuid.UUID `json:"plan_id" binding:"required"`
	BillingCycle string    `json:"billing_cycle" binding:"required,oneof=monthly yearly"`
	AutoRenew    bool      `json:"auto_renew"`
}

type UpdateSubscriptionRequest struct {
	AutoRenew *bool `json:"auto_renew"`
	Status    string `json:"status,omitempty" binding:"omitempty,oneof=active suspended cancelled"`
}

type CreatePlanRequest struct {
	Name           string   `json:"name" binding:"required"`
	DisplayName    string   `json:"display_name" binding:"required"`
	Description    string   `json:"description"`
	Price          float64  `json:"price" binding:"required,min=0"`
	Currency       string   `json:"currency"`
	BillingCycle   string   `json:"billing_cycle" binding:"required,oneof=monthly yearly"`
	TrialDays      int      `json:"trial_days"`
	MaxLocations   int      `json:"max_locations"`
	MaxUsers       int      `json:"max_users"`
	MaxProducts    int      `json:"max_products"`
	Features       []string `json:"features"`
	AIFeatures     []string `json:"ai_features"`
	Popular        bool     `json:"popular"`
	Enterprise     bool     `json:"enterprise"`
	Active         bool     `json:"active"`
	SortOrder      int      `json:"sort_order"`
	YearlyDiscount float64  `json:"yearly_discount"`
}

type CreatePaymentRequest struct {
	SubscriptionID uuid.UUID `json:"subscription_id" binding:"required"`
	Amount         float64   `json:"amount" binding:"required,min=0"`
	Currency       string    `json:"currency"`
	PaymentMethod  string    `json:"payment_method"`
	Description    string    `json:"description"`
}

type RazorpayWebhookPayload struct {
	Event   string `json:"event"`
	Payload struct {
		Payment struct {
			ID     string  `json:"id"`
			Amount int64   `json:"amount"` // Amount in paise
			Status string  `json:"status"`
			Method string  `json:"method"`
		} `json:"payment"`
		Subscription struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		} `json:"subscription"`
	} `json:"payload"`
}

type SubscriptionResponse struct {
	ID                 uuid.UUID      `json:"id"`
	TenantID           uuid.UUID      `json:"tenant_id"`
	Plan               PricingPlan    `json:"plan"`
	Status             string         `json:"status"`
	CurrentPeriodStart time.Time      `json:"current_period_start"`
	CurrentPeriodEnd   time.Time      `json:"current_period_end"`
	TrialStart         *time.Time     `json:"trial_start"`
	TrialEnd           *time.Time     `json:"trial_end"`
	BillingCycle       string         `json:"billing_cycle"`
	Amount             float64        `json:"amount"`
	Currency           string         `json:"currency"`
	NextBillingDate    *time.Time     `json:"next_billing_date"`
	Usage              *UsageRecord   `json:"usage,omitempty"`
	CreatedAt          time.Time      `json:"created_at"`
	UpdatedAt          time.Time      `json:"updated_at"`
}

type DashboardMetrics struct {
	TotalSubscriptions    int                    `json:"total_subscriptions"`
	ActiveSubscriptions   int                    `json:"active_subscriptions"`
	TrialSubscriptions    int                    `json:"trial_subscriptions"`
	TotalRevenue          float64                `json:"total_revenue"`
	MonthlyRevenue        float64                `json:"monthly_revenue"`
	TotalTenants          int                    `json:"total_tenants"`
	NewTenants            int                    `json:"new_tenants"`
	ChurnRate             float64                `json:"churn_rate"`
	PlanDistribution      map[string]int         `json:"plan_distribution"`
	RevenueByPlan         map[string]float64     `json:"revenue_by_plan"`
	MonthlyGrowth         map[string]float64     `json:"monthly_growth"`
}