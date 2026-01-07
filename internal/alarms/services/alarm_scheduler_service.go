package services

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/robfig/cron/v3"
)

// AlarmSchedulerService handles scheduled alarm checks
type AlarmSchedulerService struct {
	db           *database.DB
	alarmService *AlarmService
	cron         *cron.Cron
}

// NewAlarmSchedulerService creates a new alarm scheduler service
func NewAlarmSchedulerService(db *database.DB, alarmService *AlarmService) *AlarmSchedulerService {
	return &AlarmSchedulerService{
		db:           db,
		alarmService: alarmService,
		cron:         cron.New(cron.WithSeconds()),
	}
}

// Start starts the alarm scheduler
func (s *AlarmSchedulerService) Start() {
	// Process expired snoozes - every minute
	s.cron.AddFunc("0 * * * * *", func() {
		ctx := context.Background()
		if err := s.alarmService.ProcessExpiredSnoozes(ctx); err != nil {
			log.Printf("[ALARM] Error processing expired snoozes: %v", err)
		}
	})

	// Process auto-resolves - every 5 minutes
	s.cron.AddFunc("0 */5 * * * *", func() {
		ctx := context.Background()
		if err := s.alarmService.ProcessAutoResolves(ctx); err != nil {
			log.Printf("[ALARM] Error processing auto-resolves: %v", err)
		}
	})

	// Process escalations - every 5 minutes
	s.cron.AddFunc("0 */5 * * * *", func() {
		ctx := context.Background()
		if err := s.alarmService.ProcessEscalations(ctx); err != nil {
			log.Printf("[ALARM] Error processing escalations: %v", err)
		}
	})

	// Scheduled alarm checks - every 15 minutes
	s.cron.AddFunc("0 */15 * * * *", func() {
		log.Println("[ALARM] Running scheduled alarm checks")
		s.runScheduledAlarmChecks()
	})

	// Low stock checks - every hour at :30
	s.cron.AddFunc("0 30 * * * *", func() {
		log.Println("[ALARM] Running low stock checks")
		s.runLowStockChecks()
	})

	// Settlement reminder - daily at 6 PM
	s.cron.AddFunc("0 0 18 * * *", func() {
		log.Println("[ALARM] Running settlement reminder check")
		s.runSettlementReminders()
	})

	// Expiring products check - daily at 8 AM
	s.cron.AddFunc("0 0 8 * * *", func() {
		log.Println("[ALARM] Running expiring products check")
		s.runExpiringProductsCheck()
	})

	// Credit overdue check - daily at 10 AM
	s.cron.AddFunc("0 0 10 * * *", func() {
		log.Println("[ALARM] Running credit overdue check")
		s.runCreditOverdueCheck()
	})

	// Inventory variance check - daily at 11 PM
	s.cron.AddFunc("0 0 23 * * *", func() {
		log.Println("[ALARM] Running inventory variance check")
		s.runInventoryVarianceCheck()
	})

	// Cash collection reminder - daily at 5 PM
	s.cron.AddFunc("0 0 17 * * *", func() {
		log.Println("[ALARM] Running cash collection reminder")
		s.runCashCollectionReminder()
	})

	// Daily sales submission check for salesmen - at 1 PM IST
	s.cron.AddFunc("0 0 13 * * *", func() {
		log.Println("[ALARM] Running daily sales submission check for salesmen")
		s.runDailySalesSubmissionCheck("salesman", "13:00")
	})

	// Daily sales submission check for managers - at 2 PM IST
	s.cron.AddFunc("0 0 14 * * *", func() {
		log.Println("[ALARM] Running daily sales submission check for managers")
		s.runDailySalesSubmissionCheck("manager", "14:00")
	})

	// Cleanup old alarms - weekly at 3 AM on Sunday
	s.cron.AddFunc("0 0 3 * * 0", func() {
		log.Println("[ALARM] Running old alarm cleanup")
		ctx := context.Background()
		if err := s.alarmService.CleanupOldAlarms(ctx, 90); err != nil {
			log.Printf("[ALARM] Error cleaning up old alarms: %v", err)
		}
	})

	s.cron.Start()
	log.Println("[ALARM] Scheduler started")
}

// Stop stops the alarm scheduler
func (s *AlarmSchedulerService) Stop() {
	s.cron.Stop()
	log.Println("[ALARM] Scheduler stopped")
}

// ========================================
// Scheduled Alarm Check Methods
// ========================================

func (s *AlarmSchedulerService) runScheduledAlarmChecks() {
	ctx := context.Background()

	// Get all tenants with active alarm configurations
	var tenantIDs []uuid.UUID
	s.db.WithContext(ctx).Model(&models.AlarmConfiguration{}).
		Distinct("tenant_id").
		Where("is_enabled = true").
		Pluck("tenant_id", &tenantIDs)

	for _, tenantID := range tenantIDs {
		// Get tenant's alarm configs with schedules
		var configs []models.AlarmConfiguration
		s.db.WithContext(ctx).
			Where("tenant_id = ? AND is_enabled = true AND (cron_expression IS NOT NULL AND cron_expression != '' OR preset_schedule IS NOT NULL AND preset_schedule != '')", tenantID).
			Find(&configs)

		for _, config := range configs {
			if s.shouldRunCheck(config) {
				s.runAlarmCheck(ctx, tenantID, config)
			}
		}
	}
}

func (s *AlarmSchedulerService) shouldRunCheck(config models.AlarmConfiguration) bool {
	// Event-only alarms don't run on schedule
	if config.ScheduleType == models.AlarmScheduleEventOnly || config.ScheduleType == "" {
		return false
	}

	// Get the effective cron expression
	cronExpr := config.GetCronExpression()
	if cronExpr == "" {
		return false
	}

	// Get current time in the configured timezone
	loc, err := time.LoadLocation(config.Timezone)
	if err != nil {
		loc = time.Local
	}
	now := time.Now().In(loc)

	// Check preset schedules first
	switch config.PresetSchedule {
	case "daily_8am":
		return now.Hour() == 8 && now.Minute() < 15
	case "daily_9am":
		return now.Hour() == 9 && now.Minute() < 15
	case "daily_9pm":
		return now.Hour() == 21 && now.Minute() < 15
	case "daily_10pm":
		return now.Hour() == 22 && now.Minute() < 15
	case "daily_1pm_8pm":
		return (now.Hour() == 13 || now.Hour() == 20) && now.Minute() < 15
	case "weekly_monday":
		return now.Weekday() == time.Monday && now.Hour() == 9 && now.Minute() < 15
	case "weekly_friday":
		return now.Weekday() == time.Friday && now.Hour() == 17 && now.Minute() < 15
	case "end_of_day":
		return now.Hour() == 22 && now.Minute() < 15
	case "hourly":
		return now.Minute() < 15
	case "every_6_hours":
		return now.Hour()%6 == 0 && now.Minute() < 15
	case "every_12_hours":
		return (now.Hour() == 0 || now.Hour() == 12) && now.Minute() < 15
	}

	// Parse custom cron expression
	if config.CronExpression != "" {
		// Parse the cron expression (standard 5-field format: min hour dom month dow)
		parser := cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow)
		schedule, err := parser.Parse(config.CronExpression)
		if err != nil {
			log.Printf("[ALARM] Invalid cron expression '%s': %v", config.CronExpression, err)
			return false
		}

		// Get the next scheduled time from 15 minutes ago
		windowStart := now.Add(-15 * time.Minute)
		nextRun := schedule.Next(windowStart)

		// Check if next run falls within the current 15-minute window
		return nextRun.Before(now) || nextRun.Equal(now) || (nextRun.After(now) && nextRun.Before(now.Add(1*time.Minute)))
	}

	return false
}

func (s *AlarmSchedulerService) runAlarmCheck(ctx context.Context, tenantID uuid.UUID, config models.AlarmConfiguration) {
	// Dispatch to specific check based on alarm code
	switch config.AlarmCode {
	case "LOW_STOCK":
		s.checkLowStockForTenant(ctx, tenantID, config.ShopID, config)
	case "SETTLEMENT_PENDING":
		s.checkSettlementForTenant(ctx, tenantID, config.ShopID)
	case "EXPIRING_PRODUCTS":
		s.checkExpiringProductsForTenant(ctx, tenantID, config.ShopID, config)
	case "CREDIT_OVERDUE":
		s.checkCreditOverdueForTenant(ctx, tenantID, config)
	case "INVENTORY_VARIANCE":
		s.checkInventoryVarianceForTenant(ctx, tenantID, config.ShopID, config)
	case "CASH_DISCREPANCY":
		s.checkCashDiscrepancyForTenant(ctx, tenantID, config.ShopID, config)
	}
}

// ========================================
// Low Stock Checks
// ========================================

func (s *AlarmSchedulerService) runLowStockChecks() {
	ctx := context.Background()

	// Get enabled low stock alarm configs
	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", "LOW_STOCK").
		Find(&configs)

	for _, config := range configs {
		s.checkLowStockForTenant(ctx, config.TenantID, config.ShopID, config)
	}
}

func (s *AlarmSchedulerService) checkLowStockForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, config models.AlarmConfiguration) {
	// Get threshold from config
	threshold := 10 // Default
	thresholds := config.GetThresholds()
	if thresholds != nil && thresholds.MinQuantity != nil {
		threshold = int(*thresholds.MinQuantity)
	}

	// Query for low stock products
	query := s.db.WithContext(ctx).
		Table("products").
		Select("products.id, products.name, products.sku, inventory_items.quantity, inventory_items.shop_id").
		Joins("JOIN inventory_items ON products.id = inventory_items.product_id").
		Where("products.tenant_id = ? AND inventory_items.quantity <= ? AND products.is_active = true", tenantID, threshold)

	if shopID != nil {
		query = query.Where("inventory_items.shop_id = ?", *shopID)
	}

	var results []struct {
		ID       uuid.UUID
		Name     string
		SKU      string
		Quantity int
		ShopID   uuid.UUID
	}

	if err := query.Find(&results).Error; err != nil {
		log.Printf("[ALARM] Error checking low stock for tenant %s: %v", tenantID, err)
		return
	}

	// Trigger alarm for each low stock item
	for _, item := range results {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"product_id":      item.ID.String(),
			"product_name":    item.Name,
			"sku":             item.SKU,
			"quantity":        item.Quantity,
			"threshold":       threshold,
			"shop_id":         item.ShopID.String(),
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         models.AlarmCodeLowStock,
			ShopID:            &item.ShopID,
			RelatedEntityType: "product",
			RelatedEntityID:   &item.ID,
			TriggerData:       triggerData,
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering low stock alarm: %v", err)
		}
	}
}

// ========================================
// Settlement Reminders
// ========================================

func (s *AlarmSchedulerService) runSettlementReminders() {
	ctx := context.Background()

	// Get enabled settlement alarm configs
	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", "SETTLEMENT_PENDING").
		Find(&configs)

	for _, config := range configs {
		s.checkSettlementForTenant(ctx, config.TenantID, config.ShopID)
	}
}

func (s *AlarmSchedulerService) checkSettlementForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) {
	today := time.Now().Format("2006-01-02")

	// Check for unsettled shops today
	query := s.db.WithContext(ctx).
		Table("shops").
		Select("shops.id, shops.name").
		Where("shops.tenant_id = ? AND shops.is_active = true", tenantID).
		Where("NOT EXISTS (SELECT 1 FROM daily_settlements ds WHERE ds.shop_id = shops.id AND ds.settlement_date = ?)", today)

	if shopID != nil {
		query = query.Where("shops.id = ?", *shopID)
	}

	var unsettledShops []struct {
		ID   uuid.UUID
		Name string
	}

	if err := query.Find(&unsettledShops).Error; err != nil {
		log.Printf("[ALARM] Error checking settlements for tenant %s: %v", tenantID, err)
		return
	}

	for _, shop := range unsettledShops {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"shop_id":   shop.ID.String(),
			"shop_name": shop.Name,
			"date":      today,
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         "settlement_pending",
			ShopID:            &shop.ID,
			RelatedEntityType: "shop",
			RelatedEntityID:   &shop.ID,
			TriggerData:       triggerData,
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering settlement alarm: %v", err)
		}
	}
}

// ========================================
// Expiring Products Check
// ========================================

func (s *AlarmSchedulerService) runExpiringProductsCheck() {
	ctx := context.Background()

	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", "EXPIRING_PRODUCTS").
		Find(&configs)

	for _, config := range configs {
		s.checkExpiringProductsForTenant(ctx, config.TenantID, config.ShopID, config)
	}
}

func (s *AlarmSchedulerService) checkExpiringProductsForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, config models.AlarmConfiguration) {
	// Default 30 days for expiry warning
	daysBeforeExpiry := 30
	thresholds := config.GetThresholds()
	if thresholds != nil && thresholds.DaysBefore != nil {
		daysBeforeExpiry = *thresholds.DaysBefore
	}

	expiryDate := time.Now().AddDate(0, 0, daysBeforeExpiry)

	query := s.db.WithContext(ctx).
		Table("inventory_items").
		Select("inventory_items.id, inventory_items.shop_id, products.name, products.sku, inventory_items.expiry_date, inventory_items.quantity").
		Joins("JOIN products ON products.id = inventory_items.product_id").
		Where("products.tenant_id = ? AND inventory_items.expiry_date <= ? AND inventory_items.expiry_date > ? AND inventory_items.quantity > 0",
			tenantID, expiryDate, time.Now())

	if shopID != nil {
		query = query.Where("inventory_items.shop_id = ?", *shopID)
	}

	var results []struct {
		ID         uuid.UUID
		ShopID     uuid.UUID
		Name       string
		SKU        string
		ExpiryDate time.Time
		Quantity   int
	}

	if err := query.Find(&results).Error; err != nil {
		log.Printf("[ALARM] Error checking expiring products: %v", err)
		return
	}

	for _, item := range results {
		daysUntilExpiry := int(time.Until(item.ExpiryDate).Hours() / 24)

		triggerData, _ := json.Marshal(map[string]interface{}{
			"product_name":      item.Name,
			"sku":               item.SKU,
			"expiry_date":       item.ExpiryDate.Format("2006-01-02"),
			"days_until_expiry": daysUntilExpiry,
			"quantity":          item.Quantity,
			"threshold_days":    daysBeforeExpiry,
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         "expiring_products",
			ShopID:            &item.ShopID,
			RelatedEntityType: "inventory_item",
			RelatedEntityID:   &item.ID,
			TriggerData:       triggerData,
		}

		// Set priority based on urgency
		if daysUntilExpiry <= 7 {
			req.Priority = models.AlarmPriorityCritical
		} else if daysUntilExpiry <= 14 {
			req.Priority = models.AlarmPriorityHigh
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering expiring product alarm: %v", err)
		}
	}
}

// ========================================
// Credit Overdue Check
// ========================================

func (s *AlarmSchedulerService) runCreditOverdueCheck() {
	ctx := context.Background()

	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", "CREDIT_OVERDUE").
		Find(&configs)

	for _, config := range configs {
		s.checkCreditOverdueForTenant(ctx, config.TenantID, config)
	}
}

func (s *AlarmSchedulerService) checkCreditOverdueForTenant(ctx context.Context, tenantID uuid.UUID, config models.AlarmConfiguration) {
	// Get overdue threshold in days
	overdueDays := 30
	thresholds := config.GetThresholds()
	if thresholds != nil && thresholds.DaysOverdue != nil {
		overdueDays = *thresholds.DaysOverdue
	}

	cutoffDate := time.Now().AddDate(0, 0, -overdueDays)

	var results []struct {
		ID           uuid.UUID
		CustomerID   uuid.UUID
		CustomerName string
		Amount       float64
		DueDate      time.Time
		DaysOverdue  int
	}

	query := `
		SELECT
			cs.id,
			cs.customer_id,
			c.name as customer_name,
			cs.balance_amount as amount,
			cs.due_date,
			EXTRACT(DAY FROM NOW() - cs.due_date)::int as days_overdue
		FROM credit_sales cs
		JOIN customers c ON c.id = cs.customer_id
		WHERE cs.tenant_id = $1
			AND cs.status = 'pending'
			AND cs.due_date < $2
			AND cs.balance_amount > 0
	`

	if err := s.db.WithContext(ctx).Raw(query, tenantID, cutoffDate).Scan(&results).Error; err != nil {
		log.Printf("[ALARM] Error checking credit overdue: %v", err)
		return
	}

	for _, item := range results {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"customer_id":    item.CustomerID.String(),
			"customer_name":  item.CustomerName,
			"amount":         item.Amount,
			"due_date":       item.DueDate.Format("2006-01-02"),
			"days_overdue":   item.DaysOverdue,
			"threshold_days": overdueDays,
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         models.AlarmCodeCollectionOverdue,
			RelatedEntityType: "credit_sale",
			RelatedEntityID:   &item.ID,
			TriggerData:       triggerData,
		}

		// Set priority based on amount and days overdue
		if item.DaysOverdue > 60 || item.Amount > 50000 {
			req.Priority = models.AlarmPriorityCritical
		} else if item.DaysOverdue > 45 || item.Amount > 25000 {
			req.Priority = models.AlarmPriorityHigh
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering credit overdue alarm: %v", err)
		}
	}
}

// ========================================
// Inventory Variance Check
// ========================================

func (s *AlarmSchedulerService) runInventoryVarianceCheck() {
	ctx := context.Background()

	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", "INVENTORY_VARIANCE").
		Find(&configs)

	for _, config := range configs {
		s.checkInventoryVarianceForTenant(ctx, config.TenantID, config.ShopID, config)
	}
}

func (s *AlarmSchedulerService) checkInventoryVarianceForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, config models.AlarmConfiguration) {
	// Get variance threshold percentage
	varianceThreshold := 5.0
	thresholds := config.GetThresholds()
	if thresholds != nil && thresholds.MaxVariancePercent != nil {
		varianceThreshold = *thresholds.MaxVariancePercent
	}

	// Check for significant variances from recent audits
	query := s.db.WithContext(ctx).
		Table("audit_results").
		Select("audit_results.id, audit_results.shop_id, products.name, products.sku, audit_results.expected_quantity, audit_results.actual_quantity, audit_results.variance_percentage").
		Joins("JOIN products ON products.id = audit_results.product_id").
		Where("audit_results.tenant_id = ? AND ABS(audit_results.variance_percentage) >= ? AND audit_results.created_at >= ?",
			tenantID, varianceThreshold, time.Now().AddDate(0, 0, -1))

	if shopID != nil {
		query = query.Where("audit_results.shop_id = ?", *shopID)
	}

	var results []struct {
		ID                 uuid.UUID
		ShopID             uuid.UUID
		Name               string
		SKU                string
		ExpectedQuantity   int
		ActualQuantity     int
		VariancePercentage float64
	}

	if err := query.Find(&results).Error; err != nil {
		log.Printf("[ALARM] Error checking inventory variance: %v", err)
		return
	}

	for _, item := range results {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"product_name":        item.Name,
			"sku":                 item.SKU,
			"expected_quantity":   item.ExpectedQuantity,
			"actual_quantity":     item.ActualQuantity,
			"variance_percentage": item.VariancePercentage,
			"threshold_percent":   varianceThreshold,
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         "inventory_variance",
			ShopID:            &item.ShopID,
			RelatedEntityType: "audit_result",
			RelatedEntityID:   &item.ID,
			TriggerData:       triggerData,
		}

		// Set priority based on variance
		if item.VariancePercentage > 20 || item.VariancePercentage < -20 {
			req.Priority = models.AlarmPriorityCritical
		} else if item.VariancePercentage > 10 || item.VariancePercentage < -10 {
			req.Priority = models.AlarmPriorityHigh
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering inventory variance alarm: %v", err)
		}
	}
}

// ========================================
// Cash Discrepancy Check
// ========================================

func (s *AlarmSchedulerService) checkCashDiscrepancyForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, config models.AlarmConfiguration) {
	// Get discrepancy threshold
	discrepancyThreshold := 100.0
	thresholds := config.GetThresholds()
	if thresholds != nil && thresholds.MaxVarianceAmount != nil {
		discrepancyThreshold = *thresholds.MaxVarianceAmount
	}

	// Check for cash discrepancies in recent submissions
	query := s.db.WithContext(ctx).
		Table("cash_submissions").
		Select("cash_submissions.id, cash_submissions.shop_id, cash_submissions.expected_amount, cash_submissions.submitted_amount, cash_submissions.discrepancy_amount").
		Where("cash_submissions.tenant_id = ? AND ABS(cash_submissions.discrepancy_amount) >= ? AND cash_submissions.created_at >= ?",
			tenantID, discrepancyThreshold, time.Now().AddDate(0, 0, -1))

	if shopID != nil {
		query = query.Where("cash_submissions.shop_id = ?", *shopID)
	}

	var results []struct {
		ID                uuid.UUID
		ShopID            uuid.UUID
		ExpectedAmount    float64
		SubmittedAmount   float64
		DiscrepancyAmount float64
	}

	if err := query.Find(&results).Error; err != nil {
		log.Printf("[ALARM] Error checking cash discrepancy: %v", err)
		return
	}

	for _, item := range results {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"expected_amount":     item.ExpectedAmount,
			"submitted_amount":    item.SubmittedAmount,
			"discrepancy_amount":  item.DiscrepancyAmount,
			"threshold_amount":    discrepancyThreshold,
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         models.AlarmCodeCashShortage,
			ShopID:            &item.ShopID,
			RelatedEntityType: "cash_submission",
			RelatedEntityID:   &item.ID,
			TriggerData:       triggerData,
		}

		// Set priority based on discrepancy amount
		if item.DiscrepancyAmount > 1000 || item.DiscrepancyAmount < -1000 {
			req.Priority = models.AlarmPriorityCritical
		} else if item.DiscrepancyAmount > 500 || item.DiscrepancyAmount < -500 {
			req.Priority = models.AlarmPriorityHigh
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering cash discrepancy alarm: %v", err)
		}
	}
}

// ========================================
// Cash Collection Reminder
// ========================================

func (s *AlarmSchedulerService) runCashCollectionReminder() {
	ctx := context.Background()

	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", "CASH_COLLECTION_DUE").
		Find(&configs)

	for _, config := range configs {
		s.checkCashCollectionForTenant(ctx, config.TenantID, config.ShopID, config)
	}
}

func (s *AlarmSchedulerService) checkCashCollectionForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, config models.AlarmConfiguration) {
	// Get threshold for uncollected cash
	amountThreshold := 10000.0
	thresholds := config.GetThresholds()
	if thresholds != nil && thresholds.MinAmount != nil {
		amountThreshold = *thresholds.MinAmount
	}

	// Query for shops with significant uncollected cash
	query := s.db.WithContext(ctx).
		Table("shops").
		Select("shops.id, shops.name, COALESCE(SUM(cash_submissions.submitted_amount - COALESCE(cash_submissions.collected_amount, 0)), 0) as pending_amount").
		Joins("LEFT JOIN cash_submissions ON cash_submissions.shop_id = shops.id AND cash_submissions.status != 'collected'").
		Where("shops.tenant_id = ? AND shops.is_active = true", tenantID).
		Group("shops.id, shops.name").
		Having("COALESCE(SUM(cash_submissions.submitted_amount - COALESCE(cash_submissions.collected_amount, 0)), 0) >= ?", amountThreshold)

	if shopID != nil {
		query = query.Where("shops.id = ?", *shopID)
	}

	var results []struct {
		ID            uuid.UUID
		Name          string
		PendingAmount float64
	}

	if err := query.Find(&results).Error; err != nil {
		log.Printf("[ALARM] Error checking cash collection: %v", err)
		return
	}

	for _, shop := range results {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"shop_id":          shop.ID.String(),
			"shop_name":        shop.Name,
			"pending_amount":   shop.PendingAmount,
			"threshold_amount": amountThreshold,
		})

		req := &models.TriggerAlarmRequest{
			AlarmCode:         "cash_collection_due",
			ShopID:            &shop.ID,
			RelatedEntityType: "shop",
			RelatedEntityID:   &shop.ID,
			TriggerData:       triggerData,
		}

		if shop.PendingAmount > 50000 {
			req.Priority = models.AlarmPriorityCritical
		} else if shop.PendingAmount > 25000 {
			req.Priority = models.AlarmPriorityHigh
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering cash collection alarm: %v", err)
		}
	}
}

// ========================================
// Daily Sales Submission Check
// ========================================

func (s *AlarmSchedulerService) runDailySalesSubmissionCheck(targetRole string, deadlineTime string) {
	ctx := context.Background()
	today := time.Now().Format("2006-01-02")

	// Get enabled sales submission alarm configs
	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("alarm_code = ? AND is_enabled = true", models.AlarmCodeDailySalesNotSubmitted).
		Find(&configs)

	for _, config := range configs {
		s.checkSalesSubmissionForTenant(ctx, config.TenantID, config.ShopID, targetRole, deadlineTime, today, config)
	}
}

func (s *AlarmSchedulerService) checkSalesSubmissionForTenant(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, targetRole, deadlineTime, today string, config models.AlarmConfiguration) {
	// Daily sales are SHOP-based, not user-based
	// Get all active SHOPS that haven't submitted daily sales today
	var pendingShops []struct {
		ShopID   uuid.UUID `gorm:"column:shop_id"`
		ShopName string    `gorm:"column:shop_name"`
	}

	query := `
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
	`

	args := []interface{}{tenantID, today}

	if shopID != nil {
		query = `
			SELECT s.id as shop_id, s.name as shop_name
			FROM shops s
			WHERE s.tenant_id = ?
			  AND s.id = ?
			  AND s.is_active = true
			  AND NOT EXISTS (
				SELECT 1 FROM daily_sales_records dsr
				WHERE dsr.shop_id = s.id
				  AND dsr.record_date = ?
				  AND dsr.deleted_at IS NULL
			  )
		`
		args = []interface{}{tenantID, *shopID, today}
	}

	if err := s.db.WithContext(ctx).Raw(query, args...).Scan(&pendingShops).Error; err != nil {
		log.Printf("[ALARM] Error checking sales submission for tenant %s: %v", tenantID, err)
		return
	}

	log.Printf("[ALARM] Found %d shops without daily sales submission for %s", len(pendingShops), today)

	for _, shop := range pendingShops {
		triggerData, _ := json.Marshal(map[string]interface{}{
			"shop_id":       shop.ShopID.String(),
			"shop_name":     shop.ShopName,
			"date":          today,
			"deadline_time": deadlineTime,
		})

		shopIDPtr := shop.ShopID
		req := &models.TriggerAlarmRequest{
			AlarmCode:         models.AlarmCodeDailySalesNotSubmitted,
			ShopID:            &shopIDPtr,
			Title:             "📊 Daily Sales Pending",
			Message:           shop.ShopName + " has not submitted daily sales",
			Priority:          models.AlarmPriorityHigh,
			RelatedEntityType: "shop",
			RelatedEntityID:   &shopIDPtr,
			TriggerData:       triggerData,
		}

		if _, err := s.alarmService.TriggerAlarm(ctx, tenantID, req); err != nil {
			log.Printf("[ALARM] Error triggering sales submission alarm for shop %s: %v", shop.ShopName, err)
		}
	}
}

// ========================================
// Manual Check Triggers
// ========================================

// RunAllChecksForTenant runs all alarm checks for a specific tenant (for manual trigger)
func (s *AlarmSchedulerService) RunAllChecksForTenant(ctx context.Context, tenantID uuid.UUID) error {
	var configs []models.AlarmConfiguration
	s.db.WithContext(ctx).
		Where("tenant_id = ? AND is_enabled = true", tenantID).
		Find(&configs)

	for _, config := range configs {
		s.runAlarmCheck(ctx, tenantID, config)
	}

	return nil
}

// RunSpecificCheckForTenant runs a specific alarm check
func (s *AlarmSchedulerService) RunSpecificCheckForTenant(ctx context.Context, tenantID uuid.UUID, alarmCode string, shopID *uuid.UUID) error {
	config, err := s.alarmService.GetAlarmConfiguration(ctx, tenantID, alarmCode, shopID)
	if err != nil {
		return err
	}

	s.runAlarmCheck(ctx, tenantID, *config)
	return nil
}
