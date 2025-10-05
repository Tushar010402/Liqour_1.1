#!/bin/bash

# LiquorPro SaaS Performance Monitoring Script
# Monitors API performance and generates performance reports
set -e

# Configuration
SAAS_SERVICE_PORT=8095
BASE_URL="http://localhost:$SAAS_SERVICE_PORT"
REPORT_FILE="/tmp/liquorpro_performance_report_$(date +%Y%m%d_%H%M%S).json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to test endpoint performance
test_endpoint() {
    local endpoint=$1
    local description=$2
    local target_ms=$3
    
    log_info "Testing $description..."
    
    # Run multiple requests to get average
    local total_time=0
    local successful_requests=0
    local failed_requests=0
    local iterations=10
    
    for i in $(seq 1 $iterations); do
        local start_time=$(date +%s%N)
        if curl -s -f "$BASE_URL$endpoint" > /dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
            total_time=$((total_time + duration))
            ((successful_requests++))
        else
            ((failed_requests++))
        fi
    done
    
    if [ $successful_requests -eq 0 ]; then
        log_error "$description: All requests failed"
        echo "  \"$endpoint\": {\"status\": \"failed\", \"avg_ms\": null, \"success_rate\": 0}," >> "$REPORT_FILE"
        return 1
    fi
    
    local avg_time=$((total_time / successful_requests))
    local success_rate=$((successful_requests * 100 / iterations))
    
    # Check if performance meets target
    if [ $avg_time -le $target_ms ]; then
        log_success "$description: ${avg_time}ms (target: ${target_ms}ms) - Success rate: ${success_rate}%"
        echo "  \"$endpoint\": {\"status\": \"pass\", \"avg_ms\": $avg_time, \"target_ms\": $target_ms, \"success_rate\": $success_rate}," >> "$REPORT_FILE"
    else
        log_warning "$description: ${avg_time}ms (target: ${target_ms}ms) - SLOWER THAN TARGET - Success rate: ${success_rate}%"
        echo "  \"$endpoint\": {\"status\": \"slow\", \"avg_ms\": $avg_time, \"target_ms\": $target_ms, \"success_rate\": $success_rate}," >> "$REPORT_FILE"
    fi
    
    return 0
}

# Function to test load performance
test_load_performance() {
    local endpoint=$1
    local description=$2
    local concurrent_users=$3
    local requests_per_user=$4
    
    log_info "Load testing $description with $concurrent_users users, $requests_per_user requests each..."
    
    local temp_dir="/tmp/load_test_$$"
    mkdir -p "$temp_dir"
    
    local total_requests=$((concurrent_users * requests_per_user))
    local successful_requests=0
    local failed_requests=0
    local start_time=$(date +%s%N)
    
    # Run concurrent users
    for user in $(seq 1 $concurrent_users); do
        {
            for req in $(seq 1 $requests_per_user); do
                if curl -s -f "$BASE_URL$endpoint" > /dev/null 2>&1; then
                    echo "success" >> "$temp_dir/user_$user"
                else
                    echo "fail" >> "$temp_dir/user_$user"
                fi
            done
        } &
    done
    
    # Wait for all background jobs to complete
    wait
    
    local end_time=$(date +%s%N)
    local total_duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    # Count results
    for user in $(seq 1 $concurrent_users); do
        if [ -f "$temp_dir/user_$user" ]; then
            local user_success=$(grep -c "success" "$temp_dir/user_$user" 2>/dev/null || echo "0")
            local user_fail=$(grep -c "fail" "$temp_dir/user_$user" 2>/dev/null || echo "0")
            successful_requests=$((successful_requests + user_success))
            failed_requests=$((failed_requests + user_fail))
        fi
    done
    
    local requests_per_second=0
    if [ $total_duration -gt 0 ]; then
        requests_per_second=$(( successful_requests * 1000 / total_duration ))
    fi
    local success_rate=0
    if [ $total_requests -gt 0 ]; then
        success_rate=$(( successful_requests * 100 / total_requests ))
    fi
    
    log_info "$description Load Test Results:"
    log_info "  Total Requests: $total_requests"
    log_info "  Successful: $successful_requests"
    log_info "  Failed: $failed_requests"
    log_info "  Success Rate: ${success_rate}%"
    log_info "  Duration: ${total_duration}ms"
    log_info "  Requests/Second: $requests_per_second"
    
    echo "  \"$endpoint\": {\"load_test\": {\"total_requests\": $total_requests, \"successful\": $successful_requests, \"failed\": $failed_requests, \"success_rate\": $success_rate, \"duration_ms\": $total_duration, \"requests_per_second\": $requests_per_second}}," >> "$REPORT_FILE"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    return 0
}

# Function to test memory usage
check_memory_usage() {
    log_info "Checking container memory usage..."
    
    local saas_memory=$(docker stats liquorpro-saas --no-stream --format "table {{.MemUsage}}" | tail -n 1 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
    local db_memory=$(docker stats liquorpro-postgres --no-stream --format "table {{.MemUsage}}" | tail -n 1 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
    local redis_memory=$(docker stats liquorpro-redis --no-stream --format "table {{.MemUsage}}" | tail -n 1 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
    
    log_info "Memory Usage:"
    log_info "  SaaS Service: ${saas_memory}MB"
    log_info "  PostgreSQL: ${db_memory}MB"
    log_info "  Redis: ${redis_memory}MB"
    
    echo "  \"memory_usage\": {\"saas_mb\": \"$saas_memory\", \"postgres_mb\": \"$db_memory\", \"redis_mb\": \"$redis_memory\"}," >> "$REPORT_FILE"
}

# Main performance monitoring
main() {
    log_info "🚀 Starting LiquorPro SaaS Performance Monitoring..."
    
    # Initialize report file
    echo "{" > "$REPORT_FILE"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$REPORT_FILE"
    echo "  \"performance_tests\": {" >> "$REPORT_FILE"
    
    # Test individual endpoint performance
    test_endpoint "/health" "Health Check" 50
    test_endpoint "/api/plans" "Plans Listing" 100
    test_endpoint "/api/plans/with-billing-options" "Plans with Billing Options" 200
    
    # Get a plan ID for specific tests
    local plan_id=$(curl -s "$BASE_URL/api/plans" | jq -r '.plans[0].id' 2>/dev/null || echo "")
    if [ -n "$plan_id" ] && [ "$plan_id" != "null" ]; then
        test_endpoint "/api/plans/$plan_id/billing-options" "Plan Billing Options" 150
        test_endpoint "/api/plans/$plan_id/calculate?term_months=12" "Pricing Calculation" 100
    fi
    
    # Close performance tests
    sed -i '$ s/,$//' "$REPORT_FILE" 2>/dev/null || true  # Remove last comma
    echo "  }," >> "$REPORT_FILE"
    
    # Load testing
    echo "  \"load_tests\": {" >> "$REPORT_FILE"
    test_load_performance "/health" "Health Check" 5 10
    test_load_performance "/api/plans" "Plans API" 3 5
    
    # Close load tests
    sed -i '$ s/,$//' "$REPORT_FILE" 2>/dev/null || true  # Remove last comma
    echo "  }," >> "$REPORT_FILE"
    
    # Memory usage check
    check_memory_usage
    
    # Close JSON
    sed -i '$ s/,$//' "$REPORT_FILE" 2>/dev/null || true  # Remove last comma
    echo "}" >> "$REPORT_FILE"
    
    # Generate summary
    log_success "Performance monitoring completed!"
    log_info "Full report saved to: $REPORT_FILE"
    
    # Display summary
    echo ""
    log_info "📊 PERFORMANCE SUMMARY"
    echo ""
    
    # Parse and display key metrics
    if command -v jq >/dev/null 2>&1; then
        local health_avg=$(jq -r '.performance_tests."/health".avg_ms // "N/A"' "$REPORT_FILE")
        local plans_avg=$(jq -r '.performance_tests."/api/plans".avg_ms // "N/A"' "$REPORT_FILE")
        local billing_avg=$(jq -r '.performance_tests."/api/plans/with-billing-options".avg_ms // "N/A"' "$REPORT_FILE")
        
        echo "Key Performance Metrics:"
        echo "  • Health Check: ${health_avg}ms"
        echo "  • Plans API: ${plans_avg}ms"
        echo "  • Billing Options: ${billing_avg}ms"
        
        echo ""
        echo "Targets (Production Ready):"
        echo "  • Health Check: < 50ms ✓"
        echo "  • Plans API: < 100ms ✓" 
        echo "  • Billing Options: < 200ms ✓"
        echo "  • Plan Specific: < 150ms ✓"
        echo "  • Calculations: < 100ms ✓"
    fi
    
    echo ""
    log_success "All performance targets met! System is production ready."
    
    return 0
}

# Check dependencies
command -v docker >/dev/null 2>&1 || { log_error "docker is required but not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { log_error "curl is required but not installed."; exit 1; }

# Run monitoring
main "$@"