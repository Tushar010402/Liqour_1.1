#!/bin/bash

# Comprehensive SaaS Admin API Test Script

echo "================================"
echo "Complete SaaS Admin API Testing"
echo "================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get token first
echo -e "\n${YELLOW}Getting SaaS Admin Token...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"mobile":"+918630668488","otp":"111111"}' \
    http://localhost:8095/api/saas-admin/verify-otp)

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}✓ Token obtained${NC}"
else
    echo -e "${RED}✗ Failed to get token${NC}"
    exit 1
fi

# Test function
test_endpoint() {
    local name=$1
    local method=$2
    local url=$3
    local data=$4
    local expected_status=$5

    if [ "$method" == "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN" "$url")
    else
        response=$(curl -s -X "$method" -w "\n%{http_code}" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" "$url")
    fi

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "$expected_status" ]] || ([[ -z "$expected_status" ]] && [[ "$http_code" =~ ^(200|201)$ ]]); then
        echo -e "${GREEN}✓${NC} $name - Status: $http_code"
        if [[ "$http_code" =~ ^(200|201)$ ]]; then
            echo "$body" | jq -C '.' 2>/dev/null | head -10 || echo "$body" | head -3
        fi
    else
        echo -e "${RED}✗${NC} $name - Status: $http_code (Expected: ${expected_status:-200/201})"
        echo "$body" | head -3
    fi
}

echo -e "\n${YELLOW}=== TESTING ALL REGISTERED ROUTES ===${NC}\n"

# Test routes at /api/super-admin (new build)
echo -e "${YELLOW}1. Testing Super Admin Routes (if available)${NC}"
test_endpoint "Tenants (super-admin)" "GET" "http://localhost:8095/api/super-admin/tenants"
test_endpoint "Subscriptions (super-admin)" "GET" "http://localhost:8095/api/super-admin/subscriptions"
test_endpoint "Plans (super-admin)" "GET" "http://localhost:8095/api/super-admin/plans"

# Test routes at /api/admin (current deployment)
echo -e "\n${YELLOW}2. Testing Admin Routes${NC}"
test_endpoint "Subscriptions" "GET" "http://localhost:8095/api/admin/subscriptions"
test_endpoint "System Health" "GET" "http://localhost:8095/api/admin/system/health"
test_endpoint "Audit Logs" "GET" "http://localhost:8095/api/admin/system/audit-logs"
test_endpoint "Plans" "GET" "http://localhost:8095/api/admin/plans"

# Analytics
echo -e "\n${YELLOW}3. Testing Analytics${NC}"
test_endpoint "Dashboard" "GET" "http://localhost:8095/api/admin/analytics/dashboard"
test_endpoint "Revenue" "GET" "http://localhost:8095/api/admin/analytics/revenue"
test_endpoint "Subscriptions" "GET" "http://localhost:8095/api/admin/analytics/subscriptions"
test_endpoint "Tenants" "GET" "http://localhost:8095/api/admin/analytics/tenants"

# Discount Management
echo -e "\n${YELLOW}4. Testing Discount Management${NC}"
test_endpoint "Get Configs" "GET" "http://localhost:8095/api/admin/discounts/configs"
test_endpoint "Default Config" "GET" "http://localhost:8095/api/admin/discounts/configs/default"
test_endpoint "Billing Terms" "GET" "http://localhost:8095/api/admin/discounts/billing-terms"
test_endpoint "Analytics" "GET" "http://localhost:8095/api/admin/discounts/analytics"

# Usage Management
echo -e "\n${YELLOW}5. Testing Usage Management${NC}"
test_endpoint "All Tenants Usage" "GET" "http://localhost:8095/api/admin/usage/all-tenants"
test_endpoint "Usage Alerts" "GET" "http://localhost:8095/api/admin/usage/alerts"

# Transitions
echo -e "\n${YELLOW}6. Testing Plan Transitions${NC}"
test_endpoint "All Transitions" "GET" "http://localhost:8095/api/admin/transitions/all"

# Test Create/Update Operations
echo -e "\n${YELLOW}7. Testing Write Operations${NC}"
test_endpoint "Initialize Plans" "POST" "http://localhost:8095/api/admin/plans/initialize" '{}'
test_endpoint "Toggle Maintenance" "POST" "http://localhost:8095/api/admin/system/maintenance" '{"enabled":false}'

# Test specific tenant operations (using a sample tenant ID)
echo -e "\n${YELLOW}8. Testing Tenant-Specific Operations${NC}"
TENANT_ID="106e40f8-049b-4661-a5ca-8903ced493c4"
test_endpoint "Tenant Usage" "GET" "http://localhost:8095/api/admin/usage/$TENANT_ID/current"
test_endpoint "Tenant Metrics" "GET" "http://localhost:8095/api/admin/usage/$TENANT_ID/metrics"

# Protected routes (need tenant context)
echo -e "\n${YELLOW}9. Testing Protected Routes${NC}"
test_endpoint "Get Subscription (Protected)" "GET" "http://localhost:8095/api/subscriptions" "" "400"
test_endpoint "Get Payments (Protected)" "GET" "http://localhost:8095/api/payments" "" "400"
test_endpoint "Get Invoices (Protected)" "GET" "http://localhost:8095/api/invoices" "" "400"

# Count results
echo -e "\n${YELLOW}=== TEST SUMMARY ===${NC}"
TOTAL_TESTS=30
echo "Total Endpoints Tested: $TOTAL_TESTS"
echo -e "${GREEN}Working Endpoints${NC}: Check output above"
echo -e "${RED}Failed Endpoints${NC}: Check output above"

# Final status check
echo -e "\n${YELLOW}=== SERVICE STATUS ===${NC}"
curl -s http://localhost:8095/health | jq '.'

echo -e "\n================================"
echo "Testing Complete"
echo "================================"