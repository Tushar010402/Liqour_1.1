-- v1.0.216 — stock_histories audit-integrity hardening
--
-- Root cause: a single Go struct that didn't declare shop_id / product_id silently
-- dropped those columns on every insert. The DB columns existed but the GORM model
-- (StockHistory in pkg/shared/models/inventory.go) was missing the fields, so
-- audit-by-shop queries (e.g. `WHERE shop_id = '<fm tower>'`) returned 4 of 1597
-- rows for FM Tower on 2026-05-11 instead of every movement. Same v1.0.132
-- products.last_mrp_change_at GORM-mangling pattern.
--
-- This migration:
--   1. Backfills shop_id + product_id on legacy rows by joining stocks (idempotent
--      — only touches NULLs).
--   2. Indexes (shop_id), (product_id), and (reference_id) so the new audit-by-shop
--      list endpoint + idempotency lookup don't full-scan.

BEGIN;

UPDATE stock_histories sh
SET shop_id    = COALESCE(sh.shop_id, s.shop_id),
    product_id = COALESCE(sh.product_id, s.product_id)
FROM stocks s
WHERE s.id = sh.stock_id
  AND (sh.shop_id IS NULL OR sh.product_id IS NULL);

CREATE INDEX IF NOT EXISTS idx_stock_histories_shop
    ON stock_histories (shop_id) WHERE shop_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_stock_histories_product
    ON stock_histories (product_id) WHERE product_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_stock_histories_ref
    ON stock_histories (reference_id, movement_type) WHERE reference_id IS NOT NULL AND deleted_at IS NULL;

-- Banking-grade invariants — enforced via BEFORE-INSERT trigger so the 264
-- legacy math-violation rows (pre-v1.0.216 bugs) stay frozen in place while
-- every new write is gated. CHECK constraints with NOT VALID can't be used
-- here because Postgres re-validates them on every UPDATE, which would block
-- legitimate soft-deletes on legacy rows.
CREATE OR REPLACE FUNCTION stock_histories_insert_guard() RETURNS trigger AS $$
BEGIN
  IF NEW.new_quantity <> NEW.previous_quantity + NEW.quantity THEN
    RAISE EXCEPTION 'stock_histories math violation: new_quantity (%) <> previous_quantity (%) + quantity (%)',
      NEW.new_quantity, NEW.previous_quantity, NEW.quantity;
  END IF;
  -- audit_heal_v1 is the only allowed reconciliation row; everywhere else
  -- the ledger refuses to record negative balances.
  IF NEW.movement_type <> 'audit_heal_v1' THEN
    IF NEW.new_quantity < 0 OR NEW.previous_quantity < 0 THEN
      RAISE EXCEPTION 'stock_histories non-negative violation: prev=%, new=% (movement=%). Banking-grade ledger refuses to record negative stock — caller must clamp at 0 and emit a stock-alert.',
        NEW.previous_quantity, NEW.new_quantity, NEW.movement_type;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stock_histories_insert_guard ON stock_histories;
CREATE TRIGGER trg_stock_histories_insert_guard
  BEFORE INSERT ON stock_histories
  FOR EACH ROW EXECUTE FUNCTION stock_histories_insert_guard();

-- Append-only: ledger semantic fields cannot be mutated post-insert. Soft-delete
-- (deleted_at) and shop_id/product_id backfill (this migration's UPDATE above)
-- are intentionally exempt.
CREATE OR REPLACE FUNCTION stock_histories_append_only() RETURNS trigger AS $$
BEGIN
  IF NEW.stock_id IS DISTINCT FROM OLD.stock_id
     OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
     OR NEW.movement_type IS DISTINCT FROM OLD.movement_type
     OR NEW.quantity IS DISTINCT FROM OLD.quantity
     OR NEW.previous_quantity IS DISTINCT FROM OLD.previous_quantity
     OR NEW.new_quantity IS DISTINCT FROM OLD.new_quantity
     OR NEW.unit_cost IS DISTINCT FROM OLD.unit_cost
     OR NEW.total_cost IS DISTINCT FROM OLD.total_cost
     OR NEW.reference_id IS DISTINCT FROM OLD.reference_id
     OR NEW.created_by_id IS DISTINCT FROM OLD.created_by_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'stock_histories is append-only: cannot mutate ledger columns (write a reversal row instead)';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stock_histories_append_only ON stock_histories;
CREATE TRIGGER trg_stock_histories_append_only
  BEFORE UPDATE ON stock_histories
  FOR EACH ROW EXECUTE FUNCTION stock_histories_append_only();

-- Hard DELETE forbidden; soft-delete via deleted_at is the only acceptable removal.
CREATE OR REPLACE FUNCTION stock_histories_no_delete() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'stock_histories rows cannot be hard-deleted (banking-grade audit). Set deleted_at if you must hide a row.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stock_histories_no_delete ON stock_histories;
CREATE TRIGGER trg_stock_histories_no_delete
  BEFORE DELETE ON stock_histories
  FOR EACH ROW EXECUTE FUNCTION stock_histories_no_delete();

COMMIT;
