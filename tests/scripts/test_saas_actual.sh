#!/bin/bash

# Test actual SaaS admin endpoints as they are deployed

echo "================================"
echo "Testing Actual SaaS Admin APIs"
echo "================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get token first
echo -e "\n${YELLOW}1. Getting SaaS Admin Token...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"mobile":"+918630668488","otp":"111111"}' \
    http://localhost:8095/api/saas-admin/verify-otp)

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}✓ Token obtained${NC}"
    echo "Token: ${TOKEN:0:30}..."
else
    echo -e "${RED}✗ Failed to get token${NC}"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

# Test function
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
        echo -e "${GREEN}✓${NC} $name - Status: $http_code"
        echo "$body" | jq -C '.' 2>/dev/null || echo "$body"
    else
        echo -e "${RED}✗${NC} $name - Status: $http_code"
        echo "$body"
    fi
    echo "---"
}

echo -e "\n${YELLOW}2. Testing Health Check${NC}"
test_endpoint "Service Health" "GET" "http://localhost:8095/health"

echo -e "\n${YELLOW}3. Testing Public Endpoints${NC}"
test_endpoint "Get Public Plans" "GET" "http://localhost:8095/api/plans"

echo -e "\n${YELLOW}4. Testing Admin Endpoints (at /api/admin)${NC}"
test_endpoint "Get All Subscriptions" "GET" "http://localhost:8095/api/admin/subscriptions"
test_endpoint "System Health" "GET" "http://localhost:8095/api/admin/system/health"
test_endpoint "Audit Logs" "GET" "http://localhost:8095/api/admin/system/audit-logs"
test_endpoint "Toggle Maintenance" "POST" "http://localhost:8095/api/admin/system/maintenance" '{"enabled":false}'

echo -e "\n${YELLOW}5. Testing Analytics Endpoints${NC}"
test_endpoint "Dashboard" "GET" "http://localhost:8095/api/admin/analytics/dashboard"
test_endpoint "Revenue" "GET" "http://localhost:8095/api/admin/analytics/revenue"
test_endpoint "Subscriptions" "GET" "http://localhost:8095/api/admin/analytics/subscriptions"
test_endpoint "Tenants" "GET" "http://localhost:8095/api/admin/analytics/tenants"

echo -e "\n${YELLOW}6. Testing Tenant Management${NC}"
test_endpoint "Get All Tenants" "GET" "http://localhost:8095/api/admin/tenants"

echo -e "\n${YELLOW}7. Testing Plan Management${NC}"
test_endpoint "Get All Plans" "GET" "http://localhost:8095/api/admin/plans"
test_endpoint "Initialize Plans" "POST" "http://localhost:8095/api/admin/plans/initialize" '{}'

echo -e "\n${YELLOW}8. Testing Usage Management${NC}"
test_endpoint "Get All Tenants Usage" "GET" "http://localhost:8095/api/admin/usage/all-tenants"
test_endpoint "Get Usage Alerts" "GET" "http://localhost:8095/api/admin/usage/alerts"

echo -e "\n${YELLOW}9. Testing Discount Management${NC}"
test_endpoint "Get Discount Configs" "GET" "http://localhost:8095/api/admin/discounts/configs"
test_endpoint "Get Billing Terms" "GET" "http://localhost:8095/api/admin/discounts/billing-terms"

echo -e "\n${YELLOW}10. Testing Protected Routes (require tenant context)${NC}"
test_endpoint "Get Subscription" "GET" "http://localhost:8095/api/subscriptions"
test_endpoint "Get Payments" "GET" "http://localhost:8095/api/payments"
test_endpoint "Get Invoices" "GET" "http://localhost:8095/api/invoices"

echo -e "\n================================"
echo "Testing Complete"
echo "================================"

# Summary
echo -e "\n${YELLOW}Key Findings:${NC}"
echo "• Routes are at /api/admin/* not /api/super-admin/*"
echo "• Authentication is working"
echo "• Need to check if handlers are properly connected"