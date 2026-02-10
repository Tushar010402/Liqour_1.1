#!/bin/bash
set -e

# ============================================================================
# LiquorPro Production Deployment Script
# Automated deployment with database migrations, health checks, and rollback
# ============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
MODE="${1:-production}"
SKIP_BACKUP="${2:-false}"

echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   █████   ███   █████████  █████  █████  ███████  ████████   ║
║  ▓▓▓▓▓   ▓▓▓   ▓▓▓▓▓▓▓▓▓ ▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓▓▓ ▓▓▓▓▓▓▓▓    ║
║  ▓▓▓▓▓   ▓▓▓   ▓▓▓   ▓▓▓ ▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓  ▓▓  ▓▓▓  ▓▓▓   ║
║  ▓▓▓▓▓   ▓▓▓   ▓▓▓▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓▓▓  ▓▓▓▓▓▓▓▓    ║
║  ▓▓▓▓▓   ▓▓▓   ▓▓▓       ▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓  ▓▓  ▓▓▓  ▓▓▓   ║
║  ▓▓▓▓▓▓▓▓▓▓▓   ▓▓▓       ▓▓▓▓▓▓▓▓▓▓▓▓  ▓▓▓▓▓▓▓  ▓▓▓   ▓▓▓  ║
║                                                               ║
║            PRODUCTION DEPLOYMENT SYSTEM v1.0                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Deployment Mode: ${GREEN}$MODE${NC}"
echo -e "${CYAN}Time: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Pre-flight Checks
# ============================================================================

echo -e "${BLUE}[1/8] Running pre-flight checks...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi
echo -e "${GREEN}   ✅ Docker is running${NC}"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo -e "${RED}❌ docker-compose not found. Please install docker-compose.${NC}"
    exit 1
fi
echo -e "${GREEN}   ✅ docker-compose is available${NC}"

# Determine docker-compose command
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Check if .env.production exists
if [ ! -f ".env.production" ]; then
    echo -e "${YELLOW}⚠️  .env.production not found${NC}"
    if [ -f ".env.production.example" ]; then
        echo -e "${YELLOW}   Creating .env.production from template...${NC}"
        cp .env.production.example .env.production
        echo -e "${RED}   ⚠️  CRITICAL: Edit .env.production and update passwords before deploying!${NC}"
        echo -e "${RED}   Exiting for security. Edit .env.production and run again.${NC}"
        exit 1
    else
        echo -e "${RED}❌ .env.production.example not found. Cannot continue.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}   ✅ Environment configuration found${NC}"

# Source database credentials from .env.production
DB_USER=$(grep '^DATABASE_USER=' .env.production | cut -d= -f2)
DB_NAME=$(grep '^DATABASE_NAME=' .env.production | cut -d= -f2)

# Check disk space (need at least 10GB free)
FREE_SPACE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$FREE_SPACE" -lt 10 ]; then
    echo -e "${YELLOW}⚠️  Warning: Low disk space (${FREE_SPACE}GB free). Recommended: 10GB+${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}   ✅ Sufficient disk space (${FREE_SPACE}GB free)${NC}"
fi

echo ""

# ============================================================================
# Backup Existing Database (if exists)
# ============================================================================

if [ "$SKIP_BACKUP" != "true" ]; then
    echo -e "${BLUE}[2/8] Creating database backup...${NC}"

    if $DOCKER_COMPOSE -f docker-compose.production.yml ps | grep -q liquorpro-postgres-prod; then
        BACKUP_DIR="./backups"
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql.gz"

        echo -e "${YELLOW}   Creating backup at: $BACKUP_FILE${NC}"

        if $DOCKER_COMPOSE -f docker-compose.production.yml exec -T postgres pg_dump -U "$DB_USER" "$DB_NAME" 2>/dev/null | gzip > "$BACKUP_FILE"; then
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            echo -e "${GREEN}   ✅ Backup created successfully ($BACKUP_SIZE)${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Could not create backup (database may not be initialized yet)${NC}"
        fi
    else
        echo -e "${YELLOW}   ⏭️  No existing database to backup${NC}"
    fi
else
    echo -e "${BLUE}[2/8] Skipping database backup...${NC}"
fi

echo ""

# ============================================================================
# Stop Existing Services
# ============================================================================

echo -e "${BLUE}[3/8] Stopping existing services...${NC}"

if $DOCKER_COMPOSE -f docker-compose.production.yml ps | grep -q "liquorpro"; then
    echo -e "${YELLOW}   Stopping running containers...${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml down
    echo -e "${GREEN}   ✅ Services stopped${NC}"
else
    echo -e "${YELLOW}   ⏭️  No running services to stop${NC}"
fi

echo ""

# ============================================================================
# Build Docker Images
# ============================================================================

echo -e "${BLUE}[4/8] Building Docker images...${NC}"

export BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
export VERSION=${VERSION:-1.0.0}
export GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo -e "${CYAN}   Build metadata:${NC}"
echo -e "${CYAN}   - Version: ${GREEN}$VERSION${NC}"
echo -e "${CYAN}   - Build Date: ${GREEN}$BUILD_DATE${NC}"
echo -e "${CYAN}   - Git Commit: ${GREEN}$GIT_COMMIT${NC}"
echo ""

# Tag current images as :previous for rollback
echo -e "${YELLOW}   Tagging current images as :previous...${NC}"
for svc in gateway auth sales inventory finance saas migrations; do
    if docker image inspect "liquorpro/$svc:${VERSION:-latest}" > /dev/null 2>&1; then
        docker tag "liquorpro/$svc:${VERSION:-latest}" "liquorpro/$svc:previous" 2>/dev/null || true
    fi
done

DEPLOY_TAG="deploy-$(date +%Y%m%d-%H%M%S)"
BUILD_FLAGS=""
if [ "${NO_CACHE:-false}" = "true" ]; then
    BUILD_FLAGS="--no-cache"
fi

if $DOCKER_COMPOSE -f docker-compose.production.yml build $BUILD_FLAGS; then
    echo -e "${GREEN}   ✅ All images built successfully${NC}"
    # Tag new images with deploy timestamp
    for svc in gateway auth sales inventory finance saas migrations; do
        docker tag "liquorpro/$svc:${VERSION:-latest}" "liquorpro/$svc:$DEPLOY_TAG" 2>/dev/null || true
    done
    echo -e "${CYAN}   Tagged as: $DEPLOY_TAG${NC}"
else
    echo -e "${RED}❌ Image build failed${NC}"
    exit 1
fi

echo ""

# ============================================================================
# Start Infrastructure Services
# ============================================================================

echo -e "${BLUE}[5/8] Starting infrastructure services...${NC}"

# Start PostgreSQL and Redis first
$DOCKER_COMPOSE -f docker-compose.production.yml up -d postgres redis

echo -e "${YELLOW}   Waiting for PostgreSQL to be ready...${NC}"
ATTEMPTS=0
MAX_ATTEMPTS=60
until $DOCKER_COMPOSE -f docker-compose.production.yml exec -T postgres pg_isready -U "$DB_USER" > /dev/null 2>&1 || [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS + 1))
    printf "${YELLOW}   ."
    sleep 2
done
echo ""

if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}❌ PostgreSQL failed to start${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml logs postgres
    exit 1
fi

echo -e "${GREEN}   ✅ PostgreSQL is ready${NC}"

echo -e "${YELLOW}   Waiting for Redis to be ready...${NC}"
ATTEMPTS=0
until $DOCKER_COMPOSE -f docker-compose.production.yml exec -T redis redis-cli ping 2>/dev/null | grep -q PONG || [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS + 1))
    printf "${YELLOW}   ."
    sleep 2
done
echo ""

if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}❌ Redis failed to start${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml logs redis
    exit 1
fi

echo -e "${GREEN}   ✅ Redis is ready${NC}"

echo ""

# ============================================================================
# Run Database Migrations
# ============================================================================

echo -e "${BLUE}[6/8] Running database migrations...${NC}"

# Start migration container
if $DOCKER_COMPOSE -f docker-compose.production.yml up --abort-on-container-exit migrations; then
    echo -e "${GREEN}   ✅ Migrations completed successfully${NC}"

    # Show migration status
    echo -e "${CYAN}   Current schema version:${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT version, name, applied_at FROM schema_migrations WHERE success = true ORDER BY applied_at DESC LIMIT 5;" 2>/dev/null || true
else
    echo -e "${RED}❌ Migration failed${NC}"
    echo -e "${RED}   Checking migration logs:${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml logs migrations

    echo -e "${RED}   Rolling back...${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml down
    exit 1
fi

echo ""

# ============================================================================
# Start Application Services
# ============================================================================

echo -e "${BLUE}[7/8] Starting application services...${NC}"

# Start all services
if $DOCKER_COMPOSE -f docker-compose.production.yml up -d gateway auth sales inventory finance saas; then
    echo -e "${GREEN}   ✅ All services started${NC}"
else
    echo -e "${RED}❌ Failed to start services${NC}"
    exit 1
fi

# Wait for services to be healthy
echo -e "${YELLOW}   Waiting for services to be healthy (this may take up to 60 seconds)...${NC}"
sleep 10

SERVICES=("gateway:8090" "auth:8091" "sales:8092" "inventory:8093" "finance:8094" "saas:8095")
ALL_HEALTHY=true

for SERVICE in "${SERVICES[@]}"; do
    IFS=':' read -r NAME PORT <<< "$SERVICE"

    ATTEMPTS=0
    MAX_ATTEMPTS=30
    HEALTHY=false

    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if curl -sf http://localhost:$PORT/health > /dev/null 2>&1; then
            echo -e "${GREEN}   ✅ $NAME is healthy (port $PORT)${NC}"
            HEALTHY=true
            break
        fi
        ATTEMPTS=$((ATTEMPTS + 1))
        sleep 2
    done

    if [ "$HEALTHY" = false ]; then
        echo -e "${RED}   ❌ $NAME health check failed (port $PORT)${NC}"
        ALL_HEALTHY=false
    fi
done

echo ""

# ============================================================================
# Deployment Summary
# ============================================================================

echo -e "${BLUE}[8/8] Deployment Summary${NC}"
echo ""

if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║           ✅  DEPLOYMENT SUCCESSFUL  ✅                     ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}Service Status:${NC}"
    $DOCKER_COMPOSE -f docker-compose.production.yml ps
    echo ""

    echo -e "${CYAN}API Endpoints:${NC}"
    echo -e "${GREEN}   Gateway:    http://localhost:8090/health${NC}"
    echo -e "${GREEN}   Auth:       http://localhost:8091/health${NC}"
    echo -e "${GREEN}   Sales:      http://localhost:8092/health${NC}"
    echo -e "${GREEN}   Inventory:  http://localhost:8093/health${NC}"
    echo -e "${GREEN}   Finance:    http://localhost:8094/health${NC}"
    echo -e "${GREEN}   SaaS:       http://localhost:8095/health${NC}"
    echo ""

    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "   View logs:       ${YELLOW}$DOCKER_COMPOSE -f docker-compose.production.yml logs -f${NC}"
    echo -e "   Stop services:   ${YELLOW}$DOCKER_COMPOSE -f docker-compose.production.yml down${NC}"
    echo -e "   Restart service: ${YELLOW}$DOCKER_COMPOSE -f docker-compose.production.yml restart <service>${NC}"
    echo ""

    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}║        ⚠️   DEPLOYMENT COMPLETED WITH WARNINGS  ⚠️         ║${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}Some services failed health checks. Check logs:${NC}"
    echo -e "${YELLOW}   $DOCKER_COMPOSE -f docker-compose.production.yml logs${NC}"
    echo ""

    exit 1
fi
