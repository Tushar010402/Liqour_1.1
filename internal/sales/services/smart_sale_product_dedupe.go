package services

import (
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/matching"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ============================================================================
// v1.0.328 — Near-duplicate product dedupe for Smart Sale matching.
//
// Background
// ----------
// Two LIVE products with the same effective SKU at the same shop can coexist
// when their `name` and `size` strings differ just enough to escape unique
// constraints. Real incident (FM Tower 2026-05-28):
//   ab40e44c "8PM Gold Scotch Tetra - 180ml"        size "180ML"            stock 26
//   8d20df01 "8pm Gold Scotch Whisky Tetra 180ml"   size "180ml (Quarter)"  stock 94
// Both LIVE, both have stock rows. The matcher ranks 8d20df01 higher because
// the OCR text includes "Whisky", so the review screen shows opening 94 while
// the Inventory page (which dedupes at a different layer) correctly shows 26.
//
// Behaviour
// ---------
// Group `products` by (NormalizeForMatch(brand), ParseSizeML(size)). Any group
// with ≥2 entries is collapsed to ONE canonical entry. Canonical preference:
//   1) Has stock > 0 over zero-stock twin
//   2) Higher stock if both > 0
//   3) Canonical size string ("Xml (Quarter|Half|Full)") over raw "XML"
//   4) More recently updated
// Losers are removed from the returned products slice and their entries in
// shopStockMap are zeroed so downstream code paths that still reference their
// IDs cannot surface stale stock.
//
// Why pre-match dedupe instead of fixing data once
// ------------------------------------------------
// Data fixes scale O(N tenants × N shops × N SKUs). A pre-match pass scales
// O(1 code change) and self-heals every future occurrence of the same class.
// The data fix at /root/<merge-script> is still useful for cleaning historical
// rows but this guard ensures NEW duplicates don't break the next sale.
//
// Tradeoffs
// ---------
// • A legitimate two-product situation (e.g. PET pack vs Tetra pack of the
//   same brand at slightly different SKU names) at the same shop with same
//   size_ml would be collapsed — but those should have DIFFERENT names that
//   normalise to distinct keys ("8PM Gold PET" vs "8PM Gold Tetra" normalise
//   differently). Real twins (this bug class) have normalised-name collision.
//   The packaging/PET/Tetra disambiguation is already handled by the
//   v1.0.327 rate-tiebreaker — those products should have DIFFERENT rates.
// • If both twins have stock 0, we still collapse (canonical by name/recency)
//   so a non-zero stock that arrives via stock_setup approve later doesn't
//   land on the wrong twin.
// ============================================================================

// DedupeStats summarises one dedupe pass.
type DedupeStats struct {
	Removed  int      // count of duplicate products dropped from the candidate pool
	Groups   int      // count of collision groups encountered
	Examples []string // up to 3 human-readable group descriptions for the log
}

// dedupeNearDuplicateProductsForShop collapses near-duplicate products at the
// given shop. Returns the trimmed candidate slice + stats. shopStockMap is
// mutated: losers' product_id keys are reset to 0.
func dedupeNearDuplicateProductsForShop(
	products []models.Product,
	shopStockMap map[string]int,
	db *database.DB,
	shopID uuid.UUID,
) ([]models.Product, DedupeStats) {
	if len(products) < 2 {
		return products, DedupeStats{}
	}

	type key struct {
		normName string
		sizeML   int
	}
	byKey := map[key][]int{} // key → indices into products

	for i, p := range products {
		normName := matching.NormalizeForMatch(p.Name)
		if normName == "" {
			continue
		}
		sizeML := matching.ParseSizeML(p.Size)
		k := key{normName: normName, sizeML: sizeML}
		byKey[k] = append(byKey[k], i)
	}

	keep := make([]bool, len(products))
	for i := range keep {
		keep[i] = true
	}

	stats := DedupeStats{}
	for k, indices := range byKey {
		if len(indices) < 2 {
			continue
		}
		stats.Groups++
		bestIdx := indices[0]
		for _, j := range indices[1:] {
			if dedupePrefers(products[j], products[bestIdx], shopStockMap) {
				bestIdx = j
			}
		}
		var loserNames []string
		for _, j := range indices {
			if j == bestIdx {
				continue
			}
			keep[j] = false
			stats.Removed++
			shopStockMap[products[j].ID.String()] = 0
			loserNames = append(loserNames, fmt.Sprintf("%s (stock=%d, size=%q)",
				truncateNameForDedupeLog(products[j].Name, 40),
				shopStockMap[products[j].ID.String()],
				products[j].Size))
		}
		if len(stats.Examples) < 3 {
			stats.Examples = append(stats.Examples, fmt.Sprintf(
				"normalised=%q sizeML=%d → kept %s (stock=%d, size=%q); dropped %s",
				k.normName, k.sizeML,
				truncateNameForDedupeLog(products[bestIdx].Name, 40),
				shopStockMap[products[bestIdx].ID.String()],
				products[bestIdx].Size,
				strings.Join(loserNames, ", ")))
		}
	}

	if stats.Removed == 0 {
		return products, stats
	}

	out := make([]models.Product, 0, len(products)-stats.Removed)
	for i, p := range products {
		if keep[i] {
			out = append(out, p)
		}
	}
	return out, stats
}

// dedupePrefers returns true if candidate `a` is a better canonical pick than
// the current best `b`. Order of preference encoded in the description above.
func dedupePrefers(a, b models.Product, shopStockMap map[string]int) bool {
	sa := shopStockMap[a.ID.String()]
	sb := shopStockMap[b.ID.String()]
	// 1) Has stock > 0 beats zero
	if sa > 0 && sb <= 0 {
		return true
	}
	if sb > 0 && sa <= 0 {
		return false
	}
	// 2) Higher stock if both > 0
	if sa > 0 && sb > 0 && sa != sb {
		return sa > sb
	}
	// 3) Canonical size string preferred
	aCanon := isCanonicalSizeString(a.Size)
	bCanon := isCanonicalSizeString(b.Size)
	if aCanon != bCanon {
		return aCanon
	}
	// 4) More recently updated
	return a.UpdatedAt.After(b.UpdatedAt)
}

// isCanonicalSizeString matches the v1.0.297 normalisation: sizes formatted as
// "180ml (Quarter)", "375ml (Half)", "750ml (Full)".
func isCanonicalSizeString(s string) bool {
	s = strings.TrimSpace(strings.ToLower(s))
	return strings.Contains(s, "(quarter)") ||
		strings.Contains(s, "(half)") ||
		strings.Contains(s, "(full)") ||
		strings.Contains(s, "(nip)")
}

// truncateNameForDedupeLog clips a string to n chars + "..." for readable log lines.
func truncateNameForDedupeLog(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

// Avoid unused-import warnings in case future trimming removes a reference.
var _ = time.Now
