-- Migration: Fix cash_collections and cash_requests tables
-- Date: 2025-10-28
-- Description: Add missing columns to match Go models

-- ============================================
-- 1. Add shop_id column to cash_collections
-- ============================================
ALTER TABLE cash_collections
ADD COLUMN IF NOT EXISTS shop_id UUID;

-- Add foreign key constraint for shop_id
ALTER TABLE cash_collections
ADD CONSTRAINT fk_cash_collections_shop_id
FOREIGN KEY (shop_id) REFERENCES shops(id)
ON DELETE CASCADE;

-- Create index for shop_id queries
CREATE INDEX IF NOT EXISTS idx_cash_collections_shop_id
ON cash_collections(shop_id);

-- ============================================
-- 2. Add expires_at column to cash_collections
-- ============================================
ALTER TABLE cash_collections
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;

-- ============================================
-- 3. Add expires_at column to cash_requests
-- ============================================
ALTER TABLE cash_requests
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;

-- ============================================
-- 4. Update existing pending records with expiration
-- ============================================
-- Set 10-minute expiration for existing pending collections
UPDATE cash_collections
SET expires_at = created_at + INTERVAL '10 minutes'
WHERE status = 'pending' AND expires_at IS NULL;

-- Set 10-minute expiration for existing pending requests
UPDATE cash_requests
SET expires_at = created_at + INTERVAL '10 minutes'
WHERE status = 'pending' AND expires_at IS NULL;

-- ============================================
-- 5. Mark expired records
-- ============================================
-- Mark old pending collections as expired
UPDATE cash_collections
SET status = 'expired'
WHERE status = 'pending'
AND expires_at IS NOT NULL
AND expires_at < NOW();

-- Mark old pending requests as expired
UPDATE cash_requests
SET status = 'expired'
WHERE status = 'pending'
AND expires_at IS NOT NULL
AND expires_at < NOW();

-- ============================================
-- Verify changes
-- ============================================
-- This will show the updated table structure
-- \d cash_collections
-- \d cash_requests