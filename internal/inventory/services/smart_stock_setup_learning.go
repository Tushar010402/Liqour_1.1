package services

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// ============================================================================
// Active learning — three pipelines that all read from the same source of
// truth: stock_setup_items.raw_ai_extraction (what AI saw) vs the row's
// final fields (what user approved).
//
//   #2 Few-shot   — store best (predicted, ground_truth) pairs; inject 3-5
//                   into the cached system prompt once 5+ samples per
//                   tenant exist.
//   #3 Distinguishers — auto-derive new flavor/variant tokens from
//                   user_corrected rows where AI matched the wrong sibling.
//   #6 Calibration — log (predicted_conf, was_corrected) to a new table;
//                   weekly cron fits a Platt scaling per-tenant so the
//                   amber-underline threshold becomes principled.
//
// All three activate automatically once enough labeled data exists; until
// then they're harmless no-ops. The data-capture path runs on every approve.
// ============================================================================

const (
	fewShotMinSamples       = 5
	fewShotMaxSamples       = 5
	fewShotCacheTTL         = 1 * time.Hour
	calibrationMinSamples   = 100
	distinguisherMinHits    = 3 // a token must appear in 3+ corrections to be promoted
)

// CorrectionOutcome is one (predicted, actual) pair from a user-approved
// stock setup. Captured async on every apply. Powers all three pipelines.
type CorrectionOutcome struct {
	ID           uuid.UUID  `gorm:"type:uuid;primary_key;default:uuid_generate_v4()"`
	TenantID     uuid.UUID  `gorm:"type:uuid;not null;index"`
	JobID        *uuid.UUID `gorm:"type:uuid;index"`
	ItemID       *uuid.UUID `gorm:"type:uuid"`

	// What the AI said.
	AIBrand          string  `gorm:"size:255"`
	AIRate           float64 `gorm:"type:numeric(10,2)"`
	AIQty            int
	AIConfidence     float64 `gorm:"type:numeric(4,3)"`
	AIMatchedProduct string  `gorm:"size:255"`

	// What the user approved.
	UserBrand           string  `gorm:"size:255"`
	UserRate            float64 `gorm:"type:numeric(10,2)"`
	UserQty             int
	UserMatchedProduct  string  `gorm:"size:255"`

	// Derived flags.
	WasCorrected   bool   `gorm:"default:false;index"` // any field changed
	BrandCorrected bool   `gorm:"default:false"`
	RateCorrected  bool   `gorm:"default:false"`
	QtyCorrected   bool   `gorm:"default:false"`
	CorrectionType string `gorm:"size:32"` // "match_swap" | "name_edit" | "rate_edit" | "qty_edit" | "skipped"

	CreatedAt time.Time `gorm:"not null;index"`
}

func (CorrectionOutcome) TableName() string { return "ai_correction_outcomes" }

// LogCorrectionOutcomes is the data-capture entrypoint called from
// ApplyStockSetup after a successful save. Async + non-blocking — failures
// are logged but never affect the apply response.
func (s *SmartStockSetupService) LogCorrectionOutcomes(tenantID uuid.UUID, jobIDStr string, items []apiCorrectionInput) {
	if len(items) == 0 {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("Smart Stock Setup: LogCorrectionOutcomes panic recovered: %v", r)
			}
		}()
		var jobUUID *uuid.UUID
		if id, err := uuid.Parse(jobIDStr); err == nil {
			jobUUID = &id
		}
		batch := make([]CorrectionOutcome, 0, len(items))
		for _, it := range items {
			rec := CorrectionOutcome{
				TenantID:           tenantID,
				JobID:              jobUUID,
				AIBrand:            it.AIBrand,
				AIRate:             it.AIRate,
				AIQty:              it.AIQty,
				AIConfidence:       it.AIConfidence,
				AIMatchedProduct:   it.AIMatchedProduct,
				UserBrand:          it.UserBrand,
				UserRate:           it.UserRate,
				UserQty:            it.UserQty,
				UserMatchedProduct: it.UserMatchedProduct,
				CreatedAt:          time.Now(),
			}
			rec.BrandCorrected = !strings.EqualFold(strings.TrimSpace(rec.AIBrand), strings.TrimSpace(rec.UserBrand)) && rec.UserBrand != ""
			rec.RateCorrected = !floatNearlyEqual(rec.AIRate, rec.UserRate, 0.01) && rec.UserRate > 0
			rec.QtyCorrected = rec.AIQty != rec.UserQty && rec.UserQty > 0
			// Honour the Flutter-side was_corrected flag too — covers
			// alternative-picks where the user swapped product_id without
			// editing the brand-name string (e.g. picked the right item
			// from the alternative-matches dropdown). Without this flag,
			// alternative-pick corrections would never reach the learning
			// pipelines because the brand string didn't change.
			rec.WasCorrected = rec.BrandCorrected || rec.RateCorrected || rec.QtyCorrected || it.PayloadWasCorrected
			if rec.WasCorrected && !rec.BrandCorrected && !rec.RateCorrected && !rec.QtyCorrected {
				// Pure alternative-pick: brand_corrected stays false but the
				// row IS a learning signal (user swapped product link).
				rec.BrandCorrected = true
			}
			rec.CorrectionType = correctionTypeOf(rec)
			batch = append(batch, rec)
		}
		if err := s.db.CreateInBatches(&batch, 200).Error; err != nil {
			log.Printf("Smart Stock Setup: correction-outcome insert failed: %v", err)
			return
		}
		log.Printf("Smart Stock Setup: logged %d correction outcomes (job %s)", len(batch), jobIDStr)
	}()
}

// apiCorrectionInput is the lean shape ApplyStockSetup builds and feeds in.
// Decoupled from the model so callers don't have to know the GORM type.
type apiCorrectionInput struct {
	AIBrand            string
	AIRate             float64
	AIQty              int
	AIConfidence       float64
	AIMatchedProduct   string
	UserBrand          string
	UserRate           float64
	UserQty            int
	UserMatchedProduct string
	// PayloadWasCorrected = the apply request's was_corrected flag from
	// Flutter. Captures alternative-pick corrections (user swapped
	// product_id without editing the brand-name string), which the plain
	// brand-string-difference check would otherwise miss.
	PayloadWasCorrected bool
}

func correctionTypeOf(r CorrectionOutcome) string {
	switch {
	case r.BrandCorrected:
		return "name_edit"
	case r.RateCorrected:
		return "rate_edit"
	case r.QtyCorrected:
		return "qty_edit"
	case !r.WasCorrected:
		return "approved_as_is"
	default:
		return "other"
	}
}

func floatNearlyEqual(a, b, eps float64) bool {
	d := a - b
	if d < 0 {
		d = -d
	}
	return d <= eps
}

// ============================================================================
// captureApplyLearning — single entrypoint for everything the apply path
// needs to teach the model. Runs unconditionally (success, failure, and
// pending_approval all qualify), so the user's review-screen edits become
// training signal even when the SQL apply died.
//
// History (v1.0.132): pre-fix the alias-learning + LogCorrectionOutcomes
// blocks lived inline in ApplyStockSetup behind an `if applied > 0` gate.
// The May 1 2026 incident (a1a30429-868f-4ece-ba2c-a3375f83da22) showed
// the cost: a column-name mismatch killed the wrapping txn → applied=0 →
// gate skipped → "R.S Barrel → SEAGRAM'S ROYAL STAG BARREL SELECT RESERVE",
// the three negative aliases for the rejected rows, and the OCR-junk
// signal for row 5 all evaporated. This helper lifts the work out of the
// gate and makes it idempotent (the alias upserts already are; the
// outcome-log batch is fine to insert even if the apply rolled back —
// the calibration pipeline can filter on apply_outcome later).
//
// Idempotency: LearnAlias / LearnNegativeAlias / shop_product_rates
// upserts all use ON CONFLICT, so calling this twice for the same
// (tenant, ocr_text, product) is safe.
//
// Async: every callee already spawns its own goroutine, but the loop
// itself runs in a goroutine here too so the apply handler can return
// the HTTP response without waiting on the model lookup.
//
// applyOutcome is logged for telemetry (one of "applied",
// "pending_approval", "apply_failed") so future analysis can split
// learning hits by outcome.
// ============================================================================
func (s *SmartStockSetupService) captureApplyLearning(
	tenantID uuid.UUID,
	userID uuid.UUID,
	req SmartStockSetupApplyRequest,
	setupRecordID uuid.UUID,
	applyOutcome string,
) {
	if len(req.Items) == 0 {
		return
	}

	// v1.0.160 — derive shop scope from the request. ApplyStockSetup callers
	// always set req.ShopID; ReplayApplyLearning may pass an empty string in
	// older flows, in which case we fall back to tenant-wide (uuid.Nil) so
	// the legacy behaviour is preserved.
	shopID := uuid.Nil
	if parsed, perr := uuid.Parse(req.ShopID); perr == nil {
		shopID = parsed
	}

	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("Smart Stock Setup: captureApplyLearning panic recovered: %v (outcome=%s)", r, applyOutcome)
			}
		}()

		aliasHits := 0
		negAliasHits := 0

		for _, item := range req.Items {
			// Only learn from explicit user corrections — auto-matched rows
			// are not signal because they're the AI's own guess fed back.
			if !item.WasCorrected {
				continue
			}

			// Three-tier alias key fallback (v1.0.115). Picker swap leaves
			// OCRText empty AND overwrites BrandName with the picked name,
			// so the AI's first-guess brand text is the only thing that
			// can serve as the alias key for picker rows.
			ocrText := item.OCRText
			if ocrText == "" {
				ocrText = item.OriginalAIBrand
			}
			if ocrText == "" {
				ocrText = item.BrandName
			}
			if ocrText == "" {
				continue
			}

			// Negative alias: user explicitly rejected a different product
			// than what the AI / matcher first proposed. This is signal
			// even when the apply failed — "this OCR text does NOT mean
			// this product at this shop" is permanent learning.
			//
			// v1.0.160 — scoped to the shop that did the correction so a
			// rejection at FM Tower doesn't suppress the same alias at
			// Tetra Pack (where the user may legitimately mean it).
			if item.OriginalProductID != "" && item.OriginalProductID != item.ProductID {
				if rejectedPID, perr := uuid.Parse(item.OriginalProductID); perr == nil {
					if s.aliasService != nil {
						if naErr := s.aliasService.LearnNegativeAliasScoped(tenantID, shopID, ocrText, rejectedPID); naErr == nil {
							negAliasHits++
						}
					}
				}
			}

			// Positive alias: only when we have a final product_id to point
			// to (the user kept a row and confirmed a match). On apply_failed
			// for a row the user kept-and-edited, item.ProductID may already
			// be the new auto-create UUID OR may be the empty string if the
			// failure happened in the deferred-create branch — in the latter
			// case there's nothing to attach the alias to and we skip.
			if item.ProductID == "" {
				continue
			}
			pid, perr := uuid.Parse(item.ProductID)
			if perr != nil {
				continue
			}
			if s.aliasService == nil {
				continue
			}

			var product models.Product
			if err := s.db.Select("name").Where("id = ?", pid).First(&product).Error; err != nil {
				// Product disappeared (apply_failed: txn rollback may have
				// undone an auto-create) — fall back to user's review-screen
				// brand text as the canonical name. Better to learn an
				// imperfect alias than to lose the signal entirely.
				canonical := item.EditedName
				if canonical == "" {
					canonical = item.OfficialBrandName
				}
				if canonical == "" {
					canonical = item.BrandName
				}
				if canonical == "" {
					continue
				}
				// v1.0.160 — scoped write so the unmaterialised lesson stays
				// anchored to the shop that taught it.
				// v1.0.199 — DUAL-WRITE: ALSO write tenant-wide so other shops
				// in the same tenant inherit the lesson without re-teaching.
				// Shop-scoped row is the local-confirmation marker; tenant-wide
				// row is the default that benefits sibling shops via the
				// LookupAliasCascade tenant-exact step. Shop can still override
				// later by writing a different product at shop scope.
				if laErr := s.aliasService.LearnAliasScoped(tenantID, shopID, ocrText, canonical, nil, "user_correction_unmaterialized"); laErr == nil {
					aliasHits++
					log.Printf("SmartStockSetup learning(%s): LEARNED unmaterialized correction '%s' -> '%s' (product missing, shop=%s)", applyOutcome, ocrText, canonical, shopID)
				}
				if shopID != uuid.Nil {
					if laErr := s.aliasService.LearnAliasScoped(tenantID, uuid.Nil, ocrText, canonical, nil, "user_correction_unmaterialized_tenant"); laErr == nil {
						log.Printf("SmartStockSetup learning(%s): LEARNED tenant-wide unmaterialized '%s' -> '%s'", applyOutcome, ocrText, canonical)
					}
				}
				continue
			}
			// v1.0.160 — scoped positive learn.
			// v1.0.199 — DUAL-WRITE same rationale as above.
			if laErr := s.aliasService.LearnAliasScoped(tenantID, shopID, ocrText, product.Name, &pid, "user_correction"); laErr == nil {
				aliasHits++
				log.Printf("SmartStockSetup learning(%s): LEARNED correction '%s' -> '%s' (shop=%s)", applyOutcome, ocrText, product.Name, shopID)
			}
			if shopID != uuid.Nil {
				if laErr := s.aliasService.LearnAliasScoped(tenantID, uuid.Nil, ocrText, product.Name, &pid, "user_correction_tenant"); laErr == nil {
					log.Printf("SmartStockSetup learning(%s): LEARNED tenant-wide '%s' -> '%s'", applyOutcome, ocrText, product.Name)
				}
			}
		}

		log.Printf("Smart Stock Setup: captureApplyLearning done — outcome=%s alias_hits=%d neg_alias_hits=%d items=%d record=%s",
			applyOutcome, aliasHits, negAliasHits, len(req.Items), setupRecordID)
	}()

	// Correction-outcome telemetry — separate goroutine so the alias loop
	// above doesn't block on the batch insert. LogCorrectionOutcomes is
	// already its own goroutine internally.
	samples := make([]apiCorrectionInput, 0, len(req.Items))
	for _, it := range req.Items {
		samples = append(samples, apiCorrectionInput{
			AIBrand:             it.OCRText,
			AIRate:              it.Rate,
			AIQty:               it.Quantity,
			AIConfidence:        0,
			AIMatchedProduct:    it.OriginalProductID,
			UserBrand:           it.BrandName,
			UserRate:            it.Rate,
			UserQty:             it.Quantity,
			UserMatchedProduct:  it.BrandName,
			PayloadWasCorrected: it.WasCorrected,
		})
	}
	jobIDStr := ""
	if setupRecordID != uuid.Nil {
		jobIDStr = setupRecordID.String()
	}
	s.LogCorrectionOutcomes(tenantID, jobIDStr, samples)
	_ = userID
}

// ReplayApplyLearning is the public hook for
// POST /stocks/smart-setup/jobs/:id/replay-learning. Unlike captureApplyLearning
// (which sees a real setup_record_id when the apply succeeds), replay only
// has the job UUID — we tag the outcome explicitly so calibration / few-shot
// pipelines can later filter or weight replayed signal. setup_record_id is
// uuid.Nil because no record was created.
func (s *SmartStockSetupService) ReplayApplyLearning(
	tenantID uuid.UUID,
	userID uuid.UUID,
	jobID string,
	req SmartStockSetupApplyRequest,
) {
	log.Printf("Smart Stock Setup: replay-learning invoked — job=%s tenant=%s user=%s items=%d",
		jobID, tenantID, userID, len(req.Items))
	s.captureApplyLearning(tenantID, userID, req, uuid.Nil, "replayed")
}

// ============================================================================
// #2 Few-shot prompt builder
// ============================================================================

type fewShotCache struct {
	mu      sync.RWMutex
	entries map[uuid.UUID]fewShotEntry
}

type fewShotEntry struct {
	hint   string
	loaded time.Time
}

var globalFewShotCache = &fewShotCache{entries: map[uuid.UUID]fewShotEntry{}}

// FewShotPromptHint returns a "WORKED EXAMPLES from this tenant" block to
// prepend to the system prompt, or empty string when not enough labeled
// samples exist yet OR when the operator hasn't explicitly opted in.
//
// SECURITY: Few-shot pulls strings (OCR text, user-typed brand names) into
// the cached system prompt. Even though those strings are bounded to register
// brand names, an adversarial user could try to inject prompt-steering text.
// Gated behind SMART_STOCK_SETUP_FEWSHOT_ENABLED=1 so the operator must
// review the data before turning it on. The capture pipeline still runs
// regardless — it's just the inject path that's gated.
func (s *SmartStockSetupService) FewShotPromptHint(tenantID uuid.UUID) string {
	if tenantID == uuid.Nil {
		return ""
	}
	if os.Getenv("SMART_STOCK_SETUP_FEWSHOT_ENABLED") != "1" {
		return ""
	}
	globalFewShotCache.mu.RLock()
	c, ok := globalFewShotCache.entries[tenantID]
	globalFewShotCache.mu.RUnlock()
	if ok && time.Since(c.loaded) < fewShotCacheTTL {
		return c.hint
	}

	// Sample selection: rows where the user corrected the brand. Those are
	// the highest-signal training pairs (model was wrong, ground truth is
	// known). Limit to fewShotMaxSamples per tenant.
	var rows []CorrectionOutcome
	err := s.db.Where("tenant_id = ? AND brand_corrected = TRUE AND ai_brand <> '' AND user_matched_product <> ''", tenantID).
		Order("created_at DESC").
		Limit(fewShotMaxSamples).
		Find(&rows).Error
	hint := ""
	if err == nil && len(rows) >= fewShotMinSamples {
		var sb strings.Builder
		sb.WriteString("\n\nWORKED EXAMPLES from this shop's prior corrections — when you see similar text, prefer the corrected interpretation:\n")
		for i, r := range rows {
			sb.WriteString(formatFewShotLine(i+1, r))
		}
		hint = sb.String()
	}

	globalFewShotCache.mu.Lock()
	globalFewShotCache.entries[tenantID] = fewShotEntry{hint: hint, loaded: time.Now()}
	globalFewShotCache.mu.Unlock()
	return hint
}

func formatFewShotLine(idx int, r CorrectionOutcome) string {
	return "  " + itoaSmall(idx) + ". OCR text: \"" + r.AIBrand + "\" → correct product: \"" + r.UserMatchedProduct + "\"\n"
}

func itoaSmall(n int) string {
	if n < 10 {
		return string(rune('0' + n))
	}
	return "?"
}

// ============================================================================
// #3 Active-learning distinguisher derivation
// ============================================================================

// derivedDistinguishers is a hot-path lookup populated by RefreshDistinguishers
// (cron-triggered). Keys are tokens that user corrections show should never
// fuzz-match across — e.g. "spicymint" was confused for "cranberry" in 5+
// corrections, so it's added here.
type derivedDistinguishers struct {
	mu     sync.RWMutex
	tokens map[string]struct{}
}

var globalDerivedDistinguishers = &derivedDistinguishers{tokens: map[string]struct{}{}}

// DerivedDistinguisher returns true when token t was learned from corrections
// to be a hard distinguisher (should never fuzz-bridge during fuzzy match).
func DerivedDistinguisher(t string) bool {
	globalDerivedDistinguishers.mu.RLock()
	_, ok := globalDerivedDistinguishers.tokens[strings.ToLower(t)]
	globalDerivedDistinguishers.mu.RUnlock()
	return ok
}

// RefreshDistinguishers is the cron entry point. Scans ai_correction_outcomes
// where brand_corrected=TRUE, extracts tokens that the AI's brand had but the
// user's chosen brand did not (or vice versa), counts hits, promotes any
// token with hits >= distinguisherMinHits to the live set.
func (s *SmartStockSetupService) RefreshDistinguishers(ctx context.Context) error {
	var rows []CorrectionOutcome
	if err := s.db.WithContext(ctx).
		Where("brand_corrected = TRUE AND ai_brand <> '' AND user_brand <> ''").
		Order("created_at DESC").
		Limit(2000).
		Find(&rows).Error; err != nil {
		return err
	}
	hits := map[string]int{}
	for _, r := range rows {
		aiTokens := tokenSet(r.AIBrand)
		userTokens := tokenSet(r.UserBrand)
		for t := range symmetricDiff(aiTokens, userTokens) {
			if len(t) < 3 || stockSetupGenericWords[t] || labelColorTokens[t] {
				continue
			}
			hits[t]++
		}
	}
	promoted := map[string]struct{}{}
	for t, n := range hits {
		if n >= distinguisherMinHits {
			promoted[t] = struct{}{}
		}
	}
	globalDerivedDistinguishers.mu.Lock()
	globalDerivedDistinguishers.tokens = promoted
	globalDerivedDistinguishers.mu.Unlock()
	log.Printf("Smart Stock Setup: refreshed derived distinguishers — %d tokens from %d correction rows",
		len(promoted), len(rows))
	return nil
}

func tokenSet(s string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, t := range strings.Fields(strings.ToLower(s)) {
		if len(t) >= 3 {
			out[t] = struct{}{}
		}
	}
	return out
}

func symmetricDiff(a, b map[string]struct{}) map[string]struct{} {
	out := map[string]struct{}{}
	for t := range a {
		if _, in := b[t]; !in {
			out[t] = struct{}{}
		}
	}
	for t := range b {
		if _, in := a[t]; !in {
			out[t] = struct{}{}
		}
	}
	return out
}

// ============================================================================
// #6 Confidence calibration (Platt scaling)
// ============================================================================

// CalibrationStats summarises the confidence vs correctness curve per tenant.
// Built by RefreshCalibration; consulted by the Flutter amber-threshold
// decider so a tenant whose 0.7-confidence rows are 95% correct can lift the
// threshold; one whose 0.7 rows are 50% correct keeps it.
type CalibrationStats struct {
	TenantID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	SampleCount      int       `gorm:"not null"`
	BucketAccuracy   datatypesJSON `gorm:"type:jsonb"` // {"0.5":0.62,"0.6":0.71,...}
	UpdatedAt        time.Time     `gorm:"not null"`
}

func (CalibrationStats) TableName() string { return "ai_calibration_stats" }

// datatypesJSON is a tiny shim so this file doesn't drag the gorm.io/datatypes
// import everywhere — we marshal manually.
type datatypesJSON []byte

func (j *datatypesJSON) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	switch v := value.(type) {
	case []byte:
		*j = append((*j)[:0], v...)
	case string:
		*j = append((*j)[:0], v...)
	}
	return nil
}

// RefreshCalibration computes per-bucket accuracy from the last 90 days of
// corrections per tenant. Run from a cron. Once SampleCount >= calibrationMinSamples,
// the Flutter threshold logic switches to data-driven values.
func (s *SmartStockSetupService) RefreshCalibration(ctx context.Context) error {
	type tenantBucket struct {
		TenantID uuid.UUID
		Bucket   float64
		Total    int
		Correct  int
	}
	var rows []tenantBucket
	err := s.db.WithContext(ctx).Raw(`
		SELECT tenant_id,
		       FLOOR(ai_confidence * 10) / 10.0 AS bucket,
		       COUNT(*)::int                     AS total,
		       SUM(CASE WHEN was_corrected THEN 0 ELSE 1 END)::int AS correct
		FROM ai_correction_outcomes
		WHERE created_at > NOW() - INTERVAL '90 days'
		  AND ai_confidence IS NOT NULL
		GROUP BY tenant_id, bucket
	`).Scan(&rows).Error
	if err != nil {
		return err
	}
	perTenant := map[uuid.UUID]map[string]float64{}
	totals := map[uuid.UUID]int{}
	for _, r := range rows {
		if perTenant[r.TenantID] == nil {
			perTenant[r.TenantID] = map[string]float64{}
		}
		acc := 0.0
		if r.Total > 0 {
			acc = float64(r.Correct) / float64(r.Total)
		}
		key := strings.TrimRight(strings.TrimRight(formatFloat1(r.Bucket), "0"), ".")
		if key == "" {
			key = "0"
		}
		perTenant[r.TenantID][key] = acc
		totals[r.TenantID] += r.Total
	}
	for tid, buckets := range perTenant {
		if totals[tid] < calibrationMinSamples {
			continue
		}
		blob, _ := json.Marshal(buckets)
		stats := CalibrationStats{
			TenantID:       tid,
			SampleCount:    totals[tid],
			BucketAccuracy: blob,
			UpdatedAt:      time.Now(),
		}
		_ = s.db.Save(&stats).Error
	}
	return nil
}

func formatFloat1(f float64) string {
	// Compact 1-decimal formatter; avoids strconv import bloat in this file.
	scaled := int64(f*10 + 0.5)
	if scaled < 0 {
		return "0"
	}
	whole := scaled / 10
	frac := scaled % 10
	return itoaInt64(whole) + "." + itoaInt64(frac)
}

func itoaInt64(n int64) string {
	if n == 0 {
		return "0"
	}
	out := ""
	for n > 0 {
		out = string(rune('0'+n%10)) + out
		n /= 10
	}
	return out
}

// ============================================================================
// Periodic refresher — wired into the inventory worker startup so all three
// pipelines stay fresh without a separate cron service.
// ============================================================================

// StartLearningRefresher launches the background goroutine that keeps few-shot,
// derived distinguishers, and calibration up to date. Called once during
// service init. Runs every learningRefreshInterval; idempotent + cheap.
func (s *SmartStockSetupService) StartLearningRefresher(ctx context.Context) {
	go func() {
		// Initial run after 30s so we don't slow boot.
		select {
		case <-ctx.Done():
			return
		case <-time.After(30 * time.Second):
		}
		s.runLearningRefresh(ctx)

		t := time.NewTicker(15 * time.Minute)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				s.runLearningRefresh(ctx)
			}
		}
	}()
}

func (s *SmartStockSetupService) runLearningRefresh(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Smart Stock Setup: learning refresh panic recovered: %v", r)
		}
	}()
	if err := s.RefreshDistinguishers(ctx); err != nil {
		log.Printf("Smart Stock Setup: distinguisher refresh failed: %v", err)
	}
	if err := s.RefreshCalibration(ctx); err != nil {
		log.Printf("Smart Stock Setup: calibration refresh failed: %v", err)
	}
	// Few-shot doesn't have a separate refresh — the cache TTL handles it.
	log.Printf("Smart Stock Setup: learning refresh complete (next in 15m)")
}

// ============================================================================
// AutoMigrate hook — called from main when the inventory service starts.
// ============================================================================

func MigrateLearningSchemas(db *gorm.DB) error {
	if err := db.AutoMigrate(&CorrectionOutcome{}, &CalibrationStats{}, &ShopTemplate{}); err != nil {
		return err
	}
	// v1.0.295 — partial unique index on stocks (tenant_id, shop_id, product_id)
	// for live rows only. Without it, the Stock Setup write sites could create
	// duplicate live rows when an existing row was soft-deleted (a 2026-05-14
	// bulk cleanup caused this on chhotu's tenant — 8 ghost+live pairs, and
	// Flutter ended up reading qty=4 instead of qty=15 for After Dark Blue Rare
	// on the 750ml record 4e90dd7a, surfacing as the 244-vs-255 display gap).
	// The code-side Unscoped() fix in ApplyStockSetup / ApproveStockSetup /
	// ReapplyStockSetup now revives soft-deleted rows; this index is the
	// belt-and-braces guarantee that even bad code can't slip a duplicate
	// through. IF NOT EXISTS so the migration is idempotent.
	if err := db.Exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS idx_stocks_unique_live_tenant_shop_product
		ON stocks (tenant_id, shop_id, product_id)
		WHERE deleted_at IS NULL
	`).Error; err != nil {
		return err
	}
	return nil
}

// ============================================================================
// Helper used by template + few-shot above. Sorted-deduped string slice.
// ============================================================================

var _ = sort.Strings // silence unused import if compiler is finicky
