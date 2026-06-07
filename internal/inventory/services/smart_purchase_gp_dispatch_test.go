package services

import "testing"

// v1.0.340 — full-case dispatch invariant. The real failure: 90ml Royal Stag
// Superior printed 1 case × 96 bottles, Textract bled 48 from the 180ml row
// below. reconcileGPDispatchBottles must restore 96, and must NOT touch
// correct rows, unknown sizes, or over-reads.
func TestReconcileGPDispatchBottles(t *testing.T) {
	items := []GatePassDutyItem{
		{BrandName: "Royal Stag Superior 90", SizeML: 90, Cases: 1, Bottles: 48},  // bled → 96
		{BrandName: "Blenders Pride 180", SizeML: 180, Cases: 1, Bottles: 48},      // correct → keep
		{BrandName: "Officers Choice 180", SizeML: 180, Cases: 10, Bottles: 480},   // correct → keep
		{BrandName: "After Dark 750", SizeML: 750, Cases: 1, Bottles: 0},           // dropped → 12
		{BrandName: "8PM Gold 90", SizeML: 90, Cases: 2, Bottles: 96},              // 2×96=192? no, 8PM is 90→96 → 192
		{BrandName: "Unknown size", SizeML: 0, Cases: 1, Bottles: 5},               // unknown → keep
		{BrandName: "Over-read", SizeML: 180, Cases: 1, Bottles: 60},               // >48 → keep+warn
	}
	fixed := reconcileGPDispatchBottles(items)

	want := []int{96, 48, 480, 12, 192, 5, 60}
	for i, w := range want {
		if items[i].Bottles != w {
			t.Errorf("row %d (%s): bottles=%d, want %d", i, items[i].BrandName, items[i].Bottles, w)
		}
	}
	// rows 0 (48→96), 3 (0→12), 4 (96→192) were corrected = 3
	if fixed != 3 {
		t.Errorf("fixed=%d, want 3", fixed)
	}
}

// Guards idempotency: running twice must not change anything the second time.
func TestReconcileGPDispatchBottlesIdempotent(t *testing.T) {
	items := []GatePassDutyItem{
		{BrandName: "Royal Stag Superior 90", SizeML: 90, Cases: 1, Bottles: 48},
		{BrandName: "After Dark 750", SizeML: 750, Cases: 1, Bottles: 0},
	}
	reconcileGPDispatchBottles(items)
	if second := reconcileGPDispatchBottles(items); second != 0 {
		t.Errorf("second pass corrected %d rows, want 0 (not idempotent)", second)
	}
}
