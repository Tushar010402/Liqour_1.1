-- Migration: Fix cash_requests table - Add all missing columns
-- Description: Add shop_id, rejected_at, reject_reason, created_by_id to match CashRequest Go model
-- Date: 2025-10-28

BEGIN;

-- Add missing columns
ALTER TABLE cash_requests
  ADD COLUMN IF NOT EXISTS shop_id UUID,
  ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS created_by_id UUID;

-- Add foreign key constraints
ALTER TABLE cash_requests
  ADD CONSTRAINT fk_cash_requests_shop_id
  FOREIGN KEY (shop_id) REFERENCES shops(id)
  ON DELETE SET NULL;

ALTER TABLE cash_requests
  ADD CONSTRAINT fk_cash_requests_created_by_id
  FOREIGN KEY (created_by_id) REFERENCES users(id)
  ON DELETE RESTRICT;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_cash_requests_shop_id
  ON cash_requests(shop_id)
  WHERE shop_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cash_requests_created_by_id
  ON cash_requests(created_by_id);

CREATE INDEX IF NOT EXISTS idx_cash_requests_status
  ON cash_requests(status);

-- Migrate existing data: set created_by_id from requester_id where null
UPDATE cash_requests
SET created_by_id = requester_id
WHERE created_by_id IS NULL;

COMMENT ON COLUMN cash_requests.shop_id IS 'Optional shop association for cash request';
COMMENT ON COLUMN cash_requests.rejected_at IS 'Timestamp when request was rejected';
COMMENT ON COLUMN cash_requests.reject_reason IS 'Reason for rejection';
COMMENT ON COLUMN cash_requests.created_by_id IS 'User who created this cash request';

COMMIT;
