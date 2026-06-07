package services

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ============================================================================
// A/B evaluation harness — Phase 2.6.
//
// Replays an existing smart_stock_setup_job through one or more OCR backends
// and returns a row-by-row comparison so we can measure real accuracy gains
// from model changes (e.g. switching default from Gemini to Claude) without
// re-uploading the source images.
//
// Usage from the handler:
//
//	result, err := s.EvaluateJob(ctx, jobID, tenantID, []string{"claude", "gemini"})
//
// The result has `Models` keyed by model name, each carrying its per-row
// extraction. Plus `Diff` which surfaces the rows where models disagree on
// any of brand / opening / receipt / total / sale / closing / rate / amount.
// ============================================================================

// EvalRowDiff describes one row's per-model values. When all models agree on
// a field, that field's `Disagree` slice is empty. When they disagree, it
// lists model names that produced a different value.
type EvalRowDiff struct {
	RowNumber  int                 `json:"row_number"`
	PageNumber int                 `json:"page_number"`
	Brand      map[string]string   `json:"brand"`     // modelName -> value
	Opening    map[string]int      `json:"opening"`
	Receipt    map[string]int      `json:"receipt"`
	Total      map[string]int      `json:"total"`
	Sale       map[string]int      `json:"sale"`
	Closing    map[string]int      `json:"closing"`
	Rate       map[string]float64  `json:"rate"`
	Amount     map[string]float64  `json:"amount"`
	Confidence map[string]float64  `json:"confidence"`
	Disagree   map[string][]string `json:"disagree"` // field -> models
}

// EvalModelResult is one model's output for the whole job (multi-image).
type EvalModelResult struct {
	Model       string                          `json:"model"`
	OK          bool                            `json:"ok"`
	Error       string                          `json:"error,omitempty"`
	DurationMs  int64                           `json:"duration_ms"`
	RowCount    int                             `json:"row_count"`
	AvgConf     float64                         `json:"avg_confidence"`
	Items       []ExtractedStockRegisterItem    `json:"items"`
}

// EvalResult is the harness response: per-model extractions plus a row-level
// diff showing where the models disagree.
type EvalResult struct {
	JobID    string             `json:"job_id"`
	Models   []EvalModelResult  `json:"models"`
	Diff     []EvalRowDiff      `json:"diff"`
	Summary  EvalSummary        `json:"summary"`
}

type EvalSummary struct {
	TotalRows         int                `json:"total_rows"`
	UnanimousRows     int                `json:"unanimous_rows"`
	DisagreeingRows   int                `json:"disagreeing_rows"`
	PerModelMatched   map[string]int     `json:"per_model_matched_count"`
	PerModelAvgConf   map[string]float64 `json:"per_model_avg_conf"`
}

// EvaluateJob is the entry point for the eval handler. The caller passes the
// job_id, the tenant_id (scoping check), and the list of model names to run.
// Supported models: "claude", "gemini", "openai".
func (s *SmartStockSetupService) EvaluateJob(ctx context.Context, jobID string, tenantID uuid.UUID, modelNames []string) (*EvalResult, error) {
	if s.ocr == nil {
		return nil, fmt.Errorf("OCR not configured")
	}

	// Load job + verify tenant scope.
	var job models.SmartStockSetupJob
	if err := s.db.Where("id = ? AND tenant_id = ?", jobID, tenantID).First(&job).Error; err != nil {
		return nil, fmt.Errorf("job not found: %w", err)
	}
	if len(job.ImagePaths) == 0 {
		return nil, fmt.Errorf("job has no image_paths")
	}

	// Resolve category name + size for prompt context (mirrors what the live
	// extraction flow uses so the comparison is apples-to-apples).
	var categoryName string
	if job.CategoryID != nil {
		var cat struct{ Name string }
		_ = s.db.Table("categories").Select("name").
			Where("id = ? AND tenant_id = ?", *job.CategoryID, tenantID).
			Scan(&cat).Error
		categoryName = cat.Name
	}
	sizeML := normalizeSizeText(job.Size)

	// Load product names + master brand names for prompt context.
	products, err := s.purchaseService.loadProductsScoped(tenantID, &job.ShopID, nil, sizeML)
	if err != nil {
		return nil, fmt.Errorf("loadProducts failed: %w", err)
	}
	productNames := make([]string, 0, len(products))
	for _, p := range products {
		productNames = append(productNames, p.Name)
	}
	masterBrands := s.loadMasterBrands(sizeML, s.getTenantState(tenantID))
	masterNames := make([]string, 0, len(masterBrands))
	for _, m := range masterBrands {
		masterNames = append(masterNames, m.BrandName)
	}

	out := &EvalResult{
		JobID:  jobID,
		Models: make([]EvalModelResult, 0, len(modelNames)),
	}
	out.Summary.PerModelMatched = map[string]int{}
	out.Summary.PerModelAvgConf = map[string]float64{}

	// Run each model across all images, accumulating rows like the production
	// pipeline does. We deliberately skip the post-processing matcher — the
	// goal is to compare RAW extraction quality, not the matcher's downstream
	// behavior (which is identical for all models).
	for _, mn := range modelNames {
		mn = strings.ToLower(strings.TrimSpace(mn))
		modelResult := EvalModelResult{Model: mn}
		started := time.Now()

		var allItems []ExtractedStockRegisterItem
		var firstErr error
		for _, p := range job.ImagePaths {
			imgBytes, err := os.ReadFile(p)
			if err != nil {
				firstErr = fmt.Errorf("read %s: %w", p, err)
				break
			}
			contentType := http.DetectContentType(imgBytes)

			var res *StockRegisterExtractionResult
			var callErr error
			switch mn {
			case "claude":
				res, callErr = s.ocr.extractRegisterWithClaude(ctx, imgBytes, contentType, categoryName, sizeML, productNames, masterNames)
			case "gemini":
				res, callErr = s.ocr.extractRegisterWithGemini(ctx, imgBytes, contentType, categoryName, sizeML, productNames, masterNames)
			case "openai":
				res, callErr = s.ocr.extractRegisterWithOpenAI(ctx, imgBytes, contentType, categoryName, sizeML, productNames, masterNames)
			default:
				firstErr = fmt.Errorf("unknown model %q (supported: claude, gemini, openai)", mn)
			}
			if firstErr != nil {
				break
			}
			if callErr != nil {
				firstErr = callErr
				break
			}
			if res != nil {
				for i := range res.Items {
					if res.Items[i].PageNumber == 0 {
						res.Items[i].PageNumber = len(allItems) + 1
					}
				}
				allItems = append(allItems, res.Items...)
			}
		}
		modelResult.DurationMs = time.Since(started).Milliseconds()
		if firstErr != nil {
			modelResult.OK = false
			modelResult.Error = firstErr.Error()
			log.Printf("Smart Stock Setup eval: model %s failed: %v", mn, firstErr)
		} else {
			modelResult.OK = true
			modelResult.Items = allItems
			modelResult.RowCount = len(allItems)
			if len(allItems) > 0 {
				var sum float64
				for _, it := range allItems {
					sum += it.Confidence
				}
				modelResult.AvgConf = sum / float64(len(allItems))
			}
			out.Summary.PerModelMatched[mn] = len(allItems)
			out.Summary.PerModelAvgConf[mn] = modelResult.AvgConf
		}
		out.Models = append(out.Models, modelResult)
	}

	// Build diff. Index each model's rows by (row_number, page_number) and
	// align across models so we can compare cell-by-cell.
	type rowKey struct {
		row, page int
	}
	allKeys := map[rowKey]struct{}{}
	for _, m := range out.Models {
		for _, it := range m.Items {
			allKeys[rowKey{it.RowNumber, it.PageNumber}] = struct{}{}
		}
	}
	for k := range allKeys {
		diff := EvalRowDiff{
			RowNumber:  k.row,
			PageNumber: k.page,
			Brand:      map[string]string{},
			Opening:    map[string]int{},
			Receipt:    map[string]int{},
			Total:      map[string]int{},
			Sale:       map[string]int{},
			Closing:    map[string]int{},
			Rate:       map[string]float64{},
			Amount:     map[string]float64{},
			Confidence: map[string]float64{},
			Disagree:   map[string][]string{},
		}
		for _, m := range out.Models {
			for _, it := range m.Items {
				if it.RowNumber == k.row && it.PageNumber == k.page {
					diff.Brand[m.Model] = it.Brand
					diff.Opening[m.Model] = it.Opening
					diff.Receipt[m.Model] = it.Receipt
					diff.Total[m.Model] = it.Total
					diff.Sale[m.Model] = it.Sale
					diff.Closing[m.Model] = it.Closing
					diff.Rate[m.Model] = it.Rate
					diff.Amount[m.Model] = it.Amount
					diff.Confidence[m.Model] = it.Confidence
					break
				}
			}
		}
		// Compute disagreement per field.
		if hasMultipleDistinctStrings(diff.Brand) {
			diff.Disagree["brand"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctInts(diff.Opening) {
			diff.Disagree["opening"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctInts(diff.Receipt) {
			diff.Disagree["receipt"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctInts(diff.Total) {
			diff.Disagree["total"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctInts(diff.Sale) {
			diff.Disagree["sale"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctInts(diff.Closing) {
			diff.Disagree["closing"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctFloats(diff.Rate) {
			diff.Disagree["rate"] = mapKeys(diff.Brand)
		}
		if hasMultipleDistinctFloats(diff.Amount) {
			diff.Disagree["amount"] = mapKeys(diff.Brand)
		}
		out.Diff = append(out.Diff, diff)
	}
	out.Summary.TotalRows = len(out.Diff)
	for _, d := range out.Diff {
		if len(d.Disagree) == 0 {
			out.Summary.UnanimousRows++
		} else {
			out.Summary.DisagreeingRows++
		}
	}
	return out, nil
}

func hasMultipleDistinctStrings(m map[string]string) bool {
	if len(m) < 2 {
		return false
	}
	var first string
	first_set := false
	for _, v := range m {
		if !first_set {
			first = v
			first_set = true
			continue
		}
		if v != first {
			return true
		}
	}
	return false
}

func hasMultipleDistinctInts(m map[string]int) bool {
	if len(m) < 2 {
		return false
	}
	var first int
	first_set := false
	for _, v := range m {
		if !first_set {
			first = v
			first_set = true
			continue
		}
		if v != first {
			return true
		}
	}
	return false
}

func hasMultipleDistinctFloats(m map[string]float64) bool {
	if len(m) < 2 {
		return false
	}
	var first float64
	first_set := false
	for _, v := range m {
		if !first_set {
			first = v
			first_set = true
			continue
		}
		d := v - first
		if d < 0 {
			d = -d
		}
		if d > 0.01 {
			return true
		}
	}
	return false
}

func mapKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
