//go:build helpers
// +build helpers

package services

// Tests for the AI-stock-setup matching helpers. Locks in the contract that
// the live AI matching pipeline depends on:
//   - extractBoldPortion: returns the catalog-flagged "key" identifier or ""
//   - flavorMismatchToken: static cross-family flavor/sub-variant guard
//   - buildBrandSiblingIndex: dynamic per-brand discriminator computation
//   - siblingDistinguisherMismatch: dynamic guard using the index above
//   - mrpProximityBonus: tiered MRP-distance scoring used by alts + master
//   - buildExtractionAudit: orphan + missing-master collection
//
// These functions are pure (no DB / no external calls) so the tests run fast
// and don't need any test fixtures or build tags.

import (
	"testing"
)

// ------------------------------------------------------------
// extractBoldPortion
// ------------------------------------------------------------

func TestExtractBoldPortion(t *testing.T) {
	intp := func(i int) *int { return &i }
	cases := []struct {
		name   string
		full   string
		start  *int
		length *int
		want   string
	}{
		{"nil bounds → empty", "100 Strokes Royal Whisky", nil, nil, ""},
		{"length zero → empty", "100 Strokes Royal Whisky", intp(0), intp(0), ""},
		{"start out of range → empty", "abc", intp(10), intp(2), ""},
		{"normal prefix", "100 Strokes Royal Whisky", intp(0), intp(11), "100 Strokes"},
		{"middle slice", "M2 Magic Moments Cranberry Vodka", intp(3), intp(13), "Magic Moments"},
		{"length overflows tail → clamp to end", "Old Monk", intp(4), intp(99), "Monk"},
		{"bold == full → empty (no extra signal)", "Royal Stag", intp(0), intp(10), ""},
		{"unicode handled by rune count", "₹100 Pipers", intp(0), intp(4), "₹100"},
	}
	for _, c := range cases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			got := extractBoldPortion(c.full, c.start, c.length)
			if got != c.want {
				t.Fatalf("extractBoldPortion(%q, %v, %v) = %q, want %q",
					c.full, c.start, c.length, got, c.want)
			}
		})
	}
}

// ------------------------------------------------------------
// flavorMismatchToken (static cross-family list)
// ------------------------------------------------------------

func TestFlavorMismatchToken_Cranberry(t *testing.T) {
	// Source: M2 Cranberry register row. AI guess: Magic Moments.
	tok, mismatch := flavorMismatchToken(
		"M2 Cranberry", "M2 Magic Moments Remix Cranberry Flavoured Vodka",
		"Magic Moments Vodka", "MAGIC MOMENTS VODKA", "Magic Moments Vodka",
	)
	if !mismatch {
		t.Fatalf("expected mismatch on Cranberry but got match")
	}
	if tok != "cranberry" {
		t.Fatalf("expected tok=cranberry, got %q", tok)
	}
}

func TestFlavorMismatchToken_AgreesWhenBothFlavored(t *testing.T) {
	_, mismatch := flavorMismatchToken(
		"M2 Cranberry", "M2 Magic Moments Cranberry Vodka",
		"M2 Magic Moments Cranberry", "M2 MAGIC MOMENTS REMIX CRANBERRY FLAVOURED VODKA", "M2 Magic Moments Cranberry",
	)
	if mismatch {
		t.Fatalf("expected no mismatch when both sides carry the flavor")
	}
}

func TestFlavorMismatchToken_RumVsVodka(t *testing.T) {
	// "spiced" is in the distinguisher list; appears in source only.
	tok, mismatch := flavorMismatchToken(
		"Old Monk Spiced Rum", "",
		"Old Monk Original Rum", "OLD MONK ORIGINAL RUM", "Old Monk Original",
	)
	if !mismatch {
		t.Fatalf("expected mismatch on 'spiced' distinguisher")
	}
	if tok != "spiced" {
		t.Fatalf("expected tok=spiced, got %q", tok)
	}
}

// ------------------------------------------------------------
// buildBrandSiblingIndex / siblingDistinguisherMismatch (dynamic)
// ------------------------------------------------------------

// Catalog with one M2 family (linked to a real saas_brand_id) and one
// "American Pride" family (no saas_brand_id — falls back to first 2 tokens).
// Verifies discriminator detection in both modes.
func newSampleCatalog() []dbProduct {
	return []dbProduct{
		// M2 family — saas_brand_id "mm-id"
		{ID: "1", Name: "M2 Magic Moments Vodka 750ML", DisplayName: "M2 Magic Moments Vodka", BrandName: "Magic Moments", SaasBrandID: "mm-id", Size: "750ML", MRP: 600},
		{ID: "2", Name: "M2 Magic Moments Cranberry Vodka 750ML", DisplayName: "M2 Magic Moments Cranberry", BrandName: "Magic Moments", SaasBrandID: "mm-id", Size: "750ML", MRP: 680},
		{ID: "3", Name: "M2 Magic Moments Green Apple Vodka 750ML", DisplayName: "M2 Magic Moments Green Apple", BrandName: "Magic Moments", SaasBrandID: "mm-id", Size: "750ML", MRP: 680},
		{ID: "4", Name: "M2 Magic Moments Jamun Vodka 750ML", DisplayName: "M2 Magic Moments Jamun", BrandName: "Magic Moments", SaasBrandID: "mm-id", Size: "750ML", MRP: 680},

		// American Pride family — no saas_brand_id; index falls back to "american pride" prefix
		{ID: "10", Name: "American Pride Whisky 750ML", DisplayName: "American Pride Whisky", BrandName: "American Pride", Size: "750ML", MRP: 640},
		{ID: "11", Name: "American Pride Black Whisky 750ML", DisplayName: "American Pride Black", BrandName: "American Pride", Size: "750ML", MRP: 720},
		{ID: "12", Name: "American Pride Premium Whisky 750ML", DisplayName: "American Pride Premium", BrandName: "American Pride", Size: "750ML", MRP: 800},

		// A solo brand — no siblings, so it shouldn't appear in the index.
		{ID: "20", Name: "Standalone Special 750ML", DisplayName: "Standalone Special", BrandName: "Standalone", Size: "750ML", MRP: 500},
	}
}

func TestBuildBrandSiblingIndex_DiscriminatorsForKnownFamilies(t *testing.T) {
	idx := buildBrandSiblingIndex(newSampleCatalog())

	// M2 family — "magic" / "moments" / "vodka" / "750ml" appear in ALL variants
	// so they shouldn't be discriminators. "cranberry", "green", "apple", "jamun"
	// appear in only one variant each → must be discriminators.
	mm, ok := idx["sb:mm-id"]
	if !ok {
		t.Fatalf("M2 family missing from index")
	}
	for _, shared := range []string{"magic", "moments", "vodka"} {
		if _, isDisc := mm[shared]; isDisc {
			t.Errorf("token %q is shared across all variants but flagged as discriminator", shared)
		}
	}
	for _, distinct := range []string{"cranberry", "green", "apple", "jamun"} {
		if _, isDisc := mm[distinct]; !isDisc {
			t.Errorf("token %q unique to one variant but missing from discriminators", distinct)
		}
	}

	// American Pride — falls back to fn:american pride
	ap, ok := idx["fn:american pride"]
	if !ok {
		t.Fatalf("American Pride family missing from index (fallback key)")
	}
	for _, shared := range []string{"american", "pride", "whisky"} {
		if _, isDisc := ap[shared]; isDisc {
			t.Errorf("token %q shared across all American Pride variants but flagged discriminator", shared)
		}
	}
	for _, distinct := range []string{"black", "premium"} {
		if _, isDisc := ap[distinct]; !isDisc {
			t.Errorf("token %q unique to one American Pride variant but missing from discriminators", distinct)
		}
	}
}

func TestBuildBrandSiblingIndex_SkipsSoloFamilies(t *testing.T) {
	idx := buildBrandSiblingIndex(newSampleCatalog())
	if _, present := idx["fn:standalone special"]; present {
		t.Fatalf("solo brand should not be in sibling index — has no discriminators")
	}
}

func TestSiblingDistinguisherMismatch_RejectsCranberryOntoPlainMM(t *testing.T) {
	idx := buildBrandSiblingIndex(newSampleCatalog())
	plainMM := dbProduct{ID: "1", Name: "M2 Magic Moments Vodka", DisplayName: "M2 Magic Moments Vodka", BrandName: "Magic Moments", SaasBrandID: "mm-id"}
	tok, mismatch := siblingDistinguisherMismatch("M2 Cranberry", "M2 Magic Moments Cranberry Vodka", &plainMM, idx)
	if !mismatch {
		t.Fatalf("expected dynamic guard to reject Cranberry → plain MM")
	}
	if tok != "cranberry" {
		t.Fatalf("expected tok=cranberry, got %q", tok)
	}
}

func TestSiblingDistinguisherMismatch_AcceptsCranberryOntoCranberry(t *testing.T) {
	idx := buildBrandSiblingIndex(newSampleCatalog())
	cran := dbProduct{ID: "2", Name: "M2 Magic Moments Cranberry Vodka", DisplayName: "M2 Magic Moments Cranberry", BrandName: "Magic Moments", SaasBrandID: "mm-id"}
	if _, mismatch := siblingDistinguisherMismatch("M2 Cranberry", "", &cran, idx); mismatch {
		t.Fatalf("expected dynamic guard to accept Cranberry onto Cranberry product")
	}
}

func TestSiblingDistinguisherMismatch_AmericanPrideBlackVsPlain(t *testing.T) {
	idx := buildBrandSiblingIndex(newSampleCatalog())
	plain := dbProduct{ID: "10", Name: "American Pride Whisky", DisplayName: "American Pride Whisky", BrandName: "American Pride"}
	tok, mismatch := siblingDistinguisherMismatch("American Pride Black", "American Pride Black Whisky", &plain, idx)
	if !mismatch {
		t.Fatalf("expected dynamic guard to reject Black → plain whisky")
	}
	if tok != "black" {
		t.Fatalf("expected tok=black, got %q", tok)
	}
}

func TestSiblingDistinguisherMismatch_NoIndexNoMismatch(t *testing.T) {
	plain := dbProduct{ID: "20", Name: "Standalone Special", DisplayName: "Standalone Special", BrandName: "Standalone"}
	if _, mismatch := siblingDistinguisherMismatch("Standalone Special", "", &plain, brandSiblingIndex{}); mismatch {
		t.Fatalf("empty index should never report a mismatch")
	}
}

// ------------------------------------------------------------
// mrpProximityBonus
// ------------------------------------------------------------

func TestMrpProximityBonus_Tiers(t *testing.T) {
	cases := []struct {
		name     string
		rate     float64
		mrp      float64
		want     float64
	}{
		{"both zero → no signal", 0, 0, 0},
		{"rate zero → no signal", 0, 770, 0},
		{"mrp zero → no signal", 770, 0, 0},
		{"exact match → +0.30", 770, 770, 0.30},
		{"within ±10 above → +0.30", 770, 778, 0.30},
		{"within ±10 below → +0.30", 770, 762, 0.30},
		{"within ±30 → +0.20", 770, 745, 0.20},
		{"within ±60 → +0.10", 770, 715, 0.10},
		{"between 60 and 150 → neutral", 770, 650, 0},
		{"beyond 150 → -0.15", 770, 500, -0.15},
		{"way beyond 150 → -0.15 (no further demote)", 770, 200, -0.15},
	}
	for _, c := range cases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			got := mrpProximityBonus(c.rate, c.mrp)
			if got != c.want {
				t.Fatalf("mrpProximityBonus(%v, %v) = %v, want %v", c.rate, c.mrp, got, c.want)
			}
		})
	}
}

// Verifies: a row whose register Rate is ₹770 will see the ₹770 candidate
// outscore the ₹800 candidate via mrpProximityBonus, even when both have
// identical fuzzy/text scores. Mirrors the user-visible ordering bug.
func TestMrpProximityBonus_OutranksFartherCandidate(t *testing.T) {
	rate := 770.0
	c1Score := 0.70 + mrpProximityBonus(rate, 770) // exact-rate candidate
	c2Score := 0.70 + mrpProximityBonus(rate, 800) // ₹30 off
	c3Score := 0.70 + mrpProximityBonus(rate, 1200) // far off
	if !(c1Score > c2Score && c2Score > c3Score) {
		t.Fatalf("expected ordering c1>c2>c3, got %.2f %.2f %.2f", c1Score, c2Score, c3Score)
	}
	if c3Score >= c1Score {
		t.Fatalf("far-off candidate should never outrank exact rate match")
	}
}

// ------------------------------------------------------------
// buildExtractionAudit
// ------------------------------------------------------------

func TestBuildExtractionAudit_FlagsOrphansAtRequestedSize(t *testing.T) {
	products := []dbProduct{
		// Linked, requested size — NOT orphan.
		{ID: "1", Name: "Magic Moments Vodka 750ML", DisplayName: "Magic Moments Vodka", SaasBrandID: "sb-1", Size: "750ML"},
		// NULL saas_brand_id at requested size — orphan.
		{ID: "2", Name: "Old Local Whisky 750ML", DisplayName: "Old Local Whisky", SaasBrandID: "", Size: "750ML"},
		// NULL saas_brand_id at OTHER size — should be SKIPPED (out of scope).
		{ID: "3", Name: "Old Local Whisky 180ML", DisplayName: "Old Local Whisky", SaasBrandID: "", Size: "180ML"},
	}
	audit := buildExtractionAudit(products, nil, nil, 750)
	if audit == nil {
		t.Fatalf("expected non-nil audit when an orphan exists at the requested size")
	}
	if len(audit.OrphanProducts) != 1 || audit.OrphanProducts[0].ProductID != "2" {
		t.Fatalf("expected exactly the 750ML orphan (id=2), got %+v", audit.OrphanProducts)
	}
}

func TestBuildExtractionAudit_FlagsAutoCreateWithNoMasterMatch(t *testing.T) {
	items := []SmartStockSetupExtractedItem{
		// auto_create with master suggestions — NOT a "missing master" candidate.
		{Status: "auto_create", BrandName: "Has Suggestions", MasterBrandSuggestions: []MasterBrandSuggestion{{BrandName: "Foo"}}},
		// auto_create with NO suggestions — counts as truly missing from master.
		{Status: "auto_create", BrandName: "Genuinely Unknown Brand"},
		// matched row — should never appear in missing list.
		{Status: "matched", BrandName: "Already Matched"},
		// duplicate of "Genuinely Unknown Brand" with different casing — should dedupe.
		{Status: "auto_create", BrandName: "GENUINELY unknown BRAND"},
	}
	audit := buildExtractionAudit(nil, items, nil, 0)
	if audit == nil {
		t.Fatalf("expected non-nil audit when a missing-master brand exists")
	}
	if len(audit.MissingMasterBrands) != 1 || audit.MissingMasterBrands[0] != "Genuinely Unknown Brand" {
		t.Fatalf("expected single deduped 'Genuinely Unknown Brand', got %+v", audit.MissingMasterBrands)
	}
}

func TestBuildExtractionAudit_NilWhenNothingToReport(t *testing.T) {
	products := []dbProduct{
		{ID: "1", SaasBrandID: "sb-1", Size: "750ML"},
	}
	items := []SmartStockSetupExtractedItem{
		{Status: "matched", BrandName: "All Good"},
	}
	if audit := buildExtractionAudit(products, items, nil, 750); audit != nil {
		t.Fatalf("expected nil audit when no orphans / no missing brands, got %+v", audit)
	}
}

// ------------------------------------------------------------
// hasLabelColorConflict — blocks Red↔Blue↔Black↔Blonde↔Gold swaps within a
// brand family while leaving unrelated products and mid-phrase color words
// alone. Regression cover for the 2026-04-20 job where AI emitted
// "JW Blue Label" and the matcher happily returned "JW Red Label" at 0.9
// confidence (rate ₹2200 vs catalog MRP ₹1810).
// ------------------------------------------------------------

func TestHasLabelColorConflict(t *testing.T) {
	cases := []struct {
		name string
		src  string
		cand string
		want bool
	}{
		// The failure this is built to stop:
		{"JW blue vs red (shared root walker)", "Johnnie Walker Blue Label", "Johnnie Walker Red Label Blended", true},
		{"JW red vs black", "Johnnie Walker Red Label", "Johnnie Walker Black Label Blended Scotch Whisky 12 Y", true},
		{"JW blonde vs black", "Johnnie Walker Blonde Whisky", "Johnnie Walker Black Label", true},
		{"JW black vs double black", "Johnnie Walker Black Label", "Johnnie Walker Double Black Blended Scotch", true},
		{"Dewars white vs gold", "Dewars White Label", "Dewars Gold Label Reserve", true},
		{"same color both sides", "Johnnie Walker Red Label", "Johnnie Walker Red Label Blended", false},

		// Must NOT false-positive across unrelated families or on mid-phrase colors:
		{"Dewars white vs JW red — different families", "Dewars White Label", "Johnnie Walker Red Label Blended", false},
		{"Royal Green Reserve (green excluded)", "Royal Green Reserve Blended", "Royal Green Reserve Blended Whisky", false},
		{"Green product vs Black product with no shared root", "Royal Green Reserve Blended Whisky", "8 PM Premium Black Superior Whisky", false},
		{"Empty inputs", "", "Johnnie Walker Red Label", false},
		{"No color in either", "Imperial Blue Dual Cask Smooth", "Imperial Blue Dual Cask Smooth Whisky", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := hasLabelColorConflict(tc.src, tc.cand); got != tc.want {
				t.Errorf("hasLabelColorConflict(%q, %q) = %v, want %v", tc.src, tc.cand, got, tc.want)
			}
		})
	}
}

func TestLabelColorIn_DoubleBlackCompound(t *testing.T) {
	// "double black" is a distinct JW SKU from plain "black label" — must be
	// tokenised as the compound so the conflict check treats them as different.
	if c := labelColorIn("Johnnie Walker Double Black"); c != "double_black" {
		t.Errorf("expected double_black compound, got %q", c)
	}
	if c := labelColorIn("Johnnie Walker Black Label"); c != "black" {
		t.Errorf("expected plain black, got %q", c)
	}
}
