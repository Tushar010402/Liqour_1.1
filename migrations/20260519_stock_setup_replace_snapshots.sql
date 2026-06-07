-- 2026-05-19 — stock_setup_replace_snapshots
--
-- Reversible audit for the AI Stock Setup "snapshot replace" at approval.
--
-- When a manager/admin approves a record, every in-scope product (same
-- shop + normalized size + beer/non-beer bucket as the record — NEVER
-- broader than the record) that is NOT in the approved set has its stock
-- zeroed (existing clearStaleStockOutsideSetup behaviour) AND the product
-- itself soft-deactivated (deleted_at set) so inventory reflects exactly
-- the approved snapshot — old/stale/duplicate rows disappear, only the
-- just-approved products remain.
--
-- This table records the pre-change state per product per record so the
-- ENTIRE replace can be reversed (un-delete the products, restore their
-- prior stock) if an approved register turns out to have silently dropped
-- a real item. This is what makes the destructive-looking replace safe:
-- nothing is hard-deleted, every removal is recorded and recoverable.
--
-- No FK constraints — intentional. stock_setup_items itself has no FK to
-- products; a FK here could abort the approve transaction if a product row
-- is later removed by another path. Forward-only, additive, idempotent.

CREATE TABLE IF NOT EXISTS stock_setup_replace_snapshots (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               uuid NOT NULL,
    stock_setup_record_id   uuid NOT NULL,
    product_id              uuid NOT NULL,
    shop_id                 uuid NOT NULL,
    stock_id                uuid,
    prev_stock_quantity     integer NOT NULL DEFAULT 0,
    prev_product_deleted_at timestamptz,
    prev_is_active          boolean NOT NULL DEFAULT true,
    action                  varchar(24) NOT NULL DEFAULT 'deactivated',
    restored                boolean NOT NULL DEFAULT false,
    restored_at             timestamptz,
    restored_by_id          uuid,
    notes                   text,
    created_by_id           uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now()
);

-- Restore lookup: all not-yet-restored snapshot rows for a record.
CREATE INDEX IF NOT EXISTS idx_ssrs_record
    ON stock_setup_replace_snapshots (tenant_id, stock_setup_record_id)
    WHERE restored = false;

-- Per-product audit ("what approval removed this product, and when").
CREATE INDEX IF NOT EXISTS idx_ssrs_product
    ON stock_setup_replace_snapshots (tenant_id, product_id);
