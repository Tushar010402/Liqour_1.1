package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
)

// SmartSaleSetupJob persists a single background AI Sales Entry extraction so
// clients can submit receipt images, close the app, and come back later to a
// stored result. Mirrors SmartStockSetupJob — same lifecycle, same worker
// pattern — but lives in the sales domain because the extraction pipeline
// (and the referenced master data — daily sales items, shop stock, OCR
// mappings) is owned by the sales service.
//
// Lifecycle:
//
//	pending    — row created, images saved to disk, waiting for the worker.
//	processing — worker claimed it; `started_at` is set.
//	done       — ProcessSmartSale succeeded; `result` holds the full
//	             SmartSaleResult JSON; `completed_at` is set.
//	failed     — terminal failure after retry budget exhausted;
//	             `error_message` explains why.
//	canceled   — user (or cleanup) canceled a pending job before it ran.
//
// Why a dedicated table (not reusing DailySalesRecord's `pending` state):
// a daily-sales record is *approved* state; jobs represent transient
// processing that may end in zero records (all items unmatched, or a vendor
// failure). Mixing them would pollute the approved-sales audit trail.
type SmartSaleSetupJob struct {
	TenantModel

	// Actor context.
	UserID uuid.UUID `json:"user_id" gorm:"type:uuid;not null;index"`
	ShopID uuid.UUID `json:"shop_id" gorm:"type:uuid;not null;index"`

	// Processing status. Indexed so the worker's
	// "SELECT … WHERE status='pending'" poll stays cheap as the table grows.
	Status string `json:"status" gorm:"not null;default:'pending';index"`

	// Input params captured at submit time so processing is reproducible
	// from the row alone — no dependence on ephemeral client state.
	ShopName string    `json:"shop_name,omitempty"`
	SaleDate time.Time `json:"sale_date"`
	Category string    `json:"category,omitempty"` // "beer" | "non_beer"
	Size     string    `json:"size,omitempty"`

	// Absolute paths on the sales container's filesystem. The worker reads
	// these back and streams them into ProcessSmartSale.
	ImagePaths JSONStringList `json:"image_paths" gorm:"type:jsonb;default:'[]'"`

	// Populated after extraction returns. Stored as an opaque JSONB blob —
	// the Flutter client round-trips it through the same parser the
	// synchronous endpoint uses, so no schema drift risk.
	Result SmartSaleJobResult `json:"result,omitempty" gorm:"type:jsonb"`

	// Failure plumbing — ErrorMessage is user-facing; RetryCount controls how
	// many times the worker re-queues before giving up.
	ErrorMessage string `json:"error_message,omitempty"`
	RetryCount   int    `json:"retry_count" gorm:"default:0"`

	// Progress tracking for polling UIs. StartedAt may be nil when still
	// pending; CompletedAt only set on terminal states (done/failed/canceled).
	StartedAt   *time.Time `json:"started_at,omitempty"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`

	// v1.0.182 — per-image cv-sidecar /quality-check snapshot captured at
	// extraction time. Lets the accuracy dashboard plot blur/contrast trends
	// per shop and detect quality regressions (lens dirt, lighting changes,
	// shopkeepers switching to a worse phone). One element per uploaded
	// image; nil/empty when cv-sidecar was unreachable. See
	// QualityCheckSnapshot for the wire shape.
	QualityCheckResults QualityCheckSnapshots `json:"quality_check_results,omitempty" gorm:"type:jsonb"`
}

// QualityCheckSnapshot captures the cv-sidecar /quality-check response for
// a single uploaded image at the moment we ran extraction on it. Persisted
// alongside the SmartSaleSetupJob row so an admin can correlate poor
// accuracy with poor input quality without re-fetching the source image.
type QualityCheckSnapshot struct {
	ImageIndex   int      `json:"image_index"`
	Blur         float64  `json:"blur"`
	Contrast     float64  `json:"contrast"`
	Brightness   float64  `json:"brightness"`
	SkewDeg      float64  `json:"skew_deg"`
	Issues       []string `json:"issues,omitempty"`
	SevereIssues []string `json:"severe_issues,omitempty"`
	Score        float64  `json:"score"`
	Advisory     bool     `json:"advisory"`
	Severe       bool     `json:"severe"`
	Override     bool     `json:"override,omitempty"`
}

// QualityCheckSnapshots is GORM-friendly jsonb storage for a list of snapshots.
type QualityCheckSnapshots []QualityCheckSnapshot

func (q QualityCheckSnapshots) Value() (driver.Value, error) {
	if q == nil {
		return nil, nil
	}
	return json.Marshal(q)
}

func (q *QualityCheckSnapshots) Scan(value interface{}) error {
	if value == nil {
		*q = nil
		return nil
	}
	b, ok := value.([]byte)
	if !ok {
		if s, ok2 := value.(string); ok2 {
			b = []byte(s)
		} else {
			return errors.New("QualityCheckSnapshots.Scan: unsupported type")
		}
	}
	return json.Unmarshal(b, q)
}

// TableName pins the table name so a future package rename doesn't ripple
// into a silent DB migration.
func (SmartSaleSetupJob) TableName() string { return "smart_sale_setup_jobs" }

// Status constants — the set of values allowed in the `status` column.
const (
	SmartSaleJobPending    = "pending"
	SmartSaleJobProcessing = "processing"
	SmartSaleJobDone       = "done"
	SmartSaleJobFailed     = "failed"
	SmartSaleJobCanceled   = "canceled"
)

// SmartSaleJobResult is an opaque JSONB blob holding the full SmartSaleResult
// serialised at worker-completion time. Typed as map so GORM's jsonb
// round-trip works cleanly without the sales services package (which would
// create a circular import).
type SmartSaleJobResult map[string]interface{}

// Value / Scan make SmartSaleJobResult a valid sql.Scanner + driver.Valuer
// so GORM can persist it as jsonb.
func (j SmartSaleJobResult) Value() (driver.Value, error) {
	if j == nil {
		return nil, nil
	}
	return json.Marshal(j)
}

func (j *SmartSaleJobResult) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	b, ok := value.([]byte)
	if !ok {
		if s, ok2 := value.(string); ok2 {
			b = []byte(s)
		} else {
			return errors.New("SmartSaleJobResult.Scan: unsupported type")
		}
	}
	return json.Unmarshal(b, j)
}
