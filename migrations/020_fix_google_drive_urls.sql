-- Fix Google Drive URLs for Direct Image Access
-- Converts sharing URLs to direct download URLs
-- FROM: https://drive.google.com/file/d/FILE_ID/view?usp=sharing
-- TO: https://drive.google.com/uc?export=view&id=FILE_ID
-- Date: 2025-07-13

BEGIN;

-- Update brand_variants table (SaaS level)
UPDATE brand_variants
SET picture = 'https://drive.google.com/uc?export=view&id=' ||
    SUBSTRING(picture FROM 'file/d/([^/]+)/')
WHERE picture LIKE '%drive.google.com/file/d/%'
AND picture NOT LIKE '%uc?export=view%';

-- Update products table (Tenant level)
UPDATE products
SET image_url = 'https://drive.google.com/uc?export=view&id=' ||
    SUBSTRING(image_url FROM 'file/d/([^/]+)/')
WHERE image_url LIKE '%drive.google.com/file/d/%'
AND image_url NOT LIKE '%uc?export=view%';

COMMIT;

-- Verification
SELECT '=== URL CONVERSION SUMMARY ===' as info;

SELECT
    'Brand Variants with Direct URLs' as metric,
    COUNT(*) as count
FROM brand_variants
WHERE picture LIKE '%uc?export=view%';

SELECT
    'Tenant Products with Direct URLs' as metric,
    COUNT(*) as count
FROM products
WHERE image_url LIKE '%uc?export=view%';

-- Show sample converted URLs
SELECT 'Sample Converted Brand Variant URLs:' as info;
SELECT
    b.name as brand,
    v.size,
    v.picture as new_url
FROM brand_variants v
JOIN saas_brands b ON v.brand_id = b.id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer'
AND v.picture LIKE '%uc?export=view%'
LIMIT 5;

SELECT 'Sample Converted Product URLs:' as info;
SELECT
    name,
    image_url as new_url
FROM products
WHERE image_url LIKE '%uc?export=view%'
LIMIT 5;
