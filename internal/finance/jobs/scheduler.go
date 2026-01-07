package jobs

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/audit/services"
	detectionServices "github.com/liquorpro/go-backend/internal/detection/services"
	financeServices "github.com/liquorpro/go-backend/internal/finance/services"
	notificationServices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/robfig/cron/v3"
)

// JobScheduler manages background jobs for finance, detection, and audit
type JobScheduler struct {
	db                  *database.DB
	cron                *cron.Cron
	financeService      *financeServices.FinanceMatrixService
	detectionService    *detectionServices.DetectionService
	auditService        *services.AuditService
	notificationService *notificationServices.NotificationService
}

// NewJobScheduler creates a new job scheduler
func NewJobScheduler(
	db *database.DB,
	financeService *financeServices.FinanceMatrixService,
	detectionService *detectionServices.DetectionService,
	auditService *services.AuditService,
	notificationService *notificationServices.NotificationService,
) *JobScheduler {
	return &JobScheduler{
		db:                  db,
		cron:                cron.New(cron.WithSeconds()),
		financeService:      financeService,
		detectionService:    detectionService,
		auditService:        auditService,
		notificationService: notificationService,
	}
}

// Start starts all scheduled jobs
func (s *JobScheduler) Start() {
	// Daily metrics computation - runs at 1 AM
	s.cron.AddFunc("0 0 1 * * *", func() {
		log.Println("[JOB] Starting daily metrics computation")
		s.computeDailyMetrics()
	})

	// Hourly variance checks - runs every hour at :15
	s.cron.AddFunc("0 15 * * * *", func() {
		log.Println("[JOB] Starting hourly variance checks")
		s.runVarianceChecks()
	})

	// Alert escalation - runs every 10 minutes
	s.cron.AddFunc("0 */10 * * * *", func() {
		s.escalateOverdueAlerts()
	})

	// Scheduled audits - runs every 5 minutes
	s.cron.AddFunc("0 */5 * * * *", func() {
		s.runScheduledAudits()
	})

	// Expire overdue audits - runs every 15 minutes
	s.cron.AddFunc("0 */15 * * * *", func() {
		s.expireOverdueAudits()
	})

	// Daily digest notifications - runs at 8 AM
	s.cron.AddFunc("0 0 8 * * *", func() {
		log.Println("[JOB] Sending daily digest notifications")
		s.sendDailyDigests()
	})

	// Hourly digest notifications - runs every hour at :00
	s.cron.AddFunc("0 0 * * * *", func() {
		s.sendHourlyDigests()
	})

	// Weekly digest notifications - runs on Monday at 9 AM
	s.cron.AddFunc("0 0 9 * * 1", func() {
		log.Println("[JOB] Sending weekly digest notifications")
		s.sendWeeklyDigests()
	})

	// Credit aging update - runs at 2 AM
	s.cron.AddFunc("0 0 2 * * *", func() {
		log.Println("[JOB] Updating credit aging")
		s.updateCreditAging()
	})

	// Detection metrics aggregation - runs at 3 AM
	s.cron.AddFunc("0 0 3 * * *", func() {
		log.Println("[JOB] Aggregating detection metrics")
		s.aggregateDetectionMetrics()
	})

	// Start the cron scheduler
	s.cron.Start()
	log.Println("[JOB] Scheduler started with", len(s.cron.Entries()), "jobs")
}

// Stop stops the scheduler
func (s *JobScheduler) Stop() {
	s.cron.Stop()
	log.Println("[JOB] Scheduler stopped")
}

// computeDailyMetrics computes daily finance metrics for all tenants/shops
func (s *JobScheduler) computeDailyMetrics() {
	ctx := context.Background()
	yesterday := time.Now().AddDate(0, 0, -1)

	// Get all active tenant-shop combinations
	var shops []struct {
		TenantID uuid.UUID
		ShopID   uuid.UUID
	}

	s.db.WithContext(ctx).
		Table("shops").
		Select("tenant_id, id as shop_id").
		Where("deleted_at IS NULL AND is_active = true").
		Scan(&shops)

	for _, shop := range shops {
		err := s.financeService.ComputeDailyMetrics(ctx, shop.TenantID, shop.ShopID, yesterday)
		if err != nil {
			log.Printf("[JOB] Error computing metrics for shop %s: %v", shop.ShopID, err)
		}
	}

	log.Printf("[JOB] Computed daily metrics for %d shops", len(shops))
}

// runVarianceChecks runs variance detection checks
func (s *JobScheduler) runVarianceChecks() {
	ctx := context.Background()
	today := time.Now()

	// Get daily sales records that need variance checking
	var records []struct {
		TenantID         uuid.UUID
		ShopID           uuid.UUID
		TotalCashAmount  float64
		TotalSalesAmount float64
		SalesmanID       uuid.UUID
	}

	s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select("tenant_id, shop_id, total_cash_amount, total_sales_amount, salesman_id").
		Where("record_date = ? AND status = 'approved'", today.Format("2006-01-02")).
		Scan(&records)

	for _, record := range records {
		// Get expected vs actual for cash variance
		var cashHolding models.CashHolding
		s.db.WithContext(ctx).
			Where("tenant_id = ? AND shop_id = ? AND user_id = ?",
				record.TenantID, record.ShopID, record.SalesmanID).
			First(&cashHolding)

		// Analyze cash variance
		s.detectionService.AnalyzeCashVariance(
			ctx,
			record.TenantID,
			record.ShopID,
			today,
			record.TotalCashAmount,
			cashHolding.CurrentBalance,
			[]uuid.UUID{record.SalesmanID},
		)

		// Analyze discount patterns
		s.detectionService.AnalyzeDiscountPatterns(ctx, record.TenantID, record.SalesmanID, today)
	}

	log.Printf("[JOB] Completed variance checks for %d records", len(records))
}

// escalateOverdueAlerts escalates alerts that haven't been acknowledged
func (s *JobScheduler) escalateOverdueAlerts() {
	ctx := context.Background()
	if err := s.detectionService.EscalateAlerts(ctx); err != nil {
		log.Printf("[JOB] Error escalating alerts: %v", err)
	}
}

// runScheduledAudits creates audit sessions for due schedules
func (s *JobScheduler) runScheduledAudits() {
	ctx := context.Background()
	if err := s.auditService.RunScheduledAudits(ctx); err != nil {
		log.Printf("[JOB] Error running scheduled audits: %v", err)
	}
}

// expireOverdueAudits marks overdue audits as expired
func (s *JobScheduler) expireOverdueAudits() {
	ctx := context.Background()
	if err := s.auditService.ExpireOverdueAudits(ctx); err != nil {
		log.Printf("[JOB] Error expiring overdue audits: %v", err)
	}
}

// sendDailyDigests sends daily notification digests
func (s *JobScheduler) sendDailyDigests() {
	ctx := context.Background()
	if err := s.notificationService.SendDigests(ctx, models.DigestFrequencyDaily); err != nil {
		log.Printf("[JOB] Error sending daily digests: %v", err)
	}
}

// sendHourlyDigests sends hourly notification digests
func (s *JobScheduler) sendHourlyDigests() {
	ctx := context.Background()
	if err := s.notificationService.SendDigests(ctx, models.DigestFrequencyHourly); err != nil {
		log.Printf("[JOB] Error sending hourly digests: %v", err)
	}
}

// sendWeeklyDigests sends weekly notification digests
func (s *JobScheduler) sendWeeklyDigests() {
	ctx := context.Background()
	if err := s.notificationService.SendDigests(ctx, models.DigestFrequencyWeekly); err != nil {
		log.Printf("[JOB] Error sending weekly digests: %v", err)
	}
}

// updateCreditAging updates credit aging for all outstanding credits
func (s *JobScheduler) updateCreditAging() {
	ctx := context.Background()
	now := time.Now()

	// Update days_outstanding for all outstanding credits
	s.db.WithContext(ctx).Exec(`
		UPDATE credit_sales_aging
		SET
			days_outstanding = EXTRACT(DAY FROM (CURRENT_DATE - sale_date)),
			updated_at = NOW()
		WHERE status = 'outstanding' AND deleted_at IS NULL
	`)

	// Create finance alerts for overdue credits
	var overdueCredits []struct {
		TenantID          uuid.UUID
		ShopID            uuid.UUID
		CustomerID        uuid.UUID
		OutstandingAmount float64
		DaysOutstanding   int
	}

	s.db.WithContext(ctx).
		Table("credit_sales_aging").
		Select("tenant_id, shop_id, customer_id, outstanding_amount, days_outstanding").
		Where("status = 'outstanding' AND days_outstanding > 90 AND deleted_at IS NULL").
		Scan(&overdueCredits)

	for _, credit := range overdueCredits {
		// Check if alert already exists
		var existingAlert models.FinanceAlert
		err := s.db.WithContext(ctx).
			Where("tenant_id = ? AND shop_id = ? AND alert_type = 'credit_overdue' AND related_entity_id = ? AND status IN ('active', 'escalated')",
				credit.TenantID, credit.ShopID, credit.CustomerID).
			First(&existingAlert).Error

		if err != nil { // No existing alert
			alert := &models.FinanceAlert{
				TenantID:          credit.TenantID,
				ShopID:            &credit.ShopID,
				AlertType:         models.AlertTypeCreditOverdue,
				Severity:          models.AlertSeverityHigh,
				Title:             "Credit Overdue - 90+ Days",
				Message:           fmt.Sprintf("Outstanding credit of ₹%.2f is overdue by %d days", credit.OutstandingAmount, credit.DaysOutstanding),
				Amount:            &credit.OutstandingAmount,
				RelatedEntityID:   &credit.CustomerID,
				RelatedEntityType: "customer",
				Status:            models.AlertStatusActive,
				CreatedAt:         now,
				UpdatedAt:         now,
			}
			s.financeService.CreateFinanceAlert(ctx, alert)
		}
	}

	log.Printf("[JOB] Updated credit aging, found %d overdue credits", len(overdueCredits))
}

// aggregateDetectionMetrics aggregates daily detection metrics
func (s *JobScheduler) aggregateDetectionMetrics() {
	ctx := context.Background()
	yesterday := time.Now().AddDate(0, 0, -1)
	yesterdayDate := time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), 0, 0, 0, 0, yesterday.Location())

	// Aggregate cash variance metrics
	s.db.WithContext(ctx).Exec(`
		INSERT INTO detection_metrics (tenant_id, shop_id, metric_type, metric_date, value, rolling_mean, rolling_std_dev, sample_size, created_at, updated_at)
		SELECT
			tenant_id,
			shop_id,
			'cash_shortage' as metric_type,
			$1 as metric_date,
			COALESCE(SUM(CASE WHEN variance_type = 'shortage' THEN ABS(variance_amount) ELSE 0 END), 0) as value,
			(SELECT AVG(ABS(variance_amount)) FROM cash_variances WHERE variance_date >= $1 - INTERVAL '30 days'),
			(SELECT STDDEV(ABS(variance_amount)) FROM cash_variances WHERE variance_date >= $1 - INTERVAL '30 days'),
			(SELECT COUNT(*) FROM cash_variances WHERE variance_date >= $1 - INTERVAL '30 days'),
			NOW(),
			NOW()
		FROM cash_variances
		WHERE variance_date = $1
		GROUP BY tenant_id, shop_id
		ON CONFLICT (tenant_id, shop_id, metric_type, metric_date)
		DO UPDATE SET value = EXCLUDED.value, rolling_mean = EXCLUDED.rolling_mean, rolling_std_dev = EXCLUDED.rolling_std_dev, updated_at = NOW()
	`, yesterdayDate)

	// Aggregate discount abuse metrics
	s.db.WithContext(ctx).Exec(`
		INSERT INTO detection_metrics (tenant_id, shop_id, user_id, metric_type, metric_date, value, created_at, updated_at)
		SELECT
			tenant_id,
			shop_id,
			salesman_id as user_id,
			'discount_abuse' as metric_type,
			$1 as metric_date,
			COALESCE(SUM(discount_amount), 0) as value,
			NOW(),
			NOW()
		FROM daily_sales_records
		WHERE record_date = $1 AND status = 'approved'
		GROUP BY tenant_id, shop_id, salesman_id
		ON CONFLICT (tenant_id, shop_id, user_id, metric_type, metric_date)
		DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
	`, yesterdayDate)

	log.Println("[JOB] Completed detection metrics aggregation")
}

// RunOnce runs a specific job once (useful for testing or manual triggers)
func (s *JobScheduler) RunOnce(jobName string) error {
	switch jobName {
	case "daily_metrics":
		s.computeDailyMetrics()
	case "variance_checks":
		s.runVarianceChecks()
	case "escalate_alerts":
		s.escalateOverdueAlerts()
	case "scheduled_audits":
		s.runScheduledAudits()
	case "expire_audits":
		s.expireOverdueAudits()
	case "daily_digests":
		s.sendDailyDigests()
	case "credit_aging":
		s.updateCreditAging()
	case "detection_metrics":
		s.aggregateDetectionMetrics()
	default:
		return fmt.Errorf("unknown job: %s", jobName)
	}
	return nil
}
