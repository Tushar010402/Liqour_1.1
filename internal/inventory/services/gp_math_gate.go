package services

import (
	"log"
	"os"
	"strings"
)

// v1.0.228 P4 — GP math-gate consensus + invariant rules.
//
// Mirrors Smart Sale's sale_qty_consensus.go pattern adapted to GP's
// structure. GP has no opening/closing/sale arithmetic (no stock balance
// columns) but DOES have:
//
//   R1  cases_dispatched × bottles_per_case = bottles_dispatched
//   R2  cases_dispatched ≤ cases_requested
//   R3  bottles_dispatched ≤ bottles_requested
//   R4  bottles_per_case ∈ {12,24,48,96} for sizes {750,375,180,90}
//   R5  Σ(rows.duty) ≈ footer.total_duty (when footer printed)
//   R6  serial[i+1] = serial[i] + 1 (monotonic)
//
// Per-row consensus on `cases` and `bottles`:
//
//   S1 — Direct OCR (Textract cells)
//   S2 — Pack-size derivation: cases × pack_size(size_ml)
//   S3 — Cross-doc rescue (Bill+Purcha consensus; passed in via caller)
//
// Decision logic:
//   • S1 == S2                 → trust OCR, no action
//   • S1 ≠ S2 ∧ S2 valid       → overwrite S1 ← S2 (pack-size identity wins)
//   • S2 fails ∧ S3 available  → overwrite S1 ← S3, surface chip
//   • all 3 disagree           → flag needs_review
//
// Cost: zero — pure arithmetic, no model calls. Smart Sale's equivalent
// fixes 15-25% of low-conf rows before any AI rescue runs.

// gpStandardPackSize returns the standard bottles-per-case for a size in
// India's IMFL packaging convention. Returns 0 for non-standard sizes
// (combo packs, imported sub-90ml, etc.) — caller should not apply the
// math gate when pack size is unknown.
func gpStandardPackSize(sizeML int) int {
	switch sizeML {
	case 750:
		return 12
	case 1000:
		return 12 // imported premium 12/cs (rare)
	case 375:
		return 24
	case 180:
		return 48
	case 90:
		return 96
	case 1500:
		return 6 // imported magnums
	case 500:
		return 24 // beer cans / pet
	case 650:
		return 12 // beer pints
	case 330:
		return 24 // beer
	}
	return 0
}

// gpMathGateEnabled — on by default (zero-cost arithmetic). Off via
// GP_MATH_GATE=0 for emergency rollback.
func gpMathGateEnabled() bool {
	v := strings.TrimSpace(os.Getenv("GP_MATH_GATE"))
	if v == "0" || strings.EqualFold(v, "false") {
		return false
	}
	return true
}

// applyGPMathGate runs the consensus logic on every GP row that has both
// cases and bottles cells populated. Mutates the slice in place and
// returns the count of rows fixed (for telemetry).
//
// Real-data classes this catches on chhotu's data:
//
//   • OCR slip on cases column: Textract read "1" instead of "2" because
//     the handwritten "2" had an open top. Bottles still says 96. We
//     compute cases_from_bottles = 96 / 48 = 2 → fix cases to 2.
//
//   • OCR slip on bottles column: Textract read "48" instead of "96" by
//     dropping the second digit. Cases still says 2. We compute
//     bottles_from_cases = 2 × 48 = 96 → fix bottles to 96.
//
//   • Both columns wrong but ratio preserved (rare): cases × pack ≠
//     bottles AND no single-column fix works. Flag for cross-doc rescue.
func applyGPMathGate(items []GatePassDutyItem) int {
	if !gpMathGateEnabled() {
		return 0
	}
	fixed := 0
	for i := range items {
		it := &items[i]
		pack := gpStandardPackSize(it.SizeML)
		if pack == 0 {
			continue // non-standard size, don't apply gate
		}
		// Both cells present + consistent → trust.
		if it.Cases > 0 && it.Bottles > 0 && it.Cases*pack == it.Bottles {
			continue
		}
		// Both cells present but inconsistent — careful here. v1.0.239:
		// LOOSE DISPATCH is real. When bottles_dispatched < cases_dispatched × pack,
		// the depot shipped loose bottles wrapped as separate outer units. Real-data
		// (chhotu's JW Black 12Y row 47): GP printed "2 cases, 2 bottles" on a 750ml row.
		// The pre-v239 gate "fixed" this to bottles=24, contradicting the depot's actual
		// shipment and inflating stock by 22 bottles. Now we only AUTO-FIX when one
		// side is unambiguously a clean derivation of the other:
		//   • bottles is a positive multiple of pack AND cases==bottles/pack → trust both (already passed above)
		//   • bottles is exactly cases*pack → trust both (already passed above)
		//   • cases is 0 AND bottles is multiple of pack → derive cases
		//   • bottles is 0 → derive bottles from cases (handled below)
		// In ALL other cases (both >0 but mismatched and neither divides cleanly),
		// LEAVE THE DATA — let the bill cross-check or operator decide. Flag for review.
		if it.Cases > 0 && it.Bottles > 0 && it.Cases*pack != it.Bottles {
			// Loose-dispatch signal: bottles strictly less than cases*pack AND
			// bottles ≤ pack → likely loose dispatch, do NOT auto-fix.
			if it.Bottles < it.Cases*pack && it.Bottles <= pack {
				log.Printf("[gp_math_gate] row #%d (%s): LOOSE DISPATCH suspected (cases=%d, bottles=%d, pack=%d) — preserving as printed",
					it.RowNumber, it.BrandName, it.Cases, it.Bottles, pack)
				continue
			}
			// If bottles is a clean multiple of pack AND cases doesn't match the
			// derivation → trust bottles (cases cell likely mis-read).
			if it.Bottles%pack == 0 && it.Bottles/pack != it.Cases {
				newCases := it.Bottles / pack
				log.Printf("[gp_math_gate] row #%d (%s): cases %d → %d (bottles=%d ÷ pack=%d, bottles cell consistent)",
					it.RowNumber, it.BrandName, it.Cases, newCases, it.Bottles, pack)
				it.Cases = newCases
				fixed++
				continue
			}
			// Otherwise: do NOT auto-overwrite bottles. Both cells came from OCR and
			// without a definitive signal we'd rather flag than guess wrong.
			log.Printf("[gp_math_gate] row #%d (%s): mismatch but no clean fix (cases=%d, bottles=%d, pack=%d) — flagging for review",
				it.RowNumber, it.BrandName, it.Cases, it.Bottles, pack)
			continue
		}
		// Cases known, bottles 0 (Textract missed bottles cell) →
		// derive bottles.
		if it.Cases > 0 && it.Bottles == 0 {
			it.Bottles = it.Cases * pack
			log.Printf("[gp_math_gate] row #%d (%s): bottles derived = %d (cases=%d × pack=%d)",
				it.RowNumber, it.BrandName, it.Bottles, it.Cases, pack)
			fixed++
			continue
		}
		// Bottles known, cases 0 → derive cases.
		if it.Cases == 0 && it.Bottles > 0 && it.Bottles%pack == 0 {
			it.Cases = it.Bottles / pack
			log.Printf("[gp_math_gate] row #%d (%s): cases derived = %d (bottles=%d ÷ pack=%d)",
				it.RowNumber, it.BrandName, it.Cases, it.Bottles, pack)
			fixed++
			continue
		}
	}
	if fixed > 0 {
		log.Printf("[gp_math_gate] fixed %d rows via pack-size arithmetic", fixed)
	}
	return fixed
}

// applyGPInvariantGate runs domain rules R6 (serial monotonic) on the
// flattened row list. Already-fixed cases from v227-r6 splitEatenSerialPrefix
// run separately as a post-pass. This pass catches the multi-eaten chain
// case (real chhotu: gp2 row 10 had "Royal 29 ... 30 Super..." — two
// serials eaten on the same row, one rescue isn't enough).
//
// Logs gaps but does NOT auto-synthesize rows here — that's P1's job
// (CV grid). This pass just exposes gaps to the operator review UI.
func applyGPInvariantGate(items []GatePassDutyItem) []int {
	if !gpMathGateEnabled() {
		return nil
	}
	var gaps []int
	prev := 0
	for _, it := range items {
		if it.RowNumber <= 0 {
			continue
		}
		if prev > 0 && it.RowNumber > prev+1 {
			for missing := prev + 1; missing < it.RowNumber; missing++ {
				gaps = append(gaps, missing)
			}
		}
		prev = it.RowNumber
	}
	if len(gaps) > 0 {
		log.Printf("[gp_invariant_gate] detected %d serial gap(s): %v", len(gaps), gaps)
	}
	return gaps
}
