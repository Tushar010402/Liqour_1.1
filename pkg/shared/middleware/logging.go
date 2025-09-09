package middleware

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/pkg/shared/logger"
)

// LoggingMiddleware provides structured logging for HTTP requests
func LoggingMiddleware() gin.HandlerFunc {
	return logger.LogRequest
}

// RequestIDMiddleware adds unique request IDs
func RequestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			// Generate a simple request ID (you might want to use UUID here)
			requestID = generateRequestID()
		}
		
		c.Header("X-Request-ID", requestID)
		c.Set("request_id", requestID)
		
		c.Next()
	}
}

func generateRequestID() string {
	return time.Now().Format("20060102150405") + "-" + randomString(6)
}

func randomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, n)
	for i := range result {
		result[i] = letters[time.Now().UnixNano()%int64(len(letters))]
	}
	return string(result)
}