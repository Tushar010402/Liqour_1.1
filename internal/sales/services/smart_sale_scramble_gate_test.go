package services

import (
	"testing"

	"github.com/sirupsen/logrus"
)

// TestScrambleGate_ForcesReviewOnStructuralWarnings locks in the v1.0.340 Bug-1
// fix: a row that the OCR pipeline flagged as structurally suspect (Textract
// returned rows out of order, or bound a brand cell ~a full row out of place)
// must be forced to NeedsReview even when its brand→product match confidence is
// high. This is the guard that would have stopped Malsaii d6f860d1 from
// silently saving a quantity rotation. Borderline brand-cell jitter (the 60-75%
// delta seen on most handwritten rows) must NOT be gated, to avoid red-flagging
// every line (the v1.0.319 UX regression).
func TestScrambleGate_ForcesReviewOnStructuralWarnings(t *testing.T) {
	pid := "11111111-1111-1111-1111-111111111111"
	svc := &SmartSaleService{logger: logrus.New()}

	mk := func(warnings []string) SmartSaleExtractedItem {
		return SmartSaleExtractedItem{
			ProductID:       &pid,
			MatchConfidence: 0.99, // high — would otherwise auto-accept
			NeedsReview:     false,
			Warnings:        warnings,
		}
	}

	cases := []struct {
		name       string
		warnings   []string
		wantReview bool
	}{
		{"row_order_inversion forces review", []string{"textract_row_order_inversion:serials=7_before_3"}, true},
		{"severe brand y-outlier forces review", []string{"textract_cell_y_outlier:brand:delta_pct=120"}, true},
		{"borderline brand y-outlier stays clean", []string{"textract_cell_y_outlier:brand:delta_pct=70"}, false},
		// v1.0.341 — drifted sale/quantity cell (the direct scramble cause)
		{"severe sale y-outlier forces review", []string{"textract_cell_y_outlier:sale:delta_pct=95"}, true},
		{"sale y-outlier at threshold forces review", []string{"textract_cell_y_outlier:sale:delta_pct=90"}, true},
		{"borderline sale y-outlier stays clean", []string{"textract_cell_y_outlier:sale:delta_pct=75"}, false},
		{"page_incomplete alone stays clean (handled elsewhere)", []string{"page_incomplete:1:missing:2"}, false},
		{"no warnings stays clean", nil, false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			items := []SmartSaleExtractedItem{mk(c.warnings)}
			svc.validatePageCompleteness(items, nil)
			if items[0].NeedsReview != c.wantReview {
				t.Fatalf("NeedsReview=%v, want %v (warnings=%v reason=%q)",
					items[0].NeedsReview, c.wantReview, c.warnings, items[0].ReviewReason)
			}
			if c.wantReview && items[0].ReviewReason == "" {
				t.Fatalf("expected a ReviewReason to be set when forcing review")
			}
		})
	}
}

// TestScrambleGate_KillSwitch verifies SMART_SALE_SCRAMBLE_GATE=0 disables the
// gate so a high-confidence inverted row is left untouched (escape hatch).
func TestScrambleGate_KillSwitch(t *testing.T) {
	t.Setenv("SMART_SALE_SCRAMBLE_GATE", "0")
	pid := "11111111-1111-1111-1111-111111111111"
	svc := &SmartSaleService{logger: logrus.New()}
	items := []SmartSaleExtractedItem{{
		ProductID:       &pid,
		MatchConfidence: 0.99,
		NeedsReview:     false,
		Warnings:        []string{"textract_row_order_inversion:serials=7_before_3"},
	}}
	svc.validatePageCompleteness(items, nil)
	if items[0].NeedsReview {
		t.Fatalf("kill-switch off should leave NeedsReview=false, got true")
	}
}
