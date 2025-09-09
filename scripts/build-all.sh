#!/bin/bash

# LiquorPro - Build All Services Script
set -e

echo "🍾 LiquorPro - Building all services..."

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

# Check if Go is installed
if ! command -v go &> /dev/null; then
    print_error "Go is not installed. Please install Go 1.21 or later."
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
REQUIRED_VERSION="1.21"

if ! printf '%s\n%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V -C; then
    print_error "Go version $GO_VERSION is too old. Please upgrade to Go $REQUIRED_VERSION or later."
    exit 1
fi

print_status "Go version $GO_VERSION detected ✓"

# Create build directory
mkdir -p build

print_status "Installing dependencies..."
go mod download
go mod tidy

# Build services
SERVICES=(
    "gateway"
    "auth"
    "sales"
    "inventory"
    "finance"
    "frontend"
)

for service in "${SERVICES[@]}"; do
    print_status "Building $service service..."
    
    if CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-w -s" -o "build/$service" "./cmd/$service/main.go"; then
        print_success "$service service built successfully"
    else
        print_error "Failed to build $service service"
        exit 1
    fi
done

print_success "All services built successfully!"

# Build info
echo ""
echo "📦 Build Summary:"
echo "=================="
ls -la build/
echo ""

# Docker build option
if command -v docker &> /dev/null; then
    echo "🐳 Docker detected!"
    echo ""
    echo "To build Docker images:"
    echo "  docker-compose build"
    echo ""
    echo "To start all services:"
    echo "  docker-compose up -d"
    echo ""
    echo "To start development environment:"
    echo "  docker-compose -f docker-compose.dev.yml up -d"
else
    print_warning "Docker not found. Install Docker to use containerized deployment."
fi

print_success "🍾 Build completed successfully!"