-- Migration: Add approval workflow to stock_purchases
-- Date: 2025-12-03
-- Description: Adds approval workflow fields for stock purchase authorization

-- Add approval workflow columns to stock_purchases
ALTER TABLE stock_purchases
ADD COLUMN IF NOT EXISTS approved_by_id UUID REFERENCES users(id),
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN IF NOT EXISTS created_by_role VARCHAR(50);

-- Backfill: Set existing records as approved (legacy data)
-- This ensures existing purchases continue to work
UPDATE stock_purchases
SET approved_by_id = created_by,
    approved_at = created_at,
    submitted_at = COALESCE(submitted_at, created_at),
    created_by_role = 'admin',
    status = CASE
        WHEN status = 'received' THEN 'received'
        WHEN status = 'cancelled' THEN 'cancelled'
        ELSE 'approved'
    END
WHERE approved_by_id IS NULL;

-- Indexes for approval queries
CREATE INDEX IF NOT EXISTS idx_stock_purchases_status_pending
ON stock_purchases(tenant_id, status) WHERE status = 'pending' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_stock_purchases_approved_by
ON stock_purchases(approved_by_id) WHERE approved_by_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stock_purchases_submitted_at
ON stock_purchases(submitted_at DESC);

-- Add comment for documentation
COMMENT ON COLUMN stock_purchases.approved_by_id IS 'User who approved/rejected the purchase';
COMMENT ON COLUMN stock_purchases.approved_at IS 'Timestamp when purchase was approved/rejected';
COMMENT ON COLUMN stock_purchases.rejection_reason IS 'Reason for rejection if status is rejected';
COMMENT ON COLUMN stock_purchases.submitted_at IS 'Timestamp when purchase was submitted for approval';
COMMENT ON COLUMN stock_purchases.created_by_role IS 'Role of user at time of creation (for auto-approval logic)';
