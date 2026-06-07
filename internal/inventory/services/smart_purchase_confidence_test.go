package services

import "testing"

// v1.0.343 — unified row confidence. A fully-corroborated row is "high"; any
// missing/disagreeing source drops it to "review" so it can't ship silently.
func TestScoreRowConfidence(t *testing.T) {
	tests := []struct {
		name     string
		item     SmartPurchaseExtractedItem
		wantTier string
	}{
		{
			name: "clean matched row, bill-corroborated price -> high",
			item: SmartPurchaseExtractedItem{
				Status: "matched", MatchConfidence: 0.95,
				QuantityRaw: 1, QuantityBottles: 96,
				RatePerBottle: 250, CostSource: "bill",
			},
			wantTier: "high",
		},
		{
			name: "not found -> review",
			item: SmartPurchaseExtractedItem{
				Status: "not_found", QuantityRaw: 1, QuantityBottles: 48, RatePerBottle: 100, CostSource: "bill",
			},
			wantTier: "review",
		},
		{
			name: "zero price -> review",
			item: SmartPurchaseExtractedItem{
				Status: "matched", MatchConfidence: 0.95,
				QuantityRaw: 1, QuantityBottles: 48, RatePerBottle: 0,
			},
			wantTier: "review",
		},
		{
			name: "auto-corrected quantity (QuantityFlagged) -> review",
			item: SmartPurchaseExtractedItem{
				Status: "matched", MatchConfidence: 0.99,
				QuantityRaw: 1, QuantityBottles: 96, RatePerBottle: 250, CostSource: "bill",
				QuantityFlagged: true,
			},
			wantTier: "review",
		},
		{
			name: "disputed bill vs GP -> review",
			item: SmartPurchaseExtractedItem{
				Status: "matched", MatchConfidence: 0.9,
				QuantityRaw: 1, QuantityBottles: 48, RatePerBottle: 200, CostSource: "bill",
				ResolutionSource: "disputed",
			},
			wantTier: "review",
		},
		{
			name: "price present but not bill-corroborated -> still high (mild)",
			item: SmartPurchaseExtractedItem{
				Status: "matched", MatchConfidence: 0.95,
				QuantityRaw: 1, QuantityBottles: 48, RatePerBottle: 200, CostSource: "",
			},
			wantTier: "high", // -0.15 only => 0.85
		},
		{
			name: "block-severity cross-val flag -> review",
			item: SmartPurchaseExtractedItem{
				Status: "matched", MatchConfidence: 0.9,
				QuantityRaw: 1, QuantityBottles: 48, RatePerBottle: 200, CostSource: "bill",
				CrossValFlags: []CrossValFlag{{Kind: "quantity_disputed", Severity: "block"}},
			},
			wantTier: "review",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			score, tier, _ := scoreRowConfidence(&tc.item)
			if tier != tc.wantTier {
				t.Errorf("tier=%q (score %.2f), want %q", tier, score, tc.wantTier)
			}
			if score < 0 || score > 1 {
				t.Errorf("score %.2f out of [0,1]", score)
			}
		})
	}
}
