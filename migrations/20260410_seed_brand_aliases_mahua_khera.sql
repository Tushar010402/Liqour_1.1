-- Migration: Seed brand aliases from OCR correction patterns (Mahua Khera April 8-9 analysis)
-- These aliases map common handwritten abbreviations/OCR misreads to correct product names.
-- Uses ON CONFLICT to avoid duplicates if aliases already exist.

-- High Priority aliases (appeared 3+ times across 22 extraction attempts)
INSERT INTO ocr_brand_aliases (id, tenant_id, canonical_brand_name, alias_name, occurrence_count, confidence_score, source, created_at, updated_at)
SELECT gen_random_uuid(), t.id, v.canonical, LOWER(v.alias), 5, 80.0, 'manual', NOW(), NOW()
FROM (VALUES
    -- Royal Stag variants
    ('Royal Stag Whisky', 'Seagrams Royal Stag Superior Whisky'),
    ('Royal Stag', 'Seagrams Royal Stag Superior Whisky'),
    ('RS Bouri', 'Royal Stag Bourbon Whisky'),
    ('RS Bourn', 'Royal Stag Bourbon Whisky'),
    ('R.S 82971', 'Royal Stag Bourbon Whisky'),
    ('R.S. Bapull', 'Royal Stag Barrel Select'),
    ('R.S. Bapull Signature', 'Royal Stag Barrel Select'),
    -- McDowell's variants
    ('MCD Original Whisky', 'Mc Dowells No1 ORIGINAL BLENDED WHISKY'),
    ('MCD Original', 'Mc Dowells No1 ORIGINAL BLENDED WHISKY'),
    -- Old Monk variants
    ('VOV Old Monk Matured Rum', 'OLD MONK THE LEGEND RUM VERY OLD Vatted'),
    ('VOV Old Monk', 'OLD MONK THE LEGEND RUM VERY OLD Vatted'),
    ('Old Monk Rum', 'OLD MONK THE LEGEND RUM VERY OLD Vatted'),
    -- Vodka variants
    ('Very Cranberry Vodka', 'MOOOZ CRANBERRY VODKA'),
    ('Magic Moments Vodka', 'M2 Magic Moments Superior Vodka'),
    ('Magic Moments', 'M2 Magic Moments Superior Vodka'),
    -- Whisky variants
    ('8 PM Black Whisky', '8 PM Premium Black Superior Whisky'),
    ('8PM Black', '8 PM Premium Black Superior Whisky'),
    ('White And Blue Rare Whisky', 'Officers Choice Blue Superior Grain Whisky'),
    -- Iconia / Iconiq variants
    ('Iconia', 'ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY'),
    ('Iconic', 'ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY'),
    ('1 Conia', 'ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY'),
    ('Iconiq', 'ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY'),
    -- Blenders Pride variants
    ('BP Blue', 'Blenders Pride Blue Collection'),
    ('BP Premium', 'Blenders Pride Premium Whisky'),
    -- Rockford variant
    ('Roford', 'THE ROCKFORD RESERVE'),
    ('Rockford', 'THE ROCKFORD RESERVE'),
    -- Johnnie Walker variants
    ('Dobir Blak', 'Johnnie Walker Double Black'),
    ('Robic B4kP', 'Johnnie Walker Double Black'),
    ('Redo Label', 'Johnnie Walker Red Label'),
    ('Godo Label', 'Johnnie Walker Gold Label Reserve'),
    ('Black Label', 'Johnnie Walker Black Label'),
    ('JW Black', 'Johnnie Walker Black Label'),
    ('JW Red', 'Johnnie Walker Red Label'),
    -- 1965 Spirit variants
    ('Sov 1965 XXX Rum', '1965 Spirit of Victory XXX Rum'),
    ('Sov 1965 Lemon Rum', '1965 Spirit of Victory Lemon Rum'),
    ('1965 XXX Rum', '1965 Spirit of Victory XXX Rum')
) AS v(alias, canonical)
CROSS JOIN (
    SELECT DISTINCT id FROM tenants LIMIT 10
) t
ON CONFLICT (tenant_id, alias_name) DO UPDATE
    SET canonical_brand_name = EXCLUDED.canonical_brand_name,
        confidence_score = GREATEST(ocr_brand_aliases.confidence_score, EXCLUDED.confidence_score),
        occurrence_count = ocr_brand_aliases.occurrence_count + 1,
        updated_at = NOW();
