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

// SmartSaleJobService manages the persistent background-job layer for
// AI Sales Entry extraction. Submit-and-poll replaces the synchronous
// /smart-sale/process request so users can close the app mid-extraction
// and resume later, and so transient AI-vendor hiccups get auto-retried
// without the user having to re-pick images.
//
// Architecture (Postgres-backed queue, no Redis dependency):
//   - Submit stores images to disk + a row in smart_sale_setup_jobs with
//     status='pending'.
//   - A worker goroutine polls every workerPollInterval, claims one pending
//     job via "SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1", runs the existing
//     ProcessSmartSale pipeline, and writes the SmartSaleResult back.
//   - Clients poll GET /jobs/:id until status is terminal (done/failed/canceled).
//
// Why mirror the stock-setup implementation exactly (pkg/shared/models/
// stock_setup_job.go + internal/inventory/services/stock_setup_job_service.go):
// one pattern, one mental model, one set of bugs to fix. Copy-pasting the
// claim/retry/rescue pattern beats inventing a second approach for the same
// requirement.
type SmartSaleJobService struct {
	db          *database.DB
	mainService *SmartSaleService
}

// NewSmartSaleJobService wires the job service to its dependencies. The
// SmartSaleService is held so the worker can call ProcessSmartSale without
// duplicating the OCR/validation/record-creation pipeline.
func NewSmartSaleJobService(db *database.DB, mainService *SmartSaleService) *SmartSaleJobService {
	return &SmartSaleJobService{db: db, mainService: mainService}
}

// --------------------------------------------------------------------------
// Worker tuning
// --------------------------------------------------------------------------

const (
	// Poll period when the queue is idle. Kept short because end-users poll
	// the status endpoint every 3s; a longer worker interval would
	// introduce visible lag between submit and start-of-processing.
	saleWorkerPollInterval = 3 * time.Second
	// Retry budget per job. A single flaky AI call shouldn't permanently
	// fail the user's submission. After 3 attempts the job is marked
	// permanently failed and the user is shown the last error.
	saleWorkerMaxRetries = 3
	// Upper-bound for a single job's processing phase. ProcessSmartSale
	// itself has an inner AI timeout; this is a defensive outer bound so a
	// hung call can't pin the worker forever.
	saleWorkerJobTimeout = 6 * time.Minute
)

// --------------------------------------------------------------------------
// Submit
// --------------------------------------------------------------------------

// SmartSaleJobImage is a single uploaded image in raw-bytes form. Kept
// separate from the request type so the handler can pass the image batch
// around without leaking multipart.FileHeader into the service layer.
type SmartSaleJobImage struct {
	Data        []byte
	ContentType string
	Filename    string
}

// SubmitSaleJobRequest carries everything needed to enqueue a single
// extraction.
type SubmitSaleJobRequest struct {
	TenantID string
	UserID   string
	UserRole string
	ShopID   string
	ShopName string
	SaleDate time.Time
	Category string // "beer" | "non_beer"
	Size     string // optional size filter
	Images   []SmartSaleJobImage
}

// Submit persists a new job: saves images to a per-job directory and creates
// a row with status='pending'. Returns the fresh job ID so clients can poll.
//
// Image storage path: /app/uploads/smart_sale/jobs/{job_id}/image_N.{ext} —
// sibling to the existing daily-sales receipt storage so cleanup tooling
// that already scans /app/uploads/smart_sale picks these up.
func (s *SmartSaleJobService) Submit(req SubmitSaleJobRequest) (*models.SmartSaleSetupJob, error) {
	if len(req.Images) == 0 {
		return nil, fmt.Errorf("at least one image is required")
	}
	if len(req.Images) > 5 {
		return nil, fmt.Errorf("maximum 5 images per job")
	}
	if req.Category != "beer" && req.Category != "non_beer" {
		return nil, fmt.Errorf("invalid category: must be 'beer' or 'non_beer'")
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

	jobID := uuid.New()

	// Per-job image directory. Must live under /app/uploads (which the
	// container mounts writable); keeping it under smart_sale/jobs keeps
	// cleanup scoped and discoverable.
	jobDir := filepath.Join("/app/uploads/smart_sale/jobs", jobID.String())
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
			// Clean up partials so the job dir isn't half-written on failure.
			_ = os.RemoveAll(jobDir)
			return nil, fmt.Errorf("write image %d: %w", i+1, err)
		}
		imagePaths = append(imagePaths, fp)
	}

	// Persist the user role in ErrorMessage prefix? No — thread it through
	// a dedicated field would be cleanest, but ProcessSmartSale signs off
	// on roleStr anyway for audit hooks. Store on the row as metadata.
	// For now we stash it inside ErrorMessage as an empty-string prefix
	// (the existing ErrorMessage is "" on success); role goes through
	// context threading in runJob.
	saleDate := req.SaleDate
	if saleDate.IsZero() {
		saleDate = time.Now()
	}

	job := &models.SmartSaleSetupJob{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: jobID},
			TenantID:  &tenantUUID,
		},
		UserID:     userUUID,
		ShopID:     shopUUID,
		Status:     models.SmartSaleJobPending,
		ShopName:   req.ShopName,
		SaleDate:   saleDate,
		Category:   req.Category,
		Size:       req.Size,
		ImagePaths: models.JSONStringList(imagePaths),
	}
	if err := s.db.Create(job).Error; err != nil {
		_ = os.RemoveAll(jobDir)
		return nil, fmt.Errorf("insert job: %w", err)
	}
	log.Printf("Smart Sale: job %s submitted (tenant=%s user=%s shop=%s images=%d category=%s size=%s)",
		jobID, req.TenantID, req.UserID, req.ShopID, len(imagePaths), req.Category, req.Size)
	return job, nil
}

// --------------------------------------------------------------------------
// Get / List / Cancel
// --------------------------------------------------------------------------

// Get returns a single job with strict tenant+user scoping — one user can't
// peek at another user's jobs even within the same tenant. Extractions can
// contain rate/sales figures the other user isn't authorised to see.
func (s *SmartSaleJobService) Get(jobID, tenantID, userID string) (*models.SmartSaleSetupJob, error) {
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
	var job models.SmartSaleSetupJob
	err = s.db.Where("id = ? AND tenant_id = ? AND user_id = ?", jobUUID, tenantUUID, userUUID).
		First(&job).Error
	if err != nil {
		return nil, fmt.Errorf("job not found")
	}
	return &job, nil
}

// List returns this user's recent jobs, newest first. Limit clamped to
// [1, 50] so a pathological client can't request the full history.
func (s *SmartSaleJobService) List(tenantID, userID string, limit int) ([]models.SmartSaleSetupJob, error) {
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
	var jobs []models.SmartSaleSetupJob
	err = s.db.Where("tenant_id = ? AND user_id = ?", tenantUUID, userUUID).
		Order("created_at DESC").
		Limit(limit).
		Find(&jobs).Error
	return jobs, err
}

// Cancel marks a pending job as canceled. No-op (returns nil) if the job
// has already started processing or is terminal — once the worker claims a
// job, reversing the AI call in-flight isn't worth the complexity.
func (s *SmartSaleJobService) Cancel(jobID, tenantID, userID string) error {
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
	res := s.db.Model(&models.SmartSaleSetupJob{}).
		Where("id = ? AND tenant_id = ? AND user_id = ? AND status = ?",
			jobUUID, tenantUUID, userUUID, models.SmartSaleJobPending).
		Updates(map[string]interface{}{
			"status":       models.SmartSaleJobCanceled,
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
// would spawn duplicate workers (harmless thanks to SKIP LOCKED but wasteful).
//
// The worker exits cleanly when ctx is canceled — main.go passes a
// shutdown-aware context so draining a slow job during deploy doesn't leave
// a zombie process.
func (s *SmartSaleJobService) StartWorker(ctx context.Context) {
	log.Printf("Smart Sale: starting background worker (poll=%v, max_retries=%d)",
		saleWorkerPollInterval, saleWorkerMaxRetries)

	// Sentinel: on first boot, any job stuck in 'processing' is almost
	// certainly abandoned from a previous deploy (crash / OOM mid-job).
	// Flip them back to pending so the retry path picks them up. Bounded
	// by retry_count so we don't infinite-loop a poison job across deploys.
	s.rescueStalledJobs()

	go func() {
		ticker := time.NewTicker(saleWorkerPollInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Printf("Smart Sale: worker shutting down")
				return
			case <-ticker.C:
				// processOne returns true when it did work; when it did we
				// immediately loop so a queued burst drains without a full
				// poll-interval pause per item.
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

	// Periodic stuck-job rescue. The startup sentinel above only fires once,
	// so a job that gets stuck mid-flight (e.g. OpenAI hang past the per-job
	// context timeout, but the runJob goroutine still resolved cleanly into
	// a terminal state) waits for the next deploy to recover. This ticker
	// requeues anything still in 'processing' with started_at older than
	// 2× the per-job timeout — that window is long enough that runJob's own
	// timeout would have fired first under normal conditions, so anything
	// still here really is orphaned.
	go func() {
		t := time.NewTicker(saleWorkerJobTimeout)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				cutoff := time.Now().Add(-2 * saleWorkerJobTimeout)
				res := s.db.Model(&models.SmartSaleSetupJob{}).
					Where("status = ? AND started_at < ? AND retry_count < ?",
						models.SmartSaleJobProcessing, cutoff, saleWorkerMaxRetries).
					Updates(map[string]interface{}{
						"status":        models.SmartSaleJobPending,
						"started_at":    nil,
						"retry_count":   gorm.Expr("retry_count + 1"),
						"error_message": fmt.Sprintf("auto-rescued: stuck >%v in processing", 2*saleWorkerJobTimeout),
					})
				if res.Error != nil {
					log.Printf("Smart Sale: periodic rescue failed: %v", res.Error)
					continue
				}
				if res.RowsAffected > 0 {
					log.Printf("Smart Sale: periodic rescue requeued %d stuck jobs", res.RowsAffected)
				}
			}
		}
	}()
}

// rescueStalledJobs flips abandoned 'processing' rows back to 'pending' at
// worker startup so a crash mid-job doesn't leak a permanent processing
// state. Only runs once per boot.
func (s *SmartSaleJobService) rescueStalledJobs() {
	res := s.db.Model(&models.SmartSaleSetupJob{}).
		Where("status = ? AND retry_count < ?", models.SmartSaleJobProcessing, saleWorkerMaxRetries).
		Updates(map[string]interface{}{
			"status":      models.SmartSaleJobPending,
			"started_at":  nil,
			"retry_count": gorm.Expr("retry_count + 1"),
		})
	if res.Error != nil {
		log.Printf("Smart Sale: rescue-stalled-jobs failed: %v", res.Error)
		return
	}
	if res.RowsAffected > 0 {
		log.Printf("Smart Sale: rescued %d stalled jobs back to pending", res.RowsAffected)
	}
}

// processOne claims at most one pending job and runs it to completion.
// Returns true when work was done so the caller can drain a burst, false
// when the queue is empty so the caller parks until the next tick.
func (s *SmartSaleJobService) processOne(ctx context.Context) bool {
	if ctx.Err() != nil {
		return false
	}
	// Claim the oldest pending job with FOR UPDATE SKIP LOCKED.
	var claimed models.SmartSaleSetupJob
	tx := s.db.Begin()
	if tx.Error != nil {
		log.Printf("Smart Sale: worker begin tx failed: %v", tx.Error)
		return false
	}
	err := tx.Raw(`
		SELECT * FROM smart_sale_setup_jobs
		WHERE status = ? AND deleted_at IS NULL
		ORDER BY created_at ASC
		LIMIT 1
		FOR UPDATE SKIP LOCKED
	`, models.SmartSaleJobPending).Scan(&claimed).Error
	if err != nil || claimed.ID == uuid.Nil {
		tx.Rollback()
		return false
	}
	now := time.Now()
	if err := tx.Model(&models.SmartSaleSetupJob{}).
		Where("id = ?", claimed.ID).
		Updates(map[string]interface{}{
			"status":     models.SmartSaleJobProcessing,
			"started_at": now,
		}).Error; err != nil {
		tx.Rollback()
		log.Printf("Smart Sale: claim job %s failed: %v", claimed.ID, err)
		return false
	}
	if err := tx.Commit().Error; err != nil {
		log.Printf("Smart Sale: claim commit failed: %v", err)
		return false
	}

	log.Printf("Smart Sale: worker claimed job %s (retry=%d, images=%d)",
		claimed.ID, claimed.RetryCount, len(claimed.ImagePaths))

	// Process with a bounded outer timeout so a hung call can't pin the worker.
	jobCtx, cancel := context.WithTimeout(ctx, saleWorkerJobTimeout)
	defer cancel()
	s.runJob(jobCtx, &claimed)
	return true
}

// runJob executes a single claimed job end-to-end and writes the terminal
// status back to the row. Retries failed jobs up to saleWorkerMaxRetries by
// flipping the row back to 'pending'.
func (s *SmartSaleJobService) runJob(ctx context.Context, job *models.SmartSaleSetupJob) {
	if job.TenantID == nil {
		s.markFailed(job, "missing tenant_id on job row")
		return
	}

	// Read image bytes back from disk. Absent files mean the server disk
	// was wiped between submit and run — treat as permanent failure.
	imageData := make([][]byte, 0, len(job.ImagePaths))
	for _, p := range job.ImagePaths {
		data, err := os.ReadFile(p)
		if err != nil {
			s.markFailed(job, fmt.Sprintf("read image %s: %v", p, err))
			return
		}
		imageData = append(imageData, data)
	}

	req := &SmartSaleRequest{
		ShopID:    job.ShopID,
		ShopName:  job.ShopName,
		SaleDate:  job.SaleDate,
		Category:  job.Category,
		Size:      job.Size,
		ImageData: imageData,
	}

	// v1.0.182 — capture per-image quality snapshot BEFORE extraction so
	// the accuracy dashboard can correlate poor extraction with poor input.
	// Best-effort: cv-sidecar disabled / unreachable returns nil, we just
	// skip persistence. Never blocks extraction.
	if cv := s.mainService.CVSidecar(); cv != nil {
		snaps := make(models.QualityCheckSnapshots, 0, len(imageData))
		for idx, data := range imageData {
			res := cv.QualityCheck(ctx, data)
			if res == nil {
				continue
			}
			snaps = append(snaps, models.QualityCheckSnapshot{
				ImageIndex:   idx,
				Blur:         res.Blur,
				Contrast:     res.Contrast,
				Brightness:   res.Brightness,
				SkewDeg:      res.SkewDeg,
				Issues:       res.Issues,
				SevereIssues: res.SevereIssues,
				Score:        res.Score,
				Advisory:     res.Advisory,
				Severe:       res.Severe,
			})
		}
		if len(snaps) > 0 {
			if err := s.db.Model(&models.SmartSaleSetupJob{}).
				Where("id = ?", job.ID).
				Update("quality_check_results", snaps).Error; err != nil {
				log.Printf("Smart Sale: persist quality_check_results job %s: %v", job.ID, err)
			}
		}
	}

	// Note on role: extraction-level authorisation is enforced inside
	// ProcessSmartSale from role + tenant context. We don't persist role on
	// the job row (would go stale if user role changes between submit and
	// run), so pass empty string here — ProcessSmartSale treats unknown
	// roles as the lowest-privilege path (same as the sync handler today
	// when role context is missing).
	result, err := s.mainService.ProcessSmartSale(ctx, req, job.UserID, *job.TenantID, "")
	if err != nil {
		s.handleFailure(job, err.Error())
		return
	}

	// Serialise result → JSONB for storage. Round-trip through json.Marshal
	// strips unexported fields + ensures pure JSON-compatible values.
	raw, mErr := json.Marshal(result)
	if mErr != nil {
		s.handleFailure(job, fmt.Sprintf("marshal result: %v", mErr))
		return
	}
	var asMap models.SmartSaleJobResult
	if err := json.Unmarshal(raw, &asMap); err != nil {
		s.handleFailure(job, fmt.Sprintf("unmarshal result: %v", err))
		return
	}

	now := time.Now()
	updates := map[string]interface{}{
		"status":        models.SmartSaleJobDone,
		"result":        asMap,
		"completed_at":  now,
		"error_message": "",
	}
	if err := s.db.Model(&models.SmartSaleSetupJob{}).
		Where("id = ?", job.ID).Updates(updates).Error; err != nil {
		log.Printf("Smart Sale: store result for job %s failed: %v", job.ID, err)
		return
	}
	log.Printf("Smart Sale: job %s completed (status=%s items=%d)",
		job.ID, result.Status, len(result.ExtractedItems))
}

// isTransientSaleError returns true for errors that are likely to succeed on
// retry — network timeouts, OpenAI 429/5xx, connection resets. Permanent
// errors (malformed image, missing file, JSON parse) shouldn't burn the user's
// retry budget; they need code or input fixes.
func isTransientSaleError(errMsg string) bool {
	m := strings.ToLower(errMsg)
	return strings.Contains(m, "timeout") ||
		strings.Contains(m, "deadline exceeded") ||
		strings.Contains(m, "429") ||
		strings.Contains(m, "rate limit") ||
		strings.Contains(m, "500") ||
		strings.Contains(m, "502") ||
		strings.Contains(m, "503") ||
		strings.Contains(m, "504") ||
		strings.Contains(m, "connection reset") ||
		strings.Contains(m, "connection refused") ||
		strings.Contains(m, "eof") ||
		strings.Contains(m, "i/o timeout") ||
		strings.Contains(m, "no such host") ||
		strings.Contains(m, "tls handshake")
}

// handleFailure retries up to saleWorkerMaxRetries for transient AI errors
// (timeouts, 5xx, rate-limits). Permanent errors fail immediately so the user
// gets a clear error message instead of waiting through three doomed retries.
func (s *SmartSaleJobService) handleFailure(job *models.SmartSaleSetupJob, errMsg string) {
	transient := isTransientSaleError(errMsg)
	if transient && job.RetryCount+1 < saleWorkerMaxRetries {
		_ = s.db.Model(&models.SmartSaleSetupJob{}).
			Where("id = ?", job.ID).
			Updates(map[string]interface{}{
				"status":        models.SmartSaleJobPending,
				"retry_count":   job.RetryCount + 1,
				"started_at":    nil,
				"error_message": errMsg,
			}).Error
		log.Printf("Smart Sale: job %s failed attempt %d (transient) — retrying: %s",
			job.ID, job.RetryCount+1, errMsg)
		return
	}
	if !transient {
		log.Printf("Smart Sale: job %s permanent error — skipping retries: %s", job.ID, errMsg)
	}
	s.markFailed(job, errMsg)
}

// markFailed sets terminal status=failed with the given message. No further
// retries happen after this; the user must submit a new job.
func (s *SmartSaleJobService) markFailed(job *models.SmartSaleSetupJob, errMsg string) {
	now := time.Now()
	_ = s.db.Model(&models.SmartSaleSetupJob{}).
		Where("id = ?", job.ID).
		Updates(map[string]interface{}{
			"status":        models.SmartSaleJobFailed,
			"error_message": errMsg,
			"completed_at":  now,
			"retry_count":   job.RetryCount + 1,
		}).Error
	log.Printf("Smart Sale: job %s PERMANENTLY FAILED after %d attempts: %s",
		job.ID, job.RetryCount+1, errMsg)
}

// --------------------------------------------------------------------------
// HTTP status-code mapping
// --------------------------------------------------------------------------

// SaleJobErrorToStatus maps service-layer errors to HTTP status codes so the
// handler layer stays terse. 404 for not-found, 400 for validation, 500 for
// anything else.
func SaleJobErrorToStatus(err error) int {
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
