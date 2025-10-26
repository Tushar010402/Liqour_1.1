-- Migration: Make shop_id nullable in cash_holdings table
-- This allows users to hold cash without requiring shop assignment
-- Cash balances are user-specific, shop is optional metadata

-- Remove NOT NULL constraint from shop_id column
ALTER TABLE cash_holdings
ALTER COLUMN shop_id DROP NOT NULL;

-- Add comment explaining the change
COMMENT ON COLUMN cash_holdings.shop_id IS 'Optional shop ID - cash is user-specific, shop is metadata';
