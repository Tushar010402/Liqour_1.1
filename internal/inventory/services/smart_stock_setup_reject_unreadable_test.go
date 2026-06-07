//go:build reject_unreadable
// +build reject_unreadable

// Permanent regression guard for the v1.0.283 anti-phantom gate
// (shouldRejectUnreadableAutoCreate), HARDENED after a second production
// instance. The function is pure, so this runs without a DB. The `services`
// package has pre-existing vet/mock breakage that blocks the default suite, so
// — like the other service tests — this is build-tagged. Run with:
//
//	docker run --rm -v /var/www/liquorpro:/src -w /src -e GOTOOLCHAIN=auto \
//	  golang:1.24-alpine sh -c 'go test -tags=reject_unreadable -vet=off \
//	  -run TestShouldRejectUnreadableAutoCreate ./internal/inventory/services/...'
//
// CONTRACT (provenance, NOT confidence): a row is rejected iff NOTHING vouches
// for it — no catalog master link, no operator correction/manual-add, no
// photo, and the operator did not retype a distinct name. Confidence is NOT a
// parameter: instance #1 ("Chonploopr") was low-confidence OCR garble;
// instance #2 ("Vin Green Label The Rich Blend Whisky") was a CONFIDENT
// hallucination — the old ≤0.50 floor would have let #2 through. Any single
// vouching signal must keep the row.
package services

import "testing"

func TestShouldRejectUnreadableAutoCreate(t *testing.T) {
	type tc struct {
		name            string
		masterLinked    bool
		wasCorrected    bool
		hasPhoto        bool
		vouchedBySubmit bool // v1.0.291 — 5th vouching signal: row was visible on review screen at submit
		editedName      string
		brandName       string
		officialName    string
		want            bool
	}
	cases := []tc{
		{
			// Instance #1 — low-confidence OCR garble. MUST reject.
			name:      "Chonploopr class (OCR garble) — reject",
			brandName: "Chonploopr", officialName: "Chonploopr",
			want: true,
		},
		{
			// Instance #2 — long, plausible, CONFIDENT hallucination. The
			// edge case the original confidence-floor gate MISSED. Same
			// provenance vacuum (no master/correction/photo) → MUST reject.
			name:      "Vin Green Label (confident hallucination) — reject",
			brandName: "Vin Green Label The Rich Blend Whisky",
			want:      true,
		},
		{
			name:      "no vouching signal at all — reject",
			brandName: "Anything Unmatched",
			want:      true,
		},
		{
			name:         "catalog-linked (operator picked / fuzzy master) — keep",
			masterLinked: true, brandName: "Chonploopr", want: false,
		},
		{
			name:         "operator corrected / manual Add-Missing — keep",
			wasCorrected: true, brandName: "Some New Local Brand", want: false,
		},
		{
			name:     "photo-verified row — keep",
			hasPhoto: true, brandName: "Vin Green Label The Rich Blend Whisky",
			want: false,
		},
		{
			name:       "operator retyped a DISTINCT name (manual authorship) — keep",
			editedName: "Blenders Pride", brandName: "Blndrs Prde", officialName: "Blndrs Prde",
			want: false,
		},
		{
			name:       "edited name equals AI brand (no real authorship) — still reject",
			editedName: "Chonploopr", brandName: "Chonploopr", officialName: "Chonploopr",
			want: true,
		},
		{
			name:       "edited name equals AI official name (no real authorship) — still reject",
			editedName: "Vin Green Label The Rich Blend Whisky",
			brandName:  "", officialName: "Vin Green Label The Rich Blend Whisky",
			want: true,
		},
		{
			// Defence-in-depth: multiple vouching signals → keep (never
			// double-negative into a reject).
			name:         "catalog-linked AND photo AND corrected — keep",
			masterLinked: true, wasCorrected: true, hasPhoto: true,
			brandName: "Whatever", want: false,
		},
		{
			// v1.0.291 — operator saw the row on the review screen and
			// tapped Set Opening Stock. That gesture IS the vouching event:
			// even a garbled OCR name like "imjum" must save. The other 4
			// signals (master/corrected/photo/authored) are all false here —
			// only vouchedBySubmit keeps the row.
			name:            "operator vouched at submit (garbled name, but seen on review) — keep",
			vouchedBySubmit: true,
			brandName:       "imjum",
			officialName:    "imjum",
			want:            false,
		},
		{
			// Re-extraction / admin-direct auto-apply do NOT pass through
			// the review screen, so vouchedBySubmit stays false. The gate
			// must still reject — this is the path v290 always-on protects.
			name:            "background path (no review screen) — still reject",
			vouchedBySubmit: false,
			brandName:       "Chonploopr",
			officialName:    "Chonploopr",
			want:            true,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := shouldRejectUnreadableAutoCreate(
				c.masterLinked, c.wasCorrected, c.hasPhoto, c.vouchedBySubmit,
				c.editedName, c.brandName, c.officialName,
			)
			if got != c.want {
				t.Fatalf("shouldRejectUnreadableAutoCreate = %v, want %v", got, c.want)
			}
		})
	}
}
