package services

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/robfig/cron/v3"
	"gorm.io/gorm"
)

// AuditService handles physical audit operations
type AuditService struct {
	db        *database.DB
	cache     *cache.Cache
	scheduler *cron.Cron
}

// NewAuditService creates a new audit service
func NewAuditService(db *database.DB, cache *cache.Cache) *AuditService {
	return &AuditService{
		db:        db,
		cache:     cache,
		scheduler: cron.New(),
	}
}

// =====================================================
// Audit Schedules
// =====================================================

// CreateSchedule creates a new audit schedule
func (s *AuditService) CreateSchedule(ctx context.Context, tenantID, creatorID uuid.UUID, req *models.CreateAuditScheduleRequest) (*models.AuditSchedule, error) {
	schedule := &models.AuditSchedule{
		TenantID:          tenantID,
		ShopID:            req.ShopID,
		AuditType:         req.AuditType,
		Name:              req.Name,
		Description:       req.Description,
		IsEnabled:         true,
		CronExpression:    req.CronExpression,
		ScheduledTime:     req.ScheduledTime,
		DaysOfWeek:        req.DaysOfWeek,
		DaysOfMonth:       req.DaysOfMonth,
		IncludeCashAudit:  req.IncludeCashAudit,
		IncludeInventory:  req.IncludeInventory,
		InventoryScope:    req.InventoryScope,
		AssignedCounters:  req.AssignedCounters,
		AssignedAuditors:  req.AssignedAuditors,
		NotifyBefore:      req.NotifyBefore,
		ExpiresAfter:      req.ExpiresAfter,
		RequiresApproval:  req.RequiresApproval,
		ApprovalRoles:     req.ApprovalRoles,
		CreatedBy:         creatorID,
		CreatedAt:         time.Now(),
		UpdatedAt:         time.Now(),
	}

	// Set defaults
	if schedule.NotifyBefore == 0 {
		schedule.NotifyBefore = 30
	}
	if schedule.ExpiresAfter == 0 {
		schedule.ExpiresAfter = 60
	}

	// Calculate next run
	schedule.NextRunAt = s.calculateNextRun(schedule)

	if err := s.db.WithContext(ctx).Create(schedule).Error; err != nil {
		return nil, err
	}

	return schedule, nil
}

// UpdateSchedule updates an audit schedule
func (s *AuditService) UpdateSchedule(ctx context.Context, scheduleID uuid.UUID, updates map[string]interface{}) error {
	updates["updated_at"] = time.Now()
	return s.db.WithContext(ctx).Model(&models.AuditSchedule{}).
		Where("id = ?", scheduleID).
		Updates(updates).Error
}

// EnableSchedule enables/disables a schedule
func (s *AuditService) EnableSchedule(ctx context.Context, scheduleID uuid.UUID, enabled bool) error {
	return s.db.WithContext(ctx).Model(&models.AuditSchedule{}).
		Where("id = ?", scheduleID).
		Updates(map[string]interface{}{
			"is_enabled": enabled,
			"updated_at": time.Now(),
		}).Error
}

// GetSchedules returns audit schedules
func (s *AuditService) GetSchedules(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, auditType string) ([]models.AuditSchedule, error) {
	var schedules []models.AuditSchedule

	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}
	if auditType != "" {
		query = query.Where("audit_type = ?", auditType)
	}

	err := query.
		Preload("Shop").
		Order("created_at DESC").
		Find(&schedules).Error

	return schedules, err
}

// RunScheduledAudits creates audit sessions for due schedules
func (s *AuditService) RunScheduledAudits(ctx context.Context) error {
	now := time.Now()

	var dueSchedules []models.AuditSchedule
	if err := s.db.WithContext(ctx).
		Where("is_enabled = true AND next_run_at <= ? AND deleted_at IS NULL", now).
		Find(&dueSchedules).Error; err != nil {
		return err
	}

	for _, schedule := range dueSchedules {
		// Create audit session
		shopID := schedule.ShopID
		if shopID == nil {
			continue // Skip tenant-level schedules without shop
		}

		_, err := s.CreateAuditSession(ctx, schedule.TenantID, &models.CreateAuditSessionRequest{
			ShopID:           *shopID,
			AuditType:        schedule.AuditType,
			TriggerType:      models.AuditTriggerScheduled,
			ScheduledAt:      now,
			AssignedCounters: schedule.AssignedCounters,
			IncludeCashAudit: schedule.IncludeCashAudit,
			IncludeInventory: schedule.IncludeInventory,
			InventoryScope:   schedule.InventoryScope,
		})

		if err == nil {
			// Update schedule
			nextRun := s.calculateNextRun(&schedule)
			s.db.WithContext(ctx).Model(&schedule).Updates(map[string]interface{}{
				"last_run_at": now,
				"next_run_at": nextRun,
				"updated_at":  now,
			})

			// Send notifications
			s.sendAuditNotifications(ctx, &schedule, "reminder")
		}
	}

	return nil
}

func (s *AuditService) calculateNextRun(schedule *models.AuditSchedule) *time.Time {
	if schedule.CronExpression != "" {
		parser := cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow)
		cronSchedule, err := parser.Parse(schedule.CronExpression)
		if err == nil {
			next := cronSchedule.Next(time.Now())
			return &next
		}
	}

	// Calculate based on days of week/month and scheduled time
	now := time.Now()
	var next time.Time

	if len(schedule.DaysOfWeek) > 0 {
		// Weekly schedule
		currentDay := int(now.Weekday())
		for _, day := range schedule.DaysOfWeek {
			if day > currentDay {
				next = now.AddDate(0, 0, day-currentDay)
				break
			}
		}
		if next.IsZero() {
			// Next week
			next = now.AddDate(0, 0, 7-currentDay+schedule.DaysOfWeek[0])
		}
	} else if len(schedule.DaysOfMonth) > 0 {
		// Monthly schedule
		currentDay := now.Day()
		for _, day := range schedule.DaysOfMonth {
			if day > currentDay {
				next = time.Date(now.Year(), now.Month(), day, 0, 0, 0, 0, now.Location())
				break
			}
		}
		if next.IsZero() {
			// Next month
			next = time.Date(now.Year(), now.Month()+1, schedule.DaysOfMonth[0], 0, 0, 0, 0, now.Location())
		}
	} else {
		// Daily schedule
		next = now.AddDate(0, 0, 1)
	}

	// Apply scheduled time
	if schedule.ScheduledTime != "" {
		t, err := time.Parse("15:04", schedule.ScheduledTime)
		if err == nil {
			next = time.Date(next.Year(), next.Month(), next.Day(), t.Hour(), t.Minute(), 0, 0, next.Location())
		}
	}

	return &next
}

// =====================================================
// Audit Sessions
// =====================================================

// CreateAuditSession creates a new audit session
func (s *AuditService) CreateAuditSession(ctx context.Context, tenantID uuid.UUID, req *models.CreateAuditSessionRequest) (*models.AuditSession, error) {
	// Generate session number
	sessionNumber := s.generateSessionNumber(ctx, tenantID)

	now := time.Now()
	scheduledAt := req.ScheduledAt
	if scheduledAt.IsZero() {
		scheduledAt = now
	}

	expiresAt := scheduledAt.Add(60 * time.Minute) // Default 60 minutes

	session := &models.AuditSession{
		TenantID:         tenantID,
		ShopID:           req.ShopID,
		SessionNumber:    sessionNumber,
		AuditType:        req.AuditType,
		TriggerType:      req.TriggerType,
		Status:           models.AuditStatusScheduled,
		AuditDate:        time.Date(scheduledAt.Year(), scheduledAt.Month(), scheduledAt.Day(), 0, 0, 0, 0, scheduledAt.Location()),
		ScheduledAt:      scheduledAt,
		ExpiresAt:        &expiresAt,
		AuditorID:        req.AuditorID,
		AssignedCounters: req.AssignedCounters,
		IncludeCashAudit: req.IncludeCashAudit,
		IncludeInventory: req.IncludeInventory,
		InventoryScope:   req.InventoryScope,
		Notes:            req.Notes,
		CreatedAt:        now,
		UpdatedAt:        now,
	}

	if session.TriggerType == "" {
		session.TriggerType = models.AuditTriggerManual
	}

	if err := s.db.WithContext(ctx).Create(session).Error; err != nil {
		return nil, err
	}

	// Create cash audit record if needed
	if session.IncludeCashAudit {
		cashAudit := &models.CashAudit{
			TenantID:  tenantID,
			SessionID: session.ID,
			ShopID:    req.ShopID,
			CreatedAt: now,
			UpdatedAt: now,
		}
		// Get expected amount from system
		expectedAmount := s.getExpectedCashAmount(ctx, tenantID, req.ShopID)
		cashAudit.ExpectedAmount = expectedAmount
		cashAudit.SystemAmount = expectedAmount

		s.db.WithContext(ctx).Create(cashAudit)
	}

	// Create inventory audit record if needed
	if session.IncludeInventory {
		invAudit := &models.InventoryAudit{
			TenantID:    tenantID,
			SessionID:   session.ID,
			ShopID:      req.ShopID,
			Scope:       req.InventoryScope,
			CategoryIDs: req.CategoryIDs,
			ProductIDs:  req.ProductIDs,
			CreatedAt:   now,
			UpdatedAt:   now,
		}

		// Get total SKUs to count
		invAudit.TotalSKUs = s.getTotalSKUsToCount(ctx, tenantID, req.ShopID, invAudit)

		s.db.WithContext(ctx).Create(invAudit)
	}

	return session, nil
}

// StartAuditSession starts an audit session
func (s *AuditService) StartAuditSession(ctx context.Context, sessionID, auditorID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("id = ? AND status = ?", sessionID, models.AuditStatusScheduled).
		Updates(map[string]interface{}{
			"status":     models.AuditStatusInProgress,
			"started_at": now,
			"auditor_id": auditorID,
			"updated_at": now,
		}).Error
}

// GetAuditSession returns audit session details
func (s *AuditService) GetAuditSession(ctx context.Context, sessionID uuid.UUID) (*models.AuditSessionDetailResponse, error) {
	var session models.AuditSession
	if err := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("Auditor").
		Preload("Reviewer").
		First(&session, "id = ?", sessionID).Error; err != nil {
		return nil, err
	}

	response := &models.AuditSessionDetailResponse{
		Session: session,
	}

	// Get cash audit
	var cashAudit models.CashAudit
	if err := s.db.WithContext(ctx).
		Where("session_id = ?", sessionID).
		First(&cashAudit).Error; err == nil {
		response.CashAudit = &cashAudit
	}

	// Get inventory audit
	var invAudit models.InventoryAudit
	if err := s.db.WithContext(ctx).
		Where("session_id = ?", sessionID).
		Preload("Items").
		First(&invAudit).Error; err == nil {
		response.InventoryAudit = &invAudit
	}

	// Get variances
	s.db.WithContext(ctx).
		Where("session_id = ?", sessionID).
		Find(&response.Variances)

	// Build timeline
	response.Timeline = s.buildAuditTimeline(ctx, &session)

	return response, nil
}

// ListAuditSessions returns audit sessions
func (s *AuditService) ListAuditSessions(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, status string, page, pageSize int) ([]models.AuditSession, int64, error) {
	var sessions []models.AuditSession
	var total int64

	query := s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}

	query.Count(&total)

	offset := (page - 1) * pageSize
	err := query.
		Preload("Shop").
		Preload("Auditor").
		Order("scheduled_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&sessions).Error

	return sessions, total, err
}

// ExpireOverdueAudits marks overdue audits as expired
func (s *AuditService) ExpireOverdueAudits(ctx context.Context) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("status IN (?, ?) AND expires_at < ?",
			models.AuditStatusScheduled, models.AuditStatusInProgress, now).
		Update("status", models.AuditStatusExpired).Error
}

// =====================================================
// Cash Audit
// =====================================================

// SubmitCashCount submits cash count for an audit
func (s *AuditService) SubmitCashCount(ctx context.Context, auditorID uuid.UUID, req *models.SubmitCashCountRequest) (*models.CashAudit, error) {
	// Get cash audit
	var cashAudit models.CashAudit
	if err := s.db.WithContext(ctx).
		Where("session_id = ?", req.SessionID).
		First(&cashAudit).Error; err != nil {
		return nil, fmt.Errorf("cash audit not found for session")
	}

	// Calculate counted amount from denominations
	countedAmount := 0.0
	if req.Denominations != nil {
		countedAmount = req.Denominations.Total()
	}
	countedAmount += req.CoinTotal

	// Calculate variance
	variance := countedAmount - cashAudit.ExpectedAmount

	now := time.Now()
	cashAudit.CountedAmount = countedAmount
	cashAudit.VarianceAmount = variance
	cashAudit.Denominations = req.Denominations
	cashAudit.CoinTotal = req.CoinTotal
	cashAudit.IsBlindCount = req.IsBlindCount
	cashAudit.CountedAt = &now
	cashAudit.CountedBy = &auditorID
	cashAudit.Notes = req.Notes
	cashAudit.Photos = req.Photos
	cashAudit.UpdatedAt = now

	if err := s.db.WithContext(ctx).Save(&cashAudit).Error; err != nil {
		return nil, err
	}

	// Create variance record if significant
	if math.Abs(variance) > 0 {
		s.createAuditVariance(ctx, req.SessionID, cashAudit.ShopID, "cash", nil, req.CounterID,
			cashAudit.ExpectedAmount, countedAmount, variance, nil)
	}

	// Update session
	s.updateSessionVariances(ctx, req.SessionID)

	return &cashAudit, nil
}

// =====================================================
// Inventory Audit
// =====================================================

// SubmitInventoryCount submits inventory counts
func (s *AuditService) SubmitInventoryCount(ctx context.Context, auditorID uuid.UUID, req *models.SubmitInventoryCountRequest) (*models.InventoryAudit, error) {
	// Get inventory audit
	var invAudit models.InventoryAudit
	if err := s.db.WithContext(ctx).
		Where("session_id = ?", req.SessionID).
		First(&invAudit).Error; err != nil {
		return nil, fmt.Errorf("inventory audit not found for session")
	}

	now := time.Now()
	if invAudit.StartedAt == nil {
		invAudit.StartedAt = &now
	}

	totalVarianceQty := 0
	totalVarianceValue := 0.0
	varianceSKUs := 0
	countedSKUs := 0

	for _, item := range req.Items {
		// Get system quantity and cost
		systemQty, unitCost := s.getProductStock(ctx, invAudit.TenantID, invAudit.ShopID, item.ProductID)

		varianceQty := systemQty - item.CountedQuantity
		varianceValue := float64(varianceQty) * unitCost

		auditItem := &models.InventoryAuditItem{
			TenantID:         invAudit.TenantID,
			InventoryAuditID: invAudit.ID,
			ProductID:        item.ProductID,
			LocationCode:     item.LocationCode,
			SystemQuantity:   systemQty,
			CountedQuantity:  &item.CountedQuantity,
			VarianceQuantity: varianceQty,
			UnitCost:         unitCost,
			VarianceValue:    varianceValue,
			BatchNumber:      item.BatchNumber,
			ExpiryDate:       item.ExpiryDate,
			CountedAt:        &now,
			CountedBy:        &auditorID,
			Notes:            item.Notes,
			CreatedAt:        now,
			UpdatedAt:        now,
		}

		s.db.WithContext(ctx).Create(auditItem)

		countedSKUs++
		if varianceQty != 0 {
			varianceSKUs++
			totalVarianceQty += int(math.Abs(float64(varianceQty)))
			totalVarianceValue += math.Abs(varianceValue)

			// Create variance record
			s.createAuditVariance(ctx, req.SessionID, invAudit.ShopID, "inventory", &item.ProductID, "",
				float64(systemQty)*unitCost, float64(item.CountedQuantity)*unitCost, varianceValue, nil)
		}
	}

	// Update inventory audit
	invAudit.CountedSKUs = countedSKUs
	invAudit.VarianceSKUs = varianceSKUs
	invAudit.TotalVarianceQty = totalVarianceQty
	invAudit.TotalVarianceValue = totalVarianceValue
	invAudit.Notes = req.Notes
	invAudit.UpdatedAt = now

	if countedSKUs >= invAudit.TotalSKUs {
		invAudit.CompletedAt = &now
	}

	if err := s.db.WithContext(ctx).Save(&invAudit).Error; err != nil {
		return nil, err
	}

	// Update session
	s.updateSessionVariances(ctx, req.SessionID)

	return &invAudit, nil
}

// GetInventoryItemsToCount returns items to be counted
func (s *AuditService) GetInventoryItemsToCount(ctx context.Context, sessionID uuid.UUID) ([]models.InventoryAuditItem, error) {
	// Get inventory audit
	var invAudit models.InventoryAudit
	if err := s.db.WithContext(ctx).
		Where("session_id = ?", sessionID).
		First(&invAudit).Error; err != nil {
		return nil, err
	}

	// Get stock items based on scope
	var items []models.InventoryAuditItem

	stockQuery := s.db.WithContext(ctx).
		Table("stocks s").
		Select(`
			s.product_id,
			p.name as product_name,
			s.quantity as system_quantity,
			s.average_cost as unit_cost
		`).
		Joins("JOIN products p ON s.product_id = p.id").
		Where("s.tenant_id = ? AND s.shop_id = ? AND s.deleted_at IS NULL", invAudit.TenantID, invAudit.ShopID)

	switch invAudit.Scope {
	case "category":
		if len(invAudit.CategoryIDs) > 0 {
			stockQuery = stockQuery.Where("p.category_id IN ?", invAudit.CategoryIDs)
		}
	case "product":
		if len(invAudit.ProductIDs) > 0 {
			stockQuery = stockQuery.Where("s.product_id IN ?", invAudit.ProductIDs)
		}
	case "random":
		stockQuery = stockQuery.Order("RANDOM()").Limit(50)
	case "low_stock":
		stockQuery = stockQuery.Where("s.quantity <= s.minimum_level")
	case "high_value":
		stockQuery = stockQuery.Order("s.quantity * s.average_cost DESC").Limit(50)
	}

	stockQuery.Scan(&items)
	return items, nil
}

// =====================================================
// Review & Approval
// =====================================================

// SubmitForReview submits audit for review
func (s *AuditService) SubmitForReview(ctx context.Context, sessionID uuid.UUID) error {
	now := time.Now()

	// Check if audit is complete
	var session models.AuditSession
	if err := s.db.WithContext(ctx).First(&session, "id = ?", sessionID).Error; err != nil {
		return err
	}

	if session.IncludeCashAudit {
		var cashAudit models.CashAudit
		if err := s.db.WithContext(ctx).Where("session_id = ?", sessionID).First(&cashAudit).Error; err != nil {
			return fmt.Errorf("cash audit not completed")
		}
		if cashAudit.CountedAt == nil {
			return fmt.Errorf("cash count not submitted")
		}
	}

	if session.IncludeInventory {
		var invAudit models.InventoryAudit
		if err := s.db.WithContext(ctx).Where("session_id = ?", sessionID).First(&invAudit).Error; err != nil {
			return fmt.Errorf("inventory audit not completed")
		}
		if invAudit.CountedSKUs < invAudit.TotalSKUs {
			return fmt.Errorf("inventory count not complete: %d/%d SKUs counted", invAudit.CountedSKUs, invAudit.TotalSKUs)
		}
	}

	return s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("id = ?", sessionID).
		Updates(map[string]interface{}{
			"status":       models.AuditStatusPendingReview,
			"completed_at": now,
			"updated_at":   now,
		}).Error
}

// ReviewAudit reviews and approves/rejects an audit
func (s *AuditService) ReviewAudit(ctx context.Context, reviewerID uuid.UUID, req *models.ReviewAuditRequest) error {
	now := time.Now()

	updates := map[string]interface{}{
		"status":       req.Status,
		"reviewer_id":  reviewerID,
		"reviewed_at":  now,
		"review_notes": req.ReviewNotes,
		"updated_at":   now,
	}

	return s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("id = ? AND status = ?", req.SessionID, models.AuditStatusPendingReview).
		Updates(updates).Error
}

// =====================================================
// Variance Resolution
// =====================================================

// ResolveVariance resolves an audit variance
func (s *AuditService) ResolveVariance(ctx context.Context, resolverID uuid.UUID, req *models.ResolveVarianceRequest) (*models.AuditResolution, error) {
	// Get variance
	var variance models.AuditVariance
	if err := s.db.WithContext(ctx).First(&variance, "id = ?", req.VarianceID).Error; err != nil {
		return nil, err
	}

	now := time.Now()

	resolution := &models.AuditResolution{
		TenantID:       variance.TenantID,
		VarianceID:     req.VarianceID,
		ResolutionType: req.ResolutionType,
		Amount:         req.Amount,
		Description:    req.Description,
		Attachments:    req.Attachments,
		CreatedBy:      resolverID,
		CreatedAt:      now,
	}

	if err := s.db.WithContext(ctx).Create(resolution).Error; err != nil {
		return nil, err
	}

	// Update variance status
	s.db.WithContext(ctx).Model(&variance).Updates(map[string]interface{}{
		"status":     models.VarianceStatusResolved,
		"updated_at": now,
	})

	return resolution, nil
}

// GetOpenVariances returns unresolved variances
func (s *AuditService) GetOpenVariances(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]models.AuditVariance, error) {
	var variances []models.AuditVariance

	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND status IN (?, ?)", tenantID, models.VarianceStatusOpen, models.VarianceStatusInvestigating)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.
		Preload("Session").
		Preload("Product").
		Order("severity DESC, created_at DESC").
		Find(&variances).Error

	return variances, err
}

// =====================================================
// Dashboard & Reports
// =====================================================

// GetDashboard returns audit dashboard data
func (s *AuditService) GetDashboard(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) (*models.AuditDashboardResponse, error) {
	response := &models.AuditDashboardResponse{}

	// Get summary
	response.Summary = s.getAuditSummary(ctx, tenantID, shopID)

	// Get scheduled audits for today
	today := time.Now().Truncate(24 * time.Hour)
	tomorrow := today.Add(24 * time.Hour)

	var scheduled []models.AuditSession
	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND status = ? AND scheduled_at BETWEEN ? AND ?",
			tenantID, models.AuditStatusScheduled, today, tomorrow)
	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}
	query.Preload("Shop").Find(&scheduled)
	response.ScheduledAudits = scheduled

	// Get pending review
	var pending []models.AuditSession
	pendingQuery := s.db.WithContext(ctx).
		Where("tenant_id = ? AND status = ?", tenantID, models.AuditStatusPendingReview)
	if shopID != nil {
		pendingQuery = pendingQuery.Where("shop_id = ?", *shopID)
	}
	pendingQuery.Preload("Shop").Find(&pending)
	response.PendingReview = pending

	// Get open variances
	openVariances, _ := s.GetOpenVariances(ctx, tenantID, shopID)
	response.OpenVariances = openVariances

	// Get trends
	response.CompletionTrend = s.getCompletionTrend(ctx, tenantID, shopID, 7)
	response.VarianceTrend = s.getVarianceTrend(ctx, tenantID, shopID, 7)

	return response, nil
}

func (s *AuditService) getAuditSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) models.AuditSummary {
	summary := models.AuditSummary{}
	today := time.Now().Truncate(24 * time.Hour)
	tomorrow := today.Add(24 * time.Hour)

	// Use int64 variables for GORM Count() compatibility
	var scheduledToday, completedToday, pendingReview, overdueAudits, openVariances int64

	baseQuery := func() *gorm.DB {
		q := s.db.WithContext(ctx).Model(&models.AuditSession{}).Where("tenant_id = ?", tenantID)
		if shopID != nil {
			q = q.Where("shop_id = ?", *shopID)
		}
		return q
	}

	// Scheduled today
	baseQuery().Where("status = ? AND scheduled_at BETWEEN ? AND ?",
		models.AuditStatusScheduled, today, tomorrow).Count(&scheduledToday)

	// Completed today
	baseQuery().Where("status = ? AND completed_at BETWEEN ? AND ?",
		models.AuditStatusApproved, today, tomorrow).Count(&completedToday)

	// Pending review
	baseQuery().Where("status = ?", models.AuditStatusPendingReview).Count(&pendingReview)

	// Overdue
	baseQuery().Where("status IN (?, ?) AND expires_at < ?",
		models.AuditStatusScheduled, models.AuditStatusInProgress, time.Now()).Count(&overdueAudits)

	// Open variances
	varQuery := s.db.WithContext(ctx).Model(&models.AuditVariance{}).
		Where("tenant_id = ? AND status IN (?, ?)", tenantID, models.VarianceStatusOpen, models.VarianceStatusInvestigating)
	if shopID != nil {
		varQuery = varQuery.Where("shop_id = ?", *shopID)
	}
	varQuery.Count(&openVariances)

	// Assign to summary struct
	summary.ScheduledToday = int(scheduledToday)
	summary.CompletedToday = int(completedToday)
	summary.PendingReview = int(pendingReview)
	summary.OverdueAudits = int(overdueAudits)
	summary.OpenVariances = int(openVariances)

	// Total variance value
	s.db.WithContext(ctx).Model(&models.AuditVariance{}).
		Where("tenant_id = ? AND status IN (?, ?)", tenantID, models.VarianceStatusOpen, models.VarianceStatusInvestigating).
		Select("COALESCE(SUM(ABS(variance_value)), 0)").Scan(&summary.TotalVarianceValue)

	// Completion rate (last 30 days)
	thirtyDaysAgo := time.Now().AddDate(0, 0, -30)
	var totalAudits, completedAudits int64
	baseQuery().Where("scheduled_at >= ?", thirtyDaysAgo).Count(&totalAudits)
	baseQuery().Where("status = ? AND scheduled_at >= ?", models.AuditStatusApproved, thirtyDaysAgo).Count(&completedAudits)
	if totalAudits > 0 {
		summary.CompletionRate = float64(completedAudits) / float64(totalAudits) * 100
	}

	return summary
}

func (s *AuditService) getCompletionTrend(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, days int) []models.DailyAuditStat {
	var trend []models.DailyAuditStat
	startDate := time.Now().AddDate(0, 0, -days)

	query := s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Select(`
			DATE(scheduled_at) as date,
			COUNT(CASE WHEN status = 'scheduled' THEN 1 END) as scheduled_count,
			COUNT(CASE WHEN status = 'approved' THEN 1 END) as completed_count,
			COUNT(CASE WHEN status = 'expired' THEN 1 END) as expired_count,
			COUNT(CASE WHEN status = 'approved' THEN 1 END) as approved_count,
			COUNT(CASE WHEN status = 'rejected' THEN 1 END) as rejected_count
		`).
		Where("tenant_id = ? AND scheduled_at >= ?", tenantID, startDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	query.Group("DATE(scheduled_at)").Order("date").Scan(&trend)
	return trend
}

func (s *AuditService) getVarianceTrend(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, days int) []models.DailyVarianceStat {
	var trend []models.DailyVarianceStat
	startDate := time.Now().AddDate(0, 0, -days)

	query := s.db.WithContext(ctx).Model(&models.AuditVariance{}).
		Select(`
			DATE(created_at) as date,
			SUM(CASE WHEN variance_type = 'cash' THEN ABS(variance_value) ELSE 0 END) as cash_variance,
			SUM(CASE WHEN variance_type = 'inventory' THEN ABS(variance_value) ELSE 0 END) as inv_variance,
			SUM(ABS(variance_value)) as total_variance,
			COUNT(*) as variance_count
		`).
		Where("tenant_id = ? AND created_at >= ?", tenantID, startDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	query.Group("DATE(created_at)").Order("date").Scan(&trend)
	return trend
}

// =====================================================
// Helper Functions
// =====================================================

func (s *AuditService) generateSessionNumber(ctx context.Context, tenantID uuid.UUID) string {
	var count int64
	s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("tenant_id = ?", tenantID).
		Count(&count)
	return fmt.Sprintf("AUD-%s-%05d", time.Now().Format("200601"), count+1)
}

func (s *AuditService) getExpectedCashAmount(ctx context.Context, tenantID, shopID uuid.UUID) float64 {
	// Get expected cash from daily sales
	var expected float64
	s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select("COALESCE(SUM(total_cash_amount), 0)").
		Where("tenant_id = ? AND shop_id = ? AND record_date = ? AND status = 'approved'",
			tenantID, shopID, time.Now().Format("2006-01-02")).
		Scan(&expected)
	return expected
}

func (s *AuditService) getTotalSKUsToCount(ctx context.Context, tenantID, shopID uuid.UUID, invAudit *models.InventoryAudit) int {
	var count int64

	query := s.db.WithContext(ctx).Model(&models.Stock{}).
		Where("tenant_id = ? AND shop_id = ? AND deleted_at IS NULL", tenantID, shopID)

	switch invAudit.Scope {
	case "category":
		if len(invAudit.CategoryIDs) > 0 {
			query = query.Joins("JOIN products p ON stocks.product_id = p.id").
				Where("p.category_id IN ?", invAudit.CategoryIDs)
		}
	case "product":
		if len(invAudit.ProductIDs) > 0 {
			query = query.Where("product_id IN ?", invAudit.ProductIDs)
		}
	case "random", "high_value":
		return 50 // Fixed count for random/high value
	case "low_stock":
		query = query.Where("quantity <= minimum_level")
	}

	query.Count(&count)
	return int(count)
}

func (s *AuditService) getProductStock(ctx context.Context, tenantID, shopID, productID uuid.UUID) (int, float64) {
	var stock models.Stock
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND shop_id = ? AND product_id = ?", tenantID, shopID, productID).
		First(&stock).Error; err != nil {
		return 0, 0
	}
	return stock.Quantity, stock.AverageCost
}

func (s *AuditService) createAuditVariance(ctx context.Context, sessionID, shopID uuid.UUID, varType string, productID *uuid.UUID, counterID string, expected, actual, variance float64, responsible *uuid.UUID) {
	variancePercent := 0.0
	if expected != 0 {
		variancePercent = (variance / expected) * 100
	}

	severity := models.VarianceSeverityMinor
	absVariance := math.Abs(variance)
	if absVariance > 10000 {
		severity = models.VarianceSeverityCritical
	} else if absVariance > 5000 {
		severity = models.VarianceSeverityMajor
	} else if absVariance > 1000 {
		severity = models.VarianceSeverityModerate
	}

	// Get session for tenant ID
	var session models.AuditSession
	s.db.WithContext(ctx).First(&session, "id = ?", sessionID)

	varianceRecord := &models.AuditVariance{
		TenantID:          session.TenantID,
		SessionID:         sessionID,
		ShopID:            shopID,
		VarianceType:      varType,
		ProductID:         productID,
		CounterID:         counterID,
		ExpectedValue:     expected,
		ActualValue:       actual,
		VarianceValue:     variance,
		VariancePercent:   variancePercent,
		Severity:          severity,
		Status:            models.VarianceStatusOpen,
		ResponsibleUserID: responsible,
		CreatedAt:         time.Now(),
		UpdatedAt:         time.Now(),
	}

	s.db.WithContext(ctx).Create(varianceRecord)
}

func (s *AuditService) updateSessionVariances(ctx context.Context, sessionID uuid.UUID) {
	var stats struct {
		Count int64
		Total float64
	}

	s.db.WithContext(ctx).Model(&models.AuditVariance{}).
		Select("COUNT(*) as count, COALESCE(SUM(ABS(variance_value)), 0) as total").
		Where("session_id = ?", sessionID).
		Scan(&stats)

	s.db.WithContext(ctx).Model(&models.AuditSession{}).
		Where("id = ?", sessionID).
		Updates(map[string]interface{}{
			"variance_count":       stats.Count,
			"total_variance_value": stats.Total,
			"updated_at":           time.Now(),
		})
}

func (s *AuditService) buildAuditTimeline(ctx context.Context, session *models.AuditSession) []models.AuditTimelineEvent {
	var timeline []models.AuditTimelineEvent

	// Add scheduled event
	timeline = append(timeline, models.AuditTimelineEvent{
		Timestamp:   session.CreatedAt,
		EventType:   "scheduled",
		Description: "Audit scheduled",
	})

	if session.StartedAt != nil {
		timeline = append(timeline, models.AuditTimelineEvent{
			Timestamp:   *session.StartedAt,
			EventType:   "started",
			Description: "Audit started",
			UserID:      session.AuditorID,
		})
	}

	if session.CompletedAt != nil {
		timeline = append(timeline, models.AuditTimelineEvent{
			Timestamp:   *session.CompletedAt,
			EventType:   "completed",
			Description: "Audit completed",
		})
	}

	if session.ReviewedAt != nil {
		status := "approved"
		if session.Status == models.AuditStatusRejected {
			status = "rejected"
		}
		timeline = append(timeline, models.AuditTimelineEvent{
			Timestamp:   *session.ReviewedAt,
			EventType:   "reviewed",
			Description: fmt.Sprintf("Audit %s", status),
			UserID:      session.ReviewerID,
		})
	}

	return timeline
}

func (s *AuditService) sendAuditNotifications(ctx context.Context, schedule *models.AuditSchedule, notificationType string) {
	// This would integrate with the notification service
	// Implementation depends on notification service setup
}
