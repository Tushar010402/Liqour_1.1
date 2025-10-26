-- Migration: Add Bulk Import Tables
-- Description: Creates tables for tracking bulk product imports via Excel/CSV/OCR
-- Date: 2025-10-21

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create import_history table for tracking all bulk import operations
CREATE TABLE IF NOT EXISTS import_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    shop_id UUID,

    -- Import metadata
    import_type VARCHAR(20) NOT NULL CHECK (import_type IN ('excel', 'csv', 'image_ocr', 'invoice_ocr')),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'validating', 'validated', 'processing', 'completed', 'failed', 'cancelled')),

    -- File information
    file_name VARCHAR(255),
    file_size BIGINT,
    file_path TEXT,

    -- Processing statistics
    total_rows INTEGER DEFAULT 0,
    valid_rows INTEGER DEFAULT 0,
    invalid_rows INTEGER DEFAULT 0,
    processed_rows INTEGER DEFAULT 0,
    products_created INTEGER DEFAULT 0,
    stocks_created INTEGER DEFAULT 0,

    -- Error tracking
    error_message TEXT,
    error_details JSONB,

    -- Validation and processing data
    validation_json JSONB,
    import_data JSONB,

    -- Performance metrics
    processing_time INTEGER, -- milliseconds

    -- Timestamps
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP,

    -- Foreign keys (soft references - no hard constraints to allow flexibility)
    CONSTRAINT fk_import_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_import_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_import_shop FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE SET NULL
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_import_history_tenant_id ON import_history(tenant_id);
CREATE INDEX IF NOT EXISTS idx_import_history_user_id ON import_history(user_id);
CREATE INDEX IF NOT EXISTS idx_import_history_shop_id ON import_history(shop_id);
CREATE INDEX IF NOT EXISTS idx_import_history_status ON import_history(status);
CREATE INDEX IF NOT EXISTS idx_import_history_import_type ON import_history(import_type);
CREATE INDEX IF NOT EXISTS idx_import_history_created_at ON import_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_import_history_tenant_status ON import_history(tenant_id, status);

-- Create composite index for common filtering
CREATE INDEX IF NOT EXISTS idx_import_history_tenant_created ON import_history(tenant_id, created_at DESC);

-- Add comments for documentation
COMMENT ON TABLE import_history IS 'Tracks all bulk import operations including Excel, CSV, and OCR-based imports';
COMMENT ON COLUMN import_history.import_type IS 'Type of import: excel, csv, image_ocr, or invoice_ocr';
COMMENT ON COLUMN import_history.status IS 'Current status: pending, validating, validated, processing, completed, failed, or cancelled';
COMMENT ON COLUMN import_history.validation_json IS 'Stores validation results and row-level match details';
COMMENT ON COLUMN import_history.import_data IS 'Stores the parsed import data before execution';
COMMENT ON COLUMN import_history.processing_time IS 'Time taken to process import in milliseconds';

-- Create updated_at trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add trigger to auto-update updated_at timestamp
CREATE TRIGGER update_import_history_updated_at
    BEFORE UPDATE ON import_history
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Optional: Create a view for recent imports summary
CREATE OR REPLACE VIEW recent_imports_summary AS
SELECT
    ih.id,
    ih.tenant_id,
    ih.user_id,
    ih.shop_id,
    ih.import_type,
    ih.status,
    ih.file_name,
    ih.total_rows,
    ih.valid_rows,
    ih.invalid_rows,
    ih.products_created,
    ih.stocks_created,
    ih.created_at,
    ih.completed_at,
    ih.processing_time,
    u.full_name as imported_by,
    s.name as shop_name,
    CASE
        WHEN ih.status = 'completed' THEN
            ROUND((ih.valid_rows::DECIMAL / NULLIF(ih.total_rows, 0)) * 100, 2)
        ELSE NULL
    END as success_rate
FROM import_history ih
LEFT JOIN users u ON ih.user_id = u.id
LEFT JOIN shops s ON ih.shop_id = s.id
WHERE ih.created_at >= NOW() - INTERVAL '30 days'
ORDER BY ih.created_at DESC;

COMMENT ON VIEW recent_imports_summary IS 'Summary view of imports from the last 30 days with user and shop details';

-- Grant appropriate permissions (adjust based on your role setup)
-- GRANT SELECT, INSERT, UPDATE ON import_history TO inventory_service_role;
-- GRANT SELECT ON recent_imports_summary TO inventory_service_role;
