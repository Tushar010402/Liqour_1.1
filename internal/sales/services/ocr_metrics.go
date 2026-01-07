package services

import (
	"sync"
	"time"
)

// OCRMetrics tracks real-time OCR performance metrics
type OCRMetrics struct {
	mu sync.RWMutex

	// Performance metrics
	TotalRequests         int64
	SuccessfulRequests    int64
	FailedRequests        int64
	TotalProcessingTimeMS int64
	MinProcessingTimeMS   int64
	MaxProcessingTimeMS   int64

	// Accuracy metrics
	TotalItemsExtracted   int64
	ValidItems            int64
	InvalidItems          int64
	ItemsWithGarbage      int64
	ItemsCleaned          int64

	// API metrics
	VisionAPICallsTotal   int64
	VisionAPICallsFailed  int64
	GeminiAPICallsTotal   int64
	GeminiAPICallsFailed  int64
	GeminiAPIRetries      int64

	// Rate limiting metrics
	RateLimitHits         int64
	LastRateLimitTime     time.Time

	// Timestamps
	StartTime             time.Time
	LastRequestTime       time.Time
}

// Global metrics instance
var globalMetrics = &OCRMetrics{
	StartTime: time.Now(),
}

// GetMetrics returns the global metrics instance
func GetOCRMetrics() *OCRMetrics {
	return globalMetrics
}

// RecordRequest records a new OCR request
func (m *OCRMetrics) RecordRequest() {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.TotalRequests++
	m.LastRequestTime = time.Now()
}

// RecordSuccess records a successful OCR request
func (m *OCRMetrics) RecordSuccess(processingTimeMS int64) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.SuccessfulRequests++
	m.TotalProcessingTimeMS += processingTimeMS

	if m.MinProcessingTimeMS == 0 || processingTimeMS < m.MinProcessingTimeMS {
		m.MinProcessingTimeMS = processingTimeMS
	}

	if processingTimeMS > m.MaxProcessingTimeMS {
		m.MaxProcessingTimeMS = processingTimeMS
	}
}

// RecordFailure records a failed OCR request
func (m *OCRMetrics) RecordFailure() {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.FailedRequests++
}

// RecordItemExtraction records extracted items
func (m *OCRMetrics) RecordItemExtraction(total, valid, invalid, withGarbage, cleaned int) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.TotalItemsExtracted += int64(total)
	m.ValidItems += int64(valid)
	m.InvalidItems += int64(invalid)
	m.ItemsWithGarbage += int64(withGarbage)
	m.ItemsCleaned += int64(cleaned)
}

// RecordVisionAPICall records Vision API call
func (m *OCRMetrics) RecordVisionAPICall(success bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.VisionAPICallsTotal++
	if !success {
		m.VisionAPICallsFailed++
	}
}

// RecordGeminiAPICall records Gemini API call
func (m *OCRMetrics) RecordGeminiAPICall(success bool, retries int) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.GeminiAPICallsTotal++
	if !success {
		m.GeminiAPICallsFailed++
	}
	m.GeminiAPIRetries += int64(retries)
}

// RecordRateLimitHit records a rate limit hit
func (m *OCRMetrics) RecordRateLimitHit() {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.RateLimitHits++
	m.LastRateLimitTime = time.Now()
}

// GetSnapshot returns a snapshot of current metrics
func (m *OCRMetrics) GetSnapshot() MetricsSnapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()

	avgProcessingTime := int64(0)
	if m.SuccessfulRequests > 0 {
		avgProcessingTime = m.TotalProcessingTimeMS / m.SuccessfulRequests
	}

	successRate := float64(0)
	if m.TotalRequests > 0 {
		successRate = float64(m.SuccessfulRequests) / float64(m.TotalRequests) * 100
	}

	accuracyRate := float64(0)
	if m.TotalItemsExtracted > 0 {
		accuracyRate = float64(m.ValidItems) / float64(m.TotalItemsExtracted) * 100
	}

	cleaningRate := float64(0)
	if m.TotalItemsExtracted > 0 {
		cleaningRate = float64(m.ItemsCleaned) / float64(m.TotalItemsExtracted) * 100
	}

	visionSuccessRate := float64(0)
	if m.VisionAPICallsTotal > 0 {
		visionSuccessRate = float64(m.VisionAPICallsTotal-m.VisionAPICallsFailed) / float64(m.VisionAPICallsTotal) * 100
	}

	geminiSuccessRate := float64(0)
	if m.GeminiAPICallsTotal > 0 {
		geminiSuccessRate = float64(m.GeminiAPICallsTotal-m.GeminiAPICallsFailed) / float64(m.GeminiAPICallsTotal) * 100
	}

	uptime := time.Since(m.StartTime)

	return MetricsSnapshot{
		// Summary
		Uptime:            uptime.String(),
		TotalRequests:     m.TotalRequests,
		SuccessfulRequests: m.SuccessfulRequests,
		FailedRequests:    m.FailedRequests,
		SuccessRate:       successRate,

		// Performance
		AvgProcessingTimeMS: avgProcessingTime,
		MinProcessingTimeMS: m.MinProcessingTimeMS,
		MaxProcessingTimeMS: m.MaxProcessingTimeMS,

		// Accuracy
		TotalItemsExtracted: m.TotalItemsExtracted,
		ValidItems:          m.ValidItems,
		InvalidItems:        m.InvalidItems,
		AccuracyRate:        accuracyRate,

		// Cleaning
		ItemsWithGarbage:    m.ItemsWithGarbage,
		ItemsCleaned:        m.ItemsCleaned,
		CleaningRate:        cleaningRate,

		// API Health
		VisionAPICallsTotal:  m.VisionAPICallsTotal,
		VisionAPICallsFailed: m.VisionAPICallsFailed,
		VisionSuccessRate:    visionSuccessRate,
		GeminiAPICallsTotal:  m.GeminiAPICallsTotal,
		GeminiAPICallsFailed: m.GeminiAPICallsFailed,
		GeminiSuccessRate:    geminiSuccessRate,
		GeminiAPIRetries:     m.GeminiAPIRetries,

		// Rate Limiting
		RateLimitHits:     m.RateLimitHits,
		LastRateLimitTime: m.LastRateLimitTime.Format(time.RFC3339),

		// Timestamps
		StartTime:       m.StartTime.Format(time.RFC3339),
		LastRequestTime: m.LastRequestTime.Format(time.RFC3339),
	}
}

// Reset resets all metrics (useful for testing)
func (m *OCRMetrics) Reset() {
	m.mu.Lock()
	defer m.mu.Unlock()

	*m = OCRMetrics{
		StartTime: time.Now(),
	}
}

// MetricsSnapshot represents a point-in-time snapshot of metrics
type MetricsSnapshot struct {
	// Summary
	Uptime             string  `json:"uptime"`
	TotalRequests      int64   `json:"total_requests"`
	SuccessfulRequests int64   `json:"successful_requests"`
	FailedRequests     int64   `json:"failed_requests"`
	SuccessRate        float64 `json:"success_rate_percent"`

	// Performance
	AvgProcessingTimeMS int64 `json:"avg_processing_time_ms"`
	MinProcessingTimeMS int64 `json:"min_processing_time_ms"`
	MaxProcessingTimeMS int64 `json:"max_processing_time_ms"`

	// Accuracy
	TotalItemsExtracted int64   `json:"total_items_extracted"`
	ValidItems          int64   `json:"valid_items"`
	InvalidItems        int64   `json:"invalid_items"`
	AccuracyRate        float64 `json:"accuracy_rate_percent"`

	// Cleaning
	ItemsWithGarbage    int64   `json:"items_with_garbage"`
	ItemsCleaned        int64   `json:"items_cleaned"`
	CleaningRate        float64 `json:"cleaning_rate_percent"`

	// API Health
	VisionAPICallsTotal  int64   `json:"vision_api_calls_total"`
	VisionAPICallsFailed int64   `json:"vision_api_calls_failed"`
	VisionSuccessRate    float64 `json:"vision_success_rate_percent"`
	GeminiAPICallsTotal  int64   `json:"gemini_api_calls_total"`
	GeminiAPICallsFailed int64   `json:"gemini_api_calls_failed"`
	GeminiSuccessRate    float64 `json:"gemini_success_rate_percent"`
	GeminiAPIRetries     int64   `json:"gemini_api_retries"`

	// Rate Limiting
	RateLimitHits     int64  `json:"rate_limit_hits"`
	LastRateLimitTime string `json:"last_rate_limit_time"`

	// Timestamps
	StartTime       string `json:"start_time"`
	LastRequestTime string `json:"last_request_time"`
}
