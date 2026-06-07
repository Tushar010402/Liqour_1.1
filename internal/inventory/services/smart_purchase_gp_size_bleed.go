package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
)

// GP SIZE-BLEED REPAIR (v1.0.370)
//
// FAILURE MODE (real: job 3f8a6dc8, Mahua Khera, "After Dark" rows 10/11):
// the UP-excise gate pass is photographed at a slight downward skew, and a row
// whose Packaging-Type cell wraps onto TWO lines ("Laminate" / "(Tetra)") makes
// that row physically taller. Textract's TABLES engine then draws the cell-to-row
// boundary for the *Packaging Size* and *Packaging Type* columns one row off, so
// those two adjacent middle columns swap between a neighbouring pair while the
// numeric columns to their right (Cases / Bottles / Duty) stay correctly aligned.
//
//	GP row 10 Moonwalk      TRUE 180 / Laminate(Tetra)  → extracted 375 / Glass
//	GP row 11 After Dark    TRUE 375 / Glass            → extracted 180 / "Laminate (Tetra) Glass"
//
// FINGERPRINT: the receiving row's Packaging-Type becomes a CONCATENATION of two
// packaging families ("Laminate (Tetra) Glass" = Moonwalk's Tetra + After Dark's
// own Glass). That concatenation is an unambiguous signal that this row and an
// adjacent one had their Size+Packaging cells crossed.
//
// WHY EXISTING SAFEGUARDS MISS IT: the bill cross-check can't help (the bill OCR
// also reads "180ml" for After Dark, so it agrees with the wrong value), and
// reconcileGPDispatchBottles can't help (180 × 2 cases × 48/case = 96 bottles is
// internally self-consistent, so a swapped-but-consistent size trips no invariant).
//
// REPAIR (deterministic, then corroborated — never a guess):
//  1. Detect a row whose Packaging-Type carries ≥2 packaging families.
//  2. Its true family is the one the adjacent donor row currently holds (the
//     family that crossed OUT of this row); the OTHER family belongs to the donor
//     (it crossed IN). The size that belongs here is literally sitting on the
//     donor row, and vice-versa — so the fix is to SWAP the two rows' sizes and
//     split the packaging back.
//  3. Corroborate with the vision-LLM's per-row size read (bleed-resistant — it
//     reads the document structurally, one row per serial). If the LLM contradicts
//     the geometric swap, DON'T apply it — flag both rows for review instead.
//  4. Every touched row is marked SizeBleedSuspect → NeedsReview downstream, and
//     is exempted from reconcileGPDispatchBottles / the bill size cross-check so
//     the corrected size+bottles are not re-clobbered.

// gpBleedRepairCtxKey carries the per-job gate down to the extraction layer.
type gpBleedRepairCtxKey struct{}

func withGPBleedRepair(ctx context.Context, on bool) context.Context {
	return context.WithValue(ctx, gpBleedRepairCtxKey{}, on)
}

// gpBleedRepairEnabled reports whether size-bleed repair is on for this job.
// Dark by default; auto-on for the SMART_PURCHASE_TEST_USER_ID tester, or
// globally with SMART_PURCHASE_GP_BLEED_REPAIR=1.
func gpBleedRepairEnabled(userID string) bool {
	if test := strings.TrimSpace(os.Getenv("SMART_PURCHASE_TEST_USER_ID")); test != "" {
		if strings.EqualFold(strings.TrimSpace(userID), test) {
			return true
		}
	}
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_BLEED_REPAIR"))
	return v == "1" || strings.EqualFold(v, "true")
}

func gpBleedRepairFromCtx(ctx context.Context) bool {
	if v, ok := ctx.Value(gpBleedRepairCtxKey{}).(bool); ok {
		return v
	}
	g := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_BLEED_REPAIR"))
	return g == "1" || strings.EqualFold(g, "true")
}

// packagingFamilies returns the distinct packaging families named in a
// Packaging-Type string. The generic word "bottle" is intentionally ignored —
// it appears in both "Glass Bottle" and "Pet Bottle" and carries no family.
// A result with >1 family means two rows' packaging cells were merged.
func packagingFamilies(pkg string) []string {
	s := strings.ToLower(pkg)
	var out []string
	seen := map[string]bool{}
	add := func(f string) {
		if !seen[f] {
			seen[f] = true
			out = append(out, f)
		}
	}
	if strings.Contains(s, "glass") {
		add("glass")
	}
	if strings.Contains(s, "pet") {
		add("pet")
	}
	if strings.Contains(s, "tetra") || strings.Contains(s, "laminate") {
		add("tetra")
	}
	if strings.Contains(s, "can") {
		add("can")
	}
	if strings.Contains(s, "pouch") {
		add("pouch")
	}
	return out
}

func canonicalPackaging(family string) string {
	switch family {
	case "glass":
		return "Glass Bottle"
	case "pet":
		return "Pet Bottle"
	case "tetra":
		return "Tetra (Laminate)"
	case "can":
		return "Can"
	case "pouch":
		return "Pouch"
	default:
		return ""
	}
}

func familiesContain(fams []string, f string) bool {
	for _, x := range fams {
		if x == f {
			return true
		}
	}
	return false
}

// otherFamily returns the single family in fams that is not `f` — only when
// there are exactly two families (the swap case); otherwise "".
func otherFamily(fams []string, f string) string {
	if len(fams) != 2 {
		return ""
	}
	for _, x := range fams {
		if x != f {
			return x
		}
	}
	return ""
}

// repairGPSizeBleed fixes adjacent Size+Packaging column swaps in-place and
// returns the number of rows it repaired. `rows` is the merged GP-ensemble
// output; `llm` is the parallel vision-LLM read (rows[i] aligns with llm[i],
// because mergeGPEnsemble emits one row per LLM row in order) and is used purely
// to corroborate — it is never written back.
func repairGPSizeBleed(rows, llm []GatePassDutyItem) int {
	repaired := 0
	llmSize := func(i int) int {
		if i >= 0 && i < len(llm) {
			return llm[i].SizeML
		}
		return 0
	}
	llmFamily := func(i int) string {
		if i >= 0 && i < len(llm) {
			if f := packagingFamilies(llm[i].PackagingType); len(f) == 1 {
				return f[0]
			}
		}
		return ""
	}

	for i := range rows {
		fams := packagingFamilies(rows[i].PackagingType)
		if len(fams) < 2 {
			continue // single (or no) family — not a concatenation/bleed row
		}

		// Try the row above first (the common bleed direction for a tall
		// 2-line packaging cell), then the row below.
		swapped := false
		for _, j := range []int{i - 1, i + 1} {
			if j < 0 || j >= len(rows) {
				continue
			}
			jf := packagingFamilies(rows[j].PackagingType)
			if len(jf) != 1 || !familiesContain(fams, jf[0]) {
				continue // donor must be clean & share a family with the bleed row
			}
			iTrueFam := jf[0]                  // family the donor is holding == this row's own
			jTrueFam := otherFamily(fams, iTrueFam) // the other family == donor's own
			if jTrueFam == "" {
				continue
			}
			// If the LLM gave THIS row a clean family, it must agree with the
			// geometric conclusion; otherwise we don't trust the swap direction.
			if lf := llmFamily(i); lf != "" && lf != iTrueFam {
				rows[i].SizeBleedSuspect = true
				log.Printf("  GP bleed: row %d %q packaging %q is multi-family but LLM family %q != geometric %q — flagged, not auto-swapped",
					rows[i].RowNumber, truncBrand(rows[i].BrandName), rows[i].PackagingType, lf, iTrueFam)
				break
			}

			si, sj := rows[i].SizeML, rows[j].SizeML
			if si <= 0 || sj <= 0 || si == sj {
				rows[i].SizeBleedSuspect = true
				break
			}
			// Geometric swap puts sj on row i and si on row j. Corroborate with
			// the LLM read where present: llm[i] should equal sj, llm[j] == si.
			if l := llmSize(i); l > 0 && l != sj {
				rows[i].SizeBleedSuspect, rows[j].SizeBleedSuspect = true, true
				log.Printf("  GP bleed: row %d %q swap would set %dML but LLM read %dML — contradiction, flagged for review (not swapped)",
					rows[i].RowNumber, truncBrand(rows[i].BrandName), sj, l)
				break
			}
			if l := llmSize(j); l > 0 && l != si {
				rows[i].SizeBleedSuspect, rows[j].SizeBleedSuspect = true, true
				log.Printf("  GP bleed: donor row %d %q swap would set %dML but LLM read %dML — contradiction, flagged for review (not swapped)",
					rows[j].RowNumber, truncBrand(rows[j].BrandName), si, l)
				break
			}

			// Execute the deterministic, corroborated swap.
			rows[i].SizeML, rows[j].SizeML = sj, si
			rows[i].Size, rows[j].Size = fmt.Sprintf("%dML", sj), fmt.Sprintf("%dML", si)
			rows[i].PackagingType = canonicalPackaging(iTrueFam)
			rows[j].PackagingType = canonicalPackaging(jTrueFam)
			rows[i].SizeBleedSuspect, rows[j].SizeBleedSuspect = true, true
			// Size was actually CHANGED (not merely flagged) — drives the truthful
			// "corrected to Xml" review message.
			rows[i].SizeBleedCorrected, rows[j].SizeBleedCorrected = true, true

			// v1.0.373 — the Cases/Bottles columns bleed TOGETHER with Size on these
			// rows (job 4f2b33cf: Moonwalk r10 ↔ After Dark r11 also had their
			// cases/bottles crossed — Textract gave Moonwalk 1×24 / After Dark 2×96,
			// truth is Moonwalk 2×96 / After Dark 1×24). The old repair kept the bled
			// bottles AND the row is exempt from reconcileGPDispatchBottles, so the
			// wrong count shipped. The vision-LLM reads each row structurally
			// (bleed-resistant) and — because we only reach this swap once the LLM
			// SIZE already corroborates the corrected size (the contradiction guards
			// above) — its cases/bottles for these rows are trustworthy. Adopt them
			// when they form a coherent full-case dispatch under the now-correct size.
			adoptLLMQty(&rows[i], llm, i)
			adoptLLMQty(&rows[j], llm, j)

			repaired++
			swapped = true
			log.Printf("  GP bleed REPAIR: rows %d/%d size+pkg crossed — %q now %dML/%s (%d×%d), %q now %dML/%s (%d×%d) (LLM-corroborated)",
				rows[i].RowNumber, rows[j].RowNumber,
				truncBrand(rows[i].BrandName), sj, canonicalPackaging(iTrueFam), rows[i].Cases, rows[i].Bottles,
				truncBrand(rows[j].BrandName), si, canonicalPackaging(jTrueFam), rows[j].Cases, rows[j].Bottles)
			break
		}
		if !swapped && !rows[i].SizeBleedSuspect {
			// Concatenated packaging but no clean adjacent donor — can't safely
			// reconstruct. Flag for review rather than ship a corrupt size.
			rows[i].SizeBleedSuspect = true
			log.Printf("  GP bleed: row %d %q packaging %q multi-family but no clean adjacent donor — flagged for review",
				rows[i].RowNumber, truncBrand(rows[i].BrandName), rows[i].PackagingType)
		}
	}

	// DIAGNOSTIC (SMART_PURCHASE_GP_BLEED_DEBUG=1) — dump both engines' full
	// (size, cases, bottles, btl/case, std-coherent?) triples for every row, so we
	// can see on a clone exactly what the LLM read where Textract disagrees. Pure
	// logging; no behaviour change. Used to design the row-8-class auto-fix.
	if dbg := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_BLEED_DEBUG")); dbg == "1" || strings.EqualFold(dbg, "true") {
		for i := range rows {
			tS, tC, tB := rows[i].SizeML, rows[i].Cases, rows[i].Bottles
			lS, lC, lB := 0, 0, 0
			if i < len(llm) {
				lS, lC, lB = llm[i].SizeML, llm[i].Cases, llm[i].Bottles
			}
			tag := ""
			if lS > 0 && lS != tS {
				tag = "  <== SIZE DISAGREE"
			}
			log.Printf("  GP bleed DEBUG row %d %-26q | TEXTRACT size=%d cases=%d btl=%d bpc=%s%s | LLM size=%d cases=%d btl=%d bpc=%s%s | pkg=%q%s",
				rows[i].RowNumber, truncBrand(rows[i].BrandName),
				tS, tC, tB, bpcStr(tC, tB), coherentStr(tS, tC, tB),
				lS, lC, lB, bpcStr(lC, lB), coherentStr(lS, lC, lB),
				rows[i].PackagingType, tag)
		}
	}

	// Safety net — flag (NEVER change) a row whose merged size disagrees with the
	// LLM when both are standard sizes. Catches a standalone size misread the
	// concatenation pass can't pair (e.g. job 3f8a6dc8 row 8 "Verve Cranberry":
	// Textract 180, truth 375).
	//
	// BUT suppress the most common false positive: when a brand is listed at two
	// sizes, the LLM frequently SWAPS which size belongs to which row. There the
	// LLM's per-brand size MULTISET equals Textract's — it only reordered them —
	// and Textract is authoritative for the size column, so flagging would be
	// noise (job 3f8a6dc8 rows 6/12 "Royal Green": Textract {180,375} correct,
	// LLM {375,180}). Only flag when the LLM introduces a size the brand's
	// Textract set does NOT contain.
	brandT := map[string][]int{}
	brandL := map[string][]int{}
	for i := range rows {
		if rows[i].SizeBleedSuspect {
			continue
		}
		k := strings.ToLower(strings.TrimSpace(rows[i].BrandName))
		if rows[i].SizeML > 0 {
			brandT[k] = append(brandT[k], rows[i].SizeML)
		}
		if l := llmSize(i); l > 0 {
			brandL[k] = append(brandL[k], l)
		}
	}
	for i := range rows {
		if rows[i].SizeBleedSuspect {
			continue
		}
		l := llmSize(i)
		if l <= 0 || l == rows[i].SizeML {
			continue
		}
		if _, ok := StandardCaseSizes[l]; !ok {
			continue
		}
		if _, ok := StandardCaseSizes[rows[i].SizeML]; !ok {
			continue
		}
		k := strings.ToLower(strings.TrimSpace(rows[i].BrandName))
		if sameSizeMultiset(brandT[k], brandL[k]) {
			continue // LLM merely reordered this brand's sizes — Textract is right
		}
		rows[i].SizeBleedSuspect = true
		// FLAG-ONLY (not corrected): the two engines give different standard sizes
		// and there is no data signal to safely pick (e.g. job 4f2b33cf row 8
		// "Verve Cranberry": Textract 180 vs LLM 375, both internally coherent —
		// only the row's own pixels can decide). Record the alternative so review
		// shows both candidates rather than a false "re-derived" claim.
		rows[i].SizeAltML = l
		log.Printf("  GP bleed: row %d %q size %dML disagrees with LLM %dML (both standard, not a same-brand reorder) — flagged for review (alt=%dML)",
			rows[i].RowNumber, truncBrand(rows[i].BrandName), rows[i].SizeML, l, l)
	}

	if repaired > 0 {
		log.Printf("SmartPurchase GP bleed: repaired %d adjacent size/packaging swap(s)", repaired)
	}
	return repaired
}

// adoptLLMQty replaces a swapped row's Cases/Bottles with the vision-LLM's read
// for the same row, but ONLY when the LLM's quantities form a coherent full-case
// dispatch under the row's (already-corrected) size — i.e. bottles == cases ×
// StandardCaseSizes[size]. Used after a size-bleed swap, where the numeric
// columns commonly bled along with the size and Textract's count is unreliable,
// while the LLM (which sized this row correctly, by construction of reaching the
// swap) read it structurally. No-op if the LLM row is missing, has zero counts,
// the size is non-standard, or the LLM count is itself incoherent (then we keep
// Textract's count rather than trust an incoherent LLM read).
func adoptLLMQty(r *GatePassDutyItem, llm []GatePassDutyItem, idx int) {
	if idx < 0 || idx >= len(llm) {
		return
	}
	lc, lb := llm[idx].Cases, llm[idx].Bottles
	if lc <= 0 || lb <= 0 {
		return
	}
	std, ok := StandardCaseSizes[r.SizeML]
	if !ok || lb != lc*std {
		return
	}
	if r.Cases == lc && r.Bottles == lb {
		return // already matches — nothing to do
	}
	log.Printf("  GP bleed: row %d %q adopting LLM dispatch %d×%d=%d (was %d×%d=%d — bled with size)",
		r.RowNumber, truncBrand(r.BrandName), lc, std, lb, r.Cases, std, r.Bottles)
	r.Cases, r.Bottles = lc, lb
}

// sameSizeMultiset reports whether two size slices contain the same values with
// the same multiplicities (order-independent) — i.e. one is a reordering of the
// other. Empty/length-mismatched slices are never "same" (we only suppress when
// there is a genuine like-for-like permutation to compare).
func sameSizeMultiset(a, b []int) bool {
	if len(a) == 0 || len(a) != len(b) {
		return false
	}
	count := map[int]int{}
	for _, x := range a {
		count[x]++
	}
	for _, x := range b {
		count[x]--
	}
	for _, c := range count {
		if c != 0 {
			return false
		}
	}
	return true
}

// bpcStr renders the observed bottles-per-case (bottles/cases) for the diagnostic
// dump, or "-" when cases is unknown/zero.
func bpcStr(cases, bottles int) string {
	if cases <= 0 {
		return "-"
	}
	return fmt.Sprintf("%d", bottles/cases)
}

// coherentStr reports, for the diagnostic dump, whether a (size,cases,bottles)
// triple is a clean full-case dispatch under the standard pack table —
// i.e. bottles == cases × StandardCaseSizes[size]. " OK" means coherent,
// " !!" means the btl/case contradicts the size (the disambiguating signal).
func coherentStr(size, cases, bottles int) string {
	if size <= 0 || cases <= 0 {
		return ""
	}
	std, ok := StandardCaseSizes[size]
	if !ok {
		return " ?"
	}
	if bottles == cases*std {
		return " OK"
	}
	return " !!"
}

func truncBrand(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 32 {
		return s[:32]
	}
	return s
}
