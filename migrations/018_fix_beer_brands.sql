-- Fix Beer Brands Migration
-- Updates prices, adds Haywards 5000, consolidates Ultra Max
-- Date: 2025-07-13

BEGIN;

-- 1. Fix Carlsberg Elephant 500ML price (150 → 160)
UPDATE brand_variants
SET selling_price = 160, mrp = 160
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'CARLSBERG ELEPHANT')
AND size = '500ML';

-- 2. Fix Tuborg Strong 500ML price (120 → 140)
UPDATE brand_variants
SET selling_price = 140, mrp = 140
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'TUBORG STRONG')
AND size = '500ML';

-- 3. Add Haywards 5000 brand and variant
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'HAYWARDS 5000', 'India''s iconic strong lager known for bold taste and red-gold branding', NULL, true, 108, NOW(), NOW())
ON CONFLICT (name) DO NOTHING;

DO $$
DECLARE
    beer_id UUID;
    normal_sub_id UUID;
    haywards_brand_id UUID;
BEGIN
    SELECT id INTO beer_id FROM brand_categories WHERE name = 'Beer' LIMIT 1;
    SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = beer_id AND name = 'Normal' LIMIT 1;
    SELECT id INTO haywards_brand_id FROM saas_brands WHERE name = 'HAYWARDS 5000';

    -- Only insert if variant doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM brand_variants
        WHERE brand_id = haywards_brand_id AND size = '500ML'
    ) THEN
        INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                                   government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
        VALUES (gen_random_uuid(), haywards_brand_id, beer_id, normal_sub_id, '500ML',
                'Strong Lager Beer - Standard bottle with red and gold label',
                0, 100, 120, 120,
                'https://drive.google.com/file/d/15riz_1YkeQGuy3a1Wa1Le4oyc5RsJsfB/view?usp=sharing',
                true, NOW(), NOW());
    END IF;
END $$;

-- 4. Consolidate ULTRA MAX into KINGFISHER ULTRA MAX
-- First, update the variant to point to KINGFISHER ULTRA MAX brand
DO $$
DECLARE
    ultra_max_id UUID;
    kingfisher_ultra_max_id UUID;
BEGIN
    SELECT id INTO ultra_max_id FROM saas_brands WHERE name = 'ULTRA MAX';
    SELECT id INTO kingfisher_ultra_max_id FROM saas_brands WHERE name = 'KINGFISHER ULTRA MAX';

    -- Only proceed if both brands exist and ULTRA MAX has variants
    IF ultra_max_id IS NOT NULL AND kingfisher_ultra_max_id IS NOT NULL THEN
        -- Move the 650ML variant from ULTRA MAX to KINGFISHER ULTRA MAX
        -- First check if KINGFISHER ULTRA MAX already has a 650ML
        IF NOT EXISTS (
            SELECT 1 FROM brand_variants
            WHERE brand_id = kingfisher_ultra_max_id AND size = '650ML'
        ) THEN
            UPDATE brand_variants
            SET brand_id = kingfisher_ultra_max_id
            WHERE brand_id = ultra_max_id AND size = '650ML';
        ELSE
            -- If it already exists, just delete the ULTRA MAX variant
            DELETE FROM brand_variants WHERE brand_id = ultra_max_id AND size = '650ML';
        END IF;

        -- Delete any remaining ULTRA MAX variants
        DELETE FROM brand_variants WHERE brand_id = ultra_max_id;

        -- Delete the ULTRA MAX brand
        DELETE FROM saas_brands WHERE id = ultra_max_id;
    END IF;
END $$;

COMMIT;

-- Verification
SELECT '=== BEER BRAND FIX SUMMARY ===' as info;

SELECT b.name, v.size, v.selling_price, v.buying_price
FROM saas_brands b
JOIN brand_variants v ON b.id = v.brand_id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer'
ORDER BY b.name, v.size DESC;

SELECT
    'Total Beer Brands' as metric,
    COUNT(*) as count
FROM saas_brands b
WHERE EXISTS (
    SELECT 1 FROM brand_variants v
    JOIN brand_categories c ON v.category_id = c.id
    WHERE v.brand_id = b.id AND c.name = 'Beer'
)
UNION ALL
SELECT
    'Total Beer Variants' as metric,
    COUNT(*) as count
FROM brand_variants v
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer';
