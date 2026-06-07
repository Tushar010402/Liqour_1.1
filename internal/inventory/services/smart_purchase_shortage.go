package services

import (
	"fmt"
	"strings"
)

// v1.0.221 shortage + leakage handling.
//
// Real-world scenario: a 96-bottle case is billed and dispatched per the
// gate pass, but the operator counts only 94 bottles at delivery. Two
// bottles were lost between depot and shop floor. Reason is one of:
//
//   "depot_short"   — depot didn't load all 96. Operator confirmed at
//                     receipt; vendor owes a credit note.
//   "transit_leak"  — bottle broke in transit. Insurance / vendor
//                     responsibility depending on contract.
//   "transit_broken" — same as above but stronger signal (glass shards
//                     visible). Sometimes claimed separately.
//   "other"         — operator-typed reason. Free-form note.
//
// Stock impact: stocks.quantity += actual_received_qty (NOT billed_qty).
// Bill total stays at billed_qty × cost_per_bottle so the vendor invoice
// reconciles, but the loss is captured for accountability.
//
// stock_purchase_items already has `leakage` + `short_received` int
// columns, populated by this helper based on the operator's reason. The
// audit row in stock_histories carries the reason in `notes`.
//
// Cross-check: when DSE register's "Receipt" column for the same date +
// shop + size + brand differs from GP's "Bottles Dispatched" by 1-2, we
// surface that as a soft warning ("DSE-GP mismatch — short or leak?")
// pre-emptively, so the operator can mark it during review instead of
// after-the-fact reconciliation.

// ShortageReason classifies why actual_received_qty < bill_qty. Stored
// as text in stock_purchase_items.notes and stock_histories.reference.
type ShortageReason string

const (
	ShortageNone         ShortageReason = "none"
	ShortageDepotShort   ShortageReason = "depot_short"
	ShortageTransitLeak  ShortageReason = "transit_leak"
	ShortageTransitBroken ShortageReason = "transit_broken"
	ShortageOther        ShortageReason = "other"
)

// ParseShortageReason normalizes a user-facing reason string to the
// canonical enum value. Defaults to ShortageOther for unrecognised input.
func ParseShortageReason(s string) ShortageReason {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "", "none", "no_shortage":
		return ShortageNone
	case "depot_short", "godown_short", "short_from_godown", "short":
		return ShortageDepotShort
	case "transit_leak", "leak", "leakage":
		return ShortageTransitLeak
	case "transit_broken", "broken":
		return ShortageTransitBroken
	default:
		return ShortageOther
	}
}

// ShortageResolution is the per-row output of resolveShortage. Caller
// writes these onto stock_purchase_items + stock_histories.
type ShortageResolution struct {
	ActualReceivedQty int            // what to add to stocks.quantity
	LeakageQty        int            // → stock_purchase_items.leakage
	ShortReceivedQty  int            // → stock_purchase_items.short_received
	Reason            ShortageReason // for audit row
	ReasonText        string         // operator's free-form note (only when Reason == ShortageOther)
	AuditNote         string         // human-readable note for stock_histories.notes
	IsValid           bool           // false when inputs are inconsistent (e.g. actual > bill)
	ValidationError   string         // explanation when IsValid is false
}

// resolveShortage reconciles billed_qty, gp_qty, and operator's reported
// actual_received_qty into a per-row resolution. Validates that the math
// adds up; surfaces the canonical reason; returns the audit note text to
// store on the stock_history row.
//
// Inputs:
//   - billQty: bottles per `bill.cases × pack_size` (the invoice amount)
//   - gpQty:   bottles per GP `Bottles Dispatched` (legal physical receipt)
//   - actualReceivedQty: operator's count at the shop (≤ gpQty, normally)
//   - reasonInput: free-text reason ("short_from_godown" / "leak" / etc.)
//   - reasonNote:  optional operator-typed extra detail
//
// Decision tree:
//   - actualReceivedQty == gpQty == billQty → no shortage, clean apply
//   - actualReceivedQty < gpQty             → leak/short between depot
//                                              load and shop receipt
//   - gpQty < billQty                       → depot under-loaded (depot_short)
//     and actualReceivedQty == gpQty
//   - gpQty < billQty and actualReceivedQty < gpQty → BOTH depot_short
//                                              and transit_leak; we split
//                                              the shortage proportionally
//                                              by reason.
//   - actualReceivedQty > gpQty             → ERROR (operator received more
//                                              than dispatched). Sets
//                                              IsValid=false.
func resolveShortage(
	billQty, gpQty, actualReceivedQty int,
	reasonInput, reasonNote string,
) ShortageResolution {
	out := ShortageResolution{
		ActualReceivedQty: actualReceivedQty,
		ReasonText:        strings.TrimSpace(reasonNote),
		IsValid:           true,
	}

	if billQty < 0 || gpQty < 0 || actualReceivedQty < 0 {
		out.IsValid = false
		out.ValidationError = fmt.Sprintf("negative quantities not allowed (bill=%d gp=%d actual=%d)", billQty, gpQty, actualReceivedQty)
		return out
	}
	if actualReceivedQty > gpQty {
		out.IsValid = false
		out.ValidationError = fmt.Sprintf("actual_received_qty %d exceeds GP dispatched %d — operator can't receive more than what was shipped", actualReceivedQty, gpQty)
		return out
	}

	// Clean case: every number agrees.
	if actualReceivedQty == gpQty && gpQty == billQty {
		out.Reason = ShortageNone
		out.AuditNote = fmt.Sprintf("Clean receipt: bill=%d / GP=%d / received=%d (no shortage)", billQty, gpQty, actualReceivedQty)
		return out
	}

	// Operator-stated reason takes priority over our inferred classification.
	reason := ParseShortageReason(reasonInput)

	// Components of the shortage:
	//   depot_short = bill - gp           (depot didn't load full bill)
	//   transit_leak = gp - actual_received (lost between depot and shop)
	depotShortQty := billQty - gpQty
	if depotShortQty < 0 {
		depotShortQty = 0
	}
	transitLeakQty := gpQty - actualReceivedQty
	if transitLeakQty < 0 {
		transitLeakQty = 0
	}

	// If both shortages exist, the operator's stated reason picks the
	// dominant one (UI presents them separately). Default classification
	// when the operator didn't specify:
	if reason == ShortageNone {
		switch {
		case depotShortQty > 0 && transitLeakQty == 0:
			reason = ShortageDepotShort
		case transitLeakQty > 0 && depotShortQty == 0:
			reason = ShortageTransitLeak
		case depotShortQty > 0 && transitLeakQty > 0:
			reason = ShortageOther // both — operator confirms breakdown
		}
	}
	out.Reason = reason

	// Populate the two distinct columns. Both can be non-zero (bill 96 →
	// gp 94 → received 92 = 2 depot_short + 2 transit_leak).
	out.ShortReceivedQty = depotShortQty
	out.LeakageQty = transitLeakQty

	parts := []string{
		fmt.Sprintf("bill=%d", billQty),
		fmt.Sprintf("GP=%d", gpQty),
		fmt.Sprintf("received=%d", actualReceivedQty),
	}
	if depotShortQty > 0 {
		parts = append(parts, fmt.Sprintf("depot_short=%d", depotShortQty))
	}
	if transitLeakQty > 0 {
		parts = append(parts, fmt.Sprintf("transit_leak=%d", transitLeakQty))
	}
	parts = append(parts, fmt.Sprintf("reason=%s", reason))
	if out.ReasonText != "" {
		parts = append(parts, fmt.Sprintf("note=%q", out.ReasonText))
	}
	out.AuditNote = strings.Join(parts, " · ")
	return out
}

// netReceivedQty is the bottles that actually enter stock for a RECEIVED
// purchase item: GROSS billed quantity minus operator-reported leakage and
// short-received, clamped at 0. This is the SINGLE place stock subtracts a
// shortage — ReceivePurchase calls it once per item.
//
// INVARIANT: `grossQty` must be the gross billed bottle count, NOT a value
// already netted of shortage. smart_purchase_apply.go stores GROSS on the
// item (matching the legacy CreatePurchase path) precisely so this single
// subtraction is correct. Storing a pre-netted quantity here would subtract
// the shortage a second time (stock = gross - 2*(leak+short)) — the bug this
// helper + its test exist to prevent.
func netReceivedQty(grossQty, leakage, shortReceived int) int {
	n := grossQty - leakage - shortReceived
	if n < 0 {
		n = 0
	}
	return n
}

// DSEGPMismatchSignal is the cross-check output between the shop's DSE
// "Receipt" column entry for a brand+size+date and the GP's "Bottles
// Dispatched" for the same canonical row. Surfaced as a soft pre-emptive
// warning when |DSE.Receipt - GP.Bottles| in (0, 3] — outside that range
// it's either a clean match or a different issue (likely OCR error).
type DSEGPMismatchSignal struct {
	DSEReceiptQty   int    // operator's hand-written Receipt column
	GPBottlesQty    int    // GP's Bottles Dispatched
	DiffBottles     int    // GP - DSE (positive = DSE under-recorded)
	LikelyReason    ShortageReason
	HumanReadable   string
}

// computeDSEGPMismatch returns a soft warning when DSE.Receipt and GP
// dispatched disagree by 1-3 bottles. Anything ≥ 4 is suspicious enough
// to be an OCR / different-day error rather than a shortage, so we don't
// surface those (they get caught by other warning classes).
func computeDSEGPMismatch(dseReceipt, gpBottles int) (DSEGPMismatchSignal, bool) {
	if dseReceipt <= 0 || gpBottles <= 0 {
		return DSEGPMismatchSignal{}, false
	}
	diff := gpBottles - dseReceipt
	abs := diff
	if abs < 0 {
		abs = -abs
	}
	if abs == 0 || abs > 3 {
		return DSEGPMismatchSignal{}, false
	}
	sig := DSEGPMismatchSignal{
		DSEReceiptQty: dseReceipt,
		GPBottlesQty:  gpBottles,
		DiffBottles:   diff,
	}
	switch {
	case diff > 0:
		// GP > DSE: operator wrote down fewer than dispatched — likely
		// short or leak that already happened before they entered the DSE.
		sig.LikelyReason = ShortageTransitLeak
		sig.HumanReadable = fmt.Sprintf("GP dispatched %d but you recorded only %d in sale register — was %d btl short/leaked?",
			gpBottles, dseReceipt, diff)
	case diff < 0:
		// DSE > GP: operator recorded more than dispatched — anomalous,
		// could be combined with another delivery the same day.
		sig.LikelyReason = ShortageOther
		sig.HumanReadable = fmt.Sprintf("You recorded %d in sale register but GP shows only %d dispatched — combined delivery?",
			dseReceipt, gpBottles)
	}
	return sig, true
}
