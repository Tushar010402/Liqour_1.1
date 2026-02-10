package services

import (
	"context"
	"log"
	"time"

	"github.com/robfig/cron/v3"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// PendingSalesScheduler checks for pending sales and sends reminders to approvers
type PendingSalesScheduler struct {
	db                   *database.DB
	workflowNotification *notifservices.WorkflowNotificationService
	cron                 *cron.Cron
}

// NewPendingSalesScheduler creates a new pending sales scheduler
func NewPendingSalesScheduler(db *database.DB, wn *notifservices.WorkflowNotificationService) *PendingSalesScheduler {
	// Use IST timezone for scheduling
	ist := time.FixedZone("IST", 5*60*60+30*60)
	return &PendingSalesScheduler{
		db:                   db,
		workflowNotification: wn,
		cron:                 cron.New(cron.WithLocation(ist)),
	}
}

// Start begins the scheduler
func (s *PendingSalesScheduler) Start() {
	// Run every 30 minutes to check for pending sales
	_, err := s.cron.AddFunc("*/30 * * * *", s.checkPendingSales)
	if err != nil {
		log.Printf("[SCHEDULER] Failed to add pending sales check: %v", err)
	}

	_, err = s.cron.AddFunc("*/30 * * * *", s.checkPendingDailySales)
	if err != nil {
		log.Printf("[SCHEDULER] Failed to add pending daily sales check: %v", err)
	}

	s.cron.Start()
	log.Println("[SCHEDULER] Pending sales reminder scheduler started (runs every 30 minutes)")
}

// Stop gracefully stops the scheduler
func (s *PendingSalesScheduler) Stop() {
	ctx := s.cron.Stop()
	<-ctx.Done()
	log.Println("[SCHEDULER] Pending sales reminder scheduler stopped")
}

// checkPendingSales checks for pending sales and sends reminders
func (s *PendingSalesScheduler) checkPendingSales() {
	ctx := context.Background()
	now := time.Now()

	log.Println("[SCHEDULER] Checking for pending sales...")

	// Escalating reminder thresholds - checked in reverse priority order (highest first)
	// Uses last_reminder_level column to ensure each sale gets at most ONE notification per level
	thresholds := []struct {
		minAge time.Duration
		level  int
	}{
		{12 * time.Hour, 3}, // Critical - pending 12+ hours
		{4 * time.Hour, 2},  // Urgent - pending 4+ hours
		{2 * time.Hour, 1},  // Normal - pending 2+ hours
	}

	for _, threshold := range thresholds {
		ageCutoff := now.Add(-threshold.minAge)

		// Query: pending sales older than threshold that haven't been notified at this level yet
		var pendingSales []models.Sale
		err := s.db.Where(
			"status = ? AND created_at <= ? AND last_reminder_level < ? AND deleted_at IS NULL",
			"pending", ageCutoff, threshold.level,
		).Preload("Shop").Preload("CreatedBy").Find(&pendingSales).Error

		if err != nil {
			log.Printf("[SCHEDULER] Failed to fetch pending sales for level %d: %v", threshold.level, err)
			continue
		}

		if len(pendingSales) > 0 {
			log.Printf("[SCHEDULER] Found %d pending sales for level %d reminders", len(pendingSales), threshold.level)
		}

		for _, sale := range pendingSales {
			if sale.TenantID != nil {
				if err := s.workflowNotification.NotifyPendingSalesReminder(ctx, &sale, threshold.level); err != nil {
					log.Printf("[SCHEDULER] Failed to send reminder for sale %s: %v", sale.SaleNumber, err)
					continue
				}

				// Mark this sale as notified at this level to prevent re-sending
				s.db.Model(&models.Sale{}).Where("id = ?", sale.ID).Updates(map[string]interface{}{
					"last_reminder_level":   threshold.level,
					"last_reminder_sent_at": now,
				})
			}
		}
	}
}

// checkPendingDailySales checks for pending daily sales records and sends reminders
func (s *PendingSalesScheduler) checkPendingDailySales() {
	ctx := context.Background()
	now := time.Now()

	log.Println("[SCHEDULER] Checking for pending daily sales records...")

	// Same escalating threshold logic for daily sales records
	thresholds := []struct {
		minAge time.Duration
		level  int
	}{
		{12 * time.Hour, 3}, // Critical - pending 12+ hours
		{4 * time.Hour, 2},  // Urgent - pending 4+ hours
		{2 * time.Hour, 1},  // Normal - pending 2+ hours
	}

	for _, threshold := range thresholds {
		ageCutoff := now.Add(-threshold.minAge)

		// Query: pending daily sales older than threshold that haven't been notified at this level yet
		var pendingRecords []models.DailySalesRecord
		err := s.db.Where(
			"status = ? AND created_at <= ? AND last_reminder_level < ? AND deleted_at IS NULL",
			"pending", ageCutoff, threshold.level,
		).Preload("Shop").Preload("CreatedBy").Find(&pendingRecords).Error

		if err != nil {
			log.Printf("[SCHEDULER] Failed to fetch pending daily sales for level %d: %v", threshold.level, err)
			continue
		}

		if len(pendingRecords) > 0 {
			log.Printf("[SCHEDULER] Found %d pending daily sales records for level %d reminders", len(pendingRecords), threshold.level)
		}

		for _, record := range pendingRecords {
			if record.TenantID != nil {
				if err := s.workflowNotification.NotifyPendingDailySalesReminder(ctx, &record, threshold.level); err != nil {
					log.Printf("[SCHEDULER] Failed to send reminder for daily sales %s: %v", record.ID, err)
					continue
				}

				// Mark this record as notified at this level to prevent re-sending
				s.db.Model(&models.DailySalesRecord{}).Where("id = ?", record.ID).Updates(map[string]interface{}{
					"last_reminder_level":   threshold.level,
					"last_reminder_sent_at": now,
				})
			}
		}
	}
}
