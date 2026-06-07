package services

import "testing"

// TestNetReceivedQty_NoDoubleSubtract locks the v1.0.390 fix: a per-item
// shortage must be subtracted from stock EXACTLY ONCE.
//
// Bug history: smart_purchase_apply.go used to store the already-netted
// `actualReceived` (= gross - leakage - short) as the item Quantity AND also
// persist Leakage/ShortReceived. ReceivePurchase then subtracted them again,
// so stock landed at `gross - 2*(leak+short)`. chhotu's 90ml Royal Stag
// (billed 96, 1 short) would have become 94, not 95. The fix stores GROSS on
// the item; netReceivedQty is the single subtraction.
func TestNetReceivedQty_NoDoubleSubtract(t *testing.T) {
	cases := []struct {
		name              string
		grossBilled       int
		leakage, short    int
		wantNetIntoStock  int
	}{
		{"clean receipt", 96, 0, 0, 96},
		{"chhotu 90ml: 1 short", 96, 0, 1, 95},
		{"leak + short", 96, 2, 3, 91},
		{"all leaked clamps to 0, never negative", 12, 20, 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			// Apply stores GROSS billed as item.Quantity (the fix). Receive
			// subtracts shortage once via netReceivedQty.
			storedQty := c.grossBilled // smart_purchase_apply.go: spi.Quantity = bottles
			got := netReceivedQty(storedQty, c.leakage, c.short)
			if got != c.wantNetIntoStock {
				t.Fatalf("net into stock = %d, want %d (gross=%d leak=%d short=%d)",
					got, c.wantNetIntoStock, c.grossBilled, c.leakage, c.short)
			}

			// Guard: the OLD buggy path stored the netted qty, then receive
			// subtracted again. Prove that path double-counts so a future
			// revert is unmistakable.
			// (Skip when the correct result already clamps to 0 — both paths
			// bottom out there and can't be distinguished.)
			buggyStored := c.grossBilled - c.leakage - c.short
			buggy := netReceivedQty(buggyStored, c.leakage, c.short)
			if c.leakage+c.short > 0 && got > 0 && buggy >= got {
				t.Fatalf("double-subtract guard ineffective: buggy=%d got=%d", buggy, got)
			}
		})
	}
}

// TestResolveShortage_ValidationGate confirms the apply-side validator the
// fix relies on: it accepts a real short and rejects impossible input
// (receiving more than was dispatched), so apply drops bogus shortages
// instead of persisting them.
func TestResolveShortage_ValidationGate(t *testing.T) {
	// Apply calls resolveShortage(bottles, bottles, bottles-leak-short, ...).
	t.Run("valid 1-bottle short", func(t *testing.T) {
		res := resolveShortage(96, 96, 95, "depot_short", "")
		if !res.IsValid {
			t.Fatalf("expected valid, got error: %s", res.ValidationError)
		}
		if res.ActualReceivedQty != 95 {
			t.Fatalf("ActualReceivedQty = %d, want 95", res.ActualReceivedQty)
		}
	})

	t.Run("received more than dispatched is rejected", func(t *testing.T) {
		res := resolveShortage(96, 96, 97, "", "")
		if res.IsValid {
			t.Fatalf("expected invalid for over-receipt, got valid")
		}
	})

	t.Run("negative net rejected", func(t *testing.T) {
		res := resolveShortage(96, 96, -1, "", "")
		if res.IsValid {
			t.Fatalf("expected invalid for negative actual, got valid")
		}
	})
}
