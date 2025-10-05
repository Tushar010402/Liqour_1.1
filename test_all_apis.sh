#!/bin/bash

BASE_URL="http://localhost:8095"
LOG_FILE="api_test_results.log"

# Initialize log
echo "=== COMPLETE SaaS API TESTING - $(date) ===" > $LOG_FILE

# Function to get fresh token
get_token() {
    curl -s -X POST "$BASE_URL/api/saas-admin/demo-login" \
      -H "Content-Type: application/json" \
      -d '{"mobile": "8630668488"}' | jq -r '.token // "ERROR"'
}

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local auth_required=${4:-false}
    local data=${5:-""}
    
    echo "Testing: $method $endpoint - $description"
    echo "Testing: $method $endpoint - $description" >> $LOG_FILE
    
    if [ "$auth_required" = true ]; then
        TOKEN=$(get_token)
        if [ "$TOKEN" = "ERROR" ]; then
            echo "❌ Failed to get token for $endpoint" | tee -a $LOG_FILE
            return 1
        fi
        
        if [ -n "$data" ]; then
            response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X $method "$BASE_URL$endpoint" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "$data")
        else
            response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X $method "$BASE_URL$endpoint" \
                -H "Authorization: Bearer $TOKEN")
        fi
    else
        if [ -n "$data" ]; then
            response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X $method "$BASE_URL$endpoint" \
                -H "Content-Type: application/json" \
                -d "$data")
        else
            response=$(curl -s -w "HTTP_STATUS:%{http_code}" -X $method "$BASE_URL$endpoint")
        fi
    fi
    
    # Extract HTTP status
    http_code=$(echo "$response" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed 's/HTTP_STATUS:[0-9]*$//')
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "✅ $http_code - SUCCESS" | tee -a $LOG_FILE
        echo "$body" | head -2 >> $LOG_FILE
    elif [ "$http_code" -ge 400 ] && [ "$http_code" -lt 500 ]; then
        echo "⚠️ $http_code - CLIENT ERROR" | tee -a $LOG_FILE
        echo "$body" | head -1 >> $LOG_FILE
    else
        echo "❌ $http_code - SERVER ERROR" | tee -a $LOG_FILE
        echo "$body" | head -1 >> $LOG_FILE
    fi
    
    echo "" >> $LOG_FILE
    sleep 0.1  # Rate limiting
}

# PUBLIC ROUTES
echo "=== TESTING PUBLIC ROUTES ==="
test_endpoint "GET" "/health" "Health Check" false
test_endpoint "GET" "/api/plans" "Public Plans" false
test_endpoint "GET" "/api/plans/with-billing-options" "Plans with Billing Options" false
test_endpoint "GET" "/api/plans/7bf1db64-60d3-4825-8a14-204fd2d242b6/billing-options" "Plan Billing Options" false
test_endpoint "GET" "/api/plans/7bf1db64-60d3-4825-8a14-204fd2d242b6/billing-variants" "Plan Billing Variants" false
test_endpoint "GET" "/api/plans/7bf1db64-60d3-4825-8a14-204fd2d242b6/calculate" "Calculate Plan Pricing" false

# SAAS ADMIN AUTH ROUTES
echo "=== TESTING SAAS ADMIN AUTH ROUTES ==="
test_endpoint "POST" "/api/saas-admin/is-admin" "Is Admin Check" false '{"mobile": "8630668488"}'
test_endpoint "POST" "/api/saas-admin/send-otp" "Send OTP" false '{"mobile": "8630668488"}'
test_endpoint "POST" "/api/saas-admin/verify-otp" "Verify OTP" false '{"mobile": "8630668488", "otp": "111111"}'
test_endpoint "POST" "/api/saas-admin/demo-login" "Demo Login" false '{"mobile": "8630668488"}'

# PROTECTED SUBSCRIPTION ROUTES
echo "=== TESTING PROTECTED SUBSCRIPTION ROUTES ==="
test_endpoint "GET" "/api/subscriptions" "Get Subscription (tenant)" true
test_endpoint "POST" "/api/subscriptions" "Create Subscription" true '{"plan_id": "7bf1db64-60d3-4825-8a14-204fd2d242b6", "tenant_id": "7b223f84-2acd-4e58-b94c-60e344bec5a1"}'

# ADMIN ROUTES - PLANS
echo "=== TESTING ADMIN PLAN ROUTES ==="
test_endpoint "GET" "/api/admin/plans" "Get Admin Plans" true
test_endpoint "GET" "/api/admin/plans/7bf1db64-60d3-4825-8a14-204fd2d242b6" "Get Specific Plan" true
test_endpoint "GET" "/api/admin/plans/7bf1db64-60d3-4825-8a14-204fd2d242b6/features" "Get Plan Features" true
test_endpoint "POST" "/api/admin/plans/initialize" "Initialize Default Plans" true

# ADMIN ROUTES - SUBSCRIPTIONS
echo "=== TESTING ADMIN SUBSCRIPTION ROUTES ==="
test_endpoint "GET" "/api/admin/subscriptions" "Get All Subscriptions" true
test_endpoint "GET" "/api/admin/subscriptions/828b3f66-e346-47bb-9498-0949fd71a7a9" "Get Subscription Details" true

# ADMIN ROUTES - DISCOUNTS
echo "=== TESTING ADMIN DISCOUNT ROUTES ==="
test_endpoint "GET" "/api/admin/discounts/configs" "Get Discount Configs" true
test_endpoint "GET" "/api/admin/discounts/configs/default" "Get Default Discount Config" true
test_endpoint "GET" "/api/admin/discounts/billing-terms" "Get Billing Term Configs" true
test_endpoint "GET" "/api/admin/discounts/analytics" "Get Discount Analytics" true
test_endpoint "POST" "/api/admin/discounts/initialize" "Initialize Discount Configs" true

# ADMIN ROUTES - ANALYTICS
echo "=== TESTING ADMIN ANALYTICS ROUTES ==="
test_endpoint "GET" "/api/admin/analytics/dashboard" "Analytics Dashboard" true
test_endpoint "GET" "/api/admin/analytics/revenue" "Revenue Analytics" true
test_endpoint "GET" "/api/admin/analytics/subscriptions" "Subscription Metrics" true
test_endpoint "GET" "/api/admin/analytics/tenants" "Tenant Metrics" true

# ADMIN ROUTES - SYSTEM
echo "=== TESTING ADMIN SYSTEM ROUTES ==="
test_endpoint "GET" "/api/admin/system/health" "System Health" true
test_endpoint "GET" "/api/admin/system/audit-logs" "Audit Logs" true
test_endpoint "POST" "/api/admin/system/maintenance" "Toggle Maintenance" true '{"enabled": false}'

# ADMIN ROUTES - USAGE
echo "=== TESTING ADMIN USAGE ROUTES ==="
test_endpoint "GET" "/api/admin/usage/7b223f84-2acd-4e58-b94c-60e344bec5a1/current" "Get Current Usage" true
test_endpoint "GET" "/api/admin/usage/7b223f84-2acd-4e58-b94c-60e344bec5a1/metrics" "Get Usage Metrics" true
test_endpoint "GET" "/api/admin/usage/all-tenants" "Get All Tenants Usage" true
test_endpoint "GET" "/api/admin/usage/alerts" "Get Usage Alerts" true

# ADMIN ROUTES - TRANSITIONS
echo "=== TESTING ADMIN TRANSITION ROUTES ==="
test_endpoint "POST" "/api/admin/transitions/preview" "Preview Transition" true '{"subscription_id": "828b3f66-e346-47bb-9498-0949fd71a7a9", "new_plan_id": "21521211-def8-4022-a1f2-d1e9ecad9cd9"}'
test_endpoint "GET" "/api/admin/transitions/subscription/828b3f66-e346-47bb-9498-0949fd71a7a9/history" "Get Transition History" true
test_endpoint "GET" "/api/admin/transitions/subscription/828b3f66-e346-47bb-9498-0949fd71a7a9/available" "Get Available Transitions" true

echo "=== TESTING COMPLETE ==="
echo "Results saved to: $LOG_FILE"
echo ""
echo "SUMMARY:"
grep -E "(✅|⚠️|❌)" $LOG_FILE | sort | uniq -c