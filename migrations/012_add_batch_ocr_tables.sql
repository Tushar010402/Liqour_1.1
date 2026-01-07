-- Migration: Add Batch OCR Tables for Multi-Image Stock Initialization
-- Created: 2025-10-26
-- Purpose: Support multi-image OCR processing for stock initialization

-- Batch OCR Sessions Table
CREATE TABLE IF NOT EXISTS batch_ocr_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, processing, completed, partial, failed
    session_type VARCHAR(50) NOT NULL DEFAULT 'stock_initialization', -- stock_initialization, invoice_import

    total_images INTEGER NOT NULL DEFAULT 0,
    completed_images INTEGER NOT NULL DEFAULT 0,
    failed_images INTEGER NOT NULL DEFAULT 0,
    total_items_extracted INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT valid_status CHECK (status IN ('pending', 'processing', 'completed', 'partial', 'failed')),
    CONSTRAINT valid_session_type CHECK (session_type IN ('stock_initialization', 'invoice_import')),
    CONSTRAINT valid_image_counts CHECK (
        total_images >= 0 AND
        completed_images >= 0 AND
        failed_images >= 0 AND
        completed_images + failed_images <= total_images
    )
);

-- Indexes for batch_ocr_sessions
CREATE INDEX idx_batch_ocr_sessions_tenant_id ON batch_ocr_sessions(tenant_id);
CREATE INDEX idx_batch_ocr_sessions_user_id ON batch_ocr_sessions(user_id);
CREATE INDEX idx_batch_ocr_sessions_shop_id ON batch_ocr_sessions(shop_id);
CREATE INDEX idx_batch_ocr_sessions_status ON batch_ocr_sessions(status);
CREATE INDEX idx_batch_ocr_sessions_created_at ON batch_ocr_sessions(created_at DESC);

-- Add batch_session_id to ocr_sessions to link individual sessions to batch
ALTER TABLE ocr_sessions
ADD COLUMN IF NOT EXISTS batch_session_id UUID REFERENCES batch_ocr_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ocr_sessions_batch_id ON ocr_sessions(batch_session_id);

-- Updated trigger for batch_ocr_sessions
CREATE OR REPLACE FUNCTION update_batch_ocr_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_batch_ocr_sessions_updated_at
    BEFORE UPDATE ON batch_ocr_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_batch_ocr_sessions_updated_at();

-- Comments for documentation
COMMENT ON TABLE batch_ocr_sessions IS 'Batch OCR sessions for processing multiple invoice images simultaneously';
COMMENT ON COLUMN batch_ocr_sessions.session_type IS 'Type of batch processing: stock_initialization for initial stock setup, invoice_import for regular purchases';
COMMENT ON COLUMN batch_ocr_sessions.total_images IS 'Total number of images in this batch';
COMMENT ON COLUMN batch_ocr_sessions.completed_images IS 'Number of images successfully processed';
COMMENT ON COLUMN batch_ocr_sessions.failed_images IS 'Number of images that failed processing';
COMMENT ON COLUMN batch_ocr_sessions.total_items_extracted IS 'Total number of items extracted across all images';
COMMENT ON COLUMN ocr_sessions.batch_session_id IS 'Reference to parent batch session if this is part of a multi-image batch';
