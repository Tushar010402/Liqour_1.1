#!/bin/bash

# COMPREHENSIVE SAAS ADMIN API TEST - 100% Coverage
# This script tests ALL endpoints with CORRECT parameters

echo "=========================================="
echo "COMPREHENSIVE SAAS ADMIN API TEST SUITE"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL=0
PASS=0
FAIL=0

# Base URL
BASE_URL="http://localhost:8095"

# ==================== AUTHENTICATION ====================
echo -e "\n${BLUE}=== AUTHENTICATION ===${NC}"

# Get authentication token
TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"mobile":"+918630668488","otp":"111111"}' \
    $BASE_URL/api/saas-admin/verify-otp)

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
USER_ID=$(echo "$TOKEN_RESPONSE" | grep -o '"user_id":"[^"]*' | cut -d'"' -f4 || echo "default-admin-id")

if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}✓ Authentication successful${NC}"
    echo "Token: ${TOKEN:0:30}..."
    ((PASS++))
else
    echo -e "${RED}✗ Authentication failed${NC}"
    echo "Response: $TOKEN_RESPONSE"
    ((FAIL++))
    exit 1
fi
((TOTAL++))

# Test function
test_endpoint() {
    local name=$1
    local method=$2
    local url=$3
    local data=$4
    local expected_status=$5

    ((TOTAL++))

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

    if [[ -z "$expected_status" ]]; then
        expected_status="200|201"
    fi

    if [[ "$http_code" =~ ^($expected_status)$ ]]; then
        echo -e "${GREEN}✓${NC} $name (${http_code})"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $name (${http_code} - Expected: $expected_status)"
        echo "   Error: $(echo $body | jq -r '.error' 2>/dev/null || echo $body)"
        ((FAIL++))
    fi
}

# ==================== HEALTH CHECK ====================
echo -e "\n${BLUE}=== HEALTH CHECK ===${NC}"
test_endpoint "Service Health" "GET" "$BASE_URL/health"

# ==================== PUBLIC ENDPOINTS ====================
echo -e "\n${BLUE}=== PUBLIC ENDPOINTS ===${NC}"
test_endpoint "Get Public Plans" "GET" "$BASE_URL/api/plans"
test_endpoint "Plans with Billing Options" "GET" "$BASE_URL/api/plans/with-billing-options"

# ==================== TENANT MANAGEMENT ====================
echo -e "\n${BLUE}=== TENANT MANAGEMENT ===${NC}"
test_endpoint "Get All Tenants" "GET" "$BASE_URL/api/super-admin/tenants"

# ==================== SUBSCRIPTION MANAGEMENT ====================
echo -e "\n${BLUE}=== SUBSCRIPTION MANAGEMENT ===${NC}"
test_endpoint "Get All Subscriptions" "GET" "$BASE_URL/api/super-admin/subscriptions"
test_endpoint "Get Subscription Details" "GET" "$BASE_URL/api/super-admin/subscriptions/67271e43-6479-45f6-b174-f1007bd4fe0d"
test_endpoint "Update Subscription Status" "PUT" "$BASE_URL/api/super-admin/subscriptions/67271e43-6479-45f6-b174-f1007bd4fe0d/status" '{
    "status": "active",
    "reason": "Manual activation"
}'

# ==================== PLAN MANAGEMENT ====================
echo -e "\n${BLUE}=== PLAN MANAGEMENT ===${NC}"
test_endpoint "Get All Admin Plans" "GET" "$BASE_URL/api/super-admin/plans"
test_endpoint "Get Specific Plan" "GET" "$BASE_URL/api/super-admin/plans/20f458ed-6fce-459f-a76f-3bc74708dcd6"
test_endpoint "Get Plan Features" "GET" "$BASE_URL/api/super-admin/plans/20f458ed-6fce-459f-a76f-3bc74708dcd6/features"
test_endpoint "Create New Plan" "POST" "$BASE_URL/api/super-admin/plans" '{
    "name": "test_plan_'$(date +%s)'",
    "display_name": "Test Plan",
    "description": "Test plan for API testing",
    "price": 3999,
    "currency": "INR",
    "billing_cycle": "monthly",
    "trial_days": 14,
    "max_locations": 5,
    "max_users": 15,
    "max_products": 3000,
    "features": ["inventory", "sales", "reports"],
    "active": true
}'
test_endpoint "Initialize Default Plans" "POST" "$BASE_URL/api/super-admin/plans/initialize" '{}'

# ==================== ANALYTICS ====================
echo -e "\n${BLUE}=== ANALYTICS ===${NC}"
test_endpoint "Dashboard Analytics" "GET" "$BASE_URL/api/super-admin/analytics/dashboard"
test_endpoint "Revenue Analytics" "GET" "$BASE_URL/api/super-admin/analytics/revenue"
test_endpoint "Subscription Metrics" "GET" "$BASE_URL/api/super-admin/analytics/subscriptions"
test_endpoint "Tenant Metrics" "GET" "$BASE_URL/api/super-admin/analytics/tenants"

# ==================== SYSTEM MANAGEMENT ====================
echo -e "\n${BLUE}=== SYSTEM MANAGEMENT ===${NC}"
test_endpoint "System Health" "GET" "$BASE_URL/api/super-admin/system/health"
test_endpoint "Audit Logs" "GET" "$BASE_URL/api/super-admin/system/audit-logs"
test_endpoint "Toggle Maintenance Mode" "POST" "$BASE_URL/api/super-admin/system/maintenance" '{
    "enabled": false,
    "message": "System maintenance"
}'

# ==================== USAGE TRACKING ====================
echo -e "\n${BLUE}=== USAGE TRACKING ===${NC}"
test_endpoint "All Tenants Usage" "GET" "$BASE_URL/api/super-admin/usage/all-tenants"
test_endpoint "Usage Alerts" "GET" "$BASE_URL/api/super-admin/usage/alerts"

# Test with specific tenant and resource type
TENANT_ID="106e40f8-049b-4661-a5ca-8903ced493c4"
test_endpoint "Tenant Current Usage" "GET" "$BASE_URL/api/super-admin/usage/$TENANT_ID/current?resource_type=users"
test_endpoint "Tenant Usage Metrics" "GET" "$BASE_URL/api/super-admin/usage/$TENANT_ID/metrics"
test_endpoint "Tenant Usage History" "GET" "$BASE_URL/api/super-admin/usage/$TENANT_ID/history"
test_endpoint "Billing Period Usage" "GET" "$BASE_URL/api/super-admin/usage/$TENANT_ID/billing-period"
test_endpoint "Track Usage Event" "POST" "$BASE_URL/api/super-admin/usage/$TENANT_ID/track" '{
    "resource_type": "products",
    "action": "create",
    "quantity": 1,
    "metadata": "test product creation"
}'

# ==================== DISCOUNT MANAGEMENT ====================
echo -e "\n${BLUE}=== DISCOUNT MANAGEMENT ===${NC}"
test_endpoint "Global Discount Configs" "GET" "$BASE_URL/api/super-admin/discounts/configs"
test_endpoint "Default Discount Config" "GET" "$BASE_URL/api/super-admin/discounts/configs/default"
test_endpoint "Billing Terms" "GET" "$BASE_URL/api/super-admin/discounts/billing-terms"
test_endpoint "Discount Analytics" "GET" "$BASE_URL/api/super-admin/discounts/analytics"
test_endpoint "Initialize Discount Configs" "POST" "$BASE_URL/api/super-admin/discounts/initialize" '{}'
test_endpoint "Create Discount Config" "POST" "$BASE_URL/api/super-admin/discounts/configs" '{
    "name": "Summer Sale",
    "discount_type": "percentage",
    "value": 20,
    "valid_from": "2025-06-01T00:00:00Z",
    "valid_to": "2025-08-31T23:59:59Z",
    "applicable_plans": ["all"],
    "is_active": true
}'

# ==================== PLAN TRANSITIONS ====================
echo -e "\n${BLUE}=== PLAN TRANSITIONS ===${NC}"
test_endpoint "Get All Transitions" "GET" "$BASE_URL/api/super-admin/transitions/all"
test_endpoint "Get Transition History" "GET" "$BASE_URL/api/super-admin/transitions/subscription/67271e43-6479-45f6-b174-f1007bd4fe0d/history"
test_endpoint "Available Transitions" "GET" "$BASE_URL/api/super-admin/transitions/subscription/67271e43-6479-45f6-b174-f1007bd4fe0d/available"
test_endpoint "Preview Plan Transition" "POST" "$BASE_URL/api/super-admin/transitions/preview" '{
    "subscription_id": "67271e43-6479-45f6-b174-f1007bd4fe0d",
    "new_plan_id": "df387387-c0d0-4c0a-a462-e85120b51ce0",
    "transition_type": "UPGRADE",
    "effective_date": "2025-10-01T00:00:00Z",
    "proration_mode": "IMMEDIATE",
    "reason": "Customer requested upgrade"
}'
test_endpoint "Initiate Plan Transition" "POST" "$BASE_URL/api/super-admin/transitions/initiate" '{
    "subscription_id": "67271e43-6479-45f6-b174-f1007bd4fe0d",
    "new_plan_id": "df387387-c0d0-4c0a-a462-e85120b51ce0",
    "transition_type": "UPGRADE",
    "effective_date": "2025-10-01T00:00:00Z",
    "proration_mode": "END_OF_PERIOD",
    "reason": "Testing transition"
}'

# ==================== PROTECTED ENDPOINTS ====================
echo -e "\n${BLUE}=== PROTECTED ENDPOINTS (Should fail with 400) ===${NC}"
test_endpoint "Get Subscription (Protected)" "GET" "$BASE_URL/api/subscriptions" "" "400"
test_endpoint "Get Payments (Protected)" "GET" "$BASE_URL/api/payments" "" "400"
test_endpoint "Get Invoices (Protected)" "GET" "$BASE_URL/api/invoices" "" "400"

# ==================== PAYMENT ENDPOINTS ====================
echo -e "\n${BLUE}=== PAYMENT MANAGEMENT ===${NC}"
test_endpoint "Create Payment" "POST" "$BASE_URL/api/payments" '{
    "subscription_id": "67271e43-6479-45f6-b174-f1007bd4fe0d",
    "amount": 4999,
    "currency": "INR",
    "payment_method": "razorpay",
    "status": "pending"
}' "400"

# ==================== EDGE CASES ====================
echo -e "\n${BLUE}=== EDGE CASES ===${NC}"
test_endpoint "Invalid UUID" "GET" "$BASE_URL/api/super-admin/subscriptions/invalid-uuid" "" "400"
test_endpoint "Non-existent Resource" "GET" "$BASE_URL/api/super-admin/subscriptions/00000000-0000-0000-0000-000000000000" "" "404"

# ==================== SUMMARY ====================
echo -e "\n${BLUE}=========================================="
echo "          TEST RESULTS SUMMARY"
echo "==========================================${NC}"

SUCCESS_RATE=$((PASS * 100 / TOTAL))
echo -e "Total Tests: ${TOTAL}"
echo -e "Passed: ${GREEN}${PASS}${NC}"
echo -e "Failed: ${RED}${FAIL}${NC}"
echo -e "Success Rate: ${SUCCESS_RATE}%"

if [ $SUCCESS_RATE -eq 100 ]; then
    echo -e "\n${GREEN}✅ PERFECT! All SaaS Admin APIs are working 100%!${NC}"
elif [ $SUCCESS_RATE -ge 90 ]; then
    echo -e "\n${GREEN}✅ EXCELLENT! SaaS Admin APIs are ${SUCCESS_RATE}% functional${NC}"
elif [ $SUCCESS_RATE -ge 80 ]; then
    echo -e "\n${YELLOW}⚠️ GOOD! SaaS Admin APIs are ${SUCCESS_RATE}% functional${NC}"
else
    echo -e "\n${RED}❌ NEEDS ATTENTION! Only ${SUCCESS_RATE}% of APIs are working${NC}"
fi

echo -e "\n=========================================="
echo "Testing Complete - $(date)"
echo "=========================================="