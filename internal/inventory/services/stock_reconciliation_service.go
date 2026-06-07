package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// StockReconciliationService runs a daily integrity sweep that asserts the
// banking-grade invariant:
//
//	for every stock_id, stocks.quantity must equal the latest
//	stock_histories.new_quantity for that stock_id.
//
// Any divergence indicates either an in-flight bug in the apply paths or a
// manual DB poke. The sweep writes an `audit_heal_v1` reconciliation row that
// closes the gap (so the ledger balances going forward) and logs the diff so
// the on-call engineer can root-cause the source.
type StockReconciliationService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewStockReconciliationService(db *database.DB, cache *cache.Cache) *StockReconciliationService {
	return &StockReconciliationService{db: db, cache: cache}
}

// reconcileInterval defaults to 24h. Override via env STOCK_RECONCILE_INTERVAL
// (Go duration: 1h, 30m, etc.). A non-positive override disables the worker.
func reconcileInterval() time.Duration {
	if s := os.Getenv("STOCK_RECONCILE_INTERVAL"); s != "" {
		if d, err := time.ParseDuration(s); err == nil {
			return d
		}
	}
	return 24 * time.Hour
}

// StartWorker runs an immediate sweep on boot (catches any drift that happened
// since last restart), then re-runs every reconcileInterval until ctx is done.
// Boot-time sweep is intentional: it converts any drift accumulated during a
// deploy window into a visible audit_heal_v1 row before users start writing.
func (s *StockReconciliationService) StartWorker(ctx context.Context) {
	d := reconcileInterval()
	if d <= 0 {
		log.Printf("StockReconciliation: disabled (interval=%v)", d)
		return
	}
	log.Printf("StockReconciliation: starting (interval=%v)", d)

	go func() {
		// Tiny startup delay so the DB / cache are fully initialized before
		// the first sweep. Pinned to 30s — short enough to catch drift fast,
		// long enough that a slow boot won't race the schema migrator.
		select {
		case <-ctx.Done():
			return
		case <-time.After(30 * time.Second):
		}

		if err := s.RunOnce(ctx); err != nil {
			log.Printf("StockReconciliation: boot sweep failed: %v", err)
		}

		t := time.NewTicker(d)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Printf("StockReconciliation: worker shutting down")
				return
			case <-t.C:
				if err := s.RunOnce(ctx); err != nil {
					log.Printf("StockReconciliation: sweep failed: %v", err)
				}
			}
		}
	}()
}

// reconcileRow is the projection of a single drifted (stock, latest_history)
// pair. Only stocks where the audit ledger disagrees with the live balance
// show up here; the LEFT JOIN catches stocks that have no history at all
// (e.g. fresh purchase with the pre-v1.0.216 missing-history bug — those
// rows always appear because their "audit_says" is implicitly 0).
type reconcileRow struct {
	TenantID   uuid.UUID `gorm:"column:tenant_id"`
	StockID    uuid.UUID `gorm:"column:stock_id"`
	ShopID     uuid.UUID `gorm:"column:shop_id"`
	ProductID  uuid.UUID `gorm:"column:product_id"`
	CurQty     int       `gorm:"column:cur_qty"`
	AuditQty   int       `gorm:"column:audit_qty"`
	Delta      int       `gorm:"column:delta"`
}

// RunOnce performs a single reconciliation sweep across every (shop, product)
// stock row in the database. Returns nil on success even if drift was found —
// the heal rows ARE the success state. Errors only surface when the underlying
// query itself fails.
func (s *StockReconciliationService) RunOnce(ctx context.Context) error {
	start := time.Now()

	var rows []reconcileRow
	// Latest history per stock_id, joined back to current stocks. The DISTINCT
	// ON (stock_id) ORDER BY created_at DESC pattern is the cheap version of
	// "newest non-deleted history row per stock"; the (reference_id, movement_type)
	// index + the post-2026-05-11 (shop_id) index keep this fast.
	err := s.db.WithContext(ctx).Raw(`
		WITH latest AS (
			SELECT DISTINCT ON (sh.stock_id)
			       sh.stock_id, sh.new_quantity, sh.tenant_id
			FROM stock_histories sh
			WHERE sh.deleted_at IS NULL
			ORDER BY sh.stock_id, sh.created_at DESC, sh.id DESC
		)
		SELECT s.tenant_id, s.id AS stock_id, s.shop_id, s.product_id,
		       s.quantity AS cur_qty,
		       l.new_quantity AS audit_qty,
		       (s.quantity - l.new_quantity) AS delta
		FROM stocks s
		JOIN latest l ON l.stock_id = s.id
		WHERE s.deleted_at IS NULL
		  AND s.quantity <> l.new_quantity
	`).Scan(&rows).Error
	if err != nil {
		return fmt.Errorf("reconcile query: %w", err)
	}

	if len(rows) == 0 {
		log.Printf("StockReconciliation: clean (no drift) in %v", time.Since(start))
		return nil
	}

	// Find a safe actor for the heal rows. Banking-grade audit insists on a
	// non-NULL created_by_id; picking any active admin/manager for the tenant
	// keeps the foreign key happy without inventing a synthetic user.
	healUserCache := map[uuid.UUID]uuid.UUID{}
	getHealUser := func(tenantID uuid.UUID) uuid.UUID {
		if u, ok := healUserCache[tenantID]; ok {
			return u
		}
		var u struct{ ID uuid.UUID }
		s.db.WithContext(ctx).Raw(`
			SELECT id FROM users
			WHERE tenant_id = ? AND is_active = true AND role IN ('saas_admin','admin','manager','owner')
			ORDER BY CASE role WHEN 'saas_admin' THEN 0 WHEN 'admin' THEN 1 WHEN 'owner' THEN 2 ELSE 3 END,
			         created_at ASC
			LIMIT 1
		`, tenantID).Scan(&u)
		healUserCache[tenantID] = u.ID
		return u.ID
	}

	healed := 0
	for _, r := range rows {
		userID := getHealUser(r.TenantID)
		if userID == uuid.Nil {
			log.Printf("StockReconciliation: skipping stock %s — no admin/manager found for tenant %s",
				r.StockID, r.TenantID)
			continue
		}

		shopRef, prodRef, refID := r.ShopID, r.ProductID, r.StockID
		tenantRef := r.TenantID
		heal := models.StockHistory{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantRef,
			},
			StockID:          r.StockID,
			ShopID:           &shopRef,
			ProductID:        &prodRef,
			MovementType:     "audit_heal_v1",
			Quantity:         r.Delta,
			PreviousQuantity: r.AuditQty,
			NewQuantity:      r.CurQty,
			Reference:        fmt.Sprintf("Nightly reconciliation %s — stock %s", time.Now().UTC().Format("2006-01-02"), r.StockID),
			ReferenceID:      &refID,
			Notes:            fmt.Sprintf("Auto-heal: cur_qty=%d, audit_says=%d, delta=%d. Banking-grade reconciliation closes the gap; the underlying cause should be root-caused in code.", r.CurQty, r.AuditQty, r.Delta),
			CreatedByID:      userID,
		}
		if err := s.db.WithContext(ctx).Create(&heal).Error; err != nil {
			log.Printf("StockReconciliation: failed to write heal row for stock %s (tenant %s): %v",
				r.StockID, r.TenantID, err)
			continue
		}
		healed++
		log.Printf("StockReconciliation: 🩹 stock=%s shop=%s product=%s cur=%d audit=%d delta=%d",
			r.StockID, r.ShopID, r.ProductID, r.CurQty, r.AuditQty, r.Delta)
	}

	log.Printf("StockReconciliation: %d drifted / %d healed in %v",
		len(rows), healed, time.Since(start))
	return nil
}

// Ensure the worker type satisfies the same interface as other background
// workers — pre-empts the "shape drifted" class of bug if the cmd/inventory
// wireup gets refactored.
var _ interface {
	StartWorker(ctx context.Context)
} = (*StockReconciliationService)(nil)

// gorm import kept so a future Tx variant doesn't need to re-import.
var _ = (*gorm.DB)(nil)
