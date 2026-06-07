// v1.0.243 — Gemini brand-image verifier for AI Stock Setup.
//
// One-shot vision verification: caller hands us a bottle/case photo plus the
// OCR'd brand text and a shortlist of plausible master-brand candidates;
// Gemini Flash 2.0 picks the canonical brand visible in the photo. We use
// this only at Stock Setup time (one-time per shop) so per-call cost is
// negligible. The saas_brands.picture column doubles as a free cache —
// repeat verifications of the same canonical brand return cache_hit=true
// without calling Gemini at all.

package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/google/generative-ai-go/genai"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"google.golang.org/api/option"
	"gorm.io/gorm"
)

// MasterBrandCandidate is a row pre-fetched from saas_brands by token overlap
// against the OCR text. We pass up to ~8 of these to Gemini so it can pick
// from a constrained list instead of free-form labelling.
type MasterBrandCandidate struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	HasPicture    bool   `json:"-"`
	ReferenceURL  string `json:"-"`
}

// BrandVerificationResult is the JSON returned by the verify endpoint.
type BrandVerificationResult struct {
	CanonicalName  string  `json:"canonical_name"`
	MasterBrandID  string  `json:"master_brand_id,omitempty"`
	Size           string  `json:"size"`
	GeminiAgreed   bool    `json:"gemini_agreed"`
	Confidence     float64 `json:"confidence"`
	Reason         string  `json:"reason,omitempty"`
	CacheHit       bool    `json:"cache_hit"`
	ReferenceImage string  `json:"reference_image_url,omitempty"`
	// v1.0.244 — Two-photo support. When verifier was asked for the back
	// face, ExtractedMRP holds the M.R.P. printed on the back label
	// (₹ value); 0 when not found or face=="front".
	Face         string  `json:"face,omitempty"`
	ExtractedMRP float64 `json:"extracted_mrp,omitempty"`
	// v1.0.355 — Gemini's RAW free-text brand read, preserved BEFORE the matched
	// candidate overwrites CanonicalName. Lets the caller detect "the photo says a
	// different bottle than the candidate it was matched to" (the candidate
	// prefetch is seeded from the product's current name, so Gemini can wrongly
	// re-confirm the existing identity). Empty when no free-text read.
	RawBrandRead string `json:"raw_brand_read,omitempty"`
}

// GeminiBrandVerifier wraps a Gemini client + the inventory DB.
type GeminiBrandVerifier struct {
	client *genai.Client
	db     *gorm.DB
	logger *logrus.Logger
}

// NewGeminiBrandVerifier initialises the Gemini client with the same env /
// file-path resolution that the sales-side GeminiOCRService already uses.
// Returns a verifier with client=nil if no API key is present — Verify()
// falls back to "keep OCR text, mark unverified-by-system" so the apply
// gate still works (operator just can't auto-correct).
func NewGeminiBrandVerifier(db *gorm.DB, logger *logrus.Logger) (*GeminiBrandVerifier, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		if b, err := os.ReadFile("/app/credentials/gemini-api-key.txt"); err == nil {
			apiKey = strings.TrimSpace(string(b))
		}
	}
	if apiKey == "" {
		if b, err := os.ReadFile("./credentials/gemini-api-key.txt"); err == nil {
			apiKey = strings.TrimSpace(string(b))
		}
	}
	if apiKey == "" {
		logger.Warn("GeminiBrandVerifier: no API key found — verifier will fall back to OCR-only")
		return &GeminiBrandVerifier{db: db, logger: logger}, nil
	}
	ctx := context.Background()
	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		logger.Warnf("GeminiBrandVerifier: client init failed: %v — falling back", err)
		return &GeminiBrandVerifier{db: db, logger: logger}, nil
	}
	logger.Info("GeminiBrandVerifier ready (Gemini 2.0 Flash)")
	return &GeminiBrandVerifier{client: client, db: db, logger: logger}, nil
}

// CandidatesForOCR returns the top N master brands by simple token overlap.
// Empty result is OK — Gemini will free-form label and the handler can
// resolve afterwards. We deliberately include hasPicture so the handler can
// prefer cached brands.
func (g *GeminiBrandVerifier) CandidatesForOCR(ocrText string, limit int) []MasterBrandCandidate {
	if limit <= 0 {
		limit = 8
	}
	tokens := normaliseTokens(ocrText)
	if len(tokens) == 0 {
		return nil
	}
	// Pre-filter by ILIKE on each token; ranking happens in Go (small N).
	var rows []struct {
		ID      string
		Name    string
		Picture string
	}
	q := g.db.Table("saas_brands").Select("id, name, COALESCE(picture, '') AS picture").
		Where("deleted_at IS NULL")
	// v1.0.243 — Order so that previously-cached brands surface first within
	// the 120-row prefetch cap. Without this, a brand with millions of token
	// matches (e.g. "whisky") could push the actual target out of the cap and
	// cause a cache miss + unnecessary Gemini call. We also try to put rows
	// with the most ILIKE-token overlaps near the top so the in-Go jaccard
	// pass works on the most relevant 120 rows.
	if len(tokens) > 0 {
		var likeArgs []interface{}
		var likeSQL []string
		var rankSQL []string
		for _, t := range tokens {
			if len(t) < 3 {
				continue
			}
			likeSQL = append(likeSQL, "name ILIKE ?")
			likeArgs = append(likeArgs, "%"+t+"%")
			// each match contributes +1 to a relevance score.
			rankSQL = append(rankSQL, "(CASE WHEN name ILIKE ? THEN 1 ELSE 0 END)")
		}
		if len(likeSQL) > 0 {
			q = q.Where("("+strings.Join(likeSQL, " OR ")+")", likeArgs...)
		}
		if len(rankSQL) > 0 {
			// SELECT the same rank expression so ORDER BY can reference it.
			rankExpr := strings.Join(rankSQL, " + ")
			// We need the rank args duplicated since the SELECT also takes them.
			rankArgs := make([]interface{}, len(likeArgs))
			copy(rankArgs, likeArgs)
			q = q.Select("id, name, COALESCE(picture, '') AS picture, ("+rankExpr+") AS relevance", rankArgs...).
				Order("(picture IS NOT NULL AND picture != '') DESC, relevance DESC, length(name) ASC")
		}
	}
	if err := q.Limit(120).Find(&rows).Error; err != nil {
		g.logger.WithError(err).Warn("CandidatesForOCR: prefetch failed")
		return nil
	}
	// Rank by jaccard.
	ranked := make([]struct {
		MasterBrandCandidate
		score float64
	}, 0, len(rows))
	ocrSet := verifierTokenSet(tokens)
	for _, r := range rows {
		nameTokens := normaliseTokens(r.Name)
		nameSet := verifierTokenSet(nameTokens)
		score := jaccard(ocrSet, nameSet)
		if score <= 0 {
			continue
		}
		ranked = append(ranked, struct {
			MasterBrandCandidate
			score float64
		}{
			MasterBrandCandidate: MasterBrandCandidate{
				ID:           r.ID,
				Name:         r.Name,
				HasPicture:   r.Picture != "",
				ReferenceURL: r.Picture,
			},
			score: score,
		})
	}
	// Sort desc.
	for i := 0; i < len(ranked); i++ {
		for j := i + 1; j < len(ranked); j++ {
			if ranked[j].score > ranked[i].score {
				ranked[i], ranked[j] = ranked[j], ranked[i]
			}
		}
	}
	if len(ranked) > limit {
		ranked = ranked[:limit]
	}
	out := make([]MasterBrandCandidate, len(ranked))
	for i, r := range ranked {
		out[i] = r.MasterBrandCandidate
	}
	return out
}

// LookupCachedCanonical checks if any candidate already has a stored
// reference image. If so we can short-circuit Gemini entirely on a follow-up
// Stock Setup that hits the same OCR text. The match is exact-on-canonical
// (operator's manual edits won't accidentally collide).
func (g *GeminiBrandVerifier) LookupCachedCanonical(ocrText string, candidates []MasterBrandCandidate) *MasterBrandCandidate {
	normOCR := normaliseString(ocrText)
	for _, c := range candidates {
		if !c.HasPicture {
			continue
		}
		if normaliseString(c.Name) == normOCR {
			cc := c
			return &cc
		}
	}
	return nil
}

// Verify runs one Gemini call. Caller already guarded the cache-hit path.
// On error or no-client, returns gemini_agreed=false + confidence=0 — caller
// decides what to do (typically: keep OCR text, mark row unverified).
//
// v1.0.244 — `face` is "front" (default — read brand + size from label) or
// "back" (read brand for sanity + extract M.R.P. printed on the back).
func (g *GeminiBrandVerifier) Verify(
	ctx context.Context,
	imageBytes []byte,
	mimeType string,
	ocrBrandText string,
	ocrSize string,
	candidates []MasterBrandCandidate,
	face string,
) (*BrandVerificationResult, error) {
	if face == "" {
		face = "front"
	}
	if g.client == nil {
		return &BrandVerificationResult{
			CanonicalName: ocrBrandText,
			Size:          ocrSize,
			GeminiAgreed:  false,
			Confidence:    0,
			Reason:        "gemini_unavailable",
			Face:          face,
		}, nil
	}
	if len(imageBytes) == 0 {
		return nil, fmt.Errorf("empty image")
	}
	model := g.client.GenerativeModel("gemini-2.5-flash")
	model.ResponseMIMEType = "application/json"
	temp := float32(0.05)
	model.Temperature = &temp

	prompt := buildBrandVerifyPrompt(ocrBrandText, ocrSize, candidates, face)
	// genai.ImageData wants the format suffix (e.g. "jpeg"), not the full
	// MIME type ("image/jpeg"). Strip the "image/" prefix if present.
	imageFormat := strings.TrimPrefix(strings.ToLower(mimeType), "image/")
	if imageFormat == "" || imageFormat == mimeType {
		imageFormat = "jpeg"
	}
	imgPart := genai.ImageData(imageFormat, imageBytes)

	// v1.0.243 — 30s is the practical ceiling for Gemini 2.5 Flash on a 2-4MB
	// bottle photo. Operators using the in-app camera (image_picker) get
	// downscaled JPEGs ~200-500KB so this timeout is mostly headroom for
	// gallery uploads of full-res photos.
	callCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	start := time.Now()
	resp, err := model.GenerateContent(callCtx, genai.Text(prompt), imgPart)
	if err != nil {
		return nil, fmt.Errorf("gemini generate: %w", err)
	}
	if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil || len(resp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("gemini returned empty response")
	}
	raw, ok := resp.Candidates[0].Content.Parts[0].(genai.Text)
	if !ok {
		return nil, fmt.Errorf("gemini returned non-text part")
	}
	g.logger.WithFields(logrus.Fields{
		"latency_ms": time.Since(start).Milliseconds(),
		"ocr_text":   ocrBrandText,
	}).Info("GeminiBrandVerifier: response received")

	res := parseVerifyResponse(string(raw), ocrBrandText, ocrSize, candidates, face)

	// v1.0.260 Fix D — recover a discarded-but-correct read. Gemini answered
	// with a confident free-text brand but picked NO candidate (the garbled-OCR
	// prefetch never offered the right verbose master row), so MasterBrandID is
	// empty and v1.0.257 Fix C would refuse to apply the name — the row stays
	// stuck on OCR garbage even though the operator photographed the right
	// bottle and Gemini read it perfectly. Re-anchor using Gemini's OWN CLEAN
	// read against the master catalog. Guard: only when confident and the read
	// is actually distinct from the (garbled) OCR text, so we never anchor
	// noise.
	if res != nil && res.MasterBrandID == "" && res.Confidence >= 0.7 &&
		res.CanonicalName != "" &&
		!strings.EqualFold(strings.TrimSpace(res.CanonicalName), strings.TrimSpace(ocrBrandText)) {
		if mid, mname, okA := g.anchorCanonicalToMaster(res.CanonicalName); okA {
			g.logger.WithFields(logrus.Fields{
				"gemini_read": res.CanonicalName, "anchored_to": mname,
				"master_brand_id": mid, "ocr": ocrBrandText, "face": face,
			}).Info("GeminiBrandVerifier: Fix D re-anchored free-text read to master (v1.0.260)")
			res.MasterBrandID = mid
			res.CanonicalName = mname
		}
	}

	// v1.0.355 — RECOVER A MISMATCHED CANDIDATE. The candidate prefetch is seeded
	// from the product's CURRENT name, so when an operator photographs a genuinely
	// DIFFERENT bottle (e.g. "Royal Stag Barrel Select" onto a product still named
	// "Royal Stag Double Dark"), Gemini can pick the current-name candidate and its
	// name overwrites the free-text read — so the bottle never gets renamed. When
	// Gemini's RAW read is confident yet token-distinct from the matched canonical,
	// re-anchor the raw read against the master catalog; if it fully resolves to a
	// DIFFERENT master (anchorCanonicalToMaster already requires full-token
	// containment, so it won't fire on noise/ambiguity), trust that better identity.
	// Ships default-OFF (VERIFY_RECOVER_MISMATCHED_CANDIDATE=1 enables) per the
	// "no new bugs" bar — observe logs before enabling.
	if os.Getenv("VERIFY_RECOVER_MISMATCHED_CANDIDATE") == "1" &&
		res != nil && res.MasterBrandID != "" && res.Confidence >= 0.7 &&
		res.RawBrandRead != "" &&
		!brandReadsTokenEqual(res.RawBrandRead, res.CanonicalName) {
		if mid, mname, okA := g.anchorCanonicalToMaster(res.RawBrandRead); okA && mid != res.MasterBrandID {
			g.logger.WithFields(logrus.Fields{
				"raw_read": res.RawBrandRead, "was_matched_to": res.CanonicalName,
				"recovered_to": mname, "master_brand_id": mid, "face": face,
			}).Warn("GeminiBrandVerifier: recovered mismatched candidate — photo read a different bottle (v1.0.355)")
			res.MasterBrandID = mid
			res.CanonicalName = mname
		}
	}
	return res, nil
}

// brandReadsTokenEqual reports whether two brand strings share their distinctive
// token set (after dropping the narrow verify filler words). Used to detect when
// Gemini's raw free-text read genuinely differs from the candidate it was matched
// to (vs a trivial wording/case difference).
func brandReadsTokenEqual(a, b string) bool {
	ta := distinctiveBrandTokens(a)
	tb := distinctiveBrandTokens(b)
	if len(ta) == 0 || len(tb) == 0 {
		return strings.EqualFold(strings.TrimSpace(a), strings.TrimSpace(b))
	}
	for t := range ta {
		if _, ok := tb[t]; !ok {
			return false
		}
	}
	for t := range tb {
		if _, ok := ta[t]; !ok {
			return false
		}
	}
	return true
}

// distinctiveBrandTokens lowercases, splits on non-alphanumerics, drops the
// verifyFillerWords (structural/spirit/size noise), and returns the ≥3-char
// distinctive tokens as a set — the same notion anchorCanonicalToMaster uses.
func distinctiveBrandTokens(s string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, tok := range strings.FieldsFunc(strings.ToLower(s), func(r rune) bool {
		return !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'))
	}) {
		if len(tok) < 3 {
			continue
		}
		if _, filler := verifyFillerWords[tok]; filler {
			continue
		}
		out[tok] = struct{}{}
	}
	return out
}

// ---- prompt + parsing ----

func buildBrandVerifyPrompt(ocrText, ocrSize string, candidates []MasterBrandCandidate, face string) string {
	var sb strings.Builder
	if face == "back" {
		sb.WriteString("You are reading the BACK label of a single liquor bottle photograph for two facts: the brand (sanity-check) and the M.R.P. (Maximum Retail Price).\n\n")
	} else {
		sb.WriteString("You are verifying a single liquor bottle/case/piece photograph against a stock-register entry.\n\n")
	}
	sb.WriteString("STOCK-REGISTER ENTRY (what the shop operator typed/OCR'd):\n")
	sb.WriteString(fmt.Sprintf("  - brand: %q\n", ocrText))
	if ocrSize != "" {
		sb.WriteString(fmt.Sprintf("  - size:  %q\n", ocrSize))
	}
	sb.WriteString("\n")
	if len(candidates) > 0 {
		sb.WriteString("CANDIDATE MASTER BRANDS (pick one if the photo matches it):\n")
		for i, c := range candidates {
			sb.WriteString(fmt.Sprintf("  %d. id=%s  name=%q\n", i+1, c.ID, c.Name))
		}
		sb.WriteString("\n")
	}
	if face == "back" {
		sb.WriteString(`TASK (BACK LABEL):
1. Read the brand name printed on the back label.
2. Read the volume in millilitres if visible.
3. Find the M.R.P. (Maximum Retail Price). Look for labels like "M.R.P. ₹", "MRP Rs.", "Maximum Retail Price", "₹ <number>", "Rs. <number>" — usually printed in a small box on the back.
   - If MRP is printed as a range (e.g. "MRP: ₹650 (incl. of all taxes)"), return the numeric value (650).
   - If MRP is not visible or unreadable, return mrp=0.
4. If one CANDIDATE matches the back-label brand, return that candidate's id and name.
5. If NO candidate matches, return the canonical brand name as printed.
6. If the photo is unreadable, return brand="" and confidence=0 and mrp=0.

OUTPUT — return ONLY this JSON, no prose:
{
  "brand": "<canonical brand name from back label>",
  "size_ml": <integer ml or 0>,
  "mrp": <numeric M.R.P. in ₹, or 0 if not found>,
  "matched_candidate_id": "<uuid from list above, or empty>",
  "confidence": <0.0-1.0>,
  "agreed_with_ocr": <true if your read matches the stock-register entry>,
  "reason": "<short note if confidence < 0.7 or mrp unreadable>"
}
`)
	} else {
		sb.WriteString(`TASK (FRONT LABEL):
1. Read the brand name printed on the bottle/case label in the photo.
2. Read the volume in millilitres if visible.
3. If one CANDIDATE matches the photo, return that candidate's id and name.
4. If NO candidate matches, return the canonical brand name as printed.
5. If the photo is unreadable, return brand="" and confidence=0.

OUTPUT — return ONLY this JSON, no prose:
{
  "brand": "<canonical brand name from label>",
  "size_ml": <integer ml or 0>,
  "matched_candidate_id": "<uuid from list above, or empty>",
  "confidence": <0.0-1.0>,
  "agreed_with_ocr": <true if your read matches the stock-register entry>,
  "reason": "<short note if confidence < 0.7>"
}
`)
	}
	return sb.String()
}

func parseVerifyResponse(raw, ocrText, ocrSize string, candidates []MasterBrandCandidate, face string) *BrandVerificationResult {
	raw = strings.TrimSpace(raw)
	// Strip code-fence if Gemini ever wraps it.
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var parsed struct {
		Brand              string  `json:"brand"`
		SizeML             int     `json:"size_ml"`
		MRP                float64 `json:"mrp"` // v1.0.244 — back-label only
		MatchedCandidateID string  `json:"matched_candidate_id"`
		Confidence         float64 `json:"confidence"`
		AgreedWithOCR      bool    `json:"agreed_with_ocr"`
		Reason             string  `json:"reason"`
	}
	if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
		return &BrandVerificationResult{
			CanonicalName: ocrText,
			Size:          ocrSize,
			GeminiAgreed:  false,
			Confidence:    0,
			Reason:        "parse_error: " + err.Error(),
			Face:          face,
		}
	}

	// Resolve matched candidate back to its name.
	canonical := strings.TrimSpace(parsed.Brand)
	rawBrandRead := canonical // v1.0.355 — keep the free-text read before any overwrite
	masterBrandID := strings.TrimSpace(parsed.MatchedCandidateID)
	if masterBrandID != "" {
		for _, c := range candidates {
			if c.ID == masterBrandID {
				// v1.0.358 / Phase 1 — DE-BIAS THE READ (VERIFY_READ_IS_TRUTH, default-off;
				// VERIFY_DEBIAS_READ honored as legacy alias). The candidate list is seeded
				// from the per-shop product name, so letting a matched candidate overwrite
				// the read unconditionally made the SAME image read differently per shop.
				// When read-is-truth is on, only adopt the candidate name if it token-agrees
				// with Gemini's own free-text read of the bottle (brandReadsTokenEqual);
				// otherwise keep the IMAGE's read as truth and let the deterministic anchor
				// normalize it. MasterBrandID is still returned for catalog anchoring.
				if !verifyReadIsTruth() || rawBrandRead == "" || brandReadsTokenEqual(rawBrandRead, c.Name) {
					canonical = c.Name
				}
				break
			}
		}
	}
	if canonical == "" {
		canonical = ocrText
	}

	sizeOut := ocrSize
	if parsed.SizeML > 0 {
		sizeOut = fmt.Sprintf("%dml", parsed.SizeML)
	}

	return &BrandVerificationResult{
		CanonicalName: canonical,
		MasterBrandID: masterBrandID,
		Size:          sizeOut,
		GeminiAgreed:  parsed.AgreedWithOCR,
		Confidence:    parsed.Confidence,
		Reason:        parsed.Reason,
		Face:          face,
		ExtractedMRP:  parsed.MRP,
		RawBrandRead:  rawBrandRead,
	}
}

// ---- tokeniser helpers (kept package-local, no cross-package import) ----

var nonAlnumRe = regexp.MustCompile(`[^a-z0-9]+`)

func normaliseString(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = nonAlnumRe.ReplaceAllString(s, " ")
	s = strings.Join(strings.Fields(s), " ")
	return s
}

func normaliseTokens(s string) []string {
	norm := normaliseString(s)
	if norm == "" {
		return nil
	}
	return strings.Fields(norm)
}

func verifierTokenSet(tokens []string) map[string]struct{} {
	m := make(map[string]struct{}, len(tokens))
	for _, t := range tokens {
		if len(t) < 2 {
			continue
		}
		m[t] = struct{}{}
	}
	return m
}

func jaccard(a, b map[string]struct{}) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	var inter int
	for t := range a {
		if _, ok := b[t]; ok {
			inter++
		}
	}
	uni := len(a) + len(b) - inter
	if uni == 0 {
		return 0
	}
	return float64(inter) / float64(uni)
}

// PopulatePictureIfMissing sets saas_brands.picture for the given brand if
// currently NULL/empty. Idempotent — safe to call on every verify.
func (g *GeminiBrandVerifier) PopulatePictureIfMissing(brandID, imageURL string) error {
	if brandID == "" || imageURL == "" {
		return nil
	}
	return g.db.Exec(`UPDATE saas_brands
		SET picture = ?, updated_at = NOW()
		WHERE id = ? AND (picture IS NULL OR picture = '') AND deleted_at IS NULL`,
		imageURL, brandID).Error
}

// verifyFillerWords — structural words, spirit nouns and size units that do NOT
// discriminate one brand variant from another. Deliberately NARROWER than
// stockSetupGenericWords: colour / variant words (gold, black, green, rare,
// special, premium, superior, reserve …) are KEPT because they are exactly
// what separates "8 PM GOLD" from "8 PM Special Rare Whisky" — dropping them
// would let a clean Gemini read of GOLD anchor to the RARE master row.
var verifyFillerWords = map[string]bool{
	"the": true, "a": true, "an": true, "of": true, "and": true, "for": true,
	"with": true, "blend": true, "blended": true, "grain": true, "indian": true,
	"whisky": true, "whiskey": true, "rum": true, "vodka": true, "gin": true,
	"brandy": true, "wine": true, "beer": true, "scotch": true, "bourbon": true,
	"liquor": true, "caribbean": true, "ml": true, "ltr": true, "l": true,
	"cl": true, "pet": true, "tetra": true, "btl": true, "pc": true, "pcs": true,
}

// digitAlphaSplit turns an alnum-mix brand key like "8pm" back into its spaced
// form "8 pm" so an ILIKE prefilter also catches catalog rows stored WITH the
// space ("8 PM Premium Black Superior Whisky"). Returns "" when not a clean
// digit-head + alpha-tail token.
func digitAlphaSplit(tok string) string {
	i := 0
	for i < len(tok) && tok[i] >= '0' && tok[i] <= '9' {
		i++
	}
	if i == 0 || i == len(tok) {
		return ""
	}
	for j := i; j < len(tok); j++ {
		if tok[j] >= '0' && tok[j] <= '9' {
			return ""
		}
	}
	return tok[:i] + " " + tok[i:]
}

// anchorCanonicalToMaster is v1.0.260 Fix D. When Gemini returns a CONFIDENT
// free-text brand read (matched_candidate_id empty — because the garbled-OCR
// candidate prefetch never offered the right verbose master row), the correct
// answer was previously DISCARDED: MasterBrandID stayed empty, so v1.0.257
// Fix C refused to apply the name and the row stayed stuck on the OCR garbage
// ("PM Rare Whisky Green" for a photographed 8 PM GOLD bottle, chhotu job
// da824f5c row 1, 2026-05-16). This re-queries saas_brands using GEMINI'S OWN
// CLEAN read (not the garbled OCR) and anchors it.
//
// Conservative by construction — anchors ONLY when a master row CONTAINS every
// meaningful token of Gemini's read (variant words kept), so "8 PM GOLD"
// resolves to "8PM Gold Blend of Scotch & Indian Grain Whisky" and is REJECTED
// by "8 PM Special Rare Whisky" (no "gold"). Among full-containment rows it
// prefers the one with the fewest extra distinctive tokens, then the shortest
// name. Returns ok=false (leave unanchored — honest) when there is no
// unambiguous catalog row.
func (g *GeminiBrandVerifier) anchorCanonicalToMaster(canonical string) (id, name string, ok bool) {
	if g == nil || g.db == nil {
		return "", "", false
	}
	canon := strings.TrimSpace(canonical)
	if canon == "" {
		return "", "", false
	}
	// Meaningful tokens of the clean Gemini read: keep colours/variant words,
	// drop only structural/spirit/size filler and bare size numbers.
	var meaningful []string
	strongKey := false
	for _, t := range brandKeyTokens(canon) {
		if verifyFillerWords[t] {
			continue
		}
		allDigit := true
		for _, r := range t {
			if r < '0' || r > '9' {
				allDigit = false
				break
			}
		}
		if allDigit { // sizes / prices / years — never brand identity
			continue
		}
		meaningful = append(meaningful, t)
		if isAlnumMix(t) || len(t) >= 4 { // a real brand key, not a 2-3 char scrap
			strongKey = true
		}
	}
	// Need a real signal: ≥2 meaningful tokens, or ≥1 strong brand key.
	if len(meaningful) == 0 || (len(meaningful) < 2 && !strongKey) {
		return "", "", false
	}

	// Bounded ILIKE prefilter on the meaningful tokens (len ≥ 3), including the
	// spaced form of alnum-mix keys so "8pm" also catches "8 PM ..." rows.
	var likeSQL []string
	var likeArgs []interface{}
	for _, t := range meaningful {
		if len(t) < 3 {
			continue
		}
		likeSQL = append(likeSQL, "name ILIKE ?")
		likeArgs = append(likeArgs, "%"+t+"%")
		if sp := digitAlphaSplit(t); sp != "" {
			likeSQL = append(likeSQL, "name ILIKE ?")
			likeArgs = append(likeArgs, "%"+sp+"%")
		}
	}
	if len(likeSQL) == 0 {
		return "", "", false
	}
	var rows []struct {
		ID   string
		Name string
	}
	if err := g.db.Table("saas_brands").
		Select("id, name").
		Where("deleted_at IS NULL").
		Where("("+strings.Join(likeSQL, " OR ")+")", likeArgs...).
		// v1.0.358 — stable total order so the SAME read always anchors to the SAME
		// saas_brand tenant-wide (the 300-row prefetch was previously unordered, so
		// ties could flip between runs/shops). Aligns with the Go tie-break below
		// (shortest distinctive name, then id).
		Order("length(name) ASC, id ASC").
		Limit(300).Find(&rows).Error; err != nil {
		g.logger.WithError(err).Debug("anchorCanonicalToMaster: prefetch failed")
		return "", "", false
	}

	tokenHit := func(want string, have map[string]bool) bool {
		if have[want] {
			return true
		}
		// Gemini text is clean (not garbled OCR), so exact / containment is
		// enough; no heavy fuzzy needed here.
		for h := range have {
			if len(want) >= 4 && len(h) >= 4 &&
				(strings.Contains(h, want) || strings.Contains(want, h)) {
				return true
			}
		}
		return false
	}

	bestExtra := 1 << 30
	bestLen := 1 << 30
	for _, r := range rows {
		nameToks := brandKeyTokens(r.Name)
		have := make(map[string]bool, len(nameToks))
		distinct := 0
		for _, nt := range nameToks {
			have[nt] = true
			if !verifyFillerWords[nt] {
				distinct++
			}
		}
		// Require the master to CONTAIN every meaningful token of the read.
		full := true
		for _, mt := range meaningful {
			if !tokenHit(mt, have) {
				full = false
				break
			}
		}
		if !full {
			continue
		}
		extra := distinct - len(meaningful)
		if extra < 0 {
			extra = 0
		}
		// v1.0.358 — fully ordered tie-break (fewest extra tokens, then shortest
		// name, then lowest id) so the result is deterministic even if two masters
		// tie on (extra, len). No reliance on DB arrival order.
		better := extra < bestExtra ||
			(extra == bestExtra && len(r.Name) < bestLen) ||
			(extra == bestExtra && len(r.Name) == bestLen && (id == "" || r.ID < id))
		if better {
			bestExtra = extra
			bestLen = len(r.Name)
			id, name, ok = r.ID, r.Name, true
		}
	}
	return id, name, ok
}

// ---- v1.0.358 tenant-wide image-content-hash cache ----

// ImageVerifyCacheVersion bundles the normalize knobs + prompt era. Bump to
// invalidate the whole image_verify_cache table on a normalize/prompt change.
const ImageVerifyCacheVersion = "imgverify-v1.0.358-1600q80"

// imageVerifyCacheVersion returns the EFFECTIVE cache version. When the read-is-
// truth de-bias (Phase 1) is enabled the read logic changes, so cached entries
// computed under the old candidate-overwrite behavior must not be reused: the
// version gains a "-readtruth" suffix, which transparently flushes the old rows
// for lookups and writes fresh ones. Flipping the flag back reverts the version
// (and re-exposes the old cache), so the rollout is fully reversible.
func imageVerifyCacheVersion() string {
	if verifyReadIsTruth() {
		return ImageVerifyCacheVersion + "-readtruth"
	}
	return ImageVerifyCacheVersion
}

// ImageVerifyHashEnabled gates the tenant-wide image-hash cache (default-on).
func ImageVerifyHashEnabled() bool { return os.Getenv("IMAGE_VERIFY_HASH_CACHE") != "0" }

// verifyReadIsTruth gates Phase 1 of the image→identity correctness engine: a
// per-shop candidate match only ADOPTS its catalog name when it token-agrees with
// Gemini's own free-text read of the label (brandReadsTokenEqual); otherwise the
// IMAGE read is kept as truth and the deterministic anchor normalizes it. This is
// what stops the SAME bottle from resolving to different names in different shops
// (the candidate list is seeded from the per-shop product name). Default OFF (exact
// current behavior) → enable with VERIFY_READ_IS_TRUTH=1. VERIFY_DEBIAS_READ=1 is
// honored as a legacy alias so the existing rollout switch keeps working.
func verifyReadIsTruth() bool {
	return os.Getenv("VERIFY_READ_IS_TRUTH") == "1" || os.Getenv("VERIFY_DEBIAS_READ") == "1"
}

// ImageSHA256 returns the lowercase hex SHA-256 of the image bytes. The caller
// passes the POST-normalize bytes so client-quality differences collapse and the
// same physical capture hits the cache across shops.
func ImageSHA256(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// LookupImageHash returns a cached verify result for (tenant, sha, version, face)
// and bumps hit_count. Returns nil on miss / any error (fail-open → caller falls
// through to Gemini). Skips invalidated rows.
func (g *GeminiBrandVerifier) LookupImageHash(tenantID uuid.UUID, sha, face string) *BrandVerificationResult {
	if g.db == nil || sha == "" {
		return nil
	}
	var row struct {
		CanonicalName string
		MasterBrandID *string
		ExtractedMRP  *float64
		Confidence    *float64
		RawBrandRead  *string
	}
	r := g.db.Raw(`
		UPDATE image_verify_cache
		   SET hit_count = hit_count + 1, last_hit_at = NOW()
		 WHERE tenant_id = ? AND image_sha256 = ? AND cache_version = ? AND face = ?
		   AND invalidated_at IS NULL
		 RETURNING canonical_name, master_brand_id, extracted_mrp, confidence, raw_brand_read`,
		tenantID, sha, imageVerifyCacheVersion(), face).Row()
	if err := r.Scan(&row.CanonicalName, &row.MasterBrandID, &row.ExtractedMRP, &row.Confidence, &row.RawBrandRead); err != nil {
		return nil
	}
	res := &BrandVerificationResult{
		CanonicalName: row.CanonicalName,
		Face:          face,
		CacheHit:      true,
		Reason:        "image_hash_cache_hit",
	}
	if row.MasterBrandID != nil {
		res.MasterBrandID = *row.MasterBrandID
	}
	if row.ExtractedMRP != nil {
		res.ExtractedMRP = *row.ExtractedMRP
	}
	if row.Confidence != nil {
		res.Confidence = *row.Confidence
	}
	if row.RawBrandRead != nil {
		res.RawBrandRead = *row.RawBrandRead
	}
	return res
}

// StoreImageHash persists a confident verify result keyed by image hash. Best
// effort (ignores duplicate-key from concurrent writers). Caller should only call
// this for a fresh (non-cache) result with Confidence >= 0.5 so a noise read can
// never poison the tenant-wide answer.
func (g *GeminiBrandVerifier) StoreImageHash(tenantID uuid.UUID, sha, face string, res *BrandVerificationResult) {
	if g.db == nil || sha == "" || res == nil {
		return
	}
	var masterID interface{}
	if mid, err := uuid.Parse(strings.TrimSpace(res.MasterBrandID)); err == nil && mid != uuid.Nil {
		masterID = mid
	}
	g.db.Exec(`
		INSERT INTO image_verify_cache
		    (tenant_id, image_sha256, cache_version, face, canonical_name, master_brand_id, extracted_mrp, confidence, raw_brand_read)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (tenant_id, image_sha256, cache_version, face) DO NOTHING`,
		tenantID, sha, imageVerifyCacheVersion(), face, res.CanonicalName, masterID, res.ExtractedMRP, res.Confidence, res.RawBrandRead)
}
