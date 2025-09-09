package models

import (
	"time"

	"github.com/google/uuid"
)

// Category represents product categories (Wine, Beer, Whiskey, etc.)
type Category struct {
	TenantModel
	Name        string `json:"name" gorm:"not null"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active" gorm:"default:true"`
	
	// Relationships
	Products []Product `json:"products,omitempty" gorm:"foreignKey:CategoryID"`
}

// Brand represents liquor brands
type Brand struct {
	TenantModel
	Name        string `json:"name" gorm:"not null"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active" gorm:"default:true"`
	
	// Relationships
	Products     []Product     `json:"products,omitempty" gorm:"foreignKey:BrandID"`
	BrandPricing []BrandPricing `json:"brand_pricing,omitempty" gorm:"foreignKey:BrandID"`
}

// Product represents liquor products
type Product struct {
	TenantModel
	Name         string    `json:"name" gorm:"not null"`
	CategoryID   uuid.UUID `json:"category_id" gorm:"type:uuid;not null"`
	Category     *Category `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	BrandID      uuid.UUID `json:"brand_id" gorm:"type:uuid;not null"`
	Brand        *Brand    `json:"brand,omitempty" gorm:"foreignKey:BrandID"`
	Size         string    `json:"size"` // e.g., "750ml", "1L"
	AlcoholContent float64 `json:"alcohol_content"`
	Description  string    `json:"description"`
	Barcode      string    `json:"barcode"`
	SKU          string    `json:"sku" gorm:"unique"`
	IsActive     bool      `json:"is_active" gorm:"default:true"`
	
	// Pricing
	CostPrice   float64 `json:"cost_price"`
	SellingPrice float64 `json:"selling_price"`
	MRP         float64 `json:"mrp"`
	
	// Relationships
	Stocks           []Stock           `json:"stocks,omitempty" gorm:"foreignKey:ProductID"`
	StockBatches     []StockBatch      `json:"stock_batches,omitempty" gorm:"foreignKey:ProductID"`
	SaleItems        []SaleItem        `json:"sale_items,omitempty" gorm:"foreignKey:ProductID"`
	DailySalesItems  []DailySalesItem  `json:"daily_sales_items,omitempty" gorm:"foreignKey:ProductID"`
	StockPurchaseItems []StockPurchaseItem `json:"stock_purchase_items,omitempty" gorm:"foreignKey:ProductID"`
}

// BrandPricing represents pricing for specific brand and size combinations
type BrandPricing struct {
	TenantModel
	BrandID      uuid.UUID `json:"brand_id" gorm:"type:uuid;not null"`
	Brand        *Brand    `json:"brand,omitempty" gorm:"foreignKey:BrandID"`
	Size         string    `json:"size" gorm:"not null"`
	CostPrice    float64   `json:"cost_price"`
	SellingPrice float64   `json:"selling_price"`
	MRP          float64   `json:"mrp"`
}

// Stock represents current inventory levels per shop
type Stock struct {
	TenantModel
	ShopID      uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop        *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	ProductID   uuid.UUID `json:"product_id" gorm:"type:uuid;not null"`
	Product     *Product  `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	
	Quantity         int     `json:"quantity" gorm:"default:0"`
	ReservedQuantity int     `json:"reserved_quantity" gorm:"default:0"`
	MinimumLevel     int     `json:"minimum_level" gorm:"default:0"`
	MaximumLevel     int     `json:"maximum_level" gorm:"default:0"`
	
	// Costing
	CostingMethod        string    `json:"costing_method" gorm:"default:'fifo'"`
	AverageCost          float64   `json:"average_cost"`
	LastPurchasePrice    float64   `json:"last_purchase_price"`
	LastPurchaseDate     *time.Time `json:"last_purchase_date"`
	
	// Financial accounting
	FinancialAccountCode string    `json:"financial_account_code"`
	LastReconciled       *time.Time `json:"last_reconciled"`
	
	// Relationships
	StockBatches []StockBatch  `json:"stock_batches,omitempty" gorm:"foreignKey:StockID"`
	StockHistory []StockHistory `json:"stock_history,omitempty" gorm:"foreignKey:StockID"`
}

// StockBatch represents individual batches of stock with batch-specific details
type StockBatch struct {
	TenantModel
	StockID       uuid.UUID `json:"stock_id" gorm:"type:uuid;not null"`
	Stock         *Stock    `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	ProductID     uuid.UUID `json:"product_id" gorm:"type:uuid;not null"`
	Product       *Product  `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	
	BatchNumber   string    `json:"batch_number" gorm:"not null"`
	Quantity      int       `json:"quantity" gorm:"not null"`
	CostPrice     float64   `json:"cost_price" gorm:"not null"`
	SellingPrice  float64   `json:"selling_price" gorm:"not null"`
	
	ManufactureDate *time.Time `json:"manufacture_date"`
	ExpiryDate      *time.Time `json:"expiry_date"`
	PurchaseDate    time.Time  `json:"purchase_date" gorm:"not null"`
	
	SupplierID      *uuid.UUID `json:"supplier_id" gorm:"type:uuid"`
	Supplier        *Vendor    `json:"supplier,omitempty" gorm:"foreignKey:SupplierID"`
	
	// Purchase reference
	StockPurchaseID *uuid.UUID     `json:"stock_purchase_id" gorm:"type:uuid"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`
}

// StockHistory tracks all stock movements for audit purposes
type StockHistory struct {
	TenantModel
	StockID         uuid.UUID `json:"stock_id" gorm:"type:uuid;not null"`
	Stock           *Stock    `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	MovementType    string    `json:"movement_type" gorm:"not null"` // purchase, sale, adjustment, transfer
	Quantity        int       `json:"quantity" gorm:"not null"`
	PreviousQuantity int      `json:"previous_quantity" gorm:"not null"`
	NewQuantity     int       `json:"new_quantity" gorm:"not null"`
	UnitCost        float64   `json:"unit_cost"`
	TotalCost       float64   `json:"total_cost"`
	Reference       string    `json:"reference"` // Reference to sale, purchase, etc.
	ReferenceID     *uuid.UUID `json:"reference_id" gorm:"type:uuid"`
	Notes           string    `json:"notes"`
	
	// User who made the change
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`
}

// StockPurchase represents purchase orders/receipts
type StockPurchase struct {
	TenantModel
	PurchaseNumber string    `json:"purchase_number" gorm:"unique;not null"`
	VendorID       uuid.UUID `json:"vendor_id" gorm:"type:uuid;not null"`
	Vendor         *Vendor   `json:"vendor,omitempty" gorm:"foreignKey:VendorID"`
	ShopID         uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop           *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	PurchaseDate   time.Time `json:"purchase_date" gorm:"not null"`
	
	SubTotal    float64 `json:"sub_total" gorm:"not null"`
	TaxAmount   float64 `json:"tax_amount" gorm:"default:0"`
	TotalAmount float64 `json:"total_amount" gorm:"not null"`
	
	Status      string `json:"status" gorm:"default:'pending'"` // pending, received, cancelled
	ReceivedAt  *time.Time `json:"received_at"`
	
	Notes       string `json:"notes"`
	ReceiptNo   string `json:"receipt_no"`
	
	// Created by
	CreatedBy   uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User   `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	
	// Relationships
	Items    []StockPurchaseItem    `json:"items,omitempty" gorm:"foreignKey:StockPurchaseID"`
	Payments []StockPurchasePayment `json:"payments,omitempty" gorm:"foreignKey:StockPurchaseID"`
}

// StockPurchaseItem represents individual items in a purchase order
type StockPurchaseItem struct {
	TenantModel
	StockPurchaseID uuid.UUID      `json:"stock_purchase_id" gorm:"type:uuid;not null"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`
	ProductID       uuid.UUID      `json:"product_id" gorm:"type:uuid;not null"`
	Product         *Product       `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	
	Quantity        int     `json:"quantity" gorm:"not null"`
	UnitCost        float64 `json:"unit_cost" gorm:"not null"`
	TotalCost       float64 `json:"total_cost" gorm:"not null"`
	TotalPrice      float64 `json:"total_price" gorm:"not null"`
	
	BatchNumber     string     `json:"batch_number"`
	ManufactureDate *time.Time `json:"manufacture_date"`
	ExpiryDate      *time.Time `json:"expiry_date"`
}

// StockPurchasePayment represents payments made for stock purchases
type StockPurchasePayment struct {
	TenantModel
	StockPurchaseID uuid.UUID      `json:"stock_purchase_id" gorm:"type:uuid;not null"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`
	
	Amount        float64   `json:"amount" gorm:"not null"`
	Method        string    `json:"method" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	PaymentDate   time.Time `json:"payment_date" gorm:"not null"`
	Reference     string    `json:"reference"`
	Notes         string    `json:"notes"`
}

// StockMovement represents stock movements for tracking
type StockMovement struct {
	TenantModel
	StockID      uuid.UUID `json:"stock_id" gorm:"type:uuid;not null"`
	Stock        *Stock    `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	MovementType string    `json:"movement_type" gorm:"not null"` // in, out, adjustment
	Quantity     int       `json:"quantity" gorm:"not null"`
	Reference    string    `json:"reference"`
	ReferenceID  *uuid.UUID `json:"reference_id" gorm:"type:uuid"`
	Notes        string    `json:"notes"`
}