package alias

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/redis/go-redis/v9"
)

// hygieneBlockCanonicalEnabled — Track B3. Default ON. Disable per-incident
// with OCR_ALIAS_HYGIENE_BLOCK_CANONICAL=0 if the guard mis-fires.
func hygieneBlockCanonicalEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("OCR_ALIAS_HYGIENE_BLOCK_CANONICAL")))
	if v == "0" || v == "false" || v == "off" || v == "no" {
		return false
	}
	return true
}

// tenantShopDemoteEnabled — WS1.4. Default ON. When a tenant-wide alias write
// (shop_id NULL) carries a product that actually belongs to ONE shop, demote the
// write to that product's shop so it can never bleed that shop's identity into
// another shop's matching. Disable with OCR_ALIAS_TENANT_SHOP_DEMOTE=0.
func tenantShopDemoteEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("OCR_ALIAS_TENANT_SHOP_DEMOTE")))
	if v == "0" || v == "false" || v == "off" || v == "no" {
		return false
	}
	return true
}

// shopValidatedGlobalEnabled — WS1.1. When ON, EVERY LookupAliasCascade call
// (purchase, sale, stock-setup) validates that an alias's product belongs to
// the requesting shop (or is tenant-wide) before using it — global strict shop
// isolation. Default OFF (dark); flip with OCR_ALIAS_SHOP_VALIDATED=1 after the
// purchase tester confirms it. Purchase callers can also force validation per
// job (test user) regardless of this global, via LookupAliasCascadeShopValidated.
func shopValidatedGlobalEnabled() bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv("OCR_ALIAS_SHOP_VALIDATED")))
	return v == "1" || v == "true" || v == "on" || v == "yes"
}

// productShopScope reports the shop a product is scoped to.
//   - (nil, true)   → product exists and is TENANT-WIDE (products.shop_id IS NULL)
//   - (&shop, true) → product exists and belongs to that shop
//   - (nil, false)  → product not found / deleted (cannot validate)
//
// Used by both the write-time demotion guard and the read-time shop-validated
// alias cascade so a single source of truth decides "may this alias be used for
// this shop".
func (s *AliasService) productShopScope(tenantID, productID uuid.UUID) (shopID *uuid.UUID, found bool) {
	var row struct {
		ID     string
		ShopID *string
	}
	err := s.db.Raw(`
		SELECT id::text AS id, shop_id::text AS shop_id
		FROM products
		WHERE id = ? AND tenant_id = ? AND deleted_at IS NULL
		LIMIT 1
	`, productID, tenantID).Scan(&row).Error
	if err != nil || row.ID == "" {
		return nil, false
	}
	if row.ShopID == nil || strings.TrimSpace(*row.ShopID) == "" {
		return nil, true // tenant-wide product
	}
	sid, perr := uuid.Parse(strings.TrimSpace(*row.ShopID))
	if perr != nil {
		return nil, true
	}
	return &sid, true
}

// aliasUsableForShop reports whether an alias whose product is productID may be
// used for targetShop: true iff the product is tenant-wide OR belongs to
// targetShop. A nil productID (name-only alias) is always usable. An alias whose
// product belongs to a DIFFERENT shop must never be used for targetShop.
func (s *AliasService) aliasUsableForShop(tenantID, targetShop uuid.UUID, productID *uuid.UUID) bool {
	if productID == nil {
		return true
	}
	pShop, found := s.productShopScope(tenantID, *productID)
	if !found {
		return false // cannot validate → fail safe (do not use cross-shop-capable hint)
	}
	if pShop == nil {
		return true // tenant-wide product is shared by design
	}
	return *pShop == targetShop
}

// AliasService provides alias lookup and learning for OCR brand matching.
//
// v1.0.160 — shop-scope cascade. Every public method now has an explicit
// shop-scoped variant (`*Scoped`). Legacy callers without a shop in scope
// keep working unchanged: the non-scoped methods delegate to the scoped
// ones with shop_id = uuid.Nil, which writes/reads the tenant-wide row
// (NULL shop_id in DB).
//
// Lookup cascade (LookupAliasCascade) consults rows in this order:
//   1. shop-scoped exact match  (tenant_id, shop_id, lower(alias_name))
//   2. tenant-wide exact match  (tenant_id, shop_id IS NULL, lower(alias_name))
//   3. shop-scoped fuzzy        (jaccard ≥ 0.6, tenant_id + shop_id)
//   4. tenant-wide fuzzy        (jaccard ≥ 0.6, tenant_id + shop_id IS NULL)
//   5. negative-alias gate      blocks any of the above when shop OR tenant
//                               negative alias matches.
type AliasService struct {
	db    *database.DB
	redis *redis.Client // optional Redis cache
}

// AliasOption configures optional features
type AliasOption func(*AliasService)

// WithRedis enables Redis caching for alias lookups
func WithRedis(client *redis.Client) AliasOption {
	return func(s *AliasService) { s.redis = client }
}

// NewAliasService creates a new AliasService
func NewAliasService(db *database.DB, opts ...AliasOption) *AliasService {
	s := &AliasService{db: db}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

// AliasSource identifies which tier of the cascade produced a hit. Useful
// for callers that want to log learning provenance (e.g. "shop-scoped
// alias fired" vs "tenant-wide fuzzy fallback fired").
type AliasSource string

const (
	AliasSourceShopExact     AliasSource = "shop_exact"
	AliasSourceTenantExact   AliasSource = "tenant_exact"
	AliasSourceShopFuzzy     AliasSource = "shop_fuzzy"
	AliasSourceTenantFuzzy   AliasSource = "tenant_fuzzy"
	AliasSourceNone          AliasSource = "none"
)

// aliasCache is the cached representation of an alias lookup result
type aliasCache struct {
	ProductID     *uuid.UUID `json:"pid,omitempty"`
	CanonicalName string     `json:"cn"`
	Found         bool       `json:"f"`
	Source        string     `json:"src,omitempty"`
}

const aliasCacheTTL = 1 * time.Hour
const aliasCachePrefix = "alias:"

// shopCacheTag returns a short cache-key tag for the shop dimension.
// Tenant-wide rows use "_" so they don't collide with any real shop UUID.
func shopCacheTag(shopID uuid.UUID) string {
	if shopID == uuid.Nil {
		return "_"
	}
	return shopID.String()[:8]
}

// LookupAlias checks if an OCR text has a known alias for this tenant.
// Returns the product ID, canonical name, and whether a match was found.
//
// Backward-compat shim: callers that don't have a shopID still work. They
// get a TENANT-WIDE lookup (only rows with shop_id IS NULL match), which
// preserves pre-v1.0.160 behaviour. New callers should use
// LookupAliasCascade with their shopID for shop-aware matching.
func (s *AliasService) LookupAlias(tenantID uuid.UUID, ocrText string) (*uuid.UUID, string, bool) {
	pid, name, _, found := s.LookupAliasCascade(context.Background(), tenantID, uuid.Nil, ocrText, "")
	return pid, name, found
}

// LookupAliasScoped is the same as LookupAlias but scoped to a specific shop.
// Returns the alias source tier so callers can log provenance.
func (s *AliasService) LookupAliasScoped(ctx context.Context, tenantID, shopID uuid.UUID, ocrText string) (*uuid.UUID, string, AliasSource, bool) {
	return s.LookupAliasCascade(ctx, tenantID, shopID, ocrText, "")
}

// LookupAliasCascade is the v1.0.160 unified lookup entry point. It walks
// shop → tenant → fuzzy in priority order and returns the first hit, with
// negative-alias rows blocking any candidate that the same (tenant, shop)
// has explicitly rejected.
//
// sizeHint is reserved for future use (size-aware aliases). Today it's
// accepted but ignored — keeping the param in the signature avoids another
// callsite churn when we wire size into the schema.
func (s *AliasService) LookupAliasCascade(ctx context.Context, tenantID, shopID uuid.UUID, ocrText, sizeHint string) (*uuid.UUID, string, AliasSource, bool) {
	// Global strict shop isolation when OCR_ALIAS_SHOP_VALIDATED=1; otherwise
	// legacy behavior (dark by default).
	return s.lookupAliasCascadeImpl(ctx, tenantID, shopID, ocrText, sizeHint, shopValidatedGlobalEnabled())
}

// LookupAliasCascadeShopValidated — WS1.1. Same cascade, but ALWAYS validates
// that a candidate alias's product belongs to the requesting shop (or is
// tenant-wide) before using it: a tenant-wide alias pointing at ANOTHER shop's
// product is skipped and the cascade continues, so a lower-confidence same-shop
// alias — or, failing that, the normal matcher — wins instead of a cross-shop
// bind. Purchase callers use this for gated jobs (test user) so the guard can be
// validated before the global OCR_ALIAS_SHOP_VALIDATED flip.
func (s *AliasService) LookupAliasCascadeShopValidated(ctx context.Context, tenantID, shopID uuid.UUID, ocrText, sizeHint string) (*uuid.UUID, string, AliasSource, bool) {
	return s.lookupAliasCascadeImpl(ctx, tenantID, shopID, ocrText, sizeHint, true)
}

func (s *AliasService) lookupAliasCascadeImpl(ctx context.Context, tenantID, shopID uuid.UUID, ocrText, sizeHint string, validate bool) (*uuid.UUID, string, AliasSource, bool) {
	_ = sizeHint // reserved
	normalized := strings.ToLower(strings.TrimSpace(ocrText))
	if normalized == "" {
		return nil, "", AliasSourceNone, false
	}

	// usable gates each candidate on shop scope when validation is on. A
	// cross-shop product → not usable → the candidate is skipped and the
	// cascade falls through to the next tier (never a silent cross-shop bind).
	usable := func(pid *uuid.UUID) bool {
		if !validate {
			return true
		}
		if !s.aliasUsableForShop(tenantID, shopID, pid) {
			log.Printf("AliasService: SKIP cross-shop alias '%s' (product %v not in shop %s) — falling through", normalized, pid, shopID)
			return false
		}
		return true
	}

	// Build the form variants we'll try as exact-match keys. Same logic as
	// pre-v1.0.160: "B P Blue" → "bp blue" via punctuation strip + multi-
	// space collapse.
	compacted := strings.ReplaceAll(strings.ReplaceAll(normalized, ".", ""), "  ", " ")
	compacted = strings.Join(strings.Fields(compacted), " ")
	forms := []string{normalized}
	if compacted != normalized && compacted != "" {
		forms = append(forms, compacted)
	}

	// Tier 1 + 2: exact-match across both scopes. Shop-scoped first.
	for _, form := range forms {
		// Shop-scoped exact match (only when caller provided a real shop).
		if shopID != uuid.Nil {
			if pid, name, found := s.lookupExact(tenantID, &shopID, form); found {
				if !s.isBlockedNegative(tenantID, shopID, form, pid) && usable(pid) {
					return pid, name, AliasSourceShopExact, true
				}
			}
		}
		// Tenant-wide exact match.
		if pid, name, found := s.lookupExact(tenantID, nil, form); found {
			if !s.isBlockedNegative(tenantID, shopID, form, pid) && usable(pid) {
				return pid, name, AliasSourceTenantExact, true
			}
		}
	}

	// Tier 3 + 4: fuzzy fallback. Shop-scoped first (cheaper — fewer rows),
	// then tenant-wide.
	if shopID != uuid.Nil {
		if pid, name, found := s.fuzzyLookupAlias(tenantID, &shopID, normalized); found {
			if !s.isBlockedNegative(tenantID, shopID, normalized, pid) && usable(pid) {
				return pid, name, AliasSourceShopFuzzy, true
			}
		}
	}
	if pid, name, found := s.fuzzyLookupAlias(tenantID, nil, normalized); found {
		if !s.isBlockedNegative(tenantID, shopID, normalized, pid) && usable(pid) {
			return pid, name, AliasSourceTenantFuzzy, true
		}
	}

	return nil, "", AliasSourceNone, false
}

// lookupExact runs an indexed lookup against ocr_brand_aliases scoped to
// (tenant_id, shop_id|NULL, alias_name). Caller normalises text and walks
// form variants. Returns Redis-cached results when available.
//
// `scope` IS the shop_id pointer used in the WHERE clause:
//   nil  → shop_id IS NULL (tenant-wide row)
//   ptr  → shop_id = *ptr (shop-scoped row)
func (s *AliasService) lookupExact(tenantID uuid.UUID, scope *uuid.UUID, normalized string) (*uuid.UUID, string, bool) {
	// Try Redis cache first.
	cacheTag := "_"
	if scope != nil {
		cacheTag = scope.String()[:8]
	}
	cacheKey := fmt.Sprintf("%s%s:%s:%s", aliasCachePrefix, tenantID.String()[:8], cacheTag, normalized)
	if s.redis != nil {
		ctx := context.Background()
		if data, err := s.redis.Get(ctx, cacheKey).Bytes(); err == nil {
			var cached aliasCache
			if json.Unmarshal(data, &cached) == nil {
				if !cached.Found {
					return nil, "", false
				}
				log.Printf("AliasService: CACHE HIT '%s' [%s] -> '%s'", normalized, cacheTag, cached.CanonicalName)
				return cached.ProductID, cached.CanonicalName, true
			}
		}
	}

	q := s.db.Model(&models.OCRBrandAlias{}).
		Where("tenant_id = ? AND LOWER(alias_name) = ?", tenantID, normalized).
		Where("(deleted_at IS NULL)")
	if scope == nil {
		q = q.Where("shop_id IS NULL")
	} else {
		q = q.Where("shop_id = ?", *scope)
	}

	var alias models.OCRBrandAlias
	err := q.Order("confidence_score DESC, occurrence_count DESC").First(&alias).Error
	if err != nil {
		s.cacheAliasResultKeyed(cacheKey, aliasCache{Found: false})
		return nil, "", false
	}

	// Async update usage stats (don't block the request).
	go func() {
		now := time.Now()
		s.db.Model(&models.OCRBrandAlias{}).
			Where("id = ?", alias.ID).
			Updates(map[string]interface{}{
				"occurrence_count": alias.OccurrenceCount + 1,
				"last_used_at":     now,
			})
	}()

	s.cacheAliasResultKeyed(cacheKey, aliasCache{
		ProductID:     alias.ProductID,
		CanonicalName: alias.CanonicalBrandName,
		Found:         true,
	})

	log.Printf("AliasService: HIT '%s' [%s] -> '%s' (product: %v, count: %d)", normalized, cacheTag, alias.CanonicalBrandName, alias.ProductID, alias.OccurrenceCount)
	return alias.ProductID, alias.CanonicalBrandName, true
}

// fuzzyLookupAlias scans aliases at the requested scope and returns the
// highest-scoring jaccard ≥ 0.6 match. `scope` semantics match lookupExact.
func (s *AliasService) fuzzyLookupAlias(tenantID uuid.UUID, scope *uuid.UUID, normalized string) (*uuid.UUID, string, bool) {
	textTokens := aliasTokenSet(normalized)
	if len(textTokens) == 0 {
		return nil, "", false
	}

	q := s.db.Model(&models.OCRBrandAlias{}).
		Where("tenant_id = ? AND occurrence_count > 0", tenantID).
		Where("(deleted_at IS NULL)")
	if scope == nil {
		q = q.Where("shop_id IS NULL")
	} else {
		q = q.Where("shop_id = ?", *scope)
	}
	var aliases []models.OCRBrandAlias
	if err := q.Find(&aliases).Error; err != nil || len(aliases) == 0 {
		return nil, "", false
	}

	const threshold = 0.6
	bestScore := threshold
	bestIdx := -1
	for i := range aliases {
		score := aliasJaccard(textTokens, aliasTokenSet(strings.ToLower(aliases[i].AliasName)))
		if score > bestScore {
			bestScore = score
			bestIdx = i
		} else if score == bestScore && bestIdx >= 0 && aliases[i].OccurrenceCount > aliases[bestIdx].OccurrenceCount {
			// Tiebreak on occurrence_count — prefer well-used aliases.
			bestIdx = i
		}
	}
	if bestIdx < 0 {
		return nil, "", false
	}
	hit := aliases[bestIdx]
	scopeTag := "tenant"
	if scope != nil {
		scopeTag = "shop"
	}
	log.Printf("alias fuzzy(%s): %q -> %q via jaccard=%.2f (occ=%d)", scopeTag, normalized, hit.AliasName, bestScore, hit.OccurrenceCount)
	return hit.ProductID, hit.CanonicalBrandName, true
}

// isBlockedNegative returns true if the (tenant, shop|NULL, alias_name,
// product_id) combination is in ocr_negative_aliases. Both the shop-scoped
// row AND the tenant-wide row are consulted so a tenant-wide rejection
// blocks every shop, while a shop-specific rejection only blocks the shop
// that taught it.
func (s *AliasService) isBlockedNegative(tenantID, shopID uuid.UUID, aliasText string, productID *uuid.UUID) bool {
	if productID == nil {
		return false
	}
	normalized := strings.ToLower(strings.TrimSpace(aliasText))
	if normalized == "" {
		return false
	}
	q := s.db.Model(&models.OCRNegativeAlias{}).
		Where("tenant_id = ? AND LOWER(alias_name) = ? AND rejected_product_id = ?", tenantID, normalized, *productID)
	if shopID != uuid.Nil {
		q = q.Where("shop_id IS NULL OR shop_id = ?", shopID)
	} else {
		q = q.Where("shop_id IS NULL")
	}
	var count int64
	q.Count(&count)
	return count > 0
}

// aliasTokenSet splits a lowercased string on whitespace + common punctuation
// and returns the unique-token set. Keep self-contained (no cross-package import).
func aliasTokenSet(s string) map[string]struct{} {
	out := map[string]struct{}{}
	field := func(r rune) bool {
		switch r {
		case ' ', '\t', '\n', '\r', '.', ',', '/', '\\', '-', '_', '(', ')', '[', ']', '{', '}', '&', '\'', '"', ':', ';', '|':
			return true
		}
		return false
	}
	for _, t := range strings.FieldsFunc(strings.ToLower(s), field) {
		if t == "" {
			continue
		}
		out[t] = struct{}{}
	}
	return out
}

// aliasJaccard returns |A ∩ B| / |A ∪ B|.
func aliasJaccard(a, b map[string]struct{}) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	inter := 0
	for k := range a {
		if _, ok := b[k]; ok {
			inter++
		}
	}
	union := len(a) + len(b) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

// LookupAliasWithNegatives is the legacy compatibility entry point. It does
// a tenant-wide lookup (no shop scope) and gathers tenant-wide negative
// aliases for the same text. New callers should use
// LookupAliasWithNegativesScoped to pass a shopID for full cascade.
func (s *AliasService) LookupAliasWithNegatives(tenantID uuid.UUID, ocrText string) (productID *uuid.UUID, canonicalName string, found bool, rejectedIDs []uuid.UUID) {
	return s.LookupAliasWithNegativesScoped(context.Background(), tenantID, uuid.Nil, ocrText)
}

// LookupAliasWithNegativesScopedSource runs the full cascade and additionally
// returns the AliasSource that produced the hit. Callers that want to skip
// downstream guards on EXACT-match aliases (which were operator-confirmed
// or backfilled from approved history) use this so they can differentiate
// from fuzzy hits.
//
// v1.0.168.
func (s *AliasService) LookupAliasWithNegativesScopedSource(ctx context.Context, tenantID, shopID uuid.UUID, ocrText string) (productID *uuid.UUID, canonicalName string, source AliasSource, found bool, rejectedIDs []uuid.UUID) {
	productID, canonicalName, source, found = s.LookupAliasCascade(ctx, tenantID, shopID, ocrText, "")

	normalized := strings.ToLower(strings.TrimSpace(ocrText))
	if normalized == "" {
		return
	}

	q := s.db.Model(&models.OCRNegativeAlias{}).
		Where("tenant_id = ? AND LOWER(alias_name) = ?", tenantID, normalized)
	if shopID != uuid.Nil {
		q = q.Where("shop_id IS NULL OR shop_id = ?", shopID)
	} else {
		q = q.Where("shop_id IS NULL")
	}
	var negatives []models.OCRNegativeAlias
	q.Find(&negatives)

	for _, neg := range negatives {
		rejectedIDs = append(rejectedIDs, neg.RejectedProductID)
		if found && productID != nil && *productID == neg.RejectedProductID {
			found = false
			productID = nil
			canonicalName = ""
			source = AliasSourceNone
		}
	}
	return
}

// LookupAliasWithNegativesScoped runs the full cascade and additionally
// returns every negative-alias product_id at this (tenant, shop) — useful
// to the matcher for de-prioritising candidates that exact-match negative
// rejections.
func (s *AliasService) LookupAliasWithNegativesScoped(ctx context.Context, tenantID, shopID uuid.UUID, ocrText string) (productID *uuid.UUID, canonicalName string, found bool, rejectedIDs []uuid.UUID) {
	productID, canonicalName, _, found = s.LookupAliasCascade(ctx, tenantID, shopID, ocrText, "")

	normalized := strings.ToLower(strings.TrimSpace(ocrText))
	if normalized == "" {
		return
	}

	q := s.db.Model(&models.OCRNegativeAlias{}).
		Where("tenant_id = ? AND LOWER(alias_name) = ?", tenantID, normalized)
	if shopID != uuid.Nil {
		q = q.Where("shop_id IS NULL OR shop_id = ?", shopID)
	} else {
		q = q.Where("shop_id IS NULL")
	}
	var negatives []models.OCRNegativeAlias
	q.Find(&negatives)

	for _, neg := range negatives {
		rejectedIDs = append(rejectedIDs, neg.RejectedProductID)
		// If the positive alias points to a rejected product, drop it.
		if found && productID != nil && *productID == neg.RejectedProductID {
			found = false
			productID = nil
			canonicalName = ""
		}
	}
	return
}

// LearnAlias is the legacy entry point — writes a TENANT-WIDE alias
// (shop_id NULL). New callers with a shop in scope should use
// LearnAliasScoped so the lesson stays anchored to the shop that taught it.
//
// Hygiene guard: rejects pairs whose token-jaccard < 0.20 (prevents
// "M2 Magic Moments" → "JAMUN SPICYMINT"-style mis-routes from polluting
// the corpus). Also drops trivially-short text and identical canonical/alias
// pairs.
func (s *AliasService) LearnAlias(tenantID uuid.UUID, ocrText string, canonicalName string, productID *uuid.UUID, source string) error {
	return s.LearnAliasScoped(tenantID, uuid.Nil, ocrText, canonicalName, productID, source)
}

// LearnAliasScoped writes an alias scoped to a specific shop (shopID != uuid.Nil)
// or tenant-wide (shopID == uuid.Nil). Same hygiene guards as LearnAlias.
func (s *AliasService) LearnAliasScoped(tenantID, shopID uuid.UUID, ocrText string, canonicalName string, productID *uuid.UUID, source string) error {
	normalized := strings.ToLower(strings.TrimSpace(ocrText))
	canonicalLower := strings.ToLower(strings.TrimSpace(canonicalName))

	// Hygiene 1: reject empty / too-short / canonical-equals-alias entries.
	if !s.isAliasLearnable(normalized, canonicalLower) {
		return nil
	}

	// Hygiene 2: dirty-alias guard (token-jaccard < 0.20).
	score := aliasJaccard(aliasTokenSet(normalized), aliasTokenSet(canonicalLower))
	if score < 0.20 {
		log.Printf("LearnAlias rejected: alias=%q canonical=%q jaccard=%.2f below 0.20 floor", ocrText, canonicalName, score)
		return nil
	}

	// Hygiene 3: skip if this exact (tenant, shop, alias, product) is in the
	// negative-alias table — that means we previously learned it was wrong.
	if productID != nil && s.isBlockedNegative(tenantID, shopID, normalized, productID) {
		log.Printf("LearnAlias rejected: alias=%q product=%s is in ocr_negative_aliases (shop=%s)", ocrText, productID, shopID)
		return nil
	}

	// v1.0.183 Track B3 — canonical-pollution guard. Refuse to learn an alias
	// whose text exactly matches an active product's canonical name in this
	// tenant pointing to a DIFFERENT product. Without this, the alias cascade
	// double-routes: real OCR text → product A's canonical → (this alias)
	// → product B. Concrete case: "the rockford reserve fine & rare" was
	// learned to point at "Rockford Premium" 16 times for chhotu's tenant
	// because chhotu's reviewers kept correcting a downstream Rockford row
	// — but "Fine & Rare" is itself a canonical product, so every future
	// extraction of any Fine & Rare match silently re-routed to Premium.
	if hygieneBlockCanonicalEnabled() && productID != nil {
		var collision struct {
			ID   string
			Name string
		}
		// Active products only (deleted_at IS NULL). Compare lowercased name.
		err := s.db.Raw(`
			SELECT id::text AS id, name AS name
			FROM products
			WHERE tenant_id = ?
			  AND deleted_at IS NULL
			  AND lower(name) = ?
			LIMIT 1
		`, tenantID, normalized).Scan(&collision).Error
		if err == nil && collision.ID != "" && collision.ID != productID.String() {
			log.Printf("LearnAlias rejected: alias=%q matches canonical product %s (id=%s) but caller wants to point at %s — refusing pollution", ocrText, collision.Name, collision.ID, productID)
			return nil
		}
	}

	// v1.0.307 — source → confidence map. Higher confidence wins on
	// ON CONFLICT (GREATEST), so this is the tier that decides which signal
	// trumps another when multiple paths teach the same alias. Tiers:
	//   100  user_correction / operator_approved   — operator explicitly vouched
	//    95  image_verify*                          — operator confirmed photo identity
	//    90  stock_setup_approved*                  — operator approved item via Stock Setup
	//    80  default (any unlabelled source)
	//    60  auto_variant                           — soft heuristic, lowest signal
	confidence := 80.0
	switch source {
	case "user_correction", "operator_approved":
		confidence = 100.0
	case "image_verify", "image_verify_tenant", "inventory_photo_verify":
		confidence = 95.0
	case "stock_setup_approved", "stock_setup_approved_tenant",
		"stock_setup_ai_brand", "stock_setup_ai_brand_tenant":
		confidence = 90.0
	case "auto_variant":
		confidence = 60.0
	}

	// WS1.4 — tenant→shop demotion (STRICT SHOP ISOLATION). A tenant-wide alias
	// (shop_id NULL) must NEVER bind a product that belongs to a single shop:
	// that is exactly the bleed that made a Mahua Khera purchase match FM Tower's
	// Rockford product. If a tenant-wide write carries a shop-scoped product,
	// rewrite it as a SHOP-SCOPED alias for that product's own shop. Tenant-wide
	// products (shop_id NULL) and name-only writes (productID nil) are unaffected.
	// Done after the confidence tier is computed so confidence is unchanged.
	if tenantShopDemoteEnabled() && shopID == uuid.Nil && productID != nil {
		if pShop, ok := s.productShopScope(tenantID, *productID); ok && pShop != nil {
			log.Printf("LearnAlias: DEMOTED tenant-wide alias %q → product %s to its shop %s (source=%s) — prevents cross-shop bleed", ocrText, productID, *pShop, source)
			shopID = *pShop
			if !strings.HasSuffix(source, "_demoted_shop") {
				source = source + "_demoted_shop"
			}
		}
	}

	// Upsert. Two distinct ON CONFLICT targets — one for tenant-wide rows
	// (shop_id IS NULL) and one for shop-scoped rows (shop_id IS NOT NULL).
	// Both are partial unique indexes created by migration
	// 20260504_add_shop_scope_to_aliases.sql.
	var execErr error
	if shopID == uuid.Nil {
		execErr = s.db.Exec(`
			INSERT INTO ocr_brand_aliases (id, tenant_id, shop_id, canonical_brand_name, product_id, alias_name, occurrence_count, confidence_score, source, created_at, updated_at)
			VALUES (gen_random_uuid(), ?, NULL, ?, ?, ?, 1, ?, ?, NOW(), NOW())
			ON CONFLICT (tenant_id, alias_name) WHERE shop_id IS NULL DO UPDATE SET
				occurrence_count = ocr_brand_aliases.occurrence_count + 1,
				confidence_score = GREATEST(ocr_brand_aliases.confidence_score, EXCLUDED.confidence_score),
				product_id = COALESCE(EXCLUDED.product_id, ocr_brand_aliases.product_id),
				canonical_brand_name = EXCLUDED.canonical_brand_name,
				source = CASE WHEN EXCLUDED.confidence_score > ocr_brand_aliases.confidence_score THEN EXCLUDED.source ELSE ocr_brand_aliases.source END,
				updated_at = NOW()
		`, tenantID, canonicalName, productID, normalized, confidence, source).Error
	} else {
		execErr = s.db.Exec(`
			INSERT INTO ocr_brand_aliases (id, tenant_id, shop_id, canonical_brand_name, product_id, alias_name, occurrence_count, confidence_score, source, created_at, updated_at)
			VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, 1, ?, ?, NOW(), NOW())
			ON CONFLICT (tenant_id, shop_id, alias_name) WHERE shop_id IS NOT NULL DO UPDATE SET
				occurrence_count = ocr_brand_aliases.occurrence_count + 1,
				confidence_score = GREATEST(ocr_brand_aliases.confidence_score, EXCLUDED.confidence_score),
				product_id = COALESCE(EXCLUDED.product_id, ocr_brand_aliases.product_id),
				canonical_brand_name = EXCLUDED.canonical_brand_name,
				source = CASE WHEN EXCLUDED.confidence_score > ocr_brand_aliases.confidence_score THEN EXCLUDED.source ELSE ocr_brand_aliases.source END,
				updated_at = NOW()
		`, tenantID, shopID, canonicalName, productID, normalized, confidence, source).Error
	}

	if execErr != nil {
		log.Printf("AliasService: Failed to learn alias '%s' -> '%s' (shop=%s): %v", ocrText, canonicalName, shopID, execErr)
		return execErr
	}

	// Invalidate cache for both scopes — a tenant-wide write may shadow a
	// shop-scoped read, and vice versa. Cheap to drop both.
	s.invalidateAliasCache(tenantID, uuid.Nil, normalized)
	if shopID != uuid.Nil {
		s.invalidateAliasCache(tenantID, shopID, normalized)
	}

	log.Printf("AliasService: LEARNED '%s' -> '%s' (product: %v, source: %s, shop: %s)", ocrText, canonicalName, productID, source, shopID)
	return nil
}

// isAliasLearnable applies the hygiene guards that don't depend on
// canonical/alias jaccard. Pulled out so other learn paths can reuse.
//
// Rules:
//   (a) alias must be ≥ 2 chars after trim
//   (b) alias must NOT equal the canonical (already encoded in product
//       name → no alias needed)
func (s *AliasService) isAliasLearnable(normalizedAlias, normalizedCanonical string) bool {
	if len(normalizedAlias) < 2 {
		return false
	}
	if normalizedAlias == normalizedCanonical {
		return false
	}
	return true
}

// LearnNegativeAlias is the legacy entry — writes a TENANT-WIDE negative
// rejection. New callers should use LearnNegativeAliasScoped.
func (s *AliasService) LearnNegativeAlias(tenantID uuid.UUID, ocrText string, rejectedProductID uuid.UUID) error {
	return s.LearnNegativeAliasScoped(tenantID, uuid.Nil, ocrText, rejectedProductID)
}

// LearnNegativeAliasScoped records that a user rejected a specific match,
// scoped to (tenant, shop). When shopID == uuid.Nil the rejection is
// tenant-wide (legacy behaviour).
func (s *AliasService) LearnNegativeAliasScoped(tenantID, shopID uuid.UUID, ocrText string, rejectedProductID uuid.UUID) error {
	normalized := strings.ToLower(strings.TrimSpace(ocrText))
	if len(normalized) < 2 {
		return nil
	}

	var err error
	if shopID == uuid.Nil {
		err = s.db.Exec(`
			INSERT INTO ocr_negative_aliases (id, tenant_id, shop_id, alias_name, rejected_product_id, occurrence_count, created_at, updated_at)
			VALUES (gen_random_uuid(), ?, NULL, ?, ?, 1, NOW(), NOW())
			ON CONFLICT (tenant_id, alias_name, rejected_product_id) WHERE shop_id IS NULL DO UPDATE SET
				occurrence_count = ocr_negative_aliases.occurrence_count + 1,
				updated_at = NOW()
		`, tenantID, normalized, rejectedProductID).Error
	} else {
		err = s.db.Exec(`
			INSERT INTO ocr_negative_aliases (id, tenant_id, shop_id, alias_name, rejected_product_id, occurrence_count, created_at, updated_at)
			VALUES (gen_random_uuid(), ?, ?, ?, ?, 1, NOW(), NOW())
			ON CONFLICT (tenant_id, shop_id, alias_name, rejected_product_id) WHERE shop_id IS NOT NULL DO UPDATE SET
				occurrence_count = ocr_negative_aliases.occurrence_count + 1,
				updated_at = NOW()
		`, tenantID, shopID, normalized, rejectedProductID).Error
	}

	if err != nil {
		log.Printf("AliasService: Failed to learn negative alias '%s' !-> '%s' (shop=%s): %v", ocrText, rejectedProductID, shopID, err)
		return err
	}

	log.Printf("AliasService: NEGATIVE '%s' !-> product %s (shop=%s)", ocrText, rejectedProductID, shopID)
	return nil
}

// AliasLearnItem represents a single alias to learn in batch.
type AliasLearnItem struct {
	OCRText       string
	CanonicalName string
	ProductID     *uuid.UUID
	Source        string
}

// BatchLearnAliases efficiently learns multiple TENANT-WIDE aliases in a
// single transaction. Backwards-compatible signature.
func (s *AliasService) BatchLearnAliases(tenantID uuid.UUID, items []AliasLearnItem) error {
	return s.BatchLearnAliasesScoped(tenantID, uuid.Nil, items)
}

// BatchLearnAliasesScoped learns multiple aliases in a single transaction
// scoped to (tenant, shop). shopID == uuid.Nil → tenant-wide.
func (s *AliasService) BatchLearnAliasesScoped(tenantID, shopID uuid.UUID, items []AliasLearnItem) error {
	if len(items) == 0 {
		return nil
	}

	tx := s.db.Begin()
	for _, item := range items {
		normalized := strings.ToLower(strings.TrimSpace(item.OCRText))
		canonicalLower := strings.ToLower(strings.TrimSpace(item.CanonicalName))
		if !s.isAliasLearnable(normalized, canonicalLower) {
			continue
		}

		confidence := 80.0
		if item.Source == "user_correction" {
			confidence = 100.0
		} else if item.Source == "auto_variant" {
			confidence = 60.0
		}

		if shopID == uuid.Nil {
			tx.Exec(`
				INSERT INTO ocr_brand_aliases (id, tenant_id, shop_id, canonical_brand_name, product_id, alias_name, occurrence_count, confidence_score, source, created_at, updated_at)
				VALUES (gen_random_uuid(), ?, NULL, ?, ?, ?, 1, ?, ?, NOW(), NOW())
				ON CONFLICT (tenant_id, alias_name) WHERE shop_id IS NULL DO UPDATE SET
					occurrence_count = ocr_brand_aliases.occurrence_count + 1,
					confidence_score = GREATEST(ocr_brand_aliases.confidence_score, EXCLUDED.confidence_score),
					product_id = COALESCE(EXCLUDED.product_id, ocr_brand_aliases.product_id),
					canonical_brand_name = EXCLUDED.canonical_brand_name,
					updated_at = NOW()
			`, tenantID, item.CanonicalName, item.ProductID, normalized, confidence, item.Source)
		} else {
			tx.Exec(`
				INSERT INTO ocr_brand_aliases (id, tenant_id, shop_id, canonical_brand_name, product_id, alias_name, occurrence_count, confidence_score, source, created_at, updated_at)
				VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, 1, ?, ?, NOW(), NOW())
				ON CONFLICT (tenant_id, shop_id, alias_name) WHERE shop_id IS NOT NULL DO UPDATE SET
					occurrence_count = ocr_brand_aliases.occurrence_count + 1,
					confidence_score = GREATEST(ocr_brand_aliases.confidence_score, EXCLUDED.confidence_score),
					product_id = COALESCE(EXCLUDED.product_id, ocr_brand_aliases.product_id),
					canonical_brand_name = EXCLUDED.canonical_brand_name,
					updated_at = NOW()
			`, tenantID, shopID, item.CanonicalName, item.ProductID, normalized, confidence, item.Source)
		}

		s.invalidateAliasCache(tenantID, uuid.Nil, normalized)
		if shopID != uuid.Nil {
			s.invalidateAliasCache(tenantID, shopID, normalized)
		}
	}

	if err := tx.Commit().Error; err != nil {
		log.Printf("AliasService: Batch learn failed (shop=%s): %v", shopID, err)
		return err
	}

	log.Printf("AliasService: Batch learned %d aliases (shop=%s)", len(items), shopID)
	return nil
}

// DecayUnusedAliases reduces confidence for aliases not used in the last N days.
// Only decays auto_match and auto_variant aliases. User corrections are permanent.
// Operates across all scopes (shop + tenant).
func (s *AliasService) DecayUnusedAliases(daysThreshold int, decayAmount float64) (int64, error) {
	result := s.db.Exec(`
		UPDATE ocr_brand_aliases
		SET confidence_score = GREATEST(confidence_score - ?, 0),
			updated_at = NOW()
		WHERE source IN ('auto_match', 'auto_variant', 'ai_auto', 'auto_learned')
		  AND (last_used_at IS NULL OR last_used_at < NOW() - INTERVAL '1 day' * ?)
		  AND confidence_score > 0
	`, decayAmount, daysThreshold)

	if result.Error != nil {
		return 0, result.Error
	}
	log.Printf("AliasService: Decayed %d unused aliases (threshold: %d days, amount: %.1f)", result.RowsAffected, daysThreshold, decayAmount)
	return result.RowsAffected, nil
}

// PurgeWeakAliases removes aliases with confidence below a threshold.
func (s *AliasService) PurgeWeakAliases(minConfidence float64) (int64, error) {
	result := s.db.Exec(`
		DELETE FROM ocr_brand_aliases
		WHERE confidence_score < ?
		  AND source IN ('auto_match', 'auto_variant', 'ai_auto', 'auto_learned')
	`, minConfidence)

	if result.Error != nil {
		return 0, result.Error
	}
	log.Printf("AliasService: Purged %d weak aliases (below confidence %.1f)", result.RowsAffected, minConfidence)
	return result.RowsAffected, nil
}

// AutoGenerateVariants creates common OCR variants for a new product, scoped
// tenant-wide (these are deterministic patterns derived from the canonical
// name, not shop-specific OCR observations). Source "auto_variant" with
// confidence 60 (lowest priority).
func (s *AliasService) AutoGenerateVariants(tenantID uuid.UUID, productName string, brandName string, productID *uuid.UUID) error {
	variants := generateVariants(productName, brandName)
	if len(variants) == 0 {
		return nil
	}

	items := make([]AliasLearnItem, 0, len(variants))
	for _, v := range variants {
		items = append(items, AliasLearnItem{
			OCRText:       v,
			CanonicalName: productName,
			ProductID:     productID,
			Source:        "auto_variant",
		})
	}

	return s.BatchLearnAliasesScoped(tenantID, uuid.Nil, items)
}

// generateVariants creates common OCR misread/abbreviation variants
func generateVariants(productName, brandName string) []string {
	var variants []string
	name := brandName
	if name == "" {
		name = productName
	}
	nameLower := strings.ToLower(strings.TrimSpace(name))
	words := strings.Fields(nameLower)

	if len(words) == 0 {
		return nil
	}

	// Generate initials: "Blender Pride Premium Whisky" → "bppw"
	if len(words) >= 2 {
		var initials strings.Builder
		for _, w := range words {
			if len(w) > 0 {
				initials.WriteByte(w[0])
			}
		}
		init := initials.String()
		if len(init) >= 2 && len(init) <= 5 {
			variants = append(variants, init)
		}
	}

	// First two words only: "Blender Pride Premium Whisky" → "blender pride"
	if len(words) >= 3 {
		variants = append(variants, strings.Join(words[:2], " "))
	}

	// Without common suffixes: strip "whisky", "rum", "vodka", "beer", "brandy"
	suffixes := []string{"whisky", "whiskey", "rum", "vodka", "beer", "brandy", "gin", "wine", "scotch"}
	for _, suffix := range suffixes {
		if len(words) >= 2 && words[len(words)-1] == suffix {
			stripped := strings.Join(words[:len(words)-1], " ")
			if stripped != nameLower {
				variants = append(variants, stripped)
			}
			break
		}
	}

	return variants
}

// RunMaintenance performs alias table maintenance (call daily from cron).
func (s *AliasService) RunMaintenance() {
	decayed, _ := s.DecayUnusedAliases(30, 5.0)
	purged, _ := s.PurgeWeakAliases(10.0)
	log.Printf("AliasService: Maintenance complete — decayed: %d, purged: %d", decayed, purged)
}

// --- Internal cache helpers ---

func (s *AliasService) cacheAliasResultKeyed(cacheKey string, result aliasCache) {
	if s.redis == nil {
		return
	}
	data, err := json.Marshal(result)
	if err != nil {
		return
	}
	ctx := context.Background()
	s.redis.Set(ctx, cacheKey, data, aliasCacheTTL)
}

func (s *AliasService) invalidateAliasCache(tenantID, shopID uuid.UUID, normalized string) {
	if s.redis == nil {
		return
	}
	cacheKey := fmt.Sprintf("%s%s:%s:%s", aliasCachePrefix, tenantID.String()[:8], shopCacheTag(shopID), normalized)
	ctx := context.Background()
	s.redis.Del(ctx, cacheKey)
}

