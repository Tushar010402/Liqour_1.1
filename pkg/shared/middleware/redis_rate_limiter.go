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

// RateLimitTier defines rate limits for different user tiers
type RateLimitTier struct {
	Name              string
	RequestsPerMinute int
}

// Default tiers matching requirements
var (
	TierPublic  = RateLimitTier{"public", 60}
	TierUser    = RateLimitTier{"user", 120}
	TierPremium = RateLimitTier{"premium", 300}
	TierAdmin   = RateLimitTier{"admin", 600}
)

// EndpointLimit defines per-endpoint rate limits
type EndpointLimit struct {
	Path              string
	RequestsPerMinute int
	IdentifierFunc    func(*gin.Context) string // Custom identifier (IP, phone, etc.)
	KeyPrefix         string
}

// RedisRateLimiter implements distributed rate limiting using Redis
type RedisRateLimiter struct {
	redis          *redis.Client
	logger         *zap.Logger
	endpointLimits map[string]EndpointLimit
}

// NewRedisRateLimiter creates a new Redis-based rate limiter
func NewRedisRateLimiter(redisClient *redis.Client, logger *zap.Logger) *RedisRateLimiter {
	return &RedisRateLimiter{
		redis:          redisClient,
		logger:         logger,
		endpointLimits: make(map[string]EndpointLimit),
	}
}

// RegisterEndpointLimit adds a specific limit for an endpoint
func (r *RedisRateLimiter) RegisterEndpointLimit(limit EndpointLimit) {
	r.endpointLimits[limit.Path] = limit
}

// Lua script for atomic rate limiting using sliding window counter
// This is more accurate than token bucket for distributed systems
var rateLimitScript = redis.NewScript(`
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
		if ttl < 0 then
			ttl = window
		end
		return {1, limit - current - 1, current_time + ttl}
	else
		local ttl = redis.call('TTL', key)
		if ttl < 0 then
			ttl = window
		end
		return {0, 0, current_time + ttl}
	end
`)

// checkLimit performs atomic rate limit check via Redis
func (r *RedisRateLimiter) checkLimit(ctx context.Context, key string, limit int) (allowed bool, remaining int, resetTime time.Time, err error) {
	now := time.Now()

	result, err := rateLimitScript.Run(ctx, r.redis,
		[]string{key},
		limit,
		60, // 60 second window
		now.Unix(),
	).Result()

	if err != nil {
		if r.logger != nil {
			r.logger.Error("Rate limit script execution failed",
				zap.String("key", key),
				zap.Error(err),
			)
		}
		return false, 0, time.Time{}, err
	}

	vals, ok := result.([]interface{})
	if !ok || len(vals) != 3 {
		return false, 0, time.Time{}, fmt.Errorf("invalid script result format")
	}

	allowed = vals[0].(int64) == 1
	remaining = int(vals[1].(int64))
	resetTime = time.Unix(vals[2].(int64), 0)

	return allowed, remaining, resetTime, nil
}

// getTierFromRole maps user roles to rate limit tiers
func (r *RedisRateLimiter) getTierFromRole(role string) RateLimitTier {
	switch role {
	case "admin", "super_admin", "saas_admin", "owner":
		return TierAdmin
	case "premium":
		return TierPremium
	case "manager", "assistant_manager", "executive", "salesman", "user":
		return TierUser
	default:
		return TierPublic
	}
}

// RoleBasedMiddleware applies rate limits based on user role
// CRITICAL: This must run AFTER AuthMiddleware to have role information
func (r *RedisRateLimiter) RoleBasedMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()

		// Determine tier based on role (set by AuthMiddleware)
		tier := TierPublic
		if role, exists := c.Get("role"); exists {
			if roleStr, ok := role.(string); ok {
				tier = r.getTierFromRole(roleStr)
			}
		}

		// Build rate limit key
		key := r.buildRoleKey(c, tier.Name)

		allowed, remaining, resetTime, err := r.checkLimit(ctx, key, tier.RequestsPerMinute)
		if err != nil {
			if r.logger != nil {
				r.logger.Error("Rate limit check failed, allowing request (fail-open)",
					zap.Error(err),
					zap.String("key", key),
				)
			}
			// Fail open on Redis errors to prevent blocking legitimate traffic
			c.Next()
			return
		}

		// Set standard rate limit headers
		c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", tier.RequestsPerMinute))
		c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", remaining))
		c.Header("X-RateLimit-Reset", fmt.Sprintf("%d", resetTime.Unix()))
		c.Header("X-RateLimit-Tier", tier.Name)

		if !allowed {
			retryAfter := int(time.Until(resetTime).Seconds())
			if retryAfter < 1 {
				retryAfter = 1
			}
			c.Header("Retry-After", fmt.Sprintf("%d", retryAfter))

			if r.logger != nil {
				r.logger.Warn("Rate limit exceeded",
					zap.String("tier", tier.Name),
					zap.Int("limit", tier.RequestsPerMinute),
					zap.String("key", key),
					zap.String("path", c.Request.URL.Path),
				)
			}

			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":       "rate_limit_exceeded",
				"message":     fmt.Sprintf("Rate limit exceeded for %s tier. Try again in %d seconds", tier.Name, retryAfter),
				"tier":        tier.Name,
				"limit":       tier.RequestsPerMinute,
				"retry_after": retryAfter,
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// EndpointMiddleware applies endpoint-specific limits
// This runs BEFORE auth for public endpoints like /api/auth/login
func (r *RedisRateLimiter) EndpointMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()
		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}

		limit, exists := r.endpointLimits[path]
		if !exists {
			// No specific endpoint limit configured
			c.Next()
			return
		}

		// Get identifier for this endpoint
		var identifier string
		if limit.IdentifierFunc != nil {
			identifier = limit.IdentifierFunc(c)
		} else {
			// Default to user_id if authenticated, otherwise IP
			if userID := c.GetString("user_id"); userID != "" {
				identifier = userID
			} else {
				identifier = c.ClientIP()
			}
		}

		key := fmt.Sprintf("ratelimit:%s:%s", limit.KeyPrefix, identifier)

		allowed, remaining, resetTime, err := r.checkLimit(ctx, key, limit.RequestsPerMinute)
		if err != nil {
			if r.logger != nil {
				r.logger.Error("Endpoint rate limit check failed, allowing request (fail-open)",
					zap.Error(err),
					zap.String("path", path),
					zap.String("identifier", identifier),
				)
			}
			// Fail open
			c.Next()
			return
		}

		c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", limit.RequestsPerMinute))
		c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", remaining))
		c.Header("X-RateLimit-Reset", fmt.Sprintf("%d", resetTime.Unix()))

		if !allowed {
			retryAfter := int(time.Until(resetTime).Seconds())
			if retryAfter < 1 {
				retryAfter = 1
			}
			c.Header("Retry-After", fmt.Sprintf("%d", retryAfter))

			if r.logger != nil {
				r.logger.Warn("Endpoint rate limit exceeded",
					zap.String("path", path),
					zap.Int("limit", limit.RequestsPerMinute),
					zap.String("identifier", identifier),
				)
			}

			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":       "endpoint_rate_limit_exceeded",
				"message":     fmt.Sprintf("Too many requests to %s. Try again in %d seconds", path, retryAfter),
				"endpoint":    path,
				"limit":       limit.RequestsPerMinute,
				"retry_after": retryAfter,
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// GlobalIPMiddleware applies a global IP-based rate limit for all requests
// This provides baseline DDoS protection
func (r *RedisRateLimiter) GlobalIPMiddleware(requestsPerMinute int) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()
		ip := c.ClientIP()
		key := fmt.Sprintf("ratelimit:global:ip:%s", ip)

		allowed, remaining, resetTime, err := r.checkLimit(ctx, key, requestsPerMinute)
		if err != nil {
			// Fail open
			c.Next()
			return
		}

		c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", requestsPerMinute))
		c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", remaining))
		c.Header("X-RateLimit-Reset", fmt.Sprintf("%d", resetTime.Unix()))

		if !allowed {
			retryAfter := int(time.Until(resetTime).Seconds())
			if retryAfter < 1 {
				retryAfter = 1
			}
			c.Header("Retry-After", fmt.Sprintf("%d", retryAfter))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":       "global_rate_limit_exceeded",
				"message":     fmt.Sprintf("Too many requests. Try again in %d seconds", retryAfter),
				"retry_after": retryAfter,
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// buildRoleKey creates a Redis key for role-based rate limiting
func (r *RedisRateLimiter) buildRoleKey(c *gin.Context, tier string) string {
	// Use tenant:user:tier format for authenticated users
	if userID := c.GetString("user_id"); userID != "" {
		tenantID := c.GetString("tenant_id")
		if tenantID != "" {
			return fmt.Sprintf("ratelimit:role:%s:%s:%s", tenantID, userID, tier)
		}
		return fmt.Sprintf("ratelimit:role:global:%s:%s", userID, tier)
	}
	// Use IP for unauthenticated requests
	return fmt.Sprintf("ratelimit:ip:%s:%s", c.ClientIP(), tier)
}

// GetIPIdentifier returns IP address for rate limiting
func GetIPIdentifier(c *gin.Context) string {
	return c.ClientIP()
}

// GetPhoneOrIPIdentifier tries to get phone from request body, falls back to IP
func GetPhoneOrIPIdentifier(c *gin.Context) string {
	// Try to peek at the phone field from various sources
	if phone := c.Query("phone"); phone != "" {
		return "phone:" + phone
	}
	if phone := c.Query("mobile"); phone != "" {
		return "phone:" + phone
	}
	if phone := c.PostForm("phone"); phone != "" {
		return "phone:" + phone
	}
	if phone := c.PostForm("mobile"); phone != "" {
		return "phone:" + phone
	}
	// Fall back to IP for JSON requests (can't peek body without consuming)
	return "ip:" + c.ClientIP()
}
