#!/bin/bash

# Demonstration of Smart Brand UX Flow
# Shows how users interact with the new consolidated brand structure

DB_HOST="aa65a9c67220_liquorpro-postgres-prod"
DB_USER="liquorpro_prod"
DB_NAME="liquorpro_production"

clear
echo "==========================================="
echo "   SMART BRAND UX DEMONSTRATION"
echo "==========================================="
echo ""
echo "📦 OLD SYSTEM (39 Confusing Entries):"
echo "--------------------------------------"
echo "❌ 8 PM GOLD SCOTCH WHISKY 180ML"
echo "❌ 8 PM PREMIUM BLACK 180ML"
echo "❌ 8 PM SPECIAL BLEND 375ML"
echo "❌ MC DOWELLS NO.1 180ML"
echo "❌ MC DOWELLS NO.1 375ML"
echo "❌ IMPERIAL BLUE PREMIER GRAIN 180ML"
echo "❌ IMPERIAL BLUE PREMIER GRAIN 375ML"
echo "... and 32 more confusing entries"
echo ""
echo "Problems:"
echo "• Users see duplicate brand names"
echo "• Confusing to find the right size"
echo "• Hard to compare prices across sizes"
echo ""

read -p "Press Enter to see the NEW smart system..."
clear

echo "==========================================="
echo "   NEW SMART BRAND SYSTEM"
echo "==========================================="
echo ""
echo "✅ Step 1: Select Brand (28 unique brands)"
echo "-------------------------------------------"

# Show unique brands
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        ROW_NUMBER() OVER (ORDER BY sort_order) AS \"#\",
        name AS \"Brand Name\",
        description AS \"Description\"
     FROM saas_brands
     LIMIT 10;" 2>/dev/null

echo ""
echo "User selects: 8 PM"
echo ""
read -p "Press Enter to see variants..."

echo ""
echo "✅ Step 2: Choose Variant & Size"
echo "---------------------------------"
echo "Available variants for 8 PM:"
echo ""

sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        v.description AS \"Variant\",
        v.size AS \"Size\",
        '₹' || v.mrp AS \"Price\",
        CASE
            WHEN v.mrp = 120 THEN '★ Best Value'
            WHEN v.mrp = 170 THEN '★★ Premium'
            WHEN v.mrp = 240 THEN '★★★ Large Pack'
        END AS \"Tag\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     WHERE b.name = '8 PM'
     ORDER BY v.mrp;" 2>/dev/null

echo ""
echo "Benefits of New System:"
echo "✓ Clear brand selection"
echo "✓ Easy size comparison"
echo "✓ Price transparency"
echo "✓ Better user experience"
echo ""

read -p "Press Enter to see another example..."
clear

echo "==========================================="
echo "   EXAMPLE 2: MC DOWELLS NO.1"
echo "==========================================="
echo ""
echo "Old System: Two separate entries"
echo "---------------------------------"
echo "❌ MC DOWELLS NO.1 180ML"
echo "❌ MC DOWELLS NO.1 375ML"
echo ""
echo "New System: One brand, multiple sizes"
echo "--------------------------------------"

sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "SELECT
        'MC DOWELLS NO.1' AS \"Brand\",
        v.size AS \"Size Options\",
        '₹' || v.mrp AS \"Price\",
        '₹' || ROUND((v.mrp::float /
            CASE v.size
                WHEN '180ML' THEN 180
                WHEN '375ML' THEN 375
            END * 1000)::numeric, 2) AS \"Per Liter\"
     FROM saas_brands b
     JOIN brand_variants v ON b.id = v.brand_id
     WHERE b.name = 'MC DOWELLS NO.1'
     ORDER BY v.size;" 2>/dev/null

echo ""
echo "User can easily compare:"
echo "• 180ML at ₹150 = ₹833/liter"
echo "• 375ML at ₹310 = ₹826/liter"
echo "➜ 375ML offers better value!"
echo ""

read -p "Press Enter to see the summary..."
clear

echo "==========================================="
echo "   SMART BRAND CONSOLIDATION SUMMARY"
echo "==========================================="
echo ""

# Show statistics
echo "📊 IMPROVEMENT METRICS:"
echo "----------------------"
echo -n "Brand Count Reduction: "
echo "39 → 28 (28% reduction)"
echo -n "Brands with Multiple Sizes: "
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(DISTINCT brand_id) FROM brand_variants GROUP BY brand_id HAVING COUNT(*) > 1;" | xargs
echo -n "Total Product Variants: "
echo "39 (preserved all products)"
echo ""

echo "🎯 USER EXPERIENCE IMPROVEMENTS:"
echo "--------------------------------"
echo "✅ Cleaner brand list (no duplicates)"
echo "✅ Intuitive size selection"
echo "✅ Easy price comparison"
echo "✅ Better search & filtering"
echo "✅ Simplified inventory management"
echo ""

echo "💼 BUSINESS BENEFITS:"
echo "--------------------"
echo "• Easier brand onboarding for tenants"
echo "• Consistent brand naming"
echo "• Better OCR matching accuracy"
echo "• Simplified reporting"
echo "• Scalable for adding new sizes"
echo ""

echo "==========================================="
echo "   Smart Brand System Ready!"
echo "==========================================="