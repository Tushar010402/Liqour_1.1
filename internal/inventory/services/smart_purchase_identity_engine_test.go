package services

import "testing"

// Robustness lock for the image→identity engine, built from the REAL production
// variant pairs that caused (or risked) mislinkage. The core safety mechanism is
// variantConflict (threshold-free: two names conflict when each carries a
// distinctive word the other lacks). This is what makes the engine "not do it
// again": a different variant of the same family is never reused (WS-B) and a
// product linked to the wrong-variant master is always flagged (WS-D) — even for
// one-word-apart variants that a plain jaccard floor lets through.
//
// Sources: v1.0.366/367 — Rockford Reserve Premium↔Fine & Rare↔Classic Finest,
// M2 Remix Green Apple↔Superior, 100 Pipers Exquisite↔Deluxe, ICONIQ White
// Finest↔Deluxe, White & Blue Rare Oak↔Supreme, Johnnie Walker Blonde↔Aged 18.
func TestIdentityEngine_VariantConflict(t *testing.T) {
	// DISTINCT variants of the same family — MUST conflict (never reuse, always flag).
	conflict := []struct{ family, a, b string }{
		{"Rockford", "THE ROCKFORD RESERVE PREMIUM WHISKY", "THE ROCKFORD RESERVE FINE & RARE WHISKY"},
		{"Rockford", "THE ROCKFORD RESERVE PREMIUM WHISKY", "ROCKFORD CLASSIC FINEST BLENDED WHISKY"},
		{"M2 Remix", "M2 MAGIC MOMENTS REMIX GREEN APPLE FLAVOURED VODKA", "M2 MAGIC MOMENTS REMIX SUPERIOR VODKA"},
		{"100 Pipers", "SEAGRAM'S 100 PIPERS EXQUISITE BLENDED WHISKY", "SEAGRAM'S 100 PIPERS DELUXE BLENDED WHISKY"},
		{"ICONIQ White", "ICONIQ WHITE FINEST INTERNATIONAL GRAIN WHISKY", "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY"},
		{"White & Blue", "WHITE & BLUE RARE OAK WHISKY", "WHITE & BLUE SUPREME WHISKY"},
		{"Johnnie Walker", "JOHNNIE WALKER BLONDE BLENDED SCOTCH WHISKY", "JOHNNIE WALKER AGED 18 YEARS BLENDED SCOTCH WHISKY"},
		{"cross-brand", "THE ROCKFORD RESERVE PREMIUM WHISKY", "SEAGRAM'S ROYAL STAG SUPERIOR WHISKY"},
	}
	for _, p := range conflict {
		if !variantConflict(p.a, p.b) {
			t.Errorf("[%s] expected variantConflict TRUE for %q vs %q", p.family, p.a, p.b)
		}
	}

	// SAME variant (incl. case / punctuation / category-word differences) — MUST
	// NOT conflict (reuse + treat as consistent link).
	same := [][2]string{
		{"THE ROCKFORD RESERVE PREMIUM WHISKY", "the rockford reserve premium whisky"},
		{"M2 Magic Moments Remix Green Apple Vodka", "M2 MAGIC MOMENTS REMIX GREEN APPLE FLAVOURED VODKA"},
		{"White & Blue Rare Oak Whisky", "WHITE & BLUE RARE OAK WHISKY"},
		{"Johnnie Walker Blonde Blended Scotch", "JOHNNIE WALKER BLONDE BLENDED SCOTCH WHISKY"},
		{"Seagrams Blenders Pride", "SEAGRAM'S BLENDERS PRIDE"},
	}
	for _, p := range same {
		if variantConflict(p[0], p[1]) {
			t.Errorf("expected variantConflict FALSE for %q vs %q", p[0], p[1])
		}
	}
}

// TestIdentityEngine_ReuseFloorHolds locks the WS-B overlap floor: the same
// variant reaches it (reuse) while distinct same-family variants stay strictly
// below it (so even without the conflict guard the floor alone is safe for the
// pairs whose distinctive words are dropped by gpStopwords, e.g. "premium").
func TestIdentityEngine_ReuseFloorHolds(t *testing.T) {
	j := func(a, b string) float64 { return jaccardTokens(gpTokenSet(lower(a)), gpTokenSet(lower(b))) }
	if v := j("THE ROCKFORD RESERVE PREMIUM WHISKY", "THE ROCKFORD RESERVE PREMIUM WHISKY"); v < reuseNameJaccardFloor {
		t.Errorf("same variant must reach reuse floor: %.2f", v)
	}
	// Rockford Premium vs Classic Finest — clearly below the floor.
	if v := j("THE ROCKFORD RESERVE PREMIUM WHISKY", "ROCKFORD CLASSIC FINEST BLENDED WHISKY"); v >= reuseNameJaccardFloor {
		t.Errorf("distinct variant must stay below reuse floor: %.2f", v)
	}
}

// lower lowercases ASCII without importing strings just for the test.
func lower(s string) string {
	b := []byte(s)
	for i := range b {
		if b[i] >= 'A' && b[i] <= 'Z' {
			b[i] += 'a' - 'A'
		}
	}
	return string(b)
}
