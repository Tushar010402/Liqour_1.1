-- Migration 023: Fix daily_sales_items table schema
-- Adds missing columns for item quantity and payment breakdown
-- Date: 2025-11-21

-- Add missing columns to daily_sales_items table
ALTER TABLE daily_sales_items
ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS cash_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS card_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS upi_amount DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS credit_amount DECIMAL(12,2) DEFAULT 0;

-- Migrate existing data from quantity_sold to quantity
UPDATE daily_sales_items
SET quantity = COALESCE(quantity_sold, 0)
WHERE quantity IS NULL OR quantity = 0;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_daily_sales_items_product_id ON daily_sales_items(product_id);
CREATE INDEX IF NOT EXISTS idx_daily_sales_items_record_id ON daily_sales_items(daily_sales_record_id);
