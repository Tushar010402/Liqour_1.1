-- Beer Brands Migration
-- Adds 11 unique beer brands with 17 product variants
-- Date: 2025-07-13

BEGIN;

-- Ensure Beer category exists
INSERT INTO brand_categories (id, name, description, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), 'Beer', 'Beer and lager products', true, NOW(), NOW())
ON CONFLICT (name) DO NOTHING;

-- Ensure subcategories exist for Beer
DO $$
DECLARE
    beer_id UUID;
BEGIN
    SELECT id INTO beer_id FROM brand_categories WHERE name = 'Beer' LIMIT 1;

    INSERT INTO brand_subcategories (id, name, category_id, description, is_active, created_at, updated_at)
    VALUES
        (gen_random_uuid(), 'Premium', beer_id, 'Premium beer variants', true, NOW(), NOW()),
        (gen_random_uuid(), 'Normal', beer_id, 'Regular beer variants', true, NOW(), NOW()),
        (gen_random_uuid(), 'Imported', beer_id, 'Imported beer brands', true, NOW(), NOW())
    ON CONFLICT DO NOTHING;
END $$;

-- Create 11 unique beer brands
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order, created_at, updated_at) VALUES
-- Multi-variant brands (5)
(gen_random_uuid(), 'BUDWEISER MAGNUM', 'Premium American lager beer with red-gold label and crown logo', NULL, true, 100, NOW(), NOW()),
(gen_random_uuid(), 'CARLSBERG ELEPHANT', 'Imported strong beer with distinctive elephant logo and green bottle', NULL, true, 101, NOW(), NOW()),
(gen_random_uuid(), 'KINGFISHER STRONG', 'India''s popular strong beer with iconic kingfisher bird logo', NULL, true, 102, NOW(), NOW()),
(gen_random_uuid(), 'TUBORG STRONG', 'Strong beer with recognizable green bottle and Tuborg crest', NULL, true, 103, NOW(), NOW()),
(gen_random_uuid(), 'KINGFISHER ULTRA MAX', 'Premium strong beer with bold styling and stylized label', NULL, true, 104, NOW(), NOW()),
(gen_random_uuid(), 'HOEGAARDEN', 'Imported Belgian wheat beer with white label and distinctive fonts', NULL, true, 105, NOW(), NOW()),

-- Single-variant brands (5)
(gen_random_uuid(), 'AMSTEL', 'Imported European lager with circular crest label', NULL, true, 106, NOW(), NOW()),
(gen_random_uuid(), 'GOD FATHER', 'Mass-market strong beer with bold label and dark bottle', NULL, true, 107, NOW(), NOW()),
(gen_random_uuid(), 'HAYWARDS 5000', 'India''s iconic strong lager known for bold taste and red-gold branding', NULL, true, 108, NOW(), NOW()),
(gen_random_uuid(), 'BRO CODE', 'Modern premium beer with compact bottle and distinctive label', NULL, true, 109, NOW(), NOW()),
(gen_random_uuid(), 'CORONA', 'Iconic imported beer with clear bottle, yellow label and lime association', NULL, true, 110, NOW(), NOW());

-- Create all 17 variants with pricing and images
DO $$
DECLARE
    brand RECORD;
    beer_id UUID;
    premium_sub_id UUID;
    normal_sub_id UUID;
    imported_sub_id UUID;
BEGIN
    -- Get Beer category ID
    SELECT id INTO beer_id FROM brand_categories WHERE name = 'Beer' LIMIT 1;

    -- Get subcategory IDs
    SELECT id INTO premium_sub_id FROM brand_subcategories WHERE category_id = beer_id AND name = 'Premium' LIMIT 1;
    SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = beer_id AND name = 'Normal' LIMIT 1;
    SELECT id INTO imported_sub_id FROM brand_subcategories WHERE category_id = beer_id AND name = 'Imported' LIMIT 1;

    -- BRAND 1: BUDWEISER MAGNUM (2 variants - Premium)
    SELECT id INTO brand FROM saas_brands WHERE name = 'BUDWEISER MAGNUM';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, premium_sub_id, '650ML', 'Premium Beer - Tall bottle with red-gold label and embossed crown logo',
     0, 170, 210, 210, 'https://drive.google.com/file/d/1XPjdI4lJbFBNEuKHCBJfyIuC8gxMT64V/view?usp=sharing', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, beer_id, premium_sub_id, '500ML', 'Premium Beer - Standard bottle with red crest label',
     0, 130, 160, 160, 'https://drive.google.com/file/d/1VzytsZvI1AE6WG40b7I40c-nJzoQgOhR/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 2: CARLSBERG ELEPHANT (2 variants - Imported)
    SELECT id INTO brand FROM saas_brands WHERE name = 'CARLSBERG ELEPHANT';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, imported_sub_id, '650ML', 'Imported Strong Beer - Large bottle with green glass and elephant logo',
     0, 165, 210, 210, 'https://drive.google.com/file/d/159xE4dsY_QwJhEd0IFWPqm2ZF9cNA4LM/view?usp=sharing', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, beer_id, imported_sub_id, '500ML', 'Imported Strong Beer - Standard bottle with elephant logo',
     0, 120, 160, 160, 'https://drive.google.com/file/d/1mgSuJawDSezyqHyfovlBLc5pxWEjnk8x/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 3: KINGFISHER STRONG (2 variants - Normal)
    SELECT id INTO brand FROM saas_brands WHERE name = 'KINGFISHER STRONG';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, normal_sub_id, '650ML', 'Strong Beer - Tall bottle with red-blue label and kingfisher bird logo',
     0, 150, 190, 190, 'https://drive.google.com/file/d/1h0MXZ7PM-5Y3Vum1X-Nx6IwDzkVtKR0B/view?usp=sharing', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, beer_id, normal_sub_id, '500ML', 'Strong Beer - Standard bottle with kingfisher bird logo',
     0, 112, 140, 140, 'https://drive.google.com/file/d/1ujKIyWEImPpgXvKLlMd9d99KOEGG0SVZ/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 4: TUBORG STRONG (2 variants - Normal)
    SELECT id INTO brand FROM saas_brands WHERE name = 'TUBORG STRONG';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, normal_sub_id, '650ML', 'Strong Beer - Tall green bottle with Tuborg crest',
     0, 148, 190, 190, 'https://drive.google.com/file/d/1WioUhm5LFk7j_a5mEdUSy6jevLuqT-yo/view?usp=sharing', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, beer_id, normal_sub_id, '500ML', 'Strong Beer - Standard green bottle with Tuborg label',
     0, 95, 140, 140, 'https://drive.google.com/file/d/1Ni1EqLIkXb0yH4QhR4TON_VsKEQirCoh/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 5: KINGFISHER ULTRA MAX (2 variants - Premium)
    SELECT id INTO brand FROM saas_brands WHERE name = 'KINGFISHER ULTRA MAX';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, premium_sub_id, '650ML', 'Premium Strong Beer - Bold label with matte finish',
     0, 155, 190, 190, 'https://drive.google.com/file/d/1CpaGntSV5pleDsNUTVwzylRJYctbHi2i/view?usp=sharing', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, beer_id, premium_sub_id, '500ML', 'Premium Strong Beer - Stylized label with gloss finish',
     0, 125, 150, 150, 'https://drive.google.com/file/d/1A_EoaYiyv1BH8v-JF6iMHiEzIckvm7-f/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 6: HOEGAARDEN (2 variants - Imported)
    SELECT id INTO brand FROM saas_brands WHERE name = 'HOEGAARDEN';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, imported_sub_id, '500ML', 'Imported Wheat Beer - Short stubby bottle with white label and blue/orange accents',
     0, 195, 240, 240, 'https://drive.google.com/file/d/1OxoQYkelRdvs7-sxPFyVJTLh_E2jNJ-W/view?usp=sharing', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, beer_id, imported_sub_id, '330ML', 'Imported Wheat Beer - Compact bottle with white label and distinctive fonts',
     0, 130, 160, 160, 'https://drive.google.com/file/d/11frVhr2249QezGgtUfeLymcWFRMTKGPj/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 7: AMSTEL (1 variant - Imported)
    SELECT id INTO brand FROM saas_brands WHERE name = 'AMSTEL';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, imported_sub_id, '500ML', 'Imported Lager - Standard bottle with circular crest label',
     0, 118, 150, 150, 'https://drive.google.com/file/d/1iYAEVls4_IImtYji3GqC-KO3u-jm7o0d/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 8: GOD FATHER (1 variant - Normal)
    SELECT id INTO brand FROM saas_brands WHERE name = 'GOD FATHER';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, normal_sub_id, '500ML', 'Strong Beer - Dark bottle with bold label',
     0, 110, 140, 140, 'https://drive.google.com/file/d/16ZtON-eShAugaeRTXVDW6QzdZvmCTVNo/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 9: HAYWARDS 5000 (1 variant - Normal)
    SELECT id INTO brand FROM saas_brands WHERE name = 'HAYWARDS 5000';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, normal_sub_id, '500ML', 'Strong Lager Beer - Standard bottle with red and gold label',
     0, 100, 120, 120, 'https://drive.google.com/file/d/15riz_1YkeQGuy3a1Wa1Le4oyc5RsJsfB/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 10: BRO CODE (1 variant - Premium)
    SELECT id INTO brand FROM saas_brands WHERE name = 'BRO CODE';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, premium_sub_id, '330ML', 'Premium Beer - Compact bottle with matte label',
     0, 135, 170, 170, 'https://drive.google.com/file/d/1oKIIMlAWeSTMXpbnKrz6MJLPoAcaafQl/view?usp=sharing', true, NOW(), NOW());

    -- BRAND 11: CORONA (1 variant - Imported)
    SELECT id INTO brand FROM saas_brands WHERE name = 'CORONA';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, beer_id, imported_sub_id, '330ML', 'Imported Beer - Clear bottle with yellow label',
     0, 125, 160, 160, 'https://drive.google.com/file/d/1_SUycdU2m3i1MSXtroyN5KmdzGcRkOp3/view?usp=sharing', true, NOW(), NOW());

END $$;

COMMIT;

-- Verification Queries
SELECT '=== BEER BRAND IMPORT SUMMARY ===' as info;

SELECT
    'Total Beer Brands' as metric,
    COUNT(*) as count
FROM saas_brands
WHERE name IN ('BUDWEISER MAGNUM', 'CARLSBERG ELEPHANT', 'KINGFISHER STRONG', 'TUBORG STRONG',
               'KINGFISHER ULTRA MAX', 'HOEGAARDEN', 'AMSTEL', 'GOD FATHER', 'HAYWARDS 5000',
               'BRO CODE', 'CORONA')
UNION ALL
SELECT
    'Total Beer Variants' as metric,
    COUNT(*) as count
FROM brand_variants v
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer'
UNION ALL
SELECT
    'Premium Beer Products' as metric,
    COUNT(*) as count
FROM brand_variants v
JOIN brand_subcategories s ON v.subcategory_id = s.id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer' AND s.name = 'Premium'
UNION ALL
SELECT
    'Normal Beer Products' as metric,
    COUNT(*) as count
FROM brand_variants v
JOIN brand_subcategories s ON v.subcategory_id = s.id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer' AND s.name = 'Normal'
UNION ALL
SELECT
    'Imported Beer Products' as metric,
    COUNT(*) as count
FROM brand_variants v
JOIN brand_subcategories s ON v.subcategory_id = s.id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer' AND s.name = 'Imported';

-- Show all beer brands with their variants
SELECT b.name as "Brand Name",
       s.name as "Subcategory",
       COUNT(v.id) as "Variants",
       STRING_AGG(v.size || ' (₹' || v.selling_price || ')', ', ' ORDER BY v.size DESC) as "Products"
FROM saas_brands b
JOIN brand_variants v ON b.id = v.brand_id
JOIN brand_categories c ON v.category_id = c.id
JOIN brand_subcategories s ON v.subcategory_id = s.id
WHERE c.name = 'Beer'
GROUP BY b.id, b.name, s.name
ORDER BY s.name, b.name;
