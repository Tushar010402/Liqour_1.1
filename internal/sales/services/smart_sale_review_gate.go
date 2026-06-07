package services

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
)

// ============================================================================
// v1.0.160 — Mandatory review-warning gate for Smart Sale apply.
//
// Background
// ----------
// Pre-v1.0.160 the Apply endpoint accepted whatever Flutter posted. If the
// review-screen surfaced a row with "math_disagree" or "Amount cell appears
// back-filled" and the user submitted without addressing it, the row would
// silently apply and silently corrupt downstream stock. The "submit anyway"
// path was an unbounded loophole that defeated every accuracy guard in the
// pipeline (Track A/F/G, sheet-grid, cell-level voting, etc.).
//
// Behaviour
// ---------
// Every blocking-warning substring this gate recognizes MUST be acknowledged
// by the operator on the review screen. The Flutter client emits one entry
// per acknowledged warning into SmartSaleApplyItem.UserConfirmedWarnings.
// On apply, every blocking warning a row carries must have a corresponding
// confirmation; otherwise the row is rejected with HTTP 422 and a structured
// payload Flutter renders inline.
//
// Backward compatibility
// ----------------------
// • Rows whose Warnings slice is empty or contains only non-blocking entries
//   pass through unchanged — no contract change for the happy path.
// • Old Flutter clients on v1.0.158 and below send no UserConfirmedWarnings
//   field. They will start receiving 422 the moment they hit a row with a
//   blocking warning. v1.0.159 already surfaces every chip in the warning
//   list this gate recognizes; v1.0.160 Flutter sends the confirmation
//   field, so the upgrade is a coordinated client+server release.
// • SMART_SALE_MANDATORY_REVIEW=0 toggles the gate to log-only mode. The
//   backend still computes the rejected list and warns it but does not
//   short-circuit the apply. Default (env unset or !=0) = enforced.
//
// Multi-tenant
// ------------
// The gate is purely structural — it inspects the warning strings and the
// confirmation strings on each row without ever consulting tenant config.
// Same behaviour for every tenant; no per-tenant flag, no per-shop bypass.
// ============================================================================

// blockingWarningSubstrings lists every warning prefix/substring that hard-
// blocks an apply unless the row carries a matching UserConfirmedWarnings
// entry. The list is intentionally narrow: every entry corresponds to a
// real bug class chhotu/Tushar hit in production. When adding a new entry,
// also wire the matching chip on the Flutter review screen so the operator
// can actually confirm it.
//
// Match semantics: case-insensitive substring of either the row warning OR
// the confirmation string. So Flutter can echo back the verbatim warning
// text it rendered (preferred) or send the canonical short tag below.
var blockingWarningSubstrings = []string{
	"amount cell appears back-filled", // sale_qty_consensus.go consensus path
	"math_disagree",                   // sale_sheet_grid.go + smart_sale_service.go ApplyMathGate
	"close_misread_suspected",         // sheet-grid + smart_sale_service ApplyMathGate
	"cannot apply",                    // legacy hard-block strings ("Sale qty exceeds stock... Cannot apply.")
	"sale qty unclear",                // sale_qty_consensus low-confidence demotion
	"stock discrepancy",               // matchProductsAndValidate "Image opening != DB"
	"exceeds available stock",         // duplicate-merge guard + apply gate
	// v1.0.327 — alias-conflict warning (two AI rows bind to same product_id
	// with divergent OCR rates). The real cross-row check fires in
	// ValidateNoAliasConflicts at apply-handler entry; this entry exists so
	// that IF Flutter forwards the per-row warning string via
	// UserConfirmedWarnings the substring matcher recognizes it as a known
	// blocking tag rather than treating it as freeform text.
	"alias_conflict_row_",
}

// RejectedRow is one row that failed the review gate. Surfaced verbatim in
// the 422 body so Flutter can scroll to + highlight the offender.
type RejectedRow struct {
	Position            int      `json:"position"`             // 1-based order in req.Items as posted
	ProductID           string   `json:"product_id,omitempty"` // helpful when brand_name is empty
	ProductName         string   `json:"product_name"`         // BrandName fallback to "(unnamed row)"
	UnconfirmedWarnings []string `json:"unconfirmed_warnings"` // exact warning strings the user has not yet confirmed
}

// ReviewGateResult summarises the outcome of ValidateWarningConfirmations.
// Enforced=true means the caller MUST short-circuit with 422 + Rejected.
// Enforced=false (log-only mode) means Rejected is informational only.
type ReviewGateResult struct {
	Rejected []RejectedRow
	Enforced bool
}

// ValidateWarningConfirmations walks every apply item, picks out the
// blocking warnings, and matches them against the row's UserConfirmedWarnings
// list. Any blocking warning without a confirmation lands the row in the
// rejected list. The caller is responsible for short-circuiting the request
// when len(Rejected)>0 AND Enforced=true.
//
// Why no rowWarningsByIndex parameter: the original SmartSaleResult.Warnings
// live in the /process response and are NOT part of the apply payload (Go's
// SmartSaleApplyItem has no `warnings` field — by design, since the client
// is the source of truth for review-screen state). To get a deterministic
// gate that fires even when the /process cache is gone (draft resumes,
// hours-later submits), we reconstruct the blocking warnings from the
// apply-payload's own deterministic signals (opening_stock + receipt +
// closing_stock + original_ai_*) via deriveBlockingWarningsFromItem.
func ValidateWarningConfirmations(items []SmartSaleApplyItem) ReviewGateResult {
	enforced := os.Getenv("SMART_SALE_MANDATORY_REVIEW") != "0"

	var rejected []RejectedRow
	for i, it := range items {
		// Only rows that will actually persist matter. Zero-quantity rows
		// are filtered out earlier in ApplySmartSale and never deduct
		// stock; gating them adds friction without integrity benefit.
		if it.Quantity <= 0 {
			continue
		}

		blocking := deriveBlockingWarningsFromItem(it)
		if len(blocking) == 0 {
			continue
		}

		confirmed := normalizeConfirmations(it.UserConfirmedWarnings)
		var unconfirmed []string
		for _, w := range blocking {
			if !isWarningConfirmed(w, confirmed) {
				unconfirmed = append(unconfirmed, w)
			}
		}
		if len(unconfirmed) == 0 {
			continue
		}

		name := strings.TrimSpace(it.BrandName)
		if name == "" {
			name = "(unnamed row)"
		}
		rejected = append(rejected, RejectedRow{
			Position:            i + 1,
			ProductID:           it.ProductID,
			ProductName:         name,
			UnconfirmedWarnings: unconfirmed,
		})
	}

	if len(rejected) > 0 {
		log.Printf("SmartSale: review-gate flagged %d rows (enforced=%v) — first row: pos=%d name=%s warnings=%v",
			len(rejected), enforced, rejected[0].Position, rejected[0].ProductName, rejected[0].UnconfirmedWarnings)
	}

	return ReviewGateResult{Rejected: rejected, Enforced: enforced}
}

// deriveBlockingWarningsFromItem recomputes the subset of blocking warnings
// the Flutter review screen surfaced for this row. We can't trust the AI
// pipeline's transient SmartSaleResult to still be in memory at apply time
// (process and apply are separate requests, possibly hours apart for draft
// resumes), so we reconstruct from the deterministic apply-time signals
// echoed in the payload itself:
//
//   • OpeningStock + Receipt + Quantity vs computed close → math_disagree
//   • Quantity > OpeningStock+Receipt → exceeds available stock
//   • OriginalAIAmount differs from Quantity*Rate by ≥ ₹1 → back-fill heuristic
//
// The "stock discrepancy" + "Sale qty unclear" + "close_misread_suspected"
// + "Cannot apply" tags are surfaced by the server-side validation already
// running BEFORE this gate (matchProductsAndValidate populates Warnings on
// SmartSaleExtractedItem). When Flutter echoes those strings back via the
// dedicated UserConfirmedWarnings field there's no ambiguity. When it
// doesn't echo them (legacy clients) we still catch the math + over-sell
// classes deterministically here.
func deriveBlockingWarningsFromItem(it SmartSaleApplyItem) []string {
	var out []string

	// Math identity: opening + receipt - qty == closing (±2 tolerance).
	// The same gate the Flutter v1.0.157 L4-UX preflight enforces.
	if it.OpeningStock != nil && it.Receipt != nil && it.OriginalAIClosing != nil {
		open := *it.OpeningStock
		recv := *it.Receipt
		close_ := *it.OriginalAIClosing
		if it.Quantity > 0 {
			expected := open + recv - it.Quantity
			diff := expected - close_
			if diff < 0 {
				diff = -diff
			}
			if diff > 2 {
				out = append(out, "math_disagree")
			}
		}
	}

	// Over-sell: confirmed qty exceeds opening+receipt. The dedicated
	// stockGate in ApplySmartSale also catches this against db stock,
	// but doing it here means the gate fires even when stock-gate is
	// disabled (SMART_SALE_STOCK_GATE=0).
	if it.OpeningStock != nil {
		cap := *it.OpeningStock
		if it.Receipt != nil && *it.Receipt > 0 {
			cap += *it.Receipt
		}
		if cap > 0 && it.Quantity > cap {
			out = append(out, "exceeds available stock")
		}
	}

	// Back-fill heuristic: AI's amount equals qty*rate exactly while the
	// stock-math implied a different qty. This is sale_qty_consensus.go's
	// "Amount cell appears back-filled" warning translated to apply-time.
	// We only emit it when OriginalAIAmount and OriginalAIQuantity disagree
	// (the user MUST have edited qty for this to fire) AND the original
	// amount/quantity ratio still divides cleanly by the rate — strong
	// signal the AI back-filled amount = qty*rate instead of reading the
	// register column.
	if it.OriginalAIAmount != nil && it.OriginalAIQuantity != nil && it.Rate > 0 {
		origAmt := *it.OriginalAIAmount
		origQty := *it.OriginalAIQuantity
		if origQty > 0 && origAmt > 0 && origQty != it.Quantity {
			expected := float64(origQty) * it.Rate
			if absFloat(origAmt-expected) < 1.0 {
				out = append(out, "Amount cell appears back-filled")
			}
		}
	}

	return out
}

func absFloat(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

// ============================================================================
// v1.0.327 — Apply-time alias-conflict guard for Smart Sale.
//
// Mirrors v1.0.301 Stock Setup's dup-product-id guard at
// internal/inventory/services/smart_stock_setup_service.go:7601 but operates
// on SmartSaleApplyItem before any DB tx opens.
//
// Background
// ----------
// The matcher (pkg/shared/matching/matcher.go) is text-dominant. Two AI rows
// whose OCR brand text normalizes identically can bind to the same product_id
// even when their OCR rates clearly differ (e.g. "8PM Gold PET ₹130" and
// "8PM Gold Tetra ₹140" both → one '8 PM Gold Scotch' SKU). createDailySalesEntries
// (smart_sale_service.go ~:6302) then silently sums their Quantity + Amount
// into a single daily_sales_item, destroying the second SKU's sale. v1.0.327
// matcher tiebreaker prevents most of these; this gate is the backstop.
//
// Behaviour
// ---------
// Returns HTTP 422 with a structured payload Flutter renders inline listing
// every (product_id, [row positions], [rates]) collision whose rate divergence
// exceeds SMART_SALE_ALIAS_CONFLICT_RATE_PCT (default 5%). Below the threshold
// the rows are treated as legitimate same-SKU duplicates and pass through to
// the existing silent-merge logic (with belt-and-braces logging).
//
// Rollout
// -------
// SMART_SALE_ALIAS_CONFLICT_GUARD=0 → log-only (still computes rejected list,
// still warns, but does NOT short-circuit the apply). Default (env unset or
// !=0) = enforced. Same shape as SMART_SALE_MANDATORY_REVIEW.
// ============================================================================

// AliasConflictRow describes one set of apply rows that all bind to the same
// product_id but disagree on the OCR rate.
type AliasConflictRow struct {
	ProductID   string    `json:"product_id"`
	ProductName string    `json:"product_name"`
	Rows        []int     `json:"rows"`  // 1-based positions in req.Items
	Rates       []float64 `json:"rates"` // matching positions
}

// AliasConflictGateResult summarises ValidateNoAliasConflicts.
type AliasConflictGateResult struct {
	Conflicts []AliasConflictRow
	Enforced  bool
}

// aliasRowEntry is the internal accumulator the alias-conflict gate uses
// to group rows by product_id. Package-scoped so ratesDivergeAcross can
// reference the type directly.
type aliasRowEntry struct {
	pos  int
	rate float64
	name string
}

// ValidateNoAliasConflicts groups apply items by product_id and reports every
// group whose member rates diverge by more than the configured pct threshold.
// Zero-quantity rows are skipped (they don't persist, so a silent merge of
// two zero-qty rows is harmless). Empty product_ids are skipped (not-found
// rows fall through to the operator picker).
func ValidateNoAliasConflicts(items []SmartSaleApplyItem) AliasConflictGateResult {
	enforced := os.Getenv("SMART_SALE_ALIAS_CONFLICT_GUARD") != "0"
	ratePct := aliasConflictRatePctEnv()

	groups := map[string][]aliasRowEntry{}
	for i, it := range items {
		if it.Quantity <= 0 {
			continue
		}
		pid := strings.TrimSpace(it.ProductID)
		if pid == "" {
			continue
		}
		groups[pid] = append(groups[pid], aliasRowEntry{
			pos:  i + 1,
			rate: it.Rate,
			name: strings.TrimSpace(it.BrandName),
		})
	}

	var conflicts []AliasConflictRow
	for pid, rows := range groups {
		if len(rows) < 2 {
			continue
		}
		if !ratesDivergeAcross(rows, ratePct) {
			continue
		}
		positions := make([]int, 0, len(rows))
		rates := make([]float64, 0, len(rows))
		name := ""
		for _, r := range rows {
			positions = append(positions, r.pos)
			rates = append(rates, r.rate)
			if name == "" && r.name != "" {
				name = r.name
			}
		}
		if name == "" {
			name = "(unnamed product)"
		}
		conflicts = append(conflicts, AliasConflictRow{
			ProductID:   pid,
			ProductName: name,
			Rows:        positions,
			Rates:       rates,
		})
	}

	if len(conflicts) > 0 {
		log.Printf("SmartSale: alias-conflict gate flagged %d collision(s) (enforced=%v, ratePct=%.1f) — first: product=%s rows=%v rates=%v",
			len(conflicts), enforced, ratePct, conflicts[0].ProductName, conflicts[0].Rows, conflicts[0].Rates)
	}
	return AliasConflictGateResult{Conflicts: conflicts, Enforced: enforced}
}

// ratesDivergeAcross returns true if any pair in the group differs by more
// than pctThreshold. Treats either zero-rate as "unknown" → divergent, so a
// row missing a rate can't silently merge with one that has it.
func ratesDivergeAcross(rows []aliasRowEntry, pctThreshold float64) bool {
	for i := 0; i < len(rows); i++ {
		for j := i + 1; j < len(rows); j++ {
			a, b := rows[i].rate, rows[j].rate
			if a <= 0 || b <= 0 {
				return true
			}
			denom := a
			if b > denom {
				denom = b
			}
			diff := a - b
			if diff < 0 {
				diff = -diff
			}
			if diff/denom*100.0 > pctThreshold {
				return true
			}
		}
	}
	return false
}

// FormatAliasConflictMessage returns a human-readable summary for logs.
func FormatAliasConflictMessage(c AliasConflictRow) string {
	rateStrs := make([]string, len(c.Rates))
	for i, r := range c.Rates {
		rateStrs[i] = fmt.Sprintf("₹%.0f", r)
	}
	return fmt.Sprintf("rows %v match product %q at divergent rates [%s] — rebind one before submitting",
		c.Rows, c.ProductName, strings.Join(rateStrs, ", "))
}

func aliasConflictRatePctEnv() float64 {
	if v := strings.TrimSpace(os.Getenv("SMART_SALE_ALIAS_CONFLICT_RATE_PCT")); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil && parsed > 0 {
			return parsed
		}
	}
	return 5.0
}

// normalizeConfirmations lowercases + trims user-supplied confirmation
// strings so the matcher can do case-insensitive substring compares.
func normalizeConfirmations(in []string) []string {
	if len(in) == 0 {
		return nil
	}
	out := make([]string, 0, len(in))
	for _, s := range in {
		s = strings.ToLower(strings.TrimSpace(s))
		if s != "" {
			out = append(out, s)
		}
	}
	return out
}

// isWarningConfirmed returns true when at least one blocking-substring of
// `warning` matches at least one confirmation string. Substring match is
// directional both ways: a confirmation containing the canonical tag
// ("math_disagree") matches a longer warning ("math_disagree:ai_sale=12
// open(40)-close(20)=20"), AND a confirmation that is the verbatim long
// warning still matches the canonical tag.
func isWarningConfirmed(warning string, confirmations []string) bool {
	w := strings.ToLower(strings.TrimSpace(warning))
	if w == "" {
		return true // nothing to confirm
	}
	for _, c := range confirmations {
		if c == "" {
			continue
		}
		if strings.Contains(w, c) || strings.Contains(c, w) {
			return true
		}
	}
	// Also accept any blocking-substring match. e.g., warning is the long
	// "math_disagree:..." string and Flutter sent the short tag "math_disagree".
	for _, sub := range blockingWarningSubstrings {
		if !strings.Contains(w, sub) {
			continue
		}
		for _, c := range confirmations {
			if strings.Contains(c, sub) {
				return true
			}
		}
	}
	return false
}
