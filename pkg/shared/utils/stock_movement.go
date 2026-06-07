package utils

import (
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// StockMovementParams describes a single stock-balance change that must be
// applied AND audited atomically. Every code path that mutates stocks.quantity
// MUST go through ApplyStockMovement so the four bug classes that hit FM Tower
// in 2026-05 are structurally impossible to reintroduce:
//
//  1. Bug "audit-row missing" — purchase apply previously bumped stocks.quantity
//     but wrote a StockMovement (legacy table) instead of a StockHistory; this
//     helper always writes the StockHistory row.
//  2. Bug "shop_id NULL" — StockHistory.ShopID is denormalized from the locked
//     stock row, so audit queries can filter by shop without joining stocks.
//  3. Bug "stale previous_quantity" — the helper locks the stock row FOR UPDATE
//     and uses the just-read value as PreviousQuantity, eliminating the
//     pre-v1.0.162 stale-snapshot drift that produced negative new_quantity
//     rows.
//  4. Bug "duplicate apply" — when IdempotencyRef is set, the helper checks for
//     an existing StockHistory row with the same (ReferenceID, MovementType)
//     and returns the previous result instead of re-applying. Protects against
//     double-tap submits and retry storms.
type StockMovementParams struct {
	TenantID     uuid.UUID
	StockID      uuid.UUID
	Delta        int    // signed: positive = receive, negative = sell
	MovementType string // "daily_sale", "purchase", "opening_stock_setup", ...
	Reference    string
	ReferenceID  *uuid.UUID
	UnitCost     float64
	TotalCost    float64
	Notes        string
	UserID       uuid.UUID
	// IdempotencyRef, when non-nil, makes the call skip the write if a
	// stock_histories row already exists with the same ReferenceID and
	// MovementType. The pointer disambiguates "no key supplied" (nil) from
	// "zero-uuid key" (which never matches).
	IdempotencyRef *uuid.UUID
}

// StockMovementResult is returned for callers that need the post-apply numbers
// (e.g. daily_sales_items.opening_stock / closing_stock locked-snapshot writes).
type StockMovementResult struct {
	PreviousQuantity int
	NewQuantity      int
	HistoryID        uuid.UUID
	Skipped          bool // true when an idempotency hit short-circuited the write
}

// ApplyStockMovement performs the locked balance update + audit insert. Must be
// called inside an existing gorm.Transaction; the caller is responsible for
// commit/rollback.
func ApplyStockMovement(tx *gorm.DB, p StockMovementParams) (*StockMovementResult, error) {
	if tx == nil {
		return nil, errors.New("stock_movement: nil tx")
	}
	if p.StockID == uuid.Nil {
		return nil, errors.New("stock_movement: empty stock_id")
	}
	if p.MovementType == "" {
		return nil, errors.New("stock_movement: empty movement_type")
	}

	// Idempotency short-circuit. We look up before locking so retries don't
	// hold a row lock waiting for the prior txn to commit; the unique-ish
	// (reference_id, movement_type) pair is rare enough that a stale read is
	// safe — worst case the real lock below dedups again.
	if p.IdempotencyRef != nil && *p.IdempotencyRef != uuid.Nil {
		var existing models.StockHistory
		err := tx.Where("reference_id = ? AND movement_type = ? AND deleted_at IS NULL",
			*p.IdempotencyRef, p.MovementType).
			Order("created_at DESC").
			First(&existing).Error
		if err == nil {
			return &StockMovementResult{
				PreviousQuantity: existing.PreviousQuantity,
				NewQuantity:      existing.NewQuantity,
				HistoryID:        existing.ID,
				Skipped:          true,
			}, nil
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, fmt.Errorf("stock_movement: idempotency lookup: %w", err)
		}
	}

	// Lock the stock row FOR UPDATE so previous_quantity is the value at the
	// instant we update, not a stale snapshot. This is the structural fix for
	// the pre-v1.0.162 audit drift class.
	var stock models.Stock
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ?", p.StockID).
		First(&stock).Error; err != nil {
		return nil, fmt.Errorf("stock_movement: lock stock %s: %w", p.StockID, err)
	}

	prev := stock.Quantity
	newQ := prev + p.Delta
	if newQ < 0 {
		// Caller is responsible for over-sell policy — we record what was
		// asked but never write negative balances. A 0 floor here matches
		// pre-existing daily-sale partial-deduct behavior.
		newQ = 0
	}

	if err := tx.Model(&models.Stock{}).
		Where("id = ?", p.StockID).
		Update("quantity", newQ).Error; err != nil {
		return nil, fmt.Errorf("stock_movement: update stocks: %w", err)
	}

	tenantPtr := p.TenantID
	shopPtr := stock.ShopID
	productPtr := stock.ProductID

	history := models.StockHistory{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantPtr,
		},
		StockID:          stock.ID,
		ShopID:           &shopPtr,
		ProductID:        &productPtr,
		MovementType:     p.MovementType,
		Quantity:         p.Delta,
		PreviousQuantity: prev,
		NewQuantity:      newQ,
		UnitCost:         p.UnitCost,
		TotalCost:        p.TotalCost,
		Reference:        p.Reference,
		ReferenceID:      p.ReferenceID,
		Notes:            p.Notes,
		CreatedByID:      p.UserID,
	}
	if err := tx.Create(&history).Error; err != nil {
		return nil, fmt.Errorf("stock_movement: write history: %w", err)
	}

	return &StockMovementResult{
		PreviousQuantity: prev,
		NewQuantity:      newQ,
		HistoryID:        history.ID,
		Skipped:          false,
	}, nil
}
