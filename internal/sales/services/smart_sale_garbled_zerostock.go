package services

import (
	"os"
	"regexp"
	"strings"
)

// v1.0.312 — close the "garbled OCR matched to a zero-stock product" loop.
//
// CONTEXT: chhotu's 180ml job 304e4e27 surfaced row 21 "M2 MAGIC MOMENTS J..."
// (OCR text "M4MJUM", a handwritten row at the bottom of page 2). The
// alias-cascade fuzzy tier resolved M4MJUM → M2 Magic Moments Jamun, a real
// catalog product at the tenant, but the shop has Opening=0 for that SKU.
// flagStockUnavailable correctly set NoStockBlock=true; the apply-time gate
// would refuse to persist it. But the row STILL appeared in the operator's
// review list, so the operator had to scroll, recognise the garbled match,
// and manually clear it on every job. The user's complaint: "we do not have
// stock why it's capturing this and why require a lot of manual task."
//
// FIX: when NoStockBlock fires AND the underlying match is suspect (fuzzy /
// short garbled OCR / digit-letter mix), drop the productID binding so the
// row falls into the existing "could not be matched and were skipped" bucket
// instead of cluttering the matched-rows list with red flags the operator
// must clear by hand.
//
// HIGH-CONFIDENCE matches (alias-cascade exact hits, MatchConfidence ≥ 0.85)
// are kept — the operator may legitimately want to receive stock for that
// SKU before recording the sale, so we keep the red NoStockBlock chip there.
//
// Gated by SMART_SALE_DROP_GARBLED_ZEROSTOCK (default ON). Disable per-
// tenant if a real "shop forgot to set up this SKU" case gets buried.

// dropGarbledZeroStockMatches walks validated items and, for each row whose
// flagStockUnavailable already marked NoStockBlock=true, decides whether the
// match itself is suspect. Suspect matches are unbound (ProductID cleared,
// BrandName reverted to the raw OCR text, validation_status flipped to
// not_found) so the row joins the unmatched-skipped bucket.
//
// Returns the count of rows demoted, for log+telemetry.
func (s *SmartSaleService) dropGarbledZeroStockMatches(items []SmartSaleExtractedItem) int {
	if !dropGarbledZeroStockEnabled() {
		return 0
	}
	dropped := 0
	for i := range items {
		it := &items[i]
		if !it.NoStockBlock {
			continue
		}
		if it.Quantity <= 0 {
			// Zero-qty rows aren't capturing a sale — leave them alone.
			continue
		}
		if it.ProductID == nil || *it.ProductID == "" {
			// Already unbound — nothing to drop.
			continue
		}
		// Skip operator-vouched / non-AI sources — those rows are explicit
		// operator picks and dropping them would be surprising.
		switch it.Source {
		case "operator_add", "manual_add", "user_correction":
			continue
		}
		if !isGarbledMatch(it) {
			continue
		}

		raw := strings.TrimSpace(it.OriginalAIBrand)
		if raw == "" {
			raw = strings.TrimSpace(it.OCRText)
		}
		// Preserve audit trail.
		if it.OriginalAIBrand == "" {
			it.OriginalAIBrand = it.BrandName
		}
		if raw != "" {
			it.BrandName = raw
		}
		it.ProductID = nil
		it.MatchedBrandName = ""
		it.MatchConfidence = 0
		it.ValidationStatus = "not_found"
		it.NoStockBlock = false
		it.NeedsReview = true
		it.ReviewReason = "garbled_ocr_no_stock"
		// Replace the no-stock-block warning with a clearer one so the
		// operator (or downstream UX rendering "X items could not be
		// matched") sees the right reason.
		it.Warnings = filterStockBlockWarnings(it.Warnings)
		it.Warnings = append(it.Warnings,
			"Garbled OCR — no matching shop stock; please pick the product manually or skip.")
		dropped++
	}
	if dropped > 0 {
		s.logger.Infof("SmartSale: dropped %d garbled-OCR + zero-stock matches to skipped bucket (v1.0.312 guard)", dropped)
	}
	return dropped
}

// dropGarbledZeroStockEnabled returns true unless explicitly disabled. Defaults
// ON because the failure mode (silent zero-stock match cluttering review) is
// strictly worse than the recovery (operator picks product from dropdown).
func dropGarbledZeroStockEnabled() bool {
	v := strings.TrimSpace(os.Getenv("SMART_SALE_DROP_GARBLED_ZEROSTOCK"))
	if v == "" {
		return true
	}
	return v != "0" && !strings.EqualFold(v, "false") && !strings.EqualFold(v, "off")
}

// isGarbledMatch returns true when the row's match looks like a fuzzy /
// low-confidence hit on a short / digit-letter-mix OCR string — the
// signature of chhotu's "M4MJUM → M2 Magic Moments Jamun" class.
//
// Heuristics (any one is enough):
//  1. MatchConfidence < 0.85   — fuzzy tier or low-trust matcher score
//  2. OriginalAIBrand length < 8 AND mixes digits + letters (M4MJUM, SM19Jum)
//  3. OriginalAIBrand differs wildly from BrandName (Jaccard < 0.25 on
//     letter-only tokens) — a short alias matched a long canonical name
func isGarbledMatch(it *SmartSaleExtractedItem) bool {
	if it.MatchConfidence > 0 && it.MatchConfidence < 0.85 {
		return true
	}
	raw := strings.TrimSpace(it.OriginalAIBrand)
	if raw == "" {
		raw = strings.TrimSpace(it.OCRText)
	}
	if raw == "" {
		return false
	}
	if len(raw) < 8 && hasDigitLetterMix(raw) {
		return true
	}
	if it.BrandName != "" && it.BrandName != raw {
		if letterJaccard(raw, it.BrandName) < 0.25 {
			return true
		}
	}
	return false
}

var digitLetterMixRe = regexp.MustCompile(`(?i)([a-z].*[0-9]|[0-9].*[a-z])`)

func hasDigitLetterMix(s string) bool {
	return digitLetterMixRe.MatchString(s)
}

// letterJaccard normalises both inputs to lowercase letter tokens (no digits,
// no punctuation), then returns intersect/union of the token sets.
func letterJaccard(a, b string) float64 {
	ta := letterTokens(a)
	tb := letterTokens(b)
	if len(ta) == 0 || len(tb) == 0 {
		return 0
	}
	setA := make(map[string]struct{}, len(ta))
	for _, t := range ta {
		setA[t] = struct{}{}
	}
	inter := 0
	seenB := make(map[string]struct{}, len(tb))
	for _, t := range tb {
		if _, dup := seenB[t]; dup {
			continue
		}
		seenB[t] = struct{}{}
		if _, ok := setA[t]; ok {
			inter++
		}
	}
	union := len(setA) + len(seenB) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

func letterTokens(s string) []string {
	out := make([]string, 0, 8)
	var cur strings.Builder
	for _, r := range strings.ToLower(s) {
		if r >= 'a' && r <= 'z' {
			cur.WriteRune(r)
			continue
		}
		if cur.Len() > 0 {
			out = append(out, cur.String())
			cur.Reset()
		}
	}
	if cur.Len() > 0 {
		out = append(out, cur.String())
	}
	return out
}

func filterStockBlockWarnings(ws []string) []string {
	out := ws[:0]
	for _, w := range ws {
		lw := strings.ToLower(w)
		if strings.Contains(lw, "shop stock is 0") ||
			strings.Contains(lw, "no stock at this shop") ||
			strings.Contains(lw, "cannot record sale") {
			continue
		}
		out = append(out, w)
	}
	return out
}
