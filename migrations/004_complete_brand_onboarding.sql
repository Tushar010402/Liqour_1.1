-- ============================================================================
-- Migration: Complete Brand Onboarding (50 Products)
-- Date: 2025-12-10
-- Source: JSON Dataset with comprehensive pricing and metadata
-- ============================================================================
-- Summary:
--   - New category: RTD (Ready to Drink)
--   - New subcategories: Scotch, Single Malt, Irish, Premium, Regular, Dark, White, Flavored, Plain
--   - Add variants to 19 existing brands (21 variants)
--   - Create 31 new brands with variants (29 variants)
--   - Total new variants: 50
-- ============================================================================

BEGIN;

-- ============================================================================
-- PART 1: Create New Category (RTD)
-- ============================================================================
INSERT INTO brand_categories (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'RTD', 'Ready to Drink Beverages', true, 6, NOW(), NOW())
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- PART 2: Create New Subcategories
-- ============================================================================

-- Whiskey subcategories
INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Scotch', 'Scotch Whisky', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Whiskey'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Single Malt', 'Single Malt Whisky', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Whiskey'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Irish', 'Irish Whiskey', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Whiskey'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Premium', 'Premium Whisky', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Whiskey'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Regular', 'Regular Whisky', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Whiskey'
ON CONFLICT DO NOTHING;

-- Rum subcategories
INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Dark', 'Dark Rum', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Rum'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'White', 'White Rum', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Rum'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Flavored', 'Flavored Rum', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Rum'
ON CONFLICT DO NOTHING;

-- RTD subcategories
INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Plain', 'Plain RTD', true, NOW(), NOW()
FROM brand_categories WHERE name = 'RTD'
ON CONFLICT DO NOTHING;

INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Flavored', 'Flavored RTD', true, NOW(), NOW()
FROM brand_categories WHERE name = 'RTD'
ON CONFLICT DO NOTHING;

-- Vodka subcategories
INSERT INTO brand_subcategories (id, category_id, name, description, is_active, created_at, updated_at)
SELECT gen_random_uuid(), id, 'Premium', 'Premium Vodka', true, NOW(), NOW()
FROM brand_categories WHERE name = 'Vodka'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 3: Add Variants to Existing Brands (19 brands, 21 variants)
-- ============================================================================

DO $$
DECLARE
    whiskey_id UUID;
    vodka_id UUID;
    rum_id UUID;
    normal_sub_id UUID;
BEGIN
    -- Get category IDs
    SELECT id INTO whiskey_id FROM brand_categories WHERE name = 'Whiskey';
    SELECT id INTO vodka_id FROM brand_categories WHERE name = 'Vodka';
    SELECT id INTO rum_id FROM brand_categories WHERE name = 'Rum';
    SELECT id INTO normal_sub_id FROM brand_subcategories WHERE name = 'Normal' LIMIT 1;

    -- 1. 8 PM 750ML (Regular - Special Blend Scotch)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Special Blend Scotch',
        276.00, 368.00, 460.00, 460.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = '8 PM';

    -- 2. 8 PM 750ML (Premium Black Superior)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Premium Black Superior',
        402.00, 536.00, 670.00, 670.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = '8 PM';

    -- 3. MC DOWELLS NO.1 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Premium Whisky',
        366.00, 488.00, 610.00, 610.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'MC DOWELLS NO.1';

    -- 4. AFTER DARK 750ML (Blue Rare Grain)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Blue Rare Grain',
        366.00, 488.00, 610.00, 610.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'AFTER DARK';

    -- 5. IMPERIAL BLUE 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Smooth Superior Grain',
        372.00, 496.00, 620.00, 620.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'IMPERIAL BLUE';

    -- 6. ROYAL STAG 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Superior Whisky',
        408.00, 544.00, 680.00, 680.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ROYAL STAG';

    -- 7. ROYAL GREEN RESERVE 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Reserve',
        408.00, 544.00, 680.00, 680.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ROYAL GREEN RESERVE';

    -- 8. WHITE & BLUE RESERVE 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Reserve',
        414.00, 552.00, 690.00, 690.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'WHITE & BLUE RESERVE';

    -- 9. ICONIQ WHITE DELUXE 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Deluxe Inter Grain',
        360.00, 480.00, 600.00, 600.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ICONIQ WHITE DELUXE';

    -- 10. STERLING RESERVE 750ML (B7)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'B7 Special Blended',
        408.00, 544.00, 680.00, 680.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'STERLING RESERVE';

    -- 11. SEAGRAMS BLENDERS PRIDE 750ML (Regular)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Extra Premium',
        558.00, 744.00, 930.00, 930.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'SEAGRAMS BLENDERS PRIDE';

    -- 12. SEAGRAMS BLENDERS PRIDE 750ML (Reserve Collection)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Reserve Collection Extra Premium',
        612.00, 816.00, 1020.00, 1020.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'SEAGRAMS BLENDERS PRIDE';

    -- 13. THE ROCK FORD RESERVE 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Reserve Fine',
        600.00, 800.00, 1000.00, 1000.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'THE ROCK FORD RESERVE';

    -- 14. BLACK DOG 750ML (Regular)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Centenary Black Reserve Scotch',
        906.00, 1208.00, 1510.00, 1510.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BLACK DOG';

    -- 15. BLACK DOG 750ML (Gold Reserve)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Gold Reserve Scotch',
        1320.00, 1760.00, 2200.00, 2200.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BLACK DOG';

    -- 16. 100 PIPERS 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Deluxe Scotch',
        942.00, 1256.00, 1570.00, 1570.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = '100 PIPERS';

    -- 17. SIGNATURE 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Premier Grain Reserve Selection',
        552.00, 736.00, 920.00, 920.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'SIGNATURE';

    -- 18. ALL SEASONS 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Rare Reserve',
        408.00, 544.00, 680.00, 680.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ALL SEASONS';

    -- 19. GOLFERS SHOT 180ML (Additional variant - skip if exists)
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), sb.id, whiskey_id, normal_sub_id, '180ML', 'Classic',
        90.00, 120.00, 150.00, 150.00, true, NOW(), NOW()
    FROM saas_brands sb
    WHERE sb.name = 'GOLFERS SHOT'
    AND NOT EXISTS (
        SELECT 1 FROM brand_variants bv
        WHERE bv.brand_id = sb.id AND bv.size = '180ML' AND bv.description = 'Classic'
    );

    RAISE NOTICE 'Added variants to existing brands';
END $$;

-- ============================================================================
-- PART 4: Create New Brands (31 brands)
-- ============================================================================

-- ============================================================================
-- PART 4A: New Whisky Brands - Regular/Premium (6 brands)
-- ============================================================================

-- Royal Challenge
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'ROYAL CHALLENGE', 'Premium Indian Whisky', true, 40, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Verb Convery
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'VERB CONVERY', 'Premium Whisky', true, 41, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- R.S. Barrel
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'R.S. BARREL', 'Premium Barrel Aged Whisky', true, 42, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Antiquity Blue
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'ANTIQUITY BLUE', 'Ultra Premium Whisky', true, 43, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- American Pride
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'AMERICAN PRIDE', 'American Style Whisky', true, 44, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Blender Double Blue
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'BLENDER DOUBLE BLUE', 'Blended Whisky', true, 45, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4B: New Whisky Brands - Scotch (7 brands)
-- ============================================================================

-- Black & White
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'BLACK & WHITE', 'Blended Scotch Whisky', true, 46, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Ballantine''s
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'BALLANTINES', 'Finest Blended Scotch', true, 47, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Johnnie Walker Red Label
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'JOHNNIE WALKER RED LABEL', 'Iconic Red Label Scotch', true, 48, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Johnnie Walker Blonde
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'JOHNNIE WALKER BLONDE', 'Smooth Blonde Scotch', true, 49, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Chivas Regal
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'CHIVAS REGAL', '12 Year Old Blended Scotch', true, 50, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Johnnie Walker Black Label
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'JOHNNIE WALKER BLACK LABEL', '12 Year Old Black Label', true, 51, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Johnnie Walker Green Label
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'JOHNNIE WALKER GREEN LABEL', '15 Year Old Blended Malt', true, 52, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4C: New Whisky Brands - Single Malt (2 brands)
-- ============================================================================

-- The Glenlivet
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'THE GLENLIVET', '12 Year Old Single Malt', true, 53, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Glenfiddich
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'GLENFIDDICH', '12 Year Old Single Malt', true, 54, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4D: New Whisky Brands - Premium Indian (2 brands)
-- ============================================================================

-- Ranthambore
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'RANTHAMBORE', 'Premium Indian Single Malt', true, 55, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Longitud 77
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'LONGITUD 77', 'Premium Craft Whisky', true, 56, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4E: New Whisky Brands - Irish (1 brand)
-- ============================================================================

-- Jameson
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'JAMESON', 'Triple Distilled Irish Whiskey', true, 57, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4F: New Vodka Brands - Premium (2 brands)
-- ============================================================================

-- Absolut Vodka
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'ABSOLUT VODKA', 'Swedish Premium Vodka', true, 58, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Ketel One
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'KETEL ONE', 'Dutch Premium Vodka', true, 59, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4G: New Rum Brands (4 brands)
-- ============================================================================

-- Old Monk
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'OLD MONK', 'Legendary Indian Rum', true, 60, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Old Monk Coffee
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'OLD MONK COFFEE', 'Coffee Flavored Rum', true, 61, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Bacardi Black
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'BACARDI BLACK', 'Premium Dark Rum', true, 62, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Bacardi White
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'BACARDI WHITE', 'Superior White Rum', true, 63, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Bacardi Lemon
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'BACARDI LEMON', 'Citrus Flavored Rum', true, 64, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 4H: New RTD Brands (3 brands)
-- ============================================================================

-- Magic Sada
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'MAGIC SADA', 'Ready to Drink Plain', true, 65, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Magic Apple
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'MAGIC APPLE', 'Ready to Drink Apple', true, 66, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Magic Orange
INSERT INTO saas_brands (id, name, description, is_active, sort_order, created_at, updated_at)
VALUES (gen_random_uuid(), 'MAGIC ORANGE', 'Ready to Drink Orange', true, 67, NOW(), NOW())
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PART 5: Add Variants to New Brands
-- ============================================================================

DO $$
DECLARE
    whiskey_id UUID;
    vodka_id UUID;
    rum_id UUID;
    rtd_id UUID;
    normal_sub_id UUID;
BEGIN
    -- Get category IDs
    SELECT id INTO whiskey_id FROM brand_categories WHERE name = 'Whiskey';
    SELECT id INTO vodka_id FROM brand_categories WHERE name = 'Vodka';
    SELECT id INTO rum_id FROM brand_categories WHERE name = 'Rum';
    SELECT id INTO rtd_id FROM brand_categories WHERE name = 'RTD';
    SELECT id INTO normal_sub_id FROM brand_subcategories WHERE name = 'Normal' LIMIT 1;

    -- ============================================================================
    -- 4A: Whisky Regular/Premium variants
    -- ============================================================================

    -- Royal Challenge 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Premium Whisky',
        408.00, 544.00, 680.00, 680.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ROYAL CHALLENGE';

    -- Verb Convery 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Premium Whisky',
        456.00, 608.00, 760.00, 760.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'VERB CONVERY';

    -- R.S. Barrel 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Barrel Aged',
        468.00, 624.00, 780.00, 780.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'R.S. BARREL';

    -- Antiquity Blue 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Ultra Premium',
        576.00, 768.00, 960.00, 960.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ANTIQUITY BLUE';

    -- American Pride 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'American Style',
        366.00, 488.00, 610.00, 610.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'AMERICAN PRIDE';

    -- Blender Double Blue 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Double Blended',
        366.00, 488.00, 610.00, 610.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BLENDER DOUBLE BLUE';

    -- ============================================================================
    -- 4B: Scotch variants
    -- ============================================================================

    -- Black & White 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Blended Scotch',
        1002.00, 1336.00, 1670.00, 1670.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BLACK & WHITE';

    -- Ballantine's 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Finest Blended Scotch',
        1056.00, 1408.00, 1760.00, 1760.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BALLANTINES';

    -- Johnnie Walker Red Label 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Iconic Red Label',
        1080.00, 1440.00, 1800.00, 1800.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'JOHNNIE WALKER RED LABEL';

    -- Johnnie Walker Blonde 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Smooth Blonde',
        1536.00, 2048.00, 2560.00, 2560.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'JOHNNIE WALKER BLONDE';

    -- Chivas Regal 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', '12 Year Old',
        1740.00, 2320.00, 2900.00, 2900.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'CHIVAS REGAL';

    -- Johnnie Walker Black Label 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', '12 Year Old',
        1854.00, 2472.00, 3090.00, 3090.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'JOHNNIE WALKER BLACK LABEL';

    -- Johnnie Walker Green Label 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', '15 Year Blended Malt',
        2700.00, 3600.00, 4500.00, 4500.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'JOHNNIE WALKER GREEN LABEL';

    -- ============================================================================
    -- 4C: Single Malt variants
    -- ============================================================================

    -- The Glenlivet 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', '12 Year Single Malt',
        1962.00, 2616.00, 3270.00, 3270.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'THE GLENLIVET';

    -- Glenfiddich 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', '12 Year Single Malt',
        2730.00, 3640.00, 4550.00, 4550.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'GLENFIDDICH';

    -- ============================================================================
    -- 4D: Premium Indian variants
    -- ============================================================================

    -- Ranthambore 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Indian Single Malt',
        996.00, 1328.00, 1660.00, 1660.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'RANTHAMBORE';

    -- Longitud 77 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Premium Craft',
        2790.00, 3720.00, 4650.00, 4650.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'LONGITUD 77';

    -- ============================================================================
    -- 4E: Irish variants
    -- ============================================================================

    -- Jameson 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, whiskey_id, normal_sub_id, '750ML', 'Triple Distilled Irish',
        1356.00, 1808.00, 2260.00, 2260.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'JAMESON';

    -- ============================================================================
    -- 4F: Vodka variants
    -- ============================================================================

    -- Absolut Vodka 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, vodka_id, normal_sub_id, '750ML', 'Swedish Premium',
        1068.00, 1424.00, 1780.00, 1780.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'ABSOLUT VODKA';

    -- Ketel One 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, vodka_id, normal_sub_id, '750ML', 'Dutch Premium',
        1314.00, 1752.00, 2190.00, 2190.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'KETEL ONE';

    -- ============================================================================
    -- 4G: Rum variants
    -- ============================================================================

    -- Old Monk 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rum_id, normal_sub_id, '750ML', 'Dark Rum 7 Year',
        366.00, 488.00, 610.00, 610.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'OLD MONK';

    -- Old Monk 1000ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rum_id, normal_sub_id, '1000ML', 'Dark Rum 7 Year XXX',
        480.00, 640.00, 800.00, 800.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'OLD MONK';

    -- Old Monk Coffee 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rum_id, normal_sub_id, '750ML', 'Coffee Flavored',
        390.00, 520.00, 650.00, 650.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'OLD MONK COFFEE';

    -- Bacardi Black 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rum_id, normal_sub_id, '750ML', 'Premium Dark Rum',
        570.00, 760.00, 950.00, 950.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BACARDI BLACK';

    -- Bacardi White 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rum_id, normal_sub_id, '750ML', 'Superior White Rum',
        570.00, 760.00, 950.00, 950.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BACARDI WHITE';

    -- Bacardi Lemon 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rum_id, normal_sub_id, '750ML', 'Citrus Flavored Rum',
        570.00, 760.00, 950.00, 950.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'BACARDI LEMON';

    -- ============================================================================
    -- 4H: RTD variants
    -- ============================================================================

    -- Magic Sada 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rtd_id, normal_sub_id, '750ML', 'Plain Soda',
        360.00, 480.00, 600.00, 600.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'MAGIC SADA';

    -- Magic Apple 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rtd_id, normal_sub_id, '750ML', 'Apple Flavored',
        402.00, 536.00, 670.00, 670.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'MAGIC APPLE';

    -- Magic Orange 750ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
        government_duty, buying_price, selling_price, mrp, is_active, created_at, updated_at)
    SELECT gen_random_uuid(), id, rtd_id, normal_sub_id, '750ML', 'Orange Flavored',
        402.00, 536.00, 670.00, 670.00, true, NOW(), NOW()
    FROM saas_brands WHERE name = 'MAGIC ORANGE';

    RAISE NOTICE 'Successfully added all new brands and variants';
END $$;

COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Count new brands
SELECT 'Total Brands' as metric, COUNT(*) as count FROM saas_brands;

-- Count variants by size
SELECT size, COUNT(*) as count FROM brand_variants GROUP BY size ORDER BY size;

-- List all 750ML variants
SELECT b.name as brand, bv.size, bv.description, bv.buying_price, bv.selling_price, bv.mrp
FROM saas_brands b
JOIN brand_variants bv ON b.id = bv.brand_id
WHERE bv.size = '750ML'
ORDER BY b.name;

-- Count by category
SELECT bc.name as category, COUNT(DISTINCT bv.id) as variants
FROM brand_categories bc
LEFT JOIN brand_variants bv ON bc.id = bv.category_id
GROUP BY bc.name
ORDER BY bc.name;
