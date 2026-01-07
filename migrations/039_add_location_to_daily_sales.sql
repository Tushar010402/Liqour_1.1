-- Migration: 039_add_location_to_daily_sales.sql
-- Purpose: Add optional location tracking fields to daily_sales_records for sales monitoring
-- Date: 2025-11-30

-- Add location tracking columns to daily_sales_records table
ALTER TABLE daily_sales_records ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 8);
ALTER TABLE daily_sales_records ADD COLUMN IF NOT EXISTS longitude DECIMAL(11, 8);
ALTER TABLE daily_sales_records ADD COLUMN IF NOT EXISTS location_accuracy VARCHAR(20);
ALTER TABLE daily_sales_records ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMPTZ;

-- Add comments for documentation
COMMENT ON COLUMN daily_sales_records.latitude IS 'GPS latitude where sales record was created (optional)';
COMMENT ON COLUMN daily_sales_records.longitude IS 'GPS longitude where sales record was created (optional)';
COMMENT ON COLUMN daily_sales_records.location_accuracy IS 'Location accuracy level: high, medium, low (optional)';
COMMENT ON COLUMN daily_sales_records.location_captured_at IS 'Timestamp when location was captured (optional)';
