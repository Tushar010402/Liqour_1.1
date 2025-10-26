-- Migration: Make shop_id nullable in cash_requests table
-- This allows cash requests to be user-to-user without requiring shop assignment

-- Remove NOT NULL constraint from shop_id column
ALTER TABLE cash_requests
ALTER COLUMN shop_id DROP NOT NULL;

-- Add comment explaining the change
COMMENT ON COLUMN cash_requests.shop_id IS 'Optional shop ID - cash is user-specific, shop is metadata';
