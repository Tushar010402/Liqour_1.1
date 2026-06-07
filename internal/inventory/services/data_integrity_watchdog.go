package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// DataIntegrityWatchdog is a read-only background sweep that looks for the
// danger patterns behind the FM Tower 8PM Tetra/PET incident (2026-05-29) and
// surfaces them as data_integrity_alerts rows + loud logs, BEFORE a customer
// notices. It never mutates business data — it only reads, and appends to its
// own append-only alert table. Three checks:
//
//	sale_math_mismatch   approved sale rows where opening - sold != closing
//	                     (the symptom that showed "opening 26 / closing 9")
//	stock_ledger_drift   stocks.quantity != latest stock_histories.new_quantity
//	                     (an un-laddered write — what dropped the Tetra 94→26)
//	deleted_with_stock   stocks rows soft-deleted while quantity > 0
//	                     (what silently lost the 26-unit PET)
//
// This is defense-in-depth alongside the structural fixes (v1.0.329 packaging
// guard, approve drift guard, atomic stock-setup) and the block_stock_delete_with_qty
// DB trigger. The structural fixes prevent; the watchdog detects anything that
// still slips through any code path (incl. raw SQL / manual pokes).
type DataIntegrityWatchdog struct {
	db    *database.DB
	cache *cache.Cache
}

func NewDataIntegrityWatchdog(db *database.DB, c *cache.Cache) *DataIntegrityWatchdog {
	return &DataIntegrityWatchdog{db: db, cache: c}
}

// integrityInterval defaults to 6h. Override via DATA_INTEGRITY_INTERVAL
// (Go duration). A non-positive value disables the worker.
func integrityInterval() time.Duration {
	if s := os.Getenv("DATA_INTEGRITY_INTERVAL"); s != "" {
		if d, err := time.ParseDuration(s); err == nil {
			return d
		}
	}
	return 6 * time.Hour
}

// StartWorker runs a boot sweep (after a short delay so the DB is ready) then
// re-sweeps every interval until ctx is done. Mirrors StockReconciliationService.
func (w *DataIntegrityWatchdog) StartWorker(ctx context.Context) {
	d := integrityInterval()
	if d <= 0 {
		log.Printf("DataIntegrityWatchdog: disabled (interval=%v)", d)
		return
	}
	log.Printf("DataIntegrityWatchdog: starting (interval=%v)", d)

	go func() {
		select {
		case <-ctx.Done():
			return
		case <-time.After(45 * time.Second):
		}
		if err := w.RunOnce(ctx); err != nil {
			log.Printf("DataIntegrityWatchdog: boot sweep failed: %v", err)
		}
		t := time.NewTicker(d)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Printf("DataIntegrityWatchdog: worker shutting down")
				return
			case <-t.C:
				if err := w.RunOnce(ctx); err != nil {
					log.Printf("DataIntegrityWatchdog: sweep failed: %v", err)
				}
			}
		}
	}()
}

// alertRow is the shared projection every check produces.
type alertRow struct {
	TenantID    *string `gorm:"column:tenant_id"`
	ShopID      *string `gorm:"column:shop_id"`
	EntityType  string  `gorm:"column:entity_type"`
	EntityID    string  `gorm:"column:entity_id"`
	Detail      string  `gorm:"column:detail"`
}

// perCheckCap bounds how many rows a single check will record per sweep, so a
// systemic regression can't write millions of alert rows. The count is always
// logged so truncation is never silent.
const perCheckCap = 500

// RunOnce performs one read-only sweep. Returns nil on success even when alerts
// are found — the alert rows ARE the output. Errors only surface on query failure.
func (w *DataIntegrityWatchdog) RunOnce(ctx context.Context) error {
	start := time.Now()
	db := w.db.WithContext(ctx)

	total := 0
	total += w.runCheck(ctx, "sale_math_mismatch", "warn", `
		SELECT dsi.tenant_id::text AS tenant_id,
		       dsr.shop_id::text   AS shop_id,
		       'daily_sales_item'  AS entity_type,
		       dsi.id::text        AS entity_id,
		       'approved sale row math broken: opening ' || dsi.opening_stock ||
		         ' - sold ' || dsi.quantity_sold || ' != closing ' || dsi.closing_stock ||
		         ' (product ' || coalesce(dsi.ocr_brand_name,'?') || ', record ' || dsr.id || ')' AS detail
		FROM daily_sales_items dsi
		JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		WHERE dsi.deleted_at IS NULL AND dsr.deleted_at IS NULL
		  AND dsr.status = 'approved'
		  AND dsr.approved_at > now() - interval '45 days'
		  AND (dsi.opening_stock > 0 OR dsi.closing_stock > 0)
		  AND dsi.opening_stock - dsi.quantity_sold <> dsi.closing_stock
		ORDER BY dsr.approved_at DESC
		LIMIT `+fmt.Sprint(perCheckCap+1))

	total += w.runCheck(ctx, "stock_ledger_drift", "error", `
		WITH latest AS (
			SELECT DISTINCT ON (sh.stock_id) sh.stock_id, sh.new_quantity
			FROM stock_histories sh
			WHERE sh.deleted_at IS NULL
			ORDER BY sh.stock_id, sh.created_at DESC, sh.id DESC
		)
		SELECT s.tenant_id::text AS tenant_id,
		       s.shop_id::text   AS shop_id,
		       'stock'           AS entity_type,
		       s.id::text        AS entity_id,
		       'live stock ' || s.quantity || ' != audit ledger ' || l.new_quantity ||
		         ' (product ' || s.product_id || ') — un-laddered write' AS detail
		FROM stocks s
		JOIN latest l ON l.stock_id = s.id
		WHERE s.deleted_at IS NULL AND s.quantity <> l.new_quantity
		LIMIT `+fmt.Sprint(perCheckCap+1))

	total += w.runCheck(ctx, "deleted_with_stock", "error", `
		SELECT s.tenant_id::text AS tenant_id,
		       s.shop_id::text   AS shop_id,
		       'stock'           AS entity_type,
		       s.id::text        AS entity_id,
		       'stock row soft-deleted while holding ' || s.quantity ||
		         ' units (product ' || s.product_id || ', deleted ' ||
		         to_char(s.deleted_at,'YYYY-MM-DD HH24:MI') || ') — units silently removed' AS detail
		FROM stocks s
		WHERE s.deleted_at IS NOT NULL AND s.quantity > 0
		  AND s.deleted_at > now() - interval '45 days'
		LIMIT `+fmt.Sprint(perCheckCap+1))

	_ = db
	log.Printf("DataIntegrityWatchdog: sweep complete — %d open alert(s) recorded in %v", total, time.Since(start))
	return nil
}

// runCheck executes one detection query, upserts an alert per row (deduped by
// fingerprint via the partial unique index), and logs loudly. Returns the count
// recorded. Errors are logged, never fatal — one broken check must not blind the
// others.
func (w *DataIntegrityWatchdog) runCheck(ctx context.Context, name, severity, query string) int {
	var rows []alertRow
	if err := w.db.WithContext(ctx).Raw(query).Scan(&rows).Error; err != nil {
		log.Printf("DataIntegrityWatchdog: check %q query failed (skipped): %v", name, err)
		return 0
	}
	if len(rows) == 0 {
		return 0
	}
	if len(rows) > perCheckCap {
		log.Printf("DataIntegrityWatchdog: 🚨 check %q hit the %d-row cap — MORE rows exist than recorded (systemic regression?)", name, perCheckCap)
		rows = rows[:perCheckCap]
	}

	recorded := 0
	for _, r := range rows {
		fingerprint := name + ":" + r.EntityID
		// Append-only; the partial unique index (fingerprint WHERE resolved_at
		// IS NULL) makes this idempotent across sweeps.
		err := w.db.WithContext(ctx).Exec(`
			INSERT INTO data_integrity_alerts
			  (tenant_id, shop_id, check_name, severity, entity_type, entity_id, detail, fingerprint)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
			ON CONFLICT (fingerprint) WHERE resolved_at IS NULL DO NOTHING`,
			r.TenantID, r.ShopID, name, severity, r.EntityType, r.EntityID, r.Detail, fingerprint).Error
		if err != nil {
			log.Printf("DataIntegrityWatchdog: failed to record alert %q for %s: %v", name, r.EntityID, err)
			continue
		}
		recorded++
		log.Printf("DataIntegrityWatchdog: 🚨 [%s/%s] %s", severity, name, r.Detail)
	}
	return recorded
}
