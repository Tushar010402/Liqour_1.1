#!/bin/bash

# LiquorPro - Development Environment Startup Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🍾 LiquorPro - Development Environment"
echo "====================================="

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker Desktop."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose."
    exit 1
fi

print_success "Prerequisites check passed ✓"

# Check if containers are already running
if docker-compose -f docker-compose.dev.yml ps | grep -q "Up"; then
    print_warning "Development environment is already running."
    echo ""
    print_status "Current status:"
    docker-compose -f docker-compose.dev.yml ps
    echo ""
    
    read -p "Do you want to restart the environment? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stopping existing environment..."
        docker-compose -f docker-compose.dev.yml down
    else
        print_status "Keeping existing environment running."
        print_success "Access the application at: http://localhost:8095"
        exit 0
    fi
fi

# Create necessary directories
print_status "Creating necessary directories..."
mkdir -p logs
mkdir -p data/postgres
mkdir -p data/redis

# Start development environment
print_status "Starting development environment..."
docker-compose -f docker-compose.dev.yml up -d

# Wait for services to be healthy
print_status "Waiting for services to start..."
sleep 10

# Check service health
print_status "Checking service health..."

SERVICES=("postgres" "redis" "gateway" "auth" "sales" "inventory" "finance" "frontend")
PORTS=(5433 6380 8090 8091 8092 8093 8094 8095)

for i in "${!SERVICES[@]}"; do
    service=${SERVICES[$i]}
    port=${PORTS[$i]}
    
    if docker-compose -f docker-compose.dev.yml ps | grep "$service" | grep -q "Up"; then
        print_success "$service is running on port $port ✓"
    else
        print_warning "$service is not running properly ✗"
    fi
done

echo ""
print_status "🌐 Development URLs:"
echo "===================="
echo "Frontend (Main App):    http://localhost:8095"
echo "API Gateway:           http://localhost:8090"
echo "Auth Service:          http://localhost:8091"
echo "Sales Service:         http://localhost:8092"
echo "Inventory Service:     http://localhost:8093"
echo "Finance Service:       http://localhost:8094"
echo ""

print_status "🛠️  Development Tools:"
echo "======================="
echo "Adminer (DB Admin):    http://localhost:8090"
echo "Redis Commander:       http://localhost:8091"
echo "MailHog (Email):       http://localhost:8025"
echo ""

print_status "📊 Database Connection:"
echo "======================="
echo "Host:                  localhost"
echo "Port:                  5433"
echo "Database:              liquorpro_dev"
echo "Username:              dev_user"
echo "Password:              dev_password"
echo ""

print_status "🔧 Useful Commands:"
echo "==================="
echo "View logs:             docker-compose -f docker-compose.dev.yml logs -f [service-name]"
echo "Stop environment:      docker-compose -f docker-compose.dev.yml down"
echo "Restart service:       docker-compose -f docker-compose.dev.yml restart [service-name]"
echo "Build specific service: docker-compose -f docker-compose.dev.yml build [service-name]"
echo "Execute in container:  docker-compose -f docker-compose.dev.yml exec [service-name] sh"
echo ""

# Final health check
print_status "Performing final health checks..."

# Check if frontend is responding
if curl -f -s http://localhost:8095/health > /dev/null 2>&1; then
    print_success "Frontend health check passed ✓"
else
    print_warning "Frontend health check failed - service may still be starting"
fi

# Check if gateway is responding
if curl -f -s http://localhost:8090/health > /dev/null 2>&1; then
    print_success "Gateway health check passed ✓"
else
    print_warning "Gateway health check failed - service may still be starting"
fi

echo ""
print_success "🎉 Development environment is ready!"
print_status "📱 Open http://localhost:8095 to access LiquorPro"
echo ""

# Option to show logs
read -p "Do you want to view the logs? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Showing logs... (Press Ctrl+C to exit)"
    docker-compose -f docker-compose.dev.yml logs -f
fi