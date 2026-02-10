#!/bin/bash
# =============================================================================
# LiquorPro Industrial-Grade Health Monitor
# Continuous health checks with alerting capabilities
# =============================================================================

set -euo pipefail

# Configuration
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"
EMAIL_ALERT="${ALERT_EMAIL:-}"
CHECK_INTERVAL=60
LOG_FILE="/opt/liquorpro/logs/health-monitor.log"

# Services to monitor
declare -A SERVICES=(
    ["gateway"]="http://localhost:8090/health"
    ["auth"]="http://localhost:8091/health"
    ["sales"]="http://localhost:8092/health"
    ["inventory"]="http://localhost:8093/health"
    ["finance"]="http://localhost:8094/health"
    ["saas"]="http://localhost:8095/health"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

check_service() {
    local name=$1
    local url=$2
    local response
    local http_code

    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ $name${NC}"
        return 0
    else
        echo -e "${RED}❌ $name (HTTP $http_code)${NC}"
        return 1
    fi
}

check_container() {
    local name=$1
    local status

    status=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "not_found")

    case "$status" in
        "healthy")
            echo -e "${GREEN}✅ $name${NC}"
            return 0
            ;;
        "unhealthy")
            echo -e "${RED}❌ $name (unhealthy)${NC}"
            return 1
            ;;
        "starting")
            echo -e "${YELLOW}⏳ $name (starting)${NC}"
            return 0
            ;;
        *)
            echo -e "${RED}❌ $name ($status)${NC}"
            return 1
            ;;
    esac
}

check_database() {
    local result
    result=$(docker exec liquorpro-postgres-prod pg_isready -U liquorpro_prod -d liquorpro_production 2>/dev/null)

    if [[ "$result" == *"accepting connections"* ]]; then
        echo -e "${GREEN}✅ PostgreSQL${NC}"
        return 0
    else
        echo -e "${RED}❌ PostgreSQL${NC}"
        return 1
    fi
}

check_redis() {
    local result
    local redis_pass
    redis_pass=$(grep "^REDIS_PASSWORD=" /var/www/liquorpro/.env.production 2>/dev/null | cut -d= -f2)
    result=$(docker exec liquorpro-redis-prod redis-cli -a "$redis_pass" ping 2>/dev/null | grep -v Warning || echo "failed")

    if [ "$result" = "PONG" ]; then
        echo -e "${GREEN}✅ Redis${NC}"
        return 0
    else
        echo -e "${RED}❌ Redis${NC}"
        return 1
    fi
}

check_disk() {
    local usage
    usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$usage" -lt 80 ]; then
        echo -e "${GREEN}✅ Disk: ${usage}%${NC}"
        return 0
    elif [ "$usage" -lt 90 ]; then
        echo -e "${YELLOW}⚠️  Disk: ${usage}%${NC}"
        return 0
    else
        echo -e "${RED}❌ Disk: ${usage}% (CRITICAL)${NC}"
        return 1
    fi
}

check_memory() {
    local usage
    usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

    if [ "$usage" -lt 80 ]; then
        echo -e "${GREEN}✅ Memory: ${usage}%${NC}"
        return 0
    elif [ "$usage" -lt 90 ]; then
        echo -e "${YELLOW}⚠️  Memory: ${usage}%${NC}"
        return 0
    else
        echo -e "${RED}❌ Memory: ${usage}% (CRITICAL)${NC}"
        return 1
    fi
}

send_alert() {
    local message=$1

    # Slack alert
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 LiquorPro Alert: $message\"}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
    fi

    # Email alert (if configured)
    if [ -n "$EMAIL_ALERT" ] && command -v mail &>/dev/null; then
        echo "$message" | mail -s "🚨 LiquorPro Alert" "$EMAIL_ALERT" 2>/dev/null || true
    fi

    log "ALERT: $message"
}

run_checks() {
    local failed=0

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   LiquorPro Health Check - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${YELLOW}Infrastructure:${NC}"
    check_disk || ((failed++))
    check_memory || ((failed++))
    echo ""

    echo -e "${YELLOW}Database & Cache:${NC}"
    check_database || ((failed++))
    check_redis || ((failed++))
    echo ""

    echo -e "${YELLOW}Containers:${NC}"
    check_container "liquorpro-postgres-prod" || ((failed++))
    check_container "liquorpro-redis-prod" || ((failed++))
    check_container "liquorpro-gateway-prod" || ((failed++))
    check_container "liquorpro-auth-prod" || ((failed++))
    check_container "liquorpro-sales-prod" || ((failed++))
    check_container "liquorpro-inventory-prod" || ((failed++))
    check_container "liquorpro-finance-prod" || ((failed++))
    check_container "liquorpro-saas-prod" || ((failed++))
    echo ""

    echo -e "${YELLOW}API Endpoints:${NC}"
    for service in "${!SERVICES[@]}"; do
        check_service "$service" "${SERVICES[$service]}" || ((failed++))
    done
    echo ""

    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}   All systems operational ✅${NC}"
    else
        echo -e "${RED}   $failed check(s) failed ❌${NC}"
        send_alert "$failed health check(s) failed"
    fi
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo ""

    return $failed
}

# Main
mkdir -p "$(dirname "$LOG_FILE")"

case "${1:-check}" in
    check)
        run_checks
        ;;
    watch)
        log "Starting continuous health monitoring (interval: ${CHECK_INTERVAL}s)"
        while true; do
            run_checks
            sleep $CHECK_INTERVAL
        done
        ;;
    *)
        echo "Usage: $0 {check|watch}"
        exit 1
        ;;
esac
