-- Migration 006: Add Cash Collection Approval Workflow
-- Date: 2025-01-16
-- Purpose: Add approval workflow with 10-minute expiration to cash collections

-- Add approval workflow columns to cash_collections
ALTER TABLE cash_collections ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP;
ALTER TABLE cash_collections ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMP;
ALTER TABLE cash_collections ADD COLUMN IF NOT EXISTS reject_reason TEXT;

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_cash_collections_expires_at ON cash_collections(expires_at);
CREATE INDEX IF NOT EXISTS idx_cash_collections_status_expires ON cash_collections(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_cash_collections_to_user_status ON cash_collections(to_user_id, status);

-- Update default status to 'pending' for new records
ALTER TABLE cash_collections ALTER COLUMN status SET DEFAULT 'pending';

-- Update existing auto-approved records (optional - for data consistency)
-- Mark old auto-approved collections as approved with proper timestamps
UPDATE cash_collections
SET
    expires_at = collection_date + INTERVAL '10 minutes',
    approved_at = collection_date,
    approved_by_id = created_by_id
WHERE
    status = 'approved'
    AND expires_at IS NULL;

-- Mark expired old records (created more than 10 minutes ago but not approved)
UPDATE cash_collections
SET
    status = 'expired',
    expires_at = collection_date + INTERVAL '10 minutes'
WHERE
    status = 'pending'
    AND collection_date < NOW() - INTERVAL '10 minutes'
    AND expires_at IS NULL;

-- Add comments for documentation
COMMENT ON COLUMN cash_collections.expires_at IS '10-minute deadline for approval of pending collection requests';
COMMENT ON COLUMN cash_collections.rejected_at IS 'Timestamp when collection request was rejected';
COMMENT ON COLUMN cash_collections.reject_reason IS 'Reason provided by approver for rejection';
COMMENT ON COLUMN cash_collections.status IS 'pending, approved, rejected, expired - approval workflow status';

-- Verify migration
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'cash_collections'
        AND column_name = 'expires_at'
    ) THEN
        RAISE EXCEPTION 'Migration failed: expires_at column not added';
    END IF;

    RAISE NOTICE 'Migration 006 completed successfully';
END $$;
