-- v1.0.243 — Brand-image verification for AI Stock Setup.
-- Adds three carrier columns on stock_setup_record_items, a partial index
-- on saas_brands.picture (so we can quickly find "already-cached" master
-- entries), and an audit table that captures every Gemini verification
-- call for later accuracy review + cost telemetry.

BEGIN;

-- 1. Carrier columns on stock_setup_items.
ALTER TABLE stock_setup_items
  ADD COLUMN IF NOT EXISTS verified_image_url TEXT,
  ADD COLUMN IF NOT EXISTS gemini_confidence  NUMERIC(4,3),
  ADD COLUMN IF NOT EXISTS gemini_agreed      BOOLEAN,
  ADD COLUMN IF NOT EXISTS verified_via_image BOOLEAN DEFAULT FALSE;

-- 2. Find-cached-brand index. We look up by canonical_name + size, so this
-- is a coverage index for "show me brands that have a reference image".
CREATE INDEX IF NOT EXISTS idx_saas_brands_picture_present
  ON saas_brands(id) WHERE picture IS NOT NULL AND picture != '';

-- 3. Audit table. One row per verify-row call (cache hit OR Gemini call).
CREATE TABLE IF NOT EXISTS stock_setup_image_verifications (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID NOT NULL,
  shop_id          UUID NOT NULL,
  job_id           UUID,
  ocr_brand_text   TEXT NOT NULL,
  ocr_size         TEXT,
  image_url        TEXT NOT NULL,
  matched_brand_id UUID,
  canonical_name   TEXT,
  gemini_agreed    BOOLEAN,
  confidence       NUMERIC(4,3),
  cache_hit        BOOLEAN DEFAULT FALSE,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_setup_image_verifications_tenant_shop
  ON stock_setup_image_verifications(tenant_id, shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stock_setup_image_verifications_cache_hit
  ON stock_setup_image_verifications(created_at DESC) WHERE cache_hit = FALSE;

COMMIT;
