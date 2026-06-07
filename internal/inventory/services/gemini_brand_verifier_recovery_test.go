package services

import "testing"

// TestBrandReadsTokenEqual locks the v1.0.355 mismatched-candidate detector: it
// must treat trivial wording/case/spirit-noun differences as equal, but flag a
// genuinely different bottle (the Barrel Select vs Double Dark case) as distinct.
func TestBrandReadsTokenEqual(t *testing.T) {
	cases := []struct {
		name string
		a, b string
		want bool
	}{
		{"identical", "Royal Stag Barrel Select", "Royal Stag Barrel Select", true},
		{"case + spirit noun differs only", "Royal Stag Barrel Select Reserve Whisky", "royal stag barrel select reserve", true},
		{"genuinely different variant", "Seagram's Royal Stag Barrel Select Reserve", "Seagram's Royal Stag Double Dark Reserve Peaty", false},
		{"different brand entirely", "O.P.N Green Label Whisky", "Officer's Choice Blue Reserve Grain Whisky", false},
		{"empty falls back to string eq", "", "", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := brandReadsTokenEqual(c.a, c.b); got != c.want {
				t.Fatalf("brandReadsTokenEqual(%q,%q)=%v want %v", c.a, c.b, got, c.want)
			}
		})
	}
}
