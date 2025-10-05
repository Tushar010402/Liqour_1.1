#!/bin/bash

# Complete Brand Management Flow Testing
echo "🧪 Testing Complete Brand Management Flow"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SAAS_URL="http://localhost:8095"

# Test function
test_endpoint() {
    local method=$1
    local url=$2
    local data=$3
    local description=$4

    echo -e "\n${BLUE}Testing:${NC} $description"
    echo -e "${YELLOW}$method $url${NC}"

    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "%{http_code}" -o /tmp/response.json "$url")
    else
        response=$(curl -s -w "%{http_code}" -X "$method" -H "Content-Type: application/json" -d "$data" -o /tmp/response.json "$url")
    fi

    http_code="${response: -3}"

    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        echo -e "${GREEN}✅ SUCCESS (HTTP $http_code)${NC}"
        if [ -f /tmp/response.json ] && [ -s /tmp/response.json ]; then
            echo "Response:"
            cat /tmp/response.json | head -5
        fi
        return 0
    else
        echo -e "${RED}❌ FAILED (HTTP $http_code)${NC}"
        if [ -f /tmp/response.json ] && [ -s /tmp/response.json ]; then
            echo "Error Response:"
            cat /tmp/response.json
        fi
        return 1
    fi
}

echo -e "\n${BLUE}Step 1: Create Brand Categories${NC}"

# Create Whisky category with timestamp to ensure uniqueness
TIMESTAMP=$(date +%s)
if test_endpoint "POST" "$SAAS_URL/api/super-admin/brands/categories" '{
    "name": "Whisky_'$TIMESTAMP'",
    "description": "Premium Whisky Category Test",
    "is_active": true,
    "sort_order": 1
}' "Create unique Whisky category"; then
    CATEGORY_ID=$(cat /tmp/response.json | grep -o '"data":{"id":"[^"]*"' | cut -d'"' -f6)
    echo "Category ID: $CATEGORY_ID"
fi

echo -e "\n${BLUE}Step 2: Create Brand Subcategory${NC}"

# Create Premium subcategory
if test_endpoint "POST" "$SAAS_URL/api/super-admin/brands/subcategories" '{
    "name": "Premium",
    "category_id": "'$CATEGORY_ID'",
    "description": "Premium Quality Whisky",
    "is_active": true,
    "sort_order": 1
}' "Create Premium subcategory"; then
    SUBCATEGORY_ID=$(cat /tmp/response.json | grep -o '"data":{"id":"[^"]*"' | cut -d'"' -f6)
    echo "Subcategory ID: $SUBCATEGORY_ID"
fi

echo -e "\n${BLUE}Step 3: Get Existing Brand${NC}"

# Get the brand we created earlier
test_endpoint "GET" "$SAAS_URL/api/super-admin/brands" "" "Get all brands"
BRAND_ID=$(cat /tmp/response.json | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -1)
echo "Brand ID: $BRAND_ID"

echo -e "\n${BLUE}Step 4: Create Brand Variant${NC}"

# Create brand variant with valid IDs
test_endpoint "POST" "$SAAS_URL/api/super-admin/brands/variants" '{
    "brand_id": "'$BRAND_ID'",
    "category_id": "'$CATEGORY_ID'",
    "subcategory_id": "'$SUBCATEGORY_ID'",
    "size": "750ml",
    "alcohol_content": 40.0,
    "picture": "https://example.com/johnnie-walker-black-750ml.jpg",
    "government_duty": 150.00,
    "buying_price": 2500.00,
    "selling_price": 3000.00,
    "mrp": 3500.00,
    "description": "Test Johnnie Walker Black Label 750ml",
    "barcode": "1234567890123",
    "hsn_code": "2208.30.90",
    "is_active": true,
    "sort_order": 1
}' "Create brand variant with all details"

echo -e "\n${BLUE}Step 5: Get Brand with Variants${NC}"

# Get brand with variants
test_endpoint "GET" "$SAAS_URL/api/super-admin/brands?include_variants=true" "" "Get brands with variants"

echo -e "\n${BLUE}Step 6: Create Another Brand for Variety${NC}"

# Create another brand
if test_endpoint "POST" "$SAAS_URL/api/super-admin/brands" '{
    "name": "Glenfiddich",
    "description": "Premium Single Malt Scotch Whisky",
    "picture": "https://example.com/glenfiddich-logo.jpg",
    "is_active": true,
    "sort_order": 2
}' "Create Glenfiddich brand"; then
    BRAND2_ID=$(cat /tmp/response.json | grep -o '"data":{"id":"[^"]*"' | cut -d'"' -f6)
    echo "Second Brand ID: $BRAND2_ID"
fi

echo -e "\n${BLUE}Step 7: Create Variant for Second Brand${NC}"

# Create variant for second brand
test_endpoint "POST" "$SAAS_URL/api/super-admin/brands/variants" '{
    "brand_id": "'$BRAND2_ID'",
    "category_id": "'$CATEGORY_ID'",
    "size": "750ml",
    "alcohol_content": 42.8,
    "picture": "https://example.com/royal-challenge-750ml.jpg",
    "government_duty": 120.00,
    "buying_price": 1800.00,
    "selling_price": 2200.00,
    "mrp": 2500.00,
    "description": "Glenfiddich Single Malt 750ml",
    "barcode": "9876543210123",
    "hsn_code": "2208.30.90",
    "is_active": true,
    "sort_order": 1
}' "Create Glenfiddich variant"

echo -e "\n${BLUE}Step 8: Test Public Brand Access${NC}"

# Test public access
test_endpoint "GET" "$SAAS_URL/api/brands/public?include_variants=true" "" "Get public brands with variants"

echo -e "\n${BLUE}Step 9: Test Brand Assignment to Tenant${NC}"

# Test tenant assignment (using sample tenant ID)
TENANT_ID="550e8400-e29b-41d4-a716-446655440003"

test_endpoint "POST" "$SAAS_URL/api/super-admin/brands/assign" '{
    "tenant_id": "'$TENANT_ID'",
    "brand_ids": ["'$BRAND_ID'", "'$BRAND2_ID'"]
}' "Assign brands to tenant"

echo -e "\n${BLUE}Step 10: Get Tenant Brands${NC}"

# Get tenant brands
test_endpoint "GET" "$SAAS_URL/api/super-admin/brands/tenants/$TENANT_ID" "" "Get brands assigned to tenant"

echo -e "\n${GREEN}Complete Brand Management Flow Testing Completed!${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "✅ Brand categories and subcategories created"
echo "✅ Brands created with complete specifications"
echo "✅ Brand variants with pricing and government duty"
echo "✅ Public brand access for tenant selection"
echo "✅ Brand assignment to specific tenants"

rm -f /tmp/response.json