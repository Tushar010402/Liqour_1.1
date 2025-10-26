-- Migration: Add salesman_id column to daily_sales_records table
-- Description: Adds optional salesman_id column to track which salesman made the daily sales record
-- Date: 2025-10-12

-- Add salesman_id column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'daily_sales_records'
        AND column_name = 'salesman_id'
    ) THEN
        ALTER TABLE daily_sales_records
        ADD COLUMN salesman_id UUID;

        RAISE NOTICE 'Added salesman_id column to daily_sales_records table';
    ELSE
        RAISE NOTICE 'Column salesman_id already exists in daily_sales_records table';
    END IF;
END $$;

-- Add foreign key constraint if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_daily_sales_records_salesman'
        AND table_name = 'daily_sales_records'
    ) THEN
        -- Only add foreign key if salesmen table exists
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'salesmen') THEN
            ALTER TABLE daily_sales_records
            ADD CONSTRAINT fk_daily_sales_records_salesman
            FOREIGN KEY (salesman_id) REFERENCES salesmen(id) ON DELETE SET NULL;

            RAISE NOTICE 'Added foreign key constraint for salesman_id';
        ELSE
            RAISE NOTICE 'Salesmen table does not exist, skipping foreign key constraint';
        END IF;
    ELSE
        RAISE NOTICE 'Foreign key constraint already exists';
    END IF;
END $$;

-- Create index on salesman_id for better query performance
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'daily_sales_records'
        AND indexname = 'idx_daily_sales_records_salesman_id'
    ) THEN
        CREATE INDEX idx_daily_sales_records_salesman_id
        ON daily_sales_records(salesman_id);

        RAISE NOTICE 'Created index on salesman_id';
    ELSE
        RAISE NOTICE 'Index on salesman_id already exists';
    END IF;
END $$;

-- Display summary
SELECT
    'Migration completed successfully!' as message,
    EXISTS(SELECT 1 FROM information_schema.columns
           WHERE table_name = 'daily_sales_records'
           AND column_name = 'salesman_id') as salesman_id_column_exists,
    EXISTS(SELECT 1 FROM information_schema.table_constraints
           WHERE constraint_name = 'fk_daily_sales_records_salesman') as foreign_key_exists,
    EXISTS(SELECT 1 FROM pg_indexes
           WHERE tablename = 'daily_sales_records'
           AND indexname = 'idx_daily_sales_records_salesman_id') as index_exists;
