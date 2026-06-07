package services

import (
	"os"
	"sort"
	"testing"
)

// v1.0.327 alias-conflict gate tests.
//
// Real-world failure (FM Tower 180ml, 2026-05-28): two SmartSaleApplyItem
// rows with DIFFERENT MRPs ("8PM Gold PET ₹130" + "8PM Gold Tetra ₹140")
// arrive at apply pointing to the SAME product_id. createDailySalesEntries
// silently sums Quantity + Amount, destroying one SKU's sale. The gate
// rejects with HTTP 422 + alias_conflicts payload before any DB tx opens.

func TestValidateNoAliasConflicts_FlagsRateDivergent(t *testing.T) {
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_GUARD")
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_RATE_PCT")
	items := []SmartSaleApplyItem{
		{ProductID: "prod_8pm", BrandName: "8PM Gold Scotch", Quantity: 5, Rate: 130},
		{ProductID: "prod_other", BrandName: "Royal Stag", Quantity: 3, Rate: 800},
		{ProductID: "prod_8pm", BrandName: "8PM Gold Scotch", Quantity: 3, Rate: 140},
	}
	r := ValidateNoAliasConflicts(items)
	if !r.Enforced {
		t.Errorf("expected Enforced=true by default, got false")
	}
	if len(r.Conflicts) != 1 {
		t.Fatalf("expected 1 conflict, got %d", len(r.Conflicts))
	}
	c := r.Conflicts[0]
	if c.ProductID != "prod_8pm" {
		t.Errorf("conflict product_id = %s, want prod_8pm", c.ProductID)
	}
	sort.Ints(c.Rows)
	if len(c.Rows) != 2 || c.Rows[0] != 1 || c.Rows[1] != 3 {
		t.Errorf("conflict rows = %v, want [1 3]", c.Rows)
	}
}

func TestValidateNoAliasConflicts_AllowsAgreementWithinThreshold(t *testing.T) {
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_GUARD")
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_RATE_PCT")
	items := []SmartSaleApplyItem{
		{ProductID: "prod_8pm", BrandName: "8PM Gold", Quantity: 5, Rate: 130},
		{ProductID: "prod_8pm", BrandName: "8PM Gold", Quantity: 3, Rate: 131}, // ~0.8% — within 5%
	}
	r := ValidateNoAliasConflicts(items)
	if len(r.Conflicts) != 0 {
		t.Errorf("expected 0 conflicts (rates agree within threshold), got %d: %+v", len(r.Conflicts), r.Conflicts)
	}
}

func TestValidateNoAliasConflicts_LogOnlyWhenDisabled(t *testing.T) {
	os.Setenv("SMART_SALE_ALIAS_CONFLICT_GUARD", "0")
	defer os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_GUARD")
	items := []SmartSaleApplyItem{
		{ProductID: "prod_x", Quantity: 5, Rate: 100},
		{ProductID: "prod_x", Quantity: 5, Rate: 150},
	}
	r := ValidateNoAliasConflicts(items)
	if r.Enforced {
		t.Errorf("expected Enforced=false with env=0, got true")
	}
	if len(r.Conflicts) != 1 {
		t.Errorf("expected conflict still reported in log-only mode, got %d", len(r.Conflicts))
	}
}

func TestValidateNoAliasConflicts_IgnoresZeroQuantity(t *testing.T) {
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_GUARD")
	items := []SmartSaleApplyItem{
		{ProductID: "prod_x", Quantity: 0, Rate: 130}, // zero qty → won't persist
		{ProductID: "prod_x", Quantity: 5, Rate: 140},
	}
	r := ValidateNoAliasConflicts(items)
	if len(r.Conflicts) != 0 {
		t.Errorf("zero-qty row should not cause conflict, got %d", len(r.Conflicts))
	}
}

func TestValidateNoAliasConflicts_IgnoresEmptyProductID(t *testing.T) {
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_GUARD")
	items := []SmartSaleApplyItem{
		{ProductID: "", Quantity: 5, Rate: 130},
		{ProductID: "", Quantity: 5, Rate: 140},
	}
	r := ValidateNoAliasConflicts(items)
	if len(r.Conflicts) != 0 {
		t.Errorf("empty product_id rows should not group, got %d", len(r.Conflicts))
	}
}

func TestValidateNoAliasConflicts_MissingRateTreatedAsDivergent(t *testing.T) {
	os.Unsetenv("SMART_SALE_ALIAS_CONFLICT_GUARD")
	items := []SmartSaleApplyItem{
		{ProductID: "prod_x", Quantity: 5, Rate: 130},
		{ProductID: "prod_x", Quantity: 5, Rate: 0}, // missing rate → conservative: conflict
	}
	r := ValidateNoAliasConflicts(items)
	if len(r.Conflicts) != 1 {
		t.Errorf("missing rate should trigger conflict (safer to over-flag than silently merge), got %d", len(r.Conflicts))
	}
}
