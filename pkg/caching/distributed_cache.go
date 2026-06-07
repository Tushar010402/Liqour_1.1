package caching

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

var (
	ErrCacheMiss         = errors.New("cache miss")
	ErrCacheExpired      = errors.New("cache expired")
	ErrSerializationFailed = errors.New("serialization failed")
)

// DistributedCache provides distributed caching capabilities
type DistributedCache struct {
	redis       *redis.Client
	localCache  *LocalCache
	logger      *zap.Logger
	config      *CacheConfig
	metrics     *CacheMetrics
	mu          sync.RWMutex
}

// CacheConfig contains cache configuration
type CacheConfig struct {
	RedisAddr        string        `yaml:"redis_addr"`
	RedisPassword    string        `yaml:"redis_password"`
	RedisDB          int           `yaml:"redis_db"`
	LocalCacheSize   int           `yaml:"local_cache_size"`
	DefaultTTL       time.Duration `yaml:"default_ttl"`
	MaxRetries       int           `yaml:"max_retries"`
	EnableLocalCache bool          `yaml:"enable_local_cache"`
	Namespace        string        `yaml:"namespace"`
}

// CacheMetrics tracks cache performance
type CacheMetrics struct {
	Hits        int64
	Misses      int64
	Sets        int64
	Deletes     int64
	Evictions   int64
	LocalHits   int64
	RemoteHits  int64
	mu          sync.Mutex
}

// LocalCache provides L1 caching
type LocalCache struct {
	data     map[string]*CacheItem
	maxSize  int
	mu       sync.RWMutex
	metrics  *CacheMetrics
}

// CacheItem represents a cached item
type CacheItem struct {
	Value      interface{}
	Expiration time.Time
	Size       int
}

// NewDistributedCache creates a new distributed cache
func NewDistributedCache(config *CacheConfig, logger *zap.Logger) (*DistributedCache, error) {
	// Create Redis client
	redisClient := redis.NewClient(&redis.Options{
		Addr:     config.RedisAddr,
		Password: config.RedisPassword,
		DB:       config.RedisDB,
		PoolSize: 100,
		MaxRetries: config.MaxRetries,
	})

	// Test connection
	ctx := context.Background()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	cache := &DistributedCache{
		redis:   redisClient,
		logger:  logger,
		config:  config,
		metrics: &CacheMetrics{},
	}

	// Initialize local cache if enabled
	if config.EnableLocalCache {
		cache.localCache = NewLocalCache(config.LocalCacheSize, cache.metrics)
	}

	// Start metrics reporter
	go cache.reportMetrics()

	logger.Info("Distributed cache initialized",
		zap.String("redis_addr", config.RedisAddr),
		zap.Bool("local_cache", config.EnableLocalCache))

	return cache, nil
}

// Get retrieves a value from cache
func (dc *DistributedCache) Get(ctx context.Context, key string) (interface{}, error) {
	fullKey := dc.buildKey(key)

	// Try local cache first (L1)
	if dc.config.EnableLocalCache {
		if value, found := dc.localCache.Get(fullKey); found {
			dc.recordHit(true)
			return value, nil
		}
	}

	// Try Redis cache (L2)
	data, err := dc.redis.Get(ctx, fullKey).Bytes()
	if err != nil {
		if err == redis.Nil {
			dc.recordMiss()
			return nil, ErrCacheMiss
		}
		return nil, err
	}

	// Deserialize value
	var value interface{}
	if err := json.Unmarshal(data, &value); err != nil {
		return nil, fmt.Errorf("failed to deserialize: %w", err)
	}

	// Store in local cache for next time
	if dc.config.EnableLocalCache {
		dc.localCache.Set(fullKey, value, dc.config.DefaultTTL)
	}

	dc.recordHit(false)
	return value, nil
}

// GetWithLoader retrieves from cache or loads if missing
func (dc *DistributedCache) GetWithLoader(ctx context.Context, key string, loader func() (interface{}, error), ttl time.Duration) (interface{}, error) {
	// Try to get from cache
	value, err := dc.Get(ctx, key)
	if err == nil {
		return value, nil
	}

	// Load from source
	value, err = loader()
	if err != nil {
		return nil, fmt.Errorf("loader failed: %w", err)
	}

	// Cache the loaded value
	if err := dc.Set(ctx, key, value, ttl); err != nil {
		dc.logger.Warn("Failed to cache loaded value",
			zap.String("key", key),
			zap.Error(err))
	}

	return value, nil
}

// Set stores a value in cache
func (dc *DistributedCache) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	fullKey := dc.buildKey(key)

	// Serialize value
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("failed to serialize: %w", err)
	}

	// Store in Redis
	if err := dc.redis.Set(ctx, fullKey, data, ttl).Err(); err != nil {
		return err
	}

	// Store in local cache
	if dc.config.EnableLocalCache {
		dc.localCache.Set(fullKey, value, ttl)
	}

	dc.recordSet()
	return nil
}

// SetNX sets a value only if it doesn't exist
func (dc *DistributedCache) SetNX(ctx context.Context, key string, value interface{}, ttl time.Duration) (bool, error) {
	fullKey := dc.buildKey(key)

	data, err := json.Marshal(value)
	if err != nil {
		return false, fmt.Errorf("failed to serialize: %w", err)
	}

	result, err := dc.redis.SetNX(ctx, fullKey, data, ttl).Result()
	if err != nil {
		return false, err
	}

	if result {
		// Store in local cache if successfully set
		if dc.config.EnableLocalCache {
			dc.localCache.Set(fullKey, value, ttl)
		}
		dc.recordSet()
	}

	return result, nil
}

// Delete removes a value from cache
func (dc *DistributedCache) Delete(ctx context.Context, key string) error {
	fullKey := dc.buildKey(key)

	// Delete from Redis
	if err := dc.redis.Del(ctx, fullKey).Err(); err != nil {
		return err
	}

	// Delete from local cache
	if dc.config.EnableLocalCache {
		dc.localCache.Delete(fullKey)
	}

	dc.recordDelete()
	return nil
}

// DeletePattern deletes all keys matching a pattern
func (dc *DistributedCache) DeletePattern(ctx context.Context, pattern string) error {
	fullPattern := dc.buildKey(pattern)

	// Use SCAN to find keys (safer than KEYS for production)
	iter := dc.redis.Scan(ctx, 0, fullPattern, 0).Iterator()
	var keys []string

	for iter.Next(ctx) {
		keys = append(keys, iter.Val())
	}

	if err := iter.Err(); err != nil {
		return err
	}

	if len(keys) > 0 {
		// Delete keys in batches
		batchSize := 100
		for i := 0; i < len(keys); i += batchSize {
			end := i + batchSize
			if end > len(keys) {
				end = len(keys)
			}

			if err := dc.redis.Del(ctx, keys[i:end]...).Err(); err != nil {
				return err
			}
		}

		// Clear local cache entries
		if dc.config.EnableLocalCache {
			for _, key := range keys {
				dc.localCache.Delete(key)
			}
		}
	}

	return nil
}

// Increment atomically increments a counter
func (dc *DistributedCache) Increment(ctx context.Context, key string, delta int64) (int64, error) {
	fullKey := dc.buildKey(key)
	return dc.redis.IncrBy(ctx, fullKey, delta).Result()
}

// Expire sets expiration on a key
func (dc *DistributedCache) Expire(ctx context.Context, key string, ttl time.Duration) error {
	fullKey := dc.buildKey(key)
	return dc.redis.Expire(ctx, fullKey, ttl).Err()
}

// TTL gets remaining TTL for a key
func (dc *DistributedCache) TTL(ctx context.Context, key string) (time.Duration, error) {
	fullKey := dc.buildKey(key)
	return dc.redis.TTL(ctx, fullKey).Result()
}

// Lock acquires a distributed lock
func (dc *DistributedCache) Lock(ctx context.Context, key string, ttl time.Duration) (*DistributedLock, error) {
	lockKey := dc.buildKey("lock:" + key)
	lockValue := fmt.Sprintf("%d", time.Now().UnixNano())

	// Try to acquire lock
	acquired, err := dc.redis.SetNX(ctx, lockKey, lockValue, ttl).Result()
	if err != nil {
		return nil, err
	}

	if !acquired {
		return nil, errors.New("lock already held")
	}

	return &DistributedLock{
		cache: dc,
		key:   lockKey,
		value: lockValue,
	}, nil
}

// buildKey builds the full cache key with namespace
func (dc *DistributedCache) buildKey(key string) string {
	if dc.config.Namespace != "" {
		return fmt.Sprintf("%s:%s", dc.config.Namespace, key)
	}
	return key
}

// Metrics recording

func (dc *DistributedCache) recordHit(local bool) {
	dc.metrics.mu.Lock()
	defer dc.metrics.mu.Unlock()
	dc.metrics.Hits++
	if local {
		dc.metrics.LocalHits++
	} else {
		dc.metrics.RemoteHits++
	}
}

func (dc *DistributedCache) recordMiss() {
	dc.metrics.mu.Lock()
	defer dc.metrics.mu.Unlock()
	dc.metrics.Misses++
}

func (dc *DistributedCache) recordSet() {
	dc.metrics.mu.Lock()
	defer dc.metrics.mu.Unlock()
	dc.metrics.Sets++
}

func (dc *DistributedCache) recordDelete() {
	dc.metrics.mu.Lock()
	defer dc.metrics.mu.Unlock()
	dc.metrics.Deletes++
}

func (dc *DistributedCache) reportMetrics() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		dc.metrics.mu.Lock()
		metrics := *dc.metrics
		dc.metrics.mu.Unlock()

		hitRate := float64(0)
		if total := metrics.Hits + metrics.Misses; total > 0 {
			hitRate = float64(metrics.Hits) / float64(total) * 100
		}

		dc.logger.Info("Cache metrics",
			zap.Int64("hits", metrics.Hits),
			zap.Int64("misses", metrics.Misses),
			zap.Float64("hit_rate", hitRate),
			zap.Int64("local_hits", metrics.LocalHits),
			zap.Int64("remote_hits", metrics.RemoteHits),
			zap.Int64("sets", metrics.Sets),
			zap.Int64("deletes", metrics.Deletes))
	}
}

// GetMetrics returns current cache metrics
func (dc *DistributedCache) GetMetrics() CacheMetrics {
	dc.metrics.mu.Lock()
	defer dc.metrics.mu.Unlock()
	return *dc.metrics
}

// LocalCache implementation

func NewLocalCache(maxSize int, metrics *CacheMetrics) *LocalCache {
	return &LocalCache{
		data:    make(map[string]*CacheItem),
		maxSize: maxSize,
		metrics: metrics,
	}
}

func (lc *LocalCache) Get(key string) (interface{}, bool) {
	lc.mu.RLock()
	defer lc.mu.RUnlock()

	item, exists := lc.data[key]
	if !exists {
		return nil, false
	}

	// Check expiration
	if time.Now().After(item.Expiration) {
		return nil, false
	}

	return item.Value, true
}

func (lc *LocalCache) Set(key string, value interface{}, ttl time.Duration) {
	lc.mu.Lock()
	defer lc.mu.Unlock()

	// Evict if at capacity
	if len(lc.data) >= lc.maxSize {
		lc.evictOldest()
	}

	lc.data[key] = &CacheItem{
		Value:      value,
		Expiration: time.Now().Add(ttl),
	}
}

func (lc *LocalCache) Delete(key string) {
	lc.mu.Lock()
	defer lc.mu.Unlock()
	delete(lc.data, key)
}

func (lc *LocalCache) evictOldest() {
	var oldestKey string
	var oldestTime time.Time

	for key, item := range lc.data {
		if oldestTime.IsZero() || item.Expiration.Before(oldestTime) {
			oldestKey = key
			oldestTime = item.Expiration
		}
	}

	if oldestKey != "" {
		delete(lc.data, oldestKey)
		if lc.metrics != nil {
			lc.metrics.Evictions++
		}
	}
}

// DistributedLock represents a distributed lock
type DistributedLock struct {
	cache *DistributedCache
	key   string
	value string
}

// Unlock releases the distributed lock
func (dl *DistributedLock) Unlock(ctx context.Context) error {
	// Use Lua script to ensure we only delete our lock
	script := `
		if redis.call("get", KEYS[1]) == ARGV[1] then
			return redis.call("del", KEYS[1])
		else
			return 0
		end
	`

	result, err := dl.cache.redis.Eval(ctx, script, []string{dl.key}, dl.value).Result()
	if err != nil {
		return err
	}

	if result == int64(0) {
		return errors.New("lock not held or already released")
	}

	return nil
}

// Extend extends the lock TTL
func (dl *DistributedLock) Extend(ctx context.Context, ttl time.Duration) error {
	// Use Lua script to ensure we only extend our lock
	script := `
		if redis.call("get", KEYS[1]) == ARGV[1] then
			return redis.call("expire", KEYS[1], ARGV[2])
		else
			return 0
		end
	`

	result, err := dl.cache.redis.Eval(ctx, script, []string{dl.key}, dl.value, int(ttl.Seconds())).Result()
	if err != nil {
		return err
	}

	if result == int64(0) {
		return errors.New("lock not held")
	}

	return nil
}

// CacheWarmer pre-loads cache with frequently accessed data
type CacheWarmer struct {
	cache   *DistributedCache
	loaders map[string]CacheLoader
	logger  *zap.Logger
}

// CacheLoader loads data for warming
type CacheLoader func(ctx context.Context) (map[string]interface{}, error)

// NewCacheWarmer creates a new cache warmer
func NewCacheWarmer(cache *DistributedCache, logger *zap.Logger) *CacheWarmer {
	return &CacheWarmer{
		cache:   cache,
		loaders: make(map[string]CacheLoader),
		logger:  logger,
	}
}

// RegisterLoader registers a cache loader
func (cw *CacheWarmer) RegisterLoader(name string, loader CacheLoader) {
	cw.loaders[name] = loader
}

// WarmCache pre-loads cache data
func (cw *CacheWarmer) WarmCache(ctx context.Context) error {
	for name, loader := range cw.loaders {
		cw.logger.Info("Warming cache",
			zap.String("loader", name))

		data, err := loader(ctx)
		if err != nil {
			cw.logger.Error("Cache warming failed",
				zap.String("loader", name),
				zap.Error(err))
			continue
		}

		// Load data into cache
		for key, value := range data {
			if err := cw.cache.Set(ctx, key, value, 1*time.Hour); err != nil {
				cw.logger.Error("Failed to warm cache entry",
					zap.String("key", key),
					zap.Error(err))
			}
		}

		cw.logger.Info("Cache warmed successfully",
			zap.String("loader", name),
			zap.Int("entries", len(data)))
	}

	return nil
}