package services

import "testing"

// TestIsGPFooterTotalRow_RealFMTowerJob replays the exact 40-row gate-pass
// extraction from FM Tower job 52714ffc-6366-4edf-bd95-fb49257d4c18
// (2026-06-01). Row 40 was the document footer "Total 61 Cs / 2436 btl"
// mis-read as a line item with the last product's brand bled into it
// (91 cases / 2438 bottles). The plausibility guard must drop ONLY that row
// and keep all 39 real lines.
func TestIsGPFooterTotalRow_RealFMTowerJob(t *testing.T) {
	// (cases, bottles) for each extracted row, in order.
	rows := [][2]int{
		{2, 96}, {2, 48}, {1, 12}, {1, 12}, {3, 144}, {1, 48}, {3, 144}, {1, 48},
		{1, 48}, {3, 144}, {10, 480}, {1, 24}, {1, 24}, {1, 48}, {2, 48}, {3, 144},
		{1, 48}, {1, 48}, {1, 48}, {1, 24}, {1, 12}, {3, 144}, {1, 24}, {1, 48},
		{1, 24}, {1, 24}, {1, 12}, {1, 48}, {3, 144}, {1, 12}, {1, 12}, {1, 12},
		{1, 24}, {1, 48}, {1, 24}, {1, 96}, {1, 48}, {1, 48}, {1, 12}, {91, 2438},
	}
	var sumCases, sumBottles int
	for _, r := range rows {
		sumCases += r[0]
		sumBottles += r[1]
	}

	const footerRowIdx = 39 // 0-based: the 40th row
	for i, r := range rows {
		// bpc=0 here: this captured run's footer is caught by the
		// cases-exceeds arm (91 > all others). The impossible-pack arm is
		// exercised by the live-run regression case in _Guards below.
		got := isGPFooterTotalRow(r[0], r[1], 0, sumCases, sumBottles, len(rows))
		want := i == footerRowIdx
		if got != want {
			t.Errorf("row %d (cases=%d bottles=%d): isGPFooterTotalRow=%v, want %v",
				i+1, r[0], r[1], got, want)
		}
	}
}

// TestIsGPFooterTotalRow_Guards verifies the small-document guard and the
// boundary behaviour so a legitimate short gate pass is never over-pruned.
func TestIsGPFooterTotalRow_Guards(t *testing.T) {
	cases := []struct {
		name                                              string
		rowCases, rowBottles, rowBPC, sumCases, sumBottles, rowCount int
		want                                              bool
	}{
		// < 4 rows: never drop, even if one line dominates.
		{"two-row GP, big line kept", 50, 600, 12, 52, 624, 2, false},
		{"three-row GP, big line kept", 50, 600, 12, 54, 648, 3, false},
		// A short (≤5-row) GP with one dominant line is kept — the softer
		// approx-total arm only engages at ≥6 rows.
		{"five-row GP, dominant line kept", 30, 300, 10, 60, 600, 5, false},
		// A row exceeding the others combined on bottles is dropped.
		{"footer total by bottles", 91, 2438, 26, 154, 4934, 40, true},
		// Exceeding on cases alone is enough.
		{"footer total by cases", 80, 10, 10, 150, 1000, 6, true},
		// Zero-qty row is never the footer total.
		{"zero qty row", 0, 0, 0, 60, 600, 6, false},

		// --- v1.0.333 regression: the live clone-run footer that slipped ---
		// FM Tower clone job 8ac60698 (2026-06-01): footer bled as the LAST
		// row with cases=1, bottles_per_case=2438, bottles=2438, while the
		// other 39 rows summed to 2496 bottles (so bottles 2438 did NOT exceed
		// 2496 — the old >otherBottles test missed it). Two arms now catch it.
		{"live footer — impossible pack size", 1, 2438, 2438, 64, 4934, 40, true},
		// Same row WITHOUT the impossible bpc still caught by the ≥80% approx
		// arm (2438 ≥ 0.8 × 2496).
		{"live footer — approx total arm", 1, 2438, 48, 64, 4934, 40, true},
		// A real, internally-consistent bulk line (42 cases × 48 = 2016) that
		// is well under the others' total is KEPT — it is a product, not a
		// footer (sane pack size, < 80% of the other rows' 3000 bottles).
		{"real bulk line kept", 42, 2016, 48, 100, 5016, 40, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := isGPFooterTotalRow(c.rowCases, c.rowBottles, c.rowBPC, c.sumCases, c.sumBottles, c.rowCount)
			if got != c.want {
				t.Errorf("isGPFooterTotalRow(cases=%d,btl=%d,bpc=%d,sumC=%d,sumB=%d,n=%d)=%v, want %v",
					c.rowCases, c.rowBottles, c.rowBPC, c.sumCases, c.sumBottles, c.rowCount, got, c.want)
			}
		})
	}
}
