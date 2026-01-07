#!/bin/bash
set -e

# ============================================================================
# LiquorPro Remote Server Deployment Script
# Deploys to: tushar@72.60.96.174:2222
# ============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Server configuration
SERVER_HOST="72.60.96.174"
SERVER_USER="tushar"
SERVER_PORT="2222"
SERVER_PATH="/opt/liquorpro"

echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        LIQUORPRO REMOTE DEPLOYMENT TO PRODUCTION              ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}Target Server: ${GREEN}$SERVER_USER@$SERVER_HOST:$SERVER_PORT${NC}"
echo -e "${CYAN}Deployment Path: ${GREEN}$SERVER_PATH${NC}"
echo -e "${CYAN}Time: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# ============================================================================
# Pre-flight Checks
# ============================================================================

echo -e "${BLUE}[1/6] Running pre-flight checks...${NC}"

# Check if .env.production exists
if [ ! -f ".env.production" ]; then
    echo -e "${RED}❌ .env.production not found${NC}"
    echo -e "${YELLOW}Run this first: cp .env.production.example .env.production${NC}"
    exit 1
fi
echo -e "${GREEN}   ✅ Environment configuration found${NC}"

# Test SSH connection
echo -e "${YELLOW}   Testing SSH connection...${NC}"
if ssh -p $SERVER_PORT -o ConnectTimeout=10 -o BatchMode=yes $SERVER_USER@$SERVER_HOST exit 2>/dev/null; then
    echo -e "${GREEN}   ✅ SSH connection successful${NC}"
else
    echo -e "${RED}❌ Cannot connect to server${NC}"
    echo -e "${YELLOW}Please ensure:${NC}"
    echo -e "${YELLOW}  - You can SSH: ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST${NC}"
    echo -e "${YELLOW}  - SSH key is added or use password${NC}"
    exit 1
fi

# Check if Docker is installed on server
echo -e "${YELLOW}   Checking Docker on server...${NC}"
if ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "docker --version" > /dev/null 2>&1; then
    DOCKER_VERSION=$(ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "docker --version")
    echo -e "${GREEN}   ✅ Docker installed: $DOCKER_VERSION${NC}"
else
    echo -e "${RED}❌ Docker not found on server${NC}"
    echo -e "${YELLOW}Install Docker on server first:${NC}"
    echo -e "${YELLOW}  curl -fsSL https://get.docker.com | sh${NC}"
    exit 1
fi

echo ""

# ============================================================================
# Create Deployment Package
# ============================================================================

echo -e "${BLUE}[2/6] Creating deployment package...${NC}"

TEMP_DIR=$(mktemp -d)
PACKAGE_NAME="liquorpro-deploy-$(date +%Y%m%d_%H%M%S).tar.gz"

echo -e "${YELLOW}   Packaging files...${NC}"

# Create tarball with necessary files
tar -czf "$TEMP_DIR/$PACKAGE_NAME" \
    --exclude='*.md' \
    --exclude='docs/' \
    --exclude='liquor_pro_app/' \
    --exclude='SaaS_Admin_Flutter_App/' \
    --exclude='.git/' \
    --exclude='bin/' \
    --exclude='*.log' \
    --exclude='backups/' \
    .env.production \
    docker-compose.production.yml \
    deploy.sh \
    Dockerfile.* \
    .dockerignore \
    cmd/ \
    internal/ \
    pkg/ \
    migrations/ \
    go.mod \
    go.sum \
    config/ \
    credentials/README.md 2>/dev/null || true

PACKAGE_SIZE=$(du -h "$TEMP_DIR/$PACKAGE_NAME" | cut -f1)
echo -e "${GREEN}   ✅ Package created: $PACKAGE_SIZE${NC}"

echo ""

# ============================================================================
# Transfer to Server
# ============================================================================

echo -e "${BLUE}[3/6] Transferring to server...${NC}"

echo -e "${YELLOW}   Uploading deployment package...${NC}"

# Create directory on server
ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "sudo mkdir -p $SERVER_PATH && sudo chown $SERVER_USER:$SERVER_USER $SERVER_PATH"

# Transfer package
if scp -P $SERVER_PORT "$TEMP_DIR/$PACKAGE_NAME" $SERVER_USER@$SERVER_HOST:$SERVER_PATH/; then
    echo -e "${GREEN}   ✅ Upload complete${NC}"
else
    echo -e "${RED}❌ Upload failed${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup temp directory
rm -rf "$TEMP_DIR"

echo ""

# ============================================================================
# Extract and Prepare on Server
# ============================================================================

echo -e "${BLUE}[4/6] Preparing deployment on server...${NC}"

ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST << 'ENDSSH'
    cd /opt/liquorpro

    # Extract package
    echo "   Extracting files..."
    tar -xzf liquorpro-deploy-*.tar.gz

    # Make scripts executable
    chmod +x deploy.sh
    chmod +x migrations/run_migrations.sh

    # Create necessary directories
    mkdir -p backups
    mkdir -p credentials

    echo "   ✅ Files extracted and prepared"
ENDSSH

echo -e "${GREEN}   ✅ Server preparation complete${NC}"

echo ""

# ============================================================================
# Deploy on Server
# ============================================================================

echo -e "${BLUE}[5/6] Running deployment on server...${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# Run deployment script on server
ssh -p $SERVER_PORT -t $SERVER_USER@$SERVER_HOST << 'ENDSSH'
    cd /opt/liquorpro

    # Run deployment
    sudo ./deploy.sh production
ENDSSH

DEPLOY_STATUS=$?

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo -e "${GREEN}   ✅ Deployment on server completed successfully${NC}"
else
    echo -e "${RED}❌ Deployment on server failed${NC}"
    exit 1
fi

echo ""

# ============================================================================
# Verify Deployment
# ============================================================================

echo -e "${BLUE}[6/6] Verifying deployment...${NC}"

SERVICES=("8090:Gateway" "8091:Auth" "8092:Sales" "8093:Inventory" "8094:Finance" "8095:SaaS")

echo -e "${YELLOW}   Testing service endpoints...${NC}"

ALL_HEALTHY=true
for SERVICE in "${SERVICES[@]}"; do
    IFS=':' read -r PORT NAME <<< "$SERVICE"

    if ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST "curl -sf http://localhost:$PORT/health > /dev/null 2>&1"; then
        echo -e "${GREEN}   ✅ $NAME (port $PORT) is healthy${NC}"
    else
        echo -e "${RED}   ❌ $NAME (port $PORT) health check failed${NC}"
        ALL_HEALTHY=false
    fi
done

echo ""

# ============================================================================
# Deployment Summary
# ============================================================================

if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║     🎉  PRODUCTION DEPLOYMENT SUCCESSFUL  🎉               ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}🌐 Your Backend is Live!${NC}"
    echo ""
    echo -e "${CYAN}API Endpoints:${NC}"
    echo -e "${GREEN}   Gateway:    http://$SERVER_HOST:8090/health${NC}"
    echo -e "${GREEN}   Auth:       http://$SERVER_HOST:8091/health${NC}"
    echo -e "${GREEN}   Sales:      http://$SERVER_HOST:8092/health${NC}"
    echo -e "${GREEN}   Inventory:  http://$SERVER_HOST:8093/health${NC}"
    echo -e "${GREEN}   Finance:    http://$SERVER_HOST:8094/health${NC}"
    echo -e "${GREEN}   SaaS:       http://$SERVER_HOST:8095/health${NC}"
    echo ""

    echo -e "${CYAN}Database Migrations:${NC}"
    ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST \
        "docker exec liquorpro-postgres-prod psql -U liquorpro -d liquorpro -c 'SELECT COUNT(*) as total_migrations FROM schema_migrations WHERE success = true;'" 2>/dev/null || true
    echo ""

    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "   1. Update your Flutter app API endpoint to: ${GREEN}http://$SERVER_HOST:8090${NC}"
    echo -e "   2. Test authentication flow"
    echo -e "   3. Set up SSL/TLS with nginx"
    echo -e "   4. Configure firewall rules"
    echo ""

    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "   SSH to server:   ${YELLOW}ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST${NC}"
    echo -e "   View logs:       ${YELLOW}docker-compose -f docker-compose.production.yml logs -f${NC}"
    echo -e "   Restart service: ${YELLOW}docker-compose -f docker-compose.production.yml restart <service>${NC}"
    echo ""

    exit 0
else
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║   ⚠️  DEPLOYMENT COMPLETED WITH WARNINGS  ⚠️              ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}Some services may need attention. SSH to server:${NC}"
    echo -e "${YELLOW}   ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST${NC}"
    echo -e "${YELLOW}   cd /opt/liquorpro${NC}"
    echo -e "${YELLOW}   docker-compose -f docker-compose.production.yml logs${NC}"
    echo ""

    exit 1
fi
