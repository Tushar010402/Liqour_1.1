package services

import "testing"

func TestPackagingFamilies(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"Glass Bottle", 1},
		{"Pet Bottle", 1},
		{"Tetra (Laminate)", 1},
		{"Laminate (Tetra)", 1},
		{"Laminate (Tetra) Glass", 2}, // the real bleed fingerprint
		{"Glass Pet", 2},
		{"", 0},
		{"Bottle", 0}, // generic word, no family
	}
	for _, c := range cases {
		if got := len(packagingFamilies(c.in)); got != c.want {
			t.Errorf("packagingFamilies(%q) = %d families, want %d (%v)", c.in, got, c.want, packagingFamilies(c.in))
		}
	}
}

// TestRepairGPSizeBleed_RealAfterDarkMoonwalk reproduces job 3f8a6dc8 exactly:
// the Packaging Size + Packaging Type columns were crossed between adjacent rows
// 10 (Moonwalk) and 11 (After Dark). The repair must swap the sizes back, split
// the concatenated packaging, keep the (correct) bottle counts untouched, and
// flag both rows for review.
func TestRepairGPSizeBleed_RealAfterDarkMoonwalk(t *testing.T) {
	// merged ensemble output (Textract size/packaging won — i.e. WRONG)
	rows := []GatePassDutyItem{
		{RowNumber: 10, BrandName: "Moonwalk Green Apple Vodka", SizeML: 375, Size: "375ML", PackagingType: "Glass Bottle", Cases: 1, Bottles: 24, DutyFee: 7204.56},
		{RowNumber: 11, BrandName: "After Dark Blue Rare Grain Whisky", SizeML: 180, Size: "180ML", PackagingType: "Laminate (Tetra) Glass", Cases: 2, Bottles: 96, DutyFee: 9160.32},
	}
	// vision-LLM read (bleed-resistant — the ground truth, verified against the
	// real gate-pass pixels for job 4f2b33cf): the Cases/Bottles columns ALSO bled
	// between these two rows, so the LLM's counts are the opposite of Textract's.
	llm := []GatePassDutyItem{
		{RowNumber: 10, BrandName: "Moonwalk Green Apple Vodka", SizeML: 180, PackagingType: "Laminate (Tetra)", Cases: 2, Bottles: 96},
		{RowNumber: 11, BrandName: "After Dark Blue Rare Grain Whisky", SizeML: 375, PackagingType: "Glass Bottle", Cases: 1, Bottles: 24},
	}

	if n := repairGPSizeBleed(rows, llm); n != 1 {
		t.Fatalf("repaired %d swaps, want 1", n)
	}

	// Moonwalk → 180 / Tetra, and the bled count is corrected to the LLM's coherent
	// read: 2 cases × 48 = 96 bottles (was Textract's bled 1×24). This is the v373
	// fix for chhotu's "Moonwalk quantity is wrong" report.
	if rows[0].SizeML != 180 {
		t.Errorf("Moonwalk size = %d, want 180", rows[0].SizeML)
	}
	if len(packagingFamilies(rows[0].PackagingType)) != 1 || !familiesContain(packagingFamilies(rows[0].PackagingType), "tetra") {
		t.Errorf("Moonwalk packaging = %q, want clean Tetra", rows[0].PackagingType)
	}
	if rows[0].Cases != 2 || rows[0].Bottles != 96 {
		t.Errorf("Moonwalk dispatch = %d×%d (bottles=%d), want 2 cases / 96 bottles", rows[0].Cases, rows[0].Bottles, rows[0].Bottles)
	}
	if !rows[0].SizeBleedSuspect {
		t.Error("Moonwalk must be flagged SizeBleedSuspect")
	}

	// After Dark → 375 / Glass, count corrected to the LLM's coherent 1 case × 24.
	if rows[1].SizeML != 375 {
		t.Errorf("After Dark size = %d, want 375", rows[1].SizeML)
	}
	if rows[1].PackagingType != "Glass Bottle" {
		t.Errorf("After Dark packaging = %q, want Glass Bottle", rows[1].PackagingType)
	}
	if rows[1].Cases != 1 || rows[1].Bottles != 24 {
		t.Errorf("After Dark dispatch = %d×%d (bottles=%d), want 1 case / 24 bottles", rows[1].Cases, rows[1].Bottles, rows[1].Bottles)
	}
	if !rows[1].SizeBleedSuspect {
		t.Error("After Dark must be flagged SizeBleedSuspect")
	}
}

// TestAdoptLLMQty_OnlyWhenCoherent guards the v373 count-adoption: it must take
// the LLM dispatch only when it forms a clean full-case pack under the corrected
// size, and otherwise leave Textract's count alone (no incoherent guesses).
func TestAdoptLLMQty_OnlyWhenCoherent(t *testing.T) {
	// Coherent LLM (2×48=96 for 180ml) → adopted.
	r := GatePassDutyItem{SizeML: 180, Cases: 1, Bottles: 24}
	adoptLLMQty(&r, []GatePassDutyItem{{Cases: 2, Bottles: 96}}, 0)
	if r.Cases != 2 || r.Bottles != 96 {
		t.Errorf("coherent adopt: got %d×%d, want 2×96", r.Cases, r.Bottles)
	}
	// Incoherent LLM (3×50=150 ≠ 3×48 for 180ml) → keep Textract's count.
	r2 := GatePassDutyItem{SizeML: 180, Cases: 1, Bottles: 48}
	adoptLLMQty(&r2, []GatePassDutyItem{{Cases: 3, Bottles: 150}}, 0)
	if r2.Cases != 1 || r2.Bottles != 48 {
		t.Errorf("incoherent keep: got %d×%d, want 1×48", r2.Cases, r2.Bottles)
	}
	// Missing LLM counts → no-op.
	r3 := GatePassDutyItem{SizeML: 375, Cases: 1, Bottles: 24}
	adoptLLMQty(&r3, []GatePassDutyItem{{}}, 0)
	if r3.Cases != 1 || r3.Bottles != 24 {
		t.Errorf("empty LLM: got %d×%d, want 1×24", r3.Cases, r3.Bottles)
	}
}

// TestRepairGPSizeBleed_LLMContradictionDoesNotSwap: if the LLM read contradicts
// the geometric swap, we must NOT auto-correct — only flag for review. No blunder.
func TestRepairGPSizeBleed_LLMContradictionDoesNotSwap(t *testing.T) {
	rows := []GatePassDutyItem{
		{RowNumber: 10, BrandName: "A", SizeML: 375, PackagingType: "Glass Bottle", Cases: 1, Bottles: 24},
		{RowNumber: 11, BrandName: "B", SizeML: 180, PackagingType: "Laminate (Tetra) Glass", Cases: 2, Bottles: 96},
	}
	// LLM says B is 750 (neither 180 nor the swap's 375) — a contradiction.
	llm := []GatePassDutyItem{
		{SizeML: 90},
		{SizeML: 750},
	}
	if n := repairGPSizeBleed(rows, llm); n != 0 {
		t.Fatalf("repaired %d, want 0 (LLM contradicts)", n)
	}
	if rows[1].SizeML != 180 {
		t.Errorf("B size = %d, want 180 unchanged (no guess)", rows[1].SizeML)
	}
	if !rows[1].SizeBleedSuspect {
		t.Error("B must still be flagged for review")
	}
}

// TestRepairGPSizeBleed_SafetyNetPermutation locks the false-positive guard from
// job 3f8a6dc8: the LLM swapped the two same-brand "Royal Green" sizes (Textract
// {180,375} correct → LLM {375,180}); those rows must NOT be flagged. But a real
// standalone misread ("Verve Cranberry": Textract 180, truth/LLM 375, brand has
// no 375 in the Textract set) MUST be flagged.
func TestRepairGPSizeBleed_SafetyNetPermutation(t *testing.T) {
	rows := []GatePassDutyItem{
		{RowNumber: 6, BrandName: "Royal Green Reserve Blended Whisky", SizeML: 180, PackagingType: "Glass Bottle", Cases: 1, Bottles: 48},
		{RowNumber: 8, BrandName: "M2 Magic Moments Verve Cranberry", SizeML: 180, PackagingType: "Glass Bottle", Cases: 1, Bottles: 48},
		{RowNumber: 12, BrandName: "Royal Green Reserve Blended Whisky", SizeML: 375, PackagingType: "Glass Bottle", Cases: 1, Bottles: 24},
	}
	llm := []GatePassDutyItem{
		{SizeML: 375}, // LLM swapped the two Royal Green sizes
		{SizeML: 375}, // LLM correctly read Verve Cranberry as 375 (Textract wrong)
		{SizeML: 180},
	}
	repairGPSizeBleed(rows, llm)
	if rows[0].SizeBleedSuspect {
		t.Error("row 6 Royal Green must NOT be flagged (LLM same-brand reorder)")
	}
	if rows[2].SizeBleedSuspect {
		t.Error("row 12 Royal Green must NOT be flagged (LLM same-brand reorder)")
	}
	if !rows[1].SizeBleedSuspect {
		t.Error("row 8 Verve Cranberry MUST be flagged (genuine standalone size misread)")
	}
}

// TestRepairGPSizeBleed_CleanRowsUntouched: ordinary clean rows are never altered
// or flagged (no false positives on the 28 good rows).
func TestRepairGPSizeBleed_CleanRowsUntouched(t *testing.T) {
	rows := []GatePassDutyItem{
		{RowNumber: 1, BrandName: "X", SizeML: 750, PackagingType: "Glass Bottle", Cases: 1, Bottles: 12},
		{RowNumber: 2, BrandName: "Y", SizeML: 180, PackagingType: "Pet Bottle", Cases: 1, Bottles: 48},
	}
	llm := []GatePassDutyItem{
		{SizeML: 750, PackagingType: "Glass Bottle"},
		{SizeML: 180, PackagingType: "Pet Bottle"},
	}
	if n := repairGPSizeBleed(rows, llm); n != 0 {
		t.Fatalf("repaired %d, want 0", n)
	}
	for i := range rows {
		if rows[i].SizeBleedSuspect {
			t.Errorf("clean row %d wrongly flagged", rows[i].RowNumber)
		}
	}
}
