package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"gorm.io/gorm"
)

type UsageTrackingService struct {
	db    *gorm.DB
	cache *cache.Cache
	cfg   *config.Config
}

type UsageMetrics struct {
	TenantID        uuid.UUID `json:"tenant_id"`
	ResourceType    string    `json:"resource_type"`
	CurrentUsage    int       `json:"current_usage"`
	Limit           int       `json:"limit"`
	UsagePercentage float64   `json:"usage_percentage"`
	LastUpdated     time.Time `json:"last_updated"`
	PeriodStart     time.Time `json:"period_start"`
	PeriodEnd       time.Time `json:"period_end"`
}

type UsageEvent struct {
	TenantID     uuid.UUID `json:"tenant_id"`
	ResourceType string    `json:"resource_type"`
	Action       string    `json:"action"` // CREATE, UPDATE, DELETE
	Quantity     int       `json:"quantity"`
	Metadata     string    `json:"metadata,omitempty"`
	Timestamp    time.Time `json:"timestamp"`
}

type UsageAlert struct {
	TenantID     uuid.UUID `json:"tenant_id"`
	ResourceType string    `json:"resource_type"`
	AlertType    string    `json:"alert_type"` // WARNING, CRITICAL, LIMIT_EXCEEDED
	CurrentUsage int       `json:"current_usage"`
	Limit        int       `json:"limit"`
	Percentage   float64   `json:"percentage"`
	Message      string    `json:"message"`
	Timestamp    time.Time `json:"timestamp"`
}

type BillingPeriodUsage struct {
	TenantID       uuid.UUID          `json:"tenant_id"`
	BillingPeriod  string             `json:"billing_period"`
	ResourceUsage  map[string]int     `json:"resource_usage"`
	OverageCharges map[string]float64 `json:"overage_charges"`
	TotalOverage   float64            `json:"total_overage"`
	PeriodStart    time.Time          `json:"period_start"`
	PeriodEnd      time.Time          `json:"period_end"`
}

func NewUsageTrackingService(db *gorm.DB, cache *cache.Cache, cfg *config.Config) *UsageTrackingService {
	service := &UsageTrackingService{
		db:    db,
		cache: cache,
		cfg:   cfg,
	}

	// Start background usage aggregation
	go service.startUsageAggregation()

	return service
}

func (s *UsageTrackingService) TrackUsage(ctx context.Context, event UsageEvent) error {
	// Record usage event
	usageRecord := &models.UsageRecord{
		TenantID:     event.TenantID,
		ResourceType: event.ResourceType,
		Action:       event.Action,
		Quantity:     event.Quantity,
		Metadata:     event.Metadata,
		Timestamp:    event.Timestamp,
	}

	if err := s.db.Create(usageRecord).Error; err != nil {
		return fmt.Errorf("failed to record usage: %w", err)
	}

	// Update real-time usage cache
	cacheKey := fmt.Sprintf("usage:%s:%s", event.TenantID.String(), event.ResourceType)

	var currentUsage int
	var cached interface{}
	if err := s.cache.Get(context.Background(), cacheKey, &cached); err == nil {
		if usage, ok := cached.(int); ok {
			currentUsage = usage
		}
	}

	switch event.Action {
	case "CREATE":
		currentUsage += event.Quantity
	case "DELETE":
		currentUsage -= event.Quantity
		if currentUsage < 0 {
			currentUsage = 0
		}
	}

	// Cache for 1 hour
	if err := s.cache.Set(context.Background(), cacheKey, currentUsage, time.Hour); err != nil {
		log.Printf("Failed to cache usage: %v", err)
	}

	// Check for usage alerts
	go s.checkUsageAlerts(event.TenantID, event.ResourceType, currentUsage)

	return nil
}

func (s *UsageTrackingService) GetCurrentUsage(ctx context.Context, tenantID uuid.UUID, resourceType string) (int, error) {
	// Handle "all" resource type by aggregating all resources
	if resourceType == "all" {
		totalUsage := 0
		resourceTypes := []string{"users", "shops", "products", "sales"}
		for _, rt := range resourceTypes {
			usage, err := s.GetCurrentUsage(ctx, tenantID, rt)
			if err != nil {
				log.Printf("Failed to get %s usage: %v", rt, err)
				continue
			}
			totalUsage += usage
		}
		return totalUsage, nil
	}

	cacheKey := fmt.Sprintf("usage:%s:%s", tenantID.String(), resourceType)

	// Try cache first
	var cached interface{}
	if err := s.cache.Get(context.Background(), cacheKey, &cached); err == nil {
		if usage, ok := cached.(int); ok {
			return usage, nil
		}
	}

	// Fallback to database aggregation
	var usage int64

	switch resourceType {
	case "users":
		if err := s.db.Model(&models.TenantUser{}).Where("tenant_id = ? AND is_active = ?", tenantID, true).Count(&usage).Error; err != nil {
			return 0, err
		}
	case "shops":
		if err := s.db.Model(&models.Shop{}).Where("tenant_id = ? AND is_active = ?", tenantID, true).Count(&usage).Error; err != nil {
			return 0, err
		}
	case "products":
		if err := s.db.Model(&models.Product{}).Where("tenant_id = ? AND is_active = ?", tenantID, true).Count(&usage).Error; err != nil {
			return 0, err
		}
	case "sales":
		// Count sales for current month
		startOfMonth := time.Now().AddDate(0, 0, -time.Now().Day()+1)
		if err := s.db.Model(&models.Sale{}).Where("tenant_id = ? AND created_at >= ?", tenantID, startOfMonth).Count(&usage).Error; err != nil {
			return 0, err
		}
	default:
		return 0, fmt.Errorf("unsupported resource type: %s", resourceType)
	}

	// Cache the result
	s.cache.Set(context.Background(), cacheKey, int(usage), time.Hour)

	return int(usage), nil
}

func (s *UsageTrackingService) GetUsageMetrics(ctx context.Context, tenantID uuid.UUID) ([]UsageMetrics, error) {
	// Get subscription to determine limits
	var subscription models.Subscription
	if err := s.db.Where("tenant_id = ? AND status = ?", tenantID, "active").
		Preload("Plan").First(&subscription).Error; err != nil {
		return nil, fmt.Errorf("failed to get subscription: %w", err)
	}

	// Use direct plan fields instead of JSON limits
	plan := subscription.Plan

	resourceTypes := []string{"users", "shops", "products", "sales"}
	var metrics []UsageMetrics

	for _, resourceType := range resourceTypes {
		currentUsage, err := s.GetCurrentUsage(ctx, tenantID, resourceType)
		if err != nil {
			log.Printf("Failed to get usage for %s: %v", resourceType, err)
			continue
		}

		var limit int
		switch resourceType {
		case "users":
			limit = plan.MaxUsers
		case "shops":
			limit = plan.MaxLocations
		case "products":
			limit = plan.MaxProducts
		case "sales":
			// For sales, use a reasonable default since not explicitly in plan
			limit = 1000 // or derive from business logic
		}

		percentage := 0.0
		if limit > 0 {
			percentage = (float64(currentUsage) / float64(limit)) * 100
		}

		now := time.Now()
		periodStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
		periodEnd := periodStart.AddDate(0, 1, 0).Add(-time.Second)

		metrics = append(metrics, UsageMetrics{
			TenantID:        tenantID,
			ResourceType:    resourceType,
			CurrentUsage:    currentUsage,
			Limit:           limit,
			UsagePercentage: percentage,
			LastUpdated:     now,
			PeriodStart:     periodStart,
			PeriodEnd:       periodEnd,
		})
	}

	return metrics, nil
}

func (s *UsageTrackingService) GetBillingPeriodUsage(ctx context.Context, tenantID uuid.UUID, periodStart, periodEnd time.Time) (*BillingPeriodUsage, error) {
	resourceUsage := make(map[string]int)
	overageCharges := make(map[string]float64)

	// Get subscription and plan details
	var subscription models.Subscription
	if err := s.db.Where("tenant_id = ? AND status = ?", tenantID, "active").
		Preload("Plan").First(&subscription).Error; err != nil {
		return nil, fmt.Errorf("failed to get subscription: %w", err)
	}

	// Use direct plan fields instead of JSON limits
	plan := subscription.Plan

	// For overage rates, we'll use a default structure since not in current model
	// In production, this could be a separate table or JSON field
	overageRates := map[string]float64{
		"users":    10.0, // $10 per extra user
		"shops":    50.0, // $50 per extra shop
		"products": 0.01, // $0.01 per extra product
		"sales":    0.05, // $0.05 per extra sale
	}

	resourceTypes := []string{"users", "shops", "products", "sales"}

	for _, resourceType := range resourceTypes {
		// Aggregate usage for the billing period
		var totalUsage int64

		switch resourceType {
		case "sales":
			if err := s.db.Model(&models.Sale{}).
				Where("tenant_id = ? AND created_at BETWEEN ? AND ?", tenantID, periodStart, periodEnd).
				Count(&totalUsage).Error; err != nil {
				log.Printf("Failed to get %s usage: %v", resourceType, err)
				continue
			}
		default:
			// For other resources, get peak usage during period
			var usage int64
			if err := s.db.Model(&models.UsageRecord{}).
				Select("MAX(quantity)").
				Where("tenant_id = ? AND resource_type = ? AND timestamp BETWEEN ? AND ?",
					tenantID, resourceType, periodStart, periodEnd).
				Scan(&usage).Error; err != nil {
				log.Printf("Failed to get %s usage: %v", resourceType, err)
				continue
			}
			totalUsage = usage
		}

		resourceUsage[resourceType] = int(totalUsage)

		// Calculate overage charges
		var limit int
		switch resourceType {
		case "users":
			limit = plan.MaxUsers
		case "shops":
			limit = plan.MaxLocations
		case "products":
			limit = plan.MaxProducts
		case "sales":
			limit = 1000 // Default sales limit
		}

		if int(totalUsage) > limit && limit > 0 {
			overage := int(totalUsage) - limit
			if rate, ok := overageRates[resourceType]; ok {
				overageCharges[resourceType] = float64(overage) * rate
			}
		}
	}

	totalOverage := 0.0
	for _, charge := range overageCharges {
		totalOverage += charge
	}

	return &BillingPeriodUsage{
		TenantID:       tenantID,
		BillingPeriod:  fmt.Sprintf("%s_%s", periodStart.Format("2006-01"), periodEnd.Format("2006-01")),
		ResourceUsage:  resourceUsage,
		OverageCharges: overageCharges,
		TotalOverage:   totalOverage,
		PeriodStart:    periodStart,
		PeriodEnd:      periodEnd,
	}, nil
}

func (s *UsageTrackingService) checkUsageAlerts(tenantID uuid.UUID, resourceType string, currentUsage int) {
	// Get subscription limits
	var subscription models.Subscription
	if err := s.db.Where("tenant_id = ? AND status = ?", tenantID, "active").
		Preload("Plan").First(&subscription).Error; err != nil {
		return
	}

	// Use direct plan fields instead of JSON limits
	plan := subscription.Plan

	var limit int
	switch resourceType {
	case "users":
		limit = plan.MaxUsers
	case "shops":
		limit = plan.MaxLocations
	case "products":
		limit = plan.MaxProducts
	case "sales":
		limit = 1000 // Default sales limit
	}

	if limit == 0 {
		return
	}

	percentage := (float64(currentUsage) / float64(limit)) * 100

	var alertType, message string
	var shouldAlert bool

	if currentUsage >= limit {
		alertType = "LIMIT_EXCEEDED"
		message = fmt.Sprintf("Usage limit exceeded for %s. Current: %d, Limit: %d", resourceType, currentUsage, limit)
		shouldAlert = true
	} else if percentage >= 90 {
		alertType = "CRITICAL"
		message = fmt.Sprintf("Critical usage warning for %s. Current: %d (%.1f%% of limit)", resourceType, currentUsage, percentage)
		shouldAlert = true
	} else if percentage >= 80 {
		alertType = "WARNING"
		message = fmt.Sprintf("Usage warning for %s. Current: %d (%.1f%% of limit)", resourceType, currentUsage, percentage)
		shouldAlert = true
	}

	if shouldAlert {
		alert := UsageAlert{
			TenantID:     tenantID,
			ResourceType: resourceType,
			AlertType:    alertType,
			CurrentUsage: currentUsage,
			Limit:        limit,
			Percentage:   percentage,
			Message:      message,
			Timestamp:    time.Now(),
		}

		// Store alert (you might want to create an alerts table)
		alertJSON, _ := json.Marshal(alert)
		cacheKey := fmt.Sprintf("alert:%s:%s:%s", tenantID.String(), resourceType, alertType)
		s.cache.Set(context.Background(), cacheKey, string(alertJSON), 24*time.Hour)

		// Here you could trigger notifications, webhooks, etc.
		log.Printf("Usage alert: %s", message)
	}
}

func (s *UsageTrackingService) startUsageAggregation() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		s.aggregateUsageData()
	}
}

func (s *UsageTrackingService) aggregateUsageData() {
	// Aggregate usage data every 5 minutes for real-time dashboard
	var tenants []models.Tenant
	if err := s.db.Find(&tenants).Error; err != nil {
		log.Printf("Failed to get tenants for usage aggregation: %v", err)
		return
	}

	for _, tenant := range tenants {
		resourceTypes := []string{"users", "shops", "products", "sales"}

		for _, resourceType := range resourceTypes {
			usage, err := s.GetCurrentUsage(context.Background(), tenant.ID, resourceType)
			if err != nil {
				log.Printf("Failed to get current usage for tenant %s, resource %s: %v", tenant.ID.String(), resourceType, err)
				continue
			}

			// Update cached metrics
			metricsKey := fmt.Sprintf("metrics:%s:%s", tenant.ID.String(), resourceType)
			metrics := map[string]interface{}{
				"usage":     usage,
				"timestamp": time.Now().Unix(),
			}

			metricsJSON, _ := json.Marshal(metrics)
			s.cache.Set(context.Background(), metricsKey, string(metricsJSON), time.Hour)
		}
	}
}

func (s *UsageTrackingService) GetUsageHistory(ctx context.Context, tenantID uuid.UUID, resourceType string, days int) ([]UsageEvent, error) {
	var records []models.UsageRecord

	startDate := time.Now().AddDate(0, 0, -days)

	query := s.db.Where("tenant_id = ? AND timestamp >= ?", tenantID, startDate)

	// Handle "all" resource type
	if resourceType != "all" {
		query = query.Where("resource_type = ?", resourceType)
	}

	if err := query.Order("timestamp DESC").Find(&records).Error; err != nil {
		return nil, fmt.Errorf("failed to get usage history: %w", err)
	}

	var events []UsageEvent
	for _, record := range records {
		events = append(events, UsageEvent{
			TenantID:     record.TenantID,
			ResourceType: record.ResourceType,
			Action:       record.Action,
			Quantity:     record.Quantity,
			Metadata:     record.Metadata,
			Timestamp:    record.Timestamp,
		})
	}

	return events, nil
}
