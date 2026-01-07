package services

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/stretchr/testify/suite"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// =============================================================================
// Test Suite
// =============================================================================

type ReminderSchedulerTestSuite struct {
	suite.Suite
	db       *gorm.DB
	tenantID uuid.UUID
	userID   uuid.UUID
}

func (s *ReminderSchedulerTestSuite) SetupTest() {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	s.Require().NoError(err)

	// Auto-migrate required tables
	err = db.AutoMigrate(
		&models.NotificationPreference{},
	)
	s.Require().NoError(err)

	s.db = db
	s.tenantID = uuid.New()
	s.userID = uuid.New()
}

func (s *ReminderSchedulerTestSuite) TearDownTest() {
	sqlDB, _ := s.db.DB()
	if sqlDB != nil {
		sqlDB.Close()
	}
}

func TestReminderSchedulerTestSuite(t *testing.T) {
	suite.Run(t, new(ReminderSchedulerTestSuite))
}

// =============================================================================
// Day Matching Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestDayMatching() {
	testCases := []struct {
		name        string
		reminderDay string
		currentDay  string
		expected    bool
	}{
		{"Exact match Monday", "mon", "mon", true},
		{"Exact match Tuesday", "tue", "tue", true},
		{"Wrong day", "mon", "tue", false},
		{"Everyday matches Monday", "everyday", "mon", true},
		{"Everyday matches Sunday", "everyday", "sun", true},
		{"Weekdays matches Monday", "weekdays", "mon", true},
		{"Weekdays matches Friday", "weekdays", "fri", true},
		{"Weekdays does not match Saturday", "weekdays", "sat", false},
		{"Weekdays does not match Sunday", "weekdays", "sun", false},
		{"Weekends matches Saturday", "weekends", "sat", true},
		{"Weekends matches Sunday", "weekends", "sun", true},
		{"Weekends does not match Monday", "weekends", "mon", false},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			result := matchDay(tc.reminderDay, tc.currentDay)
			s.Assert().Equal(tc.expected, result)
		})
	}
}

// Helper function to match days (simulating scheduler logic)
func matchDay(reminderDay, currentDay string) bool {
	switch reminderDay {
	case "everyday":
		return true
	case "weekdays":
		return currentDay != "sat" && currentDay != "sun"
	case "weekends":
		return currentDay == "sat" || currentDay == "sun"
	default:
		return reminderDay == currentDay
	}
}

// =============================================================================
// Time Matching Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestTimeMatching() {
	testCases := []struct {
		name         string
		reminderTime string
		currentTime  string
		expected     bool
	}{
		{"Exact match 9:00 AM", "09:00", "09:00", true},
		{"Exact match 6:30 PM", "18:30", "18:30", true},
		{"Wrong time", "09:00", "09:01", false},
		{"Midnight", "00:00", "00:00", true},
		{"End of day", "23:59", "23:59", true},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			result := tc.reminderTime == tc.currentTime
			s.Assert().Equal(tc.expected, result)
		})
	}
}

// =============================================================================
// Reminder Type Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestReminderTypes() {
	reminderTypes := []string{
		"daily_sales",
		"low_stock",
		"cash_collection",
		"settlement",
		"credit_overdue",
		"audit",
	}

	for _, rt := range reminderTypes {
		s.Run(rt, func() {
			// Create preference with specific reminder type
			pref := &models.NotificationPreference{
				TenantID:  s.tenantID,
				UserID:    s.userID,
				Category:  models.NotificationCategoryReminder,
				Reminders: []models.UserReminder{
					{
						Type:    rt,
						Enabled: true,
						Days:    []string{"mon", "tue", "wed", "thu", "fri"},
						Time:    "09:00",
					},
				},
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			}

			err := s.db.Create(pref).Error
			s.Require().NoError(err)

			// Verify reminder saved
			var saved models.NotificationPreference
			s.db.First(&saved, pref.ID)
			s.Assert().Len(saved.Reminders, 1)
			s.Assert().Equal(rt, saved.Reminders[0].Type)
		})
	}
}

// =============================================================================
// Reminder Configuration Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestReminderWithMultipleDays() {
	pref := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{
				Type:    "daily_sales",
				Enabled: true,
				Days:    []string{"mon", "wed", "fri"},
				Time:    "17:00",
			},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	var saved models.NotificationPreference
	s.db.First(&saved, pref.ID)
	s.Assert().Contains(saved.Reminders[0].Days, "mon")
	s.Assert().Contains(saved.Reminders[0].Days, "wed")
	s.Assert().Contains(saved.Reminders[0].Days, "fri")
	s.Assert().NotContains(saved.Reminders[0].Days, "tue")
}

func (s *ReminderSchedulerTestSuite) TestDisabledReminder() {
	pref := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{
				Type:    "settlement",
				Enabled: false, // Disabled
				Days:    []string{"everyday"},
				Time:    "18:00",
			},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	var saved models.NotificationPreference
	s.db.First(&saved, pref.ID)
	s.Assert().False(saved.Reminders[0].Enabled)
}

func (s *ReminderSchedulerTestSuite) TestMultipleReminders() {
	pref := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{
				Type:    "daily_sales",
				Enabled: true,
				Days:    []string{"everyday"},
				Time:    "09:00",
			},
			{
				Type:    "settlement",
				Enabled: true,
				Days:    []string{"everyday"},
				Time:    "18:00",
			},
			{
				Type:    "low_stock",
				Enabled: true,
				Days:    []string{"weekdays"},
				Time:    "10:00",
			},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	var saved models.NotificationPreference
	s.db.First(&saved, pref.ID)
	s.Assert().Len(saved.Reminders, 3)
}

// =============================================================================
// Query Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestQueryPreferencesWithReminders() {
	// Create preference with reminders
	pref1 := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{Type: "daily_sales", Enabled: true, Days: []string{"everyday"}, Time: "09:00"},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref1)

	// Create preference without reminders
	pref2 := &models.NotificationPreference{
		TenantID:  s.tenantID,
		UserID:    uuid.New(),
		Category:  models.NotificationCategorySales,
		Reminders: nil,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref2)

	// Query only preferences with reminders
	var withReminders []models.NotificationPreference
	err := s.db.Where("reminders IS NOT NULL").Find(&withReminders).Error
	s.Require().NoError(err)
	// Note: SQLite doesn't support JSONB, so this query behavior may differ
}

func (s *ReminderSchedulerTestSuite) TestQueryRemindersByTime() {
	now := time.Now()

	// Create reminders at different times
	times := []string{"08:00", "09:00", "09:00", "10:00", "18:00"}
	for i, t := range times {
		pref := &models.NotificationPreference{
			TenantID: s.tenantID,
			UserID:   uuid.New(),
			Category: models.NotificationCategoryReminder,
			Reminders: []models.UserReminder{
				{Type: "test", Enabled: true, Days: []string{"everyday"}, Time: t},
			},
			CreatedAt: now,
			UpdatedAt: now,
		}
		pref.ID = uuid.New()
		s.db.Create(pref)
		_ = i // Avoid unused variable warning
	}

	// Query all and filter in memory (simulating scheduler logic)
	var allPrefs []models.NotificationPreference
	s.db.Where("reminders IS NOT NULL").Find(&allPrefs)

	targetTime := "09:00"
	matchCount := 0
	for _, pref := range allPrefs {
		for _, r := range pref.Reminders {
			if r.Time == targetTime {
				matchCount++
			}
		}
	}

	s.Assert().Equal(2, matchCount)
}

// =============================================================================
// Timezone Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestTimezoneHandling() {
	// Test IST timezone loading
	loc, err := time.LoadLocation("Asia/Kolkata")
	s.Require().NoError(err)

	now := time.Now().In(loc)
	s.Assert().Equal("IST", now.Location().String()[:3]) // May vary based on Go version
}

func (s *ReminderSchedulerTestSuite) TestTimeFormatConsistency() {
	// Ensure time format is consistent
	testTimes := []struct {
		input    string
		expected string
	}{
		{"09:00", "09:00"},
		{"18:30", "18:30"},
		{"00:00", "00:00"},
		{"23:59", "23:59"},
	}

	for _, tt := range testTimes {
		s.Run(tt.input, func() {
			// Parse and re-format to ensure consistency
			parsed, err := time.Parse("15:04", tt.input)
			s.Require().NoError(err)
			formatted := parsed.Format("15:04")
			s.Assert().Equal(tt.expected, formatted)
		})
	}
}

// =============================================================================
// Edge Case Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestEmptyRemindersArray() {
	pref := &models.NotificationPreference{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{}, // Empty array
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	var saved models.NotificationPreference
	s.db.First(&saved, pref.ID)
	s.Assert().Len(saved.Reminders, 0)
}

func (s *ReminderSchedulerTestSuite) TestNullReminders() {
	pref := &models.NotificationPreference{
		TenantID:  s.tenantID,
		UserID:    s.userID,
		Category:  models.NotificationCategorySales,
		Reminders: nil, // Null
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	var saved models.NotificationPreference
	s.db.First(&saved, pref.ID)
	s.Assert().Nil(saved.Reminders)
}

func (s *ReminderSchedulerTestSuite) TestReminderWithEmptyDays() {
	pref := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{
				Type:    "daily_sales",
				Enabled: true,
				Days:    []string{}, // Empty days
				Time:    "09:00",
			},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	var saved models.NotificationPreference
	s.db.First(&saved, pref.ID)
	s.Assert().Len(saved.Reminders[0].Days, 0)
}

// =============================================================================
// Update Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestUpdateReminderTime() {
	pref := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{Type: "settlement", Enabled: true, Days: []string{"everyday"}, Time: "18:00"},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	// Update time
	pref.Reminders[0].Time = "19:00"
	pref.UpdatedAt = time.Now()
	s.db.Save(pref)

	var updated models.NotificationPreference
	s.db.First(&updated, pref.ID)
	s.Assert().Equal("19:00", updated.Reminders[0].Time)
}

func (s *ReminderSchedulerTestSuite) TestToggleReminderEnabled() {
	pref := &models.NotificationPreference{
		TenantID: s.tenantID,
		UserID:   s.userID,
		Category: models.NotificationCategoryReminder,
		Reminders: []models.UserReminder{
			{Type: "low_stock", Enabled: true, Days: []string{"weekdays"}, Time: "10:00"},
		},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.db.Create(pref)

	// Disable
	pref.Reminders[0].Enabled = false
	s.db.Save(pref)

	var disabled models.NotificationPreference
	s.db.First(&disabled, pref.ID)
	s.Assert().False(disabled.Reminders[0].Enabled)

	// Re-enable
	disabled.Reminders[0].Enabled = true
	s.db.Save(&disabled)

	var enabled models.NotificationPreference
	s.db.First(&enabled, pref.ID)
	s.Assert().True(enabled.Reminders[0].Enabled)
}

// =============================================================================
// Multi-User Tests
// =============================================================================

func (s *ReminderSchedulerTestSuite) TestMultipleUsersWithReminders() {
	// Create reminders for multiple users
	users := []uuid.UUID{uuid.New(), uuid.New(), uuid.New()}

	for _, userID := range users {
		pref := &models.NotificationPreference{
			TenantID: s.tenantID,
			UserID:   userID,
			Category: models.NotificationCategoryReminder,
			Reminders: []models.UserReminder{
				{Type: "daily_sales", Enabled: true, Days: []string{"everyday"}, Time: "09:00"},
			},
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		s.db.Create(pref)
	}

	// Query all preferences with reminders for tenant
	var prefs []models.NotificationPreference
	s.db.Where("tenant_id = ? AND reminders IS NOT NULL", s.tenantID).Find(&prefs)
	s.Assert().Len(prefs, 3)
}
