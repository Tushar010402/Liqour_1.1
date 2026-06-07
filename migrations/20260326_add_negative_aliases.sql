-- Negative aliases: records rejected matches so they're never suggested again
-- E.g., "SMITH Rum" should NOT match "Old Monk The Legend Rum"
CREATE TABLE IF NOT EXISTS ocr_negative_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    alias_name VARCHAR(255) NOT NULL,
    rejected_product_id UUID NOT NULL,
    occurrence_count INT DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tenant_id, alias_name, rejected_product_id)
);

CREATE INDEX IF NOT EXISTS idx_negative_aliases_lookup
ON ocr_negative_aliases(tenant_id, LOWER(alias_name));
