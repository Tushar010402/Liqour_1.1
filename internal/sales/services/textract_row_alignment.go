package services

import (
	"fmt"
	"sort"

	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
)

// v1.0.241 — row-alignment cross-checks for Textract Tables output.
//
// CONTEXT: chhotu's FM Tower 180 ML sheet (2026-05-26 16:16) returned the
// brand cell for printed S.N=1 with all of printed-row-4's numeric data
// (opening=26, closing=26, rate=140 — none of row 1's actual handwritten
// values). Textract's per-cell row binning had silently put row 4's cells
// into the row-index-2 bucket and vice versa, so the row loop emitted a
// "8 PM Gold Scotch Whisky PET" entry where "8 PM Gold Scotch Whisky Tetra"
// should have been. The downstream alias cascade then pinned PET → a Tetra
// product duplicate (separate bug, fixed in smart_sale_service.go).
//
// Two independent signals catch this class of slip:
//   1. Serial-monotonicity: the printed S.N column on this tenant's
//      registers is always 1,2,3,... in row order. If Textract's row
//      ordering disagrees with the parsed serial sequence, something has
//      shifted.
//   2. Cell-geometry: each Textract CELL block carries a BoundingBox. If a
//      cell's vertical center is far from the median of the row Textract
//      bound it to, that cell was probably grouped into the wrong row.
//
// Both signals only add Warnings to affected rows — they never auto-rebin
// or drop data. The preview UI surfaces the warnings as amber chips so the
// operator can re-confirm before save.

// cellYCenter returns the vertical center of a Textract cell's bounding box
// in normalised page coordinates (0=top, 1=bottom), or -1 when geometry is
// missing (older Textract responses, synthetic test fixtures).
func cellYCenter(cell ttypes.Block) float32 {
	if cell.Geometry == nil || cell.Geometry.BoundingBox == nil {
		return -1
	}
	bb := cell.Geometry.BoundingBox
	// AWS Textract SDK exposes Top / Height as plain float32 (not pointers),
	// so a missing geometry is detected via the BoundingBox==nil check above.
	return bb.Top + (bb.Height / 2.0)
}

// cellHeight returns the bounding-box height of a Textract cell in
// normalised page coordinates, or -1 when geometry is missing.
func cellHeight(cell ttypes.Block) float32 {
	if cell.Geometry == nil || cell.Geometry.BoundingBox == nil {
		return -1
	}
	return cell.Geometry.BoundingBox.Height
}

// rowMedianGeom returns (medianYCenter, medianHeight, hasGeom) computed
// from all cells in the row. Median (not mean) so a single outlier cell
// can't drag the reference value. hasGeom=false → no cell carried
// geometry; caller should skip the outlier check for this row.
func rowMedianGeom(cells map[int32]ttypes.Block) (float32, float32, bool) {
	ys := make([]float32, 0, len(cells))
	hs := make([]float32, 0, len(cells))
	for _, cell := range cells {
		if y := cellYCenter(cell); y >= 0 {
			ys = append(ys, y)
		}
		if h := cellHeight(cell); h > 0 {
			hs = append(hs, h)
		}
	}
	if len(ys) == 0 || len(hs) == 0 {
		return 0, 0, false
	}
	return medianFloat32(ys), medianFloat32(hs), true
}

func medianFloat32(xs []float32) float32 {
	cp := make([]float32, len(xs))
	copy(cp, xs)
	sort.Slice(cp, func(i, j int) bool { return cp[i] < cp[j] })
	n := len(cp)
	if n%2 == 1 {
		return cp[n/2]
	}
	return (cp[n/2-1] + cp[n/2]) / 2.0
}

// brandCellYOutlierWarning returns a non-empty warning string when the brand
// cell's Y-center is implausibly far from the rest of its row. Returns ""
// for the happy path so callers can `if w := ...; w != "" { ... }`.
//
// Threshold: |delta| > 0.6 * medianH. Tighter would false-fire on legitimate
// row height variation (handwritten cells often span 1.1-1.3x the printed
// header height); looser would miss the FM Tower case where the misbound
// cell was almost an entire row's worth out of position.
func brandCellYOutlierWarning(brandCell ttypes.Block, medianY, medianH float32) string {
	return cellYOutlierWarning(brandCell, medianY, medianH, "brand")
}

// cellYOutlierWarning is the generic form behind brandCellYOutlierWarning,
// usable for any column. `label` names the offending column in the emitted
// warning ("brand", "sale", ...).
//
// v1.0.341 — added the "sale" caller. ROOT CAUSE of the Malsaii quantity
// scramble (d6f860d1 / 39ef4998 etc.): Textract bins each CELL to a row by its
// own per-cell RowIndex. On a skewed photo of a handwritten register the crisp
// printed BRAND cell stays on its true row, but the handwritten SALE digit
// drifts into the adjacent row's bucket — so a brand gets paired with its
// neighbour's quantity (brand right, number wrong). The pre-existing check only
// watched the brand cell, so a drifted *number* cell went undetected. Watching
// the Sale cell's Y against the row median catches exactly that drift: a number
// that geometrically belongs to another line is forced to review instead of
// auto-saving onto the wrong brand.
func cellYOutlierWarning(cell ttypes.Block, medianY, medianH float32, label string) string {
	if medianH <= 0 {
		return ""
	}
	by := cellYCenter(cell)
	if by < 0 {
		return ""
	}
	delta := by - medianY
	if delta < 0 {
		delta = -delta
	}
	if delta <= medianH*0.6 {
		return ""
	}
	return fmt.Sprintf("textract_cell_y_outlier:%s:delta_pct=%.0f", label, delta/medianH*100)
}

// flagRowOrderInversions walks `out` (already in Textract row-index order)
// and adds a `textract_row_order_inversion` warning to every consecutive
// pair whose parsed S.N values are decreasing. `serialByRowIdx` is keyed by
// Textract row index; rows with serial<=0 (unparsable or empty cell) are
// skipped from the comparison so a single blank S.N cell mid-page doesn't
// generate spurious warnings.
//
// Modifies `out` in place — appends to each affected item's Warnings.
func flagRowOrderInversions(out []ExtractedReceiptItem, serialByRowIdx map[int32]int) {
	// Build (out-index, serial) pairs in the order items appear in out.
	type pair struct {
		outIdx int
		serial int
	}
	pairs := make([]pair, 0, len(out))
	for i := range out {
		s, ok := serialByRowIdx[int32(out[i].RowNumber)]
		if !ok || s <= 0 {
			continue
		}
		pairs = append(pairs, pair{outIdx: i, serial: s})
	}
	for i := 1; i < len(pairs); i++ {
		prev := pairs[i-1]
		curr := pairs[i]
		if curr.serial < prev.serial {
			warn := fmt.Sprintf("textract_row_order_inversion:serials=%d_before_%d", prev.serial, curr.serial)
			out[prev.outIdx].Warnings = append(out[prev.outIdx].Warnings, warn)
			out[curr.outIdx].Warnings = append(out[curr.outIdx].Warnings, warn)
		}
	}
}
