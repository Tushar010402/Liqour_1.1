-- Migration: 056_training_image_size_mappings.sql
-- Description: Creates table to map training images to specific sizes for AI training data
-- Date: 2026-01-23

-- Enable UUID extension if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create training_image_size_mappings table
CREATE TABLE IF NOT EXISTS training_image_size_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    daily_sales_record_id UUID NOT NULL,

    -- Image reference
    image_filename VARCHAR(500) NOT NULL,
    image_url TEXT NOT NULL,

    -- Size detection
    detected_size VARCHAR(20) NOT NULL,  -- "90ML", "180ML", "375ML", "750ML", "650ML", etc.
    detection_method VARCHAR(50) NOT NULL DEFAULT 'pending',  -- "fomoa_vision", "manual", "ocr_header", "pending"
    detection_confidence DECIMAL(5,2),

    -- For cropped beer images
    is_cropped BOOLEAN DEFAULT FALSE,
    source_image_filename VARCHAR(500),
    crop_region JSONB,  -- {"x": 0, "y": 0, "width": 100, "height": 25, "y_start_pct": 0, "y_end_pct": 25}
    cropped_image_path VARCHAR(500),

    -- Beer page specific
    is_beer_page BOOLEAN DEFAULT FALSE,
    size_section_index INT,  -- 0, 1, 2, 3 for different size sections in beer page

    -- Manual override/verification
    is_manually_verified BOOLEAN DEFAULT FALSE,
    verified_by_id UUID,
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_training_mapping_record
    ON training_image_size_mappings(daily_sales_record_id);

CREATE INDEX IF NOT EXISTS idx_training_mapping_size
    ON training_image_size_mappings(detected_size);

CREATE INDEX IF NOT EXISTS idx_training_mapping_tenant
    ON training_image_size_mappings(tenant_id);

CREATE INDEX IF NOT EXISTS idx_training_mapping_filename
    ON training_image_size_mappings(image_filename);

CREATE INDEX IF NOT EXISTS idx_training_mapping_method
    ON training_image_size_mappings(detection_method);

-- Composite index for common query pattern
CREATE INDEX IF NOT EXISTS idx_training_mapping_tenant_size
    ON training_image_size_mappings(tenant_id, detected_size);

-- Add foreign key constraint (if daily_sales_records table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'daily_sales_records') THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints
            WHERE constraint_name = 'fk_training_mapping_record'
        ) THEN
            ALTER TABLE training_image_size_mappings
            ADD CONSTRAINT fk_training_mapping_record
            FOREIGN KEY (daily_sales_record_id)
            REFERENCES daily_sales_records(id) ON DELETE CASCADE;
        END IF;
    END IF;
END $$;

-- Comments
COMMENT ON TABLE training_image_size_mappings IS 'Maps training images to specific product sizes for accurate AI training data';
COMMENT ON COLUMN training_image_size_mappings.detected_size IS 'Size detected in image: 90ML, 180ML, 375ML, 750ML, 650ML, etc.';
COMMENT ON COLUMN training_image_size_mappings.detection_method IS 'How size was detected: fomoa_vision, manual, ocr_header, pending';
COMMENT ON COLUMN training_image_size_mappings.is_beer_page IS 'True if this is a beer page containing multiple sizes vertically';
COMMENT ON COLUMN training_image_size_mappings.crop_region IS 'JSON with crop coordinates for beer pages: {x, y, width, height, y_start_pct, y_end_pct}';
