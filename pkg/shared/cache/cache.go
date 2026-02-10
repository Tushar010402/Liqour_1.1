package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// Cache wraps Redis client
type Cache struct {
	client *redis.Client
}

// Config holds cache configuration
type Config struct {
	Host     string
	Port     int
	Password string
	DB       int
}

// NewCache creates a new Redis cache client
func NewCache(config Config) (*Cache, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", config.Host, config.Port),
		Password: config.Password,
		DB:       config.DB,
		// Connection pool settings - scaled for 100K concurrent users
		PoolSize:     100,              // Every auth check hits Redis
		MinIdleConns: 20,               // Keep more warm connections
		PoolTimeout:  30 * time.Second, // Wait time for pool connection
		// Connection timeouts
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
		// Retry settings
		MaxRetries: 3,
	})

	// Test connection
	ctx := context.Background()
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	return &Cache{client: client}, nil
}

// Set stores a key-value pair with expiration
func (c *Cache) Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error {
	json, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("failed to marshal value: %w", err)
	}

	return c.client.Set(ctx, key, json, expiration).Err()
}

// Get retrieves a value by key
func (c *Cache) Get(ctx context.Context, key string, dest interface{}) error {
	result := c.client.Get(ctx, key)
	if err := result.Err(); err != nil {
		if err == redis.Nil {
			return ErrCacheMiss
		}
		return fmt.Errorf("failed to get cache key %s: %w", key, err)
	}

	data, err := result.Bytes()
	if err != nil {
		return fmt.Errorf("failed to get bytes from cache: %w", err)
	}

	if err := json.Unmarshal(data, dest); err != nil {
		return fmt.Errorf("failed to unmarshal cache data: %w", err)
	}

	return nil
}

// Delete removes a key from cache
func (c *Cache) Delete(ctx context.Context, keys ...string) error {
	return c.client.Del(ctx, keys...).Err()
}

// Exists checks if a key exists
func (c *Cache) Exists(ctx context.Context, key string) (bool, error) {
	result := c.client.Exists(ctx, key)
	if err := result.Err(); err != nil {
		return false, err
	}
	return result.Val() > 0, nil
}

// SetWithTTL sets a key with a specific TTL
func (c *Cache) SetWithTTL(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	return c.Set(ctx, key, value, ttl)
}

// GetTTL returns the remaining TTL for a key
func (c *Cache) GetTTL(ctx context.Context, key string) (time.Duration, error) {
	return c.client.TTL(ctx, key).Result()
}

// Increment increments a numeric key
func (c *Cache) Increment(ctx context.Context, key string) (int64, error) {
	return c.client.Incr(ctx, key).Result()
}

// Decrement decrements a numeric key
func (c *Cache) Decrement(ctx context.Context, key string) (int64, error) {
	return c.client.Decr(ctx, key).Result()
}

// SetNX sets a key only if it does not exist (for distributed locking)
// Returns true if the key was set, false if it already existed
func (c *Cache) SetNX(ctx context.Context, key string, value interface{}, expiration time.Duration) (bool, error) {
	jsonValue, err := json.Marshal(value)
	if err != nil {
		return false, fmt.Errorf("failed to marshal value: %w", err)
	}
	return c.client.SetNX(ctx, key, jsonValue, expiration).Result()
}

// SetHash stores a hash field
func (c *Cache) SetHash(ctx context.Context, key, field string, value interface{}) error {
	json, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("failed to marshal hash value: %w", err)
	}
	return c.client.HSet(ctx, key, field, json).Err()
}

// GetHash retrieves a hash field
func (c *Cache) GetHash(ctx context.Context, key, field string, dest interface{}) error {
	result := c.client.HGet(ctx, key, field)
	if err := result.Err(); err != nil {
		if err == redis.Nil {
			return ErrCacheMiss
		}
		return fmt.Errorf("failed to get hash %s.%s: %w", key, field, err)
	}

	data, err := result.Bytes()
	if err != nil {
		return fmt.Errorf("failed to get bytes from hash: %w", err)
	}

	if err := json.Unmarshal(data, dest); err != nil {
		return fmt.Errorf("failed to unmarshal hash data: %w", err)
	}

	return nil
}

// DeleteHash deletes hash fields
func (c *Cache) DeleteHash(ctx context.Context, key string, fields ...string) error {
	return c.client.HDel(ctx, key, fields...).Err()
}

// SetList pushes values to a list
func (c *Cache) SetList(ctx context.Context, key string, values ...interface{}) error {
	jsonValues := make([]interface{}, len(values))
	for i, v := range values {
		json, err := json.Marshal(v)
		if err != nil {
			return fmt.Errorf("failed to marshal list value: %w", err)
		}
		jsonValues[i] = json
	}
	return c.client.RPush(ctx, key, jsonValues...).Err()
}

// GetList retrieves list values
func (c *Cache) GetList(ctx context.Context, key string, start, stop int64) ([]string, error) {
	return c.client.LRange(ctx, key, start, stop).Result()
}

// Flush clears all keys
func (c *Cache) Flush(ctx context.Context) error {
	return c.client.FlushDB(ctx).Err()
}

// Close closes the Redis connection
func (c *Cache) Close() error {
	return c.client.Close()
}

// Health checks cache connectivity
func (c *Cache) Health(ctx context.Context) error {
	return c.client.Ping(ctx).Err()
}

// Lock acquires a distributed lock
func (c *Cache) Lock(ctx context.Context, key string, expiration time.Duration) (bool, error) {
	result := c.client.SetNX(ctx, "lock:"+key, "locked", expiration)
	return result.Result()
}

// Unlock releases a distributed lock
func (c *Cache) Unlock(ctx context.Context, key string) error {
	return c.client.Del(ctx, "lock:"+key).Err()
}

// Client returns the underlying Redis client for advanced operations
func (c *Cache) Client() *redis.Client {
	return c.client
}

// ============================================================================
// High-Performance Methods for Sub-20ms Response Times
// ============================================================================

// IncrementWithExpiry atomically increments a key and sets expiry (single round-trip)
// Returns the new value after increment
func (c *Cache) IncrementWithExpiry(ctx context.Context, key string, expiry time.Duration) (int64, error) {
	pipe := c.client.Pipeline()
	incrCmd := pipe.Incr(ctx, key)
	pipe.Expire(ctx, key, expiry)
	_, err := pipe.Exec(ctx)
	if err != nil {
		return 0, err
	}
	return incrCmd.Val(), nil
}

// GetMulti retrieves multiple keys in a single round-trip using pipeline
// Returns a map of key -> raw JSON bytes (caller must unmarshal)
func (c *Cache) GetMulti(ctx context.Context, keys ...string) (map[string][]byte, error) {
	if len(keys) == 0 {
		return make(map[string][]byte), nil
	}

	pipe := c.client.Pipeline()
	cmds := make(map[string]*redis.StringCmd, len(keys))

	for _, key := range keys {
		cmds[key] = pipe.Get(ctx, key)
	}

	_, err := pipe.Exec(ctx)
	// Ignore redis.Nil errors - some keys may not exist
	if err != nil && err != redis.Nil {
		return nil, err
	}

	results := make(map[string][]byte, len(keys))
	for key, cmd := range cmds {
		if data, err := cmd.Bytes(); err == nil {
			results[key] = data
		}
	}

	return results, nil
}

// SetMulti stores multiple key-value pairs in a single round-trip using pipeline
func (c *Cache) SetMulti(ctx context.Context, items map[string]interface{}, expiration time.Duration) error {
	if len(items) == 0 {
		return nil
	}

	pipe := c.client.Pipeline()

	for key, value := range items {
		jsonData, err := json.Marshal(value)
		if err != nil {
			return fmt.Errorf("failed to marshal value for key %s: %w", key, err)
		}
		pipe.Set(ctx, key, jsonData, expiration)
	}

	_, err := pipe.Exec(ctx)
	return err
}

// ExistsMulti checks multiple keys existence in a single round-trip
// Returns a map of key -> exists
func (c *Cache) ExistsMulti(ctx context.Context, keys ...string) (map[string]bool, error) {
	if len(keys) == 0 {
		return make(map[string]bool), nil
	}

	pipe := c.client.Pipeline()
	cmds := make(map[string]*redis.IntCmd, len(keys))

	for _, key := range keys {
		cmds[key] = pipe.Exists(ctx, key)
	}

	_, err := pipe.Exec(ctx)
	if err != nil {
		return nil, err
	}

	results := make(map[string]bool, len(keys))
	for key, cmd := range cmds {
		results[key] = cmd.Val() > 0
	}

	return results, nil
}

// GetAndDelete atomically gets and deletes a key (for OTP verification)
func (c *Cache) GetAndDelete(ctx context.Context, key string, dest interface{}) error {
	result := c.client.GetDel(ctx, key)
	if err := result.Err(); err != nil {
		if err == redis.Nil {
			return ErrCacheMiss
		}
		return fmt.Errorf("failed to get and delete key %s: %w", key, err)
	}

	data, err := result.Bytes()
	if err != nil {
		return fmt.Errorf("failed to get bytes: %w", err)
	}

	if err := json.Unmarshal(data, dest); err != nil {
		return fmt.Errorf("failed to unmarshal data: %w", err)
	}

	return nil
}

// SetIfNotExistsWithValue sets a key only if it doesn't exist, using raw string value
// More efficient than SetNX when value doesn't need JSON marshaling
func (c *Cache) SetIfNotExistsRaw(ctx context.Context, key string, value string, expiration time.Duration) (bool, error) {
	return c.client.SetNX(ctx, key, value, expiration).Result()
}

// GetRaw retrieves a raw string value without JSON unmarshaling
func (c *Cache) GetRaw(ctx context.Context, key string) (string, error) {
	result, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", ErrCacheMiss
	}
	return result, err
}

// Custom errors
var (
	ErrCacheMiss = fmt.Errorf("cache miss")
)

// Common cache keys and patterns
const (
	UserSessionKey      = "session:user:%s"
	TenantKey           = "tenant:%s"
	ProductKey          = "product:%s"
	StockKey            = "stock:%s:%s"          // shop:product
	DailySalesKey       = "daily_sales:%s:%s"    // shop:date
	PendingApprovalsKey = "pending_approvals:%s" // user_id
	DeviceSessionKey    = "session:device:%s"    // session_id
	UserProfileKey      = "user_profile:%s"      // user_id
	RateLimitKey        = "ratelimit:%s:%s:%d"   // name:identifier:window
	ActiveSessionsKey   = "device_sessions:%s"   // user_id
	RateLimitConfigKey  = "ratelimit_config:%s"  // rate_limit_name
	UserByPhoneKey      = "user:phone:%s"        // phone number -> user data
	OTPCounterKey       = "otp_counter:%s"       // phone -> attempt count
	BlockedNumberKey    = "blocked:mobile:%s"    // blocked phone numbers

	// Cache durations - optimized for sub-20ms response times
	DefaultTTL         = 1 * time.Hour
	SessionTTL         = 7 * 24 * time.Hour  // 7 days - match JWT_REFRESH_HOURS=168
	ShortTTL           = 15 * time.Minute
	LongTTL            = 24 * time.Hour
	ProfileCacheTTL    = 5 * time.Minute    // User profile cache
	RateLimitConfigTTL = 1 * time.Hour      // Rate limit config cache (long - rarely changes)
	RateLimitTTL       = 5 * time.Minute    // Rate limit counter cache
	DeviceCacheTTL     = 30 * time.Second   // Device session cache
	UserByPhoneTTL     = 2 * time.Minute    // User lookup by phone (short for consistency)
	OTPWindowTTL       = 2 * time.Minute    // OTP rate limit window
)
