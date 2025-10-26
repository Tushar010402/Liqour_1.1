-- Migration: Add OCR Quick Sale Support Tables
-- Date: 2025-01-16
-- Description: Add tables for OCR-based quick sale feature with receipt scanning

-- 1. OCR Sessions table - tracks each OCR processing request
CREATE TABLE IF NOT EXISTS ocr_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Image information
    image_url TEXT NOT NULL,
    image_size INTEGER NOT NULL, -- in bytes
    image_type VARCHAR(50) NOT NULL, -- jpeg, png, etc

    -- OCR processing status
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed, expired
    ocr_provider VARCHAR(50) DEFAULT 'google_vision', -- for future multi-provider support

    -- Extracted text and metadata
    raw_text TEXT, -- Full extracted text from OCR
    processed_at TIMESTAMPTZ,
    error_message TEXT,

    -- Processing metrics
    confidence_score DECIMAL(5,2), -- Overall OCR confidence 0-100
    processing_time_ms INTEGER, -- Time taken for OCR processing

    -- Receipt metadata (if extractable)
    receipt_date DATE,
    receipt_number VARCHAR(100),
    vendor_name VARCHAR(255),
    total_amount DECIMAL(10,2),

    -- Session metadata
    session_type VARCHAR(50) DEFAULT 'quick_sale', -- quick_sale, inventory_check, etc
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT ocr_sessions_status_check CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'expired'))
);

-- 2. OCR Extracted Items table - items parsed from OCR text
CREATE TABLE IF NOT EXISTS ocr_extracted_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES ocr_sessions(id) ON DELETE CASCADE,

    -- Extracted product information
    extracted_text VARCHAR(500) NOT NULL, -- Raw extracted product line
    brand_text VARCHAR(255), -- Extracted brand name
    size_text VARCHAR(100), -- Extracted size/volume
    quantity_text VARCHAR(50), -- Extracted quantity
    price_text VARCHAR(50), -- Extracted price (if available)

    -- Parsed values
    parsed_quantity INTEGER,
    parsed_price DECIMAL(10,2),
    parsed_size VARCHAR(50),

    -- Matching results
    matched_product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    matched_brand_id UUID REFERENCES saas_brands(id) ON DELETE SET NULL,
    matched_variant_id UUID REFERENCES saas_brand_variants(id) ON DELETE SET NULL,

    -- Matching confidence and method
    match_confidence DECIMAL(5,2) NOT NULL DEFAULT 0, -- 0-100 confidence score
    match_method VARCHAR(50), -- exact, fuzzy, alias, pattern, manual
    match_details JSONB, -- Additional matching metadata

    -- User corrections
    is_confirmed BOOLEAN DEFAULT FALSE,
    is_rejected BOOLEAN DEFAULT FALSE,
    user_corrected_product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    user_corrected_quantity INTEGER,
    correction_reason TEXT,

    -- Item position in receipt
    line_number INTEGER,
    bounding_box JSONB, -- OCR bounding box coordinates

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Brand Aliases table - for better OCR matching
CREATE TABLE IF NOT EXISTS brand_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    brand_id UUID NOT NULL REFERENCES saas_brands(id) ON DELETE CASCADE,

    alias_text VARCHAR(255) NOT NULL, -- The alias text
    alias_type VARCHAR(50) NOT NULL DEFAULT 'abbreviation', -- abbreviation, typo, colloquial, ocr_common

    -- Usage tracking
    match_count INTEGER DEFAULT 0, -- How many times this alias was used
    last_matched_at TIMESTAMPTZ,

    -- Management
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT brand_aliases_unique UNIQUE (tenant_id, brand_id, alias_text),
    CONSTRAINT brand_aliases_type_check CHECK (alias_type IN ('abbreviation', 'typo', 'colloquial', 'ocr_common'))
);

-- 4. Size Patterns table - for size extraction and normalization
CREATE TABLE IF NOT EXISTS size_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID REFERENCES saas_categories(id) ON DELETE CASCADE,
    subcategory_id UUID REFERENCES saas_subcategories(id) ON DELETE CASCADE,

    -- Pattern information
    pattern_regex TEXT NOT NULL, -- Regex pattern for matching
    normalized_size VARCHAR(50) NOT NULL, -- Normalized size value
    size_ml INTEGER, -- Size in ML for liquor products

    -- Pattern metadata
    pattern_type VARCHAR(50) NOT NULL DEFAULT 'standard', -- standard, regional, brand_specific
    priority INTEGER DEFAULT 100, -- Higher priority patterns are checked first

    -- Usage tracking
    match_count INTEGER DEFAULT 0,
    last_matched_at TIMESTAMPTZ,

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT size_patterns_type_check CHECK (pattern_type IN ('standard', 'regional', 'brand_specific'))
);

-- 5. OCR Learning Feedback table - for improving matching over time
CREATE TABLE IF NOT EXISTS ocr_learning_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    extracted_item_id UUID NOT NULL REFERENCES ocr_extracted_items(id) ON DELETE CASCADE,

    -- Feedback details
    feedback_type VARCHAR(50) NOT NULL, -- correct_match, wrong_match, missing_product, wrong_quantity
    correct_product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    correct_quantity INTEGER,

    -- Learning metadata
    original_confidence DECIMAL(5,2),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT ocr_feedback_type_check CHECK (feedback_type IN ('correct_match', 'wrong_match', 'missing_product', 'wrong_quantity'))
);

-- Indexes for performance
CREATE INDEX idx_ocr_sessions_tenant_id ON ocr_sessions(tenant_id);
CREATE INDEX idx_ocr_sessions_user_id ON ocr_sessions(user_id);
CREATE INDEX idx_ocr_sessions_shop_id ON ocr_sessions(shop_id);
CREATE INDEX idx_ocr_sessions_status ON ocr_sessions(status);
CREATE INDEX idx_ocr_sessions_created_at ON ocr_sessions(created_at DESC);

CREATE INDEX idx_ocr_extracted_items_session_id ON ocr_extracted_items(session_id);
CREATE INDEX idx_ocr_extracted_items_matched_product_id ON ocr_extracted_items(matched_product_id);
CREATE INDEX idx_ocr_extracted_items_match_confidence ON ocr_extracted_items(match_confidence);

CREATE INDEX idx_brand_aliases_tenant_id ON brand_aliases(tenant_id);
CREATE INDEX idx_brand_aliases_brand_id ON brand_aliases(brand_id);
CREATE INDEX idx_brand_aliases_alias_text ON brand_aliases(alias_text);

CREATE INDEX idx_size_patterns_category_id ON size_patterns(category_id);
CREATE INDEX idx_size_patterns_subcategory_id ON size_patterns(subcategory_id);
CREATE INDEX idx_size_patterns_priority ON size_patterns(priority DESC);

CREATE INDEX idx_ocr_learning_feedback_tenant_id ON ocr_learning_feedback(tenant_id);
CREATE INDEX idx_ocr_learning_feedback_extracted_item_id ON ocr_learning_feedback(extracted_item_id);

-- Insert some common size patterns for liquor products
INSERT INTO size_patterns (pattern_regex, normalized_size, size_ml, pattern_type, priority) VALUES
    -- Standard ML patterns
    ('(\d+)\s*ml', '$1ml', NULL, 'standard', 100),
    ('(\d+)\s*ML', '$1ml', NULL, 'standard', 100),
    ('(\d+)\s*mL', '$1ml', NULL, 'standard', 100),

    -- Liter patterns
    ('(\d+(?:\.\d+)?)\s*l\b', '$1L', NULL, 'standard', 90),
    ('(\d+(?:\.\d+)?)\s*L\b', '$1L', NULL, 'standard', 90),
    ('(\d+(?:\.\d+)?)\s*ltr', '$1L', NULL, 'standard', 90),
    ('(\d+(?:\.\d+)?)\s*LTR', '$1L', NULL, 'standard', 90),

    -- Common liquor sizes
    ('180\s*ml', '180ml', 180, 'standard', 100),
    ('375\s*ml', '375ml', 375, 'standard', 100),
    ('750\s*ml', '750ml', 750, 'standard', 100),
    ('1000\s*ml', '1L', 1000, 'standard', 100),

    -- Nip/Quarter/Half patterns
    ('nip', '180ml', 180, 'colloquial', 80),
    ('quarter', '180ml', 180, 'colloquial', 80),
    ('half', '375ml', 375, 'colloquial', 80),
    ('full', '750ml', 750, 'colloquial', 80),

    -- Pint patterns
    ('pint', '375ml', 375, 'regional', 85),
    ('PINT', '375ml', 375, 'regional', 85)
ON CONFLICT DO NOTHING;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_ocr_sessions_updated_at BEFORE UPDATE ON ocr_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_ocr_extracted_items_updated_at BEFORE UPDATE ON ocr_extracted_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_brand_aliases_updated_at BEFORE UPDATE ON brand_aliases
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_size_patterns_updated_at BEFORE UPDATE ON size_patterns
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();