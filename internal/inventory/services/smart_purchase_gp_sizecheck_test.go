package services

import "testing"

// v1.0.342 — bill↔GP size cross-check decision. Closes the size-bleed edge case
// (e.g. a 750ml GP row mis-read as 180ml) using the bill as the authoritative
// size source, WITHOUT regressing correctly-extracted rows.
func TestDecideGPSizeCorrection(t *testing.T) {
	set := func(sizes ...int) map[int]bool {
		m := map[int]bool{}
		for _, s := range sizes {
			m[s] = true
		}
		return m
	}
	tests := []struct {
		name        string
		gpSize      int
		cases       int
		rawBottles  int
		bill        map[int]bool
		wantAction  string
		wantSize    int
		wantBottles int
	}{
		{
			name: "size bled 750->180, raw 12 fits bill's 750 -> correct 750/12",
			gpSize: 180, cases: 1, rawBottles: 12, bill: set(750),
			wantAction: "correct", wantSize: 750, wantBottles: 12,
		},
		{
			name: "clean row (raw 48 == 1x48 for 180) -> never touched even if bill differs",
			gpSize: 180, cases: 1, rawBottles: 48, bill: set(750),
			wantAction: "none",
		},
		{
			name: "verified 90ml: raw 48 broken but bill HAS 90 -> confirmed, skip (reconcile fixes bottles)",
			gpSize: 90, cases: 1, rawBottles: 48, bill: set(90, 750),
			wantAction: "none",
		},
		{
			name: "brand absent from bill -> no change",
			gpSize: 180, cases: 1, rawBottles: 12, bill: set(),
			wantAction: "none",
		},
		{
			name: "broken + off-bill but no bill size fits raw bottles -> ambiguous",
			gpSize: 90, cases: 1, rawBottles: 50, bill: set(180, 375),
			wantAction: "ambiguous",
		},
		{
			name: "non-standard GP size (0) -> left to resolveGPSizeML",
			gpSize: 0, cases: 1, rawBottles: 12, bill: set(750),
			wantAction: "none",
		},
		{
			name: "zero cases -> skip",
			gpSize: 180, cases: 0, rawBottles: 12, bill: set(750),
			wantAction: "none",
		},
		{
			name: "size bled 90->180, raw 96 fits bill's 90 (3 cases would be 288, here 1 case) -> correct 90/96",
			gpSize: 180, cases: 1, rawBottles: 96, bill: set(90),
			wantAction: "correct", wantSize: 90, wantBottles: 96,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			size, bottles, action := decideGPSizeCorrection(tc.gpSize, tc.cases, tc.rawBottles, tc.bill)
			if action != tc.wantAction {
				t.Fatalf("action=%q want %q", action, tc.wantAction)
			}
			if action == "correct" && (size != tc.wantSize || bottles != tc.wantBottles) {
				t.Errorf("size=%d bottles=%d, want size=%d bottles=%d", size, bottles, tc.wantSize, tc.wantBottles)
			}
		})
	}
}
