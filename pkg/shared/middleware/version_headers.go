package middleware

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
)

// VersionConfig holds cached version info for response headers
type VersionConfig struct {
	MinVersion    string
	LatestVersion string
}

var (
	versionCache     *VersionConfig
	versionCacheMu   sync.RWMutex
	versionCacheTime time.Time
	versionCacheTTL  = 5 * time.Minute
)

// VersionHeadersMiddleware adds X-Min-App-Version and X-Latest-App-Version to all responses
func VersionHeadersMiddleware(redisCache *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {
		cfg := getCachedVersionConfig(redisCache)
		if cfg != nil {
			c.Header("X-Min-App-Version", cfg.MinVersion)
			c.Header("X-Latest-App-Version", cfg.LatestVersion)
		}
		c.Next()
	}
}

func getCachedVersionConfig(redisCache *cache.Cache) *VersionConfig {
	versionCacheMu.RLock()
	if versionCache != nil && time.Since(versionCacheTime) < versionCacheTTL {
		cfg := versionCache
		versionCacheMu.RUnlock()
		return cfg
	}
	versionCacheMu.RUnlock()

	// Fetch from Redis
	versionCacheMu.Lock()
	defer versionCacheMu.Unlock()

	// Double-check after acquiring write lock
	if versionCache != nil && time.Since(versionCacheTime) < versionCacheTTL {
		return versionCache
	}

	ctx := context.Background()
	var cfg VersionConfig
	if err := redisCache.Get(ctx, "app:version:android", &cfg); err == nil {
		versionCache = &cfg
		versionCacheTime = time.Now()
		return versionCache
	}

	// Fallback: try to read individual keys
	client := redisCache.Client()
	minV, err1 := client.Get(ctx, "app:min_version").Result()
	latestV, err2 := client.Get(ctx, "app:latest_version").Result()
	if err1 == nil && err2 == nil {
		versionCache = &VersionConfig{MinVersion: minV, LatestVersion: latestV}
		versionCacheTime = time.Now()
		return versionCache
	}

	return nil
}

// InvalidateVersionCache forces the next request to refetch version config
func InvalidateVersionCache() {
	versionCacheMu.Lock()
	versionCache = nil
	versionCacheMu.Unlock()
}

// SeedVersionToRedis stores version config in Redis (called after DB read)
func SeedVersionToRedis(redisCache *cache.Cache, platform, minVersion, latestVersion string) {
	ctx := context.Background()
	cfg := VersionConfig{MinVersion: minVersion, LatestVersion: latestVersion}
	redisCache.Set(ctx, fmt.Sprintf("app:version:%s", platform), cfg, 1*time.Hour)

	// Also set simple keys for backward compat
	client := redisCache.Client()
	client.Set(ctx, "app:min_version", minVersion, 1*time.Hour)
	client.Set(ctx, "app:latest_version", latestVersion, 1*time.Hour)

	InvalidateVersionCache()
}
