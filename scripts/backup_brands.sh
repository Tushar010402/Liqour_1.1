#!/bin/bash

# Backup script for LiquorPro brand data
# This script creates a comprehensive backup of all brand-related tables

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/www/liquorpro/backups"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "=== Starting brand data backup at $(date) ==="

# Get database credentials from environment
DB_HOST="aa65a9c67220_liquorpro-postgres-prod"
DB_USER="liquorpro_prod"
DB_NAME="liquorpro_production"

# Create SQL backup of brand-related tables
echo "Creating SQL backup..."
sudo docker exec $DB_HOST pg_dump -U $DB_USER -d $DB_NAME \
    -t saas_brands \
    -t brand_variants \
    -t tenant_brands \
    -t tenant_brand_variants \
    -t brand_categories \
    -t brand_subcategories \
    -t brands \
    -t products \
    | sudo tee "$BACKUP_DIR/brands_backup_${TIMESTAMP}.sql" > /dev/null

# Export to CSV for easy viewing
echo "Exporting to CSV..."
sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "\COPY (SELECT * FROM saas_brands) TO STDOUT WITH CSV HEADER" \
    | sudo tee "$BACKUP_DIR/saas_brands_${TIMESTAMP}.csv" > /dev/null

sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "\COPY (SELECT * FROM brand_variants) TO STDOUT WITH CSV HEADER" \
    | sudo tee "$BACKUP_DIR/brand_variants_${TIMESTAMP}.csv" > /dev/null

sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "\COPY (SELECT * FROM tenant_brands) TO STDOUT WITH CSV HEADER" \
    | sudo tee "$BACKUP_DIR/tenant_brands_${TIMESTAMP}.csv" > /dev/null

sudo docker exec $DB_HOST psql -U $DB_USER -d $DB_NAME -c \
    "\COPY (SELECT * FROM brand_categories) TO STDOUT WITH CSV HEADER" \
    | sudo tee "$BACKUP_DIR/brand_categories_${TIMESTAMP}.csv" > /dev/null

echo "=== Backup completed at $(date) ==="
echo "Backup files created:"
echo "  - $BACKUP_DIR/brands_backup_${TIMESTAMP}.sql"
echo "  - $BACKUP_DIR/saas_brands_${TIMESTAMP}.csv"
echo "  - $BACKUP_DIR/brand_variants_${TIMESTAMP}.csv"
echo "  - $BACKUP_DIR/tenant_brands_${TIMESTAMP}.csv"
echo "  - $BACKUP_DIR/brand_categories_${TIMESTAMP}.csv"