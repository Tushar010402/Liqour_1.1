#!/bin/bash

# LiquorPro Rollback Script
# Rolls back to previous Docker image versions
# Usage: ./rollback.sh

set -e

# Configuration
PROJECT_DIR="/opt/liquorpro/backend"
BACKUP_DIR="/opt/liquorpro/backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

log_step "🔄 LiquorPro Rollback Procedure"

cd "$PROJECT_DIR"

# ========================================
# List Available Versions
# ========================================
log_step "Available Docker Image Versions"

echo ""
log_info "Gateway versions:"
docker images liquorpro/gateway --format "table {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" | head -5

echo ""
log_info "Auth versions:"
docker images liquorpro/auth --format "table {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" | head -5

echo ""
log_info "Current running containers:"
docker-compose -f docker-compose.production.yml ps

echo ""

# ========================================
# Confirm Rollback
# ========================================
log_warn "⚠️  This will rollback all services to the previous version"
read -p "Are you sure you want to rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Rollback cancelled"
    exit 0
fi

# ========================================
# Stop Current Containers
# ========================================
log_step "Stopping Current Containers"

docker-compose -f docker-compose.production.yml down

log_info "✓ Containers stopped"

# ========================================
# Start Previous Version
# ========================================
log_step "Starting Previous Version"

# Use previous tag or latest-1
export VERSION="previous"

docker-compose -f docker-compose.production.yml up -d

log_info "Waiting for services to start (30 seconds)..."
sleep 30

# ========================================
# Verify Health
# ========================================
log_step "Verifying Service Health"

SERVICES=("gateway:8090" "auth:8091" "sales:8092" "inventory:8093" "finance:8094" "saas:8095")
ALL_HEALTHY=true

for SERVICE in "${SERVICES[@]}"; do
    IFS=':' read -r NAME PORT <<< "$SERVICE"

    if curl -f -s "http://localhost:$PORT/health" > /dev/null; then
        log_info "✓ $NAME is healthy"
    else
        log_error "✗ $NAME is unhealthy"
        ALL_HEALTHY=false
    fi
done

# ========================================
# Result
# ========================================
if [ "$ALL_HEALTHY" = true ]; then
    log_step "✅ Rollback Successful!"

    log_info "All services are running the previous version"
    log_info "Monitor logs: docker-compose -f docker-compose.production.yml logs -f"
else
    log_step "❌ Rollback Issues Detected"

    log_error "Some services are unhealthy after rollback"
    log_error "Check logs: docker-compose -f docker-compose.production.yml logs"
fi
