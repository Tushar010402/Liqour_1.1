-- Migration: 057_ai_training_images.sql
-- Description: Creates standalone AI training images table for generic document extraction training
-- Date: 2026-01-23

-- Enable UUID extension if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create ai_training_images table for standalone AI training (not linked to daily_sales)
CREATE TABLE IF NOT EXISTS ai_training_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID,

    -- Image info
    image_filename VARCHAR(500) NOT NULL,
    image_url TEXT NOT NULL,
    image_type VARCHAR(50), -- 'receipt', 'table', 'register', 'invoice', 'form', 'text'

    -- AI extraction result (raw JSON from Fomoa)
    ai_extracted_data JSONB NOT NULL,
    ai_extraction_method VARCHAR(50) DEFAULT 'fomoa_vision',
    ai_confidence DECIMAL(5,2),

    -- User verified data (corrected version)
    verified_data JSONB,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_by_id UUID,
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Training status
    is_used_for_training BOOLEAN DEFAULT FALSE,
    training_exported_at TIMESTAMP WITH TIME ZONE,

    -- Metadata
    uploaded_by_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_ai_training_images_tenant
    ON ai_training_images(tenant_id);

CREATE INDEX IF NOT EXISTS idx_ai_training_images_verified
    ON ai_training_images(is_verified);

CREATE INDEX IF NOT EXISTS idx_ai_training_images_type
    ON ai_training_images(image_type);

CREATE INDEX IF NOT EXISTS idx_ai_training_images_uploaded_by
    ON ai_training_images(uploaded_by_id);

CREATE INDEX IF NOT EXISTS idx_ai_training_images_created
    ON ai_training_images(created_at DESC);

-- Composite index for common query patterns
CREATE INDEX IF NOT EXISTS idx_ai_training_images_tenant_verified
    ON ai_training_images(tenant_id, is_verified);

CREATE INDEX IF NOT EXISTS idx_ai_training_images_tenant_type
    ON ai_training_images(tenant_id, image_type);

-- Comments
COMMENT ON TABLE ai_training_images IS 'Standalone AI training images for document extraction - supports any document type';
COMMENT ON COLUMN ai_training_images.image_type IS 'Document type: receipt, table, register, invoice, form, text';
COMMENT ON COLUMN ai_training_images.ai_extracted_data IS 'JSON extraction result from Fomoa AI Vision with headers, rows, form_fields, raw_text';
COMMENT ON COLUMN ai_training_images.verified_data IS 'User-corrected version of extracted data - ground truth for training';
COMMENT ON COLUMN ai_training_images.is_verified IS 'Whether a human has verified/corrected the extraction';
COMMENT ON COLUMN ai_training_images.is_used_for_training IS 'Whether this image has been exported for AI retraining';
