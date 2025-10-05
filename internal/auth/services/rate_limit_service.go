package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// RateLimitService handles rate limiting operations
type RateLimitService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewRateLimitService creates a new rate limit service
func NewRateLimitService(db *database.DB, cache *cache.Cache) *RateLimitService {
	return &RateLimitService{
		db:    db,
		cache: cache,
	}
}

// GetRateLimits retrieves all rate limits (global and tenant-specific)
func (s *RateLimitService) GetRateLimits(tenantID *uuid.UUID, isGlobal bool) ([]models.RateLimit, error) {
	var rateLimits []models.RateLimit

	query := s.db.Where("is_active = ?", true)

	if isGlobal {
		query = query.Where("is_global = ?", true)
	} else if tenantID != nil {
		// Get both global limits and tenant-specific limits
		query = query.Where("(is_global = ? OR tenant_id = ?)", true, *tenantID)
	}

	if err := query.Order("priority DESC, created_at ASC").Find(&rateLimits).Error; err != nil {
		return nil, fmt.Errorf("failed to retrieve rate limits: %w", err)
	}

	return rateLimits, nil
}

// GetRateLimitByName retrieves a specific rate limit by name
func (s *RateLimitService) GetRateLimitByName(name string, tenantID *uuid.UUID) (*models.RateLimit, error) {
	var rateLimit models.RateLimit

	query := s.db.Where("name = ? AND is_active = ?", name, true)

	if tenantID != nil {
		// Check tenant-specific first, then global
		query = query.Where("(tenant_id = ? OR is_global = ?)", *tenantID, true)
	} else {
		// Only global for SaaS admin or system-wide checks
		query = query.Where("is_global = ?", true)
	}

	if err := query.Order("priority DESC").First(&rateLimit).Error; err != nil {
		return nil, fmt.Errorf("rate limit not found: %w", err)
	}

	return &rateLimit, nil
}

// CreateRateLimit creates a new rate limit configuration
func (s *RateLimitService) CreateRateLimit(rateLimit *models.RateLimit) error {
	if err := s.db.Create(rateLimit).Error; err != nil {
		return fmt.Errorf("failed to create rate limit: %w", err)
	}

	// Invalidate cache for this rate limit
	s.invalidateRateLimitCache(rateLimit.Name)

	return nil
}

// UpdateRateLimit updates an existing rate limit configuration
func (s *RateLimitService) UpdateRateLimit(rateLimitID uuid.UUID, updates *models.RateLimit) error {
	var rateLimit models.RateLimit
	if err := s.db.Where("id = ?", rateLimitID).First(&rateLimit).Error; err != nil {
		return fmt.Errorf("rate limit not found: %w", err)
	}

	// Update fields
	if updates.Description != "" {
		rateLimit.Description = updates.Description
	}
	if updates.MaxAttempts > 0 {
		rateLimit.MaxAttempts = updates.MaxAttempts
	}
	if updates.TimeWindow > 0 {
		rateLimit.TimeWindow = updates.TimeWindow
	}
	if updates.BlockDuration > 0 {
		rateLimit.BlockDuration = updates.BlockDuration
	}
	rateLimit.IsActive = updates.IsActive
	rateLimit.Priority = updates.Priority
	if updates.Settings != "" {
		rateLimit.Settings = updates.Settings
	}
	if updates.UpdatedByID != nil {
		rateLimit.UpdatedByID = updates.UpdatedByID
	}

	if err := s.db.Save(&rateLimit).Error; err != nil {
		return fmt.Errorf("failed to update rate limit: %w", err)
	}

	// Invalidate cache
	s.invalidateRateLimitCache(rateLimit.Name)

	return nil
}

// DeleteRateLimit soft deletes a rate limit configuration
func (s *RateLimitService) DeleteRateLimit(rateLimitID uuid.UUID) error {
	var rateLimit models.RateLimit
	if err := s.db.Where("id = ?", rateLimitID).First(&rateLimit).Error; err != nil {
		return fmt.Errorf("rate limit not found: %w", err)
	}

	if err := s.db.Delete(&rateLimit).Error; err != nil {
		return fmt.Errorf("failed to delete rate limit: %w", err)
	}

	// Invalidate cache
	s.invalidateRateLimitCache(rateLimit.Name)

	return nil
}

// CheckRateLimit checks if a request should be rate limited
func (s *RateLimitService) CheckRateLimit(rateLimitName string, identifier string, tenantID *uuid.UUID, userID *uuid.UUID, requestIP string, userAgent string) (bool, error) {
	// Get rate limit configuration
	rateLimit, err := s.getRateLimitConfig(rateLimitName, tenantID)
	if err != nil {
		// If no rate limit is configured, allow the request
		return false, nil
	}

	// Check current attempt count and window
	now := time.Now()
	windowStart := now.Truncate(rateLimit.TimeWindow)
	windowEnd := windowStart.Add(rateLimit.TimeWindow)

	// Get current log entry from database
	var logEntry models.RateLimitLog
	err = s.db.Where("rate_limit_id = ? AND identifier = ? AND window_start = ?",
		rateLimit.ID, identifier, windowStart).First(&logEntry).Error

	if err != nil {
		// No existing log entry, create new one
		logEntry = models.RateLimitLog{
			RateLimitID:  rateLimit.ID,
			Identifier:   identifier,
			RequestIP:    requestIP,
			UserAgent:    userAgent,
			TenantID:     tenantID,
			UserID:       userID,
			AttemptCount: 1,
			IsBlocked:    false,
			WindowStart:  windowStart,
			WindowEnd:    windowEnd,
		}

		if err := s.db.Create(&logEntry).Error; err != nil {
			return false, fmt.Errorf("failed to create rate limit log: %w", err)
		}

		// First request in window, not blocked
		return false, nil
	}

	// Check if currently blocked
	if logEntry.IsBlocked && logEntry.BlockedUntil != nil && now.Before(*logEntry.BlockedUntil) {
		return true, nil
	}

	// Increment attempt count
	logEntry.AttemptCount++
	logEntry.RequestIP = requestIP
	logEntry.UserAgent = userAgent

	// Check if limit exceeded
	if logEntry.AttemptCount > rateLimit.MaxAttempts {
		// Block the identifier
		blockedUntil := now.Add(rateLimit.BlockDuration)
		logEntry.IsBlocked = true
		logEntry.BlockedUntil = &blockedUntil

		if err := s.db.Save(&logEntry).Error; err != nil {
			return false, fmt.Errorf("failed to update rate limit log: %w", err)
		}

		return true, nil
	}

	// Update attempt count
	if err := s.db.Save(&logEntry).Error; err != nil {
		return false, fmt.Errorf("failed to update rate limit log: %w", err)
	}

	return false, nil
}

// GetRateLimitStats returns statistics for rate limiting
func (s *RateLimitService) GetRateLimitStats(tenantID *uuid.UUID, hours int) (map[string]interface{}, error) {
	if hours == 0 {
		hours = 24 // Default to last 24 hours
	}

	since := time.Now().Add(-time.Duration(hours) * time.Hour)

	var stats struct {
		TotalRequests   int64 `json:"total_requests"`
		BlockedRequests int64 `json:"blocked_requests"`
		UniqueIPs       int64 `json:"unique_ips"`
	}

	query := s.db.Model(&models.RateLimitLog{}).Where("created_at > ?", since)
	if tenantID != nil {
		query = query.Where("tenant_id = ?", *tenantID)
	}

	// Total requests
	if err := query.Count(&stats.TotalRequests).Error; err != nil {
		return nil, fmt.Errorf("failed to get total requests: %w", err)
	}

	// Blocked requests
	if err := query.Where("is_blocked = ?", true).Count(&stats.BlockedRequests).Error; err != nil {
		return nil, fmt.Errorf("failed to get blocked requests: %w", err)
	}

	// Unique IPs
	if err := s.db.Model(&models.RateLimitLog{}).
		Where("created_at > ?", since).
		Distinct("request_ip").
		Count(&stats.UniqueIPs).Error; err != nil {
		return nil, fmt.Errorf("failed to get unique IPs: %w", err)
	}

	// Rate limit breakdown
	var breakdown []struct {
		RateLimitName string `json:"rate_limit_name"`
		Requests      int64  `json:"requests"`
		Blocked       int64  `json:"blocked"`
	}

	err := s.db.Raw(`
		SELECT rl.name as rate_limit_name,
		       COUNT(rll.id) as requests,
		       COUNT(CASE WHEN rll.is_blocked THEN 1 END) as blocked
		FROM rate_limit_logs rll
		JOIN rate_limits rl ON rl.id = rll.rate_limit_id
		WHERE rll.created_at > ?
		GROUP BY rl.name
		ORDER BY requests DESC
	`, since).Scan(&breakdown).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get rate limit breakdown: %w", err)
	}

	result := map[string]interface{}{
		"total_requests":   stats.TotalRequests,
		"blocked_requests": stats.BlockedRequests,
		"unique_ips":       stats.UniqueIPs,
		"block_rate":       float64(stats.BlockedRequests) / float64(stats.TotalRequests) * 100,
		"breakdown":        breakdown,
		"period_hours":     hours,
	}

	return result, nil
}

// Helper methods

func (s *RateLimitService) getRateLimitConfig(name string, tenantID *uuid.UUID) (*models.RateLimit, error) {
	// Try cache first
	ctx := context.Background()
	cacheKey := fmt.Sprintf("rate_limit_config:%s", name)
	if tenantID != nil {
		cacheKey = fmt.Sprintf("rate_limit_config:%s:%s", name, tenantID.String())
	}

	var cached string
	err := s.cache.Get(ctx, cacheKey, &cached)
	if err == nil && cached != "" {
		// Cache hit - get from database (simplified approach)
		return s.GetRateLimitByName(name, tenantID)
	}

	// Get from database
	rateLimit, err := s.GetRateLimitByName(name, tenantID)
	if err != nil {
		return nil, err
	}

	// Cache for 5 minutes
	s.cache.Set(ctx, cacheKey, "exists", 5*time.Minute)

	return rateLimit, nil
}

func (s *RateLimitService) generateCacheKey(rateLimitName, identifier string, tenantID *uuid.UUID) string {
	key := fmt.Sprintf("rate_limit:%s:%s", rateLimitName, identifier)
	if tenantID != nil {
		key = fmt.Sprintf("rate_limit:%s:%s:%s", rateLimitName, identifier, tenantID.String())
	}
	return key
}

func (s *RateLimitService) invalidateRateLimitCache(name string) {
	// Invalidate cache entries for this rate limit
	// For simplicity, we'll just delete the specific keys we know about
	ctx := context.Background()

	// Delete global config
	globalKey := fmt.Sprintf("rate_limit_config:%s", name)
	s.cache.Delete(ctx, globalKey)

	// Note: In production, you might want to implement pattern-based deletion
	// or use a different caching strategy
}

// ResetRateLimit resets the rate limit for a specific identifier
func (s *RateLimitService) ResetRateLimit(rateLimitName string, identifier string, tenantID *uuid.UUID) error {
	// Delete all log entries for this identifier and rate limit
	query := s.db.Model(&models.RateLimitLog{}).
		Where("identifier = ?", identifier)

	if rateLimitName != "" {
		var rateLimit models.RateLimit
		if err := s.db.Where("name = ?", rateLimitName).First(&rateLimit).Error; err != nil {
			return fmt.Errorf("rate limit not found: %w", err)
		}
		query = query.Where("rate_limit_id = ?", rateLimit.ID)
	}

	if tenantID != nil {
		query = query.Where("tenant_id = ?", *tenantID)
	}

	if err := query.Delete(&models.RateLimitLog{}).Error; err != nil {
		return fmt.Errorf("failed to reset rate limit: %w", err)
	}

	// Clear cache
	ctx := context.Background()
	cacheKey := s.generateCacheKey(rateLimitName, identifier, tenantID)
	s.cache.Delete(ctx, cacheKey)

	return nil
}
