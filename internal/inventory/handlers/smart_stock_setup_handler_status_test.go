package handlers

import (
	"net/http"
	"testing"

	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// TestApplyResultHTTPStatus is the permanent regression guard for the
// v1.0.278 "submitted but nothing saved" contract fix. For ~24h the app told
// operators their AI Stock Setup was submitted while the apply transaction had
// actually saved 0 rows — purely because the handler returned HTTP 200 on a
// failed result. This test makes that lie impossible to reintroduce: a failed
// or nothing-persisted apply MUST map to a non-2xx status.
//
// Pure: no DB, no auth, no customer data — safe to run anywhere, every build.
func TestApplyResultHTTPStatus(t *testing.T) {
	cases := []struct {
		name string
		in   *services.SmartStockSetupApplyResult
		want int
	}{
		{
			name: "total failure (the exact 24h bug) -> 422, never 200",
			in:   &services.SmartStockSetupApplyResult{Status: "failed", ItemsApplied: 0, ItemsFailed: 29, ItemsReceived: 29},
			want: http.StatusUnprocessableEntity,
		},
		{
			name: "nothing persisted but status not set -> 422",
			in:   &services.SmartStockSetupApplyResult{Status: "", ItemsApplied: 0, ItemsReceived: 29},
			want: http.StatusUnprocessableEntity,
		},
		{
			name: "full success -> 200",
			in:   &services.SmartStockSetupApplyResult{Status: "success", ItemsApplied: 29, ItemsReceived: 29},
			want: http.StatusOK,
		},
		{
			name: "partial success (rows DID persist) -> 200",
			in:   &services.SmartStockSetupApplyResult{Status: "partial", ItemsApplied: 26, ItemsFailed: 3, ItemsReceived: 29},
			want: http.StatusOK,
		},
		{
			name: "pending approval (salesman flow, recorded) -> 200",
			in:   &services.SmartStockSetupApplyResult{Status: "pending_approval", ItemsApplied: 29, ItemsReceived: 29},
			want: http.StatusOK,
		},
		{
			name: "single row applied -> 200",
			in:   &services.SmartStockSetupApplyResult{Status: "success", ItemsApplied: 1, ItemsReceived: 1},
			want: http.StatusOK,
		},
		{
			name: "nil result -> 200 (legacy no-op path, unchanged)",
			in:   nil,
			want: http.StatusOK,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := applyResultHTTPStatus(c.in)
			if got != c.want {
				t.Fatalf("applyResultHTTPStatus(%+v) = %d, want %d — the 'submitted but nothing saved' contract is broken", c.in, got, c.want)
			}
		})
	}
}
