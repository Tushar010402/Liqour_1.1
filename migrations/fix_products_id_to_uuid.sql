-- Fix Products Table ID from INTEGER to UUID
-- This migration converts the products table to use UUID primary keys

-- Step 1: Create a new products table with UUID
CREATE TABLE IF NOT EXISTS products_new (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    shop_id UUID,
    template_id INTEGER,
    name TEXT NOT NULL,
    sku VARCHAR(255),
    barcode VARCHAR(255),
    brand_id UUID,
    category_id UUID,
    subcategory_id UUID,
    size VARCHAR(50),
    alcohol_content NUMERIC(5,2),
    description TEXT,
    cost_price NUMERIC(10,2),
    selling_price NUMERIC(10,2),
    saas_brand_id UUID,
    saas_variant_id UUID,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Step 2: Copy data from old table to new table (generate new UUIDs)
INSERT INTO products_new (
    tenant_id, shop_id, template_id,
    name, sku, barcode,
    brand_id, category_id, subcategory_id,
    size, alcohol_content, description,
    cost_price, selling_price,
    saas_brand_id, saas_variant_id,
    is_active, created_at, updated_at, deleted_at
)
SELECT
    tenant_id, shop_id, template_id,
    name, sku, barcode,
    brand_id, category_id, subcategory_id,
    size, alcohol_content, description,
    cost_price, selling_price,
    saas_brand_id, saas_variant_id,
    is_active, created_at, updated_at, deleted_at
FROM products
WHERE deleted_at IS NULL;

-- Step 3: Drop old table
DROP TABLE products;

-- Step 4: Rename new table
ALTER TABLE products_new RENAME TO products;

-- Step 5: Recreate indexes
CREATE INDEX IF NOT EXISTS idx_products_tenant_id ON products(tenant_id);
CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_brand_id ON products(brand_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_subcategory_id ON products(subcategory_id);
CREATE INDEX IF NOT EXISTS idx_products_saas_variant ON products(tenant_id, saas_variant_id) WHERE saas_variant_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_tenant_saas_variant_unique ON products(tenant_id, saas_variant_id) WHERE saas_variant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_deleted_at ON products(deleted_at);

-- Verify the new structure
\d products
