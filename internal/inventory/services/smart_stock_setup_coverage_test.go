package services

import (
	"testing"
)

// row builds a scan item as it appears in smart_stock_setup_jobs.result["items"]
// (JSONB → map[string]interface{}, numbers as float64).
func row(brand string, opening, sizeML, rowNum int) interface{} {
	return map[string]interface{}{
		"brand_name": brand,
		"opening":    float64(opening),
		"size_ml":    float64(sizeML),
		"row_number": float64(rowNum),
		"size":       "375ml",
	}
}

func submittedItem(brand string) SmartStockSetupApplyItem {
	return SmartStockSetupApplyItem{BrandName: brand, Size: "375ml (Half)"}
}

// The Malsaii incident: the 375 scan had both "8 PM Special Rare" (98) and
// "8 PM Premium Black Superior" (2); only Special Rare was submitted. The Black
// row must be reported as coverage-missing — never silently lost.
func TestCoverage_FlagsQuietlyOmittedRow(t *testing.T) {
	jobItems := []interface{}{
		row("8 PM Special Rare Whisky", 98, 375, 1),
		row("8 PM Premium Black Superior", 2, 375, 7),
	}
	req := SmartStockSetupApplyRequest{
		Size:  "375ml (Half)",
		Items: []SmartStockSetupApplyItem{submittedItem("8 PM Special Rare Whisky")},
	}
	got := coverageMissingItems(jobItems, req)
	if len(got) != 1 {
		t.Fatalf("expected 1 missing item, got %d: %+v", len(got), got)
	}
	if got[0].BrandName != "8 PM Premium Black Superior" {
		t.Fatalf("expected the Black row flagged, got %q", got[0].BrandName)
	}
	if got[0].Reason != "extracted_but_not_submitted" {
		t.Fatalf("unexpected reason %q", got[0].Reason)
	}
}

func TestCoverage_AllSubmitted_NoFalsePositive(t *testing.T) {
	jobItems := []interface{}{
		row("8 PM Special Rare Whisky", 98, 375, 1),
		row("8 PM Premium Black Superior", 2, 375, 7),
	}
	req := SmartStockSetupApplyRequest{
		Size: "375ml (Half)",
		Items: []SmartStockSetupApplyItem{
			submittedItem("8 PM Special Rare Whisky"),
			submittedItem("8 PM Premium Black Superior"),
		},
	}
	if got := coverageMissingItems(jobItems, req); len(got) != 0 {
		t.Fatalf("expected no missing items, got %d: %+v", len(got), got)
	}
}

// Rows of a different size than the one being applied must not be flagged
// (apply is per-size; the 180 scan is a separate submission).
func TestCoverage_DifferentSize_NotFlagged(t *testing.T) {
	jobItems := []interface{}{
		row("Royal Stag Barrel Select", 5, 180, 19), // 180, while applying 375
	}
	req := SmartStockSetupApplyRequest{
		Size:  "375ml (Half)",
		Items: []SmartStockSetupApplyItem{submittedItem("8 PM Special Rare Whisky")},
	}
	if got := coverageMissingItems(jobItems, req); len(got) != 0 {
		t.Fatalf("expected no missing items for off-size rows, got %+v", got)
	}
}

// opening==0 rows are intentionally skipped at apply, so they are not coverage
// gaps either.
func TestCoverage_ZeroOpening_NotFlagged(t *testing.T) {
	jobItems := []interface{}{row("Absolut Vodka", 0, 375, 3)}
	req := SmartStockSetupApplyRequest{
		Size:  "375ml (Half)",
		Items: []SmartStockSetupApplyItem{submittedItem("Something Else")},
	}
	if got := coverageMissingItems(jobItems, req); len(got) != 0 {
		t.Fatalf("expected no missing items for zero-opening rows, got %+v", got)
	}
}

// An operator-edited name still counts the row as submitted (no false positive).
func TestCoverage_EditedNameCountsAsSubmitted(t *testing.T) {
	jobItems := []interface{}{row("8 PM Premium Black Superior", 2, 375, 7)}
	req := SmartStockSetupApplyRequest{
		Size: "375ml (Half)",
		Items: []SmartStockSetupApplyItem{
			{BrandName: "scan-garbled-name", EditedName: "8 PM Premium Black Superior", Size: "375ml (Half)"},
		},
	}
	if got := coverageMissingItems(jobItems, req); len(got) != 0 {
		t.Fatalf("edited name should count as submitted, got %+v", got)
	}
}
