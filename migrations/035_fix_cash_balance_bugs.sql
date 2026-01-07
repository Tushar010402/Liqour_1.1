-- Migration: 035_fix_cash_balance_bugs.sql
-- Description: Fix cash balance bugs - add trigger for new users, backfill missing cash_holdings
-- Date: 2025-11-26

-- UP MIGRATION

-- 1. Create function to auto-create cash_holdings for new users
CREATE OR REPLACE FUNCTION create_cash_holding_for_user()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tenant_id IS NOT NULL AND NEW.role IN ('salesman', 'executive', 'assistant_manager', 'manager', 'admin', 'owner') THEN
        INSERT INTO cash_holdings (id, tenant_id, user_id, role, current_balance, created_at, updated_at)
        VALUES (gen_random_uuid(), NEW.tenant_id, NEW.id, NEW.role, 0, NOW(), NOW())
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Create trigger for new user creation
DROP TRIGGER IF EXISTS trigger_create_cash_holding ON users;
CREATE TRIGGER trigger_create_cash_holding
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION create_cash_holding_for_user();

-- 3. Create missing cash_holdings for existing users
-- Note: The unique constraint is on (user_id, shop_id), not (user_id, tenant_id)
INSERT INTO cash_holdings (id, tenant_id, user_id, role, current_balance, created_at, updated_at)
SELECT gen_random_uuid(), u.tenant_id, u.id, u.role, 0, NOW(), NOW()
FROM users u
WHERE u.tenant_id IS NOT NULL
  AND u.deleted_at IS NULL
  AND u.role IN ('salesman', 'executive', 'assistant_manager', 'manager', 'admin', 'owner')
  AND NOT EXISTS (
    SELECT 1 FROM cash_holdings ch
    WHERE ch.user_id = u.id
  )
ON CONFLICT DO NOTHING;

-- 4. Add index for faster cash_transactions queries (if not exists)
CREATE INDEX IF NOT EXISTS idx_cash_transactions_user_tenant
ON cash_transactions(user_id, tenant_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cash_transactions_type
ON cash_transactions(transaction_type);

-- 5. Mark all overdue pending requests as overdue (cleanup)
UPDATE money_collections
SET status = 'overdue'
WHERE status = 'pending'
  AND deadline_at < NOW()
  AND deleted_at IS NULL;

-- DOWN MIGRATION (run manually if rollback needed)
-- DROP TRIGGER IF EXISTS trigger_create_cash_holding ON users;
-- DROP FUNCTION IF EXISTS create_cash_holding_for_user();
