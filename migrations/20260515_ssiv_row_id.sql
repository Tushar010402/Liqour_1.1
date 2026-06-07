-- v1.0.255 — Resilient Stock-Setup photo recovery.
--
-- v252's durable key (session_id/row_number/page_number) requires an updated
-- app and is NULL on 100% of audit rows because the operator runs a stale
-- APK. The Flutter row_id (= _ReviewProduct.id) is, however, a REQUIRED
-- verify-row form field on EVERY app version since v243 — it is already
-- embedded in image_url as `…/{rowID}-{face}-{ts}.jpg`. Persisting it in its
-- own column lets the record builder bind photos→items by exact key (matched
-- rows: rowID==product_id; auto rows: rowID `auto_<rownum>_` → ai_row_number)
-- WITHOUT depending on the app being updated. Existing rows are recovered by
-- regexing image_url, so no data migration is needed — this column is just
-- forward cleanliness.
BEGIN;

ALTER TABLE stock_setup_image_verifications
  ADD COLUMN IF NOT EXISTS row_id TEXT;

COMMIT;
