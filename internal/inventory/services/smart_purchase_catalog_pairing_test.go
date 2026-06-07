package services

import (
	"strings"
	"testing"

	"github.com/google/uuid"
)

// hasWarning reports whether the item carries the given warning code.
func hasWarning(it *SmartPurchaseExtractedItem, code string) bool {
	for _, w := range it.Warnings {
		if w == code {
			return true
		}
	}
	return false
}

// TestEnrichBillCost_CatalogIdentityPairing exercises Fix A (v1.0.331): when
// the gate-pass full canonical and the bill's clipped shorthand both resolve
// to the same master saas_brand_id, the price must pair on catalog identity
// even though raw-string token overlap is ~0 (the case that left >18 FM Tower
// rows priceless under the old fuzzy-only matcher).
func TestEnrichBillCost_CatalogIdentityPairing(t *testing.T) {
	svc := &SmartPurchaseService{} // Pass 1/2 touch no DB

	b1 := uuid.New() // 8PM Gold master brand
	b2 := uuid.New() // unrelated brand

	// GP row: full excise canonical, 180ml, resolved to b1.
	gpCanonical := "8 PM GOLD BLEND OF SCOTCH & INDIAN GRAIN WHISKY"
	sizeML := 180

	billItems := []ExtractedPurchaseItem{
		// [0] same brand, WRONG size — must be rejected by the size gate.
		{Brand: "8PM GLD QTR", SizeML: 375, Amount: 9999},
		// [1] same brand, correct size, clipped text with ~0 token overlap.
		{Brand: "8PM GLD PET", SizeML: 180, Amount: 4608},
		// [2] different brand, same size — must never be chosen.
		{Brand: "ICONIQ WHITE DELUXE", SizeML: 180, Amount: 1111},
	}
	billBrandIDs := []uuid.UUID{b1, b1, b2}

	// Sanity: the correct bill row scores below the Pass-2 token floor, so
	// only the catalog pass can rescue it. If this assumption ever breaks the
	// test still passes for the right reason, but we assert it to document why
	// Fix A is load-bearing here.
	gpToks := gpTokenSet(strings.ToLower(gpCanonical))
	billToks := gpTokenSet(strings.ToLower(billItems[1].Brand))
	if sc := maxF(jaccardTokens(gpToks, billToks), overlapCoeff(gpToks, billToks)); sc >= 0.30 {
		t.Fatalf("test setup invalid: bill[1] token score %.2f ≥ 0.30 — Pass 2 would match it, not exercising the catalog pass", sc)
	}

	// --- With catalog ids: must pair to bill[1] on identity+size. ---
	item := SmartPurchaseExtractedItem{
		BrandName:       gpCanonical,
		CanonicalBrand:  gpCanonical,
		SizeML:          sizeML,
		QuantityBottles: 96,
		QuantityRaw:     1,
	}
	svc.enrichBillCost(&item, billItems, gpCanonical, sizeML, 0, b1, billBrandIDs)

	if hasWarning(&item, "cost_missing_no_bill_match") {
		t.Fatalf("catalog pass should have paired a price; got cost_missing. warnings=%v", item.Warnings)
	}
	if item.CostSource != "bill_catalog_id" {
		t.Errorf("CostSource = %q, want bill_catalog_id", item.CostSource)
	}
	if want := 4608.0; item.Amount != want {
		t.Errorf("Amount = %.2f, want %.2f (bill[1], the same-size same-brand row)", item.Amount, want)
	}
	if want := 4608.0 / 96.0; item.RatePerBottle != want {
		t.Errorf("RatePerBottle = %.2f, want %.2f", item.RatePerBottle, want)
	}

	// --- Without catalog ids (all Nil): Pass 2 fuzzy-only must miss. ---
	item2 := SmartPurchaseExtractedItem{
		BrandName:       gpCanonical,
		CanonicalBrand:  gpCanonical,
		SizeML:          sizeML,
		QuantityBottles: 96,
		QuantityRaw:     1,
	}
	svc.enrichBillCost(&item2, billItems, gpCanonical, sizeML, 0, uuid.Nil, nil)
	if !hasWarning(&item2, "cost_missing_no_bill_match") {
		t.Errorf("without catalog ids the fuzzy-only path should miss this row; warnings=%v cost=%.2f", item2.Warnings, item2.RatePerBottle)
	}
}
