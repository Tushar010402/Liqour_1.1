package services

import (
	"context"
	"fmt"
	"log"
	"sort"
	"strings"

	"github.com/google/uuid"
)

// v1.0.222 — Past-purchase disambiguation.
//
// Closes the Row-23 class problem: tenant has 2+ products with the same
// (saas_brand_id, size_ml) but different flavour variants (Green Apple vs
// Orange). The GP canonical doesn't carry the flavour suffix so the v221
// tiebreaker can't distinguish.
//
// Flow: operator uploads a previous purchase bill that contains the same
// brand. We extract the brand text from that bill (which DOES carry the
// flavour suffix), resolve it to a saas_brand_id, pick the matching tenant
// product, and teach AliasService so the next bill at this shop resolves
// silently without an upload.

// DisambigResult is what the handler returns to Flutter.
//
// v1.0.238 — the Purcha gate was removed. PurchaQtyObserved + QtyMatchWithGP
// + GPExpectedQty fields are KEPT here for Flutter response-schema stability
// (old APKs may still read them) but populated values are no longer used by
// the apply payload (the four purcha_* fields on SmartPurchaseApplyItem are
// gone). The disambig endpoint itself remains useful for past-purchase
// variant disambiguation; only the Purcha-photo gate is removed.
type DisambigResult struct {
	ProductID         string  `json:"product_id"`
	ProductName       string  `json:"product_name"`
	BrandResolved     string  `json:"brand_resolved"`
	Confidence        float64 `json:"confidence"`
	Action            string  `json:"action"` // "resolved" | "no_match"
	AliasLearned      bool    `json:"alias_learned"`
	PurchaQtyObserved int     `json:"purcha_qty_observed,omitempty"`
	QtyMatchWithGP    *bool   `json:"qty_match_with_gp,omitempty"` // nil = unverified
	GPExpectedQty     int     `json:"gp_expected_qty,omitempty"`
}

// v1.0.223 batch disambig — one image, many rows resolved.
//
// Operator workflow: at size 180ml chhotu has 3 ambiguous rows (M2 Remix
// Green Apple / Orange / Pink). He uploads ONE past 180ml purchase that
// contains all three flavours. We extract once, run the per-row resolution
// loop against the cached extraction, and return a map keyed by row index.
//
// This collapses N camera-picker round trips into 1 per size bucket.

// DisambigQuery is one row that wants to be resolved from the shared image.
//
// v1.0.226 — added GPExpectedQty so the Purcha matcher can compare its
// extracted qty against what the GP claimed and flag mismatches. 0 means
// "don't verify qty" (e.g. legacy callers).
type DisambigQuery struct {
	RowIndex            int         `json:"row_index"`
	GPCanonical         string      `json:"gp_canonical"`
	SizeML              int         `json:"size_ml"`
	CandidateProductIDs []uuid.UUID `json:"candidate_product_ids,omitempty"`
	GPExpectedQty       int         `json:"gp_expected_qty,omitempty"`
}

// DisambigBatchResult lists one DisambigResult per input row, in the same
// order. Rows that could not be resolved come back with Action="no_match".
type DisambigBatchResult struct {
	Items          []DisambigBatchItem `json:"items"`
	ExtractedCount int                 `json:"extracted_count"` // brand lines extracted from image
	ResolvedCount  int                 `json:"resolved_count"`  // rows where Action=="resolved"
}

// DisambigBatchItem pairs the original row index with the resolution.
type DisambigBatchItem struct {
	RowIndex int             `json:"row_index"`
	Result   *DisambigResult `json:"result"`
}

// ResolveDisambigBatch — backwards-compatible wrapper for callers that
// still pass a single image. Internally delegates to
// ResolveDisambigBatchMulti with one page.
func (s *SmartPurchaseService) ResolveDisambigBatch(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	imageBytes []byte,
	contentType string,
	queries []DisambigQuery,
) (*DisambigBatchResult, error) {
	return s.ResolveDisambigBatchMulti(ctx, tenantID, shopID,
		[]DisambigPageInput{{Bytes: imageBytes, ContentType: contentType, Source: "image_0"}},
		queries)
}

// ResolveDisambigBatchMulti — v1.0.226 multi-image + multi-page version.
//
// Accepts N pages (raw image bytes — PDF rendering happens upstream in
// the handler via cv-sidecar /pdf-to-pages). Runs the Claude brand
// extractor once per page, unions the lines, then resolves each query
// against the unioned set. Per-page failures are skipped, not fatal.
//
// On Purcha-gate qty verification: when a query supplies GPExpectedQty,
// the matched Purcha line's bottle count is compared and QtyMatchWithGP
// is populated. The matcher uses ±1 bottle tolerance to absorb OCR drift.
func (s *SmartPurchaseService) ResolveDisambigBatchMulti(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	pages []DisambigPageInput,
	queries []DisambigQuery,
) (*DisambigBatchResult, error) {
	if len(pages) == 0 {
		return nil, fmt.Errorf("ResolveDisambigBatch: no pages")
	}
	if len(queries) == 0 {
		return nil, fmt.Errorf("ResolveDisambigBatch: no queries provided")
	}
	extraction, err := s.ocr.extractBrandsForDisambigMulti(ctx, pages)
	if err != nil {
		return nil, fmt.Errorf("past-purchase extraction failed: %w", err)
	}
	out := &DisambigBatchResult{
		Items: make([]DisambigBatchItem, 0, len(queries)),
	}
	if extraction == nil || len(extraction.Items) == 0 {
		for _, q := range queries {
			out.Items = append(out.Items, DisambigBatchItem{
				RowIndex: q.RowIndex,
				Result:   &DisambigResult{Action: "no_match"},
			})
		}
		return out, nil
	}
	out.ExtractedCount = len(extraction.Items)

	tx := s.db.WithContext(ctx)

	// v1.0.227-r1 — greedy 1-to-1 assignment with hybrid + fuzzy scoring.
	//
	// Pre-v227-r1 each query independently picked its best Purcha line,
	// which let ONE Purcha line "feed" multiple GP rows (Rockford Reserve
	// cross-talked to All Seasons + BPL Exclusive + Royal Challenge in
	// chhotu's real data). Now we score ALL (query, purcha_line) pairs,
	// sort by score desc, and walk pairs claiming the first unclaimed
	// query AND the first unclaimed Purcha line — so a Purcha line is
	// awarded to ONLY the best-scoring GP row.
	type candidate struct {
		qIdx, pIdx int
		score      float64
		brand      string
		qty        int
	}
	cands := make([]candidate, 0, len(queries)*4)

	for qi, q := range queries {
		gpCanonical := strings.TrimSpace(q.GPCanonical)
		if gpCanonical == "" || q.SizeML <= 0 {
			continue
		}
		gpTokens := gpTokenSet(strings.ToLower(gpCanonical))
		gpVariants := variantTokens(gpTokens)
		for pi, it := range extraction.Items {
			brand := strings.TrimSpace(it.CanonicalBrand)
			if brand == "" {
				brand = strings.TrimSpace(it.Brand)
			}
			if brand == "" {
				continue
			}
			lineSize := int(it.SizeML)
			if lineSize == 0 {
				lineSize = parseBillSizeML(it.SizeText)
			}
			if lineSize > 0 && lineSize != q.SizeML {
				continue
			}
			pTokens := gpTokenSet(strings.ToLower(brand))
			pVariants := variantTokens(pTokens)
			// Variant-token guard — refuse match when both carry variant
			// tokens but none in common (Royal Stag Superior vs Barrel).
			if len(gpVariants) > 0 && len(pVariants) > 0 {
				if !tokenSetsIntersect(gpVariants, pVariants) {
					continue
				}
			}
			// Hybrid score — jaccard | overlap | typo-aware overlap.
			//
			// typoOverlap counts each Purcha token that matches a GP
			// token EITHER exactly or via edit-distance ≤ 2 OR by
			// 3-char prefix. Rescues "Jamenson"↔"Jameson",
			// "Blendra"↔"Blenders", "Primiume"↔"Premium", "Mcd"↔"Mc Dowells".
			jacc := jaccardTokens(gpTokens, pTokens)
			over := overlapCoeff(gpTokens, pTokens)
			fuzz := fuzzyOverlap(gpTokens, pTokens)
			score := jacc
			if over > score {
				score = over
			}
			if fuzz > score {
				score = fuzz
			}
			if score < 0.40 {
				continue
			}
			cands = append(cands, candidate{
				qIdx: qi, pIdx: pi, score: score, brand: brand,
				qty: int(it.QuantityBottles),
			})
		}
	}
	// Sort by score descending — highest match wins the assignment.
	sort.Slice(cands, func(i, j int) bool { return cands[i].score > cands[j].score })

	claimedQ := make(map[int]bool, len(queries))
	claimedP := make(map[int]bool)
	type winner struct {
		score float64
		brand string
		qty   int
	}
	wins := make(map[int]winner, len(queries))
	for _, c := range cands {
		if claimedQ[c.qIdx] || claimedP[c.pIdx] {
			continue
		}
		claimedQ[c.qIdx] = true
		claimedP[c.pIdx] = true
		wins[c.qIdx] = winner{score: c.score, brand: c.brand, qty: c.qty}
	}

	for qi, q := range queries {
		gpCanonical := strings.TrimSpace(q.GPCanonical)
		if gpCanonical == "" || q.SizeML <= 0 {
			out.Items = append(out.Items, DisambigBatchItem{
				RowIndex: q.RowIndex,
				Result:   &DisambigResult{Action: "no_match"},
			})
			continue
		}
		w, ok := wins[qi]
		if !ok {
			out.Items = append(out.Items, DisambigBatchItem{
				RowIndex: q.RowIndex,
				Result:   &DisambigResult{Action: "no_match"},
			})
			continue
		}
		bestBrand := w.brand
		bestScore := w.score
		bestQty := w.qty
		_ = bestScore // keep alias logging below symmetrical
		brandMatch := s.resolveSaasBrandByGPCanonical(tx, bestBrand)
		if brandMatch.SaasBrandID == uuid.Nil {
			out.Items = append(out.Items, DisambigBatchItem{
				RowIndex: q.RowIndex,
				Result:   &DisambigResult{Action: "no_match", BrandResolved: bestBrand, Confidence: bestScore},
			})
			continue
		}
		picked, perr := s.selectBestProductForGPRow(tx, tenantID, shopID, brandMatch.SaasBrandID, q.SizeML, bestBrand, shopIsolationEnabled(ctx), identityEngineFromCtx(ctx))
		if perr != nil || picked == nil || picked.WinnerID == uuid.Nil {
			out.Items = append(out.Items, DisambigBatchItem{
				RowIndex: q.RowIndex,
				Result:   &DisambigResult{Action: "no_match", BrandResolved: bestBrand, Confidence: bestScore},
			})
			continue
		}
		// Refuse out-of-candidate-set resolutions when candidates supplied.
		if len(q.CandidateProductIDs) > 0 {
			within := false
			for _, c := range q.CandidateProductIDs {
				if c == picked.WinnerID {
					within = true
					break
				}
			}
			if !within {
				out.Items = append(out.Items, DisambigBatchItem{
					RowIndex: q.RowIndex,
					Result:   &DisambigResult{Action: "no_match", BrandResolved: bestBrand, Confidence: bestScore},
				})
				continue
			}
		}
		aliasLearned := false
		if s.aliasService != nil {
			pid := picked.WinnerID
			// v1.0.226-r2 — bidirectional alias capture, mirroring
			// Smart Sale's captureApplyLearning pattern. Three keys
			// learned per successful Purcha match:
			//   (1) gpCanonical → product   (existing; routes future GP
			//       canonical re-matches silently)
			//   (2) bestBrand → product     (Purcha's OCR text → product
			//       — when the same operator types "AD Blue 180" on Smart
			//       Sale next time it resolves without asking)
			//   (3) bestBrand → product (tenant-wide fallback when shop-
			//       scoped key already exists for another product)
			// Each LearnAliasScoped has its own hygiene guards
			// (<2-char block, alias==canonical block, jaccard<0.20
			// dirty-pair block) so noisy lines self-reject.
			if err := s.aliasService.LearnAliasScoped(tenantID, shopID, gpCanonical, picked.WinnerName, &pid, "smart_purchase_disambig_batch"); err == nil {
				aliasLearned = true
			} else {
				log.Printf("[disambig_batch] LearnAliasScoped (gp_canonical) failed for row %d: %v", q.RowIndex, err)
			}
			if bestBrand != "" && !strings.EqualFold(strings.TrimSpace(bestBrand), strings.TrimSpace(gpCanonical)) {
				if err := s.aliasService.LearnAliasScoped(tenantID, shopID, bestBrand, picked.WinnerName, &pid, "smart_purchase_disambig_batch_ocr"); err == nil {
					aliasLearned = true
				} else {
					log.Printf("[disambig_batch] LearnAliasScoped (purcha_ocr) failed for row %d: %v", q.RowIndex, err)
				}
				// Tenant-wide fallback so OTHER shops in the same
				// tenant pick up the alias when they see the same
				// operator-shorthand.
				if err := s.aliasService.LearnAlias(tenantID, bestBrand, picked.WinnerName, &pid, "smart_purchase_disambig_batch_tenant"); err != nil {
					log.Printf("[disambig_batch] LearnAlias (tenant fallback) failed for row %d: %v", q.RowIndex, err)
				}
			}
		}
		// v1.0.227-r1 — qty cross-check against the GP. ±1 bottle
		// tolerance absorbs OCR digit drift. Qty-parse-error guard:
		// when the Purcha qty came back as a tiny fraction of the GP
		// expected qty (< 30%), we treat it as "Claude couldn't read
		// the qty column on this row" rather than a real mismatch.
		// Real-data trigger: "100 Strokes Royal Whisky 180ml" Claude
		// returned qty=1 because the "1" came from "180" in the size
		// text. Without this guard a one-bottle false-positive lights
		// up a red qty-mismatch chip on a row that's actually fine.
		var qtyMatch *bool
		if q.GPExpectedQty > 0 && bestQty > 0 {
			// Treat as parse error (skip qty assertion entirely) when
			// Purcha qty is suspiciously small vs the GP.
			ratio := float64(bestQty) / float64(q.GPExpectedQty)
			if ratio < 0.30 {
				bestQty = 0 // emits qty_match=null instead of false
			} else {
				match := absInt(q.GPExpectedQty-bestQty) <= 1
				qtyMatch = &match
			}
		}
		out.Items = append(out.Items, DisambigBatchItem{
			RowIndex: q.RowIndex,
			Result: &DisambigResult{
				ProductID:         picked.WinnerID.String(),
				ProductName:       picked.WinnerName,
				BrandResolved:     bestBrand,
				Confidence:        bestScore,
				Action:            "resolved",
				AliasLearned:      aliasLearned,
				PurchaQtyObserved: bestQty,
				QtyMatchWithGP:    qtyMatch,
				GPExpectedQty:     q.GPExpectedQty,
			},
		})
		out.ResolvedCount++
	}
	log.Printf("[disambig_batch] resolved %d/%d queries from %d extracted lines", out.ResolvedCount, len(queries), out.ExtractedCount)
	return out, nil
}

// ResolveDisambigFromPastPurchase runs the full disambig pipeline.
//
// Args:
//   - imageBytes / contentType — the operator's uploaded past-purchase image
//   - gpCanonical — the ambiguous GP-canonical brand name (e.g. "M2 Magic
//     Moments Remix Superior")
//   - sizeML — the size from the current GP row
//   - candidateProductIDs — the duplicate tenant products that triggered the
//     ambiguity (the result of selectBestProductForGPRow with Ambiguous=true);
//     may be empty if the caller wants a free resolve
//
// Returns the picked product + whether the alias was successfully learned.
// On no match, Action="no_match" and ProductID="".
func (s *SmartPurchaseService) ResolveDisambigFromPastPurchase(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	imageBytes []byte,
	contentType string,
	gpCanonical string,
	sizeML int,
	candidateProductIDs []uuid.UUID,
) (*DisambigResult, error) {
	if len(imageBytes) == 0 {
		return nil, fmt.Errorf("ResolveDisambigFromPastPurchase: empty image")
	}
	if sizeML <= 0 {
		return nil, fmt.Errorf("ResolveDisambigFromPastPurchase: sizeML must be > 0")
	}
	gpCanonical = strings.TrimSpace(gpCanonical)
	if gpCanonical == "" {
		return nil, fmt.Errorf("ResolveDisambigFromPastPurchase: gpCanonical required")
	}

	// 1. Extract brands from the past-purchase image using the Claude
	// Sonnet 4.6 brand-only extractor (v1.0.224). Same accuracy bar Smart
	// Sale uses — tight prompt, single call, no cascade noise. Falls back
	// to ExtractFromImage internally if the Anthropic key is missing or
	// the Claude call fails.
	extraction, err := s.ocr.extractBrandsForDisambig(ctx, imageBytes, contentType)
	if err != nil {
		return nil, fmt.Errorf("past-purchase extraction failed: %w", err)
	}
	if extraction == nil || len(extraction.Items) == 0 {
		return &DisambigResult{Action: "no_match"}, nil
	}

	// 2. Find the line whose Brand best matches the ambiguous GP canonical
	// AND whose size aligns with sizeML. The past purchase will contain
	// many brands — we want the one the operator is disambiguating.
	gpTokens := gpTokenSet(strings.ToLower(gpCanonical))
	bestScore := 0.0
	bestBrand := ""
	for _, it := range extraction.Items {
		brand := strings.TrimSpace(it.CanonicalBrand)
		if brand == "" {
			brand = strings.TrimSpace(it.Brand)
		}
		if brand == "" {
			continue
		}
		// Soft size filter — accept any line within ±1 ml bucket. Past
		// purchase may have multiple sizes; we only want the matching one.
		lineSize := int(it.SizeML)
		if lineSize == 0 {
			lineSize = parseBillSizeML(it.SizeText)
		}
		if lineSize > 0 && lineSize != sizeML {
			continue
		}
		score := jaccardTokens(gpTokens, gpTokenSet(strings.ToLower(brand)))
		if score > bestScore {
			bestScore = score
			bestBrand = brand
		}
	}
	// Require token overlap ≥ 0.40 — the past-purchase brand should share
	// most root tokens with the GP canonical; the extra tokens carry the
	// flavour suffix we need.
	if bestBrand == "" || bestScore < 0.40 {
		log.Printf("[disambig] no past-purchase line matches gpCanonical=%q sizeML=%d (bestScore=%.2f)", gpCanonical, sizeML, bestScore)
		return &DisambigResult{Action: "no_match", Confidence: bestScore}, nil
	}

	log.Printf("[disambig] past-purchase resolved %q → %q (jaccard=%.2f, size=%dml)", gpCanonical, bestBrand, bestScore, sizeML)

	// 3. Resolve the disambiguated brand to a saas_brand_id via the same
	// 5-tier cascade used for the GP canonical.
	tx := s.db.WithContext(ctx)
	brandMatch := s.resolveSaasBrandByGPCanonical(tx, bestBrand)
	if brandMatch.SaasBrandID == uuid.Nil {
		log.Printf("[disambig] disambiguated brand %q has no saas_brand match", bestBrand)
		return &DisambigResult{Action: "no_match", BrandResolved: bestBrand, Confidence: bestScore}, nil
	}

	// 4. Pick the tenant product. If the caller passed candidates, prefer
	// one of those; otherwise run selectBestProductForGPRow normally.
	picked, err := s.selectBestProductForGPRow(tx, tenantID, shopID, brandMatch.SaasBrandID, sizeML, bestBrand, shopIsolationEnabled(ctx), identityEngineFromCtx(ctx))
	if err != nil || picked == nil || picked.WinnerID == uuid.Nil {
		log.Printf("[disambig] no tenant product for saas_brand=%s size=%dml: %v", brandMatch.SaasBrandID, sizeML, err)
		return &DisambigResult{Action: "no_match", BrandResolved: bestBrand, Confidence: bestScore}, nil
	}

	// If candidates were passed, refuse to resolve to a product outside the
	// candidate set — defensive against the past purchase pointing at a
	// completely different SKU than what was on the current GP row.
	if len(candidateProductIDs) > 0 {
		within := false
		for _, c := range candidateProductIDs {
			if c == picked.WinnerID {
				within = true
				break
			}
		}
		if !within {
			log.Printf("[disambig] picked product %s is outside candidate set %v — refusing", picked.WinnerID, candidateProductIDs)
			return &DisambigResult{Action: "no_match", BrandResolved: bestBrand, Confidence: bestScore}, nil
		}
	}

	// 5. Learn the alias so the next bill resolves silently. Source tag
	// "smart_purchase_disambig" lets us audit how many variant resolutions
	// were operator-uploaded vs auto.
	aliasLearned := false
	if s.aliasService != nil {
		pid := picked.WinnerID
		if err := s.aliasService.LearnAliasScoped(tenantID, shopID, gpCanonical, picked.WinnerName, &pid, "smart_purchase_disambig"); err != nil {
			log.Printf("[disambig] LearnAliasScoped failed: %v", err)
		} else {
			aliasLearned = true
		}
	}

	return &DisambigResult{
		ProductID:     picked.WinnerID.String(),
		ProductName:   picked.WinnerName,
		BrandResolved: bestBrand,
		Confidence:    bestScore,
		Action:        "resolved",
		AliasLearned:  aliasLearned,
	}, nil
}

// v1.0.226-r1 — token-similarity helpers for the disambig matcher.
//
// overlapCoeff returns intersection ÷ min(|A|, |B|) — favours subset
// relationships where one side is a shorter expression of the other.
// Range [0, 1]. Used alongside jaccard to rescue the realistic case
// where the operator's Purcha is much shorter than the GP canonical.
func overlapCoeff(a, b map[string]struct{}) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	min := len(a)
	if len(b) < min {
		min = len(b)
	}
	inter := 0
	for k := range a {
		if _, ok := b[k]; ok {
			inter++
		}
	}
	return float64(inter) / float64(min)
}

// variantTokens returns the subset of a token set that contains
// liquor-brand variant qualifiers — words that distinguish two SKUs in
// the same brand family. Tuned on chhotu real-data ambiguity classes:
//
//   • Royal Stag Superior ↔ Royal Stag Barrel
//   • Magic Moments Plain ↔ Green Apple ↔ Orange ↔ Pink
//   • Blenders Pride Reserve ↔ Exclusive Premium
//   • Black Dog Centenary ↔ Quintessential
//   • Imperial Blue Dual Cask ↔ Smooth Smoke ↔ Original
//
// When both sides of a match candidate carry variant tokens, the
// disambig matcher demands at least one variant in common; otherwise
// brand-family matches like "Royal Stag" can silently misroute stock
// onto the wrong SKU.
var brandVariantLexicon = map[string]struct{}{
	"barrel": {}, "superior": {}, "select": {}, "exclusive": {},
	"premium": {}, "reserve": {}, "rare": {}, "classic": {},
	"blue": {}, "black": {}, "red": {}, "green": {},
	"orange": {}, "apple": {}, "pink": {}, "white": {},
	"smooth": {}, "honey": {}, "spicymint": {}, "jamun": {},
	"centenary": {}, "quintessential": {}, "deluxe": {},
	"label": {}, "platinum": {}, "gold": {}, "silver": {},
	"tetra": {}, "international": {}, "dual": {}, "cask": {},
	"signature": {}, "celebration": {}, "edition": {},
	"remix": {}, "vintage": {}, "original": {},
}

func variantTokens(tokens map[string]struct{}) map[string]struct{} {
	out := make(map[string]struct{})
	for t := range tokens {
		if _, ok := brandVariantLexicon[t]; ok {
			out[t] = struct{}{}
		}
	}
	return out
}

func tokenSetsIntersect(a, b map[string]struct{}) bool {
	for k := range a {
		if _, ok := b[k]; ok {
			return true
		}
	}
	return false
}

// v1.0.227-r1 — typo-aware overlap scorer.
//
// Counts each Purcha token that matches a GP token EITHER exactly OR via
// edit-distance ≤ 2 OR by a 3-character prefix match. Returns
// matches ÷ min(|gp|, |purcha|).
//
// Real-data wins this enables (all previously scored < 0.40):
//   • "Jamenson Irish Whisky"      ↔ "JAMESON IRISH WHISKEY"        → 0.67
//   • "Blendra Pride Primiume"     ↔ "BLENDERS PRIDE PREMIUM"       → 0.67
//   • "Mcd Original Why"           ↔ "MC DOWELLS NO1 ORIGINAL"      → 0.50
func fuzzyOverlap(gp, purcha map[string]struct{}) float64 {
	if len(gp) == 0 || len(purcha) == 0 {
		return 0
	}
	matched := 0
	used := make(map[string]bool, len(purcha))
	for gt := range gp {
		// Exact pass first.
		if _, ok := purcha[gt]; ok && !used[gt] {
			used[gt] = true
			matched++
			continue
		}
		// Fuzzy pass — find a Purcha token that's edit-distance ≤2 or
		// a 3-char prefix match.
		for pt := range purcha {
			if used[pt] {
				continue
			}
			if isFuzzyTokenMatch(gt, pt) {
				used[pt] = true
				matched++
				break
			}
		}
	}
	min := len(gp)
	if len(purcha) < min {
		min = len(purcha)
	}
	return float64(matched) / float64(min)
}

// isFuzzyTokenMatch — true when two tokens are clearly the same word
// modulo OCR / handwriting drift. Used by fuzzyOverlap; keeps the search
// space tiny so the scorer stays O(n·m) on small token sets.
func isFuzzyTokenMatch(a, b string) bool {
	if a == b {
		return true
	}
	if len(a) < 3 || len(b) < 3 {
		return false // refuse single/double-char fuzz — too noisy
	}
	// 3-char prefix match catches "Mcd" ↔ "Mc Dowells" via "mcd"/"mcd"
	// (the matcher tokenizes "Mc" + "Dowells" but Purcha collapsed to
	// "Mcd"). Also catches "Primiume"/"Premium" via "pri"/"pre" — no,
	// that's "pri" vs "pre" first 3 chars differ. Use 4-char common
	// prefix instead, otherwise the false-positive surface is too wide.
	if len(a) >= 4 && len(b) >= 4 && a[:4] == b[:4] {
		return true
	}
	// Edit-distance ≤ 2 catches Jameson/Jamenson + Blenders/Blendra +
	// Premium/Primiume. Cap on length difference (don't pay the DP cost
	// when one string is twice the other).
	la, lb := len(a), len(b)
	if absInt(la-lb) > 2 {
		return false
	}
	return levenshteinLE2(a, b)
}

// levenshteinLE2 — true when edit distance between a and b is ≤ 2.
// Bounded DP: returns false as soon as the running minimum exceeds 2.
// Cheaper than computing the full distance when most pairs are far apart.
func levenshteinLE2(a, b string) bool {
	la, lb := len(a), len(b)
	if a == b {
		return true
	}
	if absInt(la-lb) > 2 {
		return false
	}
	// Standard 2-row DP, clamped at 2.
	prev := make([]int, lb+1)
	cur := make([]int, lb+1)
	for j := 0; j <= lb; j++ {
		prev[j] = j
	}
	for i := 1; i <= la; i++ {
		cur[0] = i
		rowMin := cur[0]
		for j := 1; j <= lb; j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			del := prev[j] + 1
			ins := cur[j-1] + 1
			sub := prev[j-1] + cost
			best := del
			if ins < best {
				best = ins
			}
			if sub < best {
				best = sub
			}
			cur[j] = best
			if best < rowMin {
				rowMin = best
			}
		}
		if rowMin > 2 {
			return false
		}
		prev, cur = cur, prev
	}
	return prev[lb] <= 2
}
