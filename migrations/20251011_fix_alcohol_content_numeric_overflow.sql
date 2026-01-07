-- Migration: Fix alcohol_content numeric field overflow
-- Date: 2025-10-11
-- Issue: alcohol_content NUMERIC(5,2) can only hold values up to 999.99
--        This causes overflow when storing duty amounts like 1200.0, 2400.0
-- Solution: Change to NUMERIC(10,2) to accommodate duty amounts up to 99,999,999.99

-- Alter products table (not tenant_products)
ALTER TABLE products
ALTER COLUMN alcohol_content TYPE NUMERIC(10,2);

-- Verify the change
DO $$
BEGIN
    RAISE NOTICE 'alcohol_content column updated to NUMERIC(10,2)';
    RAISE NOTICE 'Can now store duty amounts up to 99,999,999.99';
END $$;
