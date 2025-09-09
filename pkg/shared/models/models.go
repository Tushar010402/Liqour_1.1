package models

import (
	"fmt"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// AllModels returns a slice of all model structs for GORM AutoMigrate
func AllModels() []interface{} {
	return []interface{}{
		// Base models
		&Tenant{},
		&Shop{},
		&User{},
		&TenantRole{},
		&TenantPermission{},
		&UserSession{},
		&Salesman{},
		
		// Inventory models
		&Category{},
		&Brand{},
		&Product{},
		&BrandPricing{},
		&Stock{},
		&StockBatch{},
		&StockHistory{},
		&StockPurchase{},
		&StockPurchaseItem{},
		&StockPurchasePayment{},
		
		// Sales models
		&Sale{},
		&SaleItem{},
		&SalePayment{},
		&SaleReturn{},
		&SaleReturnItem{},
		&DailySalesRecord{},
		&DailySalesItem{},
		&SaleFinanceLog{},
		&DailySaleSummary{},
		
		// Finance models
		&Vendor{},
		&VendorBankAccount{},
		&VendorTransaction{},
		&VendorInvoice{},
		&VendorInvoiceTransaction{},
		&BankAccount{},
		&BankTransaction{},
		&CashDeposit{},
		&ExecutiveFinance{},
		&Expense{},
		
		// Assistant Manager models
		&MoneyCollection{},
		&BankDeposit{},
		&StockVerification{},
		&StockVerificationItem{},
		&AssistantManagerLedger{},
	}
}

// MigrateDB runs all database migrations
func MigrateDB(db *gorm.DB) error {
	return db.AutoMigrate(AllModels()...)
}

// CreateIndexes creates additional database indexes for performance
func CreateIndexes(db *gorm.DB) error {
	// Tenant isolation indexes
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_tenant_shops ON shops(tenant_id)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_tenant_users ON users(tenant_id)").Error; err != nil {
		return err
	}
	
	// Sales performance indexes
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(sale_date)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_daily_sales_date ON daily_sales_records(record_date)").Error; err != nil {
		return err
	}
	
	// Stock management indexes
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_stock_shop_product ON stocks(shop_id, product_id)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_stock_history_stock ON stock_histories(stock_id)").Error; err != nil {
		return err
	}
	
	// Finance indexes
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_money_collection_deadline ON money_collections(approval_deadline)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_money_collection_status ON money_collections(status)").Error; err != nil {
		return err
	}
	
	return nil
}

// DatabaseConfig holds database configuration
type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	DBName   string
	SSLMode  string
}

// GetConnectionString returns the PostgreSQL connection string
func (config *DatabaseConfig) GetConnectionString() string {
	return fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		config.Host, config.Port, config.User, config.Password, config.DBName, config.SSLMode)
}

// BeforeCreate hooks for UUID generation if needed
func (b *BaseModel) BeforeCreate(tx *gorm.DB) error {
	if b.ID.String() == "00000000-0000-0000-0000-000000000000" {
		b.ID = uuid.New()
	}
	return nil
}

func (t *TenantModel) BeforeCreate(tx *gorm.DB) error {
	if t.ID.String() == "00000000-0000-0000-0000-000000000000" {
		t.ID = uuid.New()
	}
	return nil
}