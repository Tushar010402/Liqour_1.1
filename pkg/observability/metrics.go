package observability

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"
)

// MetricsCollector manages all application metrics
type MetricsCollector struct {
	// HTTP metrics
	httpRequestsTotal    *prometheus.CounterVec
	httpRequestDuration  *prometheus.HistogramVec
	httpResponseSize     *prometheus.HistogramVec
	httpActiveRequests   prometheus.Gauge

	// Business metrics
	salesTotal           *prometheus.CounterVec
	salesAmount          *prometheus.CounterVec
	inventoryLevels      *prometheus.GaugeVec
	stockAdjustments     *prometheus.CounterVec
	returnsTotal         *prometheus.CounterVec

	// WebSocket metrics
	wsConnections        prometheus.Gauge
	wsMessagesTotal      *prometheus.CounterVec
	wsMessageDuration    *prometheus.HistogramVec
	wsChannelSubscribers *prometheus.GaugeVec

	// Circuit breaker metrics
	circuitBreakerState  *prometheus.GaugeVec
	circuitBreakerTrips  *prometheus.CounterVec

	// Rate limiter metrics
	rateLimiterHits      *prometheus.CounterVec
	rateLimiterRejected  *prometheus.CounterVec
	rateLimiterTokens    *prometheus.GaugeVec

	// Database metrics
	dbQueryDuration      *prometheus.HistogramVec
	dbConnectionsActive  prometheus.Gauge
	dbConnectionsIdle    prometheus.Gauge
	dbErrors             *prometheus.CounterVec

	// Cache metrics
	cacheHits            *prometheus.CounterVec
	cacheMisses          *prometheus.CounterVec
	cacheEvictions       *prometheus.CounterVec
	cacheSizeBytes       prometheus.Gauge

	// Event sourcing metrics
	eventsStored         *prometheus.CounterVec
	eventsProcessed      *prometheus.CounterVec
	eventLag             *prometheus.GaugeVec
	projectionLag        *prometheus.GaugeVec

	// System metrics
	goroutinesCount      prometheus.Gauge
	memoryUsage          *prometheus.GaugeVec
	cpuUsage             prometheus.Gauge
	gcDuration           prometheus.Summary

	// Custom business metrics
	userRegistrations    *prometheus.CounterVec
	loginAttempts        *prometheus.CounterVec
	tenantActivity       *prometheus.GaugeVec
	revenueTotal         *prometheus.CounterVec

	logger *zap.Logger
}

// NewMetricsCollector creates a new metrics collector
func NewMetricsCollector(logger *zap.Logger) *MetricsCollector {
	mc := &MetricsCollector{
		logger: logger,

		// HTTP metrics
		httpRequestsTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "http_requests_total",
				Help: "Total number of HTTP requests",
			},
			[]string{"method", "path", "status"},
		),
		httpRequestDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_request_duration_seconds",
				Help:    "HTTP request duration in seconds",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"method", "path", "status"},
		),
		httpResponseSize: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_response_size_bytes",
				Help:    "HTTP response size in bytes",
				Buckets: prometheus.ExponentialBuckets(100, 2, 10),
			},
			[]string{"method", "path"},
		),
		httpActiveRequests: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "http_active_requests",
				Help: "Number of active HTTP requests",
			},
		),

		// Business metrics
		salesTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "sales_total",
				Help: "Total number of sales",
			},
			[]string{"tenant_id", "shop_id", "status"},
		),
		salesAmount: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "sales_amount_total",
				Help: "Total sales amount",
			},
			[]string{"tenant_id", "shop_id", "currency"},
		),
		inventoryLevels: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "inventory_levels",
				Help: "Current inventory levels",
			},
			[]string{"tenant_id", "shop_id", "product_id", "category"},
		),
		stockAdjustments: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "stock_adjustments_total",
				Help: "Total number of stock adjustments",
			},
			[]string{"tenant_id", "shop_id", "type", "reason"},
		),
		returnsTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "returns_total",
				Help: "Total number of returns",
			},
			[]string{"tenant_id", "shop_id", "reason"},
		),

		// WebSocket metrics
		wsConnections: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "websocket_connections_active",
				Help: "Number of active WebSocket connections",
			},
		),
		wsMessagesTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "websocket_messages_total",
				Help: "Total number of WebSocket messages",
			},
			[]string{"type", "direction"},
		),
		wsMessageDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "websocket_message_duration_seconds",
				Help:    "WebSocket message processing duration",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"type"},
		),
		wsChannelSubscribers: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "websocket_channel_subscribers",
				Help: "Number of subscribers per channel",
			},
			[]string{"channel"},
		),

		// Circuit breaker metrics
		circuitBreakerState: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "circuit_breaker_state",
				Help: "Circuit breaker state (0=closed, 1=open, 2=half-open)",
			},
			[]string{"name"},
		),
		circuitBreakerTrips: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "circuit_breaker_trips_total",
				Help: "Total number of circuit breaker trips",
			},
			[]string{"name"},
		),

		// Rate limiter metrics
		rateLimiterHits: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "rate_limiter_hits_total",
				Help: "Total number of rate limiter hits",
			},
			[]string{"name"},
		),
		rateLimiterRejected: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "rate_limiter_rejected_total",
				Help: "Total number of rate limiter rejections",
			},
			[]string{"name"},
		),
		rateLimiterTokens: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "rate_limiter_tokens_available",
				Help: "Available tokens in rate limiter",
			},
			[]string{"name"},
		),

		// Database metrics
		dbQueryDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "db_query_duration_seconds",
				Help:    "Database query duration",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"query_type", "table"},
		),
		dbConnectionsActive: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "db_connections_active",
				Help: "Number of active database connections",
			},
		),
		dbConnectionsIdle: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "db_connections_idle",
				Help: "Number of idle database connections",
			},
		),
		dbErrors: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "db_errors_total",
				Help: "Total number of database errors",
			},
			[]string{"operation", "error_type"},
		),

		// Cache metrics
		cacheHits: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "cache_hits_total",
				Help: "Total number of cache hits",
			},
			[]string{"cache_type"},
		),
		cacheMisses: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "cache_misses_total",
				Help: "Total number of cache misses",
			},
			[]string{"cache_type"},
		),
		cacheEvictions: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "cache_evictions_total",
				Help: "Total number of cache evictions",
			},
			[]string{"cache_type", "reason"},
		),
		cacheSizeBytes: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "cache_size_bytes",
				Help: "Current cache size in bytes",
			},
		),

		// Event sourcing metrics
		eventsStored: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "events_stored_total",
				Help: "Total number of events stored",
			},
			[]string{"event_type", "aggregate_type"},
		),
		eventsProcessed: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "events_processed_total",
				Help: "Total number of events processed",
			},
			[]string{"event_type", "handler"},
		),
		eventLag: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "event_lag_seconds",
				Help: "Event processing lag in seconds",
			},
			[]string{"event_type"},
		),
		projectionLag: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "projection_lag_seconds",
				Help: "Projection lag in seconds",
			},
			[]string{"projection_name"},
		),

		// System metrics
		goroutinesCount: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "goroutines_count",
				Help: "Current number of goroutines",
			},
		),
		memoryUsage: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "memory_usage_bytes",
				Help: "Memory usage in bytes",
			},
			[]string{"type"},
		),
		cpuUsage: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "cpu_usage_percent",
				Help: "CPU usage percentage",
			},
		),
		gcDuration: prometheus.NewSummary(
			prometheus.SummaryOpts{
				Name:       "gc_duration_seconds",
				Help:       "GC duration summary",
				Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
			},
		),

		// Custom business metrics
		userRegistrations: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "user_registrations_total",
				Help: "Total number of user registrations",
			},
			[]string{"tenant_id", "role"},
		),
		loginAttempts: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "login_attempts_total",
				Help: "Total number of login attempts",
			},
			[]string{"status", "method"},
		),
		tenantActivity: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "tenant_activity_score",
				Help: "Tenant activity score",
			},
			[]string{"tenant_id"},
		),
		revenueTotal: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "revenue_total",
				Help: "Total revenue",
			},
			[]string{"tenant_id", "currency", "payment_method"},
		),
	}

	// Register all metrics
	mc.registerMetrics()

	return mc
}

// registerMetrics registers all metrics with Prometheus
func (mc *MetricsCollector) registerMetrics() {
	// HTTP metrics
	prometheus.MustRegister(mc.httpRequestsTotal)
	prometheus.MustRegister(mc.httpRequestDuration)
	prometheus.MustRegister(mc.httpResponseSize)
	prometheus.MustRegister(mc.httpActiveRequests)

	// Business metrics
	prometheus.MustRegister(mc.salesTotal)
	prometheus.MustRegister(mc.salesAmount)
	prometheus.MustRegister(mc.inventoryLevels)
	prometheus.MustRegister(mc.stockAdjustments)
	prometheus.MustRegister(mc.returnsTotal)

	// WebSocket metrics
	prometheus.MustRegister(mc.wsConnections)
	prometheus.MustRegister(mc.wsMessagesTotal)
	prometheus.MustRegister(mc.wsMessageDuration)
	prometheus.MustRegister(mc.wsChannelSubscribers)

	// Circuit breaker metrics
	prometheus.MustRegister(mc.circuitBreakerState)
	prometheus.MustRegister(mc.circuitBreakerTrips)

	// Rate limiter metrics
	prometheus.MustRegister(mc.rateLimiterHits)
	prometheus.MustRegister(mc.rateLimiterRejected)
	prometheus.MustRegister(mc.rateLimiterTokens)

	// Database metrics
	prometheus.MustRegister(mc.dbQueryDuration)
	prometheus.MustRegister(mc.dbConnectionsActive)
	prometheus.MustRegister(mc.dbConnectionsIdle)
	prometheus.MustRegister(mc.dbErrors)

	// Cache metrics
	prometheus.MustRegister(mc.cacheHits)
	prometheus.MustRegister(mc.cacheMisses)
	prometheus.MustRegister(mc.cacheEvictions)
	prometheus.MustRegister(mc.cacheSizeBytes)

	// Event sourcing metrics
	prometheus.MustRegister(mc.eventsStored)
	prometheus.MustRegister(mc.eventsProcessed)
	prometheus.MustRegister(mc.eventLag)
	prometheus.MustRegister(mc.projectionLag)

	// System metrics
	prometheus.MustRegister(mc.goroutinesCount)
	prometheus.MustRegister(mc.memoryUsage)
	prometheus.MustRegister(mc.cpuUsage)
	prometheus.MustRegister(mc.gcDuration)

	// Business metrics
	prometheus.MustRegister(mc.userRegistrations)
	prometheus.MustRegister(mc.loginAttempts)
	prometheus.MustRegister(mc.tenantActivity)
	prometheus.MustRegister(mc.revenueTotal)
}

// Middleware for Gin framework
func (mc *MetricsCollector) GinMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path

		// Increment active requests
		mc.httpActiveRequests.Inc()
		defer mc.httpActiveRequests.Dec()

		// Process request
		c.Next()

		// Record metrics
		duration := time.Since(start).Seconds()
		status := fmt.Sprintf("%d", c.Writer.Status())
		method := c.Request.Method

		mc.httpRequestsTotal.WithLabelValues(method, path, status).Inc()
		mc.httpRequestDuration.WithLabelValues(method, path, status).Observe(duration)
		mc.httpResponseSize.WithLabelValues(method, path).Observe(float64(c.Writer.Size()))
	}
}

// ExposeMetrics exposes metrics endpoint
func (mc *MetricsCollector) ExposeMetrics() http.Handler {
	return promhttp.Handler()
}

// Business metric recording methods

func (mc *MetricsCollector) RecordSale(tenantID, shopID string, amount float64, status string) {
	mc.salesTotal.WithLabelValues(tenantID, shopID, status).Inc()
	mc.salesAmount.WithLabelValues(tenantID, shopID, "USD").Add(amount)
	mc.revenueTotal.WithLabelValues(tenantID, "USD", "card").Add(amount)
}

func (mc *MetricsCollector) RecordStockAdjustment(tenantID, shopID, adjustmentType, reason string) {
	mc.stockAdjustments.WithLabelValues(tenantID, shopID, adjustmentType, reason).Inc()
}

func (mc *MetricsCollector) UpdateInventoryLevel(tenantID, shopID, productID, category string, level float64) {
	mc.inventoryLevels.WithLabelValues(tenantID, shopID, productID, category).Set(level)
}

func (mc *MetricsCollector) RecordReturn(tenantID, shopID, reason string) {
	mc.returnsTotal.WithLabelValues(tenantID, shopID, reason).Inc()
}

// WebSocket metrics

func (mc *MetricsCollector) UpdateWebSocketConnections(count float64) {
	mc.wsConnections.Set(count)
}

func (mc *MetricsCollector) RecordWebSocketMessage(messageType, direction string) {
	mc.wsMessagesTotal.WithLabelValues(messageType, direction).Inc()
}

func (mc *MetricsCollector) RecordWebSocketMessageDuration(messageType string, duration float64) {
	mc.wsMessageDuration.WithLabelValues(messageType).Observe(duration)
}

func (mc *MetricsCollector) UpdateChannelSubscribers(channel string, count float64) {
	mc.wsChannelSubscribers.WithLabelValues(channel).Set(count)
}

// Circuit breaker metrics

func (mc *MetricsCollector) UpdateCircuitBreakerState(name string, state int) {
	mc.circuitBreakerState.WithLabelValues(name).Set(float64(state))
}

func (mc *MetricsCollector) RecordCircuitBreakerTrip(name string) {
	mc.circuitBreakerTrips.WithLabelValues(name).Inc()
}

// Rate limiter metrics

func (mc *MetricsCollector) RecordRateLimiterHit(name string) {
	mc.rateLimiterHits.WithLabelValues(name).Inc()
}

func (mc *MetricsCollector) RecordRateLimiterRejection(name string) {
	mc.rateLimiterRejected.WithLabelValues(name).Inc()
}

func (mc *MetricsCollector) UpdateRateLimiterTokens(name string, tokens float64) {
	mc.rateLimiterTokens.WithLabelValues(name).Set(tokens)
}

// Database metrics

func (mc *MetricsCollector) RecordDBQuery(queryType, table string, duration float64) {
	mc.dbQueryDuration.WithLabelValues(queryType, table).Observe(duration)
}

func (mc *MetricsCollector) UpdateDBConnections(active, idle float64) {
	mc.dbConnectionsActive.Set(active)
	mc.dbConnectionsIdle.Set(idle)
}

func (mc *MetricsCollector) RecordDBError(operation, errorType string) {
	mc.dbErrors.WithLabelValues(operation, errorType).Inc()
}

// Cache metrics

func (mc *MetricsCollector) RecordCacheHit(cacheType string) {
	mc.cacheHits.WithLabelValues(cacheType).Inc()
}

func (mc *MetricsCollector) RecordCacheMiss(cacheType string) {
	mc.cacheMisses.WithLabelValues(cacheType).Inc()
}

func (mc *MetricsCollector) RecordCacheEviction(cacheType, reason string) {
	mc.cacheEvictions.WithLabelValues(cacheType, reason).Inc()
}

func (mc *MetricsCollector) UpdateCacheSize(sizeBytes float64) {
	mc.cacheSizeBytes.Set(sizeBytes)
}

// Event sourcing metrics

func (mc *MetricsCollector) RecordEventStored(eventType, aggregateType string) {
	mc.eventsStored.WithLabelValues(eventType, aggregateType).Inc()
}

func (mc *MetricsCollector) RecordEventProcessed(eventType, handler string) {
	mc.eventsProcessed.WithLabelValues(eventType, handler).Inc()
}

func (mc *MetricsCollector) UpdateEventLag(eventType string, lagSeconds float64) {
	mc.eventLag.WithLabelValues(eventType).Set(lagSeconds)
}

func (mc *MetricsCollector) UpdateProjectionLag(projectionName string, lagSeconds float64) {
	mc.projectionLag.WithLabelValues(projectionName).Set(lagSeconds)
}

// AlertManager for defining alert rules

// AlertRule represents a Prometheus alert rule
type AlertRule struct {
	Name        string
	Expression  string
	Duration    time.Duration
	Labels      map[string]string
	Annotations map[string]string
}

// GetAlertRules returns predefined alert rules
func GetAlertRules() []AlertRule {
	return []AlertRule{
		{
			Name:       "HighErrorRate",
			Expression: `rate(http_requests_total{status=~"5.."}[5m]) > 0.05`,
			Duration:   5 * time.Minute,
			Labels:     map[string]string{"severity": "critical"},
			Annotations: map[string]string{
				"summary":     "High error rate detected",
				"description": "Error rate is above 5% for the last 5 minutes",
			},
		},
		{
			Name:       "HighLatency",
			Expression: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1`,
			Duration:   5 * time.Minute,
			Labels:     map[string]string{"severity": "warning"},
			Annotations: map[string]string{
				"summary":     "High latency detected",
				"description": "95th percentile latency is above 1 second",
			},
		},
		{
			Name:       "CircuitBreakerOpen",
			Expression: `circuit_breaker_state > 0`,
			Duration:   1 * time.Minute,
			Labels:     map[string]string{"severity": "critical"},
			Annotations: map[string]string{
				"summary":     "Circuit breaker is open",
				"description": "Circuit breaker {{ $labels.name }} is open",
			},
		},
		{
			Name:       "LowInventory",
			Expression: `inventory_levels < 10`,
			Duration:   10 * time.Minute,
			Labels:     map[string]string{"severity": "warning"},
			Annotations: map[string]string{
				"summary":     "Low inventory detected",
				"description": "Product {{ $labels.product_id }} has low inventory in shop {{ $labels.shop_id }}",
			},
		},
		{
			Name:       "DatabaseConnectionPoolExhausted",
			Expression: `db_connections_idle == 0`,
			Duration:   2 * time.Minute,
			Labels:     map[string]string{"severity": "critical"},
			Annotations: map[string]string{
				"summary":     "Database connection pool exhausted",
				"description": "No idle database connections available",
			},
		},
		{
			Name:       "HighMemoryUsage",
			Expression: `memory_usage_bytes{type="heap"} > 1073741824`,
			Duration:   5 * time.Minute,
			Labels:     map[string]string{"severity": "warning"},
			Annotations: map[string]string{
				"summary":     "High memory usage",
				"description": "Memory usage is above 1GB",
			},
		},
		{
			Name:       "EventProcessingLag",
			Expression: `event_lag_seconds > 60`,
			Duration:   5 * time.Minute,
			Labels:     map[string]string{"severity": "warning"},
			Annotations: map[string]string{
				"summary":     "Event processing lag detected",
				"description": "Event type {{ $labels.event_type }} has processing lag > 60 seconds",
			},
		},
	}
}