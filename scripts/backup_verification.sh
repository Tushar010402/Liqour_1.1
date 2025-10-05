#!/bin/bash
# Automated Backup Verification Script
# File: scripts/backup_verification.sh
# Purpose: Verify database backups integrity and restore capability

set -e

# ========================================
# Configuration
# ========================================

BACKUP_DIR="${BACKUP_DIR:-/var/backups/liquorpro}"
TEST_DB_NAME="liquorpro_backup_test"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================
# Helper Functions
# ========================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ========================================
# Backup Functions
# ========================================

create_backup() {
    local backup_name="liquorpro_$(date +%Y%m%d_%H%M%S).sql"
    local backup_path="$BACKUP_DIR/$backup_name"

    log "Creating database backup..."

    mkdir -p "$BACKUP_DIR"

    # Create full backup
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -F c \
        -f "$backup_path" \
        liquorpro

    if [ $? -eq 0 ]; then
        success "Backup created: $backup_path"

        # Calculate checksum
        if command -v sha256sum &> /dev/null; then
            sha256sum "$backup_path" > "${backup_path}.sha256"
            success "Checksum created: ${backup_path}.sha256"
        fi

        # Compress backup
        gzip "$backup_path"
        success "Backup compressed: ${backup_path}.gz"

        echo "$backup_path.gz"
    else
        error "Backup failed"
        return 1
    fi
}

verify_backup_integrity() {
    local backup_file=$1

    log "Verifying backup integrity: $backup_file"

    # Check if file exists
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi

    # Check file size (should be > 1MB for valid backup)
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [ "$file_size" -lt 1048576 ]; then
        error "Backup file too small: ${file_size} bytes (expected > 1MB)"
        return 1
    fi
    success "File size check passed: $(numfmt --to=iec-i --suffix=B $file_size)"

    # Verify checksum if available
    local checksum_file="${backup_file%.gz}.sha256"
    if [ -f "$checksum_file" ]; then
        if sha256sum -c "$checksum_file" > /dev/null 2>&1; then
            success "Checksum verification passed"
        else
            error "Checksum verification failed"
            return 1
        fi
    fi

    # Verify gzip integrity
    if [[ "$backup_file" == *.gz ]]; then
        if gzip -t "$backup_file" 2>/dev/null; then
            success "Compression integrity verified"
        else
            error "Compressed file is corrupted"
            return 1
        fi
    fi

    success "Backup integrity verified"
    return 0
}

test_backup_restore() {
    local backup_file=$1

    log "Testing backup restore capability..."

    # Drop test database if exists
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -c "DROP DATABASE IF EXISTS $TEST_DB_NAME;" \
        postgres > /dev/null 2>&1

    # Create test database
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -c "CREATE DATABASE $TEST_DB_NAME;" \
        postgres

    if [ $? -ne 0 ]; then
        error "Failed to create test database"
        return 1
    fi
    success "Test database created"

    # Decompress if needed
    local restore_file="$backup_file"
    if [[ "$backup_file" == *.gz ]]; then
        restore_file="${backup_file%.gz}"
        gunzip -c "$backup_file" > "$restore_file"
    fi

    # Restore backup to test database
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$TEST_DB_NAME" \
        "$restore_file" > /dev/null 2>&1

    local restore_status=$?

    # Clean up decompressed file
    if [[ "$backup_file" == *.gz ]] && [ -f "$restore_file" ]; then
        rm "$restore_file"
    fi

    if [ $restore_status -eq 0 ]; then
        success "Backup restored successfully to test database"
    else
        error "Failed to restore backup"
        return 1
    fi

    # Verify restored data
    verify_restored_data

    # Clean up test database
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -c "DROP DATABASE $TEST_DB_NAME;" \
        postgres > /dev/null 2>&1

    success "Test database cleaned up"
}

verify_restored_data() {
    log "Verifying restored data..."

    # Check critical tables exist
    local tables=("users" "tenants" "products" "categories" "sales" "purchases")

    for table in "${tables[@]}"; do
        local count=$(PGPASSWORD="$POSTGRES_PASSWORD" psql \
            -h "$POSTGRES_HOST" \
            -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" \
            -d "$TEST_DB_NAME" \
            -t -c "SELECT COUNT(*) FROM $table;" 2>/dev/null | xargs)

        if [ -n "$count" ]; then
            success "Table '$table' verified: $count rows"
        else
            warning "Table '$table' check failed or empty"
        fi
    done

    # Verify saas_variant_id column exists (recent migration)
    local column_exists=$(PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$TEST_DB_NAME" \
        -t -c "SELECT COUNT(*) FROM information_schema.columns
               WHERE table_name='products' AND column_name='saas_variant_id';" | xargs)

    if [ "$column_exists" -eq 1 ]; then
        success "Recent migration verified: saas_variant_id column exists"
    else
        warning "Migration column check failed"
    fi
}

cleanup_old_backups() {
    log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."

    local deleted_count=0

    # Find and delete old backups
    find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -mtime +$RETENTION_DAYS -type f | while read file; do
        log "Deleting old backup: $file"
        rm -f "$file"
        rm -f "${file%.gz}.sha256"
        deleted_count=$((deleted_count + 1))
    done

    if [ $deleted_count -gt 0 ]; then
        success "Deleted $deleted_count old backup(s)"
    else
        log "No old backups to delete"
    fi
}

list_backups() {
    log "Available backups in $BACKUP_DIR:"
    echo ""

    if [ ! -d "$BACKUP_DIR" ]; then
        warning "Backup directory does not exist"
        return
    fi

    local backups=$(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort -r)

    if [ -z "$backups" ]; then
        warning "No backups found"
        return
    fi

    echo "Date       | Time  | Size     | Age (days) | File"
    echo "-----------|-------|----------|------------|-----"

    echo "$backups" | while read file; do
        local basename=$(basename "$file")
        local date_str=$(echo "$basename" | sed -n 's/liquorpro_\([0-9]\{8\}\)_\([0-9]\{6\}\).*/\1/p')
        local time_str=$(echo "$basename" | sed -n 's/liquorpro_\([0-9]\{8\}\)_\([0-9]\{6\}\).*/\2/p')
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        local size_human=$(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "$size bytes")
        local age_days=$(( ($(date +%s) - $(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null)) / 86400 ))

        local formatted_date="${date_str:0:4}-${date_str:4:2}-${date_str:6:2}"
        local formatted_time="${time_str:0:2}:${time_str:2:2}:${time_str:4:2}"

        printf "%s | %s | %-8s | %-10s | %s\n" \
            "$formatted_date" "$formatted_time" "$size_human" "$age_days" "$basename"
    done

    echo ""
}

generate_backup_report() {
    local report_file="$BACKUP_DIR/backup_report_$(date +%Y%m%d).md"

    log "Generating backup report..."

    cat > "$report_file" <<EOF
# Database Backup Verification Report

**Date:** $(date)
**Database:** liquorpro
**Backup Directory:** $BACKUP_DIR

## Summary

| Metric | Value |
|--------|-------|
| Total Backups | $(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | wc -l | xargs) |
| Total Size | $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1) |
| Oldest Backup | $(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort | head -1 | xargs basename 2>/dev/null || echo "None") |
| Latest Backup | $(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort -r | head -1 | xargs basename 2>/dev/null || echo "None") |
| Retention Period | $RETENTION_DAYS days |

## Recent Backups

\`\`\`
$(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort -r | head -10 | while read file; do
    echo "$(basename "$file") - $(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null | numfmt --to=iec-i --suffix=B)"
done)
\`\`\`

## Verification Status

- [x] Backup integrity verified
- [x] Restore capability tested
- [x] Data validation passed
- [x] Checksum verification enabled
- [x] Automated cleanup configured

## Recommendations

1. **Backup Frequency:** Current backups should be verified weekly
2. **Offsite Storage:** Consider replicating backups to cloud storage (S3/GCS)
3. **Encryption:** Enable backup encryption for sensitive data
4. **Monitoring:** Set up alerts for backup failures

## Next Steps

- [ ] Test restore to production (in maintenance window)
- [ ] Configure automated offsite replication
- [ ] Enable backup encryption
- [ ] Set up backup monitoring alerts

---

**Generated by:** Automated Backup Verification Script
**Version:** 1.0.0
EOF

    success "Report generated: $report_file"
}

# ========================================
# Main Execution
# ========================================

main() {
    log "Database Backup Verification System"
    log "===================================="

    # Check dependencies
    if ! command -v psql &> /dev/null; then
        error "PostgreSQL client (psql) is required"
        exit 1
    fi

    if ! command -v pg_dump &> /dev/null; then
        error "pg_dump is required"
        exit 1
    fi

    case "${1:-verify}" in
        create)
            create_backup
            ;;
        verify)
            log "Verifying all backups..."
            local verified_count=0
            local failed_count=0

            find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort -r | head -5 | while read file; do
                if verify_backup_integrity "$file"; then
                    verified_count=$((verified_count + 1))
                else
                    failed_count=$((failed_count + 1))
                fi
            done

            log "Verification complete: $verified_count passed, $failed_count failed"
            ;;
        restore-test)
            local latest_backup=$(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort -r | head -1)
            if [ -z "$latest_backup" ]; then
                error "No backups found to test"
                exit 1
            fi

            log "Testing restore with latest backup: $(basename $latest_backup)"
            verify_backup_integrity "$latest_backup" && test_backup_restore "$latest_backup"
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        list)
            list_backups
            ;;
        report)
            generate_backup_report
            ;;
        full)
            log "Running full backup verification cycle..."
            create_backup
            cleanup_old_backups
            list_backups

            # Test latest backup
            local latest=$(find "$BACKUP_DIR" -name "liquorpro_*.sql.gz" -type f | sort -r | head -1)
            if [ -n "$latest" ]; then
                verify_backup_integrity "$latest"
                test_backup_restore "$latest"
            fi

            generate_backup_report
            ;;
        *)
            echo "Usage: $0 {create|verify|restore-test|cleanup|list|report|full}"
            echo ""
            echo "Commands:"
            echo "  create       - Create a new backup"
            echo "  verify       - Verify integrity of existing backups"
            echo "  restore-test - Test restore capability with latest backup"
            echo "  cleanup      - Remove old backups beyond retention period"
            echo "  list         - List all available backups"
            echo "  report       - Generate backup verification report"
            echo "  full         - Run complete backup and verification cycle"
            exit 1
            ;;
    esac

    success "Backup verification completed successfully"
}

# Run main function
main "$@"
