package models

import (
	"time"

	"github.com/google/uuid"
)

// Vendor represents suppliers/vendors
type Vendor struct {
	TenantModel
	Name            string `json:"name" gorm:"not null"`
	ContactPerson   string `json:"contact_person"`
	Phone           string `json:"phone"`
	Email           string `json:"email"`
	Address         string `json:"address"`
	City            string `json:"city"`
	State           string `json:"state"`
	Country         string `json:"country"`
	PostalCode      string `json:"postal_code"`
	TaxID           string `json:"tax_id"`
	GSTNumber       string `json:"gst_number"`
	PANNumber       string `json:"pan_number"`
	PaymentTerms    string `json:"payment_terms"`
	CreditLimit     float64 `json:"credit_limit" gorm:"default:0"`
	IsActive        bool   `json:"is_active" gorm:"default:true"`
	
	// Created by
	CreatedBy       uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser   *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	
	// Relationships
	BankAccounts    []VendorBankAccount `json:"bank_accounts,omitempty" gorm:"foreignKey:VendorID"`
	Transactions    []VendorTransaction `json:"transactions,omitempty" gorm:"foreignKey:VendorID"`
	Invoices        []VendorInvoice     `json:"invoices,omitempty" gorm:"foreignKey:VendorID"`
	StockPurchases  []StockPurchase     `json:"stock_purchases,omitempty" gorm:"foreignKey:VendorID"`
}

// VendorBankAccount represents vendor banking details
type VendorBankAccount struct {
	TenantModel
	VendorID        uuid.UUID `json:"vendor_id" gorm:"type:uuid;not null"`
	Vendor          *Vendor   `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	BankName        string    `json:"bank_name" gorm:"not null"`
	AccountNumber   string    `json:"account_number" gorm:"not null"`
	IFSCCode        string    `json:"ifsc_code" gorm:"not null"`
	AccountHolder   string    `json:"account_holder" gorm:"not null"`
	AccountHolderName string  `json:"account_holder_name" gorm:"not null"`
	BranchCode      string    `json:"branch_code"`
	SwiftCode       string    `json:"swift_code"`
	IsPrimary       bool      `json:"is_primary" gorm:"default:false"`
	IsDefault       bool      `json:"is_default" gorm:"default:false"`
	
	// Created by
	CreatedBy       uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser   *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
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
	CreatedBy       uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser   *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
}

// VendorInvoice represents vendor invoices/bills
type VendorInvoice struct {
	TenantModel
	InvoiceNumber   string    `json:"invoice_number" gorm:"not null"`
	VendorID        uuid.UUID `json:"vendor_id" gorm:"type:uuid;not null"`
	Vendor          *Vendor   `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	InvoiceDate     time.Time `json:"invoice_date" gorm:"not null"`
	DueDate         time.Time `json:"due_date" gorm:"not null"`
	
	SubTotal        float64 `json:"sub_total" gorm:"not null"`
	TaxAmount       float64 `json:"tax_amount" gorm:"default:0"`
	TotalAmount     float64 `json:"total_amount" gorm:"not null"`
	PaidAmount      float64 `json:"paid_amount" gorm:"default:0"`
	DueAmount       float64 `json:"due_amount" gorm:"not null"`
	
	Status          string `json:"status" gorm:"default:'pending'"` // pending, partial, paid, overdue
	
	// Relationships
	Transactions    []VendorInvoiceTransaction `json:"transactions,omitempty" gorm:"foreignKey:VendorInvoiceID"`
}

// VendorInvoiceTransaction represents payments against vendor invoices
type VendorInvoiceTransaction struct {
	TenantModel
	VendorInvoiceID uuid.UUID      `json:"vendor_invoice_id" gorm:"type:uuid;not null"`
	VendorInvoice   *VendorInvoice `json:"vendor_invoice,omitempty" gorm:"foreignKey:VendorInvoiceID"`
	
	Amount          float64   `json:"amount" gorm:"not null"`
	PaymentMethod   string    `json:"payment_method" gorm:"not null"`
	PaymentDate     time.Time `json:"payment_date" gorm:"not null"`
	Reference       string    `json:"reference"`
	Notes           string    `json:"notes"`
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
	Transactions      []BankTransaction `json:"transactions,omitempty" gorm:"foreignKey:BankAccountID"`
	CashDeposits      []CashDeposit     `json:"cash_deposits,omitempty" gorm:"foreignKey:BankAccountID"`
}

// BankTransaction represents bank account transactions
type BankTransaction struct {
	TenantModel
	BankAccountID   uuid.UUID    `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount     *BankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`
	
	TransactionType string    `json:"transaction_type" gorm:"not null"` // credit, debit
	Amount          float64   `json:"amount" gorm:"not null"`
	TransactionDate time.Time `json:"transaction_date" gorm:"not null"`
	Description     string    `json:"description" gorm:"not null"`
	Reference       string    `json:"reference"`
	
	PreviousBalance float64 `json:"previous_balance"`
	NewBalance      float64 `json:"new_balance"`
	
	// Created by
	CreatedByID     uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy       *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// CashDeposit represents cash deposits to bank accounts
type CashDeposit struct {
	TenantModel
	BankAccountID   uuid.UUID    `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount     *BankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`
	ShopID          uuid.UUID    `json:"shop_id" gorm:"type:uuid;not null"`
	Shop            *Shop        `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	
	Amount          float64   `json:"amount" gorm:"not null"`
	DepositDate     time.Time `json:"deposit_date" gorm:"not null"`
	SlipNumber      string    `json:"slip_number"`
	Notes           string    `json:"notes"`
	
	// Status and approval
	Status          string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt      *time.Time `json:"approved_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy      *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedByID     uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy       *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// ExecutiveFinance represents executive financial records
type ExecutiveFinance struct {
	TenantModel
	ExecutiveID     uuid.UUID `json:"executive_id" gorm:"type:uuid;not null"`
	Executive       *User     `json:"executive,omitempty" gorm:"foreignKey:ExecutiveID"`
	
	RecordDate      time.Time `json:"record_date" gorm:"not null"`
	TotalAmount     float64   `json:"total_amount" gorm:"not null"`
	Description     string    `json:"description"`
	
	// Status and approval
	Status          string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt      *time.Time `json:"approved_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy      *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedByID     uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy       *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// Expense represents general business expenses
type Expense struct {
	TenantModel
	CategoryID      *uuid.UUID       `json:"category_id" gorm:"type:uuid"`
	Category        *ExpenseCategory `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	ShopID          *uuid.UUID       `json:"shop_id" gorm:"type:uuid"`
	Shop            *Shop            `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	VendorID        *uuid.UUID       `json:"vendor_id" gorm:"type:uuid"`
	Vendor          *Vendor          `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	
	ExpenseDate     time.Time `json:"expense_date" gorm:"not null"`
	Description     string    `json:"description" gorm:"not null"`
	Amount          float64   `json:"amount" gorm:"not null"`
	PaymentMethod   string    `json:"payment_method" gorm:"not null"`
	Notes           string    `json:"notes"`
	
	// Receipt/bill details
	ReceiptNo       string `json:"receipt_no"`
	BillNumber      string `json:"bill_number"`
	VendorName      string `json:"vendor_name"`
	
	// Status and approval
	Status          string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt      *time.Time `json:"approved_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy      *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedBy       *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	CreatedByID     uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
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
	
	CollectionDate     time.Time `json:"collection_date" gorm:"not null"`
	Amount             float64   `json:"amount" gorm:"not null"`
	CollectionType     string    `json:"collection_type" gorm:"not null"` // daily_sales, credit_recovery, other
	Description        string    `json:"description"`
	Notes              string    `json:"notes"`
	
	// 15-minute approval deadline
	CollectedAt        time.Time  `json:"collected_at" gorm:"not null"`
	SubmittedAt        time.Time  `json:"submitted_at" gorm:"not null"`
	DeadlineAt         time.Time  `json:"deadline_at" gorm:"not null"` // submitted_at + 15 minutes
	ApprovalDeadline   time.Time  `json:"approval_deadline" gorm:"not null"` // submitted_at + 15 minutes
	
	// Status and approval
	Status             string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, expired
	ApprovedAt         *time.Time `json:"approved_at"`
	ApprovedByID       *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy         *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedByUser     *User      `json:"approved_by_user,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedBy          uuid.UUID  `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser      *User      `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	
	RejectionReason    string `json:"rejection_reason"`
	
	// Relationships
	BankDeposits       []BankDeposit       `json:"bank_deposits,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	StockVerifications []StockVerification `json:"stock_verifications,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	LedgerEntries      []AssistantManagerLedger `json:"ledger_entries,omitempty" gorm:"foreignKey:MoneyCollectionID"`
}

// BankDeposit represents bank deposits made by assistant managers
type BankDeposit struct {
	TenantModel
	MoneyCollectionID  *uuid.UUID      `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection    *MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	BankAccountID      uuid.UUID       `json:"bank_account_id" gorm:"type:uuid;not null"`
	BankAccount        *BankAccount    `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`
	
	DepositDate        time.Time `json:"deposit_date" gorm:"not null"`
	Amount             float64   `json:"amount" gorm:"not null"`
	SlipNumber         string    `json:"slip_number"`
	
	// Status and approval
	Status             string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt         *time.Time `json:"approved_at"`
	ApprovedByID       *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy         *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedByID        uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy          *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// StockVerification represents stock verification by assistant managers
type StockVerification struct {
	TenantModel
	MoneyCollectionID  *uuid.UUID      `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection    *MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	ShopID             uuid.UUID       `json:"shop_id" gorm:"type:uuid;not null"`
	Shop               *Shop           `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	
	VerificationDate   time.Time `json:"verification_date" gorm:"not null"`
	TotalStockValue    float64   `json:"total_stock_value" gorm:"not null"`
	DiscrepancyAmount  float64   `json:"discrepancy_amount" gorm:"default:0"`
	Notes              string    `json:"notes"`
	
	// Status and approval
	Status             string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt         *time.Time `json:"approved_at"`
	ApprovedByID       *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy         *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedByID        uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy          *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
	
	// Relationships
	Items              []StockVerificationItem `json:"items,omitempty" gorm:"foreignKey:StockVerificationID"`
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
	AssistantManagerID uuid.UUID `json:"assistant_manager_id" gorm:"type:uuid;not null"`
	AssistantManager   *User     `json:"assistant_manager,omitempty" gorm:"foreignKey:AssistantManagerID"`
	MoneyCollectionID  *uuid.UUID `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection    *MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	
	TransactionDate    time.Time `json:"transaction_date" gorm:"not null"`
	TransactionType    string    `json:"transaction_type" gorm:"not null"` // collection, deposit, verification, adjustment
	Amount             float64   `json:"amount" gorm:"not null"`
	Description        string    `json:"description" gorm:"not null"`
	Reference          string    `json:"reference"`
	
	// Running balance
	PreviousBalance    float64 `json:"previous_balance"`
	NewBalance         float64 `json:"new_balance"`
	
	// Created by
	CreatedByID        uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy          *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// AssistantManagerMoneyCollection alias for MoneyCollection (for backward compatibility)
type AssistantManagerMoneyCollection = MoneyCollection

// AssistantManagerExpense represents expenses made by assistant managers
type AssistantManagerExpense struct {
	TenantModel
	CategoryID         uuid.UUID `json:"category_id" gorm:"type:uuid;not null"`
	Category           *ExpenseCategory `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	AssistantManagerID uuid.UUID `json:"assistant_manager_id" gorm:"type:uuid;not null"`
	AssistantManager   *User     `json:"assistant_manager,omitempty" gorm:"foreignKey:AssistantManagerID"`
	ShopID             uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop               *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	
	ExpenseDate        time.Time `json:"expense_date" gorm:"not null"`
	Description        string    `json:"description" gorm:"not null"`
	Amount             float64   `json:"amount" gorm:"not null"`
	PaymentMethod      string    `json:"payment_method" gorm:"not null"`
	Notes              string    `json:"notes"`
	
	// Receipt/bill details
	ReceiptNo          string `json:"receipt_no"`
	BillNumber         string `json:"bill_number"`
	VendorName         string `json:"vendor_name"`
	
	// Status and approval
	Status             string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt         *time.Time `json:"approved_at"`
	ApprovedByID       *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy         *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedBy          uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByID        uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser      *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
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
	Status             string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt         *time.Time `json:"approved_at"`
	ApprovedByID       *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy         *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	
	// Created by
	CreatedBy          uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByID        uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedByUser      *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedByID"`
}

// ExpenseCategory represents expense categories
type ExpenseCategory struct {
	TenantModel
	Name        string `json:"name" gorm:"not null"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active" gorm:"default:true"`
	
	// Created by
	CreatedBy   uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User   `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	
	// Relationships
	Expenses []Expense                  `json:"expenses,omitempty" gorm:"foreignKey:CategoryID"`
	AssistantManagerExpenses []AssistantManagerExpense `json:"assistant_manager_expenses,omitempty" gorm:"foreignKey:CategoryID"`
}