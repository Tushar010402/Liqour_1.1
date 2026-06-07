package services

import "testing"

// TestReconcileMergedAgainstFooter mirrors chhotu job 0673458a: the raw LLM read
// got "M2 Magic Moments Superior Vodka" as 375ml 1×24 (S.No 16) AND 180ml 2×96
// (S.No 17) and reconciled to the printed footer; the Textract overlay in
// mergeGPEnsemble then bled S.No 17 into a phantom 375ml 1×24, breaking the total.
// The printed footer is the judge: the corrupted row must revert to the LLM read.
func TestReconcileMergedAgainstFooter(t *testing.T) {
	mk := func(sno int, brand string, sizeML, cases, bottles int, duty float64) GatePassDutyItem {
		return GatePassDutyItem{
			RowNumber: sno, BrandName: brand,
			SizeML: sizeML, Cases: cases, Bottles: bottles, DutyFee: duty,
		}
	}

	// The correct LLM read: 24 + 96 + 24 = 144 bottles.
	llm := func() []GatePassDutyItem {
		return []GatePassDutyItem{
			mk(16, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5138.64),
			mk(17, "M2 Magic Moments Superior Vodka", 180, 2, 96, 10389.12),
			mk(18, "All Seasons Rare Reserve Whisky", 375, 1, 24, 5777.04),
		}
	}

	t.Run("reverts overlay-bled row to the LLM read", func(t *testing.T) {
		// Overlay bled S.No 17: 180/2×96 → phantom 375/1×24. Sum 24+24+24 = 72,
		// off the footer 144 by 72 (> tol 48), while the LLM read reconciles.
		merged := []GatePassDutyItem{
			mk(16, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5138.64),
			mk(17, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5441.64), // corrupted (size+qty+duty bled)
			mk(18, "All Seasons Rare Reserve Whisky", 375, 1, 24, 5777.04),
		}
		// Footer litres = 24×375 + 96×180 + 24×375 = 35.28 L (validates SIZE).
		footer := &GatePassExtraction{TotalCases: 4, TotalBottles: 144, TotalLitres: 35.28}
		out := reconcileMergedAgainstFooter(merged, llm(), footer)

		if out[1].SizeML != 180 || out[1].Cases != 2 || out[1].Bottles != 96 {
			t.Fatalf("row 17 must revert to LLM 180/2×96, got %dml %dc/%db", out[1].SizeML, out[1].Cases, out[1].Bottles)
		}
		if out[1].DutyFee != 10389.12 {
			t.Errorf("row 17 duty must revert to 10389.12, got %.2f", out[1].DutyFee)
		}
		if out[0].SizeML != 375 || out[2].SizeML != 375 {
			t.Errorf("already-correct rows must be untouched")
		}
		sum := 0
		for _, r := range out {
			sum += r.Bottles
		}
		if sum != 144 {
			t.Errorf("post-revert bottle sum = %d, want 144 (reconciled)", sum)
		}
	})

	t.Run("no-op when the merge already reconciles", func(t *testing.T) {
		merged := llm() // identical, already correct
		footer := &GatePassExtraction{TotalCases: 4, TotalBottles: 144}
		out := reconcileMergedAgainstFooter(merged, llm(), footer)
		if out[1].SizeML != 180 || out[1].Bottles != 96 {
			t.Errorf("correct merge must be left untouched")
		}
	})

	t.Run("no-op when the LLM read does not reconcile either", func(t *testing.T) {
		// Both off the footer → we cannot trust the LLM read, so keep merged.
		merged := []GatePassDutyItem{
			mk(16, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5138.64),
			mk(17, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5441.64),
			mk(18, "All Seasons Rare Reserve Whisky", 375, 1, 24, 5777.04),
		}
		badLLM := []GatePassDutyItem{
			mk(16, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5138.64),
			mk(17, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5441.64),
			mk(18, "All Seasons Rare Reserve Whisky", 375, 1, 24, 5777.04),
		}
		footer := &GatePassExtraction{TotalCases: 4, TotalBottles: 144} // neither sums to 144
		out := reconcileMergedAgainstFooter(merged, badLLM, footer)
		if out[1].SizeML != 375 {
			t.Errorf("must NOT revert when the LLM read also fails to reconcile")
		}
	})

	t.Run("litres total catches a size error that bottles alone cannot", func(t *testing.T) {
		// The read's bottle total matches the footer (144) but a SIZE is wrong:
		// row 17 read as 375ml/96 instead of 180ml/96. Bottles still sum to 144,
		// so cases+bottles look fine — but litres = 9 + 36 + 9 = 54L ≠ footer 35.28L,
		// so we must NOT trust this read (no revert).
		sizeWrongLLM := []GatePassDutyItem{
			mk(16, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5138.64),
			mk(17, "M2 Magic Moments Superior Vodka", 375, 4, 96, 10389.12), // size wrong (should be 180)
			mk(18, "All Seasons Rare Reserve Whisky", 375, 1, 24, 5777.04),
		}
		merged := []GatePassDutyItem{
			mk(16, "M2 Magic Moments Superior Vodka", 375, 1, 24, 5138.64),
			mk(17, "M2 Magic Moments Superior Vodka", 180, 2, 96, 10389.12), // merge happens to be right
			mk(18, "All Seasons Rare Reserve Whisky", 375, 1, 24, 5777.04),
		}
		footer := &GatePassExtraction{TotalCases: 4, TotalBottles: 144, TotalLitres: 35.28}
		out := reconcileMergedAgainstFooter(merged, sizeWrongLLM, footer)
		if out[1].SizeML != 180 {
			t.Errorf("must NOT revert to a read whose litres total fails (size-wrong LLM); merged size should stand")
		}
	})

	t.Run("no-op when no footer total is known", func(t *testing.T) {
		merged := []GatePassDutyItem{
			mk(17, "M2 Magic Moments Superior Vodka", 375, 1, 24, 0),
		}
		footer := &GatePassExtraction{TotalBottles: 0}
		out := reconcileMergedAgainstFooter(merged, []GatePassDutyItem{
			mk(17, "M2 Magic Moments Superior Vodka", 180, 2, 96, 0),
		}, footer)
		if out[0].SizeML != 375 {
			t.Errorf("must NOT change anything without a footer oracle")
		}
	})
}
