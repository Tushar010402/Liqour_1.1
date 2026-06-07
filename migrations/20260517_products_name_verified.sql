-- 2026-05-17 — products.name_verified
--
-- Stock Setup now saves EVERY readable row verbatim (never skips), even when
-- the brand is garbled OCR with no catalog match ("100 Step"). Such a product
-- carries an unverified name. The authoritative name is fixed later by a
-- trusted bottle photo (Gemini) from the inventory page, and a purchase for
-- that product is blocked until the name is image-verified — so purchase and
-- sales always reconcile on the correct name.
--
-- name_verified = true  -> name is trustworthy (master-catalog pick OR a
--                          confirmed high-confidence bottle-photo verify)
-- name_verified = false -> raw, unverified Stock-Setup text; must be
--                          image-verified before it can be purchased.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS name_verified boolean NOT NULL DEFAULT false;

-- Backfill so the gate is meaningful immediately for existing data:
--   * catalog-linked products (saas_brand_id present) have a trustworthy
--     name -> verified.
--   * products already confirmed against a photo -> verified.
--   * everything else (uncatalogued raw text) stays false -> needs a photo
--     verify before purchase.
UPDATE products
   SET name_verified = true
 WHERE deleted_at IS NULL
   AND name_verified = false
   AND ( saas_brand_id IS NOT NULL
      OR verified_via_image_front = true
      OR verified_via_image_back  = true );

-- Fast lookup of products still needing verification (inventory chip + the
-- purchase gate both filter on this).
CREATE INDEX IF NOT EXISTS idx_products_name_unverified
  ON products (tenant_id, shop_id)
  WHERE deleted_at IS NULL AND name_verified = false;
