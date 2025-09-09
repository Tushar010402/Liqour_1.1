package database

import (
	"fmt"
	"log"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// DB holds the database connection
type DB struct {
	*gorm.DB
}

// Config holds database configuration
type Config struct {
	Host     string
	Port     int
	User     string
	Password string
	DBName   string
	SSLMode  string
	TimeZone string
}

// NewDatabase creates a new database connection
func NewDatabase(config Config) (*DB, error) {
	dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s TimeZone=%s",
		config.Host, config.Port, config.User, config.Password, config.DBName, config.SSLMode, config.TimeZone)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
		NowFunc: func() time.Time {
			return time.Now().UTC()
		},
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get underlying sql.DB: %w", err)
	}

	// Connection pool settings
	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(25)
	sqlDB.SetConnMaxLifetime(5 * time.Minute)

	return &DB{db}, nil
}

// Migrate runs database migrations
func (db *DB) Migrate() error {
	log.Println("Running database migrations...")
	
	if err := models.MigrateDB(db.DB); err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	if err := models.CreateIndexes(db.DB); err != nil {
		return fmt.Errorf("failed to create indexes: %w", err)
	}

	log.Println("Database migrations completed successfully")
	return nil
}

// Close closes the database connection
func (db *DB) Close() error {
	sqlDB, err := db.DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}

// Health checks database connectivity
func (db *DB) Health() error {
	sqlDB, err := db.DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Ping()
}

// TenantScope adds tenant isolation to queries
func TenantScope(tenantID string) func(*gorm.DB) *gorm.DB {
	return func(db *gorm.DB) *gorm.DB {
		return db.Where("tenant_id = ?", tenantID)
	}
}

// ActiveScope filters only active records
func ActiveScope() func(*gorm.DB) *gorm.DB {
	return func(db *gorm.DB) *gorm.DB {
		return db.Where("is_active = ?", true)
	}
}

// Transaction wraps database operations in a transaction
func (db *DB) Transaction(fn func(*gorm.DB) error) error {
	return db.DB.Transaction(fn)
}