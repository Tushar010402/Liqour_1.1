-- Migration: Smart Brand Consolidation
-- Purpose: Consolidate 39 separate brands into 29 unique brands with proper size variants
-- Date: 2025-11-19
-- Result: 29 brands with 39 total variants preserving all pricing data

BEGIN;

-- Step 1: Clear existing incorrect structure
DELETE FROM tenant_brand_variants WHERE 1=1;
DELETE FROM tenant_brands WHERE 1=1;
DELETE FROM brand_variants WHERE 1=1;
DELETE FROM saas_brands WHERE 1=1;

-- Step 2: Get category IDs
DO $$
DECLARE
    whiskey_id UUID;
    vodka_id UUID;
BEGIN
    SELECT id INTO whiskey_id FROM brand_categories WHERE name = 'Whiskey' LIMIT 1;
    SELECT id INTO vodka_id FROM brand_categories WHERE name = 'Vodka' LIMIT 1;

    -- Store in temp table for use in INSERT statements
    CREATE TEMP TABLE IF NOT EXISTS temp_categories AS
    SELECT 'Whiskey' as name, whiskey_id as id
    UNION ALL
    SELECT 'Vodka' as name, vodka_id as id;
END $$;

-- Step 3: Create 29 unique brands with smart naming
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order, created_at, updated_at) VALUES
-- WHISKY BRANDS (22 unique brands)
(gen_random_uuid(), '8 PM', 'Premium Whisky Brand with multiple variants', NULL, true, 1, NOW(), NOW()),
(gen_random_uuid(), 'ROYAL STAG', 'Superior Whisky by Seagrams', NULL, true, 2, NOW(), NOW()),
(gen_random_uuid(), 'MC DOWELLS NO.1', 'Popular Premium Whisky', NULL, true, 3, NOW(), NOW()),
(gen_random_uuid(), 'IMPERIAL BLUE', 'Premier Grain Whisky', NULL, true, 4, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS IMPERIAL BLUE DUAL CASK', 'Smooth Dual Cask Whisky', NULL, true, 5, NOW(), NOW()),
(gen_random_uuid(), 'VIN GREEN LABEL', 'Green Label Whisky', NULL, true, 6, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS BLENDERS PRIDE', 'Extra Premium Whisky', NULL, true, 7, NOW(), NOW()),
(gen_random_uuid(), 'STERLING RESERVE B7', 'Special Blended Whisky', NULL, true, 8, NOW(), NOW()),
(gen_random_uuid(), 'WHITE & BLUE RESERVE', 'Reserve Whisky', NULL, true, 9, NOW(), NOW()),
(gen_random_uuid(), 'GOLFERS SHOT', 'Premium Barrel Whisky', NULL, true, 10, NOW(), NOW()),
(gen_random_uuid(), 'THE ROCK FORD RESERVE', 'Fine Reserve Whisky', NULL, true, 11, NOW(), NOW()),
(gen_random_uuid(), 'WHISKIN CRAFT', 'Premium Reserve Whisky', NULL, true, 12, NOW(), NOW()),
(gen_random_uuid(), 'ALCOBREW SINGLE OAK', 'Superior Grain Whisky', NULL, true, 13, NOW(), NOW()),
(gen_random_uuid(), 'OFFICERS CHOICE', 'Original Whisky', NULL, true, 14, NOW(), NOW()),
(gen_random_uuid(), 'ALL SEASONS', 'Rare Reserve Whisky', NULL, true, 15, NOW(), NOW()),
(gen_random_uuid(), '100 PIPERS', 'Deluxe Scotch Whisky', NULL, true, 16, NOW(), NOW()),
(gen_random_uuid(), 'ICONIQ WHITE', 'Deluxe Inter Grain Whisky', NULL, true, 17, NOW(), NOW()),
(gen_random_uuid(), 'AFTER DARK', 'Blue Rare Grain Whisky', NULL, true, 18, NOW(), NOW()),
(gen_random_uuid(), 'SIGNATURE', 'Premier Grain Whisky Reserve Selection', NULL, true, 19, NOW(), NOW()),
(gen_random_uuid(), 'BLACK DOG', 'Centenary Black Reserve Scotch Whisky', NULL, true, 20, NOW(), NOW()),
(gen_random_uuid(), 'ROYAL GREEN', 'Reserve Whisky', NULL, true, 21, NOW(), NOW()),

-- VODKA BRANDS (7 unique brands)
(gen_random_uuid(), 'MOONWALK', 'Green Apple Flavored Vodka', NULL, true, 22, NOW(), NOW()),
(gen_random_uuid(), 'RAFFLES', 'Green Apple Vodka', NULL, true, 23, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS REMIX', 'Superior Flavored Vodka', NULL, true, 24, NOW(), NOW()),
(gen_random_uuid(), 'IGL BUNTY', 'Premium Green Apple Vodka', NULL, true, 25, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS REMAX', 'Superior Orange Vodka', NULL, true, 26, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS', 'Superior Vodka', NULL, true, 27, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS VERVE', 'Premium Cranberry Vodka', NULL, true, 28, NOW(), NOW());

-- Step 4: Create all 39 variants with proper pricing
DO $$
DECLARE
    brand RECORD;
    whiskey_id UUID;
    vodka_id UUID;
    normal_sub_id UUID;
BEGIN
    -- Get category IDs
    SELECT id INTO whiskey_id FROM brand_categories WHERE name = 'Whiskey' LIMIT 1;
    SELECT id INTO vodka_id FROM brand_categories WHERE name = 'Vodka' LIMIT 1;

    -- BRAND 1: 8 PM (3 variants: Gold Scotch 180ML, Premium Black 180ML, Special Blend 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = '8 PM';
    SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = whiskey_id AND name = 'Normal' LIMIT 1;

    -- Gold Scotch 180ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Gold Scotch',
            85.17, 102.70, 120, 120, 'https://drive.google.com/file/d/1eRNLsi0xQJshohWs2z4-PHq5B6ucU7zM/view', true, NOW(), NOW());

    -- Premium Black 180ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Premium Black',
            113.36, 148.81, 170, 170, 'https://drive.google.com/file/d/1140xidLigCJTf0iRmhHZ7igC-ntVXNCh/view', true, NOW(), NOW());

    -- Special Blend 375ML
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Special Blend',
            169.42, 203.95, 240, 240, 'https://drive.google.com/file/d/1yO6I7IBCTKcZk1kc8eCm2fCxykbqV9Kb/view', true, NOW(), NOW());

    -- BRAND 2: ROYAL STAG (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'ROYAL STAG';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Superior Whisky',
     121.78, 158.67, 180, 180, 'https://drive.google.com/file/d/10Q-tTF9gKsRySwH_UzfzmZPtBVfcm_UA/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Superior Whisky',
     230.71, 305.56, 350, 350, 'https://drive.google.com/file/d/1xe9_b0xKVqU3fTj4cPRUrmV_e-UvrfzG/view', true, NOW(), NOW());

    -- BRAND 3: MC DOWELLS NO.1 (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'MC DOWELLS NO.1';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Premium Whisky',
     97.58, 129.84, 150, 150, 'https://drive.google.com/file/d/1BhlXYe5_kEvXxwM7KTl-yyuRurjdQ8rm/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Premium Whisky',
     202.78, 267.99, 310, 310, 'https://drive.google.com/file/d/1QqPmDTr5fJOF9agpUAkgGikWq0axwdVw/view', true, NOW(), NOW());

    -- BRAND 4: IMPERIAL BLUE (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'IMPERIAL BLUE';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Premier Grain',
     99.29, 130.12, 150, 150, 'https://drive.google.com/file/d/1Aso3NtHOtVrGGMDANhJwQM4yyx9Konrt/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Premier Grain',
     206.34, 268.57, 310, 310, 'https://drive.google.com/file/d/1eCm-zmA4xsOfAuv5pFpp4E-eIYn-ajvo/view', true, NOW(), NOW());

    -- BRAND 5: SEAGRAMS IMPERIAL BLUE DUAL CASK (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'SEAGRAMS IMPERIAL BLUE DUAL CASK';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Smooth Whisky',
     106.12, 139.60, 160, 160, 'https://drive.google.com/file/d/1W2eY2kCb8xwUOCcLzjLEh708pHAThAFy/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Smooth Whisky',
     209.75, 277.50, 320, 320, 'https://drive.google.com/file/d/1sIbOf7bbcrHsHUdpjjsUlbRbxsNSCmJo/view', true, NOW(), NOW());

    -- BRAND 6: VIN GREEN LABEL (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'VIN GREEN LABEL';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Green Label',
     85.42, 102.74, 120, 120, 'https://drive.google.com/file/d/1Y6JMcTGzZKX_cQeB--4VhrINP-gvvLnd/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Green Label',
     169.95, 204.03, 240, 240, 'https://drive.google.com/file/d/1LzeUqZ5op-T9AuzvarzLv6z2PXhz0WSd/view', true, NOW(), NOW());

    -- BRAND 7: SEAGRAMS BLENDERS PRIDE (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'SEAGRAMS BLENDERS PRIDE';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Extra Premium',
     147.93, 215.67, 240, 240, 'https://drive.google.com/file/d/1rm4BusvpTcy81qR-PdC9nLUEkPqMS9qm/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Extra Premium',
     290.19, 425.13, 480, 480, 'https://drive.google.com/file/d/1fJaiSt_h-TrLjYN6QGBpV6f-B5THXz9M/view', true, NOW(), NOW());

    -- BRAND 8: STERLING RESERVE B7 (2 variants: 180ML, 375ML Special)
    SELECT id INTO brand FROM saas_brands WHERE name = 'STERLING RESERVE B7';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'B7 Blend',
     121.78, 158.67, 180, 180, 'https://drive.google.com/file/d/1RDPHhq3Eh94zG8a0BrXz6X1qTM9ELAZK/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'B7 Special Blend',
     230.71, 305.56, 350, 350, 'https://drive.google.com/file/d/16vbzd_j9fRhOQGzQ3n7pnx90m2_6gq1d/view', true, NOW(), NOW());

    -- BRAND 9: WHITE & BLUE RESERVE (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'WHITE & BLUE RESERVE';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Reserve',
     113.11, 148.79, 170, 170, 'https://drive.google.com/file/d/1Lk93Y8Tc1dH7BLkun9kSJTICwoMvHiOl/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Reserve',
     223.46, 295.80, 340, 340, 'https://drive.google.com/file/d/1XZn1ZmBlNjOXuUwxTfBBTapU1CEySMQ7/view', true, NOW(), NOW());

    -- BRAND 10: ICONIQ WHITE (2 variants: 180ML, 375ML)
    SELECT id INTO brand FROM saas_brands WHERE name = 'ICONIQ WHITE';

    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Deluxe Inter Grain',
     98.19, 129.94, 150, 150, 'https://drive.google.com/file/d/1PJxL1EB5ICpxtCrKTbQb2zitpqFi-2fH/view', true, NOW(), NOW()),
    (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', 'Deluxe Inter Grain',
     204.05, 268.20, 310, 310, 'https://drive.google.com/file/d/1IdhQT-qcmXYjcmv3kSfR_tkNnUptnz8W/view', true, NOW(), NOW());

    -- SINGLE SIZE WHISKY BRANDS (180ML only - 11 brands)

    -- GOLFERS SHOT
    SELECT id INTO brand FROM saas_brands WHERE name = 'GOLFERS SHOT';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Premium Barrel',
            140.60, 205.90, 240, 240, 'https://drive.google.com/file/d/166O6yeERevhcm_BdhXh0vOMeeyranH-X/view', true, NOW(), NOW());

    -- THE ROCK FORD RESERVE
    SELECT id INTO brand FROM saas_brands WHERE name = 'THE ROCK FORD RESERVE';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Reserve Fine',
            148.56, 224.83, 250, 250, 'https://drive.google.com/file/d/1HdL-NjByjSX48v9wqNl6oojAqFqkwJ2-/view', true, NOW(), NOW());

    -- WHISKIN CRAFT
    SELECT id INTO brand FROM saas_brands WHERE name = 'WHISKIN CRAFT';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Premium Reserve',
            117.36, 158.28, 180, 180, 'https://drive.google.com/file/d/1Lwz-x3ZGJ-iinzI5flQ8u2fbBtd24nyI/view', true, NOW(), NOW());

    -- ALCOBREW SINGLE OAK
    SELECT id INTO brand FROM saas_brands WHERE name = 'ALCOBREW SINGLE OAK';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Superior Grain',
            120.94, 167.71, 190, 190, 'https://drive.google.com/file/d/1FXkS52fDu8F8Ltp6fcMU8uf5amVqgzdS/view', true, NOW(), NOW());

    -- OFFICERS CHOICE
    SELECT id INTO brand FROM saas_brands WHERE name = 'OFFICERS CHOICE';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Original',
            85.16, 102.70, 120, 120, 'https://drive.google.com/file/d/1fIKsiqOfbJQLiPPVTPMuvp9tSLbJ3kHu/view', true, NOW(), NOW());

    -- ALL SEASONS
    SELECT id INTO brand FROM saas_brands WHERE name = 'ALL SEASONS';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Rare Reserve',
            121.78, 158.67, 180, 180, 'https://drive.google.com/file/d/12OAGwJqnjQjsDqeorMmH9e7t-GG2BLJa/view', true, NOW(), NOW());

    -- 100 PIPERS
    SELECT id INTO brand FROM saas_brands WHERE name = '100 PIPERS';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Deluxe Scotch',
            223.58, 359.84, 390, 390, 'https://drive.google.com/file/d/15EXE1DFipFWVoSArRZjraz_Loj8wtbso/view', true, NOW(), NOW());

    -- AFTER DARK
    SELECT id INTO brand FROM saas_brands WHERE name = 'AFTER DARK';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Blue Rare Grain',
            97.87, 129.88, 150, 150, 'https://drive.google.com/file/d/12rZ9Ck0DSG1P_nRqvWI-w0hpwmjhMftE/view', true, NOW(), NOW());

    -- SIGNATURE
    SELECT id INTO brand FROM saas_brands WHERE name = 'SIGNATURE';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Premier Grain Reserve',
            140.60, 205.90, 230, 230, 'https://drive.google.com/file/d/1h0Z280Xw9F3NVBIQeIvOWoaGfCLjsMNC/view', true, NOW(), NOW());

    -- BLACK DOG
    SELECT id INTO brand FROM saas_brands WHERE name = 'BLACK DOG';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Centenary Black Reserve',
            208.15, 330.83, 360, 360, 'https://drive.google.com/file/d/1-oO1pVOjIFBjXXEzSvxpo1a5Z2ceY6YV/view', true, NOW(), NOW());

    -- ROYAL GREEN
    SELECT id INTO brand FROM saas_brands WHERE name = 'ROYAL GREEN';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', 'Reserve',
            121.78, 158.67, 180, 180, 'https://drive.google.com/file/d/1zyGuaPBr0oqp1vqWAJHYMk6eGQZFZK27/view', true, NOW(), NOW());

    -- VODKA BRANDS (7 brands, all 180ML only)
    SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = vodka_id AND name = 'Normal' LIMIT 1;

    -- MOONWALK
    SELECT id INTO brand FROM saas_brands WHERE name = 'MOONWALK';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Green Apple',
            85.42, 102.74, 120, 120, 'https://drive.google.com/file/d/1hBIb-DUn2DTLykS4nqTx_S9ELYVfQJA7/view', true, NOW(), NOW());

    -- RAFFLES
    SELECT id INTO brand FROM saas_brands WHERE name = 'RAFFLES';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Green Apple',
            85.41, 102.74, 120, 120, 'https://drive.google.com/file/d/1mSCUzdQTfacq58iQiwhsQBqLfipSmfVO/view', true, NOW(), NOW());

    -- M2 MAGIC MOMENTS REMIX
    SELECT id INTO brand FROM saas_brands WHERE name = 'M2 MAGIC MOMENTS REMIX';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Green Apple',
            113.13, 148.79, 170, 170, 'https://drive.google.com/file/d/1HjSh9c-ho-qvfI4hUr8ZolX1EwoWvz-l/view', true, NOW(), NOW());

    -- IGL BUNTY
    SELECT id INTO brand FROM saas_brands WHERE name = 'IGL BUNTY';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Premium Green Apple',
            85.17, 102.70, 120, 120, 'https://drive.google.com/file/d/1lVQz4wZO6tNumKhuUO0RhBE04DR2oVYM/view', true, NOW(), NOW());

    -- M2 MAGIC MOMENTS REMAX
    SELECT id INTO brand FROM saas_brands WHERE name = 'M2 MAGIC MOMENTS REMAX';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Orange',
            113.14, 148.79, 170, 170, 'https://drive.google.com/file/d/1OvF-Xe01AmIJb7AeGJf1XABZGPyGVd1b/view', true, NOW(), NOW());

    -- M2 MAGIC MOMENTS
    SELECT id INTO brand FROM saas_brands WHERE name = 'M2 MAGIC MOMENTS';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Superior',
            98.21, 129.94, 150, 150, 'https://drive.google.com/file/d/1_TTfjQa1Uhu-r6SxibdHvr3ULVxNFkpu/view', true, NOW(), NOW());

    -- M2 MAGIC MOMENTS VERVE
    SELECT id INTO brand FROM saas_brands WHERE name = 'M2 MAGIC MOMENTS VERVE';
    INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, description,
                               government_duty, buying_price, selling_price, mrp, picture, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', 'Cranberry',
            130.17, 177.64, 200, 200, 'https://drive.google.com/file/d/1eV_47hZ5a7ccrShhNGU45-_8DipEexr2/view', true, NOW(), NOW());

END $$;

-- Clean up temp table
DROP TABLE IF EXISTS temp_categories;

COMMIT;

-- Verification Queries
SELECT 'BRAND CONSOLIDATION RESULTS:' as info;
SELECT '=============================' as separator;

SELECT
    'Total Unique Brands' as metric,
    COUNT(*) as count
FROM saas_brands
UNION ALL
SELECT
    'Total Variants' as metric,
    COUNT(*) as count
FROM brand_variants
UNION ALL
SELECT
    'Brands with Multiple Sizes' as metric,
    COUNT(DISTINCT b.id) as count
FROM saas_brands b
WHERE EXISTS (
    SELECT 1 FROM brand_variants v
    WHERE v.brand_id = b.id
    GROUP BY v.brand_id
    HAVING COUNT(DISTINCT v.size) > 1
)
UNION ALL
SELECT
    'Whisky Brands' as metric,
    COUNT(DISTINCT b.id) as count
FROM saas_brands b
JOIN brand_variants v ON b.id = v.brand_id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Whiskey'
UNION ALL
SELECT
    'Vodka Brands' as metric,
    COUNT(DISTINCT b.id) as count
FROM saas_brands b
JOIN brand_variants v ON b.id = v.brand_id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Vodka';

-- Show brands with their variant counts
SELECT
    b.name as brand_name,
    COUNT(v.id) as variant_count,
    STRING_AGG(DISTINCT v.size || ' (' || v.description || ')', ', ' ORDER BY v.size) as variants
FROM saas_brands b
JOIN brand_variants v ON b.id = v.brand_id
GROUP BY b.id, b.name
HAVING COUNT(v.id) > 1
ORDER BY variant_count DESC, b.name;