-- Create Real Indian Liquor Brands for SaaS Catalog
-- These brands will be available for all tenants to onboard

-- Clear existing test data
DELETE FROM saas_brand_variants;
DELETE FROM saas_brands WHERE name LIKE '%AAA%' OR name LIKE '%KKK%' OR name = 'Inactive Test Brand';

-- Insert Real Indian & International Liquor Brands

-- 1. JOHNNIE WALKER (Scotch Whisky)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b1a2c3d4-1111-4444-8888-111111111111',
    'Johnnie Walker',
    'World-famous Scotch whisky brand available in multiple variants',
    'https://example.com/johnnie-walker.jpg',
    true,
    1
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Johnnie Walker Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b1a2c3d4-1111-4444-8888-111111111111', 'Johnnie Walker Red Label', '750ml', 1600, 1900, 2100, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b1a2c3d4-1111-4444-8888-111111111111', 'Johnnie Walker Black Label', '750ml', 2800, 3200, 3500, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b1a2c3d4-1111-4444-8888-111111111111', 'Johnnie Walker Blue Label', '750ml', 15000, 17000, 18500, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b1a2c3d4-1111-4444-8888-111111111111', 'Johnnie Walker Gold Label', '750ml', 5500, 6200, 6800, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 2. ROYAL STAG (Indian Whisky)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b2a2c3d4-2222-4444-8888-222222222222',
    'Royal Stag',
    'Popular Indian whisky brand by Pernod Ricard',
    'https://example.com/royal-stag.jpg',
    true,
    2
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Royal Stag Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b2a2c3d4-2222-4444-8888-222222222222', 'Royal Stag', '750ml', 800, 950, 1100, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b2a2c3d4-2222-4444-8888-222222222222', 'Royal Stag Barrel Select', '750ml', 1200, 1400, 1600, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b2a2c3d4-2222-4444-8888-222222222222', 'Royal Stag', '375ml', 450, 550, 650, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 3. OFFICER'S CHOICE (Indian Whisky)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b3a2c3d4-3333-4444-8888-333333333333',
    'Officer''s Choice',
    'India''s largest selling whisky brand',
    'https://example.com/officers-choice.jpg',
    true,
    3
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Officer's Choice Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b3a2c3d4-3333-4444-8888-333333333333', 'Officer''s Choice Whisky', '750ml', 550, 650, 750, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b3a2c3d4-3333-4444-8888-333333333333', 'Officer''s Choice Blue', '750ml', 650, 750, 850, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b3a2c3d4-3333-4444-8888-333333333333', 'Officer''s Choice Black', '750ml', 700, 800, 900, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 4. KINGFISHER (Beer)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b4a2c3d4-4444-4444-8888-444444444444',
    'Kingfisher',
    'India''s most popular beer brand',
    'https://example.com/kingfisher.jpg',
    true,
    4
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Kingfisher Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b4a2c3d4-4444-4444-8888-444444444444', 'Kingfisher Premium', '650ml', 120, 150, 170, (SELECT id FROM saas_categories WHERE name = 'Beer' LIMIT 1), NULL),
    (gen_random_uuid(), 'b4a2c3d4-4444-4444-8888-444444444444', 'Kingfisher Strong', '650ml', 130, 160, 180, (SELECT id FROM saas_categories WHERE name = 'Beer' LIMIT 1), NULL),
    (gen_random_uuid(), 'b4a2c3d4-4444-4444-8888-444444444444', 'Kingfisher Ultra', '330ml', 80, 100, 120, (SELECT id FROM saas_categories WHERE name = 'Beer' LIMIT 1), NULL),
    (gen_random_uuid(), 'b4a2c3d4-4444-4444-8888-444444444444', 'Kingfisher Ultra Max', '500ml', 100, 130, 150, (SELECT id FROM saas_categories WHERE name = 'Beer' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 5. BREEZER (Flavored Alcoholic Beverage)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b5a2c3d4-5555-4444-8888-555555555555',
    'Bacardi Breezer',
    'Fruit-flavored alcoholic beverage',
    'https://example.com/breezer.jpg',
    true,
    5
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Breezer Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b5a2c3d4-5555-4444-8888-555555555555', 'Breezer Orange', '275ml', 80, 100, 120, (SELECT id FROM saas_categories WHERE name = 'Wine' LIMIT 1), NULL),
    (gen_random_uuid(), 'b5a2c3d4-5555-4444-8888-555555555555', 'Breezer Cranberry', '275ml', 80, 100, 120, (SELECT id FROM saas_categories WHERE name = 'Wine' LIMIT 1), NULL),
    (gen_random_uuid(), 'b5a2c3d4-5555-4444-8888-555555555555', 'Breezer Watermelon', '275ml', 80, 100, 120, (SELECT id FROM saas_categories WHERE name = 'Wine' LIMIT 1), NULL),
    (gen_random_uuid(), 'b5a2c3d4-5555-4444-8888-555555555555', 'Breezer Jamaica Passion', '275ml', 80, 100, 120, (SELECT id FROM saas_categories WHERE name = 'Wine' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 6. OLD MONK (Rum)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b6a2c3d4-6666-4444-8888-666666666666',
    'Old Monk',
    'Legendary Indian dark rum',
    'https://example.com/old-monk.jpg',
    true,
    6
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Old Monk Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b6a2c3d4-6666-4444-8888-666666666666', 'Old Monk Rum', '750ml', 450, 550, 650, (SELECT id FROM saas_categories WHERE name = 'Rum' LIMIT 1), NULL),
    (gen_random_uuid(), 'b6a2c3d4-6666-4444-8888-666666666666', 'Old Monk Rum', '375ml', 230, 280, 330, (SELECT id FROM saas_categories WHERE name = 'Rum' LIMIT 1), NULL),
    (gen_random_uuid(), 'b6a2c3d4-6666-4444-8888-666666666666', 'Old Monk Gold Reserve', '750ml', 650, 750, 850, (SELECT id FROM saas_categories WHERE name = 'Rum' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 7. SMIRNOFF (Vodka)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b7a2c3d4-7777-4444-8888-777777777777',
    'Smirnoff',
    'World''s best-selling vodka brand',
    'https://example.com/smirnoff.jpg',
    true,
    7
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Smirnoff Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b7a2c3d4-7777-4444-8888-777777777777', 'Smirnoff Vodka', '750ml', 900, 1100, 1300, (SELECT id FROM saas_categories WHERE name = 'Vodka' LIMIT 1), NULL),
    (gen_random_uuid(), 'b7a2c3d4-7777-4444-8888-777777777777', 'Smirnoff Vodka', '375ml', 480, 580, 680, (SELECT id FROM saas_categories WHERE name = 'Vodka' LIMIT 1), NULL),
    (gen_random_uuid(), 'b7a2c3d4-7777-4444-8888-777777777777', 'Smirnoff Green Apple', '750ml', 950, 1150, 1350, (SELECT id FROM saas_categories WHERE name = 'Vodka' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- 8. SIGNATURE (Indian Whisky)
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order)
VALUES (
    'b8a2c3d4-8888-4444-8888-888888888888',
    'Signature',
    'Premium Indian whisky',
    'https://example.com/signature.jpg',
    true,
    8
) ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Signature Variants
INSERT INTO saas_brand_variants (id, saas_brand_id, name, size, cost_price, selling_price, mrp, saas_category_id, saas_subcategory_id)
VALUES
    (gen_random_uuid(), 'b8a2c3d4-8888-4444-8888-888888888888', 'Signature Whisky', '750ml', 1200, 1400, 1600, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL),
    (gen_random_uuid(), 'b8a2c3d4-8888-4444-8888-888888888888', 'Signature Rare Aged', '750ml', 1800, 2100, 2400, (SELECT id FROM saas_categories WHERE name = 'Whiskey' LIMIT 1), NULL)
ON CONFLICT DO NOTHING;

-- Summary
SELECT
    'Brands Created' as type,
    COUNT(*) as count
FROM saas_brands
WHERE is_active = true

UNION ALL

SELECT
    'Variants Created' as type,
    COUNT(*) as count
FROM saas_brand_variants;

-- List all brands with variant count
SELECT
    b.name as brand_name,
    b.description,
    COUNT(v.id) as variant_count,
    b.is_active
FROM saas_brands b
LEFT JOIN saas_brand_variants v ON b.id = v.saas_brand_id
WHERE b.is_active = true
GROUP BY b.id, b.name, b.description, b.is_active
ORDER BY b.sort_order;
