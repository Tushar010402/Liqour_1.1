package middleware

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// AuditLog structure for logging
type AuditLog struct {
	Timestamp    time.Time              `json:"timestamp"`
	Method       string                 `json:"method"`
	Path         string                 `json:"path"`
	UserID       string                 `json:"user_id,omitempty"`
	TenantID     string                 `json:"tenant_id,omitempty"`
	IP           string                 `json:"ip"`
	UserAgent    string                 `json:"user_agent"`
	RequestBody  interface{}            `json:"request_body,omitempty"`
	QueryParams  map[string][]string    `json:"query_params,omitempty"`
	StatusCode   int                    `json:"status_code"`
	ResponseTime float64                `json:"response_time_ms"`
	ErrorMessage string                 `json:"error_message,omitempty"`
}

// AuditMiddleware logs all API requests for audit purposes
func AuditMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip health check endpoints
		if c.Request.URL.Path == "/health" || c.Request.URL.Path == "/metrics" {
			c.Next()
			return
		}

		start := time.Now()

		// Capture request body if present
		var requestBody interface{}
		if c.Request.Method != "GET" && c.Request.Method != "DELETE" {
			bodyBytes, _ := io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))

			// Try to parse as JSON
			if len(bodyBytes) > 0 {
				json.Unmarshal(bodyBytes, &requestBody)
			}
		}

		// Create response writer to capture status code
		blw := &bodyLogWriter{body: bytes.NewBufferString(""), ResponseWriter: c.Writer}
		c.Writer = blw

		// Process request
		c.Next()

		// Calculate response time
		duration := time.Since(start)

		// Extract user info from context
		userID, _ := c.Get("user_id")
		tenantID, _ := c.Get("tenant_id")

		// Create audit log entry
		auditLog := AuditLog{
			Timestamp:    start,
			Method:       c.Request.Method,
			Path:         c.Request.URL.Path,
			IP:           c.ClientIP(),
			UserAgent:    c.Request.UserAgent(),
			QueryParams:  c.Request.URL.Query(),
			StatusCode:   blw.Status(),
			ResponseTime: duration.Seconds() * 1000, // Convert to milliseconds
		}

		// Add user info if available
		if uid, ok := userID.(string); ok && uid != "" {
			auditLog.UserID = uid
		}
		if tid, ok := tenantID.(string); ok && tid != "" {
			auditLog.TenantID = tid
		}

		// Add request body for write operations
		if requestBody != nil && (c.Request.Method == "POST" || c.Request.Method == "PUT" || c.Request.Method == "PATCH") {
			// Sanitize sensitive data
			auditLog.RequestBody = sanitizeRequestBody(requestBody)
		}

		// Add error message if request failed
		if blw.Status() >= 400 {
			if err, exists := c.Get("error"); exists {
				if errStr, ok := err.(string); ok {
					auditLog.ErrorMessage = errStr
				}
			}
		}

		// Log to stdout in JSON format (can be captured by log aggregation systems)
		logJSON, _ := json.Marshal(auditLog)
		log.Printf("AUDIT: %s", string(logJSON))

		// For critical operations, you could also write to a database
		if shouldLogToDatabase(c.Request.Method, c.Request.URL.Path) {
			// TODO: Implement database logging for critical operations
			// e.g., tenant creation, deletion, role changes, etc.
		}
	}
}

// bodyLogWriter captures response status code
type bodyLogWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w bodyLogWriter) Write(b []byte) (int, error) {
	w.body.Write(b)
	return w.ResponseWriter.Write(b)
}

func (w bodyLogWriter) Status() int {
	if w.ResponseWriter.Status() == 0 {
		return 200
	}
	return w.ResponseWriter.Status()
}

// sanitizeRequestBody removes sensitive data from request body
func sanitizeRequestBody(body interface{}) interface{} {
	if bodyMap, ok := body.(map[string]interface{}); ok {
		// Remove sensitive fields
		sensitiveFields := []string{"password", "token", "secret", "api_key", "credit_card"}
		for _, field := range sensitiveFields {
			if _, exists := bodyMap[field]; exists {
				bodyMap[field] = "[REDACTED]"
			}
		}
	}
	return body
}

// shouldLogToDatabase determines if the operation should be logged to database
func shouldLogToDatabase(method, path string) bool {
	// Log critical operations to database for compliance
	criticalPaths := []string{
		"/tenants",
		"/users",
		"/roles",
		"/permissions",
		"/billing",
		"/subscriptions",
	}

	for _, critical := range criticalPaths {
		if method != "GET" && contains(path, critical) {
			return true
		}
	}

	return false
}

func contains(str, substr string) bool {
	return bytes.Contains([]byte(str), []byte(substr))
}