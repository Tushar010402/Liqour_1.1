#!/bin/bash
# =============================================================================
# LiquorPro Production Manager
# Industrial-grade production management for all operations
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.production.yml"
ENV_FILE="$PROJECT_ROOT/.env.production"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $1"; }
log_error() { echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"; }

dc() {
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

show_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       🍾 LiquorPro Production Manager                      ║${NC}"
    echo -e "${CYAN}║       Industrial-Grade Production Operations               ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

cmd_start() {
    log "Starting all services..."
    dc up -d
    log_success "All services started"
    sleep 5
    cmd_status
}

cmd_stop() {
    log "Stopping all services..."
    dc down
    log_success "All services stopped"
}

cmd_restart() {
    local service=${1:-}
    if [ -n "$service" ]; then
        log "Restarting $service..."
        dc restart "$service"
        log_success "$service restarted"
    else
        log "Restarting all services..."
        dc restart
        log_success "All services restarted"
    fi
}

cmd_status() {
    echo ""
    echo -e "${YELLOW}Container Status:${NC}"
    dc ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

cmd_logs() {
    local service=${1:-}
    local lines=${2:-100}
    if [ -n "$service" ]; then
        dc logs -f --tail "$lines" "$service"
    else
        dc logs -f --tail "$lines"
    fi
}

cmd_health() {
    "$SCRIPT_DIR/health-monitor.sh" check
}

cmd_backup() {
    "$SCRIPT_DIR/backup-production.sh"
}

cmd_restore() {
    local backup_file=${1:-}
    if [ -z "$backup_file" ]; then
        echo "Available backups:"
        ls -la /opt/liquorpro/backups/daily/*.sql.gz 2>/dev/null | tail -10
        echo ""
        log_error "Usage: $0 restore <backup_file.sql.gz>"
        exit 1
    fi

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi

    log_warning "This will REPLACE the current database!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log "Restore cancelled"
        exit 0
    fi

    log "Creating safety backup before restore..."
    cmd_backup

    log "Restoring from $backup_file..."
    gunzip -c "$backup_file" | docker exec -i liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production
    log_success "Database restored successfully"
}

cmd_shell() {
    local service=${1:-sales}
    log "Opening shell in $service..."
    docker exec -it "liquorpro-${service}-prod" /bin/sh
}

cmd_db() {
    log "Opening PostgreSQL shell..."
    docker exec -it liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production
}

cmd_redis() {
    log "Opening Redis CLI..."
    docker exec -it liquorpro-redis-prod redis-cli
}

cmd_update() {
    log "Pulling latest images..."
    dc pull

    log "Recreating containers..."
    dc up -d --force-recreate

    log_success "Update completed"
    cmd_status
}

cmd_rebuild() {
    local service=${1:-}
    if [ -n "$service" ]; then
        log "Rebuilding $service..."
        dc build --no-cache "$service"
        dc up -d --force-recreate "$service"
    else
        log "Rebuilding all services..."
        dc build --no-cache
        dc up -d --force-recreate
    fi
    log_success "Rebuild completed"
}

cmd_cleanup() {
    log "Cleaning up Docker resources..."
    docker system prune -f
    docker volume prune -f
    log_success "Cleanup completed"
}

cmd_stats() {
    echo ""
    echo -e "${YELLOW}Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | grep liquorpro
    echo ""

    echo -e "${YELLOW}Database Stats:${NC}"
    docker exec liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production -c "
        SELECT
            'Tables' as metric, COUNT(*)::text as value FROM information_schema.tables WHERE table_schema = 'public'
        UNION ALL
        SELECT 'Products', COUNT(*)::text FROM products
        UNION ALL
        SELECT 'Users', COUNT(*)::text FROM users
        UNION ALL
        SELECT 'Shops', COUNT(*)::text FROM shops
        UNION ALL
        SELECT 'Tenants', COUNT(*)::text FROM tenants
        UNION ALL
        SELECT 'Sales', COUNT(*)::text FROM daily_sales
        UNION ALL
        SELECT 'DB Size', pg_size_pretty(pg_database_size('liquorpro_production'));
    " 2>/dev/null || log_warning "Could not fetch database stats"
    echo ""
}

cmd_test_ocr() {
    log "Testing Smart Sale OCR configuration..."

    echo ""
    echo -e "${YELLOW}OCR API Keys Status:${NC}"
    docker exec liquorpro-sales-prod env | grep -E "OPENAI|GEMINI|FOMOA" | while read line; do
        key=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2)
        if [ -n "$value" ] && [ "$value" != "" ]; then
            echo -e "  ${GREEN}✅ $key${NC}: configured"
        else
            echo -e "  ${RED}❌ $key${NC}: NOT SET"
        fi
    done

    echo ""
    echo -e "${YELLOW}OCR Service Status:${NC}"
    docker logs liquorpro-sales-prod 2>&1 | grep -E "PRIMARY|FALLBACK|ChatGPT|OpenAI|Gemini|Fomoa" | tail -10
    echo ""
}

show_help() {
    show_header
    echo -e "${YELLOW}Usage:${NC} $0 <command> [options]"
    echo ""
    echo -e "${YELLOW}Service Commands:${NC}"
    echo "  start                   Start all services"
    echo "  stop                    Stop all services"
    echo "  restart [service]       Restart all or specific service"
    echo "  status                  Show service status"
    echo "  logs [service] [lines]  View logs (default: all services, 100 lines)"
    echo "  update                  Pull latest images and recreate"
    echo "  rebuild [service]       Rebuild images from scratch"
    echo ""
    echo -e "${YELLOW}Database Commands:${NC}"
    echo "  backup                  Create database backup"
    echo "  restore <file>          Restore database from backup"
    echo "  db                      Open PostgreSQL shell"
    echo "  redis                   Open Redis CLI"
    echo ""
    echo -e "${YELLOW}Monitoring Commands:${NC}"
    echo "  health                  Run health checks"
    echo "  stats                   Show resource usage and stats"
    echo "  test-ocr                Test Smart Sale OCR configuration"
    echo ""
    echo -e "${YELLOW}Maintenance Commands:${NC}"
    echo "  shell [service]         Open shell in container (default: sales)"
    echo "  cleanup                 Clean up Docker resources"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 start                # Start production"
    echo "  $0 logs sales 200       # View last 200 lines of sales logs"
    echo "  $0 restart gateway      # Restart gateway service"
    echo "  $0 backup               # Create database backup"
    echo ""
}

# Main
cd "$PROJECT_ROOT"

case "${1:-help}" in
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    restart)    cmd_restart "${2:-}" ;;
    status)     cmd_status ;;
    logs)       cmd_logs "${2:-}" "${3:-100}" ;;
    health)     cmd_health ;;
    backup)     cmd_backup ;;
    restore)    cmd_restore "${2:-}" ;;
    shell)      cmd_shell "${2:-sales}" ;;
    db)         cmd_db ;;
    redis)      cmd_redis ;;
    update)     cmd_update ;;
    rebuild)    cmd_rebuild "${2:-}" ;;
    cleanup)    cmd_cleanup ;;
    stats)      cmd_stats ;;
    test-ocr)   cmd_test_ocr ;;
    help|--help|-h) show_help ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
