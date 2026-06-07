package services

import (
	"strings"
	"testing"

	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
)

// mkCellWithGeom builds a synthetic Textract CELL block with the supplied
// vertical position. Width/Left are 0/1 (unused by the row-alignment
// checks) and BlockType is fixed to CELL.
func mkCellWithGeom(top, height float32) ttypes.Block {
	return ttypes.Block{
		BlockType: ttypes.BlockTypeCell,
		Geometry: &ttypes.Geometry{
			BoundingBox: &ttypes.BoundingBox{
				Top:    top,
				Left:   0.0,
				Height: height,
				Width:  1.0,
			},
		},
	}
}

// TestRowMedianGeom_Median verifies median-of-Y picks the middle value, not
// the mean. Real Textract responses for a single row carry slightly
// different Y centers per cell (printed labels vs handwritten ink); median
// is robust against one wildly-misaligned cell.
func TestRowMedianGeom_Median(t *testing.T) {
	// Top values 0.10..0.13 + outlier 0.90, Height 0.04 → Y centers 0.12,
	// 0.13, 0.14, 0.15, 0.92. Median (middle of 5) = 0.14.
	cells := map[int32]ttypes.Block{
		1: mkCellWithGeom(0.10, 0.04),
		2: mkCellWithGeom(0.11, 0.04),
		3: mkCellWithGeom(0.12, 0.04), // median Y-center = 0.14
		4: mkCellWithGeom(0.13, 0.04),
		5: mkCellWithGeom(0.90, 0.04), // outlier — would skew the mean to ~0.27
	}
	y, h, ok := rowMedianGeom(cells)
	if !ok {
		t.Fatal("expected hasGeom=true on 5 cells with geometry")
	}
	if y < 0.135 || y > 0.145 {
		t.Errorf("median Y = %.3f, expected ~0.14", y)
	}
	if h < 0.039 || h > 0.041 {
		t.Errorf("median H = %.3f, expected ~0.04", h)
	}
}

// TestRowMedianGeom_NoGeometry returns hasGeom=false when no cells carry
// geometry (older Textract responses, synthetic test cells without a
// BoundingBox). Caller must skip the outlier check in this case.
func TestRowMedianGeom_NoGeometry(t *testing.T) {
	cells := map[int32]ttypes.Block{
		1: {BlockType: ttypes.BlockTypeCell},
		2: {BlockType: ttypes.BlockTypeCell},
	}
	_, _, ok := rowMedianGeom(cells)
	if ok {
		t.Fatal("expected hasGeom=false when no cells have BoundingBox")
	}
}

// TestBrandCellYOutlier_FMTowerRowSwap reproduces the May 26 FM Tower bug:
// Textract bound row 4's brand cell (Y center ~0.30) into the row 1 bucket
// (row median Y ~0.10). A row height of ~0.04 means the cell is 5x its
// own height away from the row — well above the 0.6x threshold.
func TestBrandCellYOutlier_FMTowerRowSwap(t *testing.T) {
	rowMedianY := float32(0.10)
	rowMedianH := float32(0.04)
	// Brand cell came from row 4 (Y center ~0.30) but got binned into row 1
	misboundBrand := mkCellWithGeom(0.28, 0.04) // Y center = 0.30
	w := brandCellYOutlierWarning(misboundBrand, rowMedianY, rowMedianH)
	if w == "" {
		t.Fatal("expected outlier warning for brand cell 5x row-height away")
	}
	if !strings.HasPrefix(w, "textract_cell_y_outlier:brand") {
		t.Errorf("unexpected warning format: %q", w)
	}
}

// TestSaleCellYOutlier_DriftedQuantity (v1.0.341) — the Malsaii scramble root
// cause: the brand cell sits on its true row but the handwritten SALE digit was
// binned one row down, so its Y-center is a full row-height away from the row
// median. The new "sale" outlier check must flag it (this is what forces the
// row to review instead of pairing the wrong quantity with the right brand).
func TestSaleCellYOutlier_DriftedQuantity(t *testing.T) {
	rowMedianY := float32(0.10)
	rowMedianH := float32(0.04)
	driftedSale := mkCellWithGeom(0.16, 0.04) // Y center 0.18, ~2 rows away
	w := cellYOutlierWarning(driftedSale, rowMedianY, rowMedianH, "sale")
	if w == "" {
		t.Fatal("expected outlier warning for a drifted sale cell")
	}
	if !strings.HasPrefix(w, "textract_cell_y_outlier:sale") {
		t.Errorf("unexpected warning format: %q", w)
	}
	// A sale cell sitting on its own row must NOT warn.
	healthySale := mkCellWithGeom(0.098, 0.04) // Y center 0.118, delta 0.018 < 0.024
	if w := cellYOutlierWarning(healthySale, rowMedianY, rowMedianH, "sale"); w != "" {
		t.Errorf("did not expect warning on a healthy sale cell, got %q", w)
	}
}

// TestBrandCellYOutlier_HealthyRow no warning when the brand cell sits
// within the normal row band. Tolerance is 0.6 * medianH, so a 0.5 *
// medianH offset must pass.
func TestBrandCellYOutlier_HealthyRow(t *testing.T) {
	rowMedianY := float32(0.20)
	rowMedianH := float32(0.04)
	brand := mkCellWithGeom(0.198, 0.04) // Y center 0.218, delta = 0.018 < 0.024
	if w := brandCellYOutlierWarning(brand, rowMedianY, rowMedianH); w != "" {
		t.Errorf("did not expect warning on healthy row, got %q", w)
	}
}

// TestBrandCellYOutlier_NoGeometry silently passes (returns empty) when
// geometry is missing. Tests/old responses must not trip the guard.
func TestBrandCellYOutlier_NoGeometry(t *testing.T) {
	brand := ttypes.Block{BlockType: ttypes.BlockTypeCell}
	if w := brandCellYOutlierWarning(brand, 0.10, 0.04); w != "" {
		t.Errorf("expected empty warning when brand cell lacks geometry, got %q", w)
	}
	// Also: if the row itself had no geometry (medianH==0), no warning.
	brand2 := mkCellWithGeom(0.30, 0.04)
	if w := brandCellYOutlierWarning(brand2, 0, 0); w != "" {
		t.Errorf("expected empty warning when row medianH=0, got %q", w)
	}
}

// TestFlagRowOrderInversions_FMTowerSwap reproduces the May 26 case at the
// item-list level: two items emitted with Textract row indices 2 and 5,
// but parsed serial numbers 4 and 1 respectively (Textract bound row 1's
// data to row index 5 and vice versa, so the serial values landed inverted
// to the row-index order).
//
// NOTE: in the actual incident the serials happened to read correctly
// (1 and 4 in row-index order), so this exact inversion check wouldn't
// have caught THAT specific case. The check exists for the broader class
// of slips where the serial column AND data both shift together — common
// in tilted-photo registers chhotu's Mahua Khera shop ships.
func TestFlagRowOrderInversions_DetectsDecreasingSerials(t *testing.T) {
	out := []ExtractedReceiptItem{
		{Brand: "First item", RowNumber: 2},
		{Brand: "Second item", RowNumber: 3},
		{Brand: "Third item", RowNumber: 5},
	}
	// Textract row index → printed serial value.
	// Row 5's serial = 1 (inversion against rows 2 and 3 which say 4 and 5).
	serials := map[int32]int{
		2: 4,
		3: 5,
		5: 1,
	}
	flagRowOrderInversions(out, serials)
	if len(out[1].Warnings) == 0 || len(out[2].Warnings) == 0 {
		t.Fatalf("expected inversion warnings on items 1 and 2; got %+v", out)
	}
	for _, w := range out[1].Warnings {
		if !strings.HasPrefix(w, "textract_row_order_inversion") {
			continue
		}
		if !strings.Contains(w, "5_before_1") {
			t.Errorf("expected warning to name the offending pair, got %q", w)
		}
	}
}

// TestFlagRowOrderInversions_MonotonicNoWarning happy path — serials 1,2,3
// in row-index order produce zero warnings.
func TestFlagRowOrderInversions_MonotonicNoWarning(t *testing.T) {
	out := []ExtractedReceiptItem{
		{Brand: "a", RowNumber: 2},
		{Brand: "b", RowNumber: 3},
		{Brand: "c", RowNumber: 4},
	}
	flagRowOrderInversions(out, map[int32]int{2: 1, 3: 2, 4: 3})
	for i, it := range out {
		for _, w := range it.Warnings {
			if strings.HasPrefix(w, "textract_row_order_inversion") {
				t.Errorf("item %d: unexpected inversion warning %q", i, w)
			}
		}
	}
}

// TestFlagRowOrderInversions_BlankSerialsSkipped — a row whose serial cell
// was blank (serial=0, not in map) must not break the monotonicity check
// for the rows surrounding it. Tested by inserting an item with no serial
// between two valid ones.
func TestFlagRowOrderInversions_BlankSerialsSkipped(t *testing.T) {
	out := []ExtractedReceiptItem{
		{Brand: "a", RowNumber: 2},
		{Brand: "b", RowNumber: 3}, // serial unparsable
		{Brand: "c", RowNumber: 4},
	}
	flagRowOrderInversions(out, map[int32]int{2: 1, 4: 2})
	for i, it := range out {
		for _, w := range it.Warnings {
			if strings.HasPrefix(w, "textract_row_order_inversion") {
				t.Errorf("item %d: unexpected inversion warning %q", i, w)
			}
		}
	}
}
