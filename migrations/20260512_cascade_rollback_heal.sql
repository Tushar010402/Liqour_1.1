-- 2026-05-12 cascade-rollback heal
--
-- Reverses the corrupt 2026-05-11 06:15/06:18/06:23 UTC "Cascade alignment"
-- audit_heal_v1 chain that overwrote stocks.quantity for 99 products at 2
-- shops. Symptoms: Daily Sales Record 319389bb-b14f-4854-996d-5927eea6849b
-- cannot approve ("insufficient stock for product Black & White Celebration")
-- and Mahua Khera 2026-05-01 records look like deductions are missing.
--
-- Root cause: ad-hoc SQL run by user af831608 (bev.trinken@gmail.com) on
-- 2026-05-11. NOT from any code path — no file in the repo writes the
-- "Cascade alignment" reference string. Stock_reconciliation_service.go
-- writes a different (legitimate) reference. The cascade chain miscomputed
-- 97 product values, a v2 alignment touched 21 more, then a rewind tried
-- to undo it but didn't restore the pre-cascade legitimate state.
--
-- Restore formula:
--   correct_qty = pre_cascade_qty + sum(post-rewind legit movements)
-- where:
--   pre_cascade_qty = previous_quantity of the FIRST Cascade* row today for
--                     this (product, shop). This is the legitimate state
--                     after the innocent 04:46 worker-sweep + 06:03
--                     phantom-reject heal but before any bad cascade row.
--   post-rewind legit movements = sum of stock_histories.quantity for
--                                 daily_sale + purchase + opening_stock_setup
--                                 + manual_adjustment rows AFTER 06:23:45 UTC.
--                                 Preserves real sales/purchases that
--                                 happened after the rewind.
--
-- Dry-run summary: 99 products, 80 already correct, 19 need adjustment
-- (11 restore-up + 8 reduce-down), 0 would go negative, net change +38 units.
--
-- Run with:
--   docker exec -i liquorpro-postgres-prod psql -U liquorpro_prod \
--     -d liquorpro_production -f /docker-entrypoint-initdb.d/cascade_rollback_heal.sql
-- (or copy file into container first)

BEGIN;

CREATE TEMP TABLE _heal_plan ON COMMIT DROP AS
WITH first_cascade AS (
  SELECT product_id, shop_id, previous_quantity, created_at
  FROM stock_histories
  WHERE movement_type = 'audit_heal_v1'
    AND created_at >= '2026-05-11 00:00:00+00'
    AND (reference LIKE 'Cascade alignment%'
      OR reference LIKE 'Cascade-v2 alignment%'
      OR reference LIKE 'Cascade rewind%')
), first_touch AS (
  SELECT DISTINCT ON (product_id, shop_id)
         product_id, shop_id, previous_quantity AS pre_cascade_qty
  FROM first_cascade
  ORDER BY product_id, shop_id, created_at
), post_rewind_legit AS (
  SELECT sh.product_id, sh.shop_id, SUM(sh.quantity) AS post_legit_delta
  FROM stock_histories sh
  JOIN first_touch ft ON ft.product_id = sh.product_id AND ft.shop_id = sh.shop_id
  WHERE sh.created_at > '2026-05-11 06:23:45.333274+00'
    AND sh.movement_type IN ('daily_sale','purchase','opening_stock_setup','manual_adjustment')
  GROUP BY sh.product_id, sh.shop_id
)
SELECT ft.product_id, ft.shop_id, s.id AS stock_id, s.tenant_id,
       ft.pre_cascade_qty,
       COALESCE(prl.post_legit_delta, 0)                              AS post_legit_delta,
       ft.pre_cascade_qty + COALESCE(prl.post_legit_delta, 0)         AS correct_qty,
       s.quantity                                                     AS current_qty
FROM first_touch ft
LEFT JOIN post_rewind_legit prl
       ON prl.product_id = ft.product_id AND prl.shop_id = ft.shop_id
JOIN stocks s
       ON s.product_id = ft.product_id AND s.shop_id = ft.shop_id;

-- Safety assertions: nothing should go negative
DO $$
DECLARE neg_count INT;
BEGIN
  SELECT COUNT(*) INTO neg_count FROM _heal_plan WHERE correct_qty < 0;
  IF neg_count > 0 THEN
    RAISE EXCEPTION 'Cascade rollback heal would put % rows negative — aborting', neg_count;
  END IF;
END $$;

-- Apply
UPDATE stocks s
SET quantity   = hp.correct_qty,
    updated_at = NOW()
FROM _heal_plan hp
WHERE s.id = hp.stock_id
  AND hp.correct_qty <> hp.current_qty;

-- Audit row per restored product
INSERT INTO stock_histories
  (id, tenant_id, stock_id, shop_id, product_id, movement_type,
   quantity, previous_quantity, new_quantity,
   reference, notes,
   created_by_id, created_at, updated_at)
SELECT
  gen_random_uuid(), hp.tenant_id, hp.stock_id, hp.shop_id, hp.product_id,
  'audit_heal_v1_rollback',
  (hp.correct_qty - hp.current_qty),
  hp.current_qty,
  hp.correct_qty,
  'Cascade rollback 2026-05-12 — restored to pre-cascade legitimate state',
  'Reverses the corrupt 2026-05-11 06:15/06:18/06:23 UTC Cascade audit_heal_v1 chain. correct_qty = pre_cascade_qty (first Cascade* row previous_quantity) + sum(post-rewind daily_sale/purchase/setup deltas). Restores deduct-correct state so pending records (incl. 319389bb-b14f-4854-996d-5927eea6849b) can approve.',
  'af831608-bc06-45cd-a0e0-10a81db07b15',
  NOW(), NOW()
FROM _heal_plan hp
WHERE hp.correct_qty <> hp.current_qty;

-- Final proof rows for the log
SELECT 'changed_rows' AS metric, COUNT(*) AS value
  FROM _heal_plan WHERE correct_qty <> current_qty;

SELECT 'black_white_after_heal' AS metric, quantity AS value
  FROM stocks
 WHERE product_id = '28edc4fe-e23c-437b-a584-63d0768dc37d'
   AND shop_id    = 'c5cf581d-c879-4ca3-9a92-bc1d06be4967';

COMMIT;
