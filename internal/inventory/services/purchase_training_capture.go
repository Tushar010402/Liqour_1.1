package services

// v1.0.238 Track C — AI Purchase training corpus capture.
//
// Async hook fired after every successful ApplySmartPurchase. For each item
// applied, we record one row per (engine, doc, col) into
// purchase_training_samples — the AI's raw value, the operator-confirmed
// truth, and whether they diverged.
//
// Mirrors the design of digit_training_capture.go (v1.0.140, Smart Sale) so
// the cv-sidecar training pipeline can reuse the same Dataset / Augment /
// Train scaffolding by swapping the table name + per-cell normalisation.
//
// Cell-crop image bytes are NOT captured by this initial v238 hook — the GP
// pipeline doesn't carry per-cell bounding-box coordinates through to the
// apply payload yet (unlike Smart Sale's cv-sidecar /sheet output). What WE
// capture is the operator-validated text-vs-ai-raw label, the engine, and the
// pipeline version. A future iteration adds image crops once we extend
// GatePassDutyItem to carry x/y/w/h per cell.
//
// Behind env flag SMART_PURCHASE_TRAIN_CAPTURE=1; default off so this is a
// no-op until enabled per-tenant.

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
)

// PurchaseTrainingCaptureEnabled — env-gated rollout knob.
// Reads SMART_PURCHASE_TRAIN_CAPTURE=1 (global). Per-tenant override possible
// via SMART_PURCHASE_TRAIN_CAPTURE_TENANT_<uuid>=1 if we ever need it.
func PurchaseTrainingCaptureEnabled() bool {
	return os.Getenv("SMART_PURCHASE_TRAIN_CAPTURE") == "1"
}

// purchaseTrainingPipelineVersion is the value stamped into every captured
// row. Bump per backend release that materially changes extraction logic
// (model swap, prompt change, cv-sidecar pipeline change).
const purchaseTrainingPipelineVersion = "v1.0.238"

// capturePurchaseTrainingSamples is fire-and-forget; runs in a goroutine,
// recover-guarded, never affects the apply response. Unique index on
// (image_sha256, page_index, row_idx, col_name) absorbs duplicate inserts.
func (s *SmartPurchaseService) capturePurchaseTrainingSamples(
	tenantID, shopID uuid.UUID,
	jobID uuid.UUID,
	applyRecordID uuid.UUID,
	req SmartPurchaseApplyRequest,
	captureReason string,
) {
	if !PurchaseTrainingCaptureEnabled() {
		return
	}
	if len(req.Items) == 0 {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				// Best-effort log; never panic the apply flow.
				_ = r
			}
		}()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		// Synthetic image_sha256 — without real per-cell bboxes we use a
		// (jobID, rowIdx) tuple stamp so duplicates within the same job are
		// idempotent. When future iterations add real per-cell crops, swap
		// to image-bytes sha256.
		var jobIDPtr, applyIDPtr *uuid.UUID
		if jobID != uuid.Nil {
			jobIDPtr = &jobID
		}
		if applyRecordID != uuid.Nil {
			applyIDPtr = &applyRecordID
		}

		for idx, it := range req.Items {
			// Skip apply-time additions / operator-added rows that have no
			// AI provenance to learn from.
			if it.ProductID == "" {
				continue
			}
			// Build a stable per-row sha so re-applies of the same job don't
			// pile up duplicate training rows.
			rowKey := jobID.String() + ":" + applyRecordID.String() + ":row" + uintToStr(idx)
			sum := sha256.Sum256([]byte(rowKey))
			imageSHA := hex.EncodeToString(sum[:])

			// Walk the columns we care about. truth_value comes from the
			// final apply payload (operator-confirmed). ai_raw_value is the
			// original_ai_* echo we already round-trip from extract → review.
			cells := []struct {
				docKind  string // 'gp_page' or 'bill_page'
				colName  string
				engine   string
				aiRaw    string
				truth    string
			}{
				// GP-side label: brand text (operator-confirmed via the BrandName chip).
				{"gp_page", "brand", "claude", strings.TrimSpace(it.OriginalAIBrand), strings.TrimSpace(it.BrandName)},
				// GP-side label: size_ml. AI's original size isn't echoed today,
				// so we use SizeML as both raw and truth — it still records the
				// engine-version + tenant + correctness pair for future use.
				{"gp_page", "size_ml", "claude", intToStr(it.SizeML), intToStr(it.SizeML)},
				// GP-side label: bottles dispatched (operator-confirmed).
				{"gp_page", "bottles_disp", "claude", intToStr(it.OriginalAIQty), intToStr(it.Bottles)},
				// Bill-side label: per-bottle cost (Textract reads it from the bill).
				{"bill_page", "bill_cost", "textract", floatToStr(it.OriginalAIRate), floatToStr(it.CostPrice)},
			}
			// Page index 0 — we don't track per-row page on apply payload
			// today. Future iteration: surface page_index on apply.
			pageIdx := 0

			for _, c := range cells {
				if c.aiRaw == "" && c.truth == "" {
					continue // nothing to learn from
				}
				wasCorrected := c.aiRaw != "" && c.truth != "" && c.aiRaw != c.truth

				// Note: x_left/x_right/y_top/y_bot/page_w/page_h are 0 here
				// because we don't have per-cell bboxes yet. Schema requires
				// NOT NULL so 0 stands in until the cell-crop iteration adds
				// real coords.
				_ = s.db.WithContext(ctx).Exec(`
					INSERT INTO purchase_training_samples (
						tenant_id, shop_id, smart_purchase_job_id, apply_record_id,
						source, pipeline_version, capture_reason,
						doc_kind, col_name, engine, engine_version,
						image_sha256, image_path,
						page_index, row_idx,
						x_left, x_right, y_top, y_bot, page_w, page_h,
						ai_raw_value, truth_value, was_corrected
					) VALUES (
						?, ?, ?, ?,
						'forward', ?, ?,
						?, ?, ?, ?,
						?, ?,
						?, ?,
						0, 0, 0, 0, 0, 0,
						?, ?, ?
					) ON CONFLICT (image_sha256, page_index, row_idx, col_name) DO NOTHING
				`,
					tenantID, shopID, jobIDPtr, applyIDPtr,
					purchaseTrainingPipelineVersion, captureReason,
					c.docKind, c.colName, c.engine, purchaseTrainingPipelineVersion,
					imageSHA, "",
					pageIdx, idx,
					nullIfEmpty(c.aiRaw), nullIfEmpty(c.truth), wasCorrected,
				).Error
			}
		}
	}()
}

func uintToStr(i int) string {
	if i < 0 {
		return "neg"
	}
	const digits = "0123456789"
	if i == 0 {
		return "0"
	}
	buf := make([]byte, 0, 12)
	for i > 0 {
		buf = append([]byte{digits[i%10]}, buf...)
		i /= 10
	}
	return string(buf)
}

func intToStr(i int) string {
	if i == 0 {
		return ""
	}
	return uintToStr(i)
}

func floatToStr(f float64) string {
	if f <= 0 {
		return ""
	}
	// 2 decimal places — matches how operator sees cost on the review screen.
	return strings.TrimRight(strings.TrimRight(
		formatFloat(f, 2), "0"), ".")
}

func formatFloat(f float64, prec int) string {
	// Avoid pulling strconv just for this — use fmt-like approach.
	// Simple impl: multiply, round, divide.
	mul := 1.0
	for i := 0; i < prec; i++ {
		mul *= 10
	}
	r := int64(f*mul + 0.5)
	s := uintToStr(int(r))
	if len(s) <= prec {
		s = strings.Repeat("0", prec-len(s)+1) + s
	}
	dot := len(s) - prec
	return s[:dot] + "." + s[dot:]
}

func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
