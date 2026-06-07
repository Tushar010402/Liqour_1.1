package services

import (
	"testing"

	"github.com/google/uuid"
)

func strPtr(s string) *string { return &s }

// TestPickMisboundDuplicateLosers_RealFMTowerCollision replays the exact
// mis-bind from FM Tower job 52714ffc: "SUPERIOR VODKA" (conf 0.95) and
// "SEAGRAMS ROYAL STAG SUPERIOR WHISKY" (conf 1.0, exact) both bound to the
// same Royal Stag product. The vodka row must be unbound; the whisky row
// (the stronger, exact match) must stay.
func TestPickMisboundDuplicateLosers_RealFMTowerCollision(t *testing.T) {
	pid := uuid.New().String()
	items := []SmartPurchaseExtractedItem{
		{RowNumber: 23, BrandName: "SUPERIOR VODKA", SizeML: 375, ProductID: strPtr(pid), MatchConfidence: 0.95},
		{RowNumber: 36, BrandName: "SEAGRAMS ROYAL STAG SUPERIOR WHISKY", SizeML: 375, ProductID: strPtr(pid), MatchConfidence: 1.0},
	}
	losers := pickMisboundDuplicateLosers(items)
	if len(losers) != 1 {
		t.Fatalf("want exactly 1 loser, got %d: %v", len(losers), losers)
	}
	if items[losers[0]].RowNumber != 23 {
		t.Errorf("unbound the wrong row: want row 23 (SUPERIOR VODKA), got row %d (%q)",
			items[losers[0]].RowNumber, items[losers[0]].BrandName)
	}
}

// TestClassifyDuplicateBindings_SerialIsLineIdentity — v1.0.361: the gate-pass
// serial is each line's identity. The SAME product on DISTINCT serials is two
// legitimate dispatch lines → kept (neither dropped nor unbound). Only the SAME
// serial read twice is a true double-extraction → dropped. (Supersedes the older
// "a product never appears on two GP lines → drop the exact duplicate" rule, which
// silently lost real lines like After Dark 180ml on S.No 2 AND 11.)
func TestClassifyDuplicateBindings_SerialIsLineIdentity(t *testing.T) {
	pid := uuid.New().String()
	// Distinct serials (4, 9), same product → both kept.
	distinct := []SmartPurchaseExtractedItem{
		{RowNumber: 4, BrandName: "8PM Gold Blend Scotch Indian Grain Whisky", SizeML: 180, ProductID: strPtr(pid), MatchConfidence: 1.0},
		{RowNumber: 9, BrandName: "8PM GOLD BLEND SCOTCH INDIAN GRAIN WHISKY", SizeML: 180, ProductID: strPtr(pid), MatchConfidence: 0.95},
	}
	if unbind, drop := classifyDuplicateBindings(distinct); len(unbind) != 0 || len(drop) != 0 {
		t.Errorf("distinct serials of same product must be kept; got unbind=%v drop=%v", unbind, drop)
	}
	// Same serial (9, 9) → a true double-extraction → drop the weaker one.
	twin := []SmartPurchaseExtractedItem{
		{RowNumber: 9, BrandName: "8PM Gold Blend Scotch Indian Grain Whisky", SizeML: 180, ProductID: strPtr(pid), MatchConfidence: 1.0},
		{RowNumber: 9, BrandName: "8PM GOLD BLEND SCOTCH INDIAN GRAIN WHISKY", SizeML: 180, ProductID: strPtr(pid), MatchConfidence: 0.95},
	}
	if _, drop := classifyDuplicateBindings(twin); len(drop) != 1 {
		t.Errorf("same-serial double-read must drop exactly 1; got drop=%v", drop)
	}
}

// TestPickMisboundDuplicateLosers_NoFalsePositiveAcrossProducts confirms rows
// on DIFFERENT products are never touched, and unbound (nil) product rows are
// ignored.
func TestPickMisboundDuplicateLosers_NoFalsePositiveAcrossProducts(t *testing.T) {
	a, b := uuid.New().String(), uuid.New().String()
	items := []SmartPurchaseExtractedItem{
		{RowNumber: 1, BrandName: "Brand A Whisky", SizeML: 750, ProductID: strPtr(a), MatchConfidence: 1.0},
		{RowNumber: 2, BrandName: "Brand B Vodka", SizeML: 750, ProductID: strPtr(b), MatchConfidence: 1.0},
		{RowNumber: 3, BrandName: "Unmatched New SKU", SizeML: 90, ProductID: nil},
	}
	if losers := pickMisboundDuplicateLosers(items); len(losers) != 0 {
		t.Errorf("distinct products / nil-pid rows should never be losers, got %v", losers)
	}
}
