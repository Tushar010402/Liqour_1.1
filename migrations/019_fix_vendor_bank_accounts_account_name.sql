-- Migration: Fix vendor_bank_accounts - Remove old account_name column
-- Description: Drop account_name column and ensure account_holder/account_holder_name are NOT NULL to match Go model
-- Date: 2025-10-28

BEGIN;

-- First, ensure new columns have data by copying from account_name if they're null
UPDATE vendor_bank_accounts
SET
  account_holder = COALESCE(account_holder, account_name),
  account_holder_name = COALESCE(account_holder_name, account_name)
WHERE account_holder IS NULL OR account_holder_name IS NULL;

-- Now make account_holder and account_holder_name NOT NULL (to match Go model)
ALTER TABLE vendor_bank_accounts
  ALTER COLUMN account_holder SET NOT NULL,
  ALTER COLUMN account_holder_name SET NOT NULL;

-- Drop the old account_name column (no longer used by backend)
ALTER TABLE vendor_bank_accounts
  DROP COLUMN IF EXISTS account_name;

-- Ensure created_by is NOT NULL (matches Go model)
-- First set a default for existing rows (use a system UUID or the tenant admin)
UPDATE vendor_bank_accounts
SET created_by = tenant_id
WHERE created_by IS NULL;

ALTER TABLE vendor_bank_accounts
  ALTER COLUMN created_by SET NOT NULL;

COMMIT;

-- Record migration
INSERT INTO schema_migrations (version, name, applied_at, success)
VALUES ('019', 'fix_vendor_bank_accounts_account_name', NOW(), true)
ON CONFLICT (version) DO NOTHING;
