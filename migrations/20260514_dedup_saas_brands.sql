-- v1.0.241 — Master catalog dedup + size-suffix strip.
--
-- Two cleanups in one migration:
--   1. Case-variant dedup: for each LOWER(name) cluster with >1 row, pick a
--      canonical (highest product_refs → longest name → alpha tie-break),
--      redirect every products.saas_brand_id from non-canonical → canonical,
--      then soft-delete non-canonical rows.
--   2. Size-suffix strip: rename master entries like "Mateus Rose Wine 750 ML"
--      → "Mateus Rose Wine". Size lives on products.size, not in the master
--      name.
--
-- Idempotent: rerunning is safe. The dedup leaves 0 clusters with >1 row, so
-- the second run's WITH clause returns empty. The size-strip update is a
-- no-op once names already lack the suffix.

BEGIN;

-- ============================================================================
-- 1. CASE-VARIANT DEDUP
-- ============================================================================

WITH clusters AS (
  SELECT regexp_replace(LOWER(TRIM(name)),'\s+',' ','g') AS norm,
         id, name,
         (SELECT COUNT(*) FROM products WHERE saas_brand_id = sb.id AND deleted_at IS NULL) AS prod_refs,
         length(name) AS namelen
  FROM saas_brands sb WHERE deleted_at IS NULL
),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY norm ORDER BY prod_refs DESC, namelen DESC, name DESC) AS rk
  FROM clusters
  WHERE norm IN (SELECT norm FROM clusters GROUP BY norm HAVING COUNT(*) > 1)
),
keepers AS (SELECT norm, id AS keeper_id FROM ranked WHERE rk = 1),
duplicates AS (
  SELECT r.id AS dup_id, k.keeper_id, r.name AS dup_name
  FROM ranked r JOIN keepers k USING (norm) WHERE r.rk > 1
)
-- Redirect every products reference from dup → keeper
UPDATE products p SET saas_brand_id = d.keeper_id
FROM duplicates d
WHERE p.saas_brand_id = d.dup_id;

-- Same redirect into stock_purchase_items if it stores saas_brand_id (no-op if column missing)
-- (skipped; we'll re-link via products which is the source of truth)

-- Soft-delete the non-canonical master rows
WITH clusters AS (
  SELECT regexp_replace(LOWER(TRIM(name)),'\s+',' ','g') AS norm,
         id, name,
         (SELECT COUNT(*) FROM products WHERE saas_brand_id = sb.id AND deleted_at IS NULL) AS prod_refs,
         length(name) AS namelen
  FROM saas_brands sb WHERE deleted_at IS NULL
),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY norm ORDER BY prod_refs DESC, namelen DESC, name DESC) AS rk
  FROM clusters
  WHERE norm IN (SELECT norm FROM clusters GROUP BY norm HAVING COUNT(*) > 1)
)
UPDATE saas_brands SET deleted_at = NOW(), updated_at = NOW()
WHERE id IN (SELECT id FROM ranked WHERE rk > 1);

-- ============================================================================
-- 2. SIZE-SUFFIX STRIP
-- ============================================================================

-- Strip trailing " 750 ML" / " 750ML" / "-330ML" / etc. from master names.
-- Pattern: optional space|dash, 2-4 digits, optional space, ml (any case),
-- optional space, end-of-string.
UPDATE saas_brands
SET name = regexp_replace(name, '\s*[\-\s]\s*\d{2,4}\s*ml\s*$', '', 'gi'),
    updated_at = NOW()
WHERE name ~* '\s*[\-\s]\s*\d{2,4}\s*ml\s*$'
  AND deleted_at IS NULL;

COMMIT;
