-- Migration: Fix vendors table schema to match backend model
-- Date: 2025-10-28
-- Description: Add missing columns and rename existing columns to match the Vendor model

-- Add missing columns if they don't exist
ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS contact_person VARCHAR(255),
  ADD COLUMN IF NOT EXISTS country VARCHAR(100) DEFAULT 'India',
  ADD COLUMN IF NOT EXISTS tax_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS payment_terms VARCHAR(50),
  ADD COLUMN IF NOT EXISTS created_by UUID;

-- Rename columns to match backend model (only if they exist with old names)
DO $$
BEGIN
    -- Rename gstin to gst_number if gstin exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'vendors' AND column_name = 'gstin'
    ) THEN
        ALTER TABLE vendors RENAME COLUMN gstin TO gst_number;
    END IF;

    -- Rename pan to pan_number if pan exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'vendors' AND column_name = 'pan'
    ) THEN
        ALTER TABLE vendors RENAME COLUMN pan TO pan_number;
    END IF;
END $$;

-- Ensure gst_number and pan_number columns exist (in case they were already renamed)
ALTER TABLE vendors
  ADD COLUMN IF NOT EXISTS gst_number VARCHAR(50),
  ADD COLUMN IF NOT EXISTS pan_number VARCHAR(50);

-- Add comment
COMMENT ON TABLE vendors IS 'Vendor/Supplier management table with complete schema matching backend model';
