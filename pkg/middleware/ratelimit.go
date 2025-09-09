package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"go.uber.org/zap"
)

// RateLimiter interface for different rate limiting strategies
type RateLimiter interface {
	Allow(ctx context.Context, key string) (bool, error)
	Reset(ctx context.Context, key string) error
}

// RedisRateLimiter implements rate limiting using Redis
type RedisRateLimiter struct {
	client   *redis.Client
	limit    int
	window   time.Duration
	logger   *zap.Logger
}

// NewRedisRateLimiter creates a new Redis-based rate limiter
func NewRedisRateLimiter(client *redis.Client, limit int, window time.Duration, logger *zap.Logger) *RedisRateLimiter {
	return &RedisRateLimiter{
		client: client,
		limit:  limit,
		window: window,
		logger: logger,
	}
}

// Allow checks if the request is allowed based on rate limit
func (rl *RedisRateLimiter) Allow(ctx context.Context, key string) (bool, error) {
	now := time.Now()
	windowStart := now.Truncate(rl.window).Unix()
	redisKey := fmt.Sprintf("rate_limit:%s:%d", key, windowStart)

	// Use Redis pipeline for atomic operations
	pipe := rl.client.Pipeline()
	
	// Increment counter
	incrCmd := pipe.Incr(ctx, redisKey)
	
	// Set expiration only if this is a new key
	pipe.Expire(ctx, redisKey, rl.window)
	
	_, err := pipe.Exec(ctx)
	if err != nil {
		rl.logger.Error("Failed to execute rate limit pipeline", zap.Error(err))
		return false, err
	}

	count := incrCmd.Val()
	
	rl.logger.Debug("Rate limit check",
		zap.String("key", key),
		zap.Int64("count", count),
		zap.Int("limit", rl.limit),
	)

	return count <= int64(rl.limit), nil
}

// Reset resets the rate limit for a key
func (rl *RedisRateLimiter) Reset(ctx context.Context, key string) error {
	pattern := fmt.Sprintf("rate_limit:%s:*", key)
	keys, err := rl.client.Keys(ctx, pattern).Result()
	if err != nil {
		return err
	}
	
	if len(keys) > 0 {
		return rl.client.Del(ctx, keys...).Err()
	}
	
	return nil
}

// RateLimitConfig holds rate limiting configuration
type RateLimitConfig struct {
	Global struct {
		Enabled bool `yaml:"enabled" json:"enabled"`
		Limit   int  `yaml:"limit" json:"limit"`
		Window  string `yaml:"window" json:"window"`
	} `yaml:"global" json:"global"`
	
	PerUser struct {
		Enabled bool `yaml:"enabled" json:"enabled"`
		Limit   int  `yaml:"limit" json:"limit"`
		Window  string `yaml:"window" json:"window"`
	} `yaml:"per_user" json:"per_user"`
	
	PerTenant struct {
		Enabled bool `yaml:"enabled" json:"enabled"`
		Limit   int  `yaml:"limit" json:"limit"`
		Window  string `yaml:"window" json:"window"`
	} `yaml:"per_tenant" json:"per_tenant"`
	
	PerIP struct {
		Enabled bool `yaml:"enabled" json:"enabled"`
		Limit   int  `yaml:"limit" json:"limit"`
		Window  string `yaml:"window" json:"window"`
	} `yaml:"per_ip" json:"per_ip"`
}

// RateLimitMiddleware creates a rate limiting middleware
func RateLimitMiddleware(redisClient *redis.Client, config RateLimitConfig, logger *zap.Logger) gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		ctx := c.Request.Context()
		
		// Check different rate limit types
		if config.Global.Enabled {
			if !checkRateLimit(ctx, redisClient, "global", "global", config.Global.Limit, config.Global.Window, logger, c) {
				return
			}
		}
		
		if config.PerIP.Enabled {
			clientIP := c.ClientIP()
			if !checkRateLimit(ctx, redisClient, "ip", clientIP, config.PerIP.Limit, config.PerIP.Window, logger, c) {
				return
			}
		}
		
		if config.PerUser.Enabled {
			userID := c.GetString("user_id")
			if userID != "" {
				if !checkRateLimit(ctx, redisClient, "user", userID, config.PerUser.Limit, config.PerUser.Window, logger, c) {
					return
				}
			}
		}
		
		if config.PerTenant.Enabled {
			tenantID := c.GetString("tenant_id")
			if tenantID != "" {
				if !checkRateLimit(ctx, redisClient, "tenant", tenantID, config.PerTenant.Limit, config.PerTenant.Window, logger, c) {
					return
				}
			}
		}
		
		c.Next()
	})
}

// checkRateLimit performs the actual rate limit check
func checkRateLimit(ctx context.Context, redisClient *redis.Client, limitType, key string, limit int, windowStr string, logger *zap.Logger, c *gin.Context) bool {
	window, err := time.ParseDuration(windowStr)
	if err != nil {
		logger.Error("Invalid rate limit window", zap.String("window", windowStr), zap.Error(err))
		return true // Allow request if configuration is invalid
	}
	
	rateLimiter := NewRedisRateLimiter(redisClient, limit, window, logger)
	
	allowed, err := rateLimiter.Allow(ctx, fmt.Sprintf("%s:%s", limitType, key))
	if err != nil {
		logger.Error("Rate limit check failed", 
			zap.String("type", limitType),
			zap.String("key", key),
			zap.Error(err),
		)
		return true // Allow request if rate limiter fails
	}
	
	if !allowed {
		logger.Warn("Rate limit exceeded",
			zap.String("type", limitType),
			zap.String("key", key),
			zap.Int("limit", limit),
			zap.String("window", windowStr),
		)
		
		// Set rate limit headers
		c.Header("X-RateLimit-Limit", strconv.Itoa(limit))
		c.Header("X-RateLimit-Window", windowStr)
		c.Header("Retry-After", windowStr)
		
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":   "Rate limit exceeded",
			"message": fmt.Sprintf("Too many requests. Limit: %d per %s", limit, windowStr),
			"retry_after": windowStr,
		})
		c.Abort()
		return false
	}
	
	// Set rate limit headers for successful requests
	c.Header("X-RateLimit-Limit", strconv.Itoa(limit))
	c.Header("X-RateLimit-Window", windowStr)
	
	return true
}

// TokenBucketRateLimiter implements token bucket algorithm
type TokenBucketRateLimiter struct {
	client     *redis.Client
	capacity   int
	refillRate float64
	logger     *zap.Logger
}

// NewTokenBucketRateLimiter creates a token bucket rate limiter
func NewTokenBucketRateLimiter(client *redis.Client, capacity int, refillRate float64, logger *zap.Logger) *TokenBucketRateLimiter {
	return &TokenBucketRateLimiter{
		client:     client,
		capacity:   capacity,
		refillRate: refillRate,
		logger:     logger,
	}
}

// Allow checks if request is allowed using token bucket algorithm
func (tbl *TokenBucketRateLimiter) Allow(ctx context.Context, key string) (bool, error) {
	now := time.Now()
	redisKey := fmt.Sprintf("token_bucket:%s", key)
	
	// Lua script for atomic token bucket operations
	luaScript := `
		local key = KEYS[1]
		local capacity = tonumber(ARGV[1])
		local refill_rate = tonumber(ARGV[2])
		local now = tonumber(ARGV[3])
		local tokens_requested = tonumber(ARGV[4])
		
		local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
		local tokens = tonumber(bucket[1]) or capacity
		local last_refill = tonumber(bucket[2]) or now
		
		-- Calculate tokens to add based on time elapsed
		local time_elapsed = (now - last_refill) / 1000 -- Convert to seconds
		local tokens_to_add = time_elapsed * refill_rate
		tokens = math.min(capacity, tokens + tokens_to_add)
		
		-- Check if we have enough tokens
		if tokens >= tokens_requested then
			tokens = tokens - tokens_requested
			redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
			redis.call('EXPIRE', key, 3600) -- Expire after 1 hour of inactivity
			return {1, tokens}
		else
			redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
			redis.call('EXPIRE', key, 3600)
			return {0, tokens}
		end
	`
	
	result, err := rl.client.Eval(ctx, luaScript, []string{redisKey}, tbl.capacity, tbl.refillRate, now.UnixMilli(), 1).Result()
	if err != nil {
		tbl.logger.Error("Token bucket script failed", zap.Error(err))
		return false, err
	}
	
	resultArray := result.([]interface{})
	allowed := resultArray[0].(int64) == 1
	
	return allowed, nil
}

// Reset resets the token bucket for a key
func (tbl *TokenBucketRateLimiter) Reset(ctx context.Context, key string) error {
	redisKey := fmt.Sprintf("token_bucket:%s", key)
	return tbl.client.Del(ctx, redisKey).Err()
}