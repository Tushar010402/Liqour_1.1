package middleware

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

const (
	// Max file size for OCR images (10MB)
	MaxOCRImageSize = 10 * 1024 * 1024

	// Supported image types
	ImageTypeJPEG = "jpeg"
	ImageTypePNG  = "png"
	ImageTypeJPG  = "jpg"

	// Rate limiting
	MaxOCRRequestsPerMinute = 10
	MaxOCRRequestsPerHour   = 100
)

// OCRRateLimiter tracks OCR request rates per user
type OCRRateLimiter struct {
	requests map[string][]time.Time
	logger   *logrus.Logger
}

// NewOCRRateLimiter creates a new rate limiter for OCR requests
func NewOCRRateLimiter(logger *logrus.Logger) *OCRRateLimiter {
	return &OCRRateLimiter{
		requests: make(map[string][]time.Time),
		logger:   logger,
	}
}

// OCRValidationMiddleware validates OCR requests
func OCRValidationMiddleware(logger *logrus.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Log request start
		startTime := time.Now()
		path := c.Request.URL.Path

		logger.WithFields(logrus.Fields{
			"method":     c.Request.Method,
			"path":       path,
			"client_ip":  c.ClientIP(),
			"user_agent": c.Request.UserAgent(),
		}).Info("OCR request started")

		// Only validate OCR endpoints
		if !strings.Contains(path, "/ocr") {
			c.Next()
			return
		}

		// Validate request method
		if c.Request.Method == http.MethodPost {
			// Read body for validation
			bodyBytes, err := io.ReadAll(c.Request.Body)
			if err != nil {
				logger.Errorf("Failed to read request body: %v", err)
				c.JSON(http.StatusBadRequest, gin.H{
					"error": "Invalid request body",
				})
				c.Abort()
				return
			}

			// Restore body for next handlers
			c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))

			// Check content size
			if len(bodyBytes) > MaxOCRImageSize {
				logger.Warnf("OCR image too large: %d bytes", len(bodyBytes))
				c.JSON(http.StatusRequestEntityTooLarge, gin.H{
					"error": fmt.Sprintf("Image size exceeds maximum of %d MB", MaxOCRImageSize/(1024*1024)),
				})
				c.Abort()
				return
			}

			// Log request size
			logger.Debugf("OCR request body size: %d bytes", len(bodyBytes))
		}

		c.Next()

		// Log request completion
		latency := time.Since(startTime)
		statusCode := c.Writer.Status()

		logFields := logrus.Fields{
			"status":   statusCode,
			"latency":  latency.Milliseconds(),
			"method":   c.Request.Method,
			"path":     path,
		}

		if statusCode >= 400 {
			logger.WithFields(logFields).Warn("OCR request failed")
		} else {
			logger.WithFields(logFields).Info("OCR request completed")
		}
	}
}

// OCRRateLimitMiddleware implements rate limiting for OCR requests
func (r *OCRRateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip non-OCR endpoints
		if !strings.Contains(c.Request.URL.Path, "/ocr") {
			c.Next()
			return
		}

		userID := c.GetHeader("X-User-ID")
		if userID == "" {
			userID = c.ClientIP() // Fallback to IP
		}

		now := time.Now()

		// Clean old requests
		r.cleanOldRequests(userID, now)

		// Check rate limits
		userRequests := r.requests[userID]

		// Count requests in last minute
		minuteAgo := now.Add(-time.Minute)
		recentRequests := 0
		for _, reqTime := range userRequests {
			if reqTime.After(minuteAgo) {
				recentRequests++
			}
		}

		if recentRequests >= MaxOCRRequestsPerMinute {
			r.logger.Warnf("Rate limit exceeded for user %s: %d requests/minute", userID, recentRequests)
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "Rate limit exceeded. Please wait before making more OCR requests.",
				"retry_after": "60",
			})
			c.Abort()
			return
		}

		// Count requests in last hour
		hourAgo := now.Add(-time.Hour)
		hourlyRequests := 0
		for _, reqTime := range userRequests {
			if reqTime.After(hourAgo) {
				hourlyRequests++
			}
		}

		if hourlyRequests >= MaxOCRRequestsPerHour {
			r.logger.Warnf("Hourly rate limit exceeded for user %s: %d requests/hour", userID, hourlyRequests)
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "Hourly rate limit exceeded. Please try again later.",
				"retry_after": "3600",
			})
			c.Abort()
			return
		}

		// Add current request
		r.requests[userID] = append(r.requests[userID], now)

		c.Next()
	}
}

// cleanOldRequests removes requests older than 1 hour
func (r *OCRRateLimiter) cleanOldRequests(userID string, now time.Time) {
	cutoff := now.Add(-time.Hour)
	cleaned := []time.Time{}

	for _, reqTime := range r.requests[userID] {
		if reqTime.After(cutoff) {
			cleaned = append(cleaned, reqTime)
		}
	}

	r.requests[userID] = cleaned
}

// OCRImageTypeValidator validates image types
func OCRImageTypeValidator() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Only validate OCR image uploads
		if !strings.Contains(c.Request.URL.Path, "/ocr") {
			c.Next()
			return
		}

		// Check for image_type in JSON body
		var body map[string]interface{}
		if err := c.ShouldBindJSON(&body); err == nil {
			if imageType, ok := body["image_type"].(string); ok {
				// Validate image type
				imageType = strings.ToLower(imageType)
				if imageType != ImageTypeJPEG && imageType != ImageTypePNG && imageType != ImageTypeJPG {
					c.JSON(http.StatusBadRequest, gin.H{
						"error": fmt.Sprintf("Unsupported image type: %s. Supported types: jpeg, jpg, png", imageType),
					})
					c.Abort()
					return
				}
			}
		}

		c.Next()
	}
}

// OCRCircuitBreaker implements circuit breaker pattern for OCR service
type OCRCircuitBreaker struct {
	failures      int
	lastFailTime  time.Time
	state         string // "closed", "open", "half-open"
	maxFailures   int
	timeout       time.Duration
	logger        *logrus.Logger
}

// NewOCRCircuitBreaker creates a new circuit breaker
func NewOCRCircuitBreaker(logger *logrus.Logger) *OCRCircuitBreaker {
	return &OCRCircuitBreaker{
		state:       "closed",
		maxFailures: 5,
		timeout:     30 * time.Second,
		logger:      logger,
	}
}

// Middleware returns the circuit breaker middleware
func (cb *OCRCircuitBreaker) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Only apply to OCR endpoints
		if !strings.Contains(c.Request.URL.Path, "/ocr") {
			c.Next()
			return
		}

		// Check circuit breaker state
		if cb.state == "open" {
			// Check if timeout has passed
			if time.Since(cb.lastFailTime) > cb.timeout {
				cb.state = "half-open"
				cb.logger.Info("OCR circuit breaker: transitioning to half-open")
			} else {
				cb.logger.Warn("OCR circuit breaker: request rejected (circuit open)")
				c.JSON(http.StatusServiceUnavailable, gin.H{
					"error": "OCR service temporarily unavailable. Please try again later.",
					"retry_after": cb.timeout.Seconds(),
				})
				c.Abort()
				return
			}
		}

		// Process request
		c.Next()

		// Check response status
		statusCode := c.Writer.Status()

		if statusCode >= 500 {
			// Service error - record failure
			cb.recordFailure()
		} else if statusCode < 400 {
			// Success - reset if in half-open state
			if cb.state == "half-open" {
				cb.reset()
			}
		}
	}
}

// recordFailure records a failure and potentially opens the circuit
func (cb *OCRCircuitBreaker) recordFailure() {
	cb.failures++
	cb.lastFailTime = time.Now()

	if cb.failures >= cb.maxFailures {
		cb.state = "open"
		cb.logger.Errorf("OCR circuit breaker: opening circuit after %d failures", cb.failures)
	}
}

// reset resets the circuit breaker
func (cb *OCRCircuitBreaker) reset() {
	cb.failures = 0
	cb.state = "closed"
	cb.logger.Info("OCR circuit breaker: circuit reset to closed")
}

// OCRMetricsMiddleware collects metrics for OCR operations
func OCRMetricsMiddleware(logger *logrus.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !strings.Contains(c.Request.URL.Path, "/ocr") {
			c.Next()
			return
		}

		startTime := time.Now()

		// Add request ID for tracing
		requestID := fmt.Sprintf("ocr-%d-%d", time.Now().Unix(), time.Now().Nanosecond())
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)

		c.Next()

		// Collect metrics
		duration := time.Since(startTime)
		statusCode := c.Writer.Status()

		// Log metrics
		logger.WithFields(logrus.Fields{
			"request_id": requestID,
			"duration_ms": duration.Milliseconds(),
			"status": statusCode,
			"endpoint": c.Request.URL.Path,
			"method": c.Request.Method,
		}).Info("OCR metrics")

		// You can send these metrics to Prometheus, Datadog, etc.
	}
}