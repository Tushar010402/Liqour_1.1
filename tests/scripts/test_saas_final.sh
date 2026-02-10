#!/bin/bash

# Final Comprehensive SaaS Admin API Test

echo "================================"
echo "Final SaaS Admin API Test Suite"
echo "================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0

# Get token first
echo -e "\n${YELLOW}Authentication...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"mobile":"+918630668488","otp":"111111"}' \
    http://localhost:8095/api/saas-admin/verify-otp)

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}✓ Authentication successful${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Authentication failed${NC}"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

# Test function with counter
test_endpoint() {
    local name=$1
    local method=$2
    local url=$3
    local data=$4

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

    if [[ "$http_code" =~ ^(200|201)$ ]]; then
        echo -e "${GREEN}✓${NC} $name"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $name (Status: $http_code)"
        ((FAIL++))
    fi
}

echo -e "\n${YELLOW}Core Services...${NC}"
test_endpoint "Health Check" "GET" "http://localhost:8095/health"

echo -e "\n${YELLOW}Tenant Management...${NC}"
test_endpoint "Get All Tenants" "GET" "http://localhost:8095/api/super-admin/tenants"

echo -e "\n${YELLOW}Subscription Management...${NC}"
test_endpoint "Get All Subscriptions" "GET" "http://localhost:8095/api/super-admin/subscriptions"
SUBSCRIPTION_ID="67271e43-6479-45f6-b174-f1007bd4fe0d"
test_endpoint "Get Subscription Details" "GET" "http://localhost:8095/api/super-admin/subscriptions/$SUBSCRIPTION_ID"

echo -e "\n${YELLOW}Plan Management...${NC}"
test_endpoint "Get All Plans" "GET" "http://localhost:8095/api/super-admin/plans"
test_endpoint "Get Public Plans" "GET" "http://localhost:8095/api/plans"
test_endpoint "Get Plans with Billing" "GET" "http://localhost:8095/api/plans/with-billing-options"
test_endpoint "Create Plan" "POST" "http://localhost:8095/api/super-admin/plans" '{
    "name": "test_plan_api",
    "display_name": "Test Plan API",
    "description": "Test plan created via API",
    "price": 2999,
    "currency": "INR",
    "billing_cycle": "monthly",
    "trial_days": 7,
    "max_locations": 3,
    "max_users": 10,
    "max_products": 2000,
    "features": ["inventory", "sales"],
    "active": true
}'

echo -e "\n${YELLOW}Analytics...${NC}"
test_endpoint "Dashboard Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/dashboard"
test_endpoint "Revenue Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/revenue"
test_endpoint "Subscription Metrics" "GET" "http://localhost:8095/api/super-admin/analytics/subscriptions"
test_endpoint "Tenant Metrics" "GET" "http://localhost:8095/api/super-admin/analytics/tenants"

echo -e "\n${YELLOW}System Management...${NC}"
test_endpoint "System Health" "GET" "http://localhost:8095/api/super-admin/system/health"
test_endpoint "Audit Logs" "GET" "http://localhost:8095/api/super-admin/system/audit-logs"
test_endpoint "Toggle Maintenance Mode" "POST" "http://localhost:8095/api/super-admin/system/maintenance" '{"enabled":false}'

echo -e "\n${YELLOW}Usage Tracking...${NC}"
test_endpoint "All Tenants Usage" "GET" "http://localhost:8095/api/super-admin/usage/all-tenants"
test_endpoint "Usage Alerts" "GET" "http://localhost:8095/api/super-admin/usage/alerts"
TENANT_ID="106e40f8-049b-4661-a5ca-8903ced493c4"
test_endpoint "Specific Tenant Usage" "GET" "http://localhost:8095/api/super-admin/usage/$TENANT_ID/current"
test_endpoint "Tenant Usage Metrics" "GET" "http://localhost:8095/api/super-admin/usage/$TENANT_ID/metrics"

echo -e "\n${YELLOW}Discount Management...${NC}"
test_endpoint "Global Discount Configs" "GET" "http://localhost:8095/api/super-admin/discounts/configs"
test_endpoint "Default Discount Config" "GET" "http://localhost:8095/api/super-admin/discounts/configs/default"
test_endpoint "Billing Terms" "GET" "http://localhost:8095/api/super-admin/discounts/billing-terms"
test_endpoint "Discount Analytics" "GET" "http://localhost:8095/api/super-admin/discounts/analytics"
test_endpoint "Initialize Discounts" "POST" "http://localhost:8095/api/super-admin/discounts/initialize" '{}'

echo -e "\n${YELLOW}Plan Transitions...${NC}"
test_endpoint "All Transitions" "GET" "http://localhost:8095/api/super-admin/transitions/all"
test_endpoint "Preview Transition" "POST" "http://localhost:8095/api/super-admin/transitions/preview" '{
    "subscription_id": "'$SUBSCRIPTION_ID'",
    "target_plan_id": "df387387-c0d0-4c0a-a462-e85120b51ce0",
    "effective_date": "2025-10-01"
}'

echo -e "\n${YELLOW}Protected Endpoints (should require tenant context)...${NC}"
# These should return 400 as they need tenant context
response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN" "http://localhost:8095/api/subscriptions")
http_code=$(echo "$response" | tail -1)
if [[ "$http_code" == "400" ]]; then
    echo -e "${GREEN}✓${NC} Protected route correctly requires tenant context"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Protected route not working correctly (Status: $http_code)"
    ((FAIL++))
fi

echo -e "\n================================"
echo -e "${YELLOW}TEST RESULTS SUMMARY${NC}"
echo "================================"
echo -e "Total Tests: $((PASS + FAIL))"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"

if [ $FAIL -eq 0 ]; then
    echo -e "\n${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo "SaaS Admin APIs are 100% functional!"
else
    echo -e "\n${YELLOW}⚠️ Some tests failed - see details above${NC}"
    PERCENTAGE=$((PASS * 100 / (PASS + FAIL)))
    echo "Success Rate: ${PERCENTAGE}%"
fi

echo -e "\n================================"
echo "Testing Complete"
echo "================================"