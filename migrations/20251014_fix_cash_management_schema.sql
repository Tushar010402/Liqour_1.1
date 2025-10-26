-- ══════════════════════════════════════════════════════════════════════════════
-- Cash Management Schema Fix - Add Missing GORM Columns
-- Created: 2025-10-14
-- Purpose: Add id, created_at, updated_at, deleted_at columns to cash tables
-- ══════════════════════════════════════════════════════════════════════════════

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 1. Fix cash_holdings table
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Add deleted_at column for soft deletes (GORM standard)
ALTER TABLE cash_holdings
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

-- Add index on deleted_at for soft delete queries
CREATE INDEX IF NOT EXISTS idx_cash_holdings_deleted_at ON cash_holdings(deleted_at);

COMMENT ON COLUMN cash_holdings.deleted_at IS 'Soft delete timestamp (GORM standard)';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 2. Fix cash_collections table
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ALTER TABLE cash_collections
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_cash_collections_deleted_at ON cash_collections(deleted_at);

COMMENT ON COLUMN cash_collections.deleted_at IS 'Soft delete timestamp (GORM standard)';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 3. Fix cash_submissions table
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ALTER TABLE cash_submissions
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_cash_submissions_deleted_at ON cash_submissions(deleted_at);

COMMENT ON COLUMN cash_submissions.deleted_at IS 'Soft delete timestamp (GORM standard)';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 4. Fix cash_transactions table
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ALTER TABLE cash_transactions
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_cash_transactions_deleted_at ON cash_transactions(deleted_at);

COMMENT ON COLUMN cash_transactions.deleted_at IS 'Soft delete timestamp (GORM standard)';

-- ══════════════════════════════════════════════════════════════════════════════
-- Migration Complete
-- ══════════════════════════════════════════════════════════════════════════════

-- Verify all columns exist
DO $$
BEGIN
    -- Check cash_holdings
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'cash_holdings' AND column_name = 'deleted_at') THEN
        RAISE EXCEPTION 'cash_holdings.deleted_at column missing';
    END IF;

    -- Check cash_collections
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'cash_collections' AND column_name = 'deleted_at') THEN
        RAISE EXCEPTION 'cash_collections.deleted_at column missing';
    END IF;

    -- Check cash_submissions
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'cash_submissions' AND column_name = 'deleted_at') THEN
        RAISE EXCEPTION 'cash_submissions.deleted_at column missing';
    END IF;

    -- Check cash_transactions
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'cash_transactions' AND column_name = 'deleted_at') THEN
        RAISE EXCEPTION 'cash_transactions.deleted_at column missing';
    END IF;

    RAISE NOTICE '✅ All cash management tables have deleted_at columns';
END $$;
