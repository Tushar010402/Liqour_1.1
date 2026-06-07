package services

import "testing"

// v1.0.344 — the combined-request row state machine. A confident read that's
// applied immediately is "approved" (auto); a low-confidence proposal that
// differs from the current value stays "pending" until reviewed; a read that
// matches the current value is a no-op (no real change → approved/idle).
func TestPhotoRowState(t *testing.T) {
	tests := []struct {
		name                  string
		proposedName, current string
		proposedMRP, curMRP   float64
		nameApplied           bool
		mrpApplied            bool
		wantKind              string
		wantStatus            string
		wantAuto              bool
	}{
		{
			name: "confident name auto-applied → approved",
			proposedName: "Royal Stag", current: "100 Step", nameApplied: true,
			wantKind: "name", wantStatus: "approved", wantAuto: true,
		},
		{
			name: "low-conf name queued → pending",
			proposedName: "Royal Stag", current: "100 Step", nameApplied: false,
			wantKind: "name", wantStatus: "pending", wantAuto: false,
		},
		{
			name: "name+mrp both confident → approved name_mrp",
			proposedName: "Royal Stag", current: "100 Step", nameApplied: true,
			proposedMRP: 180, curMRP: 0, mrpApplied: true,
			wantKind: "name_mrp", wantStatus: "approved", wantAuto: true,
		},
		{
			name: "name confident applied + mrp low queued → pending (mrp still needs review)",
			proposedName: "Royal Stag", current: "100 Step", nameApplied: true,
			proposedMRP: 180, curMRP: 0, mrpApplied: false,
			wantKind: "name_mrp", wantStatus: "pending", wantAuto: true,
		},
		{
			name: "mrp-only confident → approved mrp",
			proposedMRP: 250, curMRP: 0, mrpApplied: true,
			wantKind: "mrp", wantStatus: "approved", wantAuto: true,
		},
		{
			name: "mrp-only low → pending mrp",
			proposedMRP: 250, curMRP: 0, mrpApplied: false,
			wantKind: "mrp", wantStatus: "pending", wantAuto: false,
		},
		{
			name: "proposed name equals current → no real change → approved",
			proposedName: "Royal Stag", current: "royal stag", nameApplied: false,
			wantKind: "name", wantStatus: "approved", wantAuto: false,
		},
		{
			name: "proposed mrp equals current → no real change → approved",
			proposedMRP: 180, curMRP: 180, mrpApplied: false,
			wantKind: "mrp", wantStatus: "approved", wantAuto: false,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			kind, status, auto := photoRowState(tc.proposedName, tc.current, tc.proposedMRP, tc.curMRP, tc.nameApplied, tc.mrpApplied)
			if kind != tc.wantKind {
				t.Errorf("change_kind = %q, want %q", kind, tc.wantKind)
			}
			if status != tc.wantStatus {
				t.Errorf("status = %q, want %q", status, tc.wantStatus)
			}
			if auto != tc.wantAuto {
				t.Errorf("auto_applied = %v, want %v", auto, tc.wantAuto)
			}
		})
	}
}
