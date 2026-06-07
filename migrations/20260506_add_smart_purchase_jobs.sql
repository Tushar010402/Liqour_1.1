-- v1.0.188 — Smart Purchase async job queue
--
-- Goal: replace the synchronous /smart-purchase/extract endpoint with a
-- submit-and-poll pattern so multi-page invoice + gate-pass uploads no
-- longer time out at the nginx 60s gateway. The current synchronous path
-- runs 6+ parallel Gemini calls (50-60s each), reliably triggering 504s
-- on chhotu's class of 4-page invoice + 4-page gate-pass submissions.
--
-- Design: mirrors smart_sale_setup_jobs (the equivalent table in the sales
-- domain). Same columns, same lifecycle states, same indexes, same worker
-- claim pattern (FOR UPDATE SKIP LOCKED). One pattern, one set of bugs to fix.
--
-- Lifecycle: pending → processing → done | failed | canceled
-- Worker: 1 goroutine per inventory pod, poll every 3s, retry transient
-- failures up to 3x, outer per-job timeout 8 minutes.
--
-- Idempotent CREATE TABLE / CREATE INDEX so re-runs don't fail.

CREATE TABLE IF NOT EXISTS smart_purchase_jobs (
    -- BaseModel + TenantModel fields
    id UUID PRIMARY KEY,
    tenant_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,

    -- Actor context
    user_id UUID NOT NULL,
    shop_id UUID NOT NULL,

    -- Lifecycle
    status VARCHAR(32) NOT NULL DEFAULT 'pending',

    -- Input snapshot (kept reproducible from the row alone — no client state needed)
    shop_name TEXT,
    vendor_id UUID,

    -- Per-job image directory: /app/uploads/purchases/jobs/{job_id}/<kind>_N.<ext>
    invoice_image_paths   JSONB NOT NULL DEFAULT '[]'::jsonb,
    gate_pass_image_paths JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Output (populated only on status=done)
    result JSONB,

    -- Failure plumbing
    error_message TEXT,
    retry_count   INTEGER NOT NULL DEFAULT 0,

    -- Progress markers for polling UI
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- Worker SELECT … WHERE status='pending' is the hot path; index narrowly.
CREATE INDEX IF NOT EXISTS idx_smart_purchase_jobs_status
    ON smart_purchase_jobs(status)
    WHERE deleted_at IS NULL;

-- Tenant + user list queries (rendering the "active jobs" banner on app cold start).
CREATE INDEX IF NOT EXISTS idx_smart_purchase_jobs_tenant_user
    ON smart_purchase_jobs(tenant_id, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_smart_purchase_jobs_shop
    ON smart_purchase_jobs(shop_id);

CREATE INDEX IF NOT EXISTS idx_smart_purchase_jobs_deleted_at
    ON smart_purchase_jobs(deleted_at);
