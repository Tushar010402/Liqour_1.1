package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/datatypes"
)

// ========================================
// Finance Matrix Constants
// ========================================

// Alert Types
const (
	AlertTypeCashShortage       = "cash_shortage"
	AlertTypeInventoryShrinkage = "inventory_shrinkage"
	AlertTypeExcessiveDiscount  = "excessive_discount"
	AlertTypeVoidAbuse          = "void_abuse"
	AlertTypeReturnAbuse        = "return_abuse"
	AlertTypeLowStock           = "low_stock"
	AlertTypeOverdueCollection  = "overdue_collection"
	AlertTypeBudgetExceeded     = "budget_exceeded"
	AlertTypeAnomaly            = "anomaly"
)

// Alert Severities
const (
	SeverityInfo     = "info"
	SeverityWarning  = "warning"
	SeverityCritical = "critical"
)

// Finance Alert Statuses (using prefix to avoid collision with detection.go AlertStatus)
const (
	FinanceAlertStatusUnread       = "unread"
	FinanceAlertStatusRead         = "read"
	FinanceAlertStatusAcknowledged = "acknowledged"
	FinanceAlertStatusResolved     = "resolved"
	FinanceAlertStatusDismissed    = "dismissed"
)

// Credit Aging Buckets
const (
	AgingBucket0To30  = "0-30"
	AgingBucket31To60 = "31-60"
	AgingBucket61To90 = "61-90"
	AgingBucket90Plus = "90+"
)

// Credit Sale Statuses
const (
	CreditStatusOutstanding = "outstanding"
	CreditStatusPartial     = "partial"
	CreditStatusPaid        = "paid"
	CreditStatusWrittenOff  = "written_off"
	CreditStatusDisputed    = "disputed"
)

// Shrinkage Types
const (
	ShrinkageTypeTheft         = "theft"
	ShrinkageTypeDamage        = "damage"
	ShrinkageTypeSpoilage      = "spoilage"
	ShrinkageTypeCountingError = "counting_error"
	ShrinkageTypeReceivingErr  = "receiving_error"
	ShrinkageTypeUnknown       = "unknown"
)

// Budget Statuses
const (
	BudgetStatusActive    = "active"
	BudgetStatusClosed    = "closed"
	BudgetStatusExceeded  = "exceeded"
	BudgetStatusCancelled = "cancelled"
)

// ========================================
// Finance Metrics Daily
// ========================================

// FinanceMetricsDaily stores pre-computed daily metrics for dashboard
type FinanceMetricsDaily struct {
	ID       uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID   *uuid.UUID `json:"shop_id" gorm:"type:uuid;index"` // NULL for tenant-wide aggregates

	MetricDate time.Time `json:"metric_date" gorm:"type:date;not null"`

	// Sales Metrics
	TotalSales          float64 `json:"total_sales" gorm:"default:0"`
	CashSales           float64 `json:"cash_sales" gorm:"default:0"`
	CardSales           float64 `json:"card_sales" gorm:"default:0"`
	UPISales            float64 `json:"upi_sales" gorm:"default:0"`
	CreditSales         float64 `json:"credit_sales" gorm:"default:0"`
	SalesCount          int     `json:"sales_count" gorm:"default:0"`
	ItemsSold           int     `json:"items_sold" gorm:"default:0"`
	AvgTransactionValue float64 `json:"avg_transaction_value" gorm:"default:0"`
	TransactionCount    int     `json:"transaction_count" gorm:"default:0"`

	// Payment amount aliases for compatibility
	CashAmount   float64 `json:"cash_amount" gorm:"default:0"`
	CardAmount   float64 `json:"card_amount" gorm:"default:0"`
	UPIAmount    float64 `json:"upi_amount" gorm:"default:0"`
	CreditAmount float64 `json:"credit_amount" gorm:"default:0"`

	// Comparison
	PrevPeriodSales     float64 `json:"prev_period_sales" gorm:"default:0"`
	SalesGrowthAmount   float64 `json:"sales_growth_amount" gorm:"default:0"`
	SalesGrowthPercent  float64 `json:"sales_growth_percent" gorm:"default:0"`

	// Cash Flow
	CashInflow   float64 `json:"cash_inflow" gorm:"default:0"`
	CashOutflow  float64 `json:"cash_outflow" gorm:"default:0"`
	NetCashFlow  float64 `json:"net_cash_flow" gorm:"default:0"`
	OpeningCash  float64 `json:"opening_cash" gorm:"default:0"`
	ClosingCash  float64 `json:"closing_cash" gorm:"default:0"`
	CashVariance float64 `json:"cash_variance" gorm:"default:0"`

	// Expenses
	TotalExpenses float64 `json:"total_expenses" gorm:"default:0"`

	// Profit & Margins
	GrossProfit float64 `json:"gross_profit" gorm:"default:0"`
	GrossMargin float64 `json:"gross_margin" gorm:"default:0"`

	// Inventory
	InventoryValue      float64 `json:"inventory_value" gorm:"default:0"`
	InventoryItemsCount int     `json:"inventory_items_count" gorm:"default:0"`

	// Returns & Discounts
	TotalReturns   float64 `json:"total_returns" gorm:"default:0"`
	ReturnsCount   int     `json:"returns_count" gorm:"default:0"`
	TotalDiscounts float64 `json:"total_discounts" gorm:"default:0"`
	DiscountsCount int     `json:"discounts_count" gorm:"default:0"`
	RefundAmount   float64 `json:"refund_amount" gorm:"default:0"`
	DiscountAmount float64 `json:"discount_amount" gorm:"default:0"`

	// Computation Tracking
	ComputedAt            time.Time `json:"computed_at" gorm:"default:CURRENT_TIMESTAMP"`
	ComputationDurationMs int       `json:"computation_duration_ms"`

	CreatedAt time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt time.Time `json:"updated_at" gorm:"autoUpdateTime"`

	// Relationships
	Tenant *Tenant `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`
	Shop   *Shop   `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
}

func (FinanceMetricsDaily) TableName() string {
	return "finance_metrics_daily"
}

// ========================================
// Credit Sales Aging
// ========================================

// CreditSalesAging tracks credit sales receivables with aging buckets
type CreditSalesAging struct {
	TenantModel
	ShopID uuid.UUID `json:"shop_id" gorm:"type:uuid;not null;index"`
	Shop   *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	// Customer Info
	CustomerName    string `json:"customer_name"`
	CustomerPhone   string `json:"customer_phone" gorm:"index"`
	CustomerAddress string `json:"customer_address"`

	// Sale Reference
	DailySalesRecordID *uuid.UUID        `json:"daily_sales_record_id" gorm:"type:uuid"`
	DailySalesRecord   *DailySalesRecord `json:"daily_sales_record,omitempty" gorm:"foreignKey:DailySalesRecordID"`
	SaleID             *uuid.UUID        `json:"sale_id" gorm:"type:uuid"`
	Sale               *Sale             `json:"sale,omitempty" gorm:"foreignKey:SaleID"`

	// Amount Details
	OriginalAmount    float64 `json:"original_amount" gorm:"not null"`
	PaidAmount        float64 `json:"paid_amount" gorm:"default:0"`
	OutstandingAmount float64 `json:"outstanding_amount" gorm:"not null;index"`

	// Dates
	CreditDate      time.Time  `json:"credit_date" gorm:"type:date;not null"`
	DueDate         *time.Time `json:"due_date" gorm:"type:date"`
	LastPaymentDate *time.Time `json:"last_payment_date" gorm:"type:date"`
	LastReminderDate *time.Time `json:"last_reminder_date" gorm:"type:date"`

	// Aging
	DaysOutstanding int    `json:"days_outstanding" gorm:"default:0"`
	AgingBucket     string `json:"aging_bucket" gorm:"default:'0-30';index"` // '0-30', '31-60', '61-90', '90+'

	// Status
	Status   string `json:"status" gorm:"default:'outstanding';index"` // outstanding, partial, paid, written_off, disputed
	Priority string `json:"priority" gorm:"default:'normal'"`          // low, normal, high, critical

	// Notes
	Notes             string     `json:"notes"`
	LastFollowUpNotes string     `json:"last_follow_up_notes"`
	NextFollowUpDate  *time.Time `json:"next_follow_up_date" gorm:"type:date"`

	// Write-off
	WrittenOffAmount float64    `json:"written_off_amount" gorm:"default:0"`
	WrittenOffAt     *time.Time `json:"written_off_at"`
	WrittenOffByID   *uuid.UUID `json:"written_off_by" gorm:"type:uuid"`
	WrittenOffBy     *User      `json:"written_off_by_user,omitempty" gorm:"foreignKey:WrittenOffByID"`
	WriteOffReason   string     `json:"write_off_reason"`

	// Audit
	CreatedByID uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

func (CreditSalesAging) TableName() string {
	return "credit_sales_aging"
}

// ========================================
// Expense Budget
// ========================================

// ExpenseBudget tracks budget vs actual for expense categories
type ExpenseBudget struct {
	TenantModel
	ShopID            *uuid.UUID       `json:"shop_id" gorm:"type:uuid;index"`
	Shop              *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	ExpenseCategoryID *uuid.UUID       `json:"expense_category_id" gorm:"type:uuid;index"`
	ExpenseCategory   *ExpenseCategory `json:"expense_category,omitempty" gorm:"foreignKey:ExpenseCategoryID"`

	// Budget Period
	BudgetYear  int `json:"budget_year" gorm:"not null;index"`
	BudgetMonth int `json:"budget_month" gorm:"not null;index"` // 0 for annual, 1-12 for monthly

	// Amounts
	BudgetedAmount  float64 `json:"budgeted_amount" gorm:"not null;default:0"`
	ActualAmount    float64 `json:"actual_amount" gorm:"default:0"`
	VarianceAmount  float64 `json:"variance_amount" gorm:"default:0"`
	VariancePercent float64 `json:"variance_percent" gorm:"default:0"`

	// Thresholds
	WarningThresholdPercent  float64 `json:"warning_threshold_percent" gorm:"default:80"`
	CriticalThresholdPercent float64 `json:"critical_threshold_percent" gorm:"default:100"`

	// Status
	Status string `json:"status" gorm:"default:'active'"` // active, closed, exceeded, cancelled

	// Notes
	Notes            string `json:"notes"`
	AdjustmentReason string `json:"adjustment_reason"`

	// Audit
	CreatedByID  uuid.UUID  `json:"created_by" gorm:"type:uuid;not null"`
	CreatedBy    *User      `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
	ApprovedByID *uuid.UUID `json:"approved_by" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by_user,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedAt   *time.Time `json:"approved_at"`
}

func (ExpenseBudget) TableName() string {
	return "expense_budgets"
}

// ========================================
// Shrinkage Record
// ========================================

// ShrinkageRecord tracks inventory shrinkage from verifications
type ShrinkageRecord struct {
	TenantModel
	ShopID              uuid.UUID          `json:"shop_id" gorm:"type:uuid;not null;index"`
	Shop                *Shop              `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	ProductID           uuid.UUID          `json:"product_id" gorm:"type:uuid;not null;index"`
	Product             *Product           `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	StockVerificationID *uuid.UUID         `json:"stock_verification_id" gorm:"type:uuid;index"`
	StockVerification   *StockVerification `json:"stock_verification,omitempty" gorm:"foreignKey:StockVerificationID"`

	// Verification Details
	VerificationDate time.Time `json:"verification_date" gorm:"type:date;not null;index"`

	// Quantities
	SystemQuantity   int `json:"system_quantity" gorm:"not null"`
	PhysicalQuantity int `json:"physical_quantity" gorm:"not null"`
	VarianceQuantity int `json:"variance_quantity" gorm:"not null"` // system - physical (negative = shortage)

	// Values
	UnitCost      float64 `json:"unit_cost" gorm:"not null"`
	UnitPrice     float64 `json:"unit_price"`
	VarianceValue float64 `json:"variance_value" gorm:"not null"` // variance_quantity * unit_cost
	RetailLoss    float64 `json:"retail_loss"`                    // variance_quantity * unit_price

	// Shrinkage Rate
	ShrinkageRate float64 `json:"shrinkage_rate"` // (variance / system) * 100

	// Classification
	ShrinkageType string `json:"shrinkage_type" gorm:"default:'unknown'"` // theft, damage, spoilage, counting_error, receiving_error, unknown
	Severity      string `json:"severity" gorm:"default:'low';index"`      // low, medium, high, critical
	RiskScore     int    `json:"risk_score" gorm:"default:0;index"`        // 0-100

	// Analysis
	ProbableCauses       datatypes.JSON `json:"probable_causes"`        // [{cause, probability}]
	SimilarPatternCount  int            `json:"similar_pattern_count" gorm:"default:0"`
	IsRecurring          bool           `json:"is_recurring" gorm:"default:false"`

	// Investigation
	InvestigationID *uuid.UUID    `json:"investigation_id" gorm:"type:uuid;index"`
	Investigation   *Investigation `json:"investigation,omitempty" gorm:"foreignKey:InvestigationID"`

	// Resolution
	Status          string     `json:"status" gorm:"default:'pending'"` // pending, investigating, resolved, written_off
	Reason          string     `json:"reason"`
	ResolutionNotes string     `json:"resolution_notes"`
	ResolvedByID    *uuid.UUID `json:"resolved_by" gorm:"type:uuid"`
	ResolvedBy      *User      `json:"resolved_by_user,omitempty" gorm:"foreignKey:ResolvedByID"`
	ResolvedAt      *time.Time `json:"resolved_at"`

	// Approval
	ApprovedByID *uuid.UUID `json:"approved_by" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by_user,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedAt   *time.Time `json:"approved_at"`

	// Audit
	CreatedByID uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

func (ShrinkageRecord) TableName() string {
	return "shrinkage_records"
}

// ========================================
// Finance Alert
// ========================================

// FinanceAlert represents proactive alerts for managers
type FinanceAlert struct {
	ID       uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID   *uuid.UUID `json:"shop_id" gorm:"type:uuid;index"`
	UserID   *uuid.UUID `json:"user_id" gorm:"type:uuid;index"` // Target user for the alert

	// Alert Details
	AlertType string `json:"alert_type" gorm:"not null;index"` // cash_shortage, low_stock, etc.
	Severity  string `json:"severity" gorm:"not null;index"`   // info, warning, critical
	Category  string `json:"category"`                          // finance, inventory, sales, audit

	// Content
	Title       string `json:"title" gorm:"not null"`
	Message     string `json:"message" gorm:"not null"`
	ActionURL   string `json:"action_url"`
	ActionLabel string `json:"action_label"`

	// Related Entity
	RelatedType string     `json:"related_type"` // cash_holding, stock, credit_sale, expense, etc.
	RelatedID   *uuid.UUID `json:"related_id" gorm:"type:uuid"`

	// Metrics
	MetricValue     float64 `json:"metric_value"`
	MetricThreshold float64 `json:"metric_threshold"`
	MetricUnit      string  `json:"metric_unit"` // %, Rs, units

	// Status
	Status           string     `json:"status" gorm:"default:'unread';index"` // unread, read, acknowledged, resolved, dismissed
	ReadAt           *time.Time `json:"read_at"`
	AcknowledgedAt   *time.Time `json:"acknowledged_at"`
	AcknowledgedByID *uuid.UUID `json:"acknowledged_by" gorm:"type:uuid"`
	AcknowledgedBy   *User      `json:"acknowledged_by_user,omitempty" gorm:"foreignKey:AcknowledgedByID"`
	ResolvedAt       *time.Time `json:"resolved_at"`
	ResolvedByID     *uuid.UUID `json:"resolved_by" gorm:"type:uuid"`
	ResolvedBy       *User      `json:"resolved_by_user,omitempty" gorm:"foreignKey:ResolvedByID"`
	ResolutionNotes  string     `json:"resolution_notes"`

	// Auto-dismiss
	ExpiresAt    *time.Time `json:"expires_at"`
	IsPersistent bool       `json:"is_persistent" gorm:"default:false"`

	// Notifications
	NotificationsSent datatypes.JSON `json:"notifications_sent"` // [{channel, sent_at, status}]

	CreatedAt time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt time.Time `json:"updated_at" gorm:"autoUpdateTime"`

	// Relationships
	Tenant *Tenant `json:"tenant,omitempty" gorm:"foreignKey:TenantID"`
	Shop   *Shop   `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	User   *User   `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

func (FinanceAlert) TableName() string {
	return "finance_alerts"
}

// ========================================
// Request/Response DTOs
// ========================================

// DashboardSummaryResponse represents the finance matrix dashboard data
type DashboardSummaryResponse struct {
	// Period
	PeriodStart time.Time `json:"period_start"`
	PeriodEnd   time.Time `json:"period_end"`
	PeriodLabel string    `json:"period_label"` // "Today", "This Week", "This Month"

	// Sales Summary
	Sales struct {
		TotalSales          float64 `json:"total_sales"`
		CashSales           float64 `json:"cash_sales"`
		CardSales           float64 `json:"card_sales"`
		UPISales            float64 `json:"upi_sales"`
		CreditSales         float64 `json:"credit_sales"`
		SalesCount          int     `json:"sales_count"`
		ItemsSold           int     `json:"items_sold"`
		AvgTransactionValue float64 `json:"avg_transaction_value"`
		GrowthPercent       float64 `json:"growth_percent"`
		GrowthAmount        float64 `json:"growth_amount"`
	} `json:"sales"`

	// Cash Flow Summary
	CashFlow struct {
		TotalCashInflow    float64           `json:"total_cash_inflow"`
		TotalCashOutflow   float64           `json:"total_cash_outflow"`
		NetCashFlow        float64           `json:"net_cash_flow"`
		PendingCollections int               `json:"pending_collections"`
		PendingAmount      float64           `json:"pending_amount"`
		TeamCashHoldings   []UserCashHolding `json:"team_cash_holdings"`
	} `json:"cash_flow"`

	// Inventory Summary
	Inventory struct {
		TotalValue         float64 `json:"total_value"`
		ItemsCount         int     `json:"items_count"`
		LowStockItems      int     `json:"low_stock_items"`
		ShrinkageValue     float64 `json:"shrinkage_value"`
		ShrinkagePercent   float64 `json:"shrinkage_percent"`
		SlowMovingItems    int     `json:"slow_moving_items"`
		DeadStockItems     int     `json:"dead_stock_items"`
	} `json:"inventory"`

	// Expense Summary
	Expenses struct {
		TotalExpenses     float64               `json:"total_expenses"`
		TopCategories     []ExpenseCategoryStat `json:"top_categories"`
		BudgetUtilization float64               `json:"budget_utilization"`
	} `json:"expenses"`

	// Credit Summary
	Credit struct {
		TotalOutstanding float64           `json:"total_outstanding"`
		CustomerCount    int               `json:"customer_count"`
		OverdueAmount    float64           `json:"overdue_amount"`
		AgingBuckets     []AgingBucketStat `json:"aging_buckets"`
	} `json:"credit"`

	// Alerts Summary
	Alerts struct {
		UnreadCount   int            `json:"unread_count"`
		CriticalCount int            `json:"critical_count"`
		RecentAlerts  []FinanceAlert `json:"recent_alerts"`
	} `json:"alerts"`

	// Extended analytics fields
	CashHoldings           *CashHoldingsSummary  `json:"cash_holdings,omitempty"`
	CreditAging            *CreditAgingSummary   `json:"credit_aging,omitempty"`
	ExpensesByCategory     []ExpenseCategoryStat `json:"expenses_by_category,omitempty"`
	DailySalesTrend        []DailySalesStat      `json:"daily_sales_trend,omitempty"`
	PaymentMethodBreakdown map[string]float64    `json:"payment_method_breakdown,omitempty"`
	TopProducts            []TopProductStat      `json:"top_products,omitempty"`
	Insights               []FinanceInsight      `json:"insights,omitempty"`

	// Generated timestamp
	GeneratedAt time.Time `json:"generated_at"`
}

// CashHoldingsSummary represents aggregated cash holdings
type CashHoldingsSummary struct {
	TotalCashOnHand     float64           `json:"total_cash_on_hand"`
	TotalUserHoldings   float64           `json:"total_user_holdings"`
	PendingCollections  float64           `json:"pending_collections"`
	PendingDeposits     float64           `json:"pending_deposits"`
	UserBreakdown       []UserCashHolding `json:"user_breakdown,omitempty"`
}

// CreditAgingSummary represents credit aging breakdown
type CreditAgingSummary struct {
	TotalOutstanding float64           `json:"total_outstanding"`
	Current          float64           `json:"current"`
	Days30           float64           `json:"days_30"`
	Days60           float64           `json:"days_60"`
	Days90           float64           `json:"days_90"`
	Over90           float64           `json:"over_90"`
	CustomerCount    int               `json:"customer_count"`
	AgingBuckets     []AgingBucketStat `json:"aging_buckets,omitempty"`
}

// UserCashHolding represents cash holding for a user
type UserCashHolding struct {
	UserID         uuid.UUID `json:"user_id"`
	UserName       string    `json:"user_name"`
	UserRole       string    `json:"user_role"`
	CurrentBalance float64   `json:"current_balance"`
	ShopID         *uuid.UUID `json:"shop_id,omitempty"`
	ShopName       string    `json:"shop_name,omitempty"`
}

// ExpenseCategoryStat represents expense stats by category
type ExpenseCategoryStat struct {
	CategoryID   uuid.UUID `json:"category_id"`
	CategoryName string    `json:"category_name"`
	TotalAmount  float64   `json:"total_amount"`
	Percentage   float64   `json:"percentage"`
	TrendPercent float64   `json:"trend_percent"` // vs previous period
}

// AgingBucketStat represents credit aging bucket statistics
type AgingBucketStat struct {
	Bucket        string  `json:"bucket"` // 0-30, 31-60, 61-90, 90+
	CustomerCount int     `json:"customer_count"`
	TotalAmount   float64 `json:"total_amount"`
	Percentage    float64 `json:"percentage"`
}

// SalesMetricsRequest represents filters for sales metrics
type SalesMetricsRequest struct {
	TenantID  uuid.UUID  `json:"tenant_id"`
	ShopID    *uuid.UUID `json:"shop_id,omitempty"`
	StartDate time.Time  `json:"start_date"`
	EndDate   time.Time  `json:"end_date"`
	GroupBy   string     `json:"group_by"` // day, week, month
}

// CreditPaymentRequest represents a payment on credit sale
type CreditPaymentRequest struct {
	CreditSaleID  uuid.UUID `json:"credit_sale_id" binding:"required"`
	Amount        float64   `json:"amount" binding:"required,gt=0"`
	PaymentMethod string    `json:"payment_method"`
	Notes         string    `json:"notes"`
}

// DailySalesStat represents daily sales statistics
type DailySalesStat struct {
	Date         time.Time `json:"date"`
	TotalSales   float64   `json:"total_sales"`
	CashSales    float64   `json:"cash_sales"`
	CardSales    float64   `json:"card_sales"`
	UPISales     float64   `json:"upi_sales"`
	CreditSales  float64   `json:"credit_sales"`
	Expenses     float64   `json:"expenses"`
	Transactions int64     `json:"transactions"`
}

// TopProductStat represents top selling product statistics
type TopProductStat struct {
	ProductID        uuid.UUID `json:"product_id"`
	ProductName      string    `json:"product_name"`
	SKU              string    `json:"sku"`
	QuantitySold     int64     `json:"quantity_sold"`
	TotalRevenue     float64   `json:"total_revenue"`
	TransactionCount int64     `json:"transaction_count"`
}

// FinanceInsight represents a generated financial insight
type FinanceInsight struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID    uuid.UUID  `json:"tenant_id" gorm:"type:uuid;not null;index"`
	ShopID      *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid;index"`
	Type        string     `json:"type"`        // sales_trend, cash_variance, credit_utilization, etc.
	InsightType string     `json:"insight_type"` // Alias for Type
	Severity    string     `json:"severity"`     // info, warning, critical
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Value       float64    `json:"value"`
	Change      float64    `json:"change"`        // percentage change
	Trend       string     `json:"trend"`         // up, down, stable
	Direction   string     `json:"direction"`     // Alias for Trend
	ActionURL   string     `json:"action_url"`    // deep link to action
	IsRead      bool       `json:"is_read" gorm:"default:false"`
	ExpiresAt   *time.Time `json:"expires_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at" gorm:"autoCreateTime"`
}

// SalesmanPerformance represents salesman performance metrics
type SalesmanPerformance struct {
	SalesmanID       uuid.UUID `json:"salesman_id"`
	SalesmanName     string    `json:"salesman_name"`
	TotalSalesCount  int64     `json:"total_sales_count"`
	TotalSalesAmount float64   `json:"total_sales_amount"`
	CashCollected    float64   `json:"cash_collected"`
	CreditGiven      float64   `json:"credit_given"`
	AvgSaleValue     float64   `json:"avg_sale_value"`
	ItemsSold        int64     `json:"items_sold"`
}

// StockTurnoverStat represents stock turnover statistics
type StockTurnoverStat struct {
	ProductID       uuid.UUID `json:"product_id"`
	ProductName     string    `json:"product_name"`
	SKU             string    `json:"sku"`
	CurrentStock    int       `json:"current_stock"`
	SoldQuantity    int64     `json:"sold_quantity"`
	StockValue      float64   `json:"stock_value"`
	TurnoverRatio   float64   `json:"turnover_ratio"`
	DaysOfStock     int       `json:"days_of_stock"`
	StockVelocity   string    `json:"stock_velocity"` // fast, medium, slow, dead
	LastSoldAt      *time.Time `json:"last_sold_at,omitempty"`
}
