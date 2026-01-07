-- Create batch_ocr_sessions table
CREATE TABLE IF NOT EXISTS batch_ocr_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    session_type VARCHAR(50) NOT NULL, -- stock_initialization, sale_entry, etc.
    status VARCHAR(20) NOT NULL DEFAULT 'processing', -- processing, completed, failed
    current_stage VARCHAR(50) NOT NULL DEFAULT 'vision_api', -- vision_api, gemini_extraction, item_matching, completed
    progress DECIMAL(5,2) DEFAULT 0.0, -- 0.00 to 100.00
    total_images INTEGER DEFAULT 0,
    processed_images INTEGER DEFAULT 0,
    total_items INTEGER DEFAULT 0,
    receipt_type VARCHAR(100),
    session_ids TEXT[], -- Array of individual OCR session IDs
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    CONSTRAINT batch_ocr_sessions_tenant_fk FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT batch_ocr_sessions_shop_fk FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
);

-- Create ocr_sessions table (individual image sessions)
CREATE TABLE IF NOT EXISTS ocr_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID NOT NULL REFERENCES batch_ocr_sessions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    image_url TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'processing',
    raw_text TEXT, -- Raw text extracted by Vision API
    receipt_type VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    CONSTRAINT ocr_sessions_batch_fk FOREIGN KEY (batch_id) REFERENCES batch_ocr_sessions(id) ON DELETE CASCADE,
    CONSTRAINT ocr_sessions_tenant_fk FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT ocr_sessions_shop_fk FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
);

-- Create ocr_items table (extracted items from OCR)
CREATE TABLE IF NOT EXISTS ocr_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES ocr_sessions(id) ON DELETE CASCADE,
    batch_id UUID NOT NULL REFERENCES batch_ocr_sessions(id) ON DELETE CASCADE,
    row_number INTEGER NOT NULL, -- Serial number from invoice
    brand_text VARCHAR(255) NOT NULL, -- Original OCR text
    normalized_brand_name VARCHAR(255), -- Gemini-normalized brand name
    size_text VARCHAR(50), -- e.g., 750ml, 1L
    quantity INTEGER DEFAULT 0,
    selling_price DECIMAL(10,2),
    matched_brand_id UUID REFERENCES brands(id) ON DELETE SET NULL,
    matched_variant_id UUID, -- For future variant matching
    match_confidence DECIMAL(5,2), -- 0.00 to 100.00
    match_strategy VARCHAR(50), -- gemini_smart, exact, fuzzy, manual
    user_selected_brand_id UUID REFERENCES brands(id) ON DELETE SET NULL,
    is_reviewed BOOLEAN DEFAULT FALSE,
    is_selected BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ocr_items_session_fk FOREIGN KEY (session_id) REFERENCES ocr_sessions(id) ON DELETE CASCADE,
    CONSTRAINT ocr_items_batch_fk FOREIGN KEY (batch_id) REFERENCES batch_ocr_sessions(id) ON DELETE CASCADE
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_batch_ocr_sessions_tenant ON batch_ocr_sessions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_batch_ocr_sessions_shop ON batch_ocr_sessions(shop_id);
CREATE INDEX IF NOT EXISTS idx_batch_ocr_sessions_status ON batch_ocr_sessions(status);
CREATE INDEX IF NOT EXISTS idx_batch_ocr_sessions_created ON batch_ocr_sessions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ocr_sessions_batch ON ocr_sessions(batch_id);
CREATE INDEX IF NOT EXISTS idx_ocr_sessions_tenant ON ocr_sessions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ocr_sessions_shop ON ocr_sessions(shop_id);

CREATE INDEX IF NOT EXISTS idx_ocr_items_session ON ocr_items(session_id);
CREATE INDEX IF NOT EXISTS idx_ocr_items_batch ON ocr_items(batch_id);
CREATE INDEX IF NOT EXISTS idx_ocr_items_brand ON ocr_items(matched_brand_id);
CREATE INDEX IF NOT EXISTS idx_ocr_items_row ON ocr_items(row_number);

-- Add comments
COMMENT ON TABLE batch_ocr_sessions IS 'Stores batch OCR processing sessions for multiple images';
COMMENT ON TABLE ocr_sessions IS 'Stores individual image OCR processing sessions';
COMMENT ON TABLE ocr_items IS 'Stores extracted items from OCR with Gemini AI normalization and matching';

COMMENT ON COLUMN ocr_items.normalized_brand_name IS 'Brand name normalized by Gemini AI (cleaned OCR errors, standardized format)';
COMMENT ON COLUMN ocr_items.match_strategy IS 'How the brand was matched: gemini_smart (AI-based), exact (exact match), fuzzy (fuzzy match), manual (user selection)';
COMMENT ON COLUMN ocr_items.match_confidence IS 'Confidence score from Gemini AI matching (0-100)';
