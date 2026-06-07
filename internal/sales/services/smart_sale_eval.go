package services

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ============================================================================
// Smart Sale A/B evaluation harness — WS-5.1.
//
// Replays an existing smart_sale_setup_job's images through the current OCR
// pipeline so admins can compare a fresh extraction against the originally-
// stored result without forcing the user to re-upload. Tenant-scoped.
//
// Lean by design: returns one fresh extraction (current Gemini default) and
// a row-level summary versus the job's persisted result.Items. Doesn't fan
// out across model variants — Smart Sale's OCR layer is single-backend
// today; multi-backend support can layer on later when Smart Sale gets the
// same Sonnet/Opus stack as Stock Setup.
// ============================================================================

type SaleEvalSummary struct {
	JobID            string              `json:"job_id"`
	Pipeline         string              `json:"pipeline"` // "current" (legacy Gemini-only) or "v_next" (full hardened pipeline)
	OriginalRowCount int                 `json:"original_row_count"`
	FreshRowCount    int                 `json:"fresh_row_count"`
	Recovered        int                 `json:"recovered"` // fresh - original (positive = new pipeline found more)
	CoverageSummary  []SaleCoverageEntry `json:"coverage_summary,omitempty"`
	DurationMs       int64               `json:"duration_ms"`
	OK               bool                `json:"ok"`
	Error            string              `json:"error,omitempty"`
}

type SaleEvalResult struct {
	Summary       SaleEvalSummary        `json:"summary"`
	OriginalItems interface{}            `json:"original_items,omitempty"`
	FreshItems    []ExtractedReceiptItem `json:"fresh_items,omitempty"`
}

// EvaluateJob replays a stored Smart Sale job through the OCR pipeline and
// returns a comparison summary. When pipeline="v_next" (v1.0.131), runs the
// full hardened pipeline (Claude primary + voting + recovery + page-rescue +
// handwritten-band) and surfaces CoverageSummary so the admin can see exactly
// which pages got rescued. When pipeline="current" or empty, runs the legacy
// Gemini single-pass for backwards compatibility.
//
// Caller supplies tenantID for scoping; passing tenantID=Nil errors out
// rather than letting the query bypass scope.
func (s *SmartSaleService) EvaluateJob(ctx context.Context, jobID string, tenantID uuid.UUID, pipeline string) (*SaleEvalResult, error) {
	if tenantID == uuid.Nil {
		return nil, fmt.Errorf("tenant scoping required")
	}

	var job models.SmartSaleSetupJob
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", jobID, tenantID).First(&job).Error; err != nil {
		return nil, fmt.Errorf("job not found: %w", err)
	}
	if len(job.ImagePaths) == 0 {
		return nil, fmt.Errorf("job has no image_paths")
	}

	if pipeline == "" {
		pipeline = "current"
	}
	out := &SaleEvalResult{
		Summary: SaleEvalSummary{JobID: jobID, Pipeline: pipeline},
	}
	started := time.Now()

	// Original count — the stored result blob from when the job ran. The JSONB
	// uses `extracted_items` (the v1.0.118+ schema); older blobs may have
	// `items`. Try both. v1.0.131 fix: pre-v1.0.131 only checked `items` and
	// reported original_row_count=0 on every job.
	if job.Result != nil {
		out.OriginalItems = map[string]interface{}(job.Result)
		if items, ok := job.Result["extracted_items"].([]interface{}); ok {
			out.Summary.OriginalRowCount = len(items)
		} else if items, ok := job.Result["items"].([]interface{}); ok {
			out.Summary.OriginalRowCount = len(items)
		}
	}

	// Load image bytes once
	imageData := make([][]byte, 0, len(job.ImagePaths))
	for _, p := range job.ImagePaths {
		imgBytes, err := os.ReadFile(p)
		if err != nil {
			out.Summary.Error = fmt.Sprintf("read %s: %v", p, err)
			out.Summary.DurationMs = time.Since(started).Milliseconds()
			return out, nil
		}
		imageData = append(imageData, imgBytes)
	}

	switch pipeline {
	case "sheet_grid":
		// v1.0.138 — sheet-grid pipeline. CV produces sheet-JSON, brand
		// resolved by row-index against shop's MRP-ordered inventory,
		// ONE batched Sonnet call per page reads only handwritten Sale
		// cells. Math gate + retry-once-then-warn (option C). Image-hash
		// cached: re-running pays $0.
		extractor := NewSaleSheetExtractor(s.db.DB, s.logger, s.cvSidecar, s.aliasService)
		sizeML := parseSizeToML(job.Size)
		printed, plErr := LoadShopPrintedBrandList(s.db.DB, tenantID, job.ShopID, sizeML, job.Category)
		if plErr != nil {
			out.Summary.Error = fmt.Sprintf("printed brand list: %v", plErr)
			out.Summary.DurationMs = time.Since(started).Milliseconds()
			return out, nil
		}
		s.logger.Infof("sheet-grid eval: shop=%s size=%dml printed_brands=%d", job.ShopID, sizeML, len(printed))
		freshItems := make([]ExtractedReceiptItem, 0, 64)
		var totalCost float64
		var totalCalls int
		for pi, imgBytes := range imageData {
			// v1.0.160 — pass job.ShopID so the alias-resolved-brand step uses
			// shop-scoped cascade (shop → tenant → fuzzy).
			pageRes, perr := extractor.ExtractPage(ctx, imgBytes, pi+1, printed, tenantID, job.ShopID)
			if perr != nil {
				out.Summary.Error = fmt.Sprintf("sheet_grid page %d: %v", pi+1, perr)
				out.Summary.DurationMs = time.Since(started).Milliseconds()
				return out, nil
			}
			totalCost += pageRes.CostINR
			totalCalls += pageRes.CallsMade
			for _, r := range pageRes.Rows {
				if r.SaleQty <= 0 {
					continue
				}
				ric := ExtractedReceiptItem{
					Brand:      r.BrandName,
					Quantity:   r.SaleQty,
					RowNumber:  r.RowIdx,
					PageNumber: pi + 1,
					Confidence: r.Confidence,
					// v1.0.138 — surface sheet-grid signals to Flutter:
					// • Source distinguishes verified rows from operator-attention rows.
					// • FieldConfidence["sale"] feeds the existing amber-underline UI.
					// • Warnings becomes the chip text on the review row.
					Source:   r.Source,
					Warnings: r.Warnings,
					FieldConfidence: map[string]float64{
						"sale": r.Confidence,
					},
				}
				if r.MRP > 0 {
					mrp := r.MRP
					ric.RatePerUnit = &mrp
					amt := r.MRP * float64(r.SaleQty)
					ric.Price = &amt
				}
				freshItems = append(freshItems, ric)
			}
		}
		out.Summary.OK = true
		out.Summary.FreshRowCount = len(freshItems)
		out.Summary.Recovered = out.Summary.FreshRowCount - out.Summary.OriginalRowCount
		out.Summary.DurationMs = time.Since(started).Milliseconds()
		out.FreshItems = freshItems
		s.logger.Infof("sheet-grid eval: rows=%d ai_calls=%d est_cost=₹%.2f duration=%dms",
			len(freshItems), totalCalls, totalCost, out.Summary.DurationMs)
	case "full_dry":
		// v1.0.136 Phase 4 — runs the full ProcessSmartSale pipeline
		// (extract + vote + recovery + Track F/G/E/E2 + Phase 2 + match +
		// post-filter) but does NOT persist anything. Returns the same
		// shape as v_next but with the validated/matched items, so the
		// harness can measure end-to-end accuracy not just raw extraction.
		req := &SmartSaleRequest{
			ShopID:    job.ShopID,
			Category:  job.Category,
			Size:      job.Size,
			ImageData: imageData,
			SaleDate:  job.SaleDate,
		}
		fullResult, fullErr := s.ProcessSmartSale(ctx, req, job.UserID, tenantID, "admin")
		out.Summary.DurationMs = time.Since(started).Milliseconds()
		if fullErr != nil {
			out.Summary.Error = fmt.Sprintf("full_dry pipeline: %v", fullErr)
			return out, nil
		}
		if fullResult == nil {
			out.Summary.Error = "full_dry pipeline: nil result"
			return out, nil
		}
		// Convert SmartSaleExtractedItem → ExtractedReceiptItem so the
		// /eval response shape stays consistent.
		converted := make([]ExtractedReceiptItem, 0, len(fullResult.ExtractedItems))
		for _, it := range fullResult.ExtractedItems {
			ric := ExtractedReceiptItem{
				Brand:      it.MatchedBrandName,
				Quantity:   it.Quantity,
				RowNumber:  it.RowNumber,
				PageNumber: it.PageNumber,
				Confidence: it.Confidence,
				RawText:    it.OCRText,
			}
			if ric.Brand == "" {
				ric.Brand = it.BrandName
			}
			if it.Rate > 0 {
				r := it.Rate
				ric.RatePerUnit = &r
			}
			if it.Amount > 0 {
				a := it.Amount
				ric.Price = &a
			}
			if it.OpeningStock != nil && *it.OpeningStock > 0 {
				ric.OpeningStock = it.OpeningStock
			}
			if it.ClosingStock != nil && *it.ClosingStock > 0 {
				ric.ClosingStock = it.ClosingStock
			}
			converted = append(converted, ric)
		}
		out.Summary.OK = fullResult.Status != "failed"
		out.Summary.FreshRowCount = len(converted)
		out.Summary.Recovered = out.Summary.FreshRowCount - out.Summary.OriginalRowCount
		out.FreshItems = converted
	case "v_next":
		// Build a synthetic SmartSaleRequest to drive the full pipeline.
		// We don't care about validation/matching here — the eval scope is
		// "did we extract more rows from the photo?". So we call
		// extractFromImages directly which runs vote + recovery + page-rescue.
		req := &SmartSaleRequest{
			ShopID:    job.ShopID,
			Category:  job.Category,
			Size:      job.Size,
			ImageData: imageData,
		}
		// Empty product list — Smart Sale's main pass scopes to shop products
		// for matching, but for the eval we just want raw extraction. Pass nil
		// so the AI extracts whatever it sees. (For a more apples-to-apples
		// test we could load products; left as a future enhancement.)
		var productNames []string
		freshItems, _, coverage, err := s.extractFromImages(ctx, req, productNames, tenantID)
		if err != nil {
			out.Summary.Error = fmt.Sprintf("v_next pipeline: %v", err)
			out.Summary.DurationMs = time.Since(started).Milliseconds()
			return out, nil
		}
		out.Summary.DurationMs = time.Since(started).Milliseconds()
		out.Summary.OK = true
		out.Summary.FreshRowCount = len(freshItems)
		out.Summary.CoverageSummary = coverage
		out.Summary.Recovered = out.Summary.FreshRowCount - out.Summary.OriginalRowCount
		out.FreshItems = freshItems
	default:
		// Legacy current pipeline — Gemini single-pass.
		if s.geminiService == nil {
			return nil, fmt.Errorf("Gemini OCR not configured — cannot run current pipeline eval")
		}
		freshItems := []ExtractedReceiptItem{}
		for i, imgBytes := range imageData {
			imgType := http.DetectContentType(imgBytes)
			res, err := s.geminiService.ExtractFromImage(ctx, imgBytes, imgType)
			if err != nil {
				out.Summary.Error = fmt.Sprintf("ocr image %d: %v", i+1, err)
				out.Summary.DurationMs = time.Since(started).Milliseconds()
				return out, nil
			}
			if res != nil {
				for j := range res.Items {
					if res.Items[j].PageNumber == 0 {
						res.Items[j].PageNumber = i + 1
					}
				}
				freshItems = append(freshItems, res.Items...)
			}
		}
		out.Summary.DurationMs = time.Since(started).Milliseconds()
		out.Summary.OK = true
		out.Summary.FreshRowCount = len(freshItems)
		out.Summary.Recovered = out.Summary.FreshRowCount - out.Summary.OriginalRowCount
		out.FreshItems = freshItems
	}

	return out, nil
}
