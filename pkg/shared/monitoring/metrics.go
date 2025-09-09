package monitoring

import (
	"fmt"
	"runtime"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// Metrics holds application metrics
type Metrics struct {
	mu sync.RWMutex
	
	// HTTP metrics
	TotalRequests   int64            `json:"total_requests"`
	TotalErrors     int64            `json:"total_errors"`
	ResponseTimes   []time.Duration  `json:"-"` // Store last 1000 response times
	StatusCodes     map[int]int64    `json:"status_codes"`
	
	// System metrics
	StartTime       time.Time        `json:"start_time"`
	Uptime          time.Duration    `json:"uptime"`
	MemoryUsage     MemoryStats      `json:"memory_usage"`
	
	// Business metrics
	ActiveSessions  int64            `json:"active_sessions"`
	DatabaseConns   int64            `json:"database_connections"`
	CacheHitRate    float64          `json:"cache_hit_rate"`
	
	// Service-specific metrics
	ServiceMetrics  map[string]interface{} `json:"service_metrics"`
}

// MemoryStats holds memory usage statistics
type MemoryStats struct {
	AllocMB      uint64 `json:"alloc_mb"`
	TotalAllocMB uint64 `json:"total_alloc_mb"`
	SysMB        uint64 `json:"sys_mb"`
	GCCycles     uint32 `json:"gc_cycles"`
}

var (
	globalMetrics *Metrics
	once          sync.Once
)

// Initialize sets up the metrics system
func Initialize() *Metrics {
	once.Do(func() {
		globalMetrics = &Metrics{
			StartTime:      time.Now(),
			StatusCodes:    make(map[int]int64),
			ServiceMetrics: make(map[string]interface{}),
			ResponseTimes:  make([]time.Duration, 0, 1000),
		}
	})
	return globalMetrics
}

// GetMetrics returns current metrics
func GetMetrics() *Metrics {
	if globalMetrics == nil {
		return Initialize()
	}
	
	globalMetrics.mu.RLock()
	defer globalMetrics.mu.RUnlock()
	
	// Update dynamic metrics
	globalMetrics.Uptime = time.Since(globalMetrics.StartTime)
	globalMetrics.MemoryUsage = getMemoryStats()
	
	return globalMetrics
}

// IncrementRequests increments the total request counter
func IncrementRequests() {
	if globalMetrics == nil {
		return
	}
	
	globalMetrics.mu.Lock()
	globalMetrics.TotalRequests++
	globalMetrics.mu.Unlock()
}

// IncrementErrors increments the error counter
func IncrementErrors() {
	if globalMetrics == nil {
		return
	}
	
	globalMetrics.mu.Lock()
	globalMetrics.TotalErrors++
	globalMetrics.mu.Unlock()
}

// RecordResponseTime records a response time
func RecordResponseTime(duration time.Duration) {
	if globalMetrics == nil {
		return
	}
	
	globalMetrics.mu.Lock()
	defer globalMetrics.mu.Unlock()
	
	// Keep only last 1000 response times for average calculation
	if len(globalMetrics.ResponseTimes) >= 1000 {
		globalMetrics.ResponseTimes = globalMetrics.ResponseTimes[1:]
	}
	globalMetrics.ResponseTimes = append(globalMetrics.ResponseTimes, duration)
}

// RecordStatusCode records a status code
func RecordStatusCode(statusCode int) {
	if globalMetrics == nil {
		return
	}
	
	globalMetrics.mu.Lock()
	globalMetrics.StatusCodes[statusCode]++
	globalMetrics.mu.Unlock()
}

// SetServiceMetric sets a service-specific metric
func SetServiceMetric(key string, value interface{}) {
	if globalMetrics == nil {
		return
	}
	
	globalMetrics.mu.Lock()
	globalMetrics.ServiceMetrics[key] = value
	globalMetrics.mu.Unlock()
}

// GetAverageResponseTime calculates average response time
func GetAverageResponseTime() time.Duration {
	if globalMetrics == nil {
		return 0
	}
	
	globalMetrics.mu.RLock()
	defer globalMetrics.mu.RUnlock()
	
	if len(globalMetrics.ResponseTimes) == 0 {
		return 0
	}
	
	var total time.Duration
	for _, t := range globalMetrics.ResponseTimes {
		total += t
	}
	
	return total / time.Duration(len(globalMetrics.ResponseTimes))
}

// getMemoryStats returns current memory usage statistics
func getMemoryStats() MemoryStats {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	
	return MemoryStats{
		AllocMB:      m.Alloc / 1024 / 1024,
		TotalAllocMB: m.TotalAlloc / 1024 / 1024,
		SysMB:        m.Sys / 1024 / 1024,
		GCCycles:     m.NumGC,
	}
}

// MetricsMiddleware tracks HTTP request metrics
func MetricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		
		// Process request
		c.Next()
		
		// Record metrics
		duration := time.Since(start)
		statusCode := c.Writer.Status()
		
		IncrementRequests()
		RecordResponseTime(duration)
		RecordStatusCode(statusCode)
		
		if statusCode >= 400 {
			IncrementErrors()
		}
	}
}

// HealthCheck returns health status with basic metrics
func HealthCheck() gin.HandlerFunc {
	return func(c *gin.Context) {
		metrics := GetMetrics()
		
		status := "healthy"
		details := gin.H{
			"status":         status,
			"uptime":         metrics.Uptime.String(),
			"total_requests": metrics.TotalRequests,
			"total_errors":   metrics.TotalErrors,
			"memory_mb":      metrics.MemoryUsage.AllocMB,
		}
		
		// Add average response time if available
		if avg := GetAverageResponseTime(); avg > 0 {
			details["avg_response_time"] = avg.String()
		}
		
		c.JSON(200, details)
	}
}

// DetailedMetrics returns comprehensive metrics
func DetailedMetrics() gin.HandlerFunc {
	return func(c *gin.Context) {
		metrics := GetMetrics()
		
		response := gin.H{
			"timestamp":        time.Now().UTC(),
			"service_metrics":  metrics,
			"avg_response_time": GetAverageResponseTime().String(),
		}
		
		c.JSON(200, response)
	}
}

// StartMetricsCollector starts a background goroutine to collect periodic metrics
func StartMetricsCollector() {
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		
		for range ticker.C {
			// Collect and log periodic metrics
			metrics := GetMetrics()
			
			// Log key metrics every 30 seconds
			if metrics.TotalRequests > 0 {
				errorRate := float64(metrics.TotalErrors) / float64(metrics.TotalRequests) * 100
				
				// You can log or send to monitoring system here
				_ = errorRate // For now, just prevent unused variable warning
			}
			
			// Trigger garbage collection if memory usage is high
			if metrics.MemoryUsage.AllocMB > 100 { // 100MB threshold
				runtime.GC()
			}
		}
	}()
}

// DatabaseConnectionMetrics tracks database connection pool metrics
func DatabaseConnectionMetrics(activeConns int64, idleConns int64, maxOpenConns int64) {
	SetServiceMetric("db_active_connections", activeConns)
	SetServiceMetric("db_idle_connections", idleConns)
	SetServiceMetric("db_max_connections", maxOpenConns)
}

// CacheMetrics tracks cache hit rate and operations
func CacheMetrics(hits int64, misses int64, operations int64) {
	if globalMetrics == nil {
		return
	}
	
	var hitRate float64
	if operations > 0 {
		hitRate = float64(hits) / float64(operations) * 100
	}
	
	globalMetrics.mu.Lock()
	globalMetrics.CacheHitRate = hitRate
	globalMetrics.mu.Unlock()
	
	SetServiceMetric("cache_hits", hits)
	SetServiceMetric("cache_misses", misses)
	SetServiceMetric("cache_operations", operations)
}

// BusinessMetrics tracks business-specific metrics
func BusinessMetrics(activeSessions int64, dailySales float64, pendingApprovals int64) {
	if globalMetrics == nil {
		return
	}
	
	globalMetrics.mu.Lock()
	globalMetrics.ActiveSessions = activeSessions
	globalMetrics.mu.Unlock()
	
	SetServiceMetric("daily_sales_amount", dailySales)
	SetServiceMetric("pending_approvals", pendingApprovals)
}

// AlertThresholds defines when to trigger alerts
type AlertThresholds struct {
	ErrorRatePercent    float64
	ResponseTimeMS      int64
	MemoryUsageMB       uint64
	DiskUsagePercent    float64
}

// CheckAlerts evaluates current metrics against thresholds
func CheckAlerts(thresholds AlertThresholds) []string {
	var alerts []string
	metrics := GetMetrics()
	
	// Check error rate
	if metrics.TotalRequests > 0 {
		errorRate := float64(metrics.TotalErrors) / float64(metrics.TotalRequests) * 100
		if errorRate > thresholds.ErrorRatePercent {
			alerts = append(alerts, fmt.Sprintf("High error rate: %.2f%%", errorRate))
		}
	}
	
	// Check response time
	avgResponseTime := GetAverageResponseTime()
	if avgResponseTime > time.Duration(thresholds.ResponseTimeMS)*time.Millisecond {
		alerts = append(alerts, fmt.Sprintf("High response time: %s", avgResponseTime))
	}
	
	// Check memory usage
	if metrics.MemoryUsage.AllocMB > thresholds.MemoryUsageMB {
		alerts = append(alerts, fmt.Sprintf("High memory usage: %d MB", metrics.MemoryUsage.AllocMB))
	}
	
	return alerts
}