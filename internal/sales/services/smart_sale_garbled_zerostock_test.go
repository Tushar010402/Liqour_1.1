package services

import (
	"os"
	"testing"

	"github.com/sirupsen/logrus"
)

// helper — stub the minimal SmartSaleService we need (only logger).
func newTestService() *SmartSaleService {
	l := logrus.New()
	l.SetLevel(logrus.WarnLevel)
	return &SmartSaleService{logger: l}
}

func gzsPtr(s string) *string { return &s }

func TestDropGarbledZeroStockMatches_M4MJUM(t *testing.T) {
	// The exact case from chhotu's job 304e4e27 review screen.
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "M2 MAGIC MOMENTS JAMUN SPICY MINT",
			OriginalAIBrand:  "M4MJUM",
			ProductID:        gzsPtr("11111111-1111-1111-1111-111111111111"),
			MatchedBrandName: "M2 MAGIC MOMENTS JAMUN SPICY MINT",
			MatchConfidence:  0.71, // fuzzy tier
			Quantity:         2,
			NoStockBlock:     true,
			Warnings: []string{
				"Cannot record sale: M2 MAGIC MOMENTS JAMUN SPICY MINT shop stock is 0. Receive new stock before recording this sale.",
			},
		},
	}

	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 1 {
		t.Fatalf("expected 1 dropped row, got %d", dropped)
	}
	got := items[0]
	if got.ProductID != nil {
		t.Errorf("expected ProductID cleared, got %v", got.ProductID)
	}
	if got.NoStockBlock {
		t.Errorf("expected NoStockBlock cleared")
	}
	if got.ValidationStatus != "not_found" {
		t.Errorf("expected ValidationStatus=not_found, got %q", got.ValidationStatus)
	}
	if got.ReviewReason != "garbled_ocr_no_stock" {
		t.Errorf("expected ReviewReason=garbled_ocr_no_stock, got %q", got.ReviewReason)
	}
	if got.BrandName != "M4MJUM" {
		t.Errorf("expected BrandName reverted to raw OCR 'M4MJUM', got %q", got.BrandName)
	}
}

func TestDropGarbledZeroStockMatches_KeepsHighConfidence(t *testing.T) {
	// A row where shop has 0 stock but the alias-cascade was an EXACT hit
	// (operator probably wants to record a future sale once stock arrives).
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "Royal Stag Superior Whisky",
			OriginalAIBrand:  "Royal Stag Superior Whisky",
			ProductID:        gzsPtr("22222222-2222-2222-2222-222222222222"),
			MatchedBrandName: "Royal Stag Superior Whisky",
			MatchConfidence:  0.99, // exact alias hit
			Quantity:         1,
			NoStockBlock:     true,
		},
	}
	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 0 {
		t.Fatalf("expected 0 dropped (exact match must be kept), got %d", dropped)
	}
	if items[0].ProductID == nil {
		t.Errorf("ProductID must NOT be cleared on exact-match zero-stock row")
	}
	if !items[0].NoStockBlock {
		t.Errorf("NoStockBlock must remain set so apply-gate still refuses")
	}
}

func TestDropGarbledZeroStockMatches_KeepsZeroQty(t *testing.T) {
	// Zero-qty row is just an inventory snapshot, not a sale — leave alone.
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "M2 MAGIC MOMENTS JAMUN SPICY MINT",
			OriginalAIBrand:  "M4MJUM",
			ProductID:        gzsPtr("11111111-1111-1111-1111-111111111111"),
			MatchedBrandName: "M2 MAGIC MOMENTS JAMUN SPICY MINT",
			MatchConfidence:  0.71,
			Quantity:         0,
			NoStockBlock:     true,
		},
	}
	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 0 {
		t.Fatalf("expected 0 dropped on qty=0 row, got %d", dropped)
	}
}

func TestDropGarbledZeroStockMatches_KeepsOperatorAdds(t *testing.T) {
	// Operator-typed rows are explicit and must never be silently demoted.
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "Some niche SKU",
			OriginalAIBrand:  "",
			ProductID:        gzsPtr("33333333-3333-3333-3333-333333333333"),
			MatchedBrandName: "Some niche SKU",
			MatchConfidence:  0.4, // looks garbled by score
			Quantity:         3,
			NoStockBlock:     true,
			Source:           "operator_add",
		},
	}
	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 0 {
		t.Fatalf("expected 0 dropped for operator_add, got %d", dropped)
	}
}

func TestDropGarbledZeroStockMatches_LeavesStockedRows(t *testing.T) {
	// NoStockBlock false (stock exists) — nothing to do.
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "8 PM Rare Whisky",
			OriginalAIBrand:  "8 PM Rare",
			ProductID:        gzsPtr("44444444-4444-4444-4444-444444444444"),
			MatchedBrandName: "8 PM Rare Whisky",
			MatchConfidence:  0.92,
			Quantity:         5,
			NoStockBlock:     false,
		},
	}
	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 0 {
		t.Fatalf("expected 0 dropped on stocked row, got %d", dropped)
	}
}

func TestDropGarbledZeroStockMatches_DigitLetterMixShortRaw(t *testing.T) {
	// "SM19Jum" — short, mixes letters and digits, fuzzy-matched.
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "Some Whisky 180ml",
			OriginalAIBrand:  "SM19Jum",
			ProductID:        gzsPtr("55555555-5555-5555-5555-555555555555"),
			MatchedBrandName: "Some Whisky 180ml",
			MatchConfidence:  0.90, // above threshold, but raw OCR is still garbled
			Quantity:         5,
			NoStockBlock:     true,
		},
	}
	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 1 {
		t.Fatalf("expected 1 dropped (short digit-letter-mix raw), got %d", dropped)
	}
}

func TestDropGarbledZeroStockMatches_EnvDisable(t *testing.T) {
	t.Setenv("SMART_SALE_DROP_GARBLED_ZEROSTOCK", "0")
	items := []SmartSaleExtractedItem{
		{
			BrandName:        "M2 MAGIC MOMENTS JAMUN SPICY MINT",
			OriginalAIBrand:  "M4MJUM",
			ProductID:        gzsPtr("11111111-1111-1111-1111-111111111111"),
			MatchedBrandName: "M2 MAGIC MOMENTS JAMUN SPICY MINT",
			MatchConfidence:  0.71,
			Quantity:         2,
			NoStockBlock:     true,
		},
	}
	s := newTestService()
	dropped := s.dropGarbledZeroStockMatches(items)
	if dropped != 0 {
		t.Fatalf("expected 0 dropped when env flag off, got %d", dropped)
	}
	if items[0].ProductID == nil {
		t.Errorf("ProductID must be untouched when flag off")
	}
	_ = os.Unsetenv("SMART_SALE_DROP_GARBLED_ZEROSTOCK")
}

func TestIsGarbledMatch_Heuristics(t *testing.T) {
	cases := []struct {
		name string
		it   SmartSaleExtractedItem
		want bool
	}{
		{
			name: "low confidence",
			it:   SmartSaleExtractedItem{MatchConfidence: 0.6, OriginalAIBrand: "Royal Stag", BrandName: "Royal Stag"},
			want: true,
		},
		{
			name: "high conf clean",
			it:   SmartSaleExtractedItem{MatchConfidence: 0.92, OriginalAIBrand: "Royal Stag", BrandName: "Royal Stag"},
			want: false,
		},
		{
			name: "short digit-letter mix",
			it:   SmartSaleExtractedItem{MatchConfidence: 0.99, OriginalAIBrand: "SM19Jum", BrandName: "Some Whisky"},
			want: true,
		},
		{
			name: "long raw clean",
			it:   SmartSaleExtractedItem{MatchConfidence: 0.99, OriginalAIBrand: "Royal Stag Superior Whisky", BrandName: "Royal Stag Superior Whisky"},
			want: false,
		},
		{
			name: "wildly different tokens",
			it:   SmartSaleExtractedItem{MatchConfidence: 0.99, OriginalAIBrand: "xyz", BrandName: "Blender Pride Reserve Collection Blue"},
			want: true, // jaccard < 0.25
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := isGarbledMatch(&c.it)
			if got != c.want {
				t.Errorf("isGarbledMatch(%+v) = %v, want %v", c.it, got, c.want)
			}
		})
	}
}
