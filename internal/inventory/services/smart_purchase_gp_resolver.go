package services

import (
	"fmt"
	"log"
	"sort"
	"strings"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// v1.0.221 GP-canonical resolver.
//
// Given a Gate Pass row's `Description` column (the official excise canonical
// name signed by the depot), find the matching `saas_brands.id` in the master
// catalog. That brand_id is then the strict key used by
// selectBestProductForGPRow to find the tenant product to apply against.
//
// Why this matters: gate passes use the OFFICIAL canonical brand name from
// the UP excise database. Those same names also live in our `saas_brands`
// table (1492 brands as of v1.0.175). Strict canonical → brand_id is the
// bridge that gets purchase matching from 35% accurate (bill fuzzy text) to
// near-100% (excise canonical join).
//
// Cascade (in order, first hit wins):
//   1. exact case-insensitive match on `saas_brands.name`
//   2. exact match on `saas_brands.display_name`
//   3. token-overlap fuzzy on `name` (≥ 0.70 jaccard)
//   4. token-overlap fuzzy on `display_name` (≥ 0.70 jaccard)
//   5. meta_keywords contains-match
// No match → returns uuid.Nil + confidence 0.

// GPBrandMatch is one resolver hit, with the source tier and confidence
// score so callers can surface the result with appropriate certainty.
type GPBrandMatch struct {
	SaasBrandID   uuid.UUID
	CanonicalName string // the saas_brands.name we matched against
	Confidence    float64 // 1.0 for exact; ≥0.70 for fuzzy
	MatchTier     string  // "exact_name" | "exact_display" | "fuzzy_name" | "fuzzy_display" | "keyword"
	Candidates    int     // total candidates considered (>1 means there's potential ambiguity)
}

// resolveSaasBrandByGPCanonical maps a GP Description text to a master
// `saas_brands.id`. Returns (uuid.Nil, 0, "no_match", 0) when nothing is
// confident enough — caller should treat as "needs onboarding" and route
// to the master-catalog inline picker.
func (s *SmartPurchaseService) resolveSaasBrandByGPCanonical(
	tx *gorm.DB,
	gpDescription string,
) GPBrandMatch {
	gp := strings.TrimSpace(gpDescription)
	if gp == "" {
		return GPBrandMatch{MatchTier: "empty_input"}
	}
	gpLower := strings.ToLower(gp)

	// Tier 1 + 2: exact match on name OR display_name (case-insensitive).
	type row struct {
		ID          uuid.UUID `gorm:"column:id"`
		Name        string    `gorm:"column:name"`
		DisplayName string    `gorm:"column:display_name"`
	}
	var exact []row
	err := tx.Table("saas_brands").
		Select("id, name, COALESCE(display_name,'') AS display_name").
		Where(`deleted_at IS NULL AND is_active = true
		       AND (LOWER(name) = ? OR LOWER(COALESCE(display_name,'')) = ?)`,
			gpLower, gpLower).
		Limit(5).
		Scan(&exact).Error
	if err == nil && len(exact) > 0 {
		// Multiple exacts can happen when saas_brands itself has the dirty
		// "SEAGRAMS X" vs "SEAGRAM'S X" pair we saw at chhotu's shop.
		// Prefer the one whose `name` is the exact match (vs display_name).
		best := exact[0]
		tier := "exact_display"
		if strings.EqualFold(strings.TrimSpace(best.Name), gp) {
			tier = "exact_name"
		}
		for _, r := range exact[1:] {
			if strings.EqualFold(strings.TrimSpace(r.Name), gp) {
				best = r
				tier = "exact_name"
				break
			}
		}
		return GPBrandMatch{
			SaasBrandID:   best.ID,
			CanonicalName: best.Name,
			Confidence:    1.0,
			MatchTier:     tier,
			Candidates:    len(exact),
		}
	}

	// Tier 3 + 4: fuzzy by token jaccard on name + display_name. Pull a
	// candidate set with at least one shared trigram-ish substring then
	// score in Go (Postgres trigram extension may not be enabled).
	gpTokens := gpTokenSet(gpLower)
	if len(gpTokens) == 0 {
		return GPBrandMatch{MatchTier: "no_tokens"}
	}
	// v1.0.234 — multi-seed candidate query. Pre-v234 the resolver used
	// only the LONGEST token as a LIKE seed. Chhotu's "Beagrams Royal Stag
	// Superior Whisky" → seed "beagrams" → 0 candidates (no master row has
	// "beagrams" in its name). The edit-aware jaccard rescue from v233 was
	// dead code because there were no candidates to score against. Fix:
	// fan out to ALL tokens ≥ 4 chars, UNION the candidate sets, dedupe.
	// Cap each token's seed at 50 rows so a 6-token brand can't fetch 300+
	// rows in worst case.
	seeds := []string{}
	for t := range gpTokens {
		if len(t) >= 4 {
			seeds = append(seeds, t)
		}
	}
	if len(seeds) == 0 {
		// All tokens < 4 chars — fall back to longest token + first-4-chars
		// of input (pre-v234 behavior for ultra-short brand names).
		seed := longestTokenLowercase(gpLower)
		if len(seed) < 3 {
			seed = gpLower
			if len(seed) > 4 {
				seed = seed[:4]
			}
		}
		seeds = []string{seed}
	}

	candidates := []row{}
	seen := make(map[uuid.UUID]bool)
	for _, s := range seeds {
		likeSeed := "%" + s + "%"
		var batch []row
		if err := tx.Table("saas_brands").
			Select("id, name, COALESCE(display_name,'') AS display_name").
			Where(`deleted_at IS NULL AND is_active = true
			       AND (LOWER(name) LIKE ? OR LOWER(COALESCE(display_name,'')) LIKE ?)`,
				likeSeed, likeSeed).
			Limit(50).
			Scan(&batch).Error; err != nil {
			log.Printf("[smart_purchase_gp_resolver] fuzzy candidate query (seed=%q) failed: %v", s, err)
			continue
		}
		for _, r := range batch {
			if seen[r.ID] {
				continue
			}
			seen[r.ID] = true
			candidates = append(candidates, r)
		}
	}
	if len(candidates) == 0 {
		return GPBrandMatch{MatchTier: "no_match", Candidates: 0}
	}

	type scoredRow struct {
		row
		Score float64
		Tier  string
	}
	scored := make([]scoredRow, 0, len(candidates))
	for _, c := range candidates {
		nameTokens := gpTokenSet(strings.ToLower(c.Name))
		nameScore := jaccardTokens(gpTokens, nameTokens)
		dispTokens := map[string]struct{}{}
		dispScore := 0.0
		if c.DisplayName != "" {
			dispTokens = gpTokenSet(strings.ToLower(c.DisplayName))
			dispScore = jaccardTokens(gpTokens, dispTokens)
		}
		// v1.0.233 — edit-aware jaccard rescue for OCR typo class.
		// v1.0.234 — also OR with overlap-coefficient (existing helper from
		// smart_purchase_disambig.go) to rescue the subset case where the
		// bill brand description is SHORTER than master canonical.
		// Real example: "Iconiq White Why 180" vs "ICONIQ WHITE DELUXE
		// INTERNATIONAL GRAIN WHISKY". jaccard = 2/(3+5-2) = 0.33 — below
		// floor. overlap = 2/min(3,5) = 0.67 — above floor.
		nameScoreEdit := jaccardTokensEditAware(gpTokens, nameTokens)
		nameScoreOverlap := overlapCoeff(gpTokens, nameTokens)
		dispScoreEdit := 0.0
		dispScoreOverlap := 0.0
		if c.DisplayName != "" {
			dispScoreEdit = jaccardTokensEditAware(gpTokens, dispTokens)
			dispScoreOverlap = overlapCoeff(gpTokens, dispTokens)
		}
		if nameScoreEdit > nameScore {
			nameScore = nameScoreEdit
		}
		if nameScoreOverlap > nameScore {
			nameScore = nameScoreOverlap
		}
		if dispScoreEdit > dispScore {
			dispScore = dispScoreEdit
		}
		if dispScoreOverlap > dispScore {
			dispScore = dispScoreOverlap
		}
		if nameScore >= dispScore {
			scored = append(scored, scoredRow{row: c, Score: nameScore, Tier: "fuzzy_name"})
		} else {
			scored = append(scored, scoredRow{row: c, Score: dispScore, Tier: "fuzzy_display"})
		}
	}
	sort.SliceStable(scored, func(i, j int) bool { return scored[i].Score > scored[j].Score })

	// v1.0.233 — floor lowered from 0.70 → 0.60 because edit-aware jaccard
	// (above) is conservative: it only credits a near-token-pair when DL≤2
	// AND length≥4 AND no exact partner exists. Pre-v233 floor 0.70 was
	// rejecting valid OCR-typo matches like Beagrams/Seagrams. Confidence
	// is the raw score, so downstream callers can still bucket "high"
	// (≥0.85) vs "needs review" (<0.85) without code change.
	if len(scored) > 0 && scored[0].Score >= 0.60 {
		w := scored[0]
		conf := w.Score
		if len(scored) > 1 && (scored[0].Score-scored[1].Score) < 0.05 {
			conf -= 0.05 // penalise close-call resolutions
		}
		return GPBrandMatch{
			SaasBrandID:   w.row.ID,
			CanonicalName: w.row.Name,
			Confidence:    conf,
			MatchTier:     w.Tier,
			Candidates:    len(scored),
		}
	}

	// Tier 5: meta_keywords contains-match (last-ditch).
	//
	// v1.0.230 — meta_keywords is a Postgres `text[]` column (NOT comma-
	// separated text). Pre-v230 the resolver compared it to '' as if it were a
	// string and called LOWER() on it — both throw `malformed array literal:
	// ""` (SQLSTATE 22P02) and the resolver silently fell back to no_match
	// while spamming the inventory logs. Now we use `array_length > 0` for the
	// empty check and `EXISTS (SELECT 1 FROM unnest(meta_keywords) k WHERE
	// LOWER(k) LIKE ?)` for the contains-match against an unnested element.
	// v1.0.234 — meta_keywords lookup now iterates per-seed (parity with
	// the multi-seed candidate query above). Uses the first seed that
	// returns rows.
	var byKw []row
	for _, s := range seeds {
		likeSeedKw := "%" + s + "%"
		_ = tx.Table("saas_brands").
			Select("id, name, COALESCE(display_name,'') AS display_name").
			Where(`deleted_at IS NULL AND is_active = true
			       AND meta_keywords IS NOT NULL
			       AND array_length(meta_keywords, 1) > 0
			       AND EXISTS (
			           SELECT 1 FROM unnest(meta_keywords) AS kw
			           WHERE LOWER(kw) LIKE ?
			       )`, likeSeedKw).
			Limit(5).
			Scan(&byKw).Error
		if len(byKw) > 0 {
			break
		}
	}
	if len(byKw) > 0 {
		return GPBrandMatch{
			SaasBrandID:   byKw[0].ID,
			CanonicalName: byKw[0].Name,
			Confidence:    0.75,
			MatchTier:     "keyword",
			Candidates:    len(byKw),
		}
	}
	return GPBrandMatch{MatchTier: "no_match", Candidates: len(scored)}
}

// gpTokenSet splits a lower-cased brand string into significant tokens
// (≥ 2 chars, no stopwords). Used for jaccard scoring in the fuzzy tiers.
// Kept inline so this file has no cross-package dependency.
func gpTokenSet(s string) map[string]struct{} {
	out := make(map[string]struct{}, 8)
	tok := strings.FieldsFunc(s, func(r rune) bool {
		return r == ' ' || r == '\t' || r == ',' || r == '.' || r == '-' ||
			r == '(' || r == ')' || r == '/' || r == '&' || r == ':' || r == ';'
	})
	for _, t := range tok {
		t = strings.TrimSpace(t)
		if len(t) < 2 {
			continue
		}
		if _, isStop := gpStopwords[t]; isStop {
			continue
		}
		out[t] = struct{}{}
	}
	return out
}

// jaccardTokens returns |A ∩ B| / |A ∪ B| for two pre-tokenised string sets.
// Used by the fuzzy tiers; identical math to AliasService's hygiene jaccard.
func jaccardTokens(a, b map[string]struct{}) float64 {
	if len(a) == 0 && len(b) == 0 {
		return 1
	}
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	inter := 0
	for t := range a {
		if _, ok := b[t]; ok {
			inter++
		}
	}
	union := len(a) + len(b) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

// jaccardTokensEditAware credits near-matching tokens (DL distance ≤ 2)
// as matches in addition to exact overlap. Conservative: a near-match only
// counts when BOTH tokens are ≥ 4 chars long (so short variant suffixes
// like "no1", "v2" can't fuzz-merge) AND neither token already has an
// exact partner in the other set (so we don't double-count).
//
// v1.0.233 — used by the GP resolver to rescue OCR-typo class. The
// canonical example is "Beagrams Royal Stag" vs "Seagrams Royal Stag":
// exact-jaccard = 2/(3+3-2) = 0.67 (rejected at the 0.60 floor only
// when "Beagrams" → "Seagrams" via DL=1 promotes to a near-match,
// giving inter = 3 → jaccard = 1.0).
func jaccardTokensEditAware(a, b map[string]struct{}) float64 {
	if len(a) == 0 && len(b) == 0 {
		return 1
	}
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	usedA := make(map[string]bool, len(a))
	usedB := make(map[string]bool, len(b))
	inter := 0
	// Pass 1: exact matches.
	for ta := range a {
		if _, ok := b[ta]; ok {
			usedA[ta] = true
			usedB[ta] = true
			inter++
		}
	}
	// Pass 2: near-matches (DL ≤ 2, both ≥ 4 chars). Earliest-bind, not
	// optimal-bipartite — fine for ≤ 8 tokens.
	for ta := range a {
		if usedA[ta] || len(ta) < 4 {
			continue
		}
		for tb := range b {
			if usedB[tb] || len(tb) < 4 {
				continue
			}
			d := levenshtein(ta, tb)
			if d <= 2 {
				usedA[ta] = true
				usedB[tb] = true
				inter++
				break
			}
		}
	}
	union := len(a) + len(b) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

// longestTokenLowercase returns the longest space-delimited token in s,
// trimmed and lowercased. Used to seed the SQL LIKE candidate query so we
// don't full-scan saas_brands for every resolve.
func longestTokenLowercase(s string) string {
	best := ""
	for _, t := range strings.FieldsFunc(s, func(r rune) bool { return r == ' ' || r == '-' }) {
		t = strings.ToLower(strings.TrimSpace(t))
		if len(t) > len(best) {
			best = t
		}
	}
	return best
}

// gpStopwords are tokens that shouldn't contribute to similarity scoring
// (almost every brand name contains them; including them inflates the
// jaccard score and weakens discrimination).
//
// v1.0.234 — added industry abbreviations seen on real bills (chhotu's
// supplier Sonu Singh FL-2 uses "Why" for Whisky everywhere — pre-v234
// the resolver scored "Iconiq White Why" against "ICONIQ WHITE DELUXE
// INTERNATIONAL GRAIN WHISKY" with jaccard 0.33 because "why" wasn't
// known as a whisky synonym).
var gpStopwords = map[string]struct{}{
	"whisky": {}, "whiskey": {}, "vodka": {}, "rum": {}, "scotch": {},
	"the": {}, "and": {}, "of": {}, "premium": {}, "blended": {},
	"flavoured": {}, "flavored": {}, "bottle": {}, "glass": {}, "pet": {},
	"tetra": {}, "pack": {}, "ml": {}, "liter": {}, "litre": {},
	// v1.0.234 — printed-bill abbreviations:
	"why": {}, "whi": {}, "wsk": {}, // → whisky
	"vk": {},  // → vodka
	"bld": {}, // → blended
	"int": {}, "intl": {}, // → international
	"resv": {}, "rsv": {}, // → reserve
}

// ResolverSummary aggregates the outcome of resolving N GP rows. Useful for
// the dry-run admin endpoint that surfaces resolver health on a real job.
type ResolverSummary struct {
	Total           int
	ExactName       int
	ExactDisplay    int
	FuzzyName       int
	FuzzyDisplay    int
	Keyword         int
	NoMatch         int
	AvgConfidence   float64
}

// summarizeResolverHits is a tiny helper for callers that want one-line
// telemetry of resolver outcomes across a whole purchase job.
func summarizeResolverHits(hits []GPBrandMatch) ResolverSummary {
	out := ResolverSummary{Total: len(hits)}
	if len(hits) == 0 {
		return out
	}
	confSum := 0.0
	for _, h := range hits {
		confSum += h.Confidence
		switch h.MatchTier {
		case "exact_name":
			out.ExactName++
		case "exact_display":
			out.ExactDisplay++
		case "fuzzy_name":
			out.FuzzyName++
		case "fuzzy_display":
			out.FuzzyDisplay++
		case "keyword":
			out.Keyword++
		default:
			out.NoMatch++
		}
	}
	out.AvgConfidence = confSum / float64(len(hits))
	return out
}

// String returns a one-line dump of a ResolverSummary for log lines.
func (r ResolverSummary) String() string {
	return fmt.Sprintf(
		"resolver: total=%d exact_name=%d exact_display=%d fuzzy_name=%d fuzzy_display=%d kw=%d nomatch=%d avg_conf=%.2f",
		r.Total, r.ExactName, r.ExactDisplay, r.FuzzyName, r.FuzzyDisplay, r.Keyword, r.NoMatch, r.AvgConfidence)
}
