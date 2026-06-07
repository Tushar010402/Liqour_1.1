package middleware

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// HTTP metrics
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		},
		[]string{"method", "endpoint", "status"},
	)

	httpRequestSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_size_bytes",
			Help:    "HTTP request size in bytes",
			Buckets: []float64{100, 1000, 10000, 100000, 1000000},
		},
		[]string{"method", "endpoint"},
	)

	httpResponseSize = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_response_size_bytes",
			Help:    "HTTP response size in bytes",
			Buckets: []float64{100, 1000, 10000, 100000, 1000000},
		},
		[]string{"method", "endpoint"},
	)

	// Business metrics
	authFailedLoginAttempts = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "auth_failed_login_attempts_total",
			Help: "Total number of failed login attempts",
		},
	)

	authSuccessfulLogins = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "auth_successful_logins_total",
			Help: "Total number of successful logins",
		},
	)

	salesTransactionsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "sales_transactions_total",
			Help: "Total number of sales transactions",
		},
		[]string{"status", "payment_method"},
	)

	salesRevenue = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "sales_revenue_total",
			Help: "Total sales revenue",
		},
		[]string{"currency", "shop_id"},
	)

	inventoryStockLevel = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "inventory_stock_level",
			Help: "Current stock levels",
		},
		[]string{"product_id", "level"},
	)

	paymentErrorsTotal = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "payment_errors_total",
			Help: "Total number of payment processing errors",
		},
	)

	apiRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "api_requests_total",
			Help: "Total number of API requests",
		},
		[]string{"user_id", "endpoint"},
	)

	// Database metrics
	dbConnectionsActive = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "db_connections_active",
			Help: "Number of active database connections",
		},
	)

	dbQueriesTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "db_queries_total",
			Help: "Total number of database queries",
		},
		[]string{"query_type"},
	)

	dbQueryDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "db_query_duration_seconds",
			Help:    "Database query duration in seconds",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		},
		[]string{"query_type"},
	)

	// Cache metrics
	cacheHits = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "cache_hits_total",
			Help: "Total number of cache hits",
		},
	)

	cacheMisses = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "cache_misses_total",
			Help: "Total number of cache misses",
		},
	)
)

// PrometheusMiddleware creates a Gin middleware for Prometheus metrics collection
func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip metrics endpoint to avoid recursion
		if c.Request.URL.Path == "/metrics" {
			c.Next()
			return
		}

		start := time.Now()
		requestSize := computeRequestSize(c.Request)

		// Process request
		c.Next()

		// Calculate metrics
		duration := time.Since(start).Seconds()
		status := strconv.Itoa(c.Writer.Status())
		endpoint := c.FullPath()
		if endpoint == "" {
			endpoint = "unknown"
		}
		method := c.Request.Method
		responseSize := float64(c.Writer.Size())

		// Update metrics
		httpRequestsTotal.WithLabelValues(method, endpoint, status).Inc()
		httpRequestDuration.WithLabelValues(method, endpoint, status).Observe(duration)
		httpRequestSize.WithLabelValues(method, endpoint).Observe(float64(requestSize))
		httpResponseSize.WithLabelValues(method, endpoint).Observe(responseSize)

		// Update API metrics if user is authenticated
		if userID := c.GetString("user_id"); userID != "" {
			apiRequestsTotal.WithLabelValues(userID, endpoint).Inc()
		}
	}
}

// PrometheusHandler returns the HTTP handler for metrics endpoint
func PrometheusHandler() gin.HandlerFunc {
	h := promhttp.Handler()
	return func(c *gin.Context) {
		h.ServeHTTP(c.Writer, c.Request)
	}
}

// Helper function to compute request size
func computeRequestSize(r *http.Request) int64 {
	size := int64(0)
	if r.ContentLength > 0 {
		size = r.ContentLength
	}
	return size
}

// Business Metrics Recording Functions

// RecordFailedLogin records a failed login attempt
func RecordFailedLogin() {
	authFailedLoginAttempts.Inc()
}

// RecordSuccessfulLogin records a successful login
func RecordSuccessfulLogin() {
	authSuccessfulLogins.Inc()
}

// RecordSalesTransaction records a sales transaction
func RecordSalesTransaction(status, paymentMethod string, amount float64, currency, shopID string) {
	salesTransactionsTotal.WithLabelValues(status, paymentMethod).Inc()
	salesRevenue.WithLabelValues(currency, shopID).Add(amount)
}

// RecordInventoryLevel records inventory stock levels
func RecordInventoryLevel(productID string, level string, quantity float64) {
	inventoryStockLevel.WithLabelValues(productID, level).Set(quantity)
}

// RecordPaymentError records a payment processing error
func RecordPaymentError() {
	paymentErrorsTotal.Inc()
}

// RecordDBQuery records database query metrics
func RecordDBQuery(queryType string, duration time.Duration) {
	dbQueriesTotal.WithLabelValues(queryType).Inc()
	dbQueryDuration.WithLabelValues(queryType).Observe(duration.Seconds())
}

// SetDBConnections sets the number of active database connections
func SetDBConnections(count float64) {
	dbConnectionsActive.Set(count)
}

// RecordCacheHit records a cache hit
func RecordCacheHit() {
	cacheHits.Inc()
}

// RecordCacheMiss records a cache miss
func RecordCacheMiss() {
	cacheMisses.Inc()
}

// Custom metrics for specific business operations
var (
	// OCR processing metrics
	ocrProcessingDuration = promauto.NewHistogram(
		prometheus.HistogramOpts{
			Name:    "ocr_processing_duration_seconds",
			Help:    "Time taken to process OCR requests",
			Buckets: []float64{0.1, 0.5, 1, 2, 5, 10, 30},
		},
	)

	ocrProcessingErrors = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "ocr_processing_errors_total",
			Help: "Total number of OCR processing errors",
		},
	)

	// Tenant metrics
	tenantsActive = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "tenants_active_total",
			Help: "Total number of active tenants",
		},
	)

	tenantUsersTotal = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tenant_users_total",
			Help: "Total users per tenant",
		},
		[]string{"tenant_id"},
	)

	// Rate limiting metrics
	rateLimitHits = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "rate_limit_hits_total",
			Help: "Number of rate limit hits",
		},
		[]string{"endpoint", "user_id"},
	)
)

// RecordOCRProcessing records OCR processing metrics
func RecordOCRProcessing(duration time.Duration, success bool) {
	ocrProcessingDuration.Observe(duration.Seconds())
	if !success {
		ocrProcessingErrors.Inc()
	}
}

// SetActiveTenants sets the number of active tenants
func SetActiveTenants(count float64) {
	tenantsActive.Set(count)
}

// SetTenantUsers sets the number of users for a tenant
func SetTenantUsers(tenantID string, count float64) {
	tenantUsersTotal.WithLabelValues(tenantID).Set(count)
}

// RecordRateLimitHit records when a rate limit is hit
func RecordRateLimitHit(endpoint, userID string) {
	rateLimitHits.WithLabelValues(endpoint, userID).Inc()
}