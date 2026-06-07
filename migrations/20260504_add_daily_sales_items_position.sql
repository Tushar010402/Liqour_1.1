-- v1.0.149 — Persist user-controlled row order on daily_sales_items so every
-- view (Smart Sale review, Sales Summary, Daily Sales Entry, Web Admin) shows
-- the same order the operator picked. Default 0 keeps legacy rows first; new
-- inserts from Smart Sale apply set position = page*1000 + row_number so the
-- initial order matches IMAGE order (apple-to-apple with the source register).

ALTER TABLE daily_sales_items
    ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_daily_sales_items_record_position
    ON daily_sales_items (daily_sales_record_id, position);

-- Backfill: existing rows ordered by current MRP ascending so the first
-- view of legacy records doesn't jumble. Per-record monotonic.
UPDATE daily_sales_items dsi
SET position = ranked.rn
FROM (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY daily_sales_record_id ORDER BY unit_price ASC, created_at ASC) AS rn
    FROM daily_sales_items
    WHERE deleted_at IS NULL
) ranked
WHERE dsi.id = ranked.id AND dsi.position = 0;
