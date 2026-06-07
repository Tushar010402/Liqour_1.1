-- v1.0.249 — Per-product Front/Back photo verification. Mirrors the schema we
-- added to stock_setup_items in v244 so any product (manual entry, auto-created
-- on Stock Setup apply, or existing pre-v244) can carry verified photos with
-- back-label MRP. Operator uploads + Gemini-verifies from the inventory edit
-- screen at any time.
--
-- Product model in pkg/shared/models/inventory.go ALREADY declares these
-- fields with explicit gorm:"column:..." tags since v244 — this migration is
-- the matching DB-side alter so INSERT/UPDATE stop being silently dropped by
-- the missing-column class of bug ([[feedback-liquorpro-gorm-column-drift]]).
BEGIN;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS front_image_url             TEXT,
  ADD COLUMN IF NOT EXISTS back_image_url              TEXT,
  ADD COLUMN IF NOT EXISTS back_image_mrp              NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS back_image_mrp_confidence   NUMERIC(4,3),
  ADD COLUMN IF NOT EXISTS verified_via_image_front    BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS verified_via_image_back     BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS photo_verified_at           TIMESTAMPTZ;

-- Index supports the "show me products that still need photos" inventory
-- filter without a sequential scan.
CREATE INDEX IF NOT EXISTS idx_products_photo_pending
  ON products (tenant_id, shop_id)
  WHERE deleted_at IS NULL
    AND (verified_via_image_front IS NOT TRUE OR verified_via_image_back IS NOT TRUE);

COMMIT;
