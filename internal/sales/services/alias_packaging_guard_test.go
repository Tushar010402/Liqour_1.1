package services

import "testing"

// TestPackagingTokenConflict_FMTowerTetraPet locks in the exact alias-routing
// failure that caused the May 26 FM Tower bug: OCR text "8 PM Gold Scotch
// Whisky PET" was hitting a learned alias pinned to "8pm Gold Scotch Whisky
// Tetra 180ml". The packaging guard must mark that pair as a conflict.
func TestPackagingTokenConflict_FMTowerTetraPet(t *testing.T) {
	got := hasPackagingTokenConflict("8 pm gold scotch whisky pet", "8pm Gold Scotch Whisky Tetra 180ml")
	if !got {
		t.Fatal("expected packaging conflict between OCR 'pet' and product 'Tetra'")
	}
}

// TestPackagingTokenConflict_TableDriven exercises the guard across the
// common packaging-vs-packaging and packaging-vs-silent cases.
func TestPackagingTokenConflict_TableDriven(t *testing.T) {
	cases := []struct {
		name           string
		ocr, candidate string
		wantConflict   bool
	}{
		// True conflicts — same brand family, different packaging.
		{"pet_vs_tetra", "8 PM Gold Scotch Whisky PET", "8pm Gold Scotch Whisky Tetra 180ml", true},
		{"tetra_vs_pet", "Royal Stag Tetra", "Royal Stag Pet Bottle 180ml", true},
		{"glass_vs_pet", "Imperial Blue Glass", "Imperial Blue Pet", true},
		{"can_vs_glass", "Kingfisher Can 500ml", "Kingfisher Glass 500ml", true},
		{"tin_vs_pet", "Bira Tin", "Bira Pet", true},

		// Same packaging family — not a conflict.
		{"pet_vs_pet", "8 PM Gold Pet", "8 PM Gold Pet 180ml", false},
		{"tin_vs_can_same_family", "Tuborg Tin", "Tuborg Can", false}, // tin/can collapse

		// Silent on one or both sides — no conflict (matcher's other gates handle it).
		{"silent_ocr", "8 PM Gold Scotch Whisky", "8pm Gold Scotch Whisky Tetra 180ml", false},
		{"silent_candidate", "8 PM Gold Scotch Whisky PET", "8pm Gold Scotch Whisky", false},
		{"both_silent", "8 PM Gold Scotch Whisky", "8pm Gold Scotch Whisky 180ml", false},

		// False-positive guards — substrings of packaging words must not match.
		{"petrol_not_pet", "Petrol Pump Brand Whisky", "Real Brand Whisky 180ml", false},
		{"quarterly_not_qtr", "Quarterly Reserve Whisky", "Real Reserve 180ml", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := hasPackagingTokenConflict(tc.ocr, tc.candidate)
			if got != tc.wantConflict {
				t.Errorf("hasPackagingTokenConflict(%q, %q) = %v, want %v", tc.ocr, tc.candidate, got, tc.wantConflict)
			}
		})
	}
}

// TestPackagingTokenConflict_PunctuationStripped confirms the tokenizer
// strips surrounding punctuation so "(PET)" or "PET," still register as
// the packaging token "pet". Real catalog names sometimes wrap the
// packaging form in parentheses (e.g. "8 PM Gold Scotch (Pet)").
func TestPackagingTokenConflict_PunctuationStripped(t *testing.T) {
	cases := []struct {
		ocr, candidate string
		want           bool
	}{
		{"8 PM Gold (PET)", "8 PM Gold Tetra", true},
		{"8 PM Gold PET,", "8 PM Gold Tetra", true},
		{"8 PM Gold 'PET'", "8 PM Gold Tetra", true},
	}
	for _, tc := range cases {
		t.Run(tc.ocr, func(t *testing.T) {
			if got := hasPackagingTokenConflict(tc.ocr, tc.candidate); got != tc.want {
				t.Errorf("hasPackagingTokenConflict(%q, %q) = %v, want %v", tc.ocr, tc.candidate, got, tc.want)
			}
		})
	}
}

// TestSharedDistinctiveToken_RegressionPair sanity-checks that
// hasSharedDistinctiveToken still works on the PET/Tetra pair. Before the
// packaging guard, this function was the LAST line of defence — but with
// "pet" being 3 chars, the OCR tokens collapsed to an empty set and the
// function returned true permissively (see comment at line 6748). The
// packaging guard now catches that case; this test documents the prior
// behaviour to prevent accidental "fix" of hasSharedDistinctiveToken
// from masking the new guard.
func TestSharedDistinctiveToken_PETHasNoLongTokens(t *testing.T) {
	// "pet" is filtered out by len(t) < 4. The remaining OCR tokens are
	// generics ("gold", "scotch", "whisky"). With both sides reduced to
	// empty distinctive sets, the function returns true (permissive).
	got := hasSharedDistinctiveToken("8 pm gold scotch whisky pet", "8pm Gold Scotch Whisky Tetra 180ml")
	if !got {
		t.Fatal("hasSharedDistinctiveToken behaviour changed; the packaging guard depends on it being permissive here")
	}
}
