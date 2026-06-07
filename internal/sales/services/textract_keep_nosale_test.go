package services

import (
	"os"
	"testing"
)

// Pure-logic test for the v1.0.312 filter narrowing: mirrors the loop in
// extractWithTextract that decides which qty=0 rows to keep vs drop. We don't
// invoke extractWithTextract directly (it requires AWS creds + image bytes);
// instead we reproduce the gate so the policy is regression-tested.
func filterPreMatcherForTest(in []ExtractedReceiptItem) (kept []ExtractedReceiptItem, droppedEmpty, keptNoSale int) {
	keepNoSale := textractKeepNoSaleEnabled()
	out := make([]ExtractedReceiptItem, 0, len(in))
	for _, it := range in {
		if it.Quantity > 0 {
			out = append(out, it)
			continue
		}
		if !keepNoSale {
			droppedEmpty++
			continue
		}
		open := 0
		if it.OpeningStock != nil {
			open = *it.OpeningStock
		}
		closeQ := 0
		if it.ClosingStock != nil {
			closeQ = *it.ClosingStock
		}
		amt := 0.0
		if it.Price != nil {
			amt = *it.Price
		}
		if open > 0 || closeQ > 0 || amt > 0 {
			it.IsZeroQuantity = true
			out = append(out, it)
			keptNoSale++
			continue
		}
		droppedEmpty++
	}
	return out, droppedEmpty, keptNoSale
}

func iPtr(v int) *int       { return &v }
func fPtr(v float64) *float64 { return &v }

func TestKeepNoSale_KeepsOpeningOnlyRow(t *testing.T) {
	// Real case from chhotu today_p1 row 20: "Royal Stag Superior Whisky"
	// opening=170, no sale today, closing=blank.
	in := []ExtractedReceiptItem{
		{Brand: "Royal Stag Superior Whisky", Quantity: 0, OpeningStock: iPtr(170)},
	}
	kept, dropped, keptNoSale := filterPreMatcherForTest(in)
	if len(kept) != 1 {
		t.Fatalf("expected 1 row kept (opening>0), got %d", len(kept))
	}
	if !kept[0].IsZeroQuantity {
		t.Errorf("expected IsZeroQuantity=true on kept no-sale row")
	}
	if dropped != 0 {
		t.Errorf("expected 0 dropped, got %d", dropped)
	}
	if keptNoSale != 1 {
		t.Errorf("expected 1 keptNoSale, got %d", keptNoSale)
	}
}

func TestKeepNoSale_DropsTrulyEmpty(t *testing.T) {
	// Layout-noise row: no brand, no opening, no closing, no amount, no qty.
	// Pre-v1.0.165 header/total guards drop this, but if any slip through
	// we want them gone.
	in := []ExtractedReceiptItem{
		{Brand: "", Quantity: 0},
	}
	kept, dropped, keptNoSale := filterPreMatcherForTest(in)
	if len(kept) != 0 {
		t.Fatalf("expected 0 kept on truly empty row, got %d", len(kept))
	}
	if dropped != 1 {
		t.Errorf("expected 1 dropped, got %d", dropped)
	}
	if keptNoSale != 0 {
		t.Errorf("expected 0 keptNoSale, got %d", keptNoSale)
	}
}

func TestKeepNoSale_KeepsSaleRowsUntouched(t *testing.T) {
	in := []ExtractedReceiptItem{
		{Brand: "8 PM Rare Whisky", Quantity: 5, OpeningStock: iPtr(44), ClosingStock: iPtr(39), Price: fPtr(1250)},
	}
	kept, dropped, keptNoSale := filterPreMatcherForTest(in)
	if len(kept) != 1 {
		t.Fatalf("expected 1 kept, got %d", len(kept))
	}
	if kept[0].IsZeroQuantity {
		t.Errorf("qty>0 row must NOT be flagged IsZeroQuantity")
	}
	if dropped != 0 || keptNoSale != 0 {
		t.Errorf("unexpected: dropped=%d keptNoSale=%d", dropped, keptNoSale)
	}
}

func TestKeepNoSale_KeepsClosingOnlyRow(t *testing.T) {
	// Row with no opening but closing>0 — operator wrote what's left over.
	in := []ExtractedReceiptItem{
		{Brand: "Some Whisky", Quantity: 0, ClosingStock: iPtr(12)},
	}
	kept, _, keptNoSale := filterPreMatcherForTest(in)
	if len(kept) != 1 {
		t.Fatalf("expected closing-only row kept, got %d rows", len(kept))
	}
	if keptNoSale != 1 {
		t.Errorf("expected keptNoSale=1, got %d", keptNoSale)
	}
}

func TestKeepNoSale_EnvDisableRevertsLegacy(t *testing.T) {
	t.Setenv("SMART_SALE_TEXTRACT_KEEP_NOSALE", "0")
	in := []ExtractedReceiptItem{
		{Brand: "Royal Stag Superior Whisky", Quantity: 0, OpeningStock: iPtr(170)},
		{Brand: "8 PM Rare Whisky", Quantity: 5, OpeningStock: iPtr(44)},
	}
	kept, dropped, keptNoSale := filterPreMatcherForTest(in)
	if len(kept) != 1 {
		t.Fatalf("expected legacy 1 kept (qty>0 only), got %d", len(kept))
	}
	if dropped != 1 {
		t.Errorf("expected legacy 1 dropped, got %d", dropped)
	}
	if keptNoSale != 0 {
		t.Errorf("legacy must NOT preserve qty=0 rows; got keptNoSale=%d", keptNoSale)
	}
	_ = os.Unsetenv("SMART_SALE_TEXTRACT_KEEP_NOSALE")
}

func TestKeepNoSale_ChhotuPage1Shape(t *testing.T) {
	// Reproduce chhotu's today_p1 shape: 18 sale rows + 12 no-sale rows
	// with opening>0. Default behavior should keep all 30.
	in := make([]ExtractedReceiptItem, 0, 30)
	for i := 0; i < 18; i++ {
		in = append(in, ExtractedReceiptItem{
			Brand: "Sale row", Quantity: 1, OpeningStock: iPtr(50),
		})
	}
	for i := 0; i < 12; i++ {
		in = append(in, ExtractedReceiptItem{
			Brand: "No-sale row", Quantity: 0, OpeningStock: iPtr(30),
		})
	}
	kept, dropped, keptNoSale := filterPreMatcherForTest(in)
	if len(kept) != 30 {
		t.Fatalf("expected all 30 rows kept (18 sale + 12 no-sale), got %d", len(kept))
	}
	if dropped != 0 {
		t.Errorf("expected 0 dropped, got %d", dropped)
	}
	if keptNoSale != 12 {
		t.Errorf("expected 12 no-sale rows preserved, got %d", keptNoSale)
	}
	saleCount, noSaleCount := 0, 0
	for _, it := range kept {
		if it.IsZeroQuantity {
			noSaleCount++
		} else {
			saleCount++
		}
	}
	if saleCount != 18 || noSaleCount != 12 {
		t.Errorf("mix wrong: sale=%d noSale=%d", saleCount, noSaleCount)
	}
}
