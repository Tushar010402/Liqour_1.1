package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/sizing"
	"gorm.io/gorm"
)

// v1.0.221 GP-primary orchestrator entry point.
//
// processGPPrimary takes the extracted GP items (already parsed from the
// excise PDF by smart_purchase_gate_pass.go) plus the bill items (parsed
// by smart_purchase_ocr.go) and produces v221-shaped SmartPurchaseExtractedItem
// rows where:
//
//   - GP is the skeleton: one result row per GP row, in GP order.
//   - Bill is the price source only: each row's `RatePerBottle` + `Amount`
//     come from the matching bill line (fuzzy ≥0.55 by canonical+size).
//   - Tenant product match uses strict saas_brand_id + size_ml via the
//     selectBestProductForGPRow helper. Duplicate rows are resolved by
//     deterministic tiebreaker.
//   - Onboarding decisions use the three-way path from
//     decideOnboardingPath (auto-onboard / soft-link / ask-past-purchase).
//   - Duty-per-bottle is GP.duty_fee / GP.bottles_dispatched.
//   - DSE-GP mismatch is surfaced as a soft warning when |GP.btl - DSE.btl| ∈ (0,3].
//
// Gated by env flag SMART_PURCHASE_GP_PRIMARY (defaults off). When off,
// the legacy bill-primary path in ProcessSmartPurchase continues unchanged.
//
// Why this is additive: nothing the legacy path does is removed. The flag
// switches between two implementations of the "produce result items" step
// while the upstream extraction (bill + GP OCR) and downstream apply path
// both stay the same.

// gpPrimaryEnabled returns true when the GP-primary pipeline should run
// for this tenant. Order: global flag → per-tenant flag → off.
func gpPrimaryEnabled(tenantID uuid.UUID) bool {
	if v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_PRIMARY")); v == "1" || strings.EqualFold(v, "true") {
		return true
	}
	per := os.Getenv("SMART_PURCHASE_GP_PRIMARY_TENANT_" + tenantID.String())
	return per == "1" || strings.EqualFold(per, "true")
}

// gpDegradedFallbackEnabled — kill-switch (default ON) for the v1.0.346
// degraded-gate-pass → bill-primary fallback. Set
// SMART_PURCHASE_GP_DEGRADED_FALLBACK=0 to force GP-primary even on a poor GP.
func gpDegradedFallbackEnabled() bool {
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_DEGRADED_FALLBACK"))
	return v != "0" && !strings.EqualFold(v, "false")
}

// gpOnlyNamesEnabled — v1.0.359 owner rule: product NAME + quantity/pieces come
// from the GATE PASS only; the bill contributes ONLY cost/vendor/TCS. This is the
// master switch for that behavior. Two ways to turn it on:
//   - SMART_PURCHASE_GP_ONLY_NAMES=1  → global "ship" switch (default OFF), makes
//     GP-only the default for every job.
//   - SMART_PURCHASE_TEST_USER_ID=<uuid> → per-job portal enable: when the job's
//     user_id matches, GP-only is forced ON for THAT job only, regardless of the
//     global switch. Lets the public tester exercise the fix while real app jobs
//     keep current behavior ("portal first, then ship").
//
// Every behavioral change keys off this so the whole fix is dark by default and
// revertable by flipping the env (no redeploy).
func gpOnlyNamesEnabled(userID string) bool {
	if test := strings.TrimSpace(os.Getenv("SMART_PURCHASE_TEST_USER_ID")); test != "" {
		if strings.EqualFold(strings.TrimSpace(userID), test) {
			return true
		}
	}
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_ONLY_NAMES"))
	return v == "1" || strings.EqualFold(v, "true")
}

// gpHybridNamesEnabled — v1.0.360. Gate-pass HYBRID extraction: take the numeric
// columns (size/cases/bottles/duty) from AWS Textract (which reads them
// deterministically + correctly) but the BRAND NAMES from the vision-LLM (which
// reads the multi-line wrapped brand column ~100%, where Textract smears it
// across rows/columns). Same dark-by-default rollout as GP-only: global
// SMART_PURCHASE_GP_HYBRID_NAMES=1 OR per-job SMART_PURCHASE_TEST_USER_ID match
// (so the public tester validates it before we ship).
func gpHybridNamesEnabled(userID string) bool {
	if test := strings.TrimSpace(os.Getenv("SMART_PURCHASE_TEST_USER_ID")); test != "" {
		if strings.EqualFold(strings.TrimSpace(userID), test) {
			return true
		}
	}
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_HYBRID_NAMES"))
	return v == "1" || strings.EqualFold(v, "true")
}

// shopAliasGuardEnabled — WS1.1. Strict shop isolation for the purchase
// matcher: when ON, alias resolution refuses any alias whose product belongs to
// a DIFFERENT shop (the Rockford cross-shop bleed), and the matcher falls
// through to the same-shop product or "not found" instead of binding another
// shop's product. Same dark rollout: global SMART_PURCHASE_SHOP_ALIAS_GUARD=1 OR
// per-job SMART_PURCHASE_TEST_USER_ID match (tester validates before ship).
func shopAliasGuardEnabled(userID string) bool {
	if test := strings.TrimSpace(os.Getenv("SMART_PURCHASE_TEST_USER_ID")); test != "" {
		if strings.EqualFold(strings.TrimSpace(userID), test) {
			return true
		}
	}
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_SHOP_ALIAS_GUARD"))
	return v == "1" || strings.EqualFold(v, "true")
}

// identityEngineEnabled — WS-A/B (v1.0.366) image→identity engine. When on, the
// GP matcher REUSES an existing same-shop product found by variant-safe name+size
// (jaccard) even when its master saas_brand link is wrong — so a mislinked product
// (e.g. Rockford Reserve Premium linked to the Fine & Rare master) is reused
// instead of duplicated as "new". Dark: SMART_PURCHASE_TEST_USER_ID match OR
// global SMART_PURCHASE_IDENTITY_ENGINE=1.
func identityEngineEnabled(userID string) bool {
	if test := strings.TrimSpace(os.Getenv("SMART_PURCHASE_TEST_USER_ID")); test != "" {
		if strings.EqualFold(strings.TrimSpace(userID), test) {
			return true
		}
	}
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_IDENTITY_ENGINE"))
	return v == "1" || strings.EqualFold(v, "true")
}

type identityEngineCtxKey struct{}

func withIdentityEngine(ctx context.Context, on bool) context.Context {
	return context.WithValue(ctx, identityEngineCtxKey{}, on)
}

func identityEngineFromCtx(ctx context.Context) bool {
	if v, ok := ctx.Value(identityEngineCtxKey{}).(bool); ok {
		return v
	}
	g := strings.TrimSpace(os.Getenv("SMART_PURCHASE_IDENTITY_ENGINE"))
	return g == "1" || strings.EqualFold(g, "true")
}

// shopIsolationCtxKey carries the per-job shop-isolation decision (which knows
// the user, hence the test-user gate) down into helpers that don't have the
// user in scope — selectBestProductForGPRow lives several calls below
// ProcessSmartPurchase. Set once at the top-level entry via withShopIsolation.
type shopIsolationCtxKey struct{}

func withShopIsolation(ctx context.Context, on bool) context.Context {
	return context.WithValue(ctx, shopIsolationCtxKey{}, on)
}

// shopIsolationEnabled reports whether strict shop isolation is on for this
// call. Prefers the per-job decision stamped by withShopIsolation (covers the
// test user); when absent (e.g. operator-initiated disambig that never set it),
// falls back to the global SMART_PURCHASE_SHOP_ALIAS_GUARD switch.
func shopIsolationEnabled(ctx context.Context) bool {
	if v, ok := ctx.Value(shopIsolationCtxKey{}).(bool); ok {
		return v
	}
	g := strings.TrimSpace(os.Getenv("SMART_PURCHASE_SHOP_ALIAS_GUARD"))
	return g == "1" || strings.EqualFold(g, "true")
}

// mergeGPEnsemble — v1.0.361 robust ensemble merge. The vision-LLM is the row
// SPINE because it reads document STRUCTURE cleanly (one row per serial, reliable
// S.No, brand names ~100% — Textract smears the wrapped brand column and even
// mis-counts rows). Onto each LLM row we overlay Textract's NUMBERS (deterministic
// size/cases/bottles/duty) where Textract has a confident matching row, aligned by
// the document's own key: exact S.No first, then an ordered (size,bottles) match,
// then nearest-by-size. A field falls back to the LLM's own read when Textract has
// nothing. Downstream reconcileGPDispatchBottles + applyGPMathGate enforce the
// pack-math invariant on the result. Every LLM row yields an output row — no row
// is lost (vs the old Textract-spine two-pointer that dropped ~60% of names).
func mergeGPEnsemble(textract, llm []GatePassDutyItem) []GatePassDutyItem {
	if len(llm) == 0 {
		return textract // no LLM names — keep Textract as-is
	}
	if len(textract) == 0 {
		return llm // no Textract numbers — LLM already has both
	}
	usedT := make([]bool, len(textract))
	tptr := 0 // ordered cursor so duplicate (size,bottles) signatures stay in order
	numbersFromTextract := 0

	findTextract := func(L GatePassDutyItem) int {
		// 1) exact printed serial (both > 0) — the document's own primary key.
		if L.RowNumber > 0 {
			for k := range textract {
				if !usedT[k] && textract[k].RowNumber > 0 && textract[k].RowNumber == L.RowNumber {
					return k
				}
			}
		}
		// 2) ordered (size_ml, bottles) signature from the cursor forward.
		for k := tptr; k < len(textract); k++ {
			if !usedT[k] && textract[k].SizeML == L.SizeML && textract[k].Bottles == L.Bottles {
				return k
			}
		}
		// 3) nearest-by-size within a small window ahead.
		for k := tptr; k < len(textract) && k < tptr+3; k++ {
			if !usedT[k] && textract[k].SizeML == L.SizeML {
				return k
			}
		}
		return -1
	}

	out := make([]GatePassDutyItem, 0, len(llm))
	for li := range llm {
		row := llm[li] // base: LLM name + LLM numbers (correct in practice)
		ti := findTextract(llm[li])
		if ti >= 0 {
			T := textract[ti]
			usedT[ti] = true
			if ti >= tptr {
				tptr = ti + 1
			}
			// Numbers: Textract authority where it carries a value; else keep LLM's.
			if T.SizeML > 0 {
				row.SizeML, row.Size = T.SizeML, T.Size
			}
			if T.Cases > 0 {
				row.Cases = T.Cases
			}
			if T.Bottles > 0 {
				row.Bottles = T.Bottles
			}
			if T.DutyFee > 0 {
				row.DutyFee = T.DutyFee
			}
			if T.LiquorType != "" {
				row.LiquorType = T.LiquorType
			}
			if T.LiquorSubType != "" {
				row.LiquorSubType = T.LiquorSubType
			}
			if T.PackagingType != "" {
				row.PackagingType = T.PackagingType
			}
			numbersFromTextract++
		}
		// Name ALWAYS the LLM's (authority for the wrapped brand column).
		out = append(out, row)
	}
	log.Printf("SmartPurchase GP ensemble: %d rows (LLM spine) — Textract numbers aligned on %d, LLM-only on %d",
		len(out), numbersFromTextract, len(out)-numbersFromTextract)
	return out
}

// resolveGPOnlyName implements the owner's NAME precedence under GP-only:
// gate-pass brand → GP canonical (source=gate_pass) → matched product name →
// "Unread — needs review". The bill's printed text is NEVER returned. Pure +
// testable. `unread` is true only for the last case (caller flags for review).
func resolveGPOnlyName(gatePassBrand, canonicalBrand, canonicalSource, matchedDisplayName string) (name string, unread bool) {
	switch {
	case strings.TrimSpace(gatePassBrand) != "":
		return gatePassBrand, false
	case strings.TrimSpace(canonicalBrand) != "" && canonicalSource == "gate_pass":
		return canonicalBrand, false
	case strings.TrimSpace(matchedDisplayName) != "":
		return matchedDisplayName, false
	default:
		return "Unread — needs review", true
	}
}

// gatePassTooDegradedForPrimary reports whether the gate-pass extraction is too
// poor to drive the item list. The failure mode (seen on a low-res screenshot of
// a dense UP-excise transport pass — chhotu Mahua Khera job 87098ea4) is that the
// brand-name and/or packaging-size columns under-extract: rows come back with an
// empty brand_name or size_ml=0, so most ship unmatched + uncosted. When ≥25% of
// rows are like that, the caller keeps the BILL-PRIMARY result instead — the
// machine-printed bill carries clean names + rates + amounts. Returns the flag
// plus (badRows, total) for logging. v1.0.346.
func gatePassTooDegradedForPrimary(gpItems []GatePassDutyItem) (bool, int, int) {
	total := len(gpItems)
	if total == 0 {
		return false, 0, 0
	}
	bad := 0
	for _, g := range gpItems {
		if strings.TrimSpace(g.BrandName) == "" || g.SizeML <= 0 {
			bad++
		}
	}
	return float64(bad) >= 0.25*float64(total), bad, total
}

// resolveBillSaasBrandIDs resolves every bill row to its master
// saas_brands.id, returning a slice parallel to billItems (uuid.Nil where a
// row cannot be confidently resolved). Each distinct brand text is resolved
// at most once — results are memoised by lowercased text so a 37-row bill
// with repeated SKUs makes far fewer DB calls than 37.
//
// We prefer the bill row's CanonicalBrand (set by buildGatePassBrandMap when
// an earlier pass already paired it to a GP full name) and fall back to the
// raw Brand text. Read-only; v1.0.331 (Fix A).
func (s *SmartPurchaseService) resolveBillSaasBrandIDs(
	ctx context.Context,
	billItems []ExtractedPurchaseItem,
) []uuid.UUID {
	tx := s.db.WithContext(ctx)
	out := make([]uuid.UUID, len(billItems))
	memo := make(map[string]uuid.UUID)
	for i, b := range billItems {
		text := strings.TrimSpace(b.CanonicalBrand)
		if text == "" {
			text = strings.TrimSpace(b.Brand)
		}
		if text == "" {
			continue
		}
		key := strings.ToLower(text)
		if id, ok := memo[key]; ok {
			out[i] = id
			continue
		}
		m := s.resolveSaasBrandByGPCanonical(tx, text)
		// Only trust confident resolutions as a pairing key. The resolver's
		// fuzzy tiers floor at 0.70; exacts are 1.0. Anything below would
		// risk pairing two different brands that happen to share tokens.
		id := uuid.Nil
		if m.SaasBrandID != uuid.Nil && m.Confidence >= 0.70 {
			id = m.SaasBrandID
		}
		memo[key] = id
		out[i] = id
	}
	return out
}

// derefStr safely dereferences a *string for logging.
func derefStr(p *string) string {
	if p == nil {
		return "<nil>"
	}
	return *p
}

// classifyDuplicateBindings splits the non-winner rows that share a tenant
// product_id with a stronger row into two buckets. The winner per product is
// the highest-MatchConfidence row (ties → earliest GP row).
//
// A gate pass never lists the same product+size on two lines (operator-
// confirmed domain rule), so EVERY extra row binding a product is wrong — the
// only question is how:
//
//   - drop (IDENTICAL full brand): a DUPLICATE extraction of the SAME line — the
//     OCR emitted the row twice (FM Tower replay: "M2 Jamun Spicymint 180ml" on
//     rows 9 AND 33, "Spicymint" vs "Spicy Mint"). Summing it would double-
//     count, and the product never legitimately repeats, so we DROP it. The
//     drop test is normalized-brand EQUALITY (normBrandKey strips spacing/
//     punctuation so OCR spacing variance still matches). (v1.0.335)
//   - unbind (any other brand difference): could be a DIFFERENT product fuzzy-
//     matched onto this one — "SUPERIOR VODKA" onto "Royal Stag Superior
//     Whisky", or even "Superior Whisky" vs "Superior Vodka" (which the token
//     matcher can't tell apart once the category word is stripped). These may
//     be real distinct lines, so we never drop them blind — we UNBIND and route
//     to review/create so the operator decides. (v1.0.332)
//
// Drop is deliberately the STRICT bucket (exact normalized brand) and unbind
// the lenient one: a wrong drop loses a real delivery line, a wrong unbind only
// asks the operator to re-confirm — so when unsure we unbind, never drop. Pure.
func classifyDuplicateBindings(items []SmartPurchaseExtractedItem) (unbind, drop []int) {
	byPID := make(map[string][]int)
	for i := range items {
		if items[i].ProductID != nil && strings.TrimSpace(*items[i].ProductID) != "" {
			pid := *items[i].ProductID
			byPID[pid] = append(byPID[pid], i)
		}
	}
	for _, idxs := range byPID {
		if len(idxs) < 2 {
			continue
		}
		win := idxs[0]
		for _, j := range idxs[1:] {
			if items[j].MatchConfidence > items[win].MatchConfidence {
				win = j
			}
		}
		winKey := normBrandKey(items[win].BrandName)
		for _, j := range idxs {
			if j == win {
				continue
			}
			if winKey != "" && normBrandKey(items[j].BrandName) == winKey {
				// The gate-pass SERIAL (S.No) is each line's identity. A product CAN
				// legitimately appear on more than one line (different cases/batches),
				// so DISTINCT serials are DISTINCT lines → keep both. Only a TRUE
				// double-extraction — the SAME serial read twice (or serial unknown,
				// the legacy ambiguous case) — is a duplicate to drop.
				sameLine := items[j].RowNumber == items[win].RowNumber ||
					items[j].RowNumber == 0 || items[win].RowNumber == 0
				if sameLine {
					drop = append(drop, j) // same physical line OCR'd twice
				}
				// else: distinct serials → legitimate repeat line → keep (no drop/unbind)
			} else {
				unbind = append(unbind, j) // any brand difference → route to review, never lose it
			}
		}
	}
	return unbind, drop
}

// pickMisboundDuplicateLosers returns just the UNBIND bucket (different-brand
// mis-matches) for callers/tests that only care about that class. v1.0.332.
func pickMisboundDuplicateLosers(items []SmartPurchaseExtractedItem) []int {
	unbind, _ := classifyDuplicateBindings(items)
	return unbind
}

// maxRealBottlesPerCase is the largest plausible case pack. Real liquor/beer
// cases top out around 96 bottles (90ml "nip" cases); we allow generous
// headroom to 150. A bottles_per_case beyond this is OCR garbage — almost
// always the document grand total bled into the pack-size cell.
const maxRealBottlesPerCase = 150

// isGPFooterTotalRow returns true when a gate-pass row is the document
// grand-total line that OCR mis-read as a product. Its brand cell typically
// bleeds the PREVIOUS real product's name, so a text filter alone can't catch
// it — we rely on quantity fingerprints instead. Guarded to ≥4 total rows so
// a legitimate short GP with one dominant line is never dropped.
//
// A grand-total row's defining property is that its count EQUALS the sum of
// every real line item — it ≈ the sum of all OTHER rows, not merely "exceeds"
// them. The original >otherBottles test only fired when the cases column
// happened to OCR to an extreme value (FM Tower job 52714ffc captured run:
// cases=91). When the total instead bled into the bottles/pack cells
// (cases=1, bottles_per_case=2438, bottles=2438) the row sat JUST UNDER the
// sum of the real rows (2438 vs 2496) and slipped through — a real phantom of
// 2438 bottles reached the live review screen (clone job 8ac60698). This
// version adds two robust, largely independent fingerprints:
//
//	(1) Impossible pack size — bottles_per_case beyond any real case pack means
//	    the row's quantity is unusable garbage (grand total bled into the bpc
//	    cell). Self-contained; cannot false-positive a real product row.
//	(2) Approximate-or-exceeds total — a single row whose bottle (or case)
//	    count reaches the combined total of all OTHER rows is the total line.
//	    The softer ">=80% of others" arm is gated to ≥6 rows so a short GP with
//	    one genuinely dominant bulk line is never touched.
//
// rowCases/rowBottles/rowBPC = the candidate row's quantities + pack size
// sumCases/sumBottles        = column totals across ALL rows (candidate included)
// rowCount                   = number of rows on the document
func isGPFooterTotalRow(rowCases, rowBottles, rowBPC, sumCases, sumBottles, rowCount int) bool {
	if rowCount < 4 {
		return false
	}
	// (1) Impossible pack size — self-contained, zero false-positive risk.
	if rowBPC > maxRealBottlesPerCase {
		return true
	}
	otherCases := sumCases - rowCases
	otherBottles := sumBottles - rowBottles
	// (2a) Hard exceeds — one row larger than all others combined (any ≥4 rows).
	if rowBottles > 0 && rowBottles > otherBottles {
		return true
	}
	if rowCases > 0 && rowCases > otherCases {
		return true
	}
	// (2b) Approximate total — one row ≥80% of all others combined. Gated to
	// ≥6 rows: only long (often multi-page) registers grow a footer-as-row,
	// and the higher row floor keeps a legitimately dominant line in a short
	// GP from being mistaken for the total.
	if rowCount >= 6 {
		if rowBottles > 0 && rowBottles*5 >= otherBottles*4 {
			return true
		}
		if rowCases > 0 && rowCases*5 >= otherCases*4 {
			return true
		}
	}
	return false
}

// normBrandKey lowercases brand text and strips everything but [a-z0-9] so two
// OCR reads of the same brand compare equal regardless of spacing/punctuation.
func normBrandKey(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// postProcessGPPrimaryRows applies the deterministic cleanup passes that turn
// raw per-GP-row matches into the final review list. PURE (no DB, no I/O) so
// it can be replayed against captured production extractions in tests:
//
//  1. garbage filter — drop literal "TOTAL"/"grandtotal" brand rows and fully
//     blank rows (v1.0.233).
//  2. footer-total guard — drop the row whose case/bottle count exceeds all
//     other rows combined (v1.0.330; the OCR'd gate-pass grand-total line).
//  3. trailing duplicate-row guard — drop the LAST row when it is an exact twin
//     of the row before it (v1.0.335; the footer total mis-OCR'd as a small,
//     plausible quantity that the magnitude guard can't see).
//  4. mis-bound duplicate guard — when >1 row binds the same product, keep the
//     strongest match and unbind the rest if their brand text clearly differs
//     (v1.0.332), routing them to operator review instead of silently stacking
//     stock onto the wrong product.
//  5. renumber rows contiguously so Flutter shows no gaps.
func postProcessGPPrimaryRows(out []SmartPurchaseExtractedItem) []SmartPurchaseExtractedItem {
	beforeFilter := len(out)
	filtered := out[:0]
	dropped := 0

	// Column totals across ALL rows, for the footer-total plausibility check.
	var sumCases, sumBottles int
	for _, it := range out {
		sumCases += it.QuantityRaw
		sumBottles += it.QuantityBottles
	}
	for _, it := range out {
		brandTrim := strings.TrimSpace(it.BrandName)
		brandLower := strings.ToLower(brandTrim)
		var normB strings.Builder
		for _, r := range brandLower {
			if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
				normB.WriteRune(r)
			}
		}
		bn := normB.String()
		isTotalRow := bn == "total" || bn == "grandtotal" || bn == "gtotal" || bn == "grtotal" ||
			strings.HasPrefix(bn, "grandtotal")
		if isTotalRow {
			log.Printf("[gp_primary] dropped TOTAL-row hallucination — brand=%q row=%d", brandTrim, it.RowNumber)
			dropped++
			continue
		}
		if isGPFooterTotalRow(it.QuantityRaw, it.QuantityBottles, it.BottlesPerCase, sumCases, sumBottles, len(out)) {
			log.Printf("[gp_primary] dropped footer-total row (qty exceeds all other rows combined) — brand=%q row=%d cases=%d bottles=%d (col totals: cases=%d bottles=%d)",
				brandTrim, it.RowNumber, it.QuantityRaw, it.QuantityBottles, sumCases, sumBottles)
			dropped++
			continue
		}
		isBlankRow := brandTrim == "" && it.SizeML == 0 && it.QuantityBottles == 0 &&
			it.QuantityRaw == 0 && it.RatePerBottle == 0 && it.DutyFee == 0
		if isBlankRow {
			log.Printf("[gp_primary] dropped blank row — row=%d", it.RowNumber)
			dropped++
			continue
		}
		filtered = append(filtered, it)
	}
	out = filtered

	// v1.0.335 — trailing duplicate-row guard (footer total mis-OCR'd small).
	// When the gate-pass "Total" footer row OCRs as a PLAUSIBLE small quantity
	// (e.g. 1 case / 12 btl) instead of the implausibly-large grand total, the
	// magnitude-based footer guard above can't see it — it arrives as the LAST
	// row, having bled the previous product's brand, identical in brand + size
	// + cases + bottles. Both rows then bind the same product and SUM at approve
	// (real FM Tower replay on v1.0.334: "M2 Magic Moments Jamun Spicymint
	// 750ml 12btl" emitted as rows 39 AND 40 → 24 instead of 12). We drop the
	// terminal row ONLY when it is an exact twin of the row immediately before
	// it — same normalized brand, size, cases AND bottles. That terminal-twin
	// shape is the footer-bleed fingerprint; a genuine two-line dispatch of one
	// SKU differs in quantity or is not the last row, so it stays bound and
	// sums as before.
	if n := len(out); n >= 2 {
		last, prev := out[n-1], out[n-2]
		lastKey := normBrandKey(last.BrandName)
		if last.QuantityBottles > 0 &&
			last.SizeML == prev.SizeML &&
			last.QuantityRaw == prev.QuantityRaw &&
			last.QuantityBottles == prev.QuantityBottles &&
			lastKey != "" && lastKey == normBrandKey(prev.BrandName) {
			log.Printf("[gp_primary] dropped trailing duplicate row (footer-bleed twin of prior line) — brand=%q size=%dml cases=%d bottles=%d",
				strings.TrimSpace(last.BrandName), last.SizeML, last.QuantityRaw, last.QuantityBottles)
			out = out[:n-1]
			dropped++
		}
	}

	// v1.0.361 — COMPLETENESS NET (general, every purchase). The gate pass's serial
	// is each line's identity; the final result must preserve every distinct serial
	// that is a real product line. Snapshot them BEFORE the duplicate-binding guard
	// (artifact rows — TOTAL/footer/blank/footer-bleed-twin — were already removed
	// above and are intentionally excluded). After the guard we re-add any distinct
	// serial it removed, so no real delivery line is ever silently dropped by this or
	// any future dedup heuristic — verified against the document itself, not a
	// per-bill rule.
	preDedupBySerial := make(map[int]SmartPurchaseExtractedItem, len(out))
	for _, it := range out {
		if it.RowNumber > 0 {
			if _, seen := preDedupBySerial[it.RowNumber]; !seen {
				preDedupBySerial[it.RowNumber] = it
			}
		}
	}

	// Duplicate-binding guard — collapses a SAME-serial double-read of one product;
	// UNBIND different-brand mis-matches (route to review/create); DROP a same-serial
	// duplicate extraction outright (summing would double-count). Unbind is done in
	// place first; the dropped indices are then filtered out (indices stay valid
	// because unbinding never removes elements).
	unbindIdx, dropIdx := classifyDuplicateBindings(out)
	for _, j := range unbindIdx {
		log.Printf("[gp_primary] unbound mis-matched duplicate — row=%d brand=%q was bound to product %v (another row matched it more strongly)",
			out[j].RowNumber, out[j].BrandName, derefStr(out[j].ProductID))
		out[j].ProductID = nil
		out[j].MatchedFullName = ""
		out[j].MatchedDisplayName = ""
		out[j].MatchedBrandName = ""
		out[j].Status = "not_found_suggest_create"
		out[j].NeedsReview = true
		out[j].ReviewReason = "Another row matched this product more strongly — confirm the correct product for this line"
		out[j].Warnings = append(out[j].Warnings, "duplicate_product_binding_unbound")
		zero := 0
		out[j].CurrentStock = &zero
	}
	if len(dropIdx) > 0 {
		dropSet := make(map[int]bool, len(dropIdx))
		for _, j := range dropIdx {
			dropSet[j] = true
			log.Printf("[gp_primary] dropped duplicate-product row (same product as a stronger row; a GP never repeats a product) — row=%d brand=%q product=%v cases=%d bottles=%d",
				out[j].RowNumber, strings.TrimSpace(out[j].BrandName), derefStr(out[j].ProductID), out[j].QuantityRaw, out[j].QuantityBottles)
			dropped++
		}
		kept := out[:0]
		for i := range out {
			if !dropSet[i] {
				kept = append(kept, out[i])
			}
		}
		out = kept
	}

	// COMPLETENESS NET — re-add any distinct gate-pass serial the duplicate-binding
	// guard removed. A guard may legitimately collapse a same-serial double-read, but
	// it must never make a DISTINCT serial (a real delivery line) vanish. Recovered
	// rows are flagged for review so nothing is ever silently lost — for any purchase.
	present := make(map[int]bool, len(out))
	for i := range out {
		present[out[i].RowNumber] = true
	}
	missing := make([]int, 0)
	for sn := range preDedupBySerial {
		if !present[sn] {
			missing = append(missing, sn)
		}
	}
	if len(missing) > 0 {
		sort.Ints(missing)
		for _, sn := range missing {
			rec := preDedupBySerial[sn]
			rec.NeedsReview = true
			rec.ReviewReason = "Line recovered — a duplicate guard dropped this gate-pass serial; confirm it belongs"
			rec.Warnings = append(rec.Warnings, "recovered_dropped_line")
			out = append(out, rec)
		}
		sort.SliceStable(out, func(i, j int) bool { return out[i].RowNumber < out[j].RowNumber })
		log.Printf("[gp_primary] completeness net: recovered %d dropped gate-pass line(s) (serials %v) — every real serial preserved", len(missing), missing)
	}

	// Renumber so positions are contiguous (Flutter renders RowNumber in the
	// review header; gaps would look like missing rows).
	for i := range out {
		out[i].RowNumber = i + 1
	}
	if dropped > 0 {
		log.Printf("[gp_primary] dropped %d garbage rows from %d (final: %d)", dropped, beforeFilter, len(out))
	}
	return out
}

// processGPPrimary produces v221 result items from the (gpItems, billItems)
// pair. Order of resulting items mirrors gpItems (GP is the skeleton).
//
// This function is read-only with respect to the DB except for two
// reads-with-side-effects in production deployment: the resolver may
// trigger Postgres planner caches, and selectBestProductForGPRow does
// SELECT only. No writes. Caller (ApplySmartPurchaseV221) handles the
// actual stock + product + alias mutations.
func (s *SmartPurchaseService) processGPPrimary(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	gpItems []GatePassDutyItem,
	billItems []ExtractedPurchaseItem,
) []SmartPurchaseExtractedItem {
	out := make([]SmartPurchaseExtractedItem, 0, len(gpItems))
	if len(gpItems) == 0 {
		log.Printf("[gp_primary] no GP items — returning empty result (caller should fall back to bill-primary)")
		return out
	}

	// Pre-fetch a DSE-register cache per size we'll need. Avoids N+1
	// queries when multiple GP rows share a size.
	dseCacheBySize := make(map[int]map[string]struct{})

	// v1.0.331 — catalog-identity bill pairing (Fix A).
	//
	// The bill↔GP price pairing previously relied ONLY on raw-string token
	// jaccard/overlap inside enrichBillCost. On real data that pairs poorly:
	// the gate pass prints the FULL excise canonical ("8 PM GOLD BLEND OF
	// SCOTCH & INDIAN GRAIN WHISKY") while the bill prints a clipped vendor
	// shorthand ("8pm Gold 375"). Token jaccard tanks on the length/word
	// asymmetry — FM Tower job 52714ffc paired only 19 of 37 rows, so >18
	// real lines shipped with no price.
	//
	// Both strings, however, resolve to the SAME master saas_brands.id via
	// the excise-canonical resolver. So we resolve every bill row to its
	// saas_brand_id ONCE here (M calls, memoised by text), then enrichBillCost
	// can pair on (saas_brand_id + size_ml) — a stable catalog identity —
	// before ever falling back to fuzzy text. Resolution is read-only.
	billBrandIDs := s.resolveBillSaasBrandIDs(ctx, billItems)

	// v1.0.342 — bill↔GP size cross-check. Closes the size-bleed gap that
	// reconcileGPDispatchBottles cannot: when the GP's Packaging Size cell
	// itself bled, trusting GP Size+Cases would compute the wrong bottles. The
	// BILL is the authoritative size source (machine-printed, read cleanly by
	// Textract Expense with no fragmentation/LLM-rescue, unlike the GP). Runs
	// BEFORE the row loop so corrected sizes/bottles flow into pairing + stock.
	s.crossCheckGPSizesAgainstBill(ctx, gpItems, billItems, billBrandIDs)

	for gpIdx, gp := range gpItems {
		row := s.buildGPPrimaryRow(ctx, tenantID, shopID, gpIdx, gp, billItems, billBrandIDs, dseCacheBySize)
		out = append(out, row)
	}

	out = postProcessGPPrimaryRows(out)

	// v1.0.378 — never ship a matched row at ₹0: estimate a realistic cost from
	// the same brand's other priced sizes in this purchase (chhotu: "realistic
	// cost not showing, ₹0").
	fillCostFromSiblingSizes(out)

	log.Printf("[gp_primary] produced %d rows from %d GP entries (bill had %d lines)",
		len(out), len(gpItems), len(billItems))
	return out
}

// decideGPSizeCorrection is the pure decision behind crossCheckGPSizesAgainstBill
// (extracted for testability — no DB). Given the GP row's size, cases, and the
// set of sizes the bill carries for the SAME master brand, it returns the action:
//
//	"none"      → leave the row untouched. Returned when: cases≤0, non-standard
//	              GP size, the row is INTERNALLY CLEAN (rawBottles == cases×bpc of
//	              the GP size — size+bottles already agree, so never second-guess
//	              a correctly-extracted row), the brand is absent from the bill,
//	              or the GP size is confirmed by the bill.
//	"correct"   → the row is internally broken (rawBottles ≠ cases×bpc(gpSize)),
//	              the GP size is NOT on the bill, and the raw dispatched bottles
//	              fit EXACTLY ONE bill size (cases×bpc) — positive size-bleed
//	              evidence. newSize/newBottles are the bill-authoritative values.
//	"ambiguous" → broken + GP size off-bill but no unique bill size fits the raw
//	              bottles — caller warns + keeps (won't guess).
//
// rawBottles is the as-extracted dispatched count (GatePassDutyItem.RawBottles),
// NOT the reconcile-rewritten Bottles — reconcile forces consistency with the
// GP size, which would erase the very signal this needs.
func decideGPSizeCorrection(gpSizeML, cases, rawBottles int, billSizes map[int]bool) (newSize, newBottles int, action string) {
	if cases <= 0 {
		return 0, 0, "none"
	}
	gpBpc, known := StandardCaseSizes[gpSizeML]
	if !known {
		return 0, 0, "none"
	}
	if rawBottles == cases*gpBpc {
		return 0, 0, "none" // clean row — GP size and bottles agree, never touch
	}
	if len(billSizes) == 0 || billSizes[gpSizeML] {
		return 0, 0, "none" // brand absent from bill, or GP size confirmed by bill
	}
	// Broken row + GP size off-bill: adopt the unique bill size whose full case
	// equals the raw dispatched bottles.
	fitSize, fits := 0, 0
	for sz := range billSizes {
		if rawBottles > 0 && rawBottles == cases*StandardCaseSizes[sz] {
			fitSize = sz
			fits++
		}
	}
	if fits == 1 {
		return fitSize, cases * StandardCaseSizes[fitSize], "correct"
	}
	return 0, 0, "ambiguous"
}

// crossCheckGPSizesAgainstBill validates each GP row's Packaging Size against
// the bill and corrects a bled GP size in place. v1.0.342.
//
// reconcileGPDispatchBottles (gate_pass.go) trusts the GP's Size+Cases columns
// to fix a bled BOTTLES cell — correct when the size is right (the verified
// 90ml Royal Stag case). But a genuine SIZE bleed (e.g. a 750ml row mis-read as
// 180ml with a correct 12 bottles) is internally indistinguishable from a
// bottle bleed, so trusting GP size would wrongly inflate bottles. The bill
// breaks the tie: it carries the same SKUs at their true sizes and reads
// cleanly via Textract Expense (no fragmentation/LLM-rescue that the GP needs).
//
// Rule (conservative — only acts on an unambiguous bill):
//   - resolve each GP row to its master saas_brand_id (memoised, read-only),
//   - if the GP's (known standard) size is NOT among the bill's sizes for that
//     brand AND the bill carries EXACTLY ONE size for it → adopt the bill size
//     and recompute dispatched bottles = cases × bpc(billSize).
//   - GP size already on the bill → consistent, untouched.
//   - bill has multiple sizes for the brand and none match → ambiguous, warn+keep.
//
// Gated by SMART_PURCHASE_GP_BILL_SIZE_CROSSCHECK (default on; "0" disables).
func (s *SmartPurchaseService) crossCheckGPSizesAgainstBill(
	ctx context.Context,
	gpItems []GatePassDutyItem,
	billItems []ExtractedPurchaseItem,
	billBrandIDs []uuid.UUID,
) int {
	if os.Getenv("SMART_PURCHASE_GP_BILL_SIZE_CROSSCHECK") == "0" {
		return 0
	}
	if len(billBrandIDs) != len(billItems) {
		return 0 // resolver bailed — no reliable bill identities to check against
	}

	// master brand id → set of standard sizes present on the bill
	billSizes := make(map[uuid.UUID]map[int]bool)
	for i, b := range billItems {
		id := billBrandIDs[i]
		if id == uuid.Nil {
			continue
		}
		ml := int(b.SizeML)
		if ml == 0 {
			ml = parseBillSizeML(b.SizeText)
		}
		if _, ok := StandardCaseSizes[ml]; !ok {
			continue
		}
		if billSizes[id] == nil {
			billSizes[id] = make(map[int]bool)
		}
		billSizes[id][ml] = true
	}
	if len(billSizes) == 0 {
		return 0
	}

	tx := s.db.WithContext(ctx)
	memo := make(map[string]uuid.UUID)
	fixed := 0
	for i := range gpItems {
		gp := &gpItems[i]
		if gp.Cases <= 0 {
			continue
		}
		if gp.SizeBleedSuspect {
			// v1.0.370 — size already reconstructed from the column-bleed swap
			// (LLM-corroborated). The bill is the very source that agrees with the
			// WRONG value here (its OCR also misreads the size), so it must NOT be
			// allowed to "correct" the repaired size back. Leave it.
			continue
		}
		if _, known := StandardCaseSizes[gp.SizeML]; !known {
			continue // size=0 / non-standard — resolveGPSizeML handles those
		}
		canon := strings.TrimSpace(gp.BrandName)
		if canon == "" {
			continue
		}
		key := strings.ToLower(canon)
		id, seen := memo[key]
		if !seen {
			m := s.resolveSaasBrandByGPCanonical(tx, canon)
			id = uuid.Nil
			if m.SaasBrandID != uuid.Nil && m.Confidence >= 0.70 {
				id = m.SaasBrandID
			}
			memo[key] = id
		}
		if id == uuid.Nil {
			continue
		}
		rawB := gp.RawBottles
		if rawB == 0 {
			rawB = gp.Bottles // pre-v342 path that didn't snapshot — fall back
		}
		newSize, newBottles, action := decideGPSizeCorrection(gp.SizeML, gp.Cases, rawB, billSizes[id])
		switch action {
		case "correct":
			log.Printf("  GP size cross-check: %s GP size %dml→%dml (bill authoritative); bottles %d→%d (%d×%d/case)",
				gp.BrandName, gp.SizeML, newSize, gp.Bottles, newBottles, gp.Cases, StandardCaseSizes[newSize])
			gp.SizeML = newSize
			gp.Bottles = newBottles
			fixed++
		case "ambiguous":
			billList := make([]int, 0, len(billSizes[id]))
			for sz := range billSizes[id] {
				billList = append(billList, sz)
			}
			log.Printf("  GP size cross-check: WARN %s GP size=%dml absent from bill sizes %v — ambiguous, kept",
				gp.BrandName, gp.SizeML, billList)
		}
	}
	if fixed > 0 {
		log.Printf("SmartPurchase GP: bill cross-check corrected size on %d GP row(s)", fixed)
	}
	return fixed
}

// buildGPPrimaryRow runs the full per-row pipeline:
//   1. Resolve GP brand → saas_brand_id
//   2. Find best tenant product (strict + tiebreaker)
//   3. If no tenant product, decide onboarding path
//   4. Match bill row by canonical name + size for cost
//   5. Compute per-bottle cost + duty
//   6. Cross-check against DSE register, surface mismatch warning
//   7. Assemble SmartPurchaseExtractedItem
func (s *SmartPurchaseService) buildGPPrimaryRow(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	gpIdx int,
	gp GatePassDutyItem,
	billItems []ExtractedPurchaseItem,
	billBrandIDs []uuid.UUID,
	dseCacheBySize map[int]map[string]struct{},
) SmartPurchaseExtractedItem {
	tx := s.db.WithContext(ctx)
	gpCanonical := strings.TrimSpace(gp.BrandName)

	// v1.0.225 — robust size_ml resolution.
	//
	// Textract's AnalyzeExpense often fails to surface the GP's "Packaging
	// Size" column as a labeled field — the size value lands in an unlabeled
	// OTHER bucket and gets dropped in mapGatePassExpense. The downstream
	// effect was catastrophic on chhotu's 11 May test: every row had
	// size_ml=0 → tenant product match returned 0 → all 36 rows flagged
	// ask_past_purchase. Fixed here with a 4-tier fallback chain so the
	// orchestrator never sees a zero size when bottles+cases are known.
	sizeML := resolveGPSizeML(gp)
	sizeText := gp.Size
	if sizeML > 0 && (sizeText == "" || sizeText == "0ML" || sizeText == "0") {
		// Replace the bogus "0ML" with the inferred numeric size so the UI
		// renders "750ml" instead of "0ML".
		sizeText = fmt.Sprintf("%dml", sizeML)
	}

	item := SmartPurchaseExtractedItem{
		RowNumber:        gpIdx + 1,
		BrandName:        gpCanonical,
		CanonicalBrand:   gpCanonical,
		CanonicalSource:  "gate_pass",
		Size:             sizeText,
		SizeML:           sizeML,
		GatePassBrand:    gpCanonical,
		QuantityRaw:      gp.Cases,
		QuantityUnit:     "cases",
		BottlesPerCase:   bottlesPerCaseFromGP(gp),
		QuantityBottles:  gp.Bottles,
		DutyFee:          gp.DutyFee,
		ResolutionSource: "gate_pass",
	}

	if gp.Bottles > 0 {
		item.DutyPerBottle = gp.DutyFee / float64(gp.Bottles)
	}

	// v1.0.343 — surface our OWN auto-corrections. When reconcileGPDispatchBottles
	// or crossCheckGPSizesAgainstBill changed the dispatched count (RawBottles is
	// the as-extracted value, Bottles the corrected one), the row is right but we
	// GUESSED — so flag it for a one-tap operator confirm instead of shipping the
	// change silently. This is the "flag-don't-guess" rule applied to our fixes:
	// the verified 90ml Royal Stag case (48→96) now appears on the review screen.
	if gp.RawBottles > 0 && gp.RawBottles != gp.Bottles {
		item.QuantityFlagged = true
		item.NeedsReview = true
		if item.ReviewReason == "" {
			item.ReviewReason = fmt.Sprintf("Auto-corrected dispatched bottles %d→%d (%d cases × %d/case) — please confirm",
				gp.RawBottles, gp.Bottles, gp.Cases, item.BottlesPerCase)
		}
		item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
			Kind:          "quantity_auto_corrected",
			Severity:      "warn",
			BillValue:     fmt.Sprintf("extracted %d", gp.RawBottles),
			GatePassValue: fmt.Sprintf("corrected %d", gp.Bottles),
			Detail:        fmt.Sprintf("%d cases × %d/case", gp.Cases, item.BottlesPerCase),
		})
	}

	// v1.0.370 — size-bleed repair touched this row (Packaging Size column was
	// crossed with an adjacent row). Whether auto-corrected or only flagged, the
	// size is no longer something we read cleanly — surface it for a one-tap
	// operator confirm rather than ship it silently ("flag-don't-guess").
	if gp.SizeBleedSuspect {
		item.NeedsReview = true
		// v1.0.372 — truthful, outcome-specific message. The old text always said
		// "re-derived to Xml", which lied for rows that were only FLAGGED (their
		// size was never changed). Three cases:
		switch {
		case gp.SizeBleedCorrected:
			// Size was actually corrected by the deterministic adjacent swap.
			if item.ReviewReason == "" {
				item.ReviewReason = fmt.Sprintf("Size column was misaligned on the gate pass and corrected to %dml — please confirm the size", sizeML)
			}
			item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
				Kind:          "size_bleed_corrected",
				Severity:      "warn",
				GatePassValue: fmt.Sprintf("%dml", sizeML),
				Detail:        "packaging-size column crossed with an adjacent row; corrected by deterministic swap + LLM-corroborated",
			})
		case gp.SizeAltML > 0:
			// Could not safely auto-pick — surface BOTH candidate sizes so the
			// operator resolves it in one tap instead of guessing.
			if item.ReviewReason == "" {
				item.ReviewReason = fmt.Sprintf("Size could not be read reliably — the gate pass reads %dml but an alternate reading is %dml; please confirm the size", sizeML, gp.SizeAltML)
			}
			item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
				Kind:          "size_uncertain",
				Severity:      "warn",
				GatePassValue: fmt.Sprintf("%dml", sizeML),
				Detail:        fmt.Sprintf("two reads disagree on the packaging size (%dml vs %dml); needs operator confirmation", sizeML, gp.SizeAltML),
			})
		default:
			if item.ReviewReason == "" {
				item.ReviewReason = fmt.Sprintf("Size column may be misaligned on the gate pass (read %dml) — please confirm the size", sizeML)
			}
			item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
				Kind:          "size_uncertain",
				Severity:      "warn",
				GatePassValue: fmt.Sprintf("%dml", sizeML),
				Detail:        "packaging-size column may have crossed with an adjacent row",
			})
		}
		item.Warnings = append(item.Warnings, "size_column_bleed_repaired")
	}

	// Tier 1 — GP → saas_brand_id resolution.
	brandMatch := s.resolveSaasBrandByGPCanonical(tx, gpCanonical)
	if brandMatch.SaasBrandID == uuid.Nil {
		// Cannot resolve to master at all → fully-new path; operator must
		// type details. Rare with the 5-tier cascade on real data.
		item.Status = "not_found_suggest_create"
		item.OnboardingTier = "fully_new"
		item.NeedsReview = true
		item.ReviewReason = "GP canonical name not found in master catalog"
		item.Warnings = append(item.Warnings, "no_master_catalog_match")
		s.enrichBillCost(&item, billItems, gpCanonical, sizeML, 0, brandMatch.SaasBrandID, billBrandIDs)
		return item
	}

	// Tier 2 — strict tenant product match by saas_brand_id + size_ml.
	picked, err := s.selectBestProductForGPRow(tx, tenantID, shopID, brandMatch.SaasBrandID, sizeML, gpCanonical, shopIsolationEnabled(ctx), identityEngineFromCtx(ctx))
	if err != nil {
		log.Printf("[gp_primary] row %d selectBestProductForGPRow error: %v", gpIdx+1, err)
	}

	if picked != nil && picked.WinnerID != uuid.Nil {
		pidStr := picked.WinnerID.String()
		item.ProductID = &pidStr
		item.MatchedFullName = picked.WinnerName
		item.MatchedDisplayName = picked.WinnerName
		item.MatchedBrandName = picked.WinnerName
		item.MatchedExciseBrandName = brandMatch.CanonicalName
		item.MatchConfidence = brandMatch.Confidence
		item.Status = "matched"
		curr := picked.WinnerQty
		item.CurrentStock = &curr

		// WS-B (v1.0.366) — the product was found by the variant-safe name+size
		// REUSE fallback, i.e. it exists in this shop but is MISLINKED to the
		// wrong master saas_brand. Reuse it (no duplicate created) and flag a
		// one-tap link-repair: the GP resolved to brandMatch.SaasBrandID, the
		// product carries a different link. Read-only here; the actual re-link is
		// an operator-confirmed apply action / WS-C remediation.
		if picked.ReusedByName {
			item.NeedsReview = true
			item.Warnings = append(item.Warnings, "reused_mislinked_product")
			if item.ReviewReason == "" {
				item.ReviewReason = fmt.Sprintf("Reused existing shop stock %q (qty %d) matched by name — its catalog link looks wrong; confirm and we'll re-link to %q",
					picked.WinnerName, picked.WinnerQty, brandMatch.CanonicalName)
			}
			item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
				Kind:          "catalog_link_repair",
				Severity:      "warn",
				GatePassValue: brandMatch.CanonicalName,
				Detail:        fmt.Sprintf("reused product %s by name+size (jaccard %.2f)", picked.WinnerID, picked.ReuseScore),
			})
		}

		// WS-D (v1.0.367) — catalog-link consistency net. A STRICT saas_brand+size
		// match can still bind a product whose NAME is a different variant of the
		// same family (a latent mislink that WS-C's exact-name pass didn't cover,
		// e.g. saas_brand shared but name says a different edition). If the bound
		// product's name is variant-INCONSISTENT with the GP canonical (token
		// jaccard < 0.5), surface it for review instead of silently trusting the
		// link. Skips the reuse path (already flagged) and gates on the engine.
		if identityEngineFromCtx(ctx) && !picked.ReusedByName {
			// The precise mislink signal is the bound product's NAME vs the master
			// it is linked to (== the GP-resolved master, since this is a strict
			// saas_brand match). A correct link scores ≈1.0 (the product name is the
			// master's canonical); a variant-mislink scores ~0.50 (Premium-named
			// product linked to the Fine & Rare master). The 0.70 floor cleanly
			// separates the two (measured on real pairs: correct ≈1.0, mislink
			// 0.50–0.57) without flagging legitimate close variants.
			masterName := brandMatch.CanonicalName
			// Robust, threshold-free mislink signal: the bound product and the
			// master it is linked to denote DIFFERENT variants (each has a
			// distinctive word the other lacks) — e.g. a "Premium"-named product
			// linked to the "Fine & Rare" master. Catches one-word-apart variants
			// that a jaccard threshold would miss.
			if masterName != "" && variantConflict(picked.WinnerName, masterName) {
				item.NeedsReview = true
				item.Warnings = append(item.Warnings, "catalog_link_inconsistent")
				if item.ReviewReason == "" {
					item.ReviewReason = fmt.Sprintf("Product %q is linked to catalog brand %q but they look like different variants — please confirm the link",
						picked.WinnerName, masterName)
				}
				item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
					Kind:          "catalog_link_inconsistent",
					Severity:      "warn",
					GatePassValue: masterName,
					Detail:        fmt.Sprintf("product %q vs master %q are different variants", picked.WinnerName, masterName),
				})
				log.Printf("[gp_primary] WS-D catalog-link inconsistency: product %q linked to master %q (variant conflict) — flagged for review", picked.WinnerName, masterName)
			}
		}

		if len(picked.LoserIDs) > 0 {
			item.Warnings = append(item.Warnings, fmt.Sprintf("duplicate_products_collapsed_%d", len(picked.LoserIDs)))
		}
		if picked.Ambiguous {
			item.Warnings = append(item.Warnings, "ambiguous_two_rows_with_stock")
			item.NeedsReview = true
		}
		// v1.0.240 — fetch master MRP for the loose-dispatch salvage in enrichBillCost.
		tier2MRP, _ := s.fetchMasterVariantMRPCategory(tx, brandMatch.SaasBrandID, sizeML)
		s.enrichBillCost(&item, billItems, gpCanonical, sizeML, tier2MRP, brandMatch.SaasBrandID, billBrandIDs)
		return item
	}

	// Tier 3 — no tenant product → onboarding path. v1.0.222 — pass the
	// per-request DSE cache so a 60-row bill with 4 distinct sizes hits the
	// DB 4 times instead of 60.
	decision, dseHit, decErr := s.decideOnboardingPath(tx, tenantID, shopID, gpCanonical, sizeML, brandMatch, dseCacheBySize)
	if decErr != nil {
		log.Printf("[gp_primary] row %d decideOnboardingPath error: %v", gpIdx+1, decErr)
	}
	// v1.0.233 — every onboarding-path row gets a real `CurrentStock=0` instead
	// of nil. Without this, the Flutter review-row's opening cell rendered "—"
	// for never-onboarded brands, looking like a bug to chhotu ("opening not
	// showing for half the rows!"). Zero is the truthful answer for a SKU
	// the shop has never stocked.
	zeroStock := 0
	switch decision {
	case OnboardingAutoFromMaster:
		item.Status = "matched"
		item.OnboardingTier = "master_create_shop_product"
		item.MatchedExciseBrandName = brandMatch.CanonicalName
		item.MatchConfidence = brandMatch.Confidence
		item.Warnings = append(item.Warnings, "auto_onboard_from_master")
		item.CurrentStock = &zeroStock
		mrp, category := s.fetchMasterVariantMRPCategory(tx, brandMatch.SaasBrandID, sizeML)
		item.OnboardingPayload = &OnboardingPayload{
			MasterSaaSBrandID:  brandMatch.SaasBrandID.String(),
			MasterDisplayName:  brandMatch.CanonicalName,
			MasterMRP:          mrp,
			MasterCategory:     category,
			SuggestedBrandName: brandMatch.CanonicalName,
			SuggestedSizeML:    sizeML,
		}
	case OnboardingSoftLinkFromDSE:
		item.Status = "matched"
		item.OnboardingTier = "master_create_shop_product"
		item.MatchedExciseBrandName = brandMatch.CanonicalName
		item.MatchConfidence = brandMatch.Confidence
		hint := strings.Join(dseHit.Matches, ", ")
		item.Warnings = append(item.Warnings, fmt.Sprintf("soft_link_from_dse:%s", hint))
		item.CurrentStock = &zeroStock
		mrp, category := s.fetchMasterVariantMRPCategory(tx, brandMatch.SaasBrandID, sizeML)
		item.OnboardingPayload = &OnboardingPayload{
			MasterSaaSBrandID:  brandMatch.SaasBrandID.String(),
			MasterDisplayName:  brandMatch.CanonicalName,
			MasterMRP:          mrp,
			MasterCategory:     category,
			SuggestedBrandName: brandMatch.CanonicalName,
			SuggestedSizeML:    sizeML,
		}
	case OnboardingAskPastPurchase:
		item.Status = "not_found_suggest_create"
		item.OnboardingTier = "fully_new"
		item.NeedsReview = true
		item.ReviewReason = "Tenant has no products row + DSE register has no match — upload past purchase or confirm new SKU"
		item.Warnings = append(item.Warnings, "ask_past_purchase")
		item.CurrentStock = &zeroStock
		item.OnboardingPayload = &OnboardingPayload{
			SuggestedBrandName: gpCanonical,
			SuggestedSizeML:    sizeML,
		}
	}
	// v1.0.240 — Tier-3 onboarding paths already fetched MRP into OnboardingPayload.
	var tier3MRP float64
	if item.OnboardingPayload != nil {
		tier3MRP = item.OnboardingPayload.MasterMRP
	}
	s.enrichBillCost(&item, billItems, gpCanonical, sizeML, tier3MRP, brandMatch.SaasBrandID, billBrandIDs)
	// v1.0.233 — patch BillCostPrice from the bill match (set by enrichBillCost).
	if item.OnboardingPayload != nil && item.RatePerBottle > 0 {
		item.OnboardingPayload.BillCostPrice = item.RatePerBottle
	}
	return item
}

// fetchMasterVariantMRPCategory looks up the per-size MRP + category name
// for a saas_brand. Returns (0,"") when the variant row is absent — that
// means the master catalog has the brand at *some* sizes but not this one;
// the operator will need to type MRP in the onboarding sheet.
//
// Used by v1.0.233 OnboardingPayload population so Flutter can render the
// "Create from catalog (₹X)" chip without a second roundtrip.
func (s *SmartPurchaseService) fetchMasterVariantMRPCategory(
	tx *gorm.DB, saasBrandID uuid.UUID, sizeML int,
) (mrp float64, category string) {
	if saasBrandID == uuid.Nil || sizeML == 0 {
		return 0, ""
	}
	sizeStr := fmt.Sprintf("%dML", sizeML)
	type row struct {
		MRP      float64 `gorm:"column:mrp"`
		Category string  `gorm:"column:category"`
	}
	var r row
	err := tx.Raw(`
		SELECT bv.mrp AS mrp, COALESCE(bc.name, '') AS category
		FROM brand_variants bv
		LEFT JOIN brand_categories bc ON bv.category_id = bc.id
		WHERE bv.deleted_at IS NULL
		  AND bv.brand_id = ?
		  AND UPPER(bv.size) = UPPER(?)
		LIMIT 1
	`, saasBrandID, sizeStr).Scan(&r).Error
	if err != nil {
		log.Printf("[gp_primary] fetchMasterVariantMRPCategory(%s, %dml): %v", saasBrandID, sizeML, err)
		return 0, ""
	}
	return r.MRP, r.Category
}

// enrichBillCost finds the bill row that matches this GP row and copies ONLY
// price-related fields (`RatePerBottle`, `RatePerCase`, `Amount`) onto the
// result item. Discards bill brand text, bill quantity, bill packing — those
// all come from the GP.
//
// v1.0.331 (Fix A) — pairing now runs in two passes:
//
//  1. Catalog-identity pass (preferred). When the GP row resolved to a master
//     saas_brand_id (gpSaasBrandID) we pair against the bill row(s) that
//     resolved to the SAME saas_brand_id (billBrandIDs[i]) at a matching
//     size. This is a stable join key that survives the bill's clipped
//     shorthand vs the GP's full excise canonical — the case raw-string
//     jaccard kept missing (FM Tower job 52714ffc: 19/37 → near-37/37).
//  2. Token-overlap fallback. Unchanged legacy behaviour for rows the
//     catalog pass can't resolve (bill text the resolver couldn't place, or
//     a GP row with no master brand).
//
// When no bill row matches (rare: GP-only row, depot ahead of invoicing),
// the item ships with `RatePerBottle=0` and `cost_missing` warning. The
// operator types the cost during review.
func (s *SmartPurchaseService) enrichBillCost(
	item *SmartPurchaseExtractedItem,
	billItems []ExtractedPurchaseItem,
	gpCanonical string,
	sizeML int,
	masterMRP float64,
	gpSaasBrandID uuid.UUID,
	billBrandIDs []uuid.UUID,
) {
	gpTokens := gpTokenSet(strings.ToLower(strings.TrimSpace(gpCanonical)))
	if len(gpTokens) == 0 {
		item.Warnings = append(item.Warnings, "cost_missing_gp_canonical_empty")
		return
	}

	bestScore := 0.0
	bestIdx := -1
	viaCatalogID := false

	// Pass 1 — catalog-identity. Restrict to bill rows that resolved to the
	// same master brand at a compatible size. Among those, prefer the closest
	// by token score (disambiguates the rare two-lines-same-brand-same-size
	// case); if none scores, the lone candidate still wins because the brand
	// id already proves identity.
	if gpSaasBrandID != uuid.Nil && len(billBrandIDs) == len(billItems) {
		catScore := -1.0
		catIdx := -1
		for i, b := range billItems {
			if billBrandIDs[i] == uuid.Nil || billBrandIDs[i] != gpSaasBrandID {
				continue
			}
			billML := int(b.SizeML)
			if billML == 0 {
				billML = parseBillSizeML(b.SizeText)
			}
			if billML != 0 && sizeML != 0 && billML != sizeML {
				continue // same brand, different size = different SKU
			}
			bTokens := gpTokenSet(strings.ToLower(strings.TrimSpace(b.Brand)))
			sc := maxF(jaccardTokens(gpTokens, bTokens), overlapCoeff(gpTokens, bTokens))
			if sc > catScore {
				catScore = sc
				catIdx = i
			}
		}
		if catIdx >= 0 {
			bestIdx = catIdx
			viaCatalogID = true
		}
	}

	// Pass 2 — token-overlap fallback (only when the catalog pass found nothing).
	for i, b := range billItems {
		if viaCatalogID {
			break
		}
		// Size gate first — cheap reject. b.SizeML is float64 in
		// ExtractedPurchaseItem; coerce to int for comparison.
		billML := int(b.SizeML)
		if billML == 0 {
			billML = parseBillSizeML(b.SizeText)
		}
		if billML != 0 && billML != sizeML {
			continue
		}
		// v1.0.225 — cross-extractor matching. Claude-extracted GP names are
		// FULL canonical ("AFTER DARK BLUE RARE GRAIN WHISKY") while Textract
		// bill brands are short/abbreviated ("After Dark Bl 750ml"). Score
		// jaccard against BOTH b.Brand and b.CanonicalBrand and keep the max
		// — whichever extractor gave us a closer string wins.
		//
		// v1.0.226-r1 — added overlap-coefficient parallel score. Same
		// rationale as the disambig matcher: jaccard punishes length
		// asymmetry between bill shorthand and GP canonical; overlap
		// rescues the subset case. Final = max(jaccard, overlap).
		bTokensA := gpTokenSet(strings.ToLower(strings.TrimSpace(b.Brand)))
		bTokensB := gpTokenSet(strings.ToLower(strings.TrimSpace(b.CanonicalBrand)))
		scoreA := maxF(jaccardTokens(gpTokens, bTokensA), overlapCoeff(gpTokens, bTokensA))
		scoreB := maxF(jaccardTokens(gpTokens, bTokensB), overlapCoeff(gpTokens, bTokensB))
		score := scoreA
		if scoreB > score {
			score = scoreB
		}
		// v1.0.226-r1 — variant-token guard. If GP carries variant tokens
		// (Barrel / Superior / Blue / Green Apple / etc.) AND the bill row
		// carries variant tokens TOO, require ≥1 in common — otherwise
		// brand-family neighbours (Royal Stag Superior vs Barrel) silently
		// swap cost data.
		gpVar := variantTokens(gpTokens)
		bVar := variantTokens(bTokensA)
		if len(bVar) == 0 {
			bVar = variantTokens(bTokensB)
		}
		if len(gpVar) > 0 && len(bVar) > 0 && !tokenSetsIntersect(gpVar, bVar) {
			continue // family match w/o variant agreement — skip this bill row
		}
		if score > bestScore {
			bestScore = score
			bestIdx = i
		}
	}
	// v1.0.225 — threshold lowered from 0.55 → 0.30. The size_ml gate already
	// rejects cross-size mismatches; within a size the bill rarely contains
	// two SKUs sharing 30% of canonical-brand tokens, so false positives are
	// rare. The lower bar lets the cost-enrichment match cross-extractor name
	// abbreviation differences (real-data: 25% → 80%+ enrichment rate).
	// The token-score floor only applies to Pass 2 matches; a Pass 1
	// catalog-identity match is already proven by the shared saas_brand_id
	// and is accepted regardless of how the clipped bill text scores.
	if bestIdx < 0 || (!viaCatalogID && bestScore < 0.30) {
		item.Warnings = append(item.Warnings, "cost_missing_no_bill_match")
		return
	}

	b := billItems[bestIdx]
	if item.QuantityBottles > 0 && b.Amount > 0 {
		item.RatePerBottle = b.Amount / float64(item.QuantityBottles)
	} else if b.RatePerBottle > 0 {
		item.RatePerBottle = b.RatePerBottle
	}
	if b.RatePerCase > 0 {
		item.RatePerCase = b.RatePerCase
	}
	if b.Amount > 0 {
		item.Amount = b.Amount
	}

	// v1.0.240 — LOOSE DISPATCH salvage. When the bill amount divided by
	// GP's bottles count gives an implausibly low per-bottle price (< 25%
	// of master MRP), the GP probably over-counted bottles (Claude defaulted
	// to cases × bpc instead of the literal printed count). Real-data:
	// chhotu's JW Black row 47 — GP printed "2 cases / 2 bottles" but Claude
	// returned bottles=24; bill row 60 "(2 Pcs)" annotation was dropped by
	// Textract. Without this salvage: ₹5815.20 / 24 = ₹242/bottle (absurd
	// for JW Black). With it: GP-bottles fallback to QuantityRaw (=2), giving
	// ₹5815.20 / 2 = ₹2907.60/bottle (real wholesale).
	if masterMRP > 0 && item.RatePerBottle > 0 && b.Amount > 0 &&
		item.QuantityRaw > 0 && item.QuantityBottles > item.QuantityRaw {
		ratio := item.RatePerBottle / masterMRP
		if ratio < 0.25 {
			// Try interpreting GP cases count as literal bottles.
			implied := b.Amount / float64(item.QuantityRaw)
			impliedRatio := implied / masterMRP
			if impliedRatio >= 0.25 && impliedRatio <= 2.0 {
				log.Printf("[gp_primary] LOOSE DISPATCH salvage — '%s' %dml: GP says %d bottles → ₹%.2f/btl (%.2fx MRP ₹%.0f, absurd). Treating GP cases=%d as literal bottle count → ₹%.2f/btl (%.2fx MRP). Adjusting.",
					item.BrandName, sizeML,
					item.QuantityBottles, item.RatePerBottle, ratio, masterMRP,
					item.QuantityRaw, implied, impliedRatio)
				item.QuantityBottles = item.QuantityRaw
				item.RatePerBottle = implied
				if item.QuantityBottles > 0 && item.DutyFee > 0 {
					item.DutyPerBottle = item.DutyFee / float64(item.QuantityBottles)
				}
				item.Warnings = append(item.Warnings, "loose_dispatch_inferred_via_mrp")
			}
		}
	}
	// v1.0.226 — GP is canonical. Bill's brand text is preserved in a
	// dedicated `BillOCRText` field for alias-teaching at apply time but
	// NEVER overwrites `item.BrandName` (which the Flutter UI reads to
	// display the brand). User decision: "GP brand name as priority, bill
	// name just for buying price."
	if b.Brand != "" && !strings.EqualFold(strings.TrimSpace(b.Brand), strings.TrimSpace(item.CanonicalBrand)) {
		item.BillOCRText = b.Brand
	}
	if b.BatchNumber != "" && item.BatchNumber == "" {
		item.BatchNumber = b.BatchNumber
	}
	if viaCatalogID {
		item.CostSource = "bill_catalog_id"
	} else {
		item.CostSource = "bill"
	}
}

// fillCostFromSiblingSizes — v1.0.378. A matched row whose bill line couldn't be
// paired (common when a multi-size brand has one size the bill OCR dropped — e.g.
// "Royal Stag Superior" billed at 90/180/750 but not 375) ships with
// RatePerBottle=0 → ₹0 on the review screen and a zero-cost stock entry. Instead,
// estimate a REALISTIC per-bottle cost from the SAME brand's other priced sizes in
// this very purchase: per-ml cost is near-constant across sizes of one product, so
// median(per-ml over siblings) × this size lands within a few % of the true bill
// price (validated on real data: 375 estimate ≈₹330 vs true ₹315). Flagged
// cost_source="sibling_estimate" + a warning so the operator sees it's an estimate
// and can edit. Kill-switch SMART_PURCHASE_COST_SIBLING_FALLBACK=0.
func fillCostFromSiblingSizes(rows []SmartPurchaseExtractedItem) {
	if v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_COST_SIBLING_FALLBACK")); v == "0" || strings.EqualFold(v, "false") {
		return
	}
	norm := func(s string) string { return strings.ToLower(strings.TrimSpace(s)) }
	byBrand := map[string][]float64{} // canonical brand → per-ml costs from priced rows
	for i := range rows {
		r := &rows[i]
		if r.RatePerBottle > 0 && r.SizeML > 0 {
			if k := norm(r.CanonicalBrand); k != "" {
				byBrand[k] = append(byBrand[k], r.RatePerBottle/float64(r.SizeML))
			}
		}
	}
	median := func(v []float64) float64 {
		if len(v) == 0 {
			return 0
		}
		s := append([]float64(nil), v...)
		sort.Float64s(s)
		n := len(s)
		if n%2 == 1 {
			return s[n/2]
		}
		return (s[n/2-1] + s[n/2]) / 2
	}
	filled := 0
	for i := range rows {
		r := &rows[i]
		if r.RatePerBottle > 0 || r.SizeML <= 0 || r.QuantityBottles <= 0 {
			continue
		}
		// Only estimate for rows the operator can actually buy now (matched to a
		// product). Not-found rows must be onboarded first; don't fabricate cost.
		if r.ProductID == nil && r.Status != "matched" {
			continue
		}
		perMl := median(byBrand[norm(r.CanonicalBrand)])
		if perMl <= 0 {
			continue
		}
		est := perMl * float64(r.SizeML)
		if est <= 0 {
			continue
		}
		r.RatePerBottle = float64(int(est*100+0.5)) / 100 // round to paise
		if r.BottlesPerCase > 0 {
			r.RatePerCase = r.RatePerBottle * float64(r.BottlesPerCase)
		}
		r.Amount = r.RatePerBottle * float64(r.QuantityBottles)
		r.CostSource = "sibling_estimate"
		r.Warnings = append(r.Warnings, "cost_estimated_from_sibling_size")
		filled++
		log.Printf("  GP cost fallback: %q %dml had no bill cost — estimated ₹%.2f/btl from same-brand sizes (per-ml median %.4f)",
			truncBrand(r.CanonicalBrand), r.SizeML, r.RatePerBottle, perMl)
	}
	if filled > 0 {
		log.Printf("SmartPurchase GP: filled %d zero-cost row(s) with realistic same-brand estimate", filled)
	}
}

// parseGPSizeML pulls the leading numeric ml out of a GP Size string. The
// excise PDF columns are reliably "180" / "750" / "90" — no suffix
// confusion. Falls back to the sizing package for edge cases.
func parseGPSizeML(s string) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	return sizing.ExtractML(s)
}

// parseBillSizeML normalises a bill's free-text size ("180ML", "180 ml",
// "180ML Pet") to numeric ml.
func parseBillSizeML(s string) int {
	return sizing.ExtractML(s)
}

// bottlesPerCaseFromGP infers pack size from GP's case/bottle counts.
// Returns 0 when either side is zero (caller should fall back to a
// per-size default).
func bottlesPerCaseFromGP(gp GatePassDutyItem) int {
	if gp.Cases <= 0 || gp.Bottles <= 0 {
		return 0
	}
	return gp.Bottles / gp.Cases
}

// resolveGPSizeML — v1.0.225 4-tier size resolution.
//
// Why this exists: Textract's AnalyzeExpense regularly drops the GP's
// "Packaging Size" column into an unlabeled OTHER bucket and the
// downstream mapper sets it to 0. Real-data: chhotu's 11 May job had
// size_ml=0 on 100% of rows, cascading to ALL rows being flagged
// ask_past_purchase + no cost enrichment + size="0ML" in the UI.
//
// Resolution order, first non-zero wins:
//   1. Direct gp.SizeML field (Textract column parse).
//   2. parseGPSizeML(gp.Size) — explicit size text from the GP.
//   3. Brand-text scan — many GP brand strings contain "Pet 180" or "750ml" suffix.
//   4. Pack-size ratio: bottles ÷ cases → standard size lookup
//      (12=750, 24=375, 48=180, 96=90).
func resolveGPSizeML(gp GatePassDutyItem) int {
	if gp.SizeML > 0 {
		return gp.SizeML
	}
	if v := parseGPSizeML(gp.Size); v > 0 {
		return v
	}
	if v := sizing.ExtractML(gp.BrandName); v > 0 {
		return v
	}
	if gp.Cases > 0 && gp.Bottles > 0 {
		btlPerCase := gp.Bottles / gp.Cases
		switch btlPerCase {
		case 12:
			return 750 // most common; 1000ml also 12/cs but rare in UP IMFL
		case 24:
			return 375
		case 48:
			return 180
		case 96:
			return 90
		case 6:
			return 1500 // imported premium; 6/cs is rare
		}
	}
	return 0
}

// maxF returns the larger of two float64s. Helper for v226-r1 hybrid
// (jaccard | overlap-coefficient) score blending in enrichBillCost.
func maxF(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}
