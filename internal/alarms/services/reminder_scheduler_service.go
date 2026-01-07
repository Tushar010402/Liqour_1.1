package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	notificationServices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/robfig/cron/v3"
)

// ReminderSchedulerService handles user-configurable reminders
type ReminderSchedulerService struct {
	db           *database.DB
	alarmService *AlarmService
	cron         *cron.Cron
	location     *time.Location
}

// NewReminderSchedulerService creates a new reminder scheduler
func NewReminderSchedulerService(db *database.DB, alarmService *AlarmService) *ReminderSchedulerService {
	// Use IST timezone
	loc, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("[REMINDER] Warning: Could not load IST timezone, using UTC: %v", err)
		loc = time.UTC
	}

	return &ReminderSchedulerService{
		db:           db,
		alarmService: alarmService,
		cron:         cron.New(cron.WithSeconds()),
		location:     loc,
	}
}

// Start starts the reminder scheduler
func (s *ReminderSchedulerService) Start() {
	// Run every minute at :00 seconds to check for reminders
	s.cron.AddFunc("0 * * * * *", func() {
		s.processReminders()
	})

	s.cron.Start()
	log.Println("[REMINDER] User reminder scheduler started")
}

// Stop stops the reminder scheduler
func (s *ReminderSchedulerService) Stop() {
	s.cron.Stop()
	log.Println("[REMINDER] User reminder scheduler stopped")
}

// processReminders checks all user reminders and triggers matching ones
func (s *ReminderSchedulerService) processReminders() {
	ctx := context.Background()
	now := time.Now().In(s.location)
	currentTime := now.Format("15:04") // HH:mm format
	currentDay := strings.ToLower(now.Weekday().String()[:3]) // mon, tue, wed, etc.

	log.Printf("[REMINDER] Checking reminders at %s (%s)", currentTime, currentDay)

	// Get all notification preferences with reminders
	var preferences []models.NotificationPreference
	err := s.db.WithContext(ctx).
		Where("reminders IS NOT NULL AND reminders != '[]'::jsonb AND reminders != 'null'::jsonb").
		Find(&preferences).Error

	if err != nil {
		log.Printf("[REMINDER] Error fetching preferences: %v", err)
		return
	}

	for _, pref := range preferences {
		s.processUserReminders(ctx, pref, currentTime, currentDay, now)
	}
}

// processUserReminders processes reminders for a single user
func (s *ReminderSchedulerService) processUserReminders(ctx context.Context, pref models.NotificationPreference, currentTime, currentDay string, now time.Time) {
	if pref.Reminders == nil || len(pref.Reminders) == 0 {
		return
	}

	for _, reminder := range pref.Reminders {
		if !reminder.Enabled {
			continue
		}

		// Check if time matches
		if reminder.Time != currentTime {
			continue
		}

		// Check if day matches
		if !s.dayMatches(reminder.Days, currentDay) {
			continue
		}

		log.Printf("[REMINDER] Triggering reminder '%s' for user %s", reminder.ID, pref.UserID)

		// Execute the reminder check
		s.executeReminder(ctx, pref, reminder, now)
	}
}

// dayMatches checks if the current day matches the reminder days
func (s *ReminderSchedulerService) dayMatches(days []string, currentDay string) bool {
	for _, day := range days {
		day = strings.ToLower(day)
		if day == "daily" || day == currentDay {
			return true
		}
	}
	return false
}

// executeReminder executes a specific reminder and sends notification if condition is met
func (s *ReminderSchedulerService) executeReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	switch reminder.ID {
	case "daily_sales":
		s.checkDailySalesReminder(ctx, pref, reminder, now)
	case "low_stock":
		s.checkLowStockReminder(ctx, pref, reminder, now)
	case "cash_collection":
		s.checkCashCollectionReminder(ctx, pref, reminder, now)
	case "settlement":
		s.checkSettlementReminder(ctx, pref, reminder, now)
	case "credit_overdue":
		s.checkCreditOverdueReminder(ctx, pref, reminder, now)
	case "audit_reminder":
		s.checkAuditReminder(ctx, pref, reminder, now)
	default:
		log.Printf("[REMINDER] Unknown reminder type: %s", reminder.ID)
	}
}

// ========================================
// Daily Sales Reminder
// ========================================

func (s *ReminderSchedulerService) checkDailySalesReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	// Business model: Submit YESTERDAY's sales (not same day)
	yesterday := now.AddDate(0, 0, -1).Format("2006-01-02")

	// Get user details
	var user models.User
	if err := s.db.WithContext(ctx).Where("id = ?", pref.UserID).First(&user).Error; err != nil {
		log.Printf("[REMINDER] Error getting user %s: %v", pref.UserID, err)
		return
	}

	// Check based on user role
	switch user.Role {
	case "admin", "owner":
		// Check for all users who haven't submitted
		s.checkTeamSalesSubmission(ctx, pref, user, yesterday, reminder)
	case "manager":
		// Check manager's own submission and their team
		s.checkManagerSalesSubmission(ctx, pref, user, yesterday, reminder)
	case "salesman":
		// Check if salesman has submitted
		s.checkSalesmanSubmission(ctx, pref, user, yesterday, reminder)
	}
}

func (s *ReminderSchedulerService) checkSalesmanSubmission(ctx context.Context, pref models.NotificationPreference, user models.User, today string, reminder models.Reminder) {
	// Get salesman's shop
	var salesman models.Salesman
	if err := s.db.WithContext(ctx).Where("user_id = ?", user.ID).First(&salesman).Error; err != nil {
		log.Printf("[REMINDER] Salesman record not found for user %s", user.ID)
		return
	}

	// Check if the SHOP has submitted daily sales today
	var count int64
	s.db.WithContext(ctx).Model(&models.DailySalesRecord{}).
		Where("shop_id = ? AND record_date = ? AND deleted_at IS NULL", salesman.ShopID, today).
		Count(&count)

	if count == 0 {
		// Get shop name
		var shop models.Shop
		shopName := "your shop"
		if err := s.db.WithContext(ctx).Where("id = ?", salesman.ShopID).First(&shop).Error; err == nil {
			shopName = shop.Name
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    "⏰ Submit Daily Sales",
			Body:     fmt.Sprintf("%s has not submitted yesterday's sales • Please submit now", shopName),
			Category: models.NotificationCategorySales,
			Priority: models.NotificationPriorityHigh,
			Data: map[string]interface{}{
				"type":        "shop_sales_reminder",
				"date":        today,
				"shop_id":     salesman.ShopID.String(),
				"shop_name":   shopName,
				"action":      "submit_sales",
				"reminder_id": reminder.ID,
			},
			ChannelID: "reminders",
			ThreadID:  "daily_sales_reminders",
		})
	}
}

func (s *ReminderSchedulerService) checkManagerSalesSubmission(ctx context.Context, pref models.NotificationPreference, user models.User, today string, reminder models.Reminder) {
	// Get manager's shop from salesman table
	var salesman models.Salesman
	if err := s.db.WithContext(ctx).Where("user_id = ?", user.ID).First(&salesman).Error; err != nil {
		log.Printf("[REMINDER] Manager %s has no shop assignment", user.ID)
		return
	}

	// Get shop details
	var shop models.Shop
	if err := s.db.WithContext(ctx).Where("id = ?", salesman.ShopID).First(&shop).Error; err != nil {
		log.Printf("[REMINDER] Could not find shop %s for manager %s", salesman.ShopID, user.ID)
		return
	}

	// Check if manager's SHOP has submitted daily sales today
	var shopSalesCount int64
	s.db.WithContext(ctx).Model(&models.DailySalesRecord{}).
		Where("shop_id = ? AND record_date = ? AND deleted_at IS NULL", salesman.ShopID, today).
		Count(&shopSalesCount)

	if shopSalesCount == 0 {
		// Shop has not submitted yesterday's sales
		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    "⏰ Submit Daily Sales",
			Body:     fmt.Sprintf("%s has not submitted yesterday's sales • Please submit now", shop.Name),
			Category: models.NotificationCategorySales,
			Priority: models.NotificationPriorityHigh,
			Data: map[string]interface{}{
				"type":        "shop_sales_reminder",
				"date":        today,
				"shop_id":     salesman.ShopID.String(),
				"shop_name":   shop.Name,
				"action":      "submit_sales",
				"reminder_id": reminder.ID,
			},
			ChannelID: "reminders",
			ThreadID:  "daily_sales_reminders",
		})

		log.Printf("[REMINDER] Daily sales reminder: Shop %s has not submitted for %s", shop.Name, today)
	}
}

func (s *ReminderSchedulerService) checkTeamSalesSubmission(ctx context.Context, pref models.NotificationPreference, user models.User, today string, reminder models.Reminder) {
	// Get all SHOPS that haven't submitted daily sales today
	// Daily sales are SHOP-based, not user-based
	var pendingShops []struct {
		ShopID   uuid.UUID `gorm:"column:shop_id"`
		ShopName string    `gorm:"column:shop_name"`
	}

	s.db.WithContext(ctx).Raw(`
		SELECT s.id as shop_id, s.name as shop_name
		FROM shops s
		WHERE s.tenant_id = ?
		  AND s.is_active = true
		  AND NOT EXISTS (
			SELECT 1 FROM daily_sales_records dsr
			WHERE dsr.shop_id = s.id
			  AND dsr.record_date = ?
			  AND dsr.deleted_at IS NULL
		  )
		ORDER BY s.name
	`, pref.TenantID, today).Scan(&pendingShops)

	if len(pendingShops) > 0 {
		// Build clean shop names list
		shopNames := make([]string, 0, len(pendingShops))
		for _, shop := range pendingShops {
			shopNames = append(shopNames, shop.ShopName)
		}

		// iOS Best Practice: Short title (max 50 chars), short body (max 150 chars)
		var title, body string
		if len(shopNames) == 1 {
			title = "📊 Sales Pending"
			body = shopNames[0] + " → Submit yesterday's sales"
		} else if len(shopNames) == 2 {
			title = "📊 2 Shops Pending"
			body = shopNames[0] + ", " + shopNames[1] + " → Submit sales"
		} else if len(shopNames) == 3 {
			title = "📊 3 Shops Pending"
			body = strings.Join(shopNames, ", ") + " → Submit sales"
		} else {
			title = fmt.Sprintf("📊 %d Shops Pending", len(shopNames))
			body = strings.Join(shopNames[:3], ", ")
			body += fmt.Sprintf(" +%d more → Submit sales", len(shopNames)-3)
		}

		// Ensure body fits iOS limit
		if len(body) > 145 {
			body = body[:142] + "..."
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    title,
			Body:     body,
			Category: models.NotificationCategorySales,
			Priority: models.NotificationPriorityHigh,
			Data: map[string]interface{}{
				"type":          "shops_sales_pending",
				"date":          today,
				"pending_count": len(pendingShops),
				"shop_names":    shopNames,
				"reminder_id":   reminder.ID,
				"action":        "view_pending_sales",
			},
			ChannelID: "reminders",
			ThreadID:  "daily_sales_pending",
		})

		// Trigger alarm per SHOP for tracking (without duplicate notification)
		for _, shop := range pendingShops {
			triggerData, _ := json.Marshal(map[string]interface{}{
				"shop_id":   shop.ShopID.String(),
				"shop_name": shop.ShopName,
				"date":      today,
			})

			shopID := shop.ShopID
			req := &models.TriggerAlarmRequest{
				AlarmCode:         models.AlarmCodeDailySalesNotSubmitted,
				Title:             "📊 Daily Sales Pending",
				Message:           shop.ShopName + " has not submitted daily sales",
				Priority:          models.AlarmPriorityHigh,
				RelatedEntityType: "shop",
				RelatedEntityID:   &shopID,
				ShopID:            &shopID,
				TriggerData:       triggerData,
			}

			if _, err := s.alarmService.TriggerAlarm(ctx, pref.TenantID, req); err != nil {
				log.Printf("[REMINDER] Error triggering alarm for shop %s: %v", shop.ShopName, err)
			}
		}

		log.Printf("[REMINDER] Daily sales reminder: %d shops pending for tenant %s", len(pendingShops), pref.TenantID)
	}
}

// ========================================
// Low Stock Reminder
// ========================================

func (s *ReminderSchedulerService) checkLowStockReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	// Get user to determine their shop access
	var user models.User
	if err := s.db.WithContext(ctx).Where("id = ?", pref.UserID).First(&user).Error; err != nil {
		log.Printf("[REMINDER] Error getting user %s: %v", pref.UserID, err)
		return
	}

	// Default threshold used only when product has no reorder_level set
	defaultThreshold := 10

	var results []struct {
		ProductID    uuid.UUID `gorm:"column:product_id"`
		ProductName  string    `gorm:"column:product_name"`
		ShopID       uuid.UUID `gorm:"column:shop_id"`
		ShopName     string    `gorm:"column:shop_name"`
		Quantity     int       `gorm:"column:quantity"`
		ReorderLevel int       `gorm:"column:reorder_level"`
		Urgency      string    `gorm:"column:urgency"`
	}

	// Get shop ID for shop-specific users
	var shopID *uuid.UUID
	if user.Role == "salesman" || user.Role == "manager" {
		var salesman models.Salesman
		if err := s.db.WithContext(ctx).Where("user_id = ?", user.ID).First(&salesman).Error; err == nil {
			shopID = &salesman.ShopID
		}
	}

	// Smart query using product's reorder_level with fallback to default
	// Urgency levels: CRITICAL (out of stock), LOW (below reorder level)
	query := `
		SELECT
			p.id as product_id,
			p.name as product_name,
			st.shop_id,
			s.name as shop_name,
			st.quantity,
			COALESCE(NULLIF(st.reorder_level, 0), NULLIF(st.minimum_level, 0), ?) as reorder_level,
			CASE
				WHEN st.quantity = 0 THEN 'CRITICAL'
				WHEN st.quantity <= COALESCE(NULLIF(st.reorder_level, 0), NULLIF(st.minimum_level, 0), ?) * 0.5 THEN 'LOW'
				ELSE 'WARNING'
			END as urgency
		FROM stocks st
		JOIN products p ON p.id = st.product_id
		JOIN shops s ON s.id = st.shop_id
		WHERE st.tenant_id = ?
		  AND p.is_active = true
		  AND s.is_active = true
		  AND st.quantity <= COALESCE(NULLIF(st.reorder_level, 0), NULLIF(st.minimum_level, 0), ?)
	`

	var args []interface{}
	args = append(args, defaultThreshold, defaultThreshold, pref.TenantID, defaultThreshold)

	if shopID != nil {
		query += " AND st.shop_id = ?"
		args = append(args, *shopID)
	}

	// Order by urgency (CRITICAL first), then by quantity ascending
	query += ` ORDER BY
		CASE
			WHEN st.quantity = 0 THEN 1
			WHEN st.quantity <= COALESCE(NULLIF(st.reorder_level, 0), NULLIF(st.minimum_level, 0), 10) * 0.5 THEN 2
			ELSE 3
		END,
		st.quantity ASC
		LIMIT 15`

	if err := s.db.WithContext(ctx).Raw(query, args...).Scan(&results).Error; err != nil {
		log.Printf("[REMINDER] Error checking low stock: %v", err)
		return
	}

	if len(results) > 0 {
		// Count by urgency
		criticalCount := 0
		lowCount := 0
		warningCount := 0
		for _, r := range results {
			switch r.Urgency {
			case "CRITICAL":
				criticalCount++
			case "LOW":
				lowCount++
			default:
				warningCount++
			}
		}

		// Build title
		var title string
		if criticalCount > 0 {
			title = fmt.Sprintf("🚨 %d Out of Stock", criticalCount)
			if lowCount+warningCount > 0 {
				title += fmt.Sprintf(" + %d Low", lowCount+warningCount)
			}
		} else {
			title = fmt.Sprintf("📦 %d Items Low Stock", len(results))
		}

		// Build concise body for push notification (iOS limit ~4 lines visible)
		// Show top 3-4 critical items, summarize the rest
		var bodyLines []string
		shown := 0
		maxToShow := 4

		// Critical items first (Out of Stock)
		for _, r := range results {
			if r.Urgency == "CRITICAL" && shown < maxToShow {
				bodyLines = append(bodyLines, fmt.Sprintf("🔴 %s @ %s", r.ProductName, r.ShopName))
				shown++
			}
		}

		// Low items if space allows
		for _, r := range results {
			if r.Urgency == "LOW" && shown < maxToShow {
				bodyLines = append(bodyLines, fmt.Sprintf("🟡 %s (%d left)", r.ProductName, r.Quantity))
				shown++
			}
		}

		// Add summary if more items
		remaining := len(results) - shown
		if remaining > 0 {
			bodyLines = append(bodyLines, fmt.Sprintf("+%d more items need attention", remaining))
		}

		body := strings.Join(bodyLines, "\n")

		// Set priority based on urgency
		priority := models.NotificationPriorityNormal
		if criticalCount > 0 {
			priority = models.NotificationPriorityCritical
		} else if lowCount > 0 {
			priority = models.NotificationPriorityHigh
		}

		// Limit items for push notification to avoid FCM 4KB limit
		// Only include product_id and shop_id for top 5 critical items
		type SimplifiedItem struct {
			ProductID string `json:"product_id"`
			ShopID    string `json:"shop_id"`
			Quantity  int    `json:"quantity"`
		}
		simplifiedItems := make([]SimplifiedItem, 0, 5)
		for i, r := range results {
			if i >= 5 {
				break // Limit to 5 items for push notification
			}
			simplifiedItems = append(simplifiedItems, SimplifiedItem{
				ProductID: r.ProductID.String(),
				ShopID:    r.ShopID.String(),
				Quantity:  r.Quantity,
			})
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    title,
			Body:     body,
			Category: models.NotificationCategoryInventory,
			Priority: priority,
			Data: map[string]interface{}{
				"type":           "low_stock_alert",
				"total_count":    len(results),
				"critical_count": criticalCount,
				"low_count":      lowCount,
				"warning_count":  warningCount,
				"action":         "view_low_stock",
				"reminder_id":    reminder.ID,
				"items":          simplifiedItems, // Simplified for FCM size limit
			},
			ChannelID: "inventory",
			ThreadID:  "low_stock_alerts",
		})
	}
}

// ========================================
// Cash Collection Reminder
// ========================================

func (s *ReminderSchedulerService) checkCashCollectionReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	var results []struct {
		ShopID        uuid.UUID `gorm:"column:shop_id"`
		ShopName      string    `gorm:"column:shop_name"`
		PendingAmount float64   `gorm:"column:pending_amount"`
	}

	err := s.db.WithContext(ctx).Raw(`
		SELECT
			s.id as shop_id,
			s.name as shop_name,
			COALESCE(SUM(cs.submitted_amount - COALESCE(cs.collected_amount, 0)), 0) as pending_amount
		FROM shops s
		LEFT JOIN cash_submissions cs ON cs.shop_id = s.id AND cs.status != 'collected'
		WHERE s.tenant_id = ? AND s.is_active = true
		GROUP BY s.id, s.name
		HAVING COALESCE(SUM(cs.submitted_amount - COALESCE(cs.collected_amount, 0)), 0) >= 1000
		ORDER BY pending_amount DESC
	`, pref.TenantID).Scan(&results).Error

	if err != nil {
		log.Printf("[REMINDER] Error checking cash collection: %v", err)
		return
	}

	if len(results) > 0 {
		totalPending := 0.0
		for _, r := range results {
			totalPending += r.PendingAmount
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    fmt.Sprintf("💰 %s Pending", formatCurrency(totalPending)),
			Body:     fmt.Sprintf("%d shops awaiting collection", len(results)),
			Category: models.NotificationCategoryFinance,
			Priority: models.NotificationPriorityNormal,
			Data: map[string]interface{}{
				"type":          "cash_collection_pending",
				"shop_count":    len(results),
				"total_pending": totalPending,
				"action":        "collect_cash",
				"reminder_id":   reminder.ID,
			},
			ChannelID: "reminders",
			ThreadID:  "cash_collection",
		})
	}
}

// ========================================
// Settlement Reminder
// ========================================

func (s *ReminderSchedulerService) checkSettlementReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	today := now.Format("2006-01-02")

	var unsettledShops []struct {
		ShopID   uuid.UUID `gorm:"column:id"`
		ShopName string    `gorm:"column:name"`
	}

	err := s.db.WithContext(ctx).Raw(`
		SELECT s.id, s.name
		FROM shops s
		WHERE s.tenant_id = ? AND s.is_active = true
		  AND NOT EXISTS (
			SELECT 1 FROM daily_settlements ds
			WHERE ds.shop_id = s.id AND ds.settlement_date = ?
		  )
	`, pref.TenantID, today).Scan(&unsettledShops).Error

	if err != nil {
		log.Printf("[REMINDER] Error checking settlements: %v", err)
		return
	}

	if len(unsettledShops) > 0 {
		names := make([]string, len(unsettledShops))
		for i, shop := range unsettledShops {
			names[i] = shop.ShopName
		}

		// Limit shop names in body
		var bodyNames string
		if len(names) <= 3 {
			bodyNames = strings.Join(names, ", ")
		} else {
			bodyNames = strings.Join(names[:3], ", ") + fmt.Sprintf(" +%d more", len(names)-3)
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    fmt.Sprintf("🏪 Settlement Due • %d shops", len(unsettledShops)),
			Body:     bodyNames + " pending",
			Category: models.NotificationCategoryFinance,
			Priority: models.NotificationPriorityHigh,
			Data: map[string]interface{}{
				"type":            "settlement_pending",
				"date":            today,
				"pending_count":   len(unsettledShops),
				"unsettled_shops": names,
				"action":          "view_settlements",
				"reminder_id":     reminder.ID,
			},
			ChannelID: "reminders",
			ThreadID:  "settlements",
		})
	}
}

// ========================================
// Credit Overdue Reminder
// ========================================

func (s *ReminderSchedulerService) checkCreditOverdueReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	var results []struct {
		CustomerID   uuid.UUID `gorm:"column:customer_id"`
		CustomerName string    `gorm:"column:customer_name"`
		TotalAmount  float64   `gorm:"column:total_amount"`
		DaysOverdue  int       `gorm:"column:max_days_overdue"`
	}

	err := s.db.WithContext(ctx).Raw(`
		SELECT
			c.id as customer_id,
			c.name as customer_name,
			SUM(cs.balance_amount) as total_amount,
			MAX(EXTRACT(DAY FROM NOW() - cs.due_date)::int) as max_days_overdue
		FROM credit_sales cs
		JOIN customers c ON c.id = cs.customer_id
		WHERE cs.tenant_id = ?
		  AND cs.status = 'pending'
		  AND cs.due_date < NOW()
		  AND cs.balance_amount > 0
		GROUP BY c.id, c.name
		ORDER BY total_amount DESC
		LIMIT 10
	`, pref.TenantID).Scan(&results).Error

	if err != nil {
		log.Printf("[REMINDER] Error checking credit overdue: %v", err)
		return
	}

	if len(results) > 0 {
		totalOverdue := 0.0
		for _, r := range results {
			totalOverdue += r.TotalAmount
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    fmt.Sprintf("⚠️ %s Overdue", formatCurrency(totalOverdue)),
			Body:     fmt.Sprintf("%d customers past due", len(results)),
			Category: models.NotificationCategoryFinance,
			Priority: models.NotificationPriorityHigh,
			Data: map[string]interface{}{
				"type":           "credit_overdue",
				"customer_count": len(results),
				"total_overdue":  totalOverdue,
				"action":         "view_overdue",
				"reminder_id":    reminder.ID,
			},
			ChannelID: "reminders",
			ThreadID:  "credit_overdue",
		})
	}
}

// ========================================
// Audit Reminder
// ========================================

func (s *ReminderSchedulerService) checkAuditReminder(ctx context.Context, pref models.NotificationPreference, reminder models.Reminder, now time.Time) {
	// Check for shops that haven't been audited in the last 7 days
	weekAgo := now.AddDate(0, 0, -7).Format("2006-01-02")

	var shopsNeedingAudit []struct {
		ShopID      uuid.UUID  `gorm:"column:id"`
		ShopName    string     `gorm:"column:name"`
		LastAuditAt *time.Time `gorm:"column:last_audit_at"`
	}

	err := s.db.WithContext(ctx).Raw(`
		SELECT s.id, s.name, MAX(a.created_at) as last_audit_at
		FROM shops s
		LEFT JOIN audits a ON a.shop_id = s.id
		WHERE s.tenant_id = ? AND s.is_active = true
		GROUP BY s.id, s.name
		HAVING MAX(a.created_at) IS NULL OR MAX(a.created_at) < ?
	`, pref.TenantID, weekAgo).Scan(&shopsNeedingAudit).Error

	if err != nil {
		log.Printf("[REMINDER] Error checking audits: %v", err)
		return
	}

	if len(shopsNeedingAudit) > 0 {
		names := make([]string, len(shopsNeedingAudit))
		for i, shop := range shopsNeedingAudit {
			names[i] = shop.ShopName
		}

		// Limit shop names in body
		var bodyNames string
		if len(names) <= 3 {
			bodyNames = strings.Join(names, ", ")
		} else {
			bodyNames = strings.Join(names[:3], ", ") + fmt.Sprintf(" +%d more", len(names)-3)
		}

		s.sendNotification(ctx, pref.TenantID, pref.UserID, &models.SendNotificationRequest{
			Title:    fmt.Sprintf("📋 Audit Due • %d shops", len(shopsNeedingAudit)),
			Body:     bodyNames + " need review",
			Category: models.NotificationCategoryAudit,
			Priority: models.NotificationPriorityNormal,
			Data: map[string]interface{}{
				"type":                "audit_reminder",
				"shops_needing_audit": names,
				"shop_count":          len(shopsNeedingAudit),
				"action":              "start_audit",
				"reminder_id":         reminder.ID,
			},
			ChannelID: "reminders",
			ThreadID:  "audit_reminders",
		})
	}
}

// ========================================
// Helper Functions
// ========================================

func (s *ReminderSchedulerService) sendNotification(ctx context.Context, tenantID, userID uuid.UUID, req *models.SendNotificationRequest) {
	// Create notification directly in database with modern features
	data := req.Data
	if data == nil {
		data = make(map[string]interface{})
	}

	// Add modern features to data for frontend
	if req.ChannelID != "" {
		data["channel_id"] = req.ChannelID
	}
	if req.ThreadID != "" {
		data["thread_id"] = req.ThreadID
	}

	notification := &models.Notification{
		TenantID: tenantID,
		UserID:   userID,
		Title:    req.Title,
		Body:     req.Body,
		Category: req.Category,
		Priority: req.Priority,
		Data:     data,
		Status:   models.NotificationStatusPending,
	}

	if err := s.db.WithContext(ctx).Create(notification).Error; err != nil {
		log.Printf("[REMINDER] Error creating notification: %v", err)
		return
	}

	// Send push notification if user has FCM tokens
	s.sendPushNotification(ctx, tenantID, userID, notification, req.ChannelID, req.ThreadID)

	log.Printf("[REMINDER] Notification sent to user %s: %s", userID, req.Title)
}

func (s *ReminderSchedulerService) sendPushNotification(ctx context.Context, tenantID, userID uuid.UUID, notification *models.Notification, channelID, threadID string) {
	// Get user's push tokens from preferences
	var pref models.NotificationPreference
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND user_id = ?", tenantID, userID).
		First(&pref).Error

	if err != nil {
		log.Printf("[REMINDER] No notification preferences found for user %s", userID)
		return
	}

	// Check if push is enabled
	if !pref.Channels.Push {
		log.Printf("[REMINDER] Push notifications disabled for user %s", userID)
		return
	}

	// Get device tokens
	var devices []models.NotificationDevice
	s.db.WithContext(ctx).
		Where("user_id = ? AND is_active = true", userID).
		Find(&devices)

	if len(devices) == 0 {
		log.Printf("[REMINDER] No active devices found for user %s", userID)
		return
	}

	// Get Firebase client
	firebaseClient := notificationServices.GetFirebaseClient()
	if firebaseClient == nil || !firebaseClient.IsEnabled() {
		log.Printf("[REMINDER] Firebase client not available, cannot send push")
		return
	}

	// Build data map for FCM
	dataMap := make(map[string]string)
	dataMap["notification_id"] = notification.ID.String()
	dataMap["category"] = string(notification.Category)
	dataMap["priority"] = string(notification.Priority)
	if channelID != "" {
		dataMap["channel_id"] = channelID
	}
	if threadID != "" {
		dataMap["thread_id"] = threadID
	}

	// Add any existing data from notification
	if notification.Data != nil {
		if dataMapInterface, ok := notification.Data.(map[string]interface{}); ok {
			for k, v := range dataMapInterface {
				// Properly serialize complex types to JSON strings
				switch val := v.(type) {
				case string:
					dataMap[k] = val
				case float64:
					dataMap[k] = fmt.Sprintf("%.0f", val)
				case int:
					dataMap[k] = fmt.Sprintf("%d", val)
				case bool:
					dataMap[k] = fmt.Sprintf("%t", val)
				default:
					// For maps, slices, etc. - serialize to JSON
					if jsonBytes, err := json.Marshal(v); err == nil {
						dataMap[k] = string(jsonBytes)
					} else {
						dataMap[k] = fmt.Sprintf("%v", v)
					}
				}
			}
		}
	}

	successCount := 0
	for _, device := range devices {
		log.Printf("[REMINDER] Sending push to device %s (platform: %s)", device.DeviceID, device.Platform)

		messageID, err := firebaseClient.SendPush(ctx, device.FCMToken, notification.Title, notification.Body, dataMap)
		if err != nil {
			log.Printf("[REMINDER] Failed to send push to device %s: %v", device.DeviceID, err)

			// Mark device as inactive if token is invalid
			if strings.Contains(err.Error(), "NotRegistered") || strings.Contains(err.Error(), "InvalidRegistration") || strings.Contains(err.Error(), "Unregistered") {
				device.IsActive = false
				s.db.WithContext(ctx).Save(&device)
				log.Printf("[REMINDER] Marked device %s as inactive due to invalid token", device.DeviceID)
			}
			continue
		}

		log.Printf("[REMINDER] Push sent successfully to device %s, message ID: %s", device.DeviceID, messageID)
		successCount++

		// Update device last used time
		now := time.Now()
		device.LastUsedAt = &now
		s.db.WithContext(ctx).Save(&device)
	}

	// Update notification status if at least one push was sent successfully
	if successCount > 0 {
		notification.Status = models.NotificationStatusSent
		s.db.WithContext(ctx).Save(notification)
		log.Printf("[REMINDER] Notification %s marked as sent (delivered to %d devices)", notification.ID, successCount)
	}
}

// formatPendingUsersMessage formats the message for pending users with shop-wise grouping
func formatPendingUsersMessage(users []struct {
	UserID   uuid.UUID `gorm:"column:id"`
	Username string    `gorm:"column:username"`
	Role     string    `gorm:"column:role"`
	ShopName string    `gorm:"column:shop_name"`
}) string {
	if len(users) == 0 {
		return ""
	}

	// Group by shop
	shopGroups := make(map[string]int)
	for _, u := range users {
		shopName := u.ShopName
		if shopName == "" || shopName == "No Shop" {
			shopName = "Unassigned"
		}
		shopGroups[shopName]++
	}

	// If only one shop, show simpler message
	if len(shopGroups) == 1 {
		for shopName, count := range shopGroups {
			if count == 1 {
				return fmt.Sprintf("%s: 1 pending", shopName)
			}
			return fmt.Sprintf("%s: %d pending", shopName, count)
		}
	}

	// Multiple shops - show shop-wise breakdown
	parts := make([]string, 0, len(shopGroups))
	for shopName, count := range shopGroups {
		parts = append(parts, fmt.Sprintf("%s: %d", shopName, count))
	}

	// Limit to 3 shops in the message
	if len(parts) > 3 {
		return fmt.Sprintf("%s + %d more", strings.Join(parts[:3], " | "), len(parts)-3)
	}

	return strings.Join(parts, " | ")
}

func formatLowStockMessage(count int) string {
	if count == 1 {
		return "1 product is running low on stock."
	}
	return strconv.Itoa(count) + " products are running low on stock."
}

func formatCashCollectionMessage(shopCount int, totalPending float64) string {
	amountStr := formatCurrency(totalPending)
	if shopCount == 1 {
		return amountStr + " pending cash collection from 1 shop."
	}
	return amountStr + " pending cash collection from " + strconv.Itoa(shopCount) + " shops."
}

func formatCreditOverdueMessage(customerCount int, totalOverdue float64) string {
	amountStr := formatCurrency(totalOverdue)
	if customerCount == 1 {
		return amountStr + " overdue from 1 customer."
	}
	return amountStr + " overdue from " + strconv.Itoa(customerCount) + " customers."
}

func formatAuditReminderMessage(shopNames []string) string {
	if len(shopNames) == 1 {
		return shopNames[0] + " hasn't been audited in over 7 days."
	} else if len(shopNames) <= 3 {
		return strings.Join(shopNames, ", ") + " haven't been audited in over 7 days."
	}
	return strconv.Itoa(len(shopNames)) + " shops haven't been audited in over 7 days."
}

func formatCurrency(amount float64) string {
	if amount >= 10000000 { // 1 Crore+
		return fmt.Sprintf("₹%.2f Cr", amount/10000000)
	} else if amount >= 100000 { // 1 Lakh+
		return fmt.Sprintf("₹%.2f L", amount/100000)
	} else if amount >= 1000 { // 1 Thousand+
		return fmt.Sprintf("₹%.0f", amount)
	}
	return fmt.Sprintf("₹%.0f", amount)
}
