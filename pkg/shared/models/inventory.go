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
	SortOrder   int    `json:"sort_order" gorm:"default:0"`

	// Relationships
	Products      []Product     `json:"products,omitempty" gorm:"foreignKey:CategoryID"`
	Subcategories []Subcategory `json:"subcategories,omitempty" gorm:"foreignKey:CategoryID"`
}

// Subcategory represents product subcategories (Premium, Ultra Premium, Normal, Basic)
type Subcategory struct {
	TenantModel
	Name        string    `json:"name" gorm:"not null"`
	CategoryID  uuid.UUID `json:"category_id" gorm:"type:uuid;not null"`
	Category    *Category `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	PriceRange  string    `json:"price_range"` // Premium, Ultra Premium, Normal, Basic
	Description string    `json:"description"`
	SortOrder   int       `json:"sort_order" gorm:"default:0"`
	IsActive    bool      `json:"is_active" gorm:"default:true"`

	// Relationships
	Products         []Product         `json:"products,omitempty" gorm:"foreignKey:SubcategoryID"`
	ProductTemplates []ProductTemplate `json:"product_templates,omitempty" gorm:"foreignKey:SubcategoryID"`
}

// Brand represents liquor brands
type Brand struct {
	TenantModel
	Name        string `json:"name" gorm:"not null"`
	Description string `json:"description"`
	IsActive    bool   `json:"is_active" gorm:"default:true"`

	// Relationships
	Products     []Product      `json:"products,omitempty" gorm:"foreignKey:BrandID"`
	BrandPricing []BrandPricing `json:"brand_pricing,omitempty" gorm:"foreignKey:BrandID"`
}

// ProductTemplate represents predefined product templates with images
type ProductTemplate struct {
	BaseModel
	Name           string       `json:"name" gorm:"not null"`
	CategoryID     uuid.UUID    `json:"category_id" gorm:"type:uuid;not null"`
	Category       *Category    `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	SubcategoryID  *uuid.UUID   `json:"subcategory_id" gorm:"type:uuid"`
	Subcategory    *Subcategory `json:"subcategory,omitempty" gorm:"foreignKey:SubcategoryID"`
	BrandID        *uuid.UUID   `json:"brand_id" gorm:"type:uuid"`
	Brand          *Brand       `json:"brand,omitempty" gorm:"foreignKey:BrandID"`
	ImageURL       string       `json:"image_url"`
	Sizes          string       `json:"sizes" gorm:"type:text"` // JSON array of size options
	DutyFeeRate    float64      `json:"duty_fee_rate" gorm:"default:0"`
	IsStandard     bool         `json:"is_standard" gorm:"default:true"`
	Description    string       `json:"description"`
	AlcoholContent float64      `json:"alcohol_content"`
	IsActive       bool         `json:"is_active" gorm:"default:true"`
	SortOrder      int          `json:"sort_order" gorm:"default:0"`
}

// Product represents liquor products
type Product struct {
	TenantModel
	Name          string           `json:"name" gorm:"not null"`
	CategoryID    uuid.UUID        `json:"category_id" gorm:"type:uuid;not null"`
	Category      *Category        `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	SubcategoryID *uuid.UUID       `json:"subcategory_id" gorm:"type:uuid"`
	Subcategory   *Subcategory     `json:"subcategory,omitempty" gorm:"foreignKey:SubcategoryID"`
	BrandID       uuid.UUID        `json:"brand_id" gorm:"type:uuid;not null"`
	Brand         *Brand           `json:"brand,omitempty" gorm:"foreignKey:BrandID"`
	TemplateID    *uuid.UUID       `json:"template_id" gorm:"type:uuid"`
	Template      *ProductTemplate `json:"template,omitempty" gorm:"foreignKey:TemplateID"`

	// SaaS Brand Tracking - for duplicate prevention
	SaaSBrandID   *uuid.UUID `json:"saas_brand_id" gorm:"column:saas_brand_id;type:uuid"`
	SaaSVariantID *uuid.UUID `json:"saas_variant_id" gorm:"column:saas_variant_id;type:uuid;index:idx_products_tenant_saas_variant_unique,unique,where:saas_variant_id IS NOT NULL"`

	Size           string  `json:"size"` // e.g., "750ml", "1L"
	AlcoholContent float64 `json:"alcohol_content"`
	Description    string  `json:"description"`
	Barcode        string  `json:"barcode"`
	SKU            string  `json:"sku" gorm:"unique"`
	ImageURL       string  `json:"image_url"`
	IsActive       bool    `json:"is_active" gorm:"default:true"`

	// Enhanced Pricing with Duty Fees
	CostPrice    float64 `json:"cost_price"`
	DutyFee      float64 `json:"duty_fee" gorm:"default:0"`
	TotalCost    float64 `json:"total_cost"` // CostPrice + DutyFee
	SellingPrice float64 `json:"selling_price"`
	MRP          float64 `json:"mrp"`

	// Relationships
	Stocks             []Stock             `json:"stocks,omitempty" gorm:"foreignKey:ProductID"`
	StockBatches       []StockBatch        `json:"stock_batches,omitempty" gorm:"foreignKey:ProductID"`
	SaleItems          []SaleItem          `json:"sale_items,omitempty" gorm:"foreignKey:ProductID"`
	DailySalesItems    []DailySalesItem    `json:"daily_sales_items,omitempty" gorm:"foreignKey:ProductID"`
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
	ShopID    uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop      *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	ProductID uuid.UUID `json:"product_id" gorm:"type:uuid;not null"`
	Product   *Product  `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	Quantity          int `json:"quantity" gorm:"default:0"`
	DamagedQuantity   int `json:"damaged_quantity" gorm:"default:0"`
	ReservedQuantity  int `json:"reserved_quantity" gorm:"default:0"`
	AvailableQuantity int `json:"available_quantity" gorm:"default:0"`
	MinimumLevel      int `json:"minimum_level" gorm:"default:0"`
	MaximumLevel      int `json:"maximum_level" gorm:"default:0"`

	// Costing
	CostingMethod     string     `json:"costing_method" gorm:"default:'fifo'"`
	AverageCost       float64    `json:"average_cost"`
	LastPurchasePrice float64    `json:"last_purchase_price"`
	LastPurchaseDate  *time.Time `json:"last_purchase_date"`

	// Financial accounting
	FinancialAccountCode string     `json:"financial_account_code"`
	LastReconciled       *time.Time `json:"last_reconciled"`

	// Relationships
	StockBatches []StockBatch   `json:"stock_batches,omitempty" gorm:"foreignKey:StockID"`
	StockHistory []StockHistory `json:"stock_history,omitempty" gorm:"foreignKey:StockID"`
}

// UpdateAvailableQuantity recalculates available quantity based on current stock levels
func (s *Stock) UpdateAvailableQuantity() {
	s.AvailableQuantity = s.Quantity - s.ReservedQuantity - s.DamagedQuantity
}

// StockBatch represents individual batches of stock with batch-specific details
type StockBatch struct {
	TenantModel
	StockID   uuid.UUID `json:"stock_id" gorm:"type:uuid;not null"`
	Stock     *Stock    `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	ProductID uuid.UUID `json:"product_id" gorm:"type:uuid;not null"`
	Product   *Product  `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	BatchNumber  string  `json:"batch_number" gorm:"not null"`
	Quantity     int     `json:"quantity" gorm:"not null"`
	CostPrice    float64 `json:"cost_price" gorm:"not null"`
	SellingPrice float64 `json:"selling_price" gorm:"not null"`

	ManufactureDate *time.Time `json:"manufacture_date"`
	ExpiryDate      *time.Time `json:"expiry_date"`
	PurchaseDate    time.Time  `json:"purchase_date" gorm:"not null"`

	SupplierID *uuid.UUID `json:"supplier_id" gorm:"type:uuid"`
	Supplier   *Vendor    `json:"supplier,omitempty" gorm:"foreignKey:SupplierID"`

	// Purchase reference
	StockPurchaseID *uuid.UUID     `json:"stock_purchase_id" gorm:"type:uuid"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`
}

// StockHistory tracks all stock movements for audit purposes
type StockHistory struct {
	TenantModel
	StockID          uuid.UUID  `json:"stock_id" gorm:"type:uuid;not null"`
	Stock            *Stock     `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	MovementType     string     `json:"movement_type" gorm:"not null"` // purchase, sale, adjustment, transfer
	Quantity         int        `json:"quantity" gorm:"not null"`
	PreviousQuantity int        `json:"previous_quantity" gorm:"not null"`
	NewQuantity      int        `json:"new_quantity" gorm:"not null"`
	UnitCost         float64    `json:"unit_cost"`
	TotalCost        float64    `json:"total_cost"`
	Reference        string     `json:"reference"` // Reference to sale, purchase, etc.
	ReferenceID      *uuid.UUID `json:"reference_id" gorm:"type:uuid"`
	Notes            string     `json:"notes"`

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
	RoundOff    float64 `json:"round_off" gorm:"default:0"`
	TotalAmount float64 `json:"total_amount" gorm:"not null"`

	Status     string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected, received
	ReceivedAt *time.Time `json:"received_at"`

	Notes     string `json:"notes"`
	ReceiptNo string `json:"receipt_no"`

	// Receipt/Invoice Information
	ReceiptNumber   *string    `json:"receipt_number" gorm:"type:varchar(100)"`
	ReceiptDate     *time.Time `json:"receipt_date"`
	ReceiptImageURL *string    `json:"receipt_image_url" gorm:"type:text"`
	ReceiptNotes    *string    `json:"receipt_notes" gorm:"type:text"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	CreatedByRole string    `json:"created_by_role"` // Role at time of creation

	// Approval workflow
	SubmittedAt     time.Time  `json:"submitted_at" gorm:"not null"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy      *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedAt      *time.Time `json:"approved_at"`
	RejectionReason string     `json:"rejection_reason"`

	// Relationships
	Items    []StockPurchaseItem    `json:"items,omitempty" gorm:"foreignKey:StockPurchaseID"`
	Payments []StockPurchasePayment `json:"payments,omitempty" gorm:"foreignKey:StockPurchaseID"`
}

// StockPurchaseItem represents individual items in a purchase order
type StockPurchaseItem struct {
	TenantModel
	StockPurchaseID uuid.UUID      `json:"stock_purchase_id" gorm:"column:purchase_id;type:uuid;not null"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`
	ProductID       uuid.UUID      `json:"product_id" gorm:"type:uuid;not null"`
	Product         *Product       `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	Quantity   int     `json:"quantity" gorm:"not null"`
	UnitCost   float64 `json:"unit_cost" gorm:"column:unit_price;not null"`
	TotalCost  float64 `json:"total_cost" gorm:"column:total_price;not null"`
	TotalPrice float64 `json:"total_price" gorm:"-"`

	BatchNumber string     `json:"batch_number"`
	ExpiryDate  *time.Time `json:"expiry_date"`
}

// StockPurchasePayment represents payments made for stock purchases
type StockPurchasePayment struct {
	TenantModel
	StockPurchaseID uuid.UUID      `json:"stock_purchase_id" gorm:"column:purchase_id;type:uuid;not null"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`

	Amount          float64   `json:"amount" gorm:"not null"`
	Method          string    `json:"method" gorm:"column:payment_method"`
	PaymentMethod   string    `json:"payment_method" gorm:"column:payment_method"`
	PaymentDate     time.Time `json:"payment_date"`
	Reference       string    `json:"reference" gorm:"column:reference_number"`
	ReferenceNumber string    `json:"reference_number" gorm:"column:reference_number;-"`
	Notes           string    `json:"notes"`
}

// StockMovement represents stock movements for tracking
type StockMovement struct {
	TenantModel
	StockID      uuid.UUID  `json:"stock_id" gorm:"type:uuid;not null"`
	Stock        *Stock     `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	MovementType string     `json:"movement_type" gorm:"not null"` // in, out, adjustment
	Quantity     int        `json:"quantity" gorm:"not null"`
	Reference    string     `json:"reference"`
	ReferenceID  *uuid.UUID `json:"reference_id" gorm:"type:uuid"`
	Notes        string     `json:"notes"`
}

// StockPurchaseDraft represents auto-saved stock purchase data per user per shop
type StockPurchaseDraft struct {
	TenantModel
	ShopID        uuid.UUID  `json:"shop_id" gorm:"type:uuid;not null;index"`
	UserID        uuid.UUID  `json:"user_id" gorm:"type:uuid;not null;index"`
	ShopName      string     `json:"shop_name"`
	DraftData     string     `json:"draft_data" gorm:"type:jsonb;default:'{}'"` // JSON items array
	VendorID      *uuid.UUID `json:"vendor_id" gorm:"type:uuid"`
	ReceiptURL    *string    `json:"receipt_url"`
	ReceiptNumber *string    `json:"receipt_number"`
	ReceiptDate   *time.Time `json:"receipt_date"`
	TotalAmount   float64    `json:"total_amount" gorm:"default:0"`
	ItemCount     int        `json:"item_count" gorm:"default:0"`
	DeviceID      string     `json:"device_id"`
	Version       int        `json:"version" gorm:"default:1"`
}

// TableName specifies the table name for StockPurchaseDraft
func (StockPurchaseDraft) TableName() string {
	return "stock_purchase_drafts"
}
