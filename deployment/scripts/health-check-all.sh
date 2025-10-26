#!/bin/bash

# LiquorPro Comprehensive Health Check Script
# Tests all services, database, cache, and infrastructure
# Usage: ./health-check-all.sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

log_pass() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_skip() {
    echo -e "${YELLOW}[⊘ SKIP]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# ========================================
# Header
# ========================================
echo ""
log_section "🏥 LiquorPro Production Health Check"
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ========================================
# Docker Status
# ========================================
log_section "Docker Infrastructure"

if docker info > /dev/null 2>&1; then
    log_pass "Docker daemon is running"
else
    log_fail "Docker daemon is not running"
fi

if docker-compose --version > /dev/null 2>&1; then
    log_pass "Docker Compose is installed"
else
    log_fail "Docker Compose is not installed"
fi

# ========================================
# Database Services
# ========================================
log_section "Database Services"

# PostgreSQL
if docker ps | grep -q "liquorpro-postgres-prod.*Up"; then
    log_pass "PostgreSQL container is running"

    if docker exec liquorpro-postgres-prod pg_isready -U liquorpro_prod -d liquorpro_production > /dev/null 2>&1; then
        log_pass "PostgreSQL is accepting connections"
    else
        log_fail "PostgreSQL is not accepting connections"
    fi
else
    log_fail "PostgreSQL container is not running"
fi

# Redis
if docker ps | grep -q "liquorpro-redis-prod.*Up"; then
    log_pass "Redis container is running"

    if docker exec liquorpro-redis-prod redis-cli ping > /dev/null 2>&1; then
        log_pass "Redis is responding to ping"
    else
        log_fail "Redis is not responding"
    fi
else
    log_fail "Redis container is not running"
fi

# ========================================
# Microservices
# ========================================
log_section "Microservices Health"

# Array of services
declare -A SERVICES=(
    ["Gateway"]="8090"
    ["Auth"]="8091"
    ["Sales"]="8092"
    ["Inventory"]="8093"
    ["Finance"]="8094"
    ["Frontend"]="8095"
)

for SERVICE in "${!SERVICES[@]}"; do
    PORT="${SERVICES[$SERVICE]}"
    CONTAINER="liquorpro-${SERVICE,,}-prod"

    # Check if container is running
    if docker ps | grep -q "$CONTAINER.*Up"; then
        log_pass "$SERVICE container is running"

        # Check health endpoint
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/health" 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
            log_pass "$SERVICE health endpoint is OK (HTTP $HTTP_CODE)"
        else
            log_fail "$SERVICE health endpoint failed (HTTP $HTTP_CODE)"
        fi
    else
        log_fail "$SERVICE container is not running"
    fi
done

# ========================================
# Network Connectivity
# ========================================
log_section "Network Connectivity"

# Check if Nginx is running
if systemctl is-active --quiet nginx; then
    log_pass "Nginx is running"

    # Check if Nginx config is valid
    if sudo nginx -t > /dev/null 2>&1; then
        log_pass "Nginx configuration is valid"
    else
        log_fail "Nginx configuration has errors"
    fi
else
    log_fail "Nginx is not running"
fi

# Check external HTTPS access
if curl -f -s -k "https://localhost" > /dev/null 2>&1; then
    log_pass "HTTPS endpoint is accessible"
else
    log_skip "HTTPS endpoint check (might not be configured yet)"
fi

# ========================================
# Disk Space
# ========================================
log_section "System Resources"

# Check root partition disk space
ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$ROOT_USAGE" -lt 80 ]; then
    log_pass "Root partition disk usage: ${ROOT_USAGE}%"
else
    log_fail "Root partition disk usage critical: ${ROOT_USAGE}%"
fi

# Check /opt/liquorpro disk space
if [ -d "/opt/liquorpro" ]; then
    LIQUORPRO_SIZE=$(du -sh /opt/liquorpro 2>/dev/null | cut -f1)
    log_pass "LiquorPro directory size: $LIQUORPRO_SIZE"
fi

# ========================================
# Memory Usage
# ========================================
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
if [ "$MEMORY_USAGE" -lt 85 ]; then
    log_pass "Memory usage: ${MEMORY_USAGE}%"
else
    log_fail "Memory usage critical: ${MEMORY_USAGE}%"
fi

# ========================================
# Docker Container Stats
# ========================================
log_section "Docker Container Resources"

echo ""
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# ========================================
# SSL Certificate Status
# ========================================
log_section "SSL Certificate"

if [ -d "/etc/letsencrypt/live" ]; then
    CERT_DOMAINS=$(sudo ls /etc/letsencrypt/live/ 2>/dev/null | grep -v README)

    if [ -n "$CERT_DOMAINS" ]; then
        for DOMAIN in $CERT_DOMAINS; do
            CERT_FILE="/etc/letsencrypt/live/$DOMAIN/cert.pem"
            if [ -f "$CERT_FILE" ]; then
                EXPIRY_DATE=$(sudo openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
                EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
                CURRENT_EPOCH=$(date +%s)
                DAYS_REMAINING=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

                if [ "$DAYS_REMAINING" -gt 7 ]; then
                    log_pass "SSL certificate for $DOMAIN: $DAYS_REMAINING days remaining"
                else
                    log_fail "SSL certificate for $DOMAIN expires in $DAYS_REMAINING days"
                fi
            fi
        done
    else
        log_skip "No SSL certificates found"
    fi
else
    log_skip "Let's Encrypt not configured"
fi

# ========================================
# Firewall Status
# ========================================
log_section "Security"

if sudo ufw status | grep -q "Status: active"; then
    log_pass "Firewall (UFW) is active"
else
    log_fail "Firewall (UFW) is not active"
fi

if systemctl is-active --quiet fail2ban; then
    log_pass "Fail2ban is running"
else
    log_fail "Fail2ban is not running"
fi

# ========================================
# Backup Status
# ========================================
log_section "Backup Status"

BACKUP_DIR="/opt/liquorpro/backups/postgres"
if [ -d "$BACKUP_DIR" ]; then
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)

    if [ -n "$LATEST_BACKUP" ]; then
        BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 86400 ))
        BACKUP_SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)

        if [ "$BACKUP_AGE" -lt 2 ]; then
            log_pass "Latest backup: $(basename $LATEST_BACKUP) ($BACKUP_SIZE, $BACKUP_AGE days old)"
        else
            log_fail "Latest backup is $BACKUP_AGE days old (should be < 2 days)"
        fi
    else
        log_fail "No backups found"
    fi
else
    log_skip "Backup directory not found"
fi

# ========================================
# Summary
# ========================================
log_section "Health Check Summary"

PASS_RATE=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))

echo ""
echo "Total Checks: $TOTAL_CHECKS"
echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
echo "Pass Rate: $PASS_RATE%"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
    echo -e "${GREEN}✅ System Status: HEALTHY${NC}"
    EXIT_CODE=0
elif [ "$FAILED_CHECKS" -le 2 ]; then
    echo -e "${YELLOW}⚠️  System Status: DEGRADED${NC}"
    EXIT_CODE=1
else
    echo -e "${RED}❌ System Status: CRITICAL${NC}"
    EXIT_CODE=2
fi

echo ""

exit $EXIT_CODE
