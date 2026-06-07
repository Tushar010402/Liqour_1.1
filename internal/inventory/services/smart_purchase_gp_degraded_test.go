package services

import "testing"

// v1.0.346 — the degraded-gate-pass detector. A GP with ≥25% of rows missing a
// brand name or a size is "too degraded" to drive the item list, so the caller
// falls back to the clean bill (bill-primary). Clean GPs (FM Tower) must NOT
// trip it; chhotu's Mahua Khera job (19/51 empty names + 12/51 zero sizes) must.
func TestGatePassTooDegradedForPrimary(t *testing.T) {
	mk := func(name string, sizeML int) GatePassDutyItem {
		return GatePassDutyItem{BrandName: name, SizeML: sizeML}
	}

	tests := []struct {
		name     string
		items    []GatePassDutyItem
		wantDeg  bool
	}{
		{
			name:    "empty gp → not degraded (caller handles len==0 elsewhere)",
			items:   nil,
			wantDeg: false,
		},
		{
			name: "clean GP (FM Tower-like) → not degraded",
			items: []GatePassDutyItem{
				mk("Royal Stag Superior Whisky", 180),
				mk("Blenders Pride", 750),
				mk("8 PM Gold", 375),
				mk("Magic Moments Vodka", 180),
			},
			wantDeg: false,
		},
		{
			name: "one bad of five (20%) → below 25% → not degraded",
			items: []GatePassDutyItem{
				mk("A", 180), mk("B", 180), mk("C", 180), mk("D", 180), mk("", 0),
			},
			wantDeg: false,
		},
		{
			name: "two bad of five (40%) → degraded",
			items: []GatePassDutyItem{
				mk("A", 180), mk("B", 180), mk("C", 180), mk("", 180), mk("E", 0),
			},
			wantDeg: true,
		},
		{
			name: "Mahua Khera-like: many empty names + zero sizes → degraded",
			items: func() []GatePassDutyItem {
				out := make([]GatePassDutyItem, 0, 51)
				for i := 0; i < 32; i++ {
					out = append(out, mk("Some Brand Whisky", 180))
				}
				for i := 0; i < 19; i++ {
					out = append(out, mk("", 0)) // empty name + zero size
				}
				return out
			}(),
			wantDeg: true, // 19/51 ≈ 37% ≥ 25%
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, _, _ := gatePassTooDegradedForPrimary(tc.items)
			if got != tc.wantDeg {
				t.Errorf("degraded = %v, want %v", got, tc.wantDeg)
			}
		})
	}
}
