#!/bin/bash

# LiquorPro SaaS Production Deployment Script
# This script automates the production deployment process
set -e

echo "🚀 Starting LiquorPro SaaS Production Deployment..."

# Configuration
SAAS_SERVICE_PORT=8095
DB_CONTAINER="liquorpro-postgres"
REDIS_CONTAINER="liquorpro-redis"
SAAS_CONTAINER="liquorpro-saas"

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

# Function to check if service is healthy
check_service_health() {
    local service_name=$1
    local health_url=$2
    local max_attempts=30
    local attempt=1

    log_info "Checking $service_name health..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$health_url" > /dev/null 2>&1; then
            log_success "$service_name is healthy!"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts: $service_name not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    log_error "$service_name failed to become healthy within $((max_attempts * 2)) seconds"
    return 1
}

# Function to run API tests
run_api_tests() {
    log_info "Running API functionality tests..."
    
    # Test health endpoint
    if ! curl -s -f "http://localhost:$SAAS_SERVICE_PORT/health" > /dev/null; then
        log_error "Health check failed"
        return 1
    fi
    
    # Test public plans endpoint
    if ! curl -s -f "http://localhost:$SAAS_SERVICE_PORT/api/plans" | jq '.plans' > /dev/null 2>&1; then
        log_error "Plans API test failed"
        return 1
    fi
    
    # Test billing options endpoint
    if ! curl -s -f "http://localhost:$SAAS_SERVICE_PORT/api/plans/with-billing-options" | jq '.data' > /dev/null 2>&1; then
        log_error "Billing options API test failed"
        return 1
    fi
    
    log_success "All API tests passed!"
    return 0
}

# Function to verify database migrations
verify_migrations() {
    log_info "Verifying database migrations..."
    
    # Check if all required tables exist
    local required_tables=(
        "pricing_plans"
        "subscriptions"
        "plan_billing_variants"
        "global_discount_config"
        "plan_discount_override"
        "billing_term_config"
        "payments"
        "invoices"
        "usage_records"
        "webhook_events"
        "admin_users"
        "audit_logs"
    )
    
    for table in "${required_tables[@]}"; do
        if ! docker exec $DB_CONTAINER psql -U liquorpro -d liquorpro -c "\\dt" | grep -q "$table"; then
            log_error "Required table '$table' not found in database"
            return 1
        fi
    done
    
    log_success "All required database tables verified!"
    return 0
}

# Function to initialize default data
initialize_default_data() {
    log_info "Initializing default data if needed..."
    
    # Check if plans exist
    local plans_count=$(curl -s "http://localhost:$SAAS_SERVICE_PORT/api/plans" | jq '.plans | length' 2>/dev/null || echo "0")
    
    if [ "$plans_count" -eq 0 ]; then
        log_warning "No plans found, will need manual initialization through admin interface"
    else
        log_success "Found $plans_count existing plans"
    fi
    
    # Check pricing plan configuration
    local first_plan_id=$(curl -s "http://localhost:$SAAS_SERVICE_PORT/api/plans" | jq -r '.plans[0].id' 2>/dev/null || echo "")
    
    if [ -n "$first_plan_id" ] && [ "$first_plan_id" != "null" ]; then
        local billing_options=$(curl -s "http://localhost:$SAAS_SERVICE_PORT/api/plans/$first_plan_id/billing-options" | jq '.data.billing_options | length' 2>/dev/null || echo "0")
        if [ "$billing_options" -ge 4 ]; then
            log_success "Multi-term billing options configured correctly"
        else
            log_warning "Multi-term billing options may need configuration"
        fi
    fi
}

# Main deployment flow
main() {
    log_info "Production Deployment Checklist Starting..."
    
    # Step 1: Build and start services
    log_info "Step 1: Building and starting services..."
    if ! docker-compose up -d --build; then
        log_error "Failed to start services with docker-compose"
        exit 1
    fi
    log_success "Services started successfully"
    
    # Step 2: Wait for database to be ready
    log_info "Step 2: Waiting for database to be ready..."
    if ! check_service_health "PostgreSQL" ""; then
        # For PostgreSQL, we check by attempting a connection
        local attempt=1
        while [ $attempt -le 30 ]; do
            if docker exec $DB_CONTAINER pg_isready -U liquorpro > /dev/null 2>&1; then
                log_success "PostgreSQL is ready!"
                break
            fi
            log_info "Attempt $attempt/30: PostgreSQL not ready yet..."
            sleep 2
            ((attempt++))
        done
        
        if [ $attempt -gt 30 ]; then
            log_error "PostgreSQL failed to become ready"
            exit 1
        fi
    fi
    
    # Step 3: Wait for Redis to be ready
    log_info "Step 3: Waiting for Redis to be ready..."
    local attempt=1
    while [ $attempt -le 30 ]; do
        if docker exec $REDIS_CONTAINER redis-cli ping > /dev/null 2>&1; then
            log_success "Redis is ready!"
            break
        fi
        log_info "Attempt $attempt/30: Redis not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt 30 ]; then
        log_error "Redis failed to become ready"
        exit 1
    fi
    
    # Step 4: Wait for SaaS service to be ready
    log_info "Step 4: Waiting for SaaS service to be ready..."
    if ! check_service_health "SaaS Service" "http://localhost:$SAAS_SERVICE_PORT/health"; then
        exit 1
    fi
    
    # Step 5: Verify database migrations
    log_info "Step 5: Verifying database migrations..."
    if ! verify_migrations; then
        exit 1
    fi
    
    # Step 6: Run API tests
    log_info "Step 6: Running API functionality tests..."
    if ! run_api_tests; then
        exit 1
    fi
    
    # Step 7: Initialize default data
    log_info "Step 7: Checking default data..."
    initialize_default_data
    
    # Step 8: Performance verification
    log_info "Step 8: Running performance tests..."
    local response_time=$(curl -s -w "%{time_total}" -o /dev/null "http://localhost:$SAAS_SERVICE_PORT/health")
    local response_time_ms=$(echo "$response_time * 1000" | bc)
    
    if (( $(echo "$response_time < 0.1" | bc -l) )); then
        log_success "Health endpoint response time: ${response_time_ms}ms (< 100ms target)"
    else
        log_warning "Health endpoint response time: ${response_time_ms}ms (slower than 100ms target)"
    fi
    
    # Final summary
    echo ""
    log_success "🎉 PRODUCTION DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
    echo ""
    echo "Service URLs:"
    echo "  • Health Check: http://localhost:$SAAS_SERVICE_PORT/health"
    echo "  • Plans API: http://localhost:$SAAS_SERVICE_PORT/api/plans"
    echo "  • Billing Options: http://localhost:$SAAS_SERVICE_PORT/api/plans/with-billing-options"
    echo ""
    echo "Admin Access:"
    echo "  • Admin endpoints require JWT authentication with super_admin role"
    echo "  • Use the Flutter admin interface for management"
    echo ""
    echo "Next Steps:"
    echo "  1. Configure production JWT secrets"
    echo "  2. Set up proper SSL/TLS certificates"
    echo "  3. Configure production database credentials"
    echo "  4. Set up monitoring and alerting"
    echo "  5. Initialize default discount configurations through admin UI"
    echo ""
    log_info "Deployment completed at $(date)"
}

# Check for required dependencies
command -v docker >/dev/null 2>&1 || { log_error "docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { log_error "docker-compose is required but not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { log_error "curl is required but not installed."; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed."; exit 1; }
command -v bc >/dev/null 2>&1 || { log_error "bc is required but not installed."; exit 1; }

# Run main function
main "$@"