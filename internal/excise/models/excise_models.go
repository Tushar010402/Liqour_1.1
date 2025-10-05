package models

import (
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ExciseLicense represents an excise license for a shop
type ExciseLicense struct {
	models.TenantModel
	ShopID uuid.UUID     `json:"shop_id" gorm:"type:uuid;not null"`
	Shop   *models.Shop  `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	// License details
	LicenseNumber      string `json:"license_number" gorm:"uniqueIndex;not null"`
	LicenseType        string `json:"license_type" gorm:"not null"` // FL-2A, CL-2, COMPOSITE, etc.
	LicenseCategory    string `json:"license_category"`

	// Validity
	IssuedDate         time.Time `json:"issued_date" gorm:"not null"`
	ExpiryDate         time.Time `json:"expiry_date" gorm:"not null"`
	IsActive           bool      `json:"is_active" gorm:"default:true"`

	// Financial
	MonthlyFee         float64      `json:"monthly_fee" gorm:"not null"`
	BankAccountID      *uuid.UUID   `json:"bank_account_id" gorm:"type:uuid"`
	BankAccount        *models.BankAccount `json:"bank_account,omitempty" gorm:"foreignKey:BankAccountID"`

	// Additional details
	Restrictions       map[string]interface{} `json:"restrictions" gorm:"type:jsonb"`
	LicenseConditions  string                 `json:"license_conditions"`
	IssuingAuthority   string                 `json:"issuing_authority"`

	// Audit
	CreatedBy          uuid.UUID  `json:"created_by" gorm:"type:uuid"`
	UpdatedBy          *uuid.UUID `json:"updated_by" gorm:"type:uuid"`
	CreatedByUser      *models.User `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	UpdatedByUser      *models.User `json:"updated_by_user,omitempty" gorm:"foreignKey:UpdatedBy"`
}

// TableName specifies the table name for ExciseLicense
func (ExciseLicense) TableName() string {
	return "excise_licenses"
}

// DaysUntilExpiry returns the number of days until license expires
func (l *ExciseLicense) DaysUntilExpiry() int {
	return int(time.Until(l.ExpiryDate).Hours() / 24)
}

// IsExpired checks if the license has expired
func (l *ExciseLicense) IsExpired() bool {
	return time.Now().After(l.ExpiryDate)
}

// IsExpiringSoon checks if license is expiring within 30 days
func (l *ExciseLicense) IsExpiringSoon() bool {
	return l.DaysUntilExpiry() <= 30 && l.DaysUntilExpiry() > 0
}

// LicenseStatus returns the current status of the license
func (l *ExciseLicense) LicenseStatus() string {
	if l.IsExpired() {
		return "expired"
	}
	if l.IsExpiringSoon() {
		return "expiring_soon"
	}
	if l.IsActive {
		return "active"
	}
	return "inactive"
}

// ExciseDailyReport represents daily excise report for portal submission
type ExciseDailyReport struct {
	models.TenantModel
	ShopID             uuid.UUID          `json:"shop_id" gorm:"type:uuid;not null"`
	Shop               *models.Shop       `json:"shop,omitempty" gorm:"foreignKey:ShopID"`
	LicenseID          uuid.UUID          `json:"license_id" gorm:"type:uuid;not null"`
	License            *ExciseLicense     `json:"license,omitempty" gorm:"foreignKey:LicenseID"`
	ReportDate         time.Time          `json:"report_date" gorm:"not null"`

	// Stock breakdown (JSONB)
	OpeningStock       StockBreakdown `json:"opening_stock" gorm:"type:jsonb"`
	StockLifted        StockBreakdown `json:"stock_lifted" gorm:"type:jsonb"`
	Sales              StockBreakdown `json:"sales" gorm:"type:jsonb"`
	Returns            StockBreakdown `json:"returns" gorm:"type:jsonb"`
	ClosingStock       StockBreakdown `json:"closing_stock" gorm:"type:jsonb"`

	// Financial linkages
	MoneyCollectionID  *uuid.UUID              `json:"money_collection_id" gorm:"type:uuid"`
	MoneyCollection    *models.MoneyCollection `json:"money_collection,omitempty" gorm:"foreignKey:MoneyCollectionID"`
	CashDepositID      *uuid.UUID              `json:"cash_deposit_id" gorm:"type:uuid"`
	CashDeposit        *models.CashDeposit     `json:"cash_deposit,omitempty" gorm:"foreignKey:CashDepositID"`
	ConsiderationFeePaid float64               `json:"consideration_fee_paid" gorm:"default:0"`

	// Portal upload status
	UploadedToPortal   bool                   `json:"uploaded_to_portal" gorm:"default:false"`
	UploadTimestamp    *time.Time             `json:"upload_timestamp"`
	UploadAttempts     int                    `json:"upload_attempts" gorm:"default:0"`
	SMSConfirmation    string                 `json:"sms_confirmation"`
	PortalResponse     map[string]interface{} `json:"portal_response" gorm:"type:jsonb"`
	PortalStatus       string                 `json:"portal_status" gorm:"default:'pending'"` // pending, uploading, success, failed, retry

	// Report metadata
	ReportStatus           string `json:"report_status" gorm:"default:'draft'"` // draft, submitted, uploaded, failed
	GeneratedAutomatically bool   `json:"generated_automatically" gorm:"default:false"`

	// Audit
	CreatedBy          uuid.UUID  `json:"created_by" gorm:"type:uuid"`
	UploadedBy         *uuid.UUID `json:"uploaded_by" gorm:"type:uuid"`
	CreatedByUser      *models.User `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
	UploadedByUser     *models.User `json:"uploaded_by_user,omitempty" gorm:"foreignKey:UploadedBy"`
}

// TableName specifies the table name for ExciseDailyReport
func (ExciseDailyReport) TableName() string {
	return "excise_daily_reports"
}

// ValidateReport checks if report is valid for upload
func (r *ExciseDailyReport) ValidateReport() bool {
	errors := r.GetValidationErrors()
	return len(errors) == 0
}

// GetValidationErrors returns validation errors for the report
func (r *ExciseDailyReport) GetValidationErrors() []string {
	errors := []string{}

	// Check if all required fields are present
	if r.OpeningStock.TotalBottles < 0 {
		errors = append(errors, "Opening stock cannot be negative")
	}
	if r.ClosingStock.TotalBottles < 0 {
		errors = append(errors, "Closing stock cannot be negative")
	}

	// Validate stock equation: Opening + Lifted + Returns - Sales = Closing
	expectedClosing := r.OpeningStock.TotalBottles + r.StockLifted.TotalBottles + r.Returns.TotalBottles - r.Sales.TotalBottles
	if r.ClosingStock.TotalBottles != expectedClosing {
		errors = append(errors, fmt.Sprintf("Stock mismatch: expected %d bottles, got %d", expectedClosing, r.ClosingStock.TotalBottles))
	}

	return errors
}

// StockBreakdown represents bottle-wise stock breakdown by category
type StockBreakdown struct {
	CountryLiquor []BottleEntry `json:"country_liquor"`
	IMFL          []BottleEntry `json:"imfl"`
	Beer          []BottleEntry `json:"beer"`
	Wine          []BottleEntry `json:"wine"`
	TotalBottles  int           `json:"total_bottles"`
	TotalValue    float64       `json:"total_value"`
}

// BottleEntry represents individual product entry with bottles
type BottleEntry struct {
	ProductID     string   `json:"product_id"`
	ProductName   string   `json:"product_name"`
	SecurityCodes []string `json:"security_codes"`
	Quantity      int      `json:"quantity"`
	UnitPrice     float64  `json:"unit_price"`
	TotalValue    float64  `json:"total_value"`
}

// CalculateTotals calculates total bottles and value for stock breakdown
func (sb *StockBreakdown) CalculateTotals() {
	sb.TotalBottles = 0
	sb.TotalValue = 0

	for _, entry := range sb.CountryLiquor {
		sb.TotalBottles += entry.Quantity
		sb.TotalValue += entry.TotalValue
	}
	for _, entry := range sb.IMFL {
		sb.TotalBottles += entry.Quantity
		sb.TotalValue += entry.TotalValue
	}
	for _, entry := range sb.Beer {
		sb.TotalBottles += entry.Quantity
		sb.TotalValue += entry.TotalValue
	}
	for _, entry := range sb.Wine {
		sb.TotalBottles += entry.Quantity
		sb.TotalValue += entry.TotalValue
	}
}

// BottleSecurityCode represents individual bottle security codes
type BottleSecurityCode struct {
	models.TenantModel
	SecurityCode     string    `json:"security_code" gorm:"uniqueIndex;not null"`

	// Product linkage
	ProductID        uuid.UUID      `json:"product_id" gorm:"type:uuid;not null"`
	Product          *models.Product `json:"product,omitempty" gorm:"foreignKey:ProductID"`
	ProductName      string         `json:"product_name"`

	// Transaction linkages
	VendorTransactionID *uuid.UUID                 `json:"vendor_transaction_id" gorm:"type:uuid"`
	VendorTransaction   *models.VendorTransaction  `json:"vendor_transaction,omitempty" gorm:"foreignKey:VendorTransactionID"`
	StockPurchaseID     *uuid.UUID                 `json:"stock_purchase_id" gorm:"type:uuid"`
	StockPurchase       *models.StockPurchase      `json:"stock_purchase,omitempty" gorm:"foreignKey:StockPurchaseID"`
	SaleID              *uuid.UUID                 `json:"sale_id" gorm:"type:uuid"`
	Sale                *models.Sale               `json:"sale,omitempty" gorm:"foreignKey:SaleID"`

	// Status tracking
	Status           string     `json:"status" gorm:"default:'in_stock'"` // in_stock, sold, damaged, missing, returned
	ReceivedDate     *time.Time `json:"received_date"`
	SoldDate         *time.Time `json:"sold_date"`

	// Source tracking
	WarehouseSource  string     `json:"warehouse_source"`
	CL2GodownID      *uuid.UUID `json:"cl2_godown_id" gorm:"type:uuid"`
	CL2Godown        *models.Vendor `json:"cl2_godown,omitempty" gorm:"foreignKey:CL2GodownID"`
	BatchNumber      string     `json:"batch_number"`

	// Verification
	Verified         bool       `json:"verified" gorm:"default:false"`
	VerificationDate *time.Time `json:"verification_date"`

	// Shop tracking
	ShopID           *uuid.UUID   `json:"shop_id" gorm:"type:uuid"`
	Shop             *models.Shop `json:"shop,omitempty" gorm:"foreignKey:ShopID"`

	// Audit
	CreatedBy        uuid.UUID    `json:"created_by" gorm:"type:uuid"`
	CreatedByUser    *models.User `json:"created_by_user,omitempty" gorm:"foreignKey:CreatedBy"`
}

// TableName specifies the table name for BottleSecurityCode
func (BottleSecurityCode) TableName() string {
	return "bottle_security_codes"
}

// IsValid checks if security code is valid (not damaged or missing)
func (b *BottleSecurityCode) IsValid() bool {
	return b.Status != "damaged" && b.Status != "missing"
}

// IsAvailable checks if security code is available for sale
func (b *BottleSecurityCode) IsAvailable() bool {
	return b.Status == "in_stock" && b.Verified
}

// ExciseComplianceLog represents audit trail for compliance activities
type ExciseComplianceLog struct {
	ID        uuid.UUID `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	TenantID  uuid.UUID `json:"tenant_id" gorm:"type:uuid;not null"`
	ShopID    *uuid.UUID `json:"shop_id" gorm:"type:uuid"`
	LicenseID *uuid.UUID `json:"license_id" gorm:"type:uuid"`

	// Log details
	LogType    string                 `json:"log_type" gorm:"not null"` // license_created, fee_paid, report_uploaded, etc.
	LogLevel   string                 `json:"log_level" gorm:"default:'info'"` // debug, info, warning, error, critical
	Message    string                 `json:"message" gorm:"not null"`
	Details    map[string]interface{} `json:"details" gorm:"type:jsonb"`

	// Related entities
	RelatedEntityType string     `json:"related_entity_type"`
	RelatedEntityID   *uuid.UUID `json:"related_entity_id" gorm:"type:uuid"`

	// Timestamp
	LoggedAt  time.Time  `json:"logged_at" gorm:"default:now()"`
	LoggedBy  *uuid.UUID `json:"logged_by" gorm:"type:uuid"`
	LoggedByUser *models.User `json:"logged_by_user,omitempty" gorm:"foreignKey:LoggedBy"`
}

// TableName specifies the table name for ExciseComplianceLog
func (ExciseComplianceLog) TableName() string {
	return "excise_compliance_logs"
}

// Request/Response DTOs

// CreateLicenseRequest represents request to create new license
type CreateLicenseRequest struct {
	ShopID               uuid.UUID              `json:"shop_id" binding:"required"`
	LicenseNumber        string                 `json:"license_number" binding:"required"`
	LicenseType          string                 `json:"license_type" binding:"required"`
	IssuedDate           *time.Time             `json:"issued_date"`
	ExpiryDate           *time.Time             `json:"expiry_date"`
	MonthlyFee           float64                `json:"monthly_fee" binding:"required,min=0"`
	BankAccountID        *uuid.UUID             `json:"bank_account_id"`
	Restrictions         map[string]interface{} `json:"restrictions"`
	LicenseIssuedBy      string                 `json:"license_issued_by"`
	ExciseDistrict       string                 `json:"excise_district"`
	SecurityDeposit      float64                `json:"security_deposit"`
	AnnualGuaranteeFee   float64                `json:"annual_guarantee_fee"`
}

// UpdateLicenseRequest represents request to update license
type UpdateLicenseRequest struct {
	ExpiryDate        *time.Time             `json:"expiry_date"`
	MonthlyFee        *float64               `json:"monthly_fee"`
	BankAccountID     *uuid.UUID             `json:"bank_account_id"`
	IsActive          *bool                  `json:"is_active"`
	Restrictions      map[string]interface{} `json:"restrictions"`
	LicenseConditions *string                `json:"license_conditions"`
}

// PayLicenseFeeRequest represents request to pay license fee
type PayLicenseFeeRequest struct {
	LicenseID     uuid.UUID `json:"license_id" binding:"required"`
	FeeMonth      time.Time `json:"fee_month" binding:"required"`
	Amount        float64   `json:"amount" binding:"required,min=0"`
	PaymentMethod string    `json:"payment_method" binding:"required"`
	ReceiptNo     string    `json:"receipt_no"`
	Notes         string    `json:"notes"`
}

// AutoGenerateReportRequest represents request to auto-generate daily report
type AutoGenerateReportRequest struct {
	ShopID     uuid.UUID `json:"shop_id" binding:"required"`
	ReportDate time.Time `json:"report_date" binding:"required"`
}

// UploadToPortalRequest represents request to upload report to portal
type UploadToPortalRequest struct {
	ReportID uuid.UUID `json:"report_id" binding:"required"`
}

// ValidateSecurityCodeRequest represents request to validate security code
type ValidateSecurityCodeRequest struct {
	SecurityCode string `json:"security_code" binding:"required"`
}

// BulkAddSecurityCodesRequest represents request to bulk add security codes
type BulkAddSecurityCodesRequest struct {
	ProductID           uuid.UUID  `json:"product_id" binding:"required"`
	SecurityCodes       []string   `json:"security_codes" binding:"required,min=1"`
	VendorTransactionID *uuid.UUID `json:"vendor_transaction_id"`
	StockPurchaseID     *uuid.UUID `json:"stock_purchase_id"`
	ReceivedDate        *time.Time `json:"received_date"`
	SourceType          string     `json:"source_type"`
	SourceWarehouse     string     `json:"source_warehouse"`
	BatchNumber         string     `json:"batch_number"`
}

// LicenseResponse represents license response with compliance status
type LicenseResponse struct {
	ExciseLicense
	ShopName         string                 `json:"shop_name"`
	DaysUntilExpiry  int                    `json:"days_until_expiry"`
	Status           string                 `json:"status"`
	ComplianceStatus map[string]interface{} `json:"compliance_status"`
}

// DailyReportResponse represents daily report response
type DailyReportResponse struct {
	ExciseDailyReport
	ShopName          string   `json:"shop_name"`
	LicenseNumber     string   `json:"license_number"`
	IsValid           bool     `json:"is_valid"`
	ValidationErrors  []string `json:"validation_errors,omitempty"`
}

// SecurityCodeResponse represents security code response with validation
type SecurityCodeResponse struct {
	BottleSecurityCode
	IsValid     bool   `json:"is_valid"`
	Message     string `json:"message"`
	Status      string `json:"status"`
	ProductName string `json:"product_name"`
}

// ComplianceDashboardResponse represents overall compliance status
type ComplianceDashboardResponse struct {
	TenantID             uuid.UUID           `json:"tenant_id"`
	TotalShops           int                 `json:"total_shops"`
	ActiveLicenses       int                 `json:"active_licenses"`
	ExpiringLicenses     int                 `json:"expiring_licenses"`
	ExpiredLicenses      int                 `json:"expired_licenses"`
	PendingReports       int                 `json:"pending_reports"`
	ReportsUploadedToday int                 `json:"reports_uploaded_today"`
	PendingLicenseFees   int                 `json:"pending_license_fees"`
	TotalSecurityCodes   int                 `json:"total_security_codes"`
	SecurityCodesInStock int                 `json:"security_codes_in_stock"`
	ComplianceScore      float64             `json:"compliance_score"` // 0-100
	ComplianceStatus     string              `json:"compliance_status"` // excellent, good, warning, critical
	Licenses             []LicenseResponse   `json:"licenses"`
	RecentLogs           []ExciseComplianceLog `json:"recent_logs"`
}

// ConsiderationFeeSummary represents summary of consideration fees
type ConsiderationFeeSummary struct {
	TotalFeesPaid    float64   `json:"total_fees_paid"`
	FeesThisMonth    float64   `json:"fees_this_month"`
	FeesToday        float64   `json:"fees_today"`
	TotalBottles     int       `json:"total_bottles"`
	BottlesThisMonth int       `json:"bottles_this_month"`
	BottlesToday     int       `json:"bottles_today"`
	LastPaymentDate  *time.Time `json:"last_payment_date"`
	AverageFeePerBottle float64 `json:"average_fee_per_bottle"`
}
