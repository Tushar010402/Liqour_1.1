package middleware

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// RateLimitConfig defines rate limiting configuration
type RateLimitConfig struct {
	RequestsPerMinute int
	BurstSize         int
	KeyPrefix         string
	SkipPaths         []string
}

// AdvancedRateLimiter implements token bucket rate limiting with Redis
type AdvancedRateLimiter struct {
	redis  *redis.Client
	config RateLimitConfig
	logger *zap.Logger
}

// NewAdvancedRateLimiter creates a new rate limiter
func NewAdvancedRateLimiter(redisClient *redis.Client, config RateLimitConfig, logger *zap.Logger) *AdvancedRateLimiter {
	return &AdvancedRateLimiter{
		redis:  redisClient,
		config: config,
		logger: logger,
	}
}

// RateLimitMiddleware creates a rate limiting middleware
func (rl *AdvancedRateLimiter) RateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip rate limiting for certain paths
		for _, path := range rl.config.SkipPaths {
			if c.Request.URL.Path == path {
				c.Next()
				return
			}
		}

		// Get identifier (user ID or IP)
		identifier := rl.getIdentifier(c)
		key := fmt.Sprintf("%s:%s", rl.config.KeyPrefix, identifier)

		// Check rate limit
		allowed, remaining, resetTime, err := rl.checkRateLimit(key)
		if err != nil {
			rl.logger.Error("Rate limit check failed",
				zap.Error(err),
				zap.String("key", key))
			// Allow request on error to prevent blocking legitimate traffic
			c.Next()
			return
		}

		// Set rate limit headers
		c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", rl.config.RequestsPerMinute))
		c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", remaining))
		c.Header("X-RateLimit-Reset", fmt.Sprintf("%d", resetTime.Unix()))

		if !allowed {
			c.Header("Retry-After", fmt.Sprintf("%d", int(time.Until(resetTime).Seconds())))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":   "rate_limit_exceeded",
				"message": fmt.Sprintf("Rate limit exceeded. Try again in %d seconds", int(time.Until(resetTime).Seconds())),
				"retry_after": int(time.Until(resetTime).Seconds()),
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// getIdentifier gets the unique identifier for rate limiting
func (rl *AdvancedRateLimiter) getIdentifier(c *gin.Context) string {
	// Try to get tenant ID first (for multi-tenant apps)
	if tenantID := c.GetHeader("X-Tenant-ID"); tenantID != "" {
		if userID := c.GetString("user_id"); userID != "" {
			return fmt.Sprintf("tenant:%s:user:%s", tenantID, userID)
		}
		return fmt.Sprintf("tenant:%s", tenantID)
	}

	// Try to get user ID from context
	if userID := c.GetString("user_id"); userID != "" {
		return fmt.Sprintf("user:%s", userID)
	}

	// Fall back to IP address
	return fmt.Sprintf("ip:%s", c.ClientIP())
}

// checkRateLimit checks if request is allowed using token bucket algorithm
func (rl *AdvancedRateLimiter) checkRateLimit(key string) (allowed bool, remaining int, resetTime time.Time, err error) {
	ctx := context.Background()
	now := time.Now()
	_ = now.Truncate(time.Minute) // windowStart not used in current implementation

	// Lua script for atomic rate limiting
	script := redis.NewScript(`
		local key = KEYS[1]
		local limit = tonumber(ARGV[1])
		local window = tonumber(ARGV[2])
		local current_time = tonumber(ARGV[3])

		local current = redis.call('GET', key)

		if current == false then
			redis.call('SET', key, 1, 'EX', window)
			return {1, limit - 1, current_time + window}
		end

		current = tonumber(current)

		if current < limit then
			redis.call('INCR', key)
			local ttl = redis.call('TTL', key)
			return {1, limit - current - 1, current_time + ttl}
		else
			local ttl = redis.call('TTL', key)
			return {0, 0, current_time + ttl}
		end
	`)

	result, err := script.Run(ctx, rl.redis,
		[]string{key},
		rl.config.RequestsPerMinute,
		60, // 60 seconds window
		now.Unix(),
	).Result()

	if err != nil {
		return false, 0, time.Time{}, err
	}

	vals, ok := result.([]interface{})
	if !ok || len(vals) != 3 {
		return false, 0, time.Time{}, fmt.Errorf("invalid script result")
	}

	allowed = vals[0].(int64) == 1
	remaining = int(vals[1].(int64))
	resetTime = time.Unix(vals[2].(int64), 0)

	return allowed, remaining, resetTime, nil
}

// TieredRateLimitConfig defines tiered rate limiting
type TieredRateLimitConfig struct {
	Free      RateLimitConfig
	Premium   RateLimitConfig
	Enterprise RateLimitConfig
}

// TieredRateLimiter applies different limits based on subscription tier
type TieredRateLimiter struct {
	redis  *redis.Client
	config TieredRateLimitConfig
	logger *zap.Logger
}

// NewTieredRateLimiter creates a new tiered rate limiter
func NewTieredRateLimiter(redisClient *redis.Client, config TieredRateLimitConfig, logger *zap.Logger) *TieredRateLimiter {
	return &TieredRateLimiter{
		redis:  redisClient,
		config: config,
		logger: logger,
	}
}

// TieredRateLimitMiddleware creates tiered rate limiting middleware
func (trl *TieredRateLimiter) TieredRateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get subscription tier from context (set by auth middleware)
		tier := c.GetString("subscription_tier")

		var config RateLimitConfig
		switch tier {
		case "enterprise":
			config = trl.config.Enterprise
		case "premium":
			config = trl.config.Premium
		default:
			config = trl.config.Free
		}

		// Create rate limiter for this tier
		limiter := NewAdvancedRateLimiter(trl.redis, config, trl.logger)
		limiter.RateLimitMiddleware()(c)
	}
}

// EndpointRateLimiter applies different limits to different endpoints
type EndpointRateLimiter struct {
	redis        *redis.Client
	limits       map[string]RateLimitConfig
	defaultLimit RateLimitConfig
	logger       *zap.Logger
}

// NewEndpointRateLimiter creates endpoint-specific rate limiter
func NewEndpointRateLimiter(redisClient *redis.Client, limits map[string]RateLimitConfig, defaultLimit RateLimitConfig, logger *zap.Logger) *EndpointRateLimiter {
	return &EndpointRateLimiter{
		redis:        redisClient,
		limits:       limits,
		defaultLimit: defaultLimit,
		logger:       logger,
	}
}

// EndpointRateLimitMiddleware creates endpoint-specific rate limiting
func (erl *EndpointRateLimiter) EndpointRateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get config for this endpoint
		config, exists := erl.limits[c.Request.URL.Path]
		if !exists {
			config = erl.defaultLimit
		}

		// Apply rate limit
		limiter := NewAdvancedRateLimiter(erl.redis, config, erl.logger)
		limiter.RateLimitMiddleware()(c)
	}
}

// BrandOnboardingRateLimitConfig returns rate limit config for brand onboarding
func BrandOnboardingRateLimitConfig() RateLimitConfig {
	return RateLimitConfig{
		RequestsPerMinute: 10,  // Allow 10 brand onboarding requests per minute
		BurstSize:         3,   // Allow burst of 3 requests
		KeyPrefix:         "ratelimit:brand_onboard",
		SkipPaths:         []string{"/health", "/metrics"},
	}
}

// BrandListingRateLimitConfig returns rate limit config for brand listing
func BrandListingRateLimitConfig() RateLimitConfig {
	return RateLimitConfig{
		RequestsPerMinute: 60,  // Allow 60 brand listing requests per minute
		BurstSize:         10,  // Allow burst of 10 requests
		KeyPrefix:         "ratelimit:brand_list",
		SkipPaths:         []string{"/health", "/metrics"},
	}
}
