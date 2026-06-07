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

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	Notes string `json:"notes"`

	// OCR and image processing
	ParchaImage string `json:"parcha_image"` // Receipt/bill image

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
	ShopID     uuid.UUID  `json:"shop_id" gorm:"column:shop_id;type:uuid;not null"`
	Shop       *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	SalesmanID *uuid.UUID `json:"salesman_id" gorm:"column:salesman_id;type:uuid"`
	Salesman   *Salesman  `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`

	// Financial totals
	TotalSalesAmount  float64 `json:"total_sales_amount" gorm:"not null"`
	TotalCashAmount   float64 `json:"total_cash_amount" gorm:"default:0"`
	TotalCardAmount   float64 `json:"total_card_amount" gorm:"default:0"`
	TotalUpiAmount    float64 `json:"total_upi_amount" gorm:"default:0"`
	TotalCreditAmount float64 `json:"total_credit_amount" gorm:"default:0"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	Notes string `json:"notes"`

	// Receipt images (URLs of uploaded receipt photos for verification)
	ReceiptImages JSONStringList `json:"receipt_images,omitempty" gorm:"type:jsonb;default:'[]'"`

	// Stock alert tracking (populated by Smart Sale when stock discrepancies exist)
	HasAlerts  bool `json:"has_alerts" gorm:"default:false"`
	AlertCount int  `json:"alert_count" gorm:"default:0"`

	// Idempotency key to prevent duplicate submissions from network retries or double-taps
	IdempotencyKey *string `json:"idempotency_key,omitempty" gorm:"column:idempotency_key;uniqueIndex:idx_daily_sales_idempotency_key,where:idempotency_key IS NOT NULL AND deleted_at IS NULL"`

	// v1.0.124: SHA256 of canonical apply-payload items (client-computed).
	// Surfaced on summary fetch so Flutter can verify "what server saved =
	// what I submitted" round-trip integrity. Mismatch is a hard tamper
	// signal and must be surfaced to the user — not silent.
	ClientPayloadHash *string `json:"client_payload_hash,omitempty" gorm:"column:client_payload_hash"`

	// Relationships
	Items []DailySalesItem `json:"items,omitempty" gorm:"foreignKey:DailySalesRecordID"`
}

// DailySalesItem represents individual product sales within a daily record
type DailySalesItem struct {
	TenantModel
	DailySalesRecordID uuid.UUID         `json:"daily_sales_record_id" gorm:"type:uuid;not null"`
	DailySalesRecord   *DailySalesRecord `json:"daily_sales_record,omitempty" gorm:"foreignKey:DailySalesRecordID"`
	ProductID          uuid.UUID         `json:"product_id" gorm:"type:uuid;not null"`
	Product            *Product          `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	Quantity     int     `json:"quantity" gorm:"not null"`
	QuantitySold int     `json:"quantity_sold" gorm:"default:0"`
	UnitPrice    float64 `json:"unit_price" gorm:"not null"`
	TotalAmount  float64 `json:"total_amount" gorm:"not null"`

	// Payment breakdown for this item
	CashAmount   float64 `json:"cash_amount" gorm:"default:0"`
	CardAmount   float64 `json:"card_amount" gorm:"default:0"`
	UpiAmount    float64 `json:"upi_amount" gorm:"default:0"`
	CreditAmount float64 `json:"credit_amount" gorm:"default:0"`

	// Stock snapshot captured at creation time (locked values)
	OpeningStock int `json:"opening_stock" gorm:"default:0"`
	ClosingStock int `json:"closing_stock" gorm:"default:0"`

	// Stock alert (populated by Smart Sale when stock discrepancy exists for this item)
	StockAlert    string `json:"stock_alert,omitempty" gorm:"type:text"`
	StockAlertQty int    `json:"stock_alert_qty,omitempty" gorm:"default:0"`

	// v1.0.124: row-level audit. Source carries how the row was produced —
	// "main" (AI extracted), "recovery_pass", "setup_rescue" (auto-injected
	// from approved stock setup, user-confirmed), "manual_add" (user-added
	// from inventory picker). ClientRowID is a UUID Flutter assigned when
	// the row entered the review screen so the same row can be traced
	// across re-extracts, restores, and resubmits.
	Source      string  `json:"source,omitempty" gorm:"type:varchar(32);index:idx_dsi_source,where:source IS NOT NULL"`
	ClientRowID *string `json:"client_row_id,omitempty" gorm:"type:uuid"`

	// v1.0.133-r6 — AI-extracted register column values, snapshotted at the
	// time of insert. Pre-r6 these columns existed in the table (added by
	// an old migration) but the struct never declared them, so GORM never
	// wrote to them — every saved row had ocr_total=0 and ocr_rate=0,
	// erasing the audit trail. Now persisted on every insert. Explicit
	// gorm column tags after the v1.0.132 last_m_rpchange_at lesson.
	OcrBrandName string  `json:"ocr_brand_name,omitempty" gorm:"column:ocr_brand_name;type:varchar(255)"`
	OcrSize      string  `json:"ocr_size,omitempty"       gorm:"column:ocr_size;type:varchar(50)"`
	OcrReceipt   int     `json:"ocr_receipt,omitempty"    gorm:"column:ocr_receipt;default:0"`
	OcrTotal     int     `json:"ocr_total,omitempty"      gorm:"column:ocr_total;default:0"`
	OcrRate      float64 `json:"ocr_rate,omitempty"       gorm:"column:ocr_rate;type:numeric(10,2);default:0"`
	DBStockSnap  int     `json:"db_stock,omitempty"       gorm:"column:db_stock;default:0"`

	// v1.0.149 — operator-defined display order. Set on Smart Sale apply
	// to page*1000 + row_number so initial order matches the image. Updated
	// via PATCH /sales/daily-records/:id/items/reorder when the operator
	// drag-reorders rows on the Sales Summary screen. Every list endpoint
	// MUST sort by position ASC so all views agree.
	Position int `json:"position" gorm:"column:position;not null;default:0;index:idx_daily_sales_items_record_position,priority:2"`
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

// DayClosingRecord represents end-of-day reconciliation data
// (cash denomination count, UPI breakdown, expenses entered by salesman)
type DayClosingRecord struct {
	TenantModel
	ShopID    uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop      *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	UserID    uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`
	Date      time.Time `json:"date" gorm:"type:date;not null"`

	// Cash reconciliation
	CashDenominations string  `json:"cash_denominations" gorm:"type:jsonb;default:'{}'"`  // JSON: {"500": 5, "200": 3}
	CashTotal         float64 `json:"cash_total" gorm:"default:0"`

	// UPI reconciliation
	UpiBreakdown string  `json:"upi_breakdown" gorm:"type:jsonb;default:'{}'"`  // JSON: {"Google Pay": 1200}
	UpiTotal     float64 `json:"upi_total" gorm:"default:0"`

	// Expense reconciliation
	Expenses     string  `json:"expenses" gorm:"type:jsonb;default:'{}'"`  // JSON: {"Transport": 300}
	ExpenseTotal float64 `json:"expense_total" gorm:"default:0"`
}

// TableName overrides the default table name
func (DayClosingRecord) TableName() string {
	return "day_closing_records"
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
