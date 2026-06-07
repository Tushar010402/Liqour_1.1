package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/logger"
)

// LoggingMiddleware provides structured logging for HTTP requests
func LoggingMiddleware() gin.HandlerFunc {
	return logger.LogRequest
}

// CorrelationIDMiddleware adds correlation IDs for distributed tracing
// This middleware should be added first in the middleware chain
func CorrelationIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check for existing correlation ID from upstream services or clients
		correlationID := c.GetHeader("X-Correlation-ID")
		if correlationID == "" {
			// Check alternative header names
			correlationID = c.GetHeader("X-Request-ID")
		}

		// Generate new correlation ID if not present
		if correlationID == "" {
			correlationID = uuid.New().String()
		}

		// Set correlation ID in response headers for clients to track
		c.Header("X-Correlation-ID", correlationID)
		c.Header("X-Request-ID", correlationID)

		// Store in context for use throughout request lifecycle
		c.Set("correlation_id", correlationID)
		c.Set("request_id", correlationID)

		c.Next()
	}
}

// RequestIDMiddleware is an alias for CorrelationIDMiddleware
// for backward compatibility
func RequestIDMiddleware() gin.HandlerFunc {
	return CorrelationIDMiddleware()
}

// TraceContextMiddleware adds additional trace context for observability
func TraceContextMiddleware(serviceName, version string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Add service metadata to context
		c.Set("service_name", serviceName)
		c.Set("service_version", version)

		// Add trace span ID (different from correlation ID)
		spanID := uuid.New().String()
		c.Set("span_id", spanID)
		c.Header("X-Span-ID", spanID)

		c.Next()
	}
}
