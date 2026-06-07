package services

import (
	"strings"

	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
)

// v1.0.314 — Gap 2: dynamic column-layout detection.
//
// CONTEXT: chhotu's "SALE RECEIPT — 180 ML (contd.)" page 2 doesn't have an
// S.N column on the contd template (page 1 has 9 columns; page 2 has 8). The
// hardcoded mapping in textract_pipeline.go assumes 9 columns, so every cell
// on page 2 reads one column to the right of its real meaning — Brand reads
// "88" (Opening), Opening reads "Receipt", Sale reads "Rate", etc.
//
// The Python harness confirmed this end-to-end:
//   page 1 (9-col): raw=29 kept=28  ← clean read
//   page 2 (8-col): raw=30 kept=14, suspicious_brand=12  ← column-slip
//
// FIX: read row 1 (header) cell texts and figure out which Textract column
// index corresponds to each canonical field (BRAND, OPEN, SALE, RATE, etc).
// Build a `ColumnLayout` indexed by the canonical role, then have the row
// loop consume cells through this layout instead of the hardcoded constants.
//
// Falls back to the legacy 9-col mapping if header detection fails (no header
// row found / row 1 text doesn't match any expected keyword), so existing
// well-formed registers see zero behavior change.

// ColumnLayout maps each canonical sale-register role to the Textract column
// index that actually contains the data for that role on this particular
// page. Use the zero value to mean "column not present"; the row loop must
// tolerate missing columns (e.g. no S.N column on contd pages → SerialNo=0).
type ColumnLayout struct {
	SerialNo int32
	Brand    int32
	Opening  int32
	Receipt  int32
	Total    int32
	Sale     int32
	Rate     int32
	Amount   int32
	Closing  int32

	// Detected is true when at least Brand AND Sale columns were located via
	// header text (the minimum needed to read a row). False → caller should
	// fall back to the legacy hardcoded mapping.
	Detected bool

	// Source records how the layout was decided ("header_detect", "legacy_9col")
	// — useful for the log line so we can see when the dynamic path saved a
	// page that legacy would have garbled.
	Source string
}

// legacyColumnLayout returns the pre-v1.0.314 hardcoded 9-column mapping.
// Stored as a function (not a const) so tests can compare against the same
// values the production row loop falls back to.
func legacyColumnLayout() ColumnLayout {
	return ColumnLayout{
		SerialNo: int32(colSerialNo),
		Brand:    int32(colBrand),
		Opening:  int32(colOpening),
		Receipt:  int32(colReceipt),
		Total:    int32(colTotal),
		Sale:     int32(colSale),
		Rate:     int32(colRate),
		Amount:   int32(colAmount),
		Closing:  int32(colClosing),
		Detected: false,
		Source:   "legacy_9col",
	}
}

// detectColumnLayout walks all rows tagged COLUMN_HEADER by Textract and
// returns a ColumnLayout that maps each canonical role to its Textract column
// index. Falls back to legacyColumnLayout() when no header row has enough
// recognisable keywords (Brand + Sale required, ≥4 hits overall).
//
// Real-world calibration on chhotu's page 2: Textract returns row 1 as an
// empty "title band" + row 2 with the real "Brand Name / Openin / Receipt /
// Total / Sale / Rate / Amount / Closin" text (both rows marked
// COLUMN_HEADER). The pre-v1.0.314 detector only looked at row 1 and missed
// every contd page. EntityTypes-based scanning fixes that without depending
// on row index.
func detectColumnLayout(rowsByIdx map[int32]map[int32]ttypes.Block, blockByID map[string]ttypes.Block) ColumnLayout {
	headerRow := pickHeaderRow(rowsByIdx, blockByID)
	if len(headerRow) == 0 {
		return legacyColumnLayout()
	}

	out := ColumnLayout{Source: "header_detect"}
	hits := 0
	matches := func(fn func(string) bool, clean, compact string) bool {
		return fn(clean) || fn(compact)
	}
	for colIdx, cell := range headerRow {
		raw := strings.ToUpper(strings.TrimSpace(cellText(cell, blockByID)))
		if raw == "" {
			continue
		}
		// Two normalisations — clean keeps tokens separated ("S N", "M R P"),
		// compact collapses them ("SN", "MRP"). Header keywords like "MRP"
		// only match the compact form when Textract returns each letter as a
		// separate word; "S N" only matches in the spaced form.
		clean := stripHeaderPunct(raw)
		compact := strings.ReplaceAll(clean, " ", "")
		switch {
		case matches(looksLikeSerialHeader, clean, compact):
			out.SerialNo = colIdx
			hits++
		case matches(looksLikeBrandHeader, clean, compact):
			out.Brand = colIdx
			hits++
		case matches(looksLikeOpeningHeader, clean, compact):
			out.Opening = colIdx
			hits++
		case matches(looksLikeReceiptHeader, clean, compact):
			out.Receipt = colIdx
			hits++
		case matches(looksLikeTotalHeader, clean, compact):
			out.Total = colIdx
			hits++
		case matches(looksLikeSaleHeader, clean, compact):
			out.Sale = colIdx
			hits++
		case matches(looksLikeRateHeader, clean, compact):
			out.Rate = colIdx
			hits++
		case matches(looksLikeAmountHeader, clean, compact):
			out.Amount = colIdx
			hits++
		case matches(looksLikeClosingHeader, clean, compact):
			out.Closing = colIdx
			hits++
		}
	}

	// v1.0.319 — infer Brand/Serial from data-column positions when the
	// header row has the data labels (Opening / Sale / Rate / Amount /
	// Closing) but Brand/Serial cells were empty in the captured row.
	// chhotu's 750ml job a095aa63 page 1 hit exactly this: skewed photo +
	// rotated table, Textract returned a header row with the 5 data
	// columns clearly labelled but the S.N + Brand cells empty (the labels
	// "S.N" and "Brand Name" sat several rows lower in the cropped frame).
	// Without inference we'd fall back to legacy_9col, lose header_detect
	// trust, and the rescue gate would burn ~30s on Claude for no recall
	// gain. The shape of every register on this tenant is fixed:
	// S.N=Brand-1=Opening-2 to the left of Opening, so we can recover both
	// from the Opening column's index.
	if out.Brand == 0 && out.Opening > 1 {
		out.Brand = out.Opening - 1
		hits++
	}
	if out.SerialNo == 0 && out.Brand > 1 {
		out.SerialNo = out.Brand - 1
	}

	// Minimum bar: we MUST have Brand + Sale to read a row. Otherwise fall
	// back to legacy — we can always re-read the next page with detection
	// disabled if header was missed.
	if out.Brand == 0 || out.Sale == 0 || hits < 4 {
		return legacyColumnLayout()
	}
	out.Detected = true
	return out
}

// pickHeaderRow returns the cell map of the row that should be used for
// header-keyword scanning. Strategy:
//  1. Prefer rows whose cells carry Textract's COLUMN_HEADER EntityType AND
//     contain non-empty text. Scan all rows, score by header keyword hits,
//     return the row with the most hits.
//  2. Fall back to row 1 if no COLUMN_HEADER rows have data (legacy path).
//
// chhotu's page 2 has row 1 = empty (COLUMN_HEADER) + row 2 = actual headers
// (also COLUMN_HEADER). Scanning all COLUMN_HEADER rows finds row 2.
func pickHeaderRow(rowsByIdx map[int32]map[int32]ttypes.Block, blockByID map[string]ttypes.Block) map[int32]ttypes.Block {
	headerCandidates := make(map[int32]map[int32]ttypes.Block, 4)
	for rIdx, cells := range rowsByIdx {
		anyHeader := false
		anyText := false
		for _, cell := range cells {
			for _, et := range cell.EntityTypes {
				if et == ttypes.EntityTypeColumnHeader {
					anyHeader = true
					break
				}
			}
			if anyHeader {
				if strings.TrimSpace(cellText(cell, blockByID)) != "" {
					anyText = true
				}
			}
		}
		if anyHeader && anyText {
			headerCandidates[rIdx] = cells
		}
	}
	if len(headerCandidates) > 0 {
		// Multiple COLUMN_HEADER rows can carry text on multi-header receipts
		// (e.g. row 1 = "Rept Sale" sub-band + row 2 = column names). Score
		// each candidate by how many header keywords it contains, pick the
		// best.
		bestRow := map[int32]ttypes.Block{}
		bestHits := -1
		for _, cells := range headerCandidates {
			hits := countHeaderHits(cells, blockByID)
			if hits > bestHits {
				bestHits = hits
				bestRow = cells
			}
		}
		return bestRow
	}
	// Legacy fallback: try row 1.
	if r1, ok := rowsByIdx[1]; ok && len(r1) > 0 {
		return r1
	}
	return nil
}

func countHeaderHits(cells map[int32]ttypes.Block, blockByID map[string]ttypes.Block) int {
	hits := 0
	for _, cell := range cells {
		raw := strings.ToUpper(strings.TrimSpace(cellText(cell, blockByID)))
		if raw == "" {
			continue
		}
		clean := stripHeaderPunct(raw)
		compact := strings.ReplaceAll(clean, " ", "")
		switch {
		case looksLikeBrandHeader(clean) || looksLikeBrandHeader(compact),
			looksLikeOpeningHeader(clean) || looksLikeOpeningHeader(compact),
			looksLikeSaleHeader(clean) || looksLikeSaleHeader(compact),
			looksLikeRateHeader(clean) || looksLikeRateHeader(compact),
			looksLikeAmountHeader(clean) || looksLikeAmountHeader(compact),
			looksLikeClosingHeader(clean) || looksLikeClosingHeader(compact),
			looksLikeReceiptHeader(clean) || looksLikeReceiptHeader(compact),
			looksLikeTotalHeader(clean) || looksLikeTotalHeader(compact),
			looksLikeSerialHeader(clean) || looksLikeSerialHeader(compact):
			hits++
		}
	}
	return hits
}

// isHeaderRow returns true when ANY cell in the row carries the
// COLUMN_HEADER EntityType. Used by the data loop to skip every header
// band (not just row 1) before reading values.
func isHeaderRow(cells map[int32]ttypes.Block) bool {
	for _, cell := range cells {
		for _, et := range cell.EntityTypes {
			if et == ttypes.EntityTypeColumnHeader {
				return true
			}
		}
	}
	return false
}

// stripHeaderPunct collapses non-alphanumeric runs to a single space so
// "S.N." → "S N", "Openin/g" → "OPENIN G", " RECEIPT: " → "RECEIPT".
func stripHeaderPunct(s string) string {
	var b strings.Builder
	lastSpace := true
	for _, r := range s {
		isAlnum := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		if isAlnum {
			b.WriteRune(r)
			lastSpace = false
			continue
		}
		if !lastSpace {
			b.WriteRune(' ')
			lastSpace = true
		}
	}
	return strings.TrimSpace(b.String())
}

func headerContainsAny(h string, needles ...string) bool {
	for _, n := range needles {
		if strings.Contains(h, n) {
			return true
		}
	}
	return false
}

// Header keyword detectors. We intentionally check the SerialNo case last
// because "S N" / "SR NO" / "NO" are very short tokens and would
// false-match inside longer cells if checked first.
func looksLikeBrandHeader(h string) bool {
	return headerContainsAny(h, "BRAND", "ITEM", "PARTICULAR", "PRODUCT", "DESCRIPTION")
}
func looksLikeOpeningHeader(h string) bool {
	return headerContainsAny(h, "OPEN", "OPNG", "OPNIN", "OPENIN") && !headerContainsAny(h, "OPENED")
}
func looksLikeReceiptHeader(h string) bool {
	return headerContainsAny(h, "RECEIPT", "RECVD", "RECEIVED", "RECEI", "PURCH")
}
func looksLikeTotalHeader(h string) bool {
	// Distinct from "GRAND TOTAL" — that one is a footer, never a column header.
	// "TOTAL STOCK" / "TOTAL" mid-table = our Opening+Receipt column.
	if headerContainsAny(h, "GRAND") {
		return false
	}
	return headerContainsAny(h, "TOTAL", "TOT", "AVAIL")
}
func looksLikeSaleHeader(h string) bool {
	return headerContainsAny(h, "SALE", "SOLD", "SAL")
}
func looksLikeRateHeader(h string) bool {
	return headerContainsAny(h, "RATE", "MRP", "PRICE", "RT")
}
func looksLikeAmountHeader(h string) bool {
	return headerContainsAny(h, "AMOUNT", "AMT", "VALUE", "REVENU")
}
func looksLikeClosingHeader(h string) bool {
	return headerContainsAny(h, "CLOSING", "CLOSIN", "CLSG", "CLOSE", "BALANCE", "BAL")
}
func looksLikeSerialHeader(h string) bool {
	// Match standalone "S N", "S NO", "SR NO", "SRNO" — must be short.
	if len(h) > 6 {
		return false
	}
	return headerContainsAny(h, "S N", "SN", "SR", "NO", "SRL")
}
