package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/datatypes"
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
	// ShopID scopes the product to a specific shop. NULL = tenant-wide (legacy shared
	// product visible to all shops in the tenant). Shop-scoping is "opt-in": new products
	// are created per-shop when shop_id is passed, old products with shop_id NULL remain
	// visible across the tenant.
	ShopID        *uuid.UUID       `json:"shop_id,omitempty" gorm:"column:shop_id;type:uuid"`
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
	// v1.0.123 MRP-change audit. Surfaced on Smart Sale review + inventory
	// product cards for 7 days after a change so the whole tenant can see
	// who changed the price (transparency / anti-scam). Auto-stops surfacing
	// after 7 days but the audit record stays so reports can reconstruct
	// price history. Updated on every code path that writes products.mrp:
	// Stock Setup Apply/Approve, Smart Sale Apply, web-admin product edit.
	// v1.0.132 — explicit gorm:"column:..." tags. Without them, GORM's default
	// naming strategy mangles `LastMRPChangeAt` → `last_m_rpchange_at` (it
	// splits the `MRP` acronym wrong against the following `Change` word).
	// The actual DB columns are `last_mrp_change_at` etc., so every Product
	// INSERT/UPDATE since v1.0.123 produced SQLSTATE 42703 ("column does not
	// exist") and aborted the surrounding transaction (SQLSTATE 25P02). That
	// silently broke Stock-Setup Apply for any setup containing an
	// auto-created (new-brand) row — the wrapping savepoint at L4582 sits
	// AFTER the failing product CREATE, so the abort poisons the txn and the
	// `stock_setup_records` insert that follows is dropped, leaving the user
	// with a 200 OK and no record on the web portal.
	LastMRPChangeAt       *time.Time `json:"last_mrp_change_at,omitempty" gorm:"column:last_mrp_change_at"`
	LastMRPChangeByID     *uuid.UUID `json:"last_mrp_change_by_id,omitempty" gorm:"type:uuid;column:last_mrp_change_by_id"`
	LastMRPChangeByName   string     `json:"last_mrp_change_by_name,omitempty" gorm:"column:last_mrp_change_by_name"`
	LastMRPChangePrevious float64    `json:"last_mrp_change_previous,omitempty" gorm:"column:last_mrp_change_previous"`
	DisplayName           string     `json:"display_name" gorm:"column:display_name"`
	// DisplayNameBoldStart + DisplayNameBoldLength jointly define an arbitrary
	// character range [Start, Start+Length) inside DisplayName that renders
	// big/bold; the rest renders small/normal. Start NULL or 0 with Length > 0
	// = prefix bold (the original behaviour). Length NULL or 0 = no styling.
	DisplayNameBoldStart  *int `json:"display_name_bold_start,omitempty" gorm:"column:display_name_bold_start"`
	DisplayNameBoldLength *int `json:"display_name_bold_length,omitempty" gorm:"column:display_name_bold_length"`

	// v1.0.250 — Per-product Front + Back photo verification. Photos uploaded
	// via Stock Setup are now persisted onto the product itself so the same
	// images appear everywhere the product is shown: inventory list, Manual
	// Purchase picker, product edit, Smart Sale. Mirrors the StockSetupItem
	// fields (which keep their own copy as audit trail). gorm column tags are
	// explicit per the v132/v246 GORM-mangling lesson. DB columns were added
	// by migration 20260515_products_photo_columns.sql.
	FrontImageURL          string     `json:"front_image_url,omitempty" gorm:"column:front_image_url"`
	BackImageURL           string     `json:"back_image_url,omitempty" gorm:"column:back_image_url"`
	BackImageMRP           float64    `json:"back_image_mrp,omitempty" gorm:"column:back_image_mrp;type:numeric(10,2)"`
	BackImageMRPConfidence *float64   `json:"back_image_mrp_confidence,omitempty" gorm:"column:back_image_mrp_confidence;type:numeric(4,3)"`
	VerifiedViaImageFront  bool       `json:"verified_via_image_front" gorm:"column:verified_via_image_front;default:false"`
	VerifiedViaImageBack   bool       `json:"verified_via_image_back" gorm:"column:verified_via_image_back;default:false"`
	PhotoVerifiedAt        *time.Time `json:"photo_verified_at,omitempty" gorm:"column:photo_verified_at"`

	// 2026-05-17 — NameVerified: true once the product's name has been
	// confirmed against a trusted bottle photo (Gemini high-confidence read)
	// or it was onboarded from a master-catalog pick. false = the name is
	// raw, unverified Stock-Setup text (e.g. garbled OCR "100 Step") that
	// must be image-verified BEFORE a purchase can be added for it, so
	// purchase/sales reconcile on the correct name. Explicit gorm column tag
	// per the v132/v246 GORM-mangling lesson. DB column + backfill added by
	// migration 20260517_products_name_verified.sql.
	NameVerified bool `json:"name_verified" gorm:"column:name_verified;not null;default:false"`

	// 2026-05-18 — CreatedVia: provenance of how this product row was born.
	// Drives the AI-Purchase image gate: a product created by AI Stock Setup
	// ('stock_setup') with no image (image_url/front_image_url/back_image_url
	// all empty) cannot receive purchased stock until a bottle photo is
	// attached (POST /products/:id/verify-photo). Every other origin —
	// 'ai_purchase' / 'catalog' / 'manual' / 'bulk_import' and the DB default
	// 'legacy_exempt' (all pre-existing rows + any unstamped site) — is
	// exempt, so the gate is strictly forward-only. Explicit gorm column tag
	// per the v132/v246 GORM-mangling lesson. DB column + index added by
	// migration 20260518_products_created_via.sql.
	CreatedVia string `json:"created_via,omitempty" gorm:"column:created_via;not null;default:'legacy_exempt'"`

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

	Quantity         int `json:"quantity" gorm:"default:0"`
	ReservedQuantity int `json:"reserved_quantity" gorm:"default:0"`
	MinimumLevel     int `json:"minimum_level" gorm:"default:0"`
	MaximumLevel     int `json:"maximum_level" gorm:"default:0"`

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

// StockHistory tracks all stock movements for audit purposes.
//
// The shop_id column is denormalized from stocks.shop_id so audit queries can
// filter by shop without joining through stocks (which itself can have NULL
// shop_id on tenant-wide products). Pre-fix the Go struct didn't declare the
// column, so GORM silently dropped it on every insert — the FM Tower 2026-05
// audit pulled 1133 history rows where shop_id was NULL on 99% of them, exact
// same v1.0.132 GORM-mangling pattern as products.last_mrp_change_at. The
// pointer type tolerates legacy NULL rows; new writes MUST set it.
type StockHistory struct {
	TenantModel
	StockID          uuid.UUID  `json:"stock_id" gorm:"type:uuid;not null"`
	Stock            *Stock     `json:"stock,omitempty" gorm:"foreignKey:StockID"`
	ShopID           *uuid.UUID `json:"shop_id,omitempty" gorm:"column:shop_id;type:uuid;index:idx_stock_histories_shop"`
	ProductID        *uuid.UUID `json:"product_id,omitempty" gorm:"column:product_id;type:uuid;index:idx_stock_histories_product"`
	MovementType     string     `json:"movement_type" gorm:"not null"` // purchase, sale, adjustment, transfer
	Quantity         int        `json:"quantity" gorm:"not null"`
	PreviousQuantity int        `json:"previous_quantity" gorm:"not null"`
	NewQuantity      int        `json:"new_quantity" gorm:"not null"`
	UnitCost         float64    `json:"unit_cost"`
	TotalCost        float64    `json:"total_cost"`
	Reference        string     `json:"reference"` // Reference to sale, purchase, etc.
	ReferenceID      *uuid.UUID `json:"reference_id" gorm:"type:uuid;index:idx_stock_histories_ref"`
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

	// Payment tracking (columns already exist in stock_purchases).
	PaidAmount float64 `json:"paid_amount" gorm:"default:0"`
	DueAmount  float64 `json:"due_amount" gorm:"default:0"`

	Status     string     `json:"status" gorm:"default:'pending'"` // pending, received, cancelled
	ReceivedAt *time.Time `json:"received_at"`

	// Approval audit (columns already exist; map so the admin can show who
	// approved/received and when).
	ApprovedByID *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy   *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	ApprovedAt   *time.Time `json:"approved_at"`

	Notes         string `json:"notes"`
	ReceiptNo     string `json:"receipt_no"`
	InvoiceNumber string `json:"invoice_number"`

	// Receipt/invoice images
	ReceiptImages JSONStringList `json:"receipt_images,omitempty" gorm:"type:jsonb;default:'[]'"`

	// Created by
	CreatedBy     uuid.UUID `json:"created_by" gorm:"type:uuid;not null"`
	CreatedByUser *User     `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`

	// Relationships
	Items    []StockPurchaseItem    `json:"items,omitempty" gorm:"foreignKey:StockPurchaseID"`
	Payments []StockPurchasePayment `json:"payments,omitempty" gorm:"foreignKey:StockPurchaseID"`
}

// StockPurchaseItem represents individual items in a purchase order
type StockPurchaseItem struct {
	TenantModel
	StockPurchaseID uuid.UUID      `json:"stock_purchase_id" gorm:"column:purchase_id;type:uuid;not null"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID;references:ID"`
	ProductID       uuid.UUID      `json:"product_id" gorm:"type:uuid;not null"`
	Product         *Product       `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	Quantity   int     `json:"quantity" gorm:"not null"`
	UnitCost   float64 `json:"unit_cost" gorm:"column:unit_price;not null"`
	TotalCost  float64 `json:"total_cost" gorm:"column:total_price;not null"`

	DutyFee       float64    `json:"duty_fee" gorm:"default:0"`
	Leakage       int        `json:"leakage" gorm:"default:0"`
	ShortReceived int        `json:"short_received" gorm:"default:0"`
	BatchNumber   string     `json:"batch_number"`
	ExpiryDate  *time.Time `json:"expiry_date"`
}

// StockPurchasePayment represents payments made for stock purchases
type StockPurchasePayment struct {
	TenantModel
	StockPurchaseID uuid.UUID      `json:"stock_purchase_id" gorm:"column:purchase_id;type:uuid;not null"`
	StockPurchase   *StockPurchase `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID;references:ID"`

	Amount        float64   `json:"amount" gorm:"not null"`
	PaymentMethod string    `json:"payment_method" gorm:"not null"`
	PaymentDate   time.Time `json:"payment_date"`
	Reference     string    `json:"reference" gorm:"column:reference_number"`
	Notes         string    `json:"notes"`
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

// StockSetupRecord represents an AI-powered stock setup that requires manager/admin approval.
// Follows the same approval pattern as DailySalesRecord.
type StockSetupRecord struct {
	TenantModel
	ShopID   uuid.UUID `json:"shop_id" gorm:"type:uuid;not null"`
	Shop     *Shop     `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	Category string    `json:"category"` // beer, non_beer
	Size     string    `json:"size"`     // 90ML, 180ML, 375ML, 750ML

	// Totals
	TotalItems    int     `json:"total_items" gorm:"default:0"`
	TotalQuantity int     `json:"total_quantity" gorm:"default:0"`
	TotalValue    float64 `json:"total_value" gorm:"default:0"`

	// Status and approval
	Status          string     `json:"status" gorm:"default:'pending'"` // pending, approved, rejected
	ApprovedAt      *time.Time `json:"approved_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id" gorm:"type:uuid"`
	ApprovedBy      *User      `json:"approved_by,omitempty" gorm:"foreignKey:ApprovedByID"`
	RejectionReason string     `json:"rejection_reason,omitempty"`

	// Created by
	CreatedByID uuid.UUID `json:"created_by_id" gorm:"type:uuid;not null"`
	CreatedBy   *User     `json:"created_by,omitempty" gorm:"foreignKey:CreatedByID"`

	Notes string `json:"notes"`

	// Receipt images (register photos for verification)
	ReceiptImages JSONStringList `json:"receipt_images,omitempty" gorm:"type:jsonb;default:'[]'"`

	// AI model used for extraction
	AIModel string `json:"ai_model,omitempty"`

	// v1.0.216 — banking-grade idempotency for Apply. SessionID is the Smart
	// Stock Setup extraction session that produced these items; replaying
	// Apply with the same key after a network blip would (pre-fix) write a
	// new approved record AND re-bump every stocks.quantity again. The
	// (tenant_id, session_id) partial unique index makes the duplicate
	// physically impossible: the second INSERT raises a unique-violation,
	// the handler catches it and returns the existing record's result.
	SessionID *string `json:"session_id,omitempty" gorm:"column:session_id;type:varchar(255);index:idx_stock_setup_session,unique,where:session_id IS NOT NULL AND deleted_at IS NULL"`

	// Relationships
	Items []StockSetupItem `json:"items,omitempty" gorm:"foreignKey:StockSetupRecordID"`
}

// StockSetupItem represents an individual product in a stock setup record
type StockSetupItem struct {
	TenantModel
	StockSetupRecordID uuid.UUID         `json:"stock_setup_record_id" gorm:"type:uuid;not null"`
	StockSetupRecord   *StockSetupRecord `json:"stock_setup_record,omitempty" gorm:"foreignKey:StockSetupRecordID"`
	ProductID          uuid.UUID         `json:"product_id" gorm:"type:uuid;not null"`
	Product            *Product          `json:"product,omitempty" gorm:"foreignKey:ProductID"`

	// Stock quantities from register
	Quantity     int `json:"quantity" gorm:"not null"`      // Current stock quantity to set
	OpeningStock int `json:"opening_stock" gorm:"default:0"` // Opening stock from register
	Receipt      int `json:"receipt" gorm:"default:0"`       // New stock received
	Sale         int `json:"sale" gorm:"default:0"`          // Quantity sold

	// Price info
	Rate   float64 `json:"rate" gorm:"default:0"`   // Rate per unit from register
	Amount float64 `json:"amount" gorm:"default:0"` // Total amount (rate * sale)

	// DB stock at time of creation (for comparison)
	PreviousDBStock int `json:"previous_db_stock" gorm:"default:0"`

	// RawAIExtraction is the unedited per-row AI output (before user
	// correction). JSONB blob with original brand text, numeric fields,
	// confidence, field_confidence, source. Powers post-mortem audits +
	// feeds few-shot + calibration pipelines. NULL when row was manually added.
	RawAIExtraction datatypes.JSON `json:"raw_ai_extraction,omitempty" gorm:"type:jsonb"`

	// AIConfidence is the row-level confidence at apply time (mirrored out
	// of RawAIExtraction for cheap WHERE filtering). NULL = no AI signal.
	AIConfidence *float64 `json:"ai_confidence,omitempty" gorm:"type:numeric(4,3)"`

	// UserCorrected — true when the user changed name/brand/qty/rate before
	// approving. Pairs with RawAIExtraction to form (predicted, ground-truth)
	// labeled samples for few-shot + Platt calibration.
	UserCorrected bool `json:"user_corrected" gorm:"default:false"`

	// v1.0.243 — legacy single-photo verification (kept for backward compat).
	// CRITICAL: explicit gorm column tags. Without them GORM mangles names
	// (e.g. last_m_rpchange_at on the v132 bug) and the column is silently
	// dropped on INSERT — exactly what was happening to FrontImageURL on
	// every v244 apply, leaving admin with no visibility into the photos
	// chhotu was already taking.
	VerifiedImageURL string   `json:"verified_image_url,omitempty" gorm:"column:verified_image_url"`
	VerifiedViaImage bool     `json:"verified_via_image" gorm:"column:verified_via_image;default:false"`
	GeminiAgreed     *bool    `json:"gemini_agreed,omitempty" gorm:"column:gemini_agreed"`
	GeminiConfidence *float64 `json:"gemini_confidence,omitempty" gorm:"column:gemini_confidence;type:numeric(4,3)"`

	// v1.0.244 — Two-photo verification (front + back). Apply gate requires
	// both faces verified before stocks are touched. BackImageMRP is the
	// M.R.P. Gemini read off the back label; operator decides when (and
	// whether) to apply it via the Edit sheet.
	FrontImageURL          string   `json:"front_image_url,omitempty" gorm:"column:front_image_url"`
	BackImageURL           string   `json:"back_image_url,omitempty" gorm:"column:back_image_url"`
	VerifiedViaImageFront  bool     `json:"verified_via_image_front" gorm:"column:verified_via_image_front;default:false"`
	VerifiedViaImageBack   bool     `json:"verified_via_image_back" gorm:"column:verified_via_image_back;default:false"`
	BackImageMRP           float64  `json:"back_image_mrp,omitempty" gorm:"column:back_image_mrp;type:numeric(10,2)"`
	BackImageMRPConfidence *float64 `json:"back_image_mrp_confidence,omitempty" gorm:"column:back_image_mrp_confidence;type:numeric(4,3)"`
}

// StockSetupReplaceSnapshot — reversible audit for the AI Stock Setup
// snapshot-replace at approval (2026-05-19). One row per in-scope product
// that an approval DEACTIVATED (stock zeroed + product soft-deleted) because
// it was not in the approved register. Recording the pre-change state per
// product per record lets the ENTIRE replace be reversed if an approved
// register silently dropped a real item — nothing is hard-deleted, every
// removal is recoverable.
//
// Plain columns (NOT TenantModel): an audit row is never itself soft-deleted
// — "undo" is the explicit `restored` flag, not gorm.DeletedAt. Schema is
// owned by migrations/20260519_stock_setup_replace_snapshots.sql; this struct
// is used only for direct tx.Create/Find. Explicit gorm `column:` on EVERY
// field — the v132/v244 column-drift trap (GORM silently dropping untagged
// columns on INSERT) is a documented recurring incident in this codebase.
type StockSetupReplaceSnapshot struct {
	ID                   uuid.UUID  `json:"id" gorm:"column:id;type:uuid;default:gen_random_uuid();primaryKey"`
	TenantID             *uuid.UUID `json:"tenant_id" gorm:"column:tenant_id;type:uuid;index"`
	StockSetupRecordID   uuid.UUID  `json:"stock_setup_record_id" gorm:"column:stock_setup_record_id;type:uuid;not null"`
	ProductID            uuid.UUID  `json:"product_id" gorm:"column:product_id;type:uuid;not null"`
	ShopID               uuid.UUID  `json:"shop_id" gorm:"column:shop_id;type:uuid;not null"`
	StockID              *uuid.UUID `json:"stock_id,omitempty" gorm:"column:stock_id;type:uuid"`
	PrevStockQuantity    int        `json:"prev_stock_quantity" gorm:"column:prev_stock_quantity;not null;default:0"`
	PrevProductDeletedAt *time.Time `json:"prev_product_deleted_at,omitempty" gorm:"column:prev_product_deleted_at"`
	PrevIsActive         bool       `json:"prev_is_active" gorm:"column:prev_is_active;not null;default:true"`
	Action               string     `json:"action" gorm:"column:action;not null"`
	Restored             bool       `json:"restored" gorm:"column:restored;not null;default:false"`
	RestoredAt           *time.Time `json:"restored_at,omitempty" gorm:"column:restored_at"`
	RestoredByID         *uuid.UUID `json:"restored_by_id,omitempty" gorm:"column:restored_by_id;type:uuid"`
	Notes                string     `json:"notes,omitempty" gorm:"column:notes"`
	CreatedByID          *uuid.UUID `json:"created_by_id,omitempty" gorm:"column:created_by_id;type:uuid"`
	CreatedAt            time.Time  `json:"created_at" gorm:"column:created_at;autoCreateTime"`
	UpdatedAt            time.Time  `json:"updated_at" gorm:"column:updated_at;autoUpdateTime"`
}

// TableName pins the table so direct tx.Create/Find never depends on GORM's
// pluraliser (which has mis-derived names on this codebase before).
func (StockSetupReplaceSnapshot) TableName() string {
	return "stock_setup_replace_snapshots"
}
