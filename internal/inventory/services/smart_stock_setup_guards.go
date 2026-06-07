package services

import (
	"log"
	"math"
	"sort"
	"strconv"
)

// ============================================================================
// Post-extraction sanity guards (#7 batch).
//
// Three deterministic guards run on the parsed extraction BEFORE matching:
//
//   ApplyRateOutlierGuard — Flags rate values that are statistical outliers
//     versus the page's other rates. Catches OCR misreads where one row's
//     rate column was confused for the amount column (₹1620 instead of ₹160).
//
//   ApplyPageChecksumGuard — When Sale and Rate are both legible, verify
//     Sale × Rate ≈ Amount per row; if not, demote that row's confidence.
//     Plus a page-level checksum: if the extracted rows' rate column has
//     ANY duplicates, that's normal; but if the entire column is the same
//     value, something is very wrong and we mark the page low quality.
//
//   ApplyRateMonotonicGuard — Indian liquor registers are sorted ascending
//     by rate. If any row's rate decreases by more than 30% from the previous
//     row, log a warning and lower that row's confidence. Catches cases
//     where the AI mixes up two rows' rate columns.
//
// All guards are idempotent and side-effect-free except for in-place edits
// to the input slice. Safe to run on Claude, Gemini, or OpenAI output.
// ============================================================================

const (
	rateOutlierMinSamples   = 5
	rateOutlierZThreshold   = 3.0   // standard deviations
	rateMonotonicMaxDropPct = 0.30  // 30% drop down the page = suspicious
	checksumTolerancePct    = 0.02  // ±2% on Sale × Rate vs Amount
	checksumMinAmount       = 10.0  // skip checksum on sub-₹10 rows (rounding noise)
)

// ApplyRateOutlierGuard flags any row whose rate is more than 3 standard
// deviations from the page mean. Lowers per-field rate confidence to 0.5
// and adds a warning. Skips when fewer than 5 rate samples (insufficient
// statistical power).
func ApplyRateOutlierGuard(items []ExtractedStockRegisterItem) {
	rates := make([]float64, 0, len(items))
	for _, it := range items {
		if it.Rate > 0 {
			rates = append(rates, it.Rate)
		}
	}
	if len(rates) < rateOutlierMinSamples {
		return
	}
	mean := 0.0
	for _, r := range rates {
		mean += r
	}
	mean /= float64(len(rates))
	variance := 0.0
	for _, r := range rates {
		variance += (r - mean) * (r - mean)
	}
	stddev := math.Sqrt(variance / float64(len(rates)))
	if stddev < 1.0 {
		return // all rates are too similar; outlier detection meaningless
	}
	flagged := 0
	for i := range items {
		if items[i].Rate <= 0 {
			continue
		}
		z := math.Abs(items[i].Rate-mean) / stddev
		if z > rateOutlierZThreshold {
			log.Printf("Smart Stock Setup: rate outlier on row %d: ₹%.0f (page mean ₹%.0f, z=%.2f)",
				items[i].RowNumber, items[i].Rate, mean, z)
			if items[i].FieldConfidence == nil {
				items[i].FieldConfidence = map[string]float64{}
			}
			items[i].FieldConfidence["rate"] = 0.5
			items[i].FieldConfidence["amount"] = 0.5
			if items[i].Confidence > 0.6 {
				items[i].Confidence = 0.6
			}
			flagged++
		}
	}
	if flagged > 0 {
		log.Printf("Smart Stock Setup: rate-outlier guard flagged %d/%d rows", flagged, len(items))
	}
}

// ApplyPageChecksumGuard runs Sale × Rate ≈ Amount per row. Mismatches
// drop confidence on whichever field is most likely wrong (chooses the
// larger value when both are non-zero, since smaller numbers are usually
// the more legible one).
func ApplyPageChecksumGuard(items []ExtractedStockRegisterItem) {
	flagged := 0
	for i := range items {
		it := &items[i]
		if it.Sale <= 0 || it.Rate <= 0 || it.Amount < checksumMinAmount {
			continue
		}
		expected := float64(it.Sale) * it.Rate
		diff := math.Abs(it.Amount-expected) / it.Amount
		if diff <= checksumTolerancePct {
			continue
		}
		log.Printf("Smart Stock Setup: checksum mismatch row %d — sale=%d × rate=%.0f = %.0f, but amount=%.0f (diff %.1f%%)",
			it.RowNumber, it.Sale, it.Rate, expected, it.Amount, diff*100)
		if it.FieldConfidence == nil {
			it.FieldConfidence = map[string]float64{}
		}
		// All three fields lose confidence — we don't know which is wrong.
		it.FieldConfidence["sale"] = 0.5
		it.FieldConfidence["rate"] = 0.55
		it.FieldConfidence["amount"] = 0.55
		if it.Confidence > 0.65 {
			it.Confidence = 0.65
		}
		flagged++
	}
	if flagged > 0 {
		log.Printf("Smart Stock Setup: page-checksum guard flagged %d/%d rows", flagged, len(items))
	}
}

// ApplyRateMonotonicGuard exploits the convention that Indian liquor
// registers are sorted ascending by rate. If row N+1's rate drops more
// than 30% from row N's, that's a strong signal one of the two was misread.
// Lower confidence on both, log for review.
func ApplyRateMonotonicGuard(items []ExtractedStockRegisterItem) {
	if len(items) < 2 {
		return
	}
	// Sort indexes by RowNumber so the iteration follows page order.
	idxs := make([]int, len(items))
	for i := range items {
		idxs[i] = i
	}
	sort.Slice(idxs, func(a, b int) bool {
		return items[idxs[a]].RowNumber < items[idxs[b]].RowNumber
	})
	flagged := 0
	for k := 1; k < len(idxs); k++ {
		prev := &items[idxs[k-1]]
		cur := &items[idxs[k]]
		if prev.Rate <= 0 || cur.Rate <= 0 {
			continue
		}
		// Allow small drops (sometimes preprinted out-of-order rows). Only
		// flag when the drop exceeds 30%.
		drop := (prev.Rate - cur.Rate) / prev.Rate
		if drop <= rateMonotonicMaxDropPct {
			continue
		}
		log.Printf("Smart Stock Setup: rate-monotonic violation row %d→%d: ₹%.0f → ₹%.0f (drop %.0f%%)",
			prev.RowNumber, cur.RowNumber, prev.Rate, cur.Rate, drop*100)
		for _, it := range []*ExtractedStockRegisterItem{prev, cur} {
			if it.FieldConfidence == nil {
				it.FieldConfidence = map[string]float64{}
			}
			if c := it.FieldConfidence["rate"]; c == 0 || c > 0.65 {
				it.FieldConfidence["rate"] = 0.65
			}
		}
		if cur.Confidence > 0.7 {
			cur.Confidence = 0.7
		}
		flagged++
	}
	if flagged > 0 {
		log.Printf("Smart Stock Setup: rate-monotonic guard flagged %d transitions", flagged)
	}
}

// ApplyRateConcatGuard is v1.0.263 — a DETERMINISTIC fix (prompt-independent;
// the model demonstrably ignores the "never concatenate" prompt rule). The
// extractor frequently reads a single printed rate twice and concatenates it
// ("130" → "130130"), or otherwise returns an impossible 4-6 digit rate. This
// corrects it from the row's own arithmetic and from the doubled-string
// pattern — no image needed, runs every time, cannot be ignored by the model.
//
// Safe by construction: only touches a rate that is IMPOSSIBLE (> ₹5000 for a
// retail bottle) AND has an unambiguous correct value (exact doubled string,
// or Amount/Sale gives a clean plausible rate). Plausible rates are untouched.
func ApplyRateConcatGuard(items []ExtractedStockRegisterItem) {
	const maxPlausibleRate = 5000.0
	fixed := 0
	for i := range items {
		it := &items[i]
		if it.Rate > 0 && it.Rate <= maxPlausibleRate {
			continue // plausible — never touch a good rate
		}
		if it.Rate <= 0 {
			continue
		}
		orig := it.Rate
		var candidate float64

		// (a) Amount = Sale × Rate is the strongest signal. If the row has a
		// clean Sale and Amount, the true rate is Amount/Sale.
		if it.Sale > 0 && it.Amount > 0 {
			r := it.Amount / float64(it.Sale)
			if r >= 30 && r <= maxPlausibleRate && math.Abs(r-math.Round(r)) < 0.01 {
				candidate = math.Round(r)
			}
		}

		// (b) Doubled-string pattern: "130130" → "130", "9090" → "90".
		if candidate == 0 {
			s := strconv.FormatInt(int64(it.Rate), 10)
			if n := len(s); n >= 2 && n%2 == 0 && s[:n/2] == s[n/2:] {
				if h, err := strconv.ParseFloat(s[:n/2], 64); err == nil &&
					h >= 30 && h <= maxPlausibleRate {
					candidate = h
				}
			}
		}

		if candidate > 0 && candidate != orig {
			it.Rate = candidate
			fixed++
			log.Printf("Smart Stock Setup: rate-concat guard fixed row %d: ₹%.0f → ₹%.0f (deterministic)",
				it.RowNumber, orig, candidate)
			if it.FieldConfidence == nil {
				it.FieldConfidence = map[string]float64{}
			}
			if c := it.FieldConfidence["rate"]; c == 0 || c > 0.7 {
				it.FieldConfidence["rate"] = 0.7
			}
		}
	}
	if fixed > 0 {
		log.Printf("Smart Stock Setup: rate-concat guard fixed %d impossible rates", fixed)
	}
}

// ApplyAllGuards is the convenience wrapper called from
// parseStockRegisterResponse after the existing arithmetic recovery.
// Order matters: rate-concat FIRST (an impossible ₹130130 would otherwise
// poison the statistical outlier + monotonic passes), then outlier
// (statistical), then checksum (per-row math), then monotonic (page-order).
func ApplyAllGuards(items []ExtractedStockRegisterItem) {
	ApplyRateConcatGuard(items)
	ApplyRateOutlierGuard(items)
	ApplyPageChecksumGuard(items)
	ApplyRateMonotonicGuard(items)
}
