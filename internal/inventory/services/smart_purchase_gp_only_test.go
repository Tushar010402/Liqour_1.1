package services

import (
	"context"
	"testing"

	sharedinv "github.com/liquorpro/go-backend/pkg/shared/inventory"
)

// v1.0.359 — owner rule: NAME + quantity/pieces from the GATE PASS only; the
// bill gives only cost/vendor/TCS. These tests lock the behavior and the dark
// default so real jobs stay unchanged until the global switch is flipped.

func TestGPOnlyNamesEnabled_Gating(t *testing.T) {
	const testUser = "11111111-1111-1111-1111-111111111111"
	cases := []struct {
		name      string
		global    string // SMART_PURCHASE_GP_ONLY_NAMES
		testUser  string // SMART_PURCHASE_TEST_USER_ID
		jobUser   string
		wantGPOnly bool
	}{
		{"dark default (real user)", "", "", "someone", false},
		{"global off explicit", "0", "", "someone", false},
		{"global on → all jobs", "1", "", "someone", true},
		{"global true → all jobs", "true", "", "someone", true},
		{"test user matches → on for that job", "", testUser, testUser, true},
		{"test user set, different job user → off", "", testUser, "other-user", false},
		{"test user match is case-insensitive", "", testUser, "11111111-1111-1111-1111-111111111111", true},
		{"global off but test user matches → on", "0", testUser, testUser, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("SMART_PURCHASE_GP_ONLY_NAMES", c.global)
			t.Setenv("SMART_PURCHASE_TEST_USER_ID", c.testUser)
			if got := gpOnlyNamesEnabled(c.jobUser); got != c.wantGPOnly {
				t.Fatalf("gpOnlyNamesEnabled(%q) = %v, want %v", c.jobUser, got, c.wantGPOnly)
			}
		})
	}
}

func TestResolveGPOnlyName_Precedence(t *testing.T) {
	cases := []struct {
		name           string
		gatePassBrand  string
		canonicalBrand string
		canonicalSrc   string
		matchedDisplay string
		wantName       string
		wantUnread     bool
	}{
		{"gate-pass brand wins", "Seagrams Royal Stag Superior Whisky", "x", "gemini", "y", "Seagrams Royal Stag Superior Whisky", false},
		{"GP canonical when source=gate_pass", "", "Magic Moments Jamun Vodka", "gate_pass", "y", "Magic Moments Jamun Vodka", false},
		{"canonical from gemini is NOT used", "", "Some Gemini Read", "gemini", "Matched Product Name", "Matched Product Name", false},
		{"matched product name when no GP", "", "", "", "Royal Challenge Select Premium Whisky", "Royal Challenge Select Premium Whisky", false},
		{"nothing read → unread", "", "", "", "", "Unread — needs review", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, unread := resolveGPOnlyName(c.gatePassBrand, c.canonicalBrand, c.canonicalSrc, c.matchedDisplay)
			if got != c.wantName || unread != c.wantUnread {
				t.Fatalf("resolveGPOnlyName = (%q,%v), want (%q,%v)", got, unread, c.wantName, c.wantUnread)
			}
		})
	}
}

func TestMergeGPEnsemble_LLMSpineTextractNumbers(t *testing.T) {
	// Textract: correct numbers but SCRAMBLED names AND a different row count/order
	// (the real failure: Textract smears + miscounts). Serial often 0.
	textract := []GatePassDutyItem{
		{RowNumber: 0, BrandName: "INTERNATIONAL GRAIN WHISKY After Dark", SizeML: 375, Cases: 2, Bottles: 48},
		{RowNumber: 0, BrandName: "fragment row", SizeML: 0, Cases: 0, Bottles: 0}, // smear/noise row
		{RowNumber: 0, BrandName: "Blue Rare Grain Whisky All Seasons", SizeML: 180, Cases: 3, Bottles: 144},
		{RowNumber: 0, BrandName: "WHISKY M2 Magic", SizeML: 180, Cases: 2, Bottles: 96},
	}
	// LLM spine: clean names + reliable serials + good numbers, one row per product.
	llm := []GatePassDutyItem{
		{RowNumber: 1, BrandName: "After Dark Blue Rare Grain Whisky", SizeML: 375, Cases: 2, Bottles: 48},
		{RowNumber: 2, BrandName: "All Seasons Rare Reserve Whisky", SizeML: 180, Cases: 3, Bottles: 144},
		{RowNumber: 3, BrandName: "M2 Magic Moments Remix Superior Green Apple Vodka", SizeML: 180, Cases: 2, Bottles: 96},
	}
	out := mergeGPEnsemble(textract, llm)
	if len(out) != 3 {
		t.Fatalf("ensemble must yield one row per LLM spine row; got %d want 3", len(out))
	}
	wantNames := []string{
		"After Dark Blue Rare Grain Whisky",
		"All Seasons Rare Reserve Whisky",
		"M2 Magic Moments Remix Superior Green Apple Vodka",
	}
	for i, w := range wantNames {
		if out[i].BrandName != w {
			t.Errorf("row %d brand = %q, want %q (LLM name, never Textract's smear)", i, out[i].BrandName, w)
		}
	}
	// Numbers must reflect Textract's (aligned despite the noise row + serial=0).
	if out[0].SizeML != 375 || out[0].Bottles != 48 {
		t.Errorf("row0 numbers = %dml/%dbtl, want 375/48 (Textract aligned)", out[0].SizeML, out[0].Bottles)
	}
	if out[2].SizeML != 180 || out[2].Bottles != 96 {
		t.Errorf("row2 numbers = %dml/%dbtl, want 180/96", out[2].SizeML, out[2].Bottles)
	}
}

func TestMergeGPEnsemble_LLMOnlyRowKeepsLLMNumbers(t *testing.T) {
	// An LLM row Textract never read (no match) keeps the LLM's own numbers — not dropped.
	textract := []GatePassDutyItem{{RowNumber: 0, BrandName: "x", SizeML: 750, Cases: 1, Bottles: 12}}
	llm := []GatePassDutyItem{
		{RowNumber: 1, BrandName: "Black Dog Centenary", SizeML: 750, Cases: 1, Bottles: 12},
		{RowNumber: 2, BrandName: "Iconiq White Deluxe", SizeML: 180, Cases: 1, Bottles: 48},
	}
	out := mergeGPEnsemble(textract, llm)
	if len(out) != 2 {
		t.Fatalf("LLM-only row must survive; got %d want 2", len(out))
	}
	if out[1].BrandName != "Iconiq White Deluxe" || out[1].Bottles != 48 || out[1].SizeML != 180 {
		t.Errorf("LLM-only row wrong: %+v", out[1])
	}
}

func TestClassifyDuplicateBindings_DistinctSerialsKept(t *testing.T) {
	pid := "p-after-dark"
	// Same product+brand on DISTINCT serials = two legitimate dispatch lines → keep both.
	items := []SmartPurchaseExtractedItem{
		{RowNumber: 2, BrandName: "After Dark Blue Rare Grain Whisky", ProductID: &pid, MatchConfidence: 0.9},
		{RowNumber: 11, BrandName: "After Dark Blue Rare Grain Whisky", ProductID: &pid, MatchConfidence: 0.9},
	}
	unbind, drop := classifyDuplicateBindings(items)
	if len(drop) != 0 {
		t.Errorf("distinct serials (2,11) of same product must NOT be dropped; drop=%v", drop)
	}
	if len(unbind) != 0 {
		t.Errorf("identical brand must not unbind either; unbind=%v", unbind)
	}
	// SAME serial = a genuine double-extraction of one physical line → drop one.
	items2 := []SmartPurchaseExtractedItem{
		{RowNumber: 9, BrandName: "M2 Jamun Spicymint", ProductID: &pid, MatchConfidence: 0.9},
		{RowNumber: 9, BrandName: "M2 Jamun Spicy Mint", ProductID: &pid, MatchConfidence: 0.8},
	}
	if _, drop2 := classifyDuplicateBindings(items2); len(drop2) != 1 {
		t.Errorf("same-serial double-read must drop exactly 1; drop=%v", drop2)
	}
}

func TestGPHybridNamesEnabled_Gating(t *testing.T) {
	const tu = "22222222-2222-2222-2222-222222222222"
	t.Setenv("SMART_PURCHASE_GP_HYBRID_NAMES", "")
	t.Setenv("SMART_PURCHASE_TEST_USER_ID", tu)
	if !gpHybridNamesEnabled(tu) {
		t.Error("test user should force hybrid on")
	}
	if gpHybridNamesEnabled("someone-else") {
		t.Error("non-test user with global off should be off")
	}
	t.Setenv("SMART_PURCHASE_TEST_USER_ID", "")
	t.Setenv("SMART_PURCHASE_GP_HYBRID_NAMES", "1")
	if !gpHybridNamesEnabled("anybody") {
		t.Error("global on should enable for all")
	}
}

func TestShopAliasGuardEnabled_Gating(t *testing.T) {
	const tu = "33333333-3333-3333-3333-333333333333"
	t.Setenv("SMART_PURCHASE_SHOP_ALIAS_GUARD", "")
	t.Setenv("SMART_PURCHASE_TEST_USER_ID", tu)
	if !shopAliasGuardEnabled(tu) {
		t.Error("test user should force shop-isolation on")
	}
	if shopAliasGuardEnabled("someone-else") {
		t.Error("non-test user with global off should be off")
	}
	t.Setenv("SMART_PURCHASE_TEST_USER_ID", "")
	t.Setenv("SMART_PURCHASE_SHOP_ALIAS_GUARD", "1")
	if !shopAliasGuardEnabled("anybody") {
		t.Error("global on should enable for all")
	}
}

func TestShopIsolationCtx_PrefersStampThenGlobal(t *testing.T) {
	t.Setenv("SMART_PURCHASE_SHOP_ALIAS_GUARD", "")
	// No stamp, global off → off.
	if shopIsolationEnabled(context.Background()) {
		t.Error("unstamped ctx with global off must be off")
	}
	// Stamp true wins regardless of global.
	if !shopIsolationEnabled(withShopIsolation(context.Background(), true)) {
		t.Error("ctx stamped true must be on")
	}
	// Stamp false wins even when global on (per-job opt-out).
	t.Setenv("SMART_PURCHASE_SHOP_ALIAS_GUARD", "1")
	if shopIsolationEnabled(withShopIsolation(context.Background(), false)) {
		t.Error("ctx stamped false must override global on")
	}
	// Unstamped falls back to global.
	if !shopIsolationEnabled(context.Background()) {
		t.Error("unstamped ctx must fall back to global on")
	}
}

func TestIdentityEngineEnabled_Gating(t *testing.T) {
	const tu = "44444444-4444-4444-4444-444444444444"
	t.Setenv("SMART_PURCHASE_IDENTITY_ENGINE", "")
	t.Setenv("SMART_PURCHASE_TEST_USER_ID", tu)
	if !identityEngineEnabled(tu) {
		t.Error("test user should force identity engine on")
	}
	if identityEngineEnabled("someone-else") {
		t.Error("non-test user with global off should be off")
	}
	t.Setenv("SMART_PURCHASE_TEST_USER_ID", "")
	t.Setenv("SMART_PURCHASE_IDENTITY_ENGINE", "1")
	if !identityEngineEnabled("anybody") {
		t.Error("global on should enable for all")
	}
}

// TestWSB_ReuseJaccardVariantSafety is the safety invariant for the WS-B
// name+size reuse fallback: the 0.60 floor must REUSE the same variant but never
// collapse DISTINCT variants of the same brand family. Rockford Reserve Premium
// must match itself (and the mislinked product carrying that name) yet stay
// clearly below the floor vs Classic Finest / Fine & Rare.
func TestWSB_ReuseJaccardVariantSafety(t *testing.T) {
	gp := gpTokenSet("the rockford reserve premium whisky")
	same := jaccardTokens(gp, gpTokenSet("the rockford reserve premium whisky"))
	if same < 0.60 {
		t.Errorf("same variant must reuse: jaccard=%.2f, want ≥0.60", same)
	}
	classic := jaccardTokens(gp, gpTokenSet("rockford classic finest blended whisky"))
	if classic >= 0.60 {
		t.Errorf("Classic Finest must NOT reuse Premium: jaccard=%.2f, want <0.60", classic)
	}
	fineRare := jaccardTokens(gp, gpTokenSet("the rockford reserve fine & rare whisky"))
	if fineRare >= 0.60 {
		t.Errorf("Fine & Rare must NOT reuse Premium: jaccard=%.2f, want <0.60", fineRare)
	}
}

func TestPackTable_OwnerConfirmedValues(t *testing.T) {
	// Owner-confirmed: 180=48, 375=24, 750=12, 90=96, 60=150, 1000=12.
	want := map[int]int{60: 150, 90: 96, 180: 48, 375: 24, 750: 12, 1000: 12}
	for size, bpc := range want {
		if got := StandardCaseSizes[size]; got != bpc {
			t.Errorf("StandardCaseSizes[%d] = %d, want %d", size, got, bpc)
		}
		if got := GetBottlesPerCase(size); got != bpc {
			t.Errorf("GetBottlesPerCase(%d) = %d, want %d", size, got, bpc)
		}
		if got, ok := sharedinv.PackSize(size); !ok || got != bpc {
			t.Errorf("sharedinv.PackSize(%d) = (%d,%v), want (%d,true)", size, got, ok, bpc)
		}
	}
	// Regression: 1000ml must NOT be the old 9.
	if StandardCaseSizes[1000] == 9 {
		t.Errorf("StandardCaseSizes[1000] is still 9 — must be 12")
	}
}

// TestValidateBillVsGatePass_GPOnly_24vs48 reproduces the Rockford #24 screenshot:
// bill says 24 bottles (math ✗ for 180ml), GP says 48 (math ✓). Under GP-only the
// bill quantity is ignored: NO block, NO bill pack_size_violation, resolution=gate_pass.
func TestValidateBillVsGatePass_GPOnly_24vs48(t *testing.T) {
	svc := &SmartPurchaseService{}
	bill := &ExtractedPurchaseItem{
		Brand:           "Rockford Reserve Premium Whisky",
		SizeText:        "180ML",
		SizeML:          180,
		QuantityRaw:     1, // 1 "case" per the bill
		QuantityUnit:    "cases",
		QuantityBottles: 24, // bill's wrong 24
	}
	gp := &GatePassDutyItem{
		BrandName: "Rockford Reserve Premium Whisky",
		Size:      "180ML",
		SizeML:    180,
		Cases:     1,
		Bottles:   48, // GP's correct 48
	}

	// GP-only: gate pass wins silently.
	flags, resolution := svc.validateBillVsGatePass(bill, gp, true)
	if resolution != "gate_pass" {
		t.Fatalf("GP-only resolution = %q, want gate_pass", resolution)
	}
	for _, f := range flags {
		if f.Severity == "block" {
			t.Errorf("GP-only must never emit a block flag, got %+v", f)
		}
		if f.Kind == "pack_size_violation" && f.BillValue != "" {
			t.Errorf("GP-only must suppress the BILL pack_size_violation, got %+v", f)
		}
		if f.Kind == "quantity_disputed" {
			t.Errorf("GP-only must never dispute quantity, got %+v", f)
		}
	}

	// Dark path (gpOnly=false): the old behavior still disputes (24 vs 48, Δ24 > 1).
	darkFlags, darkRes := svc.validateBillVsGatePass(bill, gp, false)
	if darkRes == "gate_pass" && len(darkFlags) == 0 {
		t.Errorf("dark path should still surface the bill/GP conflict (locking unchanged real-job behavior)")
	}
}
