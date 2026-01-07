-- Migration: 052_ai_validation_system.sql
-- Description: Add AI-powered validation system with auto-learning capability for daily sales records
-- Date: 2024-12-23

-- ============================================================================
-- PHASE 1: Add validation columns to daily_sales_records
-- ============================================================================

-- Add validation tracking columns to daily_sales_records
ALTER TABLE daily_sales_records
ADD COLUMN IF NOT EXISTS ocr_session_id UUID,
ADD COLUMN IF NOT EXISTS validation_status VARCHAR(20) DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS validation_result JSONB,
ADD COLUMN IF NOT EXISTS validated_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS validation_triggered_at TIMESTAMP WITH TIME ZONE;

-- Add auto-learning feedback columns
ALTER TABLE daily_sales_records
ADD COLUMN IF NOT EXISTS validation_confirmed BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS confirmed_by_id UUID,
ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS feedback_notes TEXT;

-- Add foreign key for confirmed_by (references users table)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_daily_sales_confirmed_by'
    ) THEN
        ALTER TABLE daily_sales_records
        ADD CONSTRAINT fk_daily_sales_confirmed_by
        FOREIGN KEY (confirmed_by_id) REFERENCES users(id) ON DELETE SET NULL;
    END IF;
END $$;

-- Add index for validation status filtering
CREATE INDEX IF NOT EXISTS idx_daily_sales_validation_status
ON daily_sales_records(validation_status);

-- Add index for OCR session lookup
CREATE INDEX IF NOT EXISTS idx_daily_sales_ocr_session
ON daily_sales_records(ocr_session_id);

-- ============================================================================
-- PHASE 2: Create OCR Training Samples table (Auto-Learning Data)
-- ============================================================================

CREATE TABLE IF NOT EXISTS ocr_training_samples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    daily_sales_record_id UUID,
    ocr_session_id UUID,

    -- Original image reference
    image_url TEXT NOT NULL,
    image_hash VARCHAR(64),  -- SHA-256 hash for deduplication

    -- OCR extraction results
    ocr_extracted_items JSONB NOT NULL,  -- What OCR extracted

    -- Ground truth (human-verified data)
    verified_items JSONB,  -- What human entered/corrected

    -- Matching accuracy metrics (0-100%)
    overall_accuracy DECIMAL(5,2),
    brand_match_accuracy DECIMAL(5,2),
    quantity_accuracy DECIMAL(5,2),
    price_accuracy DECIMAL(5,2),

    -- Training status
    is_verified BOOLEAN DEFAULT FALSE,  -- Human confirmed as correct
    is_used_for_training BOOLEAN DEFAULT FALSE,
    training_batch_id VARCHAR(50),  -- Which training run used this

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Foreign keys
    CONSTRAINT fk_training_samples_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_training_samples_daily_sales
        FOREIGN KEY (daily_sales_record_id) REFERENCES daily_sales_records(id) ON DELETE SET NULL
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_training_samples_tenant
ON ocr_training_samples(tenant_id);

CREATE INDEX IF NOT EXISTS idx_training_samples_accuracy
ON ocr_training_samples(overall_accuracy);

CREATE INDEX IF NOT EXISTS idx_training_samples_verified
ON ocr_training_samples(is_verified);

CREATE INDEX IF NOT EXISTS idx_training_samples_image_hash
ON ocr_training_samples(image_hash);

CREATE INDEX IF NOT EXISTS idx_training_samples_daily_sales
ON ocr_training_samples(daily_sales_record_id);

-- Unique constraint: one sample per image per tenant
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_training_sample_per_tenant
ON ocr_training_samples(tenant_id, image_hash)
WHERE image_hash IS NOT NULL;

-- ============================================================================
-- PHASE 3: Create OCR Accuracy Metrics table (Track Improvement Over Time)
-- ============================================================================

CREATE TABLE IF NOT EXISTS ocr_accuracy_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,

    -- Time period
    metric_date DATE NOT NULL,

    -- Volume metrics
    total_validations INT DEFAULT 0,
    auto_verified INT DEFAULT 0,         -- No human correction needed
    required_correction INT DEFAULT 0,    -- Human had to fix

    -- Accuracy metrics (0-100%)
    avg_brand_accuracy DECIMAL(5,2),
    avg_quantity_accuracy DECIMAL(5,2),
    avg_price_accuracy DECIMAL(5,2),
    avg_overall_accuracy DECIMAL(5,2),

    -- Learning metrics
    training_samples_added INT DEFAULT 0,
    model_version VARCHAR(50),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Foreign key
    CONSTRAINT fk_accuracy_metrics_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,

    -- Unique constraint: one record per tenant per day
    CONSTRAINT unique_tenant_metric_date
        UNIQUE (tenant_id, metric_date)
);

-- Index for date-based queries
CREATE INDEX IF NOT EXISTS idx_accuracy_metrics_date
ON ocr_accuracy_metrics(metric_date);

CREATE INDEX IF NOT EXISTS idx_accuracy_metrics_tenant
ON ocr_accuracy_metrics(tenant_id);

-- ============================================================================
-- PHASE 4: Create Brand Alias table (For OCR Learning)
-- ============================================================================

CREATE TABLE IF NOT EXISTS ocr_brand_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,

    -- The correct/canonical brand name
    canonical_brand_name VARCHAR(255) NOT NULL,
    product_id UUID,  -- If linked to a specific product

    -- The OCR misread or alternative name
    alias_name VARCHAR(255) NOT NULL,

    -- How often this alias has been seen/confirmed
    occurrence_count INT DEFAULT 1,
    confidence_score DECIMAL(5,2) DEFAULT 100.00,

    -- Source of this alias
    source VARCHAR(50) DEFAULT 'manual',  -- manual, ocr_learning, user_correction

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE,

    -- Foreign keys
    CONSTRAINT fk_brand_aliases_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_brand_aliases_product
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL,

    -- Unique: one alias per tenant
    CONSTRAINT unique_alias_per_tenant
        UNIQUE (tenant_id, alias_name)
);

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_brand_aliases_tenant
ON ocr_brand_aliases(tenant_id);

CREATE INDEX IF NOT EXISTS idx_brand_aliases_alias
ON ocr_brand_aliases(alias_name);

CREATE INDEX IF NOT EXISTS idx_brand_aliases_canonical
ON ocr_brand_aliases(canonical_brand_name);

-- Full-text search index for fuzzy matching
CREATE INDEX IF NOT EXISTS idx_brand_aliases_alias_trgm
ON ocr_brand_aliases USING gin (alias_name gin_trgm_ops);

-- ============================================================================
-- PHASE 5: Add comment documentation
-- ============================================================================

COMMENT ON COLUMN daily_sales_records.ocr_session_id IS 'Reference to OCR batch session used for validation';
COMMENT ON COLUMN daily_sales_records.validation_status IS 'Status: pending, processing, verified, mismatches, error, skipped';
COMMENT ON COLUMN daily_sales_records.validation_result IS 'JSONB containing detailed comparison results';
COMMENT ON COLUMN daily_sales_records.validation_confirmed IS 'Manager has reviewed and confirmed the validation';

COMMENT ON TABLE ocr_training_samples IS 'Stores OCR extractions paired with human-verified data for auto-learning';
COMMENT ON TABLE ocr_accuracy_metrics IS 'Daily aggregated accuracy metrics for tracking OCR improvement over time';
COMMENT ON TABLE ocr_brand_aliases IS 'Maps OCR misreads and variations to correct brand names for improved matching';

-- ============================================================================
-- PHASE 6: Grant permissions (for production)
-- ============================================================================

-- Grant permissions to the application user (adjust user name as needed)
DO $$
BEGIN
    -- Only run if the user exists
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'liquorpro_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON ocr_training_samples TO liquorpro_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ocr_accuracy_metrics TO liquorpro_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ocr_brand_aliases TO liquorpro_app;
    END IF;
END $$;

-- ============================================================================
-- Migration complete
-- ============================================================================
