package services

// v1.0.140 — Digit Training Capture (forward-capture hook)
//
// Fires async on every Smart Sale apply outcome (success / blocked-no-stock /
// apply-failed). For each applied item, locates the source register image,
// pulls the cached cv-sidecar /sheet payload, crops the (Sale, Open, Close)
// cells via the same cropCellJPEGPadded helper the live AI pipeline uses,
// writes JPEGs to disk, and inserts one digit_training_samples row per cell.
//
// Mirrors captureApplyLearning's "fire-and-forget on every outcome" shape so
// operator edits become training signal regardless of whether
// createDailySalesEntries succeeded — same alignment-with-Stock-Setup
// philosophy that v1.0.131 introduced.
//
// Behind SMART_SALE_TRAIN_CAPTURE=1; default off so this is a no-op in
// production until explicitly enabled.

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	_ "image/jpeg"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	// digitTrainingCropDir is where labeled cell crops land on disk.
	// /app/ai-training is the writable bind mount in docker-compose
	// (uploads dir is read-only-root-fs friendly via per-subdir mounts).
	digitTrainingCropDir = "/app/ai-training/digits"
)

// DigitTrainingCaptureEnabled — env-gated rollout knob.
func DigitTrainingCaptureEnabled() bool {
	return os.Getenv("SMART_SALE_TRAIN_CAPTURE") == "1"
}

// captureCellCropsForTraining is fire-and-forget; runs entirely in a goroutine,
// recover-guarded, and never affects the apply response. Safe to call on every
// apply outcome — duplicate inserts are absorbed by the table's unique index
// on (image_sha256, page_index, row_idx, col_name).
func (s *SmartSaleService) captureCellCropsForTraining(
	tenantID uuid.UUID,
	shopID uuid.UUID,
	req *SmartSaleApplyRequest,
	captureReason string,
) {
	if !DigitTrainingCaptureEnabled() {
		return
	}
	if req == nil || len(req.Items) == 0 || len(req.ImageURLs) == 0 {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				s.logger.Warnf("SmartSale: captureCellCropsForTraining panic recovered: %v (reason=%s)", r, captureReason)
			}
		}()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		// Group items by page so we read each image (and its cv_sheet_jsonb)
		// at most once.
		type pageBucket struct {
			imageURL string
			items    []SmartSaleApplyItem
		}
		buckets := make(map[int]*pageBucket, len(req.ImageURLs))
		for _, it := range req.Items {
			if it.PageNumber <= 0 || it.RowNumber <= 0 {
				continue // operator-added or pre-v1.0.140 client; can't locate
			}
			pageIdx := it.PageNumber
			if pageIdx-1 >= len(req.ImageURLs) {
				continue
			}
			b, ok := buckets[pageIdx]
			if !ok {
				b = &pageBucket{imageURL: req.ImageURLs[pageIdx-1]}
				buckets[pageIdx] = b
			}
			b.items = append(b.items, it)
		}
		if len(buckets) == 0 {
			return
		}

		var totalInserted int
		for pageIdx, b := range buckets {
			imgBytes, err := readImageBytesFromURL(b.imageURL)
			if err != nil {
				s.logger.Warnf("digit-training-capture: page=%d read image %q failed: %v", pageIdx, b.imageURL, err)
				continue
			}
			sum := sha256.Sum256(imgBytes)
			imageSHA := hex.EncodeToString(sum[:])

			// Look up the cached /sheet payload for this image.
			sheet, err := s.loadCachedSheetForImage(ctx, imageSHA, imgBytes)
			if err != nil {
				s.logger.Warnf("digit-training-capture: page=%d sheet load failed: %v", pageIdx, err)
				continue
			}
			if sheet == nil || !sheet.OK {
				continue
			}
			byRow := indexCells(sheet.Cells)

			srcImg, _, derr := image.Decode(bytes.NewReader(imgBytes))
			if derr != nil {
				s.logger.Warnf("digit-training-capture: page=%d image decode failed: %v", pageIdx, derr)
				continue
			}

			// Date-bucketed disk dir (one mkdir per page is fine).
			dateDir := filepath.Join(digitTrainingCropDir, time.Now().UTC().Format("2006/01/02"))
			if mkErr := os.MkdirAll(dateDir, 0o755); mkErr != nil {
				s.logger.Warnf("digit-training-capture: mkdir %s failed: %v", dateDir, mkErr)
				continue
			}

			for _, it := range b.items {
				cells := byRow[it.RowNumber]
				if cells == nil {
					continue
				}
				// Capture all three numeric cells per row. Truth values:
				//   sale  = it.Quantity (operator-confirmed)
				//   open/close = no per-cell ground truth on apply payload
				//                today, so we record AI's value as truth ONLY
				//                when WasCorrected=false (operator implicitly
				//                endorsed the AI read by hitting Apply with
				//                no edit). Otherwise skip those cells.
				math := cellsMathConsistent(it)
				cellsToCapture := []struct {
					col      string
					truth    string
					aiRaw    string
					aiKnown  bool
					eligible bool
				}{
					{
						col:      "sale",
						truth:    strconv.Itoa(it.Quantity),
						aiRaw:    intPtrToStr(it.OriginalAIQuantity),
						aiKnown:  it.OriginalAIQuantity != nil,
						eligible: true,
					},
					{
						col:      "open",
						truth:    intPtrToStr(it.OriginalAIOpening),
						aiRaw:    intPtrToStr(it.OriginalAIOpening),
						aiKnown:  it.OriginalAIOpening != nil,
						// Open/close eligible only when not corrected — we'd
						// otherwise be labeling cells with AI's wrong value.
						eligible: !it.WasCorrected && it.OriginalAIOpening != nil,
					},
					{
						col:      "closing",
						truth:    intPtrToStr(it.OriginalAIClosing),
						aiRaw:    intPtrToStr(it.OriginalAIClosing),
						aiKnown:  it.OriginalAIClosing != nil,
						eligible: !it.WasCorrected && it.OriginalAIClosing != nil,
					},
				}

				for _, cap := range cellsToCapture {
					if !cap.eligible {
						continue
					}
					cell, ok := cells[cap.col]
					if !ok {
						continue
					}
					crop, cerr := cropCellJPEGPadded(srcImg, cell, 0.25, 0.10)
					if cerr != nil {
						continue
					}
					cropSum := sha256.Sum256(crop)
					cropSHA := hex.EncodeToString(cropSum[:])
					cropPath := filepath.Join(dateDir,
						fmt.Sprintf("%s_p%d_r%d_%s.jpg", imageSHA[:12], pageIdx, it.RowNumber, cap.col))

					if werr := os.WriteFile(cropPath, crop, 0o644); werr != nil {
						s.logger.Warnf("digit-training-capture: write %s failed: %v", cropPath, werr)
						continue
					}

					var dsRecID, dsItemID, clientRowID *uuid.UUID
					if id, perr := uuid.Parse(it.ClientRowID); perr == nil {
						clientRowID = &id
					}
					_ = dsRecID
					_ = dsItemID

					wasCorrected := false
					if cap.col == "sale" && cap.aiKnown {
						wasCorrected = (cap.truth != cap.aiRaw)
					}

					ins := s.db.WithContext(ctx).Exec(`
						INSERT INTO digit_training_samples (
							tenant_id, shop_id, client_row_id,
							source, pipeline_version, capture_reason,
							image_sha256, image_path,
							page_index, row_idx, col_name,
							x_left, x_right, y_top, y_bot, page_w, page_h,
							crop_path, crop_sha256, crop_w, crop_h,
							ai_raw_value, truth_value, was_corrected,
							math_consistent
						) VALUES (
							?, ?, ?,
							'forward', ?, ?,
							?, ?,
							?, ?, ?,
							?, ?, ?, ?, ?, ?,
							?, ?, ?, ?,
							?, ?, ?,
							?
						) ON CONFLICT (image_sha256, page_index, row_idx, col_name) DO NOTHING
					`,
						tenantID, shopID, clientRowID,
						SheetGridPipelineVersion, captureReason,
						imageSHA, b.imageURL,
						pageIdx, it.RowNumber, cap.col,
						cell.XLeft, cell.XRight, cell.YTop, cell.YBot,
						sheet.PageSizePx[0], sheet.PageSizePx[1],
						cropPath, cropSHA, cell.XRight-cell.XLeft, cell.YBot-cell.YTop,
						cap.aiRaw, cap.truth, wasCorrected,
						math,
					)
					if ins.Error != nil {
						s.logger.Warnf("digit-training-capture: insert failed row=%d col=%s: %v", it.RowNumber, cap.col, ins.Error)
						_ = os.Remove(cropPath) // back out the file if DB insert failed
						continue
					}
					if ins.RowsAffected > 0 {
						totalInserted++
					}
				}
			}
		}
		s.logger.Infof("digit-training-capture: reason=%s pages=%d inserted=%d", captureReason, len(buckets), totalInserted)
	}()
}

// loadCachedSheetForImage returns the cv-sidecar /sheet payload for an image,
// preferring the on-disk cache. If the cache misses, calls the sidecar once
// (off the request path) and persists the result for future use.
func (s *SmartSaleService) loadCachedSheetForImage(ctx context.Context, imageSHA string, imgBytes []byte) (*SheetResponse, error) {
	var raw []byte
	row := s.db.WithContext(ctx).Raw(`
		SELECT cv_sheet_jsonb::text FROM sale_image_extraction_cache
		 WHERE image_sha256 = ? AND pipeline_version = ?
		 LIMIT 1
	`, imageSHA, SheetGridPipelineVersion).Row()
	if err := row.Scan(&raw); err == nil && len(raw) > 0 {
		var sheet SheetResponse
		if jerr := json.Unmarshal(raw, &sheet); jerr == nil {
			return &sheet, nil
		}
	}
	// Cache miss — call sidecar.
	if s.cvSidecar == nil || !s.cvSidecar.enabled {
		return nil, fmt.Errorf("cv sidecar not enabled, can't reconstruct cells")
	}
	extractor := NewSaleSheetExtractor(s.db.DB, s.logger, s.cvSidecar, s.aliasService)
	sheet, err := extractor.fetchSheetFromCV(ctx, imgBytes)
	if err != nil {
		return nil, fmt.Errorf("fetch sheet: %w", err)
	}
	// Best-effort persist for next time. We don't have the result_jsonb
	// here (no extraction was run) — write only the cv_sheet_jsonb side.
	if sheetRaw, mErr := json.Marshal(sheet); mErr == nil {
		s.db.WithContext(ctx).Exec(`
			INSERT INTO sale_image_extraction_cache (image_sha256, pipeline_version, result_jsonb, cv_sheet_jsonb)
			VALUES (?, ?, '{}'::jsonb, ?::jsonb)
			ON CONFLICT (image_sha256, pipeline_version) DO UPDATE SET cv_sheet_jsonb = EXCLUDED.cv_sheet_jsonb
		`, imageSHA, SheetGridPipelineVersion, string(sheetRaw))
	}
	return sheet, nil
}

// readImageBytesFromURL resolves a /uploads/... URL to its on-disk path
// (the sales container has /app/uploads mounted) and reads bytes. Falls
// back to HTTP fetch when the path doesn't translate cleanly.
func readImageBytesFromURL(url string) ([]byte, error) {
	if strings.HasPrefix(url, "/uploads/") {
		path := "/app" + url
		return os.ReadFile(path)
	}
	if strings.HasPrefix(url, "http://") || strings.HasPrefix(url, "https://") {
		req, _ := http.NewRequest("GET", url, nil)
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			return nil, fmt.Errorf("http %d", resp.StatusCode)
		}
		return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	}
	if strings.HasPrefix(url, "/") {
		// Already an absolute container path.
		return os.ReadFile(url)
	}
	return nil, fmt.Errorf("unsupported image url: %s", url)
}

// cellsMathConsistent returns true when the operator-confirmed Quantity plus
// the AI-read Open/Close satisfy open − sale = close ±2. False when math
// fails (operator may have confirmed an AI typo on Open or Close), nil-ish
// (we use false in that case so the training script can filter).
func cellsMathConsistent(it SmartSaleApplyItem) bool {
	if it.OriginalAIOpening == nil || it.OriginalAIClosing == nil {
		return false
	}
	expected := *it.OriginalAIOpening - it.Quantity
	delta := expected - *it.OriginalAIClosing
	if delta < 0 {
		delta = -delta
	}
	return delta <= 2
}

func intPtrToStr(p *int) string {
	if p == nil {
		return ""
	}
	return strconv.Itoa(*p)
}
