-- 2026-05-17 — Fix uq_products_tenant_shop_brand_size structural defect.
--
-- ROOT CAUSE (found via the v1.0.272 console trace, record/job for tenant
-- 68ffde63 shop c5cf581d): the index was
--   UNIQUE (tenant_id, shop_id,
--           COALESCE(saas_brand_id, '000...0'::uuid),
--           regexp_replace(lower(coalesce(size,'')),'[^0-9a-z]','','g'))
--   WHERE deleted_at IS NULL AND shop_id IS NOT NULL
-- The COALESCE collapses EVERY uncatalogued (saas_brand_id IS NULL) product
-- to the zero-UUID, so a shop may physically hold only ONE uncatalogued
-- product per size. Creating a second distinct uncatalogued 750ml product
-- ("100 Step" while "Monkey Shoulder ... JECBA NES" already occupies the
-- slot) fails 23505 — and the app create pre-check keys on name, which can
-- never see this index's saas_brand-keyed collision. System-wide: 0 shops
-- in prod ever had >1 uncatalogued same-size product because the 2nd could
-- never be saved.
--
-- FIX: split into two correct partial unique indexes.
--   * mastered  -> dedup by saas_brand_id + size  (preserves the ORIGINAL
--                  catalog-dedup guarantee EXACTLY; the old index already
--                  enforced this superset, so build is conflict-free)
--   * uncatalogued -> dedup by lower(name) + size  (identical re-submits
--                  still dedup; distinct uncatalogued brands now coexist)
-- Verified before apply: mastered_dups=0, name_dups=0 (build cannot fail,
-- no dedup guarantee weakened for catalog-linked products).
--
-- Not GORM-managed (no source defines it); applied directly + recorded here
-- for reproducibility on other environments. Single transaction so the
-- dedup guarantee is never unprotected.
--
-- ROLLBACK (restores the original broken index — kept for completeness):
--   DROP INDEX IF EXISTS uq_products_tenant_shop_saasbrand_size;
--   DROP INDEX IF EXISTS uq_products_tenant_shop_name_size;
--   CREATE UNIQUE INDEX uq_products_tenant_shop_brand_size ON public.products
--     USING btree (tenant_id, shop_id,
--       COALESCE(saas_brand_id, '00000000-0000-0000-0000-000000000000'::uuid),
--       regexp_replace(lower((COALESCE(size, ''::character varying))::text),
--                      '[^0-9a-z]'::text, ''::text, 'g'::text))
--     WHERE ((deleted_at IS NULL) AND (shop_id IS NOT NULL));

BEGIN;

DROP INDEX IF EXISTS uq_products_tenant_shop_brand_size;

CREATE UNIQUE INDEX uq_products_tenant_shop_saasbrand_size
  ON public.products USING btree (
    tenant_id,
    shop_id,
    saas_brand_id,
    regexp_replace(lower((COALESCE(size, ''::character varying))::text),
                   '[^0-9a-z]'::text, ''::text, 'g'::text))
  WHERE (deleted_at IS NULL AND shop_id IS NOT NULL AND saas_brand_id IS NOT NULL);

CREATE UNIQUE INDEX uq_products_tenant_shop_name_size
  ON public.products USING btree (
    tenant_id,
    shop_id,
    lower(btrim((name)::text)),
    regexp_replace(lower((COALESCE(size, ''::character varying))::text),
                   '[^0-9a-z]'::text, ''::text, 'g'::text))
  WHERE (deleted_at IS NULL AND shop_id IS NOT NULL AND saas_brand_id IS NULL);

COMMIT;
