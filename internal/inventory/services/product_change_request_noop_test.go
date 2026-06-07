package services

import "testing"

// TestPCRMRPEqual locks the v1.0.352 no-op guard's comparison: a manual MRP
// "save" that doesn't move the price (at paise precision) must read as equal so
// no pending change request is ever queued. Real case: ₹350.00 → ₹350.00 junk
// rows in the Mahua Khera admin queue.
func TestPCRMRPEqual(t *testing.T) {
	cases := []struct {
		name string
		a, b float64
		want bool
	}{
		{"identical whole rupees", 350.00, 350.00, true},
		{"one paise apart", 350.00, 350.01, false},
		{"float round-trip noise rounds equal", 349.999, 350.00, true},
		{"genuine increase", 95.00, 110.00, false},
		{"both zero", 0, 0, true},
		{"half-paise below rounds equal", 330.004, 330.00, true},
		{"half-paise above rounds equal", 320.996, 321.00, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := pcrMRPEqual(c.a, c.b); got != c.want {
				t.Fatalf("pcrMRPEqual(%v, %v) = %v, want %v", c.a, c.b, got, c.want)
			}
		})
	}
}
