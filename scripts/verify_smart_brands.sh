#!/bin/bash

# Smart Brand Verification Script
# Verifies the consolidated brand structure with proper variants

DB_HOST="aa65a9c67220_liquorpro-postgres-prod"
DB_USER="liquorpro_prod"
DB_NAME="liquorpro_production"

echo "========================================="
echo "    SMART BRAND STRUCTURE REPORT"
echo "========================================="
echo ""

# Summary Statistics
echo "📊 BRAND STATISTICS:"
echo "-------------------"
echo -n "Unique Brands: "
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM saas_brands;" | xargs

echo -n "Total Variants: "
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM brand_variants;" | xargs

echo -n "Avg Variants per Brand: "
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT ROUND(AVG(variant_count), 2) FROM (
        SELECT COUNT(*) as variant_count
        FROM brand_variants
        GROUP BY brand_id
    ) as counts;" | xargs

echo ""
echo "📦 MULTI-VARIANT BRANDS:"
echo "------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        b.name AS \"Brand\",
        COUNT(v.id) AS \"Variants\",
        STRING_AGG(v.size, ', ' ORDER BY v.size) AS \"Available Sizes\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     GROUP BY b.id, b.name
     HAVING COUNT(v.id) > 1
     ORDER BY COUNT(v.id) DESC, b.name;"

echo ""
echo "🏷️ BRAND SHOWCASE - 8 PM (3 Variants):"
echo "---------------------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        v.description AS \"Variant\",
        v.size AS \"Size\",
        '₹' || v.mrp AS \"MRP\",
        '₹' || v.buying_price AS \"Buying Price\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     WHERE b.name = '8 PM'
     ORDER BY v.size, v.description;"

echo ""
echo "📈 PRICE ANALYSIS BY SIZE:"
echo "-------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        v.size AS \"Size\",
        COUNT(*) AS \"Products\",
        '₹' || MIN(v.mrp)::int AS \"Min Price\",
        '₹' || MAX(v.mrp)::int AS \"Max Price\",
        '₹' || ROUND(AVG(v.mrp))::int AS \"Avg Price\"
     FROM brand_variants v
     GROUP BY v.size
     ORDER BY v.size;"

echo ""
echo "🔍 CATEGORY DISTRIBUTION:"
echo "------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        c.name AS \"Category\",
        COUNT(DISTINCT b.id) AS \"Brands\",
        COUNT(v.id) AS \"Total Variants\"
     FROM brand_categories c
     JOIN brand_variants v ON v.category_id = c.id
     JOIN saas_brands b ON v.brand_id = b.id
     GROUP BY c.name
     ORDER BY COUNT(DISTINCT b.id) DESC;"

echo ""
echo "✅ VALIDATION CHECKS:"
echo "--------------------"

# Check for orphaned variants
ORPHANED=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM brand_variants v
     WHERE NOT EXISTS (SELECT 1 FROM saas_brands b WHERE b.id = v.brand_id);")

if [ "$ORPHANED" -eq "0" ]; then
    echo "✓ No orphaned variants"
else
    echo "⚠ Found $ORPHANED orphaned variants"
fi

# Check for brands without variants
NO_VARIANTS=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM saas_brands b
     WHERE NOT EXISTS (SELECT 1 FROM brand_variants v WHERE v.brand_id = b.id);")

if [ "$NO_VARIANTS" -eq "0" ]; then
    echo "✓ All brands have variants"
else
    echo "⚠ Found $NO_VARIANTS brands without variants"
fi

# Check total variant count
VARIANT_COUNT=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM brand_variants;")

if [ "$VARIANT_COUNT" -eq "39" ]; then
    echo "✓ Correct total variants (39)"
else
    echo "⚠ Expected 39 variants, found $VARIANT_COUNT"
fi

# Check unique brand count (should be less than 39 now)
BRAND_COUNT=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM saas_brands;")

if [ "$BRAND_COUNT" -lt "39" ]; then
    echo "✓ Successfully consolidated brands ($BRAND_COUNT unique brands from 39 products)"
else
    echo "⚠ Brand consolidation may have issues: $BRAND_COUNT brands"
fi

echo ""
echo "========================================="
echo "    Smart Brand Structure Verified!"
echo "========================================="