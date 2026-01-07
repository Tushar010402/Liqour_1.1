-- Add metadata JSONB column to brand_variants
-- Supports rich metadata for image recognition, SEO, and ML training
-- Date: 2025-07-13

BEGIN;

-- Add metadata column to brand_variants if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'brand_variants' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE brand_variants ADD COLUMN metadata JSONB DEFAULT '{}';
        COMMENT ON COLUMN brand_variants.metadata IS 'Rich metadata for image recognition, SEO, ML training - stores title, description, alt_text, keywords, colors, taxonomy, etc.';
    END IF;
END $$;

-- Create index for metadata queries
CREATE INDEX IF NOT EXISTS idx_brand_variants_metadata ON brand_variants USING GIN (metadata);

-- Update beer products with their rich metadata
UPDATE brand_variants
SET metadata = '{
    "title": "Budweiser Magnum 650ml Bottle - Premium Beer",
    "description": "Budweiser Magnum 650ml premium beer bottle — tall green/brown bottle, branded red-gold label, embossed crown logo. Use for premium/celebratory contexts.",
    "alt_text": "Budweiser Magnum 650ml premium beer bottle with red-gold label",
    "keywords": ["Budweiser Magnum", "Budweiser 650ml", "premium beer", "magnum bottle", "red gold label"],
    "canonical_name": "budweiser_magnum_650",
    "synonyms": ["Budweiser Magnum 650 ML", "Bud Magnum 650"],
    "dominant_colors": ["#8B3A2F", "#D4AF37", "#2F2F2F"],
    "shape": "tall_bottle",
    "material": "glass",
    "texture": "smooth_gloss",
    "label_tokens": ["Budweiser", "Magnum", "Premium", "Crown logo"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "3-4_degree_tilt", "top_down_overhead_for_label"],
    "background_recommendation": ["plain_white", "studio_gray", "wood_table_for_context"],
    "image_quality": {
        "min_resolution": [1200, 1600],
        "format_preference": ["jpeg", "png"],
        "lighting": "soft_diffused_front",
        "depth_of_field": "shallow_to_focus_label"
    },
    "augmentation_suggestions": ["crop_center", "slight_rotation_±5deg", "brightness_variations", "label_zoom"],
    "embedding_hint": "include brand name and ''magnum'' token; prefer ''premium'' cluster",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "premium"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'BUDWEISER MAGNUM')
AND size = '650ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Budweiser 500ml - Premium Beer",
    "description": "Budweiser 500ml — standard Budweiser styling with red crest; common SKU for brand-level recognition.",
    "alt_text": "Budweiser 500ml bottle with red crest label",
    "keywords": ["Budweiser 500", "Budweiser beer", "premium beer"],
    "canonical_name": "budweiser_500",
    "synonyms": ["Budweiser 500 ML"],
    "dominant_colors": ["#C62828", "#FFFFFF", "#BDBDBD"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss_label",
    "label_tokens": ["Budweiser", "crest"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup"],
    "background_recommendation": ["plain_white", "bar_counter"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg"],
        "lighting": "diffused",
        "depth_of_field": "shallow"
    },
    "augmentation_suggestions": ["rotate_±3deg", "crop_label", "brightness"],
    "embedding_hint": "map to Budweiser product family",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "premium"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'BUDWEISER MAGNUM')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Carlsberg Elephant 650ml - Imported Strong Beer",
    "description": "Carlsberg Elephant 650ml — large bottle with green glass and distinctive elephant logo. Perfect for imported-beer catalogs and recognition models.",
    "alt_text": "Carlsberg Elephant 650ml green bottle with elephant logo",
    "keywords": ["Carlsberg Elephant", "Carlsberg 650ml", "imported beer", "elephant logo"],
    "canonical_name": "carlsberg_elephant_650",
    "synonyms": ["Carlsberg Elephant 650 ML", "Cars Elephant 650"],
    "dominant_colors": ["#2E7D32", "#FFFFFF", "#000000"],
    "shape": "tall_bottle",
    "material": "glass",
    "texture": "matte_label_gloss_bottle",
    "label_tokens": ["Carlsberg", "Elephant", "Imported"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "slightly_left_3-4deg", "closeup_of_logo"],
    "background_recommendation": ["plain_white", "studio_dark"],
    "image_quality": {
        "min_resolution": [1200, 1600],
        "format_preference": ["jpeg", "png"],
        "lighting": "even_side_lighting",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["contrast_variations", "crop_logo_focus", "rotate_±3deg"],
    "embedding_hint": "map to ''imported'' cluster; include ''elephant'' token to disambiguate",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "imported"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'CARLSBERG ELEPHANT')
AND size = '650ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Carlsberg Elephant 500ml - Imported",
    "description": "Carlsberg Elephant 500ml — smaller but similar styling to 650ml; elephant icon and green glass help disambiguate variants.",
    "alt_text": "Carlsberg Elephant 500ml bottle with elephant logo",
    "keywords": ["Carlsberg Elephant 500", "Carlsberg 500ml", "imported"],
    "canonical_name": "carlsberg_elephant_500",
    "synonyms": ["Carlsberg Elephant 500 ML"],
    "dominant_colors": ["#2E7D32", "#FFFFFF", "#000000"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss",
    "label_tokens": ["Carlsberg", "Elephant"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup"],
    "background_recommendation": ["studio_white", "wood_table"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg"],
        "lighting": "even",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["crop_logo", "slight_rotation", "contrast_var"],
    "embedding_hint": "tie to Carlsberg Elephant family across sizes",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "imported"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'CARLSBERG ELEPHANT')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Kingfisher Strong 650ml - Strong Beer",
    "description": "Kingfisher Strong 650ml — popular strong beer with red-and-blue label and iconic kingfisher bird. Useful for recognition among mass-market strong beers.",
    "alt_text": "Kingfisher Strong 650ml bottle with kingfisher logo",
    "keywords": ["Kingfisher Strong", "Kingfisher 650ml", "strong beer"],
    "canonical_name": "kingfisher_strong_650",
    "synonyms": ["Kingfisher Strong 650 ML"],
    "dominant_colors": ["#D32F2F", "#2E7D9A", "#FFFFFF"],
    "shape": "tall_bottle",
    "material": "glass",
    "texture": "gloss",
    "label_tokens": ["Kingfisher", "Strong", "logo_bird"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup"],
    "background_recommendation": ["plain_white", "bar_counter_context"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg", "png"],
        "lighting": "diffused_front",
        "depth_of_field": "shallow_label_focus"
    },
    "augmentation_suggestions": ["rotate_±5deg", "label_crop", "brightness_minus/plus"],
    "embedding_hint": "include ''kingfisher'' and ''strong'' tokens to separate from other Kingfisher SKUs",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "strong"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'KINGFISHER STRONG')
AND size = '650ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Kingfisher Strong 500ml - Strong Beer",
    "description": "Kingfisher Strong 500ml — 500ml variant of Kingfisher Strong with consistent branding; tag family/size in metadata.",
    "alt_text": "Kingfisher Strong 500ml bottle",
    "keywords": ["Kingfisher Strong 500", "Kingfisher 500 strong"],
    "canonical_name": "kingfisher_strong_500",
    "synonyms": ["Kingfisher Strong 500 ML"],
    "dominant_colors": ["#D32F2F", "#2E7D9A", "#FFFFFF"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss",
    "label_tokens": ["Kingfisher", "Strong", "bird_logo"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_crop"],
    "background_recommendation": ["plain_white", "bar"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg"],
        "lighting": "diffused",
        "depth_of_field": "shallow"
    },
    "augmentation_suggestions": ["rotate_±3deg", "crop_label"],
    "embedding_hint": "family: Kingfisher; variant: strong; size token included",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "strong"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'KINGFISHER STRONG')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Tuborg Strong 650ml - Strong Beer",
    "description": "Tuborg Strong 650ml — recognizable label and green bottle. Add for mass-market recognition and consistent matching across lighting conditions.",
    "alt_text": "Tuborg Strong 650ml green bottle with Tuborg label",
    "keywords": ["Tuborg Strong", "Tuborg 650", "strong beer", "green bottle"],
    "canonical_name": "tuborg_strong_650",
    "synonyms": ["Tuborg Strong 650 ML"],
    "dominant_colors": ["#4CAF50", "#FFFFFF", "#1B1B1B"],
    "shape": "tall_bottle",
    "material": "glass",
    "texture": "gloss",
    "label_tokens": ["Tuborg", "Strong"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup", "angle_45deg_context"],
    "background_recommendation": ["plain_white", "wooden_table"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg"],
        "lighting": "soft_side_light",
        "depth_of_field": "shallow"
    },
    "augmentation_suggestions": ["brightness_variations", "rotate_±4deg", "crop_label_center"],
    "embedding_hint": "associate with ''tuborg'' family and ''strong'' variant",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "strong"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'TUBORG STRONG')
AND size = '650ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Tuborg Strong 500ml - Strong Beer",
    "description": "Tuborg Strong 500ml — 500ml strong variant; green bottle and Tuborg crest are key recognition features.",
    "alt_text": "Tuborg Strong 500ml bottle with Tuborg label",
    "keywords": ["Tuborg Strong 500", "Tuborg 500ml", "strong beer"],
    "canonical_name": "tuborg_strong_500",
    "synonyms": ["Tuborg Strong 500 ML"],
    "dominant_colors": ["#388E3C", "#FFFFFF", "#222222"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss",
    "label_tokens": ["Tuborg", "Strong"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup"],
    "background_recommendation": ["plain_white", "wood"],
    "image_quality": {
        "min_resolution": [900, 1200],
        "format_preference": ["jpeg"],
        "lighting": "diffused",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["crop_label", "contrast_var"],
    "embedding_hint": "tie to Tuborg family across sizes",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "strong"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'TUBORG STRONG')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Ultra Max 650ml - Premium Strong Beer",
    "description": "Ultra Max 650ml — premium-leaning strong beer with bold label. Helpful for models to differentiate premium styling and packaging.",
    "alt_text": "Ultra Max 650ml beer bottle with bold premium label",
    "keywords": ["Ultra Max", "UltraMax 650", "premium strong beer"],
    "canonical_name": "ultra_max_650",
    "synonyms": ["Ultra Max 650 ML", "Kingfisher Ultra Max 650"],
    "dominant_colors": ["#303030", "#FFD700", "#FFFFFF"],
    "shape": "tall_bottle",
    "material": "glass",
    "texture": "matte_label_gloss_bottle",
    "label_tokens": ["Ultra", "Max", "Premium"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_macro"],
    "background_recommendation": ["studio_gray", "black_table"],
    "image_quality": {
        "min_resolution": [1200, 1600],
        "format_preference": ["jpeg", "png"],
        "lighting": "controlled_studio",
        "depth_of_field": "shallow"
    },
    "augmentation_suggestions": ["contrast_boost", "crop_label", "rotate_±3deg"],
    "embedding_hint": "premium packaging tokens, ''Ultra Max'' as single token",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "premium"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'KINGFISHER ULTRA MAX')
AND size = '650ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Kingfisher Ultra Max 500ml - Premium",
    "description": "Kingfisher Ultra Max 500ml — premium variant with stylized label; helpful to tag ''Ultra Max'' as unique brand token.",
    "alt_text": "Kingfisher Ultra Max 500ml bottle",
    "keywords": ["Kingfisher Ultra Max", "500ml", "premium"],
    "canonical_name": "kingfisher_ultra_max_500",
    "synonyms": ["Kingfisher UltraMax 500 ML"],
    "dominant_colors": ["#1E88E5", "#FDD835", "#FFFFFF"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss_label",
    "label_tokens": ["Kingfisher", "Ultra Max"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_macro"],
    "background_recommendation": ["studio_gray", "bar_counter"],
    "image_quality": {
        "min_resolution": [1100, 1400],
        "format_preference": ["jpeg"],
        "lighting": "studio",
        "depth_of_field": "shallow"
    },
    "augmentation_suggestions": ["crop_label", "brightness_adjustments"],
    "embedding_hint": "separate ''Ultra Max'' cluster from other Kingfisher SKUs",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "premium"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'KINGFISHER ULTRA MAX')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Hoegaarden 500ml - Imported Wheat Beer",
    "description": "Hoegaarden 500ml — white label with blue/orange accents; often a short, stubby bottle. Important for models to detect shape + white label texture.",
    "alt_text": "Hoegaarden 500ml short bottle with white label",
    "keywords": ["Hoegaarden 500", "Hoegaarden wheat beer", "imported beer"],
    "canonical_name": "hoegaarden_500",
    "synonyms": ["Hoegaarden 500 ML"],
    "dominant_colors": ["#FFFFFF", "#2E86AB", "#F39C12"],
    "shape": "short_stubby_bottle",
    "material": "glass",
    "texture": "paper_label",
    "label_tokens": ["Hoegaarden", "Wheat"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "top_label_closeup"],
    "background_recommendation": ["plain_white", "bar_context"],
    "image_quality": {
        "min_resolution": [1200, 1400],
        "format_preference": ["jpeg"],
        "lighting": "diffused_front",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["label_zoom", "crop_center", "brightness_var"],
    "embedding_hint": "cluster under ''imported'' and ''wheat'' beer families",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "imported"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'HOEGAARDEN')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Hoegaarden 330ml - Imported Wheat Beer",
    "description": "Hoegaarden 330ml — smaller variant with white label and distinctive fonts; helpful for wheat-beer family clustering.",
    "alt_text": "Hoegaarden 330ml bottle with white label",
    "keywords": ["Hoegaarden 330", "wheat beer 330", "imported"],
    "canonical_name": "hoegaarden_330",
    "synonyms": ["Hoegaarden 330 ML"],
    "dominant_colors": ["#FFFFFF", "#2E86AB", "#F39C12"],
    "shape": "short_bottle",
    "material": "glass",
    "texture": "paper_label",
    "label_tokens": ["Hoegaarden", "Wheat"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup"],
    "background_recommendation": ["plain_white", "restaurant_table"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg"],
        "lighting": "diffused",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["crop_label", "brightness_variations"],
    "embedding_hint": "group with Hoegaarden family; emphasize label font tokens",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "imported"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'HOEGAARDEN')
AND size = '330ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Amstel 500ml - Imported Beer",
    "description": "Amstel 500ml — common imported SKU with circular crest label. Useful for distinguishing between European lager labels.",
    "alt_text": "Amstel 500ml bottle with circular crest label",
    "keywords": ["Amstel 500", "Amstel beer", "imported lager"],
    "canonical_name": "amstel_500",
    "synonyms": ["Amstel 500 ML"],
    "dominant_colors": ["#FFFFFF", "#C2185B", "#BDBDBD"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "label_paper",
    "label_tokens": ["Amstel", "crest"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_detail"],
    "background_recommendation": ["plain_white", "bar"],
    "image_quality": {
        "min_resolution": [1000, 1400],
        "format_preference": ["jpeg"],
        "lighting": "soft",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["label_crop", "rotation_small", "brightness_variations"],
    "embedding_hint": "map to imported-lager category",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "imported"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'AMSTEL')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "God Father 500ml - Strong Beer",
    "description": "God Father 500ml — mass-market strong beer typically in darker bottle; label and font are important tokens.",
    "alt_text": "God Father 500ml beer bottle with bold label",
    "keywords": ["God Father beer", "500ml strong", "GodFather"],
    "canonical_name": "god_father_500",
    "synonyms": ["God Father 500 ML"],
    "dominant_colors": ["#4E342E", "#FFFFFF", "#FFC107"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss_label",
    "label_tokens": ["God Father", "bold_label"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "label_closeup"],
    "background_recommendation": ["plain_white", "store_shelf_context"],
    "image_quality": {
        "min_resolution": [1000, 1300],
        "format_preference": ["jpeg"],
        "lighting": "even",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["crop_label", "brightness_variation"],
    "embedding_hint": "map to ''strong'' and ''value'' clusters",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "strong"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'GOD FATHER')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Haywards 5000 500ml - Strong Lager Beer",
    "description": "Haywards 5000 500ml — India''s iconic strong lager beer known for its bold taste and red-gold branding. Popular across mass-market beer segments.",
    "alt_text": "Haywards 5000 500ml strong beer bottle with red and gold label",
    "keywords": ["Haywards 5000", "Haywards beer", "500ml strong beer", "India strong beer", "Haywards red label"],
    "canonical_name": "haywards_5000_500",
    "synonyms": ["Haywards 5000 500 ML", "Haywards Strong 5000", "Haywards Red Label"],
    "dominant_colors": ["#B71C1C", "#FDD835", "#000000", "#FFFFFF"],
    "shape": "standard_bottle",
    "material": "glass",
    "texture": "gloss_bottle_with_embossed_label",
    "label_tokens": ["Haywards", "5000", "Strong", "Red Label"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "slight_3_degree_left_angle", "label_macro_closeup", "top-down overhead for supermarket-catalog style"],
    "background_recommendation": ["plain_white", "studio_gray", "dark background with soft reflectors", "retail shelf environment for contextual ML"],
    "image_quality": {
        "min_resolution": [1200, 1600],
        "format_preference": ["jpeg", "png"],
        "lighting": "diffused_soft_front_light",
        "depth_of_field": "shallow_to_focus_label"
    },
    "augmentation_suggestions": ["crop_label_center", "slight_rotation_±4deg", "exposure_variations", "color temperature warm/cool adjustments", "background removal variations"],
    "embedding_hint": "map to ''strong lager'' cluster; emphasize ''5000'' token for variant separation",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "strong", "lager"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'HAYWARDS 5000')
AND size = '500ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Bro Code 330ml - Premium Beer",
    "description": "Bro Code 330ml — compact premium beer SKU used for modern brand cataloging. Include label text tokens for reliable matching.",
    "alt_text": "Bro Code 330ml beer bottle",
    "keywords": ["Bro Code 330", "BroCode 330ml", "premium 330"],
    "canonical_name": "bro_code_330",
    "synonyms": ["Bro Code 330 ML"],
    "dominant_colors": ["#263238", "#FFFFFF", "#FFC107"],
    "shape": "short_bottle",
    "material": "glass",
    "texture": "matte_label",
    "label_tokens": ["Bro Code", "logo_text"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "closeup_label"],
    "background_recommendation": ["plain_white", "restaurant_table"],
    "image_quality": {
        "min_resolution": [900, 1200],
        "format_preference": ["jpeg"],
        "lighting": "soft",
        "depth_of_field": "moderate"
    },
    "augmentation_suggestions": ["crop_label", "brightness_var"],
    "embedding_hint": "small-format premium SKU cluster",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "premium"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'BRO CODE')
AND size = '330ML';

UPDATE brand_variants
SET metadata = '{
    "title": "Corona 330ml - Imported Beer",
    "description": "Corona 330ml — iconic clear bottle with yellow label and lime-serving association. Tag for import and clear-glass recognition.",
    "alt_text": "Corona 330ml clear bottle with yellow label",
    "keywords": ["Corona 330", "Corona beer", "imported clear bottle", "lime"],
    "canonical_name": "corona_330",
    "synonyms": ["Corona 330 ML"],
    "dominant_colors": ["#FBC02D", "#FFFFFF", "#E0E0E0"],
    "shape": "long_clear_bottle",
    "material": "glass",
    "texture": "smooth",
    "label_tokens": ["Corona", "Imported", "Lemon association"],
    "barcode_expected": false,
    "shot_angles_recommendation": ["front_centered", "clear_bottle_side_light", "lime_prop_option"],
    "background_recommendation": ["plain_white", "beach_context"],
    "image_quality": {
        "min_resolution": [1200, 1600],
        "format_preference": ["jpeg", "png"],
        "lighting": "backlight_for_transparency",
        "depth_of_field": "shallow_to_moderate"
    },
    "augmentation_suggestions": ["transparency_handling", "contrast_var", "crop_label"],
    "embedding_hint": "map to ''imported clear bottle'' cluster and ''Corona'' canonical token",
    "taxonomy": ["beverages", "alcoholic_beverages", "beer", "imported"]
}'::jsonb
WHERE brand_id = (SELECT id FROM saas_brands WHERE name = 'CORONA')
AND size = '330ML';

COMMIT;

-- Verification
SELECT '=== METADATA UPDATE SUMMARY ===' as info;

SELECT
    b.name as "Brand",
    v.size as "Size",
    CASE WHEN v.metadata != '{}'::jsonb THEN 'Yes' ELSE 'No' END as "Has Metadata",
    v.metadata->>'canonical_name' as "Canonical Name"
FROM brand_variants v
JOIN saas_brands b ON v.brand_id = b.id
JOIN brand_categories c ON v.category_id = c.id
WHERE c.name = 'Beer'
ORDER BY b.name, v.size DESC;
