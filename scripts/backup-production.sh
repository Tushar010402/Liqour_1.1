#!/bin/bash
# =============================================================================
# LiquorPro Industrial-Grade Database Backup Script
# Automated backups with rotation, compression, and verification
# =============================================================================

set -euo pipefail

# Configuration
BACKUP_DIR="/opt/liquorpro/backups"
LOG_DIR="/opt/liquorpro/logs/backup"
RETENTION_DAYS=30
RETENTION_WEEKLY=12  # Keep 12 weekly backups (3 months)
RETENTION_MONTHLY=12 # Keep 12 monthly backups (1 year)

# Database credentials (from environment or .env file)
DB_CONTAINER="liquorpro-postgres-prod"
DB_USER="${DATABASE_USER:-liquorpro_prod}"
DB_NAME="${DATABASE_NAME:-liquorpro_production}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌${NC} $1"; }

# Create directories
mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly}
mkdir -p "$LOG_DIR"

# Generate backup filename
DATE=$(date +%Y%m%d_%H%M%S)
DAY_OF_WEEK=$(date +%u)
DAY_OF_MONTH=$(date +%d)
BACKUP_FILE="liquorpro_backup_${DATE}.sql"

log "Starting LiquorPro database backup..."
log "Database: $DB_NAME | Container: $DB_CONTAINER"

# Create backup
log "Creating database dump..."
if docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists > "$BACKUP_DIR/daily/$BACKUP_FILE" 2>> "$LOG_DIR/backup.log"; then
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/daily/$BACKUP_FILE" | cut -f1)
    log_success "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"
else
    log_error "Backup failed!"
    exit 1
fi

# Compress backup
log "Compressing backup..."
gzip -f "$BACKUP_DIR/daily/$BACKUP_FILE"
COMPRESSED_SIZE=$(du -h "$BACKUP_DIR/daily/$BACKUP_FILE.gz" | cut -f1)
log_success "Compressed: $BACKUP_FILE.gz ($COMPRESSED_SIZE)"

# Verify backup integrity
log "Verifying backup integrity..."
if gzip -t "$BACKUP_DIR/daily/$BACKUP_FILE.gz" 2>/dev/null; then
    log_success "Backup integrity verified"
else
    log_error "Backup integrity check failed!"
    exit 1
fi

# Weekly backup (every Sunday)
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    log "Creating weekly backup copy..."
    cp "$BACKUP_DIR/daily/$BACKUP_FILE.gz" "$BACKUP_DIR/weekly/liquorpro_weekly_${DATE}.sql.gz"
    log_success "Weekly backup created"
fi

# Monthly backup (1st of each month)
if [ "$DAY_OF_MONTH" -eq "01" ]; then
    log "Creating monthly backup copy..."
    cp "$BACKUP_DIR/daily/$BACKUP_FILE.gz" "$BACKUP_DIR/monthly/liquorpro_monthly_${DATE}.sql.gz"
    log_success "Monthly backup created"
fi

# Cleanup old backups
log "Cleaning up old backups..."
find "$BACKUP_DIR/daily" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR/weekly" -name "*.sql.gz" -mtime +$((RETENTION_WEEKLY * 7)) -delete 2>/dev/null || true
find "$BACKUP_DIR/monthly" -name "*.sql.gz" -mtime +$((RETENTION_MONTHLY * 30)) -delete 2>/dev/null || true
log_success "Cleanup completed"

# Summary
DAILY_COUNT=$(ls -1 "$BACKUP_DIR/daily"/*.sql.gz 2>/dev/null | wc -l)
WEEKLY_COUNT=$(ls -1 "$BACKUP_DIR/weekly"/*.sql.gz 2>/dev/null | wc -l)
MONTHLY_COUNT=$(ls -1 "$BACKUP_DIR/monthly"/*.sql.gz 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

echo ""
log_success "=== Backup Summary ==="
echo "  Daily backups:   $DAILY_COUNT (kept $RETENTION_DAYS days)"
echo "  Weekly backups:  $WEEKLY_COUNT (kept $RETENTION_WEEKLY weeks)"
echo "  Monthly backups: $MONTHLY_COUNT (kept $RETENTION_MONTHLY months)"
echo "  Total size:      $TOTAL_SIZE"
echo ""
log_success "Backup completed successfully!"
