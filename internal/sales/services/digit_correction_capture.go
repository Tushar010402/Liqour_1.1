package services

import (
	"fmt"
	"log"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// digitCorrectionPair is one (raw_ai → user_corrected) sample for a single
// numeric field on a single review row.
type digitCorrectionPair struct {
	Field          string
	RawValue       string
	CorrectedValue string
}

// captureDigitCorrections persists per-shop (raw AI → user-corrected) pairs
// into ocr_digit_corrections. Idempotent + async; mirrors the inventory
// package's helper so Smart Sale doesn't have to cross-import.
func captureDigitCorrections(
	db *gorm.DB,
	tenantID uuid.UUID,
	shopID uuid.UUID,
	source string,
	pairs []digitCorrectionPair,
) {
	if db == nil || len(pairs) == 0 || tenantID == uuid.Nil || shopID == uuid.Nil {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("captureDigitCorrections panic recovered: %v (source=%s tenant=%s shop=%s)", r, source, tenantID, shopID)
			}
		}()
		hits := 0
		for _, p := range pairs {
			if p.RawValue == p.CorrectedValue || p.RawValue == "" || p.CorrectedValue == "" {
				continue
			}
			if err := db.Exec(`
				INSERT INTO ocr_digit_corrections
					(tenant_id, shop_id, source, field, raw_value, corrected_value,
					 occurrence_count, last_seen, first_seen)
				VALUES (?, ?, ?, ?, ?, ?, 1, NOW(), NOW())
				ON CONFLICT (tenant_id, shop_id, source, field, raw_value, corrected_value) DO UPDATE SET
					occurrence_count = ocr_digit_corrections.occurrence_count + 1,
					last_seen = NOW()
			`, tenantID, shopID, source, p.Field, p.RawValue, p.CorrectedValue).Error; err != nil {
				log.Printf("captureDigitCorrections upsert failed: %v (field=%s raw=%s corr=%s)", err, p.Field, p.RawValue, p.CorrectedValue)
				continue
			}
			hits++
		}
		log.Printf("captureDigitCorrections: source=%s tenant=%s shop=%s pairs=%d learned=%d", source, tenantID, shopID, len(pairs), hits)
	}()
}

func digitCorrectionsFromIntPair(field string, raw *int, corrected int) *digitCorrectionPair {
	if raw == nil || *raw == corrected {
		return nil
	}
	return &digitCorrectionPair{Field: field, RawValue: fmt.Sprintf("%d", *raw), CorrectedValue: fmt.Sprintf("%d", corrected)}
}

// ResolveDoubt persists ONE operator answer from the C2 doubt-popup queue
// (smart_sale_screen.dart _DoubtQueueModal). Mirrors captureDigitCorrections
// upsert semantics so the same raw→corrected pair across multiple sessions
// increments occurrence_count instead of duplicating rows. Returns true when
// a row was actually written (false on dedup or on no-op pairs).
//
// Idempotent + synchronous (the operator-facing modal needs to confirm the
// write succeeded before walking to the next doubt).
func (s *SmartSaleService) ResolveDoubt(
	tenantID uuid.UUID,
	shopID uuid.UUID,
	jobID string,
	clientRowID string,
	field string,
	rule string,
	aiInt *int,
	aiFloat *float64,
	userInt *int,
	userFloat *float64,
	acceptedSuggested bool,
) (bool, error) {
	if tenantID == uuid.Nil || shopID == uuid.Nil || field == "" {
		return false, fmt.Errorf("ResolveDoubt: missing tenant/shop/field")
	}

	rawValue := ""
	correctedValue := ""
	switch {
	case userInt != nil:
		correctedValue = fmt.Sprintf("%d", *userInt)
		if aiInt != nil {
			rawValue = fmt.Sprintf("%d", *aiInt)
		}
	case userFloat != nil:
		correctedValue = fmt.Sprintf("%.0f", *userFloat)
		if aiFloat != nil {
			rawValue = fmt.Sprintf("%.0f", *aiFloat)
		}
	default:
		return false, fmt.Errorf("ResolveDoubt: user_value required")
	}
	if rawValue == "" || correctedValue == "" || rawValue == correctedValue {
		// No usable signal (operator confirmed AI value, or AI cell was
		// blank). Still log for telemetry but don't write to corrections.
		s.logger.Infof("ResolveDoubt: tenant=%s shop=%s job=%s field=%s rule=%s skip-noop raw=%q corr=%q accepted=%v",
			tenantID, shopID, jobID, field, rule, rawValue, correctedValue, acceptedSuggested)
		return false, nil
	}

	source := "smart_sale_doubt"
	if acceptedSuggested {
		source = "smart_sale_doubt_accept"
	}
	err := s.db.DB.Exec(`
		INSERT INTO ocr_digit_corrections
			(tenant_id, shop_id, source, field, raw_value, corrected_value,
			 occurrence_count, last_seen, first_seen)
		VALUES (?, ?, ?, ?, ?, ?, 1, NOW(), NOW())
		ON CONFLICT (tenant_id, shop_id, source, field, raw_value, corrected_value) DO UPDATE SET
			occurrence_count = ocr_digit_corrections.occurrence_count + 1,
			last_seen = NOW()
	`, tenantID, shopID, source, field, rawValue, correctedValue).Error
	if err != nil {
		return false, fmt.Errorf("ocr_digit_corrections upsert: %w", err)
	}
	s.logger.Infof("ResolveDoubt: LEARNED tenant=%s shop=%s job=%s field=%s rule=%s raw=%q -> %q (accepted=%v)",
		tenantID, shopID, jobID, field, rule, rawValue, correctedValue, acceptedSuggested)
	return true, nil
}

func digitCorrectionsFromFloatPair(field string, raw *float64, corrected float64) *digitCorrectionPair {
	if raw == nil {
		return nil
	}
	diff := *raw - corrected
	if diff < 0 {
		diff = -diff
	}
	if diff < 0.5 {
		return nil
	}
	return &digitCorrectionPair{Field: field, RawValue: fmt.Sprintf("%.0f", *raw), CorrectedValue: fmt.Sprintf("%.0f", corrected)}
}

// LearnedDigitConfusion is one row pulled from ocr_digit_corrections.
type LearnedDigitConfusion struct {
	Field           string
	RawValue        string
	CorrectedValue  string
	OccurrenceCount int
}

// LoadTopDigitConfusions returns the most-frequent confusions for a shop.
func LoadTopDigitConfusions(
	db *gorm.DB,
	tenantID uuid.UUID,
	shopID uuid.UUID,
	source string,
	limit int,
) []LearnedDigitConfusion {
	if db == nil || tenantID == uuid.Nil || shopID == uuid.Nil || limit <= 0 {
		return nil
	}
	var rows []LearnedDigitConfusion
	if err := db.Raw(`
		SELECT field, raw_value, corrected_value, occurrence_count
		FROM ocr_digit_corrections
		WHERE tenant_id = ? AND shop_id = ? AND source = ?
		ORDER BY occurrence_count DESC, last_seen DESC
		LIMIT ?
	`, tenantID, shopID, source, limit).Scan(&rows).Error; err != nil {
		log.Printf("LoadTopDigitConfusions failed: %v (source=%s tenant=%s shop=%s)", err, source, tenantID, shopID)
		return nil
	}
	return rows
}

// LoadConfirmedDigitCorrections returns (raw → corrected) pairs that have
// been confirmed at least `minOccurrence` times for THIS shop. The textract
// pipeline calls this once per page and silently applies the corrections to
// matching cell values, so the operator never sees the same digit confusion
// twice (after the threshold).
//
// Track C5 — same-doubt-thrice auto-fix learning loop. The threshold defaults
// to 3 (env SMART_SALE_AUTO_FIX_THRESHOLD); below that, doubts still go to
// the popup queue.
func LoadConfirmedDigitCorrections(
	db *gorm.DB,
	tenantID uuid.UUID,
	shopID uuid.UUID,
	minOccurrence int,
) map[string]map[string]string {
	if db == nil || tenantID == uuid.Nil || shopID == uuid.Nil || minOccurrence < 1 {
		return nil
	}
	type row struct {
		Field          string
		RawValue       string
		CorrectedValue string
	}
	var rows []row
	if err := db.Raw(`
		SELECT field, raw_value, corrected_value
		FROM ocr_digit_corrections
		WHERE tenant_id = ? AND shop_id = ?
		  AND occurrence_count >= ?
		ORDER BY occurrence_count DESC, last_seen DESC
		LIMIT 500
	`, tenantID, shopID, minOccurrence).Scan(&rows).Error; err != nil {
		log.Printf("LoadConfirmedDigitCorrections failed: %v (tenant=%s shop=%s)", err, tenantID, shopID)
		return nil
	}
	if len(rows) == 0 {
		return nil
	}
	out := map[string]map[string]string{}
	for _, r := range rows {
		if _, ok := out[r.Field]; !ok {
			out[r.Field] = map[string]string{}
		}
		// First win — query is sorted by occurrence_count DESC so the most
		// trusted correction takes precedence.
		if _, exists := out[r.Field][r.RawValue]; !exists {
			out[r.Field][r.RawValue] = r.CorrectedValue
		}
	}
	return out
}

// v1.0.133-r5 — alias few-shot priors for Smart Sale Claude prompt.
// Mirrors the digit-confusion pattern below: load top-N (alias → canonical)
// pairs with occurrence_count >= minOcc, format as a compact prompt block,
// inject into Claude's system prompt before the brand-extraction call. The
// 31 aliases captured this week never fed back into Smart Sale extraction
// before this — Stock Setup had `FewShotPromptHint` but Smart Sale's prompt
// pipeline only had digit hints.

// LearnedAlias is one row pulled from ocr_brand_aliases for prompt-priors.
type LearnedAlias struct {
	AliasName           string
	CanonicalBrandName  string
	OccurrenceCount     int
}

// LoadTopAliasesForTenant returns the top-N most-confident brand aliases for
// a tenant, suitable for injecting as Claude few-shot priors. Filters by
// occurrence_count >= minOcc to skip noise (a single user pick that may be
// wrong). Sorted by occurrence_count DESC, last_used_at DESC so the most
// trusted, most recent learnings come first.
func LoadTopAliasesForTenant(
	db *gorm.DB,
	tenantID uuid.UUID,
	minOcc int,
	limit int,
) []LearnedAlias {
	if db == nil || tenantID == uuid.Nil || limit <= 0 {
		return nil
	}
	if minOcc < 1 {
		minOcc = 1
	}
	var rows []LearnedAlias
	if err := db.Raw(`
		SELECT alias_name, canonical_brand_name, occurrence_count
		FROM ocr_brand_aliases
		WHERE tenant_id = ?
		  AND occurrence_count >= ?
		  AND deleted_at IS NULL
		ORDER BY occurrence_count DESC, last_used_at DESC NULLS LAST, updated_at DESC
		LIMIT ?
	`, tenantID, minOcc, limit).Scan(&rows).Error; err != nil {
		log.Printf("LoadTopAliasesForTenant failed: %v (tenant=%s)", err, tenantID)
		return nil
	}
	return rows
}

// FormatAliasesForPrompt renders the rows as a compact few-shot block the
// Smart Sale extractor can prepend to Claude's system prompt. Empty string
// when there's no learned signal yet (so cold-start tenants don't get an
// empty header in the prompt).
func FormatAliasesForPrompt(rows []LearnedAlias) string {
	if len(rows) == 0 {
		return ""
	}
	out := "Tenant's most-confident brand aliases (verified by users):\n"
	for _, r := range rows {
		out += fmt.Sprintf("  • Raw text \"%s\" → product \"%s\" (verified %d×)\n",
			r.AliasName, r.CanonicalBrandName, r.OccurrenceCount)
	}
	out += "When you see similar handwriting in the register, prefer these mappings over guessing a similar-sounding brand. Avoid the rare canonical when one of these matches.\n"
	return out
}

// FormatDigitConfusionsForPrompt renders the rows as a compact few-shot block.
func FormatDigitConfusionsForPrompt(rows []LearnedDigitConfusion) string {
	if len(rows) == 0 {
		return ""
	}
	out := "Per-shop handwriting hints (most-frequent past confusions at this shop):\n"
	for _, r := range rows {
		out += fmt.Sprintf("  • Field '%s': you have previously read raw '%s' but the user corrected it to '%s' (%d times). Verify carefully.\n",
			r.Field, r.RawValue, r.CorrectedValue, r.OccurrenceCount)
	}
	out += "If you see similar handwriting, prefer the corrected value or flag the cell with low confidence.\n"
	return out
}
