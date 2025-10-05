-- Essential tables for LiquorPro

-- Sales table (missing and causing gateway errors)
CREATE TABLE IF NOT EXISTS sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID,
    shop_id UUID,
    salesman_id UUID,
    sale_date TIMESTAMP,
    total_amount DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Rate limit tables (missing)
CREATE TABLE IF NOT EXISTS rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    max_attempts INTEGER NOT NULL DEFAULT 10,
    time_window_secs INTEGER NOT NULL DEFAULT 600,
    block_duration_secs INTEGER NOT NULL DEFAULT 1800,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS rate_limit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_limit_name VARCHAR(255),
    identifier VARCHAR(255),
    attempt_count INTEGER DEFAULT 1,
    is_blocked BOOLEAN DEFAULT false,
    blocked_until TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Categories for inventory
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    tenant_id UUID,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Brands for inventory
CREATE TABLE IF NOT EXISTS brands (
    id SERIAL PRIMARY KEY,
    tenant_id UUID,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Product templates
CREATE TABLE IF NOT EXISTS product_templates (
    id SERIAL PRIMARY KEY,
    tenant_id UUID,
    category_id INTEGER REFERENCES categories(id),
    brand_id INTEGER REFERENCES brands(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(sale_date);
CREATE INDEX IF NOT EXISTS idx_tenant_shops ON shops(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users ON users(tenant_id);

-- Insert some sample rate limits
INSERT INTO rate_limits (name, description, max_attempts, time_window_secs, block_duration_secs, is_active) 
VALUES 
('login_attempts', 'Login attempt rate limiting', 5, 900, 1800, true),
('otp_requests', 'OTP request rate limiting', 3, 300, 600, true),
('api_calls', 'General API rate limiting', 100, 60, 300, true),
('password_reset', 'Password reset rate limiting', 3, 1800, 3600, true),
('registration', 'User registration rate limiting', 3, 600, 1800, true)
ON CONFLICT (name) DO NOTHING;

-- Insert sample tenants
INSERT INTO tenants (id, name, domain, is_active, created_at, updated_at) 
VALUES 
('373e965a-6dec-44d6-a2ab-0400449fc71d', 'LiquorPro Demo', 'demo.liquorpro.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('b1234567-89ab-cdef-0123-456789abcdef', 'ABC Liquor Store', 'abc.liquorpro.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('c2345678-9abc-def0-1234-56789abcdef0', 'XYZ Wine Shop', 'xyz.liquorpro.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('d3456789-abcd-ef01-2345-6789abcdef01', 'Premium Spirits', 'premium.liquorpro.com', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('e4567890-bcde-f012-3456-789abcdef012', 'Local Liquor', 'local.liquorpro.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO NOTHING;

-- Add SaaS admin user
INSERT INTO users (id, tenant_id, first_name, last_name, email, mobile, password_hash, role, is_active, created_at, updated_at) 
VALUES 
('saas-admin-001', NULL, 'SaaS', 'Admin', 'admin@liquorpro.com', '+918630668488', '$2a$10$example.hash.for.password123', 'saas_admin', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('user-demo-001', '373e965a-6dec-44d6-a2ab-0400449fc71d', 'Demo', 'User', 'demo@liquorpro.com', '+918630668489', '$2a$10$example.hash.for.password123', 'admin', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO NOTHING;

-- Success message
SELECT 'Database tables created and sample data inserted successfully!' as status;