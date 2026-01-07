-- Migration: Add receipt fields to stock_purchases
-- Date: 2025-12-04
-- Description: Adds receipt/invoice information fields for purchase documentation

-- Add receipt columns to stock_purchases
ALTER TABLE stock_purchases ADD COLUMN IF NOT EXISTS receipt_number VARCHAR(100);
ALTER TABLE stock_purchases ADD COLUMN IF NOT EXISTS receipt_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE stock_purchases ADD COLUMN IF NOT EXISTS receipt_image_url TEXT;
ALTER TABLE stock_purchases ADD COLUMN IF NOT EXISTS receipt_notes TEXT;

-- Add index for receipt lookup
CREATE INDEX IF NOT EXISTS idx_stock_purchases_receipt_number
ON stock_purchases(tenant_id, receipt_number) WHERE receipt_number IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN stock_purchases.receipt_number IS 'Vendor invoice/receipt number';
COMMENT ON COLUMN stock_purchases.receipt_date IS 'Date on the vendor invoice/receipt';
COMMENT ON COLUMN stock_purchases.receipt_image_url IS 'URL to uploaded receipt image';
COMMENT ON COLUMN stock_purchases.receipt_notes IS 'Additional notes about the receipt';
