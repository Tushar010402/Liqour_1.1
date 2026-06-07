-- v1.0.253 — Product photo+MRP change-request approval workflow.
--
-- Chhotu (role=executive) could never see the inventory Brand Photos & MRP
-- editor because it was hard-gated to admin/manager. Policy: every role can
-- use it; photos apply immediately for all; an MRP change by a non-admin/
-- manager becomes a PENDING request that admin/manager approve (mirrors the
-- proven Stock Setup pending→approve/reject pattern). This table holds those
-- pending MRP requests. Photo changes do NOT use this table (immediate).
--
-- Idempotent (run_migrations.sh tracks version+checksum; IF NOT EXISTS here
-- too for manual re-apply safety).
BEGIN;

CREATE TABLE IF NOT EXISTS product_change_requests (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          UUID NOT NULL,
  shop_id            UUID,
  product_id         UUID NOT NULL,

  -- Proposed change. Only MRP is gated (photos are immediate). current_mrp is
  -- snapshotted at request time so the approver sees old→new.
  proposed_mrp       NUMERIC(10,2) NOT NULL,
  current_mrp        NUMERIC(10,2),

  status             VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending|approved|rejected

  requested_by_id    UUID NOT NULL,
  requested_by_name  VARCHAR(255),
  requested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  approved_by_id     UUID,
  approved_by_name   VARCHAR(255),
  approved_at        TIMESTAMPTZ,
  rejection_reason   TEXT,

  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at         TIMESTAMPTZ
);

-- One OPEN pending request per (tenant, product): re-submitting an MRP just
-- updates the existing pending row instead of piling duplicates in the queue.
CREATE UNIQUE INDEX IF NOT EXISTS idx_pcr_one_open_per_product
  ON product_change_requests (tenant_id, product_id)
  WHERE status = 'pending' AND deleted_at IS NULL;

-- Admin list + sidebar pending-count badge.
CREATE INDEX IF NOT EXISTS idx_pcr_tenant_status
  ON product_change_requests (tenant_id, status, requested_at DESC)
  WHERE deleted_at IS NULL;

COMMIT;
