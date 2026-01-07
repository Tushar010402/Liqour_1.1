-- Complete Cleanup Script
-- Removes all brands and brand-related data

BEGIN;

-- Disable foreign key checks
SET session_replication_role = 'replica';

-- Step 1: Remove all tenant-specific brand data
DELETE FROM tenant_brand_variants WHERE 1=1;
DELETE FROM tenant_brands WHERE 1=1;

-- Step 2: Remove all product-brand associations
UPDATE products SET brand_id = NULL WHERE brand_id IS NOT NULL;

-- Step 3: Remove all brand variants
DELETE FROM brand_variants WHERE 1=1;

-- Step 4: Remove all master brands
DELETE FROM saas_brands WHERE 1=1;

-- Step 5: Remove any old brands table entries
DELETE FROM brands WHERE 1=1;

-- Re-enable foreign key checks
SET session_replication_role = 'origin';

COMMIT;

-- Verification
SELECT 'Cleanup Complete' as status,
       (SELECT COUNT(*) FROM saas_brands) as saas_brands_count,
       (SELECT COUNT(*) FROM brand_variants) as variants_count,
       (SELECT COUNT(*) FROM tenant_brands) as tenant_brands_count;