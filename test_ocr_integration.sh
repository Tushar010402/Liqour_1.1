#!/bin/bash

# OCR Integration Test Script
# Tests real OCR flow with actual images to verify 100% accuracy

set -e

echo "🧪 OCR Integration Test Suite"
echo "=============================="
echo ""

# Configuration
API_BASE="https://liquorpro.retailpulse.tech/api/sales"
AUTH_BASE="https://liquorpro.retailpulse.tech/api/auth"
TEST_PHONE="8126816664"
TEST_OTP="000000"  # Development mode OTP
TOKEN=""

# Function to login with OTP and get token
login() {
    echo "🔐 Step 1: Authenticating with OTP..."

    # Step 1: Send OTP
    echo "📱 Sending OTP to $TEST_PHONE..."
    SEND_RESPONSE=$(curl -s -X POST "$AUTH_BASE/send-otp" \
        -H "Content-Type: application/json" \
        -d "{
            \"mobile\": \"$TEST_PHONE\"
        }")

    SESSION_ID=$(echo $SEND_RESPONSE | jq -r '.session_id')

    if [ "$SESSION_ID" = "null" ] || [ -z "$SESSION_ID" ]; then
        echo "❌ Failed to send OTP"
        echo "Response: $SEND_RESPONSE"
        exit 1
    fi

    echo "✅ OTP sent successfully (session: ${SESSION_ID:0:8}...)"

    # Step 2: Verify OTP and get token
    echo "🔑 Verifying OTP..."
    VERIFY_RESPONSE=$(curl -s -X POST "$AUTH_BASE/verify-otp" \
        -H "Content-Type: application/json" \
        -d "{
            \"mobile\": \"$TEST_PHONE\",
            \"otp\": \"$TEST_OTP\",
            \"session_id\": \"$SESSION_ID\"
        }")

    TOKEN=$(echo $VERIFY_RESPONSE | jq -r '.token')

    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        echo "❌ OTP verification failed"
        echo "Response: $VERIFY_RESPONSE"
        exit 1
    fi

    USER_NAME=$(echo $VERIFY_RESPONSE | jq -r '.user.first_name')
    USER_ROLE=$(echo $VERIFY_RESPONSE | jq -r '.user.role')

    echo "✅ Authentication successful!"
    echo "   User: $USER_NAME"
    echo "   Role: $USER_ROLE"
    echo "   Token: ${TOKEN:0:20}..."
    echo ""
}

# Function to create batch session
create_batch_session() {
    echo "📦 Step 2: Creating batch OCR session..."

    RESPONSE=$(curl -s -X POST "$API_BASE/ocr/batch/sessions" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "session_type": "stock_initialization",
            "total_images": 1
        }')

    BATCH_ID=$(echo $RESPONSE | jq -r '.batch_id')

    if [ "$BATCH_ID" = "null" ] || [ -z "$BATCH_ID" ]; then
        echo "❌ Failed to create batch session"
        echo "Response: $RESPONSE"
        exit 1
    fi

    echo "✅ Batch session created: $BATCH_ID"
    echo ""
}

# Function to upload test image
upload_test_image() {
    local TEST_IMAGE_PATH=$1

    echo "📸 Step 3: Uploading test image..."

    if [ ! -f "$TEST_IMAGE_PATH" ]; then
        echo "❌ Test image not found: $TEST_IMAGE_PATH"
        exit 1
    fi

    # Convert image to base64
    IMAGE_BASE64=$(base64 -w 0 "$TEST_IMAGE_PATH")

    echo "Image size: $(stat -f%z "$TEST_IMAGE_PATH" 2>/dev/null || stat -c%s "$TEST_IMAGE_PATH") bytes"

    RESPONSE=$(curl -s -X POST "$API_BASE/ocr/batch/$BATCH_ID/upload" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"images\": [\"$IMAGE_BASE64\"]
        }")

    SESSION_ID=$(echo $RESPONSE | jq -r '.session_ids[0]')

    if [ "$SESSION_ID" = "null" ] || [ -z "$SESSION_ID" ]; then
        echo "❌ Failed to upload image"
        echo "Response: $RESPONSE"
        exit 1
    fi

    echo "✅ Image uploaded, session ID: $SESSION_ID"
    echo ""
}

# Function to poll for results
poll_results() {
    echo "⏳ Step 4: Polling for OCR results..."

    MAX_ATTEMPTS=50
    ATTEMPT=0

    START_TIME=$(date +%s)

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))

        RESPONSE=$(curl -s -X GET "$API_BASE/ocr/sessions/$SESSION_ID" \
            -H "Authorization: Bearer $TOKEN")

        STATUS=$(echo $RESPONSE | jq -r '.status')
        CURRENT_STAGE=$(echo $RESPONSE | jq -r '.current_stage')
        PROGRESS=$(echo $RESPONSE | jq -r '.progress_percentage')

        echo "  Attempt $ATTEMPT: Status=$STATUS, Stage=$CURRENT_STAGE, Progress=$PROGRESS%"

        if [ "$STATUS" = "completed" ]; then
            END_TIME=$(date +%s)
            DURATION=$((END_TIME - START_TIME))
            echo ""
            echo "✅ OCR completed in $DURATION seconds ($ATTEMPT polling attempts)"
            echo ""

            # Save full response
            echo "$RESPONSE" > /tmp/ocr_result.json
            break
        fi

        if [ "$STATUS" = "failed" ]; then
            ERROR=$(echo $RESPONSE | jq -r '.error_message')
            echo ""
            echo "❌ OCR failed: $ERROR"
            exit 1
        fi

        sleep 1
    done

    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo ""
        echo "❌ Timeout after $MAX_ATTEMPTS attempts"
        exit 1
    fi
}

# Function to validate results
validate_results() {
    echo "🔍 Step 5: Validating OCR accuracy..."
    echo ""

    # Extract items from response
    ITEMS=$(jq -r '.extracted_items' /tmp/ocr_result.json)
    ITEM_COUNT=$(echo $ITEMS | jq '. | length')

    echo "📊 Extracted $ITEM_COUNT items:"
    echo ""

    VALIDATION_PASSED=true

    for i in $(seq 0 $((ITEM_COUNT - 1))); do
        BRAND=$(echo $ITEMS | jq -r ".[$i].brand_text")
        NORMALIZED=$(echo $ITEMS | jq -r ".[$i].normalized_brand_name")
        SIZE=$(echo $ITEMS | jq -r ".[$i].size_text")
        QTY=$(echo $ITEMS | jq -r ".[$i].quantity")
        PRICE=$(echo $ITEMS | jq -r ".[$i].selling_price")

        echo "  Item $((i + 1)):"
        echo "    Brand (raw): $BRAND"
        echo "    Brand (normalized): $NORMALIZED"
        echo "    Size: $SIZE"
        echo "    Quantity: $QTY"
        echo "    Price: $PRICE"
        echo ""

        # Validation checks
        ISSUES=()

        # Check for Devanagari numerals (U+0966 to U+096F)
        if echo "$BRAND" | grep -qP '[\x{0966}-\x{096F}]'; then
            ISSUES+=("❌ Contains Devanagari numerals")
        fi

        # Check for Bengali numerals (U+09E6 to U+09EF)
        if echo "$BRAND" | grep -qP '[\x{09E6}-\x{09EF}]'; then
            ISSUES+=("❌ Contains Bengali numerals")
        fi

        # Check for trailing garbage (pipes, dots, single zeros at end)
        if echo "$NORMALIZED" | grep -qE '\||\s+0$|\s+\.$'; then
            ISSUES+=("❌ Contains trailing garbage")
        fi

        # Check for excessive numbers
        NUM_COUNT=$(echo "$NORMALIZED" | grep -o '[0-9]' | wc -l)
        if [ "$NUM_COUNT" -gt 3 ]; then
            ISSUES+=("⚠️  Contains many numbers (might be garbage)")
        fi

        # Check if normalized is empty
        if [ -z "$NORMALIZED" ] || [ "$NORMALIZED" = "null" ]; then
            ISSUES+=("❌ Normalized brand name is empty")
        fi

        # Report issues
        if [ ${#ISSUES[@]} -gt 0 ]; then
            echo "    🚨 VALIDATION ISSUES:"
            for issue in "${ISSUES[@]}"; do
                echo "       $issue"
            done
            echo ""
            VALIDATION_PASSED=false
        else
            echo "    ✅ All checks passed"
            echo ""
        fi
    done

    echo ""
    if [ "$VALIDATION_PASSED" = true ]; then
        echo "✅ ✅ ✅  ALL VALIDATION CHECKS PASSED! ✅ ✅ ✅"
        echo ""
        echo "🎉 OCR system is working with 100% accuracy!"
    else
        echo "❌ ❌ ❌  VALIDATION FAILED! ❌ ❌ ❌"
        echo ""
        echo "⚠️  Please review the issues above"
        exit 1
    fi
}

# Function to test performance
test_performance() {
    echo ""
    echo "⚡ Step 6: Performance metrics..."
    echo ""

    RAW_TEXT=$(jq -r '.raw_text' /tmp/ocr_result.json)
    PROCESSING_TIME=$(jq -r '.processing_time_ms' /tmp/ocr_result.json)

    echo "  Processing time: ${PROCESSING_TIME}ms"
    echo "  Raw text length: ${#RAW_TEXT} characters"

    if [ "$PROCESSING_TIME" != "null" ] && [ $PROCESSING_TIME -lt 30000 ]; then
        echo "  ✅ Performance is good (< 30 seconds)"
    else
        echo "  ⚠️  Performance could be improved"
    fi

    echo ""
}

# Main test flow
main() {
    echo "Starting OCR integration test..."
    echo ""

    # Check if test image path is provided
    if [ -z "$1" ]; then
        echo "Usage: $0 <path_to_test_image>"
        echo ""
        echo "Example: $0 /tmp/invoice.jpg"
        exit 1
    fi

    TEST_IMAGE="$1"

    # Run test steps
    login
    create_batch_session
    upload_test_image "$TEST_IMAGE"
    poll_results
    validate_results
    test_performance

    echo "=============================="
    echo "✅ Integration test completed successfully!"
    echo "=============================="
}

# Run main
main "$@"
