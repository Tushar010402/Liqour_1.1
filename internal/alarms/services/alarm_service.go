package services

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// AlarmService handles all alarm operations
type AlarmService struct {
	db           *database.DB
	cache        *cache.Cache
	notifService NotificationServiceInterface
	mu           sync.RWMutex
}

// NotificationServiceInterface for sending notifications
type NotificationServiceInterface interface {
	SendNotification(ctx context.Context, tenantID, userID uuid.UUID, req *models.SendNotificationRequest) (*models.Notification, error)
	SendBulkNotification(ctx context.Context, tenantID uuid.UUID, req *models.BulkNotificationRequest) (int, error)
}

// NewAlarmService creates a new alarm service
func NewAlarmService(db *database.DB, cache *cache.Cache, notifService NotificationServiceInterface) *AlarmService {
	return &AlarmService{
		db:           db,
		cache:        cache,
		notifService: notifService,
	}
}

// ========================================
// Alarm Definition Management (System Alarms)
// ========================================

// GetAlarmDefinitions returns all alarm definitions
func (s *AlarmService) GetAlarmDefinitions(ctx context.Context, category string) ([]models.AlarmDefinition, error) {
	var definitions []models.AlarmDefinition
	query := s.db.WithContext(ctx).Where("is_active = true")
	if category != "" {
		query = query.Where("category = ?", category)
	}
	err := query.Order("category, name").Find(&definitions).Error
	return definitions, err
}

// GetAlarmDefinitionByCode returns a specific alarm definition by code
func (s *AlarmService) GetAlarmDefinitionByCode(ctx context.Context, code string) (*models.AlarmDefinition, error) {
	var definition models.AlarmDefinition
	err := s.db.WithContext(ctx).Where("code = ? AND is_active = true", code).First(&definition).Error
	return &definition, err
}

// ========================================
// Tenant Alarm Configuration
// ========================================

// GetAlarmConfigurations returns alarm configurations for a tenant
func (s *AlarmService) GetAlarmConfigurations(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]models.AlarmConfiguration, error) {
	var configs []models.AlarmConfiguration
	query := s.db.WithContext(ctx).
		Preload("Definition").
		Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ? OR shop_id IS NULL", *shopID)
	}

	err := query.Order("alarm_code").Find(&configs).Error
	return configs, err
}

// GetAlarmConfiguration returns a specific alarm config
func (s *AlarmService) GetAlarmConfiguration(ctx context.Context, tenantID uuid.UUID, alarmCode string, shopID *uuid.UUID) (*models.AlarmConfiguration, error) {
	var config models.AlarmConfiguration
	query := s.db.WithContext(ctx).
		Preload("AlarmDefinition").
		Where("tenant_id = ? AND alarm_code = ?", tenantID, alarmCode)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	} else {
		query = query.Where("shop_id IS NULL")
	}

	err := query.First(&config).Error
	if err == gorm.ErrRecordNotFound {
		// Return default config from definition
		def, err := s.GetAlarmDefinitionByCode(ctx, alarmCode)
		if err != nil {
			return nil, err
		}
		return &models.AlarmConfiguration{
			TenantID:          tenantID,
			AlarmCode:         alarmCode,
			ShopID:            shopID,
			AlarmDefinitionID: def.ID,
			IsEnabled:         def.IsActive,
			Priority:          def.DefaultPriority,
			Thresholds:        def.ThresholdSchema,
			CooldownMinutes:   def.DefaultCooldownMinutes,
			AlarmDefinition:   def,
		}, nil
	}
	return &config, err
}

// UpdateAlarmConfiguration creates or updates a tenant alarm configuration
func (s *AlarmService) UpdateAlarmConfiguration(ctx context.Context, tenantID uuid.UUID, alarmCode string, shopID *uuid.UUID, req *models.UpdateAlarmConfigRequest) (*models.AlarmConfiguration, error) {
	// Validate alarm code exists
	def, err := s.GetAlarmDefinitionByCode(ctx, alarmCode)
	if err != nil {
		return nil, fmt.Errorf("invalid alarm code: %w", err)
	}

	var config models.AlarmConfiguration
	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND alarm_code = ?", tenantID, alarmCode)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	} else {
		query = query.Where("shop_id IS NULL")
	}

	err = query.First(&config).Error
	if err == gorm.ErrRecordNotFound {
		config = models.AlarmConfiguration{
			ID:                uuid.New(),
			TenantID:          tenantID,
			AlarmDefinitionID: def.ID,
			AlarmCode:         alarmCode,
			ShopID:            shopID,
			IsEnabled:         true,
			Priority:          def.DefaultPriority,
			CooldownMinutes:   def.DefaultCooldownMinutes,
			CreatedAt:         time.Now(),
		}
	} else if err != nil {
		return nil, err
	}

	// Update fields
	if req.IsEnabled != nil {
		config.IsEnabled = *req.IsEnabled
	}
	if req.Priority != "" {
		config.Priority = req.Priority
	}
	if req.Thresholds != nil {
		config.Thresholds = req.Thresholds
	}
	if req.ScheduleType != "" {
		config.ScheduleType = req.ScheduleType
	}
	if req.CronExpression != "" {
		config.CronExpression = req.CronExpression
	}
	if req.PresetSchedule != "" {
		config.PresetSchedule = req.PresetSchedule
	}
	if req.Timezone != "" {
		config.Timezone = req.Timezone
	}
	if len(req.Channels) > 0 {
		config.SetChannels(req.Channels)
	}
	if req.Recipients != nil {
		config.SetRecipients(req.Recipients)
	}
	if req.CooldownMinutes != nil {
		config.CooldownMinutes = *req.CooldownMinutes
	}
	if req.MaxAlertsPerDay != nil {
		config.MaxAlertsPerDay = *req.MaxAlertsPerDay
	}
	if req.QuietHoursStart != nil {
		config.QuietHoursStart = req.QuietHoursStart
	}
	if req.QuietHoursEnd != nil {
		config.QuietHoursEnd = req.QuietHoursEnd
	}
	if req.BypassQuietForCritical != nil {
		config.BypassQuietForCritical = *req.BypassQuietForCritical
	}
	if req.CustomTitleTemplate != "" {
		config.CustomTitleTemplate = req.CustomTitleTemplate
	}
	if req.CustomMessageTemplate != "" {
		config.CustomMessageTemplate = req.CustomMessageTemplate
	}

	config.UpdatedAt = time.Now()

	if err := s.db.WithContext(ctx).Save(&config).Error; err != nil {
		return nil, err
	}

	config.AlarmDefinition = def
	return &config, nil
}

// ========================================
// Alarm Instance Management
// ========================================

// TriggerAlarm creates a new alarm instance
func (s *AlarmService) TriggerAlarm(ctx context.Context, tenantID uuid.UUID, req *models.TriggerAlarmRequest) (*models.AlarmInstance, error) {
	// Get tenant config or default
	config, err := s.GetAlarmConfiguration(ctx, tenantID, req.AlarmCode, req.ShopID)
	if err != nil {
		return nil, err
	}

	// Check if alarm is enabled
	if !config.IsEnabled {
		return nil, fmt.Errorf("alarm %s is disabled for this tenant", req.AlarmCode)
	}

	// Check for existing active alarm with same entity (cooldown check)
	if req.RelatedEntityID != nil {
		var existing models.AlarmInstance
		cooldownTime := time.Now().Add(-time.Duration(config.CooldownMinutes) * time.Minute)
		err := s.db.WithContext(ctx).
			Where("tenant_id = ? AND alarm_code = ? AND related_entity_id = ? AND status IN ? AND triggered_at > ?",
				tenantID, req.AlarmCode, req.RelatedEntityID, []string{models.AlarmStatusActive, models.AlarmStatusAcknowledged}, cooldownTime).
			First(&existing).Error

		if err == nil {
			// Within cooldown period, skip
			return &existing, nil
		}
	}

	// Create new alarm instance
	now := time.Now()
	priority := config.Priority
	if req.Priority != "" {
		priority = req.Priority
	}

	// Build title and message
	title := req.Title
	if title == "" {
		if config.CustomTitleTemplate != "" {
			title = config.CustomTitleTemplate
		} else if config.AlarmDefinition != nil {
			title = config.AlarmDefinition.Name
		} else {
			title = "Alert: " + req.AlarmCode
		}
	}

	message := req.Message
	if message == "" && config.CustomMessageTemplate != "" {
		message = config.CustomMessageTemplate
	}

	instance := &models.AlarmInstance{
		ID:                uuid.New(),
		TenantID:          tenantID,
		ShopID:            req.ShopID,
		AlarmConfigID:     &config.ID,
		AlarmCode:         req.AlarmCode,
		Title:             title,
		Message:           message,
		Priority:          priority,
		Status:            models.AlarmStatusActive,
		RelatedEntityType: req.RelatedEntityType,
		RelatedEntityID:   req.RelatedEntityID,
		TriggerData:       req.TriggerData,
		TriggeredAt:       now,
		CreatedAt:         now,
		UpdatedAt:         now,
	}

	if err := s.db.WithContext(ctx).Create(instance).Error; err != nil {
		return nil, err
	}

	// Send notifications
	go s.sendAlarmNotifications(context.Background(), tenantID, instance, config)

	// Record in history
	s.recordAlarmHistory(ctx, instance, models.AlarmActionTriggered, nil, "Alarm triggered")

	return instance, nil
}

// GetAlarmInstances returns alarm instances for a tenant
func (s *AlarmService) GetAlarmInstances(ctx context.Context, tenantID uuid.UUID, filter *models.AlarmInstanceFilter) (*models.AlarmInstanceListResponse, error) {
	var instances []models.AlarmInstance
	var total int64

	query := s.db.WithContext(ctx).
		Model(&models.AlarmInstance{}).
		Where("tenant_id = ?", tenantID)

	if filter != nil {
		if filter.ShopID != nil {
			query = query.Where("shop_id = ?", *filter.ShopID)
		}
		if filter.AlarmCode != "" {
			query = query.Where("alarm_code = ?", filter.AlarmCode)
		}
		if filter.Status != "" {
			query = query.Where("status = ?", filter.Status)
		}
		if filter.Priority != "" {
			query = query.Where("priority = ?", filter.Priority)
		}
		if filter.StartDate != nil {
			query = query.Where("triggered_at >= ?", *filter.StartDate)
		}
		if filter.EndDate != nil {
			query = query.Where("triggered_at <= ?", *filter.EndDate)
		}
	}

	// Count total
	query.Count(&total)

	// Apply pagination
	page := 1
	pageSize := 20
	if filter != nil {
		if filter.Page > 0 {
			page = filter.Page
		}
		if filter.PageSize > 0 {
			pageSize = filter.PageSize
		}
	}

	offset := (page - 1) * pageSize
	err := query.Order("priority DESC, triggered_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&instances).Error

	if err != nil {
		return nil, err
	}

	return &models.AlarmInstanceListResponse{
		Alarms:   instances,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
	}, nil
}

// GetAlarmInstance returns a specific alarm instance
func (s *AlarmService) GetAlarmInstance(ctx context.Context, tenantID uuid.UUID, alarmID uuid.UUID) (*models.AlarmInstance, error) {
	var instance models.AlarmInstance
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND id = ?", tenantID, alarmID).
		First(&instance).Error
	return &instance, err
}

// AcknowledgeAlarm acknowledges an alarm
func (s *AlarmService) AcknowledgeAlarm(ctx context.Context, tenantID, userID uuid.UUID, alarmID uuid.UUID, note string) (*models.AlarmInstance, error) {
	instance, err := s.GetAlarmInstance(ctx, tenantID, alarmID)
	if err != nil {
		return nil, err
	}

	if instance.Status != models.AlarmStatusActive {
		return nil, fmt.Errorf("alarm is not active")
	}

	now := time.Now()
	instance.Status = models.AlarmStatusAcknowledged
	instance.AcknowledgedBy = &userID
	instance.AcknowledgedAt = &now
	instance.UpdatedAt = now

	if err := s.db.WithContext(ctx).Save(instance).Error; err != nil {
		return nil, err
	}

	// Record history
	s.recordAlarmHistory(ctx, instance, models.AlarmActionAcknowledged, &userID, note)

	return instance, nil
}

// ResolveAlarm resolves an alarm
func (s *AlarmService) ResolveAlarm(ctx context.Context, tenantID, userID uuid.UUID, alarmID uuid.UUID, resolution string) (*models.AlarmInstance, error) {
	instance, err := s.GetAlarmInstance(ctx, tenantID, alarmID)
	if err != nil {
		return nil, err
	}

	if instance.Status == models.AlarmStatusResolved {
		return nil, fmt.Errorf("alarm is already resolved")
	}

	now := time.Now()
	instance.Status = models.AlarmStatusResolved
	instance.ResolvedBy = &userID
	instance.ResolvedAt = &now
	instance.ResolutionNotes = resolution
	instance.UpdatedAt = now

	if err := s.db.WithContext(ctx).Save(instance).Error; err != nil {
		return nil, err
	}

	// Record history
	s.recordAlarmHistory(ctx, instance, models.AlarmActionResolved, &userID, resolution)

	return instance, nil
}

// SnoozeAlarm snoozes an alarm for a duration
func (s *AlarmService) SnoozeAlarm(ctx context.Context, tenantID, userID uuid.UUID, alarmID uuid.UUID, minutes int, reason string) (*models.AlarmInstance, error) {
	instance, err := s.GetAlarmInstance(ctx, tenantID, alarmID)
	if err != nil {
		return nil, err
	}

	if instance.Status == models.AlarmStatusResolved || instance.Status == models.AlarmStatusExpired {
		return nil, fmt.Errorf("cannot snooze resolved or expired alarm")
	}

	now := time.Now()
	snoozeUntil := now.Add(time.Duration(minutes) * time.Minute)
	instance.Status = models.AlarmStatusSnoozed
	instance.SnoozedUntil = &snoozeUntil
	instance.UpdatedAt = now

	if err := s.db.WithContext(ctx).Save(instance).Error; err != nil {
		return nil, err
	}

	// Record history
	note := fmt.Sprintf("Snoozed for %d minutes. Reason: %s", minutes, reason)
	s.recordAlarmHistory(ctx, instance, models.AlarmActionSnoozed, &userID, note)

	return instance, nil
}

// AddAlarmNote adds a note to an alarm
func (s *AlarmService) AddAlarmNote(ctx context.Context, tenantID, userID uuid.UUID, alarmID uuid.UUID, note string) error {
	instance, err := s.GetAlarmInstance(ctx, tenantID, alarmID)
	if err != nil {
		return err
	}

	alarmNote := &models.AlarmNote{
		ID:        uuid.New(),
		AlarmID:   alarmID,
		UserID:    userID,
		Note:      note,
		CreatedAt: time.Now(),
	}

	if err := s.db.WithContext(ctx).Create(alarmNote).Error; err != nil {
		return err
	}

	// Also record in history
	s.recordAlarmHistory(ctx, instance, models.AlarmActionNoteAdded, &userID, note)

	return nil
}

// GetAlarmNotes returns notes for an alarm
func (s *AlarmService) GetAlarmNotes(ctx context.Context, tenantID, alarmID uuid.UUID) ([]models.AlarmNote, error) {
	var notes []models.AlarmNote
	err := s.db.WithContext(ctx).
		Where("alarm_id = ?", alarmID).
		Order("created_at DESC").
		Preload("User").
		Find(&notes).Error
	return notes, err
}

// GetAlarmHistory returns history for an alarm
func (s *AlarmService) GetAlarmHistory(ctx context.Context, tenantID, alarmID uuid.UUID) ([]models.AlarmHistory, error) {
	var history []models.AlarmHistory
	err := s.db.WithContext(ctx).
		Where("alarm_id = ?", alarmID).
		Order("created_at DESC").
		Preload("User").
		Find(&history).Error
	return history, err
}

// ========================================
// Alarm Counts and Statistics
// ========================================

// GetAlarmCounts returns alarm counts for dashboard
func (s *AlarmService) GetAlarmCounts(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) (*models.AlarmCountsResponse, error) {
	counts := &models.AlarmCountsResponse{
		ByPriority: make(map[string]int64),
		ByCategory: make(map[string]int64),
		ByShop:     make(map[string]int64),
	}

	baseQuery := func() *gorm.DB {
		q := s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
			Where("tenant_id = ?", tenantID)
		if shopID != nil {
			q = q.Where("shop_id = ?", *shopID)
		}
		return q
	}

	// Active count
	baseQuery().Where("status = ?", models.AlarmStatusActive).Count(&counts.TotalActive)

	// Acknowledged count
	baseQuery().Where("status = ?", models.AlarmStatusAcknowledged).Count(&counts.TotalAcknowledged)

	// Snoozed count
	baseQuery().Where("status = ?", models.AlarmStatusSnoozed).Count(&counts.TotalSnoozed)

	// Resolved today
	today := time.Now().Truncate(24 * time.Hour)
	baseQuery().Where("status = ? AND resolved_at >= ?", models.AlarmStatusResolved, today).Count(&counts.TotalResolved)

	// By priority
	var priorityResults []struct {
		Priority string
		Count    int64
	}
	baseQuery().
		Select("priority, COUNT(*) as count").
		Where("status IN ?", []string{models.AlarmStatusActive, models.AlarmStatusAcknowledged}).
		Group("priority").
		Scan(&priorityResults)
	for _, r := range priorityResults {
		counts.ByPriority[r.Priority] = r.Count
	}

	// By alarm code (using ByCategory)
	var codeResults []struct {
		AlarmCode string
		Count     int64
	}
	baseQuery().
		Select("alarm_code, COUNT(*) as count").
		Where("status IN ?", []string{models.AlarmStatusActive, models.AlarmStatusAcknowledged}).
		Group("alarm_code").
		Scan(&codeResults)
	for _, r := range codeResults {
		counts.ByCategory[r.AlarmCode] = r.Count
	}

	return counts, nil
}

// GetAlarmStats returns alarm statistics for reporting
func (s *AlarmService) GetAlarmStats(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time) (*models.AlarmStatsResponse, error) {
	stats := &models.AlarmStatsResponse{
		Period:       fmt.Sprintf("%s - %s", startDate.Format("2006-01-02"), endDate.Format("2006-01-02")),
		ByPriority:   make(map[string]int64),
		ByAlarmCode:  make(map[string]int64),
		TrendData:    []models.AlarmTrendPoint{},
	}

	// Total triggered
	s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Where("tenant_id = ? AND triggered_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Count(&stats.TotalTriggered)

	// Total resolved
	s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Where("tenant_id = ? AND triggered_at BETWEEN ? AND ? AND status = ?", tenantID, startDate, endDate, models.AlarmStatusResolved).
		Count(&stats.TotalResolved)

	// Average resolution time
	var avgTime struct {
		AvgMinutes float64
	}
	s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Select("AVG(EXTRACT(EPOCH FROM (resolved_at - triggered_at))/60) as avg_minutes").
		Where("tenant_id = ? AND triggered_at BETWEEN ? AND ? AND status = ?", tenantID, startDate, endDate, models.AlarmStatusResolved).
		Scan(&avgTime)
	stats.AverageResolutionMinutes = avgTime.AvgMinutes

	// By priority
	var priorityResults []struct {
		Priority string
		Count    int64
	}
	s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Select("priority, COUNT(*) as count").
		Where("tenant_id = ? AND triggered_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("priority").
		Scan(&priorityResults)
	for _, r := range priorityResults {
		stats.ByPriority[r.Priority] = r.Count
	}

	// By alarm code
	var codeResults []struct {
		AlarmCode string
		Count     int64
	}
	s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Select("alarm_code, COUNT(*) as count").
		Where("tenant_id = ? AND triggered_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("alarm_code").
		Scan(&codeResults)
	for _, r := range codeResults {
		stats.ByAlarmCode[r.AlarmCode] = r.Count
	}

	// Daily trend
	var trendResults []struct {
		Date     string
		Count    int64
		Resolved int64
	}
	s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Select("DATE(triggered_at) as date, COUNT(*) as count, SUM(CASE WHEN status = 'resolved' THEN 1 ELSE 0 END) as resolved").
		Where("tenant_id = ? AND triggered_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("DATE(triggered_at)").
		Order("date").
		Scan(&trendResults)
	for _, r := range trendResults {
		stats.TrendData = append(stats.TrendData, models.AlarmTrendPoint{
			Date:     r.Date,
			Count:    r.Count,
			Resolved: r.Resolved,
		})
	}

	return stats, nil
}

// ========================================
// User Alarm Subscription
// ========================================

// GetUserAlarmSubscriptions returns alarm subscriptions for a user
func (s *AlarmService) GetUserAlarmSubscriptions(ctx context.Context, tenantID, userID uuid.UUID) ([]models.UserAlarmSubscription, error) {
	var subscriptions []models.UserAlarmSubscription
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Find(&subscriptions).Error
	return subscriptions, err
}

// UpdateUserAlarmSubscription updates a user's alarm subscription
func (s *AlarmService) UpdateUserAlarmSubscription(ctx context.Context, tenantID, userID uuid.UUID, req *models.UpdateAlarmSubscriptionRequest) (*models.UserAlarmSubscription, error) {
	var sub models.UserAlarmSubscription
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND alarm_code = ?", tenantID, userID, req.AlarmCode).
		First(&sub).Error

	if err == gorm.ErrRecordNotFound {
		sub = models.UserAlarmSubscription{
			TenantID:  tenantID,
			UserID:    userID,
			AlarmCode: req.AlarmCode,
			CreatedAt: time.Now(),
		}
	} else if err != nil {
		return nil, err
	}

	if req.IsSubscribed != nil {
		sub.IsSubscribed = *req.IsSubscribed
	}
	if len(req.Channels) > 0 {
		channelsJSON, _ := json.Marshal(req.Channels)
		sub.Channels = channelsJSON
	}
	if req.MinPriority != "" {
		sub.MinPriority = req.MinPriority
	}
	if req.QuietHoursEnabled != nil {
		sub.QuietHoursEnabled = *req.QuietHoursEnabled
	}
	if req.QuietHoursStart != nil {
		sub.QuietHoursStart = req.QuietHoursStart
	}
	if req.QuietHoursEnd != nil {
		sub.QuietHoursEnd = req.QuietHoursEnd
	}
	sub.UpdatedAt = time.Now()

	if err := s.db.WithContext(ctx).Save(&sub).Error; err != nil {
		return nil, err
	}

	return &sub, nil
}

// ========================================
// Internal Helpers
// ========================================

func (s *AlarmService) buildAlarmTitle(def *models.AlarmDefinition, req *models.TriggerAlarmRequest) string {
	if def == nil {
		return fmt.Sprintf("Alert: %s", req.AlarmCode)
	}
	return def.Name
}

func (s *AlarmService) buildAlarmMessage(config *models.AlarmConfiguration, req *models.TriggerAlarmRequest) string {
	if config.CustomMessageTemplate != "" {
		return config.CustomMessageTemplate
	}
	if config.AlarmDefinition != nil && config.AlarmDefinition.Description != "" {
		return config.AlarmDefinition.Description
	}
	return fmt.Sprintf("Alarm triggered: %s", req.AlarmCode)
}

func (s *AlarmService) sendAlarmNotifications(ctx context.Context, tenantID uuid.UUID, alarm *models.AlarmInstance, config *models.AlarmConfiguration) {
	if s.notifService == nil {
		return
	}

	// Build notification data
	data := map[string]interface{}{
		"alarm_id":    alarm.ID.String(),
		"alarm_code":  alarm.AlarmCode,
		"priority":    alarm.Priority,
		"message":     alarm.Message,
		"action_url":  fmt.Sprintf("/alarms/%s", alarm.ID.String()),
	}

	// Add trigger data
	if alarm.TriggerData != nil {
		var triggerMap map[string]interface{}
		if err := json.Unmarshal(alarm.TriggerData, &triggerMap); err == nil {
			for k, v := range triggerMap {
				data[k] = v
			}
		}
	}

	// Map alarm priority to notification priority
	notifPriority := models.NotificationPriorityNormal
	switch alarm.Priority {
	case models.AlarmPriorityCritical:
		notifPriority = models.NotificationPriorityCritical
	case models.AlarmPriorityHigh:
		notifPriority = models.NotificationPriorityHigh
	case models.AlarmPriorityLow:
		notifPriority = models.NotificationPriorityLow
	}

	// Get recipients from configuration
	recipients := config.GetRecipients()
	if recipients != nil && len(recipients.UserIDs) > 0 {
		bulkReq := &models.BulkNotificationRequest{
			UserIDs:  recipients.UserIDs,
			Category: models.NotificationCategoryAlert,
			Priority: notifPriority,
			Title:    alarm.Title,
			Body:     alarm.Message,
			Data:     data,
		}
		s.notifService.SendBulkNotification(ctx, tenantID, bulkReq)
	}

	if recipients != nil && len(recipients.Roles) > 0 {
		bulkReq := &models.BulkNotificationRequest{
			RoleFilter: recipients.Roles,
			Category:   models.NotificationCategoryAlert,
			Priority:   notifPriority,
			Title:      alarm.Title,
			Body:       alarm.Message,
			Data:       data,
		}
		if alarm.ShopID != nil {
			bulkReq.ShopFilter = []uuid.UUID{*alarm.ShopID}
		}
		s.notifService.SendBulkNotification(ctx, tenantID, bulkReq)
	}
}

func (s *AlarmService) recordAlarmHistory(ctx context.Context, alarm *models.AlarmInstance, action string, userID *uuid.UUID, notes string) {
	history := &models.AlarmHistory{
		ID:        uuid.New(),
		AlarmID:   alarm.ID,
		Action:    action,
		UserID:    userID,
		Notes:     notes,
		NewStatus: alarm.Status,
		CreatedAt: time.Now(),
	}
	s.db.WithContext(ctx).Create(history)
}

// ========================================
// Background Processing Methods
// ========================================

// ProcessExpiredSnoozes wakes up snoozed alarms
func (s *AlarmService) ProcessExpiredSnoozes(ctx context.Context) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Where("status = ? AND snoozed_until <= ?", models.AlarmStatusSnoozed, now).
		Updates(map[string]interface{}{
			"status":     models.AlarmStatusActive,
			"updated_at": now,
		}).Error
}

// ProcessAutoResolves resolves alarms past their expiry time
func (s *AlarmService) ProcessAutoResolves(ctx context.Context) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.AlarmInstance{}).
		Where("status IN ? AND expires_at <= ?", []string{models.AlarmStatusActive, models.AlarmStatusAcknowledged}, now).
		Updates(map[string]interface{}{
			"status":           models.AlarmStatusExpired,
			"resolution_notes": "Auto-expired",
			"updated_at":       now,
		}).Error
}

// ProcessEscalations escalates alarms that have been active too long
func (s *AlarmService) ProcessEscalations(ctx context.Context) error {
	var alarms []models.AlarmInstance
	now := time.Now()

	// Get alarms active for more than their escalation threshold (24 hours default)
	err := s.db.WithContext(ctx).
		Where("status = ? AND escalation_level = 0 AND triggered_at <= ?", models.AlarmStatusActive, now.Add(-24*time.Hour)).
		Find(&alarms).Error

	if err != nil {
		return err
	}

	for _, alarm := range alarms {
		// Increment escalation level
		alarm.EscalationLevel++
		alarm.EscalatedAt = &now
		alarm.UpdatedAt = now

		if err := s.db.WithContext(ctx).Save(&alarm).Error; err != nil {
			continue
		}

		// Record escalation history
		s.recordAlarmHistory(ctx, &alarm, models.AlarmActionEscalated, nil, "Auto-escalated due to unacknowledged status")

		// Send escalation notification
		bulkReq := models.BulkNotificationRequest{
			Category: models.NotificationCategoryAlert,
			Priority: models.NotificationPriorityCritical,
			Title:    fmt.Sprintf("[ESCALATED] %s", alarm.Title),
			Body:     fmt.Sprintf("This alarm has been escalated due to no response. %s", alarm.Message),
			Data: map[string]interface{}{
				"alarm_id":         alarm.ID.String(),
				"alarm_code":       alarm.AlarmCode,
				"escalation_level": alarm.EscalationLevel,
			},
		}
		s.notifService.SendBulkNotification(ctx, alarm.TenantID, &bulkReq)
	}

	return nil
}

// CleanupOldAlarms archives old resolved alarms
func (s *AlarmService) CleanupOldAlarms(ctx context.Context, retentionDays int) error {
	cutoff := time.Now().AddDate(0, 0, -retentionDays)

	// Move to archive table if needed, or just delete
	return s.db.WithContext(ctx).
		Where("status IN ? AND resolved_at < ?", []string{models.AlarmStatusResolved, models.AlarmStatusExpired}, cutoff).
		Delete(&models.AlarmInstance{}).Error
}

// BulkTriggerAlarms triggers multiple alarms efficiently
func (s *AlarmService) BulkTriggerAlarms(ctx context.Context, tenantID uuid.UUID, alarms []models.TriggerAlarmRequest) ([]models.AlarmInstance, error) {
	var triggered []models.AlarmInstance

	for _, req := range alarms {
		instance, err := s.TriggerAlarm(ctx, tenantID, &req)
		if err != nil {
			// Log error but continue
			continue
		}
		triggered = append(triggered, *instance)
	}

	return triggered, nil
}

// GetAlarmDefinitionByID returns an alarm definition by ID
func (s *AlarmService) GetAlarmDefinitionByID(ctx context.Context, id uuid.UUID) (*models.AlarmDefinition, error) {
	var definition models.AlarmDefinition
	err := s.db.WithContext(ctx).Where("id = ?", id).First(&definition).Error
	return &definition, err
}

// MarshalContextData helper for context data
func MarshalContextData(data interface{}) json.RawMessage {
	bytes, _ := json.Marshal(data)
	return bytes
}
