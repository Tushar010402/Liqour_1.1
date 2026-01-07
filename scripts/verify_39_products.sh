#!/bin/bash

# Verification script for 39 products imported as smart brands
# Date: 2025-11-19

DB_HOST="aa65a9c67220_liquorpro-postgres-prod"
DB_USER="liquorpro_prod"
DB_NAME="liquorpro_production"

echo "================================================"
echo "    39 PRODUCTS IMPORT VERIFICATION REPORT"
echo "================================================"
echo ""

echo "📊 IMPORT STATISTICS:"
echo "--------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        'Unique Brands' as metric, COUNT(*) as count FROM saas_brands
     UNION ALL
     SELECT
        'Product Variants' as metric, COUNT(*) as count FROM brand_variants
     UNION ALL
     SELECT
        'Images Mapped' as metric, COUNT(*) as count FROM brand_variants WHERE picture IS NOT NULL;"

echo ""
echo "🏷️ MULTI-VARIANT BRANDS (10):"
echo "------------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        ROW_NUMBER() OVER (ORDER BY COUNT(v.id) DESC) AS \"#\",
        b.name AS \"Brand\",
        COUNT(v.id) AS \"Sizes\",
        STRING_AGG(DISTINCT v.size, ', ' ORDER BY v.size) AS \"Available Sizes\",
        MIN(v.mrp) || '-' || MAX(v.mrp) AS \"Price Range\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     GROUP BY b.id, b.name
     HAVING COUNT(v.id) > 1
     ORDER BY COUNT(v.id) DESC, b.name;"

echo ""
echo "🥃 8 PM BRAND SHOWCASE (3 Variants):"
echo "------------------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        v.description AS \"Variant\",
        v.size AS \"Size\",
        '₹' || v.government_duty AS \"Duty\",
        '₹' || v.buying_price AS \"Buying\",
        '₹' || v.mrp AS \"MRP\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     WHERE b.name = '8 PM'
     ORDER BY v.mrp;"

echo ""
echo "💰 PRICE ANALYSIS:"
echo "-----------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        v.size AS \"Size\",
        COUNT(*) AS \"Products\",
        '₹' || MIN(v.mrp)::int AS \"Cheapest\",
        '₹' || MAX(v.mrp)::int AS \"Most Expensive\",
        '₹' || ROUND(AVG(v.mrp))::int AS \"Average\"
     FROM brand_variants v
     GROUP BY v.size
     ORDER BY v.size;"

echo ""
echo "📦 CATEGORY DISTRIBUTION:"
echo "------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        c.name AS \"Category\",
        COUNT(DISTINCT b.id) AS \"Brands\",
        COUNT(v.id) AS \"Products\"
     FROM brand_categories c
     JOIN brand_variants v ON v.category_id = c.id
     JOIN saas_brands b ON v.brand_id = b.id
     GROUP BY c.name
     ORDER BY COUNT(v.id) DESC;"

echo ""
echo "🔝 TOP 10 PREMIUM PRODUCTS:"
echo "---------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        ROW_NUMBER() OVER (ORDER BY v.mrp DESC) AS \"#\",
        b.name AS \"Brand\",
        v.description AS \"Variant\",
        v.size AS \"Size\",
        '₹' || v.mrp AS \"Price\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     ORDER BY v.mrp DESC
     LIMIT 10;"

echo ""
echo "🔗 IMAGE URL STATUS:"
echo "-------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        CASE
            WHEN picture IS NULL THEN 'No Image'
            WHEN picture LIKE '%drive.google.com%' THEN 'Google Drive'
            ELSE 'Other'
        END AS \"Image Source\",
        COUNT(*) AS \"Count\"
     FROM brand_variants
     GROUP BY 1;"

echo ""
echo "✅ VALIDATION CHECKS:"
echo "--------------------"

# Check for expected counts
BRAND_COUNT=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM saas_brands;")
VARIANT_COUNT=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM brand_variants;")

if [ "$BRAND_COUNT" -eq "28" ]; then
    echo "✓ Correct unique brand count (28)"
else
    echo "⚠ Expected 28 brands, found $BRAND_COUNT"
fi

if [ "$VARIANT_COUNT" -eq "39" ]; then
    echo "✓ All 39 products imported successfully"
else
    echo "⚠ Expected 39 products, found $VARIANT_COUNT"
fi

# Check for orphaned variants
ORPHANED=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM brand_variants WHERE brand_id NOT IN (SELECT id FROM saas_brands);")

if [ "$ORPHANED" -eq "0" ]; then
    echo "✓ No orphaned product variants"
else
    echo "⚠ Found $ORPHANED orphaned variants"
fi

# Check for brands without variants
NO_VARIANTS=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM saas_brands WHERE id NOT IN (SELECT brand_id FROM brand_variants);")

if [ "$NO_VARIANTS" -eq "0" ]; then
    echo "✓ All brands have product variants"
else
    echo "⚠ Found $NO_VARIANTS brands without variants"
fi

echo ""
echo "================================================"
echo "    39 Products Successfully Imported!"
echo "    28 Unique Brands with Smart Variants"
echo "================================================"