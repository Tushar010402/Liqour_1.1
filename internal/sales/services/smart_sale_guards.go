package services

import (
	"fmt"
	"log"
	"math"
	"sort"

	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ============================================================================
// Smart Sale post-extraction guards (parity with smart_stock_setup_guards.go).
//
// Three deterministic guards run on every Sale extraction (Claude / Gemini /
// OpenAI) before product matching, plus a phantom-row suppressor.
//
//   ApplySaleRateOutlierGuard  — z-score > 3 against page mean → demote rate/amount
//   ApplySaleChecksumGuard     — Sale × Rate ≈ Amount; AUTO-CORRECT Amount when
//                                mismatch (user-confirmed: trust Sale and Rate
//                                as more legible columns; recompute Amount
//                                silently with a warning chip).
//   ApplySaleRateMonotonicGuard — registers ordered ascending by rate; >30%
//                                drop between adjacent rows demotes both.
//
// Why duplicate from inventory/services? The Stock Setup guards operate on
// ExtractedStockRegisterItem; Sale operates on SmartSaleExtractedItem with
// different field names (Quantity vs Sale, OpeningStock pointer vs Opening
// int). 150 LOC of mechanical duplication is cleaner than introducing a
// shared interface that adds noise to every Phase-2 push.
// ============================================================================

const (
	saleRateOutlierMinSamples   = 5
	saleRateOutlierZThreshold   = 3.0
	saleRateMonotonicMaxDropPct = 0.30
	saleChecksumTolerancePct    = 0.02
	saleChecksumMinAmount       = 10.0
	saleChecksumMaxAmount       = 100000.0 // above this Sale*Rate is absurd → don't auto-correct
)

// ApplySaleRateOutlierGuard flags rates more than 3σ from page mean.
func ApplySaleRateOutlierGuard(items []SmartSaleExtractedItem) {
	rates := make([]float64, 0, len(items))
	for _, it := range items {
		if it.Rate > 0 {
			rates = append(rates, it.Rate)
		}
	}
	if len(rates) < saleRateOutlierMinSamples {
		return
	}
	mean := 0.0
	for _, r := range rates {
		mean += r
	}
	mean /= float64(len(rates))
	variance := 0.0
	for _, r := range rates {
		variance += (r - mean) * (r - mean)
	}
	stddev := math.Sqrt(variance / float64(len(rates)))
	if stddev < 1.0 {
		return
	}
	flagged := 0
	for i := range items {
		if items[i].Rate <= 0 {
			continue
		}
		z := math.Abs(items[i].Rate-mean) / stddev
		if z > saleRateOutlierZThreshold {
			log.Printf("Smart Sale: rate outlier on row %d: ₹%.0f (page mean ₹%.0f, z=%.2f)",
				items[i].RowNumber, items[i].Rate, mean, z)
			if items[i].FieldConfidence == nil {
				items[i].FieldConfidence = map[string]float64{}
			}
			items[i].FieldConfidence["rate"] = 0.5
			items[i].FieldConfidence["amount"] = 0.5
			if items[i].Confidence > 0.6 {
				items[i].Confidence = 0.6
			}
			items[i].Warnings = append(items[i].Warnings, "Rate looks unusual vs other rows on this page — verify")
			flagged++
		}
	}
	if flagged > 0 {
		log.Printf("Smart Sale: rate-outlier guard flagged %d/%d rows", flagged, len(items))
	}
}

// ApplySaleChecksumGuard auto-corrects Amount when Sale × Rate disagrees
// (CONFIRMED user choice). Logs and warns; never blocks the row. Skips when
// Sale × Rate is absurd (>₹100k or <₹10) — those imply Rate or Sale is wrong,
// not Amount, so we fall back to confidence demotion only.
//
// Trade-off accepted by the user: if AI misread Sale or Rate, the Amount
// auto-fix amplifies that error. Mitigated by (a) the rate-outlier guard
// catching extreme rate misreads upstream, (b) per-field amber underline
// still showing on the recomputed Amount cell so user can verify.
func ApplySaleChecksumGuard(items []SmartSaleExtractedItem) {
	autoFixed := 0
	demoted := 0
	for i := range items {
		it := &items[i]
		if it.Quantity <= 0 || it.Rate <= 0 || it.Amount < saleChecksumMinAmount {
			continue
		}
		expected := float64(it.Quantity) * it.Rate
		diff := math.Abs(it.Amount - expected)
		diffPct := diff / it.Amount
		if diffPct <= saleChecksumTolerancePct {
			continue
		}

		// Edge case: Sale × Rate is itself absurd. Don't auto-correct because
		// it would amplify the error. Just demote confidence and log.
		if expected < saleChecksumMinAmount || expected > saleChecksumMaxAmount {
			log.Printf("Smart Sale: checksum mismatch row %d (absurd-expected) — qty=%d × rate=%.0f = %.0f, amount=%.0f (diff %.0f%%); NOT auto-correcting",
				it.RowNumber, it.Quantity, it.Rate, expected, it.Amount, diffPct*100)
			if it.FieldConfidence == nil {
				it.FieldConfidence = map[string]float64{}
			}
			it.FieldConfidence["sale"] = 0.5
			it.FieldConfidence["rate"] = 0.55
			it.FieldConfidence["amount"] = 0.55
			if it.Confidence > 0.6 {
				it.Confidence = 0.6
			}
			it.NeedsReview = true
			it.Warnings = append(it.Warnings,
				fmt.Sprintf("Amount (₹%.0f), qty (%d), rate (₹%.0f) don't agree — verify all three", it.Amount, it.Quantity, it.Rate))
			demoted++
			continue
		}

		// Normal case: trust Sale and Rate, overwrite Amount.
		log.Printf("Smart Sale: amount auto-corrected row %d — AI read ₹%.0f, computed ₹%.0f from qty=%d × rate=%.0f (was %.0f%% off)",
			it.RowNumber, it.Amount, expected, it.Quantity, it.Rate, diffPct*100)
		oldAmount := it.Amount
		it.Amount = expected
		if it.FieldConfidence == nil {
			it.FieldConfidence = map[string]float64{}
		}
		it.FieldConfidence["amount"] = 0.55
		it.Warnings = append(it.Warnings,
			fmt.Sprintf("Amount auto-fixed: AI read ₹%.0f, recomputed ₹%.0f from %d × ₹%.0f", oldAmount, expected, it.Quantity, it.Rate))
		autoFixed++
	}
	if autoFixed+demoted > 0 {
		log.Printf("Smart Sale: checksum guard — auto-fixed %d, demoted-to-review %d (of %d rows)",
			autoFixed, demoted, len(items))
	}
}

// ApplySaleRateMonotonicGuard exploits the convention that registers are
// sorted ascending by rate. >30% drop between adjacent rows is suspicious.
func ApplySaleRateMonotonicGuard(items []SmartSaleExtractedItem) {
	if len(items) < 2 {
		return
	}
	idxs := make([]int, len(items))
	for i := range items {
		idxs[i] = i
	}
	sort.Slice(idxs, func(a, b int) bool {
		ra, rb := items[idxs[a]].RowNumber, items[idxs[b]].RowNumber
		pa, pb := items[idxs[a]].PageNumber, items[idxs[b]].PageNumber
		if pa != pb {
			return pa < pb
		}
		return ra < rb
	})
	flagged := 0
	for k := 1; k < len(idxs); k++ {
		prev := &items[idxs[k-1]]
		cur := &items[idxs[k]]
		// Only enforce monotonicity within a page.
		if prev.PageNumber != cur.PageNumber {
			continue
		}
		if prev.Rate <= 0 || cur.Rate <= 0 {
			continue
		}
		drop := (prev.Rate - cur.Rate) / prev.Rate
		if drop <= saleRateMonotonicMaxDropPct {
			continue
		}
		log.Printf("Smart Sale: rate-monotonic violation row %d→%d: ₹%.0f → ₹%.0f (drop %.0f%%)",
			prev.RowNumber, cur.RowNumber, prev.Rate, cur.Rate, drop*100)
		for _, it := range []*SmartSaleExtractedItem{prev, cur} {
			if it.FieldConfidence == nil {
				it.FieldConfidence = map[string]float64{}
			}
			if c := it.FieldConfidence["rate"]; c == 0 || c > 0.65 {
				it.FieldConfidence["rate"] = 0.65
			}
		}
		if cur.Confidence > 0.7 {
			cur.Confidence = 0.7
		}
		flagged++
	}
	if flagged > 0 {
		log.Printf("Smart Sale: rate-monotonic guard flagged %d transitions", flagged)
	}
}

// ApplySaleAllGuards runs all three guards in order.
func ApplySaleAllGuards(items []SmartSaleExtractedItem) {
	ApplySaleRateOutlierGuard(items)
	ApplySaleChecksumGuard(items)
	ApplySaleRateMonotonicGuard(items)
}

// ApplySalePhantomRowSuppressor drops preprinted-only rows (sale=0, amount=0,
// confidence < 0.9, brand not in tenant catalog). Returns the kept slice and
// the count suppressed.
func ApplySalePhantomRowSuppressor(items []SmartSaleExtractedItem, tenantCatalogBrands map[string]bool) ([]SmartSaleExtractedItem, int) {
	if len(items) == 0 {
		return items, 0
	}
	suppressed := 0
	kept := items[:0]
	for _, it := range items {
		// Allow rows with Quantity > 0 OR Amount > 0 OR Opening > 0 (real entries)
		hasOpening := it.OpeningStock != nil && *it.OpeningStock > 0
		allZero := it.Quantity == 0 && it.Amount == 0 && !hasOpening
		if !allZero {
			kept = append(kept, it)
			continue
		}
		confident := it.Confidence >= 0.9
		brandKey := normalizeBrandKey(it.BrandName + " " + it.OCRText)
		knownBrand := brandKey != "" && tenantCatalogBrands[brandKey]
		if confident || knownBrand {
			kept = append(kept, it)
			continue
		}
		log.Printf("Smart Sale: phantom row suppressed (page %d row %d): %q (conf=%.2f, all-zero, not in catalog)",
			it.PageNumber, it.RowNumber, it.BrandName, it.Confidence)
		suppressed++
	}
	if suppressed > 0 {
		log.Printf("Smart Sale: phantom suppressor dropped %d rows (%d → %d)",
			suppressed, len(items), len(kept))
	}
	return kept, suppressed
}

// buildSaleCatalogBrandSet converts the tenant's product list into the
// brand-key set used by the phantom suppressor. Two-token keys keep the
// match loose enough to handle minor OCR noise.
func buildSaleCatalogBrandSet(products []models.Product) map[string]bool {
	out := make(map[string]bool, len(products)*2)
	for _, p := range products {
		for _, name := range []string{p.Name, p.DisplayName} {
			if k := normalizeBrandKey(name); k != "" {
				out[k] = true
			}
		}
	}
	return out
}

// normalizeBrandKey is a lower-cased + token-truncated key used to match
// extracted brand text against the tenant's catalog for phantom detection.
// Two-token key keeps it loose enough to handle minor OCR noise.
func normalizeBrandKey(s string) string {
	const maxToks = 2
	out := ""
	count := 0
	for _, r := range s {
		if r == ' ' || r == '\t' {
			if count < maxToks-1 {
				out += " "
				count++
				continue
			}
			break
		}
		if r >= 'A' && r <= 'Z' {
			r += 32
		}
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == ' ' {
			out += string(r)
		}
	}
	return out
}
