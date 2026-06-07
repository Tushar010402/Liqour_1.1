package services

import "testing"

// TestIsGPTotalArtifactItem locks the v1.0.348 filter that stops the LLM
// gate-pass path from emitting footer/section "Total" rows as purchase items.
// Real case: Mahua Khera job 70047c55 rows 31-32 — blank name, packaging_type
// "Total", 38 cases / 1380 bottles — surfaced to the operator as
// "not_found, no name". Real SKU rows (with a brand name) must be kept.
func TestIsGPTotalArtifactItem(t *testing.T) {
	cases := []struct {
		name string
		it   GatePassDutyItem
		want bool
	}{
		{"job70047c55 total row", GatePassDutyItem{BrandName: "", PackagingType: "Total", Cases: 38, Bottles: 1380}, true},
		{"brand says Total", GatePassDutyItem{BrandName: "Total", Cases: 77, Bottles: 2671}, true},
		{"grand total packaging", GatePassDutyItem{BrandName: "", PackagingType: "Grand Total"}, true},
		{"section subtotal", GatePassDutyItem{BrandName: "SUBTOTAL", Cases: 12}, true},
		{"sub-total hyphen", GatePassDutyItem{PackagingType: "Sub-Total"}, true},
		{"real SKU glass bottle", GatePassDutyItem{BrandName: "ICONIQ WHITE DELUXE", PackagingType: "Glass Bottle", Cases: 3, Bottles: 72}, false},
		{"real SKU tetra", GatePassDutyItem{BrandName: "8PM GOLD", PackagingType: "Tetra", Cases: 5}, false},
		{"blank-name non-total kept for degraded detector", GatePassDutyItem{BrandName: "", PackagingType: "Glass Bottle", Cases: 2, Bottles: 24}, false},
	}
	for _, c := range cases {
		if got := isGPTotalArtifactItem(c.it); got != c.want {
			t.Errorf("%s: isGPTotalArtifactItem(name=%q packaging=%q) = %v, want %v",
				c.name, c.it.BrandName, c.it.PackagingType, got, c.want)
		}
	}
}
