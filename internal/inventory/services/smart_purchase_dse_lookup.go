package services

import (
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// v1.0.221 DSE-register lookup — secondary truth source for the
// onboarding-vs-new decision.
//
// When a GP row has no matching tenant `products` row (after the strict
// saas_brand_id + size_ml lookup in selectBestProductForGPRow), v221 falls
// back to the shop's recent Daily Sales Entry register for that size. The
// register is the operator's hand-written record of every brand they sell
// at that size on any given day. If a brand appears there, it's a known
// SKU the shop tracks — the missing `products` row is a data hole worth
// surfacing for one-tap link. If the brand does NOT appear, it's genuinely
// new and v221 auto-onboards from the master catalog silently.
//
// Lookup window: 90 days at this shop, scoped to records whose items have
// any product at the requested size_ml. We deliberately match against the
// operator's free-text brand strings (daily_sales_items.brand_name +
// products.name on confirmed rows) so the bridge to the DSE-register's
// hand-written world is wide.
//
// Why this matters: chhotu's catalog at this shop is missing several
// 180ml SKUs the operator actively tracks on the DSE register (Iconiq
// White 180ml, McDowell's No.1 180ml, Royal Challenge Classic 180ml from
// the v220 dry-run). Without this lookup, those rows surface as
// "needs onboarding" (operator tap required). With it, the system sees
// the brand in the register, treats it as a known SKU at this shop, and
// auto-creates the missing tenant product silently.

// DSEBrandKnown reports whether a brand string appears in the shop's
// recent daily-sales register at the requested size. Returns:
//   - found:    true when any daily_sales_items row in the lookback window
//               for this shop+size carries a brand matching gpCanonical.
//   - matches:  the top-3 brand strings actually found in the register
//               (useful for the UI when surfacing "we found these in your
//               recent sale register" hints).
type DSEBrandKnown struct {
	Found   bool
	Matches []string
}

// recentDSEBrandsAtSize returns the set of brand strings the operator has
// tracked on the daily sales register at this shop within `lookback` for
// products at the requested ml size. Used by the onboarding-decision logic.
//
// The set is deduplicated (case-insensitive). Hot path for purchase apply,
// so kept SQL-cheap: one query scoped by (shop, size_ml, date window).
func (s *SmartPurchaseService) recentDSEBrandsAtSize(
	tx *gorm.DB,
	tenantID, shopID uuid.UUID,
	sizeML int,
	lookback time.Duration,
) (map[string]struct{}, error) {
	if sizeML <= 0 {
		return nil, fmt.Errorf("recentDSEBrandsAtSize: sizeML must be > 0")
	}
	if lookback <= 0 {
		lookback = 90 * 24 * time.Hour
	}
	sincTS := time.Now().Add(-lookback)
	sizePattern := fmt.Sprintf("^0*%d([^0-9]|$)", sizeML)

	type row struct {
		BrandText string `gorm:"column:brand_text"`
	}
	var rows []row

	// Join daily_sales_items → products to grab both the OCR-text brand
	// (raw_text / brand_name) and the linked canonical name. Both feed
	// into the known-brand set.
	err := tx.Raw(`
		SELECT DISTINCT LOWER(COALESCE(NULLIF(TRIM(p.name), ''), '')) AS brand_text
		FROM daily_sales_items dsi
		JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		LEFT JOIN products p ON p.id = dsi.product_id AND p.deleted_at IS NULL
		WHERE dsr.tenant_id = ?
		  AND dsr.shop_id = ?
		  AND dsr.created_at >= ?
		  AND dsr.deleted_at IS NULL
		  AND p.size ~ ?
		  AND p.name IS NOT NULL
		  AND p.name <> ''
	`, tenantID, shopID, sincTS, sizePattern).Scan(&rows).Error
	if err != nil {
		return nil, fmt.Errorf("recentDSEBrandsAtSize query: %w", err)
	}

	out := make(map[string]struct{}, len(rows))
	for _, r := range rows {
		if r.BrandText == "" {
			continue
		}
		out[r.BrandText] = struct{}{}
	}
	return out, nil
}

// brandKnownInDSE checks whether gpCanonical appears (by sufficient token
// overlap) in the shop's recent DSE register at the given size. Returns
// the top-3 matches as a debugging/UI aid.
//
// Uses the same gpTokenSet + jaccardTokens helpers from the resolver file,
// with a soft 0.50 threshold (DSE entries are short operator labels and
// jaccard scores naturally lower than GP-vs-saas_brand comparisons).
//
// v1.0.222 — accepts an optional `cache` map (size_ml → known brand set)
// so callers that resolve many GP rows in one go (processGPPrimary) avoid
// N+1 DB queries. Pass nil to disable caching.
func (s *SmartPurchaseService) brandKnownInDSE(
	tx *gorm.DB,
	tenantID, shopID uuid.UUID,
	gpCanonical string,
	sizeML int,
	lookback time.Duration,
	cache map[int]map[string]struct{},
) (DSEBrandKnown, error) {
	known := DSEBrandKnown{}
	var brands map[string]struct{}
	if cache != nil {
		if cached, hit := cache[sizeML]; hit {
			brands = cached
		}
	}
	if brands == nil {
		fetched, err := s.recentDSEBrandsAtSize(tx, tenantID, shopID, sizeML, lookback)
		if err != nil {
			return known, err
		}
		brands = fetched
		if cache != nil {
			cache[sizeML] = brands
		}
	}
	if len(brands) == 0 {
		return known, nil
	}
	gpTokens := gpTokenSet(strings.ToLower(strings.TrimSpace(gpCanonical)))
	if len(gpTokens) == 0 {
		return known, nil
	}

	type scored struct {
		brand string
		score float64
	}
	results := make([]scored, 0, len(brands))
	for b := range brands {
		score := jaccardTokens(gpTokens, gpTokenSet(b))
		if score >= 0.50 {
			results = append(results, scored{brand: b, score: score})
		}
	}
	if len(results) == 0 {
		return known, nil
	}
	// Sort descending by score; keep top 3.
	for i := 0; i < len(results); i++ {
		for j := i + 1; j < len(results); j++ {
			if results[j].score > results[i].score {
				results[i], results[j] = results[j], results[i]
			}
		}
	}
	known.Found = true
	limit := 3
	if len(results) < limit {
		limit = len(results)
	}
	for i := 0; i < limit; i++ {
		known.Matches = append(known.Matches, results[i].brand)
	}
	log.Printf("[smart_purchase_dse_lookup] '%s' size=%dml shop=%s: found=%v top=%v",
		gpCanonical, sizeML, shopID, known.Found, known.Matches)
	return known, nil
}

// OnboardingDecision is the v221 routing outcome for a GP row that found
// no tenant products row via selectBestProductForGPRow. Three values:
//
//   - "auto_onboard":      brand is NOT on the DSE register and IS in
//                          master catalog → create tenant product silently.
//   - "soft_onboard":      brand IS on the DSE register but missing from
//                          tenant.products → likely a catalog gap; create
//                          + link with a "auto-linked from sale register"
//                          chip so the operator sees what happened.
//   - "ask_past_purchase": brand is absent from BOTH the DSE register AND
//                          the master catalog → operator must upload a
//                          previous purchase for context.
type OnboardingDecision string

const (
	OnboardingAutoFromMaster   OnboardingDecision = "auto_onboard"
	OnboardingSoftLinkFromDSE  OnboardingDecision = "soft_onboard"
	OnboardingAskPastPurchase  OnboardingDecision = "ask_past_purchase"
)

// decideOnboardingPath wraps the brandKnownInDSE + master-catalog check
// into the three-way decision the apply path follows when no tenant
// products row matches.
//
// v1.0.222 — accepts the per-request DSE size cache to amortise lookups.
func (s *SmartPurchaseService) decideOnboardingPath(
	tx *gorm.DB,
	tenantID, shopID uuid.UUID,
	gpCanonical string,
	sizeML int,
	masterMatch GPBrandMatch,
	dseCacheBySize map[int]map[string]struct{},
) (OnboardingDecision, DSEBrandKnown, error) {
	dseHit, err := s.brandKnownInDSE(tx, tenantID, shopID, gpCanonical, sizeML, 90*24*time.Hour, dseCacheBySize)
	if err != nil {
		return OnboardingAskPastPurchase, dseHit, err
	}
	hasMasterMatch := masterMatch.SaasBrandID != uuid.Nil && masterMatch.Confidence >= 0.70

	switch {
	case dseHit.Found && hasMasterMatch:
		return OnboardingSoftLinkFromDSE, dseHit, nil
	case !dseHit.Found && hasMasterMatch:
		return OnboardingAutoFromMaster, dseHit, nil
	default:
		// Either no master OR (dse-found but no master). In both cases we
		// need operator help — they need to either confirm new SKU
		// creation or upload a past purchase for disambiguation.
		return OnboardingAskPastPurchase, dseHit, nil
	}
}
