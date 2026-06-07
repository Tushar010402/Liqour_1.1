// Package sizing provides canonical size parsing + bucketing for liquor SKUs.
//
// One source of truth for `products.size` shape so the Flutter chip strips
// (SizeRangeConstants in `core/constants/size_range_constants.dart`), the
// Smart Stock Setup picker, Brand Onboarding, AI Stock Setup and the manual
// Purchase Entry screen never disagree about what "180ML" means.
//
// The historical bug: `products.size` is a free-text column. Manual entry +
// OCR write paths landed garbage like "180ML1", "8375", "180 ML", "180ml" all
// in the same shop and the Flutter chip strips rendered every variant as its
// own chip. Even fully-correct rows collided after `DISTINCT UPPER(size)`.
//
// Fix: every write goes through `Canonicalize` which maps any input to one of
// the canonical labels + ml int. Garbage that can't be safely interpreted
// returns `ok=false` so handlers can reject at the API boundary.
package sizing

import (
	"regexp"
	"strconv"
	"strings"
)

// Canonical labels — must stay in lockstep with the Flutter
// SizeRangeConstants in `liquorpro_v2/lib/core/constants/size_range_constants.dart`.
const (
	NonBeer90ml   = "90ml"
	NonBeer180ml  = "180ml"
	NonBeer375ml  = "375ml"
	NonBeer750ml  = "750ml"
	NonBeer1L     = "1000ml"
	NonBeer1L5    = "1500ml"
	NonBeer2L     = "2000ml"
	Beer330ml     = "330ml"
	Beer500ml     = "500ml"
	Beer650ml     = "650ml"
	BeerKeg       = "5000ml"
)

// Range bucket. Mirrors the Flutter `SizeRange` exactly.
type Range struct {
	Label string // operator-facing label, e.g. "180ml (Quarter)"
	MinML int
	MaxML int
	Sort  int
	// MLCanonical is what gets written to products.size (e.g. "180ml").
	MLCanonical string
}

var nonBeerRanges = []Range{
	{Label: "90ml (Nip)", MinML: 0, MaxML: 100, Sort: 1, MLCanonical: "90ml"},
	{Label: "180ml (Quarter)", MinML: 101, MaxML: 250, Sort: 2, MLCanonical: "180ml"},
	{Label: "375ml (Half)", MinML: 251, MaxML: 400, Sort: 3, MLCanonical: "375ml"},
	{Label: "750ml (Full)", MinML: 401, MaxML: 999, Sort: 4, MLCanonical: "750ml"},
	{Label: "1L+ (Large)", MinML: 1000, MaxML: 999999, Sort: 5, MLCanonical: "1000ml"},
}

var beerRanges = []Range{
	{Label: "330ml & Below", MinML: 0, MaxML: 400, Sort: 1, MLCanonical: "330ml"},
	{Label: "500ml", MinML: 401, MaxML: 550, Sort: 2, MLCanonical: "500ml"},
	{Label: "650ml", MinML: 551, MaxML: 999, Sort: 3, MLCanonical: "650ml"},
	{Label: "Keg/Bulk", MinML: 1000, MaxML: 999999, Sort: 4, MLCanonical: "5000ml"},
}

// ExtractML pulls the millilitre integer out of any size string. Tolerates
// "180ML", "180 ml", "180ml1" (stray suffix), "180-ml", "0.180L", "1L", "1Ltr",
// "quarter", "nip", etc. Returns 0 when nothing recognisable could be parsed.
//
// Mirrors `SizeRangeConstants.extractMl` on the Flutter side and the legacy
// `normalizeSizeText` helper at `internal/inventory/services/smart_purchase_ocr.go`.
func ExtractML(raw string) int {
	s := strings.ToLower(strings.TrimSpace(raw))
	if s == "" {
		return 0
	}
	s = strings.ReplaceAll(s, " ", "")

	// Direct ML tokens (covers the common write-time labels).
	direct := map[string]int{
		"90ml": 90, "180ml": 180, "330ml": 330, "375ml": 375,
		"500ml": 500, "650ml": 650, "750ml": 750, "1000ml": 1000,
		"1500ml": 1500, "2000ml": 2000, "5000ml": 5000,
		"90": 90, "180": 180, "330": 330, "375": 375,
		"500": 500, "650": 650, "750": 750, "1000": 1000,
		"1l": 1000, "1ltr": 1000, "1litre": 1000, "1liter": 1000,
		"1.5l": 1500, "1.5ltr": 1500, "2l": 2000, "2ltr": 2000,
	}
	if v, ok := direct[s]; ok {
		return v
	}

	// Colloquial Indian terms.
	colloq := map[string]int{
		"nip": 90, "np": 90, "nips": 90,
		"quarter": 180, "qr": 180, "qrt": 180, "quart": 180,
		"half": 375, "hf": 375, "halfbottle": 375,
		"full": 750, "fl": 750, "bottle": 750, "btl": 750,
		"liter": 1000, "litre": 1000, "ltr": 1000,
		"keg": 5000, "bulk": 5000,
	}
	if v, ok := colloq[s]; ok {
		return v
	}

	// Fallback: first run of digits. Tolerates "180ML1", "180-ml", "ml180".
	re := regexp.MustCompile(`(\d+)`)
	if m := re.FindString(s); m != "" {
		if val, err := strconv.Atoi(m); err == nil && val > 0 && val <= 5000 {
			return val
		}
	}
	return 0
}

// Canonicalize normalises any size string for the given category bucket.
//   - canonicalSize: shape written to products.size (e.g. "180ml")
//   - rangeLabel:    operator-facing chip label (e.g. "180ml (Quarter)")
//   - ml:            integer millilitres
//   - ok:            false when the input can't be safely interpreted; the
//                    caller should reject the write with HTTP 400.
//
// Empty input returns ok=false. ml < minimum (0) or > 5000 returns ok=false.
//
// isBeer decides which range list to bucket against; default = non-beer.
func Canonicalize(raw string, isBeer bool) (canonicalSize, rangeLabel string, ml int, ok bool) {
	ml = ExtractML(raw)
	if ml <= 0 {
		return "", "", 0, false
	}
	ranges := nonBeerRanges
	if isBeer {
		ranges = beerRanges
	}
	for _, r := range ranges {
		if ml >= r.MinML && ml <= r.MaxML {
			return r.MLCanonical, r.Label, ml, true
		}
	}
	// Outside any bucket — shouldn't happen given the 0..999999 spread, but
	// keep the safety guard.
	return "", "", ml, false
}

// CanonicalSizeFor is a thin convenience wrapper that returns only the
// canonical size text (no range label, no ml). Returns "" when the input is
// unusable; callers usually want to fall back to Canonicalize for the full
// signal in that case.
func CanonicalSizeFor(raw string, isBeer bool) string {
	c, _, _, ok := Canonicalize(raw, isBeer)
	if !ok {
		return ""
	}
	return c
}

// CategoryIsBeer is a small helper for handlers that only have the category
// name available. Anything containing "beer" (case-insensitive) is treated as
// beer; everything else routes through the non-beer range list.
func CategoryIsBeer(categoryName string) bool {
	return strings.Contains(strings.ToLower(categoryName), "beer")
}

// AllNonBeerRanges / AllBeerRanges expose the canonical buckets for filter
// endpoints that need to enumerate every label.
func AllNonBeerRanges() []Range { return append([]Range(nil), nonBeerRanges...) }
func AllBeerRanges() []Range    { return append([]Range(nil), beerRanges...) }
