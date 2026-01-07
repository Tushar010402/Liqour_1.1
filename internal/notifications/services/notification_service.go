package services

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"text/template"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// NotificationService handles all notification operations
type NotificationService struct {
	db          *database.DB
	cache       *cache.Cache
	channels    map[models.NotificationChannel]ChannelProvider
	channelsMu  sync.RWMutex
	templateMu  sync.RWMutex
	templates   map[string]*template.Template
}

// ChannelProvider interface for notification channels
type ChannelProvider interface {
	Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error)
	GetName() string
	IsEnabled() bool
}

// NewNotificationService creates a new notification service
func NewNotificationService(db *database.DB, cache *cache.Cache) *NotificationService {
	service := &NotificationService{
		db:        db,
		cache:     cache,
		channels:  make(map[models.NotificationChannel]ChannelProvider),
		templates: make(map[string]*template.Template),
	}

	// Initialize all channel providers (Push, Email, SMS, WhatsApp, InApp)
	InitializeChannelProviders(service)

	return service
}

// RegisterChannel registers a notification channel provider
func (s *NotificationService) RegisterChannel(channel models.NotificationChannel, provider ChannelProvider) {
	s.channelsMu.Lock()
	defer s.channelsMu.Unlock()
	s.channels[channel] = provider
}

// SendNotification sends a notification to a user
func (s *NotificationService) SendNotification(ctx context.Context, tenantID, userID uuid.UUID, req *models.SendNotificationRequest) (*models.Notification, error) {
	// Load user preferences
	preferences, err := s.GetUserPreferences(ctx, tenantID, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get user preferences: %w", err)
	}

	// Create notification
	notification := &models.Notification{
		TenantID:  tenantID,
		UserID:    userID,
		Category:  req.Category,
		Priority:  req.Priority,
		Title:     req.Title,
		Body:      req.Body,
		Data:      req.Data,
		ActionURL: req.ActionURL,
		ActionLabel: req.ActionLabel,
		Status:    models.NotificationStatusPending,
		GroupID:   req.GroupID,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	// If template code provided, use template
	if req.TemplateCode != "" {
		template, err := s.GetTemplateByCode(ctx, req.TemplateCode)
		if err != nil {
			return nil, fmt.Errorf("template not found: %w", err)
		}
		notification.TemplateID = &template.ID
		notification.Category = template.Category
		if notification.Priority == "" {
			notification.Priority = template.DefaultPriority
		}
		notification.Title, notification.Body, err = s.renderTemplate(template, req.Data)
		if err != nil {
			return nil, fmt.Errorf("failed to render template: %w", err)
		}
	}

	// Check if should digest
	pref := findPreference(preferences, notification.Category)
	if pref != nil && pref.DigestMode {
		return s.addToDigest(ctx, notification, pref)
	}

	// Save notification
	if err := s.db.WithContext(ctx).Create(notification).Error; err != nil {
		return nil, fmt.Errorf("failed to create notification: %w", err)
	}

	// Determine channels to send
	channels := s.determineChannels(req.Channels, pref, notification.Priority)

	// Send through each channel
	var wg sync.WaitGroup
	for _, ch := range channels {
		wg.Add(1)
		go func(channel models.NotificationChannel) {
			defer wg.Done()
			s.sendThroughChannel(ctx, notification, channel)
		}(ch)
	}
	wg.Wait()

	notification.Status = models.NotificationStatusSent
	s.db.WithContext(ctx).Save(notification)

	return notification, nil
}

// SendBulkNotification sends notification to multiple users
func (s *NotificationService) SendBulkNotification(ctx context.Context, tenantID uuid.UUID, req *models.BulkNotificationRequest) (int, error) {
	var userIDs []uuid.UUID

	// If specific user IDs provided
	if len(req.UserIDs) > 0 {
		userIDs = req.UserIDs
	}

	// If role filter provided
	if len(req.RoleFilter) > 0 {
		var users []models.User
		query := s.db.WithContext(ctx).Where("tenant_id = ?", tenantID)
		query = query.Where("role IN ?", req.RoleFilter)
		if len(req.ShopFilter) > 0 {
			query = query.Where("shop_id IN ?", req.ShopFilter)
		}
		if err := query.Find(&users).Error; err != nil {
			return 0, err
		}
		for _, u := range users {
			userIDs = append(userIDs, u.ID)
		}
	}

	// Deduplicate
	userIDMap := make(map[uuid.UUID]bool)
	for _, id := range userIDs {
		userIDMap[id] = true
	}

	sent := 0
	for userID := range userIDMap {
		singleReq := &models.SendNotificationRequest{
			UserID:       userID,
			TemplateCode: req.TemplateCode,
			Category:     req.Category,
			Priority:     req.Priority,
			Title:        req.Title,
			Body:         req.Body,
			Data:         req.Data,
			ActionURL:    req.ActionURL,
			Channels:     req.Channels,
		}
		if _, err := s.SendNotification(ctx, tenantID, userID, singleReq); err == nil {
			sent++
		}
	}

	return sent, nil
}

// GetUserNotifications retrieves paginated notifications for a user
func (s *NotificationService) GetUserNotifications(ctx context.Context, tenantID, userID uuid.UUID, page, pageSize int, category string, unreadOnly bool) (*models.NotificationListResponse, error) {
	var notifications []models.Notification
	var total int64

	query := s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID)

	if category != "" {
		query = query.Where("category = ?", category)
	}
	if unreadOnly {
		query = query.Where("read_at IS NULL")
	}

	// Count total
	query.Count(&total)

	// Fetch page
	offset := (page - 1) * pageSize
	if err := query.Order("created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&notifications).Error; err != nil {
		return nil, err
	}

	// Count unread
	var unreadCount int64
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Count(&unreadCount)

	return &models.NotificationListResponse{
		Notifications: notifications,
		Total:         total,
		Page:          page,
		PageSize:      pageSize,
		UnreadCount:   unreadCount,
	}, nil
}

// MarkNotificationsRead marks notifications as read
func (s *NotificationService) MarkNotificationsRead(ctx context.Context, tenantID, userID uuid.UUID, notificationIDs []uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND id IN ?", tenantID, userID, notificationIDs).
		Updates(map[string]interface{}{
			"read_at":    now,
			"status":     models.NotificationStatusRead,
			"updated_at": now,
		}).Error
}

// MarkAllRead marks all user notifications as read
func (s *NotificationService) MarkAllRead(ctx context.Context, tenantID, userID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Updates(map[string]interface{}{
			"read_at":    now,
			"status":     models.NotificationStatusRead,
			"updated_at": now,
		}).Error
}

// GetNotificationCounts returns notification counts for a user
func (s *NotificationService) GetNotificationCounts(ctx context.Context, tenantID, userID uuid.UUID) (*models.NotificationCountResponse, error) {
	var total, unread int64

	s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Count(&total)

	s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Count(&unread)

	// Count by category
	byCategory := make(map[models.NotificationCategory]int64)
	var categoryResults []struct {
		Category models.NotificationCategory
		Count    int64
	}
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Select("category, COUNT(*) as count").
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Group("category").
		Scan(&categoryResults)
	for _, r := range categoryResults {
		byCategory[r.Category] = r.Count
	}

	// Count by priority
	byPriority := make(map[models.NotificationPriority]int64)
	var priorityResults []struct {
		Priority models.NotificationPriority
		Count    int64
	}
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Select("priority, COUNT(*) as count").
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Group("priority").
		Scan(&priorityResults)
	for _, r := range priorityResults {
		byPriority[r.Priority] = r.Count
	}

	return &models.NotificationCountResponse{
		Total:      total,
		Unread:     unread,
		ByCategory: byCategory,
		ByPriority: byPriority,
	}, nil
}

// GetUserPreferences returns notification preferences for a user
// Returns a slice for API consistency (will contain 0 or 1 item since there's one record per user)
func (s *NotificationService) GetUserPreferences(ctx context.Context, tenantID, userID uuid.UUID) ([]models.NotificationPreference, error) {
	var preferences []models.NotificationPreference
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Find(&preferences).Error
	return preferences, err
}

// UpdateUserPreferences updates notification preferences
// Uses upsert pattern: creates if not exists, updates if exists
func (s *NotificationService) UpdateUserPreferences(ctx context.Context, tenantID, userID uuid.UUID, req *models.UpdatePreferencesRequest) (*models.NotificationPreference, error) {
	var pref models.NotificationPreference
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		First(&pref).Error

	if err == gorm.ErrRecordNotFound {
		// Create new preference with defaults
		pref = models.NotificationPreference{
			TenantID: tenantID,
			UserID:   userID,
			Channels: models.ChannelSettings{
				InApp:    true,
				Push:     true,
				Email:    true,
				SMS:      false,
				WhatsApp: false,
			},
			AlertTypes: models.AlertTypeSettings{
				LowStock:           true,
				CashShortage:       true,
				AuditReminder:      true,
				BudgetExceeded:     true,
				CollectionOverdue:  true,
				InventoryShrinkage: true,
				SuspiciousActivity: true,
			},
			Categories: models.CategorySettings{
				Sales:     true,
				Inventory: true,
				Finance:   true,
				Security:  true,
				System:    true,
			},
			Reminders:               models.ReminderSlice{},
			MinimumSeverity:         "info",
			QuietHoursEnabled:       false,
			QuietHoursStart:         "22:00:00",
			QuietHoursEnd:           "07:00:00",
			QuietHoursExceptions:    models.StringSlice{"critical"},
			DigestMode:              false,
			DigestFrequency:         "daily",
			MaxNotificationsPerHour: 10,
			PushTokens:              models.StringSlice{},
			CreatedAt:               time.Now(),
		}
	} else if err != nil {
		return nil, err
	}

	// Update channels if provided as object
	if req.Channels != nil {
		pref.Channels = *req.Channels
	}

	// Update individual channel toggles (backward compatibility)
	if req.InAppEnabled != nil {
		pref.Channels.InApp = *req.InAppEnabled
	}
	if req.PushEnabled != nil {
		pref.Channels.Push = *req.PushEnabled
	}
	if req.EmailEnabled != nil {
		pref.Channels.Email = *req.EmailEnabled
	}
	if req.SMSEnabled != nil {
		pref.Channels.SMS = *req.SMSEnabled
	}
	if req.WhatsAppEnabled != nil {
		pref.Channels.WhatsApp = *req.WhatsAppEnabled
	}

	// Update alert types if provided
	if req.AlertTypes != nil {
		pref.AlertTypes = *req.AlertTypes
	}

	// Update categories if provided
	if req.Categories != nil {
		pref.Categories = *req.Categories
	}

	// Update reminders if provided
	if req.Reminders != nil {
		pref.Reminders = *req.Reminders
	}

	// Update severity and quiet hours
	if req.MinimumSeverity != nil {
		pref.MinimumSeverity = *req.MinimumSeverity
	}
	if req.QuietHoursEnabled != nil {
		pref.QuietHoursEnabled = *req.QuietHoursEnabled
	}
	if req.QuietHoursStart != nil {
		pref.QuietHoursStart = *req.QuietHoursStart
	}
	if req.QuietHoursEnd != nil {
		pref.QuietHoursEnd = *req.QuietHoursEnd
	}
	if req.QuietHoursExceptions != nil {
		pref.QuietHoursExceptions = req.QuietHoursExceptions
	}

	// Update digest settings
	if req.DigestMode != nil {
		pref.DigestMode = *req.DigestMode
	}
	if req.DigestFrequency != nil {
		pref.DigestFrequency = *req.DigestFrequency
	}

	// Update rate limiting
	if req.MaxNotificationsPerHour != nil {
		pref.MaxNotificationsPerHour = *req.MaxNotificationsPerHour
	}

	pref.UpdatedAt = time.Now()

	if err := s.db.WithContext(ctx).Save(&pref).Error; err != nil {
		return nil, err
	}
	return &pref, nil
}

// GetTemplateByCode retrieves a notification template by code
func (s *NotificationService) GetTemplateByCode(ctx context.Context, code string) (*models.NotificationTemplate, error) {
	var template models.NotificationTemplate
	err := s.db.WithContext(ctx).
		Where("code = ? AND is_active = true", code).
		First(&template).Error
	return &template, err
}

// CreateTemplate creates a new notification template
func (s *NotificationService) CreateTemplate(ctx context.Context, tenantID *uuid.UUID, req *models.CreateTemplateRequest) (*models.NotificationTemplate, error) {
	template := &models.NotificationTemplate{
		TenantID:           tenantID,
		Name:               req.Name,
		Code:               req.Code,
		Category:           req.Category,
		DefaultPriority:    req.DefaultPriority,
		TitleTemplate:      req.TitleTemplate,
		BodyTemplate:       req.BodyTemplate,
		EmailSubject:       req.EmailSubject,
		EmailBody:          req.EmailBody,
		SMSTemplate:        req.SMSTemplate,
		WhatsAppTemplate:   req.WhatsAppTemplate,
		WhatsAppTemplateID: req.WhatsAppTemplateID,
		Variables:          req.Variables,
		IsSystem:           false,
		IsActive:           true,
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	if err := s.db.WithContext(ctx).Create(template).Error; err != nil {
		return nil, err
	}
	return template, nil
}

// SendDigests processes and sends digest notifications
func (s *NotificationService) SendDigests(ctx context.Context, frequency models.DigestFrequency) error {
	// Find all pending digests for this frequency
	var digests []models.NotificationDigest
	if err := s.db.WithContext(ctx).
		Where("digest_frequency = ? AND status = 'pending' AND period_end <= ?", frequency, time.Now()).
		Find(&digests).Error; err != nil {
		return err
	}

	for _, digest := range digests {
		// Load notifications for this digest
		var notifications []models.Notification
		s.db.WithContext(ctx).
			Where("digest_id = ?", digest.ID).
			Find(&notifications)

		if len(notifications) == 0 {
			continue
		}

		// Group by category
		categories := make(map[models.NotificationCategory]int)
		for _, n := range notifications {
			categories[n.Category]++
		}

		// Create digest summary notification
		summaryReq := &models.SendNotificationRequest{
			UserID:   digest.UserID,
			Category: models.NotificationCategorySystem,
			Priority: models.NotificationPriorityNormal,
			Title:    fmt.Sprintf("You have %d notifications", len(notifications)),
			Body:     s.buildDigestBody(categories),
		}

		// Send digest without digest mode
		preferences, _ := s.GetUserPreferences(ctx, digest.TenantID, digest.UserID)
		pref := findPreference(preferences, models.NotificationCategorySystem)
		channels := s.determineChannels(nil, pref, summaryReq.Priority)

		digestNotification := &models.Notification{
			TenantID:  digest.TenantID,
			UserID:    digest.UserID,
			Category:  summaryReq.Category,
			Priority:  summaryReq.Priority,
			Title:     summaryReq.Title,
			Body:      summaryReq.Body,
			Status:    models.NotificationStatusPending,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		s.db.WithContext(ctx).Create(digestNotification)

		for _, ch := range channels {
			s.sendThroughChannel(ctx, digestNotification, ch)
		}

		// Mark digest as sent
		digest.Status = "sent"
		digest.SentAt = &time.Time{}
		*digest.SentAt = time.Now()
		s.db.WithContext(ctx).Save(&digest)
	}

	return nil
}

// Internal helpers

func (s *NotificationService) sendThroughChannel(ctx context.Context, notification *models.Notification, channel models.NotificationChannel) {
	// For push notifications, send to ALL user's active devices
	if channel == models.NotificationChannelPush {
		s.sendPushToAllDevices(ctx, notification)
		return
	}

	s.channelsMu.RLock()
	provider, exists := s.channels[channel]
	s.channelsMu.RUnlock()

	if !exists || !provider.IsEnabled() {
		return
	}

	// Get recipient address for channel
	recipient := s.getRecipientForChannel(ctx, notification.TenantID, notification.UserID, channel)
	if recipient == "" {
		return
	}

	// Check rate limit
	if !s.checkRateLimit(ctx, notification.TenantID, notification.UserID, channel) {
		return
	}

	// Create delivery record
	delivery := &models.NotificationDelivery{
		TenantID:       notification.TenantID,
		NotificationID: notification.ID,
		Channel:        channel,
		Status:         models.DeliveryStatusPending,
		Recipient:      recipient,
		Provider:       provider.GetName(),
		AttemptCount:   1,
		LastAttemptAt:  &time.Time{},
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}
	*delivery.LastAttemptAt = time.Now()

	s.db.WithContext(ctx).Create(delivery)

	// Send
	result, err := provider.Send(ctx, notification, recipient)
	if err != nil {
		delivery.Status = models.DeliveryStatusFailed
		delivery.ErrorMessage = err.Error()
		delivery.FailedAt = &time.Time{}
		*delivery.FailedAt = time.Now()
	} else {
		delivery.Status = models.DeliveryStatusSent
		delivery.SentAt = &time.Time{}
		*delivery.SentAt = time.Now()
		if result != nil {
			delivery.ExternalID = result.ExternalID
			delivery.Metadata = result.Metadata
		}
	}
	delivery.UpdatedAt = time.Now()
	s.db.WithContext(ctx).Save(delivery)

	// Update rate limit
	s.incrementRateLimit(ctx, notification.TenantID, notification.UserID, channel)
}

// sendPushToAllDevices sends push notification to all user's active devices
func (s *NotificationService) sendPushToAllDevices(ctx context.Context, notification *models.Notification) {
	// Get all active devices for the user
	var devices []models.NotificationDevice
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND is_active = true", notification.TenantID, notification.UserID).
		Find(&devices).Error; err != nil {
		return
	}

	if len(devices) == 0 {
		return
	}

	s.channelsMu.RLock()
	provider, exists := s.channels[models.NotificationChannelPush]
	s.channelsMu.RUnlock()

	if !exists || !provider.IsEnabled() {
		return
	}

	// Check rate limit (once per user, not per device)
	if !s.checkRateLimit(ctx, notification.TenantID, notification.UserID, models.NotificationChannelPush) {
		return
	}

	// Send to each device
	for _, device := range devices {
		now := time.Now()
		delivery := &models.NotificationDelivery{
			TenantID:       notification.TenantID,
			NotificationID: notification.ID,
			Channel:        models.NotificationChannelPush,
			Status:         models.DeliveryStatusPending,
			Recipient:      device.FCMToken,
			Provider:       provider.GetName(),
			AttemptCount:   1,
			LastAttemptAt:  &now,
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		s.db.WithContext(ctx).Create(delivery)

		result, err := provider.Send(ctx, notification, device.FCMToken)
		if err != nil {
			delivery.Status = models.DeliveryStatusFailed
			delivery.ErrorMessage = err.Error()
			failedAt := time.Now()
			delivery.FailedAt = &failedAt

			// Mark token as invalid if FCM reports it as unregistered
			if strings.Contains(err.Error(), "NotRegistered") || strings.Contains(err.Error(), "InvalidRegistration") {
				device.IsActive = false
				s.db.WithContext(ctx).Save(&device)
			}
		} else {
			delivery.Status = models.DeliveryStatusSent
			sentAt := time.Now()
			delivery.SentAt = &sentAt
			if result != nil {
				delivery.ExternalID = result.ExternalID
				delivery.Metadata = result.Metadata
			}
		}
		delivery.UpdatedAt = time.Now()
		s.db.WithContext(ctx).Save(delivery)
	}

	// Update rate limit (once for all devices)
	s.incrementRateLimit(ctx, notification.TenantID, notification.UserID, models.NotificationChannelPush)
}

func (s *NotificationService) getRecipientForChannel(ctx context.Context, tenantID, userID uuid.UUID, channel models.NotificationChannel) string {
	var user models.User
	if err := s.db.WithContext(ctx).First(&user, "id = ?", userID).Error; err != nil {
		return ""
	}

	switch channel {
	case models.NotificationChannelEmail:
		return user.Email
	case models.NotificationChannelSMS:
		if user.Phone != "" {
			return user.Phone
		}
	case models.NotificationChannelWhatsApp:
		var subscription models.WhatsAppSubscription
		if err := s.db.WithContext(ctx).
			Where("tenant_id = ? AND user_id = ? AND is_verified = true", tenantID, userID).
			First(&subscription).Error; err == nil {
			return subscription.PhoneNumber
		}
	case models.NotificationChannelPush:
		// Get FCM token from notification_devices table
		var device models.NotificationDevice
		if err := s.db.WithContext(ctx).
			Where("tenant_id = ? AND user_id = ? AND is_active = true", tenantID, userID).
			Order("last_used_at DESC").
			First(&device).Error; err == nil {
			return device.FCMToken
		}
		return ""
	case models.NotificationChannelInApp:
		return userID.String()
	}
	return ""
}

func (s *NotificationService) checkRateLimit(ctx context.Context, tenantID, userID uuid.UUID, channel models.NotificationChannel) bool {
	var rateLimit models.NotificationRateLimit
	now := time.Now()

	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND channel = ? AND window_start <= ? AND window_end >= ?",
			tenantID, userID, channel, now, now).
		First(&rateLimit).Error

	if err == gorm.ErrRecordNotFound {
		return true
	}
	if err != nil {
		return true // Allow on error
	}

	return rateLimit.Count < rateLimit.Limit
}

func (s *NotificationService) incrementRateLimit(ctx context.Context, tenantID, userID uuid.UUID, channel models.NotificationChannel) {
	now := time.Now()
	windowStart := now.Truncate(time.Hour)
	windowEnd := windowStart.Add(time.Hour)

	var rateLimit models.NotificationRateLimit
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND channel = ? AND window_start = ?",
			tenantID, userID, channel, windowStart).
		First(&rateLimit).Error

	if err == gorm.ErrRecordNotFound {
		// Get limit based on channel
		limit := 100 // Default
		switch channel {
		case models.NotificationChannelSMS:
			limit = 10
		case models.NotificationChannelWhatsApp:
			limit = 20
		case models.NotificationChannelEmail:
			limit = 50
		}

		rateLimit = models.NotificationRateLimit{
			TenantID:    tenantID,
			UserID:      userID,
			Channel:     channel,
			WindowStart: windowStart,
			WindowEnd:   windowEnd,
			Count:       1,
			Limit:       limit,
			CreatedAt:   now,
			UpdatedAt:   now,
		}
		s.db.WithContext(ctx).Create(&rateLimit)
	} else if err == nil {
		s.db.WithContext(ctx).Model(&rateLimit).
			Update("count", gorm.Expr("count + 1")).
			Update("updated_at", now)
	}
}

func (s *NotificationService) determineChannels(requested []models.NotificationChannel, pref *models.NotificationPreference, priority models.NotificationPriority) []models.NotificationChannel {
	var channels []models.NotificationChannel

	// If specific channels requested, use those
	if len(requested) > 0 {
		return requested
	}

	// Use preferences
	if pref == nil {
		// Default to in-app and push
		return []models.NotificationChannel{models.NotificationChannelInApp, models.NotificationChannelPush}
	}

	// Check priority threshold (convert string to NotificationPriority)
	if !meetsPriorityThreshold(priority, models.NotificationPriority(pref.MinimumSeverity)) {
		return nil
	}

	if pref.Channels.InApp {
		channels = append(channels, models.NotificationChannelInApp)
	}
	if pref.Channels.Push {
		channels = append(channels, models.NotificationChannelPush)
	}
	if pref.Channels.Email {
		channels = append(channels, models.NotificationChannelEmail)
	}
	if pref.Channels.SMS {
		channels = append(channels, models.NotificationChannelSMS)
	}
	if pref.Channels.WhatsApp {
		channels = append(channels, models.NotificationChannelWhatsApp)
	}

	return channels
}

func (s *NotificationService) addToDigest(ctx context.Context, notification *models.Notification, pref *models.NotificationPreference) (*models.Notification, error) {
	// Find or create digest
	now := time.Now()
	var periodStart, periodEnd time.Time

	// DigestFrequency is now a string in the database
	switch pref.DigestFrequency {
	case "hourly":
		periodStart = now.Truncate(time.Hour)
		periodEnd = periodStart.Add(time.Hour)
	case "daily":
		periodStart = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
		periodEnd = periodStart.Add(24 * time.Hour)
	case "weekly":
		periodStart = time.Date(now.Year(), now.Month(), now.Day()-int(now.Weekday()), 0, 0, 0, 0, now.Location())
		periodEnd = periodStart.Add(7 * 24 * time.Hour)
	default:
		periodStart = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
		periodEnd = periodStart.Add(24 * time.Hour)
	}

	var digest models.NotificationDigest
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND digest_frequency = ? AND period_start = ? AND status = 'pending'",
			notification.TenantID, notification.UserID, pref.DigestFrequency, periodStart).
		First(&digest).Error

	if err == gorm.ErrRecordNotFound {
		digest = models.NotificationDigest{
			TenantID:          notification.TenantID,
			UserID:            notification.UserID,
			DigestFrequency:   models.DigestFrequency(pref.DigestFrequency),
			PeriodStart:       periodStart,
			PeriodEnd:         periodEnd,
			NotificationCount: 0,
			Status:            "pending",
			CreatedAt:         now,
		}
		s.db.WithContext(ctx).Create(&digest)
	}

	notification.DigestID = &digest.ID
	notification.Status = models.NotificationStatusPending

	if err := s.db.WithContext(ctx).Create(notification).Error; err != nil {
		return nil, err
	}

	// Update digest count
	s.db.WithContext(ctx).Model(&digest).
		Update("notification_count", gorm.Expr("notification_count + 1"))

	return notification, nil
}

func (s *NotificationService) renderTemplate(tmpl *models.NotificationTemplate, data map[string]interface{}) (string, string, error) {
	titleTmpl, err := template.New("title").Parse(tmpl.TitleTemplate)
	if err != nil {
		return "", "", err
	}

	bodyTmpl, err := template.New("body").Parse(tmpl.BodyTemplate)
	if err != nil {
		return "", "", err
	}

	var titleBuf, bodyBuf strings.Builder
	if err := titleTmpl.Execute(&titleBuf, data); err != nil {
		return "", "", err
	}
	if err := bodyTmpl.Execute(&bodyBuf, data); err != nil {
		return "", "", err
	}

	return titleBuf.String(), bodyBuf.String(), nil
}

func (s *NotificationService) buildDigestBody(categories map[models.NotificationCategory]int) string {
	var parts []string
	for cat, count := range categories {
		parts = append(parts, fmt.Sprintf("%d %s", count, cat))
	}
	return strings.Join(parts, ", ")
}

// findPreference returns the user's preference (now there's only one per user, category parameter is ignored)
func findPreference(preferences []models.NotificationPreference, category models.NotificationCategory) *models.NotificationPreference {
	if len(preferences) > 0 {
		return &preferences[0]
	}
	return nil
}

func meetsPriorityThreshold(priority, threshold models.NotificationPriority) bool {
	priorityOrder := map[models.NotificationPriority]int{
		models.NotificationPriorityLow:      1,
		models.NotificationPriorityNormal:   2,
		models.NotificationPriorityHigh:     3,
		models.NotificationPriorityCritical: 4,
	}
	return priorityOrder[priority] >= priorityOrder[threshold]
}

// WhatsApp specific methods

// InitiateWhatsAppOptIn starts WhatsApp verification
func (s *NotificationService) InitiateWhatsAppOptIn(ctx context.Context, tenantID, userID uuid.UUID, phoneNumber string) (*models.WhatsAppSubscription, error) {
	// Generate verification code
	code := generateVerificationCode()
	expiry := time.Now().Add(15 * time.Minute)

	subscription := &models.WhatsAppSubscription{
		TenantID:           tenantID,
		UserID:             userID,
		PhoneNumber:        phoneNumber,
		IsVerified:         false,
		VerificationCode:   code,
		VerificationExpiry: &expiry,
		Status:             "pending_verification",
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	if err := s.db.WithContext(ctx).Create(subscription).Error; err != nil {
		return nil, err
	}

	// Send verification code via WhatsApp
	// This would call the WhatsApp provider

	return subscription, nil
}

// VerifyWhatsAppOptIn verifies WhatsApp number
func (s *NotificationService) VerifyWhatsAppOptIn(ctx context.Context, tenantID, userID uuid.UUID, code string) error {
	var subscription models.WhatsAppSubscription
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND verification_code = ? AND verification_expiry > ?",
			tenantID, userID, code, time.Now()).
		First(&subscription).Error; err != nil {
		return fmt.Errorf("invalid or expired verification code")
	}

	now := time.Now()
	subscription.IsVerified = true
	subscription.OptInAt = &now
	subscription.Status = "active"
	subscription.UpdatedAt = now

	return s.db.WithContext(ctx).Save(&subscription).Error
}

// OptOutWhatsApp opts out of WhatsApp notifications
func (s *NotificationService) OptOutWhatsApp(ctx context.Context, tenantID, userID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.WhatsAppSubscription{}).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Updates(map[string]interface{}{
			"is_verified": false,
			"opt_out_at":  now,
			"status":      "opted_out",
			"updated_at":  now,
		}).Error
}

func generateVerificationCode() string {
	// Generate 6-digit code
	return fmt.Sprintf("%06d", time.Now().UnixNano()%1000000)
}

// =====================================================
// Device Management Methods (Frontend Alignment)
// =====================================================

// RegisterDevice registers an FCM token for push notifications
func (s *NotificationService) RegisterDevice(ctx context.Context, tenantID, userID uuid.UUID, req *models.RegisterDeviceRequest) error {
	now := time.Now()

	// Check if device already exists for this user
	var existingDevice models.NotificationDevice
	err := s.db.WithContext(ctx).
		Where("user_id = ? AND device_id = ?", userID, req.DeviceID).
		First(&existingDevice).Error

	if err == nil {
		// Update existing device
		existingDevice.FCMToken = req.FCMToken
		existingDevice.Platform = req.Platform
		existingDevice.DeviceName = req.DeviceName
		existingDevice.AppVersion = req.AppVersion
		existingDevice.IsActive = true
		existingDevice.LastUsedAt = &now
		existingDevice.UpdatedAt = now
		return s.db.WithContext(ctx).Save(&existingDevice).Error
	}

	if err != gorm.ErrRecordNotFound {
		return fmt.Errorf("failed to check existing device: %w", err)
	}

	// Check if FCM token exists for different device (token reuse)
	// If so, deactivate the old device
	s.db.WithContext(ctx).Model(&models.NotificationDevice{}).
		Where("fcm_token = ? AND device_id != ?", req.FCMToken, req.DeviceID).
		Updates(map[string]interface{}{
			"is_active":   false,
			"updated_at":  now,
		})

	// Create new device
	device := &models.NotificationDevice{
		UserID:     userID,
		TenantID:   tenantID,
		FCMToken:   req.FCMToken,
		DeviceID:   req.DeviceID,
		Platform:   req.Platform,
		DeviceName: req.DeviceName,
		AppVersion: req.AppVersion,
		IsActive:   true,
		LastUsedAt: &now,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	return s.db.WithContext(ctx).Create(device).Error
}

// UnregisterDevice removes an FCM token (called on logout)
func (s *NotificationService) UnregisterDevice(ctx context.Context, tenantID, userID uuid.UUID, fcmToken string) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.NotificationDevice{}).
		Where("tenant_id = ? AND user_id = ? AND fcm_token = ?", tenantID, userID, fcmToken).
		Updates(map[string]interface{}{
			"is_active":  false,
			"updated_at": now,
		}).Error
}

// GetUserDevices returns all active devices for a user
func (s *NotificationService) GetUserDevices(ctx context.Context, tenantID, userID uuid.UUID) ([]models.NotificationDevice, error) {
	var devices []models.NotificationDevice
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND is_active = true", tenantID, userID).
		Order("last_used_at DESC").
		Find(&devices).Error
	return devices, err
}

// GetUnreadCount returns just the unread notification count
func (s *NotificationService) GetUnreadCount(ctx context.Context, tenantID, userID uuid.UUID) (int64, error) {
	var count int64
	err := s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Count(&count).Error
	return count, err
}

// DeleteNotification soft deletes a single notification
func (s *NotificationService) DeleteNotification(ctx context.Context, tenantID, userID uuid.UUID, notificationID uuid.UUID) error {
	result := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ? AND id = ?", tenantID, userID, notificationID).
		Delete(&models.Notification{})

	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("notification not found")
	}
	return nil
}

// ClearAllNotifications deletes all notifications for a user
func (s *NotificationService) ClearAllNotifications(ctx context.Context, tenantID, userID uuid.UUID) error {
	return s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		Delete(&models.Notification{}).Error
}

// MarkSingleNotificationRead marks a single notification as read
func (s *NotificationService) MarkSingleNotificationRead(ctx context.Context, tenantID, userID uuid.UUID, notificationID uuid.UUID) error {
	now := time.Now()
	result := s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND id = ?", tenantID, userID, notificationID).
		Updates(map[string]interface{}{
			"read_at":    now,
			"status":     models.NotificationStatusRead,
			"updated_at": now,
		})

	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("notification not found")
	}
	return nil
}

// GetChannelStatus returns the status of all notification channels
func (s *NotificationService) GetChannelStatus(ctx context.Context, tenantID uuid.UUID) []models.ChannelStatusInfo {
	s.channelsMu.RLock()
	defer s.channelsMu.RUnlock()

	channelDescriptions := map[models.NotificationChannel]string{
		models.NotificationChannelPush:     "Firebase Cloud Messaging",
		models.NotificationChannelEmail:    "Email via SMTP/SendGrid",
		models.NotificationChannelSMS:      "SMS via Twilio/MSG91",
		models.NotificationChannelWhatsApp: "WhatsApp Business API",
		models.NotificationChannelInApp:    "In-App Notifications",
	}

	allChannels := []models.NotificationChannel{
		models.NotificationChannelPush,
		models.NotificationChannelEmail,
		models.NotificationChannelSMS,
		models.NotificationChannelWhatsApp,
		models.NotificationChannelInApp,
	}

	var statuses []models.ChannelStatusInfo
	for _, ch := range allChannels {
		provider, exists := s.channels[ch]

		status := models.ChannelStatusInfo{
			Name:         string(ch),
			Description:  channelDescriptions[ch],
			IsConfigured: exists,
			IsEnabled:    exists && provider.IsEnabled(),
		}

		// Get delivery stats for this channel
		if exists {
			var successCount, failureCount int64
			s.db.Model(&models.NotificationDelivery{}).
				Where("tenant_id = ? AND channel = ? AND status = 'delivered'", tenantID, ch).
				Count(&successCount)
			s.db.Model(&models.NotificationDelivery{}).
				Where("tenant_id = ? AND channel = ? AND status = 'failed'", tenantID, ch).
				Count(&failureCount)

			status.SuccessCount = successCount
			status.FailureCount = failureCount

			// Get last success time
			var lastDelivery models.NotificationDelivery
			if err := s.db.Where("tenant_id = ? AND channel = ? AND status = 'delivered'", tenantID, ch).
				Order("delivered_at DESC").First(&lastDelivery).Error; err == nil {
				status.LastSuccessAt = lastDelivery.DeliveredAt
			}

			// Get last error
			var lastFailed models.NotificationDelivery
			if err := s.db.Where("tenant_id = ? AND channel = ? AND status = 'failed'", tenantID, ch).
				Order("failed_at DESC").First(&lastFailed).Error; err == nil {
				status.LastError = &lastFailed.ErrorMessage
			}
		}

		statuses = append(statuses, status)
	}

	return statuses
}

// GetUserNotificationsV2 returns notifications in frontend-aligned format
func (s *NotificationService) GetUserNotificationsV2(ctx context.Context, tenantID, userID uuid.UUID, page, pageSize int, category string, unreadOnly bool) (*models.NotificationListResponseV2, error) {
	var notifications []models.Notification
	var total int64

	query := s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID)

	if category != "" {
		query = query.Where("category = ?", category)
	}
	if unreadOnly {
		query = query.Where("read_at IS NULL")
	}

	// Count total
	query.Count(&total)

	// Fetch page
	offset := (page - 1) * pageSize
	if err := query.Order("created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&notifications).Error; err != nil {
		return nil, err
	}

	// Count unread
	var unreadCount int64
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", tenantID, userID).
		Count(&unreadCount)

	// Calculate has_more
	hasMore := int64(offset+len(notifications)) < total

	response := &models.NotificationListResponseV2{
		Success: true,
	}
	response.Data.Notifications = notifications
	response.Data.TotalCount = total
	response.Data.UnreadCount = unreadCount
	response.Data.Page = page
	response.Data.PageSize = pageSize
	response.Data.HasMore = hasMore

	return response, nil
}

// GetNotificationStats returns notification statistics
func (s *NotificationService) GetNotificationStats(ctx context.Context, tenantID uuid.UUID, startDate, endDate time.Time) (*models.NotificationStats, error) {
	stats := &models.NotificationStats{
		ByChannel:  make(map[models.NotificationChannel]models.ChannelStats),
		ByCategory: make(map[models.NotificationCategory]int64),
	}

	// Total sent
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Count(&stats.TotalSent)

	// Total delivered
	s.db.WithContext(ctx).Model(&models.NotificationDelivery{}).
		Where("tenant_id = ? AND status = 'delivered' AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Count(&stats.TotalDelivered)

	// Total read
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Where("tenant_id = ? AND read_at IS NOT NULL AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Count(&stats.TotalRead)

	// Total failed
	s.db.WithContext(ctx).Model(&models.NotificationDelivery{}).
		Where("tenant_id = ? AND status = 'failed' AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Count(&stats.TotalFailed)

	// Rates
	if stats.TotalSent > 0 {
		stats.DeliveryRate = float64(stats.TotalDelivered) / float64(stats.TotalSent) * 100
		stats.ReadRate = float64(stats.TotalRead) / float64(stats.TotalSent) * 100
	}

	// By channel
	var channelResults []struct {
		Channel   models.NotificationChannel
		Status    models.DeliveryStatus
		Count     int64
		AvgTime   float64
	}
	s.db.WithContext(ctx).Model(&models.NotificationDelivery{}).
		Select("channel, status, COUNT(*) as count, AVG(EXTRACT(EPOCH FROM (sent_at - created_at))) as avg_time").
		Where("tenant_id = ? AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("channel, status").
		Scan(&channelResults)

	for _, r := range channelResults {
		cs := stats.ByChannel[r.Channel]
		switch r.Status {
		case models.DeliveryStatusSent:
			cs.Sent = r.Count
		case models.DeliveryStatusDelivered:
			cs.Delivered = r.Count
			cs.AvgDeliveryTime = r.AvgTime
		case models.DeliveryStatusFailed:
			cs.Failed = r.Count
		}
		stats.ByChannel[r.Channel] = cs
	}

	// By category
	var categoryResults []struct {
		Category models.NotificationCategory
		Count    int64
	}
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Select("category, COUNT(*) as count").
		Where("tenant_id = ? AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("category").
		Scan(&categoryResults)
	for _, r := range categoryResults {
		stats.ByCategory[r.Category] = r.Count
	}

	// Daily trend
	s.db.WithContext(ctx).Model(&models.Notification{}).
		Select("DATE(created_at) as date, COUNT(*) as sent, SUM(CASE WHEN read_at IS NOT NULL THEN 1 ELSE 0 END) as read").
		Where("tenant_id = ? AND created_at BETWEEN ? AND ?", tenantID, startDate, endDate).
		Group("DATE(created_at)").
		Order("date").
		Scan(&stats.DailyTrend)

	return stats, nil
}
