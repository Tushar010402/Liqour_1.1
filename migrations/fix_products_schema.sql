-- Fix Products Table Schema
-- Add missing columns: brand_id, category_id, subcategory_id, description

-- Add brand_id column
ALTER TABLE products
ADD COLUMN IF NOT EXISTS brand_id UUID;

-- Add category_id column
ALTER TABLE products
ADD COLUMN IF NOT EXISTS category_id UUID;

-- Add subcategory_id column
ALTER TABLE products
ADD COLUMN IF NOT EXISTS subcategory_id UUID;

-- Add description column
ALTER TABLE products
ADD COLUMN IF NOT EXISTS description TEXT;

-- Create indexes for foreign keys
CREATE INDEX IF NOT EXISTS idx_products_brand_id ON products(brand_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_subcategory_id ON products(subcategory_id);

-- Update existing products to have a default category/brand if they don't have one
-- (This ensures data integrity for existing records)
