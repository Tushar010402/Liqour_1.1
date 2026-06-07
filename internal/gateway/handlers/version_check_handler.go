package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/middleware"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// AppVersionConfig stores per-platform version + maintenance config
type AppVersionConfig struct {
	ID                 uint      `json:"id" gorm:"primaryKey;autoIncrement"`
	Platform           string    `json:"platform" gorm:"type:varchar(10);not null;uniqueIndex"` // ios, android
	MinVersion         string    `json:"min_version" gorm:"type:varchar(20);not null"`
	LatestVersion      string    `json:"latest_version" gorm:"type:varchar(20);not null"`
	StoreURL           string    `json:"store_url" gorm:"type:text;not null"`
	ReleaseNotes       string    `json:"release_notes" gorm:"type:text;default:''"`
	MaintenanceMode    bool      `json:"maintenance_mode" gorm:"default:false"`
	MaintenanceMessage string    `json:"maintenance_message" gorm:"type:text;default:''"`
	UpdatedAt          time.Time `json:"updated_at" gorm:"autoUpdateTime"`
}

func (AppVersionConfig) TableName() string { return "app_version_config" }

// VersionCheckHandler handles app version checks
type VersionCheckHandler struct {
	db     *gorm.DB
	cache  *cache.Cache
	logger *zap.Logger
}

// NewVersionCheckHandler creates a new version check handler
func NewVersionCheckHandler(db *gorm.DB, cache *cache.Cache, logger *zap.Logger) *VersionCheckHandler {
	return &VersionCheckHandler{db: db, cache: cache, logger: logger}
}

// VersionCheck handles GET /api/app/version-check
func (h *VersionCheckHandler) VersionCheck(c *gin.Context) {
	platform := c.DefaultQuery("platform", "android")
	currentVersion := c.DefaultQuery("current_version", "1.0.0")

	if platform != "ios" && platform != "android" && platform != "web" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "platform must be 'ios', 'android', or 'web'"})
		return
	}

	// Web platform — no version check needed, always up to date
	if platform == "web" {
		c.JSON(http.StatusOK, gin.H{
			"update_available":    false,
			"force_update":       false,
			"latest_version":     currentVersion,
			"min_required_version": "1.0.0",
			"maintenance_mode":   false,
		})
		return
	}

	// Try Redis cache first
	cacheKey := fmt.Sprintf("app:version_config:%s", platform)
	var config AppVersionConfig
	if err := h.cache.Get(c.Request.Context(), cacheKey, &config); err != nil {
		// Cache miss — read from DB
		if err := h.db.Where("platform = ?", platform).First(&config).Error; err != nil {
			// No config found — return safe defaults
			c.JSON(http.StatusOK, gin.H{
				"min_version":         "1.0.0",
				"latest_version":      "1.0.0",
				"force_update":        false,
				"update_available":    false,
				"release_notes":       "",
				"store_url":           "",
				"maintenance_mode":    false,
				"maintenance_message": "",
			})
			return
		}

		// Cache for 10 minutes
		h.cache.Set(c.Request.Context(), cacheKey, config, 10*time.Minute)

		// Seed version headers cache
		middleware.SeedVersionToRedis(h.cache, platform, config.MinVersion, config.LatestVersion)
	}

	forceUpdate := compareVersions(currentVersion, config.MinVersion) < 0
	updateAvailable := compareVersions(currentVersion, config.LatestVersion) < 0

	c.JSON(http.StatusOK, gin.H{
		"min_version":         config.MinVersion,
		"latest_version":      config.LatestVersion,
		"force_update":        forceUpdate,
		"update_available":    updateAvailable,
		"release_notes":       config.ReleaseNotes,
		"store_url":           config.StoreURL,
		"maintenance_mode":    config.MaintenanceMode,
		"maintenance_message": config.MaintenanceMessage,
	})
}

// UpdateVersionConfig handles PUT /api/app/version-config (admin only)
func (h *VersionCheckHandler) UpdateVersionConfig(c *gin.Context) {
	var req struct {
		Platform           string  `json:"platform" binding:"required"`
		MinVersion         *string `json:"min_version"`
		LatestVersion      *string `json:"latest_version"`
		StoreURL           *string `json:"store_url"`
		ReleaseNotes       *string `json:"release_notes"`
		MaintenanceMode    *bool   `json:"maintenance_mode"`
		MaintenanceMessage *string `json:"maintenance_message"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid request: %v", err)})
		return
	}

	if req.Platform != "ios" && req.Platform != "android" && req.Platform != "web" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "platform must be 'ios', 'android', or 'web'"})
		return
	}

	var config AppVersionConfig
	if err := h.db.Where("platform = ?", req.Platform).First(&config).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no config found for platform"})
		return
	}

	// Apply partial updates
	updates := map[string]interface{}{}
	if req.MinVersion != nil {
		updates["min_version"] = *req.MinVersion
	}
	if req.LatestVersion != nil {
		updates["latest_version"] = *req.LatestVersion
	}
	if req.StoreURL != nil {
		updates["store_url"] = *req.StoreURL
	}
	if req.ReleaseNotes != nil {
		updates["release_notes"] = *req.ReleaseNotes
	}
	if req.MaintenanceMode != nil {
		updates["maintenance_mode"] = *req.MaintenanceMode
	}
	if req.MaintenanceMessage != nil {
		updates["maintenance_message"] = *req.MaintenanceMessage
	}

	if err := h.db.Model(&config).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update config"})
		return
	}

	// Invalidate caches
	h.cache.Delete(c.Request.Context(), fmt.Sprintf("app:version_config:%s", req.Platform))
	middleware.InvalidateVersionCache()

	// Re-seed headers cache with new values
	h.db.Where("platform = ?", req.Platform).First(&config)
	middleware.SeedVersionToRedis(h.cache, req.Platform, config.MinVersion, config.LatestVersion)

	h.logger.Info("Version config updated",
		zap.String("platform", req.Platform),
		zap.Any("updates", updates))

	c.JSON(http.StatusOK, gin.H{"success": true, "config": config})
}

// GetVersionConfig handles GET /api/app/version-config (admin only)
func (h *VersionCheckHandler) GetVersionConfig(c *gin.Context) {
	var configs []AppVersionConfig
	if err := h.db.Find(&configs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch configs"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"configs": configs})
}

// compareVersions compares two semantic version strings
// Returns -1 if a < b, 0 if a == b, 1 if a > b
func compareVersions(a, b string) int {
	aParts := parseVersion(a)
	bParts := parseVersion(b)

	for i := 0; i < 3; i++ {
		if aParts[i] < bParts[i] {
			return -1
		}
		if aParts[i] > bParts[i] {
			return 1
		}
	}
	return 0
}

// parseVersion splits "1.2.3" into [1, 2, 3]
func parseVersion(v string) [3]int {
	var parts [3]int
	segments := strings.Split(strings.TrimPrefix(v, "v"), ".")
	for i := 0; i < 3 && i < len(segments); i++ {
		parts[i], _ = strconv.Atoi(segments[i])
	}
	return parts
}
