-- Migration: Fix cash_collections table - Add all missing columns
-- Description: Add approved_by_id, rejected_at, reject_reason, created_by_id to match CashCollection Go model
-- Date: 2025-10-28

BEGIN;

-- Add missing columns
ALTER TABLE cash_collections
  ADD COLUMN IF NOT EXISTS approved_by_id UUID,
  ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS created_by_id UUID;

-- Add foreign key constraints
ALTER TABLE cash_collections
  ADD CONSTRAINT fk_cash_collections_approved_by_id
  FOREIGN KEY (approved_by_id) REFERENCES users(id)
  ON DELETE SET NULL;

ALTER TABLE cash_collections
  ADD CONSTRAINT fk_cash_collections_created_by_id
  FOREIGN KEY (created_by_id) REFERENCES users(id)
  ON DELETE RESTRICT;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_cash_collections_approved_by_id
  ON cash_collections(approved_by_id)
  WHERE approved_by_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cash_collections_created_by_id
  ON cash_collections(created_by_id);

CREATE INDEX IF NOT EXISTS idx_cash_collections_status
  ON cash_collections(status);

-- Migrate existing data: set created_by_id from from_user_id where null
UPDATE cash_collections
SET created_by_id = from_user_id
WHERE created_by_id IS NULL;

COMMENT ON COLUMN cash_collections.approved_by_id IS 'User who approved this cash collection';
COMMENT ON COLUMN cash_collections.rejected_at IS 'Timestamp when collection was rejected';
COMMENT ON COLUMN cash_collections.reject_reason IS 'Reason for rejection';
COMMENT ON COLUMN cash_collections.created_by_id IS 'User who created this cash collection';

COMMIT;
