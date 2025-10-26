-- Migration: Make shop_id nullable in cash_transactions table
-- This allows cash transactions without requiring shop assignment
-- Audit trails are user-specific, shop is optional metadata

-- Remove NOT NULL constraint from shop_id column
ALTER TABLE cash_transactions
ALTER COLUMN shop_id DROP NOT NULL;

-- Add comment explaining the change
COMMENT ON COLUMN cash_transactions.shop_id IS 'Optional shop ID - transactions are user-specific, shop is metadata';
