-- 2026-05-29 — Data-integrity safeguards (post FM Tower 8PM Tetra/PET incident).
--
-- Two parts:
--   1. block_stock_delete_with_qty trigger — refuse to soft-delete a stocks row
--      that still has quantity > 0 (the gap that silently lost the 26-unit PET).
--      Catches BOTH GORM soft-deletes and raw `UPDATE stocks SET deleted_at`.
--      Legit "zero-first" flows (clearStaleStockOutsideSetup zeroes quantity in a
--      prior statement, so OLD.quantity is already 0 when the row is removed) are
--      unaffected. Audited folds that must remove a qty>0 row (product_merge folds
--      quantity into the canonical row first) opt out per-transaction with
--      `SET LOCAL liquorpro.allow_stock_delete = 'on'`.
--   2. data_integrity_alerts table — append-only sink the DataIntegrityWatchdog
--      writes to when it finds a danger pattern, so issues surface to ops.
--
-- Both are reversible: DROP TRIGGER / DROP TABLE.

BEGIN;

-- ── Part 1: block soft-deleting stock that still has units ───────────────────
CREATE OR REPLACE FUNCTION block_stock_delete_with_qty() RETURNS trigger AS $$
BEGIN
    IF coalesce(current_setting('liquorpro.allow_stock_delete', true), '') <> 'on' THEN
        RAISE EXCEPTION
            'blocked soft-delete of stock % (product %) with quantity % > 0 — zero it with a stock_histories row first, or SET LOCAL liquorpro.allow_stock_delete=''on'' for an audited fold/merge',
            OLD.id, OLD.product_id, OLD.quantity
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_stock_delete_with_qty ON stocks;
CREATE TRIGGER trg_block_stock_delete_with_qty
    BEFORE UPDATE ON stocks
    FOR EACH ROW
    WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL AND OLD.quantity > 0)
    EXECUTE FUNCTION block_stock_delete_with_qty();

-- ── Part 2: data-integrity alert sink ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS data_integrity_alerts (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at   timestamptz NOT NULL DEFAULT now(),
    tenant_id    uuid,
    shop_id      uuid,
    check_name   varchar(64)  NOT NULL,   -- e.g. 'sale_math_mismatch', 'stock_ledger_drift', 'deleted_with_stock'
    severity     varchar(16)  NOT NULL DEFAULT 'warn',
    entity_type  varchar(32),             -- 'daily_sales_item' | 'stock' | 'product'
    entity_id    uuid,
    detail       text         NOT NULL,
    resolved_at  timestamptz,
    fingerprint  varchar(128) NOT NULL    -- check_name + entity → dedupe key
);

-- One open (unresolved) alert per fingerprint; lets the watchdog upsert instead
-- of spamming a new row every sweep.
CREATE UNIQUE INDEX IF NOT EXISTS uq_data_integrity_alerts_open
    ON data_integrity_alerts (fingerprint)
    WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_data_integrity_alerts_open
    ON data_integrity_alerts (created_at DESC)
    WHERE resolved_at IS NULL;

COMMIT;
