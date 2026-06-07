package services

import (
	"os"
	"testing"
)

// TestParseVerifyResponseDebias locks Phase 1 (read-is-truth): when
// VERIFY_READ_IS_TRUTH is on, a matched candidate that DISAGREES (token-distinct)
// with Gemini's own free-text read must NOT overwrite the canonical — the image
// read is the truth. This is what stops the SAME bottle from reading differently
// per shop (the candidate list is seeded from the per-shop product name).
func TestParseVerifyResponseDebias(t *testing.T) {
	// Make sure neither flag leaks in from the environment between subtests.
	os.Unsetenv("VERIFY_READ_IS_TRUTH")
	os.Unsetenv("VERIFY_DEBIAS_READ")

	// Gemini clearly read "Royal Stag Barrel Select" but was matched (via the
	// shop's name-seeded candidate list) to the "Double Dark" candidate.
	raw := `{"brand":"Seagram's Royal Stag Barrel Select Reserve Whisky","matched_candidate_id":"cand-dd","confidence":0.9}`
	cands := []MasterBrandCandidate{
		{ID: "cand-dd", Name: "Seagram's Royal Stag Double Dark Reserve Peaty"},
	}

	t.Run("read-is-truth on keeps the image read", func(t *testing.T) {
		t.Setenv("VERIFY_READ_IS_TRUTH", "1")
		got := parseVerifyResponse(raw, "Double Dark", "750ml", cands, "front")
		if got.CanonicalName != "Seagram's Royal Stag Barrel Select Reserve Whisky" {
			t.Fatalf("read-is-truth on: canonical=%q, want the free-text Barrel Select read", got.CanonicalName)
		}
	})

	t.Run("legacy VERIFY_DEBIAS_READ alias still enables it", func(t *testing.T) {
		t.Setenv("VERIFY_DEBIAS_READ", "1")
		got := parseVerifyResponse(raw, "Double Dark", "750ml", cands, "front")
		if got.CanonicalName != "Seagram's Royal Stag Barrel Select Reserve Whisky" {
			t.Fatalf("legacy alias: canonical=%q, want the free-text Barrel Select read", got.CanonicalName)
		}
	})

	t.Run("off keeps legacy candidate overwrite (exact current behavior)", func(t *testing.T) {
		os.Unsetenv("VERIFY_READ_IS_TRUTH")
		os.Unsetenv("VERIFY_DEBIAS_READ")
		got := parseVerifyResponse(raw, "Double Dark", "750ml", cands, "front")
		if got.CanonicalName != "Seagram's Royal Stag Double Dark Reserve Peaty" {
			t.Fatalf("off: canonical=%q, want the matched candidate name (legacy)", got.CanonicalName)
		}
	})

	t.Run("token-equal candidate is adopted (normalized) with read-is-truth on", func(t *testing.T) {
		t.Setenv("VERIFY_READ_IS_TRUTH", "1")
		// Same distinctive tokens (only the spirit-noun "Whisky" differs) → adopt the
		// clean catalog form so casing/filler normalize.
		raw2 := `{"brand":"royal stag barrel select whisky","matched_candidate_id":"cand-bs","confidence":0.9}`
		cands2 := []MasterBrandCandidate{{ID: "cand-bs", Name: "Royal Stag Barrel Select"}}
		got := parseVerifyResponse(raw2, "Royal Stag", "750ml", cands2, "front")
		if got.CanonicalName != "Royal Stag Barrel Select" {
			t.Fatalf("token-equal candidate: canonical=%q, want the normalized catalog name", got.CanonicalName)
		}
	})
}

// TestSameImageTwoShopsConverges reproduces the owner's exact bug at the READ
// level: the SAME label, read with two DIFFERENT per-shop candidate lists, must
// resolve to the SAME canonical once read-is-truth is on — and to two DIFFERENT
// names with it off (the legacy divergence). Brand-anchoring to the master is not
// exercised here (no DB); we assert on the free-text-derived canonical, which is
// the value that used to diverge.
func TestSameImageTwoShopsConverges(t *testing.T) {
	os.Unsetenv("VERIFY_READ_IS_TRUTH")
	os.Unsetenv("VERIFY_DEBIAS_READ")

	// Same bottle, same Gemini read — but each shop's name-seeded candidate list
	// offers a different (wrong) local product as the match.
	raw := `{"brand":"The Rockford Reserve Premium Whisky","matched_candidate_id":"local","confidence":0.92}`
	shopA := []MasterBrandCandidate{{ID: "local", Name: "Rockford Classic Finest Blended Whisky"}}
	shopB := []MasterBrandCandidate{{ID: "local", Name: "Rockford Reserve Premium Whisky"}}

	classicFinest := "Rockford Classic Finest Blended Whisky"

	t.Run("read-is-truth on → same identity, neither dragged to the wrong product", func(t *testing.T) {
		t.Setenv("VERIFY_READ_IS_TRUTH", "1")
		a := parseVerifyResponse(raw, "Rockford Classic Finest", "180ml", shopA, "front")
		b := parseVerifyResponse(raw, "Rockford Reserve Premium", "180ml", shopB, "front")
		// Both must carry the SAME distinctive identity (reserve premium). Exact-string
		// convergence is the brand anchor's job (DB) + Phase-6 name derivation; at the
		// read level the guarantee is same distinctive tokens.
		if !brandReadsTokenEqual(a.CanonicalName, b.CanonicalName) {
			t.Fatalf("same image, different identity: shopA=%q shopB=%q", a.CanonicalName, b.CanonicalName)
		}
		// The core bug: shopA must NOT be dragged to its wrong shop-local candidate.
		if brandReadsTokenEqual(a.CanonicalName, classicFinest) {
			t.Fatalf("shopA wrongly resolved to Classic Finest: %q", a.CanonicalName)
		}
	})

	t.Run("off → legacy per-shop divergence into DIFFERENT identities (the bug)", func(t *testing.T) {
		os.Unsetenv("VERIFY_READ_IS_TRUTH")
		os.Unsetenv("VERIFY_DEBIAS_READ")
		a := parseVerifyResponse(raw, "Rockford Classic Finest", "180ml", shopA, "front")
		b := parseVerifyResponse(raw, "Rockford Reserve Premium", "180ml", shopB, "front")
		// Legacy: shopA adopts "Classic Finest", shopB adopts "Reserve Premium" — two
		// genuinely different products from one photo.
		if brandReadsTokenEqual(a.CanonicalName, b.CanonicalName) {
			t.Fatalf("expected legacy divergence but both = %q", a.CanonicalName)
		}
		if !brandReadsTokenEqual(a.CanonicalName, classicFinest) {
			t.Fatalf("legacy shopA should have adopted Classic Finest, got %q", a.CanonicalName)
		}
	})
}

// TestImageVerifyCacheVersionFlagAware locks that enabling read-is-truth changes
// the effective cache version (so old candidate-biased rows are flushed), and that
// disabling it reverts to the base version (fully reversible rollout).
func TestImageVerifyCacheVersionFlagAware(t *testing.T) {
	os.Unsetenv("VERIFY_READ_IS_TRUTH")
	os.Unsetenv("VERIFY_DEBIAS_READ")
	if got := imageVerifyCacheVersion(); got != ImageVerifyCacheVersion {
		t.Fatalf("off: version=%q, want base %q", got, ImageVerifyCacheVersion)
	}
	t.Setenv("VERIFY_READ_IS_TRUTH", "1")
	if got := imageVerifyCacheVersion(); got != ImageVerifyCacheVersion+"-readtruth" {
		t.Fatalf("on: version=%q, want base+suffix", got)
	}
}
