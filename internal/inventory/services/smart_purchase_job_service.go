package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// SmartPurchaseJobService manages the persistent background-job layer for
// AI Purchase Entry extraction. Submit-and-poll replaces the synchronous
// /smart-purchase/process request so users can close the app mid-extraction
// and resume later, and so transient AI-vendor / Textract hiccups get
// auto-retried without the user having to re-pick images.
//
// Architecture (Postgres-backed queue, no Redis dependency):
//   - Submit stores images to disk + a row in smart_purchase_jobs with
//     status='pending'.
//   - A worker goroutine polls every workerPollInterval, claims one pending
//     job via "SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1", runs the existing
//     ProcessSmartPurchase pipeline, and writes the SmartPurchaseResult back.
//   - Clients poll GET /jobs/:id until status is terminal (done/failed/canceled).
//
// Mirrors SmartSaleJobService 1:1 (sales/services/smart_sale_job_service.go).
// Same pattern, same retry policy, same bug surface — copy beats rewrite.
type SmartPurchaseJobService struct {
	db          *database.DB
	mainService *SmartPurchaseService
}

// NewSmartPurchaseJobService wires the job service to its dependencies.
func NewSmartPurchaseJobService(db *database.DB, mainService *SmartPurchaseService) *SmartPurchaseJobService {
	return &SmartPurchaseJobService{db: db, mainService: mainService}
}

// --------------------------------------------------------------------------
// Worker tuning
// --------------------------------------------------------------------------

const (
	purchaseWorkerPollInterval = 3 * time.Second
	purchaseWorkerMaxRetries   = 3
	// AI Purchase pipeline is heavier than Smart Sale (Textract + Gemini fallback
	// + matcher with master-brand cross-check + alias cascade), so the per-job
	// outer bound is 8 minutes vs Sale's 6.
	purchaseWorkerJobTimeout = 8 * time.Minute

	// v1.0.337 — default number of jobs processed concurrently. Each job is
	// ~3 min (Textract + LLM), and processOne already claims jobs with
	// FOR UPDATE SKIP LOCKED, so N independent worker goroutines each grab a
	// DIFFERENT pending job — turning a sequential queue (job K waits for all
	// K-1 ahead of it) into N-wide parallelism. 3 is a safe default: it cuts
	// queue wait ~3× for bursts without overloading Textract/LLM rate limits
	// or the DB pool. Override with SMART_PURCHASE_WORKER_CONCURRENCY.
	purchaseWorkerDefaultConcurrency = 3
	purchaseWorkerMaxConcurrency     = 8
)

// purchaseWorkerConcurrency resolves how many worker goroutines to run from
// SMART_PURCHASE_WORKER_CONCURRENCY (default 3), clamped to [1, 8] so a typo
// can never spawn an unbounded fan-out or stall the queue at 0.
func purchaseWorkerConcurrency() int {
	n := purchaseWorkerDefaultConcurrency
	if v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_WORKER_CONCURRENCY")); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			n = parsed
		}
	}
	if n < 1 {
		n = 1
	}
	if n > purchaseWorkerMaxConcurrency {
		n = purchaseWorkerMaxConcurrency
	}
	return n
}

// v1.0.369 — GLOBAL extraction-memory gate. Each in-flight job holds 2-3 large
// images in memory AND runs them through Textract + Gemini, peaking ~0.4-0.5 GB
// of anon RSS per job. The worker pool (default 3) let that many extractions run
// at once, which OOM-killed the container at its 1 GiB cgroup limit (4 restarts,
// jobs wedged in 'processing'). This semaphore bounds *concurrent extraction*
// independently of the worker count, so raising worker concurrency for queue
// responsiveness can never again blow the memory budget. Default 2 (≈1 GiB peak),
// tune with SMART_PURCHASE_EXTRACT_CONCURRENCY, clamped [1,4].
const (
	purchaseExtractDefaultConcurrency = 2
	purchaseExtractMaxConcurrency     = 4
)

var (
	purchaseExtractSem     chan struct{}
	purchaseExtractSemOnce sync.Once
)

func purchaseExtractConcurrency() int {
	n := purchaseExtractDefaultConcurrency
	if v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_EXTRACT_CONCURRENCY")); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			n = parsed
		}
	}
	if n < 1 {
		n = 1
	}
	if n > purchaseExtractMaxConcurrency {
		n = purchaseExtractMaxConcurrency
	}
	return n
}

// acquireExtractSlot blocks until a global extraction slot is free (or ctx is
// done), returning a release func. The release is idempotent-safe via the
// caller's single deferred call. On ctx cancellation it returns ok=false and a
// no-op release so the caller can bail without holding a slot.
func acquireExtractSlot(ctx context.Context) (release func(), ok bool) {
	purchaseExtractSemOnce.Do(func() {
		purchaseExtractSem = make(chan struct{}, purchaseExtractConcurrency())
	})
	select {
	case purchaseExtractSem <- struct{}{}:
		return func() { <-purchaseExtractSem }, true
	case <-ctx.Done():
		return func() {}, false
	}
}

// --------------------------------------------------------------------------
// Submit
// --------------------------------------------------------------------------

// SmartPurchaseJobImage is a single uploaded image in raw-bytes form.
type SmartPurchaseJobImage struct {
	Data        []byte
	ContentType string
	Filename    string
}

// SubmitPurchaseJobRequest carries everything needed to enqueue a single
// extraction. Mirrors the synchronous SmartPurchaseRequest 1:1 with the
// addition of explicit invoice/gate-pass split (the sync handler accepts the
// same shape but worse documented).
type SubmitPurchaseJobRequest struct {
	TenantID         string
	UserID           string
	ShopID           string
	ShopName         string
	VendorID         string // optional
	InvoiceDate      string // optional
	InvoiceImages    []SmartPurchaseJobImage
	GatePassImages   []SmartPurchaseJobImage
}

// Submit persists a new job: saves images to a per-job directory and creates
// a row with status='pending'. Returns the fresh job so clients can poll.
//
// Image storage path: /app/uploads/purchases/jobs/{job_id}/{kind}_N.{ext} —
// where {kind} is "invoice" or "gate_pass". Sibling to the existing manual
// purchase receipt storage so cleanup tooling that already scans
// /app/uploads/purchases picks these up.
func (s *SmartPurchaseJobService) Submit(req SubmitPurchaseJobRequest) (*models.SmartPurchaseJob, error) {
	if len(req.InvoiceImages) == 0 && len(req.GatePassImages) == 0 {
		return nil, fmt.Errorf("at least one image is required")
	}
	// v1.0.193 — soft cap raised to 10 invoice + 10 gate-pass = 20 images
	// total per submission. Real chhotu-class bills sometimes span 4-6
	// pages and split shipments can produce 7-8 GP pages. Beyond 10 each
	// the operator is almost certainly in error (uploaded the wrong file
	// kind) and disk + AI tokens both balloon.
	const maxImagesPerKind = 10
	if len(req.InvoiceImages) > maxImagesPerKind {
		return nil, fmt.Errorf("maximum %d invoice images per job", maxImagesPerKind)
	}
	if len(req.GatePassImages) > maxImagesPerKind {
		return nil, fmt.Errorf("maximum %d gate-pass images per job", maxImagesPerKind)
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
	var vendorUUID *uuid.UUID
	if req.VendorID != "" {
		v, err := uuid.Parse(req.VendorID)
		if err != nil {
			return nil, fmt.Errorf("invalid vendor_id")
		}
		vendorUUID = &v
	}

	jobID := uuid.New()
	jobDir := filepath.Join("/app/uploads/purchases/jobs", jobID.String())
	if err := os.MkdirAll(jobDir, 0755); err != nil {
		return nil, fmt.Errorf("create job dir: %w", err)
	}

	writeBatch := func(items []SmartPurchaseJobImage, kind string) ([]string, error) {
		paths := make([]string, 0, len(items))
		for i, img := range items {
			ext := ".jpg"
			if strings.Contains(strings.ToLower(img.ContentType), "png") {
				ext = ".png"
			}
			fp := filepath.Join(jobDir, fmt.Sprintf("%s_%d%s", kind, i+1, ext))
			if err := os.WriteFile(fp, img.Data, 0644); err != nil {
				return nil, fmt.Errorf("write %s image %d: %w", kind, i+1, err)
			}
			paths = append(paths, fp)
		}
		return paths, nil
	}

	invoicePaths, err := writeBatch(req.InvoiceImages, "invoice")
	if err != nil {
		_ = os.RemoveAll(jobDir)
		return nil, err
	}
	gatePaths, err := writeBatch(req.GatePassImages, "gate_pass")
	if err != nil {
		_ = os.RemoveAll(jobDir)
		return nil, err
	}

	job := &models.SmartPurchaseJob{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: jobID},
			TenantID:  &tenantUUID,
		},
		UserID:             userUUID,
		ShopID:             shopUUID,
		Status:             models.SmartPurchaseJobPending,
		ShopName:           req.ShopName,
		VendorID:           vendorUUID,
		InvoiceImagePaths:  models.JSONStringList(invoicePaths),
		GatePassImagePaths: models.JSONStringList(gatePaths),
	}
	if err := s.db.Create(job).Error; err != nil {
		_ = os.RemoveAll(jobDir)
		return nil, fmt.Errorf("insert job: %w", err)
	}
	log.Printf("Smart Purchase: job %s submitted (tenant=%s user=%s shop=%s invoices=%d gate_passes=%d)",
		jobID, req.TenantID, req.UserID, req.ShopID, len(invoicePaths), len(gatePaths))
	return job, nil
}

// --------------------------------------------------------------------------
// Get / List / Cancel
// --------------------------------------------------------------------------

// Get returns a single job with strict tenant+user scoping.
func (s *SmartPurchaseJobService) Get(jobID, tenantID, userID string) (*models.SmartPurchaseJob, error) {
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
	var job models.SmartPurchaseJob
	err = s.db.Where("id = ? AND tenant_id = ? AND user_id = ?", jobUUID, tenantUUID, userUUID).
		First(&job).Error
	if err != nil {
		return nil, fmt.Errorf("job not found")
	}
	return &job, nil
}

// ParchaOrderEntry is one product position in the shop's most-recent submitted
// sale register (Parsha), so the AI-purchase review can be ordered to line up
// against the physical register the operator reconciles against.
type ParchaOrderEntry struct {
	ProductID string `json:"product_id"`
	Position  int    `json:"position"`
	Name      string `json:"name"`
}

// GetParchaOrder returns the product order of the shop's latest submitted daily
// sale (by register position), plus its record date. Mirrors the tester's
// ai_shop_latest_sale. Empty (not an error) when the shop has no submitted sale.
func (s *SmartPurchaseJobService) GetParchaOrder(shopID string) ([]ParchaOrderEntry, string, error) {
	shopUUID, err := uuid.Parse(shopID)
	if err != nil {
		return nil, "", fmt.Errorf("invalid shop_id")
	}
	rows, err := s.db.Raw(`
		WITH r AS (
			SELECT id, record_date FROM daily_sales_records
			WHERE shop_id = ? AND deleted_at IS NULL
			ORDER BY created_at DESC LIMIT 1
		)
		SELECT i.position, COALESCE(i.product_id::text, '') AS product_id,
		       COALESCE(p.name, '') AS name,
		       (SELECT to_char(record_date, 'YYYY-MM-DD') FROM r) AS record_date
		FROM daily_sales_items i
		LEFT JOIN products p ON p.id = i.product_id
		WHERE i.daily_sales_record_id = (SELECT id FROM r)
		ORDER BY i.position ASC
	`, shopUUID).Rows()
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	out := []ParchaOrderEntry{}
	recordDate := ""
	for rows.Next() {
		var pos int
		var pid, name, rd string
		if err := rows.Scan(&pos, &pid, &name, &rd); err != nil {
			continue
		}
		if rd != "" {
			recordDate = rd
		}
		if pid != "" {
			out = append(out, ParchaOrderEntry{ProductID: pid, Position: pos, Name: name})
		}
	}
	return out, recordDate, nil
}

// List returns this user's recent jobs, newest first. Limit clamped to [1, 50].
func (s *SmartPurchaseJobService) List(tenantID, userID string, limit int) ([]models.SmartPurchaseJob, error) {
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
	var jobs []models.SmartPurchaseJob
	err = s.db.Where("tenant_id = ? AND user_id = ?", tenantUUID, userUUID).
		Order("created_at DESC").
		Limit(limit).
		Find(&jobs).Error
	return jobs, err
}

// Cancel marks a pending job as canceled. No-op if already processing/terminal.
func (s *SmartPurchaseJobService) Cancel(jobID, tenantID, userID string) error {
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
	res := s.db.Model(&models.SmartPurchaseJob{}).
		Where("id = ? AND tenant_id = ? AND user_id = ? AND status = ?",
			jobUUID, tenantUUID, userUUID, models.SmartPurchaseJobPending).
		Updates(map[string]interface{}{
			"status":       models.SmartPurchaseJobCanceled,
			"completed_at": now,
		})
	if res.Error != nil {
		return res.Error
	}
	return nil
}

// --------------------------------------------------------------------------
// Worker
// --------------------------------------------------------------------------

// StartWorker launches the background goroutine that drains the pending queue.
func (s *SmartPurchaseJobService) StartWorker(ctx context.Context) {
	concurrency := purchaseWorkerConcurrency()
	log.Printf("Smart Purchase: starting %d background worker(s) (poll=%v, max_retries=%d)",
		concurrency, purchaseWorkerPollInterval, purchaseWorkerMaxRetries)

	s.rescueStalledJobs()

	// v1.0.337 — N parallel worker goroutines. processOne claims each job with
	// FOR UPDATE SKIP LOCKED, so the workers never grab the same job; they just
	// drain the pending queue N-at-a-time instead of one-at-a-time. This is the
	// fix for the queue-wait that made a submission look frozen while jobs ahead
	// of it processed sequentially (each ~3 min).
	for w := 0; w < concurrency; w++ {
		go func(workerID int) {
			ticker := time.NewTicker(purchaseWorkerPollInterval)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					log.Printf("Smart Purchase: worker %d shutting down", workerID)
					return
				case <-ticker.C:
					for s.processOne(ctx) {
						select {
						case <-ctx.Done():
							return
						default:
						}
					}
				}
			}
		}(w)
	}

	// Periodic stuck-job rescue.
	go func() {
		t := time.NewTicker(purchaseWorkerJobTimeout)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				cutoff := time.Now().Add(-2 * purchaseWorkerJobTimeout)
				res := s.db.Model(&models.SmartPurchaseJob{}).
					Where("status = ? AND started_at < ? AND retry_count < ?",
						models.SmartPurchaseJobProcessing, cutoff, purchaseWorkerMaxRetries).
					Updates(map[string]interface{}{
						"status":        models.SmartPurchaseJobPending,
						"started_at":    nil,
						"retry_count":   gorm.Expr("retry_count + 1"),
						"error_message": fmt.Sprintf("auto-rescued: stuck >%v in processing", 2*purchaseWorkerJobTimeout),
					})
				if res.Error != nil {
					log.Printf("Smart Purchase: periodic rescue failed: %v", res.Error)
					continue
				}
				if res.RowsAffected > 0 {
					log.Printf("Smart Purchase: periodic rescue requeued %d stuck jobs", res.RowsAffected)
				}

				// v1.0.369 — terminal-fail exhausted zombies. A job that was killed
				// mid-run (OOM, container restart) never reaches handleFailure, so it
				// stays in 'processing'. The requeue above only rescues retry_count <
				// max; once a job has burned all retries this way it would otherwise
				// sit in 'processing' FOREVER and the Flutter poll loop would spin
				// indefinitely. Mark such stuck-and-exhausted jobs 'failed' so the
				// client gets a clear terminal state instead of an infinite spinner.
				fres := s.db.Model(&models.SmartPurchaseJob{}).
					Where("status = ? AND started_at < ? AND retry_count >= ?",
						models.SmartPurchaseJobProcessing, cutoff, purchaseWorkerMaxRetries).
					Updates(map[string]interface{}{
						"status":        models.SmartPurchaseJobFailed,
						"completed_at":  time.Now(),
						"error_message": "extraction did not complete after max retries (worker likely killed mid-run, e.g. OOM) — please retry",
					})
				if fres.Error != nil {
					log.Printf("Smart Purchase: zombie terminal-fail sweep failed: %v", fres.Error)
				} else if fres.RowsAffected > 0 {
					log.Printf("Smart Purchase: terminal-failed %d exhausted zombie jobs stuck in processing", fres.RowsAffected)
				}
			}
		}
	}()
}

func (s *SmartPurchaseJobService) rescueStalledJobs() {
	res := s.db.Model(&models.SmartPurchaseJob{}).
		Where("status = ? AND retry_count < ?", models.SmartPurchaseJobProcessing, purchaseWorkerMaxRetries).
		Updates(map[string]interface{}{
			"status":      models.SmartPurchaseJobPending,
			"started_at":  nil,
			"retry_count": gorm.Expr("retry_count + 1"),
		})
	if res.Error != nil {
		log.Printf("Smart Purchase: rescue-stalled-jobs failed: %v", res.Error)
		return
	}
	if res.RowsAffected > 0 {
		log.Printf("Smart Purchase: rescued %d stalled jobs back to pending", res.RowsAffected)
	}
}

func (s *SmartPurchaseJobService) processOne(ctx context.Context) bool {
	if ctx.Err() != nil {
		return false
	}
	var claimed models.SmartPurchaseJob
	tx := s.db.Begin()
	if tx.Error != nil {
		log.Printf("Smart Purchase: worker begin tx failed: %v", tx.Error)
		return false
	}
	err := tx.Raw(`
		SELECT * FROM smart_purchase_jobs
		WHERE status = ? AND deleted_at IS NULL
		ORDER BY created_at ASC
		LIMIT 1
		FOR UPDATE SKIP LOCKED
	`, models.SmartPurchaseJobPending).Scan(&claimed).Error
	if err != nil || claimed.ID == uuid.Nil {
		tx.Rollback()
		return false
	}
	now := time.Now()
	if err := tx.Model(&models.SmartPurchaseJob{}).
		Where("id = ?", claimed.ID).
		Updates(map[string]interface{}{
			"status":     models.SmartPurchaseJobProcessing,
			"started_at": now,
		}).Error; err != nil {
		tx.Rollback()
		log.Printf("Smart Purchase: claim job %s failed: %v", claimed.ID, err)
		return false
	}
	if err := tx.Commit().Error; err != nil {
		log.Printf("Smart Purchase: claim commit failed: %v", err)
		return false
	}

	log.Printf("Smart Purchase: worker claimed job %s (retry=%d, invoices=%d gate_passes=%d)",
		claimed.ID, claimed.RetryCount, len(claimed.InvoiceImagePaths), len(claimed.GatePassImagePaths))

	jobCtx, cancel := context.WithTimeout(ctx, purchaseWorkerJobTimeout)
	defer cancel()
	s.runJob(jobCtx, &claimed)
	return true
}

func (s *SmartPurchaseJobService) runJob(ctx context.Context, job *models.SmartPurchaseJob) {
	if job.TenantID == nil {
		s.markFailed(job, "missing tenant_id on job row")
		return
	}

	// v1.0.369 — hold a global extraction slot for the whole memory-heavy span
	// (image bytes in RAM + Textract/Gemini), so concurrent jobs can never again
	// OOM the container. If ctx is cancelled while waiting (job timeout / shutdown),
	// leave the job claimed-but-untouched — the stalled-job rescue requeues it.
	release, ok := acquireExtractSlot(ctx)
	if !ok {
		log.Printf("Smart Purchase: job %s gave up waiting for an extraction slot (ctx done) — will be rescued", job.ID)
		return
	}
	defer release()

	readBatch := func(paths []string) ([]SmartPurchaseImage, error) {
		out := make([]SmartPurchaseImage, 0, len(paths))
		for _, p := range paths {
			data, err := os.ReadFile(p)
			if err != nil {
				return nil, fmt.Errorf("read image %s: %w", p, err)
			}
			ct := "image/jpeg"
			if strings.HasSuffix(strings.ToLower(p), ".png") {
				ct = "image/png"
			}
			out = append(out, SmartPurchaseImage{
				Data:        data,
				ContentType: ct,
				Filename:    filepath.Base(p),
			})
		}
		return out, nil
	}

	invoiceImgs, err := readBatch(job.InvoiceImagePaths)
	if err != nil {
		s.markFailed(job, err.Error())
		return
	}
	gateImgs, err := readBatch(job.GatePassImagePaths)
	if err != nil {
		s.markFailed(job, err.Error())
		return
	}

	vendorID := ""
	if job.VendorID != nil {
		vendorID = job.VendorID.String()
	}

	req := SmartPurchaseRequest{
		TenantID:       job.TenantID.String(),
		UserID:         job.UserID.String(),
		ShopID:         job.ShopID.String(),
		VendorID:       vendorID,
		Images:         invoiceImgs,
		GatePassImages: gateImgs,
		JobID:          job.ID.String(),
	}

	result, err := s.mainService.ProcessSmartPurchase(ctx, req)
	if err != nil {
		s.handleFailure(job, err.Error())
		return
	}

	raw, mErr := json.Marshal(result)
	if mErr != nil {
		s.handleFailure(job, fmt.Sprintf("marshal result: %v", mErr))
		return
	}
	var asMap models.SmartPurchaseJobResult
	if err := json.Unmarshal(raw, &asMap); err != nil {
		s.handleFailure(job, fmt.Sprintf("unmarshal result: %v", err))
		return
	}

	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.SmartPurchaseJobDone,
		"result":         asMap,
		"completed_at":   now,
		"error_message":  "",
		// v1.0.227 — terminal stage so the Flutter poll loop renders
		// "Done" on the final tick before transitioning to the
		// Purcha-gate / review screen.
		"progress_stage": models.SmartPurchaseStageDone,
	}
	if err := s.db.Model(&models.SmartPurchaseJob{}).
		Where("id = ?", job.ID).Updates(updates).Error; err != nil {
		log.Printf("Smart Purchase: store result for job %s failed: %v", job.ID, err)
		return
	}
	itemCount := 0
	if result != nil {
		itemCount = len(result.Items)
	}
	log.Printf("Smart Purchase: job %s completed (status=%s items=%d)",
		job.ID, result.Status, itemCount)
}

func isTransientPurchaseError(errMsg string) bool {
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
		strings.Contains(m, "tls handshake") ||
		strings.Contains(m, "throttling") ||
		strings.Contains(m, "throttled")
}

func (s *SmartPurchaseJobService) handleFailure(job *models.SmartPurchaseJob, errMsg string) {
	transient := isTransientPurchaseError(errMsg)
	if transient && job.RetryCount+1 < purchaseWorkerMaxRetries {
		_ = s.db.Model(&models.SmartPurchaseJob{}).
			Where("id = ?", job.ID).
			Updates(map[string]interface{}{
				"status":        models.SmartPurchaseJobPending,
				"retry_count":   job.RetryCount + 1,
				"started_at":    nil,
				"error_message": errMsg,
			}).Error
		log.Printf("Smart Purchase: job %s failed attempt %d (transient) — retrying: %s",
			job.ID, job.RetryCount+1, errMsg)
		return
	}
	if !transient {
		log.Printf("Smart Purchase: job %s permanent error — skipping retries: %s", job.ID, errMsg)
	}
	s.markFailed(job, errMsg)
}

func (s *SmartPurchaseJobService) markFailed(job *models.SmartPurchaseJob, errMsg string) {
	now := time.Now()
	_ = s.db.Model(&models.SmartPurchaseJob{}).
		Where("id = ?", job.ID).
		Updates(map[string]interface{}{
			"status":        models.SmartPurchaseJobFailed,
			"error_message": errMsg,
			"completed_at":  now,
			"retry_count":   job.RetryCount + 1,
		}).Error
	log.Printf("Smart Purchase: job %s PERMANENTLY FAILED after %d attempts: %s",
		job.ID, job.RetryCount+1, errMsg)
}

// --------------------------------------------------------------------------
// HTTP status-code mapping
// --------------------------------------------------------------------------

func PurchaseJobErrorToStatus(err error) int {
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
