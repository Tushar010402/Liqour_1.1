package logger

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var (
	// Logger is the global logger instance
	Logger *zap.Logger
	// Sugar is the sugared logger for convenience
	Sugar *zap.SugaredLogger
)

// Config holds logger configuration
type Config struct {
	Level       string `json:"level"`
	Environment string `json:"environment"`
	ServiceName string `json:"service_name"`
}

// Initialize sets up the logger based on environment
func Initialize(cfg Config) error {
	var config zap.Config
	
	if cfg.Environment == "production" {
		config = zap.NewProductionConfig()
		config.EncoderConfig.TimeKey = "timestamp"
		config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	} else {
		config = zap.NewDevelopmentConfig()
		config.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	}
	
	// Set log level
	switch cfg.Level {
	case "debug":
		config.Level = zap.NewAtomicLevelAt(zap.DebugLevel)
	case "info":
		config.Level = zap.NewAtomicLevelAt(zap.InfoLevel)
	case "warn":
		config.Level = zap.NewAtomicLevelAt(zap.WarnLevel)
	case "error":
		config.Level = zap.NewAtomicLevelAt(zap.ErrorLevel)
	default:
		config.Level = zap.NewAtomicLevelAt(zap.InfoLevel)
	}
	
	// Build logger
	var err error
	Logger, err = config.Build(
		zap.AddCaller(),
		zap.AddStacktrace(zapcore.ErrorLevel),
		zap.Fields(
			zap.String("service", cfg.ServiceName),
			zap.String("environment", cfg.Environment),
			zap.Int("pid", os.Getpid()),
		),
	)
	
	if err != nil {
		return fmt.Errorf("failed to initialize logger: %w", err)
	}
	
	Sugar = Logger.Sugar()
	return nil
}

// WithContext returns a logger with context fields
func WithContext(ctx context.Context) *zap.Logger {
	if Logger == nil {
		return zap.NewNop()
	}
	
	logger := Logger
	
	// Add common context fields
	if requestID := ctx.Value("request_id"); requestID != nil {
		logger = logger.With(zap.String("request_id", requestID.(string)))
	}
	
	if userID := ctx.Value("user_id"); userID != nil {
		logger = logger.With(zap.String("user_id", userID.(string)))
	}
	
	if tenantID := ctx.Value("tenant_id"); tenantID != nil {
		logger = logger.With(zap.String("tenant_id", tenantID.(string)))
	}
	
	return logger
}

// WithGinContext returns a logger with Gin context fields
func WithGinContext(c *gin.Context) *zap.Logger {
	if Logger == nil {
		return zap.NewNop()
	}
	
	logger := Logger.With(
		zap.String("method", c.Request.Method),
		zap.String("path", c.Request.URL.Path),
		zap.String("client_ip", c.ClientIP()),
	)
	
	if requestID := c.GetString("request_id"); requestID != "" {
		logger = logger.With(zap.String("request_id", requestID))
	}
	
	if userID := c.GetString("user_id"); userID != "" {
		logger = logger.With(zap.String("user_id", userID))
	}
	
	if tenantID := c.GetString("tenant_id"); tenantID != "" {
		logger = logger.With(zap.String("tenant_id", tenantID))
	}
	
	if role := c.GetString("role"); role != "" {
		logger = logger.With(zap.String("role", role))
	}
	
	return logger
}

// LogRequest logs incoming HTTP requests
func LogRequest(c *gin.Context) {
	start := time.Now()
	path := c.Request.URL.Path
	raw := c.Request.URL.RawQuery
	
	// Process request
	c.Next()
	
	// Log after request is processed
	latency := time.Since(start)
	clientIP := c.ClientIP()
	method := c.Request.Method
	statusCode := c.Writer.Status()
	errorMessage := c.Errors.ByType(gin.ErrorTypePrivate).String()
	
	if raw != "" {
		path = path + "?" + raw
	}
	
	logger := WithGinContext(c)
	
	fields := []zap.Field{
		zap.Int("status", statusCode),
		zap.Duration("latency", latency),
		zap.String("user_agent", c.Request.UserAgent()),
	}
	
	if errorMessage != "" {
		fields = append(fields, zap.String("error", errorMessage))
	}
	
	// Log based on status code
	switch {
	case statusCode >= 500:
		logger.Error("Server error", fields...)
	case statusCode >= 400:
		logger.Warn("Client error", fields...)
	case statusCode >= 300:
		logger.Info("Redirect", fields...)
	default:
		logger.Info("Request completed", fields...)
	}
}

// LogDatabaseQuery logs database queries for debugging
func LogDatabaseQuery(query string, duration time.Duration, rowsAffected int64) {
	if Logger == nil {
		return
	}
	
	Logger.Debug("Database query",
		zap.String("query", query),
		zap.Duration("duration", duration),
		zap.Int64("rows_affected", rowsAffected),
	)
}

// LogServiceCall logs calls to other services
func LogServiceCall(service string, method string, url string, statusCode int, duration time.Duration) {
	if Logger == nil {
		return
	}
	
	fields := []zap.Field{
		zap.String("service", service),
		zap.String("method", method),
		zap.String("url", url),
		zap.Int("status_code", statusCode),
		zap.Duration("duration", duration),
	}
	
	if statusCode >= 500 {
		Logger.Error("Service call failed", fields...)
	} else if statusCode >= 400 {
		Logger.Warn("Service call client error", fields...)
	} else {
		Logger.Info("Service call completed", fields...)
	}
}

// LogCriticalOperation logs critical business operations
func LogCriticalOperation(operation string, details map[string]interface{}, success bool) {
	if Logger == nil {
		return
	}
	
	fields := []zap.Field{
		zap.String("operation", operation),
		zap.Bool("success", success),
		zap.Any("details", details),
	}
	
	if success {
		Logger.Info("Critical operation completed", fields...)
	} else {
		Logger.Error("Critical operation failed", fields...)
	}
}

// LogMoneyCollection logs money collection operations (critical 15-minute deadline)
func LogMoneyCollection(collectionID string, action string, approved bool, deadline time.Time) {
	if Logger == nil {
		return
	}
	
	Logger.Info("Money collection action",
		zap.String("collection_id", collectionID),
		zap.String("action", action),
		zap.Bool("approved", approved),
		zap.Time("deadline", deadline),
		zap.Duration("time_remaining", time.Until(deadline)),
	)
}

// LogAudit logs audit trail events
func LogAudit(userID string, tenantID string, action string, resource string, resourceID string, changes map[string]interface{}) {
	if Logger == nil {
		return
	}
	
	Logger.Info("Audit event",
		zap.String("user_id", userID),
		zap.String("tenant_id", tenantID),
		zap.String("action", action),
		zap.String("resource", resource),
		zap.String("resource_id", resourceID),
		zap.Any("changes", changes),
		zap.Time("timestamp", time.Now()),
	)
}

// LogSecurity logs security-related events
func LogSecurity(event string, userID string, ip string, details map[string]interface{}) {
	if Logger == nil {
		return
	}
	
	Logger.Warn("Security event",
		zap.String("event", event),
		zap.String("user_id", userID),
		zap.String("ip", ip),
		zap.Any("details", details),
	)
}

// Fatal logs a fatal error and exits
func Fatal(msg string, fields ...zap.Field) {
	if Logger != nil {
		Logger.Fatal(msg, fields...)
	}
	os.Exit(1)
}

// Error logs an error
func Error(msg string, fields ...zap.Field) {
	if Logger != nil {
		Logger.Error(msg, fields...)
	}
}

// Warn logs a warning
func Warn(msg string, fields ...zap.Field) {
	if Logger != nil {
		Logger.Warn(msg, fields...)
	}
}

// Info logs an info message
func Info(msg string, fields ...zap.Field) {
	if Logger != nil {
		Logger.Info(msg, fields...)
	}
}

// Debug logs a debug message
func Debug(msg string, fields ...zap.Field) {
	if Logger != nil {
		Logger.Debug(msg, fields...)
	}
}

// Sync flushes any buffered log entries
func Sync() error {
	if Logger != nil {
		return Logger.Sync()
	}
	return nil
}