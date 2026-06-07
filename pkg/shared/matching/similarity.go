package matching

import (
	"strings"
	"unicode"
)

// StringSimilarity computes Levenshtein-based similarity between two strings (0.0 - 1.0)
func StringSimilarity(a, b string) float64 {
	if a == b {
		return 1.0
	}
	if len(a) == 0 || len(b) == 0 {
		return 0.0
	}

	longer := a
	shorter := b
	if len(a) < len(b) {
		longer = b
		shorter = a
	}

	longerLen := len(longer)
	if longerLen == 0 {
		return 1.0
	}

	distance := LevenshteinDistance(longer, shorter)
	return float64(longerLen-distance) / float64(longerLen)
}

// LevenshteinDistance computes the edit distance between two strings using single-row optimization (O(n) space)
func LevenshteinDistance(a, b string) int {
	la := len(a)
	lb := len(b)

	if la == 0 {
		return lb
	}
	if lb == 0 {
		return la
	}

	prev := make([]int, lb+1)
	curr := make([]int, lb+1)

	for j := 0; j <= lb; j++ {
		prev[j] = j
	}

	for i := 1; i <= la; i++ {
		curr[0] = i
		for j := 1; j <= lb; j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			curr[j] = minInt(
				prev[j]+1,      // deletion
				curr[j-1]+1,    // insertion
				prev[j-1]+cost, // substitution
			)
		}
		prev, curr = curr, prev
	}

	return prev[lb]
}

// TokenFrequency maps each token to how many products contain it.
// Computed dynamically from the actual product catalog per tenant — no static lists.
type TokenFrequency map[string]int

// BuildTokenFrequency computes how many products each token appears in.
// Call once per request during PrepareProducts, then pass to TokenOverlapScore.
func BuildTokenFrequency(products []PreparedProduct) TokenFrequency {
	freq := make(TokenFrequency)
	for i := range products {
		seen := make(map[string]bool)
		// Count each token only once per product
		bump := func(tokens []string) {
			for _, t := range tokens {
				if !seen[t] {
					freq[t]++
					seen[t] = true
				}
			}
		}
		bump(products[i].BrandTokens)
		bump(products[i].NameTokens)
		bump(products[i].DisplayNameTokens)
		bump(products[i].ExciseBrandTokens)
		bump(products[i].ExciseDisplayTokens)
		// v1.0.187 — synonym tokens count as part of this product's vocabulary.
		for _, st := range products[i].SynonymsTokens {
			bump(st)
		}
	}
	return freq
}

// tokenWeight computes IDF-based weight for a token.
// Tokens in many products → low weight, tokens in few → high weight.
// totalProducts=50, token in 40 products → weight ≈ 0.3 (common)
// totalProducts=50, token in 2 products → weight ≈ 3.2 (distinctive)
func tokenWeight(token string, freq TokenFrequency, totalProducts int) float64 {
	if totalProducts == 0 {
		return 1.0
	}
	count := freq[token]
	if count == 0 {
		return 2.0 // unseen token — treat as distinctive
	}
	// IDF formula: log(total / count) + 0.5, clamped to [0.3, 3.0]
	ratio := float64(totalProducts) / float64(count)
	weight := 0.0
	// Simple log approximation without math import
	if ratio <= 1.5 {
		weight = 0.3 // appears in >66% of products — very common
	} else if ratio <= 3.0 {
		weight = 0.7 // appears in 33-66%
	} else if ratio <= 6.0 {
		weight = 1.2 // appears in 16-33%
	} else if ratio <= 15.0 {
		weight = 2.0 // appears in 6-16% — distinctive
	} else {
		weight = 3.0 // appears in <6% — very distinctive
	}
	return weight
}

// TokenOverlapScore computes weighted token overlap between OCR and product tokens.
// Uses dynamic IDF weights — tokens common across many products get low weight,
// distinctive brand tokens get high weight. Adapts to each tenant's catalog.
func TokenOverlapScore(ocrTokens, productTokens []string, freq TokenFrequency, totalProducts int) float64 {
	if len(ocrTokens) == 0 || len(productTokens) == 0 {
		return 0
	}

	totalWeight := 0.0
	matchedWeight := 0.0

	for _, ot := range ocrTokens {
		weight := tokenWeight(ot, freq, totalProducts)
		totalWeight += weight

		for _, pt := range productTokens {
			// Exact token match
			if ot == pt {
				matchedWeight += weight
				break
			}
			// Token is prefix of product token (e.g., "rock" matches "rockford")
			if len(ot) >= 3 && strings.HasPrefix(pt, ot) {
				matchedWeight += weight * 0.9
				break
			}
			// Product token is prefix of OCR token (e.g., product has "stag", OCR has "stag750")
			if len(pt) >= 3 && strings.HasPrefix(ot, pt) {
				matchedWeight += weight * 0.8
				break
			}
		}
	}

	if totalWeight == 0 {
		return 0
	}
	return matchedWeight / totalWeight
}

// InitialsMatch checks if a short input looks like initials of a product/brand name.
// "bp" matches "Blender Pride Premium Whisky" → 0.85
// "rs" matches "Royal Stag Whisky" → 0.85
// "8pm" matches "8 PM Black Whisky" → 0.85
func InitialsMatch(input, productName string) float64 {
	input = strings.ToLower(strings.TrimSpace(input))
	if len(input) < 2 || len(input) > 5 {
		return 0
	}

	words := strings.Fields(strings.ToLower(productName))
	if len(words) == 0 {
		return 0
	}

	// Build initials string from product name words
	var initials strings.Builder
	for _, w := range words {
		if len(w) > 0 {
			initials.WriteByte(w[0])
		}
	}
	initialsStr := initials.String()

	// Check: does input match the initials or a prefix of them?
	if input == initialsStr || strings.HasPrefix(initialsStr, input) {
		return 0.85
	}

	// Sequential character matching: "8pm" matching "8 PM Black Whisky"
	inputIdx := 0
	for _, w := range words {
		if inputIdx >= len(input) {
			break
		}
		if len(w) > 0 && w[0] == input[inputIdx] {
			inputIdx++
		}
	}
	if inputIdx == len(input) {
		return 0.85
	}

	return 0
}

// NormalizeForMatch lowercases and removes non-alphanumeric characters
func NormalizeForMatch(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// typoReplacements maps common handwritten / OCR'd brand-text typos to their
// canonical spellings. v1.0.216 — chhotu's 2026-05-11 Mahua Khera AI Purchase
// had 11 review-required rows; ≥ 4 of them were one-letter typos like Vodca
// → Vodka and Mt → ML that the matcher would resolve at 0.99 confidence if
// only the word boundary was correct. Token-level case-insensitive replace
// is safe because none of the keys are substrings of valid Indian liquor
// brand names. Add entries here, not in NormalizeForMatch.
var typoReplacements = map[string]string{
	"vodca":  "vodka",
	"wisky":  "whisky",
	"whisy":  "whisky",
	"whiscy": "whisky",
	"why":    "whisky", // chhotu's shorthand on register / GP — bare "WHY 750ML"
	"rum.":   "rum",
	"vodca.": "vodka",
	// "Mt" / "M.T." → ML in size context — but bare "mt" could be a real brand
	// token. Handle in NormalizeForMatch only when followed by digits via
	// ApplyTypoCorrections rather than this map.
}

// ApplyTypoCorrections returns s with common OCR / handwritten typos
// replaced by their canonical forms. Token-level, case-insensitive. Leaves
// non-letter characters intact so downstream normalization can run as
// before. Cheap to call once per OCR text before matching.
//
// Safe to call on already-normalized text; no-op if no typo present.
func ApplyTypoCorrections(s string) string {
	if s == "" {
		return s
	}
	// Fast path: no whitespace AND no period → single token, simple replace.
	lower := strings.ToLower(s)
	if v, ok := typoReplacements[lower]; ok {
		return restoreCase(s, v)
	}
	// Token-level replace. Preserve original separators by walking runes.
	var out strings.Builder
	var tok strings.Builder
	flush := func() {
		if tok.Len() == 0 {
			return
		}
		t := tok.String()
		if v, ok := typoReplacements[strings.ToLower(t)]; ok {
			out.WriteString(restoreCase(t, v))
		} else {
			out.WriteString(t)
		}
		tok.Reset()
	}
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			tok.WriteRune(r)
		} else {
			flush()
			out.WriteRune(r)
		}
	}
	flush()
	// "Mt" / "M.T." → "ML" only when adjacent to a size number. Heuristic:
	// "180 mt", "180mt", "180 m.t.", "180mt." — keep handling here because
	// it requires looking at the preceding digit.
	result := out.String()
	for _, pat := range []struct{ from, to string }{
		{" mt ", " ml "},
		{" mt.", " ml"},
		{" m.t.", " ml"},
		{" mt", " ml"}, // trailing
	} {
		if strings.HasSuffix(strings.ToLower(result), strings.TrimRight(pat.from, " ")) {
			result = result[:len(result)-len(strings.TrimRight(pat.from, " "))] +
				strings.TrimRight(pat.to, " ")
		}
		result = caseInsensitiveReplace(result, pat.from, pat.to)
	}
	return result
}

// restoreCase preserves the case pattern of orig when returning replacement.
// "Vodca" → "Vodka", "VODCA" → "VODKA", "vodca" → "vodka".
func restoreCase(orig, replacement string) string {
	if orig == "" {
		return replacement
	}
	if strings.ToUpper(orig) == orig {
		return strings.ToUpper(replacement)
	}
	first := orig[0]
	if first >= 'A' && first <= 'Z' && len(replacement) > 0 {
		return strings.ToUpper(replacement[:1]) + replacement[1:]
	}
	return replacement
}

// caseInsensitiveReplace replaces all case-insensitive occurrences of from
// with to in s. Used by ApplyTypoCorrections for separator-aware patterns.
func caseInsensitiveReplace(s, from, to string) string {
	if from == "" {
		return s
	}
	lowerS := strings.ToLower(s)
	lowerFrom := strings.ToLower(from)
	if !strings.Contains(lowerS, lowerFrom) {
		return s
	}
	var out strings.Builder
	i := 0
	for i < len(s) {
		if i+len(from) <= len(s) && strings.EqualFold(s[i:i+len(from)], from) {
			out.WriteString(to)
			i += len(from)
		} else {
			out.WriteByte(s[i])
			i++
		}
	}
	return out.String()
}

// NormalizeSize extracts numeric portion from size string: "750ml" → "750", "750ML" → "750"
func NormalizeSize(size string) string {
	var b strings.Builder
	for _, r := range size {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ParseSizeML extracts size in ML from text. Handles common Indian liquor sizes:
// "750ML" → 750, "quarter" → 180, "half" → 375, "full" → 750, "pint" → 375
func ParseSizeML(sizeText string) int {
	if sizeText == "" {
		return 0
	}
	s := strings.ToLower(strings.TrimSpace(sizeText))

	// Common colloquial names
	switch {
	case s == "quarter" || s == "qtr" || s == "q":
		return 180
	case s == "half" || s == "hf":
		return 375
	case s == "full" || s == "fl":
		return 750
	case s == "pint" || s == "pt":
		return 375
	case s == "nip":
		return 90
	}

	// Extract digits
	var numStr strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			numStr.WriteRune(r)
		}
	}
	if numStr.Len() == 0 {
		return 0
	}

	ml := 0
	for _, r := range numStr.String() {
		ml = ml*10 + int(r-'0')
	}
	return ml
}

// Helpers

func minInt(vals ...int) int {
	m := vals[0]
	for _, v := range vals[1:] {
		if v < m {
			m = v
		}
	}
	return m
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func absFloat(a float64) float64 {
	if a < 0 {
		return -a
	}
	return a
}

// ratePctDiff returns |ocrPrice - productPrice| / max(ocrPrice, productPrice).
// Returns 1.0 when either input is non-positive (treat unknown as worst-case).
// Used by the v1.0.327 rate-proximity tiebreaker in MatchProductsWithStock.
func ratePctDiff(ocrPrice, productPrice float64) float64 {
	if ocrPrice <= 0 || productPrice <= 0 {
		return 1.0
	}
	denom := maxFloat(ocrPrice, productPrice)
	return absFloat(ocrPrice-productPrice) / denom
}
