package handlers

import (
	"context"
	"net/http"
	"runtime"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// HealthHandler handles health check endpoints
type HealthHandler struct {
	db        *gorm.DB
	startTime time.Time
}

// NewHealthHandler creates a new health handler
func NewHealthHandler(db *gorm.DB) *HealthHandler {
	return &HealthHandler{
		db:        db,
		startTime: time.Now(),
	}
}

// HealthStatus represents the health status of a service
type HealthStatus struct {
	Status    string                 `json:"status"`
	Timestamp time.Time              `json:"timestamp"`
	Uptime    string                 `json:"uptime"`
	Checks    map[string]interface{} `json:"checks,omitempty"`
}

// ServiceHealth represents individual service health
type ServiceHealth struct {
	Name         string  `json:"name"`
	Status       string  `json:"status"`
	ResponseTime float64 `json:"response_time_ms"`
	Message      string  `json:"message,omitempty"`
}

// MetricsResponse represents system metrics
type MetricsResponse struct {
	Timestamp   time.Time `json:"timestamp"`
	Uptime      string    `json:"uptime"`
	Memory      Memory    `json:"memory"`
	Goroutines  int       `json:"goroutines"`
	CPUCount    int       `json:"cpu_count"`
	Database    DBMetrics `json:"database"`
	APIMetrics  APIStats  `json:"api_metrics"`
}

// Memory represents memory statistics
type Memory struct {
	Allocated      uint64 `json:"allocated_mb"`
	TotalAllocated uint64 `json:"total_allocated_mb"`
	System         uint64 `json:"system_mb"`
	GCCount        uint32 `json:"gc_count"`
}

// DBMetrics represents database metrics
type DBMetrics struct {
	OpenConnections int    `json:"open_connections"`
	InUse           int    `json:"in_use"`
	Idle            int    `json:"idle"`
	Status          string `json:"status"`
}

// APIStats represents API statistics
type APIStats struct {
	RequestsTotal     int64   `json:"requests_total"`
	RequestsPerMinute float64 `json:"requests_per_minute"`
	AverageLatency    float64 `json:"average_latency_ms"`
	ErrorRate         float64 `json:"error_rate_percent"`
}

// Health performs a basic health check
func (h *HealthHandler) Health(c *gin.Context) {
	status := HealthStatus{
		Status:    "healthy",
		Timestamp: time.Now(),
		Uptime:    time.Since(h.startTime).String(),
	}

	c.JSON(http.StatusOK, status)
}

// LivenessProbe checks if the service is alive (for k8s)
func (h *HealthHandler) LivenessProbe(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "alive",
		"time":   time.Now().Unix(),
	})
}

// ReadinessProbe checks if the service is ready to accept traffic (for k8s)
func (h *HealthHandler) ReadinessProbe(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Check database connection
	sqlDB, err := h.db.DB()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not_ready",
			"reason": "database_connection_failed",
			"error":  err.Error(),
		})
		return
	}

	// Ping database
	if err := sqlDB.PingContext(ctx); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not_ready",
			"reason": "database_ping_failed",
			"error":  err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status": "ready",
		"time":   time.Now().Unix(),
	})
}

// DetailedHealth performs comprehensive health checks
func (h *HealthHandler) DetailedHealth(c *gin.Context) {
	checks := make(map[string]interface{})
	overallStatus := "healthy"

	// Check database
	dbHealth := h.checkDatabase()
	checks["database"] = dbHealth
	if dbHealth.Status != "healthy" {
		overallStatus = "degraded"
	}

	// Check memory usage
	memHealth := h.checkMemory()
	checks["memory"] = memHealth
	if memHealth.Status != "healthy" {
		overallStatus = "degraded"
	}

	// Check dependent services
	services := h.checkServices()
	checks["services"] = services
	for _, svc := range services {
		if svc.Status != "healthy" {
			overallStatus = "degraded"
			break
		}
	}

	status := HealthStatus{
		Status:    overallStatus,
		Timestamp: time.Now(),
		Uptime:    time.Since(h.startTime).String(),
		Checks:    checks,
	}

	statusCode := http.StatusOK
	if overallStatus != "healthy" {
		statusCode = http.StatusServiceUnavailable
	}

	c.JSON(statusCode, status)
}

// Metrics returns system and application metrics
func (h *HealthHandler) Metrics(c *gin.Context) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	// Get database metrics
	dbMetrics := DBMetrics{Status: "unknown"}
	if sqlDB, err := h.db.DB(); err == nil {
		stats := sqlDB.Stats()
		dbMetrics = DBMetrics{
			OpenConnections: stats.OpenConnections,
			InUse:           stats.InUse,
			Idle:            stats.Idle,
			Status:          "connected",
		}
	}

	// TODO: Implement actual API metrics collection
	// This would typically come from a metrics collector like Prometheus
	apiMetrics := APIStats{
		RequestsTotal:     1000,  // Placeholder
		RequestsPerMinute: 60,    // Placeholder
		AverageLatency:    45.5,  // Placeholder
		ErrorRate:         0.5,   // Placeholder
	}

	response := MetricsResponse{
		Timestamp: time.Now(),
		Uptime:    time.Since(h.startTime).String(),
		Memory: Memory{
			Allocated:      m.Alloc / 1024 / 1024,
			TotalAllocated: m.TotalAlloc / 1024 / 1024,
			System:         m.Sys / 1024 / 1024,
			GCCount:        m.NumGC,
		},
		Goroutines: runtime.NumGoroutine(),
		CPUCount:   runtime.NumCPU(),
		Database:   dbMetrics,
		APIMetrics: apiMetrics,
	}

	c.JSON(http.StatusOK, response)
}

// checkDatabase checks database health
func (h *HealthHandler) checkDatabase() ServiceHealth {
	start := time.Now()

	sqlDB, err := h.db.DB()
	if err != nil {
		return ServiceHealth{
			Name:         "database",
			Status:       "unhealthy",
			ResponseTime: time.Since(start).Seconds() * 1000,
			Message:      err.Error(),
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := sqlDB.PingContext(ctx); err != nil {
		return ServiceHealth{
			Name:         "database",
			Status:       "unhealthy",
			ResponseTime: time.Since(start).Seconds() * 1000,
			Message:      err.Error(),
		}
	}

	return ServiceHealth{
		Name:         "database",
		Status:       "healthy",
		ResponseTime: time.Since(start).Seconds() * 1000,
	}
}

// checkMemory checks memory usage
func (h *HealthHandler) checkMemory() ServiceHealth {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	// Alert if memory usage is above 80%
	usagePercent := float64(m.Alloc) / float64(m.Sys) * 100
	status := "healthy"
	message := ""

	if usagePercent > 80 {
		status = "warning"
		message = "High memory usage"
	} else if usagePercent > 90 {
		status = "critical"
		message = "Critical memory usage"
	}

	return ServiceHealth{
		Name:    "memory",
		Status:  status,
		Message: message,
	}
}

// checkServices checks dependent services
func (h *HealthHandler) checkServices() []ServiceHealth {
	services := []ServiceHealth{
		h.checkService("auth", "http://auth:8091/health"),
		h.checkService("sales", "http://sales:8092/health"),
		h.checkService("inventory", "http://inventory:8093/health"),
		h.checkService("finance", "http://finance:8094/health"),
		h.checkService("saas", "http://saas:8095/health"),
	}

	return services
}

// checkService checks individual service health
func (h *HealthHandler) checkService(name, url string) ServiceHealth {
	start := time.Now()
	client := &http.Client{Timeout: 2 * time.Second}

	resp, err := client.Get(url)
	if err != nil {
		return ServiceHealth{
			Name:         name,
			Status:       "unhealthy",
			ResponseTime: time.Since(start).Seconds() * 1000,
			Message:      "Connection failed",
		}
	}
	defer resp.Body.Close()

	status := "healthy"
	if resp.StatusCode != http.StatusOK {
		status = "unhealthy"
	}

	return ServiceHealth{
		Name:         name,
		Status:       status,
		ResponseTime: time.Since(start).Seconds() * 1000,
	}
}