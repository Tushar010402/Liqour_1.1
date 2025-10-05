-- Create Real Indian Liquor Brands for SaaS Catalog (Fixed Schema)

-- Get category IDs
DO $$
DECLARE
    v_whiskey_cat UUID := (SELECT id FROM brand_categories WHERE name = 'Whiskey' LIMIT 1);
    v_beer_cat UUID := (SELECT id FROM brand_categories WHERE name = 'Beer' LIMIT 1);
    v_rum_cat UUID := (SELECT id FROM brand_categories WHERE name = 'Rum' LIMIT 1);
    v_vodka_cat UUID := (SELECT id FROM brand_categories WHERE name = 'Vodka' LIMIT 1);
    v_wine_cat UUID := (SELECT id FROM brand_categories WHERE name = 'Wine' LIMIT 1);

    v_jw_brand UUID;
    v_royal_brand UUID;
    v_officer_brand UUID;
    v_kingfisher_brand UUID;
    v_oldmonk_brand UUID;
    v_smirnoff_brand UUID;
    v_signature_brand UUID;
    v_breezer_brand UUID;
BEGIN
    -- Delete test brands
    DELETE FROM brand_variants WHERE brand_id IN (
        SELECT id FROM saas_brands WHERE name LIKE '%AAA%' OR name LIKE '%KKK%' OR name = 'Inactive Test Brand'
    );
    DELETE FROM saas_brands WHERE name LIKE '%AAA%' OR name LIKE '%KKK%' OR name = 'Inactive Test Brand';

    -- 1. JOHNNIE WALKER
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Johnnie Walker', 'World-famous Scotch whisky brand', true, 1)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_jw_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_jw_brand, v_whiskey_cat, '750ml', 1600, 1900, 2100, 'Johnnie Walker Red Label'),
        (v_jw_brand, v_whiskey_cat, '750ml', 2800, 3200, 3500, 'Johnnie Walker Black Label'),
        (v_jw_brand, v_whiskey_cat, '750ml', 15000, 17000, 18500, 'Johnnie Walker Blue Label'),
        (v_jw_brand, v_whiskey_cat, '750ml', 5500, 6200, 6800, 'Johnnie Walker Gold Label')
    ON CONFLICT DO NOTHING;

    -- 2. ROYAL STAG
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Royal Stag', 'Popular Indian whisky by Pernod Ricard', true, 2)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_royal_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_royal_brand, v_whiskey_cat, '750ml', 800, 950, 1100, 'Royal Stag'),
        (v_royal_brand, v_whiskey_cat, '750ml', 1200, 1400, 1600, 'Royal Stag Barrel Select'),
        (v_royal_brand, v_whiskey_cat, '375ml', 450, 550, 650, 'Royal Stag Half Bottle')
    ON CONFLICT DO NOTHING;

    -- 3. OFFICER'S CHOICE
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Officer''s Choice', 'India''s largest selling whisky brand', true, 3)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_officer_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_officer_brand, v_whiskey_cat, '750ml', 550, 650, 750, 'Officer''s Choice Whisky'),
        (v_officer_brand, v_whiskey_cat, '750ml', 650, 750, 850, 'Officer''s Choice Blue'),
        (v_officer_brand, v_whiskey_cat, '750ml', 700, 800, 900, 'Officer''s Choice Black')
    ON CONFLICT DO NOTHING;

    -- 4. KINGFISHER
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Kingfisher Beer', 'India''s most popular beer brand', true, 4)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_kingfisher_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_kingfisher_brand, v_beer_cat, '650ml', 120, 150, 170, 'Kingfisher Premium'),
        (v_kingfisher_brand, v_beer_cat, '650ml', 130, 160, 180, 'Kingfisher Strong'),
        (v_kingfisher_brand, v_beer_cat, '330ml', 80, 100, 120, 'Kingfisher Ultra'),
        (v_kingfisher_brand, v_beer_cat, '500ml', 100, 130, 150, 'Kingfisher Ultra Max')
    ON CONFLICT DO NOTHING;

    -- 5. OLD MONK
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Old Monk', 'Legendary Indian dark rum', true, 5)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_oldmonk_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_oldmonk_brand, v_rum_cat, '750ml', 450, 550, 650, 'Old Monk Rum'),
        (v_oldmonk_brand, v_rum_cat, '375ml', 230, 280, 330, 'Old Monk Half Bottle'),
        (v_oldmonk_brand, v_rum_cat, '750ml', 650, 750, 850, 'Old Monk Gold Reserve')
    ON CONFLICT DO NOTHING;

    -- 6. SMIRNOFF
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Smirnoff', 'World''s best-selling vodka brand', true, 6)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_smirnoff_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_smirnoff_brand, v_vodka_cat, '750ml', 900, 1100, 1300, 'Smirnoff Vodka'),
        (v_smirnoff_brand, v_vodka_cat, '375ml', 480, 580, 680, 'Smirnoff Half Bottle'),
        (v_smirnoff_brand, v_vodka_cat, '750ml', 950, 1150, 1350, 'Smirnoff Green Apple')
    ON CONFLICT DO NOTHING;

    -- 7. SIGNATURE
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Signature', 'Premium Indian whisky', true, 7)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_signature_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_signature_brand, v_whiskey_cat, '750ml', 1200, 1400, 1600, 'Signature Whisky'),
        (v_signature_brand, v_whiskey_cat, '750ml', 1800, 2100, 2400, 'Signature Rare Aged')
    ON CONFLICT DO NOTHING;

    -- 8. BACARDI BREEZER
    INSERT INTO saas_brands (name, description, is_active, sort_order)
    VALUES ('Bacardi Breezer', 'Fruit-flavored alcoholic beverage', true, 8)
    ON CONFLICT (name) DO UPDATE SET is_active = true
    RETURNING id INTO v_breezer_brand;

    INSERT INTO brand_variants (brand_id, category_id, size, buying_price, selling_price, mrp, description)
    VALUES
        (v_breezer_brand, v_wine_cat, '275ml', 80, 100, 120, 'Breezer Orange'),
        (v_breezer_brand, v_wine_cat, '275ml', 80, 100, 120, 'Breezer Cranberry'),
        (v_breezer_brand, v_wine_cat, '275ml', 80, 100, 120, 'Breezer Watermelon'),
        (v_breezer_brand, v_wine_cat, '275ml', 80, 100, 120, 'Breezer Jamaica Passion')
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '✓ Created real liquor brands successfully!';
END $$;

-- Verify brands created
SELECT
    b.name as brand_name,
    b.description,
    COUNT(v.id) as variants,
    b.is_active as active
FROM saas_brands b
LEFT JOIN brand_variants v ON b.id = v.brand_id
WHERE b.is_active = true
    AND b.name NOT LIKE '%Test%'
    AND b.name NOT LIKE '%AAA%'
GROUP BY b.id, b.name, b.description, b.is_active, b.sort_order
ORDER BY b.sort_order
LIMIT 10;
