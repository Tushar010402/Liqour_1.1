package services

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

// OCRMetrics holds OCR operation metrics
type OCRMetrics struct {
	TotalRequests       int64
	SuccessfulRequests  int64
	FailedRequests      int64
	AverageProcessTime  time.Duration
	AverageConfidence   float64
	TotalItemsExtracted int64
	TotalItemsMatched   int64
	CacheHits           int64
	CacheMisses         int64
	LastUpdated         time.Time
	mu                  sync.RWMutex
}

// OCRMonitoringService provides monitoring for OCR operations
type OCRMonitoringService struct {
	logger  *logrus.Logger
	metrics *OCRMetrics
	alerts  chan *OCRAlert
}

// OCRAlert represents an alert condition
type OCRAlert struct {
	Type      string
	Severity  string // "info", "warning", "error", "critical"
	Message   string
	Details   map[string]interface{}
	Timestamp time.Time
}

// NewOCRMonitoringService creates a new monitoring service
func NewOCRMonitoringService(logger *logrus.Logger) *OCRMonitoringService {
	return &OCRMonitoringService{
		logger: logger,
		metrics: &OCRMetrics{
			LastUpdated: time.Now(),
		},
		alerts: make(chan *OCRAlert, 100),
	}
}

// RecordRequest records an OCR request
func (s *OCRMonitoringService) RecordRequest(success bool, processingTime time.Duration, confidence float64) {
	s.metrics.mu.Lock()
	defer s.metrics.mu.Unlock()

	s.metrics.TotalRequests++

	if success {
		s.metrics.SuccessfulRequests++
	} else {
		s.metrics.FailedRequests++
	}

	// Update average processing time
	if s.metrics.AverageProcessTime == 0 {
		s.metrics.AverageProcessTime = processingTime
	} else {
		s.metrics.AverageProcessTime = (s.metrics.AverageProcessTime + processingTime) / 2
	}

	// Update average confidence
	if confidence > 0 {
		if s.metrics.AverageConfidence == 0 {
			s.metrics.AverageConfidence = confidence
		} else {
			s.metrics.AverageConfidence = (s.metrics.AverageConfidence + confidence) / 2
		}
	}

	s.metrics.LastUpdated = time.Now()

	// Check for alert conditions
	s.checkAlertConditions()
}

// RecordExtraction records extraction results
func (s *OCRMonitoringService) RecordExtraction(itemsExtracted, itemsMatched int) {
	s.metrics.mu.Lock()
	defer s.metrics.mu.Unlock()

	s.metrics.TotalItemsExtracted += int64(itemsExtracted)
	s.metrics.TotalItemsMatched += int64(itemsMatched)
	s.metrics.LastUpdated = time.Now()

	// Check match rate
	if itemsExtracted > 0 {
		matchRate := float64(itemsMatched) / float64(itemsExtracted)
		if matchRate < 0.5 {
			s.sendAlert(&OCRAlert{
				Type:     "LOW_MATCH_RATE",
				Severity: "warning",
				Message:  fmt.Sprintf("Low match rate: %.2f%%", matchRate*100),
				Details: map[string]interface{}{
					"items_extracted": itemsExtracted,
					"items_matched":   itemsMatched,
					"match_rate":      matchRate,
				},
				Timestamp: time.Now(),
			})
		}
	}
}

// RecordCacheHit records a cache hit
func (s *OCRMonitoringService) RecordCacheHit() {
	s.metrics.mu.Lock()
	defer s.metrics.mu.Unlock()
	s.metrics.CacheHits++
}

// RecordCacheMiss records a cache miss
func (s *OCRMonitoringService) RecordCacheMiss() {
	s.metrics.mu.Lock()
	defer s.metrics.mu.Unlock()
	s.metrics.CacheMisses++
}

// GetMetrics returns current metrics
func (s *OCRMonitoringService) GetMetrics() OCRMetrics {
	s.metrics.mu.RLock()
	defer s.metrics.mu.RUnlock()

	return OCRMetrics{
		TotalRequests:       s.metrics.TotalRequests,
		SuccessfulRequests:  s.metrics.SuccessfulRequests,
		FailedRequests:      s.metrics.FailedRequests,
		AverageProcessTime:  s.metrics.AverageProcessTime,
		AverageConfidence:   s.metrics.AverageConfidence,
		TotalItemsExtracted: s.metrics.TotalItemsExtracted,
		TotalItemsMatched:   s.metrics.TotalItemsMatched,
		CacheHits:           s.metrics.CacheHits,
		CacheMisses:         s.metrics.CacheMisses,
		LastUpdated:         s.metrics.LastUpdated,
	}
}

// checkAlertConditions checks for alert conditions
func (s *OCRMonitoringService) checkAlertConditions() {
	// High failure rate
	if s.metrics.TotalRequests > 10 {
		failureRate := float64(s.metrics.FailedRequests) / float64(s.metrics.TotalRequests)
		if failureRate > 0.2 {
			s.sendAlert(&OCRAlert{
				Type:     "HIGH_FAILURE_RATE",
				Severity: "error",
				Message:  fmt.Sprintf("High failure rate: %.2f%%", failureRate*100),
				Details: map[string]interface{}{
					"total_requests":  s.metrics.TotalRequests,
					"failed_requests": s.metrics.FailedRequests,
					"failure_rate":    failureRate,
				},
				Timestamp: time.Now(),
			})
		}
	}

	// Slow processing
	if s.metrics.AverageProcessTime > 5*time.Second {
		s.sendAlert(&OCRAlert{
			Type:     "SLOW_PROCESSING",
			Severity: "warning",
			Message:  fmt.Sprintf("Slow OCR processing: %v", s.metrics.AverageProcessTime),
			Details: map[string]interface{}{
				"average_process_time": s.metrics.AverageProcessTime.String(),
			},
			Timestamp: time.Now(),
		})
	}

	// Low confidence
	if s.metrics.AverageConfidence > 0 && s.metrics.AverageConfidence < 0.7 {
		s.sendAlert(&OCRAlert{
			Type:     "LOW_CONFIDENCE",
			Severity: "warning",
			Message:  fmt.Sprintf("Low average confidence: %.2f", s.metrics.AverageConfidence),
			Details: map[string]interface{}{
				"average_confidence": s.metrics.AverageConfidence,
			},
			Timestamp: time.Now(),
		})
	}
}

// sendAlert sends an alert
func (s *OCRMonitoringService) sendAlert(alert *OCRAlert) {
	select {
	case s.alerts <- alert:
		s.logger.WithFields(logrus.Fields{
			"type":     alert.Type,
			"severity": alert.Severity,
			"message":  alert.Message,
		}).Warn("OCR Alert")
	default:
		s.logger.Warn("Alert channel full, dropping alert")
	}
}

// GetAlerts returns the alerts channel
func (s *OCRMonitoringService) GetAlerts() <-chan *OCRAlert {
	return s.alerts
}

// HealthCheck performs a health check
func (s *OCRMonitoringService) HealthCheck(ctx context.Context) HealthStatus {
	status := HealthStatus{
		Service:   "OCR",
		Status:    "healthy",
		Timestamp: time.Now(),
		Details:   make(map[string]interface{}),
	}

	metrics := s.GetMetrics()

	// Check failure rate
	if metrics.TotalRequests > 0 {
		failureRate := float64(metrics.FailedRequests) / float64(metrics.TotalRequests)
		status.Details["failure_rate"] = fmt.Sprintf("%.2f%%", failureRate*100)

		if failureRate > 0.5 {
			status.Status = "unhealthy"
			status.Message = "High failure rate"
		} else if failureRate > 0.2 {
			status.Status = "degraded"
			status.Message = "Elevated failure rate"
		}
	}

	// Check processing time
	status.Details["avg_process_time"] = metrics.AverageProcessTime.String()
	if metrics.AverageProcessTime > 10*time.Second {
		status.Status = "degraded"
		if status.Message == "" {
			status.Message = "Slow processing"
		}
	}

	// Check cache effectiveness
	if metrics.CacheHits+metrics.CacheMisses > 0 {
		cacheHitRate := float64(metrics.CacheHits) / float64(metrics.CacheHits+metrics.CacheMisses)
		status.Details["cache_hit_rate"] = fmt.Sprintf("%.2f%%", cacheHitRate*100)
	}

	// Add more details
	status.Details["total_requests"] = metrics.TotalRequests
	status.Details["successful_requests"] = metrics.SuccessfulRequests
	status.Details["average_confidence"] = fmt.Sprintf("%.2f", metrics.AverageConfidence)
	status.Details["last_updated"] = metrics.LastUpdated.Format(time.RFC3339)

	return status
}

// HealthStatus represents service health
type HealthStatus struct {
	Service   string
	Status    string // "healthy", "degraded", "unhealthy"
	Message   string
	Details   map[string]interface{}
	Timestamp time.Time
}

// OCRPerformanceTracker tracks performance metrics
type OCRPerformanceTracker struct {
	logger      *logrus.Logger
	operations  map[string]*OperationMetrics
	mu          sync.RWMutex
}

// OperationMetrics tracks metrics for a specific operation
type OperationMetrics struct {
	Name         string
	Count        int64
	TotalTime    time.Duration
	MinTime      time.Duration
	MaxTime      time.Duration
	AverageTime  time.Duration
	LastExecuted time.Time
}

// NewOCRPerformanceTracker creates a new performance tracker
func NewOCRPerformanceTracker(logger *logrus.Logger) *OCRPerformanceTracker {
	return &OCRPerformanceTracker{
		logger:     logger,
		operations: make(map[string]*OperationMetrics),
	}
}

// StartOperation starts tracking an operation
func (t *OCRPerformanceTracker) StartOperation(name string) *OperationTimer {
	return &OperationTimer{
		tracker:   t,
		name:      name,
		startTime: time.Now(),
	}
}

// OperationTimer times an operation
type OperationTimer struct {
	tracker   *OCRPerformanceTracker
	name      string
	startTime time.Time
}

// End ends the operation timing
func (ot *OperationTimer) End() {
	duration := time.Since(ot.startTime)
	ot.tracker.recordOperation(ot.name, duration)
}

// recordOperation records operation metrics
func (t *OCRPerformanceTracker) recordOperation(name string, duration time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()

	op, exists := t.operations[name]
	if !exists {
		op = &OperationMetrics{
			Name:    name,
			MinTime: duration,
			MaxTime: duration,
		}
		t.operations[name] = op
	}

	op.Count++
	op.TotalTime += duration

	if duration < op.MinTime {
		op.MinTime = duration
	}
	if duration > op.MaxTime {
		op.MaxTime = duration
	}

	op.AverageTime = op.TotalTime / time.Duration(op.Count)
	op.LastExecuted = time.Now()

	// Log slow operations
	if duration > 3*time.Second {
		t.logger.WithFields(logrus.Fields{
			"operation": name,
			"duration":  duration.String(),
		}).Warn("Slow OCR operation")
	}
}

// GetOperationMetrics returns metrics for an operation
func (t *OCRPerformanceTracker) GetOperationMetrics(name string) (*OperationMetrics, bool) {
	t.mu.RLock()
	defer t.mu.RUnlock()

	op, exists := t.operations[name]
	if !exists {
		return nil, false
	}

	// Return a copy
	return &OperationMetrics{
		Name:         op.Name,
		Count:        op.Count,
		TotalTime:    op.TotalTime,
		MinTime:      op.MinTime,
		MaxTime:      op.MaxTime,
		AverageTime:  op.AverageTime,
		LastExecuted: op.LastExecuted,
	}, true
}

// GetAllMetrics returns all operation metrics
func (t *OCRPerformanceTracker) GetAllMetrics() map[string]*OperationMetrics {
	t.mu.RLock()
	defer t.mu.RUnlock()

	result := make(map[string]*OperationMetrics)
	for name, op := range t.operations {
		result[name] = &OperationMetrics{
			Name:         op.Name,
			Count:        op.Count,
			TotalTime:    op.TotalTime,
			MinTime:      op.MinTime,
			MaxTime:      op.MaxTime,
			AverageTime:  op.AverageTime,
			LastExecuted: op.LastExecuted,
		}
	}

	return result
}

// OCRErrorTracker tracks errors
type OCRErrorTracker struct {
	errors []ErrorEntry
	mu     sync.RWMutex
	logger *logrus.Logger
}

// ErrorEntry represents an error occurrence
type ErrorEntry struct {
	SessionID uuid.UUID
	Error     error
	Type      string
	Timestamp time.Time
	Context   map[string]interface{}
}

// NewOCRErrorTracker creates a new error tracker
func NewOCRErrorTracker(logger *logrus.Logger) *OCRErrorTracker {
	return &OCRErrorTracker{
		errors: make([]ErrorEntry, 0),
		logger: logger,
	}
}

// RecordError records an error
func (t *OCRErrorTracker) RecordError(sessionID uuid.UUID, err error, errorType string, context map[string]interface{}) {
	t.mu.Lock()
	defer t.mu.Unlock()

	entry := ErrorEntry{
		SessionID: sessionID,
		Error:     err,
		Type:      errorType,
		Timestamp: time.Now(),
		Context:   context,
	}

	t.errors = append(t.errors, entry)

	// Keep only last 1000 errors
	if len(t.errors) > 1000 {
		t.errors = t.errors[len(t.errors)-1000:]
	}

	// Log error
	t.logger.WithFields(logrus.Fields{
		"session_id": sessionID,
		"error_type": errorType,
		"error":      err.Error(),
	}).Error("OCR error recorded")
}

// GetRecentErrors returns recent errors
func (t *OCRErrorTracker) GetRecentErrors(limit int) []ErrorEntry {
	t.mu.RLock()
	defer t.mu.RUnlock()

	if limit > len(t.errors) {
		limit = len(t.errors)
	}

	result := make([]ErrorEntry, limit)
	copy(result, t.errors[len(t.errors)-limit:])

	return result
}

// GetErrorStats returns error statistics
func (t *OCRErrorTracker) GetErrorStats() map[string]int {
	t.mu.RLock()
	defer t.mu.RUnlock()

	stats := make(map[string]int)

	for _, entry := range t.errors {
		stats[entry.Type]++
	}

	return stats
}