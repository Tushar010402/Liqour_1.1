#!/bin/bash

# OCR Load Testing Script
# Tests parallel processing with multiple concurrent uploads

set -e

echo "🚀 OCR Load Testing Suite"
echo "=============================="
echo ""

# Configuration
API_BASE="https://liquorpro.retailpulse.tech/api/sales"
AUTH_BASE="https://liquorpro.retailpulse.tech/api/auth"
TEST_PHONE="8126816664"
TEST_OTP="000000"  # Development mode OTP
TOKEN=""
NUM_CONCURRENT=${1:-3}
NUM_IMAGES=${2:-5}

echo "Configuration:"
echo "  Test Phone: $TEST_PHONE"
echo "  Concurrent workers: $NUM_CONCURRENT"
echo "  Images per worker: $NUM_IMAGES"
echo "  Total images: $((NUM_CONCURRENT * NUM_IMAGES))"
echo ""

# Function to login with OTP
login() {
    echo "🔐 Authenticating with OTP..."

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

    echo "✅ Authentication successful"
    echo ""
}

# Function to create a test image (1x1 PNG with text overlay simulated via base64)
create_test_image() {
    # Simple 1x1 PNG (base64 encoded)
    # For real testing, replace this with actual invoice images
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
}

# Function to test single worker
test_worker() {
    local WORKER_ID=$1
    local START_TIME=$(date +%s)
    local SUCCESS_COUNT=0
    local FAIL_COUNT=0

    echo "[Worker $WORKER_ID] Starting..."

    # Create batch session
    BATCH_RESPONSE=$(curl -s -X POST "$API_BASE/ocr/batch/sessions" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"session_type\": \"stock_initialization\",
            \"total_images\": $NUM_IMAGES
        }")

    BATCH_ID=$(echo $BATCH_RESPONSE | jq -r '.batch_id')

    if [ "$BATCH_ID" = "null" ]; then
        echo "[Worker $WORKER_ID] ❌ Failed to create batch"
        return 1
    fi

    # Upload images
    for i in $(seq 1 $NUM_IMAGES); do
        IMAGE_DATA=$(create_test_image)

        UPLOAD_RESPONSE=$(curl -s -X POST "$API_BASE/ocr/batch/$BATCH_ID/upload" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"images\": [\"$IMAGE_DATA\"]}")

        SESSION_ID=$(echo $UPLOAD_RESPONSE | jq -r '.session_ids[0]')

        if [ "$SESSION_ID" = "null" ]; then
            echo "[Worker $WORKER_ID] ❌ Failed to upload image $i"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            continue
        fi

        # Poll for completion
        MAX_POLL=30
        POLL_COUNT=0
        COMPLETED=false

        while [ $POLL_COUNT -lt $MAX_POLL ]; do
            POLL_COUNT=$((POLL_COUNT + 1))

            STATUS_RESPONSE=$(curl -s -X GET "$API_BASE/ocr/sessions/$SESSION_ID" \
                -H "Authorization: Bearer $TOKEN")

            STATUS=$(echo $STATUS_RESPONSE | jq -r '.status')

            if [ "$STATUS" = "completed" ]; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                COMPLETED=true
                break
            elif [ "$STATUS" = "failed" ]; then
                FAIL_COUNT=$((FAIL_COUNT + 1))
                COMPLETED=true
                break
            fi

            sleep 0.5
        done

        if [ "$COMPLETED" = false ]; then
            echo "[Worker $WORKER_ID] ⚠️  Image $i timed out"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo "[Worker $WORKER_ID] Completed in ${DURATION}s: ✅ $SUCCESS_COUNT succeeded, ❌ $FAIL_COUNT failed"

    # Save results
    echo "$WORKER_ID,$SUCCESS_COUNT,$FAIL_COUNT,$DURATION" >> /tmp/ocr_load_results.txt
}

# Function to run load test
run_load_test() {
    echo "🔥 Starting load test with $NUM_CONCURRENT concurrent workers..."
    echo ""

    # Clear previous results
    rm -f /tmp/ocr_load_results.txt

    START_TIME=$(date +%s)

    # Launch workers in parallel
    for i in $(seq 1 $NUM_CONCURRENT); do
        test_worker $i &
    done

    # Wait for all workers to complete
    wait

    END_TIME=$(date +%s)
    TOTAL_DURATION=$((END_TIME - START_TIME))

    echo ""
    echo "=============================="
    echo "📊 Load Test Results"
    echo "=============================="
    echo ""
    echo "Total duration: ${TOTAL_DURATION}s"
    echo ""

    # Calculate statistics
    TOTAL_SUCCESS=0
    TOTAL_FAIL=0
    TOTAL_IMAGES=$((NUM_CONCURRENT * NUM_IMAGES))

    while IFS=',' read -r WORKER_ID SUCCESS FAIL DURATION; do
        TOTAL_SUCCESS=$((TOTAL_SUCCESS + SUCCESS))
        TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
    done < /tmp/ocr_load_results.txt

    SUCCESS_RATE=$((TOTAL_SUCCESS * 100 / TOTAL_IMAGES))
    THROUGHPUT=$(echo "scale=2; $TOTAL_IMAGES / $TOTAL_DURATION" | bc)

    echo "Results:"
    echo "  Total images processed: $TOTAL_IMAGES"
    echo "  Successful: $TOTAL_SUCCESS"
    echo "  Failed: $TOTAL_FAIL"
    echo "  Success rate: ${SUCCESS_RATE}%"
    echo "  Throughput: ${THROUGHPUT} images/second"
    echo ""

    # Expected performance with 3 parallel workers:
    # - Previous sequential: ~20 seconds per image
    # - Expected parallel: ~7 seconds per image
    EXPECTED_SPEEDUP=3
    AVG_TIME=$(echo "scale=2; $TOTAL_DURATION / $TOTAL_IMAGES" | bc)

    echo "Performance:"
    echo "  Average time per image: ${AVG_TIME}s"

    if (( $(echo "$AVG_TIME < 10" | bc -l) )); then
        echo "  ✅ Performance is excellent (< 10s per image)"
    elif (( $(echo "$AVG_TIME < 20" | bc -l) )); then
        echo "  ✅ Performance is good (< 20s per image)"
    else
        echo "  ⚠️  Performance needs improvement (> 20s per image)"
    fi

    echo ""

    if [ $SUCCESS_RATE -ge 95 ]; then
        echo "✅ Load test PASSED (success rate >= 95%)"
    else
        echo "❌ Load test FAILED (success rate < 95%)"
        exit 1
    fi
}

# Main
main() {
    login
    run_load_test

    echo ""
    echo "=============================="
    echo "✅ Load test completed"
    echo "=============================="
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
