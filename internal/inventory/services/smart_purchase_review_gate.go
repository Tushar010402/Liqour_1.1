package services

import (
	"fmt"
	"log"
	"math"
	"os"
	"sort"
	"strings"
)

// ============================================================================
// v1.0.216 — Mandatory review-warning gate for Smart Purchase apply.
//
// Background
// ----------
// Pre-v1.0.216 the Apply endpoint accepted every payload Flutter posted, even
// when the operator hadn't acknowledged a math-fail, variant-mismatch, or
// pack-size violation. The handler comment claimed a 422 was emitted; in
// practice no such check existed. A stale Flutter client, a typoed curl, or
// any third-party integration could bypass every pre-submit dialog.
//
// v1.0.216 also adds a NEW class of block — duplicate (canonical_brand,
// size_ml) rows in the same payload — to honour Tushar's "100% accuracy +
// no duplicacy with name and size" requirement (2026-05-11).
//
// Mirrors the Smart Sale review gate at
// `internal/sales/services/smart_sale_review_gate.go`.
//
// Behaviour
// ---------
// • Every blocking warning derived from the payload MUST appear in the row's
//   UserConfirmedWarnings before apply proceeds.
// • Duplicate rows by product_id OR by (lowered+trimmed brand_name, size_ml)
//   block unconditionally — the operator MUST merge or rename one of the
//   conflicting rows on the review screen first.
// • SMART_PURCHASE_MANDATORY_REVIEW=0 → log-only mode for emergency rollback.
//
// Multi-tenant
// ------------
// Structural only. No per-tenant config; same gate applies to every tenant.
// ============================================================================

// blockingPurchaseWarnings lists every warning substring this gate recognises.
// Match semantics: case-insensitive substring against the row's
// UserConfirmedWarnings entries.
var blockingPurchaseWarnings = []string{
	"math_fail",                  // qty × rate ≠ amount
	"pack_size_violation",        // cases × bpc ≠ bottles
	"variant_mismatch",           // cross-variant resolution
	"quantity_disputed",          // bill vs gate-pass qty disagree
	"cost_exceeds_mrp",           // cost > master MRP — operator must ack
	"zero_cost",                  // line item has cost_price ≤ 0
	"duplicate_product",          // same canonical brand+size in payload
	// v1.0.226 — Purcha gate (mandatory pre-review confirmation).
	"purcha_qty_mismatch",        // Purcha bottles count ≠ GP bottles count
	"purcha_skipped",             // operator used the escape-hatch dialog
}

// PurchaseRejectedRow describes a single row that failed the gate. Surfaced
// verbatim in the 422 body so Flutter can scroll to + highlight the offender.
//
// v1.0.232 — additional payload context so the Flutter rejected-rows sheet can
// render numbers + cross-references inline without re-walking local state.
// New fields are omitempty so old Flutter clients ignore them safely.
type PurchaseRejectedRow struct {
	Position            int      `json:"position"`             // 1-based order in req.Items as posted
	ProductID           string   `json:"product_id,omitempty"`
	ProductName         string   `json:"product_name"`         // BrandName fallback to "(unnamed row)"
	UnconfirmedWarnings []string `json:"unconfirmed_warnings"` // exact strings the operator has not yet confirmed

	// DuplicatePartnerPositions — 1-based positions of OTHER rows that
	// duplicate this one (same product_id OR same canonical brand+size). Empty
	// unless `duplicate_product` is in UnconfirmedWarnings. Lets the sheet
	// render "duplicates row 18 and 24" + scroll-to those rows.
	DuplicatePartnerPositions []int `json:"duplicate_partner_positions,omitempty"`

	// Echo of the apply payload's row math so the sheet can show concrete
	// numbers (e.g. "cost ₹0 · 12 bottles · ₹3000 expected") without needing
	// the Flutter side to re-look it up.
	CostPrice float64 `json:"cost_price,omitempty"`
	Bottles   int     `json:"bottles,omitempty"`
	Amount    float64 `json:"amount,omitempty"`
	SizeML    int     `json:"size_ml,omitempty"`

	// SuggestedFix — short, operator-readable hint per warning class. Empty
	// when the warning set has no canonical fix (purcha_qty_mismatch already
	// has its own 4-way sheet in Flutter; we don't override that copy).
	SuggestedFix string `json:"suggested_fix,omitempty"`
}

// PurchaseReviewGateResult summarises the outcome of ValidatePurchaseApply.
// Enforced=true → caller MUST 422 with Rejected. Enforced=false → log-only.
type PurchaseReviewGateResult struct {
	Rejected []PurchaseRejectedRow
	Enforced bool
}

// ValidatePurchaseApply walks every item, derives blocking warnings from the
// payload itself (deterministic), and matches against UserConfirmedWarnings.
// Also detects duplicate (canonical_brand_name, size_ml) and product_id rows
// in the same payload.
func ValidatePurchaseApply(items []SmartPurchaseApplyItem, docConfirmed []string) PurchaseReviewGateResult {
	enforced := os.Getenv("SMART_PURCHASE_MANDATORY_REVIEW") != "0"

	// ── Duplicate detection (whole-payload) ─────────────────────────────
	// v1.0.232 — track ALL prior occurrences per dup-key, not just the first.
	// Pre-v232 (and the initial v232 cut) used map[string]int → on row 3 of a
	// 3-row dup group, only row 1 was relinked (because dupByProductID[pid]
	// returned the first-seen, not the most-recent). Result: row 3 listed
	// partner [1] but never [2], and row 2 never saw [3]. Chhotu's real bill
	// has the same product at positions 1/18/24 — operator fixing row 18
	// would see "duplicates row 1" only and silently miss row 24. Fix: link
	// the new occurrence to EVERY prior occurrence so the group is fully
	// connected.
	type dupKey struct{ brand, size string }
	dupByBrandSize := make(map[dupKey][]int)
	dupByProductID := make(map[string][]int)
	flaggedDup := make(map[int]bool) // 1-based index → has duplicate warning
	// Partner positions per offender, threaded into
	// PurchaseRejectedRow.DuplicatePartnerPositions so the Flutter rejected-
	// rows sheet can render "duplicates row 18 and 24" with tap-to-scroll.
	// Keyed on 1-based position. Each entry is a set (we use a tiny
	// map[int]bool because typical N ≤ 3, then flattened + sorted on emit).
	dupPartners := make(map[int]map[int]bool)
	linkDup := func(a, b int) {
		if a == b {
			return
		}
		if dupPartners[a] == nil {
			dupPartners[a] = make(map[int]bool)
		}
		if dupPartners[b] == nil {
			dupPartners[b] = make(map[int]bool)
		}
		dupPartners[a][b] = true
		dupPartners[b][a] = true
	}
	for i, it := range items {
		// Skip zero-bottle rows — they don't write anything to stocks
		// regardless of dedup, and skipping them avoids false positives
		// when the operator splits a row by zeroing one half.
		bottles := it.Bottles
		if bottles == 0 && it.BottlesPerCase > 0 && it.Cases > 0 {
			bottles = it.Cases * it.BottlesPerCase
		}
		if bottles <= 0 {
			continue
		}
		brand := strings.ToLower(strings.TrimSpace(it.BrandName))
		// Drop trailing/leading non-alphanumeric noise for the dedup key.
		brand = strings.Trim(brand, " -.,_/")
		if brand != "" {
			key := dupKey{brand: brand, size: fmt.Sprintf("%dml", it.SizeML)}
			if priors := dupByBrandSize[key]; len(priors) > 0 {
				flaggedDup[i+1] = true
				for _, prev := range priors {
					flaggedDup[prev+1] = true
					linkDup(prev+1, i+1)
					log.Printf("SmartPurchase dedup: duplicate brand+size '%s'/%dml at positions %d and %d",
						brand, it.SizeML, prev+1, i+1)
				}
			}
			dupByBrandSize[key] = append(dupByBrandSize[key], i)
		}
		if pid := strings.TrimSpace(it.ProductID); pid != "" {
			if priors := dupByProductID[pid]; len(priors) > 0 {
				flaggedDup[i+1] = true
				for _, prev := range priors {
					flaggedDup[prev+1] = true
					linkDup(prev+1, i+1)
					log.Printf("SmartPurchase dedup: duplicate product_id %s at positions %d and %d",
						pid, prev+1, i+1)
				}
			}
			dupByProductID[pid] = append(dupByProductID[pid], i)
		}
	}

	confirmedDoc := normalizePurchaseConfirmations(docConfirmed)

	var rejected []PurchaseRejectedRow
	for i, it := range items {
		// Skip rows that don't write anything to inventory.
		bottles := it.Bottles
		if bottles == 0 && it.BottlesPerCase > 0 && it.Cases > 0 {
			bottles = it.Cases * it.BottlesPerCase
		}
		if bottles <= 0 {
			continue
		}

		blocking := derivePurchaseBlockingWarnings(it)
		if flaggedDup[i+1] {
			blocking = append(blocking, "duplicate_product")
		}
		if len(blocking) == 0 {
			continue
		}

		confirmed := normalizePurchaseConfirmations(it.UserConfirmedWarnings)
		// Document-level confirmations apply to every row.
		for k, v := range confirmedDoc {
			confirmed[k] = v
		}
		var unconfirmed []string
		for _, w := range blocking {
			if !isPurchaseWarningConfirmed(w, confirmed) {
				unconfirmed = append(unconfirmed, w)
			}
		}
		if len(unconfirmed) == 0 {
			continue
		}

		sort.Strings(unconfirmed)
		name := strings.TrimSpace(it.BrandName)
		if name == "" {
			name = "(unnamed row)"
		}

		// v1.0.232 — flatten partner positions for this row (1-based, sorted).
		var partners []int
		for p := range dupPartners[i+1] {
			partners = append(partners, p)
		}
		sort.Ints(partners)

		// v1.0.232 — suggested-fix copy keyed on the strongest blocking
		// warning. Order matches user-priority (zero_cost is more concrete
		// than math_fail; duplicate_product takes precedence over both
		// because the partner positions UI is the natural fix path).
		suggested := suggestedFixForWarnings(unconfirmed)

		rejected = append(rejected, PurchaseRejectedRow{
			Position:                  i + 1,
			ProductID:                 it.ProductID,
			ProductName:               name,
			UnconfirmedWarnings:       unconfirmed,
			DuplicatePartnerPositions: partners,
			CostPrice:                 it.CostPrice,
			Bottles:                   bottles,
			Amount:                    it.Amount,
			SizeML:                    it.SizeML,
			SuggestedFix:              suggested,
		})
	}

	if len(rejected) > 0 {
		log.Printf("SmartPurchase: review-gate flagged %d rows (enforced=%v) — first row: pos=%d name=%s warnings=%v",
			len(rejected), enforced, rejected[0].Position, rejected[0].ProductName, rejected[0].UnconfirmedWarnings)
	}

	return PurchaseReviewGateResult{Rejected: rejected, Enforced: enforced}
}

// derivePurchaseBlockingWarnings reconstructs the blocking-warning set from
// the apply-payload's own deterministic signals. The /process cache may be
// gone by apply time, so we recompute from the echoed fields.
//
// Signals checked:
//   • math_fail:           cases*bpc*cost_per_bottle vs amount (±₹1 tolerance)
//   • pack_size_violation: cases × bottles_per_case ≠ bottles (when both set)
//   • zero_cost:           cost_price ≤ 0 → silently dropped without this guard
//
// Variant mismatch + quantity dispute + cost-exceeds-MRP are surfaced by the
// extraction-time validators and echoed by Flutter in UserConfirmedWarnings.
// We do NOT re-derive them server-side — those depend on master catalog
// state we don't want to refetch per row.
func derivePurchaseBlockingWarnings(it SmartPurchaseApplyItem) []string {
	var out []string

	bottles := it.Bottles
	if bottles == 0 && it.BottlesPerCase > 0 && it.Cases > 0 {
		bottles = it.Cases * it.BottlesPerCase
	}

	// Pack-size violation (only check when caller gave us both BPC + cases).
	if it.BottlesPerCase > 0 && it.Cases > 0 && it.Bottles > 0 {
		expected := it.Cases * it.BottlesPerCase
		if expected != it.Bottles {
			out = append(out, "pack_size_violation")
		}
	}

	// Math: bottles × cost_price should be ≈ amount (±₹1 tolerance).
	if it.CostPrice > 0 && it.Amount > 0 && bottles > 0 {
		expected := float64(bottles) * it.CostPrice
		if math.Abs(expected-it.Amount) > 1.0 {
			out = append(out, "math_fail")
		}
	}

	// Zero cost lines silently drop in legacy code. Block them so they're
	// visible to the operator.
	if it.CostPrice <= 0 && bottles > 0 {
		out = append(out, "zero_cost")
	}

	// v1.0.238 — Purcha gate REMOVED. PurchaSkipped/PurchaConfirmed/
	// PurchaQtyObserved fields are no longer part of SmartPurchaseApplyItem.
	// AI Purchase now relies on Bill+GP reconciliation (Track B) instead of
	// operator-uploaded photos. The "purcha_skipped" and "purcha_qty_mismatch"
	// strings remain in `purchaseBlockingWarnings` only for backward compat
	// with old APKs whose payloads might still send them — they'll simply
	// never be raised by the new gate logic.

	return out
}

// normalizePurchaseConfirmations lowercases + trims every confirmation
// string for substring matching. Returns a map for O(1) lookup.
func normalizePurchaseConfirmations(in []string) map[string]bool {
	out := make(map[string]bool, len(in))
	for _, s := range in {
		t := strings.ToLower(strings.TrimSpace(s))
		if t == "" {
			continue
		}
		out[t] = true
	}
	return out
}

// isPurchaseWarningConfirmed returns true when any confirmation string is a
// case-insensitive substring of the warning OR vice versa. Generous match
// so Flutter can echo the verbatim warning text it rendered.
func isPurchaseWarningConfirmed(warning string, confirmed map[string]bool) bool {
	w := strings.ToLower(warning)
	for c := range confirmed {
		if strings.Contains(w, c) || strings.Contains(c, w) {
			return true
		}
	}
	return false
}

// suggestedFixForWarnings — v1.0.232. Returns a short operator-readable hint
// for the strongest blocking warning in `unconfirmed`. Order matches the
// priority an operator should fix in: duplicates first (because the partner-
// position UI is the natural resolution), then zero-cost (concrete number
// input), then math-fail (review the qty/cost/amount cells), then the rest.
// Empty when the warning set already has a dedicated UI flow.
func suggestedFixForWarnings(unconfirmed []string) string {
	has := func(needle string) bool {
		for _, w := range unconfirmed {
			if w == needle {
				return true
			}
		}
		return false
	}
	switch {
	case has("duplicate_product"):
		return "Same product appears on another row. Merge or confirm both."
	case has("zero_cost"):
		return "Enter the cost per bottle for this row."
	case has("math_fail"):
		return "Check qty × cost vs amount."
	case has("pack_size_violation"):
		return "Cases × bottles-per-case should equal total bottles."
	case has("cost_exceeds_mrp"):
		return "Cost is higher than master MRP — confirm or correct."
	case has("variant_mismatch"):
		return "Size or pack variant differs from master — re-pick or confirm."
	}
	// purcha_qty_mismatch / purcha_skipped / quantity_disputed have their
	// own dedicated bottom-sheet flows in Flutter — don't override copy.
	return ""
}
