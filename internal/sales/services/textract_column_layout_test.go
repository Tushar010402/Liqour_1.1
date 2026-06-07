package services

import (
	"testing"

	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
)

// mkHeaderRow builds a {colIdx: Block{...}} map mimicking the structure
// runTextractPageInner hands to detectColumnLayout for row 1. Each header
// cell holds one WORD child whose Text is the header string.
func mkHeaderRow(headers map[int32]string) (map[int32]ttypes.Block, map[string]ttypes.Block) {
	cells := map[int32]ttypes.Block{}
	byID := map[string]ttypes.Block{}
	idx := 0
	for colIdx, txt := range headers {
		wordID := stringPtr("word-" + textOf(colIdx))
		cellID := stringPtr("cell-" + textOf(colIdx))
		txtCopy := txt
		word := ttypes.Block{
			Id:        wordID,
			BlockType: ttypes.BlockTypeWord,
			Text:      &txtCopy,
		}
		cell := ttypes.Block{
			Id:        cellID,
			BlockType: ttypes.BlockTypeCell,
			Relationships: []ttypes.Relationship{
				{Type: ttypes.RelationshipTypeChild, Ids: []string{*wordID}},
			},
		}
		byID[*wordID] = word
		byID[*cellID] = cell
		cells[colIdx] = cell
		idx++
	}
	return cells, byID
}

func stringPtr(s string) *string { return &s }

func textOf(i int32) string {
	out := []byte{}
	if i == 0 {
		return "0"
	}
	n := i
	for n > 0 {
		out = append([]byte{'0' + byte(n%10)}, out...)
		n /= 10
	}
	return string(out)
}

func TestDetectColumnLayout_Page1NineCol(t *testing.T) {
	// chhotu's page-1 layout: 9 columns including S.N.
	cells, byID := mkHeaderRow(map[int32]string{
		1: "S.N",
		2: "Brand Name",
		3: "Openin",
		4: "Receipt",
		5: "Total",
		6: "Sale",
		7: "Rate",
		8: "Amount",
		9: "Closin",
	})
	rows := map[int32]map[int32]ttypes.Block{1: cells}
	got := detectColumnLayout(rows, byID)
	if !got.Detected {
		t.Fatalf("expected Detected=true on clean 9-col header")
	}
	if got.SerialNo != 1 || got.Brand != 2 || got.Opening != 3 ||
		got.Receipt != 4 || got.Total != 5 || got.Sale != 6 ||
		got.Rate != 7 || got.Amount != 8 || got.Closing != 9 {
		t.Errorf("9-col mapping wrong: %+v", got)
	}
}

func TestDetectColumnLayout_Page2EightColNoSerial(t *testing.T) {
	// chhotu's contd page-2 layout: 8 columns, no S.N. This is the case that
	// the legacy hardcoded mapping garbled — Brand reads "88" (Opening),
	// Sale reads "Rate" header text, etc.
	cells, byID := mkHeaderRow(map[int32]string{
		1: "Brand Name",
		2: "Openin",
		3: "Receipt",
		4: "Total",
		5: "Sale",
		6: "Rate",
		7: "Amount",
		8: "Closin",
	})
	rows := map[int32]map[int32]ttypes.Block{1: cells}
	got := detectColumnLayout(rows, byID)
	if !got.Detected {
		t.Fatalf("expected Detected=true on 8-col contd header")
	}
	if got.SerialNo != 0 {
		t.Errorf("SerialNo must be 0 on 8-col layout, got %d", got.SerialNo)
	}
	if got.Brand != 1 || got.Opening != 2 || got.Receipt != 3 ||
		got.Total != 4 || got.Sale != 5 || got.Rate != 6 ||
		got.Amount != 7 || got.Closing != 8 {
		t.Errorf("8-col mapping wrong: %+v", got)
	}
}

func TestDetectColumnLayout_MixedCasePunctuation(t *testing.T) {
	cells, byID := mkHeaderRow(map[int32]string{
		1: "S. N.",
		2: "Item / Product",
		3: "Op.Stock",
		4: "Recd.",
		5: "Tot.",
		6: "Sold",
		7: "M.R.P",
		8: "Amount Rs.",
		9: "Bal.",
	})
	rows := map[int32]map[int32]ttypes.Block{1: cells}
	got := detectColumnLayout(rows, byID)
	if !got.Detected {
		t.Fatalf("expected detection on punctuation-noisy headers; got %+v", got)
	}
	if got.Brand != 2 {
		t.Errorf("'Item / Product' should land on Brand col 2, got %d", got.Brand)
	}
	if got.Sale != 6 {
		t.Errorf("'Sold' should map to Sale col 6, got %d", got.Sale)
	}
	if got.Rate != 7 {
		t.Errorf("'M.R.P' should map to Rate col 7, got %d", got.Rate)
	}
	if got.Closing != 9 {
		t.Errorf("'Bal.' should map to Closing col 9, got %d", got.Closing)
	}
}

func TestDetectColumnLayout_FallbackOnGarbageHeader(t *testing.T) {
	// Row 1 is a normal data row, not a header — detection must NOT fire.
	cells, byID := mkHeaderRow(map[int32]string{
		1: "1",
		2: "Royal Stag Whisky",
		3: "44",
		4: "0",
		5: "44",
		6: "5",
		7: "250",
		8: "1250",
		9: "39",
	})
	rows := map[int32]map[int32]ttypes.Block{1: cells}
	got := detectColumnLayout(rows, byID)
	if got.Detected {
		t.Errorf("must fall back to legacy when row 1 is a data row, got Detected=true")
	}
	if got.Source != "legacy_9col" {
		t.Errorf("expected Source=legacy_9col, got %q", got.Source)
	}
	// And the legacy mapping must equal the hardcoded constants.
	if int(got.Brand) != colBrand || int(got.Sale) != colSale {
		t.Errorf("legacy mapping diverged from col* constants: %+v", got)
	}
}

func TestDetectColumnLayout_PartialHeaderFallsBack(t *testing.T) {
	// Only 3 columns recognised (below the min 4 hits) → fall back.
	cells, byID := mkHeaderRow(map[int32]string{
		1: "Brand",
		2: "Sale",
		3: "Rate",
		4: "unknown col",
		5: "another",
	})
	rows := map[int32]map[int32]ttypes.Block{1: cells}
	got := detectColumnLayout(rows, byID)
	if got.Detected {
		t.Errorf("expected fallback on <4 hits, got Detected=true (%+v)", got)
	}
}

// v1.0.319: chhotu 750ml job a095aa63 page 1 — skewed photo, Textract caught
// the 5 right-hand data columns (Opening/Receipt/Sale/Rate/Amount/Closing) on
// row 1 but the S.N + Brand cells were empty because their printed labels
// sat several pixel-rows lower. Pre-v1.0.319 the layout fell back to
// legacy_9col, hallucinated "MCD Double Original Whisky Rum"-style brand
// names by reading the data through the legacy positions, and every row
// landed on the operator as needs_review.
//
// New behaviour: when data columns are clearly labelled but Brand/Serial are
// empty in the header row, infer Brand = Opening - 1 and Serial = Brand - 1.
func TestDetectColumnLayout_InferBrandFromOpeningWhenHeaderCellEmpty(t *testing.T) {
	cells, byID := mkHeaderRow(map[int32]string{
		// Col 1 + 2 empty (S.N + Brand Name labels cropped off-frame).
		3: "Openin",
		4: "Receipt",
		5: "Total",
		6: "Sale",
		7: "Rate",
		8: "Amount",
		9: "Closin",
	})
	rows := map[int32]map[int32]ttypes.Block{1: cells}
	got := detectColumnLayout(rows, byID)
	if !got.Detected {
		t.Fatalf("expected Detected=true after Brand/Serial inference; got %+v", got)
	}
	if got.Brand != 2 {
		t.Errorf("expected Brand inferred to col 2 (Opening-1); got %d", got.Brand)
	}
	if got.SerialNo != 1 {
		t.Errorf("expected SerialNo inferred to col 1 (Brand-1); got %d", got.SerialNo)
	}
	if got.Opening != 3 || got.Sale != 6 || got.Closing != 9 {
		t.Errorf("data column mapping diverged from header text: %+v", got)
	}
}

// chhotu page 2 reality: row 1 is empty cells tagged COLUMN_HEADER; row 2
// has the actual header text "Brand Name / Openin / ..." also tagged
// COLUMN_HEADER. The detector must skip row 1 and use row 2.
func TestDetectColumnLayout_PrefersTaggedHeaderRowWithText(t *testing.T) {
	emptyR1, byID1 := mkHeaderRowTagged(map[int32]string{
		1: "", 2: "", 3: "", 4: "", 5: "", 6: "", 7: "", 8: "",
	}, ttypes.EntityTypeColumnHeader)
	realR2, byID2 := mkHeaderRowTagged(map[int32]string{
		1: "Brand Name",
		2: "Openin",
		3: "Receipt",
		4: "Total",
		5: "Sale",
		6: "Rate",
		7: "Amount",
		8: "Closin",
	}, ttypes.EntityTypeColumnHeader)
	// Merge byID maps.
	byID := map[string]ttypes.Block{}
	for k, v := range byID1 {
		byID[k] = v
	}
	for k, v := range byID2 {
		byID[k] = v
	}
	rows := map[int32]map[int32]ttypes.Block{1: emptyR1, 2: realR2}
	got := detectColumnLayout(rows, byID)
	if !got.Detected {
		t.Fatalf("expected header_detect on row-2 chhotu page-2 layout; got %+v", got)
	}
	if got.Brand != 1 || got.Opening != 2 || got.Sale != 5 || got.Closing != 8 {
		t.Errorf("page-2 mapping wrong: %+v", got)
	}
}

func TestIsHeaderRow(t *testing.T) {
	header, byID := mkHeaderRowTagged(map[int32]string{1: "Brand", 2: "Sale"}, ttypes.EntityTypeColumnHeader)
	data, _ := mkHeaderRow(map[int32]string{1: "Royal Stag", 2: "5"})
	_ = byID
	if !isHeaderRow(header) {
		t.Errorf("isHeaderRow must return true for COLUMN_HEADER row")
	}
	if isHeaderRow(data) {
		t.Errorf("isHeaderRow must return false for data row without EntityTypes")
	}
}

// mkHeaderRowTagged builds cells that carry the given EntityType (e.g.
// COLUMN_HEADER) so isHeaderRow / pickHeaderRow can find them.
func mkHeaderRowTagged(headers map[int32]string, et ttypes.EntityType) (map[int32]ttypes.Block, map[string]ttypes.Block) {
	cells := map[int32]ttypes.Block{}
	byID := map[string]ttypes.Block{}
	for colIdx, txt := range headers {
		wordID := stringPtr("word-tagged-" + textOf(colIdx) + "-" + txt)
		cellID := stringPtr("cell-tagged-" + textOf(colIdx) + "-" + txt)
		txtCopy := txt
		word := ttypes.Block{
			Id:        wordID,
			BlockType: ttypes.BlockTypeWord,
			Text:      &txtCopy,
		}
		var rels []ttypes.Relationship
		if txt != "" {
			rels = []ttypes.Relationship{
				{Type: ttypes.RelationshipTypeChild, Ids: []string{*wordID}},
			}
		}
		cell := ttypes.Block{
			Id:            cellID,
			BlockType:     ttypes.BlockTypeCell,
			Relationships: rels,
			EntityTypes:   []ttypes.EntityType{et},
		}
		byID[*wordID] = word
		byID[*cellID] = cell
		cells[colIdx] = cell
	}
	return cells, byID
}

func TestDetectColumnLayout_MissingHeaderRowFallsBack(t *testing.T) {
	got := detectColumnLayout(map[int32]map[int32]ttypes.Block{}, map[string]ttypes.Block{})
	if got.Detected {
		t.Errorf("must fall back when rowsByIdx is empty")
	}
	if got.Source != "legacy_9col" {
		t.Errorf("expected legacy_9col fallback")
	}
}

func TestStripHeaderPunct(t *testing.T) {
	// stripHeaderPunct is case-preserving; detectColumnLayout upper-cases
	// before calling it. Tests exercise both call shapes.
	cases := map[string]string{
		"S.N.":       "S N",
		"Openin/g":   "Openin g",
		" RECEIPT: ": "RECEIPT",
		"M.R.P":      "M R P",
		"Item-Name":  "Item Name",
		"OPENIN/G":   "OPENIN G",
	}
	for in, want := range cases {
		got := stripHeaderPunct(in)
		if got != want {
			t.Errorf("stripHeaderPunct(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestHeaderDetectors(t *testing.T) {
	checks := []struct {
		fn   func(string) bool
		name string
		in   string
		want bool
	}{
		{looksLikeBrandHeader, "BRAND_NAME", "BRAND NAME", true},
		{looksLikeBrandHeader, "ITEM", "ITEM", true},
		{looksLikeBrandHeader, "PRODUCT", "PRODUCT", true},
		{looksLikeBrandHeader, "RATE_NEG", "RATE", false},
		{looksLikeOpeningHeader, "OPENIN", "OPENIN", true},
		{looksLikeOpeningHeader, "OPENED_NEG", "OPENED", false},
		{looksLikeSaleHeader, "SALE", "SALE", true},
		{looksLikeSaleHeader, "SOLD", "SOLD", true},
		{looksLikeRateHeader, "MRP", "MRP", true},
		{looksLikeRateHeader, "PRICE", "PRICE", true},
		{looksLikeAmountHeader, "AMOUNT", "AMOUNT RS", true},
		{looksLikeClosingHeader, "CLOSIN", "CLOSIN", true},
		{looksLikeClosingHeader, "BAL", "BAL", true},
		{looksLikeTotalHeader, "GRAND_NEG", "GRAND TOTAL", false},
		{looksLikeTotalHeader, "TOTAL", "TOTAL", true},
		{looksLikeSerialHeader, "S_N", "S N", true},
		{looksLikeSerialHeader, "SR_NO", "SR NO", true},
		{looksLikeSerialHeader, "TOO_LONG", "SERIAL NUMBER", false},
	}
	for _, c := range checks {
		t.Run(c.name, func(t *testing.T) {
			if got := c.fn(c.in); got != c.want {
				t.Errorf("%s(%q) = %v, want %v", c.name, c.in, got, c.want)
			}
		})
	}
}
