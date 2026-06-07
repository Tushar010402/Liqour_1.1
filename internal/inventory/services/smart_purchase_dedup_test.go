package services

import "testing"

// TestClassifyDuplicateBindings_SameProduct — v1.0.361: the gate-pass serial is
// each line's identity. The same product on NON-adjacent DISTINCT serials (M2
// Jamun on S.No 9 AND 33) is two legitimate dispatch lines → KEPT and summed (real
// data: chhotu's SONU SINGH GP lists After Dark 180ml on S.No 2 AND 11). A
// DIFFERENT-brand collision (Superior Vodka mis-bound onto Stag) is still UNBOUND
// so the distinct line survives review. (Supersedes the v1.0.335 "a GP never
// repeats a product → drop the duplicate", which silently lost real lines.)
func TestClassifyDuplicateBindings_SameProduct(t *testing.T) {
	pid := func(s string) *string { return &s }
	rows := []SmartPurchaseExtractedItem{
		{RowNumber: 9, BrandName: "M2 Magic Moments Jamun Spicymint Vodka", SizeML: 180, QuantityBottles: 48, ProductID: pid("p-m2"), MatchConfidence: 1.0},
		{RowNumber: 20, BrandName: "Officers Choice Whisky", SizeML: 180, QuantityBottles: 48, ProductID: pid("p-oc"), MatchConfidence: 1.0},
		{RowNumber: 29, BrandName: "Superior Whisky", SizeML: 180, QuantityBottles: 48, ProductID: pid("p-stag"), MatchConfidence: 1.0},
		{RowNumber: 33, BrandName: "M2 Magic Moments Jamun Spicy Mint Vodka", SizeML: 180, QuantityBottles: 48, ProductID: pid("p-m2"), MatchConfidence: 0.9}, // distinct serial → kept
		{RowNumber: 35, BrandName: "Superior Vodka", SizeML: 180, QuantityBottles: 48, ProductID: pid("p-stag"), MatchConfidence: 0.85},                       // mis-bind onto Stag
	}
	unbind, drop := classifyDuplicateBindings(rows)
	// M2 on serials 9 & 33 are distinct lines → NOT dropped.
	if len(drop) != 0 {
		t.Errorf("distinct-serial same-product lines must be kept; got drop=%v", drop)
	}
	// row 35 (idx 4) "Superior Vodka" ≠ "Superior Whisky" → unbind, not drop.
	if len(unbind) != 1 || unbind[0] != 4 {
		t.Errorf("expected unbind=[4] (Superior Vodka mis-bind), got %v", unbind)
	}
}

// TestPostProcess_TrailingDuplicateRow locks in the v1.0.335 duplicate-row
// guard. Real failure (FM Tower job 52714ffc replay on v1.0.334): the GP
// "Total" footer row OCR'd as a plausible small quantity (1 case / 12 btl)
// bleeding the previous product's brand, so "M2 Magic Moments Jamun Spicymint
// 750ml 12btl" arrived as BOTH rows 39 and 40 → would sum to 24 at approve.
// The terminal twin must be dropped; genuine repeats must be kept.
func TestPostProcess_TrailingDuplicateRow(t *testing.T) {
	mk := func(brand string, sizeML, cases, bottles int) SmartPurchaseExtractedItem {
		return SmartPurchaseExtractedItem{BrandName: brand, SizeML: sizeML, QuantityRaw: cases, QuantityBottles: bottles}
	}

	t.Run("footer-bleed terminal twin dropped", func(t *testing.T) {
		rows := []SmartPurchaseExtractedItem{
			mk("Iconiq White Deluxe", 375, 1, 48),
			mk("Officers Choice", 180, 1, 48),
			mk("M2 Verve Cranberry", 180, 1, 48),
			mk("M2 Magic Moments Jamun Spicymint Vodka", 750, 1, 12),
			mk("M2 Magic Moments Jamun Spicymint Vodka", 750, 1, 12), // footer bleed
		}
		out := postProcessGPPrimaryRows(rows)
		if len(out) != 4 {
			t.Fatalf("expected 4 rows after dropping terminal twin, got %d", len(out))
		}
		// exactly one M2 Jamun row survives
		n := 0
		for _, it := range out {
			if normBrandKey(it.BrandName) == normBrandKey("M2 Magic Moments Jamun Spicymint Vodka") {
				n++
			}
		}
		if n != 1 {
			t.Errorf("expected exactly 1 M2 Jamun row, got %d", n)
		}
	})

	t.Run("genuine two-line dispatch (different qty) kept", func(t *testing.T) {
		rows := []SmartPurchaseExtractedItem{
			mk("Iconiq White Deluxe", 375, 1, 48),
			mk("Officers Choice", 180, 1, 48),
			mk("Blenders Pride Reserve", 750, 2, 24),
			mk("Blenders Pride Reserve", 750, 1, 12), // same SKU, different qty — real
		}
		out := postProcessGPPrimaryRows(rows)
		if len(out) != 4 {
			t.Errorf("genuine different-qty repeat must be kept; expected 4 rows, got %d", len(out))
		}
	})

	t.Run("identical pair NOT at the end is kept (not footer)", func(t *testing.T) {
		rows := []SmartPurchaseExtractedItem{
			mk("After Dark Blue", 750, 1, 12),
			mk("After Dark Blue", 750, 1, 12), // mid-document identical pair
			mk("Officers Choice", 180, 1, 48),
			mk("Iconiq White Deluxe", 375, 1, 48),
		}
		out := postProcessGPPrimaryRows(rows)
		if len(out) != 4 {
			t.Errorf("non-terminal identical pair must be kept; expected 4 rows, got %d", len(out))
		}
	})
}
