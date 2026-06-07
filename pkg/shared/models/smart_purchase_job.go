package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
)

// SmartPurchaseJob persists a single background AI Purchase extraction so
// clients can submit invoice + gate-pass images, close the app, and come
// back later to a stored result. Mirrors SmartSaleSetupJob — same lifecycle,
// same worker pattern — but lives in the inventory domain because the
// extraction pipeline (and the master catalog + matcher) is owned there.
//
// Lifecycle:
//
//	pending    — row created, images saved to disk, waiting for the worker.
//	processing — worker claimed it; `started_at` is set.
//	done       — ProcessSmartPurchase succeeded; `result` holds the full
//	             SmartPurchaseResult JSON; `completed_at` is set.
//	failed     — terminal failure after retry budget exhausted;
//	             `error_message` explains why.
//	canceled   — user (or cleanup) canceled a pending job before it ran.
//
// Why a dedicated table (not blocking the HTTP request like the legacy
// /smart-purchase/process endpoint): the legacy endpoint runs all OCR
// synchronously and times out at the nginx gateway (~60s) when the operator
// uploads a multi-page invoice + 4-page gate pass (chhotu's case). The
// async path returns a job_id immediately and lets Flutter poll for the
// result without blocking the gateway.
type SmartPurchaseJob struct {
	TenantModel

	// Actor context.
	UserID uuid.UUID `json:"user_id" gorm:"type:uuid;not null;index"`
	ShopID uuid.UUID `json:"shop_id" gorm:"type:uuid;not null;index"`

	// Processing status. Indexed so the worker's
	// "SELECT … WHERE status='pending'" poll stays cheap as the table grows.
	Status string `json:"status" gorm:"not null;default:'pending';index"`

	// Input params captured at submit time so processing is reproducible
	// from the row alone — no dependence on ephemeral client state.
	ShopName string `json:"shop_name,omitempty"`
	// VendorID may be empty when the operator hasn't picked a vendor yet
	// (AI flow infers vendor from the invoice header). We persist whatever
	// the client sent so the worker can pass it through.
	VendorID *uuid.UUID `json:"vendor_id,omitempty" gorm:"type:uuid"`

	// Absolute paths on the inventory container's filesystem, separated by
	// purpose so the worker can pass them to ProcessSmartPurchase the same
	// way the synchronous handler does. The Flutter client posts both arrays
	// in one multipart request.
	InvoiceImagePaths  JSONStringList `json:"invoice_image_paths" gorm:"type:jsonb;default:'[]'"`
	GatePassImagePaths JSONStringList `json:"gate_pass_image_paths" gorm:"type:jsonb;default:'[]'"`

	// Populated after extraction returns. Stored as an opaque JSONB blob —
	// the Flutter client round-trips it through the same parser the
	// synchronous endpoint uses, so no schema drift risk.
	Result SmartPurchaseJobResult `json:"result,omitempty" gorm:"type:jsonb"`

	// Failure plumbing — ErrorMessage is user-facing; RetryCount controls how
	// many times the worker re-queues before giving up.
	ErrorMessage string `json:"error_message,omitempty"`
	RetryCount   int    `json:"retry_count" gorm:"default:0"`

	// Progress tracking for polling UIs. StartedAt may be nil when still
	// pending; CompletedAt only set on terminal states (done/failed/canceled).
	StartedAt   *time.Time `json:"started_at,omitempty"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`

	// v1.0.227 — granular pipeline stage for the polling client. Updated
	// at six checkpoints inside ProcessSmartPurchase so the operator sees
	// "Reading Bill via Textract…" / "Reading Gate-pass via Claude…" /
	// "Matching brands…" / "Building Purcha confirmation…" instead of a
	// generic "Processing…". Always nullable — older clients ignore the
	// field and existing rows (NULL) render as "Processing…".
	ProgressStage *string `json:"progress_stage,omitempty" gorm:"type:varchar(32)"`
}

// SmartPurchase progress_stage constants. Flutter's _progressLabel maps
// each to a localized hint; an unknown value passes through as-is for
// forward compat.
const (
	SmartPurchaseStageQueued             = "queued"
	SmartPurchaseStageExtractingBill     = "extracting_bill"
	SmartPurchaseStageExtractingGP       = "extracting_gp"
	SmartPurchaseStageMatchingBrands     = "matching_brands"
	SmartPurchaseStageBuildingPurchaGate = "building_purcha_gate"
	SmartPurchaseStageDone               = "done"
)

// TableName pins the table name so a future package rename doesn't ripple
// into a silent DB migration.
func (SmartPurchaseJob) TableName() string { return "smart_purchase_jobs" }

// Status constants — the set of values allowed in the `status` column.
const (
	SmartPurchaseJobPending    = "pending"
	SmartPurchaseJobProcessing = "processing"
	SmartPurchaseJobDone       = "done"
	SmartPurchaseJobFailed     = "failed"
	SmartPurchaseJobCanceled   = "canceled"
)

// SmartPurchaseJobResult is an opaque JSONB blob holding the full
// SmartPurchaseResult serialised at worker-completion time. Typed as map so
// GORM's jsonb round-trip works cleanly without importing the inventory
// services package (which would create a circular import).
type SmartPurchaseJobResult map[string]interface{}

// Value / Scan make SmartPurchaseJobResult a valid sql.Scanner + driver.Valuer
// so GORM can persist it as jsonb.
func (j SmartPurchaseJobResult) Value() (driver.Value, error) {
	if j == nil {
		return nil, nil
	}
	return json.Marshal(j)
}

func (j *SmartPurchaseJobResult) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	b, ok := value.([]byte)
	if !ok {
		if s, ok2 := value.(string); ok2 {
			b = []byte(s)
		} else {
			return errors.New("SmartPurchaseJobResult.Scan: unsupported type")
		}
	}
	return json.Unmarshal(b, j)
}
