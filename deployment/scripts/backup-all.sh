#!/bin/bash

# LiquorPro Automated Backup Script
# Backs up PostgreSQL database and Redis data
# Usage: ./backup-all.sh
# Cron: 0 2 * * * /opt/liquorpro/backend/deployment/scripts/backup-all.sh

set -e

# Configuration
BACKUP_DIR="/opt/liquorpro/backups"
POSTGRES_BACKUP_DIR="$BACKUP_DIR/postgres"
REDIS_BACKUP_DIR="$BACKUP_DIR/redis"
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)

# S3 Configuration (from .env.production)
if [ -f "/opt/liquorpro/backend/.env.production" ]; then
    source /opt/liquorpro/backend/.env.production
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_info "========================================="
log_info "LiquorPro Backup Process Started"
log_info "========================================="

# Create backup directories
mkdir -p "$POSTGRES_BACKUP_DIR"
mkdir -p "$REDIS_BACKUP_DIR"

# ========================================
# Backup PostgreSQL
# ========================================
log_info "Backing up PostgreSQL database..."

POSTGRES_BACKUP_FILE="$POSTGRES_BACKUP_DIR/liquorpro_${DATE}.sql.gz"

if docker exec liquorpro-postgres-prod pg_dump \
    -U "${DATABASE_USER:-liquorpro_prod}" \
    "${DATABASE_NAME:-liquorpro_production}" \
    | gzip > "$POSTGRES_BACKUP_FILE"; then

    BACKUP_SIZE=$(du -h "$POSTGRES_BACKUP_FILE" | cut -f1)
    log_info "✓ PostgreSQL backup created: $POSTGRES_BACKUP_FILE ($BACKUP_SIZE)"

    # Verify backup integrity
    if gunzip -t "$POSTGRES_BACKUP_FILE" 2>/dev/null; then
        log_info "✓ PostgreSQL backup integrity verified"
    else
        log_error "PostgreSQL backup is corrupted!"
        exit 1
    fi
else
    log_error "PostgreSQL backup failed!"
    exit 1
fi

# ========================================
# Backup Redis
# ========================================
log_info "Backing up Redis data..."

REDIS_BACKUP_FILE="$REDIS_BACKUP_DIR/redis_${DATE}.rdb.gz"

# Trigger Redis save
if docker exec liquorpro-redis-prod redis-cli -a "${REDIS_PASSWORD}" SAVE > /dev/null 2>&1; then
    # Copy and compress Redis dump
    if docker cp liquorpro-redis-prod:/data/dump.rdb - | gzip > "$REDIS_BACKUP_FILE"; then
        BACKUP_SIZE=$(du -h "$REDIS_BACKUP_FILE" | cut -f1)
        log_info "✓ Redis backup created: $REDIS_BACKUP_FILE ($BACKUP_SIZE)"
    else
        log_warn "Redis backup copy failed (non-critical)"
    fi
else
    log_warn "Redis backup failed (non-critical)"
fi

# ========================================
# Upload to S3 (if configured)
# ========================================
if [ -n "$BACKUP_S3_BUCKET" ] && command -v aws &> /dev/null; then
    log_info "Uploading backups to S3..."

    if aws s3 cp "$POSTGRES_BACKUP_FILE" \
        "s3://${BACKUP_S3_BUCKET}/postgres/" \
        --region "${BACKUP_S3_REGION:-us-east-1}"; then
        log_info "✓ PostgreSQL backup uploaded to S3"
    else
        log_warn "S3 upload failed (local backup retained)"
    fi

    if [ -f "$REDIS_BACKUP_FILE" ]; then
        aws s3 cp "$REDIS_BACKUP_FILE" \
            "s3://${BACKUP_S3_BUCKET}/redis/" \
            --region "${BACKUP_S3_REGION:-us-east-1}" || true
    fi
fi

# ========================================
# Clean Old Backups
# ========================================
log_info "Cleaning backups older than $RETENTION_DAYS days..."

# Remove old PostgreSQL backups
find "$POSTGRES_BACKUP_DIR" -name "liquorpro_*.sql.gz" -mtime +$RETENTION_DAYS -delete
POSTGRES_COUNT=$(find "$POSTGRES_BACKUP_DIR" -name "liquorpro_*.sql.gz" | wc -l)
log_info "Retained $POSTGRES_COUNT PostgreSQL backups"

# Remove old Redis backups
find "$REDIS_BACKUP_DIR" -name "redis_*.rdb.gz" -mtime +$RETENTION_DAYS -delete
REDIS_COUNT=$(find "$REDIS_BACKUP_DIR" -name "redis_*.rdb.gz" | wc -l)
log_info "Retained $REDIS_COUNT Redis backups"

# ========================================
# Summary
# ========================================
log_info "========================================="
log_info "✅ Backup Process Completed Successfully"
log_info "========================================="
log_info "PostgreSQL: $POSTGRES_BACKUP_FILE"
[ -f "$REDIS_BACKUP_FILE" ] && log_info "Redis: $REDIS_BACKUP_FILE"
log_info ""
log_info "Total disk usage: $(du -sh $BACKUP_DIR | cut -f1)"

# Send notification (if Slack webhook configured)
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"text\":\"✅ LiquorPro backup completed\nDate: $(date '+%Y-%m-%d %H:%M:%S')\nSize: $(du -sh $BACKUP_DIR | cut -f1)\"}" \
        > /dev/null 2>&1 || true
fi

exit 0
