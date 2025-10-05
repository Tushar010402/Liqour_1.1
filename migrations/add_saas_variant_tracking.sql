-- Add columns to track SaaS brand origin in products table
-- This prevents duplicate onboarding of the same SaaS brand variants

ALTER TABLE products
ADD COLUMN IF NOT EXISTS saas_brand_id UUID,
ADD COLUMN IF NOT EXISTS saas_variant_id UUID;

-- Create index for faster lookups when checking duplicates
CREATE INDEX IF NOT EXISTS idx_products_saas_variant
ON products(tenant_id, saas_variant_id)
WHERE saas_variant_id IS NOT NULL;

-- Add unique constraint to prevent duplicate SaaS variant onboarding per tenant
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_tenant_saas_variant_unique
ON products(tenant_id, saas_variant_id)
WHERE saas_variant_id IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN products.saas_brand_id IS 'Reference to original SaaS brand template ID if product was onboarded from SaaS catalog';
COMMENT ON COLUMN products.saas_variant_id IS 'Reference to original SaaS brand variant ID if product was onboarded from SaaS catalog';
