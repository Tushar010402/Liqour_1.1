-- Migration: Fix vendor_bank_accounts table schema
-- Description: Add missing columns to match VendorBankAccount Go model
-- Date: 2025-10-28

BEGIN;

-- Add missing columns
ALTER TABLE vendor_bank_accounts
  ADD COLUMN IF NOT EXISTS account_holder VARCHAR(255),
  ADD COLUMN IF NOT EXISTS account_holder_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS branch_code VARCHAR(255),
  ADD COLUMN IF NOT EXISTS swift_code VARCHAR(255),
  ADD COLUMN IF NOT EXISTS is_default BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_by UUID;

-- Migrate existing data from old columns to new ones
UPDATE vendor_bank_accounts
SET
  account_holder = COALESCE(account_holder, account_name),
  account_holder_name = COALESCE(account_holder_name, account_name),
  branch_code = COALESCE(branch_code, branch)
WHERE account_holder IS NULL OR account_holder_name IS NULL OR branch_code IS NULL;

-- Add foreign key constraint for created_by
ALTER TABLE vendor_bank_accounts
  ADD CONSTRAINT fk_vendor_bank_accounts_created_by
  FOREIGN KEY (created_by) REFERENCES users(id)
  ON DELETE SET NULL;

-- Create index for created_by
CREATE INDEX IF NOT EXISTS idx_vendor_bank_accounts_created_by
  ON vendor_bank_accounts(created_by);

COMMENT ON COLUMN vendor_bank_accounts.account_holder IS 'Account holder name (matches model AccountHolder field)';
COMMENT ON COLUMN vendor_bank_accounts.account_holder_name IS 'Account holder full name (matches model AccountHolderName field)';
COMMENT ON COLUMN vendor_bank_accounts.branch_code IS 'Bank branch code';
COMMENT ON COLUMN vendor_bank_accounts.swift_code IS 'International SWIFT code for the bank';
COMMENT ON COLUMN vendor_bank_accounts.is_default IS 'Whether this is the default bank account for the vendor';
COMMENT ON COLUMN vendor_bank_accounts.created_by IS 'User who created this bank account record';

COMMIT;
