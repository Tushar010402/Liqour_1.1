package services

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// RowReextractRequest is the input to the per-row re-extract flow. The caller
// identifies the original job + which row to re-read; the service loads the
// image back from disk, calls the constrained single-row OCR, and returns a
// fresh ExtractedStockRegisterItem plus the master-brand candidates the AI
// was allowed to pick from.
type RowReextractRequest struct {
	TenantID    string
	JobID       string
	PageNumber  int
	RowNumber   int
	BandCenter  float64 // 0-1 fraction of image height, or 0 to auto-compute
}

// RowReextractResult is returned to Flutter for the "Current" vs "AI suggestion"
// comparison modal. ExtractedRow is the fresh AI read; MasterSuggestions is
// the top-K master brands so the user can pick one directly without typing.
type RowReextractResult struct {
	ExtractedRow      ExtractedStockRegisterItem `json:"extracted_row"`
	MasterSuggestions []MasterBrandSuggestion    `json:"master_suggestions"`
	Message           string                     `json:"message,omitempty"`
}

// ReextractRow re-runs the AI on a single row of an already-processed job.
// It's the backend half of the Flutter "re-extract" button; callers pass
// the job_id (for image paths + original context) and the row they want
// re-read.
func (s *SmartStockSetupService) ReextractRow(ctx context.Context, req RowReextractRequest) (*RowReextractResult, error) {
	if req.JobID == "" {
		return nil, fmt.Errorf("job_id is required")
	}
	if req.PageNumber <= 0 || req.RowNumber <= 0 {
		return nil, fmt.Errorf("page_number and row_number must be positive")
	}
	jobUUID, err := uuid.Parse(req.JobID)
	if err != nil {
		return nil, fmt.Errorf("invalid job_id")
	}
	tenantUUID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}

	// Load the job row so we know image paths, category, and size.
	var job models.SmartStockSetupJob
	if err := s.db.
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", jobUUID, tenantUUID).
		First(&job).Error; err != nil {
		return nil, fmt.Errorf("job not found")
	}
	if req.PageNumber > len(job.ImagePaths) {
		return nil, fmt.Errorf("page_number %d exceeds available pages (%d)", req.PageNumber, len(job.ImagePaths))
	}

	imagePath := job.ImagePaths[req.PageNumber-1]
	imageBytes, err := os.ReadFile(imagePath)
	if err != nil {
		return nil, fmt.Errorf("read image: %w", err)
	}
	contentType := "image/jpeg"
	if strings.HasSuffix(strings.ToLower(imagePath), ".png") {
		contentType = "image/png"
	}

	// Resolve category name (job has CategoryID, not name).
	categoryName := ""
	if job.CategoryID != nil {
		var row struct{ Name string }
		_ = s.db.Table("categories").Select("name").
			Where("id = ? AND tenant_id = ?", job.CategoryID, tenantUUID).
			Scan(&row).Error
		categoryName = row.Name
	}

	sizeML := normalizeSizeText(job.Size)

	// Build master-brand candidate list scoped to size + state. Filter down to
	// the top ~80 using the scorer so the AI sees a focused list, not all
	// ~400 brands (which bloats the prompt and dilutes attention).
	tenantState := s.getTenantState(tenantUUID)
	allMasters := s.loadMasterBrands(sizeML, tenantState)

	// If we can extract the current row's AI guess from the job result, use
	// it to bias the master list toward label-color siblings. Otherwise pass
	// the full list (truncated in the OCR call).
	currentBrand := ""
	if job.Result != nil {
		currentBrand = extractBrandAtRow(job.Result, req.PageNumber, req.RowNumber)
	}

	// Compute band center from stored page_row_counts if caller didn't supply.
	bandCenter := req.BandCenter
	if bandCenter <= 0 {
		if job.Result != nil {
			if rc := extractPageRowCount(job.Result, req.PageNumber); rc > 0 {
				bandCenter = (float64(req.RowNumber) - 0.5) / float64(rc)
			}
		}
		if bandCenter <= 0 {
			bandCenter = 0.5
		}
	}
	if bandCenter > 0.98 {
		bandCenter = 0.98
	}
	if bandCenter < 0.02 {
		bandCenter = 0.02
	}

	// Build a focused master list — names only, sorted by scoreMasterBrand
	// against the current brand guess. If no guess, sort by MRP ascending so
	// rarer high-end brands still show up.
	candidates := s.pickMasterCandidatesForReextract(currentBrand, sizeML, allMasters, 80)
	masterNames := make([]string, 0, len(candidates))
	for _, mb := range candidates {
		masterNames = append(masterNames, mb.BrandName)
	}

	// Call the AI with the single-row prompt.
	extracted, err := s.ocr.ExtractSingleRow(ctx, imageBytes, contentType, categoryName, sizeML, masterNames, req.RowNumber, bandCenter)
	if err != nil {
		return nil, fmt.Errorf("re-extract: %w", err)
	}
	if extracted == nil {
		return nil, fmt.Errorf("re-extract returned empty result")
	}
	extracted.PageNumber = req.PageNumber
	extracted.Source = "single_row_reextract"

	// Offer top master suggestions for the user to pick from directly.
	// Strategy depends on what the AI returned:
	//   1. AI got a confident brand → use scoreMasterBrand against that brand.
	//   2. AI returned "unknown" → use RATE-BAND to find master brands with
	//      MRP in ±30% of the extracted/current rate. Way more useful than
	//      alphabetical siblings of a wrong guess, because the rate column is
	//      often still readable even when the brand handwriting isn't.
	aiBrand := strings.ToLower(strings.TrimSpace(extracted.Brand))
	isUnknown := aiBrand == "" || aiBrand == "unknown"

	var topK []MasterBrandSuggestion
	if !isUnknown {
		topK = s.findMasterBrandCandidates(extracted.Brand, sizeML, extracted.Rate, allMasters, 10)
	}
	if len(topK) == 0 {
		// Pick the rate — prefer AI's rate, fall back to current job's rate.
		rateForBand := extracted.Rate
		if rateForBand <= 0 && currentBrand != "" && job.Result != nil {
			rateForBand = extractRateAtRow(job.Result, req.PageNumber, req.RowNumber)
		}
		if rateForBand > 0 {
			topK = pickMasterByRateBand(allMasters, rateForBand, 0.30, 10)
		}
		// Last-resort fallback: score against the current (wrong) brand so the
		// user at least sees something they can browse.
		if len(topK) == 0 && currentBrand != "" {
			topK = s.findMasterBrandCandidates(currentBrand, sizeML, 0, allMasters, 10)
		}
	}

	msg := "Re-extracted with master-brand constraint. Review and pick."
	if isUnknown {
		msg = "AI couldn't confidently read this row. Suggestions below are master brands with similar rates — pick one or use Search master."
	}

	return &RowReextractResult{
		ExtractedRow:      *extracted,
		MasterSuggestions: topK,
		Message:           msg,
	}, nil
}

// pickMasterByRateBand returns master brands whose MRP is within ±bandPct of
// the target rate. Sorted by absolute MRP distance ascending so the closest-
// priced brands appear first. Used as the fallback candidate list when the
// AI-constrained re-extract returns "unknown" — rate is usually still visible
// in the register even when the brand handwriting isn't.
func pickMasterByRateBand(masters []models.MasterBrandInfo, target, bandPct float64, limit int) []MasterBrandSuggestion {
	if target <= 0 || len(masters) == 0 {
		return nil
	}
	lo := target * (1.0 - bandPct)
	hi := target * (1.0 + bandPct)
	type scored struct {
		mb   *models.MasterBrandInfo
		dist float64
	}
	var inBand []scored
	for i := range masters {
		mb := &masters[i]
		if mb.MRP < lo || mb.MRP > hi {
			continue
		}
		d := mb.MRP - target
		if d < 0 {
			d = -d
		}
		inBand = append(inBand, scored{mb: mb, dist: d})
	}
	// Simple O(n·limit) partial sort.
	if limit <= 0 || limit > len(inBand) {
		limit = len(inBand)
	}
	for i := 0; i < limit && i < len(inBand); i++ {
		best := i
		for j := i + 1; j < len(inBand); j++ {
			if inBand[j].dist < inBand[best].dist {
				best = j
			}
		}
		if best != i {
			inBand[i], inBand[best] = inBand[best], inBand[i]
		}
	}
	out := make([]MasterBrandSuggestion, 0, limit)
	for i := 0; i < limit && i < len(inBand); i++ {
		mb := inBand[i].mb
		dn := mb.DisplayName
		if dn == "" {
			dn = mb.BrandName
		}
		out = append(out, MasterBrandSuggestion{
			BrandID:               mb.BrandID,
			BrandName:             mb.BrandName,
			DisplayName:           dn,
			DisplayNameBoldStart:  mb.DisplayNameBoldStart,
			DisplayNameBoldLength: mb.DisplayNameBoldLength,
			MRP:                   mb.MRP,
			// "Confidence" here is 1 - (distance / target) capped to [0, 1].
			// Gives the picker a rough ordering signal; it's NOT a match quality
			// in the OCR sense, but tells the user which price-matches are tighter.
			Confidence: 1.0 - (inBand[i].dist / target),
		})
	}
	return out
}

// extractRateAtRow reads rate from a stored job result for a given page/row.
func extractRateAtRow(result models.SmartStockJobResult, pageNumber, rowNumber int) float64 {
	items, ok := result["items"].([]interface{})
	if !ok {
		return 0
	}
	for _, raw := range items {
		m, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		pn, _ := m["page_number"].(float64)
		rn, _ := m["row_number"].(float64)
		if int(pn) != pageNumber || int(rn) != rowNumber {
			continue
		}
		r, _ := m["rate"].(float64)
		return r
	}
	return 0
}

// pickMasterCandidatesForReextract returns a trimmed master-brand list focused
// on the most likely candidates given the current (possibly wrong) brand guess.
// Falls back to returning the first N when no guess is available.
func (s *SmartStockSetupService) pickMasterCandidatesForReextract(currentBrand string, sizeML int, masters []models.MasterBrandInfo, limit int) []models.MasterBrandInfo {
	if len(masters) == 0 {
		return nil
	}
	if limit <= 0 || limit > len(masters) {
		limit = len(masters)
	}
	if currentBrand == "" {
		if limit >= len(masters) {
			return masters
		}
		return masters[:limit]
	}

	lower := strings.ToLower(currentBrand)
	type scored struct {
		mb    *models.MasterBrandInfo
		score float64
	}
	cands := make([]scored, 0, len(masters))
	for i := range masters {
		mb := &masters[i]
		sc, _ := scoreMasterBrand(lower, mb, 0)
		cands = append(cands, scored{mb: mb, score: sc})
	}
	// Sort desc by score using a simple insertion-style partial sort (picks top-limit).
	for i := 0; i < limit && i < len(cands); i++ {
		best := i
		for j := i + 1; j < len(cands); j++ {
			if cands[j].score > cands[best].score {
				best = j
			}
		}
		if best != i {
			cands[i], cands[best] = cands[best], cands[i]
		}
	}
	out := make([]models.MasterBrandInfo, 0, limit)
	for i := 0; i < limit && i < len(cands); i++ {
		out = append(out, *cands[i].mb)
	}
	return out
}

// extractBrandAtRow walks the stored job result JSON to find the current
// brand_name for a given page+row. Returns "" if not found.
func extractBrandAtRow(result models.SmartStockJobResult, pageNumber, rowNumber int) string {
	items, ok := result["items"].([]interface{})
	if !ok {
		return ""
	}
	for _, raw := range items {
		m, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		pn, _ := m["page_number"].(float64)
		rn, _ := m["row_number"].(float64)
		if int(pn) != pageNumber || int(rn) != rowNumber {
			continue
		}
		if b, ok := m["brand_name"].(string); ok {
			return b
		}
	}
	return ""
}

// extractPageRowCount reads page_row_counts[pageNumber-1] from a stored result.
func extractPageRowCount(result models.SmartStockJobResult, pageNumber int) int {
	counts, ok := result["page_row_counts"].([]interface{})
	if !ok || pageNumber <= 0 || pageNumber > len(counts) {
		return 0
	}
	f, _ := counts[pageNumber-1].(float64)
	return int(f)
}
