package services

import "testing"

// v1.0.340 — guards the mangled-GP fallback. A clean Textract TABLES read must
// be trusted (return false); a garbled read must fall through to the LLM
// (return true). Threshold is 40% garbled rows.
func TestGPTablesLooksMangled(t *testing.T) {
	clean := func(brand string) GatePassDutyItem {
		return GatePassDutyItem{BrandName: brand, SizeML: 750, Bottles: 12}
	}
	cases := []struct {
		name    string
		items   []GatePassDutyItem
		mangled bool
	}{
		{
			name:    "empty rows → mangled",
			items:   nil,
			mangled: true,
		},
		{
			name: "all clean printed read → trusted",
			items: []GatePassDutyItem{
				clean("Seagrams Blenders Pride Whisky"),
				clean("8 PM Gold Blend Whisky"),
				clean("Royal Stag Whisky"),
				clean("Magic Moments Vodka"),
				clean("After Dark Whisky"),
			},
			mangled: false,
		},
		{
			name: "one garbled out of five (20%) → still trusted",
			items: []GatePassDutyItem{
				clean("Seagrams Blenders Pride Whisky"),
				clean("8 PM Gold Blend Whisky"),
				clean("Royal Stag Whisky"),
				clean("Magic Moments Vodka"),
				{BrandName: "42", SizeML: 0, Bottles: 0}, // numeric brand + dropped numbers
			},
			mangled: false,
		},
		{
			name: "half garbled (column-slip) → mangled, fall to LLM",
			items: []GatePassDutyItem{
				clean("Seagrams Blenders Pride Whisky"),
				clean("Royal Stag Whisky"),
				{BrandName: "43", SizeML: 0, Bottles: 0},
				{BrandName: "", SizeML: 0, Bottles: 0},
				{BrandName: "x", SizeML: 0, Bottles: 0},
			},
			mangled: true,
		},
		{
			name: "good brands but numbers all dropped → mangled",
			items: []GatePassDutyItem{
				{BrandName: "Royal Stag Whisky", SizeML: 0, Bottles: 0},
				{BrandName: "Magic Moments Vodka", SizeML: 0, Bottles: 0},
				{BrandName: "After Dark Whisky", SizeML: 0, Bottles: 0},
			},
			mangled: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, why := gpTablesLooksMangled(tc.items)
			if got != tc.mangled {
				t.Fatalf("gpTablesLooksMangled = %v (%q), want %v", got, why, tc.mangled)
			}
		})
	}
}
