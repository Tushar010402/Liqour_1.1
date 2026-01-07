package middleware

import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimiter implements a token bucket algorithm for rate limiting
type RateLimiter struct {
	visitors map[string]*visitor
	mu       sync.RWMutex
	rate     int           // requests per duration
	duration time.Duration // duration window
}

// visitor tracks the rate limit for each visitor
type visitor struct {
	tokens    int
	lastVisit time.Time
	mu        sync.Mutex
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(rate int, duration time.Duration) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     rate,
		duration: duration,
	}

	// Clean up old visitors periodically
	go rl.cleanupVisitors()

	return rl
}

// RateLimitMiddleware creates a Gin middleware for rate limiting
func (rl *RateLimiter) RateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get visitor identifier (IP + User ID for authenticated users)
		visitorKey := rl.getVisitorKey(c)

		// Get or create visitor
		v := rl.getVisitor(visitorKey)

		// Check rate limit
		if !v.allow(rl.rate, rl.duration) {
			rl.handleRateLimitExceeded(c)
			return
		}

		// Add rate limit headers
		rl.addRateLimitHeaders(c, v, rl.rate)

		c.Next()
	}
}

// AdvancedRateLimitMiddleware provides different limits based on user type
func AdvancedRateLimitMiddleware() gin.HandlerFunc {
	// Different rate limits for different user types
	publicLimiter := NewRateLimiter(60, time.Minute)      // 60 requests per minute for public
	userLimiter := NewRateLimiter(120, time.Minute)       // 120 requests per minute for authenticated users
	premiumLimiter := NewRateLimiter(300, time.Minute)    // 300 requests per minute for premium users
	adminLimiter := NewRateLimiter(600, time.Minute)      // 600 requests per minute for admins

	return func(c *gin.Context) {
		// Determine which rate limiter to use
		var limiter *RateLimiter

		// Check user role from context
		if role, exists := c.Get("role"); exists {
			switch role.(string) {
			case "admin", "super_admin":
				limiter = adminLimiter
			case "premium":
				limiter = premiumLimiter
			case "user":
				limiter = userLimiter
			default:
				limiter = publicLimiter
			}
		} else {
			limiter = publicLimiter
		}

		// Apply rate limiting
		visitorKey := limiter.getVisitorKey(c)
		v := limiter.getVisitor(visitorKey)

		if !v.allow(limiter.rate, limiter.duration) {
			limiter.handleRateLimitExceeded(c)
			return
		}

		limiter.addRateLimitHeaders(c, v, limiter.rate)
		c.Next()
	}
}

// getVisitorKey generates a unique key for each visitor
func (rl *RateLimiter) getVisitorKey(c *gin.Context) string {
	// Use IP address as base
	key := c.ClientIP()

	// Add user ID if authenticated
	if userID, exists := c.Get("user_id"); exists {
		key = fmt.Sprintf("%s:%v", key, userID)
	}

	// Add tenant ID for multi-tenant isolation
	if tenantID, exists := c.Get("tenant_id"); exists {
		key = fmt.Sprintf("%s:tenant:%v", key, tenantID)
	}

	return key
}

// getVisitor retrieves or creates a visitor
func (rl *RateLimiter) getVisitor(key string) *visitor {
	rl.mu.RLock()
	v, exists := rl.visitors[key]
	rl.mu.RUnlock()

	if !exists {
		rl.mu.Lock()
		v = &visitor{
			tokens:    rl.rate,
			lastVisit: time.Now(),
		}
		rl.visitors[key] = v
		rl.mu.Unlock()
	}

	return v
}

// allow checks if a request is allowed
func (v *visitor) allow(rate int, duration time.Duration) bool {
	v.mu.Lock()
	defer v.mu.Unlock()

	now := time.Now()

	// Refill tokens based on time elapsed
	elapsed := now.Sub(v.lastVisit)
	tokensToAdd := int(elapsed.Seconds() * float64(rate) / duration.Seconds())

	v.tokens = min(rate, v.tokens+tokensToAdd)
	v.lastVisit = now

	// Check if request is allowed
	if v.tokens <= 0 {
		return false
	}

	v.tokens--
	return true
}

// handleRateLimitExceeded handles rate limit exceeded responses
func (rl *RateLimiter) handleRateLimitExceeded(c *gin.Context) {
	c.Header("Retry-After", fmt.Sprintf("%d", int(rl.duration.Seconds())))
	c.JSON(http.StatusTooManyRequests, gin.H{
		"error": "Rate limit exceeded",
		"message": fmt.Sprintf("Too many requests. Please retry after %v", rl.duration),
		"retry_after": rl.duration.Seconds(),
	})
	c.Abort()
}

// addRateLimitHeaders adds rate limit information headers
func (rl *RateLimiter) addRateLimitHeaders(c *gin.Context, v *visitor, rate int) {
	v.mu.Lock()
	tokens := v.tokens
	v.mu.Unlock()

	c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", rate))
	c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", max(0, tokens)))
	c.Header("X-RateLimit-Reset", fmt.Sprintf("%d", time.Now().Add(rl.duration).Unix()))
}

// cleanupVisitors removes old visitor entries periodically
func (rl *RateLimiter) cleanupVisitors() {
	for {
		time.Sleep(time.Minute)

		rl.mu.Lock()
		for key, v := range rl.visitors {
			v.mu.Lock()
			if time.Since(v.lastVisit) > 5*time.Minute {
				delete(rl.visitors, key)
			}
			v.mu.Unlock()
		}
		rl.mu.Unlock()
	}
}

// Helper functions
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// EndpointRateLimiter provides per-endpoint rate limiting
type EndpointRateLimiter struct {
	limits map[string]*RateLimiter
	mu     sync.RWMutex
}

// NewEndpointRateLimiter creates a new endpoint-specific rate limiter
func NewEndpointRateLimiter() *EndpointRateLimiter {
	return &EndpointRateLimiter{
		limits: map[string]*RateLimiter{
			// === AUTH (CRITICAL - brute force prevention) ===
			"/api/auth/login":                NewRateLimiter(10, time.Minute),  // 10 login attempts per minute
			"/api/auth/register":             NewRateLimiter(5, time.Minute),   // 5 registrations per minute
			"/api/auth/send-otp":             NewRateLimiter(5, time.Minute),   // 5 OTP requests per minute (OTP bombing prevention)
			"/api/auth/send-otp-registration": NewRateLimiter(5, time.Minute),  // 5 OTP requests per minute
			"/api/auth/verify-otp":           NewRateLimiter(10, time.Minute),  // 10 OTP verifications per minute
			"/api/auth/forgot-password":      NewRateLimiter(5, time.Minute),   // 5 password reset requests per minute
			"/api/auth/reset-password":       NewRateLimiter(10, time.Minute),  // 10 password resets per minute
			"/api/auth/check-user":           NewRateLimiter(10, time.Minute),  // 10 user checks per minute
			"/api/auth/refresh":              NewRateLimiter(20, time.Minute),  // 20 token refreshes per minute
			"/api/auth/logout":               NewRateLimiter(20, time.Minute),  // 20 logouts per minute

			// === OCR/AI (EXPENSIVE - Gemini API cost protection) ===
			"/api/sales/ocr/batch/sessions":     NewRateLimiter(5, time.Minute),   // 5 OCR sessions per minute
			"/api/sales/ocr/batch/deduplicate":  NewRateLimiter(10, time.Minute),  // 10 deduplication requests per minute
			"/api/sales/ocr/batch/import":       NewRateLimiter(10, time.Minute),  // 10 imports per minute
			"/api/sales/ocr/brands/match":       NewRateLimiter(10, time.Minute),  // 10 brand matches per minute
			"/api/sales/ocr/brands/create":      NewRateLimiter(5, time.Minute),   // 5 brand creations per minute
			"/api/ocr/batch":                    NewRateLimiter(10, time.Minute),  // 10 OCR requests per minute

			// === FINANCE REPORTS (EXPENSIVE database queries) ===
			"/api/finance/reports/profit-loss":    NewRateLimiter(5, time.Minute),   // 5 P&L reports per minute
			"/api/finance/reports/cash-flow":      NewRateLimiter(5, time.Minute),   // 5 cash flow reports per minute
			"/api/finance/reports/balance-sheet":  NewRateLimiter(5, time.Minute),   // 5 balance sheet reports per minute
			"/api/finance/reports/expense-summary": NewRateLimiter(10, time.Minute), // 10 expense summaries per minute
			"/api/finance/reports/vendor-aging":   NewRateLimiter(10, time.Minute),  // 10 vendor aging reports per minute
			"/api/finance/dashboard/summary":      NewRateLimiter(10, time.Minute),  // 10 dashboard summaries per minute
			"/api/finance/matrix/dashboard":       NewRateLimiter(10, time.Minute),  // 10 matrix dashboards per minute
			"/api/finance/matrix/daily-metrics":   NewRateLimiter(10, time.Minute),  // 10 daily metrics per minute

			// === SALES DASHBOARDS & REPORTS ===
			"/api/sales/dashboard/summary":  NewRateLimiter(20, time.Minute),  // 20 sales dashboards per minute
			"/api/sales/summaries":          NewRateLimiter(20, time.Minute),  // 20 sales summaries per minute
			"/api/dashboard/summary":        NewRateLimiter(20, time.Minute),  // 20 dashboards per minute

			// === DETECTION/AUDIT (HEAVY analytics) ===
			"/api/detection/dashboard":        NewRateLimiter(10, time.Minute),  // 10 detection dashboards per minute
			"/api/detection/analytics/users":  NewRateLimiter(10, time.Minute),  // 10 user analytics per minute
			"/api/audit/dashboard":            NewRateLimiter(10, time.Minute),  // 10 audit dashboards per minute
			"/api/audit/reports/summary":      NewRateLimiter(10, time.Minute),  // 10 audit summaries per minute

			// === BULK/ADMIN OPERATIONS ===
			"/api/notifications/send-bulk":       NewRateLimiter(5, time.Minute),   // 5 bulk sends per minute
			"/api/super-admin/brands/bulk":       NewRateLimiter(10, time.Minute),  // 10 bulk brand ops per minute
			"/api/finance/cash/admin/bulk-reset": NewRateLimiter(5, time.Minute),   // 5 bulk resets per minute
			"/api/export":                        NewRateLimiter(5, time.Minute),   // 5 exports per minute

			// === ADMIN ROUTES ===
			"/api/admin/users":         NewRateLimiter(30, time.Minute),  // 30 user management ops per minute
			"/api/admin/shops":         NewRateLimiter(30, time.Minute),  // 30 shop management ops per minute
			"/api/admin/salesmen":      NewRateLimiter(30, time.Minute),  // 30 salesman management ops per minute
			"/api/saas-admin/tenants":  NewRateLimiter(60, time.Minute),  // 60 tenant ops per minute
			"/api/super-admin/tenants": NewRateLimiter(60, time.Minute),  // 60 tenant ops per minute

			// === INVENTORY OPERATIONS ===
			"/api/inventory/brands/with-variants": NewRateLimiter(5, time.Minute),   // 5 complex brand creations per minute
			"/api/inventory/reports/stock":        NewRateLimiter(10, time.Minute),  // 10 stock reports per minute
			"/api/inventory/reports/movement":     NewRateLimiter(10, time.Minute),  // 10 movement reports per minute
		},
	}
}

// Middleware returns the endpoint-specific rate limit middleware
func (erl *EndpointRateLimiter) Middleware() gin.HandlerFunc {
	// Default rate limiter for undefined endpoints
	defaultLimiter := NewRateLimiter(60, time.Minute)

	return func(c *gin.Context) {
		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}

		erl.mu.RLock()
		limiter, exists := erl.limits[path]
		erl.mu.RUnlock()

		if !exists {
			limiter = defaultLimiter
		}

		visitorKey := limiter.getVisitorKey(c)
		v := limiter.getVisitor(visitorKey)

		if !v.allow(limiter.rate, limiter.duration) {
			limiter.handleRateLimitExceeded(c)
			return
		}

		limiter.addRateLimitHeaders(c, v, limiter.rate)
		c.Next()
	}
}