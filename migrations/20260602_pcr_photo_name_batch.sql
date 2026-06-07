-- v1.0.344 — Grow product_change_requests into a COMBINED photo / name / MRP
-- change-request, so an AI-Purchase photo-onboarding session surfaces as ONE
-- reviewable request on the web admin portal (bulk + per-item approve/reject).
--
-- DESIGN: forward-compatible with the existing MRP-only rows. Every new column
-- is nullable / defaulted and change_kind defaults to 'mrp', so the pre-existing
-- pending MRP requests + the existing /product-change-requests list and
-- approve/reject keep working byte-for-byte. The photo flow writes the new
-- columns (batch_id groups one capture session; name_applied/mrp_applied track
-- which fields were auto-applied at high confidence vs. still pending).
--
-- Idempotent (ADD COLUMN IF NOT EXISTS; run_migrations.sh tracks version+checksum).
BEGIN;

ALTER TABLE product_change_requests
  ADD COLUMN IF NOT EXISTS change_kind   VARCHAR(20) NOT NULL DEFAULT 'mrp',  -- mrp | name | name_mrp | photo
  ADD COLUMN IF NOT EXISTS proposed_name TEXT,                                 -- vision-read canonical name (proposal)
  ADD COLUMN IF NOT EXISTS current_name  TEXT,                                 -- product.name snapshot at request time
  ADD COLUMN IF NOT EXISTS batch_id      UUID,                                 -- groups one capture session = one combined request
  ADD COLUMN IF NOT EXISTS confidence    NUMERIC(4,3),                         -- image-read confidence 0..1
  ADD COLUMN IF NOT EXISTS auto_applied  BOOLEAN NOT NULL DEFAULT false,       -- any field applied immediately at high confidence
  ADD COLUMN IF NOT EXISTS name_applied  BOOLEAN NOT NULL DEFAULT false,       -- the name was auto-applied (confident); approve is a no-op for it
  ADD COLUMN IF NOT EXISTS mrp_applied   BOOLEAN NOT NULL DEFAULT false,       -- the MRP was auto-applied (confident)
  ADD COLUMN IF NOT EXISTS source        VARCHAR(40);                          -- e.g. 'photo_verify'

-- proposed_mrp was NOT NULL in the MRP-only world; a name-only change has no
-- MRP, so relax it. The Go model writes 0 for "no MRP change"; approve guards
-- on proposed_mrp > 0 so a name-only approval never zeroes a product's MRP.
ALTER TABLE product_change_requests ALTER COLUMN proposed_mrp DROP NOT NULL;

-- Group + list a combined request fast (one request = one batch_id).
CREATE INDEX IF NOT EXISTS idx_pcr_batch
  ON product_change_requests (tenant_id, batch_id, requested_at)
  WHERE deleted_at IS NULL AND batch_id IS NOT NULL;

COMMIT;
