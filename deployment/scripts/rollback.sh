#!/bin/bash

# LiquorPro Rollback Script
# Rolls back to previous Docker image versions
# Usage: ./rollback.sh

set -e

# Configuration
PROJECT_DIR="/var/www/liquorpro"
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

log_step "LiquorPro Rollback Procedure"

cd "$PROJECT_DIR"

# Determine docker compose command
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# ========================================
# List Available Versions
# ========================================
log_step "Available Docker Image Versions"

SERVICES=("gateway" "auth" "sales" "inventory" "finance" "saas")

for svc in "${SERVICES[@]}"; do
    echo ""
    log_info "$svc versions:"
    docker images "liquorpro/$svc" --format "table {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" | head -5
done

echo ""
log_info "Current running containers:"
$DOCKER_COMPOSE -f docker-compose.production.yml ps

echo ""

# ========================================
# Select Version
# ========================================
echo ""
log_info "Available tags (from gateway as reference):"
docker images liquorpro/gateway --format "{{.Tag}}" | sort -r | head -10
echo ""
read -p "Enter version tag to rollback to (e.g., 'previous' or 'deploy-20260206-123456'): " TARGET_TAG

if [ -z "$TARGET_TAG" ]; then
    log_error "No tag specified. Aborting."
    exit 1
fi

# Verify the tag exists for all services
for svc in "${SERVICES[@]}"; do
    if ! docker image inspect "liquorpro/$svc:$TARGET_TAG" > /dev/null 2>&1; then
        log_error "Image liquorpro/$svc:$TARGET_TAG not found!"
        exit 1
    fi
done

log_info "All images found for tag: $TARGET_TAG"

# ========================================
# Confirm Rollback
# ========================================
log_warn "This will rollback all services to tag: $TARGET_TAG"
read -p "Are you sure you want to rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Rollback cancelled"
    exit 0
fi

# ========================================
# Retag and Restart
# ========================================
log_step "Retagging Images"

for svc in "${SERVICES[@]}"; do
    log_info "Tagging liquorpro/$svc:$TARGET_TAG as :latest"
    docker tag "liquorpro/$svc:$TARGET_TAG" "liquorpro/$svc:latest"
done

log_step "Restarting Services"

$DOCKER_COMPOSE -f docker-compose.production.yml --env-file .env.production up -d

log_info "Waiting for services to start (30 seconds)..."
sleep 30

# ========================================
# Verify Health
# ========================================
log_step "Verifying Service Health"

SERVICE_PORTS=("gateway:8090" "auth:8091" "sales:8092" "inventory:8093" "finance:8094" "saas:8095")
ALL_HEALTHY=true

for SERVICE in "${SERVICE_PORTS[@]}"; do
    IFS=':' read -r NAME PORT <<< "$SERVICE"

    if curl -f -s "http://localhost:$PORT/health" > /dev/null; then
        log_info "$NAME is healthy"
    else
        log_error "$NAME is unhealthy"
        ALL_HEALTHY=false
    fi
done

# ========================================
# Result
# ========================================
if [ "$ALL_HEALTHY" = true ]; then
    log_step "Rollback Successful!"
    log_info "All services are running tag: $TARGET_TAG"
    log_info "Monitor logs: $DOCKER_COMPOSE -f docker-compose.production.yml logs -f"
else
    log_step "Rollback Issues Detected"
    log_error "Some services are unhealthy after rollback"
    log_error "Check logs: $DOCKER_COMPOSE -f docker-compose.production.yml logs"
fi
