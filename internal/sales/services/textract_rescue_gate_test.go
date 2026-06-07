package services

import "testing"

// v1.0.316 — detectCollapsedPages must trust pages where LayoutDetected=true
// AND SuspiciousBrandCount is low, even if RawRowCount is below the soft
// (50%) threshold. The chhotu page-2 contd case: 13 rows vs 30 on page 1
// — used to trigger rescue (median 30, soft 15, page 2 < 15 → collapsed).
// Now the layout-detection signal says "page is honest, just smaller".
func TestDetectCollapsedPages_TrustsLayoutDetected(t *testing.T) {
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true},
		{PageNumber: 2, RawRowCount: 13, SuspiciousBrandCount: 0, LayoutDetected: true},
	}
	got := detectCollapsedPages(stats)
	if len(got) != 0 {
		t.Errorf("expected no collapsed pages when both have LayoutDetected=true; got %v", got)
	}
}

func TestDetectCollapsedPages_LayoutDetectedButHardThresholdStillFires(t *testing.T) {
	// Page 2 returned only 5 rows out of median 30 — hard threshold (30% = 9)
	// must still fire even when layout is detected. Indicates true collapse,
	// not just a small page.
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true},
		{PageNumber: 2, RawRowCount: 5, SuspiciousBrandCount: 0, LayoutDetected: true},
	}
	got := detectCollapsedPages(stats)
	found := false
	for _, p := range got {
		if p == 2 {
			found = true
		}
	}
	if !found {
		t.Errorf("expected page 2 collapsed via hard threshold even with LayoutDetected; got %v", got)
	}
}

func TestDetectCollapsedPages_LegacyPathStillTriggers(t *testing.T) {
	// LayoutDetected=false → behaviour matches pre-v1.0.316: 13 rows vs
	// median 30 + suspicious brand triggers soft threshold.
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: false},
		{PageNumber: 2, RawRowCount: 13, SuspiciousBrandCount: 2, LayoutDetected: false},
	}
	got := detectCollapsedPages(stats)
	found := false
	for _, p := range got {
		if p == 2 {
			found = true
		}
	}
	if !found {
		t.Errorf("legacy soft-threshold path broken; expected page 2 collapsed, got %v", got)
	}
}

func TestDetectCollapsedPages_LayoutDetectedHighSuspicionRescues(t *testing.T) {
	// LayoutDetected=true but SuspiciousBrandCount=3 — still rescue. A
	// detected layout with multiple suspicious brand cells suggests the
	// header was misread.
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true},
		{PageNumber: 2, RawRowCount: 12, SuspiciousBrandCount: 3, LayoutDetected: true},
	}
	got := detectCollapsedPages(stats)
	found := false
	for _, p := range got {
		if p == 2 {
			found = true
		}
	}
	if !found {
		t.Errorf("high-suspicion page should still rescue even with LayoutDetected; got %v", got)
	}
}

// v1.0.320 — legacy_9col fallback (LayoutDetected=false) with ≥2 suspicious
// brand cells must trigger rescue even when RawRowCount is healthy. Chhotu's
// 750ml job a095aa63 page 1 (2026-05-24): 30 rows extracted (median-healthy),
// but Textract's header_detect failed so the row-cell alignment was wrong —
// 2 empty brand cells + concatenated multi-brand text on adjacent rows.
// Without this trigger the row-count gate skipped the rescue and the operator
// saw garbled brand text on the review screen.
func TestDetectCollapsedPages_LegacyHighSuspicionRescuesEvenWithFullRowCount(t *testing.T) {
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 2, LayoutDetected: false},
		{PageNumber: 2, RawRowCount: 20, SuspiciousBrandCount: 0, LayoutDetected: true},
	}
	got := detectCollapsedPages(stats)
	found := false
	for _, p := range got {
		if p == 1 {
			found = true
		}
	}
	if !found {
		t.Errorf("legacy_9col + suspicion should rescue full-count page; got %v", got)
	}
}

// v1.0.320 — legacy_9col on a sparse but clean page should NOT trigger
// rescue (only one suspicious brand). Avoids burning rescue budget on
// honest small contd pages where the header just happened to be cropped.
func TestDetectCollapsedPages_LegacyOneSuspicionDoesNotRescue(t *testing.T) {
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true},
		{PageNumber: 2, RawRowCount: 25, SuspiciousBrandCount: 1, LayoutDetected: false},
	}
	got := detectCollapsedPages(stats)
	for _, p := range got {
		if p == 2 {
			t.Errorf("single suspicious brand on legacy page should NOT rescue; got %v", got)
		}
	}
}

// v1.0.325 — blank-sale-with-rate trigger: ≥3 rows with qty=0 but rate>0
// AND ratio ≥30% of post-filter rows → trigger Phase B Claude rescue.
// The forensic finding (2026-05-25) showed 103/103 AI-wrong training samples
// had Textract returning qty=0 (not digit confusion). Math-gate caught some
// but not all (needs open+close populated). Phase B full-page Claude has
// page context and can recover the missed digits.
func TestDetectCollapsedPages_BlankSaleWithRateTriggers(t *testing.T) {
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true,
			PostFilterRowCount: 25, BlankSaleWithRateCount: 0},
		{PageNumber: 2, RawRowCount: 20, SuspiciousBrandCount: 0, LayoutDetected: true,
			PostFilterRowCount: 17, BlankSaleWithRateCount: 8}, // 47% blank — should rescue
	}
	got := detectCollapsedPages(stats)
	found := false
	for _, p := range got {
		if p == 2 {
			found = true
		}
	}
	if !found {
		t.Errorf("page 2 (8 blank-sale-with-rate / 17 post-filter = 47%%) should trigger rescue; got %v", got)
	}
}

// v1.0.325 — blank-sale-with-rate trigger must NOT fire on sparse pages
// where 1-2 blank rows happen to coexist with no-sale day. Threshold is
// ≥3 absolute AND ≥30% ratio.
func TestDetectCollapsedPages_BlankSaleWithRateRespectsThreshold(t *testing.T) {
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true,
			PostFilterRowCount: 25, BlankSaleWithRateCount: 0},
		{PageNumber: 2, RawRowCount: 20, SuspiciousBrandCount: 0, LayoutDetected: true,
			PostFilterRowCount: 17, BlankSaleWithRateCount: 2}, // only 2, below absolute floor
	}
	got := detectCollapsedPages(stats)
	for _, p := range got {
		if p == 2 {
			t.Errorf("only 2 blank-sale-with-rate (below floor of 3) should NOT rescue; got %v", got)
		}
	}
}

// v1.0.325 — blank-sale-with-rate must respect the 30% ratio floor:
// 3 absolute blanks on a 30-row page is 10% — below ratio floor, no rescue.
func TestDetectCollapsedPages_BlankSaleWithRateRespectsRatio(t *testing.T) {
	stats := []ExtractionPageStats{
		{PageNumber: 1, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true,
			PostFilterRowCount: 30, BlankSaleWithRateCount: 3}, // 10% — below 30% ratio
		{PageNumber: 2, RawRowCount: 30, SuspiciousBrandCount: 0, LayoutDetected: true,
			PostFilterRowCount: 30, BlankSaleWithRateCount: 0},
	}
	got := detectCollapsedPages(stats)
	for _, p := range got {
		if p == 1 {
			t.Errorf("3/30 = 10%% blank-sale (below 30%% ratio) should NOT rescue; got %v", got)
		}
	}
}
