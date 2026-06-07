package resilience

import (
	"context"
	"errors"
	"sync"
	"time"

	"go.uber.org/zap"
)

var (
	ErrRateLimitExceeded = errors.New("rate limit exceeded")
	ErrQuotaExceeded     = errors.New("quota exceeded")
)

// RateLimiter implements token bucket algorithm for rate limiting
type RateLimiter struct {
	name         string
	capacity     int64
	refillRate   int64
	refillPeriod time.Duration

	mu            sync.Mutex
	tokens        int64
	lastRefill    time.Time
	totalRequests int64
	totalBlocked  int64
	logger        *zap.Logger
}

// RateLimiterConfig contains configuration for rate limiter
type RateLimiterConfig struct {
	Name         string
	Capacity     int64         // Max tokens in bucket
	RefillRate   int64         // Tokens to add per period
	RefillPeriod time.Duration // How often to refill
	Logger       *zap.Logger
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(config RateLimiterConfig) *RateLimiter {
	rl := &RateLimiter{
		name:         config.Name,
		capacity:     config.Capacity,
		refillRate:   config.RefillRate,
		refillPeriod: config.RefillPeriod,
		tokens:       config.Capacity,
		lastRefill:   time.Now(),
		logger:       config.Logger,
	}

	if rl.capacity == 0 {
		rl.capacity = 100
	}
	if rl.refillRate == 0 {
		rl.refillRate = 10
	}
	if rl.refillPeriod == 0 {
		rl.refillPeriod = time.Second
	}

	// Start background refill
	go rl.startRefill()

	return rl
}

// Allow checks if a request is allowed
func (rl *RateLimiter) Allow(tokens int64) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	rl.totalRequests++

	// Refill tokens
	rl.refill()

	if rl.tokens >= tokens {
		rl.tokens -= tokens
		return true
	}

	rl.totalBlocked++
	return false
}

// AllowN checks if N requests are allowed
func (rl *RateLimiter) AllowN(n int) bool {
	return rl.Allow(int64(n))
}

// Wait waits until a request is allowed
func (rl *RateLimiter) Wait(ctx context.Context, tokens int64) error {
	for {
		if rl.Allow(tokens) {
			return nil
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(rl.refillPeriod / 10):
			// Check again after a short wait
		}
	}
}

// refill adds tokens based on elapsed time
func (rl *RateLimiter) refill() {
	now := time.Now()
	elapsed := now.Sub(rl.lastRefill)

	if elapsed >= rl.refillPeriod {
		periods := int64(elapsed / rl.refillPeriod)
		tokensToAdd := periods * rl.refillRate

		rl.tokens += tokensToAdd
		if rl.tokens > rl.capacity {
			rl.tokens = rl.capacity
		}

		rl.lastRefill = now
	}
}

// startRefill runs periodic refill
func (rl *RateLimiter) startRefill() {
	ticker := time.NewTicker(rl.refillPeriod)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		rl.refill()
		rl.mu.Unlock()
	}
}

// GetMetrics returns rate limiter metrics
func (rl *RateLimiter) GetMetrics() RateLimiterMetrics {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	return RateLimiterMetrics{
		Name:          rl.name,
		TokensAvailable: rl.tokens,
		Capacity:      rl.capacity,
		TotalRequests: rl.totalRequests,
		TotalBlocked:  rl.totalBlocked,
		BlockRate:     rl.calculateBlockRate(),
	}
}

// RateLimiterMetrics contains rate limiter metrics
type RateLimiterMetrics struct {
	Name            string  `json:"name"`
	TokensAvailable int64   `json:"tokens_available"`
	Capacity        int64   `json:"capacity"`
	TotalRequests   int64   `json:"total_requests"`
	TotalBlocked    int64   `json:"total_blocked"`
	BlockRate       float64 `json:"block_rate"`
}

func (rl *RateLimiter) calculateBlockRate() float64 {
	if rl.totalRequests == 0 {
		return 0
	}
	return float64(rl.totalBlocked) / float64(rl.totalRequests)
}

// AdaptiveRateLimiter adjusts rate limit based on system load
type AdaptiveRateLimiter struct {
	*RateLimiter
	minRate      int64
	maxRate      int64
	targetLatency time.Duration
	currentLatency time.Duration
	mu           sync.RWMutex
}

// NewAdaptiveRateLimiter creates an adaptive rate limiter
func NewAdaptiveRateLimiter(config RateLimiterConfig, minRate, maxRate int64, targetLatency time.Duration) *AdaptiveRateLimiter {
	return &AdaptiveRateLimiter{
		RateLimiter:   NewRateLimiter(config),
		minRate:       minRate,
		maxRate:       maxRate,
		targetLatency: targetLatency,
	}
}

// UpdateLatency updates the current system latency
func (arl *AdaptiveRateLimiter) UpdateLatency(latency time.Duration) {
	arl.mu.Lock()
	defer arl.mu.Unlock()

	arl.currentLatency = latency

	// Adjust rate based on latency
	if latency > arl.targetLatency*2 {
		// System is overloaded, decrease rate
		newRate := arl.refillRate * 90 / 100
		if newRate >= arl.minRate {
			arl.refillRate = newRate
			arl.logger.Info("Decreased rate limit due to high latency",
				zap.String("name", arl.name),
				zap.Int64("new_rate", newRate))
		}
	} else if latency < arl.targetLatency/2 {
		// System has capacity, increase rate
		newRate := arl.refillRate * 110 / 100
		if newRate <= arl.maxRate {
			arl.refillRate = newRate
			arl.logger.Info("Increased rate limit due to low latency",
				zap.String("name", arl.name),
				zap.Int64("new_rate", newRate))
		}
	}
}

// SlidingWindowRateLimiter implements sliding window rate limiting
type SlidingWindowRateLimiter struct {
	name       string
	limit      int64
	window     time.Duration
	mu         sync.Mutex
	requests   []time.Time
	logger     *zap.Logger
}

// NewSlidingWindowRateLimiter creates a sliding window rate limiter
func NewSlidingWindowRateLimiter(name string, limit int64, window time.Duration, logger *zap.Logger) *SlidingWindowRateLimiter {
	return &SlidingWindowRateLimiter{
		name:     name,
		limit:    limit,
		window:   window,
		requests: make([]time.Time, 0),
		logger:   logger,
	}
}

// Allow checks if request is allowed in sliding window
func (sw *SlidingWindowRateLimiter) Allow() bool {
	sw.mu.Lock()
	defer sw.mu.Unlock()

	now := time.Now()
	windowStart := now.Add(-sw.window)

	// Remove old requests outside window
	validRequests := make([]time.Time, 0)
	for _, reqTime := range sw.requests {
		if reqTime.After(windowStart) {
			validRequests = append(validRequests, reqTime)
		}
	}
	sw.requests = validRequests

	// Check if under limit
	if int64(len(sw.requests)) < sw.limit {
		sw.requests = append(sw.requests, now)
		return true
	}

	return false
}

// Reset resets the rate limiter
func (sw *SlidingWindowRateLimiter) Reset() {
	sw.mu.Lock()
	defer sw.mu.Unlock()
	sw.requests = make([]time.Time, 0)
}