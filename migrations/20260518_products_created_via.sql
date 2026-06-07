-- 2026-05-18 — products.created_via
--
-- Provenance for the AI-Purchase image gate. A product created by AI Stock
-- Setup (often with NO bottle photo) must not silently receive purchased
-- stock against an unverified image-less row. AI Purchase apply now blocks
-- when a matched product has created_via='stock_setup' AND no image
-- (image_url / front_image_url / back_image_url all empty), and the operator
-- attaches a photo inline (POST /products/:id/verify-photo) to clear it.
--
-- created_via values (set explicitly at each product-creation call site):
--   'stock_setup'  -> AI Stock Setup apply / NEVER-DROP fallback   (GATED)
--   'ai_purchase'  -> AI Purchase onboarding (fully-new custom)     (exempt)
--   'catalog'      -> master/SaaS-catalog onboarding                (exempt)
--   'manual'       -> manual product create                         (exempt)
--   'bulk_import'  -> bulk import                                    (exempt)
--   'legacy_exempt'-> DEFAULT for every pre-existing row + any
--                      creation site not yet stamped                (exempt)
--
-- Forward-only by design: the DEFAULT backfills ALL existing rows as
-- 'legacy_exempt', so the gate ONLY ever fires for stock_setup products
-- created AFTER this deploy. Zero disruption to the current data backlog.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS created_via varchar(32) NOT NULL DEFAULT 'legacy_exempt';

-- Fast lookup of gate-eligible rows (the apply gate + review annotate both
-- filter created_via = 'stock_setup').
CREATE INDEX IF NOT EXISTS idx_products_created_via
  ON products (tenant_id, created_via)
  WHERE deleted_at IS NULL;
