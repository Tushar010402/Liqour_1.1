package services

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	_ "image/jpeg"
	"image/jpeg"
	_ "image/png"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
)

// Local aliases for the alias-source enum so the pre-matcher reads cleanly.
var (
	aliasShopExact   = alias.AliasSourceShopExact
	aliasTenantExact = alias.AliasSourceTenantExact
)

// textractPipelineEnabledForTenant returns true when the v1.0.165 row-locked
// Textract Tables pipeline should run for this tenant. Order:
//   - SMART_SALE_PIPELINE=textract → all tenants
//   - SMART_SALE_PIPELINE_TENANT_<uuid>=textract → only that tenant
//   - otherwise → fall through to existing sheet-grid / legacy path
func textractPipelineEnabledForTenant(tenantID uuid.UUID) bool {
	if strings.EqualFold(strings.TrimSpace(os.Getenv("SMART_SALE_PIPELINE")), "textract") {
		return true
	}
	per := os.Getenv("SMART_SALE_PIPELINE_TENANT_" + tenantID.String())
	return strings.EqualFold(strings.TrimSpace(per), "textract")
}

// textractMinRowsForSize returns the minimum Textract row count required to
// accept its output (vs falling through to sheet-grid / legacy). The default
// 5 is conservative for full-inventory pages, but 90 ml registers list only
// 3 SKUs by physical layout — that floor will never clear, forcing every
// 90 ml job into the slow legacy path. Per-size override fixes that without
// weakening the global default.
//
// Env: SMART_SALE_TEXTRACT_MIN_ROWS_BY_SIZE = "size:rows[,size:rows...]"
// Example: "90:1,180:5,375:5,750:3"
//
// Size matching: case-insensitive, ignores whitespace, parses the leading
// integer of the size string (so "90ml (Nip)" / "90 ML" / "90ml" all match
// key "90"). Falls back to 5 when env unset / unparseable / size unmatched.
func textractMinRowsForSize(sizeRaw string) int {
	const defaultFloor = 5
	envVal := strings.TrimSpace(os.Getenv("SMART_SALE_TEXTRACT_MIN_ROWS_BY_SIZE"))
	if envVal == "" {
		return defaultFloor
	}
	target := parseLeadingInt(sizeRaw)
	if target <= 0 {
		return defaultFloor
	}
	for _, pair := range strings.Split(envVal, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		parts := strings.SplitN(pair, ":", 2)
		if len(parts) != 2 {
			continue
		}
		k, err1 := strconv.Atoi(strings.TrimSpace(parts[0]))
		v, err2 := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err1 != nil || err2 != nil || v < 1 {
			continue
		}
		if k == target {
			return v
		}
	}
	return defaultFloor
}

// parseLeadingInt pulls the first run of digits out of s.
// "90ml (Nip)" → 90 ; "180ML Quarter" → 180 ; "" → 0.
func parseLeadingInt(s string) int {
	digits := strings.Builder{}
	for _, r := range s {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
			continue
		}
		if digits.Len() > 0 {
			break
		}
	}
	if digits.Len() == 0 {
		return 0
	}
	n, err := strconv.Atoi(digits.String())
	if err != nil {
		return 0
	}
	return n
}

// awsTextractClient lazily constructs a single Textract client per process.
var (
	cachedTextractClient *textract.Client
)

func newTextractClient(ctx context.Context) (*textract.Client, error) {
	if cachedTextractClient != nil {
		return cachedTextractClient, nil
	}
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "ap-south-1"
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("textract: load aws config: %w", err)
	}
	cachedTextractClient = textract.NewFromConfig(cfg)
	return cachedTextractClient, nil
}

// chhotu's daily-sale registers have these 9 columns in this fixed order.
// Textract returns ColumnIndex 1-based. The exact mapping below is what
// converts a Textract CELL's text into the right ExtractedReceiptItem field.
const (
	colSerialNo = 1
	colBrand    = 2
	colOpening  = 3
	colReceipt  = 4
	colTotal    = 5
	colSale     = 6
	colRate     = 7
	colAmount   = 8
	colClosing  = 9
)

// extractWithTextract runs Textract AnalyzeDocument over each image of the
// request and returns a flat list of items with row+page provenance. Caller
// merges this output with the matcher / aliasing path identical to legacy.
//
// v1.0.167 — accepts tenantID/shopID so the post-extraction alias-cascade
// pre-matcher can route raw OCR text through the 398 learned aliases before
// the existing matcher runs. That's the difference between "M.M" being
// flagged Product-not-found and being recognized as M2 Magic Moments Jamun
// Spicymint via the alias loop.
func (s *SmartSaleService) extractWithTextract(
	ctx context.Context,
	req *SmartSaleRequest,
	tenantID, shopID uuid.UUID,
) ([]ExtractedReceiptItem, *ReceiptExtractionResult, error) {

	client, err := newTextractClient(ctx)
	if err != nil {
		return nil, nil, err
	}

	startedAt := time.Now()
	out := make([]ExtractedReceiptItem, 0, 64)
	totalRowSeen := 0
	repairedRows := 0
	// v1.0.306 — per-page pre-filter stats captured here, surfaced to the
	// caller via ReceiptExtractionResult.PerPageStats so the per-page rescue
	// loop in smart_sale_service.go can detect a collapsed page (raw count
	// far below sibling pages) and rerun ONLY that image through Gemini
	// before the qty=0 filter strips its evidence.
	perPageStats := make([]ExtractionPageStats, 0, len(req.ImageData))
	for pageIdx, raw := range req.ImageData {
		if len(raw) == 0 {
			// Record a zero-stat for absent images so caller can detect
			// "I sent N images and Textract returned data for fewer".
			perPageStats = append(perPageStats, ExtractionPageStats{PageNumber: pageIdx + 1})
			continue
		}
		page, layout, perr := s.runTextractPageWithLayout(ctx, client, raw, pageIdx+1)
		if perr != nil {
			s.logger.Warnf("SmartSale textract: page %d failed: %v — skipping page", pageIdx+1, perr)
			perPageStats = append(perPageStats, ExtractionPageStats{PageNumber: pageIdx + 1})
			continue
		}
		if len(page) == 0 {
			s.logger.Warnf("SmartSale textract: page %d produced 0 rows", pageIdx+1)
			perPageStats = append(perPageStats, ExtractionPageStats{PageNumber: pageIdx + 1})
			continue
		}
		s.logger.Infof("SmartSale textract: page %d → %d rows", pageIdx+1, len(page))

		// Per-page raw stats — captured BEFORE the global qty=0 filter so
		// the caller sees the real Textract output. SuspiciousBrandCount
		// catches column-slip artifacts (brand cell reading the Opening
		// column → all-digit brand text like "141", "108"). LayoutDetected
		// (v1.0.316) lets the rescue gate trust pages where Textract's
		// header_detect succeeded — without it, even clean pages with one
		// stray short brand keep triggering the (~30s per page) Claude
		// rescue on chhotu's images.
		pageStat := ExtractionPageStats{
			PageNumber:     pageIdx + 1,
			RawRowCount:    len(page),
			LayoutDetected: layout.Detected,
		}
		for _, it := range page {
			if it.RowNumber > pageStat.MaxRowNumber {
				pageStat.MaxRowNumber = it.RowNumber
			}
			if isSuspiciousBrandText(it.Brand) {
				pageStat.SuspiciousBrandCount++
			}
		}
		perPageStats = append(perPageStats, pageStat)

		// v1.0.183 Track C5 — silently apply digit corrections that this
		// shop's operator has already confirmed N+ times via the C2
		// doubt-popup queue. Runs BEFORE the math-gate so subsequent
		// arithmetic sees the corrected values. "Ask once, learn forever":
		// after threshold, the same digit confusion never goes to the popup
		// again. Threshold env: SMART_SALE_AUTO_FIX_THRESHOLD (default 3).
		if confirmedDigitAutoFixEnabled() {
			thresh := confirmedDigitAutoFixThreshold()
			confirmed := LoadConfirmedDigitCorrections(s.db.DB, tenantID, shopID, thresh)
			autoFixed := 0
			for i := range page {
				autoFixed += applyConfirmedDigitCorrections(&page[i], confirmed)
			}
			if autoFixed > 0 {
				s.logger.Infof("SmartSale textract auto-fix: page %d applied %d confirmed digit corrections (threshold>=%d)", pageIdx+1, autoFixed, thresh)
			}
		}

		// v1.0.166/167 — math-gate qty correction. For each row, compute
		// up to 3 independent estimates of the Sale qty:
		//   S2 = open + recv − close   (full stock identity)
		//   S3 = amount ÷ rate         (revenue identity)
		//   S4 = open − close          (no-receipt identity)
		// If any TWO of them agree within ±1 AND that consensus disagrees
		// with Textract's Sale-cell read, replace Sale with the consensus.
		// Pure arithmetic, no model call. v1.0.166 only fired when S2==S3
		// (3-of-3 corroboration); v1.0.167 D2 broadens to 2-of-3 to catch
		// the rows where one of the three cells was unreadable.
		mathFixed := 0
		mathSkipBadConf := 0
		for i := range page {
			row := &page[i]
			open := -1
			if row.OpeningStock != nil {
				open = *row.OpeningStock
			}
			close_ := -1
			if row.ClosingStock != nil {
				close_ = *row.ClosingStock
			}
			recv := 0
			recvHas := false
			if row.Receipt != nil {
				recv = *row.Receipt
				recvHas = true
			}
			rate := 0.0
			if row.RatePerUnit != nil {
				rate = *row.RatePerUnit
			}
			amount := 0.0
			if row.Price != nil {
				amount = *row.Price
			}

			// Per-cell confidence floor — don't trust a "corroboration" if
			// the underlying cell is itself low-conf. Picked 0.7 since math-
			// gate already self-validates via consensus.
			cellOK := func(k string) bool {
				if row.FieldConfidence == nil {
					return true
				}
				c, ok := row.FieldConfidence[k]
				return !ok || c >= 0.70
			}

			candidates := []int{}
			if open >= 0 && close_ >= 0 && recvHas && cellOK("opening") && cellOK("closing") && cellOK("receipt") {
				v := open + recv - close_
				if v >= 0 && v <= 200 {
					candidates = append(candidates, v)
				}
			}
			if rate >= 50 && rate <= 2000 && amount > 0 && cellOK("rate") && cellOK("amount") {
				v := int((amount / rate) + 0.5)
				if v >= 0 && v <= 200 {
					candidates = append(candidates, v)
				}
			}
			if open >= 0 && close_ >= 0 && (!recvHas || recv == 0) && cellOK("opening") && cellOK("closing") {
				v := open - close_
				if v >= 0 && v <= 200 {
					candidates = append(candidates, v)
				}
			}
			if len(candidates) < 2 {
				// v1.0.324 — tightened Fix #8 (was v1.0.323 single-corroborator):
				// the original gate fired on any single corroborator + AI=0,
				// but the 2026-05-24 sweep showed it added 87 fresh rows with
				// only 2 paired with truth (+75 ghost rows, net -0.7% qty
				// accuracy). Tightening now:
				//
				//   - Brand cell MUST be non-empty (≥3 chars) — avoid converting
				//     AI=0 on rows where the brand is also unreadable; those
				//     rows tend to have garbage matching downstream
				//   - Open AND close BOTH > 0 (not just one) — strongest filter
				//     for legit transaction rows
				//   - Open > close (sale > 0 implied — won't fire on no-sale rows)
				//   - Sole corroborator value in plausible range [1, 60]
				//     (real per-row sale qty caps around 60 on chhotu's busy days)
				if len(candidates) == 1 && row.Quantity == 0 && candidates[0] > 0 && candidates[0] <= 60 {
					brandLen := len(strings.TrimSpace(row.Brand))
					strongRow := brandLen >= 3 && open > 0 && close_ > 0 && open > close_
					if strongRow {
						s.logger.Infof("SmartSale textract math-gate v1.0.324: page %d row %d Sale 0 → %d (single-corroborator + brand=%q open=%d close=%d)",
							pageIdx+1, row.RowNumber, candidates[0], row.Brand, open, close_)
						row.Quantity = candidates[0]
						if row.FieldConfidence == nil {
							row.FieldConfidence = map[string]float64{}
						}
						row.FieldConfidence["sale"] = 0.85
						row.FieldConfidence["quantity"] = 0.85
						mathFixed++
						continue
					}
				}
				if len(candidates) == 1 && row.FieldConfidence != nil {
					if c, ok := row.FieldConfidence["sale"]; ok && c < 0.70 {
						mathSkipBadConf++
					}
				}
				continue
			}
			// Find a value that ≥2 candidates agree on within ±1.
			consensus := -1
			for a := 0; a < len(candidates); a++ {
				agree := 1
				for b := 0; b < len(candidates); b++ {
					if a == b {
						continue
					}
					if absInt(candidates[a]-candidates[b]) <= 1 {
						agree++
					}
				}
				if agree >= 2 {
					consensus = candidates[a]
					break
				}
			}
			if consensus < 0 || row.Quantity == consensus {
				continue
			}
			s.logger.Infof("SmartSale textract math-gate: page %d row %d Sale %d → %d (2-of-%d corroborators=%v)",
				pageIdx+1, row.RowNumber, row.Quantity, consensus, len(candidates), candidates)
			row.Quantity = consensus
			if row.FieldConfidence == nil {
				row.FieldConfidence = map[string]float64{}
			}
			row.FieldConfidence["sale"] = 0.97
			row.FieldConfidence["quantity"] = 0.97
			mathFixed++
		}
		if mathFixed > 0 {
			s.logger.Infof("SmartSale textract math-gate: page %d corrected %d Sale cells via row arithmetic (2-of-3 consensus)", pageIdx+1, mathFixed)
		}
		_ = mathSkipBadConf

		// v1.0.183 Track C1 — invariant gate. Encodes chhotu's domain rules
		// for a sales register. Auto-fixes when the rule + arithmetic gives a
		// confident answer; otherwise tags a CellDoubt for the C2 popup queue
		// so the operator confirms or corrects ONCE, then it's captured for
		// every future extraction.
		//
		// effective_opening (the available stock for the day, accounting for
		// purchases) is the Total cell when present and >= Opening, else
		// Opening + Receipt, else just Opening.
		if invariantGateEnabled() {
			gateFixed, gateDoubts := 0, 0
			for i := range page {
				row := &page[i]
				doubts := evaluateRowInvariants(row)
				for _, d := range doubts {
					if d.AutoFixed {
						gateFixed++
					} else {
						gateDoubts++
					}
				}
				if len(doubts) > 0 {
					row.CellDoubts = append(row.CellDoubts, doubts...)
				}
			}
			if gateFixed > 0 || gateDoubts > 0 {
				s.logger.Infof("SmartSale invariant-gate: page %d auto_fixed=%d open_doubts=%d", pageIdx+1, gateFixed, gateDoubts)
			}
		}

		// v1.0.167 D1 — pre-matcher alias-cascade lookup. The matcher's
		// first-pass jaccard against the catalog misses every short / abbreviated
		// brand string ("M.M" → M2 Magic Moments, "Iconiq" → ICONIQ WHITE
		// DELUXE INTERNATIONAL, "Royal Green Whisky" → Royal Green Reserve
		// Blended Whisky) because the token sets don't overlap enough.
		// LookupAliasCascade hits the 398 learned aliases (shop-scoped first,
		// tenant-wide fallback, fuzzy as last resort), and when it finds a
		// match we set MatchedBrandName so the downstream matcher's tier-1
		// alias check resolves immediately. OriginalAIBrand preserves the raw
		// OCR text so captureApplyLearning can write the correct alias if the
		// operator confirms or corrects.
		if s.aliasService != nil {
			aliasHits := 0
			exactHits := 0
			for i := range page {
				row := &page[i]
				ocrText := strings.TrimSpace(row.Brand)
				if ocrText == "" || row.PageNumber != pageIdx+1 {
					continue
				}
				pid, canonical, src, ok := s.aliasService.LookupAliasCascade(ctx, tenantID, shopID, ocrText, req.Size)
				if !ok || pid == nil {
					continue
				}
				if row.RawText == "" {
					row.RawText = ocrText
				}
				row.Brand = canonical
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				row.FieldConfidence["brand"] = 0.99
				// v1.0.168 — set ProductID hint so downstream matcher skips
				// its own loop entirely and uses this product. Honored ONLY
				// for exact-source matches; fuzzy still goes through the
				// matcher (with v1.0.168 pollution-guard bypass on its own
				// exact-source check).
				if src == aliasShopExact || src == aliasTenantExact {
					row.MatchedProductIDHint = pid.String()
					row.MatchedProductIDHintSource = string(src)
					exactHits++
				}
				aliasHits++
			}
			if aliasHits > 0 {
				s.logger.Infof("SmartSale textract alias-cascade: page %d resolved %d brands via 398-alias loop (%d exact-source hints set)", pageIdx+1, aliasHits, exactHits)
			}
		}

		// v1.0.166 — Track F repair on Textract output. Fetch CV /detect-grid
		// to populate ctx with row Y-bands, then call repairLowConfQtyCells:
		// for any row where Textract's Sale-cell confidence is below the field
		// floor (default 0.85), Sonnet re-reads ONLY that cell using a tight
		// row-strip crop and replaces the digit when the open−close
		// corroboration matches. Fixes the "100 STROKES ROYAL=102" class where
		// Textract slipped on a smudged digit but the row arithmetic still
		// resolves cleanly. No-op if CV grid detection fails or the cv sidecar
		// is unreachable; falls back to raw Textract output.
		imgCtx := ctx
		// v1.0.166 — Track F disabled by default on textract path. Pure math-
		// gate above already covers the cells where row arithmetic is sound;
		// Track F (Sonnet cell-repair) consistently returned conf<0.92 on
		// chhotu's handwritten cells (8 calls per page → 0 replacements → +24s
		// latency for nothing). Re-enable with SMART_SALE_TEXTRACT_TRACK_F=1
		// once we tune the cell-level floor or swap to a different model.
		_ = imgCtx
		if false && s.cvSidecar != nil && s.claudeService != nil && saleCellLevelEnabled() {
			cvGrid := s.cvSidecar.DetectGrid(ctx, raw)
			if cvGrid != nil && len(cvGrid.Rows) > 0 {
				imgCtx = context.WithValue(imgCtx, SaleCVRowsCtxKey, cvGrid.Rows)
				if cvGrid.Columns.Ok {
					cols := cvGrid.Columns
					imgCtx = context.WithValue(imgCtx, SaleCVColsCtxKey, &cols)
				}
				// Re-anchor Textract RowNumber to CV row indexing so
				// repairLowConfQtyCells finds the right Y-bounds. Textract
				// rows are sequential 1..N already; map them to the CV
				// non-blank rows in order.
				nonBlankIdx := 0
				cvRowMap := []int{}
				for _, r := range cvGrid.Rows {
					if !r.IsBlank {
						cvRowMap = append(cvRowMap, nonBlankIdx)
					}
					nonBlankIdx++
				}
				for i := range page {
					if i < len(cvRowMap) {
						page[i].RowNumber = cvRowMap[i] + 1
					}
				}
				items2, st := s.claudeService.repairLowConfQtyCells(imgCtx, raw, page, pageIdx+1, false)
				if st.Called > 0 {
					page = items2
					repairedRows += st.Replaced
					s.logger.Infof("SmartSale textract Track-F: page %d candidates=%d called=%d replaced=%d",
						pageIdx+1, st.Candidates, st.Called, st.Replaced)
				}
			}
		}

		totalRowSeen += len(page)
		out = append(out, page...)
	}
	if repairedRows > 0 {
		s.logger.Infof("SmartSale textract: Track F repaired %d cell digits across all pages", repairedRows)
	}

	// v1.0.171 — Sale-qty filter. Tomar = sales register; only rows where the
	// operator actually wrote a sale qty are real sales. Rows with qty=0 are
	// the shop's printed brand list (no sale that day). Filtering them BEFORE
	// matching halves the matcher's noise floor and removes the "Black Dog
	// Centenary qty=0 → matched as Black Dog Centenary" rows that confused
	// the operator review screen on chhotu's records. Setup-rescue rows (Source
	// = "setup_rescue") legitimately ship with qty=0 + needs_review chip and
	// are added LATER in validateExtractedData; this filter only drops the
	// raw-extraction zeros.
	//
	// v1.0.312 — narrow the drop. The unconditional qty=0 drop was hiding 12
	// of 30 rows on chhotu's 180 ml page 1 (the operator only fills Sale for
	// items that moved that day; everything else has opening + brand + closing
	// but no sale). Those rows are inventory state, not noise — they let the
	// operator visually confirm closing stock on the review screen and feed the
	// downstream preserveZero handler in smart_sale_service.go (default ON
	// since v1.0.151) which annotates them IsZeroQuantity=true and the apply-
	// time filter still drops them at submit so no phantom sale rows appear.
	// Only TRULY EMPTY rows (no opening, no closing, no amount) are dropped
	// here — those are the layout-noise the v1.0.171 filter was actually
	// targeting. Gated by SMART_SALE_TEXTRACT_KEEP_NOSALE (default ON);
	// set to 0 to restore the legacy unconditional drop if the wider review
	// surface causes UX regressions.
	keepNoSale := textractKeepNoSaleEnabled()
	if len(out) > 0 {
		filtered := make([]ExtractedReceiptItem, 0, len(out))
		droppedZero := 0
		keptNoSale := 0
		for _, it := range out {
			if it.Quantity > 0 {
				filtered = append(filtered, it)
				continue
			}
			if !keepNoSale {
				droppedZero++
				continue
			}
			// Keep rows that have an opening, closing, or amount signal — they
			// are real inventory rows the operator should still see. Drop only
			// the truly-empty layout noise (no numbers anywhere).
			open := 0
			if it.OpeningStock != nil {
				open = *it.OpeningStock
			}
			closeQ := 0
			if it.ClosingStock != nil {
				closeQ = *it.ClosingStock
			}
			amt := 0.0
			if it.Price != nil {
				amt = *it.Price
			}
			if open > 0 || closeQ > 0 || amt > 0 {
				it.IsZeroQuantity = true
				filtered = append(filtered, it)
				keptNoSale++
				continue
			}
			droppedZero++
		}
		if droppedZero > 0 {
			s.logger.Infof("SmartSale textract: dropped %d truly-empty rows pre-matcher (no opening, no closing, no amount)", droppedZero)
		}
		if keptNoSale > 0 {
			s.logger.Infof("SmartSale textract: kept %d qty=0 rows with opening/closing/amount signal (v1.0.312 keep-no-sale; flagged IsZeroQuantity=true for preserveZero handler)", keptNoSale)
		}
		out = filtered
	}

	// v1.0.306 — fill PostFilterRowCount per page from the surviving rows
	// so the caller's per-page rescue can see "page 2 had 11 raw rows but
	// 2 survived the qty=0 filter" vs "page 2 had 2 raw rows and 2 survived".
	postCountByPage := make(map[int]int, len(perPageStats))
	for _, it := range out {
		postCountByPage[it.PageNumber]++
	}
	// v1.0.325 — count rows per page where Textract returned qty=0 but rate>0.
	// These are likely "Textract blanked the sale cell" misses that math-gate
	// couldn't recover (single-corroborator gate skipped them). High counts
	// trigger Phase B (Claude full-page rescue) which has page context and
	// can read the qty cells properly.
	blankSaleByPage := make(map[int]int, len(perPageStats))
	for _, it := range out {
		if it.Quantity == 0 && it.RatePerUnit != nil && *it.RatePerUnit > 0 {
			blankSaleByPage[it.PageNumber]++
		}
	}
	for i := range perPageStats {
		perPageStats[i].PostFilterRowCount = postCountByPage[perPageStats[i].PageNumber]
		perPageStats[i].BlankSaleWithRateCount = blankSaleByPage[perPageStats[i].PageNumber]
	}

	if len(out) == 0 {
		return nil, nil, fmt.Errorf("textract returned no rows on any page")
	}

	res := &ReceiptExtractionResult{
		Items:          out,
		ProcessingTime: int(time.Since(startedAt).Milliseconds()),
		RowCountOnPage: totalRowSeen,
		PerPageStats:   perPageStats,
	}
	s.logger.Infof("SmartSale textract: %d total rows in %dms (%.2f$ est)",
		totalRowSeen, res.ProcessingTime, 0.015*float64(len(req.ImageData)))
	return out, res, nil
}

// textractKeepNoSaleEnabled controls whether the v1.0.171 unconditional
// qty=0 drop is narrowed to TRULY EMPTY rows only (v1.0.312). Default ON.
// Set SMART_SALE_TEXTRACT_KEEP_NOSALE=0 to revert to legacy behavior.
func textractKeepNoSaleEnabled() bool {
	v := strings.TrimSpace(os.Getenv("SMART_SALE_TEXTRACT_KEEP_NOSALE"))
	if v == "" {
		return true
	}
	return v != "0" && !strings.EqualFold(v, "false") && !strings.EqualFold(v, "off")
}

// perPageRescueEnabled returns true when per-page collapse rescue should
// dispatch a Gemini/Claude rerun on individual collapsed pages even after
// Textract globally clears the size-based min-rows floor. Default ON; set
// SMART_SALE_PER_PAGE_RESCUE=0 to disable per-tenant if a noisy page
// produces worse fallback OCR than the original Textract output.
func perPageRescueEnabled() bool {
	v := strings.TrimSpace(os.Getenv("SMART_SALE_PER_PAGE_RESCUE"))
	if v == "" {
		return true
	}
	return v != "0" && !strings.EqualFold(v, "false") && !strings.EqualFold(v, "off")
}

// detectCollapsedPages returns the 1-based page numbers that look collapsed
// relative to their sibling pages. Heuristic:
//   - Need ≥ 2 pages with data — no median = no signal.
//   - Compute median raw_row_count across pages with raw_row_count > 0.
//   - Skip if median < 5 (whole register is sparse — no signal to rescue against;
//     respects v1.0.215.13's lesson that sparse registers can't be distinguished
//     from collapsed extraction without external signal).
//   - A page is collapsed if:
//     raw_row_count < max(2, median * 0.30)
//     OR (suspicious_brand_count >= 1 AND raw_row_count < median * 0.50)
//
// The suspicious-brand path catches column-slip cases (page 2 of chhotu
// b41913a8: raw_count=2, both brands "141" / "108" — all-digit) even when
// the raw_count alone wouldn't trip the 30% threshold.
func detectCollapsedPages(stats []ExtractionPageStats) []int {
	if len(stats) < 2 {
		return nil
	}
	counts := make([]int, 0, len(stats))
	for _, s := range stats {
		if s.RawRowCount > 0 {
			counts = append(counts, s.RawRowCount)
		}
	}
	if len(counts) < 2 {
		// Includes the case where ≥ 1 page returned 0 rows; those pages are
		// collapsed by definition (handled below regardless of median).
	}
	median := medianInt(counts)
	if median < 5 {
		// Even if some pages returned 0, we can't tell collapse from "this
		// register is just sparse" without external signal. Don't dispatch
		// fallback OCR in this regime — it would just spend budget rerunning
		// already-correct sparse pages. (v1.0.215.13 lesson.)
		// Exception: pages that returned exactly 0 rows AND another page
		// returned > 0 → still rescue, since 0 is unambiguously broken.
		out := []int{}
		anyData := false
		for _, s := range stats {
			if s.RawRowCount > 0 {
				anyData = true
				break
			}
		}
		if !anyData {
			return nil
		}
		for _, s := range stats {
			if s.PageNumber > 0 && s.RawRowCount == 0 {
				out = append(out, s.PageNumber)
			}
		}
		return out
	}
	threshold := median * 30 / 100
	if threshold < 2 {
		threshold = 2
	}
	softThreshold := median * 50 / 100
	out := []int{}
	for _, s := range stats {
		if s.PageNumber <= 0 {
			continue
		}
		if s.RawRowCount == 0 {
			out = append(out, s.PageNumber)
			continue
		}
		// v1.0.325 — blank-sale-with-rate trigger is checked FIRST (before
		// the LayoutDetected trust gate) because it's a strong post-extraction
		// signal that overrides the "header detection succeeded so trust the
		// page" assumption. Textract can perfectly detect the header layout
		// AND still blank the Sale cells (digit OCR is independent of table
		// structure). When ≥3 rows on a page have qty=0 BUT rate>0 AND that's
		// ≥30% of the page, force Phase B Claude rescue regardless of layout
		// status. 2026-05-25 forensic: 103/103 AI-wrong training samples were
		// "Textract blanked the Sale cell" — this catches that class.
		if s.BlankSaleWithRateCount >= 3 && s.PostFilterRowCount > 0 {
			ratio := float64(s.BlankSaleWithRateCount) / float64(s.PostFilterRowCount)
			if ratio >= 0.30 {
				out = append(out, s.PageNumber)
				continue
			}
		}
		if s.RawRowCount < threshold {
			out = append(out, s.PageNumber)
			continue
		}
		// v1.0.316 — when Textract header_detect succeeded, trust the page
		// even if its row count is below the soft threshold. The original
		// rationale for the soft threshold was the chhotu page-2 column-slip
		// case where SuspiciousBrandCount went sky-high — that's solved by
		// the dynamic layout detector (v1.0.314/315). Without this guard,
		// every clean contd page with fewer real rows than page 1 keeps
		// triggering the ~30s Claude rescue for no recall gain.
		if s.LayoutDetected && s.SuspiciousBrandCount <= 1 {
			continue
		}
		if s.SuspiciousBrandCount >= 1 && s.RawRowCount < softThreshold {
			out = append(out, s.PageNumber)
			continue
		}
		// v1.0.320 — legacy_9col fallback (LayoutDetected=false) means
		// Textract's header_detect couldn't find a header row, so the table
		// structure is degraded. When combined with ≥2 suspicious brand
		// cells (empty / all-digit / ≤2 char), this is a strong signal of
		// row misalignment even when RawRowCount looks healthy.
		//
		// Chhotu's 750ml job a095aa63 (2026-05-24) page 1: legacy_9col +
		// 2 empty-brand cells + concatenated brand text like
		// "8 PM Vodka Whisky 1965 Ram" + "MCD Double Original Whisky Rum"
		// — Textract collapsed adjacent printed-brand rows into one cell
		// for the brand column but kept row count high (30). Without this
		// trigger the row-count gate skipped rescue and the operator saw
		// garbled brands with high match-confidence ("MCD Double Original
		// Whisky Rum" matched a real product at conf 0).
		if !s.LayoutDetected && s.SuspiciousBrandCount >= 2 && s.RawRowCount > 0 {
			out = append(out, s.PageNumber)
		}
	}
	return out
}

// medianInt — small helper, sorts a copy of xs and returns the middle value.
func medianInt(xs []int) int {
	if len(xs) == 0 {
		return 0
	}
	cp := make([]int, len(xs))
	copy(cp, xs)
	// Tiny n — use insertion sort to avoid pulling in sort just for this.
	for i := 1; i < len(cp); i++ {
		for j := i; j > 0 && cp[j-1] > cp[j]; j-- {
			cp[j-1], cp[j] = cp[j], cp[j-1]
		}
	}
	return cp[len(cp)/2]
}

// enhanceImageForTextract applies a fast contrast/exposure correction so
// over-exposed pages — chhotu's quality-check reports brightness ~235/255 + low
// contrast ~52 on every page — give Textract's TABLE detector more signal to
// lock onto. Steps (all single-pass, no external deps):
//
//  1. Decode JPEG/PNG.
//  2. Compute the 5/95-percentile luma via a 256-bin histogram (single pass).
//  3. Linear contrast stretch on each RGB channel: out = clamp((in - p05) * 255 / (p95 - p05)).
//  4. Light gamma compress (γ ≈ 1.25) to push highlights down without crushing shadows.
//  5. Re-encode JPEG quality 92.
//
// Total cost on a 3MP image: ~250ms. Returns the original bytes on any error
// so the rescue path always has something to call Textract with.
func enhanceImageForTextract(raw []byte) ([]byte, error) {
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return raw, fmt.Errorf("decode: %w", err)
	}
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	if w == 0 || h == 0 {
		return raw, fmt.Errorf("empty image")
	}

	// Single histogram pass over a luma proxy (we don't need full BT.709
	// — green channel is a fast, accurate enough stand-in for exposure
	// metrics on document scans).
	var hist [256]int64
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			_, g, _, _ := img.At(x, y).RGBA()
			hist[uint8(g>>8)]++
		}
	}
	total := int64(w) * int64(h)
	cutoff05, cutoff95 := total*5/100, total*95/100
	var lo, hi uint8 = 0, 255
	var cum int64
	for i := 0; i < 256; i++ {
		cum += hist[i]
		if lo == 0 && cum >= cutoff05 {
			lo = uint8(i)
		}
		if cum >= cutoff95 {
			hi = uint8(i)
			break
		}
	}
	if hi <= lo {
		return raw, fmt.Errorf("flat histogram lo=%d hi=%d", lo, hi)
	}
	span := float64(hi - lo)

	// Precompute the 256-entry LUT (stretch + gamma) so the per-pixel loop is
	// three table lookups, not three float ops.
	const gamma = 1.25
	invGamma := 1.0 / gamma
	var lut [256]uint8
	for i := 0; i < 256; i++ {
		v := (float64(i) - float64(lo)) * 255.0 / span
		if v < 0 {
			v = 0
		}
		if v > 255 {
			v = 255
		}
		v = math.Pow(v/255.0, invGamma) * 255.0
		lut[i] = uint8(v + 0.5)
	}

	out := image.NewRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, _ := img.At(x, y).RGBA()
			out.SetRGBA(x, y, color.RGBA{
				R: lut[uint8(r>>8)],
				G: lut[uint8(g>>8)],
				B: lut[uint8(b>>8)],
				A: 255,
			})
		}
	}

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: 92}); err != nil {
		return raw, fmt.Errorf("encode: %w", err)
	}
	return buf.Bytes(), nil
}

// runTextractPageEnhanced runs the existing runTextractPage on a contrast-
// enhanced copy of the image. Used by the per-page rescue (smart_sale_service.go)
// when Textract under-extracted a page on the first pass — gives AWS a second
// chance with a cleaner image before falling back to Claude (~30s).
func (s *SmartSaleService) runTextractPageEnhanced(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]ExtractedReceiptItem, []byte, error) {
	startedAt := time.Now()
	enhanced, err := enhanceImageForTextract(raw)
	if err != nil {
		s.logger.Warnf("SmartSale textract retry: page %d image enhance failed: %v — calling Textract on original bytes", pageNumber, err)
		enhanced = raw
	} else {
		s.logger.Infof("SmartSale textract retry: page %d enhanced %d→%d bytes in %dms",
			pageNumber, len(raw), len(enhanced), time.Since(startedAt).Milliseconds())
	}
	// v1.0.309 — add FORMS feature so Textract uses key-value-pair detection
	// alongside TABLES. FORMS picks up row signal even when the table grid
	// detector struggles (mixed printed-and-handwritten brand columns,
	// strikethrough marks). Pure TABLES on chhotu's page 2 returned 4 rows;
	// FORMS+TABLES often recovers the missing handwritten rows.
	items, _, perr := s.runTextractPageWithFeatures(ctx, client, enhanced, pageNumber,
		[]ttypes.FeatureType{ttypes.FeatureTypeTables, ttypes.FeatureTypeForms})
	return items, enhanced, perr
}

// runTextractPageBinarized is the second-chance retry: applies an Otsu
// threshold to convert the image to pure black/white before calling Textract
// with TABLES + FORMS. Defeats faint-ink + uneven-exposure cases where the
// contrast-stretch retry didn't lift Textract above the original row count
// (chhotu's printed brand column is very faint on page 2 of the 180ml book).
func (s *SmartSaleService) runTextractPageBinarized(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]ExtractedReceiptItem, []byte, error) {
	startedAt := time.Now()
	binarized, err := binarizeImageForTextract(raw)
	if err != nil {
		s.logger.Warnf("SmartSale textract binarize-retry: page %d binarize failed: %v — calling Textract on original bytes", pageNumber, err)
		binarized = raw
	} else {
		s.logger.Infof("SmartSale textract binarize-retry: page %d binarized %d→%d bytes in %dms",
			pageNumber, len(raw), len(binarized), time.Since(startedAt).Milliseconds())
	}
	items, _, perr := s.runTextractPageWithFeatures(ctx, client, binarized, pageNumber,
		[]ttypes.FeatureType{ttypes.FeatureTypeTables, ttypes.FeatureTypeForms})
	return items, binarized, perr
}

// runTextractPageWithFeatures — variant of runTextractPage that accepts the
// FeatureTypes list. Delegates to runTextractPageInner so the rescue paths
// (TABLES + FORMS) and the primary pass (TABLES only) share parsing.
func (s *SmartSaleService) runTextractPageWithFeatures(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
	features []ttypes.FeatureType,
) ([]ExtractedReceiptItem, ColumnLayout, error) {
	return s.runTextractPageInner(ctx, client, raw, pageNumber, features)
}

// binarizeImageForTextract converts the image to pure black/white via Otsu
// global thresholding — equalises faint printed text with dark handwritten
// ink so Textract's grid + cell detectors get a sharper input. Single
// histogram pass to pick the threshold, one pixel pass to apply it. ~150ms
// for a 3MP image.
//
// Otsu picks the threshold that maximises between-class variance — works
// well on document scans where most pixels are background + foreground with
// limited mid-tones. For chhotu's mixed-content brand column this collapses
// the (faint printed, dark handwritten, page background) into two clean
// classes Textract can lock onto.
func binarizeImageForTextract(raw []byte) ([]byte, error) {
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return raw, fmt.Errorf("decode: %w", err)
	}
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	if w == 0 || h == 0 {
		return raw, fmt.Errorf("empty image")
	}

	// Build luma histogram in one pass. Use BT.601 luma weights
	// (0.299R + 0.587G + 0.114B) so the threshold reflects perceived
	// brightness, not just green channel.
	var hist [256]int64
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, _ := img.At(x, y).RGBA()
			luma := (299*uint32(r>>8) + 587*uint32(g>>8) + 114*uint32(b>>8)) / 1000
			hist[uint8(luma)]++
		}
	}
	total := int64(w) * int64(h)

	// Otsu: pick threshold t minimizing intra-class variance.
	var sumAll float64
	for i := 0; i < 256; i++ {
		sumAll += float64(i) * float64(hist[i])
	}
	var sumB, wB float64
	var bestT int = 127
	var bestVar float64 = -1
	for t := 0; t < 256; t++ {
		wB += float64(hist[t])
		if wB == 0 {
			continue
		}
		wF := float64(total) - wB
		if wF == 0 {
			break
		}
		sumB += float64(t) * float64(hist[t])
		mB := sumB / wB
		mF := (sumAll - sumB) / wF
		v := wB * wF * (mB - mF) * (mB - mF)
		if v > bestVar {
			bestVar = v
			bestT = t
		}
	}

	threshold := uint32(bestT)
	out := image.NewRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, _ := img.At(x, y).RGBA()
			luma := (299*uint32(r>>8) + 587*uint32(g>>8) + 114*uint32(b>>8)) / 1000
			var v uint8 = 255
			if luma < threshold {
				v = 0
			}
			out.SetRGBA(x, y, color.RGBA{R: v, G: v, B: v, A: 255})
		}
	}

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: 92}); err != nil {
		return raw, fmt.Errorf("encode: %w", err)
	}
	return buf.Bytes(), nil
}

// isSuspiciousBrandText returns true when the OCR'd brand cell looks like
// Textract slipped a numeric column (e.g. Opening or Receipt) into the brand
// position — classic symptom of a collapsed page on a multi-page register.
// Flags rows whose brand is empty after trim, all-digit, a very short token
// (≤2 chars), or matches a schema-key word (column header text that leaked
// into a data row). Used as one signal among several when deciding per-page
// rescue.
//
// v1.0.320 — extended to catch the column-header-text leak case (chhotu
// 750ml job a095aa63 page 1 row 5 had brand="Brand" — the literal column
// header text — because Textract's vertical row alignment slipped one row).
// Before v1.0.320 those rows weren't flagged here; the smart_sale_service
// schema-key sanitizer cleared them later but the per-page rescue gate
// missed the signal and skipped Claude fallback.
func isSuspiciousBrandText(brand string) bool {
	b := strings.TrimSpace(brand)
	if b == "" {
		return true
	}
	if len(b) <= 2 {
		return true
	}
	allDigits := true
	for _, r := range b {
		if r == ' ' || r == '.' || r == ',' || r == '-' {
			continue
		}
		if r < '0' || r > '9' {
			allDigits = false
			break
		}
	}
	if allDigits {
		return true
	}
	// v1.0.320 — schema-key leak. Keep the set in sync with the sanitizer
	// in smart_sale_service.go:1031-1037 (intentional duplication: two
	// different stages, same source-of-truth).
	switch strings.ToLower(b) {
	case "brand", "raw_text", "name", "size", "size_text", "size_ml",
		"rate", "rate_per_unit", "price", "quantity", "amount", "total",
		"opening_stock", "closing_stock", "receipt",
		"row_number", "page_number", "confidence",
		// Column-header phrases. Textract occasionally pastes the
		// "Brand Name" / "Item Name" header text into a data row when
		// table-cell detection collapses the title-band into the body.
		"brand name", "item name", "particulars":
		return true
	}
	return false
}

// runTextractPage submits one page image to AnalyzeDocument and converts the
// Tables response into ExtractedReceiptItem rows. Thin wrapper that calls
// runTextractPageInner with TABLES-only — preserves the existing primary-pass
// behavior. Rescue paths use TABLES+FORMS via runTextractPageWithFeatures.
func (s *SmartSaleService) runTextractPage(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]ExtractedReceiptItem, error) {
	items, _, err := s.runTextractPageInner(ctx, client, raw, pageNumber,
		[]ttypes.FeatureType{ttypes.FeatureTypeTables})
	return items, err
}

// runTextractPageWithLayout is the v1.0.316 variant that also returns the
// ColumnLayout decision so callers can drive trust-based rescue gating.
// extractWithTextract uses this for the primary call; rescue paths stick
// with the items-only wrappers.
func (s *SmartSaleService) runTextractPageWithLayout(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]ExtractedReceiptItem, ColumnLayout, error) {
	return s.runTextractPageInner(ctx, client, raw, pageNumber,
		[]ttypes.FeatureType{ttypes.FeatureTypeTables})
}

// runTextractPageInner — actual implementation. Picks the largest TABLE
// block on the page (registers always have one dominant table; smaller
// blocks are usually header captures Textract over-segmented).
func (s *SmartSaleService) runTextractPageInner(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
	features []ttypes.FeatureType,
) ([]ExtractedReceiptItem, ColumnLayout, error) {

	pctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(pctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: raw},
		FeatureTypes: features,
	})
	if err != nil {
		return nil, ColumnLayout{}, fmt.Errorf("AnalyzeDocument: %w", err)
	}

	blockByID := map[string]ttypes.Block{}
	for _, b := range resp.Blocks {
		if b.Id != nil {
			blockByID[*b.Id] = b
		}
	}

	// Find the largest TABLE block (most cells).
	var bestTable *ttypes.Block
	bestCellCount := 0
	for i, b := range resp.Blocks {
		if b.BlockType != ttypes.BlockTypeTable {
			continue
		}
		cells := 0
		for _, rel := range b.Relationships {
			if rel.Type == ttypes.RelationshipTypeChild {
				cells += len(rel.Ids)
			}
		}
		if cells > bestCellCount {
			bestCellCount = cells
			bestTable = &resp.Blocks[i]
		}
	}
	if bestTable == nil {
		return nil, ColumnLayout{}, nil
	}

	// rowsByIdx[r] is a map[colIdx]string of CELL text on Textract row r.
	rowsByIdx := map[int32]map[int32]ttypes.Block{}
	for _, rel := range bestTable.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, cid := range rel.Ids {
			cell, ok := blockByID[cid]
			if !ok || cell.BlockType != ttypes.BlockTypeCell || cell.RowIndex == nil || cell.ColumnIndex == nil {
				continue
			}
			row := *cell.RowIndex
			col := *cell.ColumnIndex
			if rowsByIdx[row] == nil {
				rowsByIdx[row] = map[int32]ttypes.Block{}
			}
			rowsByIdx[row][col] = cell
		}
	}

	out := make([]ExtractedReceiptItem, 0, len(rowsByIdx))
	// Sort rows ascending — Textract row 1 is usually header.
	rowIDs := make([]int32, 0, len(rowsByIdx))
	for r := range rowsByIdx {
		rowIDs = append(rowIDs, r)
	}
	sortInt32(rowIDs)

	// v1.0.314 — dynamic column-layout detection. chhotu's contd pages have
	// 8 columns (no S.N) instead of 9; the hardcoded col* constants slip
	// every cell one to the right (brand reads "88" = the Opening number,
	// etc). detectColumnLayout reads the header row and remaps cells to
	// canonical roles. Falls back to legacy 9-col mapping if no header found,
	// so well-formed pages see zero change.
	layout := detectColumnLayout(rowsByIdx, blockByID)
	s.logger.Infof("SmartSale textract: page %d layout %s (brand=%d open=%d sale=%d rate=%d amt=%d close=%d serial=%d)",
		pageNumber, layout.Source, layout.Brand, layout.Opening, layout.Sale, layout.Rate, layout.Amount, layout.Closing, layout.SerialNo)

	// v1.0.241 — row-alignment cross-checks. serialByRowIdx feeds the
	// post-loop monotonicity check (Fix 1a). rowGeom caches the per-row
	// median Y/Height for the cell-geometry outlier check (Fix 1b).
	// See textract_row_alignment.go for the rationale.
	serialByRowIdx := make(map[int32]int, len(rowIDs))
	type rowMedian struct {
		y, h    float32
		hasGeom bool
	}
	rowGeoms := make(map[int32]rowMedian, len(rowsByIdx))
	for rIdx, cells := range rowsByIdx {
		y, h, ok := rowMedianGeom(cells)
		rowGeoms[rIdx] = rowMedian{y: y, h: h, hasGeom: ok}
	}

	for _, r := range rowIDs {
		cells := rowsByIdx[r]
		// v1.0.314 — skip EVERY row Textract tagged COLUMN_HEADER (chhotu's
		// page 2 has both row 1 [empty title band] and row 2 [real header
		// text] marked COLUMN_HEADER; the pre-v1.0.314 code only skipped
		// row 1 and let row 2 leak through the matcher with "Brand Name" /
		// "Openin" as if they were data).
		if isHeaderRow(cells) {
			continue
		}
		// Defensive legacy keyword check for tables that don't carry the
		// EntityType signal (older Textract responses).
		if r == 1 {
			brandHdr := strings.ToUpper(strings.TrimSpace(cellText(cells[layout.Brand], blockByID)))
			if strings.Contains(brandHdr, "BRAND") || strings.Contains(brandHdr, "ITEM") || strings.Contains(brandHdr, "PARTICULAR") {
				continue
			}
		}

		brandText := strings.TrimSpace(cellText(cells[layout.Brand], blockByID))
		serialText := strings.TrimSpace(cellText(cells[layout.SerialNo], blockByID))
		saleQty, _ := parseIntCell(cells[layout.Sale], blockByID)

		// v1.0.165 — aggressive row filter to keep Textract output clean.
		// Pre-fix every header/total/blank row leaked through to the matcher
		// and got merged into other rows by the dedup-sum step (chhotu's
		// 100 STROKES ROYAL appeared at qty=102, Imperial Blue at qty=51 —
		// sums of header+data+total rows that all happened to pattern-match
		// the same product). The four guards below kill that class:

		// Guard 1: completely empty brand AND zero quantity → blank row.
		if brandText == "" && saleQty == 0 {
			continue
		}
		// Guard 2: serial column says "Total"/"Grand"/"Sub" → footer row.
		uS := strings.ToUpper(serialText)
		if strings.Contains(uS, "TOTAL") || strings.Contains(uS, "GRAND") || strings.Contains(uS, "SUB") {
			continue
		}
		uB := strings.ToUpper(brandText)
		if strings.HasPrefix(uB, "TOTAL") || strings.HasPrefix(uB, "GRAND") || strings.HasPrefix(uB, "SUB") {
			continue
		}
		// Guard 3: implausibly-high Sale qty (>200) almost always means
		// Textract read the Amount column as Sale due to grid-detection slip.
		// Real per-row sale qty caps around 60-80 even on busy days.
		if saleQty > 200 {
			continue
		}
		// Guard 4: brand text is too short or pure punctuation — likely a
		// corner cell with stray ink. Real brands are >= 3 chars.
		//
		// v1.0.322 — relaxed: when rate cell is populated, the row has real
		// numeric data even if the brand cell is unreadable. Dropping it
		// here loses 80+ "missed truth" rows per sweep (chhotu 2026-05-24:
		// M2 Verve Cranberry, Smirnoff Orange, M2 Jamun Spicymint missed 8/8/6
		// times because the AI couldn't read the brand cell but Textract DID
		// extract the rate). The downstream stock-setup rate-rescue
		// (smart_sale_service.go v1.0.116) resolves brand by rate from the
		// shop's printed brand list. Letting these rows through gives the
		// rescue path a chance to anchor the SKU.
		if len(brandText) < 3 && saleQty == 0 {
			rateProbe, _ := parseFloatCell(cells[layout.Rate], blockByID)
			amountProbe, _ := parseFloatCell(cells[layout.Amount], blockByID)
			if rateProbe == 0 && amountProbe == 0 {
				continue
			}
		}

		open, _ := parseIntCell(cells[layout.Opening], blockByID)
		recv, _ := parseIntCell(cells[layout.Receipt], blockByID)
		total, _ := parseIntCell(cells[layout.Total], blockByID)
		rate, _ := parseFloatCell(cells[layout.Rate], blockByID)
		amount, _ := parseFloatCell(cells[layout.Amount], blockByID)
		closing, _ := parseIntCell(cells[layout.Closing], blockByID)
		serial, _ := parseIntCell(cells[layout.SerialNo], blockByID)

		// Guard 5 (v1.0.317): GRAND TOTAL footer slips through when the
		// page has no S.N column (chhotu page-2 contd template). The
		// footer row reads brand="" + sale={page total sale qty} +
		// amount={page total amount} + opening={page total opening} which
		// passes guards 1-4 because sale > 0 and brand-length check only
		// fires when saleQty==0. Real per-row sale qty caps around 30-60
		// even on chhotu's busiest days; real per-row amount caps near
		// rate*qty ≈ 5000. Drop rows where brand is empty AND either
		// opening or amount is implausibly high.
		if brandText == "" {
			if open >= 200 || amount >= 5000 || saleQty >= 30 {
				continue
			}
		}

		// Per-cell confidence comes directly from Textract's CELL block.
		fc := map[string]float64{}
		setConf := func(k string, c ttypes.Block) {
			if c.Confidence != nil {
				fc[k] = float64(*c.Confidence) / 100.0
			}
		}
		setConf("brand", cells[layout.Brand])
		setConf("opening", cells[layout.Opening])
		setConf("receipt", cells[layout.Receipt])
		setConf("total", cells[layout.Total])
		setConf("sale", cells[layout.Sale])
		setConf("quantity", cells[layout.Sale])
		setConf("rate", cells[layout.Rate])
		setConf("amount", cells[layout.Amount])
		setConf("closing", cells[layout.Closing])

		// Row-level confidence = average of cell confidences (the 0-1 scale).
		rowConf := 0.0
		if len(fc) > 0 {
			sum := 0.0
			for _, v := range fc {
				sum += v
			}
			rowConf = sum / float64(len(fc))
		}

		item := ExtractedReceiptItem{
			Brand:           brandText,
			Quantity:        saleQty,
			RowNumber:       int(r),
			PageNumber:      pageNumber,
			Confidence:      rowConf,
			RawText:         brandText,
			Source:          "textract",
			FieldConfidence: fc,
		}
		if open > 0 {
			o := open
			item.OpeningStock = &o
		}
		if recv > 0 {
			rv := recv
			item.Receipt = &rv
		}
		if total > 0 {
			t := total
			item.Total = &t
		}
		if rate > 0 {
			r2 := rate
			item.RatePerUnit = &r2
		}
		if amount > 0 {
			a := amount
			item.Price = &a
		}
		if closing > 0 || (open > 0 && saleQty >= 0) {
			c := closing
			item.ClosingStock = &c
		}
		if saleQty == 0 {
			item.IsZeroQuantity = true
		}

		// v1.0.241 — Fix 1b: brand-cell Y-outlier warning. If Textract's
		// per-cell binner put the brand cell into a row whose median Y is
		// far from this cell's actual Y, the row's data is suspect and the
		// preview UI should force a re-review chip rather than auto-save.
		if rg, ok := rowGeoms[r]; ok && rg.hasGeom {
			if w := brandCellYOutlierWarning(cells[layout.Brand], rg.y, rg.h); w != "" {
				item.Warnings = append(item.Warnings, w)
			}
			// v1.0.341 — also watch the SALE/quantity cell. This is the cell
			// that actually drifts in the Malsaii scramble class (brand+opening
			// stay on their true row, the handwritten sale digit lands one row
			// off). A drifted sale cell means this brand's quantity came from a
			// neighbouring line → force review downstream rather than auto-save.
			if w := cellYOutlierWarning(cells[layout.Sale], rg.y, rg.h, "sale"); w != "" {
				item.Warnings = append(item.Warnings, w)
			}
		}

		// v1.0.241 — Fix 1a: capture parsed S.N for the post-loop
		// monotonicity check. serial<=0 means the cell was blank or
		// unparsable (contd pages with no S.N column hit this).
		if serial > 0 {
			serialByRowIdx[r] = serial
		}

		out = append(out, item)
	}

	// v1.0.241 — Fix 1a: flag pairs of items whose printed S.N order
	// disagrees with Textract's row-index order. Both sides of the
	// inversion get a needs-review warning so the preview UI can prompt
	// the operator to verify each row's brand+numbers.
	flagRowOrderInversions(out, serialByRowIdx)

	return out, layout, nil
}

// cellText concatenates the WORDs that make up a CELL's text.
func cellText(cell ttypes.Block, byID map[string]ttypes.Block) string {
	if cell.BlockType == "" {
		return ""
	}
	var parts []string
	for _, rel := range cell.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, id := range rel.Ids {
			child, ok := byID[id]
			if !ok {
				continue
			}
			if child.BlockType == ttypes.BlockTypeWord && child.Text != nil {
				parts = append(parts, *child.Text)
			}
		}
	}
	return strings.Join(parts, " ")
}

// parseIntCell tolerates leading/trailing whitespace, commas, and Hindi
// digits the OCR sometimes returns. Returns (value, ok).
func parseIntCell(cell ttypes.Block, byID map[string]ttypes.Block) (int, bool) {
	t := strings.TrimSpace(cellText(cell, byID))
	if t == "" {
		return 0, false
	}
	t = strings.ReplaceAll(t, ",", "")
	// Strip non-digit prefixes/suffixes (Textract sometimes attaches "₹").
	clean := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		if r == '-' {
			return r
		}
		return -1
	}, t)
	if clean == "" {
		return 0, false
	}
	v, err := strconv.Atoi(clean)
	if err != nil {
		return 0, false
	}
	return v, true
}

func parseFloatCell(cell ttypes.Block, byID map[string]ttypes.Block) (float64, bool) {
	t := strings.TrimSpace(cellText(cell, byID))
	if t == "" {
		return 0, false
	}
	t = strings.ReplaceAll(t, ",", "")
	t = strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		if r == '.' || r == '-' {
			return r
		}
		return -1
	}, t)
	if t == "" {
		return 0, false
	}
	v, err := strconv.ParseFloat(t, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

// sortInt32 in-place ascending. Cheap; avoids the sort.Slice allocation.
func sortInt32(a []int32) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j-1] > a[j]; j-- {
			a[j-1], a[j] = a[j], a[j-1]
		}
	}
}

// confirmedDigitAutoFixEnabled — Track C5. Default ON.
func confirmedDigitAutoFixEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("SMART_SALE_AUTO_FIX_ENABLED")))
	if v == "0" || v == "false" || v == "off" || v == "no" {
		return false
	}
	return true
}

// confirmedDigitAutoFixThreshold — minimum occurrence_count required to
// silently apply a confirmed correction. Below this, the doubt still goes
// to the popup queue. Tunable via SMART_SALE_AUTO_FIX_THRESHOLD.
func confirmedDigitAutoFixThreshold() int {
	const def = 3
	v := strings.TrimSpace(os.Getenv("SMART_SALE_AUTO_FIX_THRESHOLD"))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 1 {
		return def
	}
	return n
}

// applyConfirmedDigitCorrections walks one row and replaces every cell whose
// AI-extracted value matches a confirmed (raw → corrected) entry for this
// shop. Returns the number of cells replaced. Mutates the row in place.
//
// The mapping is keyed by field name ("quantity"/"sale", "rate", "amount",
// "opening", "closing", "receipt") to avoid cross-cell pollution (a "5"
// confused for "9" on the rate column shouldn't auto-fix sale qty).
func applyConfirmedDigitCorrections(row *ExtractedReceiptItem, confirmed map[string]map[string]string) int {
	if row == nil || len(confirmed) == 0 {
		return 0
	}
	if row.Warnings == nil {
		row.Warnings = []string{}
	}
	hits := 0
	tryInt := func(field string, current *int) {
		if current == nil {
			return
		}
		m, ok := confirmed[field]
		if !ok || len(m) == 0 {
			return
		}
		raw := fmt.Sprintf("%d", *current)
		corr, ok := m[raw]
		if !ok || corr == raw {
			return
		}
		v, err := strconv.Atoi(corr)
		if err != nil {
			return
		}
		*current = v
		hits++
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		row.FieldConfidence[field] = 0.97
		row.Warnings = append(row.Warnings, "auto_fix:"+field+":"+raw+"->"+corr)
	}
	tryFloat := func(field string, current *float64) {
		if current == nil {
			return
		}
		m, ok := confirmed[field]
		if !ok || len(m) == 0 {
			return
		}
		raw := fmt.Sprintf("%.0f", *current)
		corr, ok := m[raw]
		if !ok || corr == raw {
			return
		}
		v, err := strconv.ParseFloat(corr, 64)
		if err != nil {
			return
		}
		*current = v
		hits++
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		row.FieldConfidence[field] = 0.97
		row.Warnings = append(row.Warnings, "auto_fix:"+field+":"+raw+"->"+corr)
	}

	// Sale / quantity: same field, two names. Try both since the popup
	// queue may have written under either key (matched on backend
	// ResolveDoubt's `field` parameter).
	if v := row.Quantity; v != 0 || row.IsZeroQuantity {
		raw := fmt.Sprintf("%d", v)
		var corr string
		var found bool
		if m, ok := confirmed["sale"]; ok {
			if c, ok := m[raw]; ok {
				corr, found = c, true
			}
		}
		if !found {
			if m, ok := confirmed["quantity"]; ok {
				if c, ok := m[raw]; ok {
					corr, found = c, true
				}
			}
		}
		if found && corr != raw {
			if vNew, err := strconv.Atoi(corr); err == nil {
				row.Quantity = vNew
				if vNew == 0 {
					row.IsZeroQuantity = true
				} else {
					row.IsZeroQuantity = false
				}
				hits++
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				row.FieldConfidence["sale"] = 0.97
				row.FieldConfidence["quantity"] = 0.97
				row.Warnings = append(row.Warnings, "auto_fix:sale:"+raw+"->"+corr)
			}
		}
	}

	tryInt("opening", row.OpeningStock)
	tryInt("closing", row.ClosingStock)
	tryInt("receipt", row.Receipt)
	tryInt("total", row.Total)
	tryFloat("rate", row.RatePerUnit)
	tryFloat("amount", row.Price)

	return hits
}

// setupRescueMaxRows — Track A5. Cap on number of setup_rescue rows
// auto-injected. Default 5 (chhotu's June 4 had 23 → operator burden was the
// complaint). 0 disables the cap (legacy behaviour). Tunable via
// SMART_SALE_RESCUE_MAX_ROWS.
func setupRescueMaxRows() int {
	const def = 5
	v := strings.TrimSpace(os.Getenv("SMART_SALE_RESCUE_MAX_ROWS"))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return def
	}
	return n
}

// setupRescueEnabled — v1.0.303. The setup-rescue feature auto-injects
// every stock-setup product that didn't appear in the AI extraction as a
// needs_review row ("AI may have missed this row — present in latest
// stock setup"). Operator directive 2026-05-23: do not show these
// auto-suggested rows. Real complaint: chhotu's 90ml (Nip) sale extracted
// Royal Stag Whisky cleanly (qty 12), but rescue injected a SECOND Royal
// Stag row (different product_id from a same-named SKU variant) plus a
// Seagrams Blenders row the operator never typed — operator wants pure
// AI extraction surfaced, will manually add what's missing.
//
// Default OFF. Set SMART_SALE_SETUP_RESCUE_ENABLED=1 (or true/on/yes) to
// flip back on. Same shape as reviewDemotionEnabled below for consistency.
func setupRescueEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("SMART_SALE_SETUP_RESCUE_ENABLED")))
	if v == "1" || v == "true" || v == "on" || v == "yes" {
		return true
	}
	return false
}

// reviewDemotionEnabled — Track A4. Default ON. Set SMART_SALE_REVIEW_DEMOTION=0
// to keep every flagged row visible (rollout escape hatch).
func reviewDemotionEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("SMART_SALE_REVIEW_DEMOTION")))
	if v == "0" || v == "false" || v == "off" || v == "no" {
		return false
	}
	return true
}

// reviewDemotionMatchFloor — minimum match confidence (0-1) required to demote
// a row out of NeedsReview. Default 0.80. Tuned via SMART_SALE_REVIEW_DEMOTION_MATCH.
func reviewDemotionMatchFloor() float64 {
	const def = 0.80
	v := strings.TrimSpace(os.Getenv("SMART_SALE_REVIEW_DEMOTION_MATCH"))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f <= 0 || f > 1 {
		return def
	}
	return f
}

// reviewDemotionFieldFloor — minimum sale field confidence (0-1) required to
// demote. Default 0.85. Tuned via SMART_SALE_REVIEW_DEMOTION_FIELD.
func reviewDemotionFieldFloor() float64 {
	const def = 0.85
	v := strings.TrimSpace(os.Getenv("SMART_SALE_REVIEW_DEMOTION_FIELD"))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f <= 0 || f > 1 {
		return def
	}
	return f
}

// invariantGateEnabled — Track C1. Default ON. Disable per-incident with
// SMART_SALE_INVARIANT_GATE=0.
func invariantGateEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("SMART_SALE_INVARIANT_GATE")))
	if v == "0" || v == "false" || v == "off" || v == "no" {
		return false
	}
	return true
}

// invariantAutoFixConfFloor — minimum confidence required to silently apply
// an arithmetic suggestion (no popup). Below this, the suggestion still goes
// to the doubt queue for operator confirmation.
func invariantAutoFixConfFloor() float64 {
	const def = 0.85
	v := strings.TrimSpace(os.Getenv("SMART_SALE_INVARIANT_AUTOFIX_CONF"))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f <= 0 || f > 1 {
		return def
	}
	return f
}

// effectiveOpening computes the available stock for the day given the four
// stock-related cells the register may have. Order:
//  1. Total cell when present and >= Opening (operator wrote the post-receipt total),
//  2. Opening + Receipt when both are valid,
//  3. just Opening (no purchase that day).
//
// Returns -1 when none of these can be computed cleanly (caller skips the row).
func effectiveOpening(open, recv, total int) int {
	if total > 0 && (open < 0 || total >= open) {
		return total
	}
	if open >= 0 && recv > 0 {
		return open + recv
	}
	if open >= 0 {
		return open
	}
	return -1
}

// evaluateRowInvariants applies the five domain invariants to one row and
// returns any doubts (auto-fixed or open) it produced. Mutates the row when
// auto-fixing — the caller should record AutoFixed=true doubts as telemetry
// only and surface AutoFixed=false doubts to the C2 popup queue.
func evaluateRowInvariants(row *ExtractedReceiptItem) []CellDoubt {
	if row == nil {
		return nil
	}
	open := -1
	if row.OpeningStock != nil {
		open = *row.OpeningStock
	}
	recv := 0
	if row.Receipt != nil {
		recv = *row.Receipt
	}
	total := 0
	if row.Total != nil {
		total = *row.Total
	}
	close_ := -1
	if row.ClosingStock != nil {
		close_ = *row.ClosingStock
	}
	rate := 0.0
	if row.RatePerUnit != nil {
		rate = *row.RatePerUnit
	}
	amount := 0.0
	if row.Price != nil {
		amount = *row.Price
	}
	sale := row.Quantity
	saleMissing := sale == 0 && row.IsZeroQuantity == false && (row.FieldConfidence == nil || row.FieldConfidence["sale"] < 0.5)

	effOpen := effectiveOpening(open, recv, total)
	if effOpen < 0 {
		return nil // can't reason without effective opening
	}

	autoFloor := invariantAutoFixConfFloor()
	addDoubt := func(d CellDoubt) []CellDoubt { return []CellDoubt{d} }

	// Rule 1: Sale > effective_opening — impossible.
	if sale > 0 && sale > effOpen {
		// Sale digit misread. Suggest from close arithmetic when close is plausible.
		if close_ >= 0 && close_ <= effOpen {
			suggested := effOpen - close_
			s := suggested
			ai := sale
			d := CellDoubt{
				Field: "sale", Rule: "sale_gt_supply",
				AIValue: &ai, Suggested: &s, Confidence: 0.90,
				HumanText: fmt.Sprintf("Brand %q: AI read Sale=%d but only %d were available (Open+Receipt=%d). We think Sale=%d (because Closing=%d).", row.Brand, sale, effOpen, effOpen, suggested, close_),
			}
			if d.Confidence >= autoFloor && suggested >= 0 {
				row.Quantity = suggested
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				row.FieldConfidence["sale"] = 0.95
				row.FieldConfidence["quantity"] = 0.95
				row.Warnings = append(row.Warnings, "invariant_sale_gt_supply:repaired")
				d.AutoFixed = true
			}
			return addDoubt(d)
		}
		// Close not usable — pure doubt for operator.
		ai := sale
		d := CellDoubt{
			Field: "sale", Rule: "sale_gt_supply",
			AIValue: &ai, Confidence: 0,
			HumanText: fmt.Sprintf("Brand %q: AI read Sale=%d but only %d were available. Please correct Sale or Closing.", row.Brand, sale, effOpen),
		}
		row.Warnings = append(row.Warnings, "invariant_sale_gt_supply")
		return addDoubt(d)
	}

	// Rule 2: Closing > effective_opening — impossible (close OR total misread).
	if close_ > effOpen {
		// Repair close from sale (when sale looks reliable).
		if sale >= 0 && sale <= effOpen {
			suggested := effOpen - sale
			if suggested >= 0 {
				s := suggested
				ai := close_
				d := CellDoubt{
					Field: "closing", Rule: "close_gt_supply",
					AIValue: &ai, Suggested: &s, Confidence: 0.85,
					HumanText: fmt.Sprintf("Brand %q: Closing=%d > available=%d (impossible). With Sale=%d, Closing should be %d.", row.Brand, close_, effOpen, sale, suggested),
				}
				if d.Confidence >= autoFloor {
					row.ClosingStock = &suggested
					if row.FieldConfidence == nil {
						row.FieldConfidence = map[string]float64{}
					}
					row.FieldConfidence["closing"] = 0.55 // amber — repaired but operator may want to verify
					row.Warnings = append(row.Warnings, "invariant_close_gt_supply:repaired")
					d.AutoFixed = true
				}
				return addDoubt(d)
			}
		}
		ai := close_
		d := CellDoubt{
			Field: "closing", Rule: "close_gt_supply",
			AIValue: &ai, Confidence: 0,
			HumanText: fmt.Sprintf("Brand %q: Closing=%d but only %d available — please verify the Closing or Total digit.", row.Brand, close_, effOpen),
		}
		row.Warnings = append(row.Warnings, "invariant_close_gt_supply")
		return addDoubt(d)
	}

	// Rule 3: Closing == effective_opening AND Sale > 0 — operator wrote no
	// change but the AI extracted a sale.
	if close_ >= 0 && close_ == effOpen && sale > 0 {
		zero := 0
		ai := sale
		d := CellDoubt{
			Field: "sale", Rule: "no_change_but_sale",
			AIValue: &ai, Suggested: &zero, Confidence: 0.95,
			HumanText: fmt.Sprintf("Brand %q: Opening = Closing = %d (no stock change). AI read Sale=%d — likely a hallucination, suggest Sale=0.", row.Brand, effOpen, sale),
		}
		if d.Confidence >= autoFloor {
			row.Quantity = 0
			row.IsZeroQuantity = true
			if row.FieldConfidence == nil {
				row.FieldConfidence = map[string]float64{}
			}
			row.FieldConfidence["sale"] = 0.95
			row.FieldConfidence["quantity"] = 0.95
			row.Warnings = append(row.Warnings, "invariant_no_change_but_sale:repaired")
			d.AutoFixed = true
		}
		return addDoubt(d)
	}

	// Rule 4: Closing < effective_opening AND Sale != effOpen - close_.
	// Pure stock-balance check. Use revenue (Amount/Rate) as a tiebreaker.
	if close_ >= 0 && close_ < effOpen {
		expected := effOpen - close_
		if sale != expected && abs(sale-expected) >= 1 {
			revenueSale := -1
			if rate >= 50 && rate <= 5000 && amount > 0 {
				revenueSale = int((amount / rate) + 0.5)
			}
			conf := 0.80
			// If revenue independently agrees with the stock-derived value, raise to auto-fix.
			if revenueSale == expected {
				conf = 0.97
			}
			s := expected
			ai := sale
			d := CellDoubt{
				Field: "sale", Rule: "sale_does_not_balance",
				AIValue: &ai, Suggested: &s, Confidence: conf,
				HumanText: fmt.Sprintf("Brand %q: Open+Receipt=%d, Closing=%d → Sale should be %d, AI read %d.", row.Brand, effOpen, close_, expected, sale),
			}
			if d.Confidence >= autoFloor && expected >= 0 {
				row.Quantity = expected
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				row.FieldConfidence["sale"] = 0.95
				row.FieldConfidence["quantity"] = 0.95
				row.Warnings = append(row.Warnings, "invariant_sale_balance:repaired")
				d.AutoFixed = true
			}
			return addDoubt(d)
		}
	}

	// Rule 5: Sale missing entirely but the math gives a clean answer.
	if saleMissing && close_ >= 0 && close_ <= effOpen {
		expected := effOpen - close_
		if expected >= 0 {
			s := expected
			d := CellDoubt{
				Field: "sale", Rule: "missing_sale",
				Suggested: &s, Confidence: 0.90,
				HumanText: fmt.Sprintf("Brand %q: AI couldn't read the Sale cell. Open+Receipt=%d, Closing=%d → Sale=%d.", row.Brand, effOpen, close_, expected),
			}
			if d.Confidence >= autoFloor {
				row.Quantity = expected
				if expected == 0 {
					row.IsZeroQuantity = true
				}
				if row.FieldConfidence == nil {
					row.FieldConfidence = map[string]float64{}
				}
				row.FieldConfidence["sale"] = 0.90
				row.FieldConfidence["quantity"] = 0.90
				row.Warnings = append(row.Warnings, "invariant_missing_sale:repaired")
				d.AutoFixed = true
			}
			return addDoubt(d)
		}
	}

	return nil
}


