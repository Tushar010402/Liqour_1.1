package database

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"go.uber.org/zap"
	
	"github.com/liquorpro/pkg/monitoring"
)

// ConnectionConfig holds database connection configuration
type ConnectionConfig struct {
	Host     string `yaml:"host" json:"host"`
	Port     int    `yaml:"port" json:"port"`
	User     string `yaml:"user" json:"user"`
	Password string `yaml:"password" json:"password"`
	DBName   string `yaml:"dbname" json:"dbname"`
	SSLMode  string `yaml:"sslmode" json:"sslmode"`
	
	// Connection Pool Settings
	MaxOpenConns    int           `yaml:"max_open_conns" json:"max_open_conns"`
	MaxIdleConns    int           `yaml:"max_idle_conns" json:"max_idle_conns"`
	ConnMaxLifetime time.Duration `yaml:"conn_max_lifetime" json:"conn_max_lifetime"`
	ConnMaxIdleTime time.Duration `yaml:"conn_max_idle_time" json:"conn_max_idle_time"`
	
	// Performance Settings
	SlowThreshold time.Duration `yaml:"slow_threshold" json:"slow_threshold"`
	LogLevel      string        `yaml:"log_level" json:"log_level"`
}

// DatabaseManager manages database connections with monitoring
type DatabaseManager struct {
	config     ConnectionConfig
	db         *gorm.DB
	sqlDB      *sql.DB
	logger     *zap.Logger
	serviceName string
}

// NewDatabaseManager creates a new database manager
func NewDatabaseManager(config ConnectionConfig, serviceName string, logger *zap.Logger) (*DatabaseManager, error) {
	dm := &DatabaseManager{
		config:      config,
		logger:      logger,
		serviceName: serviceName,
	}
	
	if err := dm.connect(); err != nil {
		return nil, err
	}
	
	return dm, nil
}

// connect establishes database connection with optimized settings
func (dm *DatabaseManager) connect() error {
	// Build DSN
	dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		dm.config.Host,
		dm.config.Port,
		dm.config.User,
		dm.config.Password,
		dm.config.DBName,
		dm.config.SSLMode,
	)
	
	// Configure GORM logger
	gormLogger := logger.New(
		&gormLogWriter{logger: dm.logger},
		logger.Config{
			SlowThreshold:             dm.config.SlowThreshold,
			LogLevel:                  dm.getLogLevel(),
			IgnoreRecordNotFoundError: true,
			Colorful:                  false,
		},
	)
	
	// Open connection with GORM
	var err error
	dm.db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger:                                   gormLogger,
		DisableForeignKeyConstraintWhenMigrating: false,
		SkipDefaultTransaction:                   false, // Keep transactions for safety
	})
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}
	
	// Get underlying sql.DB for connection pool configuration
	dm.sqlDB, err = dm.db.DB()
	if err != nil {
		return fmt.Errorf("failed to get underlying sql.DB: %w", err)
	}
	
	// Configure connection pool
	dm.configureConnectionPool()
	
	// Test connection
	if err := dm.sqlDB.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}
	
	dm.logger.Info("Database connected successfully",
		zap.String("service", dm.serviceName),
		zap.String("host", dm.config.Host),
		zap.Int("port", dm.config.Port),
		zap.String("database", dm.config.DBName),
	)
	
	// Start monitoring goroutine
	go dm.monitorConnections()
	
	return nil
}

// configureConnectionPool sets up connection pool parameters
func (dm *DatabaseManager) configureConnectionPool() {
	// Set default values if not specified
	if dm.config.MaxOpenConns == 0 {
		dm.config.MaxOpenConns = 25 // Default for most applications
	}
	if dm.config.MaxIdleConns == 0 {
		dm.config.MaxIdleConns = 10 // Should be <= MaxOpenConns
	}
	if dm.config.ConnMaxLifetime == 0 {
		dm.config.ConnMaxLifetime = time.Hour // Prevent stale connections
	}
	if dm.config.ConnMaxIdleTime == 0 {
		dm.config.ConnMaxIdleTime = 30 * time.Minute
	}
	
	// Apply connection pool settings
	dm.sqlDB.SetMaxOpenConns(dm.config.MaxOpenConns)
	dm.sqlDB.SetMaxIdleConns(dm.config.MaxIdleConns)
	dm.sqlDB.SetConnMaxLifetime(dm.config.ConnMaxLifetime)
	dm.sqlDB.SetConnMaxIdleTime(dm.config.ConnMaxIdleTime)
	
	dm.logger.Info("Database connection pool configured",
		zap.Int("max_open_conns", dm.config.MaxOpenConns),
		zap.Int("max_idle_conns", dm.config.MaxIdleConns),
		zap.Duration("conn_max_lifetime", dm.config.ConnMaxLifetime),
		zap.Duration("conn_max_idle_time", dm.config.ConnMaxIdleTime),
	)
}

// GetDB returns the GORM database instance
func (dm *DatabaseManager) GetDB() *gorm.DB {
	return dm.db
}

// GetSQLDB returns the underlying sql.DB instance
func (dm *DatabaseManager) GetSQLDB() *sql.DB {
	return dm.sqlDB
}

// Close closes the database connection
func (dm *DatabaseManager) Close() error {
	if dm.sqlDB != nil {
		return dm.sqlDB.Close()
	}
	return nil
}

// HealthCheck performs a health check on the database
func (dm *DatabaseManager) HealthCheck(ctx context.Context) error {
	ctxWithTimeout, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	
	return dm.sqlDB.PingContext(ctxWithTimeout)
}

// GetStats returns database connection statistics
func (dm *DatabaseManager) GetStats() sql.DBStats {
	return dm.sqlDB.Stats()
}

// monitorConnections monitors database connection metrics
func (dm *DatabaseManager) monitorConnections() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	
	for range ticker.C {
		stats := dm.sqlDB.Stats()
		
		// Update Prometheus metrics
		monitoring.SetDBConnections(dm.serviceName, "postgresql", float64(stats.OpenConnections))
		
		// Log connection statistics periodically
		if stats.OpenConnections > dm.config.MaxOpenConns*8/10 { // 80% threshold
			dm.logger.Warn("High database connection usage",
				zap.String("service", dm.serviceName),
				zap.Int("open_connections", stats.OpenConnections),
				zap.Int("max_open_connections", stats.MaxOpenConnections),
				zap.Int("idle_connections", stats.Idle),
				zap.Int("in_use_connections", stats.InUse),
			)
		}
		
		// Log detailed stats every 5 minutes
		if time.Now().Minute()%5 == 0 {
			dm.logger.Debug("Database connection stats",
				zap.String("service", dm.serviceName),
				zap.Int("open_connections", stats.OpenConnections),
				zap.Int("max_open_connections", stats.MaxOpenConnections),
				zap.Int("idle_connections", stats.Idle),
				zap.Int("in_use_connections", stats.InUse),
				zap.Int64("wait_count", stats.WaitCount),
				zap.Duration("wait_duration", stats.WaitDuration),
				zap.Int64("max_idle_closed", stats.MaxIdleClosed),
				zap.Int64("max_idle_time_closed", stats.MaxIdleTimeClosed),
				zap.Int64("max_lifetime_closed", stats.MaxLifetimeClosed),
			)
		}
	}
}

// ExecuteWithMetrics executes a database operation with monitoring
func (dm *DatabaseManager) ExecuteWithMetrics(operation string, fn func(*gorm.DB) error) error {
	start := time.Now()
	
	err := fn(dm.db)
	
	duration := time.Since(start)
	status := "success"
	if err != nil {
		status = "error"
	}
	
	// Record metrics
	monitoring.RecordDBQuery(dm.serviceName, operation, status, duration)
	
	return err
}

// getLogLevel converts string log level to GORM log level
func (dm *DatabaseManager) getLogLevel() logger.LogLevel {
	switch dm.config.LogLevel {
	case "silent":
		return logger.Silent
	case "error":
		return logger.Error
	case "warn":
		return logger.Warn
	case "info":
		return logger.Info
	default:
		return logger.Warn
	}
}

// Custom GORM log writer that integrates with Zap
type gormLogWriter struct {
	logger *zap.Logger
}

func (w *gormLogWriter) Printf(format string, v ...interface{}) {
	w.logger.Sugar().Infof(format, v...)
}

// ReadReplica manages read replica connections for scaling reads
type ReadReplica struct {
	manager    *DatabaseManager
	replicas   []*DatabaseManager
	currentIdx int
	logger     *zap.Logger
}

// NewReadReplica creates a read replica manager
func NewReadReplica(masterConfig ConnectionConfig, replicaConfigs []ConnectionConfig, serviceName string, logger *zap.Logger) (*ReadReplica, error) {
	// Create master connection
	master, err := NewDatabaseManager(masterConfig, serviceName+"-master", logger)
	if err != nil {
		return nil, fmt.Errorf("failed to create master connection: %w", err)
	}
	
	// Create replica connections
	replicas := make([]*DatabaseManager, len(replicaConfigs))
	for i, config := range replicaConfigs {
		replica, err := NewDatabaseManager(config, fmt.Sprintf("%s-replica-%d", serviceName, i), logger)
		if err != nil {
			// Close already created connections
			master.Close()
			for j := 0; j < i; j++ {
				replicas[j].Close()
			}
			return nil, fmt.Errorf("failed to create replica %d connection: %w", i, err)
		}
		replicas[i] = replica
	}
	
	return &ReadReplica{
		manager:  master,
		replicas: replicas,
		logger:   logger,
	}, nil
}

// GetWriteDB returns the master database for write operations
func (rr *ReadReplica) GetWriteDB() *gorm.DB {
	return rr.manager.GetDB()
}

// GetReadDB returns a read replica database (round-robin)
func (rr *ReadReplica) GetReadDB() *gorm.DB {
	if len(rr.replicas) == 0 {
		return rr.manager.GetDB() // Fallback to master
	}
	
	// Simple round-robin selection
	db := rr.replicas[rr.currentIdx].GetDB()
	rr.currentIdx = (rr.currentIdx + 1) % len(rr.replicas)
	
	return db
}

// Close closes all database connections
func (rr *ReadReplica) Close() error {
	// Close master
	if err := rr.manager.Close(); err != nil {
		rr.logger.Error("Failed to close master connection", zap.Error(err))
	}
	
	// Close replicas
	for i, replica := range rr.replicas {
		if err := replica.Close(); err != nil {
			rr.logger.Error("Failed to close replica connection", 
				zap.Int("replica", i), 
				zap.Error(err))
		}
	}
	
	return nil
}

// Transaction helper with metrics
func (dm *DatabaseManager) Transaction(fn func(*gorm.DB) error) error {
	return dm.ExecuteWithMetrics("transaction", func(db *gorm.DB) error {
		return db.Transaction(fn)
	})
}