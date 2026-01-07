-- Migration: Fix bank_transactions table columns
-- Description: Add missing columns and rename old ones to match current schema
-- Date: 2025-10-26
-- Issue: Backend expects balance_before, balance_after, od_used_before, od_used_after
--        but table has previous_balance, new_balance

-- ============================================================================
-- Step 1: Add new columns
-- ============================================================================

-- Add balance_before and balance_after columns
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'balance_before'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN balance_before DECIMAL(15, 2);

        RAISE NOTICE 'Added column balance_before';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'balance_after'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN balance_after DECIMAL(15, 2);

        RAISE NOTICE 'Added column balance_after';
    END IF;
END $$;

-- Add OD tracking columns
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'od_used_before'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN od_used_before DECIMAL(15, 2) DEFAULT 0.00;

        RAISE NOTICE 'Added column od_used_before';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'od_used_after'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN od_used_after DECIMAL(15, 2) DEFAULT 0.00;

        RAISE NOTICE 'Added column od_used_after';
    END IF;
END $$;

-- ============================================================================
-- Step 2: Copy data from old columns to new columns (if old columns exist)
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'previous_balance'
    ) THEN
        UPDATE bank_transactions
        SET balance_before = previous_balance
        WHERE balance_before IS NULL AND previous_balance IS NOT NULL;

        RAISE NOTICE 'Copied previous_balance to balance_before';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'new_balance'
    ) THEN
        UPDATE bank_transactions
        SET balance_after = new_balance
        WHERE balance_after IS NULL AND new_balance IS NOT NULL;

        RAISE NOTICE 'Copied new_balance to balance_after';
    END IF;
END $$;

-- ============================================================================
-- Step 3: Add reference columns if they don't exist
-- ============================================================================

DO $$
BEGIN
    -- Add reference_type if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'reference_type'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN reference_type VARCHAR(50);

        RAISE NOTICE 'Added column reference_type';
    END IF;

    -- Add reference_id if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'reference_id'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN reference_id UUID;

        RAISE NOTICE 'Added column reference_id';
    END IF;

    -- Rename bank_reference_number to bank_reference_no if needed
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'bank_reference_no'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'bank_reference_number'
    ) THEN
        ALTER TABLE bank_transactions
        RENAME COLUMN bank_reference_number TO bank_reference_no;

        RAISE NOTICE 'Renamed bank_reference_number to bank_reference_no';
    END IF;

    -- Add bank_reference_no if neither column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name IN ('bank_reference_no', 'bank_reference_number')
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN bank_reference_no VARCHAR(100);

        RAISE NOTICE 'Added column bank_reference_no';
    END IF;

    -- Add notes column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'notes'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN notes TEXT;

        RAISE NOTICE 'Added column notes';
    END IF;

    -- Add reconciliation_id if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'reconciliation_id'
    ) THEN
        ALTER TABLE bank_transactions
        ADD COLUMN reconciliation_id UUID;

        RAISE NOTICE 'Added column reconciliation_id';
    END IF;
END $$;

-- ============================================================================
-- Step 4: Make description nullable (it's required in current table)
-- ============================================================================

ALTER TABLE bank_transactions
ALTER COLUMN description DROP NOT NULL;

RAISE NOTICE 'Made description column nullable';

-- ============================================================================
-- Step 5: Update created_by_id to created_by if needed
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'created_by'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'bank_transactions'
        AND column_name = 'created_by_id'
    ) THEN
        ALTER TABLE bank_transactions
        RENAME COLUMN created_by_id TO created_by;

        RAISE NOTICE 'Renamed created_by_id to created_by';
    END IF;
END $$;

-- ============================================================================
-- Verification
-- ============================================================================

DO $$
DECLARE
    col_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO col_count
    FROM information_schema.columns
    WHERE table_name = 'bank_transactions'
    AND column_name IN ('balance_before', 'balance_after', 'od_used_before', 'od_used_after');

    IF col_count = 4 THEN
        RAISE NOTICE '✅ SUCCESS: All required columns exist in bank_transactions table';
    ELSE
        RAISE WARNING '⚠️ Only % out of 4 required columns were added', col_count;
    END IF;
END $$;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN bank_transactions.balance_before IS 'Account balance before this transaction';
COMMENT ON COLUMN bank_transactions.balance_after IS 'Account balance after this transaction';
COMMENT ON COLUMN bank_transactions.od_used_before IS 'OD amount used before this transaction';
COMMENT ON COLUMN bank_transactions.od_used_after IS 'OD amount used after this transaction';
