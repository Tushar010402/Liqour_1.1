package inventory

// PackSizesByML is the standard Indian-market liquor-bottle pack count
// (bottles per case) keyed by bottle volume in ml. Values verified against
// UP Excise IESCMS gate-pass spec (the same numbers a supplier prints on
// every dispatch).
//
// Used by Smart Purchase to (a) cross-validate cases × pack_size == bottles,
// (b) enforce the bill ↔ gate-pass quantity invariant, and (c) derive
// missing fields when one of cases / bottles was OCR'd cleanly but the
// other was smudged.
//
// Authoritative — never trust OCR'd BPC over this table for these sizes.
var PackSizesByML = map[int]int{
	60:   150, // nip (owner-confirmed v1.0.359)
	90:   96,  // small pet (15 cases × 96 = 1440 bottles)
	180:  48,  // pet quarter
	330:  24, // beer can / nip
	375:  24, // pint
	500:  24, // beer half-litre
	650:  12, // beer half (UP variant)
	750:  12, // standard whisky / rum / vodka bottle
	1000: 12, // litre
}

// PackSize returns (bpc, ok) for a known volume. ok=false signals that the
// caller should fall back to the OCR-extracted BPC (or refuse to derive).
//
// We deliberately do NOT default to 12 for unknowns: a wrong BPC silently
// breaks every downstream math gate. Callers that get ok=false should
// either (a) trust the supplier-printed BPC if it exists in the bill cell,
// or (b) flag the row as `pack_size_unknown` for operator review.
func PackSize(sizeML int) (int, bool) {
	bpc, ok := PackSizesByML[sizeML]
	return bpc, ok
}

// IsKnownSize is a convenience predicate for pack_size_violation gating.
func IsKnownSize(sizeML int) bool {
	_, ok := PackSizesByML[sizeML]
	return ok
}

// DeriveCases returns the implied case count for a given bottle count and
// volume, but only when the math is exact (bottles % bpc == 0). Returns
// (cases, ok=true) on clean derivation; (0, false) when the bottle count
// doesn't divide cleanly OR the volume is unknown.
func DeriveCases(bottles int, sizeML int) (int, bool) {
	if bottles <= 0 {
		return 0, false
	}
	bpc, ok := PackSizesByML[sizeML]
	if !ok || bpc <= 0 {
		return 0, false
	}
	if bottles%bpc != 0 {
		return 0, false
	}
	return bottles / bpc, true
}

// DeriveBottles returns cases × pack_size for a known volume, or (0, false)
// when the size is unknown.
func DeriveBottles(cases int, sizeML int) (int, bool) {
	if cases <= 0 {
		return 0, false
	}
	bpc, ok := PackSizesByML[sizeML]
	if !ok || bpc <= 0 {
		return 0, false
	}
	return cases * bpc, true
}
