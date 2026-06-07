package services

import (
	"os"
	"testing"

	"github.com/google/uuid"
)

// v1.0.386 — auto-onboard at apply. The DB create + idempotency paths are
// validated live against Postgres (read-only clone of a real job, see the
// release notes) because sqlite can't AutoMigrate the Postgres-default models.
// These untagged tests cover the pure pieces: the kill-switch, the canonical
// size label, and the dispatcher's pre-DB "insufficient data" guards (which
// must return ("",nil) WITHOUT touching the tx so the caller records a blocking
// skip rather than crashing or silently dropping).

func TestSmartPurchaseAutoOnboardEnabled(t *testing.T) {
	tid := uuid.New()
	// Default ON (no env).
	os.Unsetenv("SMART_PURCHASE_AUTO_ONBOARD")
	os.Unsetenv("SMART_PURCHASE_AUTO_ONBOARD_TENANT_" + tid.String())
	if !smartPurchaseAutoOnboardEnabled(tid) {
		t.Fatal("expected default ON")
	}
	// Global off.
	os.Setenv("SMART_PURCHASE_AUTO_ONBOARD", "0")
	if smartPurchaseAutoOnboardEnabled(tid) {
		t.Fatal("expected OFF when SMART_PURCHASE_AUTO_ONBOARD=0")
	}
	os.Setenv("SMART_PURCHASE_AUTO_ONBOARD", "false")
	if smartPurchaseAutoOnboardEnabled(tid) {
		t.Fatal("expected OFF when =false")
	}
	os.Unsetenv("SMART_PURCHASE_AUTO_ONBOARD")
	// Per-tenant override OFF wins over default ON.
	os.Setenv("SMART_PURCHASE_AUTO_ONBOARD_TENANT_"+tid.String(), "0")
	if smartPurchaseAutoOnboardEnabled(tid) {
		t.Fatal("expected per-tenant OFF")
	}
	os.Unsetenv("SMART_PURCHASE_AUTO_ONBOARD_TENANT_" + tid.String())
}

func TestCanonicalSizeLabel(t *testing.T) {
	cases := []struct {
		ml   int
		cat  string
		want string
	}{
		{90, "Whisky", "90ml (Nip)"},
		{180, "Whisky", "180ml (Quarter)"},
		{375, "Vodka", "375ml (Half)"},
		{750, "Whisky", "750ml (Full)"},
		{1000, "Whisky", "1L+ (Large)"},
		{330, "Beer", "330ml & Below"},
		{650, "Beer", "650ml"},
	}
	for _, c := range cases {
		if got := canonicalSizeLabel(c.ml, c.cat); got != c.want {
			t.Errorf("canonicalSizeLabel(%d,%q)=%q want %q", c.ml, c.cat, got, c.want)
		}
	}
}

// TestAutoOnboardApplyItem_InsufficientData proves the pre-DB guards: when the
// payload can't yield a (name|saas_brand)+size, the dispatcher returns ("",nil)
// without dereferencing the nil tx — the caller turns that into a BLOCKING skip,
// never a silent drop and never a crash.
func TestAutoOnboardApplyItem_InsufficientData(t *testing.T) {
	s := &SmartPurchaseService{}
	tenant, shop := uuid.New(), uuid.New()

	// 1. No payload at all.
	pid, err := s.autoOnboardApplyItem(nil, tenant, shop, SmartPurchaseApplyItem{})
	if pid != "" || err != nil {
		t.Fatalf("nil payload: want (\"\",nil) got (%q,%v)", pid, err)
	}

	// 2. Master tier with a valid saas_brand but NO resolvable size → no DB.
	pid, err = s.autoOnboardApplyItem(nil, tenant, shop, SmartPurchaseApplyItem{
		OnboardingTier:    "master_create_shop_product",
		OnboardingPayload: &OnboardingPayload{MasterSaaSBrandID: uuid.New().String()},
	})
	if pid != "" || err != nil {
		t.Fatalf("master no-size: want (\"\",nil) got (%q,%v)", pid, err)
	}

	// 3. Fully-new with no name and no size → no DB.
	pid, err = s.autoOnboardApplyItem(nil, tenant, shop, SmartPurchaseApplyItem{
		OnboardingTier:    "fully_new",
		OnboardingPayload: &OnboardingPayload{},
	})
	if pid != "" || err != nil {
		t.Fatalf("fully_new dataless: want (\"\",nil) got (%q,%v)", pid, err)
	}

	// 4. Master tier with a malformed saas_brand id → error (surfaced), not panic.
	_, err = s.autoOnboardApplyItem(nil, tenant, shop, SmartPurchaseApplyItem{
		SizeML:            180,
		OnboardingTier:    "master_create_shop_product",
		OnboardingPayload: &OnboardingPayload{MasterSaaSBrandID: "not-a-uuid"},
	})
	if err == nil {
		t.Fatal("malformed saas_brand id: expected an error")
	}
}
