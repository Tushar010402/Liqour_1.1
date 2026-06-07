-- Add stock alert fields to daily_sales_records
ALTER TABLE daily_sales_records ADD COLUMN IF NOT EXISTS has_alerts BOOLEAN DEFAULT false;
ALTER TABLE daily_sales_records ADD COLUMN IF NOT EXISTS alert_count INT DEFAULT 0;

-- Add stock alert fields to daily_sales_items
ALTER TABLE daily_sales_items ADD COLUMN IF NOT EXISTS stock_alert TEXT;
ALTER TABLE daily_sales_items ADD COLUMN IF NOT EXISTS stock_alert_qty INT DEFAULT 0;

-- Partial index for efficient filtering of records with alerts
CREATE INDEX IF NOT EXISTS idx_daily_sales_records_has_alerts
    ON daily_sales_records (has_alerts) WHERE has_alerts = true;

-- Partial index for items with stock alerts
CREATE INDEX IF NOT EXISTS idx_daily_sales_items_stock_alert
    ON daily_sales_items (daily_sales_record_id) WHERE stock_alert IS NOT NULL;
