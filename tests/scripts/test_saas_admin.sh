#!/bin/bash

# SaaS Admin API Testing Script

echo "================================"
echo "SaaS Admin API Testing"
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

echo -e "\n${YELLOW}2. Testing Subscription Endpoints${NC}"
test_endpoint "Get All Subscriptions" "GET" "http://localhost:8095/api/super-admin/subscriptions"
test_endpoint "Get Subscriptions (admin)" "GET" "http://localhost:8095/admin/subscriptions"

echo -e "\n${YELLOW}3. Testing Tenant Management${NC}"
test_endpoint "Get All Tenants" "GET" "http://localhost:8095/api/super-admin/tenants"
test_endpoint "Get Tenant Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/tenants"

echo -e "\n${YELLOW}4. Testing Analytics Endpoints${NC}"
test_endpoint "Revenue Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/revenue?period=monthly"
test_endpoint "Subscription Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/subscriptions"
test_endpoint "User Analytics" "GET" "http://localhost:8095/api/super-admin/analytics/users"

echo -e "\n${YELLOW}5. Testing Plan Management${NC}"
test_endpoint "Get All Plans" "GET" "http://localhost:8095/api/super-admin/plans"
test_endpoint "Get Plan Details" "GET" "http://localhost:8095/api/super-admin/plans/basic"

echo -e "\n${YELLOW}6. Testing System Management${NC}"
test_endpoint "System Health" "GET" "http://localhost:8095/admin/system-health"
test_endpoint "Audit Logs" "GET" "http://localhost:8095/admin/audit-logs"
test_endpoint "System Stats" "GET" "http://localhost:8095/api/super-admin/stats"

echo -e "\n${YELLOW}7. Testing User Management${NC}"
test_endpoint "Get All Users (Cross-Tenant)" "GET" "http://localhost:8095/api/super-admin/users"
test_endpoint "Get Active Sessions" "GET" "http://localhost:8095/api/super-admin/sessions"

echo -e "\n${YELLOW}8. Testing Billing & Payments${NC}"
test_endpoint "Get All Payments" "GET" "http://localhost:8095/api/super-admin/payments"
test_endpoint "Get Pending Invoices" "GET" "http://localhost:8095/api/super-admin/invoices/pending"

echo -e "\n${YELLOW}9. Testing Maintenance Mode${NC}"
test_endpoint "Get Maintenance Status" "GET" "http://localhost:8095/admin/maintenance-mode"
test_endpoint "Toggle Maintenance" "POST" "http://localhost:8095/admin/maintenance-mode" '{"enabled":false}'

echo -e "\n${YELLOW}10. Testing Cache Management${NC}"
test_endpoint "Flush Cache" "POST" "http://localhost:8095/admin/cache/flush" '{}'

echo -e "\n================================"
echo "Testing Complete"
echo "================================"