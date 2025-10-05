#!/bin/bash

# UP Excise Compliance - Complete Test Script
# Tests all excise endpoints with realistic data

BASE_URL="http://localhost:8093"
EXCISE_API="$BASE_URL/api/excise"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "============================================"
echo "UP EXCISE COMPLIANCE - COMPLETE TEST SUITE"
echo "============================================"
echo ""

# Counter for tests
PASSED=0
FAILED=0

# Function to test an endpoint
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="$4"
    local expected_status="$5"

    echo -e "${BLUE}Testing:${NC} $name"

    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" "$endpoint")
    fi

    # Extract status code and body
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASSED${NC} - HTTP $http_code"
        echo "Response: $body" | head -c 200
        echo ""
        echo ""
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} - Expected HTTP $expected_status, got $http_code"
        echo "Response: $body"
        echo ""
        ((FAILED++))
        return 1
    fi
}

echo "=== HEALTH CHECK ==="
test_endpoint "Health Check" "GET" "$EXCISE_API/health" "" "200"

echo "=== LICENSE MANAGEMENT ==="

# Test 1: Create License (will fail without tenant_id in context, but tests the endpoint)
LICENSE_DATA='{
  "shop_id": "550e8400-e29b-41d4-a716-446655440000",
  "license_number": "UP-FL2A-2025-0001",
  "license_type": "FL-2A",
  "monthly_fee": 50000.00
}'
test_endpoint "Create License (No Auth)" "POST" "$EXCISE_API/licenses" "$LICENSE_DATA" "401"

echo "=== DAILY REPORTS ==="

# Test: Auto-generate daily report
REPORT_DATA='{
  "shop_id": "550e8400-e29b-41d4-a716-446655440000",
  "report_date": "2025-10-02T00:00:00Z"
}'
test_endpoint "Auto-Generate Daily Report (No Auth)" "POST" "$EXCISE_API/daily-reports/auto-generate" "$REPORT_DATA" "401"

# Test: Get daily reports
test_endpoint "Get Daily Reports (No Auth)" "GET" "$EXCISE_API/daily-reports" "" "401"

echo "=== SECURITY CODES ==="

# Test: Validate security code
VALIDATE_DATA='{
  "security_code": "UP2025ABC123456"
}'
test_endpoint "Validate Security Code (No Auth)" "POST" "$EXCISE_API/security-codes/validate" "$VALIDATE_DATA" "401"

# Test: Bulk add security codes
BULK_ADD_DATA='{
  "product_id": "550e8400-e29b-41d4-a716-446655440001",
  "security_codes": ["UP2025ABC123456", "UP2025ABC123457", "UP2025ABC123458"]
}'
test_endpoint "Bulk Add Security Codes (No Auth)" "POST" "$EXCISE_API/security-codes/bulk-add" "$BULK_ADD_DATA" "401"

# Test: Get security code stats
test_endpoint "Get Security Code Stats (No Auth)" "GET" "$EXCISE_API/security-codes/stats" "" "401"

echo "=== COMPLIANCE ==="

# Test: Get compliance dashboard
test_endpoint "Get Compliance Dashboard (No Auth)" "GET" "$EXCISE_API/compliance/dashboard" "" "401"

# Test: Get compliance logs
test_endpoint "Get Compliance Logs (No Auth)" "GET" "$EXCISE_API/compliance/logs" "" "401"

# Test: Get expiring licenses
test_endpoint "Get Expiring Licenses (No Auth)" "GET" "$EXCISE_API/compliance/expiring-licenses" "" "401"

# Test: Get consideration fee summary
test_endpoint "Get Consideration Fee Summary (No Auth)" "GET" "$EXCISE_API/compliance/consideration-fees" "" "401"

echo ""
echo "============================================"
echo "TEST SUMMARY"
echo "============================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo ""
    echo "📋 All endpoints are responding correctly (401 = Auth required, as expected)"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Add authentication middleware configuration"
    echo "   2. Create test tenant and shop data"
    echo "   3. Test with valid authentication tokens"
    echo "   4. Test complete license creation → daily report → portal upload flow"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    exit 1
fi
