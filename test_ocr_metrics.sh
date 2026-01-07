#!/bin/bash

# OCR Metrics Testing Script
# Tests dynamic metrics endpoints and displays real-time performance statistics

set -e

echo "📊 OCR Metrics Test Suite"
echo "=============================="
echo ""

# Configuration
API_BASE="https://liquorpro.retailpulse.tech/api/sales"
AUTH_BASE="https://liquorpro.retailpulse.tech/api/auth"
TEST_PHONE="8126816664"
TEST_OTP="000000"  # Development mode OTP
TOKEN=""

# Function to login with OTP
login() {
    echo "🔐 Step 1: Authenticating with OTP..."

    # Send OTP
    SEND_RESPONSE=$(curl -s -X POST "$AUTH_BASE/send-otp" \
        -H "Content-Type: application/json" \
        -d "{\"mobile\": \"$TEST_PHONE\"}")

    SESSION_ID=$(echo $SEND_RESPONSE | jq -r '.session_id')

    if [ "$SESSION_ID" = "null" ] || [ -z "$SESSION_ID" ]; then
        echo "❌ Failed to send OTP"
        echo "Response: $SEND_RESPONSE"
        exit 1
    fi

    echo "✅ OTP sent successfully"

    # Verify OTP and get token
    VERIFY_RESPONSE=$(curl -s -X POST "$AUTH_BASE/verify-otp" \
        -H "Content-Type: application/json" \
        -d "{
            \"mobile\": \"$TEST_PHONE\",
            \"otp\": \"$TEST_OTP\",
            \"session_id\": \"$SESSION_ID\"
        }")

    TOKEN=$(echo $VERIFY_RESPONSE | jq -r '.token')

    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        echo "❌ Authentication failed"
        echo "Response: $VERIFY_RESPONSE"
        exit 1
    fi

    USER_NAME=$(echo $VERIFY_RESPONSE | jq -r '.user.first_name')
    USER_ROLE=$(echo $VERIFY_RESPONSE | jq -r '.user.role')

    echo "✅ Authentication successful!"
    echo "   User: $USER_NAME ($USER_ROLE)"
    echo ""
}

# Function to get and display metrics
get_metrics() {
    echo "📊 Step 2: Fetching OCR metrics..."
    echo ""

    RESPONSE=$(curl -s -X GET "$API_BASE/ocr/metrics" \
        -H "Authorization: Bearer $TOKEN")

    # Check if request was successful
    SUCCESS=$(echo $RESPONSE | jq -r '.success')

    if [ "$SUCCESS" != "true" ]; then
        echo "❌ Failed to fetch metrics"
        echo "Response: $RESPONSE"
        exit 1
    fi

    # Extract metrics data
    DATA=$(echo $RESPONSE | jq -r '.data')

    # Save to file for detailed analysis
    echo "$DATA" > /tmp/ocr_metrics.json

    echo "✅ Metrics retrieved successfully"
    echo ""
    echo "=============================="
    echo "📈 OCR PERFORMANCE METRICS"
    echo "=============================="
    echo ""

    # System Overview
    echo "🖥️  SYSTEM OVERVIEW"
    echo "   Uptime: $(echo $DATA | jq -r '.uptime')"
    echo "   Start Time: $(echo $DATA | jq -r '.start_time')"
    echo "   Last Request: $(echo $DATA | jq -r '.last_request_time')"
    echo ""

    # Request Statistics
    echo "📥 REQUEST STATISTICS"
    TOTAL_REQUESTS=$(echo $DATA | jq -r '.total_requests')
    SUCCESSFUL=$(echo $DATA | jq -r '.successful_requests')
    FAILED=$(echo $DATA | jq -r '.failed_requests')
    SUCCESS_RATE=$(echo $DATA | jq -r '.success_rate_percent')

    echo "   Total Requests: $TOTAL_REQUESTS"
    echo "   Successful: $SUCCESSFUL"
    echo "   Failed: $FAILED"
    echo "   Success Rate: ${SUCCESS_RATE}%"
    echo ""

    # Performance Metrics
    echo "⚡ PERFORMANCE METRICS"
    AVG_TIME=$(echo $DATA | jq -r '.avg_processing_time_ms')
    MIN_TIME=$(echo $DATA | jq -r '.min_processing_time_ms')
    MAX_TIME=$(echo $DATA | jq -r '.max_processing_time_ms')

    echo "   Average Processing Time: ${AVG_TIME}ms ($(echo "scale=2; $AVG_TIME/1000" | bc)s)"
    echo "   Min Processing Time: ${MIN_TIME}ms"
    echo "   Max Processing Time: ${MAX_TIME}ms"
    echo ""

    # Accuracy Metrics
    echo "🎯 ACCURACY METRICS"
    TOTAL_ITEMS=$(echo $DATA | jq -r '.total_items_extracted')
    VALID=$(echo $DATA | jq -r '.valid_items')
    INVALID=$(echo $DATA | jq -r '.invalid_items')
    ACCURACY=$(echo $DATA | jq -r '.accuracy_rate_percent')

    echo "   Total Items Extracted: $TOTAL_ITEMS"
    echo "   Valid Items: $VALID"
    echo "   Invalid Items: $INVALID"
    echo "   Accuracy Rate: ${ACCURACY}%"
    echo ""

    # Cleaning Statistics
    echo "🧹 CLEANING STATISTICS"
    WITH_GARBAGE=$(echo $DATA | jq -r '.items_with_garbage')
    CLEANED=$(echo $DATA | jq -r '.items_cleaned')
    CLEANING_RATE=$(echo $DATA | jq -r '.cleaning_rate_percent')

    echo "   Items with Garbage: $WITH_GARBAGE"
    echo "   Items Cleaned: $CLEANED"
    echo "   Cleaning Rate: ${CLEANING_RATE}%"
    echo ""

    # API Health
    echo "🏥 API HEALTH"
    echo ""
    echo "   Vision API:"
    VISION_TOTAL=$(echo $DATA | jq -r '.vision_api_calls_total')
    VISION_FAILED=$(echo $DATA | jq -r '.vision_api_calls_failed')
    VISION_SUCCESS=$(echo $DATA | jq -r '.vision_success_rate_percent')
    echo "     Total Calls: $VISION_TOTAL"
    echo "     Failed: $VISION_FAILED"
    echo "     Success Rate: ${VISION_SUCCESS}%"
    echo ""

    echo "   Gemini API:"
    GEMINI_TOTAL=$(echo $DATA | jq -r '.gemini_api_calls_total')
    GEMINI_FAILED=$(echo $DATA | jq -r '.gemini_api_calls_failed')
    GEMINI_SUCCESS=$(echo $DATA | jq -r '.gemini_success_rate_percent')
    GEMINI_RETRIES=$(echo $DATA | jq -r '.gemini_api_retries')
    echo "     Total Calls: $GEMINI_TOTAL"
    echo "     Failed: $GEMINI_FAILED"
    echo "     Retries: $GEMINI_RETRIES"
    echo "     Success Rate: ${GEMINI_SUCCESS}%"
    echo ""

    # Rate Limiting
    echo "🚦 RATE LIMITING"
    RATE_LIMIT_HITS=$(echo $DATA | jq -r '.rate_limit_hits')
    LAST_RATE_LIMIT=$(echo $DATA | jq -r '.last_rate_limit_time')
    echo "   Rate Limit Hits: $RATE_LIMIT_HITS"
    if [ "$LAST_RATE_LIMIT" != "0001-01-01T00:00:00Z" ] && [ "$LAST_RATE_LIMIT" != "" ]; then
        echo "   Last Hit: $LAST_RATE_LIMIT"
    else
        echo "   Last Hit: Never"
    fi
    echo ""

    echo "=============================="
    echo ""

    # Health Assessment
    echo "🏆 HEALTH ASSESSMENT"
    echo ""

    if (( $(echo "$SUCCESS_RATE >= 95" | bc -l) )); then
        echo "   ✅ Success Rate: EXCELLENT (>= 95%)"
    elif (( $(echo "$SUCCESS_RATE >= 80" | bc -l) )); then
        echo "   ⚠️  Success Rate: GOOD (>= 80%)"
    else
        echo "   ❌ Success Rate: NEEDS IMPROVEMENT (< 80%)"
    fi

    if (( $(echo "$ACCURACY >= 95" | bc -l) )); then
        echo "   ✅ Accuracy: EXCELLENT (>= 95%)"
    elif (( $(echo "$ACCURACY >= 80" | bc -l) )); then
        echo "   ⚠️  Accuracy: GOOD (>= 80%)"
    else
        echo "   ❌ Accuracy: NEEDS IMPROVEMENT (< 80%)"
    fi

    if [ "$AVG_TIME" != "0" ] && (( $(echo "$AVG_TIME < 10000" | bc -l) )); then
        echo "   ✅ Performance: EXCELLENT (< 10s)"
    elif [ "$AVG_TIME" != "0" ] && (( $(echo "$AVG_TIME < 20000" | bc -l) )); then
        echo "   ⚠️  Performance: GOOD (< 20s)"
    elif [ "$AVG_TIME" = "0" ]; then
        echo "   ℹ️  Performance: No data yet"
    else
        echo "   ❌ Performance: NEEDS IMPROVEMENT (> 20s)"
    fi

    if (( $(echo "$CLEANING_RATE > 0" | bc -l) )); then
        echo "   ✅ Cleaning: Active (${CLEANING_RATE}% of items cleaned)"
    else
        echo "   ℹ️  Cleaning: No items needed cleaning yet"
    fi

    echo ""
}

# Function to reset metrics
reset_metrics() {
    echo "🔄 Step 3: Testing metrics reset..."
    echo ""

    read -p "Do you want to reset all metrics? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping reset"
        return
    fi

    RESPONSE=$(curl -s -X POST "$API_BASE/ocr/metrics/reset" \
        -H "Authorization: Bearer $TOKEN")

    SUCCESS=$(echo $RESPONSE | jq -r '.success')

    if [ "$SUCCESS" = "true" ]; then
        echo "✅ Metrics reset successfully"
        echo ""
        echo "📊 Fetching updated metrics..."
        get_metrics
    else
        echo "❌ Failed to reset metrics"
        echo "Response: $RESPONSE"
    fi
}

# Main execution
main() {
    login
    get_metrics
    reset_metrics

    echo "=============================="
    echo "✅ Metrics test completed"
    echo "=============================="
    echo ""
    echo "Detailed metrics saved to: /tmp/ocr_metrics.json"
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed. Please install it first:"
    echo "   apt-get install jq"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "❌ bc is not installed. Please install it first:"
    echo "   apt-get install bc"
    exit 1
fi

main
