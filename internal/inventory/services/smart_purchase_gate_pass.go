package services

import (
	"context"
	"fmt"
	"log"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
	"golang.org/x/sync/errgroup"

	sharedinv "github.com/liquorpro/go-backend/pkg/shared/inventory"
)

// GatePassDutyItem represents an extracted duty item from a gate pass
type GatePassDutyItem struct {
	RowNumber int     `json:"row_number"` // S.No from the gate pass
	BrandName string  `json:"brand_name"`
	Size      string  `json:"size"`
	SizeML    int     `json:"size_ml"`
	Cases     int     `json:"cases"`
	Bottles   int     `json:"bottles"`
	DutyFee   float64 `json:"duty_fee"`
	// v1.0.342 — the dispatched-bottles value EXACTLY as extracted, snapshotted
	// before reconcileGPDispatchBottles rewrites Bottles. The bill↔GP size
	// cross-check needs the original to test whether the bill's size explains
	// the raw read (positive size-bleed evidence) — once reconcile forces
	// Bottles to cases×bpc(gpSize) that signal is gone.
	RawBottles int `json:"raw_bottles,omitempty"`
	// v1.0.212 — additional signals lifted from the UP excise GP form's
	// columns 3, 4, 7. Used as cross-check inputs when pairing bill rows to
	// GP rows: matching sub-type + packaging boosts pairing confidence;
	// mismatched sub-type penalises.
	LiquorType    string `json:"liquor_type,omitempty"`     // "FL" / "CL" / "IMFL"
	LiquorSubType string `json:"liquor_sub_type,omitempty"` // "Whisky" / "Vodka" / "Rum" / "Gin" / "Beer"
	PackagingType string `json:"packaging_type,omitempty"`  // "Glass Bottle" / "Pet Bottle" / "Tetra"
	// v1.0.370 — set by repairGPSizeBleed when this row's Packaging Size column
	// was crossed with an adjacent row (Textract column-bleed on a skewed/
	// 2-line-packaging grid) and either auto-corrected or flagged. Such a row's
	// size+bottles are authoritative-as-repaired: reconcileGPDispatchBottles and
	// the bill size cross-check SKIP it, and the item is forced to NeedsReview.
	SizeBleedSuspect bool `json:"size_bleed_suspect,omitempty"`
	// v1.0.372 — distinguishes the two SizeBleedSuspect outcomes so the operator
	// review message is truthful (the v370 message wrongly said "re-derived to Xml"
	// for rows that were only FLAGGED, never changed):
	//   SizeBleedCorrected — the size was actually changed by the repair (the
	//     deterministic adjacent swap, LLM-corroborated). Message: "corrected to X".
	//   SizeAltML — for a row that was only FLAGGED (engines disagree, can't safely
	//     auto-pick), the conflicting alternative size the other engine read. Lets
	//     the review say "reads Xml but an alternate reading is Yml" so the operator
	//     resolves it in one tap instead of guessing. 0 when no alternative is known.
	SizeBleedCorrected bool `json:"size_bleed_corrected,omitempty"`
	SizeAltML          int  `json:"size_alt_ml,omitempty"`
	// v1.0.238 — 1-based page index. Set during extraction so the Excel
	// export (Track E) can group rows by page and produce a one-sheet-per-
	// page photocopy of what AWS Textract / Claude saw.
	PageIndex int `json:"page_index,omitempty"`
}

// GatePassExtraction wraps the items array plus footer totals for reconciliation.
// The prompt now returns an object (with totals) instead of a bare array so we can
// detect row drops by comparing footer total_cases vs sum of extracted cases.
type GatePassExtraction struct {
	Items        []GatePassDutyItem `json:"items"`
	TotalCases   int                `json:"total_cases"`
	TotalBottles int                `json:"total_bottles"`
	TotalDuty    float64            `json:"total_duty"`
	// v1.0.367 — printed "Total Bulk Litres" footer. A THIRD independent oracle:
	// litres = Σ(bottles × size_ml)/1000, so it validates SIZE specifically (a
	// size error that keeps the bottle count right is invisible to total_bottles
	// but shifts total litres). 0 when the footer isn't on this page.
	TotalLitres  float64            `json:"total_bulk_litres"`
}

// extractDutyFromGatePass is the public dispatcher (v1.0.199 onwards). It picks
// AnalyzeExpense, AnalyzeDocument(TABLES), or the LLM cascade based on the
// per-tenant analyzer flag (same env vars as the bill path:
// STOCK_PURCHASE_ANALYZER + STOCK_PURCHASE_ANALYZER_TENANT_<uuid>). The LLM
// implementation is preserved as the absolute last-resort fallback.
//
// Why a dispatcher instead of inline orchestration: keeping the public
// signature stable means smart_purchase_service.go's goroutine launch
// (line 118) doesn't change, so per-tenant rollouts only need to flip
// the env var.
// gpTablesLooksMangled inspects the rows Textract TABLES produced for the
// gate pass and decides whether the read is trustworthy. v1.0.340 (mangled-GP
// fallback guard).
//
// Today the dispatcher only falls through to the LLM when TABLES returns an
// error or ZERO rows. But Textract can return the WRONG number of nonzero rows
// — column-slip and multi-line wrap bleed produce numeric/single-char brand
// cells and rows with no size and no dispatched bottles (the exact failure the
// old "SONU SINGH FL-2 60% mangled" note described). Those non-zero-but-garbage
// reads slipped through and shipped. This guard catches them: if too large a
// fraction of rows look garbled, we treat the whole page as mis-parsed and let
// the LLM re-read it (the LLM is deterministic on dense tables and was the
// pre-v339 default, so this is a safe floor — never worse than before).
//
// A row is "garbled" when EITHER:
//   - the brand has fewer than 3 letters (empty, all-digits, punctuation, or a
//     stray single char — never a real liquor brand), OR
//   - it carries no size AND no dispatched bottles (a dropped/column-slipped
//     row that contributes nothing).
//
// Threshold 0.40 mirrors the bill-side drop-ratio gate in
// textract_purchase_pipeline.go ("if >40% of rows look like junk the page
// itself was mis-parsed"). Returns (mangled, human-readable reason).
func gpTablesLooksMangled(items []GatePassDutyItem) (bool, string) {
	if len(items) == 0 {
		return true, "zero rows"
	}
	bad := 0
	for _, it := range items {
		letters := 0
		for _, r := range strings.TrimSpace(it.BrandName) {
			if unicode.IsLetter(r) {
				letters++
			}
		}
		brandGarbled := letters < 3
		numbersDropped := it.SizeML == 0 && it.Bottles == 0
		if brandGarbled || numbersDropped {
			bad++
		}
	}
	ratio := float64(bad) / float64(len(items))
	if ratio > 0.40 {
		return true, fmt.Sprintf("%d/%d rows garbled (%.0f%% > 40%% threshold)", bad, len(items), ratio*100)
	}
	return false, ""
}

// reconcileGPDispatchBottles enforces the full-case dispatch invariant on the
// gate pass's "No of Bottles Dispatched" column. v1.0.340.
//
// WHY: the rightmost dispatched-bottles cell is the most bleed-prone column in
// the dense UP Excise GP grid — Textract routinely reads it from the adjacent
// row. Real-data (FM Tower job 52714ffc): the 90ml "Seagrams Royal Stag
// Superior Whisky" row prints 1 case × 96 bottles (90ml packs 96/case) but
// Textract read 48 — the value from the 180ml Royal Stag row directly below it.
// This ran ONLY in the LLM path before; chhotu's GP uses the Textract TABLES
// path (GP_FORCE_LLM=0), which had no case-math reconciliation, so the 48
// shipped uncorrected.
//
// PRINCIPLE: the Size column ("90"/"180"/"375"/"750" — short, well-separated,
// rarely misread) and the Cases column (small integer) are far more reliable
// than the bleed-prone Bottles-Dispatched cell. These GPs dispatch WHOLE cases
// (every row on the real GP is exactly cases×bpc), so for a known standard size
// bottles MUST equal cases × bpc.
//
// Corrections (size known, cases ≥ 1):
//
//	bottles == 0          → cases×bpc  (dispatched column dropped)
//	bottles  < cases×bpc  → cases×bpc  (under-read / adjacent-row bleed, e.g. 48←96)
//	bottles  > cases×bpc  → keep + warn (ambiguous: cases may itself be under-read)
//
// Idempotent — once bottles == cases×bpc nothing changes — so it is safe to run
// on every path (TABLES / Expense / LLM) without double-correcting.
func reconcileGPDispatchBottles(items []GatePassDutyItem) int {
	fixed := 0
	for i := range items {
		it := &items[i]
		if it.SizeBleedSuspect {
			// v1.0.370 — size was column-bleed-corrected from an adjacent row;
			// its cases/bottles are the printed truth and the pack may be
			// non-standard (e.g. 180 Tetra = 24/case, not the 48 glass uses).
			// Pack-math does not apply — leave the bottles exactly as read.
			continue
		}
		bpc, ok := StandardCaseSizes[it.SizeML]
		if !ok || bpc <= 1 || it.Cases <= 0 {
			continue // non-IMFL / unknown size / loose-only row — no case math
		}
		expected := it.Cases * bpc
		switch {
		case it.Bottles == expected:
			// already consistent — nothing to do
		case it.Bottles == 0:
			log.Printf("  GP reconcile: %s %dML bottles 0→%d (dispatched column dropped; %d×%d/case)",
				it.BrandName, it.SizeML, expected, it.Cases, bpc)
			it.Bottles = expected
			fixed++
		case it.Bottles < expected:
			log.Printf("  GP reconcile: %s %dML bottles %d→%d (under-read of dispatched col / adjacent-row bleed; %d×%d/case)",
				it.BrandName, it.SizeML, it.Bottles, expected, it.Cases, bpc)
			it.Bottles = expected
			fixed++
		default: // bottles > expected — don't guess, cases may be the misread one
			log.Printf("  GP reconcile: WARN %s %dML bottles=%d but %d×%d/case=%d (cases may be under-read; kept)",
				it.BrandName, it.SizeML, it.Bottles, it.Cases, bpc, expected)
		}
	}
	if fixed > 0 {
		log.Printf("SmartPurchase GP reconcile: corrected dispatched bottles on %d row(s) via full-case invariant", fixed)
	}
	return fixed
}

// extractDutyFromGatePass is the public entry point. It runs the path-specific
// extractor (TABLES / Expense / LLM) and then applies reconcileGPDispatchBottles
// to EVERY result — v1.0.340, so the full-case invariant fix reaches the
// Textract TABLES path chhotu uses, not just the LLM path that already had it.
func (s *SmartPurchaseService) extractDutyFromGatePass(ctx context.Context, images []SmartPurchaseImage, userID string) ([]GatePassDutyItem, error) {
	// v1.0.370 — stamp the size-bleed-repair gate so the hybrid merge (several
	// calls down, with no userID in scope) can run it for the test user / when
	// globally enabled.
	if gpBleedRepairEnabled(userID) {
		ctx = withGPBleedRepair(ctx, true)
	}
	if gpSizeReReadEnabled(userID) {
		ctx = withGPSizeReRead(ctx, true)
	}
	items, err := s.extractDutyFromGatePassInner(ctx, images, userID)
	if err == nil && len(items) > 0 {
		// Snapshot the as-extracted dispatched bottles BEFORE reconcile rewrites
		// them, so the downstream bill↔GP size cross-check can use the raw read.
		for i := range items {
			items[i].RawBottles = items[i].Bottles
		}
		reconcileGPDispatchBottles(items)
	}
	return items, err
}

// gpFastLLMCtxKey marks a context so the per-page LLM cascade accepts the FIRST
// successful backend instead of escalating through gemini→claude→openai on the
// footer-truncation heuristic. The hybrid uses it because Textract backstops
// structure/completeness — the LLM only needs to supply NAMES, so the 3-backend
// cascade (real-data: ~22s wasted when a page's footer carries the GRAND total
// and its own rows look "truncated") is pure latency.
type gpFastLLMCtxKey struct{}

func withGPFastLLM(ctx context.Context) context.Context {
	return context.WithValue(ctx, gpFastLLMCtxKey{}, true)
}
func gpFastLLM(ctx context.Context) bool {
	v, _ := ctx.Value(gpFastLLMCtxKey{}).(bool)
	return v
}

// gpFooterVerdict carries the gate pass's PRINTED footer totals back UP from the
// hybrid extractor (deep in the call stack, no job result in scope) to the
// service level, so the job can emit a "footer can't be reconciled" review flag.
// v1.0.385 — the never-silently-wrong guarantee: when no read reconciles to the
// printed totals (a genuinely bad extraction the footer-arbitration could not
// fix), the operator must be told rather than shown unverified quantities. The
// caller allocates it and reads it after extraction; the hybrid fills it in.
// Written once inside the GP goroutine and read after that goroutine joins, so
// the channel close provides the happens-before — no lock needed.
type gpFooterVerdict struct {
	known         bool
	footerCases   int
	footerBottles int
	footerLitres  float64
}

type gpFooterVerdictCtxKey struct{}

func withGPFooterVerdict(ctx context.Context, fv *gpFooterVerdict) context.Context {
	return context.WithValue(ctx, gpFooterVerdictCtxKey{}, fv)
}
func gpFooterVerdictFrom(ctx context.Context) *gpFooterVerdict {
	fv, _ := ctx.Value(gpFooterVerdictCtxKey{}).(*gpFooterVerdict)
	return fv
}

// extractDutyFromGatePassHybrid — v1.0.362. Textract AnalyzeDocument(TABLES) for
// the deterministic numeric columns, then the vision-LLM (in fast/no-cascade mode)
// for the brand names it reads ~100% where Textract smears the wrapped column.
// mergeGPEnsemble uses the LLM as the row spine + overlays Textract numbers. The
// fast-LLM mode (accept the first backend, skip the 3-backend truncation cascade —
// Textract backstops completeness) is the main latency win. Run sequentially: the
// two extractors share clients on s/s.ocr and are NOT safe to run concurrently.
// Degrades safely: TABLES empty → LLM rows (names+numbers); LLM empty → Textract.
func (s *SmartPurchaseService) extractDutyFromGatePassHybrid(ctx context.Context, images []SmartPurchaseImage) ([]GatePassDutyItem, error) {
	textractRows, terr := s.extractDutyFromGatePassTables(ctx, images)
	llmEx, lerr := s.extractDutyFromGatePassLLMEx(withGPFastLLM(ctx), images)
	var llmRows []GatePassDutyItem
	if llmEx != nil {
		llmRows = llmEx.Items
	}

	if lerr != nil || len(llmRows) == 0 {
		if terr != nil || len(textractRows) == 0 {
			return nil, fmt.Errorf("gate-pass hybrid: both engines failed (textract=%v llm=%v)", terr, lerr)
		}
		log.Printf("SmartPurchase GP hybrid: LLM empty/failed (%v) — keeping Textract rows", lerr)
		return textractRows, nil
	}
	if terr != nil || len(textractRows) == 0 {
		log.Printf("SmartPurchase GP hybrid: TABLES empty/failed (%v) — using LLM rows (names+numbers)", terr)
		return llmRows, nil
	}
	merged := mergeGPEnsemble(textractRows, llmRows)
	// v1.0.370 — repair adjacent Size+Packaging column swaps (Textract cell-bleed
	// on the skewed grid) using the LLM read as corroboration. merged[i] aligns
	// with llmRows[i] (the merge emits one row per LLM row, in order).
	if gpBleedRepairFromCtx(ctx) {
		repairGPSizeBleed(merged, llmRows)
		// v1.0.374 — for any row left FLAGGED (engines disagree on a standard size,
		// no safe data-only pick), re-read its isolated pixels and auto-correct when
		// confident. Closes the row-8 "Verve Cranberry" 180-vs-375 gap.
		if gpSizeReReadFromCtx(ctx) {
			s.reReadFlaggedGPSizes(ctx, images, merged)
		}
	}
	// v1.0.366 — FOOTER-ARBITRATED OVERLAY GUARD (final arbiter). On a skewed
	// multi-page scan the Textract overlay can bleed a row's size/cases/bottles
	// across adjacent rows (chhotu job 0673458a: "M2 Magic Moments Superior" 180ml
	// 2×96 became a phantom 375ml 1×24, and the column sum jumped 1380→1500). The
	// gate pass PRINTS its own dispatched totals; the raw LLM read reconciles to
	// them exactly. If the overlay broke that reconciliation, the LLM read is the
	// trustworthy one — revert the corrupted rows to it. The printed footer is the
	// judge, so this never guesses.
	merged = reconcileMergedAgainstFooter(merged, llmRows, llmEx)
	// v1.0.385 — hand the printed footer totals up to the service so it can flag
	// the job for review if the final rows still can't reconcile to them (the
	// never-silently-wrong net for extractions the arbitration could not fix).
	if fv := gpFooterVerdictFrom(ctx); fv != nil && llmEx != nil && llmEx.TotalBottles > 0 {
		fv.known = true
		fv.footerCases = llmEx.TotalCases
		fv.footerBottles = llmEx.TotalBottles
		fv.footerLitres = llmEx.TotalLitres
	}
	return merged, nil
}

// reconcileMergedAgainstFooter reverts overlay-corrupted rows to the LLM read when
// the gate pass's printed footer total proves the merge is wrong and the LLM read
// is right. Rows align 1:1 with llmRows (the merge + in-place repair/re-read keep
// one row per LLM row, in order). Pure + deterministic. No-op (returns merged
// unchanged) unless: a footer total is known, the merged sum is OFF the footer,
// AND the LLM sum reconciles to it — i.e. only when the footer unambiguously
// indicts the overlay. v1.0.366.
func reconcileMergedAgainstFooter(merged, llmRows []GatePassDutyItem, footer *GatePassExtraction) []GatePassDutyItem {
	if footer == nil || footer.TotalBottles <= 0 || len(merged) != len(llmRows) {
		return merged
	}
	sum := func(rows []GatePassDutyItem) (cases, bottles int, litres float64) {
		for _, r := range rows {
			cases += r.Cases
			bottles += r.Bottles
			litres += float64(r.Bottles) * float64(r.SizeML) / 1000.0
		}
		return
	}
	mergedCases, mergedBottles, mergedLitres := sum(merged)
	llmCases, llmBottles, llmLitres := sum(llmRows)
	tolB := bpcTolerance(merged)
	// THREE independent printed oracles validate the read: cases, bottles, AND
	// bulk litres. litres = Σ(bottles×size)/1000, so it validates SIZE specifically
	// — a size misread that preserves the bottle count (e.g. 180↔375 with the wrong
	// pack) is invisible to total_bottles but shifts the litres total by cases'
	// worth. Requiring all three to match the footer makes "trust this read"
	// essentially unfalsifiable; then the merge/repair/re-read drifts (which can
	// COMPENSATE so the merged totals still look fine — job 0673458a: row 17 lost
	// 72 btl while others gained ~72) are reverted to the footer-proven read. The
	// litres + cases checks degrade gracefully to no-op when the footer omits them.
	absF := func(x float64) float64 {
		if x < 0 {
			return -x
		}
		return x
	}
	tolL := footer.TotalLitres * 0.02
	if tolL < 5 {
		tolL = 5
	}
	casesOK := footer.TotalCases <= 0 || absInt(footer.TotalCases-llmCases) <= 1
	bottlesOK := absInt(footer.TotalBottles-llmBottles) <= tolB
	litresOK := footer.TotalLitres <= 0 || absF(footer.TotalLitres-llmLitres) <= tolL
	llmReconciles := casesOK && bottlesOK && litresOK
	log.Printf("SmartPurchase GP: footer-arbitration — footer %dc/%db/%.1fL | merged %dc/%db/%.1fL | llm %dc/%db/%.1fL | tolB=%d tolL=%.1f | cOK=%v bOK=%v lOK=%v → reconciles=%v | rows=%d",
		footer.TotalCases, footer.TotalBottles, footer.TotalLitres,
		mergedCases, mergedBottles, mergedLitres,
		llmCases, llmBottles, llmLitres, tolB, tolL, casesOK, bottlesOK, litresOK, llmReconciles, len(merged))
	if !llmReconciles {
		return merged // read not footer-proven on all available totals; keep the merge
	}
	reverted := 0
	for i := range merged {
		if merged[i].SizeML != llmRows[i].SizeML ||
			merged[i].Cases != llmRows[i].Cases ||
			merged[i].Bottles != llmRows[i].Bottles ||
			merged[i].DutyFee != llmRows[i].DutyFee {
			merged[i].SizeML = llmRows[i].SizeML
			merged[i].Size = llmRows[i].Size
			merged[i].Cases = llmRows[i].Cases
			merged[i].Bottles = llmRows[i].Bottles
			merged[i].RawBottles = llmRows[i].Bottles
			merged[i].DutyFee = llmRows[i].DutyFee
			// Clear any stale bleed flags — the LLM read is now authoritative.
			merged[i].SizeBleedSuspect = false
			merged[i].SizeAltML = 0
			reverted++
		}
	}
	if reverted > 0 {
		log.Printf("SmartPurchase GP: footer-arbitrated revert — LLM read %dc/%db reconciles to printed footer %dc/%db → reverted %d drifted row(s) to the LLM read",
			llmCases, llmBottles, footer.TotalCases, footer.TotalBottles, reverted)
	}
	return merged
}

func (s *SmartPurchaseService) extractDutyFromGatePassInner(ctx context.Context, images []SmartPurchaseImage, userID string) ([]GatePassDutyItem, error) {
	if len(images) == 0 {
		return nil, fmt.Errorf("no gate pass images provided")
	}

	// v1.0.360 — HYBRID: Textract numbers + vision-LLM brand names. Owner
	// directive after raw-Textract proof that TABLES smears the wrapped brand
	// column but reads the numbers perfectly. Dark by default; on for the tester.
	if gpHybridNamesEnabled(userID) {
		log.Printf("SmartPurchase GP: HYBRID mode (Textract numbers + LLM brand names) for user %s", userID)
		return s.extractDutyFromGatePassHybrid(ctx, images)
	}

	// v1.0.211 — separate analyzer flag for the GATE PASS path. Real-data
	// finding (chhotu's 2026-05-08 bill, job d1c3020b): AnalyzeExpense on the
	// UP Excise dispatch form returns ~70% malformed rows (size_ml=0, dupe
	// brand text, zero quantities) because it's an INVOICE-shaped extractor
	// and the GP is a multi-column government form. Tushar's directive is
	// "use Gemini for matching fallback only" — but the GP is the authoritative
	// SOURCE of canonical brand names, so getting it RIGHT is high-leverage:
	// every paired GP row eliminates a Gemini call downstream.
	//
	// Default for GP changed: prefer LLM (existing extractDutyFromGatePassLLM
	// path is well-tested). Bill stays on Textract via STOCK_PURCHASE_ANALYZER
	// because bill formats vary across vendors and Textract Expense+Tables
	// handles them well at ~90% recall. The two paths are now independent.
	//
	// Override:
	//   STOCK_PURCHASE_GP_ANALYZER=expense   → revert GP to Textract
	//   STOCK_PURCHASE_GP_ANALYZER=llm       → explicit LLM (default)
	//   STOCK_PURCHASE_GP_ANALYZER unset     → falls through to legacy
	//     STOCK_PURCHASE_ANALYZER, then to "llm" if THAT is also unset.
	// v1.0.238 — force-LLM short-circuit. When SMART_PURCHASE_GP_FORCE_LLM=1
	// (global) or SMART_PURCHASE_GP_FORCE_LLM_TENANT_<uuid>=1 the dispatcher
	// skips Textract entirely and goes straight to Claude vision. Used for
	// tenants whose Excise GP format consistently fragments under Textract
	// (real-data: chhotu's SONU SINGH FL-2 dense 28-row pages, 60% of rows
	// mangled by multi-line wrap bleed in raw Textract output, fixed by
	// Claude vision at 100%). Setting force-LLM also drives the training
	// corpus capture (Track C) so we collect labeled crops to eventually
	// train a local model and reclaim the Textract cost path.
	if strings.EqualFold(envOrEmpty("SMART_PURCHASE_GP_FORCE_LLM"), "1") {
		log.Printf("SmartPurchase GP: SMART_PURCHASE_GP_FORCE_LLM=1 — skipping Textract, using LLM directly")
		return s.extractDutyFromGatePassLLM(ctx, images)
	}

	gpModeRaw := strings.ToLower(strings.TrimSpace(envOrEmpty("STOCK_PURCHASE_GP_ANALYZER")))
	if gpModeRaw == "" {
		gpModeRaw = strings.ToLower(strings.TrimSpace(envOrEmpty("STOCK_PURCHASE_ANALYZER")))
	}
	mode := normalizeAnalyzerName(gpModeRaw)
	if mode == "" {
		mode = "llm"
	}
	log.Printf("SmartPurchase GP: dispatcher selected mode=%q (raw=%q)", mode, gpModeRaw)

	if mode == "tables" {
		items, err := s.extractDutyFromGatePassTables(ctx, images)
		if err == nil && len(items) > 0 {
			// v1.0.340 — mangled-GP fallback guard. Don't trust a nonzero-but-
			// garbage read; only return TABLES rows when they look clean.
			if mangled, why := gpTablesLooksMangled(items); mangled {
				log.Printf("SmartPurchase GP: AnalyzeDocument(TABLES) produced %d rows but read looks MANGLED (%s) — falling through to LLM", len(items), why)
			} else {
				log.Printf("SmartPurchase GP: AnalyzeDocument(TABLES) produced %d clean rows — skipping LLM", len(items))
				return items, nil
			}
		} else if err != nil {
			log.Printf("SmartPurchase GP: AnalyzeDocument(TABLES) failed (%v) — falling through to LLM", err)
		} else {
			log.Printf("SmartPurchase GP: AnalyzeDocument(TABLES) returned 0 rows — falling through to LLM")
		}
	}

	if mode == "expense" {
		items, err := s.extractDutyFromGatePassTextract(ctx, images)
		if err == nil && len(items) > 0 {
			log.Printf("SmartPurchase GP: AnalyzeExpense produced %d rows — skipping LLM", len(items))
			return items, nil
		}
		if err != nil {
			log.Printf("SmartPurchase GP: AnalyzeExpense failed (%v) — falling through to LLM", err)
		} else {
			log.Printf("SmartPurchase GP: AnalyzeExpense returned 0 rows — falling through to LLM")
		}
		// fall through to LLM (preserves today's 48-62% recall as a floor)
	}

	return s.extractDutyFromGatePassLLM(ctx, images)
}

// gpColumnDefault is the canonical UP Excise GP column layout. Used as the
// fallback when a page's header row doesn't carry header text (real-data:
// pages 2+ of multi-page GPs typically don't repeat the header). Column
// indices are 1-indexed, matching Textract's RowIndex/ColumnIndex.
//
//	1: S.No
//	2: Brand
//	3: Liquor Type
//	4: Liquor Sub Type
//	5: Description
//	6: Packaging Size
//	7: Packaging Type
//	8: No of Cases Requested
//	9: No of Bottles Requested
//	10: No of Cases Dispatched
//	11: No of Bottles Dispatched
//	12: Duty Fee
var gpColumnDefault = gpColumnIndices{
	serial:            1,
	brand:             2,
	liquorType:        3,
	liquorSub:         4,
	description:       5,
	size:              6,
	packagingType:     7,
	casesRequested:    8,
	bottlesRequested:  9,
	casesDispatched:   10,
	bottlesDispatched: 11,
	duty:              12,
}

// v1.0.212 — GP-specific Textract TABLES extractor.
//
// Why a dedicated path:
//   AnalyzeExpense (the prior GP default) is invoice-shaped. It flattens the
//   UP Excise dispatch form's 12 columns into "description + amount" and
//   loses the Packaging Size column entirely (most rows came back with
//   size_ml=0). AnalyzeDocument(TABLES) preserves the cell grid; we then
//   detect column indices from the header row's text (S.No / Brand /
//   Liquor Sub Type / Packaging Size / Cases Dispatched / Bottles Dispatched /
//   Duty Fee) and read each row's cells from the right columns.
//
// Independent from runTextractInvoicePage on the bill side because the GP's
// 12 columns are different from the bill's 7-9 columns — sharing a hardcoded
// column-index table would be fragile.
func (s *SmartPurchaseService) extractDutyFromGatePassTables(ctx context.Context, images []SmartPurchaseImage) ([]GatePassDutyItem, error) {
	client, err := newTextractPurchaseClient(ctx)
	if err != nil {
		return nil, err
	}
	startedAt := time.Now()
	pages := make([][]GatePassDutyItem, len(images))

	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(textractPageConcurrency())
	deskew := newDeskewClient()
	for i, img := range images {
		i, img := i, img
		if len(img.Data) == 0 {
			continue
		}
		g.Go(func() error {
			// v1.0.237 — STRIP-SPLIT preprocessing. Textract's
			// AnalyzeDocument(TABLES) fragments rows when a single page
			// has >20-25 rows (real-data: chhotu DocScanner 28-row GP
			// page split rows into multi-line wraps that Textract assigned
			// to adjacent cells). Fix: split each GP image vertically into
			// 2 strips with 30% overlap. Each strip has ≤14 rows ⇒ Textract
			// handles cleanly. Merge strip results by printed S.No, dedupe
			// overlap rows. Cost: 2× Textract calls/page (still 100× cheaper
			// than Claude vision). Replaces v235's dual-variant merge (which
			// only changed JPEG quality, not row density).
			preFull := prepareTextractImageVariant(img.Data, 0)
			dctx, dcancel := context.WithTimeout(gctx, 3*time.Second)
			desk := deskew.Deskew(dctx, preFull)
			dcancel()
			if len(desk) > 0 && len(desk) != len(preFull) {
				preFull = desk
			}
			pctx, cancel := context.WithTimeout(gctx, 120*time.Second)
			defer cancel()

			// Split into N strips. N=2 with 30% overlap empirically gives
			// 100% on 28-row pages while only doubling cost.
			strips, splitErr := splitImageVerticallyOverlap(preFull, 2, 0.30)
			if splitErr != nil || len(strips) <= 1 {
				log.Printf("SmartPurchase GP page %d: split failed (%v) — running Textract on full image", i+1, splitErr)
				strips = [][]byte{preFull}
			} else {
				log.Printf("SmartPurchase GP page %d: split into %d overlapping strips", i+1, len(strips))
			}

			stripRows := make([][]GatePassDutyItem, len(strips))
			stripErrs := make([]error, len(strips))
			vg, vctx := errgroup.WithContext(pctx)
			for sIdx := range strips {
				sIdx := sIdx
				vg.Go(func() error {
					stripRows[sIdx], stripErrs[sIdx] = runTextractGatePassPage(vctx, client, strips[sIdx], i+1)
					return nil
				})
			}
			_ = vg.Wait()

			// Merge strip results by S.No. Walk strips in order, dedupe
			// rows that the operator already saw on the previous strip
			// (overlap region). Track first-seen-wins to keep the strip
			// where the row's bounding box was furthest from the edge.
			//
			// v1.0.237-r2 — when S.No column wasn't detected (RowNumber=0),
			// fall back to dedup by (brand_canonical, size_ml) tuple. Real-
			// data: Textract returns RowNumber=0 for ~80% of rows on dense
			// GP pages (column map serial=0 in logs). Without secondary
			// dedup, overlap rows from strips 1+2 appear twice.
			rows := []GatePassDutyItem{}
			seen := make(map[int]int)    // S.No → index in rows (when >0)
			seenKey := make(map[string]int) // (brand_norm|size) → index (when S.No=0)
			normalize := func(s string) string {
				out := make([]byte, 0, len(s))
				for _, r := range strings.ToLower(s) {
					if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
						out = append(out, byte(r))
					}
				}
				return string(out)
			}
			merged := 0
			for sIdx, srows := range stripRows {
				if stripErrs[sIdx] != nil {
					log.Printf("SmartPurchase GP page %d strip %d: %v", i+1, sIdx+1, stripErrs[sIdx])
					continue
				}
				for _, r := range srows {
					existIdx := -1
					if r.RowNumber > 0 {
						if idx, ok := seen[r.RowNumber]; ok {
							existIdx = idx
						}
					}
					if existIdx == -1 {
						bnorm := normalize(r.BrandName)
						if len(bnorm) >= 6 { // brand text needs to be substantive
							key := fmt.Sprintf("%s|%d", bnorm, r.SizeML)
							if idx, ok := seenKey[key]; ok {
								existIdx = idx
							}
						}
					}
					if existIdx >= 0 {
						ex := rows[existIdx]
						exScore := scoreGPRowCompleteness(ex)
						newScore := scoreGPRowCompleteness(r)
						if newScore > exScore {
							rows[existIdx] = r
						}
						merged++
						continue
					}
					rows = append(rows, r)
					if r.RowNumber > 0 {
						seen[r.RowNumber] = len(rows) - 1
					}
					bnorm := normalize(r.BrandName)
					if len(bnorm) >= 6 {
						seenKey[fmt.Sprintf("%s|%d", bnorm, r.SizeML)] = len(rows) - 1
					}
				}
			}
			log.Printf("SmartPurchase GP page %d (strip-merge): %d strips, %d unique rows (merged %d dupes)",
				i+1, len(strips), len(rows), merged)
			pre := preFull
			// v1.0.238 — fragmentation-aware auto-fallback to LLM. After
			// Textract+strip-merge, score the rows for multi-line-wrap
			// fragmentation. If level=="fragmented", re-run THIS page via
			// extractDutyFromGatePassLLM (Claude vision) and replace the
			// rows. Real-data trigger: chhotu DocScanner page-0005 (28
			// rows) had 17 of 28 brand cells mangled by Textract before
			// strip-merge could fix them. Claude gets 100% on the same
			// image. Cost per submission: cheap pages stay on Textract
			// (~₹0.05); dense pages auto-fall to Claude (~₹3). Average
			// ~₹1-2/submission, guarantees 100% accuracy.
			if len(rows) > 0 {
				level, reasons := gpFragmentationScore(rows)
				if level == "fragmented" {
					log.Printf("SmartPurchase GP page %d (fragmentation=%s): %v — auto-falling back to LLM",
						i+1, level, reasons)
					rescued, rerr := s.extractDutyFromGatePassLLM(gctx, []SmartPurchaseImage{img})
					if rerr != nil {
						log.Printf("SmartPurchase GP page %d: LLM auto-fallback failed: %v — keeping Textract rows", i+1, rerr)
					} else if len(rescued) > 0 {
						log.Printf("SmartPurchase GP page %d (LLM auto-rescue): %d rows replace %d Textract rows",
							i+1, len(rescued), len(rows))
						for j := range rescued {
							rescued[j].PageIndex = i + 1
						}
						pages[i] = rescued
						return nil
					}
				} else if level == "suspect" {
					log.Printf("SmartPurchase GP page %d (fragmentation=%s): %v — keeping Textract but flagged",
						i+1, level, reasons)
				}
			}
			// v1.0.213 — per-page LLM fallback. When Textract TABLES returns
			// 0 rows for a specific page (real-data: chhotu's GP page 2 had
			// only "Bottle" text — Textract failed to detect the table),
			// run the LLM cascade on JUST that page. Mixes Textract +
			// LLM at page granularity instead of all-or-nothing. Keeps
			// Textract primary; only spends LLM cost where actually needed.
			if len(rows) == 0 {
				log.Printf("SmartPurchase GP page %d (TABLES): 0 rows — falling back to LLM for this page only", i+1)
				rescued, rerr := s.extractDutyFromGatePassLLM(gctx, []SmartPurchaseImage{img})
				if rerr != nil {
					log.Printf("SmartPurchase GP page %d: LLM fallback also failed: %v", i+1, rerr)
				} else if len(rescued) > 0 {
					log.Printf("SmartPurchase GP page %d (LLM rescue): %d rows", i+1, len(rescued))
					for j := range rescued {
						rescued[j].PageIndex = i + 1
					}
					pages[i] = rescued
					return nil
				}
			}
			// v1.0.228 P1 — CV-sidecar /sheet row re-anchoring. When enabled
			// (GP_CV_SHEET=1), call cv-sidecar to get pixel-detected row
			// bands. If CV detected more rows than Textract, synthesize
			// placeholders for the eaten rows — the downstream math gate
			// (P4) + cross-doc rescue fill the placeholder qty from
			// Bill+Purcha. Real-data fix: chhotu gp2 serial 27 Rockford
			// 180ml that Textract collapsed into the adjacent row.
			//
			// Best-effort: any cv-sidecar failure (timeout, ok=false,
			// non-200) falls back to plain Textract row indices. Never
			// blocks the extraction path.
			if gpCVSheetEnabled() && len(rows) > 0 {
				cvCtx, cvCancel := context.WithTimeout(gctx, 8*time.Second)
				cv, cvErr := fetchGPSheetFromCV(cvCtx, pre)
				cvCancel()
				if cvErr == nil && cv != nil {
					before := len(rows)
					rows = applyCVGridToGPRows(rows, cv)
					if len(rows) != before {
						log.Printf("SmartPurchase GP page %d (P1 CV): rows %d → %d (cv detected %d non-blank rows)",
							i+1, before, len(rows), len(cv.Rows))
					}
				} else if cvErr != nil {
					log.Printf("SmartPurchase GP page %d (P1 CV): /sheet failed (non-fatal): %v", i+1, cvErr)
				}
			}
			// v1.0.238 — stamp 1-based page index on every row before
			// stuffing into the per-page slot. Used by Excel export (Track E)
			// to group rows back into per-page sheets after the flatten step.
			for j := range rows {
				rows[j].PageIndex = i + 1
			}
			pages[i] = rows
			log.Printf("SmartPurchase GP page %d (TABLES): %d rows", i+1, len(rows))
			return nil
		})
	}
	_ = g.Wait()

	// Flatten + sequential row-numbering with cumulative-vs-restart detection.
	var allItems []GatePassDutyItem
	for _, p := range pages {
		if len(p) == 0 {
			continue
		}
		minNew, maxExisting := -1, 0
		for _, ex := range allItems {
			if ex.RowNumber > maxExisting {
				maxExisting = ex.RowNumber
			}
		}
		for _, it := range p {
			if it.RowNumber > 0 && (minNew == -1 || it.RowNumber < minNew) {
				minNew = it.RowNumber
			}
		}
		if minNew != -1 && minNew <= maxExisting {
			offset := maxExisting
			for j := range p {
				p[j].RowNumber += offset
			}
		}
		allItems = append(allItems, p...)
	}

	// v1.0.227-r5 — fragment-merge post-pass.
	//
	// Textract TABLES occasionally splits a brand name across two grid rows
	// when the printed line wraps over a faint horizontal grid edge — e.g.
	// "STERLING RESERVE B-7 SPECIAL BLE" on row N and "NDED SCOTCH WHISKY"
	// on row N+1 (real-data: chhotu gp2 page). The fragment row is missing
	// its size/cases/bottles cells; the previous row's brand text is
	// truncated. We detect fragments (no size, no cases, brand looks like
	// a continuation) and concatenate them back to the previous row.
	allItems = mergeGPBrandFragments(allItems)

	// v1.0.228 P4 — math-gate consensus. Zero-cost pure arithmetic that
	// fixes OCR slips on cases/bottles cells by leveraging the pack-size
	// identity (cases × pack = bottles). Default ON; flip via GP_MATH_GATE=0.
	// Catches real-data classes:
	//   • cases read as 1 when bottles=96 at 180ml → derive cases=2 (96/48)
	//   • bottles read as 48 when cases=2 at 180ml → derive bottles=96 (2*48)
	//   • one cell missing entirely → derive from the other + pack size
	if fixed := applyGPMathGate(allItems); fixed > 0 {
		log.Printf("SmartPurchase GP: math-gate corrected %d row(s)", fixed)
	}

	// v1.0.228 P4 — invariant gate (serial monotonic). Logs detected
	// gaps for telemetry; CV grid (P1) handles synthesis.
	if gaps := applyGPInvariantGate(allItems); len(gaps) > 0 {
		log.Printf("SmartPurchase GP: serial gaps present (P1 CV grid should have filled): %v", gaps)
	}

	log.Printf("SmartPurchase GP: AnalyzeDocument(TABLES) path produced %d rows in %dms",
		len(allItems), time.Since(startedAt).Milliseconds())
	return allItems, nil
}

// gpFragmentationScore inspects Textract-extracted GP rows for the classic
// multi-line-wrap-bleed signature that Textract produces on dense Excise
// forms. Returns a level (clean | suspect | fragmented) plus the matched
// reasons.
//
// Triggers (any of these on ≥30% of rows flips to "fragmented"):
//   - Brand contains ≥2 distinct liquor-class keywords (e.g. "WHISKY" and
//     "VODKA" in the same cell — impossible on a clean row)
//   - Brand length > 120 chars (clean canonical brand text rarely exceeds 90)
//   - Brand has an interior 1-2 digit token NOT followed by ML/PM/Y/YR
//     (row-number leak from adjacent row's S.No column)
//   - Brand starts with a closing liquor-ender (Whisky/Vodka/Premium/etc.)
//     followed by an ALL-CAPS token (tail of previous row bled in)
//   - S.No column blank on >25% of rows (column-detection failed)
//
// Real-data calibration: chhotu's DocScanner page-0005 (28 rows) triggered
// 17 fragmented rows = 61% → "fragmented". Page-0004 (21 rows) triggered 0
// → "clean". The threshold (≥30%) sits between to avoid false-positives on
// edge-of-clean pages.
func gpFragmentationScore(rows []GatePassDutyItem) (level string, reasons []string) {
	if len(rows) == 0 {
		return "clean", nil
	}
	liquorClassRE := regexp.MustCompile(`(?i)\b(whisky|whiskey|vodka|rum|scotch|gin|brandy|wine)\b`)
	tailEnders := map[string]bool{
		"WHISKY": true, "WHISKEY": true, "VODKA": true, "RUM": true,
		"PREMIUM": true, "RESERVE": true, "LABEL": true, "SCOTCH": true,
		"ORIGINAL": true, "BLENDED": true,
	}
	interiorDigit := regexp.MustCompile(`\b([A-Za-z]{3,})\s+(\d{1,2})\s+([A-Za-z]{3,})\b`)
	keepAfterDigit := regexp.MustCompile(`(?i)\b\d{1,2}\s+(pm|ml|y|yr|yrs|year|years|l|ltr|cl)\b`)

	fragmented := 0
	snoBlank := 0
	multiClass := 0
	overLong := 0
	rowNumLeak := 0
	tailBleed := 0

	for _, r := range rows {
		b := strings.TrimSpace(r.BrandName)
		if r.RowNumber <= 0 {
			snoBlank++
		}
		if b == "" {
			continue
		}
		isFrag := false

		// Multi liquor-class in one cell.
		seen := map[string]bool{}
		for _, m := range liquorClassRE.FindAllString(strings.ToLower(b), -1) {
			seen[m] = true
		}
		if len(seen) >= 2 {
			multiClass++
			isFrag = true
		}

		// Over-length.
		if len(b) > 120 {
			overLong++
			isFrag = true
		}

		// Row-number leak: interior digit between two alpha tokens, NOT followed
		// by ML/PM/etc.
		if interiorDigit.MatchString(b) && !keepAfterDigit.MatchString(b) {
			rowNumLeak++
			isFrag = true
		}

		// Tail-bleed: starts with closing liquor-word + ALL-CAPS token.
		toks := strings.Fields(b)
		if len(toks) >= 3 {
			if tailEnders[strings.ToUpper(toks[0])] {
				second := toks[1]
				if len(second) >= 3 {
					allUpper := true
					for _, ch := range second {
						if !(ch >= 'A' && ch <= 'Z') {
							allUpper = false
							break
						}
					}
					if allUpper {
						tailBleed++
						isFrag = true
					}
				}
			}
		}

		if isFrag {
			fragmented++
		}
	}

	fragPct := float64(fragmented) / float64(len(rows))
	snoPct := float64(snoBlank) / float64(len(rows))

	if multiClass > 0 {
		reasons = append(reasons, fmt.Sprintf("multi-class-in-cell=%d", multiClass))
	}
	if overLong > 0 {
		reasons = append(reasons, fmt.Sprintf("brand>120chars=%d", overLong))
	}
	if rowNumLeak > 0 {
		reasons = append(reasons, fmt.Sprintf("row-num-leak=%d", rowNumLeak))
	}
	if tailBleed > 0 {
		reasons = append(reasons, fmt.Sprintf("tail-bleed=%d", tailBleed))
	}
	if snoBlank > 0 {
		reasons = append(reasons, fmt.Sprintf("sno-blank=%d/%d", snoBlank, len(rows)))
	}

	switch {
	case fragPct >= 0.30 || snoPct >= 0.50:
		level = "fragmented"
	case fragPct >= 0.10 || snoPct >= 0.25:
		level = "suspect"
	default:
		level = "clean"
	}
	return level, reasons
}

// scoreGPRowCompleteness assigns a points score based on how many fields
// of a GatePassDutyItem are populated. v1.0.237 strip-merge tiebreaker:
// when the same S.No appears in two strips (overlap region), keep the
// one with more complete cell data (brand text length, non-zero numerics).
func scoreGPRowCompleteness(r GatePassDutyItem) int {
	s := 0
	s += len(strings.TrimSpace(r.BrandName)) / 5 // longer brand = more chars read
	if r.Size != "" && r.Size != "0" && r.Size != "0ML" {
		s += 5
	}
	if r.Cases > 0 {
		s += 5
	}
	if r.Bottles > 0 {
		s += 5
	}
	if r.DutyFee > 0 {
		s += 5
	}
	return s
}

// mergeGatePassRowsBySNo unions variant-A + variant-B GP TABLES outputs
// keyed on printed S.No (RowNumber). Patterns the bill-side
// mergeExpenseRowsBySNo helper.
//
// v1.0.235 rationale: AWS Textract's character recognition on small printed
// text (chhotu's 713×1600 GP → ~10-15px per char) is non-deterministic
// across preprocessing variants. Variant 0 (CatmullRom q=92) and variant 1
// (BiLinear q=80) produce slightly different OCR per cell — running both
// and merging by S.No catches misreads either alone would have shipped.
//
// Rules:
//   - Variant A is the trusted base set.
//   - Variant B rows whose S.No is NOT in A are APPENDED.
//   - Variant B rows whose S.No collides with A REPLACE A when B has:
//       a more-complete brand (A's brand empty, OR B's brand contains tokens
//       absent from A AND vice-versa is false), OR
//       a non-zero size when A's was 0, OR
//       non-zero bottles when A's was 0.
//   - S.No=0 rows from B are skipped (un-keyable).
//
// Returns (merged, added_from_B, replaced_by_B).
func mergeGatePassRowsBySNo(a, b []GatePassDutyItem) ([]GatePassDutyItem, int, int) {
	if len(a) == 0 {
		return append([]GatePassDutyItem{}, b...), len(b), 0
	}
	if len(b) == 0 {
		return a, 0, 0
	}
	out := make([]GatePassDutyItem, len(a))
	copy(out, a)
	bySNo := make(map[int]int, len(out))
	for i, it := range out {
		if it.RowNumber > 0 {
			bySNo[it.RowNumber] = i
		}
	}
	added := 0
	replaced := 0
	for _, br := range b {
		if br.RowNumber <= 0 {
			continue
		}
		idx, exists := bySNo[br.RowNumber]
		if !exists {
			out = append(out, br)
			bySNo[br.RowNumber] = len(out) - 1
			added++
			continue
		}
		ar := &out[idx]
		// Quality scoring per row — pick the row with more populated fields.
		aBrandEmpty := strings.TrimSpace(ar.BrandName) == ""
		bHasBrand := strings.TrimSpace(br.BrandName) != ""
		aSizeZero := ar.Size == "" || ar.Size == "0" || ar.Size == "0ML"
		bHasSize := br.Size != "" && br.Size != "0" && br.Size != "0ML"
		aBottlesZero := ar.Bottles == 0
		bHasBottles := br.Bottles > 0
		if (aBrandEmpty && bHasBrand) || (aSizeZero && bHasSize) || (aBottlesZero && bHasBottles) {
			out[idx] = br
			replaced++
		}
	}
	return out, added, replaced
}

// mergeGPBrandFragments — v1.0.227-r5/r6 row-boundary fragment merger.
//
// Handles TWO real-data Textract failure modes from chhotu's GP pages:
//
// Mode 1 — "orphan fragment" (v227-r5):
//   A row with no size/cases/bottles cells whose brand text looks like a
//   continuation. Merged back to the previous row.
//
// Mode 2 — "eaten serial number" (v227-r6, NEW):
//   Dense-print sections cause Textract to misalign row boundaries:
//   the brand of row N gets cut mid-word, and its TAIL plus the NEXT
//   row's serial number end up prepended to row N+1's brand. Example
//   from chhotu gp2:
//
//     r7  S.No=26 sz=180 cs=2/96   brand="…THE RO"               ← brand cut
//     r8  S.No="" sz=180 cs=1/48   brand="27 RESERVE WHISKY      ← "27" = swallowed
//                                          STERLING RESERVE B-7…"   serial of NEXT row
//
//   The fix: detect brand text starting with a small integer (1-99)
//   followed by a known liquor word ("RESERVE", "WHISKY", "PREMIUM",
//   "VODKA", "RUM", "WHISKEY", "SCOTCH"). When matched, the digits are
//   the eaten serial number and the words before the FIRST proper
//   brand-word (capitalised name) are the tail of the previous row.
//   Synthesize a NEW row at the boundary with the swallowed brand and
//   keep both adjacent rows intact.
//
// Both modes never merge across rows that have qty data unless the
// missing-serial pattern explicitly fires (mode 2).
func mergeGPBrandFragments(items []GatePassDutyItem) []GatePassDutyItem {
	if len(items) < 2 {
		return items
	}
	out := make([]GatePassDutyItem, 0, len(items))
	out = append(out, items[0])
	merged := 0
	rescued := 0
	bledRowNum := 0
	bledCol := 0
	bledTail := 0
	for i := 1; i < len(items); i++ {
		it := items[i]
		// v1.0.236 P21 — strip in-line row-number leak.
		// Textract sometimes pulls the printed S.No into the BRAND cell as a
		// leading or middle token. Real-data: "OFFICERS CHOICE 22 ORIGINAL
		// WHISKY" (22 = next row's S.No), "26 Seagrams Blenders Pride ..."
		// (26 = current row's S.No leaked into brand). The helper's
		// heuristics handle both regardless of whether RowNumber was
		// successfully parsed from the S.No column (often it wasn't —
		// "column map serial=0" appears repeatedly in real logs).
		if stripped, ok := stripRowNumberInBrand(it.BrandName, it.RowNumber); ok {
			it.BrandName = stripped
			bledRowNum++
		}
		// v1.0.236 P22 — strip trailing liquor-type column leak.
		// Real-data: "Jameson Irish Whiskey FL", "Seagrams Royal Stag Superior
		// Whisky FL". The "FL" is the Liquor Type column (col 3) that bled
		// past the Brand column boundary. Detect: ends with " FL" or " IMFL"
		// after a known liquor-word.
		if stripped, ok := stripTrailingLiquorTypeLeak(it.BrandName); ok {
			it.BrandName = stripped
			bledCol++
		}
		// v1.0.236 P23 — strip "previous row's tail bled into this brand".
		// Real-data: row 25 "Whisky OFFICERS CHOICE WHISKY" — leading "Whisky"
		// is the tail of row 24. Detect: brand starts with a closing
		// liquor-word (Whisky/Vodka/Premium/etc.) followed by an UPPERCASE
		// brand-name. Strip everything before the first uppercase brand-name
		// token.
		if stripped, ok := stripLeadingTailBleed(it.BrandName); ok {
			it.BrandName = stripped
			bledTail++
		}
		// Mode 1 — orphan fragment merge.
		if isLikelyBrandFragment(it) && len(out) > 0 {
			last := &out[len(out)-1]
			joined := strings.TrimSpace(last.BrandName + " " + it.BrandName)
			last.BrandName = joined
			merged++
			continue
		}
		// Mode 2 — eaten-serial rescue.
		if eatenSerial, tailBrand, restBrand := splitEatenSerialPrefix(it.BrandName); eatenSerial > 0 && len(out) > 0 {
			last := &out[len(out)-1]
			// 1. Restore the tail to the previous row's brand.
			if tailBrand != "" {
				last.BrandName = strings.TrimSpace(last.BrandName + " " + tailBrand)
			}
			// 2. Synthesize the missing row with the recovered serial +
			//    same size as `it` (qty cells are unknown — set to 0 and
			//    let downstream cross-validate against Bill+Purcha).
			rescued++
			out = append(out, GatePassDutyItem{
				RowNumber: eatenSerial,
				BrandName: tailBrand,
				Size:      it.Size,
				SizeML:    it.SizeML,
				Cases:     0,
				Bottles:   0,
				DutyFee:   0,
			})
			// 3. Update `it` so its brand is just the proper rest.
			it.BrandName = restBrand
		}
		out = append(out, it)
	}
	if merged > 0 || rescued > 0 || bledRowNum > 0 || bledCol > 0 || bledTail > 0 {
		log.Printf("SmartPurchase GP: fragment-merge fixed merged=%d rescued=%d row_num_leak=%d col_leak=%d tail_bleed=%d",
			merged, rescued, bledRowNum, bledCol, bledTail)
	}
	return out
}

// stripRowNumberInBrand removes 1-3 digit tokens that leaked into the brand
// from adjacent row's serial column. v1.0.236-r2 — matches ANY digit token
// surrounded by brand-word continuations, not just the row's own number.
//
// Real-data examples from v236 first run:
//   row 34: "Royal Challenge Select 29 Premium Whisky" → strip "29"
//   row 35: "M2 Magic Moments Remix 30 Superior ..." → strip "30"
//   row 38: "THE ROCKFORD 33 RESERVE PREMIUM" → strip "33"
//   row 39: "Smirnoff Minty Jamun Triple 34 Distilled Vodka" → strip "34"
//   row 40: "M2 Magic Moments 35 Vodka" → strip "35"
//
// The leaked digit is OFTEN an ADJACENT row's index (not the row's own
// number), so we can't match on rowNumber alone. Heuristic: a 1-3 digit
// token in the MIDDLE of a brand (not first, not last) is a leak when:
//   1. brand has ≥4 tokens total
//   2. digit is NOT immediately followed by an age/size suffix (PM/YR/ML)
//   3. digit IS surrounded on at least one side by a recognised liquor word
//      (Whisky/Vodka/Rum/Reserve/Premium/Selection/Edition/Superior/etc.)
//   4. digit is NOT preceded by an age-context word (Aged/Years)
//
// rowNumber is accepted but ignored (kept for API stability; v236-r2 doesn't
// need it).
func stripRowNumberInBrand(brand string, rowNumber int) (string, bool) {
	_ = rowNumber
	b := strings.TrimSpace(brand)
	if b == "" {
		return brand, false
	}
	tokens := strings.Fields(b)
	if len(tokens) < 4 {
		return brand, false
	}
	// Recognise the words that surround leaked digits (continuations or
	// brand-end markers).
	contWords := map[string]bool{
		"premium": true, "reserve": true, "whisky": true, "whiskey": true,
		"vodka": true, "rum": true, "scotch": true, "blended": true,
		"superior": true, "select": true, "selection": true, "edition": true,
		"label": true, "smooth": true, "deluxe": true, "rare": true,
		"distilled": true, "international": true, "grain": true,
		"flavoured": true, "flavored": true,
	}
	// Words that indicate the digit is a legitimate age/quantity.
	ageWords := map[string]bool{
		"aged": true, "year": true, "years": true, "yr": true, "yrs": true,
	}
	// v1.0.236-r3: also strip 1-3 digit LEAD tokens followed by alphabetic
	// brand text (real-data: row 28 "26 Seagrams Blenders Pride..."). We
	// don't touch trailing digits (sizes like "12 Y", "750 ML" handled
	// elsewhere).
	leadStripped := false
	if len(tokens[0]) <= 3 {
		allDigit := true
		for _, r := range tokens[0] {
			if r < '0' || r > '9' {
				allDigit = false
				break
			}
		}
		if allDigit && len(tokens) >= 3 && isAlphaToken(tokens[1], 3) {
			// Next token is alpha length ≥3 — leading digit is row-number leak.
			tokens = tokens[1:]
			leadStripped = true
		}
	}

	// v1.0.236-r3: mid-string strip is now AGGRESSIVE. Any 1-3 digit token
	// in the middle (not first, not last) is a leak UNLESS followed by an
	// age/size suffix (PM/YR/ML/etc.) or preceded by an age context word.
	// The previous "must touch a continuation word" rule was too narrow —
	// it missed real-data leaks like "OFFICERS CHOICE 22 ORIGINAL WHISKY"
	// because "CHOICE" / "ORIGINAL" weren't in the continuation set.
	_ = contWords // kept for reference but no longer required
	stripped := false
	out := make([]string, 0, len(tokens))
	out = append(out, tokens[0]) // never strip token 0
	for i := 1; i < len(tokens)-1; i++ { // never strip last token either
		t := tokens[i]
		// v1.0.236-r5: only strip 1-2 digit tokens. 3-digit numbers like
		// "100" are legitimate brand prefixes ("100 STROKES ROYAL WHISKY",
		// "100 PIPERS"). Row numbers on real GP forms are 1-99.
		if len(t) < 1 || len(t) > 2 {
			out = append(out, t)
			continue
		}
		allDigit := true
		for _, r := range t {
			if r < '0' || r > '9' {
				allDigit = false
				break
			}
		}
		if !allDigit {
			out = append(out, t)
			continue
		}
		// Next-token age/size markers — KEEP digit (legitimate).
		nextU := strings.ToUpper(tokens[i+1])
		if nextU == "PM" || nextU == "YEAR" || nextU == "YEARS" || nextU == "Y" || nextU == "YRS" ||
			nextU == "ML" || nextU == "L" || nextU == "LTR" || nextU == "CL" {
			out = append(out, t)
			continue
		}
		// Previous-token age context — KEEP.
		prevL := strings.ToLower(tokens[i-1])
		if ageWords[prevL] {
			out = append(out, t)
			continue
		}
		// All other 1-2 digit mid-tokens are stripped.
		stripped = true
	}
	out = append(out, tokens[len(tokens)-1])
	if !stripped && !leadStripped {
		return brand, false
	}
	return strings.Join(out, " "), true
}

// stripTrailingLiquorTypeLeak strips " FL" / " IMFL" / " FMFL" / standalone
// liquor-type codes that Textract bled in from the adjacent Liquor Type
// column. v1.0.236 P22. v1.0.236-r2: now also handles MID-string leaks.
//
// Real examples:
//   trailing: "Jameson Irish Whiskey FL" → "Jameson Irish Whiskey"
//   mid (r2): "JOHNNIE WALKER BLACK BLENDED SCOTCH FL WHISKY 12 Y"
//             → "JOHNNIE WALKER BLACK BLENDED SCOTCH WHISKY 12 Y"
//
// Mid-string strip fires only when the FL token is surrounded by capitalised
// brand-name tokens (so we don't eat legitimate "FL" in a hypothetical brand
// name).
func stripTrailingLiquorTypeLeak(brand string) (string, bool) {
	b := strings.TrimSpace(brand)
	if b == "" {
		return brand, false
	}
	codes := map[string]bool{
		"FL": true, "IMFL": true, "FMFL": true, "CL": true, "WB": true, "BR": true,
	}
	tokens := strings.Fields(b)
	if len(tokens) < 3 {
		return brand, false
	}
	stripped := false
	out := make([]string, 0, len(tokens))
	out = append(out, tokens[0])
	for i := 1; i < len(tokens); i++ {
		t := tokens[i]
		if !codes[strings.ToUpper(t)] {
			out = append(out, t)
			continue
		}
		// Decide whether to strip:
		//   - Trailing position: previous token must be a brand-ender
		//     (Whisky/Vodka/etc.) — same rule as original v236 P22.
		//   - Mid position: previous AND next tokens must look like
		//     brand-name (alpha, length ≥3). Surrounded by real brand words.
		prevTok := out[len(out)-1]
		if i == len(tokens)-1 {
			brandEnders := map[string]bool{
				"WHISKY": true, "WHISKEY": true, "VODKA": true, "RUM": true,
				"PREMIUM": true, "RESERVE": true, "LABEL": true, "SELECTION": true,
				"EDITION": true, "SCOTCH": true, "GIN": true, "BEER": true,
			}
			if brandEnders[strings.ToUpper(prevTok)] {
				stripped = true
				continue
			}
			out = append(out, t)
			continue
		}
		nextTok := tokens[i+1]
		if isAlphaToken(prevTok, 2) && isAlphaToken(nextTok, 3) {
			stripped = true
			continue
		}
		out = append(out, t)
	}
	if !stripped {
		return brand, false
	}
	return strings.Join(out, " "), true
}

// isAlphaToken returns true when s has length ≥ min AND consists entirely
// of letters (any case). Helper for stripTrailingLiquorTypeLeak mid-string
// detection.
func isAlphaToken(s string, min int) bool {
	if len(s) < min {
		return false
	}
	for _, r := range s {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')) {
			return false
		}
	}
	return true
}

// stripLeadingTailBleed removes leading liquor-type words that bled from
// the previous row's tail. v1.0.236 P23. v1.0.236-r2 expands the trigger
// rules to cover ALL-CAPS leading bleed (real-data: row 37 "WHISKY Seagrams
// Royal Stag...", row 39 "WHISKY Smirnoff Minty Jamun...").
//
// Three trigger patterns:
//   1. Mixed-case lead + ≥2 all-caps follow tokens:
//      "Whisky OFFICERS CHOICE WHISKY" → "OFFICERS CHOICE WHISKY"
//   2. All-caps lead + mixed-case follow (different writing system):
//      "WHISKY Seagrams Royal Stag" → "Seagrams Royal Stag"
//   3. Lead is a SHORT all-caps single liquor word + at least 2 following
//      tokens that form a real brand:
//      "WHISKY Smirnoff Minty Jamun..." → "Smirnoff Minty Jamun..."
func stripLeadingTailBleed(brand string) (string, bool) {
	b := strings.TrimSpace(brand)
	tokens := strings.Fields(b)
	if len(tokens) < 3 {
		return brand, false
	}
	// All known liquor "ender" / "category" words that should NEVER be the
	// LEAD token of a brand (Indian Excise brand names never START with
	// just "Whisky" — they start with the producer/marque first).
	leadWordsUpper := map[string]bool{
		"WHISKY": true, "WHISKEY": true, "VODKA": true, "RUM": true,
		"SCOTCH": true, "ORIGINAL": true,
	}
	// Common mixed-case duplicates seen on real bills.
	leadWordsMixed := map[string]bool{
		"Whisky": true, "Whiskey": true, "Vodka": true, "Rum": true,
		"Premium": true, "Reserve": true, "Label": true, "Scotch": true,
		"Original": true, "Blended": true,
	}

	lead := tokens[0]
	upperHit := leadWordsUpper[strings.ToUpper(lead)]
	mixedHit := leadWordsMixed[lead]
	if !upperHit && !mixedHit {
		return brand, false
	}

	// Pattern 1 — mixed-case lead, ≥2 ALL-CAPS follow.
	if mixedHit && !isAllUpperLetters(lead) {
		uRun := 0
		for i := 1; i < len(tokens) && i <= 3; i++ {
			if isAllUpperLetters(tokens[i]) {
				uRun++
			} else {
				break
			}
		}
		if uRun >= 2 {
			return strings.Join(tokens[1:], " "), true
		}
	}

	// Pattern 2 + 3 — ALL-CAPS lead, ≥2 follow tokens (any case) forming a
	// brand. We avoid being too aggressive: require the 2nd token to start
	// with a capital letter (so we don't strip "WHISKY" from a legit
	// all-caps brand like "WHISKY MIRROR" — vanishingly rare on UP Excise).
	if upperHit && isAllUpperLetters(lead) {
		// First follow token must start with a capital (mixed or all upper).
		nt := tokens[1]
		if len(nt) == 0 {
			return brand, false
		}
		firstCh := nt[0]
		if !(firstCh >= 'A' && firstCh <= 'Z') {
			return brand, false
		}
		// Require ≥1 follow token to be a multi-letter alpha (real brand).
		hasRealFollow := false
		for i := 1; i < len(tokens) && i <= 4; i++ {
			if isAlphaToken(tokens[i], 3) {
				hasRealFollow = true
				break
			}
		}
		if !hasRealFollow {
			return brand, false
		}
		return strings.Join(tokens[1:], " "), true
	}
	return brand, false
}

// isAllUpperLetters returns true when s consists of A-Z runes (≥2 chars).
// Helper for stripLeadingTailBleed. Punctuation/digits return false.
func isAllUpperLetters(s string) bool {
	if len(s) < 2 {
		return false
	}
	for _, r := range s {
		if !(r >= 'A' && r <= 'Z') {
			return false
		}
	}
	return true
}

// splitEatenSerialPrefix detects the "27 RESERVE WHISKY STERLING…" pattern.
//
// Returns:
//   eatenSerial — the recovered serial number (1-99), 0 if no match.
//   tailBrand   — text BEFORE the first proper-brand token (the swallowed
//                 row's brand tail).
//   restBrand   — text FROM the first proper-brand token onward (the
//                 current row's actual brand).
//
// Heuristic: match leading "<digit><digit?> (CONTINUATION_WORD ){1,3}<BrandWord>"
// where CONTINUATION_WORD is in a small lexicon and BrandWord is a
// known liquor-brand starter (capitalised word that's NOT a continuation).
func splitEatenSerialPrefix(brand string) (int, string, string) {
	b := strings.TrimSpace(brand)
	if b == "" {
		return 0, "", ""
	}
	tokens := strings.Fields(b)
	if len(tokens) < 3 {
		return 0, "", ""
	}
	// Token 0 must be a 1-2 digit number.
	num, err := strconv.Atoi(tokens[0])
	if err != nil || num < 1 || num > 99 {
		return 0, "", ""
	}
	// At least one of tokens[1..3] must be a known liquor-tail continuation.
	tailWords := map[string]bool{
		"reserve": true, "whisky": true, "whiskey": true, "premium": true,
		"vodka": true, "rum": true, "scotch": true, "blended": true,
		"smooth": true, "select": true, "label": true, "vodca": true,
		"flavoured": true,
	}
	tailEnd := 0 // exclusive end of the tail-tokens (after token 0)
	for i := 1; i < len(tokens) && i <= 4; i++ {
		if tailWords[strings.ToLower(tokens[i])] {
			tailEnd = i + 1
		} else if tailEnd > 0 {
			// Once we've seen a tail-word and then a non-tail word, stop.
			break
		}
	}
	if tailEnd == 0 {
		return 0, "", ""
	}
	// tokens[1..tailEnd) is the tail. tokens[tailEnd:] is the proper rest.
	if tailEnd >= len(tokens) {
		return 0, "", "" // pathological — no rest brand → don't split
	}
	tail := strings.Join(tokens[1:tailEnd], " ")
	rest := strings.Join(tokens[tailEnd:], " ")
	return num, tail, rest
}

func isLikelyBrandFragment(it GatePassDutyItem) bool {
	// Real fragments have NO size + NO qty cells.
	if it.SizeML > 0 || it.Cases > 0 || it.Bottles > 0 {
		return false
	}
	b := strings.TrimSpace(it.BrandName)
	if b == "" || len(b) < 3 {
		return true // empty / tiny → fragment
	}
	// Continuation-token patterns observed in chhotu real data.
	bl := strings.ToLower(b)
	for _, suffix := range []string{
		"nded ", "whisky", "vodka", "rum", "scotch", "blended",
		"premium", "reserve", "select", "edition", "label",
	} {
		if strings.HasPrefix(bl, suffix) {
			return true
		}
	}
	// Starts lowercase (mid-word wrap).
	first := b[0]
	if first >= 'a' && first <= 'z' {
		return true
	}
	// Pure-numeric or punctuation-leading.
	if first >= '0' && first <= '9' {
		return true
	}
	return false
}

// runTextractGatePassPage reads one GP page through AnalyzeDocument(TABLES)
// and returns one GatePassDutyItem per data row. Column detection is
// header-text driven so the function tolerates minor format variation
// (column reordering by different state excise departments, occasional
// header word changes).
func runTextractGatePassPage(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]GatePassDutyItem, error) {

	pctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(pctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: raw},
		FeatureTypes: []ttypes.FeatureType{ttypes.FeatureTypeTables},
	})
	if err != nil {
		return nil, fmt.Errorf("AnalyzeDocument: %w", err)
	}

	blockByID := map[string]ttypes.Block{}
	skippedHandwriting := 0
	for _, b := range resp.Blocks {
		if b.Id == nil {
			continue
		}
		if b.BlockType == ttypes.BlockTypeWord && b.TextType == ttypes.TextTypeHandwriting {
			skippedHandwriting++
			continue
		}
		blockByID[*b.Id] = b
	}
	if skippedHandwriting > 0 {
		log.Printf("SmartPurchase GP page %d (TABLES): dropped %d handwritten word blocks", pageNumber, skippedHandwriting)
	}

	// Find the largest TABLE block.
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
		return nil, nil
	}

	// rowsByIdx[r][c] = CELL block.
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
	rowIDs := make([]int32, 0, len(rowsByIdx))
	for r := range rowsByIdx {
		rowIDs = append(rowIDs, r)
	}
	sortInt32Asc(rowIDs)
	if len(rowIDs) < 2 {
		return nil, nil
	}

	// Detect columns from the header — scan the first 3 rows because some
	// GP layouts have a "Department of Excise / Indent Date" meta row above
	// the actual table header. Pick the row with the most column matches.
	colIdx := gpColumnIndices{}
	bestMatches := 0
	for _, hr := range rowIDs[:minIntGP(3, len(rowIDs))] {
		candidate := detectGatePassColumns(rowsByIdx[hr], blockByID)
		matches := gpColMatchCount(candidate)
		if matches > bestMatches {
			bestMatches = matches
			colIdx = candidate
		}
	}
	headerRowOffset := 0 // index into rowIDs where the header was found
	if bestMatches > 0 {
		// We DID find a header — figure out which row it was in so we don't
		// emit it as a data item.
		for i, hr := range rowIDs[:minIntGP(3, len(rowIDs))] {
			if c := detectGatePassColumns(rowsByIdx[hr], blockByID); gpColMatchCount(c) == bestMatches {
				headerRowOffset = i
				break
			}
		}
	} else {
		// No header on this page (multi-page GP — header only on page 1, OR
		// header was malformed). Fall back to the canonical UP Excise column
		// layout. Validate by sampling: the duty column (12) on a data row
		// should parse as a positive float; if it does, the layout matches.
		//
		// v1.0.215.5 — sample the FIRST 5 data rows, not just row 0. Real-data
		// trigger: chhotu's GP page 2 had a sparse first row (Textract dropped
		// the leftmost cells), causing validation to fail and forcing a 30s
		// LLM cascade. Mid-page rows have the duty cell intact. Looking at
		// any of the first 5 rows recovers the layout.
		validated := false
		probedRows := minIntGP(5, len(rowIDs))
		for i := 0; i < probedRows; i++ {
			sample := rowsByIdx[rowIDs[i]]
			dutyText := strings.TrimSpace(joinCellText(sample[gpColumnDefault.duty], blockByID))
			if v, err := strconv.ParseFloat(strings.ReplaceAll(dutyText, ",", ""), 64); err == nil && v > 100 {
				colIdx = gpColumnDefault
				log.Printf("SmartPurchase GP page %d (TABLES): no header — using default column layout (duty sample=%.2f from row %d)", pageNumber, v, i)
				validated = true
				break
			}
		}
		if !validated && len(rowIDs) >= 1 {
			// Diagnostic — log first row text so we can see what Textract gave us.
			var firstRowLabels []string
			hr := rowsByIdx[rowIDs[0]]
			hrCols := make([]int32, 0, len(hr))
			for c := range hr {
				hrCols = append(hrCols, c)
			}
			sortInt32Asc(hrCols)
			for _, c := range hrCols {
				firstRowLabels = append(firstRowLabels, fmt.Sprintf("c%d=%q", c, strings.TrimSpace(joinCellText(hr[c], blockByID))))
			}
			log.Printf("SmartPurchase GP page %d (TABLES): no header columns detected, default layout didn't validate (probed %d rows) — first row was: %s", pageNumber, probedRows, strings.Join(firstRowLabels, " | "))
			return nil, nil
		}
	}

	out := make([]GatePassDutyItem, 0, len(rowIDs))
	dataStart := 0
	if bestMatches > 0 {
		dataStart = headerRowOffset + 1
	}
	for _, r := range rowIDs[dataStart:] {
		cells := rowsByIdx[r]
		read := func(c int32) string {
			if c <= 0 {
				return ""
			}
			return strings.TrimSpace(joinCellText(cells[c], blockByID))
		}
		readInt := func(c int32) int {
			if c <= 0 {
				return 0
			}
			v, _ := parseIntPurchaseCell(cells[c], blockByID)
			return v
		}
		readFloat := func(c int32) float64 {
			if c <= 0 {
				return 0
			}
			v, _ := parseFloatPurchaseCell(cells[c], blockByID)
			return v
		}

		serialText := read(colIdx.serial)
		brand := read(colIdx.brand)
		description := read(colIdx.description)
		liquorType := read(colIdx.liquorType)
		liquorSub := read(colIdx.liquorSub)
		sizeText := read(colIdx.size)
		packType := read(colIdx.packagingType)
		cases := readInt(colIdx.casesDispatched)
		bottles := readInt(colIdx.bottlesDispatched)
		duty := readFloat(colIdx.duty)

		// v1.0.214 (Tushar 2026-05-08) — when the GP Brand column is unclear
		// (empty / single token / shorter than the description), promote the
		// Description column as the canonical brand. Real-data: row 14 came
		// back with brand="Blended Whisky" (just the category) while
		// description had the full "Seagrams Blenders Pride Reserve
		// Collection Exclusive Whisky" — much better signal for matching.
		// We only swap when description is meaningfully longer (≥ brand+5)
		// and isn't itself empty.
		if descTrim := strings.TrimSpace(description); descTrim != "" {
			brandTrim := strings.TrimSpace(brand)
			needsFallback := brandTrim == "" ||
				len(strings.Fields(brandTrim)) < 2 ||
				(len(descTrim) >= len(brandTrim)+5 && strings.Contains(strings.ToLower(descTrim), strings.ToLower(brandTrim)))
			if needsFallback {
				log.Printf("SmartPurchase GP page %d row %s: description fallback for brand (was %q → %q)",
					pageNumber, serialText, brandTrim, descTrim)
				brand = descTrim
			}
		}

		// Skip empty rows (e.g. blank separator rows, footer Total).
		if brand == "" && serialText == "" && cases == 0 && bottles == 0 && duty == 0 {
			continue
		}
		// Skip the explicit "Total" row — we don't want it as an item.
		if isGPTotalRow(serialText, brand) {
			continue
		}

		serial, _ := strconv.Atoi(serialText)
		sizeML := normalizeSizeText(sizeText)
		if sizeML == 0 {
			// Heuristic: if size cell empty, try parsing standalone digits.
			if d := digitOnlyRe.FindString(sizeText); d != "" {
				if v, _ := strconv.Atoi(d); v > 0 {
					sizeML = v
				}
			}
		}

		out = append(out, GatePassDutyItem{
			RowNumber:     serial,
			BrandName:     brand,
			Size:          fmt.Sprintf("%dML", sizeML),
			SizeML:        sizeML,
			Cases:         cases,
			Bottles:       bottles,
			DutyFee:       duty,
			LiquorType:    liquorType,
			LiquorSubType: liquorSub,
			PackagingType: packType,
		})
	}
	return out, nil
}

type gpColumnIndices struct {
	serial             int32
	brand              int32
	liquorType         int32
	liquorSub          int32
	description        int32
	size               int32
	packagingType      int32
	casesRequested     int32
	bottlesRequested   int32
	casesDispatched    int32
	bottlesDispatched  int32
	duty               int32
}

// detectGatePassColumns walks the header row's cells and matches text against
// the known UP Excise GP column labels. Missing labels stay at 0 — caller
// uses 0 as "not present, skip".
func detectGatePassColumns(headerCells map[int32]ttypes.Block, blockByID map[string]ttypes.Block) gpColumnIndices {
	idx := gpColumnIndices{}
	cols := make([]int32, 0, len(headerCells))
	for c := range headerCells {
		cols = append(cols, c)
	}
	sortInt32Asc(cols)

	for _, c := range cols {
		text := strings.ToUpper(strings.TrimSpace(joinCellText(headerCells[c], blockByID)))
		text = strings.Join(strings.Fields(text), " ")
		switch {
		case idx.serial == 0 && (text == "S.NO" || text == "S NO" || text == "SR" || text == "SR.NO" || text == "SL.NO" || text == "NO."):
			idx.serial = c
		case idx.brand == 0 && text == "BRAND":
			idx.brand = c
		case idx.liquorType == 0 && (text == "LIQUOR TYPE" || text == "LIQ TYPE"):
			idx.liquorType = c
		case idx.liquorSub == 0 && (text == "LIQUOR SUB TYPE" || text == "LIQ SUB TYPE" || text == "SUB TYPE"):
			idx.liquorSub = c
		case idx.description == 0 && text == "DESCRIPTION":
			idx.description = c
		case idx.size == 0 && (strings.Contains(text, "PACKAGING SIZE") || strings.Contains(text, "PACK SIZE") || text == "SIZE"):
			idx.size = c
		case idx.packagingType == 0 && (strings.Contains(text, "PACKAGING TYPE") || strings.Contains(text, "PACK TYPE")):
			idx.packagingType = c
		case strings.Contains(text, "REQUESTED") && strings.Contains(text, "CASES"):
			idx.casesRequested = c
		case strings.Contains(text, "REQUESTED") && strings.Contains(text, "BOTTLES"):
			idx.bottlesRequested = c
		case strings.Contains(text, "DISPATCHED") && strings.Contains(text, "CASES"):
			idx.casesDispatched = c
		case strings.Contains(text, "DISPATCHED") && strings.Contains(text, "BOTTLES"):
			idx.bottlesDispatched = c
		case idx.duty == 0 && strings.Contains(text, "DUTY"):
			idx.duty = c
		}
	}
	// If the GP didn't separate Requested vs Dispatched (older format), the
	// only quantity columns are the cases/bottles ones — fold them in so we
	// have something to read.
	if idx.casesDispatched == 0 && idx.casesRequested != 0 {
		idx.casesDispatched = idx.casesRequested
	}
	if idx.bottlesDispatched == 0 && idx.bottlesRequested != 0 {
		idx.bottlesDispatched = idx.bottlesRequested
	}
	log.Printf("SmartPurchase GP: column map serial=%d brand=%d sub=%d size=%d cases=%d bottles=%d duty=%d",
		idx.serial, idx.brand, idx.liquorSub, idx.size, idx.casesDispatched, idx.bottlesDispatched, idx.duty)
	return idx
}

var digitOnlyRe = regexp.MustCompile(`\d+`)

func minIntGP(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func gpColMatchCount(idx gpColumnIndices) int {
	n := 0
	if idx.brand != 0 {
		n++
	}
	if idx.size != 0 {
		n++
	}
	if idx.casesDispatched != 0 {
		n++
	}
	if idx.bottlesDispatched != 0 {
		n++
	}
	if idx.duty != 0 {
		n++
	}
	return n
}

func isGPTotalRow(serialText, brand string) bool {
	s := strings.ToUpper(strings.TrimSpace(serialText))
	b := strings.ToUpper(strings.TrimSpace(brand))
	return s == "TOTAL" || s == "GRAND TOTAL" || b == "TOTAL" || b == "GRAND TOTAL"
}

// isGPTotalArtifactItem reports whether an LLM-extracted gate-pass row is really
// a footer / per-section "Total" line rather than a dispatched SKU. UP Excise
// GPs print a "Total" (and sometimes section sub-total) row that the LLM cascade
// occasionally emits as a data item — typically blank brand_name with
// packaging_type "Total" and aggregate cases/bottles (e.g. the real case:
// Mahua Khera job 70047c55 rows 31-32, 38 cases / 1380 bottles, no name). Those
// must never become purchase rows: they surface to the operator as
// "not_found, no name, NN cases". Detected by the explicit Total label on the
// brand or packaging cell — deterministic and unambiguous. Blank-name rows with
// no Total label are intentionally LEFT IN so the degraded-GP detector (v346)
// still counts them and can fall back to bill-primary.
func isGPTotalArtifactItem(it GatePassDutyItem) bool {
	name := strings.ToUpper(strings.TrimSpace(it.BrandName))
	pack := strings.ToUpper(strings.TrimSpace(it.PackagingType))
	switch name {
	case "TOTAL", "GRAND TOTAL", "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL":
		return true
	}
	switch pack {
	case "TOTAL", "GRAND TOTAL", "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL":
		return true
	}
	return false
}

// extractDutyFromGatePassTextract uses AnalyzeExpense to read the UP Excise
// gate-pass like an invoice. The two documents are similar enough — line items
// with a brand, size, dispatch quantity, and duty fee — that the same
// LineItemFields semantics apply. Two real-data quirks we handle here:
//
//  1. UP Excise GPs have BOTH "Cases Requested" AND "Cases Dispatched"
//     columns. Textract often returns BOTH as QUANTITY-tagged fields on the
//     same LineItem — we pick the right one by LabelDetection text first
//     ("dispatched"/"actual"/"supplied"), then by right-most BoundingBox.Left
//     since dispatched columns sit further right than requested columns.
//
//  2. Bottles dispatched is usually labelled OTHER by Textract because it
//     doesn't fit a standard tag. We recover it by geometric clustering —
//     pick the OTHER field whose Left aligns with the dispatched-bottles
//     column on the header row. Pack-math invariants from the existing
//     IMFL bpc table cross-check the recovery.
func (s *SmartPurchaseService) extractDutyFromGatePassTextract(ctx context.Context, images []SmartPurchaseImage) ([]GatePassDutyItem, error) {
	client, err := newTextractPurchaseClient(ctx)
	if err != nil {
		return nil, err
	}
	startedAt := time.Now()
	pages := make([][]GatePassDutyItem, len(images))

	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(textractPageConcurrency()) // AWS sync TPS is ~2 — see textract_expense_pipeline.go
	deskew := newDeskewClient()

	for i, img := range images {
		i := i
		img := img
		if len(img.Data) == 0 {
			continue
		}
		g.Go(func() error {
			pre := prepareTextractImage(img.Data)
			dctx, dcancel := context.WithTimeout(gctx, 3*time.Second)
			desk := deskew.Deskew(dctx, pre)
			dcancel()
			if len(desk) > 0 && len(desk) != len(pre) {
				pre = desk
			}
			pctx, cancel := context.WithTimeout(gctx, 90*time.Second)
			defer cancel()
			resp, hit, perr := cachedAnalyzeExpense(pctx, client, pre)
			if perr != nil {
				log.Printf("SmartPurchase GP page %d: AnalyzeExpense failed: %v", i+1, perr)
				return nil
			}
			if hit {
				log.Printf("SmartPurchase GP page %d: served from cache (₹0)", i+1)
			}
			if resp == nil || len(resp.ExpenseDocuments) == 0 {
				return nil
			}
			rows := mapGatePassExpense(resp.ExpenseDocuments[0])
			// v1.0.238 — stamp page index for Excel export.
			for j := range rows {
				rows[j].PageIndex = i + 1
			}
			pages[i] = rows
			log.Printf("SmartPurchase GP page %d: AnalyzeExpense → %d rows", i+1, len(pages[i]))
			return nil
		})
	}
	_ = g.Wait()

	// Flatten + sequential row-numbering with cumulative S.No detection
	// (mirrors the LLM path's logic for multi-page UP Excise GPs).
	var allItems []GatePassDutyItem
	for _, p := range pages {
		if len(p) == 0 {
			continue
		}
		minNew, maxExisting := -1, 0
		for _, ex := range allItems {
			if ex.RowNumber > maxExisting {
				maxExisting = ex.RowNumber
			}
		}
		for _, it := range p {
			if it.RowNumber > 0 && (minNew == -1 || it.RowNumber < minNew) {
				minNew = it.RowNumber
			}
		}
		if minNew != -1 && minNew <= maxExisting {
			off := maxExisting
			for j := range p {
				if p[j].RowNumber > 0 {
					p[j].RowNumber += off
				}
			}
		}
		allItems = append(allItems, p...)
	}
	if len(allItems) == 0 {
		return nil, fmt.Errorf("AnalyzeExpense returned no GP rows on any page")
	}

	// Same dedup + bpc-correction sweep the LLM path runs.
	seen := make(map[string]bool, len(allItems))
	deduped := make([]GatePassDutyItem, 0, len(allItems))
	for _, it := range allItems {
		key := fmt.Sprintf("%d|%s|%d|%d|%d", it.RowNumber, strings.ToUpper(strings.TrimSpace(it.BrandName)), it.SizeML, it.Cases, it.Bottles)
		if seen[key] {
			continue
		}
		seen[key] = true
		deduped = append(deduped, it)
	}
	if len(deduped) < len(allItems) {
		log.Printf("SmartPurchase GP: dedup removed %d row(s) (%d → %d)", len(allItems)-len(deduped), len(allItems), len(deduped))
	}
	allItems = deduped

	for i := range allItems {
		it := &allItems[i]
		bpc, ok := StandardCaseSizes[it.SizeML]
		if !ok || bpc <= 1 || it.Cases == 0 {
			continue
		}
		expected := it.Cases * bpc
		if it.Bottles == it.Cases {
			it.Bottles = expected
		} else if it.Bottles == 0 {
			it.Bottles = expected
		}
	}

	log.Printf("SmartPurchase GP: AnalyzeExpense path produced %d rows in %dms",
		len(allItems), int(time.Since(startedAt).Milliseconds()))
	return allItems, nil
}

// mapGatePassExpense translates one AnalyzeExpense ExpenseDocument into
// GatePassDutyItem rows. UP Excise GPs use 12 columns; AnalyzeExpense
// reduces them semantically to ITEM (Brand+Description), QUANTITY (cases),
// PRICE (duty fee), and OTHER buckets for the auxiliary columns.
func mapGatePassExpense(doc ttypes.ExpenseDocument) []GatePassDutyItem {
	out := make([]GatePassDutyItem, 0, 32)
	rowSerial := 0

	for _, group := range doc.LineItemGroups {
		for _, li := range group.LineItems {
			rowSerial++
			it := GatePassDutyItem{RowNumber: rowSerial}

			// Bucket fields — we may see multiple QUANTITY entries (cases
			// requested vs cases dispatched). We collect them and pick the
			// right-most by Left BoundingBox after the loop, since the
			// "Dispatched" column sits to the right of "Requested" on every
			// UP Excise GP we've seen.
			type qf struct {
				value float64
				left  float32
				label string
			}
			qfields := []qf{}
			otherFloats := []qf{}

			for _, f := range li.LineItemExpenseFields {
				tag := safeStr(f.Type, "Text")
				val := safeStr(f.ValueDetection, "Text")
				labelTxt := ""
				if f.LabelDetection != nil {
					labelTxt = strings.ToLower(safeStr(f.LabelDetection, "Text"))
				}
				left := float32(0)
				if f.ValueDetection != nil && f.ValueDetection.Geometry != nil && f.ValueDetection.Geometry.BoundingBox != nil {
					left = f.ValueDetection.Geometry.BoundingBox.Left
				}
				switch tag {
				case "ITEM":
					if it.BrandName == "" {
						it.BrandName = strings.TrimSpace(val)
						if sz := parseSizeMLFromText(val); sz > 0 {
							it.SizeML = sz
							it.Size = fmt.Sprintf("%d", sz)
						}
					} else {
						// Long-form description column gets appended.
						it.BrandName = it.BrandName + " " + strings.TrimSpace(val)
					}
				case "QUANTITY":
					if v, ok := parseNumericLike(val); ok {
						qfields = append(qfields, qf{value: v, left: left, label: labelTxt})
					}
				case "PRICE", "UNIT_PRICE":
					if v, ok := parseNumericLike(val); ok {
						// Duty fee is the largest numeric on the row by far
						// (₹thousands vs cases ≤100). Prefer the largest seen.
						if v > it.DutyFee {
							it.DutyFee = v
						}
					}
				default:
					if v, ok := parseNumericLike(val); ok {
						otherFloats = append(otherFloats, qf{value: v, left: left, label: labelTxt})
					}
				}
			}

			// Pick cases: prefer label hint "dispatched"/"actual"/"supplied",
			// fall back to right-most by Left.
			pickedCases := -1.0
			pickedCasesLeft := float32(-1)
			for _, q := range qfields {
				if strings.Contains(q.label, "dispatch") || strings.Contains(q.label, "actual") || strings.Contains(q.label, "supplied") {
					pickedCases = q.value
					pickedCasesLeft = q.left
					break
				}
			}
			if pickedCases < 0 && len(qfields) > 0 {
				rightmost := qfields[0]
				for _, q := range qfields[1:] {
					if q.left > rightmost.left {
						rightmost = q
					}
				}
				pickedCases = rightmost.value
				pickedCasesLeft = rightmost.left
			}
			if pickedCases > 0 && pickedCases < 10000 {
				it.Cases = int(pickedCases + 0.5)
			}

			// Pick bottles from OTHER: prefer the field whose Left is just to
			// the right of the picked-cases column (dispatched-bottles always
			// sits one column right of dispatched-cases on UP Excise GPs).
			if pickedCasesLeft > 0 {
				best := -1.0
				bestLeft := pickedCasesLeft
				for _, o := range otherFloats {
					if o.left <= pickedCasesLeft || o.left-pickedCasesLeft > 0.30 {
						continue
					}
					if o.value <= 0 || o.value > 10000 {
						continue
					}
					if best < 0 || o.left-pickedCasesLeft < bestLeft-pickedCasesLeft {
						best = o.value
						bestLeft = o.left
					}
				}
				if best > 0 {
					it.Bottles = int(best + 0.5)
				}
			}

			// Drop placeholder rows.
			if it.BrandName == "" && it.Cases == 0 && it.Bottles == 0 {
				rowSerial--
				continue
			}
			out = append(out, it)
		}
	}
	return out
}

// extractDutyFromGatePassLLM is the legacy LLM-only path (Gemini → Claude →
// OpenAI cascade). Kept verbatim from the v1.0.193 implementation as the
// absolute last-resort fallback. Not called directly by any new code; the
// dispatcher above falls through here when AnalyzeExpense returns nothing.
// extractDutyFromGatePassLLM — thin wrapper returning just the rows (back-compat
// for the several callers that don't need footer totals).
func (s *SmartPurchaseService) extractDutyFromGatePassLLM(ctx context.Context, images []SmartPurchaseImage) ([]GatePassDutyItem, error) {
	ex, err := s.extractDutyFromGatePassLLMEx(ctx, images)
	if err != nil {
		return nil, err
	}
	return ex.Items, nil
}

// extractDutyFromGatePassLLMEx — v1.0.366. Same extraction, but also returns the
// PRINTED FOOTER TOTALS (cases / bottles / duty) so the hybrid path can use them
// as the reconciliation oracle. The raw LLM read reconciles to the footer; if the
// later Textract overlay breaks that, the footer arbitrates the revert.
func (s *SmartPurchaseService) extractDutyFromGatePassLLMEx(ctx context.Context, images []SmartPurchaseImage) (*GatePassExtraction, error) {
	if len(images) == 0 {
		return nil, fmt.Errorf("no gate pass images provided")
	}

	prompt := `You are analyzing a UP (Uttar Pradesh) Department of Excise Transport Permit / Gate Pass.

✋ HANDWRITING POLICY (HARD RULE — read before anything else):
This document is ENTIRELY machine-printed by the excise department. Every value
you extract must come from the printed table. Treat ALL handwritten ink as
operator-personal NOISE and never include it in any field:
  - Margin notes, circled rows, ticks, asterisks, arrows, "OK" / "verified" stamps
  - Hand-tallied subtotals on the side / bottom
  - Pen strokes drawn through brand names or quantities
  - Any character whose slant / stroke thickness / ink-bleed differs from the
    printed table cells around it
If a printed cell appears struck-through with handwritten ink BUT the printed
digit underneath is still legible, USE THE PRINTED VALUE — never the strikeout.
Never invent a value to "explain" a handwritten mark.

THE DOCUMENT LAYOUT — memorize these 12 columns in order (left-to-right):
   1.  S.No                                      (serial number, anchors each row)
   2.  Brand                                     (authoritative brand name, all caps)
   3.  Liquor Type                               (FL / CL / IMFL)
   4.  Liquor Sub Type                           (Whisky / Vodka / Rum / Gin / Beer)
   5.  Description                               (long form brand+variant description)
   6.  Packaging Size                            (750 / 375 / 180 / 90 — in ML, no suffix)
   7.  Packaging Type                            (Glass Bottle / Pet Bottle / Tetra / Can)
   8.  No of Cases / Mono cartons Requested      (cases requested — IGNORE THIS)
   9.  No of Bottles Requested                   (bottles requested — IGNORE THIS)
  10.  No of Cases / Mono cartons Dispatched     ← USE THIS for "cases"
  11.  No of Bottles Dispatched                  ← USE THIS for "bottles"
  12.  Duty Fee                                  (last numeric column, in INR)

CRITICAL RULES — read these carefully, most extraction errors come from violating them:

A. ALWAYS read cases and bottles from the DISPATCHED columns (10 and 11), NOT the Requested
   columns (8 and 9). The two pairs often look alike — they're side-by-side — but Dispatched
   is what was actually shipped and what the invoice should match.

B. Cases and bottles are in TWO SEPARATE COLUMNS. NEVER read the same number twice for both.
   READ EACH CELL LITERALLY — do not infer one from the other.
   The "No of Cases Dispatched" cell and the "No of Bottles Dispatched" cell are independent
   physical printed numbers. Whatever the printed digit IS in each cell, that's the value.
   For most rows this satisfies: bottles == cases * standard_bpc
   where standard_bpc is:  750ml=12, 375ml=24, 180ml=48, 90ml=96, 1000ml=9
   BUT — LOOSE DISPATCH IS REAL and LEGAL. The depot can dispatch loose bottles (less than
   a full case) wrapped as outer packaging units. Example: row "2 cases, 2 bottles, 2450.24"
   on a 750ml row is a LOOSE DISPATCH of 2 individual bottles packaged as 2 separate outer
   wraps. The printed numbers are LITERAL: 2 cases-as-wraps, 2 bottles TOTAL. Do NOT
   "correct" this to 24 bottles by assuming standard_bpc — that would be inventing data.
   Heuristic: when bottles_dispatched < cases_dispatched * standard_bpc, the row is a loose
   dispatch and the bottles value is the actual physical count. Trust it.
   Heuristic: when bottles_dispatched > cases_dispatched * standard_bpc, the cases cell was
   probably mis-read — flag the row and prefer bottles_dispatched as ground truth.
   Heuristic: when the column appears to truly be mis-aligned (e.g. only ONE numeric cell on a
   12-column row), THEN re-read carefully. For beer the bpc may be 12 or 24.

C. Extract EVERY data row visible on this image, in S.No order. Each S.No appears EXACTLY ONCE
   in the table — do NOT emit the same S.No twice. Do NOT invent rows for non-existent S.Nos.
   The number of rows you emit MUST equal the number of distinct S.No entries you can see. If
   the image shows S.Nos 1-28, emit exactly 28 rows. If it shows 29-48, emit exactly 20 rows.
   Different S.Nos may carry the same brand+size (a brand can repeat across S.Nos with different
   batches) — keep both rows. But never duplicate the SAME S.No.

D. Return row_number = the S.No value as printed. Never renumber, never reorder.

E. Indian number formatting: "1,04,313.11" is the lakh convention = 104313.11 (NOT 1.04M). Always
   convert to plain decimal. Duty fees like "11147.52", "5921.28", "6341.76" are already plain.

F. FOOTER TOTALS — read these ONLY from the row labelled "Total" or "Grand Total" at the very
   bottom of the table:
   - total_cases       = the value in the "No of Cases Dispatched" column on the Total row.
   - total_bottles     = the value in the "No of Bottles Dispatched" column on the Total row.
   - total_duty        = the value in the Duty Fee column on the Total row (lakh-comma formatted).
   - total_bulk_litres = the "Total Bulk Litres" value in the Dispatched Details / footer
                         summary block (e.g. "Total Bulk Litres  334.80"). Plain decimal litres.
   If this image does NOT show the footer (mid-document page), set all four to 0.
   DO NOT confuse the "Total Requested" line with the "Total Dispatched" line. DO NOT sum
   "Requested + Dispatched" — they're separate columns, not separate rows.
   For this typical document the dispatched totals on the last page look like:
       Total | <skip> | 77 | 2671 | 434313.11
   (cases_dispatched=77, bottles_dispatched=2671, duty=434313.11). Numbers come from columns
   10, 11, 12 of the Total row — NOT 8, 9.

Return ONLY a JSON object. No markdown, no explanation:
{
  "items": [
    {
      "row_number": 1,
      "brand_name": "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY",
      "size": "375",
      "size_ml": 375,
      "cases": 3,
      "bottles": 72,
      "duty_fee": 15411.60
    }
  ],
  "total_cases": 77,
  "total_bottles": 2671,
  "total_duty": 434313.11,
  "total_bulk_litres": 657.30
}`

	// Use the OCR service to call AI with the gate pass images.
	// Aggregate items + footer totals across multiple images (large gate passes span pages).
	var allItems []GatePassDutyItem
	var footerTotalCases, footerTotalBottles int
	var footerTotalDuty, footerTotalLitres float64

	for i, img := range images {
		result, err := s.ocr.extractGatePassWithAI(ctx, img.Data, img.ContentType, prompt)
		if err != nil {
			log.Printf("SmartPurchase: Gate pass image %d extraction failed: %v", i, err)
			continue
		}
		// Only offset row_numbers when the AI restarted at 1 on this page. UP Excise gate
		// passes use continuing S.No across pages (page 2 starts with the next number after
		// page 1's last) — adding an offset there would double-count and rename row 29 to
		// row 57. Auto-detect: if this page's lowest S.No > existing max, the AI is using
		// cumulative numbering — leave numbers alone.
		minNew, maxExisting := -1, 0
		for _, ex := range allItems {
			if ex.RowNumber > maxExisting {
				maxExisting = ex.RowNumber
			}
		}
		for _, it := range result.Items {
			if it.RowNumber > 0 && (minNew == -1 || it.RowNumber < minNew) {
				minNew = it.RowNumber
			}
		}
		if minNew != -1 && minNew <= maxExisting {
			offset := maxExisting
			for j := range result.Items {
				if result.Items[j].RowNumber > 0 {
					result.Items[j].RowNumber += offset
				}
			}
		}
		// v1.0.238 — stamp 1-based page index for Excel export.
		for j := range result.Items {
			result.Items[j].PageIndex = i + 1
		}
		// v1.0.348 — drop footer/section "Total" artifacts the LLM emitted as
		// data rows (blank name + packaging_type "Total" + aggregate qty). The
		// Textract path already filters these (isGPTotalRow); the LLM path did
		// not, so they reached the operator as "not_found, no name, NN cases"
		// (Mahua Khera job 70047c55 rows 31-32). Filter, don't append blindly.
		for _, it := range result.Items {
			if isGPTotalArtifactItem(it) {
				log.Printf("SmartPurchase GP LLM: dropped footer/total artifact (name=%q packaging=%q cases=%d bottles=%d)",
					it.BrandName, it.PackagingType, it.Cases, it.Bottles)
				continue
			}
			allItems = append(allItems, it)
		}
		// Footer totals: take MAX, not SUM — only the last page carries the grand total.
		// Earlier pages report 0 (or, if the AI hallucinates a footer, the number is wrong
		// anyway); MAX picks the real grand-total row.
		if result.TotalCases > footerTotalCases {
			footerTotalCases = result.TotalCases
		}
		if result.TotalBottles > footerTotalBottles {
			footerTotalBottles = result.TotalBottles
		}
		if result.TotalDuty > footerTotalDuty {
			footerTotalDuty = result.TotalDuty
		}
		if result.TotalLitres > footerTotalLitres {
			footerTotalLitres = result.TotalLitres
		}
	}

	if len(allItems) == 0 {
		return nil, fmt.Errorf("no items extracted from gate pass")
	}

	// Defensive dedup: drop duplicates based on (RowNumber, BrandName, Size, Cases, Bottles)
	// composite key. The AI sometimes hallucinates duplicate rows when prompted aggressively
	// to "extract every row" — especially when there's heavy glare or a smudged area. Keep the
	// first occurrence of each composite, drop the rest. Per-row keys differ across legit
	// duplicates (different RowNumber), so this only kills true exact dupes.
	seen := make(map[string]bool, len(allItems))
	deduped := make([]GatePassDutyItem, 0, len(allItems))
	for _, it := range allItems {
		key := fmt.Sprintf("%d|%s|%d|%d|%d", it.RowNumber, strings.ToUpper(strings.TrimSpace(it.BrandName)), it.SizeML, it.Cases, it.Bottles)
		if seen[key] {
			continue
		}
		seen[key] = true
		deduped = append(deduped, it)
	}
	if len(deduped) < len(allItems) {
		log.Printf("SmartPurchase: GP dedup removed %d duplicate row(s) (%d → %d)", len(allItems)-len(deduped), len(allItems), len(deduped))
	}
	allItems = deduped

	// Post-parse column-integrity check for each row:
	// For IMFL sizes the invariant bottles == cases * standard_bpc must hold. Three failure
	// modes we auto-correct here, in priority order:
	//   (a) bottles == cases (same column read twice)                    → bottles := cases * bpc
	//   (b) bottles == 0     (bottles column skipped)                    → bottles := cases * bpc
	//   (c) bottles != cases*bpc AND cases != 0 AND |err| > tolerance    → log warning, trust cases * bpc
	// This lets downstream matching / stock math stay correct even when the AI mis-reads one
	// of the two dispatch columns.
	for i := range allItems {
		it := &allItems[i]
		bpc, ok := StandardCaseSizes[it.SizeML]
		if !ok || bpc <= 1 {
			continue // non-IMFL, skip
		}
		expected := it.Cases * bpc
		if it.Cases == 0 {
			continue // loose-bottle-only row, no case math to apply
		}
		if it.Bottles == it.Cases {
			log.Printf("  GP: correcting %s %sML: bottles %d→%d (same-column double-read)", it.BrandName, it.Size, it.Bottles, expected)
			it.Bottles = expected
		} else if it.Bottles == 0 {
			log.Printf("  GP: correcting %s %sML: bottles 0→%d (bottles column missing)", it.BrandName, it.Size, expected)
			it.Bottles = expected
		} else if it.Bottles != expected {
			// Off by more than one box — likely a case/bottle transpose or partial case
			log.Printf("  GP: WARN %s %sML: cases=%d bpc=%d expected bottles %d, got %d (discrepancy kept)", it.BrandName, it.Size, it.Cases, bpc, expected, it.Bottles)
		}
	}

	// Footer-total reconciliation: compare AI-reported footer totals to the sum of rows.
	// When they disagree by more than a small tolerance, rows were dropped or mis-read.
	var sumCases, sumBottles int
	for _, it := range allItems {
		sumCases += it.Cases
		sumBottles += it.Bottles
	}
	if footerTotalCases > 0 && absInt(footerTotalCases-sumCases) > 1 {
		log.Printf("SmartPurchase: GP footer MISMATCH — footer total_cases=%d, sum of rows=%d (likely dropped rows)", footerTotalCases, sumCases)
	}
	if footerTotalBottles > 0 && absInt(footerTotalBottles-sumBottles) > bpcTolerance(allItems) {
		log.Printf("SmartPurchase: GP footer MISMATCH — footer total_bottles=%d, sum of rows=%d", footerTotalBottles, sumBottles)
	}

	log.Printf("SmartPurchase: Extracted %d duty items from gate pass (footer: %d cases / %d bottles, sum: %d cases / %d bottles)",
		len(allItems), footerTotalCases, footerTotalBottles, sumCases, sumBottles)
	for _, item := range allItems {
		log.Printf("  GP[%d]: %s %sML: %d cases, %d bottles, duty=%.2f", item.RowNumber, item.BrandName, item.Size, item.Cases, item.Bottles, item.DutyFee)
	}

	return &GatePassExtraction{
		Items:        allItems,
		TotalCases:   footerTotalCases,
		TotalBottles: footerTotalBottles,
		TotalDuty:    footerTotalDuty,
		TotalLitres:  footerTotalLitres,
	}, nil
}

func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// bpcTolerance is a sloppy bottle-count tolerance for footer reconciliation — up to
// 1 "box" (biggest BPC in the items) of drift is OK because the AI may round a partial
// case differently from the footer.
func bpcTolerance(items []GatePassDutyItem) int {
	maxBPC := 12
	for _, it := range items {
		if bpc, ok := StandardCaseSizes[it.SizeML]; ok && bpc > maxBPC {
			maxBPC = bpc
		}
	}
	return maxBPC
}

// fuzzyMatchBrandSize matches bill items to gate pass items by brand name and size
// fuzzyMatchBrandSize checks if an invoice brand+size matches a gate pass brand+size.
// Returns a score 0.0-1.0. Higher = better match. 0 = no match.
func (s *SmartPurchaseService) fuzzyMatchBrandSize(billBrand, billSize, gpBrand, gpSize string) float64 {
	b1 := strings.ToLower(strings.TrimSpace(billBrand))
	b2 := strings.ToLower(strings.TrimSpace(gpBrand))
	s1 := strings.ToLower(strings.TrimSpace(billSize))
	s2 := strings.ToLower(strings.TrimSpace(gpSize))

	// Normalize size - remove ML/ml suffix.
	// v1.0.215.8 — also strip "mi" (OCR confuses ML→MI when the L's
	// vertical stroke looks like an I). Real-data trigger: bill row
	// "Jamenson Irish 750 MI Whisky" had size "750 MI" → after old
	// normalize "750mi" vs GP "750" → s1!=s2 → return 0.
	for _, noise := range []string{"ml", "mt", "mi", "ltr", " "} {
		s1 = strings.ReplaceAll(s1, noise, "")
		s2 = strings.ReplaceAll(s2, noise, "")
	}

	if s1 != s2 {
		return 0
	}

	// Brand matching: bidirectional significant word overlap.
	// v1.0.209 — fillers extended to category names + their bill-side
	// abbreviations. Real-data trigger: chhotu's 2026-05-08 bill paired ZERO
	// of 35 GP rows because bills print "Mcd Original Why 375ml" while GP
	// prints "McDowell's No.1 Original Whisky 375ml" — the "why" abbreviation
	// counted as one of bill's three significant words while gp's "whisky"
	// was a discriminative match-target. Adding both to fillers leaves
	// {mcd, original} (bill) vs {mcdowells, no.1, original} (gp) — far higher
	// match coverage. The earlier comment claimed category words are
	// discriminative for variants; that was true ONLY when bill+gp printed
	// the same category text. Real bills use abbreviations gp doesn't, so
	// the "discriminative" property never held.
	// v1.0.215.8 — pre-tokenize: split tokens that have an embedded size
	// (e.g. "WHY375ML" → ["why", "375ml"]; "Why.750ml" → ["why", "750ml"]).
	// Real-data trigger: bill brand "ROYAL GREEN WHY375ML" had "why375ml"
	// as a single 8-char token, which never matched any GP word, dragging
	// the score below 0.60. Splitting recovers the "375ml" size-filter
	// path AND prevents the typo-noise from polluting the significant-word
	// count.
	embeddedSizeRe := regexp.MustCompile(`(?i)([a-z]+)[\.\s]*(\d{2,4}\s*(?:ml|mt|l|cl|ltr)\.?)`)
	tokenize := func(s string) []string {
		out := strings.Fields(s)
		split := make([]string, 0, len(out))
		for _, w := range out {
			// Try to extract trailing size from words like "why375ml".
			matches := embeddedSizeRe.FindStringSubmatch(w)
			if len(matches) == 3 && len(matches[1]) >= 2 {
				split = append(split, strings.ToLower(matches[1]))
				split = append(split, strings.ToLower(strings.ReplaceAll(matches[2], " ", "")))
			} else {
				split = append(split, w)
			}
		}
		return split
	}
	words1 := tokenize(b1)
	words2 := tokenize(b2)
	fillers := map[string]bool{
		"fl": true, "of": true, "and": true, "the": true, "pet": true,
		"ml": true,
		// Category names (gp side) + bill abbreviations.
		"whisky": true, "whiskey": true, "why": true, "why.": true,
		"rum": true, "vodka": true, "gin": true, "brandy": true,
		"beer": true, "scotch": true, "wine": true,
		// v1.0.215.8 — packaging-type fillers. "Tetra"/"Can"/"Glass"/
		// "Bottle" appear inconsistently between bill (printed by
		// supplier) and GP (excise format), so treating them as
		// non-discriminative restores otherwise-valid pairs like
		// "8pm Gold Scotch Whisky Tetra 180ml" ↔ "8PM Gold Blend".
		"tetra": true, "can": true, "glass": true, "bottle": true,
	}

	// v1.0.215.8 — also treat size-like tokens (digits+ml suffix) as fillers.
	// Real-data trigger: bill brand "ROYAL GREEN WHY 750ML" had "750ml" as
	// a significant word, dragging the forward match (vs GP "Royal Green
	// Reserve Blended Whisky" which had NO "750ml" token in the brand text)
	// from 2/2=1.0 down to 2/3=0.67. Score (0.67+0.5)/2 = 0.58, just below
	// the 0.60 threshold. Filtering tokens like "750ml", "180ml", "90ml" etc
	// brings the match back to 0.75 and recovers the orphan pair.
	sizeTokenPattern := regexp.MustCompile(`^\d{2,4}(ml|mt|l|cl|ltr)\.?$`)
	isSizeToken := func(w string) bool {
		return sizeTokenPattern.MatchString(w)
	}

	// v1.0.215.8 — wordMatch now also accepts Levenshtein distance ≤ 1
	// for words of length ≥ 5. Real-data trigger: chhotu's bill prints
	// "vodca" (typo for "vodka"), "Jamenson" (typo for "Jameson"), and
	// the GP's authoritative excise text uses the correct spelling.
	// Without typo-tolerance, bill row "Magic Moments Orange Vodca" never
	// pairs to GP row "Magic Moments Remix Orange Flavoured Vodka". The
	// substring check (Contains) doesn't help because "vodca" doesn't
	// contain "vodka" and vice-versa. Levenshtein-1 catches single
	// substitutions (a↔c) and single deletions (Jamenson→Jameson).
	//
	// Min-length 5 prevents over-matching short common words (e.g. "Why"
	// vs "Was" both length 3, distance 2 — not relevant here, but the
	// guard protects against accidental too-loose acceptance).
	wordMatch := func(w1, w2 string) bool {
		if w1 == w2 || strings.Contains(w1, w2) || strings.Contains(w2, w1) {
			return true
		}
		if len(w1) >= 5 && len(w2) >= 5 && levenshteinDistance(w1, w2) <= 1 {
			return true
		}
		return false
	}

	// Forward: how many significant invoice words appear in gate pass?
	sig1 := 0
	match1 := 0
	for _, w1 := range words1 {
		if fillers[w1] || isSizeToken(w1) || len(w1) < 3 {
			continue
		}
		sig1++
		for _, w2 := range words2 {
			if wordMatch(w1, w2) {
				match1++
				break
			}
		}
	}

	// Reverse: how many significant gate pass words appear in invoice?
	sig2 := 0
	match2 := 0
	for _, w2 := range words2 {
		if fillers[w2] || isSizeToken(w2) || len(w2) < 3 {
			continue
		}
		sig2++
		for _, w1 := range words1 {
			if wordMatch(w1, w2) {
				match2++
				break
			}
		}
	}

	if sig1 == 0 || sig2 == 0 {
		return 0
	}

	// Bidirectional: average of forward and reverse coverage
	fwd := float64(match1) / float64(sig1)
	rev := float64(match2) / float64(sig2)

	// v1.0.215.8 — relaxed rev-floor when fwd is perfect AND bill has ≥2
	// significant words. Real-data trigger: bill row "Pm Black Whisky 375ML"
	// (after filters: ["pm", "black"]) is a clean SUBSET of GP "8 PM
	// Premium Black Superior Whisky" (after filters: ["premium", "black",
	// "superior"]) — fwd=2/2=1.0 but rev=1/3=0.33 trips the 0.4 floor.
	// The bill being short is NOT a sign of mis-match; it's a sign the
	// distributor printed an abbreviated SKU label. Allow rev as low as
	// 0.30 when fwd ≥ 0.8 AND sig1 ≥ 2 (proves the bill isn't a 1-word
	// fluke match like a single shared category).
	revFloor := 0.4
	if fwd >= 0.8 && sig1 >= 2 {
		revFloor = 0.30
	}
	// Both directions must have strong match — weak 0.55 scores were overriding
	// invoice→product matches incorrectly. Raise the floor.
	if fwd < 0.5 || rev < revFloor {
		return 0
	}

	return (fwd + rev) / 2.0
}

// validateBillVsGatePass cross-validates a single bill row against its
// matched gate-pass row. Returns the list of disagreement flags + the chosen
// resolution source ("bill" / "gate_pass" / "disputed" / "" when no GP).
//
// 100% rule (v1.0.193): when the two documents AGREE → ship; when they
// DISAGREE → flag, never silently pick. The operator sees both values
// side-by-side and chooses.
//
// Resolution policy (lines 1.5.2 of the plan):
//
//   1. Bill row math is internally consistent (qty × rate ≈ amount AND
//      cases × pack_size == total_bottles): trust BILL.
//   2. Bill math fails AND GP is consistent (gp.bottles == gp.cases × pack_size):
//      trust GATE PASS, re-derive bill amount as gp.bottles × rate.
//   3. Bill and GP DISAGREE on bottle count by > 1: needs_review = true,
//      status = "quantity_disputed", surface both. NO silent pick.
//   4. Bill row but no GP match: warn "not in dispatch", needs_review=true.
//   5. GP row but no bill row: caller adds to OrphanGatePassRows.
func (s *SmartPurchaseService) validateBillVsGatePass(
	bill *ExtractedPurchaseItem,
	gp *GatePassDutyItem,
	gpOnly bool,
) ([]CrossValFlag, string) {

	var flags []CrossValFlag

	// Case 5 — bill exists, GP missing for this row. Caller has already
	// gone through buildGatePassBrandMap; if gp is nil here it means the
	// fuzzy matcher couldn't find a partner above the 0.60 threshold.
	if gp == nil {
		// Only flag when at least one GP image was actually uploaded — passing
		// nil to a no-gate-pass-uploaded job shouldn't fire a "missing from
		// dispatch" warning. The caller decides this; here we just observe.
		flags = append(flags, CrossValFlag{
			Kind:     "bill_only_no_gp",
			Severity: "info",
			Detail:   "Brand+size not present in dispatch — verify with supplier or check if dispatch was split",
		})
		return flags, ""
	}

	sizeML := int(bill.SizeML + 0.5)

	// 1. Brand identity check.
	billSizeStr := bill.SizeText
	if billSizeStr == "" && sizeML > 0 {
		billSizeStr = fmt.Sprintf("%dML", sizeML)
	}
	gpSizeStr := gp.Size
	if gpSizeStr == "" && gp.SizeML > 0 {
		gpSizeStr = fmt.Sprintf("%dML", gp.SizeML)
	}
	brandScore := s.fuzzyMatchBrandSize(bill.Brand, billSizeStr, gp.BrandName, gpSizeStr)
	if brandScore < 0.5 {
		flags = append(flags, CrossValFlag{
			Kind:          "brand_disagreement",
			Severity:      "warn",
			BillValue:     bill.Brand,
			GatePassValue: gp.BrandName,
			Detail:        fmt.Sprintf("Bill brand %q vs gate-pass excise name %q (token overlap %.0f%%) — confirm same product", bill.Brand, gp.BrandName, brandScore*100),
		})
	}

	// 2. Size identity. Strict; the fuzzy matcher already returns 0 on size
	// mismatch but a row may have squeaked through with sizeML=0 if the OCR
	// missed the size cell. Re-check explicitly.
	if sizeML > 0 && gp.SizeML > 0 && sizeML != gp.SizeML {
		flags = append(flags, CrossValFlag{
			Kind:          "size_disagreement",
			Severity:      "warn",
			BillValue:     fmt.Sprintf("%dml", sizeML),
			GatePassValue: fmt.Sprintf("%dml", gp.SizeML),
			Detail:        "Bill size doesn't match gate-pass size — likely a column-drift on one of the two documents",
		})
	}

	// 3. Pack-size + bottle-count math. Authoritative pack size from the
	// shared table (legally-fixed values; see pkg/shared/inventory/pack_sizes.go).
	bpc, knownPack := sharedinv.PackSize(sizeML)
	billCases := int(bill.QuantityRaw + 0.5)
	if bill.QuantityUnit == "bottles" {
		billCases = 0 // bill row is denominated in bottles, not cases
	}
	billBottles := int(bill.QuantityBottles + 0.5)

	// 3a. Pack-size violation on the bill itself: cases × pack_size != bottles.
	// Fires only when both legs are populated AND we know the standard pack.
	// v1.0.359 — suppressed under GP-only: the bill's quantity is ignored entirely
	// (we take only cost/vendor/TCS from it), so a bill pack-math glitch like
	// "24 for 180ml" must NOT surface as a mismatch — the GP's 48 is authoritative.
	if !gpOnly && knownPack && billCases > 0 && billBottles > 0 && billCases*bpc != billBottles {
		flags = append(flags, CrossValFlag{
			Kind:      "pack_size_violation",
			Severity:  "warn",
			BillValue: fmt.Sprintf("%d cases × %d/case → %d bottles (got %d)", billCases, bpc, billCases*bpc, billBottles),
			Detail:    fmt.Sprintf("%dml standard pack is %d bottles/case — bill row's case×pack math doesn't reconcile", sizeML, bpc),
		})
	}

	// 3b. Pack-size violation on gate-pass: gp.cases × pack_size != gp.bottles.
	// Rare on legitimate dispatches (the gate-pass form printer enforces the
	// math) but happens when AI mis-read a digit; surface so operator catches.
	if knownPack && gp.Cases > 0 && gp.Bottles > 0 && gp.Cases*bpc != gp.Bottles {
		flags = append(flags, CrossValFlag{
			Kind:          "pack_size_violation",
			Severity:      "warn",
			GatePassValue: fmt.Sprintf("%d cases × %d/case → %d bottles (got %d)", gp.Cases, bpc, gp.Cases*bpc, gp.Bottles),
			Detail:        fmt.Sprintf("Gate-pass row case×pack math doesn't reconcile for %dml", sizeML),
		})
	}

	// 4. Cross-document bottle-count comparison. Both sides reduced to bottles
	// for an apples-to-apples check. Tolerance ±1 absorbs the rare partial-
	// case rounding the AI does.
	billBottlesEff := billBottles
	if billBottlesEff == 0 && knownPack && billCases > 0 {
		billBottlesEff = billCases * bpc
	}
	gpBottlesEff := gp.Bottles
	if gpBottlesEff == 0 && knownPack && gp.Cases > 0 {
		gpBottlesEff = gp.Cases * bpc
	}

	bottleDiff := billBottlesEff - gpBottlesEff
	if bottleDiff < 0 {
		bottleDiff = -bottleDiff
	}

	// Bill math sanity (used to decide bill-vs-GP precedence below).
	billMathOK := false
	if knownPack && billCases > 0 && billBottlesEff == billCases*bpc {
		billMathOK = true
	}
	if knownPack && bill.QuantityUnit == "bottles" && billBottlesEff > 0 {
		billMathOK = true
	}

	// v1.0.359 — GP-only: the bill's bottle count is ignored entirely; the gate
	// pass ALWAYS wins and we never block or resolve to the bill. Surface at most
	// an info chip when the two differ so the operator can sanity-check the
	// bill↔GP cost pairing, then resolve to the gate pass.
	if gpOnly {
		if bottleDiff > 1 {
			flags = append(flags, CrossValFlag{
				Kind:          "bottle_count_mismatch",
				Severity:      "info",
				BillValue:     fmt.Sprintf("%d bottles", billBottlesEff),
				GatePassValue: fmt.Sprintf("%d bottles", gpBottlesEff),
				Detail:        "Bill bottle count differs from gate pass — gate pass used (bill is cost-only).",
			})
		}
		return flags, "gate_pass"
	}

	switch {
	case bottleDiff == 0:
		// Documents agree — happy path. Trust the bill (which == GP anyway).
		return flags, "bill"

	case bottleDiff <= 1:
		// Within tolerance (split-shipment / rounding artifact). Trust bill.
		flags = append(flags, CrossValFlag{
			Kind:          "bottle_count_mismatch",
			Severity:      "info",
			BillValue:     fmt.Sprintf("%d bottles", billBottlesEff),
			GatePassValue: fmt.Sprintf("%d bottles", gpBottlesEff),
			Detail:        "Within ±1 tolerance — bill trusted",
		})
		return flags, "bill"

	case billMathOK && (gp.Cases*bpc != gp.Bottles || gp.Bottles <= 0):
		// Bill math passes, GP math doesn't — trust the bill (operator
		// reading the bill, not the GP, when discrepancies exist on GP).
		flags = append(flags, CrossValFlag{
			Kind:          "bottle_count_mismatch",
			Severity:      "warn",
			BillValue:     fmt.Sprintf("%d bottles (math ✓)", billBottlesEff),
			GatePassValue: fmt.Sprintf("%d bottles (math ✗)", gpBottlesEff),
			Detail:        "Bill math is internally consistent; gate-pass row appears mis-OCR'd. Used bill values.",
		})
		return flags, "bill"

	case !billMathOK && knownPack && gp.Cases > 0 && gp.Cases*bpc == gp.Bottles:
		// Bill math fails, GP math passes — flag and prefer GP. Operator
		// sees the disagreement chip but the system's resolution leans on
		// the GP because the bill's own row is inconsistent.
		flags = append(flags, CrossValFlag{
			Kind:          "bottle_count_mismatch",
			Severity:      "warn",
			BillValue:     fmt.Sprintf("%d bottles (math ✗)", billBottlesEff),
			GatePassValue: fmt.Sprintf("%d bottles (math ✓)", gpBottlesEff),
			Detail:        "Bill row math doesn't reconcile; gate-pass values used (re-verify with supplier).",
		})
		return flags, "gate_pass"

	default:
		// Both documents have plausible numbers but they DISAGREE by more
		// than 1 bottle. NEVER silently pick — surface to operator.
		flags = append(flags, CrossValFlag{
			Kind:          "quantity_disputed",
			Severity:      "block",
			BillValue:     fmt.Sprintf("%d bottles", billBottlesEff),
			GatePassValue: fmt.Sprintf("%d bottles", gpBottlesEff),
			Detail:        fmt.Sprintf("Bill says %d, gate-pass says %d (Δ%d bottles) — operator must reconcile before apply", billBottlesEff, gpBottlesEff, bottleDiff),
		})
		return flags, "disputed"
	}
}

// computeOrphanGatePassRows returns the GP rows that didn't get matched to
// any bill row. Caller surfaces them as a banner on the review screen so the
// operator can decide whether to add as missing line items.
func (s *SmartPurchaseService) computeOrphanGatePassRows(
	dutyItems []GatePassDutyItem,
	gatePassItemMap map[int]*GatePassDutyItem,
) []OrphanGatePassRow {
	if len(dutyItems) == 0 {
		return nil
	}
	matchedGPRows := map[int]bool{}
	for _, gp := range gatePassItemMap {
		if gp != nil {
			matchedGPRows[gp.RowNumber] = true
		}
	}
	out := make([]OrphanGatePassRow, 0, 4)
	for _, gp := range dutyItems {
		if matchedGPRows[gp.RowNumber] {
			continue
		}
		out = append(out, OrphanGatePassRow{
			GatePassRowNumber: gp.RowNumber,
			BrandName:         gp.BrandName,
			SizeML:            gp.SizeML,
			Cases:             gp.Cases,
			Bottles:           gp.Bottles,
			DutyFee:           gp.DutyFee,
			Detail:            "Dispatched but no matching bill row — verify with supplier or add as missing line",
		})
	}
	return out
}
