package services

import "testing"

// These tests lock in decideDriftReconcile — the pure decision behind the
// v1.0.336 sales-aware opening-drift reconcile in ApproveDailySalesRecord.
//
// Root cause it fixes: the legacy reconcile snapped live stock fully UP to the
// operator-vouched opening on ANY mismatch, then deducted. When a backlog of
// records was batch-approved (every record carrying the SAME submit-time
// opening), each approval snapped the balance back up and erased the prior
// record's legitimate daily_sale — Mahua Khera 2026-06-02, 60 products / 1035
// bottles overstated. The fix reconciles only the non-sale-attributable
// residual of the gap; the portion already sold since submit is left intact.

// TestDriftReconcile_BatchApprovalCancellation is the regression lock. It
// replays the real OFFICER'S CHOICE 180ml sequence: opening vouched at 600 on
// every backlog record, sold 36/30/40/50/44 across 5 records approved in turn.
// Under the legacy logic the live balance kept snapping back to 600 and only
// the last deduction stuck (ended at 556). Sales-aware, each gap is fully
// explained by prior sales → no reconcile, deduct from live → ends at 400.
func TestDriftReconcile_BatchApprovalCancellation(t *testing.T) {
	const vouched = 600
	sales := []int{36, 30, 40, 50, 44}

	live := 600          // current live balance going into each approval
	salesSince := 0      // Σ|daily_sale| recorded after submit (grows as prior records commit)
	for i, sold := range sales {
		illegitGap, deductBasis := decideDriftReconcile(vouched, live, salesSince, true)
		if illegitGap != 0 {
			t.Fatalf("record %d: expected no reconcile (gap fully sale-attributable), got illegitGap=%d", i, illegitGap)
		}
		if deductBasis != live {
			t.Fatalf("record %d: expected deductBasis==live=%d, got %d", i, live, deductBasis)
		}
		// Apply the deduction the approve loop would perform.
		live = deductBasis - sold
		salesSince += sold
	}
	if live != 400 {
		t.Fatalf("final stock = %d, want 400 (200 sold from 600); 556 would be the cancellation bug", live)
	}
}

// TestDriftReconcile_FMTowerRestorePreserved — the genuine clobber the reconcile
// was originally built for (record 2bc7c3c0): an un-laddered stock-setup write
// silently dropped live 94→26 with NO intervening sale. Must still restore.
func TestDriftReconcile_FMTowerRestorePreserved(t *testing.T) {
	illegitGap, deductBasis := decideDriftReconcile(94, 26, 0, true)
	if illegitGap != 68 {
		t.Fatalf("illegitGap = %d, want 68 (full clobber reconciled)", illegitGap)
	}
	if deductBasis != 94 {
		t.Fatalf("deductBasis = %d, want 94 (restored to vouched opening)", deductBasis)
	}
}

// TestDriftReconcile_MixedDriftAndSale proves the precise variant beats a binary
// "skip if any sale since" rule: a 68-unit clobber AND a legitimate 10-unit sale
// both occurred. Reconcile only the non-sale 68, honor the real 10.
func TestDriftReconcile_MixedDriftAndSale(t *testing.T) {
	illegitGap, deductBasis := decideDriftReconcile(94, 16, 10, true) // gap=78, salesSince=10
	if illegitGap != 68 {
		t.Fatalf("illegitGap = %d, want 68 (78 gap minus 10 legitimate sales)", illegitGap)
	}
	if deductBasis != 84 {
		t.Fatalf("deductBasis = %d, want 84 (live 16 + 68 restored)", deductBasis)
	}
}

// TestDriftReconcile_NegativeIllegitGapNoUpReconcile — live is HIGHER than the
// vouched opening (e.g. an intervening purchase). Never reconcile upward into a
// purchase; deduct from live as-is.
func TestDriftReconcile_NegativeIllegitGapNoUpReconcile(t *testing.T) {
	illegitGap, deductBasis := decideDriftReconcile(600, 650, 0, true) // gap = -50
	if illegitGap != 0 {
		t.Fatalf("illegitGap = %d, want 0 (no upward reconcile when live exceeds vouched)", illegitGap)
	}
	if deductBasis != 650 {
		t.Fatalf("deductBasis = %d, want 650 (deduct from live)", deductBasis)
	}
}

// TestDriftReconcile_NoDrift — vouched opening equals live: nothing to do.
func TestDriftReconcile_NoDrift(t *testing.T) {
	illegitGap, deductBasis := decideDriftReconcile(500, 500, 0, true)
	if illegitGap != 0 || deductBasis != 500 {
		t.Fatalf("got illegitGap=%d deductBasis=%d, want 0 / 500", illegitGap, deductBasis)
	}
}

// TestDriftReconcile_OpeningZeroSkipsGuard — legacy/manual rows with no vouched
// opening (0) must never trigger the guard; deduct from live.
func TestDriftReconcile_OpeningZeroSkipsGuard(t *testing.T) {
	illegitGap, deductBasis := decideDriftReconcile(0, 120, 0, true)
	if illegitGap != 0 || deductBasis != 120 {
		t.Fatalf("got illegitGap=%d deductBasis=%d, want 0 / 120", illegitGap, deductBasis)
	}
}

// TestDriftReconcile_KillSwitchOff — SMART_SALE_DRIFT_RECONCILE_SALES_AWARE=0
// must reproduce the legacy full-snap behavior exactly, so the flag is a true
// revert. Same OFFICER'S CHOICE inputs: legacy snaps fully to the vouched 600.
func TestDriftReconcile_KillSwitchOff(t *testing.T) {
	illegitGap, deductBasis := decideDriftReconcile(600, 564, 36, false)
	if illegitGap != 36 { // 600 - 564, salesSince ignored in legacy mode
		t.Fatalf("illegitGap = %d, want 36 (legacy full snap to vouched)", illegitGap)
	}
	if deductBasis != 600 {
		t.Fatalf("deductBasis = %d, want 600 (legacy snaps to vouched opening)", deductBasis)
	}
}
