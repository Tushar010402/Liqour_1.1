-- Migration: Remove all existing brand data
-- Purpose: Clean slate for new 39-brand catalog
-- Date: 2025-11-19

BEGIN;

-- Disable foreign key checks temporarily
SET session_replication_role = 'replica';

-- Step 1: Remove tenant-specific brand data
DELETE FROM tenant_brand_variants WHERE 1=1;
DELETE FROM tenant_brands WHERE 1=1;

-- Step 2: Remove any product-brand associations (if exists)
UPDATE products SET brand_id = NULL WHERE brand_id IS NOT NULL;

-- Step 3: Remove brand variants
DELETE FROM brand_variants WHERE 1=1;

-- Step 4: Remove master brands
DELETE FROM saas_brands WHERE 1=1;

-- Step 5: Remove old brands table entries (if any)
DELETE FROM brands WHERE 1=1;

-- Re-enable foreign key checks
SET session_replication_role = 'origin';

-- Reset sequences if needed
ALTER SEQUENCE IF EXISTS saas_brands_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS brand_variants_id_seq RESTART WITH 1;

COMMIT;

-- Verification query
SELECT
    (SELECT COUNT(*) FROM saas_brands) as saas_brands_count,
    (SELECT COUNT(*) FROM brand_variants) as brand_variants_count,
    (SELECT COUNT(*) FROM tenant_brands) as tenant_brands_count;