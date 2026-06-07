package caching

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"sort"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/models"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// CacheStrategy defines how data should be cached
type CacheStrategy interface {
	GetKey(params ...interface{}) string
	GetTTL() time.Duration
	ShouldCache(data interface{}) bool
	InvalidatePattern() string
}

// ProductCacheStrategy for product data
type ProductCacheStrategy struct {
	TenantID string
}

func (s *ProductCacheStrategy) GetKey(params ...interface{}) string {
	if len(params) > 0 {
		return fmt.Sprintf("product:%s:%v", s.TenantID, params[0])
	}
	return fmt.Sprintf("product:%s:all", s.TenantID)
}

func (s *ProductCacheStrategy) GetTTL() time.Duration {
	return 5 * time.Minute
}

func (s *ProductCacheStrategy) ShouldCache(data interface{}) bool {
	// Don't cache empty results
	if products, ok := data.([]*models.Product); ok {
		return len(products) > 0
	}
	return data != nil
}

func (s *ProductCacheStrategy) InvalidatePattern() string {
	return fmt.Sprintf("product:%s:*", s.TenantID)
}

// InventoryCacheStrategy for inventory data
type InventoryCacheStrategy struct {
	ShopID string
}

func (s *InventoryCacheStrategy) GetKey(params ...interface{}) string {
	if len(params) > 0 {
		return fmt.Sprintf("inventory:%s:product:%v", s.ShopID, params[0])
	}
	return fmt.Sprintf("inventory:%s:all", s.ShopID)
}

func (s *InventoryCacheStrategy) GetTTL() time.Duration {
	// Shorter TTL for inventory due to frequent updates
	return 1 * time.Minute
}

func (s *InventoryCacheStrategy) ShouldCache(data interface{}) bool {
	// Always cache inventory data to reduce DB load
	return true
}

func (s *InventoryCacheStrategy) InvalidatePattern() string {
	return fmt.Sprintf("inventory:%s:*", s.ShopID)
}

// UserCacheStrategy for user data
type UserCacheStrategy struct{}

func (s *UserCacheStrategy) GetKey(params ...interface{}) string {
	if len(params) > 0 {
		return fmt.Sprintf("user:%v", params[0])
	}
	return "user:unknown"
}

func (s *UserCacheStrategy) GetTTL() time.Duration {
	// Longer TTL for user data as it changes less frequently
	return 30 * time.Minute
}

func (s *UserCacheStrategy) ShouldCache(data interface{}) bool {
	return data != nil
}

func (s *UserCacheStrategy) InvalidatePattern() string {
	return "user:*"
}

// SalesAnalyticsCacheStrategy for analytics data
type SalesAnalyticsCacheStrategy struct {
	ShopID    string
	DateRange string
}

func (s *SalesAnalyticsCacheStrategy) GetKey(params ...interface{}) string {
	return fmt.Sprintf("analytics:sales:%s:%s", s.ShopID, s.DateRange)
}

func (s *SalesAnalyticsCacheStrategy) GetTTL() time.Duration {
	// Cache analytics for longer as they're expensive to compute
	return 15 * time.Minute
}

func (s *SalesAnalyticsCacheStrategy) ShouldCache(data interface{}) bool {
	return data != nil
}

func (s *SalesAnalyticsCacheStrategy) InvalidatePattern() string {
	return fmt.Sprintf("analytics:sales:%s:*", s.ShopID)
}

// QueryCacheStrategy for complex queries
type QueryCacheStrategy struct {
	QueryType string
	TenantID  string
}

func (s *QueryCacheStrategy) GetKey(params ...interface{}) string {
	// Create deterministic key from query parameters
	hash := fnv.New64a()
	encoder := json.NewEncoder(hash)
	encoder.Encode(params)
	return fmt.Sprintf("query:%s:%s:%x", s.QueryType, s.TenantID, hash.Sum64())
}

func (s *QueryCacheStrategy) GetTTL() time.Duration {
	// Different TTL based on query type
	switch s.QueryType {
	case "report":
		return 30 * time.Minute
	case "search":
		return 5 * time.Minute
	case "aggregate":
		return 10 * time.Minute
	default:
		return 2 * time.Minute
	}
}

func (s *QueryCacheStrategy) ShouldCache(data interface{}) bool {
	// Cache successful query results
	return data != nil
}

func (s *QueryCacheStrategy) InvalidatePattern() string {
	return fmt.Sprintf("query:%s:%s:*", s.QueryType, s.TenantID)
}

// CacheManager manages different cache strategies
type CacheManager struct {
	cache      *DistributedCache
	strategies map[string]CacheStrategy
	db         *gorm.DB
	logger     *zap.Logger
}

// NewCacheManager creates a new cache manager
func NewCacheManager(cache *DistributedCache, db *gorm.DB, logger *zap.Logger) *CacheManager {
	return &CacheManager{
		cache:      cache,
		strategies: make(map[string]CacheStrategy),
		db:         db,
		logger:     logger,
	}
}

// RegisterStrategy registers a cache strategy
func (cm *CacheManager) RegisterStrategy(name string, strategy CacheStrategy) {
	cm.strategies[name] = strategy
}

// GetWithStrategy gets data using a specific strategy
func (cm *CacheManager) GetWithStrategy(ctx context.Context, strategyName string, loader func() (interface{}, error), params ...interface{}) (interface{}, error) {
	strategy, exists := cm.strategies[strategyName]
	if !exists {
		// No strategy, just load directly
		return loader()
	}

	key := strategy.GetKey(params...)

	// Try cache first
	cached, err := cm.cache.Get(ctx, key)
	if err == nil {
		cm.logger.Debug("Cache hit",
			zap.String("strategy", strategyName),
			zap.String("key", key))
		return cached, nil
	}

	// Load from source
	data, err := loader()
	if err != nil {
		return nil, err
	}

	// Cache if strategy allows
	if strategy.ShouldCache(data) {
		if err := cm.cache.Set(ctx, key, data, strategy.GetTTL()); err != nil {
			cm.logger.Warn("Failed to cache data",
				zap.String("strategy", strategyName),
				zap.String("key", key),
				zap.Error(err))
		}
	}

	return data, nil
}

// InvalidateStrategy invalidates all cache entries for a strategy
func (cm *CacheManager) InvalidateStrategy(ctx context.Context, strategyName string) error {
	strategy, exists := cm.strategies[strategyName]
	if !exists {
		return fmt.Errorf("strategy not found: %s", strategyName)
	}

	pattern := strategy.InvalidatePattern()
	return cm.cache.DeletePattern(ctx, pattern)
}

// CacheAside implements the cache-aside pattern
func (cm *CacheManager) CacheAside(ctx context.Context, key string, loader func() (interface{}, error), ttl time.Duration) (interface{}, error) {
	// Try to get from cache
	cached, err := cm.cache.Get(ctx, key)
	if err == nil {
		return cached, nil
	}

	// Acquire lock to prevent cache stampede
	lock, err := cm.cache.Lock(ctx, key+":lock", 5*time.Second)
	if err != nil {
		// Someone else is loading, wait and retry
		time.Sleep(100 * time.Millisecond)
		cached, err = cm.cache.Get(ctx, key)
		if err == nil {
			return cached, nil
		}
	} else {
		defer lock.Unlock(ctx)
	}

	// Load from source
	data, err := loader()
	if err != nil {
		return nil, err
	}

	// Cache the result
	if err := cm.cache.Set(ctx, key, data, ttl); err != nil {
		cm.logger.Warn("Failed to cache data",
			zap.String("key", key),
			zap.Error(err))
	}

	return data, nil
}

// WriteThrough implements the write-through pattern
func (cm *CacheManager) WriteThrough(ctx context.Context, key string, data interface{}, writer func(interface{}) error, ttl time.Duration) error {
	// Write to database first
	if err := writer(data); err != nil {
		return err
	}

	// Then update cache
	if err := cm.cache.Set(ctx, key, data, ttl); err != nil {
		cm.logger.Warn("Failed to update cache after write",
			zap.String("key", key),
			zap.Error(err))
		// Don't fail the operation if cache update fails
	}

	return nil
}

// WriteBehind implements the write-behind pattern
func (cm *CacheManager) WriteBehind(ctx context.Context, key string, data interface{}, ttl time.Duration) error {
	// Update cache immediately
	if err := cm.cache.Set(ctx, key, data, ttl); err != nil {
		return err
	}

	// Queue database write asynchronously
	go func() {
		// In production, use a proper queue
		time.Sleep(100 * time.Millisecond)

		// Write to database
		if err := cm.persistData(key, data); err != nil {
			cm.logger.Error("Failed to persist data in write-behind",
				zap.String("key", key),
				zap.Error(err))
		}
	}()

	return nil
}

func (cm *CacheManager) persistData(key string, data interface{}) error {
	// Implementation depends on data type
	// This is a placeholder
	return nil
}

// RefreshAhead implements the refresh-ahead pattern
func (cm *CacheManager) RefreshAhead(ctx context.Context, key string, loader func() (interface{}, error), ttl time.Duration, refreshThreshold float64) (interface{}, error) {
	// Get from cache with TTL check
	cached, err := cm.cache.Get(ctx, key)
	if err == nil {
		// Check if we should refresh proactively
		remaining, _ := cm.cache.TTL(ctx, key)
		if float64(remaining) < float64(ttl)*refreshThreshold {
			// Refresh asynchronously
			go func() {
				ctx := context.Background()
				if data, err := loader(); err == nil {
					cm.cache.Set(ctx, key, data, ttl)
				}
			}()
		}
		return cached, nil
	}

	// Not in cache, load synchronously
	data, err := loader()
	if err != nil {
		return nil, err
	}

	cm.cache.Set(ctx, key, data, ttl)
	return data, nil
}

// TaggedCache implements tag-based cache invalidation
type TaggedCache struct {
	cache  *DistributedCache
	logger *zap.Logger
}

// NewTaggedCache creates a new tagged cache
func NewTaggedCache(cache *DistributedCache, logger *zap.Logger) *TaggedCache {
	return &TaggedCache{
		cache:  cache,
		logger: logger,
	}
}

// SetWithTags caches data with associated tags
func (tc *TaggedCache) SetWithTags(ctx context.Context, key string, value interface{}, tags []string, ttl time.Duration) error {
	// Store the value
	if err := tc.cache.Set(ctx, key, value, ttl); err != nil {
		return err
	}

	// Store key-tag associations
	for _, tag := range tags {
		tagKey := fmt.Sprintf("tag:%s", tag)

		// Get existing keys for this tag
		existingData, _ := tc.cache.Get(ctx, tagKey)
		keys := []string{}
		if existingData != nil {
			if existing, ok := existingData.([]string); ok {
				keys = existing
			}
		}

		// Add new key
		keys = append(keys, key)

		// Store updated list
		if err := tc.cache.Set(ctx, tagKey, keys, 24*time.Hour); err != nil {
			tc.logger.Warn("Failed to update tag",
				zap.String("tag", tag),
				zap.Error(err))
		}
	}

	return nil
}

// InvalidateByTag invalidates all cache entries with a specific tag
func (tc *TaggedCache) InvalidateByTag(ctx context.Context, tag string) error {
	tagKey := fmt.Sprintf("tag:%s", tag)

	// Get all keys with this tag
	data, err := tc.cache.Get(ctx, tagKey)
	if err != nil {
		return nil // Tag doesn't exist
	}

	keys, ok := data.([]string)
	if !ok {
		return nil
	}

	// Delete all associated keys
	for _, key := range keys {
		if err := tc.cache.Delete(ctx, key); err != nil {
			tc.logger.Warn("Failed to delete tagged key",
				zap.String("key", key),
				zap.Error(err))
		}
	}

	// Delete the tag itself
	return tc.cache.Delete(ctx, tagKey)
}

// MultiLevelCache implements a multi-level cache hierarchy
type MultiLevelCache struct {
	levels []CacheLevel
	logger *zap.Logger
}

// CacheLevel represents a level in the cache hierarchy
type CacheLevel struct {
	Name  string
	Cache *DistributedCache
	TTL   time.Duration
}

// NewMultiLevelCache creates a multi-level cache
func NewMultiLevelCache(logger *zap.Logger) *MultiLevelCache {
	return &MultiLevelCache{
		levels: make([]CacheLevel, 0),
		logger: logger,
	}
}

// AddLevel adds a cache level
func (mlc *MultiLevelCache) AddLevel(level CacheLevel) {
	mlc.levels = append(mlc.levels, level)
}

// Get retrieves from the cache hierarchy
func (mlc *MultiLevelCache) Get(ctx context.Context, key string) (interface{}, error) {
	for i, level := range mlc.levels {
		data, err := level.Cache.Get(ctx, key)
		if err == nil {
			// Found in this level, populate higher levels
			for j := 0; j < i; j++ {
				mlc.levels[j].Cache.Set(ctx, key, data, mlc.levels[j].TTL)
			}
			return data, nil
		}
	}

	return nil, ErrCacheMiss
}

// Set stores in all cache levels
func (mlc *MultiLevelCache) Set(ctx context.Context, key string, value interface{}) error {
	for _, level := range mlc.levels {
		if err := level.Cache.Set(ctx, key, value, level.TTL); err != nil {
			mlc.logger.Warn("Failed to set in cache level",
				zap.String("level", level.Name),
				zap.Error(err))
		}
	}
	return nil
}

// ConsistentHashCache implements consistent hashing for cache distribution
type ConsistentHashCache struct {
	nodes  []string
	ring   map[uint32]string
	logger *zap.Logger
}

// NewConsistentHashCache creates a consistent hash cache
func NewConsistentHashCache(nodes []string, logger *zap.Logger) *ConsistentHashCache {
	chc := &ConsistentHashCache{
		nodes:  nodes,
		ring:   make(map[uint32]string),
		logger: logger,
	}

	// Build hash ring
	for _, node := range nodes {
		for i := 0; i < 150; i++ { // 150 virtual nodes per physical node
			hash := chc.hash(fmt.Sprintf("%s:%d", node, i))
			chc.ring[hash] = node
		}
	}

	return chc
}

func (chc *ConsistentHashCache) hash(key string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(key))
	return h.Sum32()
}

// GetNode returns the cache node for a given key
func (chc *ConsistentHashCache) GetNode(key string) string {
	if len(chc.ring) == 0 {
		return ""
	}

	hash := chc.hash(key)

	// Find the first node with hash >= key hash
	keys := make([]uint32, 0, len(chc.ring))
	for k := range chc.ring {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })

	for _, k := range keys {
		if k >= hash {
			return chc.ring[k]
		}
	}

	// Wrap around to first node
	return chc.ring[keys[0]]
}