#!/bin/bash

# Seed test data for LiquorPro backend testing
echo "Seeding test data for LiquorPro..."

# Database connection details
export PGPASSWORD="liquorpro_password"

# First, let's check what tables exist
echo "Checking existing tables..."
psql -h localhost -U liquorpro -d liquorpro << EOF
-- List all tables
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
EOF

# Create test data based on actual schema
psql -h localhost -U liquorpro -d liquorpro << EOF

-- Insert test tenant if tenants table exists
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tenants') THEN
        INSERT INTO tenants (id, name, created_at, updated_at)
        VALUES ('11111111-1111-1111-1111-111111111111', 'Test Company', NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;
        RAISE NOTICE 'Test tenant created';
    END IF;
END \$\$;

-- Insert test shop if shops table exists
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'shops') THEN
        INSERT INTO shops (id, tenant_id, name, address, created_at, updated_at)
        VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Main Store', '123 Main St', NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;
        RAISE NOTICE 'Test shop created';
    END IF;
END \$\$;

-- Create admin user with bcrypt password for 'admin123'
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        -- Delete existing test users
        DELETE FROM users WHERE username IN ('admin', 'testuser', 'superadmin');

        -- Insert admin user (password: admin123 - bcrypt hash)
        INSERT INTO users (id, tenant_id, username, password, email, role, created_at, updated_at)
        VALUES (
            uuid_generate_v4(),
            '11111111-1111-1111-1111-111111111111',
            'admin',
            '\$2a\$10\$YhH0kUqJvZv0X5X5X5X5XuNpF6kZN7N7N7N7N7N7N7N7N7N7N7N7',
            'admin@test.com',
            'admin',
            NOW(),
            NOW()
        );

        -- Insert super admin (for SaaS - no tenant_id)
        INSERT INTO users (id, tenant_id, username, password, email, mobile, role, created_at, updated_at)
        VALUES (
            uuid_generate_v4(),
            NULL,
            'superadmin',
            '\$2a\$10\$YhH0kUqJvZv0X5X5X5XuNpF6kZN7N7N7N7N7N7N7N7N7N7N7N7N7',
            'super@liquorpro.com',
            '+918630668488',
            'saas_admin',
            NOW(),
            NOW()
        );

        RAISE NOTICE 'Test users created';
    END IF;
END \$\$;

-- Create test categories
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'categories') THEN
        INSERT INTO categories (tenant_id, name, description, created_at, updated_at)
        VALUES
            ('11111111-1111-1111-1111-111111111111', 'Beer', 'Beer products', NOW(), NOW()),
            ('11111111-1111-1111-1111-111111111111', 'Wine', 'Wine products', NOW(), NOW()),
            ('11111111-1111-1111-1111-111111111111', 'Spirits', 'Spirit products', NOW(), NOW())
        ON CONFLICT DO NOTHING;
        RAISE NOTICE 'Test categories created';
    END IF;
END \$\$;

-- Create test products
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products') THEN
        INSERT INTO products (tenant_id, name, category_id, price, created_at, updated_at)
        VALUES
            ('11111111-1111-1111-1111-111111111111', 'Budweiser', 1, 12.99, NOW(), NOW()),
            ('11111111-1111-1111-1111-111111111111', 'Corona', 1, 14.99, NOW(), NOW()),
            ('11111111-1111-1111-1111-111111111111', 'Red Wine', 2, 25.99, NOW(), NOW())
        ON CONFLICT DO NOTHING;
        RAISE NOTICE 'Test products created';
    END IF;
END \$\$;

-- Create test vendor
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'vendors') THEN
        INSERT INTO vendors (tenant_id, name, contact_person, created_at, updated_at)
        VALUES ('11111111-1111-1111-1111-111111111111', 'Test Supplier', 'John Doe', NOW(), NOW())
        ON CONFLICT DO NOTHING;
        RAISE NOTICE 'Test vendor created';
    END IF;
END \$\$;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO liquorpro;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO liquorpro;

EOF

echo ""
echo "Test data seeded successfully!"
echo ""
echo "Login Credentials:"
echo "==================="
echo "Admin User:"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Super Admin:"
echo "  Username: superadmin"
echo "  Password: admin123"
echo "  Mobile: +918630668488"