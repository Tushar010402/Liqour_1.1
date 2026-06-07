package services

import (
	"strings"
)

// smartSearchScore returns a 0..1 similarity score between an OCR brand
// string and a candidate product name using FOUR signals a human reader
// would use:
//
//  1. Abbreviation expansion — "MCD" → "McDowell's", "OC" → "Officer's Choice"
//     using a hardcoded dictionary of common Indian-liquor shop shorthand.
//  2. Levenshtein on short strings — "Iconic" vs "Iconiq" = 1 edit, "B7
//     Whisky" vs "B7 Special" = significant edits but anchored on "B7".
//  3. Char-bigram similarity — for partial OCR like "8 PM Gold Tetra Te"
//     truncated, char bigrams capture local fragment matches that token
//     jaccard misses.
//  4. Anchor-token (numeric / distinctive) match — "B7", "100", "180ml"
//     are heavy anchors; matching them adds confidence even when the rest
//     of the string is noisy.
//
// This score COMPOSES with the existing matcher's jaccard — callers
// take MAX(jaccard, smartSearchScore) so we never regress on cases the
// existing matcher already handles. v1.0.172.
func smartSearchScore(ocr, candidate string) float64 {
	o := strings.ToLower(strings.TrimSpace(ocr))
	c := strings.ToLower(strings.TrimSpace(candidate))
	if o == "" || c == "" {
		return 0
	}
	if o == c {
		return 1.0
	}
	// Substring containment is a strong signal both ways.
	if strings.Contains(c, o) || strings.Contains(o, c) {
		return 0.92
	}

	// Signal 1: abbreviation expansion. Walk the OCR string token-by-token
	// and substitute known abbreviations; re-jaccard after expansion.
	expandedOCR := expandAbbreviations(o)
	if expandedOCR != o && (strings.Contains(c, expandedOCR) || strings.Contains(expandedOCR, c)) {
		return 0.90
	}

	// Signal 2: Levenshtein-based ratio for short strings (≤ 30 chars).
	// 1 edit on a 6-char string is 0.83 similarity — high enough to favor.
	levRatio := levenshteinRatio(o, c)
	expandedLev := levenshteinRatio(expandedOCR, c)
	if expandedLev > levRatio {
		levRatio = expandedLev
	}

	// Signal 3: char-bigram Jaccard. Robust to truncation and cursive joins.
	bg := charBigramJaccard(o, c)
	expBg := charBigramJaccard(expandedOCR, c)
	if expBg > bg {
		bg = expBg
	}

	// Signal 4: anchor-token match. Numbers ("180", "B7", "100"), 1-char
	// distinguishers ("Mc"), or known-strong brand markers ("PM", "OC")
	// shared between OCR and candidate add 0.10.
	anchorBoost := 0.0
	if anchorTokenMatch(o, c) || anchorTokenMatch(expandedOCR, c) {
		anchorBoost = 0.10
	}

	// Combined score = weighted blend. Levenshtein 50% + bigram 40% + anchor 10%.
	score := 0.5*levRatio + 0.4*bg + anchorBoost
	if score > 1.0 {
		score = 1.0
	}
	return score
}

// expandAbbreviations rewrites common Indian liquor-shop shorthand into
// full canonical forms. Built from the most-occurring user-confirmed
// aliases in chhotu's tenant alias DB and shop-floor common usage.
//
// Rules applied left-to-right; first match wins per token.
func expandAbbreviations(s string) string {
	tokens := strings.Fields(s)
	if len(tokens) == 0 {
		return s
	}
	// Map of single-token abbreviations → expansion. Lowercased.
	abbr := map[string]string{
		"mcd":       "mc dowells no1 original blended whisky",
		"mcdowell":  "mc dowells no1 original blended whisky",
		"mcdowells": "mc dowells no1 original blended whisky",
		"oc":        "officers choice original whisky",
		"ocb":       "officers choice blue superior",
		"ob":        "old monk legend",
		"vov":       "old monk vatted very old",
		"bp":        "blenders pride exclusive premium",
		"sov":       "1965 spirit of victory xxx rum",
		"rs":        "royal stag superior",
		"rsb":       "royal stag barrel select",
		"rc":        "royal challenge select premium",
		"rg":        "royal green reserve blended",
		"bdg":       "black dog triple gold",
		"bdc":       "black dog centenary black",
		"bw":        "black white celebration",
		"m2":        "m2 magic moments",
		"mm":        "m2 magic moments",
		"m.m":       "m2 magic moments",
		"ib":        "imperial blue dual cask",
		"sr":        "sterling reserve b7 special",
		"b7":        "sterling reserve b7",
		"ad":        "after dark blue rare grain",
		"ms":        "magic moments superior vodka",
		"sm":        "smirnoff orange triple distilled",
	}
	// Apply expansion only when the abbreviation is a STANDALONE token
	// (no false positives on "BP" inside "Blenders Pride" since "blenders"
	// already matches without expansion).
	expanded := make([]string, 0, len(tokens)+4)
	for _, tok := range tokens {
		clean := strings.TrimFunc(tok, func(r rune) bool {
			return r == '.' || r == ',' || r == ':' || r == ';' || r == '/'
		})
		if exp, ok := abbr[clean]; ok {
			expanded = append(expanded, exp)
		} else {
			expanded = append(expanded, tok)
		}
	}
	return strings.Join(expanded, " ")
}

// levenshteinRatio = 1 - (edit_distance / max(len_a, len_b)).
// Returns 0..1 where 1 = identical, 0 = completely different.
func levenshteinRatio(a, b string) float64 {
	if a == b {
		return 1.0
	}
	maxLen := len(a)
	if len(b) > maxLen {
		maxLen = len(b)
	}
	if maxLen == 0 {
		return 0
	}
	d := levenshtein(a, b)
	r := 1.0 - float64(d)/float64(maxLen)
	if r < 0 {
		return 0
	}
	return r
}

// levenshtein computes the standard edit distance (insertions, deletions,
// substitutions). Iterative two-row DP — O(len_a * len_b) time, O(len_b) space.
func levenshtein(a, b string) int {
	if a == b {
		return 0
	}
	if len(a) == 0 {
		return len(b)
	}
	if len(b) == 0 {
		return len(a)
	}
	prev := make([]int, len(b)+1)
	curr := make([]int, len(b)+1)
	for j := 0; j <= len(b); j++ {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		curr[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			curr[j] = minInt3(prev[j]+1, curr[j-1]+1, prev[j-1]+cost)
		}
		prev, curr = curr, prev
	}
	return prev[len(b)]
}

// charBigramJaccard splits both strings into character bigrams (sliding
// window of 2 chars) and computes Jaccard similarity. Robust to typos,
// truncations, and cursive joins where token-level jaccard fails.
func charBigramJaccard(a, b string) float64 {
	if a == b {
		return 1.0
	}
	bgA := charBigrams(a)
	bgB := charBigrams(b)
	if len(bgA) == 0 || len(bgB) == 0 {
		return 0
	}
	inter := 0
	for k := range bgA {
		if _, ok := bgB[k]; ok {
			inter++
		}
	}
	un := len(bgA) + len(bgB) - inter
	if un == 0 {
		return 0
	}
	return float64(inter) / float64(un)
}

func charBigrams(s string) map[string]struct{} {
	out := map[string]struct{}{}
	s = strings.ReplaceAll(s, " ", "")
	if len(s) < 2 {
		if len(s) == 1 {
			out[s] = struct{}{}
		}
		return out
	}
	for i := 0; i < len(s)-1; i++ {
		out[s[i:i+2]] = struct{}{}
	}
	return out
}

// anchorTokenMatch returns true if the OCR string and candidate share a
// distinctive anchor — a numeric token (180, 100, B7), a 2-3 char
// brand-marker token (PM, OC, M2), or a fully-uppercase distinctive word.
func anchorTokenMatch(ocr, candidate string) bool {
	oTokens := strings.Fields(ocr)
	cTokens := strings.Fields(candidate)
	for _, ot := range oTokens {
		ot = strings.TrimFunc(ot, func(r rune) bool {
			return r == '.' || r == ',' || r == ':' || r == ';' || r == '/'
		})
		if !isAnchorToken(ot) {
			continue
		}
		for _, ct := range cTokens {
			ct = strings.TrimFunc(ct, func(r rune) bool {
				return r == '.' || r == ',' || r == ':' || r == ';' || r == '/'
			})
			if ot == ct {
				return true
			}
		}
	}
	return false
}

// isAnchorToken returns true for numeric tokens, alphanumerics like "B7",
// or 2-3 char short markers ("PM", "OC", "M2").
func isAnchorToken(t string) bool {
	if len(t) == 0 {
		return false
	}
	hasDigit := false
	hasAlpha := false
	for _, r := range t {
		if r >= '0' && r <= '9' {
			hasDigit = true
		} else if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
			hasAlpha = true
		}
	}
	// Pure-numeric token is always an anchor (180, 100, 750)
	if hasDigit && !hasAlpha {
		return true
	}
	// Mixed alphanumeric (B7, M2, M.M) is an anchor when ≤ 4 chars
	if hasDigit && hasAlpha && len(t) <= 4 {
		return true
	}
	// 2-3 char alpha-only tokens are markers (PM, OC, BP)
	if hasAlpha && !hasDigit && len(t) >= 2 && len(t) <= 3 {
		return true
	}
	return false
}

func minInt3(a, b, c int) int {
	m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}
