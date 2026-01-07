-- Migration: Add receipt_url column to cash_deposits table
-- This supports the Flutter app's cash submission feature which includes receipt photo uploads

-- Add receipt_url column for storing uploaded receipt image URLs
ALTER TABLE cash_deposits ADD COLUMN IF NOT EXISTS receipt_url TEXT;

-- Make shop_id nullable (Flutter app may not always have shop context)
ALTER TABLE cash_deposits ALTER COLUMN shop_id DROP NOT NULL;

-- Add index on status for faster filtering of pending deposits
CREATE INDEX IF NOT EXISTS idx_cash_deposits_status ON cash_deposits(status);

-- Add index on created_at for pagination queries
CREATE INDEX IF NOT EXISTS idx_cash_deposits_created_at ON cash_deposits(created_at DESC);
