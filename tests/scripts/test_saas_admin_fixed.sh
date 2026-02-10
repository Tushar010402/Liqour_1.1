#!/bin/bash

# SaaS Admin API Testing Script - Fixed Routes

echo "================================"
echo "SaaS Admin API Testing (Fixed)"
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
    echo "Token: ${TOKEN:0:20}..."
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

echo -e "\n${YELLOW}3. Testing Public Plan Endpoints${NC}"
test_endpoint "Get Public Plans" "GET" "http://localhost:8095/api/plans"
test_endpoint "Get Plans with Billing" "GET" "http://localhost:8095/api/plans/with-billing-options"

echo -e "\n${YELLOW}4. Testing Super Admin - Tenant Management${NC}"
test_endpoint "Get All Tenants" "GET" "http://localhost:8095/api/super-admin/tenants"

echo -e "\n${YELLOW}5. Testing Super Admin - Subscription Management${NC}"
test_endpoint "Get All Subscriptions" "GET" "http://localhost:8095/api/super-admin/subscriptions"

echo -e "\n${YELLOW}6. Testing Super Admin - Analytics${NC}"
test_endpoint "Dashboard Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/dashboard"
test_endpoint "Revenue Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/revenue"
test_endpoint "Subscription Metrics" "GET" "http://localhost:8095/api/super-admin/analytics/subscriptions"
test_endpoint "Tenant Metrics" "GET" "http://localhost:8095/api/super-admin/analytics/tenants"

echo -e "\n${YELLOW}7. Testing Super Admin - Plan Management${NC}"
test_endpoint "Get All Plans (Admin)" "GET" "http://localhost:8095/api/super-admin/plans"
test_endpoint "Initialize Default Plans" "POST" "http://localhost:8095/api/super-admin/plans/initialize" '{}'

echo -e "\n${YELLOW}8. Testing Super Admin - System Management${NC}"
test_endpoint "System Health" "GET" "http://localhost:8095/api/super-admin/system/health"
test_endpoint "Audit Logs" "GET" "http://localhost:8095/api/super-admin/system/audit-logs"
test_endpoint "Toggle Maintenance" "POST" "http://localhost:8095/api/super-admin/system/maintenance" '{"enabled":false}'

echo -e "\n${YELLOW}9. Testing Super Admin - Usage Management${NC}"
test_endpoint "Get All Tenants Usage" "GET" "http://localhost:8095/api/super-admin/usage/all-tenants"
test_endpoint "Get Usage Alerts" "GET" "http://localhost:8095/api/super-admin/usage/alerts"

echo -e "\n${YELLOW}10. Testing Super Admin - Discount Management${NC}"
test_endpoint "Get Global Discount Configs" "GET" "http://localhost:8095/api/super-admin/discounts/configs"
test_endpoint "Get Default Discount Config" "GET" "http://localhost:8095/api/super-admin/discounts/configs/default"
test_endpoint "Get Billing Terms" "GET" "http://localhost:8095/api/super-admin/discounts/billing-terms"
test_endpoint "Get Discount Analytics" "GET" "http://localhost:8095/api/super-admin/discounts/analytics"
test_endpoint "Initialize Discount Configs" "POST" "http://localhost:8095/api/super-admin/discounts/initialize" '{}'

echo -e "\n${YELLOW}11. Testing Super Admin - Plan Transitions${NC}"
test_endpoint "Get All Transitions" "GET" "http://localhost:8095/api/super-admin/transitions/all"

echo -e "\n${YELLOW}12. Testing Protected Routes (Tenant-level)${NC}"
test_endpoint "Get Subscription (Protected)" "GET" "http://localhost:8095/api/subscriptions"
test_endpoint "Get Payments (Protected)" "GET" "http://localhost:8095/api/payments"
test_endpoint "Get Invoices (Protected)" "GET" "http://localhost:8095/api/invoices"

echo -e "\n================================"
echo "Testing Complete"
echo "================================"

# Summary
echo -e "\n${YELLOW}Test Summary:${NC}"
echo "• Token Generation: ✓"
echo "• Routes are configured under /api/super-admin/*"
echo "• Public routes under /api/plans"
echo "• Protected tenant routes under /api/*"
echo "• Note: Some endpoints may need implementation in handlers"