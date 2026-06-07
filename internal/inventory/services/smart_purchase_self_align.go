package services

import (
	"errors"
	"fmt"
	"log"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// v1.0.221 self-align helpers — GP-primary Smart Purchase support module.
//
// Three operations the GP-primary apply path runs against every matched
// tenant product so the catalog converges to the official excise canonical
// naming over time. After enough GP-primary applies flow through, the
// tenant catalog at every shop aligns to the same canonical names used on
// excise gate passes, which means future Purchases / Sales / Stock-Setups
// land on the correct product row deterministically with no fuzzy guessing.
//
//   1. selectBestProductForGPRow — when ≥2 tenant `products` rows share the
//      same (saas_brand_id, size_ml), pick the deterministic winner.
//      Tiebreak: stock>0 first, then exact-name proximity to GP canonical,
//      then most-recent. Returns the loser ids so the caller can surface a
//      duplicate-row warning or run admin merge later.
//
//   2. promoteCanonicalName — overwrite `products.name` with the GP's
//      official excise Description. If `products.display_name` is currently
//      empty, save the OLD name there so operator-facing UI keeps showing
//      the short familiar label they're used to. No-op when names already
//      match (case + whitespace tolerant).
//
//   3. captureBillAliasFromGPMatch — record the bill row's raw OCR brand
//      text as an alias pointing to the canonical product. Reuses
//      AliasService's hygiene guards (jaccard ≥ 0.20, negative-alias block,
//      canonical-pollution refusal, identical-string skip). Cheap on
//      hygiene-rejected writes (returns nil), idempotent on existing pairs.
//
// All three are pure functions over (tx, ids, strings). Callers own the
// BEGIN/COMMIT boundary.

// SelectBestProductResult describes the winner + the losers (if any) of a
// duplicate-row tiebreaker. WinnerID is uuid.Nil when no candidates matched.
// Image→identity engine thresholds (v1.0.367). Named so they are explicit and
// locked by TestIdentityEngine_VariantPairsStaySeparated against real production
// variant pairs (Rockford Premium/Fine&Rare, M2 Green Apple/Superior, …).
const (
	// reuseNameJaccardFloor — WS-B reuse a mislinked existing product only when
	// its name is at least this token-similar to the GP canonical. Measured:
	// same variant ≈1.0; distinct same-family variants ≤0.57 — so 0.60 reuses the
	// right product and never a different variant.
	reuseNameJaccardFloor = 0.60
)

type SelectBestProductResult struct {
	WinnerID    uuid.UUID
	WinnerName  string
	WinnerQty   int
	LoserIDs    []uuid.UUID
	Ambiguous   bool   // true when ≥2 candidates both hold stock — operator may want a heads-up
	TiebreakLog string // human-readable summary for stock_histories.notes
	// WS-B (v1.0.366) — set when the winner was found via the variant-safe
	// name+size REUSE fallback (strict saas_brand match missed it). The product
	// is reused instead of duplicated; ReuseScore is the name jaccard. The
	// caller should flag it for a saas_brand link-repair + operator confirm.
	ReusedByName bool
	ReuseScore   float64
}

// variantFillers are generic category / packaging / grammar words that carry NO
// variant identity. Unlike gpStopwords (which drops "premium", "reserve", …),
// this KEEPS every variant-distinctive word so Premium / Fine & Rare / Exquisite
// / Deluxe / Green Apple / Superior stay comparable. Used only for variant
// conflict detection.
var variantFillers = map[string]struct{}{
	"the": {}, "a": {}, "an": {}, "and": {}, "of": {}, "for": {}, "with": {},
	"whisky": {}, "whiskey": {}, "vodka": {}, "rum": {}, "gin": {}, "brandy": {},
	"wine": {}, "beer": {}, "scotch": {}, "blended": {}, "blend": {}, "grain": {},
	"indian": {}, "international": {}, "intl": {}, "int": {}, "imported": {},
	"flavoured": {}, "flavored": {}, "edition": {}, "bottle": {}, "glass": {},
	"pet": {}, "tetra": {}, "pack": {}, "ml": {}, "litre": {}, "liter": {},
	"why": {}, "whi": {}, "wsk": {}, "vk": {}, "bld": {},
}

// variantTokenSet tokenizes a brand name keeping variant-distinctive words.
// Apostrophes are removed BEFORE splitting ("Seagram's" → "seagrams") and a
// trailing plural/possessive "s" is stripped from longer tokens ("seagrams" →
// "seagram", "pipers" → "piper") so punctuation and plurals never read as a
// variant difference. Variant words (premium, deluxe, finest, oak, …) are kept.
func variantTokenSet(s string) map[string]struct{} {
	s = strings.NewReplacer("'", "", "’", "", "`", "").Replace(strings.ToLower(s))
	out := make(map[string]struct{}, 8)
	for _, t := range strings.FieldsFunc(s, func(r rune) bool {
		return !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'))
	}) {
		if len(t) > 3 && strings.HasSuffix(t, "s") {
			t = t[:len(t)-1] // light stem: seagrams→seagram, pipers→piper
		}
		if len(t) < 2 {
			continue
		}
		if _, f := variantFillers[t]; f {
			continue
		}
		out[t] = struct{}{}
	}
	return out
}

// variantConflict reports whether two brand names denote DIFFERENT variants of
// (potentially) the same family: each name carries at least one distinctive word
// the other lacks. This is the robust, threshold-free variant test —
// "100 Pipers Exquisite" vs "100 Pipers Deluxe" conflict (exquisite ↔ deluxe)
// even though they share most words and score 0.60 by plain jaccard; identical
// or generic-vs-specific names do NOT conflict. Drives WS-B (never reuse a
// conflicting variant) and WS-D (flag a product linked to a conflicting master).
func variantConflict(a, b string) bool {
	ta, tb := variantTokenSet(a), variantTokenSet(b)
	aOnly, bOnly := false, false
	for t := range ta {
		if _, ok := tb[t]; !ok {
			aOnly = true
			break
		}
	}
	for t := range tb {
		if _, ok := ta[t]; !ok {
			bOnly = true
			break
		}
	}
	return aOnly && bOnly
}

// reuseExistingByNameSize finds a same-shop product at sizeML whose name is
// variant-safely close (token jaccard ≥ 0.60) to the GP canonical, ignoring the
// (possibly wrong) saas_brand link. Returns nil when none is close enough.
// Variant-safe: the 0.60 floor keeps "Reserve Premium" matching "Reserve
// Premium" while rejecting "Classic Finest" / "Fine & Rare" (distinct tokens).
func (s *SmartPurchaseService) reuseExistingByNameSize(
	tx *gorm.DB, tenantID, shopID uuid.UUID, sizeML int, gpCanonicalName string,
) *SelectBestProductResult {
	gpName := strings.TrimSpace(gpCanonicalName)
	if gpName == "" || sizeML <= 0 {
		return nil
	}
	gpTok := gpTokenSet(strings.ToLower(gpName))
	if len(gpTok) == 0 {
		return nil
	}
	type prow struct {
		ID       uuid.UUID `gorm:"column:id"`
		Name     string    `gorm:"column:name"`
		Quantity int       `gorm:"column:quantity"`
	}
	var rows []prow
	sizePattern := fmt.Sprintf("^0*%d([^0-9]|$)", sizeML)
	if err := tx.Table("products p").
		Select(`p.id, p.name, COALESCE(s.quantity,0) AS quantity`).
		Joins("LEFT JOIN stocks s ON s.product_id = p.id AND s.shop_id = ?", shopID).
		Where(`p.tenant_id = ? AND p.deleted_at IS NULL AND p.size ~ ?
		       AND (p.shop_id = ? OR p.shop_id IS NULL)`, tenantID, sizePattern, shopID).
		Scan(&rows).Error; err != nil {
		log.Printf("[smart_purchase_self_align] reuseExistingByNameSize query: %v", err)
		return nil
	}
	bestIdx, bestScore := -1, reuseNameJaccardFloor // floor is inclusive via >=
	for i, r := range rows {
		// Robust variant guard: never reuse a DIFFERENT variant of the same family
		// (Exquisite vs Deluxe score 0.60 by jaccard but conflict on the
		// distinctive word). This is the threshold-free safety net atop the floor.
		if variantConflict(gpName, r.Name) {
			continue
		}
		sc := jaccardTokens(gpTok, gpTokenSet(strings.ToLower(r.Name)))
		// Prefer a strictly higher score; on a tie prefer the in-stock row.
		if sc > bestScore || (sc == bestScore && bestIdx >= 0 && r.Quantity > rows[bestIdx].Quantity) {
			bestIdx, bestScore = i, sc
		} else if bestIdx == -1 && sc >= reuseNameJaccardFloor {
			bestIdx, bestScore = i, sc
		}
	}
	if bestIdx < 0 {
		return nil
	}
	w := rows[bestIdx]
	log.Printf("[smart_purchase_self_align] WS-B name+size REUSE: GP %q ~ product %q (id=%s, jaccard=%.2f, qty=%d) — reusing mislinked product instead of creating new",
		gpName, w.Name, w.ID, bestScore, w.Quantity)
	return &SelectBestProductResult{
		WinnerID:     w.ID,
		WinnerName:   w.Name,
		WinnerQty:    w.Quantity,
		ReusedByName: true,
		ReuseScore:   bestScore,
		TiebreakLog:  fmt.Sprintf("WS-B name+size reuse: jaccard=%.2f vs GP %q", bestScore, gpName),
	}
}

// selectBestProductForGPRow finds the tenant products row that should
// receive the stock increase for a GP row. Strict on (saas_brand_id,
// size_ml); does NOT fuzzy-fall-back to name matching — that's a separate
// caller responsibility (we only get here once the brand is canonically
// resolved).
//
// Why this exists: chhotu's Mahua Khera catalog has 8+ products at
// duplicate rows (same saas_brand_id + size_ml, different `products.name`
// text). v218 fixed the stale-clear symptom; v221 needs deterministic
// disambiguation at the write boundary so the bug class can't recur.
func (s *SmartPurchaseService) selectBestProductForGPRow(
	tx *gorm.DB,
	tenantID, shopID uuid.UUID,
	saasBrandID uuid.UUID,
	sizeML int,
	gpCanonicalName string,
	shopScoped bool,
	reuseByName bool,
) (*SelectBestProductResult, error) {
	if saasBrandID == uuid.Nil {
		return nil, errors.New("selectBestProductForGPRow: saasBrandID is required (strict-match only)")
	}
	if sizeML <= 0 {
		return nil, errors.New("selectBestProductForGPRow: sizeML must be > 0")
	}

	type row struct {
		ID            uuid.UUID `gorm:"column:id"`
		Name          string    `gorm:"column:name"`
		DisplayName   string    `gorm:"column:display_name"`
		Quantity      int       `gorm:"column:quantity"`
		CreatedAtUnix int64     `gorm:"column:created_at_unix"`
	}
	var rows []row

	// `products.size` is free-text ("180ML", "180ml (Quarter)", "180").
	// Numeric-prefix regex covers all three formats reliably without
	// importing the `sizing` canonicaliser into this hot path.
	sizePattern := fmt.Sprintf("^0*%d([^0-9]|$)", sizeML)

	q := tx.Table("products p").
		Select(`p.id, p.name, COALESCE(p.display_name, '') AS display_name,
		        COALESCE(s.quantity, 0) AS quantity,
		        EXTRACT(EPOCH FROM p.created_at)::bigint AS created_at_unix`).
		Joins("LEFT JOIN stocks s ON s.product_id = p.id AND s.shop_id = ?", shopID).
		Where(`p.tenant_id = ? AND p.deleted_at IS NULL
		       AND p.saas_brand_id = ?
		       AND p.size ~ ?`, tenantID, saasBrandID, sizePattern)

	// WS1 — STRICT SHOP ISOLATION. Historically this query filtered only by
	// tenant+saas_brand+size, using shopID solely for the stock JOIN — so it
	// returned products from EVERY shop and `ORDER BY quantity DESC` could pick
	// another shop's product (the Mahua Khera row that bound FM Tower's Rockford
	// because FM Tower held more stock). When enabled, restrict candidates to
	// THIS shop's products (plus tenant-wide/master products, shop_id IS NULL,
	// which are shared by design). Gated for dark rollout; flip with the same
	// SMART_PURCHASE_SHOP_ALIAS_GUARD switch as the alias guard.
	if shopScoped {
		q = q.Where("(p.shop_id = ? OR p.shop_id IS NULL)", shopID)
	}

	err := q.
		Order("quantity DESC, created_at_unix DESC").
		Scan(&rows).Error
	if err != nil {
		return nil, fmt.Errorf("selectBestProductForGPRow query: %w", err)
	}
	if len(rows) == 0 {
		// WS-B (v1.0.366) — variant-safe name+size REUSE fallback. The strict
		// saas_brand match found nothing, but the shop may already hold this
		// product MISLINKED to the wrong master variant (Rockford Reserve Premium
		// linked to the Fine & Rare master). Rather than create a duplicate "new"
		// product, look for an existing SAME-SHOP product at this size whose name
		// is variant-safely close to the GP canonical (token jaccard ≥ 0.60 — the
		// same floor the brand resolver uses, so "Reserve Premium" matches
		// "Reserve Premium" but NOT "Classic Finest"). Reuse it and flag for a
		// link-repair. Gated (reuseByName) + shop-scoped.
		if reuseByName && shopScoped {
			if res := s.reuseExistingByNameSize(tx, tenantID, shopID, sizeML, gpCanonicalName); res != nil {
				return res, nil
			}
		}
		return &SelectBestProductResult{}, nil
	}

	gpLower := strings.ToLower(strings.TrimSpace(gpCanonicalName))
	winnerIdx := 0
	if len(rows) > 1 {
		// rows are sorted by (quantity DESC, created_at_unix DESC).
		// Override the SQL order only when an exact GP-canonical-name match
		// exists AND it also holds stock — that's a strong signal it's the
		// operator's "live" row even if some other row was created more
		// recently. Otherwise the SQL order is authoritative.
		for i, r := range rows {
			if r.Quantity > 0 && strings.EqualFold(strings.TrimSpace(r.Name), gpLower) {
				winnerIdx = i
				break
			}
		}
	}

	w := rows[winnerIdx]
	losers := make([]uuid.UUID, 0, len(rows)-1)
	for i, r := range rows {
		if i == winnerIdx {
			continue
		}
		losers = append(losers, r.ID)
	}

	ambiguous := false
	if len(rows) > 1 && rows[0].Quantity > 0 && rows[1].Quantity > 0 {
		// Both top rows hold stock — operator might want to see the picked
		// row in the UI before committing. Not a hard block; just a hint.
		ambiguous = true
	}

	tieLog := fmt.Sprintf("v221 tiebreak: %d candidates for (brand=%s, size=%dml); winner=%s qty=%d; losers=%v; ambiguous=%v",
		len(rows), saasBrandID, sizeML, w.ID, w.Quantity, losers, ambiguous)
	log.Printf("[smart_purchase_self_align] %s", tieLog)

	return &SelectBestProductResult{
		WinnerID:    w.ID,
		WinnerName:  w.Name,
		WinnerQty:   w.Quantity,
		LoserIDs:    losers,
		Ambiguous:   ambiguous,
		TiebreakLog: tieLog,
	}, nil
}

// promoteCanonicalName rewrites `products.name` to the GP excise canonical.
// If `display_name` is empty, the previous `name` is moved there so the
// operator-facing UI keeps showing the short familiar label.
//
// Guards:
//   - No-op when names already match (case + whitespace tolerant).
//   - Never overwrites a non-empty `display_name` — that's an explicit
//     operator preference (e.g. set via the admin product editor).
//
// Returns the before/after strings for the audit log.
func (s *SmartPurchaseService) promoteCanonicalName(
	tx *gorm.DB,
	tenantID, productID uuid.UUID,
	gpCanonicalName string,
) (oldName, newName string, changed bool, err error) {
	gpCanonicalName = strings.TrimSpace(gpCanonicalName)
	if gpCanonicalName == "" {
		return "", "", false, errors.New("promoteCanonicalName: gpCanonicalName is empty")
	}

	var p models.Product
	if err = tx.Select("id, name, display_name").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", productID, tenantID).
		First(&p).Error; err != nil {
		return "", "", false, fmt.Errorf("promoteCanonicalName lookup: %w", err)
	}

	currentName := strings.TrimSpace(p.Name)
	currentDisplay := strings.TrimSpace(p.DisplayName)

	if strings.EqualFold(squashWhitespace(currentName), squashWhitespace(gpCanonicalName)) {
		return currentName, currentName, false, nil
	}

	updates := map[string]interface{}{
		"name": gpCanonicalName,
	}
	if currentDisplay == "" {
		updates["display_name"] = currentName
	}

	if err = tx.Model(&models.Product{}).
		Where("id = ? AND tenant_id = ?", productID, tenantID).
		Updates(updates).Error; err != nil {
		return "", "", false, fmt.Errorf("promoteCanonicalName update: %w", err)
	}

	demotion := "preserved"
	if currentDisplay == "" {
		demotion = "set to old name"
	}
	log.Printf("[smart_purchase_self_align] promoted canonical: product=%s '%s' → '%s' (display_name %s)",
		productID, currentName, gpCanonicalName, demotion)

	return currentName, gpCanonicalName, true, nil
}

// captureBillAliasFromGPMatch records the bill row's raw OCR brand text as
// an alias pointing to the canonical product. Uses LearnAliasScoped so the
// lesson stays anchored to this shop (v160 alias scoping). All hygiene
// guards in AliasService apply.
//
// Returns nil on hygiene-skipped writes — callers should not treat hygiene
// rejection as a failure.
func captureBillAliasFromGPMatch(
	aliasSvc *alias.AliasService,
	tenantID, shopID, productID uuid.UUID,
	billOCRText, canonicalName string,
) error {
	if aliasSvc == nil {
		return nil
	}
	billOCRText = strings.TrimSpace(billOCRText)
	canonicalName = strings.TrimSpace(canonicalName)
	if billOCRText == "" || canonicalName == "" {
		return nil
	}
	pid := productID
	return aliasSvc.LearnAliasScoped(tenantID, shopID, billOCRText, canonicalName, &pid, "smart_purchase_v221_gp_apply")
}

// squashWhitespace collapses runs of internal whitespace to a single space
// so "M2  Magic Moments" matches "M2 Magic Moments" for no-op detection.
func squashWhitespace(s string) string {
	var b strings.Builder
	prevSpace := false
	for _, r := range s {
		if r == ' ' || r == '\t' || r == '\n' {
			if !prevSpace {
				b.WriteByte(' ')
			}
			prevSpace = true
		} else {
			b.WriteRune(r)
			prevSpace = false
		}
	}
	return b.String()
}
