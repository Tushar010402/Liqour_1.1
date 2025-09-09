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

// Custom errors
var (
	ErrCacheMiss = fmt.Errorf("cache miss")
)

// Common cache keys and patterns
const (
	UserSessionKey     = "session:user:%s"
	TenantKey         = "tenant:%s"
	ProductKey        = "product:%s"
	StockKey          = "stock:%s:%s" // shop:product
	DailySalesKey     = "daily_sales:%s:%s" // shop:date
	PendingApprovalsKey = "pending_approvals:%s" // user_id
	
	// Cache durations
	DefaultTTL       = 1 * time.Hour
	SessionTTL       = 24 * time.Hour
	ShortTTL         = 15 * time.Minute
	LongTTL          = 24 * time.Hour
)