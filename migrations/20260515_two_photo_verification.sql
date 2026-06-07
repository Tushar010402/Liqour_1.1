-- v1.0.244 — Two-photo (Front + Back) verification per Stock Setup row.
-- Back photo extracts MRP via Gemini. Apply gate requires BOTH photos verified.
-- The v1.0.243 columns (verified_image_url, verified_via_image) are kept for
-- backward compat during the rollout window.

BEGIN;

-- Per-row carriers on stock_setup_items.
ALTER TABLE stock_setup_items
  ADD COLUMN IF NOT EXISTS front_image_url           TEXT,
  ADD COLUMN IF NOT EXISTS back_image_url            TEXT,
  ADD COLUMN IF NOT EXISTS back_image_mrp            NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS back_image_mrp_confidence NUMERIC(4,3),
  ADD COLUMN IF NOT EXISTS verified_via_image_front  BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS verified_via_image_back   BOOLEAN DEFAULT FALSE;

-- Audit table extension — which face was verified + the back-MRP extracted.
ALTER TABLE stock_setup_image_verifications
  ADD COLUMN IF NOT EXISTS face          TEXT DEFAULT 'front',
  ADD COLUMN IF NOT EXISTS extracted_mrp NUMERIC(10,2);

-- Index for cost-telemetry queries split by face.
CREATE INDEX IF NOT EXISTS idx_stock_setup_image_verifications_face
  ON stock_setup_image_verifications(tenant_id, face, created_at DESC);

COMMIT;
