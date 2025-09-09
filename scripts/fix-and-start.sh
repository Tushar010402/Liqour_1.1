#!/bin/bash

# LiquorPro - Fix and Start Script
set -e

echo "🔧 LiquorPro Backend - Fixing Issues and Starting Services"
echo "========================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function for colored output
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

# 1. Clean up previous containers and networks
log_info "Cleaning up previous containers and networks..."
docker-compose -f docker-compose.dev.yml down -v 2>/dev/null || true
docker system prune -f >/dev/null 2>&1 || true
log_success "Cleanup completed"

# 2. Create required directories
log_info "Creating required directories..."
mkdir -p logs
mkdir -p data/postgres
mkdir -p data/redis
log_success "Directories created"

# 3. Fix docker-compose version warning
log_info "Fixing docker-compose configuration..."
if [ -f docker-compose.dev.yml ]; then
    # Remove version line if it exists
    sed -i '' '/^version:/d' docker-compose.dev.yml 2>/dev/null || true
    log_success "Docker-compose configuration fixed"
fi

# 4. Start database and cache first
log_info "Starting database and cache services..."
docker-compose -f docker-compose.dev.yml up -d postgres redis
log_success "Database and cache services started"

# 5. Wait for database to be ready
log_info "Waiting for database to be ready..."
for i in {1..30}; do
    if docker exec liquorpro-dev-postgres pg_isready -U dev_user -d postgres >/dev/null 2>&1; then
        log_success "Database is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Database failed to start within 30 seconds"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# 6. Create databases if they don't exist
log_info "Setting up databases..."
docker exec liquorpro-dev-postgres createdb -U dev_user liquorpro 2>/dev/null || log_warning "liquorpro database already exists"
docker exec liquorpro-dev-postgres createdb -U dev_user liquorpro_dev 2>/dev/null || log_warning "liquorpro_dev database already exists"
log_success "Databases ready"

# 7. Wait for Redis to be ready  
log_info "Waiting for Redis to be ready..."
for i in {1..15}; do
    if docker exec liquorpro-dev-redis redis-cli -a dev_redis_pass ping >/dev/null 2>&1; then
        log_success "Redis is ready"
        break
    fi
    if [ $i -eq 15 ]; then
        log_error "Redis failed to start within 15 seconds"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# 8. Start backend services
log_info "Starting backend services..."
docker-compose -f docker-compose.dev.yml up -d auth sales inventory finance gateway
log_success "Backend services started"

# 9. Wait for services to be ready
log_info "Waiting for services to initialize..."
sleep 15

# 10. Check service health
log_info "Checking service health..."

check_service_health() {
    local service_name=$1
    local port=$2
    local max_attempts=10
    
    for i in $(seq 1 $max_attempts); do
        if nc -z localhost $port 2>/dev/null; then
            log_success "$service_name (port $port) is responding"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    log_warning "$service_name (port $port) is not responding yet"
    return 1
}

# Check each service
check_service_health "Gateway" 8090
check_service_health "Auth" 8091
check_service_health "Sales" 8092
check_service_health "Inventory" 8093
check_service_health "Finance" 8094

# 11. Test basic endpoints
log_info "Testing basic endpoints..."

test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=$3
    
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 $url 2>/dev/null || echo "000")
    
    if [ "$response" = "$expected_status" ]; then
        log_success "$name: HTTP $response ✓"
    else
        log_warning "$name: HTTP $response (expected $expected_status)"
    fi
}

# Test health endpoints
test_endpoint "Gateway Health" "http://localhost:8090/gateway/health" "200"
test_endpoint "Gateway Version" "http://localhost:8090/gateway/version" "200" 
test_endpoint "Auth Health" "http://localhost:8091/health" "200"

# 12. Display service information
echo ""
log_info "Service Information:"
echo "==================="
echo "🚪 Gateway Service:    http://localhost:8090"
echo "🔐 Auth Service:       http://localhost:8091" 
echo "💰 Sales Service:      http://localhost:8092"
echo "📦 Inventory Service:  http://localhost:8093"
echo "💳 Finance Service:    http://localhost:8094"
echo "🗄️  Database (Adminer): http://localhost:8100"
echo "📧 Email (MailHog):    http://localhost:8025"
echo "💾 Redis Commander:   http://localhost:8101"
echo ""

# 13. Display testing commands
log_info "Quick Testing Commands:"
echo "======================="
echo "# Test Gateway Health:"
echo "curl http://localhost:8090/gateway/health"
echo ""
echo "# Register Test User:"
echo 'curl -X POST http://localhost:8090/api/auth/register \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{'
echo '    "username": "admin",'
echo '    "email": "admin@test.com",'
echo '    "password": "SecurePass123!",'
echo '    "first_name": "Admin",'
echo '    "last_name": "User",'
echo '    "tenant_name": "Test Store",'
echo '    "company_name": "Test Store LLC"'
echo '  }'"'"
echo ""
echo "# Login Test User:"
echo 'curl -X POST http://localhost:8090/api/auth/login \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{'
echo '    "username": "admin",'
echo '    "password": "SecurePass123!"'
echo '  }'"'"
echo ""

# 14. Display logs command
log_info "View Logs:"
echo "=========="
echo "# View all service logs:"
echo "docker-compose -f docker-compose.dev.yml logs -f"
echo ""
echo "# View specific service logs:"
echo "docker logs -f liquorpro-dev-gateway"
echo "docker logs -f liquorpro-dev-auth"
echo ""

log_success "🎉 LiquorPro Backend setup completed!"
log_info "All services should now be running and accessible."

# 15. Optional: Run a quick integration test
if [ "$1" = "--test" ]; then
    echo ""
    log_info "Running integration test..."
    
    # Test user registration
    response=$(curl -s -X POST http://localhost:8090/api/auth/register \
        -H "Content-Type: application/json" \
        -d '{
            "username": "testuser",
            "email": "test@test.com", 
            "password": "TestPass123!",
            "first_name": "Test",
            "last_name": "User",
            "tenant_name": "Test Tenant",
            "company_name": "Test Company"
        }' 2>/dev/null || echo "ERROR")
    
    if echo "$response" | grep -q "token"; then
        log_success "Integration test PASSED - User registration working"
    else
        log_warning "Integration test FAILED - Check service logs"
        echo "Response: $response"
    fi
fi

echo ""
echo "🚀 Ready to test APIs! Use the commands above to get started."