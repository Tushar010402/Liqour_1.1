package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
)

// SmartStockSetupJob persists a single background extraction job so clients
// can submit images, close the app, and come back later to a stored result.
//
// Lifecycle:
//
//	pending    — row created, images saved to disk, waiting for the worker.
//	processing — worker claimed it; `started_at` is set.
//	done       — ProcessExtraction succeeded; `result` holds the full
//	             SmartStockSetupResult JSON; `completed_at` is set.
//	failed     — terminal failure after retry budget exhausted;
//	             `error_message` explains why.
//	canceled   — user (or cleanup) canceled a pending job before it ran.
//
// Why a dedicated table and not the existing StockSetupRecord: that table
// represents APPROVED setups (post-apply). Jobs are transient processing
// state — keeping them separate avoids polluting the audit trail of
// real setups with half-processed attempts.
type SmartStockSetupJob struct {
	TenantModel

	// Actor context — who submitted and which shop.
	UserID uuid.UUID `json:"user_id" gorm:"type:uuid;not null;index"`
	ShopID uuid.UUID `json:"shop_id" gorm:"type:uuid;not null;index"`

	// Processing status. Indexed so the worker's "SELECT … WHERE status='pending'"
	// poll is cheap even when the table has many completed rows.
	Status string `json:"status" gorm:"not null;default:'pending';index"`

	// Input params captured at submit time so processing is fully reproducible
	// from the row alone — no dependence on ephemeral client state.
	CategoryID  *uuid.UUID `json:"category_id,omitempty" gorm:"type:uuid"`
	Size        string     `json:"size,omitempty"`
	StockColumn string     `json:"stock_column,omitempty" gorm:"default:'total'"`

	// Absolute paths on the inventory container's filesystem. The worker
	// reads these back and streams them into ProcessExtraction.
	ImagePaths JSONStringList `json:"image_paths" gorm:"type:jsonb;default:'[]'"`

	// Populated after ProcessExtraction returns. SessionID matches the value
	// inside Result; storing it at the top level lets clients filter without
	// parsing the blob.
	SessionID string          `json:"session_id,omitempty"`
	Result    SmartStockJobResult `json:"result,omitempty" gorm:"type:jsonb"`

	// Failure plumbing — ErrorMessage is user-facing; RetryCount controls how
	// many times the worker re-queues before giving up.
	ErrorMessage string `json:"error_message,omitempty"`
	RetryCount   int    `json:"retry_count" gorm:"default:0"`

	// Progress tracking for polling UIs. StartedAt may be nil when still
	// pending; CompletedAt only set on terminal states (done/failed/canceled).
	StartedAt   *time.Time `json:"started_at,omitempty"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

// TableName pins the table name so a future package rename doesn't ripple
// into a silent DB migration.
func (SmartStockSetupJob) TableName() string { return "smart_stock_setup_jobs" }

// Status constants — the set of values allowed in the `status` column.
const (
	StockSetupJobPending    = "pending"
	StockSetupJobProcessing = "processing"
	StockSetupJobDone       = "done"
	StockSetupJobFailed     = "failed"
	StockSetupJobCanceled   = "canceled"
)

// SmartStockJobResult is an opaque JSONB blob holding the full
// SmartStockSetupResult serialised at worker-completion time. We keep it
// typed as map so GORM's jsonb round-trip works cleanly without pulling
// the services package (which would create a circular import).
type SmartStockJobResult map[string]interface{}

// Value / Scan make SmartStockJobResult a valid sql.Scanner + driver.Valuer
// so GORM can persist it as jsonb.
func (j SmartStockJobResult) Value() (driver.Value, error) {
	if j == nil {
		return nil, nil
	}
	return json.Marshal(j)
}

func (j *SmartStockJobResult) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	b, ok := value.([]byte)
	if !ok {
		if s, ok2 := value.(string); ok2 {
			b = []byte(s)
		} else {
			return errors.New("SmartStockJobResult.Scan: unsupported type")
		}
	}
	return json.Unmarshal(b, j)
}
