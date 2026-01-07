#!/bin/bash

# Verification script for 39 master brands
# This script verifies that all brands are correctly set up

DB_HOST="aa65a9c67220_liquorpro-postgres-prod"
DB_USER="liquorpro_prod"
DB_NAME="liquorpro_production"

echo "======================================"
echo "LiquorPro Brand Verification Report"
echo "======================================"
echo ""

# Total counts
echo "📊 BRAND STATISTICS:"
echo "-------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT 'Total Brands: ' || COUNT(*) FROM saas_brands;"

sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT 'Total Variants: ' || COUNT(*) FROM brand_variants;"

echo ""
echo "📦 BRAND DISTRIBUTION BY CATEGORY:"
echo "-----------------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT c.name AS category, COUNT(DISTINCT b.id) AS brand_count
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     JOIN brand_categories c ON v.category_id = c.id
     GROUP BY c.name ORDER BY brand_count DESC;"

echo ""
echo "📏 BRAND DISTRIBUTION BY SIZE:"
echo "------------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT v.size, COUNT(DISTINCT b.id) AS brand_count
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     GROUP BY v.size ORDER BY v.size;"

echo ""
echo "💰 PRICE RANGE ANALYSIS:"
echo "------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        size,
        MIN(selling_price)::numeric(10,2) AS min_price,
        MAX(selling_price)::numeric(10,2) AS max_price,
        AVG(selling_price)::numeric(10,2) AS avg_price
     FROM brand_variants
     GROUP BY size ORDER BY size;"

echo ""
echo "🎯 TOP 10 BRANDS BY MRP:"
echo "------------------------"
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT b.name, v.size, v.mrp
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     ORDER BY v.mrp DESC LIMIT 10;"

echo ""
echo "✅ VERIFICATION CHECKS:"
echo "----------------------"

# Check for brands without variants
ORPHANED_BRANDS=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM saas_brands b
     WHERE NOT EXISTS (SELECT 1 FROM brand_variants v WHERE v.brand_id = b.id);")

if [ "$ORPHANED_BRANDS" -eq "0" ]; then
    echo "✓ All brands have variants"
else
    echo "⚠ Found $ORPHANED_BRANDS brands without variants"
fi

# Check for variants without pricing
NO_PRICE_VARIANTS=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM brand_variants
     WHERE selling_price IS NULL OR selling_price = 0;")

if [ "$NO_PRICE_VARIANTS" -eq "0" ]; then
    echo "✓ All variants have pricing information"
else
    echo "⚠ Found $NO_PRICE_VARIANTS variants without pricing"
fi

# Check brand count
BRAND_COUNT=$(sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM saas_brands;")

if [ "$BRAND_COUNT" -eq "39" ]; then
    echo "✓ Correct number of brands (39)"
else
    echo "⚠ Expected 39 brands, found $BRAND_COUNT"
fi

echo ""
echo "======================================"
echo "Verification Complete"
echo "======================================"