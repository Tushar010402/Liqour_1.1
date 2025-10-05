-- Fix missing columns and tables for LiquorPro

-- Add missing columns to tenants table
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS domain VARCHAR(255);
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS subscribed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP;

-- Add missing columns to rate_limit_logs table  
ALTER TABLE rate_limit_logs ADD COLUMN IF NOT EXISTS request_ip VARCHAR(45);
ALTER TABLE rate_limit_logs ADD COLUMN IF NOT EXISTS user_agent TEXT;

-- Add missing columns to rate_limits table
ALTER TABLE rate_limits ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 1;
ALTER TABLE rate_limits ADD COLUMN IF NOT EXISTS is_global BOOLEAN DEFAULT false;

-- Create missing stocks table (critical for gateway)
CREATE TABLE IF NOT EXISTS stocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id),
    shop_id UUID REFERENCES shops(id),
    product_id INTEGER,
    quantity INTEGER DEFAULT 0,
    reserved_quantity INTEGER DEFAULT 0,
    minimum_stock INTEGER DEFAULT 0,
    maximum_stock INTEGER DEFAULT 0,
    cost_price DECIMAL(10,2),
    selling_price DECIMAL(10,2),
    batch_number VARCHAR(255),
    expiry_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create missing products table 
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    template_id INTEGER REFERENCES product_templates(id),
    shop_id UUID REFERENCES shops(id),
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100),
    barcode VARCHAR(100),
    size VARCHAR(50),
    alcohol_content DECIMAL(5,2),
    cost_price DECIMAL(10,2),
    selling_price DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create missing subcategories table
CREATE TABLE IF NOT EXISTS subcategories (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    category_id INTEGER REFERENCES categories(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create stock_history table
CREATE TABLE IF NOT EXISTS stock_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id),
    stock_id UUID REFERENCES stocks(id),
    transaction_type VARCHAR(50),
    quantity_change INTEGER,
    reference_id UUID,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Update domains for existing tenants
UPDATE tenants SET domain = 'demo.liquorpro.com' WHERE name = 'LiquorPro Demo';
UPDATE tenants SET domain = 'abc.liquorpro.com' WHERE name = 'ABC Liquor Store';
UPDATE tenants SET domain = 'xyz.liquorpro.com' WHERE name = 'XYZ Wine Shop';
UPDATE tenants SET domain = 'premium.liquorpro.com' WHERE name = 'Premium Spirits';
UPDATE tenants SET domain = 'local.liquorpro.com' WHERE name = 'Local Liquor';

-- Update rate limits with priority and global settings
UPDATE rate_limits SET priority = 1, is_global = true WHERE name = 'login_attempts';
UPDATE rate_limits SET priority = 2, is_global = true WHERE name = 'otp_requests';
UPDATE rate_limits SET priority = 3, is_global = true WHERE name = 'api_calls';
UPDATE rate_limits SET priority = 4, is_global = true WHERE name = 'password_reset';
UPDATE rate_limits SET priority = 5, is_global = true WHERE name = 'registration';

-- Create additional indexes for performance
CREATE INDEX IF NOT EXISTS idx_stock_shop_product ON stocks(shop_id, product_id);
CREATE INDEX IF NOT EXISTS idx_stock_tenant ON stocks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_products_tenant ON products(tenant_id);
CREATE INDEX IF NOT EXISTS idx_products_shop ON products(shop_id);

-- Success message
SELECT 'Database schema fixed successfully!' as status;