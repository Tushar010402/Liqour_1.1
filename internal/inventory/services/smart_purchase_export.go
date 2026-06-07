package services

// v1.0.238 Track E — AI Purchase Excel "photocopy" export.
//
// Builds a single .xlsx workbook with one sheet per GP page (12-column GP
// layout: S.No / Brand / Liquor Type / Liquor Sub Type / Description / Size /
// Pkg Type / Cases Req / Bottles Req / Cases Disp / Bottles Disp / Duty Fee),
// plus a Summary sheet with vendor / invoice / reconciliation status.
//
// Reads from the persisted SmartPurchaseJob.Result JSON — no OCR re-run, no
// network call. Cheap, deterministic, exportable at any time after a job
// completes.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/xuri/excelize/v2"
)

// gpExportColumns is the canonical 12-column layout of the UP Excise GP form.
// We render every row with this exact column set so the operator sees a
// photocopy that lines up with the printed source.
var gpExportColumns = []string{
	"S.No",
	"Brand",
	"Liquor Type",
	"Liquor Sub Type",
	"Description",
	"Packaging Size",
	"Packaging Type",
	"Cases Req",
	"Bottles Req",
	"Cases Disp",
	"Bottles Disp",
	"Duty Fee",
}

// BuildGatePassPhotocopyXLSX renders a SmartPurchaseResult into an .xlsx blob.
// Output layout:
//   - "Summary"          sheet 0: vendor / invoice / totals / reconciliation
//   - "GP Page 1..N"     one sheet per GP page, 12 canonical columns
//
// Idempotent — same Result in, same bytes out (modulo excelize's internal
// timestamps). Callers stream the returned []byte to the HTTP response with
// Content-Type application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.
func BuildGatePassPhotocopyXLSX(result map[string]interface{}) ([]byte, error) {
	f := excelize.NewFile()
	defer func() { _ = f.Close() }()

	// excelize starts with a "Sheet1" — rename to Summary.
	if err := f.SetSheetName("Sheet1", "Summary"); err != nil {
		return nil, fmt.Errorf("rename Sheet1: %w", err)
	}

	// === Summary sheet ===
	summaryRows := buildSummaryRows(result)
	for i, row := range summaryRows {
		cell := fmt.Sprintf("A%d", i+1)
		if err := f.SetSheetRow("Summary", cell, &row); err != nil {
			return nil, fmt.Errorf("summary row %d: %w", i+1, err)
		}
	}
	// Widen the Summary columns for readability.
	_ = f.SetColWidth("Summary", "A", "A", 28)
	_ = f.SetColWidth("Summary", "B", "B", 64)

	// === Group duty items by page ===
	dutyItems := extractDutyItems(result)
	byPage := map[int][]map[string]interface{}{}
	maxPage := 0
	for _, it := range dutyItems {
		p := intFromAny(it["page_index"])
		if p <= 0 {
			p = 1
		}
		byPage[p] = append(byPage[p], it)
		if p > maxPage {
			maxPage = p
		}
	}

	// Render each GP page sheet — even when 0 rows (so the operator sees the
	// page was processed but came back empty, instead of a missing sheet).
	totalPagesExpected := maxPage
	if totalPagesExpected == 0 {
		totalPagesExpected = 1
	}
	for p := 1; p <= totalPagesExpected; p++ {
		sheetName := fmt.Sprintf("GP Page %d", p)
		if _, err := f.NewSheet(sheetName); err != nil {
			return nil, fmt.Errorf("new sheet %s: %w", sheetName, err)
		}

		// Header
		header := make([]interface{}, len(gpExportColumns))
		for i, c := range gpExportColumns {
			header[i] = c
		}
		if err := f.SetSheetRow(sheetName, "A1", &header); err != nil {
			return nil, fmt.Errorf("header %s: %w", sheetName, err)
		}

		// Rows, sorted by S.No ascending so the photocopy matches the GP.
		rows := byPage[p]
		sort.SliceStable(rows, func(i, j int) bool {
			return intFromAny(rows[i]["row_number"]) < intFromAny(rows[j]["row_number"])
		})
		for i, r := range rows {
			rowVals := []interface{}{
				intFromAny(r["row_number"]),
				stringFromAny(r["brand_name"]),
				stringFromAny(r["liquor_type"]),
				stringFromAny(r["liquor_sub_type"]),
				"", // Description (Textract gives us a single brand cell; we leave
				    //              blank to keep the column layout intact)
				stringFromAny(r["size"]),
				stringFromAny(r["packaging_type"]),
				"", // Cases Req — not modeled on GatePassDutyItem (only Cases =
				    //             Cases Dispatched is captured). Left blank.
				"", // Bottles Req — not modeled (only Bottles = Dispatched).
				intFromAny(r["cases"]),
				intFromAny(r["bottles"]),
				floatFromAny(r["duty_fee"]),
			}
			cell := fmt.Sprintf("A%d", i+2)
			if err := f.SetSheetRow(sheetName, cell, &rowVals); err != nil {
				return nil, fmt.Errorf("row %d on %s: %w", i+2, sheetName, err)
			}
		}

		// Column widths — generous on Brand and Description, tight on numerics.
		_ = f.SetColWidth(sheetName, "A", "A", 6)
		_ = f.SetColWidth(sheetName, "B", "B", 48)
		_ = f.SetColWidth(sheetName, "C", "D", 14)
		_ = f.SetColWidth(sheetName, "E", "E", 32)
		_ = f.SetColWidth(sheetName, "F", "G", 14)
		_ = f.SetColWidth(sheetName, "H", "K", 11)
		_ = f.SetColWidth(sheetName, "L", "L", 12)
	}

	// Make Summary the active tab on open.
	if idx, err := f.GetSheetIndex("Summary"); err == nil {
		f.SetActiveSheet(idx)
	}

	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil {
		return nil, fmt.Errorf("write xlsx: %w", err)
	}
	return buf.Bytes(), nil
}

// buildSummaryRows is one [label, value] pair per row of the Summary sheet.
func buildSummaryRows(result map[string]interface{}) [][]interface{} {
	out := [][]interface{}{
		{"AI Purchase — GP Photocopy", ""},
		{"", ""},
		{"Vendor (from bill)", deepString(result, "detected_vendor", "name")},
		{"Vendor GST", deepString(result, "detected_vendor", "gst_number")},
		{"Invoice Number", stringFromAny(result["invoice_number"])},
		{"Invoice Date", stringFromAny(result["invoice_date"])},
		{"", ""},
		{"Bill Subtotal", floatFromAny(result["sub_total"])},
		{"Bill Total", floatFromAny(result["total_amount"])},
		{"GP Duty Total", deepFloat(result, "reconciliation", "gp_duty_total")},
		{"", ""},
		{"Vendor Matches", deepBoolStr(result, "reconciliation", "vendor_matches")},
		{"Rows on Both Documents", deepInt(result, "reconciliation", "rows_both")},
		{"Rows on Bill Only", deepInt(result, "reconciliation", "rows_bill_only")},
		{"Rows on GP Only", deepInt(result, "reconciliation", "rows_gp_only")},
	}
	// Append warnings.
	if w, ok := result["reconciliation"].(map[string]interface{}); ok {
		if ws, ok := w["warnings"].([]interface{}); ok && len(ws) > 0 {
			out = append(out, []interface{}{"", ""})
			out = append(out, []interface{}{"Warnings", strings.Join(stringifyAll(ws), "; ")})
		}
	}
	return out
}

// extractDutyItems unmarshals result["duty_items"] (whatever shape JSON
// round-tripped it into) into a slice of map[string]interface{} for uniform
// access. Handles both []interface{} (raw JSON) and []map[string]interface{}
// (already-typed).
func extractDutyItems(result map[string]interface{}) []map[string]interface{} {
	raw, ok := result["duty_items"]
	if !ok || raw == nil {
		return nil
	}
	// Round-trip through JSON to canonicalise.
	bs, err := json.Marshal(raw)
	if err != nil {
		return nil
	}
	var out []map[string]interface{}
	_ = json.Unmarshal(bs, &out)
	return out
}

// --- type-coercion helpers — JSON round-tripping makes everything float64
// for numbers and string for strings; these tighten them back. ---

func stringFromAny(v interface{}) string {
	if v == nil {
		return ""
	}
	switch x := v.(type) {
	case string:
		return x
	case float64:
		return fmt.Sprintf("%v", x)
	case int:
		return fmt.Sprintf("%d", x)
	case bool:
		if x {
			return "true"
		}
		return "false"
	}
	return fmt.Sprintf("%v", v)
}

func intFromAny(v interface{}) int {
	if v == nil {
		return 0
	}
	switch x := v.(type) {
	case int:
		return x
	case float64:
		return int(x)
	case string:
		// Drop non-numeric tails — Textract sometimes returns "750ml" here.
		var out int
		for _, r := range x {
			if r >= '0' && r <= '9' {
				out = out*10 + int(r-'0')
			} else if out > 0 {
				break
			}
		}
		return out
	}
	return 0
}

func floatFromAny(v interface{}) float64 {
	if v == nil {
		return 0
	}
	switch x := v.(type) {
	case float64:
		return x
	case int:
		return float64(x)
	case string:
		var out float64
		seenDot := false
		var div float64 = 1
		for _, r := range x {
			if r >= '0' && r <= '9' {
				out = out*10 + float64(r-'0')
				if seenDot {
					div *= 10
				}
			} else if r == '.' && !seenDot {
				seenDot = true
			} else if out > 0 {
				break
			}
		}
		return out / div
	}
	return 0
}

func deepString(m map[string]interface{}, path ...string) string {
	cur := interface{}(m)
	for _, k := range path {
		mm, ok := cur.(map[string]interface{})
		if !ok {
			return ""
		}
		cur = mm[k]
	}
	return stringFromAny(cur)
}

func deepFloat(m map[string]interface{}, path ...string) float64 {
	cur := interface{}(m)
	for _, k := range path {
		mm, ok := cur.(map[string]interface{})
		if !ok {
			return 0
		}
		cur = mm[k]
	}
	return floatFromAny(cur)
}

func deepInt(m map[string]interface{}, path ...string) int {
	cur := interface{}(m)
	for _, k := range path {
		mm, ok := cur.(map[string]interface{})
		if !ok {
			return 0
		}
		cur = mm[k]
	}
	return intFromAny(cur)
}

func deepBoolStr(m map[string]interface{}, path ...string) string {
	cur := interface{}(m)
	for _, k := range path {
		mm, ok := cur.(map[string]interface{})
		if !ok {
			return ""
		}
		cur = mm[k]
	}
	if b, ok := cur.(bool); ok {
		if b {
			return "yes"
		}
		return "no"
	}
	return ""
}

func stringifyAll(xs []interface{}) []string {
	out := make([]string, 0, len(xs))
	for _, x := range xs {
		out = append(out, stringFromAny(x))
	}
	return out
}
