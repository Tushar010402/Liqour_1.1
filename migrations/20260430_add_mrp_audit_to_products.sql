-- v1.0.123: MRP-change audit trail for transparency / anti-scam.
-- Every code path that writes products.mrp must also stamp these columns.
-- Surfaced on Smart Sale review + inventory product cards for 7 days post-change.
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS last_mrp_change_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_mrp_change_by_id UUID,
  ADD COLUMN IF NOT EXISTS last_mrp_change_by_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS last_mrp_change_previous NUMERIC(12, 2);

CREATE INDEX IF NOT EXISTS idx_products_mrp_change_at
  ON products (tenant_id, last_mrp_change_at DESC)
  WHERE last_mrp_change_at IS NOT NULL;
