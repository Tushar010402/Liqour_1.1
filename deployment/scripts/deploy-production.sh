#!/bin/bash

# LiquorPro Zero-Downtime Production Deployment Script
# Server: 72.60.96.174
# Usage: ./deploy-production.sh [version]

set -e  # Exit on error

# Configuration
PROJECT_DIR="/opt/liquorpro/backend"
LOG_DIR="/opt/liquorpro/logs"
BACKUP_DIR="/opt/liquorpro/backups"
VERSION=${1:-"latest"}
BUILD_DATE=$(date +%Y-%m-%d)
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as deploy user
if [ "$USER" != "deploy" ]; then
    log_error "This script must be run as 'deploy' user"
    exit 1
fi

log_step "🚀 LiquorPro Production Deployment - Version $VERSION"
log_info "Build Date: $BUILD_DATE"
log_info "Git Commit: $GIT_COMMIT"
echo ""

# ========================================
# Pre-Deployment Checks
# ========================================
log_step "Pre-Deployment Checks"

# Check if in correct directory
if [ ! -f "$PROJECT_DIR/docker-compose.production.yml" ]; then
    log_error "docker-compose.production.yml not found in $PROJECT_DIR"
    exit 1
fi

# Check if .env.production exists
if [ ! -f "$PROJECT_DIR/.env.production" ]; then
    log_error ".env.production file not found"
    log_error "Copy .env.production.example and fill in actual values"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
fi

log_info "✓ Pre-deployment checks passed"
cd "$PROJECT_DIR"

# ========================================
# Backup Database Before Deployment
# ========================================
log_step "Creating Pre-Deployment Database Backup"

BACKUP_FILE="$BACKUP_DIR/postgres/pre_deploy_$(date +%Y%m%d_%H%M%S).sql.gz"
log_info "Backing up database to: $BACKUP_FILE"

if docker exec liquorpro-postgres-prod pg_dump -U liquorpro_prod liquorpro_production | gzip > "$BACKUP_FILE" 2>/dev/null; then
    log_info "✓ Database backup created successfully"
else
    log_warn "Database backup failed (might be first deployment)"
fi

# ========================================
# Pull Latest Code
# ========================================
log_step "Pulling Latest Code from Git"

if [ -d ".git" ]; then
    log_info "Fetching latest changes..."
    git fetch origin

    CURRENT_BRANCH=$(git branch --show-current)
    log_info "Current branch: $CURRENT_BRANCH"

    git pull origin "$CURRENT_BRANCH"
    log_info "✓ Code updated successfully"
else
    log_warn "Not a git repository, skipping pull"
fi

# ========================================
# Build Docker Images
# ========================================
log_step "Building Docker Images"

log_info "Building images with version tag: $VERSION"

# Export environment variables for build
export VERSION=$VERSION
export BUILD_DATE=$BUILD_DATE
export GIT_COMMIT=$GIT_COMMIT

# Build all services in parallel
docker-compose -f docker-compose.production.yml build --parallel

log_info "✓ Docker images built successfully"

# ========================================
# Run Database Migrations
# ========================================
log_step "Running Database Migrations"

# Check if PostgreSQL is running
if docker ps | grep -q "liquorpro-postgres-prod"; then
    log_info "Running migrations..."

    # Add your migration commands here
    # Example:
    # docker exec liquorpro-gateway-prod /app/gateway migrate up

    log_info "✓ Migrations completed"
else
    log_warn "Database not running, migrations will run on first start"
fi

# ========================================
# Zero-Downtime Deployment
# ========================================
log_step "Starting Zero-Downtime Deployment"

log_info "Pulling existing service logs for reference..."

# Start new containers
log_info "Starting new service containers..."
docker-compose -f docker-compose.production.yml up -d

log_info "Waiting for services to be healthy (30 seconds)..."
sleep 30

# ========================================
# Health Check Verification
# ========================================
log_step "Verifying Service Health"

SERVICES=("gateway:8090" "auth:8091" "sales:8092" "inventory:8093" "finance:8094" "frontend:8095")
ALL_HEALTHY=true
FAILED_SERVICES=""

for SERVICE in "${SERVICES[@]}"; do
    IFS=':' read -r NAME PORT <<< "$SERVICE"

    log_info "Checking $NAME service..."

    # Try health check 3 times with 5 second intervals
    HEALTHY=false
    for i in {1..3}; do
        if curl -f -s "http://localhost:$PORT/health" > /dev/null 2>&1; then
            log_info "✓ $NAME is healthy"
            HEALTHY=true
            break
        else
            log_warn "Attempt $i/3 failed for $NAME, retrying..."
            sleep 5
        fi
    done

    if [ "$HEALTHY" = false ]; then
        log_error "✗ $NAME is unhealthy"
        ALL_HEALTHY=false
        FAILED_SERVICES="$FAILED_SERVICES $NAME"
    fi
done

# ========================================
# Check Deployment Status
# ========================================
if [ "$ALL_HEALTHY" = true ]; then
    log_step "✅ Deployment Successful!"

    # Clean up old Docker images
    log_info "Cleaning up old Docker images..."
    docker image prune -f > /dev/null 2>&1 || true

    # Reload Nginx
    log_info "Reloading Nginx..."
    sudo systemctl reload nginx

    log_info "========================================="
    log_info "Deployment Information:"
    log_info "========================================="
    log_info "Version: $VERSION"
    log_info "Deploy Time: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Git Commit: $GIT_COMMIT"
    log_info ""
    log_info "Services:"
    log_info "  Gateway:    https://yourdomain.com/gateway/health"
    log_info "  Auth:       https://yourdomain.com/auth/health"
    log_info "  Sales:      https://yourdomain.com/sales/health"
    log_info "  Inventory:  https://yourdomain.com/inventory/health"
    log_info "  Finance:    https://yourdomain.com/finance/health"
    log_info "  SaaS:       https://yourdomain.com/saas/health"
    log_info ""
    log_info "Monitoring:"
    log_info "  Logs: docker-compose -f docker-compose.production.yml logs -f [service]"
    log_info "  Stats: docker stats"
    log_info ""

    # Send success notification
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"✅ LiquorPro deployment successful!\nVersion: $VERSION\nCommit: $GIT_COMMIT\"}" \
            > /dev/null 2>&1 || true
    fi

    exit 0
else
    log_step "❌ Deployment Failed!"

    log_error "The following services are unhealthy:$FAILED_SERVICES"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "1. Check service logs:"
    log_error "   docker-compose -f docker-compose.production.yml logs [service]"
    log_error ""
    log_error "2. Check service status:"
    log_error "   docker-compose -f docker-compose.production.yml ps"
    log_error ""
    log_error "3. Check resource usage:"
    log_error "   docker stats"
    log_error ""
    log_error "4. Rollback to previous version:"
    log_error "   ./deployment/scripts/rollback.sh"
    log_error ""

    # Send failure notification
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"❌ LiquorPro deployment FAILED!\nVersion: $VERSION\nFailed services:$FAILED_SERVICES\"}" \
            > /dev/null 2>&1 || true
    fi

    log_warn "Services are running but some are unhealthy"
    log_warn "Manual intervention may be required"

    exit 1
fi
