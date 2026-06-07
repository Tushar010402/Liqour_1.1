-- 2026-05-02: heal stale audit snapshots written by pre-v1.0.132
-- ApproveDailySalesRecord. The buggy approve loop wrote
--   daily_sales_items.closing_stock = opening_stock
--   stock_histories.new_quantity    = previous_quantity
-- even though stocks.quantity was deducted correctly. So inventory was always
-- right — only the per-row audit/snapshot columns are wrong on records
-- approved before 2026-05-01 21:57 UTC (the v1.0.132 image build).
--
-- Two predicates encode the bug shape exactly. Both UPDATEs are self-gated,
-- so this migration is safe to re-run and harms no clean rows. The assertion
-- block at the end fails the migration (and rolls back the transaction) if
-- any buggy row remains.

BEGIN;

DO $heal_pre$
DECLARE n_items int; n_hist int;
BEGIN
  SELECT count(*) INTO n_items
    FROM daily_sales_items
   WHERE quantity > 0
     AND opening_stock = closing_stock
     AND opening_stock >= quantity;
  SELECT count(*) INTO n_hist
    FROM stock_histories
   WHERE movement_type = 'daily_sale'
     AND quantity < 0
     AND previous_quantity = new_quantity;
  RAISE NOTICE 'heal: % daily_sales_items rows, % stock_histories rows queued for repair', n_items, n_hist;
END
$heal_pre$;

-- Heal #1: daily_sales_items.closing_stock
--   opening_stock + quantity (the sale qty) are both correct in DB; closing
--   is just opening - quantity. opening_stock >= quantity guards against
--   pathological data where the bug coincidentally matched legitimate state.
UPDATE daily_sales_items
   SET closing_stock = opening_stock - quantity,
       updated_at    = NOW()
 WHERE quantity > 0
   AND opening_stock = closing_stock
   AND opening_stock >= quantity;

-- Heal #2: stock_histories.new_quantity
--   previous_quantity + quantity (negative for sales) is the post-deduction
--   stock. Scoped to movement_type='daily_sale' so adjustments / restocks
--   that legitimately have prev=new (zero-delta audit rows) are untouched.
UPDATE stock_histories
   SET new_quantity = previous_quantity + quantity
 WHERE movement_type = 'daily_sale'
   AND quantity < 0
   AND previous_quantity = new_quantity;

DO $heal_post$
DECLARE bad_items int; bad_hist int;
BEGIN
  -- Mirror the heal predicate exactly: rows where opening>=quantity are the
  -- ones the bug could have hit. Rows with opening=closing=0 (or
  -- opening<quantity) are legitimate "no stock to deduct" Smart Sale states,
  -- not bug victims, and the heal correctly leaves them alone.
  SELECT count(*) INTO bad_items
    FROM daily_sales_items
   WHERE quantity > 0
     AND opening_stock = closing_stock
     AND opening_stock >= quantity;
  SELECT count(*) INTO bad_hist
    FROM stock_histories
   WHERE movement_type = 'daily_sale'
     AND quantity < 0
     AND previous_quantity = new_quantity;
  IF bad_items > 0 OR bad_hist > 0 THEN
    RAISE EXCEPTION 'heal verify failed: % broken daily_sales_items, % broken stock_histories remain', bad_items, bad_hist;
  END IF;
  RAISE NOTICE 'heal: post-update verification clean';
END
$heal_post$;

COMMIT;
