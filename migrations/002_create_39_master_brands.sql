-- Migration: Create 39 Master Brands for LiquorPro
-- Purpose: Add pre-configured liquor brands for easy tenant onboarding
-- Date: 2025-11-19

BEGIN;

-- Ensure we have the correct categories
DO $$
DECLARE
    whiskey_id UUID;
    vodka_id UUID;
    normal_subcategory_id UUID;
BEGIN
    -- Get category IDs
    SELECT id INTO whiskey_id FROM brand_categories WHERE name = 'Whiskey' LIMIT 1;
    SELECT id INTO vodka_id FROM brand_categories WHERE name = 'Vodka' LIMIT 1;

    -- Create Normal subcategory if it doesn't exist
    INSERT INTO brand_subcategories (id, name, category_id, description, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), 'Normal', whiskey_id, 'Regular variant', true, NOW(), NOW())
    ON CONFLICT DO NOTHING;

    INSERT INTO brand_subcategories (id, name, category_id, description, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), 'Normal', vodka_id, 'Regular variant', true, NOW(), NOW())
    ON CONFLICT DO NOTHING;
END $$;

-- Insert the 39 master brands
INSERT INTO saas_brands (id, name, description, picture, is_active, sort_order, created_at, updated_at) VALUES
-- 180ML Whisky Brands (22 brands)
(gen_random_uuid(), '8 PM GOLD SCOTCH WHISKY', '180ML Premium Scotch Whisky', 'https://drive.google.com/file/d/1eRNLsi0xQJshohWs2z4-PHq5B6ucU7zM/view', true, 1, NOW(), NOW()),
(gen_random_uuid(), 'ROYAL STAG SUPERIOR WHISKY', '180ML Superior Whisky', 'https://drive.google.com/file/d/10Q-tTF9gKsRySwH_UzfzmZPtBVfcm_UA/view', true, 2, NOW(), NOW()),
(gen_random_uuid(), 'MC DOWELLS NO.1', '180ML Premium Whisky', 'https://drive.google.com/file/d/1BhlXYe5_kEvXxwM7KTl-yyuRurjdQ8rm/view', true, 3, NOW(), NOW()),
(gen_random_uuid(), 'IMPERIAL BLUE PREMIER GRAIN', '180ML Premier Grain Whisky', 'https://drive.google.com/file/d/1Aso3NtHOtVrGGMDANhJwQM4yyx9Konrt/view', true, 4, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS IMPERIAL BLUE DUAL CASK', '180ML Dual Cask Smooth Whisky', 'https://drive.google.com/file/d/1W2eY2kCb8xwUOCcLzjLEh708pHAThAFy/view', true, 5, NOW(), NOW()),
(gen_random_uuid(), 'VIN GREEN LABEL WHISKY', '180ML Green Label Whisky', 'https://drive.google.com/file/d/1Y6JMcTGzZKX_cQeB--4VhrINP-gvvLnd/view', true, 6, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS BLENDERS PRIDE', '180ML Extra Premium Whisky', 'https://drive.google.com/file/d/1rm4BusvpTcy81qR-PdC9nLUEkPqMS9qm/view', true, 7, NOW(), NOW()),
(gen_random_uuid(), 'STERLING RESERVE B7', '180ML Special Blend Whisky', 'https://drive.google.com/file/d/1RDPHhq3Eh94zG8a0BrXz6X1qTM9ELAZK/view', true, 8, NOW(), NOW()),
(gen_random_uuid(), 'WHITE & BLUE RESERVE', '180ML Reserve Whisky', 'https://drive.google.com/file/d/1Lk93Y8Tc1dH7BLkun9kSJTICwoMvHiOl/view', true, 9, NOW(), NOW()),
(gen_random_uuid(), 'GOLFERS SHOT PREMIUM BARREL', '180ML Premium Barrel Whisky', 'https://drive.google.com/file/d/166O6yeERevhcm_BdhXh0vOMeeyranH-X/view', true, 10, NOW(), NOW()),
(gen_random_uuid(), 'THE ROCK FORD RESERVE FINE', '180ML Reserve Fine Whisky', 'https://drive.google.com/file/d/1HdL-NjByjSX48v9wqNl6oojAqFqkwJ2-/view', true, 11, NOW(), NOW()),
(gen_random_uuid(), 'WHISKIN CRAFT PREMIUM RESERVE', '180ML Premium Reserve Whisky', 'https://drive.google.com/file/d/1Lwz-x3ZGJ-iinzI5flQ8u2fbBtd24nyI/view', true, 12, NOW(), NOW()),
(gen_random_uuid(), 'ALCOBREW SINGLE OAK', '180ML Superior Grain Whisky', 'https://drive.google.com/file/d/1FXkS52fDu8F8Ltp6fcMU8uf5amVqgzdS/view', true, 13, NOW(), NOW()),
(gen_random_uuid(), 'OFFICERS CHOICE ORIGINAL', '180ML Original Whisky', 'https://drive.google.com/file/d/1fIKsiqOfbJQLiPPVTPMuvp9tSLbJ3kHu/view', true, 14, NOW(), NOW()),
(gen_random_uuid(), 'ALL SEASONS RARE RESERVE', '180ML Rare Reserve Whisky', 'https://drive.google.com/file/d/12OAGwJqnjQjsDqeorMmH9e7t-GG2BLJa/view', true, 15, NOW(), NOW()),
(gen_random_uuid(), '8 PM PREMIUM BLACK', '180ML Superior Whisky', 'https://drive.google.com/file/d/1140xidLigCJTf0iRmhHZ7igC-ntVXNCh/view', true, 16, NOW(), NOW()),
(gen_random_uuid(), '100 PIPERS DELUXE', '180ML Scotch Whisky', 'https://drive.google.com/file/d/15EXE1DFipFWVoSArRZjraz_Loj8wtbso/view', true, 17, NOW(), NOW()),
(gen_random_uuid(), 'ICONIQ WHITE DELUXE', '180ML Inter Grain Whisky', 'https://drive.google.com/file/d/1PJxL1EB5ICpxtCrKTbQb2zitpqFi-2fH/view', true, 18, NOW(), NOW()),
(gen_random_uuid(), 'AFTER DARK BLUE RARE', '180ML Rare Grain Whisky', 'https://drive.google.com/file/d/12rZ9Ck0DSG1P_nRqvWI-w0hpwmjhMftE/view', true, 19, NOW(), NOW()),
(gen_random_uuid(), 'SIGNATURE PREMIER GRAIN', '180ML Reserve Selection Whisky', 'https://drive.google.com/file/d/1h0Z280Xw9F3NVBIQeIvOWoaGfCLjsMNC/view', true, 20, NOW(), NOW()),
(gen_random_uuid(), 'BLACK DOG CENTENARY', '180ML Black Reserve Scotch Whisky', 'https://drive.google.com/file/d/1-oO1pVOjIFBjXXEzSvxpo1a5Z2ceY6YV/view', true, 21, NOW(), NOW()),
(gen_random_uuid(), 'ROYAL GREEN RESERVE', '180ML Reserve Whisky', 'https://drive.google.com/file/d/1zyGuaPBr0oqp1vqWAJHYMk6eGQZFZK27/view', true, 22, NOW(), NOW()),

-- 180ML Vodka Brands (7 brands)
(gen_random_uuid(), 'MOONWALK GREEN APPLE VODKA', '180ML Green Apple Flavored Vodka', 'https://drive.google.com/file/d/1hBIb-DUn2DTLykS4nqTx_S9ELYVfQJA7/view', true, 23, NOW(), NOW()),
(gen_random_uuid(), 'RAFFLES GREEN APPLE VODKA', '180ML Green Apple Vodka', 'https://drive.google.com/file/d/1mSCUzdQTfacq58iQiwhsQBqLfipSmfVO/view', true, 24, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS REMIX GREEN APPLE', '180ML Superior Green Apple Vodka', 'https://drive.google.com/file/d/1HjSh9c-ho-qvfI4hUr8ZolX1EwoWvz-l/view', true, 25, NOW(), NOW()),
(gen_random_uuid(), 'IGL BUNTY PREMIUM VODKA', '180ML Green Apple Premium Vodka', 'https://drive.google.com/file/d/1lVQz4wZO6tNumKhuUO0RhBE04DR2oVYM/view', true, 26, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS REMAX ORANGE', '180ML Superior Orange Vodka', 'https://drive.google.com/file/d/1OvF-Xe01AmIJb7AeGJf1XABZGPyGVd1b/view', true, 27, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS SUPERIOR', '180ML Superior Vodka', 'https://drive.google.com/file/d/1_TTfjQa1Uhu-r6SxibdHvr3ULVxNFkpu/view', true, 28, NOW(), NOW()),
(gen_random_uuid(), 'M2 MAGIC MOMENTS VERVE CRANBERRY', '180ML Premium Cranberry Vodka', 'https://drive.google.com/file/d/1eV_47hZ5a7ccrShhNGU45-_8DipEexr2/view', true, 29, NOW(), NOW()),

-- 375ML Whisky Brands (10 brands)
(gen_random_uuid(), '8 PM SPECIAL BLEND', '375ML Scotch Whisky', 'https://drive.google.com/file/d/1yO6I7IBCTKcZk1kc8eCm2fCxykbqV9Kb/view', true, 30, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS ROYAL STAG SUPERIOR', '375ML Superior Whisky', 'https://drive.google.com/file/d/1xe9_b0xKVqU3fTj4cPRUrmV_e-UvrfzG/view', true, 31, NOW(), NOW()),
(gen_random_uuid(), 'MC DOWELLS NO.1 375ML', '375ML Premium Whisky', 'https://drive.google.com/file/d/1QqPmDTr5fJOF9agpUAkgGikWq0axwdVw/view', true, 32, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS BLENDERS PRIDE 375ML', '375ML Extra Premium Whisky', 'https://drive.google.com/file/d/1fJaiSt_h-TrLjYN6QGBpV6f-B5THXz9M/view', true, 33, NOW(), NOW()),
(gen_random_uuid(), 'IMPERIAL BLUE PREMIER GRAIN 375ML', '375ML Premier Grain Whisky', 'https://drive.google.com/file/d/1eCm-zmA4xsOfAuv5pFpp4E-eIYn-ajvo/view', true, 34, NOW(), NOW()),
(gen_random_uuid(), 'SEAGRAMS IMPERIAL BLUE DUAL CASK 375ML', '375ML Dual Cask Smooth Whisky', 'https://drive.google.com/file/d/1sIbOf7bbcrHsHUdpjjsUlbRbxsNSCmJo/view', true, 35, NOW(), NOW()),
(gen_random_uuid(), 'STERLING RESERVE B-7 SPECIAL', '375ML Special Blended Whisky', 'https://drive.google.com/file/d/16vbzd_j9fRhOQGzQ3n7pnx90m2_6gq1d/view', true, 36, NOW(), NOW()),
(gen_random_uuid(), 'VIN GREEN LABEL WHISKY 375ML', '375ML Green Label Whisky', 'https://drive.google.com/file/d/1LzeUqZ5op-T9AuzvarzLv6z2PXhz0WSd/view', true, 37, NOW(), NOW()),
(gen_random_uuid(), 'WHITE & BLUE RESERVE 375ML', '375ML Reserve Whisky', 'https://drive.google.com/file/d/1XZn1ZmBlNjOXuUwxTfBBTapU1CEySMQ7/view', true, 38, NOW(), NOW()),
(gen_random_uuid(), 'ICONIQ WHITE DELUXE 375ML', '375ML Inter Grain Whisky', 'https://drive.google.com/file/d/1IdhQT-qcmXYjcmv3kSfR_tkNnUptnz8W/view', true, 39, NOW(), NOW());

-- Now create brand variants with pricing for each brand
DO $$
DECLARE
    brand RECORD;
    whiskey_id UUID;
    vodka_id UUID;
    normal_sub_id UUID;
    cat_id UUID;
BEGIN
    -- Get category IDs
    SELECT id INTO whiskey_id FROM brand_categories WHERE name = 'Whiskey' LIMIT 1;
    SELECT id INTO vodka_id FROM brand_categories WHERE name = 'Vodka' LIMIT 1;

    -- Process each brand and create variants with pricing
    -- 180ML Whisky Variants
    FOR brand IN SELECT id, name FROM saas_brands WHERE name IN (
        '8 PM GOLD SCOTCH WHISKY', 'ROYAL STAG SUPERIOR WHISKY', 'MC DOWELLS NO.1',
        'IMPERIAL BLUE PREMIER GRAIN', 'SEAGRAMS IMPERIAL BLUE DUAL CASK',
        'VIN GREEN LABEL WHISKY', 'SEAGRAMS BLENDERS PRIDE', 'STERLING RESERVE B7',
        'WHITE & BLUE RESERVE', 'GOLFERS SHOT PREMIUM BARREL', 'THE ROCK FORD RESERVE FINE',
        'WHISKIN CRAFT PREMIUM RESERVE', 'ALCOBREW SINGLE OAK', 'OFFICERS CHOICE ORIGINAL',
        'ALL SEASONS RARE RESERVE', '8 PM PREMIUM BLACK', '100 PIPERS DELUXE',
        'ICONIQ WHITE DELUXE', 'AFTER DARK BLUE RARE', 'SIGNATURE PREMIER GRAIN',
        'BLACK DOG CENTENARY', 'ROYAL GREEN RESERVE'
    ) LOOP
        -- Get the correct subcategory for whiskey
        SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = whiskey_id AND name = 'Normal' LIMIT 1;

        -- Create variant based on brand name with specific pricing
        INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, alcohol_content,
                                   government_duty, buying_price, selling_price, mrp,
                                   description, is_active, created_at, updated_at)
        VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '180ML', NULL,
                CASE brand.name
                    WHEN '8 PM GOLD SCOTCH WHISKY' THEN 85.17
                    WHEN 'ROYAL STAG SUPERIOR WHISKY' THEN 121.78
                    WHEN 'MC DOWELLS NO.1' THEN 97.58
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN' THEN 99.29
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK' THEN 106.12
                    WHEN 'VIN GREEN LABEL WHISKY' THEN 85.42
                    WHEN 'SEAGRAMS BLENDERS PRIDE' THEN 147.93
                    WHEN 'STERLING RESERVE B7' THEN 121.78
                    WHEN 'WHITE & BLUE RESERVE' THEN 113.11
                    WHEN 'GOLFERS SHOT PREMIUM BARREL' THEN 140.60
                    WHEN 'THE ROCK FORD RESERVE FINE' THEN 148.56
                    WHEN 'WHISKIN CRAFT PREMIUM RESERVE' THEN 117.36
                    WHEN 'ALCOBREW SINGLE OAK' THEN 120.94
                    WHEN 'OFFICERS CHOICE ORIGINAL' THEN 85.16
                    WHEN 'ALL SEASONS RARE RESERVE' THEN 121.78
                    WHEN '8 PM PREMIUM BLACK' THEN 113.36
                    WHEN '100 PIPERS DELUXE' THEN 223.58
                    WHEN 'ICONIQ WHITE DELUXE' THEN 98.19
                    WHEN 'AFTER DARK BLUE RARE' THEN 97.87
                    WHEN 'SIGNATURE PREMIER GRAIN' THEN 140.60
                    WHEN 'BLACK DOG CENTENARY' THEN 208.15
                    WHEN 'ROYAL GREEN RESERVE' THEN 121.78
                END,
                CASE brand.name
                    WHEN '8 PM GOLD SCOTCH WHISKY' THEN 102.70
                    WHEN 'ROYAL STAG SUPERIOR WHISKY' THEN 158.67
                    WHEN 'MC DOWELLS NO.1' THEN 129.84
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN' THEN 130.12
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK' THEN 139.60
                    WHEN 'VIN GREEN LABEL WHISKY' THEN 102.74
                    WHEN 'SEAGRAMS BLENDERS PRIDE' THEN 215.67
                    WHEN 'STERLING RESERVE B7' THEN 158.67
                    WHEN 'WHITE & BLUE RESERVE' THEN 148.79
                    WHEN 'GOLFERS SHOT PREMIUM BARREL' THEN 205.90
                    WHEN 'THE ROCK FORD RESERVE FINE' THEN 224.83
                    WHEN 'WHISKIN CRAFT PREMIUM RESERVE' THEN 158.28
                    WHEN 'ALCOBREW SINGLE OAK' THEN 167.71
                    WHEN 'OFFICERS CHOICE ORIGINAL' THEN 102.70
                    WHEN 'ALL SEASONS RARE RESERVE' THEN 158.67
                    WHEN '8 PM PREMIUM BLACK' THEN 148.81
                    WHEN '100 PIPERS DELUXE' THEN 359.84
                    WHEN 'ICONIQ WHITE DELUXE' THEN 129.94
                    WHEN 'AFTER DARK BLUE RARE' THEN 129.88
                    WHEN 'SIGNATURE PREMIER GRAIN' THEN 205.90
                    WHEN 'BLACK DOG CENTENARY' THEN 330.83
                    WHEN 'ROYAL GREEN RESERVE' THEN 158.67
                END,
                CASE brand.name
                    WHEN '8 PM GOLD SCOTCH WHISKY' THEN 120
                    WHEN 'ROYAL STAG SUPERIOR WHISKY' THEN 180
                    WHEN 'MC DOWELLS NO.1' THEN 150
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN' THEN 150
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK' THEN 160
                    WHEN 'VIN GREEN LABEL WHISKY' THEN 120
                    WHEN 'SEAGRAMS BLENDERS PRIDE' THEN 240
                    WHEN 'STERLING RESERVE B7' THEN 180
                    WHEN 'WHITE & BLUE RESERVE' THEN 170
                    WHEN 'GOLFERS SHOT PREMIUM BARREL' THEN 240
                    WHEN 'THE ROCK FORD RESERVE FINE' THEN 250
                    WHEN 'WHISKIN CRAFT PREMIUM RESERVE' THEN 180
                    WHEN 'ALCOBREW SINGLE OAK' THEN 190
                    WHEN 'OFFICERS CHOICE ORIGINAL' THEN 120
                    WHEN 'ALL SEASONS RARE RESERVE' THEN 180
                    WHEN '8 PM PREMIUM BLACK' THEN 170
                    WHEN '100 PIPERS DELUXE' THEN 390
                    WHEN 'ICONIQ WHITE DELUXE' THEN 150
                    WHEN 'AFTER DARK BLUE RARE' THEN 150
                    WHEN 'SIGNATURE PREMIER GRAIN' THEN 230
                    WHEN 'BLACK DOG CENTENARY' THEN 360
                    WHEN 'ROYAL GREEN RESERVE' THEN 180
                END,
                CASE brand.name
                    WHEN '8 PM GOLD SCOTCH WHISKY' THEN 120
                    WHEN 'ROYAL STAG SUPERIOR WHISKY' THEN 180
                    WHEN 'MC DOWELLS NO.1' THEN 150
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN' THEN 150
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK' THEN 160
                    WHEN 'VIN GREEN LABEL WHISKY' THEN 120
                    WHEN 'SEAGRAMS BLENDERS PRIDE' THEN 240
                    WHEN 'STERLING RESERVE B7' THEN 180
                    WHEN 'WHITE & BLUE RESERVE' THEN 170
                    WHEN 'GOLFERS SHOT PREMIUM BARREL' THEN 240
                    WHEN 'THE ROCK FORD RESERVE FINE' THEN 250
                    WHEN 'WHISKIN CRAFT PREMIUM RESERVE' THEN 180
                    WHEN 'ALCOBREW SINGLE OAK' THEN 190
                    WHEN 'OFFICERS CHOICE ORIGINAL' THEN 120
                    WHEN 'ALL SEASONS RARE RESERVE' THEN 180
                    WHEN '8 PM PREMIUM BLACK' THEN 170
                    WHEN '100 PIPERS DELUXE' THEN 390
                    WHEN 'ICONIQ WHITE DELUXE' THEN 150
                    WHEN 'AFTER DARK BLUE RARE' THEN 150
                    WHEN 'SIGNATURE PREMIER GRAIN' THEN 230
                    WHEN 'BLACK DOG CENTENARY' THEN 360
                    WHEN 'ROYAL GREEN RESERVE' THEN 180
                END,
                '180ML variant', true, NOW(), NOW());
    END LOOP;

    -- 180ML Vodka Variants
    FOR brand IN SELECT id, name FROM saas_brands WHERE name IN (
        'MOONWALK GREEN APPLE VODKA', 'RAFFLES GREEN APPLE VODKA',
        'M2 MAGIC MOMENTS REMIX GREEN APPLE', 'IGL BUNTY PREMIUM VODKA',
        'M2 MAGIC MOMENTS REMAX ORANGE', 'M2 MAGIC MOMENTS SUPERIOR',
        'M2 MAGIC MOMENTS VERVE CRANBERRY'
    ) LOOP
        -- Get the correct subcategory for vodka
        SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = vodka_id AND name = 'Normal' LIMIT 1;

        INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, alcohol_content,
                                   government_duty, buying_price, selling_price, mrp,
                                   description, is_active, created_at, updated_at)
        VALUES (gen_random_uuid(), brand.id, vodka_id, normal_sub_id, '180ML', NULL,
                CASE brand.name
                    WHEN 'MOONWALK GREEN APPLE VODKA' THEN 85.42
                    WHEN 'RAFFLES GREEN APPLE VODKA' THEN 85.41
                    WHEN 'M2 MAGIC MOMENTS REMIX GREEN APPLE' THEN 113.13
                    WHEN 'IGL BUNTY PREMIUM VODKA' THEN 85.17
                    WHEN 'M2 MAGIC MOMENTS REMAX ORANGE' THEN 113.14
                    WHEN 'M2 MAGIC MOMENTS SUPERIOR' THEN 98.21
                    WHEN 'M2 MAGIC MOMENTS VERVE CRANBERRY' THEN 130.17
                END,
                CASE brand.name
                    WHEN 'MOONWALK GREEN APPLE VODKA' THEN 102.74
                    WHEN 'RAFFLES GREEN APPLE VODKA' THEN 102.74
                    WHEN 'M2 MAGIC MOMENTS REMIX GREEN APPLE' THEN 148.79
                    WHEN 'IGL BUNTY PREMIUM VODKA' THEN 102.70
                    WHEN 'M2 MAGIC MOMENTS REMAX ORANGE' THEN 148.79
                    WHEN 'M2 MAGIC MOMENTS SUPERIOR' THEN 129.94
                    WHEN 'M2 MAGIC MOMENTS VERVE CRANBERRY' THEN 177.64
                END,
                CASE brand.name
                    WHEN 'MOONWALK GREEN APPLE VODKA' THEN 120
                    WHEN 'RAFFLES GREEN APPLE VODKA' THEN 120
                    WHEN 'M2 MAGIC MOMENTS REMIX GREEN APPLE' THEN 170
                    WHEN 'IGL BUNTY PREMIUM VODKA' THEN 120
                    WHEN 'M2 MAGIC MOMENTS REMAX ORANGE' THEN 170
                    WHEN 'M2 MAGIC MOMENTS SUPERIOR' THEN 150
                    WHEN 'M2 MAGIC MOMENTS VERVE CRANBERRY' THEN 200
                END,
                CASE brand.name
                    WHEN 'MOONWALK GREEN APPLE VODKA' THEN 120
                    WHEN 'RAFFLES GREEN APPLE VODKA' THEN 120
                    WHEN 'M2 MAGIC MOMENTS REMIX GREEN APPLE' THEN 170
                    WHEN 'IGL BUNTY PREMIUM VODKA' THEN 120
                    WHEN 'M2 MAGIC MOMENTS REMAX ORANGE' THEN 170
                    WHEN 'M2 MAGIC MOMENTS SUPERIOR' THEN 150
                    WHEN 'M2 MAGIC MOMENTS VERVE CRANBERRY' THEN 200
                END,
                '180ML variant', true, NOW(), NOW());
    END LOOP;

    -- 375ML Whisky Variants
    FOR brand IN SELECT id, name FROM saas_brands WHERE name IN (
        '8 PM SPECIAL BLEND', 'SEAGRAMS ROYAL STAG SUPERIOR', 'MC DOWELLS NO.1 375ML',
        'SEAGRAMS BLENDERS PRIDE 375ML', 'IMPERIAL BLUE PREMIER GRAIN 375ML',
        'SEAGRAMS IMPERIAL BLUE DUAL CASK 375ML', 'STERLING RESERVE B-7 SPECIAL',
        'VIN GREEN LABEL WHISKY 375ML', 'WHITE & BLUE RESERVE 375ML',
        'ICONIQ WHITE DELUXE 375ML'
    ) LOOP
        -- Get the correct subcategory for whiskey
        SELECT id INTO normal_sub_id FROM brand_subcategories WHERE category_id = whiskey_id AND name = 'Normal' LIMIT 1;

        INSERT INTO brand_variants (id, brand_id, category_id, subcategory_id, size, alcohol_content,
                                   government_duty, buying_price, selling_price, mrp,
                                   description, is_active, created_at, updated_at)
        VALUES (gen_random_uuid(), brand.id, whiskey_id, normal_sub_id, '375ML', NULL,
                CASE brand.name
                    WHEN '8 PM SPECIAL BLEND' THEN 169.42
                    WHEN 'SEAGRAMS ROYAL STAG SUPERIOR' THEN 230.71
                    WHEN 'MC DOWELLS NO.1 375ML' THEN 202.78
                    WHEN 'SEAGRAMS BLENDERS PRIDE 375ML' THEN 290.19
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN 375ML' THEN 206.34
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK 375ML' THEN 209.75
                    WHEN 'STERLING RESERVE B-7 SPECIAL' THEN 230.71
                    WHEN 'VIN GREEN LABEL WHISKY 375ML' THEN 169.95
                    WHEN 'WHITE & BLUE RESERVE 375ML' THEN 223.46
                    WHEN 'ICONIQ WHITE DELUXE 375ML' THEN 204.05
                END,
                CASE brand.name
                    WHEN '8 PM SPECIAL BLEND' THEN 203.95
                    WHEN 'SEAGRAMS ROYAL STAG SUPERIOR' THEN 305.56
                    WHEN 'MC DOWELLS NO.1 375ML' THEN 267.99
                    WHEN 'SEAGRAMS BLENDERS PRIDE 375ML' THEN 425.13
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN 375ML' THEN 268.57
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK 375ML' THEN 277.50
                    WHEN 'STERLING RESERVE B-7 SPECIAL' THEN 305.56
                    WHEN 'VIN GREEN LABEL WHISKY 375ML' THEN 204.03
                    WHEN 'WHITE & BLUE RESERVE 375ML' THEN 295.80
                    WHEN 'ICONIQ WHITE DELUXE 375ML' THEN 268.20
                END,
                CASE brand.name
                    WHEN '8 PM SPECIAL BLEND' THEN 240
                    WHEN 'SEAGRAMS ROYAL STAG SUPERIOR' THEN 350
                    WHEN 'MC DOWELLS NO.1 375ML' THEN 310
                    WHEN 'SEAGRAMS BLENDERS PRIDE 375ML' THEN 480
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN 375ML' THEN 310
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK 375ML' THEN 320
                    WHEN 'STERLING RESERVE B-7 SPECIAL' THEN 350
                    WHEN 'VIN GREEN LABEL WHISKY 375ML' THEN 240
                    WHEN 'WHITE & BLUE RESERVE 375ML' THEN 340
                    WHEN 'ICONIQ WHITE DELUXE 375ML' THEN 310
                END,
                CASE brand.name
                    WHEN '8 PM SPECIAL BLEND' THEN 240
                    WHEN 'SEAGRAMS ROYAL STAG SUPERIOR' THEN 350
                    WHEN 'MC DOWELLS NO.1 375ML' THEN 310
                    WHEN 'SEAGRAMS BLENDERS PRIDE 375ML' THEN 480
                    WHEN 'IMPERIAL BLUE PREMIER GRAIN 375ML' THEN 310
                    WHEN 'SEAGRAMS IMPERIAL BLUE DUAL CASK 375ML' THEN 320
                    WHEN 'STERLING RESERVE B-7 SPECIAL' THEN 350
                    WHEN 'VIN GREEN LABEL WHISKY 375ML' THEN 240
                    WHEN 'WHITE & BLUE RESERVE 375ML' THEN 340
                    WHEN 'ICONIQ WHITE DELUXE 375ML' THEN 310
                END,
                '375ML variant', true, NOW(), NOW());
    END LOOP;
END $$;

COMMIT;

-- Verification
SELECT
    'Total Brands' as metric,
    COUNT(*) as count
FROM saas_brands
UNION ALL
SELECT
    'Total Variants' as metric,
    COUNT(*) as count
FROM brand_variants
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