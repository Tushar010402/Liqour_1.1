#!/bin/bash
# =============================================================================
# LiquorPro Scheduler Verification Script
# Verifies that all scheduled jobs are running correctly
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1"; }

log "${BLUE}=== LiquorPro Scheduler Verification ===${NC}"
log "Timestamp: $(date)"
log ""

# =============================================================================
# 1. Service Health Check
# =============================================================================
log "${BLUE}--- 1. Service Health ---${NC}"

check_service() {
    local name=$1
    local port=$2
    local response=$(curl -s -w "%{http_code}" "http://localhost:$port/health" -o /dev/null 2>/dev/null)
    if [ "$response" = "200" ]; then
        log "${GREEN}[OK]${NC} $name (port $port) is healthy"
        return 0
    else
        log "${RED}[FAIL]${NC} $name (port $port) - HTTP $response"
        return 1
    fi
}

check_service "Gateway" 8090
check_service "Auth" 8091
check_service "Sales" 8092
check_service "Inventory" 8093
check_service "Finance" 8094
check_service "SaaS" 8095

log ""

# =============================================================================
# 2. Finance Container Logs (Schedulers)
# =============================================================================
log "${BLUE}--- 2. Scheduler Activity (last 5 minutes) ---${NC}"

# Get recent logs from finance container
FINANCE_LOGS=$(sudo docker logs liquorpro-finance-prod --since 5m 2>&1)

# Check for reminder scheduler
REMINDER_COUNT=$(echo "$FINANCE_LOGS" | grep -c "\[REMINDER\]" 2>/dev/null)
REMINDER_COUNT=${REMINDER_COUNT:-0}
if [ "$REMINDER_COUNT" -gt 0 ] 2>/dev/null; then
    log "${GREEN}[OK]${NC} Reminder Scheduler active ($REMINDER_COUNT entries)"
    echo "$FINANCE_LOGS" | grep "\[REMINDER\]" | tail -3 | while read line; do
        log "     $line"
    done
else
    log "${YELLOW}[WARN]${NC} No reminder scheduler activity in last 5 minutes"
fi

# Check for alarm scheduler
ALARM_COUNT=$(echo "$FINANCE_LOGS" | grep -c "\[ALARM\]" 2>/dev/null)
ALARM_COUNT=${ALARM_COUNT:-0}
if [ "$ALARM_COUNT" -gt 0 ] 2>/dev/null; then
    log "${GREEN}[OK]${NC} Alarm Scheduler active ($ALARM_COUNT entries)"
    echo "$FINANCE_LOGS" | grep "\[ALARM\]" | tail -3 | while read line; do
        log "     $line"
    done
else
    log "${YELLOW}[WARN]${NC} No alarm scheduler activity in last 5 minutes"
fi

# Check for digest scheduler
DIGEST_COUNT=$(echo "$FINANCE_LOGS" | grep -ci "digest" 2>/dev/null || echo "0")
DIGEST_COUNT=$(echo "$DIGEST_COUNT" | head -1 | xargs)
if [ -n "$DIGEST_COUNT" ] && [ "$DIGEST_COUNT" -gt "0" ] 2>/dev/null; then
    log "${GREEN}[OK]${NC} Digest Scheduler active ($DIGEST_COUNT entries)"
else
    log "${YELLOW}[INFO]${NC} No digest activity (runs hourly/daily)"
fi

# Check for cron/scheduler initialization
CRON_INIT=$(echo "$FINANCE_LOGS" | grep -i "scheduler.*start\|cron.*register\|job.*register" | head -3)
if [ -n "$CRON_INIT" ]; then
    log "${GREEN}[OK]${NC} Scheduler initialization detected"
fi

log ""

# =============================================================================
# 3. Database Activity Check
# =============================================================================
log "${BLUE}--- 3. Database Activity ---${NC}"

# Find postgres container
PG_CONTAINER=$(sudo docker ps --format '{{.Names}}' | grep -i postgres | head -1)
if [ -z "$PG_CONTAINER" ]; then
    log "${RED}[FAIL]${NC} PostgreSQL container not found"
else
    # Get DB credentials from .env.production
    if [ -f ".env.production" ]; then
        source .env.production 2>/dev/null
    fi

    DB_USER="${DATABASE_USER:-liquorpro_prod}"
    DB_NAME="${DATABASE_DBNAME:-liquorpro_production}"
    DB_PASS="${DATABASE_PASSWORD}"

    # Check recent notifications (with timeout)
    NOTIF_COUNT=$(timeout 5 bash -c "PGPASSWORD='$DB_PASS' psql -h localhost -p 5433 -U '$DB_USER' -d '$DB_NAME' -t -c \"SELECT COUNT(*) FROM notifications WHERE created_at > NOW() - INTERVAL '24 hours';\"" 2>/dev/null | xargs)
    if [ -n "$NOTIF_COUNT" ] && [ "$NOTIF_COUNT" != "" ] && [[ "$NOTIF_COUNT" =~ ^[0-9]+$ ]]; then
        log "${GREEN}[OK]${NC} Notifications (24h): $NOTIF_COUNT"
    else
        log "${YELLOW}[WARN]${NC} Could not query notifications"
    fi

    # Check alarm schedule runs (with timeout)
    ALARM_RUNS=$(timeout 5 bash -c "PGPASSWORD='$DB_PASS' psql -h localhost -p 5433 -U '$DB_USER' -d '$DB_NAME' -t -c \"SELECT COUNT(*) FROM alarm_schedule_runs WHERE scheduled_for > NOW() - INTERVAL '24 hours';\"" 2>/dev/null | xargs)
    if [ -n "$ALARM_RUNS" ] && [ "$ALARM_RUNS" != "" ] && [[ "$ALARM_RUNS" =~ ^[0-9]+$ ]]; then
        log "${GREEN}[OK]${NC} Alarm schedule runs (24h): $ALARM_RUNS"
    else
        log "${YELLOW}[WARN]${NC} Could not query alarm schedule runs"
    fi

    # Check recent alarm instances (with timeout)
    ALARM_INSTANCES=$(timeout 5 bash -c "PGPASSWORD='$DB_PASS' psql -h localhost -p 5433 -U '$DB_USER' -d '$DB_NAME' -t -c \"SELECT COUNT(*) FROM alarm_instances WHERE created_at > NOW() - INTERVAL '7 days';\"" 2>/dev/null | xargs)
    if [ -n "$ALARM_INSTANCES" ] && [ "$ALARM_INSTANCES" != "" ] && [[ "$ALARM_INSTANCES" =~ ^[0-9]+$ ]]; then
        log "${GREEN}[OK]${NC} Alarm instances (7d): $ALARM_INSTANCES"
    else
        log "${YELLOW}[WARN]${NC} Could not query alarm instances"
    fi

    # Check notification deliveries with push (with timeout)
    PUSH_DELIVERIES=$(timeout 5 bash -c "PGPASSWORD='$DB_PASS' psql -h localhost -p 5433 -U '$DB_USER' -d '$DB_NAME' -t -c \"SELECT COUNT(*) FROM notification_deliveries WHERE channel = 'push' AND delivered_at IS NOT NULL AND delivered_at > NOW() - INTERVAL '7 days';\"" 2>/dev/null | xargs)
    if [ -n "$PUSH_DELIVERIES" ] && [ "$PUSH_DELIVERIES" != "" ] && [[ "$PUSH_DELIVERIES" =~ ^[0-9]+$ ]]; then
        log "${GREEN}[OK]${NC} Push deliveries (7d): $PUSH_DELIVERIES"
    else
        log "${YELLOW}[WARN]${NC} Could not query push deliveries"
    fi
fi

log ""

# =============================================================================
# 4. Cron Job Definitions
# =============================================================================
log "${BLUE}--- 4. Registered Schedulers ---${NC}"

# Show what cron jobs are defined in the code
log "Alarm Scheduler Jobs (from code):"
log "  - 0 8 * * *    Low stock check"
log "  - 0 9 * * *    Settlement reminder"
log "  - 0 10 * * *   Expiring products check"
log "  - 0 11 * * *   Credit overdue check"
log "  - 0 */4 * * *  Cash shortage check (every 4 hours)"
log "  - 0 12 * * 1   Weekly inventory variance"
log "  - 0 8 * * 6    Slow moving inventory (Saturdays)"
log "  - 0 9 * * 1    Sales target reminder (Mondays)"
log "  - 0 10 1,15 * * Vendor payment reminder (1st & 15th)"
log "  - 0 14 * * *   Pending approval reminder"
log "  - 0 0 * * 0    Audit reminder (Sundays)"

log ""
log "Reminder Scheduler (from code):"
log "  - Every minute: Check user-configured reminders"
log "  - Types: daily_sales, low_stock, cash_collection, settlement, credit_overdue, audit"

log ""
log "Digest Scheduler (from code):"
log "  - @hourly: Process hourly digests"
log "  - @daily: Process daily digests"
log "  - @weekly: Process weekly digests"

log ""

# =============================================================================
# 5. Push Notification Capability
# =============================================================================
log "${BLUE}--- 5. Firebase/Push Configuration ---${NC}"

# Check if Firebase credentials are mounted
if sudo docker exec liquorpro-finance-prod ls /app/config/firebase/service-account.json >/dev/null 2>&1; then
    log "${GREEN}[OK]${NC} Firebase credentials mounted"
else
    log "${RED}[FAIL]${NC} Firebase credentials not found in container"
fi

# Check for Firebase initialization in logs
FIREBASE_INIT=$(sudo docker logs liquorpro-finance-prod 2>&1 | grep -i "firebase\|FCM" | tail -3)
if [ -n "$FIREBASE_INIT" ]; then
    log "${GREEN}[OK]${NC} Firebase initialization detected:"
    echo "$FIREBASE_INIT" | while read line; do
        log "     $line"
    done
fi

log ""

# =============================================================================
# Summary
# =============================================================================
log "${BLUE}=== Verification Complete ===${NC}"
log "Run this script periodically to ensure schedulers are operational."
log ""
log "To manually trigger alarm checks:"
log "  curl -X POST http://localhost:8090/api/alarms/admin/run-checks -H 'Authorization: Bearer <token>'"
log ""
log "To view real-time logs:"
log "  sudo docker logs -f liquorpro-finance-prod 2>&1 | grep -E 'REMINDER|ALARM|digest'"
