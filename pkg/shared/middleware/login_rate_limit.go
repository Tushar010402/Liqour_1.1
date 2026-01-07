package middleware

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// LoginRateLimiter tracks failed login attempts and implements account lockout
type LoginRateLimiter struct {
	redis  *redis.Client
	logger *zap.Logger

	// Configurable settings (Moderate - as per plan)
	MaxFailedAttempts   int           // 10 attempts before lockout
	AccountLockDuration time.Duration // 10 minutes lockout
	IPBlockThreshold    int           // 30 attempts across all accounts
	IPBlockDuration     time.Duration // 30 minutes IP block
}

// LoginRateLimiterConfig holds configuration for login rate limiter
type LoginRateLimiterConfig struct {
	MaxFailedAttempts   int
	AccountLockDuration time.Duration
	IPBlockThreshold    int
	IPBlockDuration     time.Duration
}

// DefaultLoginRateLimiterConfig returns moderate security settings
func DefaultLoginRateLimiterConfig() LoginRateLimiterConfig {
	return LoginRateLimiterConfig{
		MaxFailedAttempts:   10,               // 10 failed attempts
		AccountLockDuration: 10 * time.Minute, // 10 minute lockout
		IPBlockThreshold:    30,               // 30 attempts from same IP
		IPBlockDuration:     30 * time.Minute, // 30 minute IP block
	}
}

// NewLoginRateLimiter creates a new login rate limiter with moderate settings
func NewLoginRateLimiter(redisClient *redis.Client, logger *zap.Logger) *LoginRateLimiter {
	config := DefaultLoginRateLimiterConfig()
	return &LoginRateLimiter{
		redis:               redisClient,
		logger:              logger,
		MaxFailedAttempts:   config.MaxFailedAttempts,
		AccountLockDuration: config.AccountLockDuration,
		IPBlockThreshold:    config.IPBlockThreshold,
		IPBlockDuration:     config.IPBlockDuration,
	}
}

// NewLoginRateLimiterWithConfig creates a login rate limiter with custom config
func NewLoginRateLimiterWithConfig(redisClient *redis.Client, logger *zap.Logger, config LoginRateLimiterConfig) *LoginRateLimiter {
	return &LoginRateLimiter{
		redis:               redisClient,
		logger:              logger,
		MaxFailedAttempts:   config.MaxFailedAttempts,
		AccountLockDuration: config.AccountLockDuration,
		IPBlockThreshold:    config.IPBlockThreshold,
		IPBlockDuration:     config.IPBlockDuration,
	}
}

// ErrAccountLocked is returned when the account is locked
var ErrAccountLocked = errors.New("account_locked")

// ErrIPBlocked is returned when the IP is blocked
var ErrIPBlocked = errors.New("ip_blocked")

// TrackFailedLogin increments failed login counter and locks if threshold exceeded
// Returns error if account is locked or IP is blocked
func (l *LoginRateLimiter) TrackFailedLogin(ctx context.Context, identifier, ip string) error {
	// Track per-account failures
	accountKey := fmt.Sprintf("login:failed:account:%s", identifier)
	count, err := l.redis.Incr(ctx, accountKey).Result()
	if err != nil {
		l.logger.Error("Failed to increment account failure counter",
			zap.String("identifier", identifier),
			zap.Error(err),
		)
		// Don't block on Redis errors - fail open
		return nil
	}
	l.redis.Expire(ctx, accountKey, l.AccountLockDuration)

	// Track per-IP failures
	ipKey := fmt.Sprintf("login:failed:ip:%s", ip)
	ipCount, err := l.redis.Incr(ctx, ipKey).Result()
	if err != nil {
		l.logger.Error("Failed to increment IP failure counter",
			zap.String("ip", ip),
			zap.Error(err),
		)
	} else {
		l.redis.Expire(ctx, ipKey, l.IPBlockDuration)
	}

	// Log the attempt
	l.logger.Warn("Failed login attempt",
		zap.String("identifier", identifier),
		zap.String("ip", ip),
		zap.Int64("account_attempts", count),
		zap.Int64("ip_attempts", ipCount),
	)

	// Check account lockout
	if count >= int64(l.MaxFailedAttempts) {
		lockKey := fmt.Sprintf("login:locked:account:%s", identifier)
		l.redis.Set(ctx, lockKey, "1", l.AccountLockDuration)
		l.logger.Warn("Account locked due to failed attempts",
			zap.String("identifier", identifier),
			zap.Duration("lock_duration", l.AccountLockDuration),
			zap.Int64("failed_attempts", count),
		)
		return ErrAccountLocked
	}

	// Check IP block
	if ipCount >= int64(l.IPBlockThreshold) {
		ipLockKey := fmt.Sprintf("login:locked:ip:%s", ip)
		l.redis.Set(ctx, ipLockKey, "1", l.IPBlockDuration)
		l.logger.Warn("IP blocked due to excessive failed attempts",
			zap.String("ip", ip),
			zap.Duration("block_duration", l.IPBlockDuration),
			zap.Int64("failed_attempts", ipCount),
		)
		return ErrIPBlocked
	}

	return nil
}

// IsAccountLocked checks if account is locked
func (l *LoginRateLimiter) IsAccountLocked(ctx context.Context, identifier string) bool {
	lockKey := fmt.Sprintf("login:locked:account:%s", identifier)
	exists, err := l.redis.Exists(ctx, lockKey).Result()
	if err != nil {
		l.logger.Error("Failed to check account lock status",
			zap.String("identifier", identifier),
			zap.Error(err),
		)
		// Fail open on Redis errors
		return false
	}
	return exists > 0
}

// IsIPBlocked checks if IP is blocked
func (l *LoginRateLimiter) IsIPBlocked(ctx context.Context, ip string) bool {
	ipLockKey := fmt.Sprintf("login:locked:ip:%s", ip)
	exists, err := l.redis.Exists(ctx, ipLockKey).Result()
	if err != nil {
		l.logger.Error("Failed to check IP block status",
			zap.String("ip", ip),
			zap.Error(err),
		)
		// Fail open on Redis errors
		return false
	}
	return exists > 0
}

// ClearFailedAttempts clears failed attempt counter on successful login
func (l *LoginRateLimiter) ClearFailedAttempts(ctx context.Context, identifier string) {
	accountKey := fmt.Sprintf("login:failed:account:%s", identifier)
	err := l.redis.Del(ctx, accountKey).Err()
	if err != nil {
		l.logger.Error("Failed to clear failed attempts",
			zap.String("identifier", identifier),
			zap.Error(err),
		)
		return
	}
	l.logger.Info("Cleared failed login attempts on successful login",
		zap.String("identifier", identifier),
	)
}

// GetRemainingAttempts returns remaining attempts before lockout
func (l *LoginRateLimiter) GetRemainingAttempts(ctx context.Context, identifier string) int {
	accountKey := fmt.Sprintf("login:failed:account:%s", identifier)
	count, err := l.redis.Get(ctx, accountKey).Int()
	if err != nil {
		// Key doesn't exist or error - return max attempts
		return l.MaxFailedAttempts
	}
	remaining := l.MaxFailedAttempts - count
	if remaining < 0 {
		return 0
	}
	return remaining
}

// GetAccountLockoutTTL returns time remaining until account lockout expires
func (l *LoginRateLimiter) GetAccountLockoutTTL(ctx context.Context, identifier string) time.Duration {
	lockKey := fmt.Sprintf("login:locked:account:%s", identifier)
	ttl, err := l.redis.TTL(ctx, lockKey).Result()
	if err != nil || ttl < 0 {
		return 0
	}
	return ttl
}

// GetIPBlockTTL returns time remaining until IP block expires
func (l *LoginRateLimiter) GetIPBlockTTL(ctx context.Context, ip string) time.Duration {
	ipLockKey := fmt.Sprintf("login:locked:ip:%s", ip)
	ttl, err := l.redis.TTL(ctx, ipLockKey).Result()
	if err != nil || ttl < 0 {
		return 0
	}
	return ttl
}

// LoginLockoutMiddleware creates a middleware that checks for account/IP lockouts before login
func (l *LoginRateLimiter) LoginLockoutMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := context.Background()
		ip := c.ClientIP()

		// Check IP block first
		if l.IsIPBlocked(ctx, ip) {
			ttl := l.GetIPBlockTTL(ctx, ip)
			c.Header("Retry-After", fmt.Sprintf("%d", int(ttl.Seconds())))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":                    "ip_blocked",
				"message":                  "Too many failed login attempts from this IP. Please try again later.",
				"retry_after":              int(ttl.Seconds()),
				"remaining_block_seconds":  int(ttl.Seconds()),
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// CheckAndBlockLogin is a helper function to check lockout status before login
// Returns appropriate error response if blocked, nil otherwise
func (l *LoginRateLimiter) CheckAndBlockLogin(c *gin.Context, identifier string) error {
	ctx := context.Background()
	ip := c.ClientIP()

	// Check IP block first
	if l.IsIPBlocked(ctx, ip) {
		ttl := l.GetIPBlockTTL(ctx, ip)
		c.Header("Retry-After", fmt.Sprintf("%d", int(ttl.Seconds())))
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":                   "ip_blocked",
			"message":                 "Too many failed login attempts from this IP. Please try again later.",
			"retry_after":             int(ttl.Seconds()),
			"remaining_block_seconds": int(ttl.Seconds()),
		})
		return ErrIPBlocked
	}

	// Check account lockout
	if l.IsAccountLocked(ctx, identifier) {
		ttl := l.GetAccountLockoutTTL(ctx, identifier)
		c.Header("Retry-After", fmt.Sprintf("%d", int(ttl.Seconds())))
		c.JSON(http.StatusLocked, gin.H{
			"error":                     "account_locked",
			"message":                   "Account temporarily locked due to too many failed login attempts.",
			"retry_after":               int(ttl.Seconds()),
			"remaining_lockout_seconds": int(ttl.Seconds()),
		})
		return ErrAccountLocked
	}

	return nil
}

// HandleFailedLogin should be called after a failed login attempt
// It tracks the failure and returns remaining attempts info
func (l *LoginRateLimiter) HandleFailedLogin(c *gin.Context, identifier string) (remainingAttempts int, wasLocked bool) {
	ctx := context.Background()
	ip := c.ClientIP()

	err := l.TrackFailedLogin(ctx, identifier, ip)
	remaining := l.GetRemainingAttempts(ctx, identifier)

	if err == ErrAccountLocked {
		return 0, true
	}

	return remaining, false
}

// HandleSuccessfulLogin should be called after a successful login
// It clears the failed attempt counter
func (l *LoginRateLimiter) HandleSuccessfulLogin(ctx context.Context, identifier string) {
	l.ClearFailedAttempts(ctx, identifier)
}
