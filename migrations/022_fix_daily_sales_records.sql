-- Migration 022: Fix daily_sales_records table schema
-- Adds missing columns for payment breakdown tracking
-- Date: 2025-11-21

-- Add missing columns to daily_sales_records table
ALTER TABLE daily_sales_records
ADD COLUMN IF NOT EXISTS total_sales_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_cash_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_card_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_upi_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_credit_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS record_date DATE,
ADD COLUMN IF NOT EXISTS salesman_id UUID,
ADD COLUMN IF NOT EXISTS approved_by_id UUID,
ADD COLUMN IF NOT EXISTS created_by_id UUID,
ADD COLUMN IF NOT EXISTS notes TEXT,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP;

-- Migrate existing data from old columns to new columns
UPDATE daily_sales_records
SET total_sales_amount = COALESCE(total_amount, 0),
    record_date = COALESCE(date, CURRENT_DATE),
    created_by_id = created_by,
    approved_by_id = approved_by
WHERE total_sales_amount IS NULL OR total_sales_amount = 0;

-- Add foreign key constraints if they don't exist
DO $$
BEGIN
    -- Add salesman_id foreign key
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'daily_sales_records_salesman_id_fkey'
    ) THEN
        ALTER TABLE daily_sales_records
        ADD CONSTRAINT daily_sales_records_salesman_id_fkey
        FOREIGN KEY (salesman_id) REFERENCES users(id);
    END IF;

    -- Add approved_by_id foreign key
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'daily_sales_records_approved_by_id_fkey'
    ) THEN
        ALTER TABLE daily_sales_records
        ADD CONSTRAINT daily_sales_records_approved_by_id_fkey
        FOREIGN KEY (approved_by_id) REFERENCES users(id);
    END IF;

    -- Add created_by_id foreign key
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'daily_sales_records_created_by_id_fkey'
    ) THEN
        ALTER TABLE daily_sales_records
        ADD CONSTRAINT daily_sales_records_created_by_id_fkey
        FOREIGN KEY (created_by_id) REFERENCES users(id);
    END IF;
END $$;

-- Create index on record_date for performance
CREATE INDEX IF NOT EXISTS idx_daily_sales_records_record_date ON daily_sales_records(record_date);
CREATE INDEX IF NOT EXISTS idx_daily_sales_records_salesman_id ON daily_sales_records(salesman_id);
