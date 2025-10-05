package health

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// HealthStatus represents the health status of a service component
type HealthStatus string

const (
	HealthStatusHealthy   HealthStatus = "healthy"
	HealthStatusUnhealthy HealthStatus = "unhealthy"
	HealthStatusDegraded  HealthStatus = "degraded"
)

// HealthCheck represents a health check response
type HealthCheck struct {
	Status      HealthStatus           `json:"status"`
	Version     string                 `json:"version,omitempty"`
	Timestamp   time.Time              `json:"timestamp"`
	Uptime      string                 `json:"uptime,omitempty"`
	Components  map[string]Component   `json:"components,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// Component represents a system component's health
type Component struct {
	Status    HealthStatus `json:"status"`
	Message   string       `json:"message,omitempty"`
	Latency   string       `json:"latency,omitempty"`
	Error     string       `json:"error,omitempty"`
	Timestamp time.Time    `json:"timestamp"`
}

// HealthChecker performs health checks
type HealthChecker struct {
	db        *gorm.DB
	startTime time.Time
	version   string
	checks    map[string]CheckFunc
}

// CheckFunc is a function that performs a health check
type CheckFunc func(ctx context.Context) Component

// NewHealthChecker creates a new health checker
func NewHealthChecker(db *gorm.DB, version string) *HealthChecker {
	return &HealthChecker{
		db:        db,
		startTime: time.Now(),
		version:   version,
		checks:    make(map[string]CheckFunc),
	}
}

// RegisterCheck registers a custom health check
func (h *HealthChecker) RegisterCheck(name string, check CheckFunc) {
	h.checks[name] = check
}

// PerformHealthCheck executes all health checks
func (h *HealthChecker) PerformHealthCheck(ctx context.Context) HealthCheck {
	components := make(map[string]Component)

	// Database check
	components["database"] = h.checkDatabase(ctx)

	// Execute custom checks
	for name, checkFunc := range h.checks {
		components[name] = checkFunc(ctx)
	}

	// Determine overall status
	overallStatus := HealthStatusHealthy
	for _, component := range components {
		if component.Status == HealthStatusUnhealthy {
			overallStatus = HealthStatusUnhealthy
			break
		} else if component.Status == HealthStatusDegraded {
			overallStatus = HealthStatusDegraded
		}
	}

	uptime := time.Since(h.startTime)

	return HealthCheck{
		Status:     overallStatus,
		Version:    h.version,
		Timestamp:  time.Now(),
		Uptime:     uptime.String(),
		Components: components,
	}
}

// checkDatabase checks database connectivity and performance
func (h *HealthChecker) checkDatabase(ctx context.Context) Component {
	start := time.Now()

	if h.db == nil {
		return Component{
			Status:    HealthStatusUnhealthy,
			Message:   "Database not configured",
			Timestamp: time.Now(),
		}
	}

	// Ping database
	sqlDB, err := h.db.DB()
	if err != nil {
		return Component{
			Status:    HealthStatusUnhealthy,
			Message:   "Failed to get database instance",
			Error:     err.Error(),
			Timestamp: time.Now(),
		}
	}

	if err := sqlDB.PingContext(ctx); err != nil {
		return Component{
			Status:    HealthStatusUnhealthy,
			Message:   "Database ping failed",
			Error:     err.Error(),
			Timestamp: time.Now(),
		}
	}

	latency := time.Since(start)

	// Check connection stats
	stats := sqlDB.Stats()
	status := HealthStatusHealthy

	// Warn if connection pool is exhausted
	if stats.InUse >= stats.MaxOpenConnections {
		status = HealthStatusDegraded
	}

	return Component{
		Status:    status,
		Message:   fmt.Sprintf("Connected (pool: %d/%d)", stats.InUse, stats.MaxOpenConnections),
		Latency:   latency.String(),
		Timestamp: time.Now(),
	}
}

// HealthHandler returns a Gin handler for health checks
func (h *HealthChecker) HealthHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()
		health := h.PerformHealthCheck(ctx)

		statusCode := http.StatusOK
		if health.Status == HealthStatusUnhealthy {
			statusCode = http.StatusServiceUnavailable
		} else if health.Status == HealthStatusDegraded {
			statusCode = http.StatusOK // Still operational
		}

		c.JSON(statusCode, health)
	}
}

// ReadinessHandler returns a simple readiness check
// Best practice: Use for Kubernetes readiness probes
func (h *HealthChecker) ReadinessHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()

		// Quick database check
		if h.db != nil {
			sqlDB, err := h.db.DB()
			if err == nil {
				if err := sqlDB.PingContext(ctx); err == nil {
					c.JSON(http.StatusOK, gin.H{
						"status": "ready",
						"timestamp": time.Now(),
					})
					return
				}
			}
		}

		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "not_ready",
			"timestamp": time.Now(),
		})
	}
}

// LivenessHandler returns a simple liveness check
// Best practice: Use for Kubernetes liveness probes
func (h *HealthChecker) LivenessHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status": "alive",
			"timestamp": time.Now(),
			"uptime": time.Since(h.startTime).String(),
		})
	}
}

// MetricsHandler returns basic metrics
func (h *HealthChecker) MetricsHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		metrics := gin.H{
			"uptime": time.Since(h.startTime).String(),
			"timestamp": time.Now(),
		}

		if h.db != nil {
			sqlDB, err := h.db.DB()
			if err == nil {
				stats := sqlDB.Stats()
				metrics["database"] = gin.H{
					"open_connections": stats.OpenConnections,
					"in_use": stats.InUse,
					"idle": stats.Idle,
					"max_open": stats.MaxOpenConnections,
					"max_idle": stats.MaxIdleClosed,
					"wait_count": stats.WaitCount,
					"wait_duration": stats.WaitDuration.String(),
				}
			}
		}

		c.JSON(http.StatusOK, metrics)
	}
}
