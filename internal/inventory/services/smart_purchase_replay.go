package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/matching"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ============================================================================
// v1.0.193 W4.1 — Smart Purchase replay-learning DIAGNOSTIC endpoint.
//
// Re-runs the matcher against a previously-extracted job using the CURRENT
// alias / shop-rate / shop-bias state, and reports how many rows would now
// resolve differently. Does NOT write to the DB. Does NOT capture learning.
// Pure diagnostic — admin can validate "did the corrections we taught the
// system actually move the needle?".
//
// Why not re-run extraction:
//   - Extraction is the slow + costly half (Textract + Gemini/Claude).
//   - Operator-confirmed alias/rate state changes between extraction time
//     and replay time. Re-running ONLY the matcher isolates that signal.
//
// Behavior contract:
//   - Load smart_purchase_jobs.result_json
//   - For each persisted item, reconstruct an ExtractedPurchaseItem from
//     the OCR-extracted fields (BrandName, Size, SizeML, QuantityRaw,
//     RatePerBottle etc.) and re-call matchAndEnrichWithHint with the
//     current alias-cascade hint + current loadProducts + current
//     ShopInventoryBias state.
//   - Compare new top-pick vs original top-pick:
//       rows_unchanged       = product_id same (or both empty)
//       rows_now_matched     = was not_found, now matched
//       rows_now_correctly_picked = product_id changed to a different match
//
// Limitation: result_json holds matched output (SmartPurchaseExtractedItem)
// not the raw pre-match ExtractedPurchaseItem. The OCR-derived fields are
// preserved on the matched item (BrandName, Size, SizeML, RatePerBottle,
// Amount, BatchNumber, QuantityRaw, etc.) so the synthetic re-extraction
// is faithful for the matcher's purposes — what's lost is QuantityFlag
// and Confidence (extraction-time per-row), neither of which the matcher
// reads in the replay path.
// ============================================================================

// SmartPurchaseReplayRowDelta describes one replayed row's change vs the
// snapshot stored on the job.
type SmartPurchaseReplayRowDelta struct {
	RowNumber          int     `json:"row_number"`
	BrandName          string  `json:"brand_name"`
	Size               string  `json:"size"`
	OriginalProductID  string  `json:"original_product_id,omitempty"`
	OriginalStatus     string  `json:"original_status,omitempty"`
	NewProductID       string  `json:"new_product_id,omitempty"`
	NewStatus          string  `json:"new_status,omitempty"`
	NewMatchConfidence float64 `json:"new_match_confidence"`
	// Outcome: "unchanged" | "now_matched" | "now_correctly_picked" |
	//          "now_unmatched" (regression — alias/rate state worsened it).
	Outcome string `json:"outcome"`
}

// SmartPurchaseReplayResponse is the diagnostic summary returned to the admin
// caller. Counts always sum to the row count of the original job.
type SmartPurchaseReplayResponse struct {
	JobID                  string                          `json:"job_id"`
	TotalRows              int                             `json:"total_rows"`
	RowsUnchanged          int                             `json:"rows_unchanged"`
	RowsNowMatched         int                             `json:"rows_now_matched"`
	RowsNowCorrectlyPicked int                             `json:"rows_now_correctly_picked"`
	RowsNowUnmatched       int                             `json:"rows_now_unmatched"`
	Items                  []SmartPurchaseReplayRowDelta   `json:"items"`
	Note                   string                          `json:"note,omitempty"`
}

// ReplaySmartPurchaseMatcher loads the persisted SmartPurchaseResult on a
// smart_purchase_jobs row and re-runs the matcher with current alias / rate /
// shop-bias state. Read-only; does not mutate the job row.
//
// Auth gate: tenantID must match the job's tenant_id. We deliberately don't
// require user_id match — admin tooling may run replays for any user's job
// within the tenant.
func (s *SmartPurchaseService) ReplaySmartPurchaseMatcher(
	ctx context.Context,
	jobID, tenantID uuid.UUID,
) (*SmartPurchaseReplayResponse, error) {

	// 1. Load the job + verify tenant scoping.
	var job models.SmartPurchaseJob
	if err := s.db.Where("id = ? AND tenant_id = ?", jobID, tenantID).First(&job).Error; err != nil {
		return nil, fmt.Errorf("job not found: %w", err)
	}
	if job.Status != models.SmartPurchaseJobDone {
		return nil, fmt.Errorf("job status is %q — replay only supported on done jobs", job.Status)
	}
	if len(job.Result) == 0 {
		return nil, fmt.Errorf("job has no result blob — nothing to replay")
	}

	// 2. Decode the persisted SmartPurchaseResult from the JSONB blob.
	rawResult, err := json.Marshal(job.Result)
	if err != nil {
		return nil, fmt.Errorf("re-marshal job result: %w", err)
	}
	var snapshot SmartPurchaseResult
	if err := json.Unmarshal(rawResult, &snapshot); err != nil {
		return nil, fmt.Errorf("decode snapshot: %w", err)
	}
	if len(snapshot.Items) == 0 {
		return &SmartPurchaseReplayResponse{
			JobID:     jobID.String(),
			TotalRows: 0,
			Note:      "snapshot has zero items — nothing to replay",
		}, nil
	}

	// 3. Rebuild matcher inputs (mirrors ProcessSmartPurchase lines ~447-512).
	shopID := job.ShopID
	products, err := s.loadProducts(tenantID, &shopID)
	if err != nil {
		return nil, fmt.Errorf("loadProducts: %w", err)
	}
	stockMap, err := s.loadStockLevels(tenantID, shopID)
	if err != nil {
		log.Printf("SmartPurchase replay: loadStockLevels failed (non-fatal): %v", err)
		stockMap = map[string]int{}
	}
	matchProducts := make([]matching.Product, len(products))
	productDBMap := make(map[string]dbProduct, len(products))
	for i, p := range products {
		brandName := p.BrandName
		if brandName == "" {
			brandName = p.Name
		}
		matchProducts[i] = matching.Product{
			ID:                p.ID,
			Name:              p.Name,
			BrandName:         brandName,
			DisplayName:       p.DisplayName,
			ExciseBrandName:   p.ExciseBrandName,
			ExciseDisplayName: p.ExciseDisplayName,
			Size:              p.Size,
			SizeML:            matching.ParseSizeML(p.Size),
			SellingPrice:      p.SellingPrice,
			CostPrice:         p.CostPrice,
		}
		productDBMap[p.ID] = p
	}
	prepared := matching.PrepareProducts(matchProducts)
	matchConfig := matching.DefaultPurchaseConfig()
	matchConfig.MinThreshold = 0.55

	tenantState := s.getTenantState(tenantID)
	masterBrandsBySize := make(map[int][]models.MasterBrandInfo)
	for _, it := range snapshot.Items {
		if it.SizeML <= 0 {
			continue
		}
		if _, ok := masterBrandsBySize[it.SizeML]; ok {
			continue
		}
		masterBrandsBySize[it.SizeML] = s.loadMasterBrands(it.SizeML, tenantState)
	}

	// 4. Pre-resolve alias hints with the CURRENT alias state. Same logic
	// as ProcessSmartPurchase — only exact-source hits are honoured.
	aliasResolved := map[string]uuid.UUID{}
	if s.aliasService != nil {
		// WS1.1 — strict shop isolation (same gate as ProcessSmartPurchase).
		shopGuard := shopAliasGuardEnabled(job.UserID.String())
		for _, it := range snapshot.Items {
			brand := strings.TrimSpace(it.BrandName)
			if brand == "" {
				continue
			}
			var (
				pid *uuid.UUID
				src alias.AliasSource
				ok  bool
			)
			if shopGuard {
				pid, _, src, ok = s.aliasService.LookupAliasCascadeShopValidated(ctx, tenantID, shopID, brand, "")
			} else {
				pid, _, src, ok = s.aliasService.LookupAliasCascade(ctx, tenantID, shopID, brand, "")
			}
			if !ok || pid == nil {
				continue
			}
			if src == alias.AliasSourceShopExact || src == alias.AliasSourceTenantExact {
				aliasResolved[strings.ToLower(brand)] = *pid
			}
		}
	}

	// 5. Replay each row.
	resp := &SmartPurchaseReplayResponse{
		JobID:     jobID.String(),
		TotalRows: len(snapshot.Items),
		Items:     make([]SmartPurchaseReplayRowDelta, 0, len(snapshot.Items)),
	}
	for _, snap := range snapshot.Items {
		// Reconstruct an ExtractedPurchaseItem from the snapshot's OCR
		// fields. The matcher only reads brand/size/quantity/rate/amount —
		// all of which round-trip on SmartPurchaseExtractedItem.
		extracted := ExtractedPurchaseItem{
			RowNumber:       float64(snap.RowNumber),
			Brand:           snap.BrandName,
			Category:        snap.Category,
			SizeText:        snap.Size,
			SizeML:          float64(snap.SizeML),
			QuantityRaw:     float64(snap.QuantityRaw),
			QuantityUnit:    snap.QuantityUnit,
			BottlesPerCase:  float64(snap.BottlesPerCase),
			QuantityBottles: float64(snap.QuantityBottles),
			RatePerBottle:   snap.RatePerBottle,
			RatePerCase:     snap.RatePerCase,
			Amount:          snap.Amount,
			BatchNumber:     snap.BatchNumber,
		}

		var aliasHint *uuid.UUID
		if pid, ok := aliasResolved[strings.ToLower(strings.TrimSpace(snap.BrandName))]; ok {
			h := pid
			aliasHint = &h
		}

		// Replay does NOT pass gate-pass enrichment — the snapshot already
		// resolved that, and we want to isolate the alias/rate/bias signal.
		// Pass nil/empty for GP inputs so cross-validation stays neutral.
		newItem := s.matchAndEnrichWithHint(
			extracted,
			prepared,
			matchConfig,
			productDBMap,
			stockMap,
			"",  // gatePassBrand
			nil, // gatePassItem
			nil, // dutyItems — empty disables cross-val flags
			masterBrandsBySize[snap.SizeML],
			aliasHint,
			false, // gpOnly — replay isolates alias/rate signal, no GP name override
		)

		origPID := ""
		if snap.ProductID != nil {
			origPID = *snap.ProductID
		}
		newPID := ""
		if newItem.ProductID != nil {
			newPID = *newItem.ProductID
		}

		delta := SmartPurchaseReplayRowDelta{
			RowNumber:          snap.RowNumber,
			BrandName:          snap.BrandName,
			Size:               snap.Size,
			OriginalProductID:  origPID,
			OriginalStatus:     snap.Status,
			NewProductID:       newPID,
			NewStatus:          newItem.Status,
			NewMatchConfidence: newItem.MatchConfidence,
		}

		// Outcome bucketing.
		switch {
		case origPID == newPID && origPID != "":
			delta.Outcome = "unchanged"
			resp.RowsUnchanged++
		case origPID == "" && newPID == "":
			delta.Outcome = "unchanged"
			resp.RowsUnchanged++
		case origPID == "" && newPID != "":
			delta.Outcome = "now_matched"
			resp.RowsNowMatched++
		case origPID != "" && newPID == "":
			delta.Outcome = "now_unmatched"
			resp.RowsNowUnmatched++
		default:
			// Both non-empty and different.
			delta.Outcome = "now_correctly_picked"
			resp.RowsNowCorrectlyPicked++
		}
		resp.Items = append(resp.Items, delta)
	}

	log.Printf("SmartPurchase replay: job=%s tenant=%s rows=%d unchanged=%d now_matched=%d picked=%d unmatched=%d",
		jobID, tenantID, resp.TotalRows,
		resp.RowsUnchanged, resp.RowsNowMatched, resp.RowsNowCorrectlyPicked, resp.RowsNowUnmatched)

	return resp, nil
}
