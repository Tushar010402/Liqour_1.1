package services

import (
	"fmt"
	"log"
	"strconv"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// digitCorrectionPair is one (raw_ai → user_corrected) sample for a single
// numeric field on a single review row. Captured asynchronously by the apply
// path when both sides are non-nil and disagree.
type digitCorrectionPair struct {
	Field          string
	RawValue       string
	CorrectedValue string
}

// captureDigitCorrections persists per-shop (raw AI → user-corrected) numeric
// pairs into ocr_digit_corrections for handwriting / digit-shape learning.
// Aggregated by occurrence_count so the extractor prompt can later inject the
// most-frequent confusions for the shop as few-shot guidance.
//
// Idempotent — uses ON CONFLICT (tenant, shop, source, field, raw_value,
// corrected_value) DO UPDATE SET occurrence_count = +1, last_seen = now().
//
// Async / non-blocking — runs in a goroutine; never blocks the apply response.
//
// Source is "stock_setup" or "smart_sale" so reports can split learning hits
// by which review screen produced them.
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

// digitCorrectionsFromIntPair returns a (raw, corrected) pair when both values
// are non-nil and disagree. Helper to keep the apply-path call sites tidy.
func digitCorrectionsFromIntPair(field string, raw *int, corrected int) *digitCorrectionPair {
	if raw == nil {
		return nil
	}
	if *raw == corrected {
		return nil
	}
	return &digitCorrectionPair{
		Field:          field,
		RawValue:       fmt.Sprintf("%d", *raw),
		CorrectedValue: fmt.Sprintf("%d", corrected),
	}
}

// digitCorrectionsFromFloatPair returns a (raw, corrected) pair when both
// values are non-nil and disagree by more than 0.5. Floats are rendered with
// no decimals because rate/amount on registers are whole rupees.
func digitCorrectionsFromFloatPair(field string, raw *float64, corrected float64) *digitCorrectionPair {
	if raw == nil {
		return nil
	}
	if absFloat64(*raw-corrected) < 0.5 {
		return nil
	}
	return &digitCorrectionPair{
		Field:          field,
		RawValue:       fmt.Sprintf("%.0f", *raw),
		CorrectedValue: fmt.Sprintf("%.0f", corrected),
	}
}

// LearnedDigitConfusion is one row pulled from ocr_digit_corrections for a
// shop+field, used by the extractor prompt builder to inject few-shot
// guidance: "at this shop the AI has previously misread X as Y N times."
type LearnedDigitConfusion struct {
	Field           string
	RawValue        string
	CorrectedValue  string
	OccurrenceCount int
}

// LoadTopDigitConfusions returns up to `limit` most-frequent confusions for a
// shop+source, ordered by occurrence_count DESC then last_seen DESC. Used by
// both extractors before each Claude call.
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

// ResolveDoubt persists ONE operator answer from the v1.0.185 Track S5
// doubt-popup queue (StockSetupDoubtModal). Mirror of the Smart Sale
// `SmartSaleService.ResolveDoubt` shape; writes into the same
// ocr_digit_corrections table, sourced as 'stock_setup' so the read-side
// LoadConfirmedDigitCorrectionsForStockSetup can pick them up.
//
// Field can be any cell name: numeric (opening/receipt/total/closing/sale/rate/
// amount) or text (brand/name). Numeric pairs go into the corrections corpus
// for digit-handwriting auto-fix. Text pairs are NOT written here (handled
// by the alias-learning pipeline on apply).
//
// Returns (persisted, error). false on dedup or text-only (no-op for digits).
func (s *SmartStockSetupService) ResolveDoubt(
	tenantID uuid.UUID,
	shopID uuid.UUID,
	jobID string,
	clientRowID string,
	field string,
	rule string,
	aiInt *int,
	aiFloat *float64,
	aiText string,
	userInt *int,
	userFloat *float64,
	userText string,
	acceptedSuggested bool,
) (bool, error) {
	if tenantID == uuid.Nil || shopID == uuid.Nil || field == "" {
		return false, fmt.Errorf("ResolveDoubt: missing tenant/shop/field")
	}

	// Brand / name doubts are captured via the alias pipeline on apply, not
	// here. Log for telemetry but don't write to ocr_digit_corrections (which
	// only stores numeric raw→corrected pairs).
	if field == "brand" || field == "name" {
		log.Printf("Smart Stock Setup ResolveDoubt: field=%s text-only (alias learning will fire on apply) tenant=%s shop=%s rule=%s ai=%q user=%q",
			field, tenantID, shopID, rule, aiText, userText)
		return false, nil
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
		return false, fmt.Errorf("ResolveDoubt: user_value required for numeric field %q", field)
	}
	if rawValue == "" || correctedValue == "" || rawValue == correctedValue {
		log.Printf("Smart Stock Setup ResolveDoubt: tenant=%s shop=%s field=%s rule=%s skip-noop raw=%q corr=%q accepted=%v",
			tenantID, shopID, field, rule, rawValue, correctedValue, acceptedSuggested)
		return false, nil
	}

	source := "stock_setup_doubt"
	if acceptedSuggested {
		source = "stock_setup_doubt_accept"
	}
	// Stamp into ocr_digit_corrections with source='stock_setup' for the
	// read path (LoadConfirmedDigitCorrectionsForStockSetup queries that
	// source). The doubt-specific source label above is preserved in the
	// `source` column for telemetry.
	err := s.db.Exec(`
		INSERT INTO ocr_digit_corrections
			(tenant_id, shop_id, source, field, raw_value, corrected_value,
			 occurrence_count, last_seen, first_seen)
		VALUES (?, ?, 'stock_setup', ?, ?, ?, 1, NOW(), NOW())
		ON CONFLICT (tenant_id, shop_id, source, field, raw_value, corrected_value) DO UPDATE SET
			occurrence_count = ocr_digit_corrections.occurrence_count + 1,
			last_seen = NOW()
	`, tenantID, shopID, field, rawValue, correctedValue).Error
	if err != nil {
		return false, fmt.Errorf("ocr_digit_corrections upsert: %w", err)
	}
	log.Printf("Smart Stock Setup ResolveDoubt: LEARNED tenant=%s shop=%s field=%s rule=%s raw=%q -> %q (accepted=%v src=%s)",
		tenantID, shopID, field, rule, rawValue, correctedValue, acceptedSuggested, source)
	return true, nil
}

// LoadConfirmedDigitCorrectionsForStockSetup returns (raw → corrected) pairs
// confirmed at least `minOccurrence` times for THIS shop. The Stock Setup
// Textract pipeline calls this once and silently applies the corrections to
// matching cell values BEFORE the math-gate / matcher run. Mirror of the
// Smart Sale `LoadConfirmedDigitCorrections` in
// /var/www/liquorpro/internal/sales/services/digit_correction_capture.go;
// scoped to source="stock_setup" so the two services don't pollute each
// other's learning corpora.
//
// v1.0.184 Track S4 — same-doubt-thrice auto-fix learning loop.
func LoadConfirmedDigitCorrectionsForStockSetup(
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
		WHERE tenant_id = ? AND shop_id = ? AND source = 'stock_setup'
		  AND occurrence_count >= ?
		ORDER BY occurrence_count DESC, last_seen DESC
		LIMIT 500
	`, tenantID, shopID, minOccurrence).Scan(&rows).Error; err != nil {
		log.Printf("LoadConfirmedDigitCorrectionsForStockSetup failed: %v (tenant=%s shop=%s)", err, tenantID, shopID)
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
		if _, exists := out[r.Field][r.RawValue]; !exists {
			out[r.Field][r.RawValue] = r.CorrectedValue
		}
	}
	return out
}

// applyConfirmedDigitCorrectionsStockSetup walks one row and replaces every
// cell whose extracted value matches a confirmed (raw → corrected) entry
// for this shop. Returns the number of cells replaced. Mutates row in place.
//
// Mapping: keyed by field name ("opening", "receipt", "total", "sale",
// "closing", "rate", "amount") to avoid cross-cell pollution (a "5"→"9" on
// rate shouldn't auto-fix opening qty).
func applyConfirmedDigitCorrectionsStockSetup(row *ExtractedStockRegisterItem, confirmed map[string]map[string]string) int {
	if row == nil || len(confirmed) == 0 {
		return 0
	}
	hits := 0
	tryInt := func(field string, current *int) {
		if current == nil || *current == 0 {
			return
		}
		m, ok := confirmed[field]
		if !ok || len(m) == 0 {
			return
		}
		raw := fmt.Sprintf("%d", *current)
		corr, ok := m[raw]
		if !ok || corr == raw {
			return
		}
		v, err := strconv.Atoi(corr)
		if err != nil {
			return
		}
		*current = v
		hits++
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		row.FieldConfidence[field] = 0.97
	}
	tryFloat := func(field string, current *float64) {
		if current == nil || *current == 0 {
			return
		}
		m, ok := confirmed[field]
		if !ok || len(m) == 0 {
			return
		}
		raw := fmt.Sprintf("%.0f", *current)
		corr, ok := m[raw]
		if !ok || corr == raw {
			return
		}
		v, err := strconv.ParseFloat(corr, 64)
		if err != nil {
			return
		}
		*current = v
		hits++
		if row.FieldConfidence == nil {
			row.FieldConfidence = map[string]float64{}
		}
		row.FieldConfidence[field] = 0.97
	}

	tryInt("opening", &row.Opening)
	tryInt("receipt", &row.Receipt)
	tryInt("total", &row.Total)
	tryInt("sale", &row.Sale)
	tryInt("closing", &row.Closing)
	tryFloat("rate", &row.Rate)
	tryFloat("amount", &row.Amount)
	return hits
}

// FormatDigitConfusionsForPrompt renders the rows as a compact few-shot block
// the extractor can drop into Claude's system prompt. Empty string when
// there's no learned signal (so the prompt stays unchanged for new shops).
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
