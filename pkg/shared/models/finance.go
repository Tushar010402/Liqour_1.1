package models

import (
	"time"

	"github.com/google/uuid"
)

// Vendor represents suppliers/vendors
type Vendor struct {
	TenantModel
	Name          string  `json:"name" gorm:"not null"`
	ContactPerson string  `json:"contact_person"`
	Phone         string  `json:"phone"`
	Email         string  `json:"email"`
	Address       string  `json:"address"`
	City          string  `json:"city"`
	State         string  `json:"state"`
	Country       string  `json:"country"`
	PostalCode    string  `json:"postal_code"`
	TaxID         string  `json:"tax_id"`
	GSTNumber     string  `json:"gst_number"`
	PANNumber     string  `json:"pan_number"`
	PaymentTerms  string  `json:"payment_terms"`
	CreditLimit   float64 `json:"credit_limit" gorm:"default:0"`
	IsActive      bool    `json:"is_active" gorm:"default:true"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`

	// Relationships
	BankAccounts   []VendorBankAccount `json:"bank_accounts,omitempty" gorm:"foreignKey:VendorID"`
	Transactions   []VendorTransaction `json:"transactions,omitempty" gorm:"foreignKey:VendorID"`
	Invoices       []VendorInvoice     `json:"invoices,omitempty" gorm:"foreignKey:VendorID"`
	StockPurchases []StockPurchase     `json:"stock_purchases,omitempty" gorm:"foreignKey:VendorID"`
}

// VendorBankAccount represents vendor banking details
type VendorBankAccount struct {
	TenantModel
	VendorID          uuid.UUID `json:"vendor_id" gorm:"type:uuid;not null"`
	Vendor            *Vendor   `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	BankName          string    `json:"bank_name" gorm:"not null"`
	AccountNumber     string    `json:"account_number" gorm:"not null"`
	IFSCCode          string    `json:"ifsc_code" gorm:"not null"`
	AccountHolder     string    `json:"account_holder" gorm:"not null"`
	AccountHolderName string    `json:"account_holder_name" gorm:"not null"`
	BranchCode        string    `json:"branch_code"`
	SwiftCode         string    `json:"swift_code"`
	IsPrimary         bool      `json:"is_primary" gorm:"default:false"`
	IsDefault         bool      `json:"is_default" gorm:"default:false"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
}

// VendorTransaction represents financial transactions with vendors
type VendorTransaction struct {
	TenantModel
	VendorID        uuid.UUID `json:"vendor_id" gorm:"type:uuid;not null"`
	Vendor          *Vendor   `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	TransactionType string    `json:"transaction_type" gorm:"not null"` // payment, purchase, adjustment
	Amount          float64   `json:"amount" gorm:"not null"`
	TransactionDate time.Time `json:"transaction_date" gorm:"not null"`
	PaymentMethod   string    `json:"payment_method"`
	Reference       string    `json:"reference"`
	ReferenceNo     string    `json:"reference_no"`
	Description     string    `json:"description"`

	// Invoice reference
	VendorInvoiceID *uuid.UUID     `json:"vendor_invoice_id" gorm:"type:uuid"`
	VendorInvoice   *VendorInvoice `json:"vendor_invoice,omitempty" gorm:"foreignKey:VendorInvoiceID"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
}

// VendorInvoice represents vendor invoices/bills
type VendorInvoice struct {
	TenantModel
	InvoiceNumber string    `json:"invoice_number" gorm:"not null"`
	VendorID      uuid.UUID `json:"vendor_id" gorm:"type:uuid;not null"`
	Vendor        *Vendor   `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	InvoiceDate   time.Time `json:"invoice_date" gorm:"not null"`
	DueDate       time.Time `json:"due_date" gorm:"not null"`

	SubTotal    float64 `json:"sub_total" gorm:"not null"`
	TaxAmount   float64 `json:"tax_amount" gorm:"default:0"`
	TotalAmount float64 `json:"total_amount" gorm:"not null"`
	PaidAmount  float64 `json:"paid_amount" gorm:"default:0"`
	DueAmount   float64 `json:"due_amount" gorm:"not null"`

	Status string `json:"status" gorm:"default:'pending'"` // pending, partial, paid, overdue

	// Relationships
	Transactions []VendorInvoiceTransaction `json:"transactions,omitempty" gorm:"foreignKey:VendorInvoiceID"`
}

// VendorInvoiceTransaction represents payments against vendor invoices
type VendorInvoiceTransaction struct {
	TenantModel
	VendorInvoiceID uuid.UUID      `json:"vendor_invoice_id" gorm:"type:uuid;not null"`
	VendorInvoice   *VendorInvoice `json:"vendor_invoice,omitempty" gorm:"foreignKey:VendorInvoiceID"`

	Amount        float64   `json:"amount" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	PaymentDate   time.Time `json:"payment_date" gorm:"not null"`
	Reference     string    `json:"reference"`
	Notes         string    `json:"notes"`
}

// BankAccount represents shop/tenant bank accounts
type BankAccount struct {
	TenantModel
	BankName          string  `json:"bank_name" gorm:"not null"`
	AccountNumber     string  `json:"account_number" gorm:"not null"`
	IFSCCode          string  `json:"ifsc_code" gorm:"not null"`
	AccountHolderName string  `json:"account_holder_name" gorm:"not null"`
	AccountType       string  `json:"account_type" gorm:"default:'savings'"`
	CurrentBalance    float64 `json:"current_balance" gorm:"default:0"`
	IsActive          bool    `json:"is_active" gorm:"default:true"`
	IsPrimary         bool    `json:"is_primary" gorm:"default:false"`

	// Relationships
	Transactions []BankTransaction `json:"transactions,omitempty" gorm:"foreignKey:BankAccountID"`
	CashDeposits []CashDeposit     `json:"cash_deposits,omitempty" gorm:"foreignKey:BankAccountID"`
}

// BankTransaction represents bank account transactions
type BankTransaction struct {
	TenantModel
	BankAccountID uuid.UUID    `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount   *BankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`

	TransactionType string    `json:"transaction_type" gorm:"not null"` // credit, debit
	Amount          float64   `json:"amount" gorm:"not null"`
	TransactionDate time.Time `json:"transaction_date" gorm:"not null"`
	Description     string    `json:"description" gorm:"not null"`
	Reference       string    `json:"reference"`

	PreviousBalance float64 `json:"previous_balance"`
	NewBalance      float64 `json:"new_balance"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// CashDeposit represents cash deposits to bank accounts
type CashDeposit struct {
	TenantModel
	BankAccountID uuid.UUID    `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount   *BankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`
	ShopID        uuid.UUID    `json:"shop_id" gorm:"type:uuid;not null"`
	Shop          *Shop        `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	Amount      float64   `json:"amount" gorm:"not null"`
	DepositDate time.Time `json:"deposit_date" gorm:"not null"`
	SlipNumber  string    `json:"slip_number"`
	Notes       string    `json:"notes"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// ExecutiveFinance represents executive financial records
type ExecutiveFinance struct {
	TenantModel
	ExecutiveID uuid.UUID `json:"executive_id" gorm:"type:uuid;not null"`
	Executive   *User     `json:"executive,omitempty" gorm:"foreignKey:ExecutiveID"`

	RecordDate  time.Time `json:"record_date" gorm:"not null"`
	TotalAmount float64   `json:"total_amount" gorm:"not null"`
	Description string    `json:"description"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// Expense represents general business expenses
type Expense struct {
	TenantModel
	CategoryID *uuid.UUID       `json:"category_id" gorm:"type:uuid"`
	Category   *ExpenseCategory `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	ShopID     *uuid.UUID       `json:"shop_id" gorm:"type:uuid"`
	Shop       *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	VendorID   *uuid.UUID       `json:"vendor_id" gorm:"type:uuid"`
	Vendor     *Vendor          `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`

	ExpenseDate   time.Time `json:"expense_date" gorm:"not null"`
	Description   string    `json:"description" gorm:"not null"`
	Amount        float64   `json:"amount" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	Notes         string    `json:"notes"`

	// Receipt/bill details
	ReceiptNo  string `json:"receipt_no"`
	BillNumber string `json:"bill_number"`
	VendorName string `json:"vendor_name"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
}

// Assistant Manager Financial Models

// MoneyCollection represents money collection by assistant managers (15-minute approval deadline)
type MoneyCollection struct {
	TenantModel
	ExecutiveID        uuid.UUID `json:"executive_id" gorm:"type:uuid;not null"`
	Executive          *User     `json:"executive,omitempty" gorm:"foreignKey:ExecutiveID"`
	AssistantManagerID uuid.UUID `json:"assistant_manager_id" gorm:"type:uuid;not null"`
	AssistantManager   *User     `json:"assistant_manager,omitempty" gorm:"foreignKey:AssistantManagerID"`
	ShopID             uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop               *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	CollectionDate time.Time `json:"collection_date" gorm:"not null"`
	Amount         float64   `json:"amount" gorm:"not null"`
	CollectionType string    `json:"collection_type" gorm:"not null"` // daily_sales, credit_recovery, other
	Description    string    `json:"description"`
	Notes          string    `json:"notes"`

	// 15-minute approval deadline
	CollectedAt      time.Time `json:"collected_at" gorm:"not null"`
	SubmittedAt      time.Time `json:"submitted_at" gorm:"not null"`
	DeadlineAt       time.Time `json:"deadline_at" gorm:"not null"`       // submitted_at + 15 minutes
	ApprovalDeadline time.Time `json:"approval_deadline" gorm:"not null"` // submitted_at + 15 minutes

	// Status and approval
	Status         string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, expired
	ApprovedAt     *time.Time `json:"approved_at"`
	ApprovedByID   *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy     *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedByUser *User      `json:"approved_by_user,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`

	RejectionReason string `json:"rejection_reason"`

	// Relationships
	BankDeposits       []BankDeposit            `json:"bank_deposits,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	StockVerifications []StockVerification      `json:"stock_verifications,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	LedgerEntries      []AssistantManagerLedger `json:"ledger_entries,omitempty" gorm:"foreignKey:MoneyCollectionID"`
}

// BankDeposit represents bank deposits made by assistant managers
type BankDeposit struct {
	TenantModel
	MoneyCollectionID *uuid.UUID       `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection   *MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	BankAccountID     uuid.UUID        `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount       *BankAccount     `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`

	DepositDate time.Time `json:"deposit_date" gorm:"not null"`
	Amount      float64   `json:"amount" gorm:"not null"`
	SlipNumber  string    `json:"slip_number"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// StockVerification represents stock verification by assistant managers
type StockVerification struct {
	TenantModel
	MoneyCollectionID *uuid.UUID       `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection   *MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	ShopID            uuid.UUID        `json:"shop_id" gorm:"type:uuid;not null"`
	Shop              *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	VerificationDate  time.Time `json:"verification_date" gorm:"not null"`
	TotalStockValue   float64   `json:"total_stock_value" gorm:"not null"`
	DiscrepancyAmount float64   `json:"discrepancy_amount" gorm:"default:0"`
	Notes             string    `json:"notes"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	// Relationships
	Items []StockVerificationItem `json:"items,omitempty" gorm:"foreignKey:StockVerificationID"`
}

// StockVerificationItem represents individual stock items in verification
type StockVerificationItem struct {
	TenantModel
	StockVerificationID uuid.UUID          `json:"stock_verification_id" gorm:"type:uuid;not null"`
	StockVerification   *StockVerification `json:"stock_verification,omitempty" gorm:"foreignKey:StockVerificationID"`
	ProductID           uuid.UUID          `json:"product_id" gorm:"type:uuid;not null"`
	Product             *Product           `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	SystemQuantity      int     `json:"system_quantity" gorm:"not null"`
	PhysicalQuantity    int     `json:"physical_quantity" gorm:"not null"`
	DiscrepancyQuantity int     `json:"discrepancy_quantity" gorm:"not null"`
	UnitValue           float64 `json:"unit_value" gorm:"not null"`
	DiscrepancyValue    float64 `json:"discrepancy_value" gorm:"not null"`
	Reason              string  `json:"reason"`
}

// AssistantManagerLedger represents complete audit trail for assistant manager transactions
type AssistantManagerLedger struct {
	TenantModel
	AssistantManagerID uuid.UUID        `json:"assistant_manager_id" gorm:"type:uuid;not null"`
	AssistantManager   *User            `json:"assistant_manager,omitempty" gorm:"foreignKey:AssistantManagerID"`
	MoneyCollectionID  *uuid.UUID       `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection    *MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`

	TransactionDate time.Time `json:"transaction_date" gorm:"not null"`
	TransactionType string    `json:"transaction_type" gorm:"not null"` // collection, deposit, verification, adjustment
	Amount          float64   `json:"amount" gorm:"not null"`
	Description     string    `json:"description" gorm:"not null"`
	Reference       string    `json:"reference"`

	// Running balance
	PreviousBalance float64 `json:"previous_balance"`
	NewBalance      float64 `json:"new_balance"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// AssistantManagerMoneyCollection alias for MoneyCollection (for backward compatibility)
type AssistantManagerMoneyCollection = MoneyCollection

// AssistantManagerExpense represents expenses made by assistant managers
type AssistantManagerExpense struct {
	TenantModel
	CategoryID         uuid.UUID        `json:"category_id" gorm:"type:uuid;not null"`
	Category           *ExpenseCategory `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	AssistantManagerID uuid.UUID        `json:"assistant_manager_id" gorm:"type:uuid;not null"`
	AssistantManager   *User            `json:"assistant_manager,omitempty" gorm:"foreignKey:AssistantManagerID"`
	ShopID             uuid.UUID        `json:"shop_id" gorm:"type:uuid;not null"`
	Shop               *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	ExpenseDate   time.Time `json:"expense_date" gorm:"not null"`
	Description   string    `json:"description" gorm:"not null"`
	Amount        float64   `json:"amount" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	Notes         string    `json:"notes"`

	// Receipt/bill details
	ReceiptNo  string `json:"receipt_no"`
	BillNumber string `json:"bill_number"`
	VendorName string `json:"vendor_name"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// AssistantManagerFinance represents financial records for assistant managers
type AssistantManagerFinance struct {
	TenantModel
	ExecutiveID        uuid.UUID `json:"executive_id" gorm:"type:uuid;not null"`
	Executive          *User     `json:"executive,omitempty" gorm:"foreignKey:ExecutiveID"`
	AssistantManagerID uuid.UUID `json:"assistant_manager_id" gorm:"type:uuid;not null"`
	AssistantManager   *User     `json:"assistant_manager,omitempty" gorm:"foreignKey:AssistantManagerID"`
	ShopID             uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop               *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	FinanceDate        time.Time `json:"finance_date" gorm:"not null"`
	RecordDate         time.Time `json:"record_date" gorm:"not null"`
	TotalSalesAmount   float64   `json:"total_sales_amount" gorm:"not null"`
	CashCollected      float64   `json:"cash_collected" gorm:"not null"`
	CardCollected      float64   `json:"card_collected" gorm:"not null"`
	UpiCollected       float64   `json:"upi_collected" gorm:"not null"`
	CreditCollected    float64   `json:"credit_collected" gorm:"not null"`
	TotalCollected     float64   `json:"total_collected" gorm:"not null"`
	TotalExpenses      float64   `json:"total_expenses" gorm:"not null"`
	NetAmount          float64   `json:"net_amount" gorm:"not null"`
	NetAmountToDeposit float64   `json:"net_amount_to_deposit" gorm:"not null"`
	Description        string    `json:"description"`
	Notes              string    `json:"notes"`

	// Status and approval
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// ExpenseCategory represents expense categories
type ExpenseCategory struct {
	TenantModel
	Name        string `json:"name" gorm:"not null"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active" gorm:"default:true"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`

	// Relationships
	Expenses                 []Expense                 `json:"expenses,omitempty" gorm:"foreignKey:CategoryID"`
	AssistantManagerExpenses []AssistantManagerExpense `json:"assistant_manager_expenses,omitempty" gorm:"foreignKey:CategoryID"`
}

// ══════════════════════════════════════════════════════════════════════════════
// Hierarchical Cash Management System
// ══════════════════════════════════════════════════════════════════════════════

// CashHolding represents real-time cash balance for each user
type CashHolding struct {
	TenantModel
	UserID         uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;uniqueIndex:idx_cash_holding_user_shop"`
	User           *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	ShopID         *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid;uniqueIndex:idx_cash_holding_user_shop"` // Shop is optional - cash is user-specific
	Shop           *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Role           string     `json:"role" gorm:"type:varchar(50);not null;default:'salesman'"`
	CurrentBalance float64    `json:"current_balance" gorm:"type:decimal(12,2);not null;default:0"`
	LastUpdatedAt  time.Time  `json:"last_updated_at" gorm:"not null"`
}

// CashCollection represents cash collection between users in hierarchy
type CashCollection struct {
	TenantModel
	FromUserID     uuid.UUID  `json:"from_user_id" gorm:"type:uuid;not null"` // Who gives cash
	FromUser       *User      `json:"from_user,omitempty" gorm:"foreignKey:FromUserID"`
	ToUserID       uuid.UUID  `json:"to_user_id" gorm:"type:uuid;not null"` // Who receives cash
	ToUser         *User      `json:"to_user,omitempty" gorm:"foreignKey:ToUserID"`
	ShopID         *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid"` // Shop is now optional
	Shop           *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Amount         float64   `json:"amount" gorm:"type:decimal(12,2);not null"`
	CollectionDate time.Time `json:"collection_date" gorm:"not null"`
	Notes          string    `json:"notes"`

	// Status and approval workflow
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, expired
	ExpiresAt    *time.Time `json:"expires_at"`                      // 10-minute deadline for approval
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	RejectedAt   *time.Time `json:"rejected_at"`
	RejectReason string     `json:"reject_reason"`

	// Created by (who initiated the collection)
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// CashSubmission represents cash submission to bank with denomination breakdown
type CashSubmission struct {
	TenantModel
	UserID uuid.UUID  `json:"user_id" gorm:"type:uuid;not null"` // Who is submitting
	User   *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	ShopID *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid"` // Shop is now optional
	Shop   *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	TotalAmount float64 `json:"total_amount" gorm:"type:decimal(12,2);not null"`

	// Denomination breakdown
	Notes500 int `json:"notes_500" gorm:"default:0"` // Count of ₹500 notes
	Notes200 int `json:"notes_200" gorm:"default:0"` // Count of ₹200 notes
	Notes100 int `json:"notes_100" gorm:"default:0"` // Count of ₹100 notes
	Notes50  int `json:"notes_50" gorm:"default:0"`  // Count of ₹50 notes
	Notes20  int `json:"notes_20" gorm:"default:0"`  // Count of ₹20 notes
	Notes10  int `json:"notes_10" gorm:"default:0"`  // Count of ₹10 notes

	// Bank deposit details
	BankAccountID   *uuid.UUID   `json:"bank_account_id" gorm:"type:uuid"`
	BankAccount     *BankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`
	BankSlipNumber  string       `json:"bank_slip_number"`
	DepositDate     time.Time    `json:"deposit_date" gorm:"not null"`
	ReceiptPhotoURL string       `json:"receipt_photo_url" gorm:"not null"` // Required evidence
	Notes           string       `json:"notes"`

	// Status and approval workflow
	Status          string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt      *time.Time `json:"approved_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy      *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	RejectionReason string     `json:"rejection_reason"`

	// Created by
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// CashTransaction represents complete audit trail for all cash movements
type CashTransaction struct {
	TenantModel
	UserID uuid.UUID  `json:"user_id" gorm:"type:uuid;not null"`
	User   *User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	ShopID *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid"` // Shop is optional - transactions can be user-specific
	Shop   *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	TransactionType string  `json:"transaction_type" gorm:"not null"` // sale, collection_received, collection_given, submission, adjustment
	Amount          float64 `json:"amount" gorm:"type:decimal(12,2);not null"`
	PreviousBalance float64 `json:"previous_balance" gorm:"column:balance_before;type:decimal(12,2);default:0"`
	NewBalance      float64 `json:"new_balance" gorm:"column:balance_after;type:decimal(12,2);default:0"`

	// Reference to related entity
	RelatedEntityType string      `json:"related_entity_type" gorm:"column:related_type"` // sale, collection, submission
	RelatedEntityID   *uuid.UUID  `json:"related_entity_id" gorm:"column:related_id;type:uuid"`
	Description       string      `json:"description"`
	TransactionDate   time.Time   `json:"transaction_date" gorm:"not null"`

	// Created by
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// CashRequest represents cash request from one user to another with approval workflow
type CashRequest struct {
	TenantModel
	RequesterID      uuid.UUID  `json:"requester_id" gorm:"type:uuid;not null"`       // Who is requesting cash
	Requester        *User      `json:"requester,omitempty" gorm:"foreignKey:RequesterID"`
	RequestedFromID  uuid.UUID  `json:"requested_from_id" gorm:"type:uuid;not null"`  // Who is being asked for cash
	RequestedFrom    *User      `json:"requested_from,omitempty" gorm:"foreignKey:RequestedFromID"`
	ShopID           *uuid.UUID `json:"shop_id,omitempty" gorm:"type:uuid"`            // Optional - cash is user-specific
	Shop             *Shop      `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Amount           float64   `json:"amount" gorm:"type:decimal(12,2);not null"`
	Reason           string    `json:"reason"`
	RequestDate      time.Time `json:"request_date" gorm:"not null"`

	// Status and approval workflow (10-minute deadline)
	Status       string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, expired
	ExpiresAt    *time.Time `json:"expires_at"`                      // 10-minute deadline for approval
	ApprovedAt   *time.Time `json:"approved_at"`
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	RejectedAt   *time.Time `json:"rejected_at"`
	RejectReason string     `json:"reject_reason"`

	// Created by (who initiated the request)
	CreatedByID   uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// ══════════════════════════════════════════════════════════════════════════════
// Tenant Bank Account Management System with OD Tracking
// ══════════════════════════════════════════════════════════════════════════════

// TenantBankAccount represents tenant bank accounts with overdraft management
type TenantBankAccount struct {
	TenantModel

	// Bank Account Details
	BankName          string `json:"bank_name" gorm:"not null"`
	AccountNumber     string `json:"account_number" gorm:"not null"`
	AccountHolderName string `json:"account_holder_name" gorm:"not null"`
	IFSCCode          string `json:"ifsc_code"`
	BranchName        string `json:"branch_name"`
	BranchAddress     string `json:"branch_address"`

	// Account Type and Status
	AccountType string `json:"account_type" gorm:"default:'current'"` // current, savings, od, cash_credit
	IsActive    bool   `json:"is_active" gorm:"default:true"`
	IsDefault   bool   `json:"is_default" gorm:"default:false"`

	// Balance Tracking
	CurrentBalance float64 `json:"current_balance" gorm:"type:decimal(15,2);default:0"`

	// Overdraft (OD) Management
	ODLimit       float64 `json:"od_limit" gorm:"type:decimal(15,2);default:0"`        // Maximum overdraft limit
	UsedODAmount  float64 `json:"used_od_amount" gorm:"type:decimal(15,2);default:0"`  // Currently used OD
	AvailableOD   float64 `json:"available_od" gorm:"<-:false;type:decimal(15,2)"`    // Computed: od_limit - used_od_amount (READ-ONLY GENERATED COLUMN)
	TotalAvailableBalance float64 `json:"total_available_balance" gorm:"<-:false;type:decimal(15,2)"` // Computed: current_balance + available_od (READ-ONLY GENERATED COLUMN)

	// Interest Rates
	ODInterestRate float64 `json:"od_interest_rate" gorm:"type:decimal(5,2);default:0"` // Annual interest rate for OD

	// Metadata
	Notes string `json:"notes"`

	// Created by
	CreatedBy   *uuid.UUID `json:"created_by,omitempty" gorm:"type:uuid"`
	CreatedUser *User      `json:"created_user,omitempty" gorm:"foreignKey:CreatedBy"`
	UpdatedBy   *uuid.UUID `json:"updated_by,omitempty" gorm:"type:uuid"`
	UpdatedUser *User      `json:"updated_user,omitempty" gorm:"foreignKey:UpdatedBy"`

	// Relationships
	Transactions     []TenantBankTransaction `json:"transactions,omitempty" gorm:"foreignKey:BankAccountID"`
	CashSubmissions  []CashSubmission        `json:"cash_submissions,omitempty" gorm:"foreignKey:BankAccountID"`
	Reconciliations  []BankReconciliation    `json:"reconciliations,omitempty" gorm:"foreignKey:BankAccountID"`
}

// TableName overrides the table name for TenantBankAccount
func (TenantBankAccount) TableName() string {
	return "tenant_bank_accounts"
}

// TenantBankTransaction represents all bank account transactions for audit trail
type TenantBankTransaction struct {
	TenantModel
	BankAccountID uuid.UUID          `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount   *TenantBankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`

	// Transaction Details
	TransactionType string  `json:"transaction_type" gorm:"not null"` // deposit, withdrawal, od_usage, od_repayment, interest_charge, bank_charges, adjustment
	Amount          float64 `json:"amount" gorm:"type:decimal(15,2);not null"`

	// Balance Snapshots
	BalanceBefore float64 `json:"balance_before" gorm:"type:decimal(15,2);not null"`
	BalanceAfter  float64 `json:"balance_after" gorm:"type:decimal(15,2);not null"`
	ODUsedBefore  float64 `json:"od_used_before" gorm:"type:decimal(15,2);default:0"`
	ODUsedAfter   float64 `json:"od_used_after" gorm:"type:decimal(15,2);default:0"`

	// Transaction References
	ReferenceType   string     `json:"reference_type"`   // cash_submission, manual_entry, bank_statement, etc.
	ReferenceID     *uuid.UUID `json:"reference_id" gorm:"type:uuid"`
	BankReferenceNo string     `json:"bank_reference_no"` // Bank slip number, transaction ID

	// Transaction Metadata
	TransactionDate time.Time `json:"transaction_date" gorm:"not null"`
	Description     string    `json:"description"`
	Notes           string    `json:"notes"`

	// Reconciliation
	IsReconciled     bool       `json:"is_reconciled" gorm:"default:false"`
	ReconciliationID *uuid.UUID `json:"reconciliation_id,omitempty" gorm:"type:uuid"`

	// Created by
	CreatedBy   *uuid.UUID `json:"created_by,omitempty" gorm:"type:uuid"`
	CreatedUser *User      `json:"created_user,omitempty" gorm:"foreignKey:CreatedBy"`
}

// TableName overrides the table name for TenantBankTransaction
func (TenantBankTransaction) TableName() string {
	return "bank_transactions"
}

// BankReconciliation represents bank reconciliation records
type BankReconciliation struct {
	TenantModel
	BankAccountID uuid.UUID          `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount   *TenantBankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`

	// Reconciliation Period
	ReconciliationDate time.Time `json:"reconciliation_date" gorm:"not null"`
	StatementStartDate time.Time `json:"statement_start_date" gorm:"not null"`
	StatementEndDate   time.Time `json:"statement_end_date" gorm:"not null"`

	// Balances
	SystemBalance        float64 `json:"system_balance" gorm:"type:decimal(15,2);not null"`
	BankStatementBalance float64 `json:"bank_statement_balance" gorm:"type:decimal(15,2);not null"`
	Difference           float64 `json:"difference" gorm:"type:decimal(15,2);default:0"` // Computed: bank_statement_balance - system_balance

	// Status
	Status string `json:"status" gorm:"default:'pending'"` // pending, in_progress, completed, discrepancy

	// Reconciliation Details
	TotalDeposits            float64 `json:"total_deposits" gorm:"type:decimal(15,2);default:0"`
	TotalWithdrawals         float64 `json:"total_withdrawals" gorm:"type:decimal(15,2);default:0"`
	UnreconciledDeposits     float64 `json:"unreconciled_deposits" gorm:"type:decimal(15,2);default:0"`
	UnreconciledWithdrawals  float64 `json:"unreconciled_withdrawals" gorm:"type:decimal(15,2);default:0"`

	// Notes and Resolution
	Notes           string `json:"notes"`
	ResolutionNotes string `json:"resolution_notes"`

	// Completion
	CompletedAt *time.Time `json:"completed_at,omitempty"`

	// Created by
	CreatedBy     *uuid.UUID `json:"created_by,omitempty" gorm:"type:uuid"`
	CreatedUser   *User      `json:"created_user,omitempty" gorm:"foreignKey:CreatedBy"`
	CompletedBy   *uuid.UUID `json:"completed_by,omitempty" gorm:"type:uuid"`
	CompletedUser *User      `json:"completed_user,omitempty" gorm:"foreignKey:CompletedBy"`
}

// TableName overrides the table name for BankReconciliation
func (BankReconciliation) TableName() string {
	return "bank_reconciliations"
}
