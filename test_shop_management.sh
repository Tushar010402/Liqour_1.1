#!/bin/bash

# Shop Management Complete Integration Test
# Tests the full shop management flow: authentication, list, create, update

set -e  # Exit on error

echo "============================================"
echo "Shop Management Integration Test"
echo "============================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Base URL
BASE_URL="http://localhost:8090"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test results
print_test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((TESTS_FAILED++))
    fi
}

# Helper function to check JSON response
check_json() {
    if echo "$1" | jq empty 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

echo "Step 1: Authenticate and get token"
echo "-----------------------------------"

# Send OTP
echo "Sending OTP to +919999992020..."
OTP_RESPONSE=$(curl -s -X POST "$BASE_URL/api/auth/send-otp" \
  -H "Content-Type: application/json" \
  -d '{"mobile":"+919999992020"}')

check_json "$OTP_RESPONSE"
print_test_result $? "Send OTP - Valid JSON response"

SESSION_ID=$(echo "$OTP_RESPONSE" | jq -r '.session_id')
if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
    print_test_result 0 "Send OTP - Session ID received"
    echo "Session ID: $SESSION_ID"
else
    print_test_result 1 "Send OTP - Session ID received"
    echo "OTP Response: $OTP_RESPONSE"
    exit 1
fi

echo ""
echo "Verifying OTP..."
VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/api/auth/verify-otp" \
  -H "Content-Type: application/json" \
  -d "{\"mobile\":\"+919999992020\",\"otp\":\"000000\",\"session_id\":\"$SESSION_ID\"}")

check_json "$VERIFY_RESPONSE"
print_test_result $? "Verify OTP - Valid JSON response"

TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.token')
TENANT_ID=$(echo "$VERIFY_RESPONSE" | jq -r '.tenant.id')

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    print_test_result 0 "Verify OTP - Token received"
    echo "Token (first 50 chars): ${TOKEN:0:50}..."
    echo "Tenant ID: $TENANT_ID"
else
    print_test_result 1 "Verify OTP - Token received"
    echo "Verify Response: $VERIFY_RESPONSE"
    exit 1
fi

echo ""
echo "Step 2: Get existing shops"
echo "-----------------------------------"

SHOPS_RESPONSE=$(curl -s -X GET "$BASE_URL/api/admin/shops" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Content-Type: application/json")

check_json "$SHOPS_RESPONSE"
print_test_result $? "Get Shops - Valid JSON response"

# Check if it's an array
if echo "$SHOPS_RESPONSE" | jq -e 'type == "array"' >/dev/null 2>&1; then
    print_test_result 0 "Get Shops - Response is array"
    SHOP_COUNT=$(echo "$SHOPS_RESPONSE" | jq 'length')
    echo "Current shops count: $SHOP_COUNT"
    echo "$SHOPS_RESPONSE" | jq '.'
else
    print_test_result 1 "Get Shops - Response is array"
    echo "Response: $SHOPS_RESPONSE"
fi

echo ""
echo "Step 3: Create a new shop"
echo "-----------------------------------"

CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/admin/shops" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Shop API",
    "address": "123 Test Street, Test City",
    "phone": "+919999999999",
    "license_number": "TEST123456",
    "latitude": 28.6139,
    "longitude": 77.2090
  }')

check_json "$CREATE_RESPONSE"
print_test_result $? "Create Shop - Valid JSON response"

SHOP_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')
if [ -n "$SHOP_ID" ] && [ "$SHOP_ID" != "null" ]; then
    print_test_result 0 "Create Shop - Shop ID received"
    echo "Created Shop ID: $SHOP_ID"
    echo "$CREATE_RESPONSE" | jq '.'
else
    print_test_result 1 "Create Shop - Shop ID received"
    echo "Create Response: $CREATE_RESPONSE"
fi

echo ""
echo "Step 4: Get shop by ID"
echo "-----------------------------------"

if [ -n "$SHOP_ID" ] && [ "$SHOP_ID" != "null" ]; then
    SHOP_DETAIL=$(curl -s -X GET "$BASE_URL/api/admin/shops/$SHOP_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-Tenant-ID: $TENANT_ID" \
      -H "Content-Type: application/json")

    check_json "$SHOP_DETAIL"
    print_test_result $? "Get Shop by ID - Valid JSON response"

    SHOP_NAME=$(echo "$SHOP_DETAIL" | jq -r '.name')
    if [ "$SHOP_NAME" = "Test Shop API" ]; then
        print_test_result 0 "Get Shop by ID - Correct shop name"
    else
        print_test_result 1 "Get Shop by ID - Correct shop name"
    fi
    echo "$SHOP_DETAIL" | jq '.'
fi

echo ""
echo "Step 5: Update shop"
echo "-----------------------------------"

if [ -n "$SHOP_ID" ] && [ "$SHOP_ID" != "null" ]; then
    UPDATE_RESPONSE=$(curl -s -X PUT "$BASE_URL/api/admin/shops/$SHOP_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-Tenant-ID: $TENANT_ID" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "Test Shop API - Updated",
        "address": "456 Updated Street, Test City",
        "phone": "+918888888888",
        "license_number": "TEST123456",
        "latitude": 28.6139,
        "longitude": 77.2090,
        "is_active": true
      }')

    check_json "$UPDATE_RESPONSE"
    print_test_result $? "Update Shop - Valid JSON response"

    UPDATED_NAME=$(echo "$UPDATE_RESPONSE" | jq -r '.name')
    if [ "$UPDATED_NAME" = "Test Shop API - Updated" ]; then
        print_test_result 0 "Update Shop - Name updated correctly"
    else
        print_test_result 1 "Update Shop - Name updated correctly"
    fi
    echo "$UPDATE_RESPONSE" | jq '.'
fi

echo ""
echo "Step 6: Verify updated shop in list"
echo "-----------------------------------"

FINAL_SHOPS=$(curl -s -X GET "$BASE_URL/api/admin/shops" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Content-Type: application/json")

FINAL_COUNT=$(echo "$FINAL_SHOPS" | jq 'length')
echo "Final shops count: $FINAL_COUNT"

if [ $FINAL_COUNT -gt $SHOP_COUNT ]; then
    print_test_result 0 "List Shops - New shop appears in list"
else
    print_test_result 1 "List Shops - New shop appears in list"
fi

echo ""
echo "============================================"
echo "Test Summary"
echo "============================================"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo ""
    echo "Shop management is working 100%!"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    exit 1
fi
