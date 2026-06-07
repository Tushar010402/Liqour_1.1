package services

import (
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// OrphanAutofixRequest drives the safe bulk cleanup of orphan tenant products.
//
// DryRun defaults to TRUE via the handler — the endpoint MUST be explicitly
// called with dry_run=false to mutate data. This is a hard rule in the
// request path so a bad click can't silently delete products or mis-link
// them to wrong master brands.
type OrphanAutofixRequest struct {
	TenantID string `json:"-"` // auth context
	DryRun   bool   `json:"-"` // handler wires from query param; never trust body
}

// OrphanAutofixResult summarises what autofix did (or would do on a dry-run).
type OrphanAutofixResult struct {
	DryRun   bool                    `json:"dry_run"`
	Deleted  []OrphanAutofixProduct  `json:"deleted,omitempty"`   // soft-deleted test-data rows
	Linked   []OrphanAutofixLink     `json:"linked,omitempty"`    // typo-rescued + linked to master
	Flagged  []OrphanAutofixFlagged  `json:"flagged,omitempty"`   // couldn't auto-fix; user must decide
	Counts   OrphanAutofixCounts     `json:"counts"`
}

type OrphanAutofixCounts struct {
	Deleted int `json:"deleted"`
	Linked  int `json:"linked"`
	Flagged int `json:"flagged"`
}

// OrphanAutofixProduct identifies a row that was (or would be) soft-deleted.
type OrphanAutofixProduct struct {
	ProductID string `json:"product_id"`
	Name      string `json:"name"`
	Reason    string `json:"reason"` // e.g. "test_data_in_test_tenant"
}

// OrphanAutofixLink records a successful typo-swap + master link.
type OrphanAutofixLink struct {
	ProductID      string  `json:"product_id"`
	OriginalName   string  `json:"original_name"`
	CorrectedName  string  `json:"corrected_name"`
	MasterBrandID  string  `json:"master_brand_id"`
	MasterName     string  `json:"master_name"`
	Score          float64 `json:"score"`
}

// OrphanAutofixFlagged is a row that couldn't be auto-fixed — reason is set so
// the Flutter UI can explain WHY and tell the user what to do (rename, set MRP,
// pick manually, etc.).
type OrphanAutofixFlagged struct {
	ProductID string `json:"product_id"`
	Name      string `json:"name"`
	Size      string `json:"size,omitempty"`
	Reason    string `json:"reason"` // "mrp_missing", "ambiguous", "not_in_master"
}

// Test-data detection: name starts with "Test " (case-insensitive) AND tenant
// name contains "test". Both gates must be satisfied so we never touch real
// customer data that happens to have "test" in a product name.
var testProductNamePattern = regexp.MustCompile(`(?i)^test\s+\w+`)

// typoSwaps is the hand-curated list of single-character name drift that
// shows up in production. Left side = the typoed token seen in tenant
// products; right side = the canonical master form. Matching is
// case-insensitive, whole-word only (not substring) to prevent
// over-rewrites like "Blender" in "Cocktail Blender" being incorrectly
// expanded to "Blenders" for non-Blenders-Pride brands.
//
// Expand this list cautiously — every addition is a commitment that the
// substitution is safe in ALL contexts. When in doubt, leave the row for
// the user to fix via the picker.
var typoSwaps = map[string]string{
	"blender":  "blenders",  // Trinken "Blender Pride" → "Blenders Pride"
	"movement": "moments",   // Trinken "Magic Movement" → "Magic Moments"
	"rathmbore": "ranthambore", // Trinken "Royal Rathmbore" → "Royal Ranthambore"
}

// OrphansAutofix runs a strictly-safe cleanup pass on the caller's tenant.
// See OrphanAutofixRequest for the dry-run contract.
//
// Safe operations (only these — no broad name-rewriting, no aggressive
// matching, no cross-tenant writes):
//  1. Soft-delete products whose name matches ^Test\s+\w+ AND whose tenant
//     name contains "test" (case-insensitive).
//  2. Typo-swap using typoSwaps then call findMasterBrand. If the corrected
//     name matches a master with score ≥0.70 AND hasDistinctiveMatch AND
//     the tenant product's MRP matches the master within ±₹30, apply the
//     rename + link-master.
//  3. Everything else → flagged with a reason so the Flutter banner can
//     explain what the user needs to do.
func (s *SmartStockSetupService) OrphansAutofix(req OrphanAutofixRequest) (*OrphanAutofixResult, error) {
	tenantUUID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant_id")
	}

	// Tenant name + state — state scopes the master catalog; tenant name
	// gates the test-data deletion.
	var tenant struct {
		Name  string
		State string
	}
	if err := s.db.Table("tenants").
		Select("name, COALESCE(state, '') AS state").
		Where("id = ?", tenantUUID).First(&tenant).Error; err != nil {
		return nil, fmt.Errorf("tenant not found")
	}
	tenantNameLower := strings.ToLower(tenant.Name)

	// Load all orphan products for this tenant. Not size-scoped: autofix is a
	// cleanup pass, not an extraction. (If this becomes slow for tenants with
	// thousands of orphans, we'll add pagination.)
	type orphan struct {
		ID          string
		Name        string
		DisplayName string
		Size        string
		MRP         float64
		SellingPrice float64
	}
	var orphans []orphan
	err = s.db.Table("products").
		Select(`id::text, name,
			COALESCE(NULLIF(display_name, ''), '') AS display_name,
			size, mrp, selling_price`).
		Where("tenant_id = ? AND deleted_at IS NULL AND saas_brand_id IS NULL", tenantUUID).
		Scan(&orphans).Error
	if err != nil {
		return nil, fmt.Errorf("load orphans: %w", err)
	}

	result := &OrphanAutofixResult{DryRun: req.DryRun}

	// Pre-load master catalog once (state-scoped, any size so rename paths
	// across sizes all share one lookup).
	masters := s.loadMasterBrands(0, tenant.State)
	// Build a size → masters index so the strong-match path can scope its
	// candidate pool to the orphan's size. Prevents a 750ML orphan from
	// matching a 180ML master variant just because the MRP and name line up.
	mastersBySize := make(map[string][]models.MasterBrandInfo, 8)
	for i := range masters {
		key := strings.ToUpper(strings.TrimSpace(masters[i].Size))
		mastersBySize[key] = append(mastersBySize[key], masters[i])
	}

	// Conservative subset-matcher fallback — runs whenever the scorer-based
	// paths reject an orphan. Linkss if (and only if) the orphan's
	// distinctive tokens are a clean subset of EXACTLY ONE master brand's
	// tokens with MRP still in tolerance. Handles the two classes of orphan
	// the main scorer misses:
	//   1. Name-identical-but-size-suffix-drags-levenshtein-down cases
	//      ("8 PM Premium Black Superior Whisky - 180ml" → master "8 PM
	//      Premium Black Superior Whisky") where Levenshtein+family-root
	//      gate combine to score below 0.85 even though the orphan's
	//      distinctive phrase lives verbatim in the master.
	//   2. Cross-size-only masters: orphan at 180ML whose brand's only master
	//      variant is at 750ML. We keep `saas_variant_id` NULL in that case
	//      so the link reflects reality ("brand match, size unavailable").
	trySafeLink := func(o orphan) *models.MasterBrandInfo {
		return s.trySafeAutoLinkMaster(o.Name, o.Size, effectiveMRPFromRow(o.MRP, o.SellingPrice), masters)
	}

	// Deletion candidates first — name gate + tenant gate both required.
	isTestTenant := strings.Contains(tenantNameLower, "test")
	toDelete := make([]string, 0)
	for _, o := range orphans {
		if isTestTenant && testProductNamePattern.MatchString(strings.TrimSpace(o.Name)) {
			result.Deleted = append(result.Deleted, OrphanAutofixProduct{
				ProductID: o.ID, Name: o.Name, Reason: "test_data_in_test_tenant",
			})
			toDelete = append(toDelete, o.ID)
		}
	}

	// Typo-rescue + link candidates. Skip anything already queued for deletion.
	deletedSet := make(map[string]bool, len(toDelete))
	for _, id := range toDelete {
		deletedSet[id] = true
	}
	type linkCandidate struct {
		orphan         orphan
		corrected      string
		master         *models.MasterBrandInfo
		score          float64
	}
	var links []linkCandidate

	for _, o := range orphans {
		if deletedSet[o.ID] {
			continue
		}
		corrected, applied := applyTypoSwaps(o.Name)
		if !applied {
			// No typo swap needed — but try a STRONG-MATCH auto-link on the raw
			// name. When the orphan's name scores ≥0.85 against a master AND has
			// a distinctive-token match AND the MRP lines up within ±₹30, the
			// link is safe to apply in bulk. Fills the gap where read-time
			// master-routing only fires during a Smart Stock Setup session, so
			// orphans that were never in an extraction stay orphan forever.
			searchRate := effectiveMRPFromRow(o.MRP, o.SellingPrice)
			// Scope candidates to the orphan's size so a 180ML tenant product
			// can't accidentally link to a 750ML master variant at a similar
			// rate.
			scopedMasters := masters
			if o.Size != "" {
				if sameSize, ok := mastersBySize[strings.ToUpper(strings.TrimSpace(o.Size))]; ok && len(sameSize) > 0 {
					scopedMasters = sameSize
				}
			}
			m := s.findMasterBrand(o.Name, normalizeSizeText(o.Size), searchRate, scopedMasters)
			if m == nil {
				if safe := trySafeLink(o); safe != nil {
					links = append(links, linkCandidate{orphan: o, corrected: o.Name, master: safe, score: 0.88})
					continue
				}
				reason := "not_in_master"
				if o.MRP == 0 && o.SellingPrice == 0 {
					reason = "mrp_missing"
				}
				result.Flagged = append(result.Flagged, OrphanAutofixFlagged{
					ProductID: o.ID, Name: o.Name, Size: o.Size, Reason: reason,
				})
				continue
			}
			// Re-score to apply the strong-match gate.
			score, hasDist := scoreMasterBrand(strings.ToLower(o.Name), m, searchRate)
			if !hasDist || score < 0.85 {
				if safe := trySafeLink(o); safe != nil {
					links = append(links, linkCandidate{orphan: o, corrected: o.Name, master: safe, score: 0.88})
					continue
				}
				result.Flagged = append(result.Flagged, OrphanAutofixFlagged{
					ProductID: o.ID, Name: o.Name, Size: o.Size, Reason: "low_confidence_match",
				})
				continue
			}
			// MRP guard — same ±₹30 tolerance as the typo-rescue path.
			if m.MRP > 0 && searchRate > 0 {
				diff := m.MRP - searchRate
				if diff < 0 {
					diff = -diff
				}
				if diff > 30 {
					if safe := trySafeLink(o); safe != nil {
						links = append(links, linkCandidate{orphan: o, corrected: o.Name, master: safe, score: 0.88})
						continue
					}
					result.Flagged = append(result.Flagged, OrphanAutofixFlagged{
						ProductID: o.ID, Name: o.Name, Size: o.Size, Reason: "mrp_mismatch",
					})
					continue
				}
			}
			// Strong match — queue as a link candidate. corrected stays as the
			// original name; renameToMasterDisplay will decide whether to adopt
			// the master's display name or keep the tenant's.
			links = append(links, linkCandidate{
				orphan:    o,
				corrected: o.Name,
				master:    m,
				score:     score,
			})
			continue
		}

		// Score the corrected name against master.
		searchRate := effectiveMRPFromRow(o.MRP, o.SellingPrice)
		m := s.findMasterBrand(corrected, normalizeSizeText(o.Size), searchRate, masters)
		if m == nil || m.BrandID == "" {
			result.Flagged = append(result.Flagged, OrphanAutofixFlagged{
				ProductID: o.ID, Name: o.Name, Size: o.Size, Reason: "typo_swap_unmatched",
			})
			continue
		}
		// Re-score directly to get a float to compare against the 0.70 gate.
		score, hasDist := scoreMasterBrand(strings.ToLower(corrected), m, searchRate)
		if !hasDist || score < 0.70 {
			result.Flagged = append(result.Flagged, OrphanAutofixFlagged{
				ProductID: o.ID, Name: o.Name, Size: o.Size, Reason: "typo_swap_low_confidence",
			})
			continue
		}
		// MRP guard: require the master's MRP to be within ±₹30 of the tenant's
		// effective price. Prevents a typo-rescue from linking a ₹200 tenant
		// product to a ₹2000 master just because the name shape matched.
		if m.MRP > 0 && searchRate > 0 {
			diff := m.MRP - searchRate
			if diff < 0 {
				diff = -diff
			}
			if diff > 30 {
				result.Flagged = append(result.Flagged, OrphanAutofixFlagged{
					ProductID: o.ID, Name: o.Name, Size: o.Size, Reason: "typo_swap_mrp_mismatch",
				})
				continue
			}
		}
		links = append(links, linkCandidate{orphan: o, corrected: corrected, master: m, score: score})
	}

	// Populate result.Linked preview even on dry-run so the user can review.
	for _, lc := range links {
		result.Linked = append(result.Linked, OrphanAutofixLink{
			ProductID:     lc.orphan.ID,
			OriginalName:  lc.orphan.Name,
			CorrectedName: renameToMasterDisplay(lc.corrected, lc.master),
			MasterBrandID: lc.master.BrandID,
			MasterName:    lc.master.BrandName,
			Score:         lc.score,
		})
	}

	result.Counts = OrphanAutofixCounts{
		Deleted: len(result.Deleted),
		Linked:  len(result.Linked),
		Flagged: len(result.Flagged),
	}

	if req.DryRun {
		log.Printf("Smart Stock Setup: autofix DRY-RUN tenant=%s — would delete=%d link=%d flag=%d",
			req.TenantID, result.Counts.Deleted, result.Counts.Linked, result.Counts.Flagged)
		return result, nil
	}

	// Real run — apply in a single transaction so a mid-way failure rolls
	// everything back (don't half-delete half-link).
	tx := s.db.Begin()
	if tx.Error != nil {
		return nil, fmt.Errorf("begin tx: %w", tx.Error)
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	now := time.Now()

	// Deletions
	if len(toDelete) > 0 {
		if err := tx.Table("products").
			Where("id IN ? AND tenant_id = ? AND saas_brand_id IS NULL", toDelete, tenantUUID).
			Updates(map[string]interface{}{"deleted_at": now}).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("soft-delete: %w", err)
		}
	}

	// Typo-rename + link. `excise_brand_name` / `excise_display_name` are
	// resolved at query time via saas_brand_id JOIN — they don't exist as
	// columns on the `products` table. Writing them caused a 42703
	// column-does-not-exist error that made bulk autofix fail silently.
	for _, lc := range links {
		updates := map[string]interface{}{
			"name":          renameToMasterDisplay(lc.corrected, lc.master),
			"saas_brand_id": lc.master.BrandID,
			"updated_at":    now,
		}
		// Write `saas_variant_id` only when the matched master variant's size
		// equals the orphan's size — otherwise this is a cross-size link
		// (brand matched but no variant exists at the orphan's size) and
		// leaving variant_id NULL accurately reflects that reality.
		if lc.master.VariantID != "" &&
			strings.EqualFold(strings.TrimSpace(lc.master.Size), strings.TrimSpace(lc.orphan.Size)) {
			if vid, err := uuid.Parse(lc.master.VariantID); err == nil {
				updates["saas_variant_id"] = vid
			}
		}
		if lc.master.DisplayNameBoldStart != nil {
			updates["display_name_bold_start"] = *lc.master.DisplayNameBoldStart
		}
		if lc.master.DisplayNameBoldLength != nil {
			updates["display_name_bold_length"] = *lc.master.DisplayNameBoldLength
		}
		if err := tx.Table("products").
			Where("id = ? AND tenant_id = ? AND saas_brand_id IS NULL", lc.orphan.ID, tenantUUID).
			Updates(updates).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("typo-link %s: %w", lc.orphan.ID, err)
		}
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	log.Printf("Smart Stock Setup: autofix COMMITTED tenant=%s — deleted=%d linked=%d flagged=%d",
		req.TenantID, result.Counts.Deleted, result.Counts.Linked, result.Counts.Flagged)
	return result, nil
}

// applyTypoSwaps walks each whole-word token in name and substitutes any
// known typo. Returns (newName, didSwap) where didSwap is true only when at
// least one substitution fired — used by the caller to skip rows that don't
// look like our known typos.
func applyTypoSwaps(name string) (string, bool) {
	fields := strings.Fields(name)
	applied := false
	for i, tok := range fields {
		lower := strings.ToLower(stripPunctTrailing(tok))
		if replacement, ok := typoSwaps[lower]; ok {
			// Preserve the trailing punctuation (e.g., commas, dashes) if any.
			suffix := ""
			if len(tok) > len(lower) {
				suffix = tok[len(lower):]
			}
			// Preserve Title-Casing roughly — if the original started uppercase,
			// uppercase the first letter of the replacement.
			rep := replacement
			if len(tok) > 0 && tok[0] >= 'A' && tok[0] <= 'Z' {
				rep = strings.ToUpper(replacement[:1]) + replacement[1:]
			}
			fields[i] = rep + suffix
			applied = true
		}
	}
	if !applied {
		return name, false
	}
	return strings.Join(fields, " "), true
}

// stripPunctTrailing removes trailing punctuation/hyphens so typoSwaps can
// match the bare token form. It does NOT touch leading punctuation — that's
// rare in our data and the false-positive risk isn't worth the extra code.
func stripPunctTrailing(tok string) string {
	for len(tok) > 0 {
		last := tok[len(tok)-1]
		if (last >= 'a' && last <= 'z') || (last >= 'A' && last <= 'Z') || (last >= '0' && last <= '9') {
			break
		}
		tok = tok[:len(tok)-1]
	}
	return tok
}

// effectiveMRPFromRow mirrors the in-service effectiveMRP helper but takes
// plain float values so autofix (which works on a trimmed struct, not a
// full dbProduct) can share the same fallback chain: mrp → selling_price.
// cost_price fallback is intentionally OMITTED — autofix's MRP gate is
// about retail price comparability; cost price is a different concept
// and mixing them risks false matches.
func effectiveMRPFromRow(mrp, sellingPrice float64) float64 {
	if mrp > 0 {
		return mrp
	}
	if sellingPrice > 0 {
		return sellingPrice
	}
	return 0
}

// renameToMasterDisplay picks the final stored name after a typo-swap link.
// Prefer the master's canonical DisplayName (user-facing short form); fall
// back to the typo-corrected name so we at least fixed the typo even when
// the master doesn't have a display form.
func renameToMasterDisplay(corrected string, mb *models.MasterBrandInfo) string {
	if mb != nil && mb.DisplayName != "" {
		return mb.DisplayName
	}
	return corrected
}

// firstNonEmptyStr picks the first non-empty string. Pure helper; no
// dependency on firstNonEmpty's variadic signature (which is used elsewhere).
func firstNonEmptyStr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

// safeLinkGenericWords is the TIGHT generic-word filter used only by the
// subset-matching auto-link fallback. Deliberately narrower than
// stockSetupGenericWords: we keep qualifiers like "premium" / "deluxe" /
// "reserve" / "blended" because they DO distinguish sibling variants
// ("100 Pipers Deluxe" vs "100 Pipers Exceptional"), and losing them
// collapses distinct brands into a single matchable class.
var safeLinkGenericWords = map[string]bool{
	"the": true, "a": true, "an": true, "of": true, "and": true,
	"for": true, "with": true, "by": true, "or": true,
	// Pure liquor types — never distinguish one SKU from another within a
	// brand family, and consistently present in every name.
	"whisky": true, "whiskey": true, "rum": true, "vodka": true,
	"gin": true, "brandy": true, "wine": true, "beer": true,
	"scotch": true, "bourbon": true, "liquor": true, "liqueur": true,
}

// safeLinkSizeSuffix matches a trailing " - 180ML" / "180ml" size suffix on
// the end of a free-text product name. The orphan's size lives in its own
// column; the suffix in the name is decorative and drags Levenshtein down.
var safeLinkSizeSuffix = regexp.MustCompile(`(?i)\s*[-–]?\s*\d+\s*m\s*l\s*$`)

// safeLinkSizeToken catches size tokens that appear mid-name (e.g. "180ml"
// between brand words) so they don't pollute the distinctive-token set.
var safeLinkSizeToken = regexp.MustCompile(`(?i)^\d+\s*ml$`)

// cleanNameForSafeLink strips the trailing size suffix from an orphan's raw
// name. Leaves everything else intact (punctuation, casing, interior
// whitespace) so the token extractor can do its own normalization.
func cleanNameForSafeLink(s string) string {
	return strings.TrimSpace(safeLinkSizeSuffix.ReplaceAllString(s, ""))
}

// distinctiveTokenSetForSafeLink lowercases, splits on whitespace, drops size
// tokens + tight generics, trims common punctuation edges, and returns the
// surviving tokens as a set. Tokens < 2 chars are dropped (covers the bare
// "8" / "&" that aren't brand identity).
func distinctiveTokenSetForSafeLink(text string) map[string]struct{} {
	out := make(map[string]struct{})
	for _, t := range strings.Fields(strings.ToLower(text)) {
		t = strings.Trim(t, `.,;:!?()[]'"-`)
		if len(t) < 2 {
			continue
		}
		if safeLinkGenericWords[t] {
			continue
		}
		if safeLinkSizeToken.MatchString(t) {
			continue
		}
		out[t] = struct{}{}
	}
	return out
}

// tokenMatchesAny returns true when `ot` matches any token in `master` either
// exactly or via a ≥3-char prefix in either direction. Prefix relaxation
// handles "pipers" vs "piper's", "8pm" vs "8 pm", and mid-word shorthand
// without letting 2-char coincidences slip through.
func tokenMatchesAny(ot string, master map[string]struct{}) bool {
	if _, ok := master[ot]; ok {
		return true
	}
	if len(ot) < 3 {
		return false
	}
	for mt := range master {
		if len(mt) < 3 {
			continue
		}
		if strings.HasPrefix(mt, ot) || strings.HasPrefix(ot, mt) {
			return true
		}
	}
	return false
}

// trySafeAutoLinkMaster is the subset-matcher fallback. Returns a master
// variant pointer when the orphan maps uniquely to one brand (all its
// distinctive tokens live in the master's token set), otherwise nil.
//
// Selection rule: prefer the master variant at the orphan's size; fall back
// to the largest-MRP variant of the same brand for a cross-size link
// (saas_variant_id then stays NULL upstream — see apply loop).
//
// Safety gates:
//   - orphan must have ≥ 2 distinctive tokens (prevents 1-word matches
//     spraying across unrelated brands).
//   - EXACTLY ONE unique brand_id must match (multiple → ambiguous → nil).
//   - At the SAME SIZE, if both orphan MRP and master MRP are present, the
//     delta must be within ±₹50 (slightly wider than the ±₹30 used by the
//     strong-match path because this fallback is explicitly for low-noise
//     cases where the name match is stronger than the Levenshtein view).
//   - Cross-size links skip the MRP check (different size = different
//     MRP by definition; tenant MRP at the orphan's size stays intact).
func (s *SmartStockSetupService) trySafeAutoLinkMaster(
	orphanName string,
	orphanSize string,
	orphanMRP float64,
	masters []models.MasterBrandInfo,
) *models.MasterBrandInfo {
	cleaned := cleanNameForSafeLink(orphanName)
	orphanTokens := distinctiveTokenSetForSafeLink(cleaned)
	if len(orphanTokens) < 2 {
		return nil
	}
	matchesByBrand := make(map[string][]*models.MasterBrandInfo, 4)
	for i := range masters {
		m := &masters[i]
		masterTokens := distinctiveTokenSetForSafeLink(m.BrandName + " " + m.DisplayName)
		allMatched := true
		for ot := range orphanTokens {
			if !tokenMatchesAny(ot, masterTokens) {
				allMatched = false
				break
			}
		}
		if !allMatched {
			continue
		}
		matchesByBrand[m.BrandID] = append(matchesByBrand[m.BrandID], m)
	}
	if len(matchesByBrand) != 1 {
		return nil
	}
	var variants []*models.MasterBrandInfo
	for _, v := range matchesByBrand {
		variants = v
	}
	sizeKey := strings.ToUpper(strings.TrimSpace(orphanSize))
	var sameSize *models.MasterBrandInfo
	var largest *models.MasterBrandInfo
	for _, v := range variants {
		if sizeKey != "" && strings.ToUpper(strings.TrimSpace(v.Size)) == sizeKey {
			sameSize = v
			continue
		}
		if largest == nil || v.MRP > largest.MRP {
			largest = v
		}
	}
	if sameSize != nil {
		if sameSize.MRP > 0 && orphanMRP > 0 {
			diff := sameSize.MRP - orphanMRP
			if diff < 0 {
				diff = -diff
			}
			if diff > 50 {
				return nil
			}
		}
		return sameSize
	}
	// Cross-size link — clone with VariantID blanked so the apply loop
	// treats it as brand-only (leaves saas_variant_id NULL).
	if largest == nil {
		return nil
	}
	crossSize := *largest
	crossSize.VariantID = ""
	return &crossSize
}
