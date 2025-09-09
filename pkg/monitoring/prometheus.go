package monitoring

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Prometheus metrics
var (
	// HTTP metrics
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "The total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status_code", "service"},
	)

	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "The HTTP request latencies in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "endpoint", "service"},
	)

	// Database metrics
	dbConnectionsActive = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "db_connections_active",
			Help: "Number of active database connections",
		},
		[]string{"service", "database"},
	)

	dbQueriesTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "db_queries_total",
			Help: "The total number of database queries",
		},
		[]string{"service", "operation", "status"},
	)

	dbQueryDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "db_query_duration_seconds",
			Help:    "The database query latencies in seconds",
			Buckets: []float64{.001, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
		},
		[]string{"service", "operation"},
	)

	// Business metrics
	activeUsersTotal = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "active_users_total",
			Help: "Number of active users by tenant",
		},
		[]string{"tenant_id", "service"},
	)

	businessOperationsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "business_operations_total",
			Help: "The total number of business operations",
		},
		[]string{"service", "operation", "tenant_id", "status"},
	)

	// System metrics
	memoryUsage = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "memory_usage_bytes",
			Help: "Memory usage in bytes",
		},
		[]string{"service", "type"},
	)

	goroutinesActive = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "goroutines_active",
			Help: "Number of active goroutines",
		},
		[]string{"service"},
	)

	// Redis metrics
	redisOperationsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "redis_operations_total",
			Help: "The total number of Redis operations",
		},
		[]string{"service", "operation", "status"},
	)

	redisConnectionsActive = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "redis_connections_active",
			Help: "Number of active Redis connections",
		},
		[]string{"service"},
	)
)

// PrometheusMiddleware tracks HTTP metrics
func PrometheusMiddleware(serviceName string) gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		start := time.Now()
		
		// Process request
		c.Next()
		
		// Calculate duration
		duration := time.Since(start)
		
		// Record metrics
		httpRequestsTotal.WithLabelValues(
			c.Request.Method,
			c.FullPath(),
			strconv.Itoa(c.Writer.Status()),
			serviceName,
		).Inc()
		
		httpRequestDuration.WithLabelValues(
			c.Request.Method,
			c.FullPath(),
			serviceName,
		).Observe(duration.Seconds())
	})
}

// RecordDBQuery records database query metrics
func RecordDBQuery(service, operation, status string, duration time.Duration) {
	dbQueriesTotal.WithLabelValues(service, operation, status).Inc()
	dbQueryDuration.WithLabelValues(service, operation).Observe(duration.Seconds())
}

// SetDBConnections sets active database connections
func SetDBConnections(service, database string, count float64) {
	dbConnectionsActive.WithLabelValues(service, database).Set(count)
}

// RecordBusinessOperation records business operation metrics
func RecordBusinessOperation(service, operation, tenantID, status string) {
	businessOperationsTotal.WithLabelValues(service, operation, tenantID, status).Inc()
}

// SetActiveUsers sets active user count
func SetActiveUsers(tenantID, service string, count float64) {
	activeUsersTotal.WithLabelValues(tenantID, service).Set(count)
}

// RecordRedisOperation records Redis operation metrics
func RecordRedisOperation(service, operation, status string) {
	redisOperationsTotal.WithLabelValues(service, operation, status).Inc()
}

// SetRedisConnections sets active Redis connections
func SetRedisConnections(service string, count float64) {
	redisConnectionsActive.WithLabelValues(service).Set(count)
}

// SetMemoryUsage sets memory usage metrics
func SetMemoryUsage(service, memType string, bytes float64) {
	memoryUsage.WithLabelValues(service, memType).Set(bytes)
}

// SetActiveGoroutines sets active goroutines count
func SetActiveGoroutines(service string, count float64) {
	goroutinesActive.WithLabelValues(service).Set(count)
}

// PrometheusHandler returns the Prometheus metrics handler
func PrometheusHandler() gin.HandlerFunc {
	h := promhttp.Handler()
	return gin.WrapH(h)
}

// StartMetricsServer starts a separate metrics server
func StartMetricsServer(port string, serviceName string) {
	router := gin.New()
	router.GET("/metrics", PrometheusHandler())
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"service": serviceName,
			"status":  "healthy",
			"metrics": "enabled",
		})
	})
	
	go router.Run(":" + port)
}