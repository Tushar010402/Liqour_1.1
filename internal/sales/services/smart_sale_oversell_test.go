package services

import "testing"

func intp(v int) *int { return &v }

// TestDeriveBlockingWarnings_OverSell locks in the over-sell detection that
// underlies the v1.0.335 reconciliation flow. The real report: "Moonwalk Green
// Apple Vodka" at Mahua Khera showed opening 11 but a confirmed sold qty of 50
// (an OCR misread) → closing −39. The review gate must flag this row with
// "exceeds available stock" so it can never silently persist.
func TestDeriveBlockingWarnings_OverSell(t *testing.T) {
	cases := []struct {
		name     string
		item     SmartSaleApplyItem
		wantWarn string
		want     bool
	}{
		{
			name:     "moonwalk 50 vs 11 — over-sell flagged",
			item:     SmartSaleApplyItem{Quantity: 50, OpeningStock: intp(11)},
			wantWarn: "exceeds available stock",
			want:     true,
		},
		{
			name:     "receipt lifts the cap — 50 vs 11+45 kept",
			item:     SmartSaleApplyItem{Quantity: 50, OpeningStock: intp(11), Receipt: intp(45)},
			wantWarn: "exceeds available stock",
			want:     false,
		},
		{
			name:     "exactly at cap — kept",
			item:     SmartSaleApplyItem{Quantity: 11, OpeningStock: intp(11)},
			wantWarn: "exceeds available stock",
			want:     false,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			warns := deriveBlockingWarningsFromItem(c.item)
			got := false
			for _, w := range warns {
				if w == c.wantWarn {
					got = true
				}
			}
			if got != c.want {
				t.Errorf("deriveBlockingWarningsFromItem(qty=%d open=%v recv=%v) over-sell=%v, want %v (warns=%v)",
					c.item.Quantity, c.item.OpeningStock, c.item.Receipt, got, c.want, warns)
			}
		})
	}
}
