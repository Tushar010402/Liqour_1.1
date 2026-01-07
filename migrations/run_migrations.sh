#!/bin/bash
set -e

# ============================================================================
# LiquorPro Database Migration Runner
# Runs all SQL migrations in order and tracks them in schema_migrations table
# ============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Database connection parameters (from environment variables)
DB_HOST="${DATABASE_HOST:-postgres}"
DB_PORT="${DATABASE_PORT:-5432}"
DB_NAME="${DATABASE_NAME:-liquorpro}"
DB_USER="${DATABASE_USER:-liquorpro}"
DB_PASSWORD="${DATABASE_PASSWORD:-liquorpro_password}"

MIGRATIONS_DIR="/migrations"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}LiquorPro Database Migration Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Database: $DB_NAME@$DB_HOST:$DB_PORT"
echo "User: $DB_USER"
echo "Migrations Directory: $MIGRATIONS_DIR"
echo ""

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}⏳ Waiting for PostgreSQL to be ready...${NC}"
max_attempts=60
attempt=0

until PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ $attempt -eq $max_attempts ]; then
        echo -e "${RED}❌ Failed to connect to PostgreSQL after $max_attempts attempts${NC}"
        exit 1
    fi
    echo -e "${YELLOW}   Attempt $attempt/$max_attempts...${NC}"
    sleep 2
done

echo -e "${GREEN}✅ PostgreSQL is ready!${NC}"
echo ""

# Function to execute SQL file
run_migration() {
    local file=$1
    local filename=$(basename "$file")
    local version=$(echo "$filename" | sed 's/^\([0-9]*\)_.*/\1/')
    local name=$(echo "$filename" | sed 's/^[0-9]*_//;s/\.sql$//')

    echo -e "${BLUE}📄 Processing: $filename${NC}"

    # Check if migration already applied
    already_applied=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM schema_migrations WHERE version = '$version' AND success = true" 2>/dev/null || echo "0")

    if [ "$already_applied" -gt 0 ]; then
        echo -e "${YELLOW}   ⏭️  Skipped (already applied)${NC}"
        return 0
    fi

    # Calculate checksum
    checksum=$(md5sum "$file" | awk '{print $1}')

    # Record start time
    start_time=$(date +%s%3N)

    # Run migration
    if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$file" > /tmp/migration.log 2>&1; then
        # Calculate execution time
        end_time=$(date +%s%3N)
        execution_time=$((end_time - start_time))

        # Record successful migration
        PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
            "INSERT INTO schema_migrations (version, name, checksum, execution_time_ms, success)
             VALUES ('$version', '$name', '$checksum', $execution_time, true)
             ON CONFLICT (version) DO UPDATE SET
                applied_at = CURRENT_TIMESTAMP,
                checksum = '$checksum',
                execution_time_ms = $execution_time,
                success = true,
                error_message = NULL" > /dev/null

        echo -e "${GREEN}   ✅ Applied successfully (${execution_time}ms)${NC}"
        return 0
    else
        # Record failed migration
        error_msg=$(cat /tmp/migration.log | head -20)
        error_msg_escaped=$(echo "$error_msg" | sed "s/'/''/g")

        PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
            "INSERT INTO schema_migrations (version, name, checksum, success, error_message)
             VALUES ('$version', '$name', '$checksum', false, '$error_msg_escaped')
             ON CONFLICT (version) DO UPDATE SET
                applied_at = CURRENT_TIMESTAMP,
                success = false,
                error_message = '$error_msg_escaped'" > /dev/null 2>&1 || true

        echo -e "${RED}   ❌ Failed!${NC}"
        echo -e "${RED}   Error: $error_msg${NC}"
        return 1
    fi
}

# Create schema_migrations table first
echo -e "${BLUE}🔧 Initializing migration tracking system...${NC}"
run_migration "$MIGRATIONS_DIR/000_schema_migrations.sql"
echo ""

# Get list of all migration files, sorted by numeric prefix
migration_files=$(find "$MIGRATIONS_DIR" -name "*.sql" -not -name "000_schema_migrations.sql" | sort -V)

if [ -z "$migration_files" ]; then
    echo -e "${YELLOW}⚠️  No migration files found${NC}"
    exit 0
fi

# Count total migrations
total_migrations=$(echo "$migration_files" | wc -l)
echo -e "${BLUE}📊 Found $total_migrations migration(s) to process${NC}"
echo ""

# Run each migration
success_count=0
failed_count=0
skipped_count=0

for file in $migration_files; do
    if run_migration "$file"; then
        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
        fi
    else
        failed_count=$((failed_count + 1))
        echo -e "${RED}❌ Migration failed: $file${NC}"
        echo -e "${RED}❌ Stopping migration process${NC}"
        exit 1
    fi
done

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Migration Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total migrations: $total_migrations"
echo -e "${GREEN}✅ Successful: $success_count${NC}"
if [ $failed_count -gt 0 ]; then
    echo -e "${RED}❌ Failed: $failed_count${NC}"
fi
echo ""

# Show current schema version
current_version=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT version FROM schema_migrations WHERE success = true ORDER BY applied_at DESC LIMIT 1" | xargs)
echo -e "${GREEN}✅ Current schema version: $current_version${NC}"
echo ""

if [ $failed_count -eq 0 ]; then
    echo -e "${GREEN}🎉 All migrations completed successfully!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some migrations failed. Please check the logs.${NC}"
    exit 1
fi
