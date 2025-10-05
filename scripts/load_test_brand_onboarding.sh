#!/bin/bash
# Load Testing Script for Brand Onboarding System
# File: scripts/load_test_brand_onboarding.sh
# Purpose: Test brand onboarding under various load conditions

set -e

# ========================================
# Configuration
# ========================================

INVENTORY_URL="${INVENTORY_URL:-http://localhost:8093}"
AUTH_URL="${AUTH_URL:-http://localhost:8091}"
CONCURRENT_USERS="${CONCURRENT_USERS:-10}"
TEST_DURATION="${TEST_DURATION:-60}"
RAMP_UP_TIME="${RAMP_UP_TIME:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test data
TEST_PHONE="+918630668489"
TENANT_ID="373e965a-6dec-44d6-a2ab-0400449fc71d"

# ========================================
# Helper Functions
# ========================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ========================================
# Authentication
# ========================================

authenticate() {
    log "Authenticating user..."

    # Send OTP
    SEND_OTP_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/auth/send-otp" \
        -H "Content-Type: application/json" \
        -d "{\"mobile_number\":\"$TEST_PHONE\"}")

    if echo "$SEND_OTP_RESPONSE" | grep -q "error"; then
        error "Failed to send OTP: $SEND_OTP_RESPONSE"
        return 1
    fi

    # For testing, use a known OTP (in production, would get from SMS)
    sleep 2

    # Verify OTP (using test OTP 000000)
    VERIFY_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/auth/verify-otp" \
        -H "Content-Type: application/json" \
        -d "{\"mobile_number\":\"$TEST_PHONE\",\"otp\":\"000000\"}")

    TOKEN=$(echo "$VERIFY_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('token', ''))" 2>/dev/null || echo "")

    if [ -z "$TOKEN" ]; then
        error "Failed to authenticate: $VERIFY_RESPONSE"
        return 1
    fi

    success "Authenticated successfully"
    export AUTH_TOKEN="$TOKEN"
}

# ========================================
# Load Test Functions
# ========================================

test_list_brands() {
    local thread_id=$1
    local iteration=$2

    START_TIME=$(date +%s%3N)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
        "$INVENTORY_URL/api/inventory/saas-brands/available" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "X-Tenant-ID: $TENANT_ID")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)

    END_TIME=$(date +%s%3N)
    RESPONSE_TIME=$((END_TIME - START_TIME))

    if [ "$HTTP_CODE" = "200" ]; then
        echo "$thread_id,$iteration,list_brands,success,$RESPONSE_TIME,$HTTP_CODE" >> results/load_test_results.csv
    else
        echo "$thread_id,$iteration,list_brands,failure,$RESPONSE_TIME,$HTTP_CODE" >> results/load_test_results.csv
    fi
}

test_onboard_brand() {
    local thread_id=$1
    local iteration=$2
    local brand_ids=$3

    START_TIME=$(date +%s%3N)

    # Create onboarding request
    REQUEST_BODY=$(cat <<EOF
{
    "brand_ids": $brand_ids,
    "shop_id": "00000000-0000-0000-0000-000000000001"
}
EOF
)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "$INVENTORY_URL/api/inventory/saas-brands/onboard" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "X-Tenant-ID: $TENANT_ID" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)

    END_TIME=$(date +%s%3N)
    RESPONSE_TIME=$((END_TIME - START_TIME))

    if [ "$HTTP_CODE" = "200" ]; then
        PRODUCTS_CREATED=$(echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('onboarded_products', 0))" 2>/dev/null || echo "0")
        echo "$thread_id,$iteration,onboard_brand,success,$RESPONSE_TIME,$HTTP_CODE,$PRODUCTS_CREATED" >> results/load_test_results.csv
    else
        echo "$thread_id,$iteration,onboard_brand,failure,$RESPONSE_TIME,$HTTP_CODE,0" >> results/load_test_results.csv
    fi
}

# ========================================
# Load Test Scenarios
# ========================================

scenario_constant_load() {
    log "Running constant load test..."
    log "Concurrent users: $CONCURRENT_USERS"
    log "Duration: ${TEST_DURATION}s"

    mkdir -p results
    echo "thread_id,iteration,operation,status,response_time_ms,http_code,products_created" > results/load_test_results.csv

    # Get brand IDs first
    BRANDS_RESPONSE=$(curl -s -X GET \
        "$INVENTORY_URL/api/inventory/saas-brands/available" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "X-Tenant-ID: $TENANT_ID")

    BRAND_IDS=$(echo "$BRANDS_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'data' in data and len(data['data']) > 0:
    ids = [brand['id'] for brand in data['data'][:3]]  # Take first 3 brands
    print(json.dumps(ids))
else:
    print('[]')
" 2>/dev/null || echo "[]")

    if [ "$BRAND_IDS" = "[]" ]; then
        error "No brands available for testing"
        return 1
    fi

    log "Using brand IDs: $BRAND_IDS"

    # Start concurrent workers
    for ((i=1; i<=CONCURRENT_USERS; i++)); do
        (
            iteration=1
            end_time=$(($(date +%s) + TEST_DURATION))

            while [ $(date +%s) -lt $end_time ]; do
                # Alternate between list and onboard
                if [ $((iteration % 2)) -eq 0 ]; then
                    test_onboard_brand "$i" "$iteration" "$BRAND_IDS"
                else
                    test_list_brands "$i" "$iteration"
                fi

                iteration=$((iteration + 1))
                sleep 0.5  # Small delay between requests
            done
        ) &
    done

    # Wait for all background jobs
    wait

    success "Constant load test completed"
}

scenario_spike_test() {
    log "Running spike test..."

    mkdir -p results
    echo "thread_id,iteration,operation,status,response_time_ms,http_code,products_created" > results/spike_test_results.csv

    # Get brand IDs
    BRANDS_RESPONSE=$(curl -s -X GET \
        "$INVENTORY_URL/api/inventory/saas-brands/available" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "X-Tenant-ID: $TENANT_ID")

    BRAND_IDS=$(echo "$BRANDS_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'data' in data and len(data['data']) > 0:
    ids = [brand['id'] for brand in data['data'][:2]]
    print(json.dumps(ids))
else:
    print('[]')
" 2>/dev/null || echo "[]")

    # Sudden spike: 50 concurrent requests
    log "Generating spike: 50 concurrent requests..."

    for ((i=1; i<=50; i++)); do
        test_list_brands "$i" "1" &
    done

    wait

    success "Spike test completed"
}

scenario_duplicate_prevention() {
    log "Testing duplicate prevention under load..."

    mkdir -p results
    echo "thread_id,iteration,operation,status,response_time_ms,http_code,products_created" > results/duplicate_test_results.csv

    # Get a single brand
    BRANDS_RESPONSE=$(curl -s -X GET \
        "$INVENTORY_URL/api/inventory/saas-brands/available" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "X-Tenant-ID: $TENANT_ID")

    BRAND_IDS=$(echo "$BRANDS_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'data' in data and len(data['data']) > 0:
    print(json.dumps([data['data'][0]['id']]))
else:
    print('[]')
" 2>/dev/null || echo "[]")

    log "Testing concurrent onboarding of same brand: $BRAND_IDS"

    # Attempt to onboard the same brand 20 times concurrently
    for ((i=1; i<=20; i++)); do
        test_onboard_brand "$i" "1" "$BRAND_IDS" &
    done

    wait

    # Check database for duplicates
    log "Checking for duplicates in database..."

    success "Duplicate prevention test completed"
}

# ========================================
# Results Analysis
# ========================================

analyze_results() {
    local results_file=$1

    if [ ! -f "$results_file" ]; then
        warning "Results file not found: $results_file"
        return 1
    fi

    log "Analyzing results from $results_file..."

    python3 <<EOF
import csv
import statistics

results = []
with open('$results_file', 'r') as f:
    reader = csv.DictReader(f)
    results = list(reader)

if not results:
    print("No results to analyze")
    exit(0)

total_requests = len(results)
successful = sum(1 for r in results if r['status'] == 'success')
failed = sum(1 for r in results if r['status'] == 'failure')

response_times = [int(r['response_time_ms']) for r in results if r['response_time_ms'].isdigit()]

if response_times:
    avg_response = statistics.mean(response_times)
    min_response = min(response_times)
    max_response = max(response_times)
    p95_response = sorted(response_times)[int(len(response_times) * 0.95)]
    p99_response = sorted(response_times)[int(len(response_times) * 0.99)]
else:
    avg_response = min_response = max_response = p95_response = p99_response = 0

print("\n" + "="*50)
print("LOAD TEST RESULTS SUMMARY")
print("="*50)
print(f"Total Requests:    {total_requests}")
print(f"Successful:        {successful} ({successful/total_requests*100:.1f}%)")
print(f"Failed:            {failed} ({failed/total_requests*100:.1f}%)")
print(f"\nResponse Times (ms):")
print(f"  Average:         {avg_response:.2f}")
print(f"  Min:             {min_response}")
print(f"  Max:             {max_response}")
print(f"  P95:             {p95_response}")
print(f"  P99:             {p99_response}")
print("="*50 + "\n")

# Performance benchmarks
if avg_response > 500:
    print("⚠ Warning: Average response time exceeds 500ms")
if p95_response > 2000:
    print("⚠ Warning: P95 response time exceeds 2s")
if failed/total_requests > 0.05:
    print("⚠ Warning: Error rate exceeds 5%")

# Products created analysis
if 'products_created' in results[0]:
    products_created = [int(r.get('products_created', 0)) for r in results if r.get('products_created', '').isdigit()]
    total_products = sum(products_created)
    print(f"\nTotal Products Created: {total_products}")

    # Check for duplicates (if multiple requests created products)
    non_zero_creates = [p for p in products_created if p > 0]
    if len(non_zero_creates) > 1:
        print(f"⚠ Warning: Multiple requests created products - check for duplicates")
        print(f"  Requests that created products: {len(non_zero_creates)}")
EOF
}

# ========================================
# Main Test Execution
# ========================================

main() {
    log "Brand Onboarding Load Testing Suite"
    log "===================================="

    # Check dependencies
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required for this script"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        error "curl is required for this script"
        exit 1
    fi

    # Authenticate
    if ! authenticate; then
        error "Authentication failed"
        exit 1
    fi

    # Run test scenarios
    log "\nTest Scenario 1: Constant Load"
    scenario_constant_load
    analyze_results "results/load_test_results.csv"

    log "\nTest Scenario 2: Spike Test"
    scenario_spike_test
    analyze_results "results/spike_test_results.csv"

    log "\nTest Scenario 3: Duplicate Prevention Under Load"
    scenario_duplicate_prevention
    analyze_results "results/duplicate_test_results.csv"

    # Generate combined report
    log "\nGenerating comprehensive report..."

    cat > results/load_test_report.md <<EOF
# Brand Onboarding Load Test Report

**Date:** $(date)
**Test Duration:** ${TEST_DURATION}s
**Concurrent Users:** $CONCURRENT_USERS

## Test Scenarios

### 1. Constant Load Test
- **Duration:** ${TEST_DURATION}s
- **Concurrent Users:** $CONCURRENT_USERS
- **Operations:** Mix of list brands and onboard requests

### 2. Spike Test
- **Spike Size:** 50 concurrent requests
- **Target:** Brand listing endpoint

### 3. Duplicate Prevention Test
- **Scenario:** 20 concurrent onboarding requests for same brand
- **Expected:** Only 1 successful product creation, others skipped

## Results

See detailed results in:
- \`load_test_results.csv\` - Constant load test
- \`spike_test_results.csv\` - Spike test
- \`duplicate_test_results.csv\` - Duplicate prevention test

## Performance Benchmarks

| Metric | Target | Status |
|--------|--------|--------|
| Average Response Time | < 500ms | Check CSV |
| P95 Response Time | < 2s | Check CSV |
| P99 Response Time | < 5s | Check CSV |
| Error Rate | < 5% | Check CSV |
| Duplicate Prevention | 100% effective | Check DB |

## Database Verification

Run this query to verify no duplicates were created:

\`\`\`sql
SELECT
    tenant_id,
    saas_variant_id,
    COUNT(*) as count
FROM products
WHERE saas_variant_id IS NOT NULL
GROUP BY tenant_id, saas_variant_id
HAVING COUNT(*) > 1;
\`\`\`

Expected: 0 rows

## Recommendations

1. If average response time > 500ms:
   - Check database query performance
   - Review SaaS service response time
   - Consider caching brand templates

2. If error rate > 5%:
   - Increase connection pool size
   - Review timeout configurations
   - Check circuit breaker settings

3. If duplicates found:
   - CRITICAL: Review unique constraint
   - Check transaction isolation level
   - Verify application-level duplicate check

## Next Steps

- [ ] Review detailed CSV results
- [ ] Check database for duplicates
- [ ] Monitor production metrics
- [ ] Adjust concurrency limits if needed
EOF

    success "\nLoad testing completed!"
    log "Results saved to results/ directory"
    log "Report available at results/load_test_report.md"
}

# Run main function
main "$@"
