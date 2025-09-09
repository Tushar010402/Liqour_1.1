package models

import (
	"time"

	"github.com/google/uuid"
)

// Sale represents individual sale transactions
type Sale struct {
	TenantModel
	SaleNumber  string    `json:"sale_number" gorm:"unique;not null"`
	ShopID      uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop        *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	SalesmanID  *uuid.UUID `json:"salesman_id" gorm:"type:uuid"`
	Salesman    *Salesman `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`
	
	SaleDate    time.Time `json:"sale_date" gorm:"not null"`
	CustomerName string   `json:"customer_name"`
	CustomerPhone string  `json:"customer_phone"`
	
	// Financial details
	SubTotal     float64 `json:"sub_total" gorm:"not null"`
	DiscountAmount float64 `json:"discount_amount" gorm:"default:0"`
	TaxAmount    float64 `json:"tax_amount" gorm:"default:0"`
	TotalAmount  float64 `json:"total_amount" gorm:"not null"`
	PaidAmount   float64 `json:"paid_amount" gorm:"default:0"`
	DueAmount    float64 `json:"due_amount" gorm:"default:0"`
	
	// Payment details
	PaymentMethod string `json:"payment_method" gorm:"default:'cash'"`
	PaymentStatus string `json:"payment_status" gorm:"default:'pending'"` // pending, partial, paid
	
	// Status and approval
	Status        string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, returned
	ApprovedAt    *time.Time `json:"approved_at"`
	ApprovedByID  *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy    *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy     *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	
	Notes         string `json:"notes"`
	
	// OCR and image processing
	ParchaImage   string `json:"parcha_image"` // Receipt/bill image
	
	// Relationships
	Items         []SaleItem    `json:"items,omitempty" gorm:"foreignKey:SaleID"`
	Payments      []SalePayment `json:"payments,omitempty" gorm:"foreignKey:SaleID"`
	Returns       []SaleReturn  `json:"returns,omitempty" gorm:"foreignKey:SaleID"`
	FinanceLogs   []SaleFinanceLog `json:"finance_logs,omitempty" gorm:"foreignKey:SaleID"`
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
	SaleID        uuid.UUID `json:"sale_id" gorm:"type:uuid;not null"`
	Sale          *Sale     `json:"sale,omitempty" gorm:"foreignKey:SaleID"`
	
	Amount        float64   `json:"amount" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	PaymentDate   time.Time `json:"payment_date" gorm:"not null"`
	Reference     string    `json:"reference"`
	Notes         string    `json:"notes"`
	
	// Bank details for card/UPI payments
	BankReference string `json:"bank_reference"`
	
	// Created by
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy     *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
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
	CreatedByID  uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy    *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	
	Notes        string `json:"notes"`
	
	// Relationships
	Items        []SaleReturnItem `json:"items,omitempty" gorm:"foreignKey:SaleReturnID"`
}

// SaleReturnItem represents individual items being returned
type SaleReturnItem struct {
	TenantModel
	SaleReturnID uuid.UUID     `json:"sale_return_id" gorm:"type:uuid;not null"`
	SaleReturn   *SaleReturn   `json:"sale_return,omitempty" gorm:"foreignKey:SaleReturnID"`
	SaleItemID   uuid.UUID     `json:"sale_item_id" gorm:"type:uuid;not null"`
	SaleItem     *SaleItem     `json:"sale_item,omitempty" gorm:"foreignKey:SaleItemID"`
	
	Quantity     int     `json:"quantity" gorm:"not null"`
	UnitPrice    float64 `json:"unit_price" gorm:"not null"`
	TotalAmount  float64 `json:"total_amount" gorm:"not null"`
	Reason       string  `json:"reason"`
}

// DailySalesRecord represents bulk daily sales entry (critical for current workflow)
type DailySalesRecord struct {
	TenantModel
	RecordDate  time.Time `json:"record_date" gorm:"not null"`
	ShopID      uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop        *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	SalesmanID  *uuid.UUID `json:"salesman_id" gorm:"type:uuid"`
	Salesman    *Salesman `json:"salesman,omitempty" gorm:"foreignKey:SalesmanID"`
	
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
	CreatedByID  uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy    *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	
	Notes        string `json:"notes"`
	
	// Relationships
	Items        []DailySalesItem `json:"items,omitempty" gorm:"foreignKey:DailySalesRecordID"`
}

// DailySalesItem represents individual product sales within a daily record
type DailySalesItem struct {
	TenantModel
	DailySalesRecordID uuid.UUID          `json:"daily_sales_record_id" gorm:"type:uuid;not null"`
	DailySalesRecord   *DailySalesRecord  `json:"daily_sales_record,omitempty" gorm:"foreignKey:DailySalesRecordID"`
	ProductID          uuid.UUID          `json:"product_id" gorm:"type:uuid;not null"`
	Product            *Product           `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	
	Quantity           int     `json:"quantity" gorm:"not null"`
	UnitPrice          float64 `json:"unit_price" gorm:"not null"`
	TotalAmount        float64 `json:"total_amount" gorm:"not null"`
	
	// Payment breakdown for this item
	CashAmount         float64 `json:"cash_amount" gorm:"default:0"`
	CardAmount         float64 `json:"card_amount" gorm:"default:0"`
	UpiAmount          float64 `json:"upi_amount" gorm:"default:0"`
	CreditAmount       float64 `json:"credit_amount" gorm:"default:0"`
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
	AccountCode     string `json:"account_code"`
	
	// Created by
	CreatedByID     uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy       *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// DailySaleSummary represents daily aggregated sales data
type DailySaleSummary struct {
	TenantModel
	SummaryDate     time.Time `json:"summary_date" gorm:"not null"`
	ShopID          uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop            *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	
	TotalSales      int     `json:"total_sales"`
	TotalItems      int     `json:"total_items"`
	TotalAmount     float64 `json:"total_amount"`
	TotalCash       float64 `json:"total_cash"`
	TotalCard       float64 `json:"total_card"`
	TotalUpi        float64 `json:"total_upi"`
	TotalCredit     float64 `json:"total_credit"`
	
	// Categories breakdown
	WhiskeyAmount   float64 `json:"whiskey_amount"`
	BeerAmount      float64 `json:"beer_amount"`
	WineAmount      float64 `json:"wine_amount"`
	OtherAmount     float64 `json:"other_amount"`
	
	IsGenerated     bool      `json:"is_generated" gorm:"default:false"`
	GeneratedAt     *time.Time `json:"generated_at"`
}