package middleware

import (
	"bytes"
	"io"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// RequestResponseLogger logs detailed request and response information
// Best practice: Use in development, limit in production to avoid log bloat
type RequestResponseLogger struct {
	logger *zap.Logger
	config LoggerConfig
}

type LoggerConfig struct {
	LogRequestBody  bool
	LogResponseBody bool
	MaxBodySize     int // Maximum bytes to log
	SkipPaths       []string
	SlowThreshold   time.Duration // Log warning if request takes longer
}

// NewRequestResponseLogger creates a new request/response logger
func NewRequestResponseLogger(logger *zap.Logger, config LoggerConfig) *RequestResponseLogger {
	if config.MaxBodySize == 0 {
		config.MaxBodySize = 1024 // Default 1KB max
	}
	if config.SlowThreshold == 0 {
		config.SlowThreshold = 500 * time.Millisecond
	}

	return &RequestResponseLogger{
		logger: logger,
		config: config,
	}
}

func (l *RequestResponseLogger) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check if path should be skipped
		for _, path := range l.config.SkipPaths {
			if c.Request.URL.Path == path {
				c.Next()
				return
			}
		}

		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		// Log request body if enabled
		var requestBody []byte
		if l.config.LogRequestBody && c.Request.Body != nil {
			requestBody, _ = io.ReadAll(io.LimitReader(c.Request.Body, int64(l.config.MaxBodySize)))
			c.Request.Body = io.NopCloser(bytes.NewBuffer(requestBody))
		}

		// Capture response using custom writer
		blw := &bodyLogWriter{body: make([]byte, 0), ResponseWriter: c.Writer}
		c.Writer = blw

		// Process request
		c.Next()

		// Calculate latency
		latency := time.Since(start)
		statusCode := c.Writer.Status()

		// Build log fields
		fields := []zap.Field{
			zap.String("method", c.Request.Method),
			zap.String("path", path),
			zap.String("query", query),
			zap.Int("status", statusCode),
			zap.Duration("latency", latency),
			zap.String("client_ip", c.ClientIP()),
			zap.String("user_agent", c.Request.UserAgent()),
		}

		// Add tenant info if available
		if tenantID := c.GetString("tenant_id"); tenantID != "" {
			fields = append(fields, zap.String("tenant_id", tenantID))
		}

		// Add user info if available
		if userID := c.GetString("user_id"); userID != "" {
			fields = append(fields, zap.String("user_id", userID))
		}

		// Log request body if enabled and present
		if l.config.LogRequestBody && len(requestBody) > 0 {
			fields = append(fields, zap.ByteString("request_body", requestBody))
		}

		// Log response body if enabled
		if l.config.LogResponseBody && len(blw.body) > 0 {
			responseBody := blw.body
			if len(responseBody) > l.config.MaxBodySize {
				responseBody = responseBody[:l.config.MaxBodySize]
			}
			fields = append(fields, zap.ByteString("response_body", responseBody))
		}

		// Write the actual response
		c.Writer = blw.ResponseWriter
		c.Writer.Write(blw.body)

		// Log based on status and performance
		if statusCode >= 500 {
			l.logger.Error("Server error", fields...)
		} else if statusCode >= 400 {
			l.logger.Warn("Client error", fields...)
		} else if latency > l.config.SlowThreshold {
			fields = append(fields, zap.String("warning", "slow_request"))
			l.logger.Warn("Slow request", fields...)
		} else {
			l.logger.Info("Request completed", fields...)
		}
	}
}

// SimpleRequestLogger provides basic request logging without body capture
// Best practice: Use in production for performance
func SimpleRequestLogger(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		statusCode := c.Writer.Status()
		method := c.Request.Method

		fields := []zap.Field{
			zap.String("method", method),
			zap.String("path", path),
			zap.String("query", query),
			zap.Int("status", statusCode),
			zap.Duration("latency", latency),
			zap.String("client_ip", c.ClientIP()),
		}

		if tenantID := c.GetString("tenant_id"); tenantID != "" {
			fields = append(fields, zap.String("tenant_id", tenantID))
		}

		if statusCode >= 500 {
			logger.Error("Request failed", fields...)
		} else if statusCode >= 400 {
			logger.Warn("Client error", fields...)
		} else {
			logger.Info("Request completed", fields...)
		}
	}
}
