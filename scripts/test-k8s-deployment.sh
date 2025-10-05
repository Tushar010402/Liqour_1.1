#!/bin/bash

# LiquorPro Kubernetes End-to-End Testing Script
# Tests the complete industrial-grade deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="liquorpro"
KAFKA_NAMESPACE="liquorpro-kafka"
MONITORING_NAMESPACE="liquorpro-monitoring"
BASE_URL="http://api.liquorpro.com"
TEST_TIMEOUT=30

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[TEST]${NC} $1"
    ((TOTAL_TESTS++))
}

# Test functions
test_kubernetes_cluster() {
    log_step "Testing Kubernetes cluster connectivity"

    if kubectl cluster-info &> /dev/null; then
        log_success "Kubernetes cluster is accessible"
    else
        log_failure "Cannot connect to Kubernetes cluster"
        return 1
    fi
}

test_namespaces() {
    log_step "Testing namespace creation"

    local namespaces=("$NAMESPACE" "$KAFKA_NAMESPACE" "$MONITORING_NAMESPACE")
    local all_good=true

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_success "Namespace $ns exists"
        else
            log_failure "Namespace $ns does not exist"
            all_good=false
        fi
    done

    if [ "$all_good" = true ]; then
        return 0
    else
        return 1
    fi
}

test_infrastructure_pods() {
    log_step "Testing infrastructure pods"

    local infrastructure_pods=("postgres" "redis")
    local all_good=true

    for pod in "${infrastructure_pods[@]}"; do
        if kubectl get pods -n "$NAMESPACE" -l app="$pod" | grep -q "Running"; then
            log_success "Infrastructure pod $pod is running"
        else
            log_failure "Infrastructure pod $pod is not running"
            all_good=false
        fi
    done

    return $([[ "$all_good" == "true" ]] && echo 0 || echo 1)
}

test_kafka_cluster() {
    log_step "Testing Kafka cluster"

    # Check Kafka pods
    local kafka_running=$(kubectl get pods -n "$KAFKA_NAMESPACE" -l app=kafka --no-headers | grep "Running" | wc -l)

    if [ "$kafka_running" -ge 1 ]; then
        log_success "Kafka cluster is running ($kafka_running pods)"
    else
        log_failure "Kafka cluster is not running properly"
        return 1
    fi

    # Check Zookeeper
    if kubectl get pods -n "$KAFKA_NAMESPACE" -l app=zookeeper | grep -q "Running"; then
        log_success "Zookeeper is running"
    else
        log_failure "Zookeeper is not running"
        return 1
    fi
}

test_application_services() {
    log_step "Testing application services"

    local services=("gateway" "auth" "sales" "inventory" "finance" "saas")
    local all_good=true

    for service in "${services[@]}"; do
        local running_pods=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers | grep "Running" | wc -l)

        if [ "$running_pods" -ge 1 ]; then
            log_success "Service $service is running ($running_pods pods)"
        else
            log_failure "Service $service is not running"
            all_good=false
        fi
    done

    return $([[ "$all_good" == "true" ]] && echo 0 || echo 1)
}

test_service_connectivity() {
    log_step "Testing service connectivity"

    # Test internal service connectivity
    local gateway_pod=$(kubectl get pods -n "$NAMESPACE" -l app=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -n "$gateway_pod" ]; then
        # Test database connectivity
        if kubectl exec -n "$NAMESPACE" "$gateway_pod" -- nc -z postgres 5432 &> /dev/null; then
            log_success "Gateway can connect to PostgreSQL"
        else
            log_failure "Gateway cannot connect to PostgreSQL"
            return 1
        fi

        # Test Redis connectivity
        if kubectl exec -n "$NAMESPACE" "$gateway_pod" -- nc -z redis 6379 &> /dev/null; then
            log_success "Gateway can connect to Redis"
        else
            log_failure "Gateway cannot connect to Redis"
            return 1
        fi

        # Test Kafka connectivity
        if kubectl exec -n "$NAMESPACE" "$gateway_pod" -- nc -z kafka.liquorpro-kafka.svc.cluster.local 9092 &> /dev/null; then
            log_success "Gateway can connect to Kafka"
        else
            log_failure "Gateway cannot connect to Kafka"
            return 1
        fi
    else
        log_failure "Cannot find gateway pod for connectivity testing"
        return 1
    fi
}

test_health_endpoints() {
    log_step "Testing service health endpoints"

    local services=("gateway:8090" "auth:8091" "sales:8092" "inventory:8093" "finance:8094" "saas:8095")
    local all_good=true

    for service_port in "${services[@]}"; do
        local service=$(echo "$service_port" | cut -d: -f1)
        local port=$(echo "$service_port" | cut -d: -f2)

        local pod=$(kubectl get pods -n "$NAMESPACE" -l app="$service" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

        if [ -n "$pod" ]; then
            if kubectl exec -n "$NAMESPACE" "$pod" -- curl -f "http://localhost:$port/health" &> /dev/null; then
                log_success "Service $service health endpoint is responding"
            else
                log_failure "Service $service health endpoint is not responding"
                all_good=false
            fi
        else
            log_failure "Cannot find pod for service $service"
            all_good=false
        fi
    done

    return $([[ "$all_good" == "true" ]] && echo 0 || echo 1)
}

test_istio_configuration() {
    log_step "Testing Istio service mesh configuration"

    # Check if Istio is installed
    if ! kubectl get namespace istio-system &> /dev/null; then
        log_failure "Istio namespace does not exist"
        return 1
    fi

    # Check Istio gateway
    if kubectl get gateway liquorpro-gateway -n "$NAMESPACE" &> /dev/null; then
        log_success "Istio gateway is configured"
    else
        log_failure "Istio gateway is not configured"
        return 1
    fi

    # Check virtual service
    if kubectl get virtualservice liquorpro-vs -n "$NAMESPACE" &> /dev/null; then
        log_success "Istio virtual service is configured"
    else
        log_failure "Istio virtual service is not configured"
        return 1
    fi

    # Check if pods have Istio sidecar
    local pods_with_sidecar=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[*].name}' | grep -o istio-proxy | wc -l)

    if [ "$pods_with_sidecar" -gt 0 ]; then
        log_success "Istio sidecars are injected ($pods_with_sidecar sidecars)"
    else
        log_failure "No Istio sidecars found"
        return 1
    fi
}

test_monitoring_stack() {
    log_step "Testing monitoring stack"

    # Test Prometheus
    if kubectl get pods -n "$MONITORING_NAMESPACE" -l app=prometheus | grep -q "Running"; then
        log_success "Prometheus is running"
    else
        log_failure "Prometheus is not running"
        return 1
    fi

    # Test Grafana
    if kubectl get pods -n "$MONITORING_NAMESPACE" -l app=grafana | grep -q "Running"; then
        log_success "Grafana is running"
    else
        log_failure "Grafana is not running"
        return 1
    fi

    # Test Jaeger
    if kubectl get pods -n "$MONITORING_NAMESPACE" -l app=jaeger-collector | grep -q "Running"; then
        log_success "Jaeger collector is running"
    else
        log_failure "Jaeger collector is not running"
        return 1
    fi

    if kubectl get pods -n "$MONITORING_NAMESPACE" -l app=jaeger-query | grep -q "Running"; then
        log_success "Jaeger query is running"
    else
        log_failure "Jaeger query is not running"
        return 1
    fi
}

test_ingress_configuration() {
    log_step "Testing ingress configuration"

    # Check if ingress exists
    if kubectl get ingress liquorpro-ingress -n "$NAMESPACE" &> /dev/null; then
        log_success "Main ingress is configured"
    else
        log_failure "Main ingress is not configured"
        return 1
    fi

    # Check if monitoring ingress exists
    if kubectl get ingress monitoring-ingress -n "$MONITORING_NAMESPACE" &> /dev/null; then
        log_success "Monitoring ingress is configured"
    else
        log_failure "Monitoring ingress is not configured"
        return 1
    fi

    # Check if ingress controller is running
    if kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep -q "Running"; then
        log_success "NGINX ingress controller is running"
    else
        log_failure "NGINX ingress controller is not running"
        return 1
    fi
}

test_database_migrations() {
    log_step "Testing database migrations"

    # Check if migration job completed successfully
    if kubectl get job db-migration -n "$NAMESPACE" &> /dev/null; then
        local job_status=$(kubectl get job db-migration -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)

        if [ "$job_status" = "Complete" ]; then
            log_success "Database migrations completed successfully"
        else
            log_failure "Database migrations did not complete successfully (Status: $job_status)"
            return 1
        fi
    else
        log_warning "Migration job not found (may not have been run yet)"
    fi

    # Test database connectivity from application
    local gateway_pod=$(kubectl get pods -n "$NAMESPACE" -l app=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -n "$gateway_pod" ]; then
        if kubectl exec -n "$NAMESPACE" "$gateway_pod" -- pg_isready -h postgres -p 5432 -U liquorpro &> /dev/null; then
            log_success "Database is ready and accepting connections"
        else
            log_failure "Database is not ready or not accepting connections"
            return 1
        fi
    fi
}

test_resource_usage() {
    log_step "Testing resource usage and limits"

    # Check if any pods are in pending state
    local pending_pods=$(kubectl get pods --all-namespaces --no-headers | grep "Pending" | wc -l)

    if [ "$pending_pods" -eq 0 ]; then
        log_success "No pods are in pending state"
    else
        log_failure "$pending_pods pods are in pending state (resource constraints?)"
        return 1
    fi

    # Check if any pods have been OOMKilled
    local oomkilled_pods=$(kubectl get pods --all-namespaces -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}' | grep -o "OOMKilled" | wc -l)

    if [ "$oomkilled_pods" -eq 0 ]; then
        log_success "No pods have been OOMKilled"
    else
        log_failure "$oomkilled_pods pods have been OOMKilled"
        return 1
    fi
}

test_autoscaling() {
    log_step "Testing horizontal pod autoscaler configuration"

    local services=("gateway" "auth" "sales" "inventory" "finance" "saas")
    local all_good=true

    for service in "${services[@]}"; do
        if kubectl get hpa "${service}-hpa" -n "$NAMESPACE" &> /dev/null; then
            log_success "HPA configured for $service"
        else
            log_failure "HPA not configured for $service"
            all_good=false
        fi
    done

    return $([[ "$all_good" == "true" ]] && echo 0 || echo 1)
}

test_security_policies() {
    log_step "Testing security policies"

    # Check network policies
    local network_policies=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers | wc -l)

    if [ "$network_policies" -gt 0 ]; then
        log_success "Network policies are configured ($network_policies policies)"
    else
        log_failure "No network policies found"
        return 1
    fi

    # Check if pods are running as non-root
    local non_root_pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.securityContext.runAsNonRoot}' | grep -o "true" | wc -l)

    if [ "$non_root_pods" -gt 0 ]; then
        log_success "Pods are configured to run as non-root"
    else
        log_warning "Some pods may be running as root"
    fi
}

# Load testing function
test_load_performance() {
    log_step "Testing basic load performance"

    # Get gateway service endpoint
    local gateway_pod=$(kubectl get pods -n "$NAMESPACE" -l app=gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -n "$gateway_pod" ]; then
        # Port forward to gateway for testing
        kubectl port-forward -n "$NAMESPACE" "pod/$gateway_pod" 8090:8090 &
        local port_forward_pid=$!

        # Wait for port forward to establish
        sleep 3

        # Perform basic load test
        local success_count=0
        local total_requests=10

        for i in $(seq 1 $total_requests); do
            if curl -s -f "http://localhost:8090/health" &> /dev/null; then
                ((success_count++))
            fi
            sleep 0.1
        done

        # Kill port forward
        kill $port_forward_pid &> /dev/null || true

        local success_rate=$((success_count * 100 / total_requests))

        if [ "$success_rate" -ge 90 ]; then
            log_success "Load test passed (${success_rate}% success rate)"
        else
            log_failure "Load test failed (${success_rate}% success rate)"
            return 1
        fi
    else
        log_failure "Cannot find gateway pod for load testing"
        return 1
    fi
}

# Main test execution
run_all_tests() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    LiquorPro Kubernetes Testing Suite                       ║"
    echo "║                        End-to-End Verification                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    # Infrastructure tests
    test_kubernetes_cluster
    test_namespaces
    test_infrastructure_pods
    test_kafka_cluster

    # Application tests
    test_application_services
    test_service_connectivity
    test_health_endpoints
    test_database_migrations

    # Configuration tests
    test_istio_configuration
    test_ingress_configuration
    test_autoscaling
    test_security_policies

    # Monitoring tests
    test_monitoring_stack

    # Performance tests
    test_resource_usage
    test_load_performance
}

# Generate test report
generate_report() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                       Test Results                         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Total Tests:${NC} $TOTAL_TESTS"
    echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
    echo -e "${RED}Failed:${NC} $FAILED_TESTS"
    echo ""

    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))

    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! Your LiquorPro deployment is healthy.${NC}"
        echo -e "${GREEN}✅ Success Rate: ${success_rate}%${NC}"
    elif [ "$success_rate" -ge 80 ]; then
        echo -e "${YELLOW}⚠️  Most tests passed with some issues.${NC}"
        echo -e "${YELLOW}📊 Success Rate: ${success_rate}%${NC}"
        echo -e "${YELLOW}🔧 Please review failed tests and fix issues.${NC}"
    else
        echo -e "${RED}❌ Multiple tests failed. Deployment needs attention.${NC}"
        echo -e "${RED}📊 Success Rate: ${success_rate}%${NC}"
        echo -e "${RED}🚨 Please review the deployment configuration.${NC}"
    fi

    echo ""
    echo -e "${BLUE}📝 For detailed logs, run:${NC}"
    echo "   kubectl logs -n $NAMESPACE -l tier=api --tail=100"
    echo "   kubectl logs -n $MONITORING_NAMESPACE -l app=prometheus --tail=100"
    echo ""
    echo -e "${BLUE}🔍 To check pod status:${NC}"
    echo "   kubectl get pods --all-namespaces"
    echo ""
    echo -e "${BLUE}📊 To access monitoring:${NC}"
    echo "   kubectl port-forward -n $MONITORING_NAMESPACE svc/grafana 3000:3000"
    echo "   kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus 9090:9090"
    echo ""
}

# Main function
main() {
    run_all_tests
    generate_report

    # Exit with appropriate code
    if [ "$FAILED_TESTS" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script interruption
trap 'log_warning "Testing interrupted"; exit 1' INT TERM

# Run main function
main "$@"