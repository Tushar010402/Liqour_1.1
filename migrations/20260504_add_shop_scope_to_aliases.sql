-- v1.0.160 — shop-scope OCR alias learning
--
-- Goal: make OCR alias matching shop-aware → tenant-aware → global, without
-- leaking aliases between shops at the same tenant.
--
-- Design: add nullable shop_id to ocr_brand_aliases AND ocr_negative_aliases.
--   shop_id IS NULL  → tenant-wide alias (legacy behaviour, still works)
--   shop_id NOT NULL → shop-scoped alias (only the shop that taught it sees
--                      it preferentially; tenant-wide rows still match too)
--
-- Backward compatible: every existing row stays NULL → continues to behave
-- as a tenant-wide entry. New writes from captureApplyLearning + sheet-grid
-- LookupAliasCascade will write shop_id = current shop. The matcher cascade
-- (in alias_service.go) consults shop-specific first, falls through to
-- tenant-wide.
--
-- Uniqueness: split the legacy single UNIQUE(tenant_id, alias_name) into
-- two partial unique indexes so shop and tenant rows can co-exist for the
-- same alias_name.

BEGIN;

-- 1. Schema additions ------------------------------------------------------

ALTER TABLE ocr_brand_aliases
    ADD COLUMN IF NOT EXISTS shop_id UUID NULL;

-- deleted_at was added in a previous unreleased migration referenced by
-- alias_hygiene_handler.go but not present in this directory. Make sure it
-- exists so the new lookup cascade's `deleted_at IS NULL` predicate doesn't
-- error on fresh installs. Column was added in the v133-r8 alias-hygiene
-- handler shipping; keep idempotent for safety.
ALTER TABLE ocr_brand_aliases
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;

ALTER TABLE ocr_negative_aliases
    ADD COLUMN IF NOT EXISTS shop_id UUID NULL;

-- 2. Replace the existing single UNIQUE constraint with two partial uniques
--    (one for tenant-scope rows, one for shop-scope rows).
--
-- The legacy constraint name is `unique_alias_per_tenant` (set by GORM
-- AutoMigrate via the OCRBrandAlias struct tag). We drop it if present and
-- recreate as partial uniques. ON CONFLICT (tenant_id, alias_name) clauses
-- in alias_service.go's INSERT statements need both partial indexes to
-- resolve correctly — we expose them under a stable predicate that the
-- ON CONFLICT target can specify (`WHERE shop_id IS NULL` /
-- `WHERE shop_id IS NOT NULL`). Postgres requires the index expression and
-- predicate to match the INSERT's ON CONFLICT clause exactly for the
-- partial index to be picked.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'unique_alias_per_tenant'
          AND conrelid = 'ocr_brand_aliases'::regclass
    ) THEN
        ALTER TABLE ocr_brand_aliases DROP CONSTRAINT unique_alias_per_tenant;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'unique_alias_per_tenant'
          AND tablename  = 'ocr_brand_aliases'
    ) THEN
        DROP INDEX IF EXISTS unique_alias_per_tenant;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ocr_brand_aliases_unique_tenant
    ON ocr_brand_aliases (tenant_id, alias_name)
    WHERE shop_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ocr_brand_aliases_unique_shop
    ON ocr_brand_aliases (tenant_id, shop_id, alias_name)
    WHERE shop_id IS NOT NULL;

-- Same treatment for ocr_negative_aliases. Legacy constraint is
-- UNIQUE(tenant_id, alias_name, rejected_product_id) declared in
-- 20260326_add_negative_aliases.sql.

DO $$
DECLARE
    cname TEXT;
BEGIN
    SELECT conname INTO cname
    FROM pg_constraint
    WHERE conrelid = 'ocr_negative_aliases'::regclass
      AND contype = 'u'
      AND conkey @> ARRAY[
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'ocr_negative_aliases'::regclass AND attname = 'tenant_id'),
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'ocr_negative_aliases'::regclass AND attname = 'alias_name'),
        (SELECT attnum FROM pg_attribute WHERE attrelid = 'ocr_negative_aliases'::regclass AND attname = 'rejected_product_id')
      ]
    LIMIT 1;
    IF cname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE ocr_negative_aliases DROP CONSTRAINT %I', cname);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ocr_negative_aliases_unique_tenant
    ON ocr_negative_aliases (tenant_id, alias_name, rejected_product_id)
    WHERE shop_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ocr_negative_aliases_unique_shop
    ON ocr_negative_aliases (tenant_id, shop_id, alias_name, rejected_product_id)
    WHERE shop_id IS NOT NULL;

-- 3. Lookup-cascade indexes -----------------------------------------------
-- (tenant_id, shop_id, lower(alias_name)) — covers shop-specific lookup.
-- (tenant_id, lower(alias_name))           — covers tenant-wide lookup
--                                            (already exists from earlier
--                                            migrations, but we rebuild for
--                                            safety).

CREATE INDEX IF NOT EXISTS idx_ocr_brand_aliases_lookup_shop
    ON ocr_brand_aliases (tenant_id, shop_id, LOWER(alias_name))
    WHERE shop_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_ocr_brand_aliases_lookup_tenant
    ON ocr_brand_aliases (tenant_id, LOWER(alias_name))
    WHERE shop_id IS NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_ocr_negative_aliases_lookup_shop
    ON ocr_negative_aliases (tenant_id, shop_id, LOWER(alias_name))
    WHERE shop_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ocr_negative_aliases_lookup_tenant
    ON ocr_negative_aliases (tenant_id, LOWER(alias_name))
    WHERE shop_id IS NULL;

COMMIT;
