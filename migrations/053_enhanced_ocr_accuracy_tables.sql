-- Migration 053: Enhanced OCR Accuracy Tables
-- Phase 4: Industrial-Grade AI Sales Validation System
-- This migration adds comprehensive field-level accuracy tracking and row validation

-- =====================================================
-- PART 1: Enhance ocr_accuracy_metrics table
-- =====================================================

-- Add new field-level accuracy columns to existing table
ALTER TABLE ocr_accuracy_metrics
ADD COLUMN IF NOT EXISTS avg_opening_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_receipt_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_total_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_sale_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_rate_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_amount_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_closing_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_row_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_math_accuracy DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_math_checks INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS passed_math_checks INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS failed_math_checks INT DEFAULT 0;

-- =====================================================
-- PART 2: Create ocr_field_training table
-- =====================================================

-- Per-field training samples for learning
CREATE TABLE IF NOT EXISTS ocr_field_training (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    session_id UUID REFERENCES ocr_sessions(id) ON DELETE SET NULL,
    batch_id UUID REFERENCES batch_ocr_sessions(id) ON DELETE SET NULL,

    -- Field identification
    field_name VARCHAR(50) NOT NULL,  -- opening, receipt, total, sale, rate, amount, closing, brand
    row_number INT,

    -- OCR extracted vs correct values
    ocr_value TEXT,
    correct_value TEXT,

    -- Context for learning
    brand_name VARCHAR(255),
    size VARCHAR(50),
    context_data JSONB,  -- Surrounding row data for context

    -- Confidence tracking
    confidence_before DECIMAL(5,2),
    confidence_after DECIMAL(5,2),
    accuracy_score DECIMAL(5,2),  -- 0-100

    -- Source tracking
    correction_source VARCHAR(50) DEFAULT 'manual',  -- manual, auto, validation

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for efficient queries
CREATE INDEX IF NOT EXISTS idx_ocr_field_training_tenant ON ocr_field_training(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ocr_field_training_field ON ocr_field_training(field_name);
CREATE INDEX IF NOT EXISTS idx_ocr_field_training_brand ON ocr_field_training(brand_name);
CREATE INDEX IF NOT EXISTS idx_ocr_field_training_created ON ocr_field_training(created_at DESC);

-- =====================================================
-- PART 3: Create ocr_row_training table
-- =====================================================

-- Row-level training samples for comprehensive learning
CREATE TABLE IF NOT EXISTS ocr_row_training (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    session_id UUID REFERENCES ocr_sessions(id) ON DELETE SET NULL,
    batch_id UUID REFERENCES batch_ocr_sessions(id) ON DELETE SET NULL,

    -- Image reference
    image_url TEXT,
    row_number INT,

    -- Complete row data
    ocr_extracted_row JSONB,   -- Complete row as extracted by OCR/Gemini
    verified_row JSONB,        -- Human-verified complete row

    -- Accuracy metrics
    row_accuracy DECIMAL(5,2),
    field_accuracies JSONB,    -- Per-field accuracy breakdown {opening: 95, sale: 100, ...}

    -- Mathematical validation results
    math_check_results JSONB,  -- {total_valid: true, closing_valid: false, amount_valid: true, notes: "..."}

    -- Verification status
    is_verified BOOLEAN DEFAULT FALSE,
    verified_by UUID,          -- User who verified
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ocr_row_training_tenant ON ocr_row_training(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ocr_row_training_batch ON ocr_row_training(batch_id);
CREATE INDEX IF NOT EXISTS idx_ocr_row_training_verified ON ocr_row_training(is_verified);
CREATE INDEX IF NOT EXISTS idx_ocr_row_training_created ON ocr_row_training(created_at DESC);

-- =====================================================
-- PART 4: Create ocr_validation_results table
-- =====================================================

-- Store comprehensive validation results for each batch
CREATE TABLE IF NOT EXISTS ocr_validation_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    batch_id UUID REFERENCES batch_ocr_sessions(id) ON DELETE CASCADE,
    shop_id UUID,

    -- Overall metrics
    overall_status VARCHAR(50),         -- verified, mismatches, errors
    overall_accuracy DECIMAL(5,2),
    overall_confidence DECIMAL(5,2),

    -- Row counts
    total_rows INT,
    valid_rows INT,
    invalid_rows INT,

    -- Field-level accuracies
    field_accuracies JSONB,  -- {opening: 95.5, sale: 98.0, rate: 99.2, ...}

    -- Math validation summary
    math_total_checks INT,
    math_passed_checks INT,
    math_failed_checks INT,
    math_pass_rate DECIMAL(5,2),

    -- Inventory validation summary
    inventory_checks_total INT DEFAULT 0,
    inventory_checks_passed INT DEFAULT 0,
    inventory_checks_failed INT DEFAULT 0,

    -- Issues
    critical_issues_count INT DEFAULT 0,
    warnings_count INT DEFAULT 0,
    issues_json JSONB,  -- Detailed issues array

    -- Recommendation
    recommended_action VARCHAR(50),  -- approve, reject, review
    confidence_level VARCHAR(50),    -- high, medium, low
    recommendations JSONB,           -- Array of recommendation strings

    -- Timestamps
    validated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ocr_validation_tenant ON ocr_validation_results(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ocr_validation_batch ON ocr_validation_results(batch_id);
CREATE INDEX IF NOT EXISTS idx_ocr_validation_status ON ocr_validation_results(overall_status);
CREATE INDEX IF NOT EXISTS idx_ocr_validation_created ON ocr_validation_results(validated_at DESC);

-- =====================================================
-- PART 5: Create ocr_accuracy_trends table
-- =====================================================

-- Track accuracy trends over time for each field
CREATE TABLE IF NOT EXISTS ocr_accuracy_trends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,

    -- Time period
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    period_type VARCHAR(20) NOT NULL,  -- daily, weekly, monthly

    -- Field being tracked
    field_name VARCHAR(50) NOT NULL,

    -- Accuracy metrics for the period
    avg_accuracy DECIMAL(5,2),
    min_accuracy DECIMAL(5,2),
    max_accuracy DECIMAL(5,2),
    sample_count INT,

    -- Trend indicators
    trend_direction VARCHAR(20),  -- improving, stable, declining
    change_from_previous DECIMAL(5,2),  -- Percent change from previous period

    -- Projected metrics (for dashboard)
    projected_days_to_100 INT,  -- Estimated days to reach 100% accuracy

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Unique constraint for period + field combination
    UNIQUE(tenant_id, period_start, period_end, field_name)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ocr_accuracy_trends_tenant ON ocr_accuracy_trends(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ocr_accuracy_trends_field ON ocr_accuracy_trends(field_name);
CREATE INDEX IF NOT EXISTS idx_ocr_accuracy_trends_period ON ocr_accuracy_trends(period_start DESC);

-- =====================================================
-- PART 6: Add columns to ocr_items table
-- =====================================================

-- Add new columns to ocr_items for complete row data
ALTER TABLE ocr_items
ADD COLUMN IF NOT EXISTS opening_stock INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS receipt_qty INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_stock INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS sale_quantity INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS rate DECIMAL(10,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS amount DECIMAL(10,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS closing_stock INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_total_valid BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS is_closing_valid BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS is_amount_valid BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS math_validation_notes TEXT,
ADD COLUMN IF NOT EXISTS field_confidences JSONB;

-- =====================================================
-- PART 7: Add validation status to batch_ocr_sessions
-- =====================================================

ALTER TABLE batch_ocr_sessions
ADD COLUMN IF NOT EXISTS validation_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS validation_accuracy DECIMAL(5,2),
ADD COLUMN IF NOT EXISTS validation_result_id UUID REFERENCES ocr_validation_results(id) ON DELETE SET NULL;

-- =====================================================
-- PART 8: Create helper functions
-- =====================================================

-- Function to calculate field accuracy
CREATE OR REPLACE FUNCTION calculate_field_accuracy(
    ocr_value NUMERIC,
    correct_value NUMERIC
) RETURNS DECIMAL(5,2) AS $$
BEGIN
    IF correct_value = 0 THEN
        IF ocr_value = 0 THEN
            RETURN 100.0;
        ELSE
            RETURN 0.0;
        END IF;
    END IF;

    RETURN GREATEST(0, 100 - (ABS(ocr_value - correct_value) / correct_value * 100));
END;
$$ LANGUAGE plpgsql;

-- Function to update accuracy metrics after learning
CREATE OR REPLACE FUNCTION update_tenant_accuracy_metrics(
    p_tenant_id UUID
) RETURNS VOID AS $$
DECLARE
    v_total_samples INT;
    v_field_record RECORD;
BEGIN
    -- Calculate averages for each field from training data
    FOR v_field_record IN
        SELECT
            field_name,
            AVG(accuracy_score) as avg_accuracy,
            COUNT(*) as sample_count
        FROM ocr_field_training
        WHERE tenant_id = p_tenant_id
          AND created_at > NOW() - INTERVAL '30 days'
        GROUP BY field_name
    LOOP
        -- Update the appropriate column in ocr_accuracy_metrics
        UPDATE ocr_accuracy_metrics
        SET
            avg_opening_accuracy = CASE WHEN v_field_record.field_name = 'opening' THEN v_field_record.avg_accuracy ELSE avg_opening_accuracy END,
            avg_receipt_accuracy = CASE WHEN v_field_record.field_name = 'receipt' THEN v_field_record.avg_accuracy ELSE avg_receipt_accuracy END,
            avg_total_accuracy = CASE WHEN v_field_record.field_name = 'total' THEN v_field_record.avg_accuracy ELSE avg_total_accuracy END,
            avg_sale_accuracy = CASE WHEN v_field_record.field_name = 'sale' THEN v_field_record.avg_accuracy ELSE avg_sale_accuracy END,
            avg_rate_accuracy = CASE WHEN v_field_record.field_name = 'rate' THEN v_field_record.avg_accuracy ELSE avg_rate_accuracy END,
            avg_amount_accuracy = CASE WHEN v_field_record.field_name = 'amount' THEN v_field_record.avg_accuracy ELSE avg_amount_accuracy END,
            avg_closing_accuracy = CASE WHEN v_field_record.field_name = 'closing' THEN v_field_record.avg_accuracy ELSE avg_closing_accuracy END,
            updated_at = NOW()
        WHERE tenant_id = p_tenant_id;
    END LOOP;

    -- Calculate row-level accuracy
    UPDATE ocr_accuracy_metrics
    SET avg_row_accuracy = (
        SELECT AVG(row_accuracy)
        FROM ocr_row_training
        WHERE tenant_id = p_tenant_id
          AND is_verified = TRUE
          AND created_at > NOW() - INTERVAL '30 days'
    ),
    updated_at = NOW()
    WHERE tenant_id = p_tenant_id;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- PART 9: Create view for accuracy dashboard
-- =====================================================

CREATE OR REPLACE VIEW ocr_accuracy_dashboard AS
SELECT
    m.tenant_id,
    m.avg_brand_accuracy,
    m.avg_quantity_accuracy,
    m.avg_price_accuracy,
    m.avg_opening_accuracy,
    m.avg_receipt_accuracy,
    m.avg_total_accuracy,
    m.avg_sale_accuracy,
    m.avg_rate_accuracy,
    m.avg_amount_accuracy,
    m.avg_closing_accuracy,
    m.avg_row_accuracy,
    m.avg_math_accuracy,
    m.total_corrections,
    m.total_math_checks,
    m.passed_math_checks,
    m.failed_math_checks,
    CASE
        WHEN m.total_math_checks > 0
        THEN ROUND((m.passed_math_checks::DECIMAL / m.total_math_checks) * 100, 2)
        ELSE 0
    END as math_pass_rate,
    m.updated_at,
    -- Calculate overall accuracy (average of all field accuracies)
    ROUND((
        COALESCE(m.avg_brand_accuracy, 0) +
        COALESCE(m.avg_opening_accuracy, 0) +
        COALESCE(m.avg_receipt_accuracy, 0) +
        COALESCE(m.avg_total_accuracy, 0) +
        COALESCE(m.avg_sale_accuracy, 0) +
        COALESCE(m.avg_rate_accuracy, 0) +
        COALESCE(m.avg_amount_accuracy, 0) +
        COALESCE(m.avg_closing_accuracy, 0)
    ) / 8, 2) as overall_accuracy
FROM ocr_accuracy_metrics m;

-- =====================================================
-- COMMENTS
-- =====================================================

COMMENT ON TABLE ocr_field_training IS 'Stores per-field training samples for OCR learning system';
COMMENT ON TABLE ocr_row_training IS 'Stores complete row training samples with field-level accuracy';
COMMENT ON TABLE ocr_validation_results IS 'Stores comprehensive validation results for each batch';
COMMENT ON TABLE ocr_accuracy_trends IS 'Tracks accuracy trends over time for dashboards and predictions';

COMMENT ON COLUMN ocr_items.opening_stock IS 'Opening stock - stock at start of day';
COMMENT ON COLUMN ocr_items.receipt_qty IS 'Receipt quantity - new stock received during day';
COMMENT ON COLUMN ocr_items.total_stock IS 'Total stock - should equal Opening + Receipt';
COMMENT ON COLUMN ocr_items.sale_quantity IS 'Sale quantity - number of bottles sold';
COMMENT ON COLUMN ocr_items.rate IS 'Rate/selling price per bottle in rupees';
COMMENT ON COLUMN ocr_items.amount IS 'Total amount - should equal Sale × Rate';
COMMENT ON COLUMN ocr_items.closing_stock IS 'Closing stock - should equal Total - Sale';
COMMENT ON COLUMN ocr_items.is_total_valid IS 'TRUE if Total = Opening + Receipt';
COMMENT ON COLUMN ocr_items.is_closing_valid IS 'TRUE if Closing = Total - Sale';
COMMENT ON COLUMN ocr_items.is_amount_valid IS 'TRUE if Amount = Sale × Rate';
