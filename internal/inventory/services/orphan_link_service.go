package services

import (
	"fmt"
	"log"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// LinkOrphanToMasterRequest is the payload for POST /products/:id/link-master.
//
// When SaasBrandID is provided, the product is linked to that exact master
// brand. When SaasBrandID is empty, the service asks findMasterBrand to
// auto-pick the best candidate for the product's current name+MRP — useful
// from the Flutter banner where the user wants "just link it to the obvious
// match" without opening a picker. Returns an error when auto-pick can't
// reach a confident match so we never link to a wrong master silently.
type LinkOrphanToMasterRequest struct {
	ProductID   string `json:"-"`             // path param — never trust body
	TenantID    string `json:"-"`             // auth context
	SaasBrandID string `json:"saas_brand_id"` // optional: explicit master pick
}

// LinkOrphanToMasterResult describes what happened so the Flutter layer can
// render an informative snackbar + refresh the orphan list.
type LinkOrphanToMasterResult struct {
	ProductID         string  `json:"product_id"`
	LinkedSaasBrandID string  `json:"linked_saas_brand_id"`
	MasterName        string  `json:"master_name"`
	MasterDisplay     string  `json:"master_display_name,omitempty"`
	MasterMRP         float64 `json:"master_mrp,omitempty"`
	AutoPicked        bool    `json:"auto_picked"`           // true when we chose the master, not the user
	Score             float64 `json:"auto_pick_score,omitempty"`
}

// LinkOrphanToMaster links a single tenant product to a saas_brands entry.
// Guards:
//   - product must belong to the caller's tenant (prevents cross-tenant writes);
//   - product must be an orphan (saas_brand_id NULL) — this endpoint never
//     overwrites an existing link so typos in the picker can't silently
//     corrupt already-linked products;
//   - target master must exist and be non-deleted;
//   - auto-pick path requires scoreMasterBrand ≥ 0.55 (same bar as findMasterBrand).
//
// On success, inferred excise name+display are written back to the product row
// so the next extraction renders `Excise:` without another round trip.
func (s *SmartStockSetupService) LinkOrphanToMaster(req LinkOrphanToMasterRequest) (*LinkOrphanToMasterResult, error) {
	if req.ProductID == "" {
		return nil, fmt.Errorf("product_id is required")
	}
	tenantUUID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}
	productUUID, err := uuid.Parse(req.ProductID)
	if err != nil {
		return nil, fmt.Errorf("invalid product_id")
	}

	// Load the product (authoritative values — never trust the body for name/mrp)
	var prod struct {
		ID          string
		Name        string
		DisplayName string
		Size        string
		MRP         float64
		SaasBrandID *string
		CategoryID  string
	}
	err = s.db.Table("products").
		Select(`id::text, name,
			COALESCE(NULLIF(display_name, ''), '') AS display_name,
			size, mrp,
			saas_brand_id::text AS saas_brand_id,
			category_id::text AS category_id`).
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", productUUID, tenantUUID).
		First(&prod).Error
	if err != nil {
		return nil, fmt.Errorf("product not found")
	}
	if prod.SaasBrandID != nil && *prod.SaasBrandID != "" {
		// Already linked — refuse silently-overwriting. The user asked for
		// "link orphan"; if they want to re-link, they should unlink first
		// (separate endpoint if we ever build one).
		return nil, fmt.Errorf("product is already linked to a master brand; cannot re-link via this endpoint")
	}

	// Resolve tenant's state (master catalog is state-scoped) to scope the auto-pick search.
	tenantState := ""
	_ = s.db.Table("tenants").Select("state").Where("id = ?", tenantUUID).Scan(&tenantState).Error

	sizeML := normalizeSizeText(prod.Size)

	// Resolve target master — either explicit or auto-pick.
	var target *models.MasterBrandInfo
	autoPicked := false
	autoPickScore := 0.0

	if req.SaasBrandID != "" {
		targetUUID, err := uuid.Parse(req.SaasBrandID)
		if err != nil {
			return nil, fmt.Errorf("invalid saas_brand_id")
		}
		var m models.MasterBrandInfo
		// State lives on `brand_variants`, NOT `saas_brands`. Previous SELECT
		// tried to read `saas_brands.state` which doesn't exist → 400
		// "target master brand not found or deleted" even for valid brand ids.
		// State is recovered below via brand_variants at variant-lookup time.
		//
		// Also: use `Scan` instead of `First` so GORM doesn't auto-inject
		// `ORDER BY variant_id` (the struct's first field) — that column
		// doesn't exist on saas_brands and caused a second 42703 error.
		err = s.db.Table("saas_brands").
			Select(`id::text AS brand_id, name AS brand_name,
				COALESCE(display_name, '') AS display_name,
				display_name_bold_start, display_name_bold_length`).
			Where("id = ? AND deleted_at IS NULL", targetUUID).
			Limit(1).
			Scan(&m).Error
		if err != nil || m.BrandID == "" {
			return nil, fmt.Errorf("target master brand not found or deleted")
		}
		target = &m
	} else {
		// Auto-pick from the size-scoped master slice so we don't link to a
		// 750ml brand when the tenant product is 180ml.
		masters := s.loadMasterBrands(sizeML, tenantState)
		searchText := firstNonEmpty(prod.DisplayName, prod.Name)
		if searchText == "" {
			return nil, fmt.Errorf("cannot auto-link: product has no usable name")
		}
		m := s.findMasterBrand(searchText, sizeML, prod.MRP, masters)
		if m == nil || m.BrandID == "" {
			return nil, fmt.Errorf("cannot auto-link: no confident master candidate for %q (rename or pick manually)", searchText)
		}
		target = m
		autoPicked = true
		// Re-score to surface the score to the UI
		if s2, _ := scoreMasterBrand(strings.ToLower(searchText), m, prod.MRP); s2 > 0 {
			autoPickScore = s2
		}
	}

	// Resolve the target's variant row at our size for saas_variant_id enrichment.
	var variantID string
	_ = s.db.Table("brand_variants").
		Select("id::text").
		Where("brand_id = ? AND UPPER(size) = UPPER(?) AND deleted_at IS NULL", target.BrandID, prod.Size).
		Scan(&variantID).Error

	// Variant-slot conflict resolution: if another tenant product is already
	// linked to this variant, skip variant-level linkage and do brand-only.
	// This happens when the tenant has two duplicate SKUs (e.g. "Rockford
	// Fine" and "Dummy- Rockford Fine" at 750ML) — the DB's unique index on
	// (tenant_id, saas_variant_id) would reject the second link. Brand-only
	// linkage still gives the product excise-name resolution and autofix
	// reports; only the variant-level 1-1 guarantee is relaxed.
	if variantID != "" {
		var taken int64
		_ = s.db.Table("products").
			Where("tenant_id = ? AND saas_variant_id = ? AND deleted_at IS NULL AND id <> ?",
				tenantUUID, variantID, productUUID).
			Count(&taken).Error
		if taken > 0 {
			log.Printf("Smart Stock Setup: link-master variant %s already taken by another product — brand-only link", variantID)
			variantID = ""
		}
	}

	// Infer excise display if the master didn't supply one (defensive — enrichment
	// in extractions already handles this, but link-master is a direct edit path).
	exciseName := target.BrandName
	exciseDisplay := target.DisplayName
	if exciseDisplay == "" {
		exciseDisplay = shortenForDisplay(target.BrandName)
	}

	// Run in a transaction so the product update + excise backfill stay consistent.
	tx := s.db.Begin()
	if tx.Error != nil {
		return nil, fmt.Errorf("begin tx: %w", tx.Error)
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// `excise_brand_name` / `excise_display_name` are NOT columns on the
	// `products` table in production — those values are resolved at query
	// time via the saas_brand_id JOIN. Writing them here was a 42703 error
	// source (SQLSTATE column-does-not-exist) that broke every single link
	// call from the Data Hygiene picker.
	updates := map[string]interface{}{
		"saas_brand_id": target.BrandID,
		"updated_at":    time.Now(),
	}
	_ = exciseName    // retained for logging / result payload only
	_ = exciseDisplay // retained for logging / result payload only
	if variantID != "" {
		updates["saas_variant_id"] = variantID
	}
	if target.DisplayNameBoldStart != nil {
		updates["display_name_bold_start"] = *target.DisplayNameBoldStart
	}
	if target.DisplayNameBoldLength != nil {
		updates["display_name_bold_length"] = *target.DisplayNameBoldLength
	}

	// The saas_brand_id IS NULL guard is a safety net against races: if two
	// link calls fire concurrently, only the first one writes. We already
	// refused the request above when the product was linked, but a concurrent
	// linker could sneak in between the read and the update.
	res := tx.Table("products").
		Where("id = ? AND tenant_id = ? AND saas_brand_id IS NULL", productUUID, tenantUUID).
		Updates(updates)
	if res.Error != nil {
		tx.Rollback()
		return nil, fmt.Errorf("update product: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		tx.Rollback()
		return nil, fmt.Errorf("product was linked concurrently; retry after refresh")
	}
	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}

	log.Printf("Smart Stock Setup: link-master — tenant=%s product=%s → master=%s (%s) auto=%v score=%.2f",
		req.TenantID, req.ProductID, target.BrandID, target.BrandName, autoPicked, autoPickScore)

	return &LinkOrphanToMasterResult{
		ProductID:         req.ProductID,
		LinkedSaasBrandID: target.BrandID,
		MasterName:        target.BrandName,
		MasterDisplay:     target.DisplayName,
		MasterMRP:         target.MRP,
		AutoPicked:        autoPicked,
		Score:             autoPickScore,
	}, nil
}

// SearchMasterBrandsRequest feeds the link-master picker. Flutter calls this
// as the user types in the bottom sheet so candidates always reflect the
// latest query.
type SearchMasterBrandsRequest struct {
	TenantID   string `json:"-"`
	Query      string `json:"query"`
	Size       string `json:"size"`        // optional — restrict candidates to this size
	CategoryID string `json:"category_id"` // optional — restrict candidates to this category
	Limit      int    `json:"limit"`
}

// SearchMasterBrands returns ranked master-brand candidates.
//
// Two modes:
//   - Search mode (Query non-empty): ranks via scoreMasterBrand so picker order
//     matches the extraction scorer.
//   - Browse mode (Query empty): returns alphabetical list of brands, dedup'd
//     by brand_id so the user sees one row per brand even when multiple
//     variants exist. Drives the "tap the field with no typing to see what's
//     available in this category+size" UX on the Add-Missing picker.
//
// CategoryID, when supplied, filters both modes to variants in that category.
func (s *SmartStockSetupService) SearchMasterBrands(req SearchMasterBrandsRequest) ([]MasterBrandSuggestion, error) {
	q := strings.TrimSpace(req.Query)
	limit := req.Limit
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	tenantUUID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}
	tenantState := ""
	_ = s.db.Table("tenants").Select("state").Where("id = ?", tenantUUID).Scan(&tenantState).Error

	sizeML := normalizeSizeText(req.Size)
	masters := s.loadMasterBrands(sizeML, tenantState)
	mastersAfterSize := len(masters)

	// Category filter runs in-memory so loadMasterBrands keeps its existing
	// signature (called by every extraction path — don't want to widen it for
	// one caller).
	if strings.TrimSpace(req.CategoryID) != "" {
		wanted := strings.TrimSpace(req.CategoryID)
		filtered := make([]models.MasterBrandInfo, 0, len(masters))
		for i := range masters {
			if masters[i].CategoryID == wanted {
				filtered = append(filtered, masters[i])
			}
		}
		masters = filtered
	}
	mastersAfterCat := len(masters)

	log.Printf("SearchMasterBrands: q=%q size=%q→sizeML=%d category=%q tenant_state=%q masters=%d→%d (after size→cat)",
		q, req.Size, sizeML, req.CategoryID, tenantState, mastersAfterSize, mastersAfterCat)

	if q == "" {
		out := browseMasterBrands(masters, limit)
		log.Printf("SearchMasterBrands: browse mode returned %d results", len(out))
		return out, nil
	}
	// Run the ranked scorer first — it handles fuzzy/typo-tolerant matches and
	// distinctive-token overlap. For very short queries (< 4 chars) or when the
	// scorer rejects everything below its 0.35 threshold, fall back to a
	// substring match so a user typing "roy" still sees every "Royal …" brand
	// instead of an empty dropdown. The substring path preserves category +
	// size filtering because `masters` is already scoped.
	ranked := s.findMasterBrandCandidates(q, sizeML, 0, masters, limit)
	if len(ranked) > 0 {
		log.Printf("SearchMasterBrands: ranked path returned %d results (top: %q)", len(ranked), ranked[0].DisplayName)
		return ranked, nil
	}
	out := substringMasterBrands(masters, q, limit)
	log.Printf("SearchMasterBrands: ranked path empty → substring fallback returned %d results", len(out))
	return out, nil
}

// substringMasterBrands returns brands whose display_name or brand_name
// contains the query as a case-insensitive substring. Used as a last-resort
// fallback when the ranked scorer rejects every candidate — typically on
// short prefixes ("roy", "jw") and typo-heavy OCR strings. Results are
// alphabetical, dedup'd by brand_id, prefix matches first (a user typing
// "roy" expects "Royal Stag" before "Corroyal Reserve").
func substringMasterBrands(masters []models.MasterBrandInfo, query string, limit int) []MasterBrandSuggestion {
	if len(masters) == 0 || limit <= 0 {
		return []MasterBrandSuggestion{}
	}
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return []MasterBrandSuggestion{}
	}
	type pick struct {
		mb          *models.MasterBrandInfo
		sortKey     string
		prefixScore int // 0 = prefix match, 1 = word-boundary match, 2 = substring
	}
	byBrand := make(map[string]pick, len(masters))
	for i := range masters {
		m := &masters[i]
		dn := strings.ToLower(m.DisplayName)
		bn := strings.ToLower(m.BrandName)
		var score int = -1
		switch {
		case strings.HasPrefix(dn, q) || strings.HasPrefix(bn, q):
			score = 0
		case strings.Contains(" "+dn, " "+q) || strings.Contains(" "+bn, " "+q):
			score = 1
		case strings.Contains(dn, q) || strings.Contains(bn, q):
			score = 2
		}
		if score < 0 {
			continue
		}
		key := m.BrandID
		if key == "" {
			key = "name:" + bn
		}
		sortKey := firstNonEmpty(dn, bn)
		cur, ok := byBrand[key]
		if !ok || score < cur.prefixScore || (score == cur.prefixScore && m.MRP > cur.mb.MRP) {
			byBrand[key] = pick{mb: m, sortKey: sortKey, prefixScore: score}
		}
	}
	picks := make([]pick, 0, len(byBrand))
	for _, p := range byBrand {
		picks = append(picks, p)
	}
	sort.SliceStable(picks, func(i, j int) bool {
		if picks[i].prefixScore != picks[j].prefixScore {
			return picks[i].prefixScore < picks[j].prefixScore
		}
		return picks[i].sortKey < picks[j].sortKey
	})
	if len(picks) > limit {
		picks = picks[:limit]
	}
	out := make([]MasterBrandSuggestion, 0, len(picks))
	for _, p := range picks {
		dn := p.mb.DisplayName
		if dn == "" {
			dn = p.mb.BrandName
		}
		// Confidence reflects match quality: prefix > word-boundary > substring.
		// Kept below scorer thresholds (>0.35) so callers that compare can
		// distinguish a ranked hit from a substring fallback.
		conf := 0.30 - float64(p.prefixScore)*0.05
		out = append(out, MasterBrandSuggestion{
			BrandID:               p.mb.BrandID,
			VariantID:             p.mb.VariantID,
			BrandName:             p.mb.BrandName,
			DisplayName:           dn,
			DisplayNameBoldStart:  p.mb.DisplayNameBoldStart,
			DisplayNameBoldLength: p.mb.DisplayNameBoldLength,
			Size:                  p.mb.Size,
			MRP:                   p.mb.MRP,
			Confidence:            conf,
		})
	}
	return out
}

// browseMasterBrands turns a master-brand slice into a dedup'd, alphabetical
// suggestion list. One row per brand_id (smallest MRP variant wins the tie)
// so the browse-mode picker doesn't surface "Royal Stag 180ml" and "Royal
// Stag 750ml" as separate rows when size isn't filtered.
func browseMasterBrands(masters []models.MasterBrandInfo, limit int) []MasterBrandSuggestion {
	if len(masters) == 0 || limit <= 0 {
		return []MasterBrandSuggestion{}
	}
	type pick struct {
		mb   *models.MasterBrandInfo
		sort string
	}
	byBrand := make(map[string]pick, len(masters))
	for i := range masters {
		m := &masters[i]
		key := m.BrandID
		if key == "" {
			key = "name:" + strings.ToLower(m.BrandName)
		}
		cur, ok := byBrand[key]
		if !ok {
			byBrand[key] = pick{mb: m, sort: strings.ToLower(firstNonEmpty(m.DisplayName, m.BrandName))}
			continue
		}
		// Prefer the variant with the larger MRP (usually the "headline" size)
		// so the picker surfaces the recognizable flagship entry. Falls back
		// to first-seen when MRPs are identical.
		if m.MRP > cur.mb.MRP {
			byBrand[key] = pick{mb: m, sort: cur.sort}
		}
	}
	picks := make([]pick, 0, len(byBrand))
	for _, p := range byBrand {
		picks = append(picks, p)
	}
	sort.SliceStable(picks, func(i, j int) bool { return picks[i].sort < picks[j].sort })
	if len(picks) > limit {
		picks = picks[:limit]
	}
	out := make([]MasterBrandSuggestion, 0, len(picks))
	for _, p := range picks {
		dn := p.mb.DisplayName
		if dn == "" {
			dn = p.mb.BrandName
		}
		out = append(out, MasterBrandSuggestion{
			BrandID:               p.mb.BrandID,
			VariantID:             p.mb.VariantID,
			BrandName:             p.mb.BrandName,
			DisplayName:           dn,
			DisplayNameBoldStart:  p.mb.DisplayNameBoldStart,
			DisplayNameBoldLength: p.mb.DisplayNameBoldLength,
			Size:                  p.mb.Size,
			MRP:                   p.mb.MRP,
			Confidence:            0,
		})
	}
	return out
}

// GetStockSetupAuditRequest scopes the audit fetch.
type GetStockSetupAuditRequest struct {
	TenantID   string
	CategoryID string
	Size       string
}

// GetStockSetupAudit returns the current data-hygiene audit for a tenant
// scoped to category+size, so the Flutter review screen can refresh the
// orphan-count banner after a user action (manual link, apply) without
// re-running the full extraction. Mirrors what buildExtractionAudit does in
// the extraction pipeline but sourced from live DB state.
//
// Size-only and category-only scopes are both accepted. Empty scope returns
// orphans across the whole tenant.
func (s *SmartStockSetupService) GetStockSetupAudit(req GetStockSetupAuditRequest) (*StockSetupAudit, error) {
	tenantUUID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}

	sizeML := 0
	if req.Size != "" {
		sizeML = normalizeSizeText(req.Size)
	}

	query := s.db.Table("products").
		Select(`products.id::text AS id, products.name, products.size,
			COALESCE(products.mrp, 0) AS mrp,
			COALESCE(NULLIF(products.display_name, ''), '') AS display_name,
			COALESCE(brands.name, '') AS brand_name`).
		Joins("LEFT JOIN brands ON products.brand_id = brands.id").
		Where("products.tenant_id = ? AND products.deleted_at IS NULL", tenantUUID).
		Where("(products.saas_brand_id IS NULL OR products.saas_brand_id::text = '')")

	if req.CategoryID != "" {
		catUUID, perr := uuid.Parse(req.CategoryID)
		if perr == nil {
			query = query.Where("products.category_id = ?", catUUID)
		}
	}

	type orphanRow struct {
		ID          string
		Name        string
		Size        string
		MRP         float64
		DisplayName string
		BrandName   string
	}
	var rows []orphanRow
	if err := query.Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("load orphans: %w", err)
	}

	orphans := make([]OrphanTenantProduct, 0, len(rows))
	for i := range rows {
		r := &rows[i]
		if sizeML > 0 {
			pSizeML := normalizeSizeText(r.Size)
			if pSizeML > 0 && pSizeML != sizeML {
				continue
			}
		}
		name := firstNonEmpty(r.DisplayName, r.BrandName, r.Name)
		orphans = append(orphans, OrphanTenantProduct{
			ProductID: r.ID,
			Name:      name,
			Size:      r.Size,
			MRP:       r.MRP,
		})
	}

	if len(orphans) == 0 {
		return &StockSetupAudit{}, nil
	}
	return &StockSetupAudit{OrphanProducts: orphans}, nil
}

