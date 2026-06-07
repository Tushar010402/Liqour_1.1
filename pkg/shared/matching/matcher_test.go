package matching

import (
	"strings"
	"testing"
)

// TestMatchProducts_ScoreClamped verifies that final scores never exceed 1.0,
// even when multiple boosts stack (strong text + size bonus + price match).
func TestMatchProducts_ScoreClamped(t *testing.T) {
	products := []Product{
		{
			ID:           "p1",
			Name:         "Royal Stag Double Dark Whisky - 750ML",
			BrandName:    "Royal Stag Double Dark Whisky",
			DisplayName:  "Royal Stag Double Dark",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 1000,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()
	cfg.EnablePriceMatching = true

	results := MatchProducts("Royal Stag Double Dark Whisky", 750, 1000, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected a match for exact product name")
	}
	for _, r := range results {
		if r.Score > 1.0 {
			t.Errorf("score clamp broken: got %.4f > 1.0 for product %s", r.Score, r.ProductName)
		}
		if r.Score < 0 {
			t.Errorf("score clamp broken: got %.4f < 0 for product %s", r.Score, r.ProductName)
		}
	}
}

// TestMatchProducts_ExciseNameHelps verifies that tenant products with only a
// cluttered or stale local name but a good excise name still match OCR text
// that reads the excise name. Simulates: local products haven't been cleaned up,
// but saas_brands has the authoritative name.
func TestMatchProducts_ExciseNameHelps(t *testing.T) {
	products := []Product{
		{
			ID:                "p1",
			Name:              "RS BS 750",                                   // garbage local name (hastily created)
			BrandName:         "",                                            // missing brand
			DisplayName:       "",                                            // missing display
			ExciseBrandName:   "Seagrams Royal Stag Barrel Select Premier Whisky", // authoritative
			ExciseDisplayName: "Royal Stag Barrel Select Premier",
			Size:              "750ML",
			SizeML:            750,
		},
		{
			ID:          "p2",
			Name:        "Absolut Vodka",
			BrandName:   "Absolut Vodka",
			DisplayName: "Absolut Vodka",
			Size:        "750ML",
			SizeML:      750,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()

	// OCR text "Royal Stag Barrel Select" should hit p1 via ExciseBrandName,
	// not p2 (Absolut). Without excise matching, p1 has only "RS BS 750" which
	// wouldn't score.
	results := MatchProducts("Royal Stag Barrel Select", 750, 0, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("excise-name matching failed: no results for 'Royal Stag Barrel Select'")
	}
	if results[0].ProductID != "p1" {
		t.Errorf("excise-name matching broken: got winner %s (score=%.2f), expected p1",
			results[0].ProductID, results[0].Score)
	}
	if results[0].Score < 0.60 {
		t.Errorf("excise-name match scored too low: %.2f (expected >= 0.60)", results[0].Score)
	}
}

// TestMatchProducts_DisplayNameHelps verifies that short display_name catches
// OCR text that would score low against a long full name.
func TestMatchProducts_DisplayNameHelps(t *testing.T) {
	products := []Product{
		{
			ID:          "p1",
			Name:        "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY - 750ML",
			BrandName:   "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY",
			DisplayName: "Iconiq White Deluxe", // short clean name
			Size:        "750ML",
			SizeML:      750,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()

	// OCR reads "Iconiq - white" — short and punctuated. Similarity vs long
	// full name is ~0.24, but vs display_name "Iconiq White Deluxe" is much better.
	results := MatchProducts("Iconiq - white", 750, 0, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("display-name matching failed: no results for 'Iconiq - white'")
	}
	if results[0].Score < 0.60 {
		t.Errorf("display-name match scored too low: %.2f (expected >= 0.60)", results[0].Score)
	}
}

// TestMatchProducts_SizeClampedBoost verifies the final clamp works even when
// price + size boosts both fire on a near-exact text match.
func TestMatchProducts_SizeClampedBoost(t *testing.T) {
	products := []Product{
		{
			ID:           "p1",
			Name:         "Blenders Pride Exclusive Premium Whisky",
			BrandName:    "Blenders Pride Exclusive Premium Whisky",
			DisplayName:  "Blenders Pride Exclusive Premium",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 1500,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()
	cfg.EnablePriceMatching = true
	// Exact price match + exact size + strong text = many stacking boosts
	results := MatchProducts("Blenders Pride Exclusive Premium Whisky", 750, 1500, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected a match")
	}
	if results[0].Score > 1.0 {
		t.Errorf("score clamp broken: got %.4f > 1.0", results[0].Score)
	}
	if results[0].Score < 0.9 {
		t.Errorf("near-exact match should score high: got %.4f", results[0].Score)
	}
}

// TestPrepareProducts_NoPanicOnEmptyExcise verifies that products without
// saas_brand_id (empty ExciseBrandName) are handled gracefully — this is
// critical because only ~30% of tenant products have saas_brand_id set.
func TestPrepareProducts_NoPanicOnEmptyExcise(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("PrepareProducts panicked with empty excise: %v", r)
		}
	}()
	products := []Product{
		{ID: "p1", Name: "Foo", BrandName: "Foo", Size: "750ML"},
		{ID: "p2", Name: "Bar", BrandName: "", DisplayName: "", ExciseBrandName: "", Size: "750ML"},
	}
	prepared := PrepareProducts(products)
	if len(prepared) != 2 {
		t.Fatalf("expected 2 prepared products, got %d", len(prepared))
	}
	// These fields must be non-nil (even if empty slices)
	if prepared[1].ExciseBrandTokens == nil && strings.Fields("") != nil {
		t.Errorf("ExciseBrandTokens should be empty slice not nil")
	}
}

// TestMatchProducts_MRPDisambiguates_8PMVariants — real-world scenario.
// Tenant has three 8 PM variants at 750ML with different MRPs:
//   - 8 PM Premium Black Superior Whisky — ₹680
//   - 8 PM Special Rare Whisky           — ₹470
//   - 8PM Gold Blend of Scotch ...       — ₹470
// OCR reads "8 PM Whisky" (ambiguous). With a known price ₹680, MRP should
// pick Premium Black despite "rare" / "gold" having similar name weight.
func TestMatchProducts_MRPDisambiguates_8PMVariants(t *testing.T) {
	products := []Product{
		{
			ID:           "premium_black",
			Name:         "8 PM Premium Black Superior Whisky - 750ML",
			BrandName:    "8 PM Premium Black Superior Whisky",
			DisplayName:  "8 PM Premium Black Superior Whisky",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 680,
		},
		{
			ID:           "special_rare",
			Name:         "8 PM Special Rare Whisky - 750ML",
			BrandName:    "8 PM Special Rare Whisky",
			DisplayName:  "8 PM Special Rare Whisky",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 470,
		},
		{
			ID:           "gold",
			Name:         "8PM Gold Blend of Scotch & Indian Grain Whisky - 750ML",
			BrandName:    "8PM Gold Blend of Scotch & Indian Grain Whisky",
			DisplayName:  "8PM Gold Blend of Scotch",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 470,
		},
	}
	prepared := PrepareProducts(products)

	// Case 1: generic OCR text + price=680 should pick Premium Black
	cfg := DefaultStockSetupConfig()
	cfg.EnablePriceMatching = true
	results := MatchProducts("8 PM Whisky", 750, 680, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected a match for '8 PM Whisky' @ ₹680")
	}
	if results[0].ProductID != "premium_black" {
		t.Errorf("MRP disambig broken (₹680): got %s, want premium_black. scores: %+v",
			results[0].ProductID, scoreSummary(results))
	}

	// Case 2: same OCR text + price=470 should pick one of the ₹470 variants (not Premium Black)
	results2 := MatchProducts("8 PM Whisky", 750, 470, prepared, cfg)
	if len(results2) == 0 {
		t.Fatal("expected a match for '8 PM Whisky' @ ₹470")
	}
	if results2[0].ProductID == "premium_black" {
		t.Errorf("MRP disambig broken (₹470): picked premium_black ₹680 despite asking for ₹470. scores: %+v",
			scoreSummary(results2))
	}
}

// TestMatchProducts_MRPPenalizesWildlyDifferentPrice — guards against matching
// when the name is OK-ish but price is way off (>₹100 difference).
func TestMatchProducts_MRPPenalizesWildlyDifferentPrice(t *testing.T) {
	products := []Product{
		{
			ID:           "cheap_match",
			Name:         "Royal Stag Superior Whisky",
			BrandName:    "Royal Stag Superior Whisky",
			DisplayName:  "Royal Stag Superior Whisky",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 800,
		},
		{
			ID:           "expensive_match",
			Name:         "Royal Stag Barrel Select Premier Whisky",
			BrandName:    "Royal Stag Barrel Select Premier Whisky",
			DisplayName:  "Royal Stag Barrel Select",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 1200,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()
	cfg.EnablePriceMatching = true

	// OCR "Royal Stag Superior Whisky" matches both on words but cheap one is exact name
	// AND exact price. Expensive one has partial name but wrong price → should lose hard.
	results := MatchProducts("Royal Stag Superior Whisky", 750, 800, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected a match")
	}
	if results[0].ProductID != "cheap_match" {
		t.Errorf("price match broken: got %s, want cheap_match. scores: %+v",
			results[0].ProductID, scoreSummary(results))
	}
}

// TestMatchProducts_MRPHelpsWhenNameWeak — covers the real case where OCR text
// is too short/noisy to decide on name alone but MRP decides.
func TestMatchProducts_MRPHelpsWhenNameWeak(t *testing.T) {
	products := []Product{
		{
			ID: "a", Name: "Magic Moments Superior Vodka", BrandName: "Magic Moments Superior Vodka",
			DisplayName: "Magic Moments Superior Vodka",
			Size:        "750ML", SizeML: 750, SellingPrice: 550,
		},
		{
			ID: "b", Name: "Magic Moments Remix Premium Vodka", BrandName: "Magic Moments Remix Premium Vodka",
			DisplayName: "Magic Moments Remix Premium",
			Size:        "750ML", SizeML: 750, SellingPrice: 900,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()
	cfg.EnablePriceMatching = true

	// OCR short: "Magic Moments Vodka" — both products match on name roughly equally.
	// Price ₹550 → should pick 'a' (exact MRP match).
	results := MatchProducts("Magic Moments Vodka", 750, 550, prepared, cfg)
	if len(results) == 0 || results[0].ProductID != "a" {
		t.Errorf("MRP as tiebreaker failed (₹550): got %+v, want winner 'a'", scoreSummary(results))
	}
	// Flip: price ₹900 → should pick 'b'.
	results = MatchProducts("Magic Moments Vodka", 750, 900, prepared, cfg)
	if len(results) == 0 || results[0].ProductID != "b" {
		t.Errorf("MRP as tiebreaker failed (₹900): got %+v, want winner 'b'", scoreSummary(results))
	}
}

// scoreSummary is a test helper that formats all MatchResults compactly.
func scoreSummary(results []MatchResult) string {
	var sb strings.Builder
	for i, r := range results {
		if i > 0 {
			sb.WriteString(", ")
		}
		sb.WriteString(r.ProductID)
		sb.WriteString("=")
		sb.WriteString(formatFloat(r.Score))
		if r.PriceMatch {
			sb.WriteString("(price)")
		}
	}
	return sb.String()
}

func formatFloat(f float64) string {
	// Avoid importing strconv in test helper
	return (&stringerFloat{f}).String()
}

type stringerFloat struct{ v float64 }

func (s *stringerFloat) String() string {
	if s.v < 0 {
		return "-" + (&stringerFloat{-s.v}).String()
	}
	intPart := int(s.v * 100)
	return itoa(intPart/100) + "." + twoDigit(intPart%100)
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	var buf [20]byte
	n := len(buf)
	for i > 0 {
		n--
		buf[n] = byte('0' + i%10)
		i /= 10
	}
	return string(buf[n:])
}

func twoDigit(i int) string {
	if i < 10 {
		return "0" + itoa(i)
	}
	return itoa(i)
}

// TestMatchProducts_ExciseBrandHit — verifies that OCR text hitting the excise
// brand name (via saas_brands) still wins even when the tenant's local product name
// is completely different. Tenant products with empty/garbage local names should be
// findable via their authoritative excise linkage.
func TestMatchProducts_ExciseBrandHit(t *testing.T) {
	products := []Product{
		{
			ID:                "p_correct",
			Name:              "Whisky 750",                // garbage local name
			BrandName:         "",
			DisplayName:       "",
			ExciseBrandName:   "Royal Stag Barrel Select Premier Whisky",
			ExciseDisplayName: "Royal Stag Barrel Select Premier",
			Size:              "750ML", SizeML: 750,
		},
		{
			ID:           "p_unrelated",
			Name:         "Absolut Vodka",
			BrandName:    "Absolut Vodka",
			DisplayName:  "Absolut Vodka",
			Size:         "750ML", SizeML: 750,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()

	results := MatchProducts("Royal Stag Barrel Select", 750, 0, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected a match via excise brand name")
	}
	if results[0].ProductID != "p_correct" {
		t.Errorf("excise matching broken: got %s, want p_correct. scores=%s",
			results[0].ProductID, scoreSummary(results))
	}
}

// TestMatchProducts_UniqueWordBoostSoftened — the unique-word boost was softened
// from 0.90 to 0.75 in the previous round. Verifies that a product sharing only
// a common-ish distinctive token doesn't dominate over one with stronger overall match.
func TestMatchProducts_UniqueWordBoostSoftened(t *testing.T) {
	products := []Product{
		{
			ID:          "strong",
			Name:        "Magic Moments Vodka",
			BrandName:   "Magic Moments Vodka",
			DisplayName: "Magic Moments Vodka",
			Size:        "750ML",
			SizeML:      750,
		},
		{
			ID:          "weak_unique",
			Name:        "Strange Product With Moments Only",
			BrandName:   "Strange Product With Moments Only",
			DisplayName: "Strange",
			Size:        "750ML",
			SizeML:      750,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultStockSetupConfig()
	results := MatchProducts("Magic Moments Vodka", 750, 0, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected matches")
	}
	if results[0].ProductID != "strong" {
		t.Errorf("expected 'strong' to win, got %s (score=%.2f)", results[0].ProductID, results[0].Score)
	}
}

// v1.0.327 — Rate-proximity tiebreaker tests.
//
// Real-world failure (FM Tower 180ml, 2026-05-28): "8 PM Gold Scotch Whisky PET"
// (₹130) and "8 PM Gold Scotch Whisky Tetra" (₹140) both bind to the same
// product_id because brand text normalizes identically. The PreferPriceMatch
// boost (PriceExactBoost + 0.05) was insufficient to flip the winner once
// shop/tenant-inventory bias enters the score. The new RateTiebreaker fires
// BEFORE PreferPriceMatch and decides on the magnitude of rate divergence.

func TestMatchProducts_RateTiebreaker_PicksRateMatchingSKUWhenTextTied(t *testing.T) {
	products := []Product{
		{
			ID:           "pet_130",
			Name:         "8 PM Gold Scotch Whisky PET - 180ML",
			BrandName:    "8 PM Gold Scotch Whisky",
			DisplayName:  "8 PM Gold Scotch",
			Size:         "180ML",
			SizeML:       180,
			SellingPrice: 130,
			CurrentStock: 50,
			IsActive:     true,
		},
		{
			ID:           "tetra_140",
			Name:         "8 PM Gold Scotch Whisky Tetra - 180ML",
			BrandName:    "8 PM Gold Scotch Whisky",
			DisplayName:  "8 PM Gold Scotch",
			Size:         "180ML",
			SizeML:       180,
			SellingPrice: 140,
			CurrentStock: 94,
			IsActive:     true,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultSaleConfig() // RateTiebreaker ON

	// OCR rate 130 → expect PET to win even with Tetra holding more stock.
	results := MatchProducts("8 PM Gold Scotch Whisky", 180, 130, prepared, cfg)
	if len(results) < 2 {
		t.Fatalf("expected both candidates, got %d", len(results))
	}
	if results[0].ProductID != "pet_130" {
		t.Errorf("rate tiebreaker broken @ ₹130: got %s, want pet_130. scores: %+v",
			results[0].ProductID, scoreSummary(results))
	}

	// OCR rate 140 → expect Tetra to win.
	results2 := MatchProducts("8 PM Gold Scotch Whisky", 180, 140, prepared, cfg)
	if len(results2) < 2 {
		t.Fatalf("expected both candidates @ ₹140, got %d", len(results2))
	}
	if results2[0].ProductID != "tetra_140" {
		t.Errorf("rate tiebreaker broken @ ₹140: got %s, want tetra_140. scores: %+v",
			results2[0].ProductID, scoreSummary(results2))
	}
}

func TestMatchProducts_RateTiebreaker_DisabledForStockSetup(t *testing.T) {
	cfg := DefaultStockSetupConfig()
	if cfg.RateTiebreakerEnabled {
		t.Error("Stock Setup config should NOT enable rate tiebreaker (it has its own v1.0.301 dup-product-id guard)")
	}
	pcfg := DefaultPurchaseConfig()
	if pcfg.RateTiebreakerEnabled {
		t.Error("Purchase config should NOT enable rate tiebreaker (cost prices on invoices are unreliable disambiguators)")
	}
	scfg := DefaultSaleConfig()
	if !scfg.RateTiebreakerEnabled {
		t.Error("Sale config MUST enable rate tiebreaker (this is the v1.0.327 fix)")
	}
}

func TestMatchProducts_RateTiebreaker_DoesNotOverrideOutsideEpsilon(t *testing.T) {
	// When text scores differ by MORE than RateTiebreakerTextEpsilon (0.06),
	// the higher-text-score candidate must still win even if its rate is worse.
	products := []Product{
		{
			ID:           "strong_text_wrong_rate",
			Name:         "Royal Stag Superior Whisky - 750ML",
			BrandName:    "Royal Stag Superior Whisky",
			DisplayName:  "Royal Stag Superior",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 800,
			CurrentStock: 10,
			IsActive:     true,
		},
		{
			ID:           "weak_text_right_rate",
			Name:         "Some Other Whisky 750ML",
			BrandName:    "Some Other Whisky",
			DisplayName:  "Some Other",
			Size:         "750ML",
			SizeML:       750,
			SellingPrice: 850,
			CurrentStock: 10,
			IsActive:     true,
		},
	}
	prepared := PrepareProducts(products)
	cfg := DefaultSaleConfig()

	// OCR text strongly matches "Royal Stag Superior" but rate 850 favours the other one.
	// Text-score gap should exceed ε_text → rate tiebreaker must NOT flip the winner.
	results := MatchProducts("Royal Stag Superior Whisky", 750, 850, prepared, cfg)
	if len(results) == 0 {
		t.Fatal("expected at least one match")
	}
	if results[0].ProductID != "strong_text_wrong_rate" {
		t.Errorf("rate tiebreaker over-reached: got %s, expected strong text match to win. scores: %+v",
			results[0].ProductID, scoreSummary(results))
	}
}
