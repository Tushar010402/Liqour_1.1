-- v1.0.184 Track B5 — setup_rescue drop learning.
--
-- Captures which products were auto-injected as setup_rescue rows on a Smart
-- Sale extraction but the operator dropped (deleted from the review screen
-- before apply). The rescue-ranking logic in MatchAndValidate uses this
-- per-shop count to deprioritize chronically-dropped products so the top-N
-- cap (Track A5) doesn't keep wasting slots on rows the operator never wants.
--
-- Idempotent — safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS smart_sale_rescue_drops (
    tenant_id        uuid                     NOT NULL,
    shop_id          uuid                     NOT NULL,
    product_id       uuid                     NOT NULL,
    dropped_count    integer                  NOT NULL DEFAULT 1,
    last_dropped_at  timestamptz              NOT NULL DEFAULT NOW(),
    first_dropped_at timestamptz              NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, shop_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_ssrd_shop_recent
    ON smart_sale_rescue_drops (tenant_id, shop_id, last_dropped_at DESC);

COMMIT;
