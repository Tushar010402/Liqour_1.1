-- Migration: Create subcategories table
-- Purpose: Add subcategories support for product classification (Normal, Premium, Limited Edition, etc.)
-- Author: Claude Code
-- Date: 2025-11-14

-- Create subcategories table
CREATE TABLE IF NOT EXISTS subcategories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    category_id UUID NOT NULL REFERENCES categories(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price_range VARCHAR(100), -- Premium, Ultra Premium, Normal, Basic, Limited Edition
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_subcategories_tenant_id ON subcategories(tenant_id);
CREATE INDEX IF NOT EXISTS idx_subcategories_category_id ON subcategories(category_id);
CREATE INDEX IF NOT EXISTS idx_subcategories_deleted_at ON subcategories(deleted_at);
CREATE INDEX IF NOT EXISTS idx_subcategories_name ON subcategories(name);

-- Add unique constraint for tenant + category + name
CREATE UNIQUE INDEX IF NOT EXISTS idx_subcategories_tenant_category_name
ON subcategories(tenant_id, category_id, name) WHERE deleted_at IS NULL;

-- Add foreign key constraint to ocr_items table
ALTER TABLE ocr_items
DROP CONSTRAINT IF EXISTS ocr_items_inferred_subcategory_id_fkey;

ALTER TABLE ocr_items
ADD CONSTRAINT ocr_items_inferred_subcategory_id_fkey
FOREIGN KEY (inferred_subcategory_id) REFERENCES subcategories(id);

-- Add comments
COMMENT ON TABLE subcategories IS 'Product subcategories for finer classification (e.g., Premium, Normal, Limited Edition)';
COMMENT ON COLUMN subcategories.price_range IS 'Price tier: Premium, Ultra Premium, Normal, Basic, Limited Edition';
