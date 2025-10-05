package models

import (
	"fmt"
	"strings"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// AllModels returns a slice of all model structs for GORM AutoMigrate
func AllModels() []interface{} {
	return []interface{}{
		// Base models
		&Tenant{},
		&Shop{},
		// &User{}, // TEMPORARILY DISABLED: User model causes GORM migration conflicts due to NULL tenant_id
		&TenantRole{},
		&TenantPermission{},
		&UserSession{},
		&Salesman{},

		// Inventory models
		&Category{},
		&Subcategory{},
		&Brand{},
		&ProductTemplate{},
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

		// Rate Limiting models
		&RateLimit{},
		&RateLimitLog{},
	}
}

// MigrateDB runs all database migrations
func MigrateDB(db *gorm.DB) error {
	// First, handle User model with special NULL tenant_id handling
	if err := migrateUserModel(db); err != nil {
		return fmt.Errorf("failed to migrate user model: %w", err)
	}

	// Migrate all other models (excluding User since we handled it above)
	models := []interface{}{
		// Base models (skip Tenant for now)
		&Shop{},
		&TenantRole{},
		&TenantPermission{},
		&UserSession{},
		&Salesman{},

		// Inventory models
		&Category{},
		// &Subcategory{}, // Temporarily disabled - schema conflict with existing table
		&Brand{},
		&ProductTemplate{},
		&Product{},
		&BrandPricing{},
		&Stock{},
		&StockBatch{},
		&StockHistory{},
		&StockPurchase{},
		&StockPurchaseItem{},
		&StockPurchasePayment{},

		// Sales models - THESE ARE CRITICAL FOR DASHBOARD
		&Sale{},
		&SaleItem{},
		&SalePayment{},
		&SaleReturn{},
		&SaleReturnItem{},
		&DailySalesRecord{}, // This contains total_sales_amount column
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

		// Rate Limiting models
		&RateLimit{},
		&RateLimitLog{},
	}

	// Auto-migrate all models
	if err := db.AutoMigrate(models...); err != nil {
		return fmt.Errorf("failed to auto-migrate models: %w", err)
	}

	// Ensure tenant_id column allows NULL values for users table
	if err := db.Exec("ALTER TABLE users ALTER COLUMN tenant_id DROP NOT NULL").Error; err != nil {
		// Ignore error if constraint doesn't exist or table doesn't exist
		if !strings.Contains(err.Error(), "does not exist") && !strings.Contains(err.Error(), "relation") {
			return fmt.Errorf("failed to drop NOT NULL constraint on tenant_id: %w", err)
		}
	}

	// Create additional indexes for performance
	if err := CreateIndexes(db); err != nil {
		return fmt.Errorf("failed to create indexes: %w", err)
	}

	return nil
}

// migrateUserModel handles User model migration with special handling for NULL tenant_id
func migrateUserModel(db *gorm.DB) error {
	// Check if users table exists using raw SQL to avoid GORM migrator
	var exists bool
	err := db.Raw("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = CURRENT_SCHEMA() AND table_name = 'users')").Scan(&exists).Error
	if err != nil {
		return fmt.Errorf("failed to check if users table exists: %w", err)
	}

	if !exists {
		// Table doesn't exist, create it manually to allow NULL tenant_id
		return createUsersTable(db)
	}

	// Table exists, ensure tenant_id allows NULL values
	if err := db.Exec("ALTER TABLE users ALTER COLUMN tenant_id DROP NOT NULL").Error; err != nil {
		// Ignore error if constraint doesn't exist
		if !strings.Contains(err.Error(), "does not exist") {
			return fmt.Errorf("failed to drop NOT NULL constraint on tenant_id: %w", err)
		}
	}

	// Skip auto-migration for User model to avoid GORM enforcing NOT NULL
	// Instead, manually ensure the table has all required columns
	return ensureUserTableColumns(db)
}

// createUsersTable creates the users table manually with nullable tenant_id
func createUsersTable(db *gorm.DB) error {
	sql := `
	CREATE TABLE IF NOT EXISTS users (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
		updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
		deleted_at TIMESTAMP WITH TIME ZONE,
		tenant_id UUID REFERENCES tenants(id),
		username VARCHAR(255) UNIQUE NOT NULL,
		email VARCHAR(255) NOT NULL,
		first_name VARCHAR(255) NOT NULL,
		last_name VARCHAR(255) NOT NULL,
		phone VARCHAR(20),
		password_hash VARCHAR(255) NOT NULL,
		role VARCHAR(50) NOT NULL,
		is_active BOOLEAN DEFAULT true,
		profile_image TEXT,
		last_login TIMESTAMP WITH TIME ZONE,
		last_login_ip VARCHAR(45)
	);
	
	CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users(tenant_id);
	CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
	CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
	CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);
	`

	return db.Exec(sql).Error
}

// ensureUserTableColumns ensures all required columns exist in users table
func ensureUserTableColumns(db *gorm.DB) error {
	// Add any missing columns without enforcing constraints that conflict with existing data
	alterCommands := []string{
		"ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_image TEXT",
		"ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login TIMESTAMP WITH TIME ZONE",
		"ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_ip VARCHAR(45)",
	}

	for _, cmd := range alterCommands {
		if err := db.Exec(cmd).Error; err != nil {
			return fmt.Errorf("failed to execute %s: %w", cmd, err)
		}
	}

	return nil
}

// migrateUserRelatedModels handles migration of models that reference User
func migrateUserRelatedModels(db *gorm.DB) error {
	// Create user-related tables manually to avoid foreign key conflicts
	userRelatedTables := []string{
		`CREATE TABLE IF NOT EXISTS tenant_roles (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			deleted_at TIMESTAMP WITH TIME ZONE,
			tenant_id UUID NOT NULL REFERENCES tenants(id),
			user_id UUID NOT NULL REFERENCES users(id),
			role VARCHAR(50) NOT NULL,
			permissions TEXT[],
			is_active BOOLEAN DEFAULT true
		)`,
		`CREATE TABLE IF NOT EXISTS tenant_permissions (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			deleted_at TIMESTAMP WITH TIME ZONE,
			tenant_id UUID NOT NULL REFERENCES tenants(id),
			user_id UUID NOT NULL REFERENCES users(id),
			permission VARCHAR(255) NOT NULL,
			resource VARCHAR(255),
			is_active BOOLEAN DEFAULT true
		)`,
		`CREATE TABLE IF NOT EXISTS user_sessions (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			deleted_at TIMESTAMP WITH TIME ZONE,
			user_id UUID NOT NULL REFERENCES users(id),
			token VARCHAR(500) UNIQUE NOT NULL,
			ip_address VARCHAR(45),
			user_agent TEXT,
			expires_at TIMESTAMP WITH TIME ZONE,
			is_active BOOLEAN DEFAULT true
		)`,
		`CREATE TABLE IF NOT EXISTS salesmen (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			deleted_at TIMESTAMP WITH TIME ZONE,
			tenant_id UUID REFERENCES tenants(id),
			user_id UUID NOT NULL REFERENCES users(id),
			shop_id UUID NOT NULL REFERENCES shops(id),
			employee_id VARCHAR(50),
			name VARCHAR(255) NOT NULL,
			phone VARCHAR(20) NOT NULL,
			address TEXT,
			certificate_image TEXT,
			join_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
			is_active BOOLEAN DEFAULT true
		)`,
	}

	for _, sql := range userRelatedTables {
		if err := db.Exec(sql).Error; err != nil {
			return fmt.Errorf("failed to create user-related table: %w", err)
		}
	}

	// Create indexes for user-related tables
	indexes := []string{
		"CREATE INDEX IF NOT EXISTS idx_tenant_roles_tenant_id ON tenant_roles(tenant_id)",
		"CREATE INDEX IF NOT EXISTS idx_tenant_roles_user_id ON tenant_roles(user_id)",
		"CREATE INDEX IF NOT EXISTS idx_tenant_permissions_tenant_id ON tenant_permissions(tenant_id)",
		"CREATE INDEX IF NOT EXISTS idx_tenant_permissions_user_id ON tenant_permissions(user_id)",
		"CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id)",
		"CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON user_sessions(token)",
		"CREATE INDEX IF NOT EXISTS idx_salesmen_tenant_id ON salesmen(tenant_id)",
		"CREATE INDEX IF NOT EXISTS idx_salesmen_user_id ON salesmen(user_id)",
		"CREATE INDEX IF NOT EXISTS idx_salesmen_shop_id ON salesmen(shop_id)",
	}

	for _, sql := range indexes {
		if err := db.Exec(sql).Error; err != nil {
			return fmt.Errorf("failed to create index: %w", err)
		}
	}

	return nil
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

	// Rate limiting indexes
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_rate_limits_name ON rate_limits(name)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_rate_limits_tenant_id ON rate_limits(tenant_id)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_rate_limit_logs_identifier ON rate_limit_logs(identifier)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_rate_limit_logs_window ON rate_limit_logs(window_start, window_end)").Error; err != nil {
		return err
	}
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_rate_limit_logs_blocked_until ON rate_limit_logs(blocked_until)").Error; err != nil {
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
