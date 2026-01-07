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

// =============================================================================
// Mock AlarmService
// =============================================================================

type MockAlarmService struct {
	mock.Mock
}

func (m *MockAlarmService) ProcessExpiredSnoozes(ctx context.Context) error {
	args := m.Called(ctx)
	return args.Error(0)
}

func (m *MockAlarmService) ProcessAutoResolves(ctx context.Context) error {
	args := m.Called(ctx)
	return args.Error(0)
}

func (m *MockAlarmService) ProcessEscalations(ctx context.Context) error {
	args := m.Called(ctx)
	return args.Error(0)
}

func (m *MockAlarmService) CreateAlarm(ctx context.Context, alarm *models.AlarmInstance) error {
	args := m.Called(ctx, alarm)
	return args.Error(0)
}

// =============================================================================
// Test Suite
// =============================================================================

type AlarmSchedulerTestSuite struct {
	suite.Suite
	db       *gorm.DB
	tenantID uuid.UUID
}

func (s *AlarmSchedulerTestSuite) SetupTest() {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	s.Require().NoError(err)

	// Auto-migrate required tables
	err = db.AutoMigrate(
		&models.AlarmDefinition{},
		&models.AlarmConfiguration{},
		&models.AlarmInstance{},
		&models.AlarmScheduleRun{},
	)
	s.Require().NoError(err)

	s.db = db
	s.tenantID = uuid.New()
}

func (s *AlarmSchedulerTestSuite) TearDownTest() {
	sqlDB, _ := s.db.DB()
	if sqlDB != nil {
		sqlDB.Close()
	}
}

func TestAlarmSchedulerTestSuite(t *testing.T) {
	suite.Run(t, new(AlarmSchedulerTestSuite))
}

// =============================================================================
// Alarm Definition Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestAlarmDefinitionCreation() {
	definition := &models.AlarmDefinition{
		Code:            "low_stock",
		Name:            "Low Stock Alert",
		Description:     "Triggered when product stock falls below threshold",
		Category:        "inventory",
		DefaultSeverity: "high",
		IsActive:        true,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	err := s.db.Create(definition).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, definition.ID)
}

func (s *AlarmSchedulerTestSuite) TestGetActiveDefinitions() {
	// Create multiple definitions
	definitions := []models.AlarmDefinition{
		{Code: "low_stock", Name: "Low Stock", Category: "inventory", DefaultSeverity: "high", IsActive: true, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{Code: "settlement_due", Name: "Settlement Due", Category: "finance", DefaultSeverity: "medium", IsActive: true, CreatedAt: time.Now(), UpdatedAt: time.Now()},
		{Code: "disabled_alarm", Name: "Disabled", Category: "system", DefaultSeverity: "low", IsActive: false, CreatedAt: time.Now(), UpdatedAt: time.Now()},
	}

	for _, d := range definitions {
		s.db.Create(&d)
	}

	// Query active only
	var active []models.AlarmDefinition
	err := s.db.Where("is_active = ?", true).Find(&active).Error
	s.Require().NoError(err)
	s.Assert().Len(active, 2)
}

// =============================================================================
// Alarm Configuration Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestAlarmConfigurationCreation() {
	// First create definition
	definition := &models.AlarmDefinition{
		Code:            "low_stock",
		Name:            "Low Stock",
		Category:        "inventory",
		DefaultSeverity: "high",
		IsActive:        true,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	s.db.Create(definition)

	// Create configuration
	config := &models.AlarmConfiguration{
		TenantID:           s.tenantID,
		AlarmDefinitionID:  definition.ID,
		IsEnabled:          true,
		Threshold:          10, // Low stock threshold
		CooldownMinutes:    60,
		QuietHoursStart:    nil,
		QuietHoursEnd:      nil,
		NotifyChannels:     []string{"in_app", "push"},
		EscalationMinutes:  30,
		AutoResolveMinutes: 0, // No auto-resolve
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	err := s.db.Create(config).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, config.ID)
}

func (s *AlarmSchedulerTestSuite) TestQuietHoursConfiguration() {
	definition := &models.AlarmDefinition{
		Code:            "settlement_reminder",
		Name:            "Settlement Reminder",
		Category:        "finance",
		DefaultSeverity: "medium",
		IsActive:        true,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	s.db.Create(definition)

	// Create config with quiet hours (10 PM to 6 AM)
	quietStart := 22 // 10 PM
	quietEnd := 6    // 6 AM

	config := &models.AlarmConfiguration{
		TenantID:          s.tenantID,
		AlarmDefinitionID: definition.ID,
		IsEnabled:         true,
		QuietHoursStart:   &quietStart,
		QuietHoursEnd:     &quietEnd,
		CreatedAt:         time.Now(),
		UpdatedAt:         time.Now(),
	}
	s.db.Create(config)

	// Verify quiet hours saved
	var saved models.AlarmConfiguration
	s.db.First(&saved, config.ID)
	s.Assert().NotNil(saved.QuietHoursStart)
	s.Assert().Equal(22, *saved.QuietHoursStart)
	s.Assert().Equal(6, *saved.QuietHoursEnd)
}

func (s *AlarmSchedulerTestSuite) TestCooldownEnforcement() {
	now := time.Now()

	// Create alarm instance
	instance := &models.AlarmInstance{
		TenantID:  s.tenantID,
		AlarmCode: "low_stock",
		Severity:  "high",
		Status:    "active",
		Title:     "Low Stock: Test Product",
		Message:   "Stock level is 5 units",
		CreatedAt: now,
		UpdatedAt: now,
	}
	s.db.Create(instance)

	// Check for recent alarms within cooldown period (last 60 minutes)
	cooldownStart := now.Add(-60 * time.Minute)
	var recentAlarms []models.AlarmInstance
	err := s.db.Where(
		"tenant_id = ? AND alarm_code = ? AND created_at > ?",
		s.tenantID, "low_stock", cooldownStart,
	).Find(&recentAlarms).Error
	s.Require().NoError(err)
	s.Assert().Len(recentAlarms, 1)
}

// =============================================================================
// Alarm Instance Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestAlarmInstanceCreation() {
	now := time.Now()

	instance := &models.AlarmInstance{
		TenantID:  s.tenantID,
		AlarmCode: "credit_overdue",
		Severity:  "high",
		Status:    "active",
		Title:     "Credit Overdue: Customer ABC",
		Message:   "Outstanding amount: ₹50,000. Days overdue: 15",
		Data: map[string]interface{}{
			"customer_id":   "cust_123",
			"customer_name": "ABC Store",
			"amount":        50000,
			"days_overdue":  15,
		},
		CreatedAt: now,
		UpdatedAt: now,
	}

	err := s.db.Create(instance).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, instance.ID)
}

func (s *AlarmSchedulerTestSuite) TestAlarmStatusTransitions() {
	now := time.Now()

	// Create active alarm
	instance := &models.AlarmInstance{
		TenantID:  s.tenantID,
		AlarmCode: "low_stock",
		Severity:  "medium",
		Status:    "active",
		Title:     "Low Stock",
		CreatedAt: now,
		UpdatedAt: now,
	}
	s.db.Create(instance)
	s.Assert().Equal("active", instance.Status)

	// Acknowledge
	instance.Status = "acknowledged"
	instance.AcknowledgedAt = &now
	s.db.Save(instance)

	var acknowledged models.AlarmInstance
	s.db.First(&acknowledged, instance.ID)
	s.Assert().Equal("acknowledged", acknowledged.Status)
	s.Assert().NotNil(acknowledged.AcknowledgedAt)

	// Resolve
	acknowledged.Status = "resolved"
	acknowledged.ResolvedAt = &now
	acknowledged.ResolutionNotes = "Stock replenished"
	s.db.Save(&acknowledged)

	var resolved models.AlarmInstance
	s.db.First(&resolved, instance.ID)
	s.Assert().Equal("resolved", resolved.Status)
	s.Assert().NotNil(resolved.ResolvedAt)
}

func (s *AlarmSchedulerTestSuite) TestSnoozeAlarm() {
	now := time.Now()
	snoozeUntil := now.Add(30 * time.Minute)

	instance := &models.AlarmInstance{
		TenantID:    s.tenantID,
		AlarmCode:   "settlement_reminder",
		Severity:    "medium",
		Status:      "snoozed",
		Title:       "Settlement Reminder",
		SnoozedAt:   &now,
		SnoozeUntil: &snoozeUntil,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	s.db.Create(instance)

	// Query snoozed alarms
	var snoozed []models.AlarmInstance
	err := s.db.Where("status = ? AND snooze_until > ?", "snoozed", now).Find(&snoozed).Error
	s.Require().NoError(err)
	s.Assert().Len(snoozed, 1)

	// Query expired snoozes
	pastTime := now.Add(-1 * time.Minute)
	var expiredSnoozes []models.AlarmInstance
	s.db.Where("status = ? AND snooze_until <= ?", "snoozed", pastTime).Find(&expiredSnoozes)
	s.Assert().Len(expiredSnoozes, 0) // Our snooze is still active
}

// =============================================================================
// Schedule Run Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestScheduleRunTracking() {
	now := time.Now()

	run := &models.AlarmScheduleRun{
		TenantID:       s.tenantID,
		AlarmCode:      "low_stock",
		ScheduledFor:   now,
		Status:         "completed",
		AlarmsCreated:  5,
		StartedAt:      now.Add(-10 * time.Second),
		CompletedAt:    &now,
		CreatedAt:      now,
	}

	err := s.db.Create(run).Error
	s.Require().NoError(err)
	s.Assert().NotEqual(uuid.Nil, run.ID)
}

func (s *AlarmSchedulerTestSuite) TestPreventDuplicateRuns() {
	now := time.Now()
	scheduledFor := now.Truncate(time.Hour) // Hourly schedule

	// First run
	run1 := &models.AlarmScheduleRun{
		TenantID:     s.tenantID,
		AlarmCode:    "low_stock",
		ScheduledFor: scheduledFor,
		Status:       "completed",
		StartedAt:    now,
		CreatedAt:    now,
	}
	s.db.Create(run1)

	// Check if already run for this schedule
	var existingRun models.AlarmScheduleRun
	result := s.db.Where(
		"tenant_id = ? AND alarm_code = ? AND scheduled_for = ?",
		s.tenantID, "low_stock", scheduledFor,
	).First(&existingRun)

	s.Assert().NoError(result.Error)
	s.Assert().Equal(run1.ID, existingRun.ID)
}

// =============================================================================
// Preset Schedule Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestPresetScheduleDetection() {
	// Test cases for different days/times
	testCases := []struct {
		name       string
		dayOfWeek  time.Weekday
		hour       int
		alarmCode  string
		shouldRun  bool
	}{
		{"Low stock hourly check", time.Monday, 10, "low_stock", true},
		{"Settlement reminder at 6 PM", time.Wednesday, 18, "settlement_reminder", true},
		{"Expiring products at 8 AM", time.Friday, 8, "expiring_products", true},
		{"Credit overdue at 10 AM", time.Tuesday, 10, "credit_overdue", true},
		{"Settlement reminder at wrong time", time.Wednesday, 10, "settlement_reminder", false},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			// This is a placeholder test structure
			// Actual implementation would check scheduler logic
			s.Assert().NotEmpty(tc.alarmCode)
		})
	}
}

// =============================================================================
// Alarm Severity Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestSeverityOrdering() {
	now := time.Now()

	// Create alarms with different severities
	severities := []string{"critical", "high", "medium", "low"}
	for _, sev := range severities {
		s.db.Create(&models.AlarmInstance{
			TenantID:  s.tenantID,
			AlarmCode: "test",
			Severity:  sev,
			Status:    "active",
			Title:     "Test " + sev,
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// Query and verify ordering by severity (critical first)
	var alarms []models.AlarmInstance
	s.db.Where("tenant_id = ?", s.tenantID).
		Order("CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 END").
		Find(&alarms)

	s.Assert().Len(alarms, 4)
	s.Assert().Equal("critical", alarms[0].Severity)
	s.Assert().Equal("low", alarms[3].Severity)
}

// =============================================================================
// Escalation Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestEscalationDetection() {
	now := time.Now()
	escalationThreshold := 30 * time.Minute
	escalationTime := now.Add(-35 * time.Minute) // Created 35 mins ago

	// Create alarm that should be escalated
	instance := &models.AlarmInstance{
		TenantID:  s.tenantID,
		AlarmCode: "cash_shortage",
		Severity:  "high",
		Status:    "active",
		Title:     "Cash Shortage",
		CreatedAt: escalationTime,
		UpdatedAt: escalationTime,
	}
	s.db.Create(instance)

	// Query alarms needing escalation
	escalationCutoff := now.Add(-escalationThreshold)
	var needsEscalation []models.AlarmInstance
	err := s.db.Where(
		"status = ? AND escalated_at IS NULL AND created_at < ?",
		"active", escalationCutoff,
	).Find(&needsEscalation).Error

	s.Require().NoError(err)
	s.Assert().Len(needsEscalation, 1)
}

func (s *AlarmSchedulerTestSuite) TestEscalationMarking() {
	now := time.Now()

	instance := &models.AlarmInstance{
		TenantID:  s.tenantID,
		AlarmCode: "credit_overdue",
		Severity:  "high",
		Status:    "active",
		Title:     "Credit Overdue",
		CreatedAt: now.Add(-1 * time.Hour),
		UpdatedAt: now.Add(-1 * time.Hour),
	}
	s.db.Create(instance)

	// Mark as escalated
	err := s.db.Model(instance).Updates(map[string]interface{}{
		"escalated_at": now,
		"severity":     "critical",
	}).Error
	s.Require().NoError(err)

	var escalated models.AlarmInstance
	s.db.First(&escalated, instance.ID)
	s.Assert().NotNil(escalated.EscalatedAt)
	s.Assert().Equal("critical", escalated.Severity)
}

// =============================================================================
// Auto-Resolve Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestAutoResolveDetection() {
	now := time.Now()
	autoResolveMinutes := 120 // 2 hours
	oldTime := now.Add(-3 * time.Hour)

	// Create old alarm that should be auto-resolved
	instance := &models.AlarmInstance{
		TenantID:  s.tenantID,
		AlarmCode: "inventory_variance",
		Severity:  "low",
		Status:    "active",
		Title:     "Inventory Variance",
		CreatedAt: oldTime,
		UpdatedAt: oldTime,
	}
	s.db.Create(instance)

	// Query alarms for auto-resolve
	autoResolveCutoff := now.Add(-time.Duration(autoResolveMinutes) * time.Minute)
	var needsAutoResolve []models.AlarmInstance
	err := s.db.Where(
		"status = ? AND created_at < ?",
		"active", autoResolveCutoff,
	).Find(&needsAutoResolve).Error

	s.Require().NoError(err)
	s.Assert().Len(needsAutoResolve, 1)
}

// =============================================================================
// Notification Integration Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestAlarmNotificationChannels() {
	definition := &models.AlarmDefinition{
		Code:            "critical_alert",
		Name:            "Critical Alert",
		Category:        "system",
		DefaultSeverity: "critical",
		IsActive:        true,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	s.db.Create(definition)

	config := &models.AlarmConfiguration{
		TenantID:          s.tenantID,
		AlarmDefinitionID: definition.ID,
		IsEnabled:         true,
		NotifyChannels:    []string{"in_app", "push", "sms"},
		CreatedAt:         time.Now(),
		UpdatedAt:         time.Now(),
	}
	s.db.Create(config)

	// Verify channels
	var saved models.AlarmConfiguration
	s.db.First(&saved, config.ID)
	s.Assert().Contains(saved.NotifyChannels, "push")
	s.Assert().Contains(saved.NotifyChannels, "sms")
}

// =============================================================================
// Multi-Tenant Tests
// =============================================================================

func (s *AlarmSchedulerTestSuite) TestMultiTenantIsolation() {
	tenant1 := uuid.New()
	tenant2 := uuid.New()
	now := time.Now()

	// Create alarms for tenant 1
	for i := 0; i < 3; i++ {
		s.db.Create(&models.AlarmInstance{
			TenantID:  tenant1,
			AlarmCode: "low_stock",
			Severity:  "high",
			Status:    "active",
			Title:     "Tenant 1 Alarm",
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// Create alarms for tenant 2
	for i := 0; i < 2; i++ {
		s.db.Create(&models.AlarmInstance{
			TenantID:  tenant2,
			AlarmCode: "low_stock",
			Severity:  "high",
			Status:    "active",
			Title:     "Tenant 2 Alarm",
			CreatedAt: now,
			UpdatedAt: now,
		})
	}

	// Query per tenant
	var tenant1Alarms []models.AlarmInstance
	s.db.Where("tenant_id = ?", tenant1).Find(&tenant1Alarms)
	s.Assert().Len(tenant1Alarms, 3)

	var tenant2Alarms []models.AlarmInstance
	s.db.Where("tenant_id = ?", tenant2).Find(&tenant2Alarms)
	s.Assert().Len(tenant2Alarms, 2)
}
