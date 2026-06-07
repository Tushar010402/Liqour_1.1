-- Migration: Add executive_shops join table
-- Purpose: Per-executive shop assignment so admins can scope an executive
--          to a subset of tenant shops (multi-shop access).
-- Date: 2026-04-28

CREATE TABLE IF NOT EXISTS executive_shops (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    shop_id     UUID NOT NULL REFERENCES shops(id)  ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ NULL,
    UNIQUE (user_id, shop_id)
);

CREATE INDEX IF NOT EXISTS idx_executive_shops_user      ON executive_shops(user_id);
CREATE INDEX IF NOT EXISTS idx_executive_shops_tenant    ON executive_shops(tenant_id);
CREATE INDEX IF NOT EXISTS idx_executive_shops_shop      ON executive_shops(shop_id);
CREATE INDEX IF NOT EXISTS idx_executive_shops_deleted   ON executive_shops(deleted_at);

COMMENT ON TABLE executive_shops IS
    'Maps executive-role users to the shops they are authorised to operate on.';

-- Backfill: keep current behaviour for existing executives by granting them
-- every active shop in their tenant. Admins can prune the list afterwards
-- via the new multi-select UI on /admin/m/staff.
INSERT INTO executive_shops (tenant_id, user_id, shop_id)
SELECT u.tenant_id, u.id, s.id
FROM users u
JOIN shops s
  ON s.tenant_id = u.tenant_id
 AND s.is_active = TRUE
 AND s.deleted_at IS NULL
WHERE u.role = 'executive'
  AND u.tenant_id IS NOT NULL
  AND u.deleted_at IS NULL
ON CONFLICT (user_id, shop_id) DO NOTHING;
