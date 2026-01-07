package services

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// MockChannelProvider mocks a notification channel provider
type MockChannelProvider struct {
	mock.Mock
	name    string
	enabled bool
}

func NewMockChannelProvider(name string, enabled bool) *MockChannelProvider {
	return &MockChannelProvider{name: name, enabled: enabled}
}

func (m *MockChannelProvider) Send(ctx context.Context, notification *models.Notification, recipient string) (*models.NotificationDelivery, error) {
	args := m.Called(ctx, notification, recipient)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.NotificationDelivery), args.Error(1)
}

func (m *MockChannelProvider) GetName() string {
	return m.name
}

func (m *MockChannelProvider) IsEnabled() bool {
	return m.enabled
}

// NotificationServiceTestSuite is the test suite for NotificationService
type NotificationServiceTestSuite struct {
	suite.Suite
	db       *gorm.DB
	service  *NotificationService
	tenantID uuid.UUID
	userID   uuid.UUID
}

// SetupTest runs before each test
func (s *NotificationServiceTestSuite) SetupTest() {
	// Create in-memory SQLite database
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	s.Require().NoError(err)

	// Auto-migrate required tables
	err = db.AutoMigrate(
		&models.Notification{},
		&models.NotificationDelivery{},
		&models.NotificationPreference{},
		&models.NotificationDevice{},
		&models.NotificationTemplate{},
		&models.NotificationDigest{},
	)
	s.Require().NoError(err)

	// Create service with mock database wrapper
	s.db = db
	s.service = &NotificationService{
		channels:  make(map[models.NotificationChannel]ChannelProvider),
		templates: make(map[string]*interface{}),
	}

	// Set up test IDs
	s.tenantID = uuid.New()
	s.userID = uuid.New()
}

// TearDownTest runs after each test
func (s *NotificationServiceTestSuite) TearDownTest() {
	sqlDB, _ := s.db.DB()
	if sqlDB != nil {
		sqlDB.Close()
	}
}

// TestNotificationServiceTestSuite runs the test suite
func TestNotificationServiceTestSuite(t *testing.T) {
	suite.Run(t, new(NotificationServiceTestSuite))
}

// =============================================================================
// Notification Creation Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestCreateNotification() {
	// Create a notification directly in DB
	notification := &models.Notification{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategorySystem,
		Priority:  models.NotificationPriorityNormal,
		Title:     "Test Notification",
		Body:      "This is a test notification body",
		Status:    models.NotificationStatusPending,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	err := s.db.Create(notification).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, notification.ID)
}

func (s *NotificationServiceTestSuite) TestGetNotificationsByUser() {
	// Create multiple notifications
	for i := 0; i < 5; i++ {
		notification := &models.Notification{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  models.NotificationCategorySystem,
			Priority:  models.NotificationPriorityNormal,
			Title:     "Test Notification",
			Body:      "Body",
			Status:    models.NotificationStatusSent,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		s.db.Create(notification)
	}

	// Query notifications
	var notifications []models.Notification
	err := s.db.Where("tenant_id = ? AND user_id = ?", s.tenantID, s.userID).Find(&notifications).Error
	s.Require().NoError(err)
	s.Assert().Len(notifications, 5)
}

func (s *NotificationServiceTestSuite) TestGetUnreadNotifications() {
	// Create mix of read and unread
	now := time.Now()
	readTime := now.Add(-1 * time.Hour)

	// Unread notifications
	for i := 0; i < 3; i++ {
		s.db.Create(&models.Notification{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  models.NotificationCategorySystem,
			Priority:  models.NotificationPriorityNormal,
			Title:     "Unread",
			Status:    models.NotificationStatusSent,
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// Read notifications
	for i := 0; i < 2; i++ {
		s.db.Create(&models.Notification{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  models.NotificationCategorySystem,
			Priority:  models.NotificationPriorityNormal,
			Title:     "Read",
			Status:    models.NotificationStatusRead,
			ReadAt:    &readTime,
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// Query unread only
	var unread []models.Notification
	err := s.db.Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", s.tenantID, s.userID).Find(&unread).Error
	s.Require().NoError(err)
	s.Assert().Len(unread, 3)
}

// =============================================================================
// Mark Read Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestMarkAsRead() {
	// Create notification
	notification := &models.Notification{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategorySystem,
		Priority:  models.NotificationPriorityNormal,
		Title:     "Test",
		Status:    models.NotificationStatusSent,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(notification)

	// Mark as read
	now := time.Now()
	err := s.db.Model(notification).Updates(map[string]interface{}{
		"read_at": now,
		"status":  models.NotificationStatusRead,
	}).Error
	s.Require().NoError(err)

	// Verify
	var updated models.Notification
	s.db.First(&updated, notification.ID)
	s.Assert().NotNil(updated.ReadAt)
	s.Assert().Equal(models.NotificationStatusRead, updated.Status)
}

func (s *NotificationServiceTestSuite) TestMarkAllAsRead() {
	// Create multiple unread notifications
	for i := 0; i < 5; i++ {
		s.db.Create(&models.Notification{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  models.NotificationCategorySystem,
			Priority:  models.NotificationPriorityNormal,
			Title:     "Unread",
			Status:    models.NotificationStatusSent,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		})
	}

	// Mark all as read
	now := time.Now()
	err := s.db.Model(&models.Notification{}).
		Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", s.tenantID, s.userID).
		Updates(map[string]interface{}{
			"read_at": now,
			"status":  models.NotificationStatusRead,
		}).Error
	s.Require().NoError(err)

	// Verify all are read
	var unread []models.Notification
	s.db.Where("tenant_id = ? AND user_id = ? AND read_at IS NULL", s.tenantID, s.userID).Find(&unread)
	s.Assert().Len(unread, 0)
}

// =============================================================================
// Device Registration Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestDeviceRegistration() {
	device := &models.NotificationDevice{
		TenantID:   s.tenantID,
		UserID:     s.userID,
		FCMToken:   "test_fcm_token_12345",
		DeviceID:   "device_001",
		Platform:   "android",
		DeviceName: "Test Phone",
		IsActive:   true,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	err := s.db.Create(device).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, device.ID)

	// Verify device saved
	var saved models.NotificationDevice
	s.db.First(&saved, device.ID)
	s.Assert().Equal("test_fcm_token_12345", saved.FCMToken)
	s.Assert().Equal("android", saved.Platform)
	s.Assert().True(saved.IsActive)
}

func (s *NotificationServiceTestSuite) TestDeviceDeactivation() {
	// Register device
	device := &models.NotificationDevice{
		TenantID:   s.tenantID,
		UserID:     s.userID,
		FCMToken:   "test_token",
		DeviceID:   "device_001",
		Platform:   "ios",
		IsActive:   true,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	s.db.Create(device)

	// Deactivate
	err := s.db.Model(device).Update("is_active", false).Error
	s.Require().NoError(err)

	// Verify
	var updated models.NotificationDevice
	s.db.First(&updated, device.ID)
	s.Assert().False(updated.IsActive)
}

func (s *NotificationServiceTestSuite) TestMultipleDevicesPerUser() {
	// Register multiple devices for same user
	devices := []models.NotificationDevice{
		{TenantID: s.tenantID, UserID: s.userID, FCMToken: "token1", DeviceID: "phone", Platform: "android", IsActive: true, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{TenantID: s.tenantID, UserID: s.userID, FCMToken: "token2", DeviceID: "tablet", Platform: "android", IsActive: true, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{TenantID: s.tenantID, UserID: s.userID, FCMToken: "token3", DeviceID: "ipad", Platform: "ios", IsActive: true, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}

	for _, d := range devices {
		s.db.Create(&d)
	}

	// Query all active devices
	var activeDevices []models.NotificationDevice
	s.db.Where("user_id = ? AND is_active = ?", s.userID, true).Find(&activeDevices)
	s.Assert().Len(activeDevices, 3)
}

// =============================================================================
// Preference Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestPreferenceCreation() {
	pref := &models.NotificationPreference{
		TenantID:   s.tenantID,
		UserID:     s.userID,
		Category:   models.NotificationCategorySales,
		InApp:      true,
		Push:       true,
		Email:      false,
		SMS:        false,
		WhatsApp:   false,
		DigestMode: false,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	err := s.db.Create(pref).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, pref.ID)
}

func (s *NotificationServiceTestSuite) TestPreferenceUpdate() {
	// Create preference
	pref := &models.NotificationPreference{
		TenantID:   s.tenantID,
		UserID:     s.userID,
		Category:   models.NotificationCategoryInventory,
		InApp:      true,
		Push:       false,
		DigestMode: false,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	s.db.Create(pref)

	// Update to enable push and digest
	err := s.db.Model(pref).Updates(map[string]interface{}{
		"push":        true,
		"digest_mode": true,
	}).Error
	s.Require().NoError(err)

	// Verify
	var updated models.NotificationPreference
	s.db.First(&updated, pref.ID)
	s.Assert().True(updated.Push)
	s.Assert().True(updated.DigestMode)
}

func (s *NotificationServiceTestSuite) TestMultiplePreferencesPerUser() {
	categories := []models.NotificationCategory{
		models.NotificationCategorySales,
		models.NotificationCategoryInventory,
		models.NotificationCategoryFinance,
		models.NotificationCategorySystem,
	}

	for _, cat := range categories {
		s.db.Create(&models.NotificationPreference{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  cat,
			InApp:     true,
			Push:      true,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		})
	}

	var prefs []models.NotificationPreference
	s.db.Where("user_id = ?", s.userID).Find(&prefs)
	s.Assert().Len(prefs, 4)
}

// =============================================================================
// Template Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestTemplateCreation() {
	template := &models.NotificationTemplate{
		TenantID:        &s.tenantID,
		Code:            "low_stock_alert",
		Name:            "Low Stock Alert",
		Category:        models.NotificationCategoryInventory,
		TitleTemplate:   "Low Stock: {{.ProductName}}",
		BodyTemplate:    "Product {{.ProductName}} is running low. Current stock: {{.Quantity}}",
		DefaultPriority: models.NotificationPriorityHigh,
		IsActive:        true,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	err := s.db.Create(template).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, template.ID)
}

func (s *NotificationServiceTestSuite) TestTemplateFindByCode() {
	// Create template
	template := &models.NotificationTemplate{
		TenantID:        nil, // Global template
		Code:            "settlement_reminder",
		Name:            "Settlement Reminder",
		Category:        models.NotificationCategoryFinance,
		TitleTemplate:   "Settlement Due",
		BodyTemplate:    "Please complete today's settlement",
		DefaultPriority: models.NotificationPriorityNormal,
		IsActive:        true,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	s.db.Create(template)

	// Find by code
	var found models.NotificationTemplate
	err := s.db.Where("code = ? AND is_active = ?", "settlement_reminder", true).First(&found).Error
	s.Require().NoError(err)
	s.Assert().Equal("Settlement Reminder", found.Name)
}

// =============================================================================
// Delivery Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestDeliveryTracking() {
	// Create notification
	notification := &models.Notification{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategorySystem,
		Priority:  models.NotificationPriorityNormal,
		Title:     "Test",
		Status:    models.NotificationStatusSent,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(notification)

	// Create delivery records
	now := time.Now()
	deliveries := []models.NotificationDelivery{
		{NotificationID: notification.ID, Channel: models.NotificationChannelInApp, Status: "delivered", DeliveredAt: &now, CreatedAt: time.Now()},
		{NotificationID: notification.ID, Channel: models.NotificationChannelPush, Status: "delivered", DeliveredAt: &now, ExternalID: "fcm_123", CreatedAt: time.Now()},
	}

	for _, d := range deliveries {
		s.db.Create(&d)
	}

	// Query deliveries
	var saved []models.NotificationDelivery
	s.db.Where("notification_id = ?", notification.ID).Find(&saved)
	s.Assert().Len(saved, 2)
}

func (s *NotificationServiceTestSuite) TestDeliveryFailure() {
	notification := &models.Notification{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategorySystem,
		Priority:  models.NotificationPriorityNormal,
		Title:     "Test",
		Status:    models.NotificationStatusSent,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(notification)

	// Create failed delivery
	delivery := &models.NotificationDelivery{
		NotificationID: notification.ID,
		Channel:        models.NotificationChannelPush,
		Status:         "failed",
		Error:          "Invalid FCM token",
		CreatedAt:      time.Now(),
	}
	s.db.Create(delivery)

	// Verify
	var saved models.NotificationDelivery
	s.db.First(&saved, delivery.ID)
	s.Assert().Equal("failed", saved.Status)
	s.Assert().Equal("Invalid FCM token", saved.Error)
}

// =============================================================================
// Channel Provider Tests
// =============================================================================

func TestMockChannelProvider(t *testing.T) {
	mockProvider := NewMockChannelProvider("push", true)

	// Set up expectations
	delivery := &models.NotificationDelivery{
		Channel:    models.NotificationChannelPush,
		Status:     "delivered",
		ExternalID: "fcm_test_123",
	}
	mockProvider.On("Send", mock.Anything, mock.Anything, "user@test.com").Return(delivery, nil)

	// Call mock
	result, err := mockProvider.Send(context.Background(), &models.Notification{}, "user@test.com")

	assert.NoError(t, err)
	assert.Equal(t, "fcm_test_123", result.ExternalID)
	mockProvider.AssertExpectations(t)
}

func TestChannelProviderDisabled(t *testing.T) {
	mockProvider := NewMockChannelProvider("sms", false)

	assert.Equal(t, "sms", mockProvider.GetName())
	assert.False(t, mockProvider.IsEnabled())
}

// =============================================================================
// Notification Counts Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestNotificationCounts() {
	now := time.Now()

	// Create various notifications
	// Unread
	for i := 0; i < 3; i++ {
		s.db.Create(&models.Notification{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  models.NotificationCategorySales,
			Priority:  models.NotificationPriorityNormal,
			Title:     "Unread",
			Status:    models.NotificationStatusSent,
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// High priority unread
	for i := 0; i < 2; i++ {
		s.db.Create(&models.Notification{
			TenantID:  s.tenantID,
			UserID:    s.userID,
			Category:  models.NotificationCategoryFinance,
			Priority:  models.NotificationPriorityHigh,
			Title:     "Urgent",
			Status:    models.NotificationStatusSent,
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// Read
	readTime := now.Add(-1 * time.Hour)
	s.db.Create(&models.Notification{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategorySales,
		Priority:  models.NotificationPriorityNormal,
		Title:     "Read",
		Status:    models.NotificationStatusRead,
		ReadAt:    &readTime,
		CreatedAt: now,
		UpdatedAt: now,
	})

	// Count queries
	var totalCount int64
	s.db.Model(&models.Notification{}).Where("user_id = ?", s.userID).Count(&totalCount)
	s.Assert().Equal(int64(6), totalCount)

	var unreadCount int64
	s.db.Model(&models.Notification{}).Where("user_id = ? AND read_at IS NULL", s.userID).Count(&unreadCount)
	s.Assert().Equal(int64(5), unreadCount)

	var highPriorityCount int64
	s.db.Model(&models.Notification{}).Where("user_id = ? AND priority = ? AND read_at IS NULL", s.userID, models.NotificationPriorityHigh).Count(&highPriorityCount)
	s.Assert().Equal(int64(2), highPriorityCount)
}

// =============================================================================
// Digest Tests
// =============================================================================

func (s *NotificationServiceTestSuite) TestDigestCreation() {
	now := time.Now()
	scheduledFor := now.Add(1 * time.Hour)

	digest := &models.NotificationDigest{
		TenantID:       s.tenantID,
		UserID:         s.userID,
		Category:       models.NotificationCategorySales,
		Frequency:      "daily",
		Status:         "pending",
		ScheduledFor:   scheduledFor,
		NotificationIDs: []uuid.UUID{uuid.New(), uuid.New()},
		CreatedAt:      now,
		UpdatedAt:      now,
	}

	err := s.db.Create(digest).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, digest.ID)
}

func (s *NotificationServiceTestSuite) TestDigestProcessing() {
	now := time.Now()
	pastTime := now.Add(-1 * time.Hour)

	// Create pending digest scheduled in the past
	digest := &models.NotificationDigest{
		TenantID:     s.tenantID,
		UserID:       s.userID,
		Category:     models.NotificationCategorySystem,
		Frequency:    "hourly",
		Status:       "pending",
		ScheduledFor: pastTime,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	s.db.Create(digest)

	// Query pending digests ready to send
	var pendingDigests []models.NotificationDigest
	err := s.db.Where("status = ? AND scheduled_for <= ?", "pending", now).Find(&pendingDigests).Error
	s.Require().NoError(err)
	s.Assert().Len(pendingDigests, 1)
}
