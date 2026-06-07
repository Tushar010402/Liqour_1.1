package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// SmartStockJobService manages the persistent background-job layer for
// Smart Stock Setup extraction. It replaces the synchronous request/response
// pattern with submit-and-poll so users can close the app mid-extraction
// and resume later.
//
// Architecture (Postgres-backed, no Redis dependency for the queue itself):
//   - Submit stores images to disk + a row in smart_stock_setup_jobs with
//     status='pending'.
//   - A worker goroutine polls every workerPollInterval, claims one pending
//     job via "SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1", runs the existing
//     ProcessExtraction, and writes the result back.
//   - Clients poll GET /jobs/:id until status is terminal (done/failed/canceled).
//
// Why Postgres instead of the existing Redis Streams queue manager: the
// inventory service is a single-instance deploy (no horizontal scale yet),
// so the complexity of Redis consumer groups + DLQ isn't load-bearing.
// Postgres is already the source of truth for everything else; one table
// keeps state easy to inspect (psql), easy to retry (UPDATE), and
// restart-safe (all state persisted).
type SmartStockJobService struct {
	db          *database.DB
	mainService *SmartStockSetupService
}

// NewSmartStockJobService wires the job service to its dependencies. The main
// SmartStockSetupService is held so the worker can call ProcessExtraction
// without duplicating the matching/OCR pipeline.
func NewSmartStockJobService(db *database.DB, mainService *SmartStockSetupService) *SmartStockJobService {
	return &SmartStockJobService{db: db, mainService: mainService}
}

// --------------------------------------------------------------------------
// Worker tuning
// --------------------------------------------------------------------------

const (
	// Poll period when the queue is idle. Kept short because end-users poll
	// the status endpoint every 3-5s; a longer worker interval would
	// introduce visible lag between submit and start-of-processing.
	workerPollInterval = 3 * time.Second
	// Max concurrent jobs per process. Extraction is CPU-light (most time is
	// waiting on the AI vendor) but holds DB + HTTP connections, so start
	// conservative — one job at a time.
	workerMaxConcurrent = 1
	// Retry budget per job. A single flaky AI call shouldn't permanently
	// fail the user's submission. After 3 attempts the job is marked
	// permanently failed and the user is shown the last error.
	workerMaxRetries = 3
	// Upper-bound for a single job's processing phase. ProcessExtraction
	// already has its own 5-min context; this is a defensive outer bound
	// so a hung call can't pin the worker forever.
	workerJobTimeout = 6 * time.Minute
)

// --------------------------------------------------------------------------
// Submit
// --------------------------------------------------------------------------

// SubmitJobRequest carries everything needed to enqueue a single extraction.
// Images are provided as raw bytes so the handler doesn't leak file handles
// into the service layer.
type SubmitJobRequest struct {
	TenantID    string
	UserID      string
	ShopID      string
	CategoryID  string
	Size        string
	StockColumn string
	Images      []SmartPurchaseImage
}

// Submit persists a new job: saves images to a per-job directory and creates
// a row with status='pending'. Returns the fresh job ID so clients can poll.
//
// Image storage path: /app/uploads/stock_setup_jobs/{job_id}/image_N.{ext}
// — separate from the existing /app/uploads/stock_setup/{tenant_short}/
// location so per-job cleanup can `rm -rf` the entire directory without
// touching historical approval-review images.
func (s *SmartStockJobService) Submit(req SubmitJobRequest) (*models.SmartStockSetupJob, error) {
	if len(req.Images) == 0 {
		return nil, fmt.Errorf("at least one image is required")
	}
	if len(req.Images) > 5 {
		return nil, fmt.Errorf("maximum 5 images per job")
	}
	tenantUUID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}
	userUUID, err := uuid.Parse(req.UserID)
	if err != nil {
		return nil, fmt.Errorf("invalid user_id")
	}
	shopUUID, err := uuid.Parse(req.ShopID)
	if err != nil {
		return nil, fmt.Errorf("invalid shop_id")
	}
	var categoryUUID *uuid.UUID
	if req.CategoryID != "" {
		c, err := uuid.Parse(req.CategoryID)
		if err != nil {
			return nil, fmt.Errorf("invalid category_id")
		}
		categoryUUID = &c
	}

	// Pre-generate the job ID so we can name the image directory with it.
	jobID := uuid.New()

	// Per-job image directory. Nested under /app/uploads/stock_setup/jobs/
	// (rather than a sibling stock_setup_jobs/) because only the existing
	// mounted subdirs of /app/uploads are writable — the parent /app/uploads
	// itself is read-only in the container. Keeping it under stock_setup also
	// means cleanup tooling that already scans that tree picks these up.
	jobDir := filepath.Join("/app/uploads/stock_setup/jobs", jobID.String())
	if err := os.MkdirAll(jobDir, 0755); err != nil {
		return nil, fmt.Errorf("create job dir: %w", err)
	}

	imagePaths := make([]string, 0, len(req.Images))
	for i, img := range req.Images {
		ext := ".jpg"
		if strings.Contains(strings.ToLower(img.ContentType), "png") {
			ext = ".png"
		}
		fp := filepath.Join(jobDir, fmt.Sprintf("image_%d%s", i+1, ext))
		if err := os.WriteFile(fp, img.Data, 0644); err != nil {
			// Clean up partials so the job dir doesn't have a half-written set.
			_ = os.RemoveAll(jobDir)
			return nil, fmt.Errorf("write image %d: %w", i+1, err)
		}
		imagePaths = append(imagePaths, fp)
	}

	stockCol := req.StockColumn
	if stockCol == "" {
		stockCol = "total"
	}

	job := &models.SmartStockSetupJob{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: jobID},
			TenantID:  &tenantUUID,
		},
		UserID:      userUUID,
		ShopID:      shopUUID,
		Status:      models.StockSetupJobPending,
		CategoryID:  categoryUUID,
		Size:        req.Size,
		StockColumn: stockCol,
		ImagePaths:  models.JSONStringList(imagePaths),
	}
	if err := s.db.Create(job).Error; err != nil {
		_ = os.RemoveAll(jobDir)
		return nil, fmt.Errorf("insert job: %w", err)
	}
	log.Printf("Smart Stock Setup: job %s submitted (tenant=%s user=%s shop=%s images=%d)",
		jobID, req.TenantID, req.UserID, req.ShopID, len(imagePaths))
	return job, nil
}

// --------------------------------------------------------------------------
// Get / List / Cancel
// --------------------------------------------------------------------------

// Get returns a single job with strict tenant+user scoping — one user can't
// peek at another user's jobs even within the same tenant, because extraction
// can contain rate/sales figures the user isn't authorised to see.
func (s *SmartStockJobService) Get(jobID, tenantID, userID string) (*models.SmartStockSetupJob, error) {
	jobUUID, err := uuid.Parse(jobID)
	if err != nil {
		return nil, fmt.Errorf("invalid job_id")
	}
	tenantUUID, err := uuid.Parse(tenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}
	userUUID, err := uuid.Parse(userID)
	if err != nil {
		return nil, fmt.Errorf("invalid user_id")
	}
	var job models.SmartStockSetupJob
	err = s.db.Where("id = ? AND tenant_id = ? AND user_id = ?", jobUUID, tenantUUID, userUUID).
		First(&job).Error
	if err != nil {
		return nil, fmt.Errorf("job not found")
	}
	return &job, nil
}

// List returns this user's recent jobs, newest first. Limit clamped to
// [1, 50] so a pathological client can't request the full history.
func (s *SmartStockJobService) List(tenantID, userID string, limit int) ([]models.SmartStockSetupJob, error) {
	tenantUUID, err := uuid.Parse(tenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}
	userUUID, err := uuid.Parse(userID)
	if err != nil {
		return nil, fmt.Errorf("invalid user_id")
	}
	if limit <= 0 {
		limit = 20
	}
	if limit > 50 {
		limit = 50
	}
	var jobs []models.SmartStockSetupJob
	err = s.db.Where("tenant_id = ? AND user_id = ?", tenantUUID, userUUID).
		Order("created_at DESC").
		Limit(limit).
		Find(&jobs).Error
	return jobs, err
}

// Cancel marks a pending job as canceled. No-op (returns nil) if the job
// has already started processing or is terminal — once the worker claims a
// job, reversing is not worth the complexity.
func (s *SmartStockJobService) Cancel(jobID, tenantID, userID string) error {
	jobUUID, err := uuid.Parse(jobID)
	if err != nil {
		return fmt.Errorf("invalid job_id")
	}
	tenantUUID, err := uuid.Parse(tenantID)
	if err != nil {
		return fmt.Errorf("invalid tenant_id")
	}
	userUUID, err := uuid.Parse(userID)
	if err != nil {
		return fmt.Errorf("invalid user_id")
	}
	now := time.Now()
	res := s.db.Model(&models.SmartStockSetupJob{}).
		Where("id = ? AND tenant_id = ? AND user_id = ? AND status = ?",
			jobUUID, tenantUUID, userUUID, models.StockSetupJobPending).
		Updates(map[string]interface{}{
			"status":       models.StockSetupJobCanceled,
			"completed_at": now,
		})
	if res.Error != nil {
		return res.Error
	}
	// RowsAffected==0 is not an error — the job was just in a state where
	// cancel is meaningless (already processing/done/failed).
	return nil
}

// --------------------------------------------------------------------------
// Worker
// --------------------------------------------------------------------------

// StartWorker launches the background goroutine that drains the pending
// queue. Safe to call exactly once per service instance; subsequent calls
// would spawn duplicate workers (which is technically fine thanks to
// SKIP LOCKED, but wasteful).
//
// The worker exits cleanly when ctx is canceled — main.go passes a
// shutdown-aware context so draining a slow job during deploy doesn't
// leave a zombie process.
func (s *SmartStockJobService) StartWorker(ctx context.Context) {
	log.Printf("Smart Stock Setup: starting background worker (poll=%v, max_retries=%d)",
		workerPollInterval, workerMaxRetries)

	// Sentinel: on first boot, any job stuck in 'processing' is almost
	// certainly abandoned from a previous deploy (we crashed / got OOM'd
	// mid-job). Flip them back to pending so the retry path picks them up.
	// Bounded by retry_count to prevent infinite retry loops across deploys.
	s.rescueStalledJobs()

	// Global orphan cleanup on boot — runs the autofix across every tenant
	// so historical orphans (from brands onboarded BEFORE the per-creation
	// master-linkage was added) get cleaned up consistently. No manual Data
	// Hygiene intervention required. Runs in a goroutine so worker startup
	// stays fast; logs per-tenant results so any regressions are observable.
	go s.runGlobalOrphanAutofixOnBoot()

	go func() {
		ticker := time.NewTicker(workerPollInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Printf("Smart Stock Setup: worker shutting down")
				return
			case <-ticker.C:
				// processOne returns true when it did work; when it did we
				// immediately loop so a queued burst drains without a
				// full poll-interval pause per item.
				for s.processOne(ctx) {
					select {
					case <-ctx.Done():
						return
					default:
					}
				}
			}
		}
	}()
}

// rescueStalledJobs flips abandoned 'processing' rows back to 'pending' at
// worker startup so a crash mid-job doesn't leak a permanent processing
// state. Only runs once per boot.
// runGlobalOrphanAutofixOnBoot runs OrphansAutofix for every tenant that has
// at least one orphan product. Fires once on service startup as a safety net
// for tenants that haven't triggered an extraction recently (those tenants
// would otherwise keep their orphans indefinitely). Combined with the
// per-job autofix hook in storeJobResult and the brand-onboarding-time
// master linkage, this guarantees new tenants start clean AND existing
// ones eventually converge to a linked state.
func (s *SmartStockJobService) runGlobalOrphanAutofixOnBoot() {
	type tenantRow struct {
		TenantID    string
		OrphanCount int
	}
	var rows []tenantRow
	err := s.db.Raw(`
		SELECT tenant_id::text AS tenant_id, COUNT(*) AS orphan_count
		FROM products
		WHERE deleted_at IS NULL AND saas_brand_id IS NULL AND tenant_id IS NOT NULL
		GROUP BY tenant_id
		HAVING COUNT(*) >= 2
		ORDER BY orphan_count DESC
	`).Scan(&rows).Error
	if err != nil {
		log.Printf("Smart Stock Setup: global orphan autofix scan failed: %v", err)
		return
	}
	if len(rows) == 0 {
		log.Printf("Smart Stock Setup: no tenants with orphan products — global autofix skipped")
		return
	}
	log.Printf("Smart Stock Setup: running global orphan autofix on %d tenant(s) with ≥2 orphans", len(rows))
	for _, r := range rows {
		res, err := s.mainService.OrphansAutofix(OrphanAutofixRequest{
			TenantID: r.TenantID,
			DryRun:   false,
		})
		if err != nil {
			log.Printf("Smart Stock Setup: global autofix tenant=%s (had %d orphans) failed: %v",
				r.TenantID, r.OrphanCount, err)
			continue
		}
		log.Printf("Smart Stock Setup: global autofix tenant=%s linked=%d deleted=%d flagged=%d (was %d orphans)",
			r.TenantID, res.Counts.Linked, res.Counts.Deleted, res.Counts.Flagged, r.OrphanCount)
	}
}

func (s *SmartStockJobService) rescueStalledJobs() {
	res := s.db.Model(&models.SmartStockSetupJob{}).
		Where("status = ? AND retry_count < ?", models.StockSetupJobProcessing, workerMaxRetries).
		Updates(map[string]interface{}{
			"status":      models.StockSetupJobPending,
			"started_at":  nil,
			"retry_count": gorm.Expr("retry_count + 1"),
		})
	if res.Error != nil {
		log.Printf("Smart Stock Setup: rescue-stalled-jobs failed: %v", res.Error)
		return
	}
	if res.RowsAffected > 0 {
		log.Printf("Smart Stock Setup: rescued %d stalled jobs back to pending", res.RowsAffected)
	}
}

// processOne claims at most one pending job and runs it to completion.
// Returns true when work was done so the caller can drain a burst, false
// when the queue is empty so the caller parks until the next tick.
func (s *SmartStockJobService) processOne(ctx context.Context) bool {
	if ctx.Err() != nil {
		return false
	}
	// Claim the oldest pending job with FOR UPDATE SKIP LOCKED — Postgres-
	// specific but always available here. Multiple worker instances (future
	// horizontal scale) are safe with this claim pattern.
	var claimed models.SmartStockSetupJob
	tx := s.db.Begin()
	if tx.Error != nil {
		log.Printf("Smart Stock Setup: worker begin tx failed: %v", tx.Error)
		return false
	}
	err := tx.Raw(`
		SELECT * FROM smart_stock_setup_jobs
		WHERE status = ? AND deleted_at IS NULL
		ORDER BY created_at ASC
		LIMIT 1
		FOR UPDATE SKIP LOCKED
	`, models.StockSetupJobPending).Scan(&claimed).Error
	if err != nil || claimed.ID == uuid.Nil {
		tx.Rollback()
		return false
	}
	now := time.Now()
	if err := tx.Model(&models.SmartStockSetupJob{}).
		Where("id = ?", claimed.ID).
		Updates(map[string]interface{}{
			"status":     models.StockSetupJobProcessing,
			"started_at": now,
		}).Error; err != nil {
		tx.Rollback()
		log.Printf("Smart Stock Setup: claim job %s failed: %v", claimed.ID, err)
		return false
	}
	if err := tx.Commit().Error; err != nil {
		log.Printf("Smart Stock Setup: claim commit failed: %v", err)
		return false
	}

	log.Printf("Smart Stock Setup: worker claimed job %s (retry=%d, images=%d)",
		claimed.ID, claimed.RetryCount, len(claimed.ImagePaths))

	// Process with a bounded outer timeout so a hung call can't pin the worker.
	jobCtx, cancel := context.WithTimeout(ctx, workerJobTimeout)
	defer cancel()
	s.runJob(jobCtx, &claimed)
	return true
}

// runJob executes a single claimed job end-to-end and writes the terminal
// status back to the row. Retries failed jobs up to workerMaxRetries by
// flipping the row back to 'pending' (the next processOne call picks it up).
func (s *SmartStockJobService) runJob(ctx context.Context, job *models.SmartStockSetupJob) {
	if job.TenantID == nil {
		s.markFailed(job, "missing tenant_id on job row")
		return
	}

	// Read image bytes back from disk. Absent files mean the server disk
	// was wiped between submit and run — treat as permanent failure.
	images := make([]SmartPurchaseImage, 0, len(job.ImagePaths))
	for _, p := range job.ImagePaths {
		data, err := os.ReadFile(p)
		if err != nil {
			s.markFailed(job, fmt.Sprintf("read image %s: %v", p, err))
			return
		}
		ct := "image/jpeg"
		if strings.HasSuffix(strings.ToLower(p), ".png") {
			ct = "image/png"
		}
		images = append(images, SmartPurchaseImage{
			Data:        data,
			ContentType: ct,
			Filename:    filepath.Base(p),
		})
	}

	req := SmartStockSetupRequest{
		TenantID:    job.TenantID.String(),
		UserID:      job.UserID.String(),
		ShopID:      job.ShopID.String(),
		StockColumn: job.StockColumn,
		Size:        job.Size,
		Images:      images,
	}
	if job.CategoryID != nil {
		req.CategoryID = job.CategoryID.String()
	}

	result, err := s.mainService.ProcessExtraction(ctx, req)
	if err != nil {
		s.handleFailure(job, err.Error())
		return
	}

	// Serialise result → JSONB for storage. json.Marshal round-trip ensures
	// the blob is pure JSON-compatible and strips unexported fields.
	raw, mErr := json.Marshal(result)
	if mErr != nil {
		s.handleFailure(job, fmt.Sprintf("marshal result: %v", mErr))
		return
	}
	var asMap models.SmartStockJobResult
	if err := json.Unmarshal(raw, &asMap); err != nil {
		s.handleFailure(job, fmt.Sprintf("unmarshal result: %v", err))
		return
	}

	now := time.Now()
	updates := map[string]interface{}{
		"status":       models.StockSetupJobDone,
		"result":       asMap,
		"session_id":   result.SessionID,
		"completed_at": now,
		"error_message": "",
	}
	if err := s.db.Model(&models.SmartStockSetupJob{}).
		Where("id = ?", job.ID).Updates(updates).Error; err != nil {
		log.Printf("Smart Stock Setup: store result for job %s failed: %v", job.ID, err)
		return
	}
	log.Printf("Smart Stock Setup: job %s completed (session=%s items=%d)",
		job.ID, result.SessionID, len(result.Items))

	// Auto-run orphan-autofix for the tenant after each extraction so newly-
	// surfaced orphan products get linked to master brands silently, without
	// the user needing to tap the Data Hygiene Auto-link button. This is the
	// "smart & automatic" behavior the user expects — matches the spirit of
	// the read-time master-routing that already happens during extraction.
	// Done in a goroutine so a slow autofix pass (rare — ~100ms per orphan)
	// doesn't delay job completion. Errors are logged but don't mark the
	// job failed — the extraction itself succeeded.
	go func(tenantID string) {
		autofixResult, err := s.mainService.OrphansAutofix(OrphanAutofixRequest{
			TenantID: tenantID,
			DryRun:   false,
		})
		if err != nil {
			log.Printf("Smart Stock Setup: post-job orphan-autofix tenant=%s failed: %v", tenantID, err)
			return
		}
		log.Printf("Smart Stock Setup: post-job orphan-autofix tenant=%s linked=%d deleted=%d flagged=%d",
			tenantID, autofixResult.Counts.Linked, autofixResult.Counts.Deleted, autofixResult.Counts.Flagged)
	}(job.TenantID.String())
}

// handleFailure retries up to workerMaxRetries, then marks the job permanently
// failed. Separated from markFailed so transient AI errors (timeouts, 5xx)
// get a second chance without user intervention.
func (s *SmartStockJobService) handleFailure(job *models.SmartStockSetupJob, errMsg string) {
	if job.RetryCount+1 < workerMaxRetries {
		// Retry: flip back to pending so processOne picks it up next tick.
		_ = s.db.Model(&models.SmartStockSetupJob{}).
			Where("id = ?", job.ID).
			Updates(map[string]interface{}{
				"status":        models.StockSetupJobPending,
				"retry_count":   job.RetryCount + 1,
				"started_at":    nil,
				"error_message": errMsg,
			}).Error
		log.Printf("Smart Stock Setup: job %s failed attempt %d — retrying: %s",
			job.ID, job.RetryCount+1, errMsg)
		return
	}
	s.markFailed(job, errMsg)
}

// markFailed sets terminal status=failed with the given message. No further
// retries happen after this; the user must submit a new job.
func (s *SmartStockJobService) markFailed(job *models.SmartStockSetupJob, errMsg string) {
	now := time.Now()
	_ = s.db.Model(&models.SmartStockSetupJob{}).
		Where("id = ?", job.ID).
		Updates(map[string]interface{}{
			"status":        models.StockSetupJobFailed,
			"error_message": errMsg,
			"completed_at":  now,
			"retry_count":   job.RetryCount + 1,
		}).Error
	log.Printf("Smart Stock Setup: job %s PERMANENTLY FAILED after %d attempts: %s",
		job.ID, job.RetryCount+1, errMsg)
}

// --------------------------------------------------------------------------
// HTTP status-code mapping (used by the handler layer)
// --------------------------------------------------------------------------

// JobErrorToStatus maps service-layer error strings to HTTP status codes so
// the handler can stay terse. 404 for not-found, 400 for validation, 500
// for everything else.
func JobErrorToStatus(err error) int {
	if err == nil {
		return http.StatusOK
	}
	msg := err.Error()
	switch {
	case strings.Contains(msg, "not found"):
		return http.StatusNotFound
	case strings.Contains(msg, "invalid"),
		strings.Contains(msg, "required"),
		strings.Contains(msg, "maximum"):
		return http.StatusBadRequest
	default:
		return http.StatusInternalServerError
	}
}
