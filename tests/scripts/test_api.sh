#!/bin/bash

# LiquorPro API Testing Script
set -e

echo "🍾 LiquorPro API Comprehensive Testing"
echo "======================================"

# Configuration
GATEWAY_URL="http://localhost:8090"
AUTH_URL="http://localhost:8091"
SALES_URL="http://localhost:8092"
INVENTORY_URL="http://localhost:8093"
FINANCE_URL="http://localhost:8094"

# Test results file
RESULTS_FILE="test_results.json"
echo '{"tests": [], "summary": {"total": 0, "passed": 0, "failed": 0}}' > $RESULTS_FILE

# Helper function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_status="$3"
    
    echo "🧪 Testing: $test_name"
    
    # Run the test with timeout
    if timeout 10s bash -c "$test_command"; then
        echo "✅ PASSED: $test_name"
        # Update results file
        jq --arg name "$test_name" --arg status "passed" '.tests += [{"name": $name, "status": $status}] | .summary.passed += 1 | .summary.total += 1' $RESULTS_FILE > tmp.json && mv tmp.json $RESULTS_FILE
        return 0
    else
        echo "❌ FAILED: $test_name"
        # Update results file
        jq --arg name "$test_name" --arg status "failed" '.tests += [{"name": $name, "status": $status}] | .summary.failed += 1 | .summary.total += 1' $RESULTS_FILE > tmp.json && mv tmp.json $RESULTS_FILE
        return 1
    fi
}

# Test 1: Health Checks
echo -e "\n📋 PHASE 1: HEALTH CHECK TESTING"
echo "================================="

run_test "Gateway Health Check" '
    response=$(curl -s -w "%{http_code}" http://localhost:8090/gateway/health)
    status_code="${response: -3}"
    if [ "$status_code" = "200" ]; then
        echo "Gateway is healthy"
        exit 0
    else
        echo "Gateway health check failed with status: $status_code"
        exit 1
    fi
'

run_test "Auth Service Health Check" '
    response=$(curl -s -w "%{http_code}" http://localhost:8091/health)
    status_code="${response: -3}"
    if [ "$status_code" = "200" ]; then
        echo "Auth service is healthy"
        exit 0
    else
        echo "Auth service health check failed with status: $status_code"
        exit 1
    fi
'

run_test "Sales Service Health Check" '
    response=$(curl -s -w "%{http_code}" http://localhost:8092/health)
    status_code="${response: -3}"
    if [ "$status_code" = "200" ]; then
        echo "Sales service is healthy"
        exit 0
    else
        echo "Sales service health check failed with status: $status_code"
        exit 1
    fi
'

# Test 2: Authentication Flow
echo -e "\n🔐 PHASE 2: AUTHENTICATION TESTING"
echo "=================================="

# Store tokens for later use
ADMIN_TOKEN=""
MANAGER_TOKEN=""
SALESMAN_TOKEN=""

run_test "User Registration" '
    response=$(curl -s -w "%{http_code}" -X POST http://localhost:8090/api/auth/register \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"admin1\",
            \"email\": \"admin1@liquidtest.com\",
            \"password\": \"SecurePass123!\",
            \"first_name\": \"Test\",
            \"last_name\": \"Admin\",
            \"phone\": \"+1234567890\",
            \"tenant_name\": \"Test Liquor Store\",
            \"company_name\": \"Test Liquor Store LLC\"
        }")
    
    status_code="${response: -3}"
    response_body="${response%???}"
    
    if [ "$status_code" = "201" ] || [ "$status_code" = "200" ]; then
        echo "User registration successful"
        # Extract token if present
        token=$(echo "$response_body" | jq -r ".token // empty")
        if [ ! -z "$token" ] && [ "$token" != "null" ]; then
            echo "$token" > admin_token.txt
            echo "Admin token saved"
        fi
        exit 0
    else
        echo "Registration failed with status: $status_code"
        echo "Response: $response_body"
        exit 1
    fi
'

run_test "User Login" '
    response=$(curl -s -w "%{http_code}" -X POST http://localhost:8090/api/auth/login \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"admin1\",
            \"password\": \"SecurePass123!\"
        }")
    
    status_code="${response: -3}"
    response_body="${response%???}"
    
    if [ "$status_code" = "200" ]; then
        echo "Login successful"
        # Extract and save token
        token=$(echo "$response_body" | jq -r ".token // empty")
        if [ ! -z "$token" ] && [ "$token" != "null" ]; then
            echo "$token" > admin_token.txt
            echo "Admin token updated"
        fi
        exit 0
    else
        echo "Login failed with status: $status_code"
        echo "Response: $response_body"
        exit 1
    fi
'

# Test 3: Admin Setup
echo -e "\n🏗️ PHASE 3: ADMIN SETUP TESTING"
echo "==============================="

run_test "Create Shop" '
    if [ -f admin_token.txt ]; then
        ADMIN_TOKEN=$(cat admin_token.txt)
        response=$(curl -s -w "%{http_code}" -X POST http://localhost:8090/api/admin/shops \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Main Test Store\",
                \"address\": \"123 Test Street, Test City\",
                \"phone\": \"+1234567890\",
                \"license_number\": \"LIC-TEST-001\"
            }")
        
        status_code="${response: -3}"
        response_body="${response%???}"
        
        if [ "$status_code" = "201" ] || [ "$status_code" = "200" ]; then
            echo "Shop created successfully"
            # Save shop ID
            shop_id=$(echo "$response_body" | jq -r ".id // empty")
            if [ ! -z "$shop_id" ] && [ "$shop_id" != "null" ]; then
                echo "$shop_id" > shop_id.txt
            fi
            exit 0
        else
            echo "Shop creation failed with status: $status_code"
            echo "Response: $response_body"
            exit 1
        fi
    else
        echo "No admin token available"
        exit 1
    fi
'

# Test 4: Inventory Setup
echo -e "\n📦 PHASE 4: INVENTORY SETUP"
echo "==========================="

run_test "Create Category" '
    if [ -f admin_token.txt ]; then
        ADMIN_TOKEN=$(cat admin_token.txt)
        response=$(curl -s -w "%{http_code}" -X POST http://localhost:8090/api/inventory/categories \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Whiskey\",
                \"description\": \"All types of whiskey products\"
            }")
        
        status_code="${response: -3}"
        response_body="${response%???}"
        
        if [ "$status_code" = "201" ] || [ "$status_code" = "200" ]; then
            echo "Category created successfully"
            # Save category ID
            category_id=$(echo "$response_body" | jq -r ".id // empty")
            if [ ! -z "$category_id" ] && [ "$category_id" != "null" ]; then
                echo "$category_id" > category_id.txt
            fi
            exit 0
        else
            echo "Category creation failed with status: $status_code"
            echo "Response: $response_body"
            exit 1
        fi
    else
        echo "No admin token available"
        exit 1
    fi
'

# Test 5: Error Scenarios
echo -e "\n⚠️ PHASE 5: ERROR SCENARIO TESTING"
echo "=================================="

run_test "Invalid Login Credentials" '
    response=$(curl -s -w "%{http_code}" -X POST http://localhost:8090/api/auth/login \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"invaliduser\",
            \"password\": \"invalidpass\"
        }")
    
    status_code="${response: -3}"
    
    if [ "$status_code" = "401" ] || [ "$status_code" = "400" ]; then
        echo "Invalid login correctly rejected"
        exit 0
    else
        echo "Invalid login should have been rejected but got status: $status_code"
        exit 1
    fi
'

run_test "Unauthorized Access" '
    response=$(curl -s -w "%{http_code}" -X GET http://localhost:8090/api/auth/profile)
    status_code="${response: -3}"
    
    if [ "$status_code" = "401" ]; then
        echo "Unauthorized access correctly rejected"
        exit 0
    else
        echo "Unauthorized access should have been rejected but got status: $status_code"
        exit 1
    fi
'

# Final Results
echo -e "\n📊 TESTING COMPLETED"
echo "===================="

# Read results
if [ -f "$RESULTS_FILE" ]; then
    total=$(jq -r '.summary.total' $RESULTS_FILE)
    passed=$(jq -r '.summary.passed' $RESULTS_FILE)
    failed=$(jq -r '.summary.failed' $RESULTS_FILE)
    
    echo "Total Tests: $total"
    echo "Passed: $passed"
    echo "Failed: $failed"
    
    if [ "$failed" -eq 0 ]; then
        echo "✅ All tests passed!"
        success_rate=100
    else
        success_rate=$(( passed * 100 / total ))
        echo "⚠️ Some tests failed. Success rate: ${success_rate}%"
    fi
    
    # Display failed tests
    if [ "$failed" -gt 0 ]; then
        echo -e "\n❌ Failed Tests:"
        jq -r '.tests[] | select(.status == "failed") | "- " + .name' $RESULTS_FILE
    fi
    
    # Display passed tests
    if [ "$passed" -gt 0 ]; then
        echo -e "\n✅ Passed Tests:"
        jq -r '.tests[] | select(.status == "passed") | "- " + .name' $RESULTS_FILE
    fi
else
    echo "❌ No results file found"
fi

echo -e "\n📄 Detailed results saved to: $RESULTS_FILE"
echo "🏁 Testing complete!"