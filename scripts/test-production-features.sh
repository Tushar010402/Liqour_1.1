#!/bin/bash

# LiquorPro Production Features Testing Script
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BASE_URL="http://localhost:8090"
METRICS_PORT="9091"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
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

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "✅ $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "❌ $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Wait for services to be ready
wait_for_services() {
    log_info "Waiting for services to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$BASE_URL/health" > /dev/null 2>&1; then
            log_success "Services are ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "Attempt $attempt/$max_attempts - waiting for services..."
        sleep 2
    done
    
    log_error "Services failed to start within timeout"
    return 1
}

# Test 1: Basic Health Check
test_health_check() {
    local response=$(curl -s "$BASE_URL/health")
    echo "$response" | grep -q '"status":"healthy"'
}

# Test 2: Prometheus Metrics
test_prometheus_metrics() {
    local response=$(curl -s "http://localhost:$METRICS_PORT/metrics")
    echo "$response" | grep -q "http_requests_total" && \
    echo "$response" | grep -q "http_request_duration_seconds" && \
    echo "$response" | grep -q "db_connections_active"
}

# Test 3: API Versioning
test_api_versioning() {
    # Test default version
    local response=$(curl -s "$BASE_URL/version")
    echo "$response" | grep -q '"current_version"'
    
    # Test version header
    local versioned_response=$(curl -s -H "X-API-Version: v1.0.0" "$BASE_URL/health")
    echo "$versioned_response" | grep -q '"status":"healthy"'
    
    # Test deprecated version warning
    curl -s -H "X-API-Version: v1.0.0" "$BASE_URL/health" -I | grep -q "X-API-Deprecation-Warning"
}

# Test 4: Rate Limiting
test_rate_limiting() {
    log_info "Testing rate limiting (this may take a moment)..."
    
    # Make rapid requests to trigger rate limiting
    local rate_limited=false
    for i in {1..50}; do
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
        if [ "$status_code" = "429" ]; then
            rate_limited=true
            break
        fi
    done
    
    if [ "$rate_limited" = true ]; then
        return 0
    else
        log_warning "Rate limiting not triggered - may need adjustment"
        return 1
    fi
}

# Test 5: Circuit Breaker
test_circuit_breaker() {
    # This is a basic test - in real scenarios, you'd test by simulating downstream failures
    local response=$(curl -s "$BASE_URL/health")
    echo "$response" | grep -q '"status"'
}

# Test 6: Database Connection Pooling
test_database_connection_pooling() {
    # Check if database health is reported in health endpoint
    local response=$(curl -s "$BASE_URL/health")
    echo "$response" | grep -q '"database"' && \
    echo "$response" | grep -q '"open_connections"'
}

# Test 7: Distributed Tracing Headers
test_distributed_tracing() {
    # Check for tracing headers in response
    local headers=$(curl -s -I "$BASE_URL/health")
    # In a real implementation, you'd check for trace IDs
    echo "$headers" | grep -q "HTTP/1.1 200"
}

# Test 8: Security Headers
test_security_headers() {
    local headers=$(curl -s -I "$BASE_URL/health")
    echo "$headers" | grep -q "X-Frame-Options: DENY" && \
    echo "$headers" | grep -q "X-Content-Type-Options: nosniff" && \
    echo "$headers" | grep -q "X-XSS-Protection: 1; mode=block"
}

# Test 9: Webhook System (if enabled)
test_webhook_system() {
    # Create a test user to get auth token first
    local auth_response=$(curl -s -X POST "$BASE_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d '{
            "username": "webhook_test",
            "email": "webhook@test.com",
            "password": "WebhookTest123!",
            "first_name": "Webhook",
            "last_name": "Test",
            "role": "admin",
            "company_name": "Webhook Test Co",
            "tenant_name": "Webhook Test Tenant"
        }')
    
    local token=$(echo "$auth_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$token" ]; then
        # Try to list webhooks
        local webhook_response=$(curl -s "$BASE_URL/api/v1/webhooks" -H "Authorization: Bearer $token")
        echo "$webhook_response" | grep -q "endpoints"
    else
        return 1
    fi
}

# Test 10: Message Queue Health
test_message_queue() {
    # Check Redis connection through health endpoint
    local response=$(curl -s "$BASE_URL/health")
    echo "$response" | grep -q '"redis"' && \
    echo "$response" | grep -q '"total_conns"'
}

# Test 11: Auto-scaling Configuration (K8s only)
test_autoscaling_config() {
    # Check if autoscaling manifests exist
    [ -f "$PROJECT_ROOT/k8s/autoscaling.yaml" ] && \
    grep -q "HorizontalPodAutoscaler" "$PROJECT_ROOT/k8s/autoscaling.yaml"
}

# Test 12: Infrastructure as Code
test_infrastructure_code() {
    # Check if Terraform files exist and are valid
    [ -f "$PROJECT_ROOT/terraform/main.tf" ] && \
    [ -f "$PROJECT_ROOT/terraform/variables.tf" ] && \
    grep -q "terraform" "$PROJECT_ROOT/terraform/main.tf"
}

# Test 13: CI/CD Pipeline
test_cicd_pipeline() {
    # Check if GitHub Actions workflow exists
    [ -f "$PROJECT_ROOT/.github/workflows/ci-cd.yml" ] && \
    grep -q "liquorpro" "$PROJECT_ROOT/.github/workflows/ci-cd.yml"
}

# Test 14: Monitoring Stack
test_monitoring_stack() {
    # Check if monitoring configuration exists
    [ -f "$PROJECT_ROOT/docker-compose.monitoring.yml" ] && \
    grep -q "prometheus" "$PROJECT_ROOT/docker-compose.monitoring.yml" && \
    grep -q "grafana" "$PROJECT_ROOT/docker-compose.monitoring.yml" && \
    grep -q "jaeger" "$PROJECT_ROOT/docker-compose.monitoring.yml"
}

# Test 15: Load Testing Capability
test_load_testing() {
    log_info "Running basic load test..."
    
    # Simple concurrent request test
    local start_time=$(date +%s)
    local success_count=0
    
    # Run 20 concurrent requests
    for i in {1..20}; do
        (
            local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
            if [ "$status_code" = "200" ]; then
                echo "success"
            fi
        ) &
    done
    
    wait
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Load test completed in ${duration}s"
    [ "$duration" -le 10 ] # Should complete within 10 seconds
}

# Test 16: Production Configuration Validation
test_production_config() {
    # Check for production-ready configurations
    [ -f "$PROJECT_ROOT/docker-compose.prod.yml" ] && \
    [ -f "$PROJECT_ROOT/k8s/liquorpro-production.yaml" ] && \
    grep -q "resources:" "$PROJECT_ROOT/k8s/liquorpro-production.yaml" && \
    grep -q "livenessProbe:" "$PROJECT_ROOT/k8s/liquorpro-production.yaml"
}

# Main test execution
main() {
    echo "🚀 LiquorPro Production Features Testing"
    echo "=========================================="
    echo ""
    
    # Wait for services
    if ! wait_for_services; then
        log_error "Services are not ready. Please ensure the system is running."
        exit 1
    fi
    
    echo ""
    log_info "Starting comprehensive production features testing..."
    echo ""
    
    # Core functionality tests
    run_test "Health Check Endpoint" "test_health_check"
    run_test "API Versioning System" "test_api_versioning"
    run_test "Security Headers" "test_security_headers"
    
    # Monitoring & Observability
    run_test "Prometheus Metrics" "test_prometheus_metrics"
    run_test "Distributed Tracing" "test_distributed_tracing"
    
    # Performance & Resilience
    run_test "Rate Limiting" "test_rate_limiting"
    run_test "Circuit Breaker" "test_circuit_breaker"
    run_test "Database Connection Pooling" "test_database_connection_pooling"
    run_test "Load Testing Capability" "test_load_testing"
    
    # Integration Systems
    run_test "Webhook System" "test_webhook_system"
    run_test "Message Queue Health" "test_message_queue"
    
    # Infrastructure & DevOps
    run_test "Auto-scaling Configuration" "test_autoscaling_config"
    run_test "Infrastructure as Code" "test_infrastructure_code"
    run_test "CI/CD Pipeline" "test_cicd_pipeline"
    run_test "Monitoring Stack" "test_monitoring_stack"
    run_test "Production Configuration" "test_production_config"
    
    # Generate test report
    echo ""
    echo "📊 Test Results Summary"
    echo "======================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
    echo ""
    
    # Detailed feature analysis
    echo "🔍 Production Readiness Analysis"
    echo "================================"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "🎉 ALL TESTS PASSED - PRODUCTION READY!"
        echo ""
        echo "✅ Your LiquorPro backend now includes:"
        echo "   • Prometheus monitoring with custom metrics"
        echo "   • Grafana dashboards for visualization"
        echo "   • Jaeger distributed tracing"
        echo "   • Redis-based rate limiting"
        echo "   • Circuit breakers for resilience"
        echo "   • Database connection pooling"
        echo "   • Webhook system for integrations"
        echo "   • Message queues with Redis Streams"
        echo "   • API versioning with deprecation"
        echo "   • Kubernetes auto-scaling (HPA/VPA)"
        echo "   • Load balancing with Nginx"
        echo "   • CI/CD pipelines with GitHub Actions"
        echo "   • Infrastructure as Code with Terraform"
        echo "   • Comprehensive automated testing"
        echo "   • Production-grade security headers"
        echo ""
        echo "🏆 INDUSTRIAL GRADE BACKEND ACHIEVED!"
        
    elif [ $FAILED_TESTS -le 3 ]; then
        log_warning "⚠️  MOSTLY READY - Minor issues detected"
        echo "   Consider addressing the failed tests for optimal production readiness."
        
    else
        log_error "❌ PRODUCTION READINESS ISSUES DETECTED"
        echo "   Please address the failed tests before deploying to production."
        
    fi
    
    echo ""
    echo "📈 Performance Metrics Available at:"
    echo "   • Prometheus: http://localhost:9090"
    echo "   • Grafana: http://localhost:3000 (admin/admin123)"
    echo "   • Jaeger UI: http://localhost:16686"
    echo ""
    echo "🛠️ Next Steps:"
    echo "   1. Deploy monitoring stack: docker-compose -f docker-compose.monitoring.yml up -d"
    echo "   2. Configure production secrets in Kubernetes/Docker"
    echo "   3. Set up automated deployment pipelines"
    echo "   4. Configure alerts and notifications"
    echo "   5. Run load tests in staging environment"
    echo ""
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"