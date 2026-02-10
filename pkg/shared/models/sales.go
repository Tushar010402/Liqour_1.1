package models

import (
	"time"

	"github.com/google/uuid"
)

// Sale represents individual sale transactions
type Sale struct {
	TenantModel
	SaleNumber string     `json:"sale_number" gorm:"unique;not null"`
	ShopID     uuid.UUID  `json:"shop_id" gorm:"type:uuid;not null"`
	Shop       *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	SalesmanID *uuid.UUID `json:"salesman_id" gorm:"type:uuid"`
	Salesman   *Salesman  `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`

	SaleDate      time.Time `json:"sale_date" gorm:"not null"`
	CustomerName  string    `json:"customer_name"`
	CustomerPhone string    `json:"customer_phone"`

	// Financial details
	SubTotal       float64 `json:"sub_total" gorm:"not null"`
	DiscountAmount float64 `json:"discount_amount" gorm:"default:0"`
	TaxAmount      float64 `json:"tax_amount" gorm:"default:0"`
	TotalAmount    float64 `json:"total_amount" gorm:"not null"`
	PaidAmount     float64 `json:"paid_amount" gorm:"default:0"`
	DueAmount      float64 `json:"due_amount" gorm:"default:0"`

	// Payment details
	PaymentMethod string `json:"payment_method" gorm:"default:'cash'"`
	PaymentStatus string `json:"payment_status" gorm:"default:'pending'"` // pending, partial, paid

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, returned
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Rejection tracking
	RejectedAt      *time.Time `json:"rejected_at"`
	RejectedByID    *uuid.UUID `json:"rejected_by_id" gorm:"type:uuid"`
	RejectedBy      *User      `json:"rejected_by,omitempty" gorm:"foreignKey:RejectedByID"`
	RejectionReason string     `json:"rejection_reason"`

	// Revert tracking (admin-only operation to undo approved sales)
	RevertedAt    *time.Time `json:"reverted_at"`
	RevertedByID  *uuid.UUID `json:"reverted_by_id" gorm:"type:uuid"`
	RevertedBy    *User      `json:"reverted_by,omitempty" gorm:"foreignKey:RevertedByID"`
	RevertReason  string     `json:"revert_reason"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	Notes string `json:"notes"`

	// OCR and image processing
	ParchaImage string `json:"parcha_image"` // Receipt/bill image

	// Reminder tracking (prevents duplicate notifications)
	LastReminderLevel  int        `json:"last_reminder_level" gorm:"default:0"`
	LastReminderSentAt *time.Time `json:"last_reminder_sent_at"`

	// Relationships
	Items       []SaleItem       `json:"items,omitempty" gorm:"foreignKey:SaleID"`
	Payments    []SalePayment    `json:"payments,omitempty" gorm:"foreignKey:SaleID"`
	Returns     []SaleReturn     `json:"returns,omitempty" gorm:"foreignKey:SaleID"`
	FinanceLogs []SaleFinanceLog `json:"finance_logs,omitempty" gorm:"foreignKey:SaleID"`
}

// SaleItem represents individual items in a sale
type SaleItem struct {
	TenantModel
	SaleID    uuid.UUID `json:"sale_id" gorm:"type:uuid;not null"`
	Sale      *Sale     `json:"sale,omitempty" gorm:"foreignKey:SaleID"`
	ProductID uuid.UUID `json:"product_id" gorm:"type:uuid;not null"`
	Product   *Product  `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	Quantity       int     `json:"quantity" gorm:"not null"`
	UnitPrice      float64 `json:"unit_price" gorm:"not null"`
	DiscountAmount float64 `json:"discount_amount" gorm:"default:0"`
	DiscountReason string  `json:"discount_reason"`
	TotalPrice     float64 `json:"total_price" gorm:"not null"`

	// Batch tracking
	StockBatchID *uuid.UUID  `json:"stock_batch_id" gorm:"type:uuid"`
	StockBatch   *StockBatch `json:"stock_batch,omitempty" gorm:"foreignKey:StockBatchID"`
}

// SalePayment represents payments received for sales
type SalePayment struct {
	TenantModel
	SaleID uuid.UUID `json:"sale_id" gorm:"type:uuid;not null"`
	Sale   *Sale     `json:"sale,omitempty" gorm:"foreignKey:SaleID"`

	Amount        float64   `json:"amount" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	PaymentDate   time.Time `json:"payment_date" gorm:"not null"`
	Reference     string    `json:"reference"`
	Notes         string    `json:"notes"`

	// Bank details for card/UPI payments
	BankReference string `json:"bank_reference"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// SaleReturn represents returned items
type SaleReturn struct {
	TenantModel
	ReturnNumber string    `json:"return_number" gorm:"unique;not null"`
	SaleID       uuid.UUID `json:"sale_id" gorm:"type:uuid;not null"`
	Sale         *Sale     `json:"sale,omitempty" gorm:"foreignKey:SaleID"`

	ReturnDate   time.Time `json:"return_date" gorm:"not null"`
	ReturnAmount float64   `json:"return_amount" gorm:"not null"`
	Reason       string    `json:"reason" gorm:"not null"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	Notes string `json:"notes"`

	// Relationships
	Items []SaleReturnItem `json:"items,omitempty" gorm:"foreignKey:SaleReturnID"`
}

// SaleReturnItem represents individual items being returned
type SaleReturnItem struct {
	TenantModel
	SaleReturnID uuid.UUID   `json:"sale_return_id" gorm:"type:uuid;not null"`
	SaleReturn   *SaleReturn `json:"sale_return,omitempty" gorm:"foreignKey:SaleReturnID"`
	SaleItemID   uuid.UUID   `json:"sale_item_id" gorm:"type:uuid;not null"`
	SaleItem     *SaleItem   `json:"sale_item,omitempty" gorm:"foreignKey:SaleItemID"`

	Quantity    int     `json:"quantity" gorm:"not null"`
	UnitPrice   float64 `json:"unit_price" gorm:"not null"`
	TotalAmount float64 `json:"total_amount" gorm:"not null"`
	Reason      string  `json:"reason"`
}

// DailySalesRecord represents bulk daily sales entry (critical for current workflow)
type DailySalesRecord struct {
	TenantModel
	RecordDate time.Time  `json:"record_date" gorm:"not null"`
	ShopID     uuid.UUID  `json:"shop_id" gorm:"type:uuid;not null"`
	Shop       *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	SalesmanID *uuid.UUID `json:"salesman_id" gorm:"type:uuid"`
	Salesman   *Salesman  `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`

	// Financial totals
	TotalSalesAmount   float64 `json:"total_sales_amount" gorm:"not null"`
	TotalCashAmount    float64 `json:"total_cash_amount" gorm:"default:0"`
	TotalCardAmount    float64 `json:"total_card_amount" gorm:"default:0"`
	TotalUpiAmount     float64 `json:"total_upi_amount" gorm:"default:0"`
	TotalCreditAmount  float64 `json:"total_credit_amount" gorm:"default:0"`
	TotalExpenseAmount float64 `json:"total_expense_amount" gorm:"default:0"` // NEW: Total expenses

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	Notes string `json:"notes"`

	// Image attachments (for receipt/bill photos)
	ImageURLs string `json:"image_urls" gorm:"type:text"` // JSON array of URLs stored as text

	// Location tracking (optional)
	Latitude           *float64   `json:"latitude,omitempty" gorm:"column:latitude;type:decimal(10,8)"`
	Longitude          *float64   `json:"longitude,omitempty" gorm:"column:longitude;type:decimal(11,8)"`
	LocationAccuracy   *string    `json:"location_accuracy,omitempty" gorm:"column:location_accuracy;size:20"`
	LocationCapturedAt *time.Time `json:"location_captured_at,omitempty" gorm:"column:location_captured_at"`

	// AI Validation Fields
	OCRSessionID          *uuid.UUID `json:"ocr_session_id,omitempty" gorm:"type:uuid"`
	ValidationStatus      string     `json:"validation_status" gorm:"default:'pending';size:20"`
	ValidationResult      *string    `json:"validation_result,omitempty" gorm:"type:jsonb"` // JSONB stored as string
	ValidatedAt           *time.Time `json:"validated_at,omitempty"`
	ValidationTriggeredAt *time.Time `json:"validation_triggered_at,omitempty"`

	// Auto-learning feedback
	ValidationConfirmed bool       `json:"validation_confirmed" gorm:"default:false"`
	ConfirmedByID       *uuid.UUID `json:"confirmed_by_id,omitempty" gorm:"type:uuid"`
	ConfirmedBy         *User      `json:"confirmed_by,omitempty" gorm:"foreignKey:ConfirmedByID"`
	ConfirmedAt         *time.Time `json:"confirmed_at,omitempty"`
	FeedbackNotes       string     `json:"feedback_notes,omitempty"`

	// Revert tracking (admin-only operation to undo approved daily sales)
	RevertedAt    *time.Time `json:"reverted_at,omitempty"`
	RevertedByID  *uuid.UUID `json:"reverted_by_id,omitempty" gorm:"type:uuid"`
	RevertedBy    *User      `json:"reverted_by,omitempty" gorm:"foreignKey:RevertedByID"`
	RevertReason  string     `json:"revert_reason,omitempty"`

	// Reminder tracking (prevents duplicate notifications)
	LastReminderLevel  int        `json:"last_reminder_level" gorm:"default:0"`
	LastReminderSentAt *time.Time `json:"last_reminder_sent_at"`

	// Relationships
	Items    []DailySalesItem    `json:"items,omitempty" gorm:"foreignKey:DailySalesRecordID"`
	Expenses []DailySalesExpense `json:"expenses,omitempty" gorm:"foreignKey:DailySalesRecordID"` // NEW: Expense breakdown
}

// DailySalesExpense represents individual expense entries within a daily sales record
type DailySalesExpense struct {
	TenantModel
	DailySalesRecordID uuid.UUID         `json:"daily_sales_record_id" gorm:"type:uuid;not null"`
	DailySalesRecord   *DailySalesRecord `json:"daily_sales_record,omitempty" gorm:"foreignKey:DailySalesRecordID"`

	HeaderID   string  `json:"header_id" gorm:"size:100;not null"`   // e.g., "godam_charges", "transport"
	HeaderName string  `json:"header_name" gorm:"size:255;not null"` // e.g., "Godam Charges", "Transport"
	Amount     float64 `json:"amount" gorm:"not null;default:0"`
}

// DailySalesItem represents individual product sales within a daily record
type DailySalesItem struct {
	TenantModel
	DailySalesRecordID uuid.UUID         `json:"daily_sales_record_id" gorm:"type:uuid;not null"`
	DailySalesRecord   *DailySalesRecord `json:"daily_sales_record,omitempty" gorm:"foreignKey:DailySalesRecordID"`
	ProductID          uuid.UUID         `json:"product_id" gorm:"type:uuid;not null"`
	Product            *Product          `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	Quantity    int     `json:"quantity" gorm:"not null"`
	UnitPrice   float64 `json:"unit_price" gorm:"not null"`
	TotalAmount float64 `json:"total_amount" gorm:"not null"`

	// Payment breakdown for this item
	CashAmount   float64 `json:"cash_amount" gorm:"default:0"`
	CardAmount   float64 `json:"card_amount" gorm:"default:0"`
	UpiAmount    float64 `json:"upi_amount" gorm:"default:0"`
	CreditAmount float64 `json:"credit_amount" gorm:"default:0"`

	// Stock audit trail - captured at creation time for inventory tracking
	OpeningStock int `json:"opening_stock" gorm:"default:0"` // Stock BEFORE this sale was recorded
	ClosingStock int `json:"closing_stock" gorm:"default:0"` // Expected stock AFTER (opening - quantity)

	// OCR-extracted data (from Smart Sale / GPT-5.2) - for manager review
	// These fields store what was extracted from the image so managers can compare with system data
	OCRBrandName string  `json:"ocr_brand_name" gorm:"size:255"`        // Brand name extracted from image
	OCRSize      string  `json:"ocr_size" gorm:"size:50"`               // Size extracted from image (e.g., "375ML")
	OCRReceipt   int     `json:"ocr_receipt" gorm:"default:0"`          // New stock received (from image)
	OCRTotal     int     `json:"ocr_total" gorm:"default:0"`            // Opening + Receipt (from image)
	DBStock      int     `json:"db_stock" gorm:"default:0"`             // Stock in database at time of submission (for comparison)
	OCRRate      float64 `json:"ocr_rate" gorm:"default:0"`             // Rate from image (for comparison with UnitPrice)
}

// SaleFinanceLog tracks financial transactions related to sales
type SaleFinanceLog struct {
	TenantModel
	SaleID          uuid.UUID `json:"sale_id" gorm:"type:uuid;not null"`
	Sale            *Sale     `json:"sale,omitempty" gorm:"foreignKey:SaleID"`
	TransactionType string    `json:"transaction_type" gorm:"not null"` // sale, payment, return, adjustment
	Amount          float64   `json:"amount" gorm:"not null"`
	Description     string    `json:"description"`

	// Financial account integration
	AccountCode string `json:"account_code"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// DailySaleSummary represents daily aggregated sales data
type DailySaleSummary struct {
	TenantModel
	SummaryDate time.Time `json:"summary_date" gorm:"not null"`
	ShopID      uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop        *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	TotalSales  int     `json:"total_sales"`
	TotalItems  int     `json:"total_items"`
	TotalAmount float64 `json:"total_amount"`
	TotalCash   float64 `json:"total_cash"`
	TotalCard   float64 `json:"total_card"`
	TotalUpi    float64 `json:"total_upi"`
	TotalCredit float64 `json:"total_credit"`

	// Categories breakdown
	WhiskeyAmount float64 `json:"whiskey_amount"`
	BeerAmount    float64 `json:"beer_amount"`
	WineAmount    float64 `json:"wine_amount"`
	OtherAmount   float64 `json:"other_amount"`

	IsGenerated bool       `json:"is_generated" gorm:"default:false"`
	GeneratedAt *time.Time `json:"generated_at"`
}

// DailySalesDraft represents a draft daily sales entry per user per shop per date
// Replaces Hive local storage for cross-device consistency
type DailySalesDraft struct {
	ID         uuid.UUID `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID   uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null"`
	UserID     uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	User       *User     `json:"user,omitempty" gorm:"foreignKey:UserID"`
	ShopID     uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop       *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	RecordDate time.Time `json:"record_date" gorm:"type:date;not null"`

	// Draft Data (JSONB for flexibility)
	// Contains: salesman_id, totals, items[], expenses[], location, images, notes
	DraftData string `json:"draft_data" gorm:"type:jsonb;not null;default:'{}'"`

	// Timestamps
	CreatedAt      time.Time  `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt      time.Time  `json:"updated_at" gorm:"autoUpdateTime"`
	LastAutoSaveAt *time.Time `json:"last_auto_save_at,omitempty"`

	// Metadata for debugging/analytics
	DeviceID   string `json:"device_id,omitempty" gorm:"size:255"`
	AppVersion string `json:"app_version,omitempty" gorm:"size:50"`
}

// TableName specifies the table name for DailySalesDraft
func (DailySalesDraft) TableName() string {
	return "daily_sales_drafts"
}

// DraftDataContent represents the structure of draft_data JSONB field
type DraftDataContent struct {
	SalesmanID         *string            `json:"salesman_id,omitempty"`
	TotalSalesAmount   float64            `json:"total_sales_amount"`
	TotalCashAmount    float64            `json:"total_cash_amount"`
	TotalCardAmount    float64            `json:"total_card_amount"`
	TotalUpiAmount     float64            `json:"total_upi_amount"`
	TotalCreditAmount  float64            `json:"total_credit_amount"`
	TotalExpenseAmount float64            `json:"total_expense_amount"`
	Notes              string             `json:"notes,omitempty"`
	Latitude           *float64           `json:"latitude,omitempty"`
	Longitude          *float64           `json:"longitude,omitempty"`
	LocationAccuracy   string             `json:"location_accuracy,omitempty"`
	LocationCapturedAt string             `json:"location_captured_at,omitempty"`
	ImageURLs          []string           `json:"image_urls,omitempty"`
	Items              []DraftItemContent `json:"items,omitempty"`
	Expenses           []DraftExpenseContent `json:"expenses,omitempty"`
}

// DraftItemContent represents an item within draft data
type DraftItemContent struct {
	ProductID    string  `json:"product_id"`
	Quantity     int     `json:"quantity"`
	UnitPrice    float64 `json:"unit_price"`
	TotalAmount  float64 `json:"total_amount"`
	CashAmount   float64 `json:"cash_amount"`
	CardAmount   float64 `json:"card_amount"`
	UpiAmount    float64 `json:"upi_amount"`
	CreditAmount float64 `json:"credit_amount"`
}

// DraftExpenseContent represents an expense within draft data
type DraftExpenseContent struct {
	HeaderID   string  `json:"header_id"`
	HeaderName string  `json:"header_name"`
	Amount     float64 `json:"amount"`
}
