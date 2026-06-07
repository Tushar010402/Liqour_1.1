-- v1.0.252 — Durable Stock-Setup photo↔row binding.
--
-- VerifyRow writes a row to stock_setup_image_verifications on every capture
-- (file + audit, even cache hits) but the photo only reaches stock_setup_items
-- (what the admin reads) if the Flutter app relays the URL in the volatile
-- submit payload. Partial submit / app-kill / re-extract drops that relay, so
-- the file + audit row survive on the server but the admin shows "no photo".
--
-- There was no stable server-side key tying a captured photo to its row: the
-- record stores session_id (varchar), but the audit table only had job_id
-- (UUID) — and Flutter passes the varchar session id there, so the INSERT's
-- NULLIF(?, '0000…')::uuid cast nulls it. These columns are plain VARCHAR/INT
-- (NO uuid cast) so the durable key — (tenant_id, session_id, page_number,
-- row_number, face) — actually persists. Backfill keyed on this is EXACT
-- (physical register position), so no fuzzy brand matching / mis-association.
BEGIN;

ALTER TABLE stock_setup_image_verifications
  ADD COLUMN IF NOT EXISTS session_id  VARCHAR(255),
  ADD COLUMN IF NOT EXISTS row_number  INT,
  ADD COLUMN IF NOT EXISTS page_number INT;

-- Supports the per-record backfill lookup (latest front/back per row) without
-- a sequential scan over the audit table.
CREATE INDEX IF NOT EXISTS idx_ssiv_session_row
  ON stock_setup_image_verifications (tenant_id, session_id, page_number, row_number, face)
  WHERE session_id IS NOT NULL;

COMMIT;
