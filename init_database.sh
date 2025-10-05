#!/bin/bash

# Database initialization script for LiquorPro
echo "Initializing LiquorPro Database..."

# Database connection details
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="liquorpro"
DB_USER="liquorpro"
DB_PASS="liquorpro_password"

# Export password to avoid prompt
export PGPASSWORD="$DB_PASS"

# Run migrations using the migrate tool
echo "Running database migrations..."

# First, let's create the necessary tables using Go migrations
cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor

# Run the migrate command to create tables
go run cmd/migrate/main.go

# Create a super admin user for testing
echo "Creating test users..."

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << EOF
-- Create tenants table if not exists
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    subscription_plan VARCHAR(50) DEFAULT 'basic',
    subscription_status VARCHAR(50) DEFAULT 'active',
    subscription_start_date TIMESTAMP,
    subscription_end_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create shops table if not exists
CREATE TABLE IF NOT EXISTS shops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id),
    name VARCHAR(255) NOT NULL,
    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create users table if not exists
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id),
    shop_id UUID REFERENCES shops(id),
    username VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    mobile VARCHAR(20),
    role VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    parent_id INTEGER REFERENCES categories(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    name VARCHAR(255) NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    brand VARCHAR(255),
    price DECIMAL(10,2),
    cost DECIMAL(10,2),
    barcode VARCHAR(255),
    sku VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create stocks table
CREATE TABLE IF NOT EXISTS stocks (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    shop_id UUID REFERENCES shops(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER DEFAULT 0,
    min_quantity INTEGER DEFAULT 10,
    max_quantity INTEGER DEFAULT 1000,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create daily_sales_records table
CREATE TABLE IF NOT EXISTS daily_sales_records (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    shop_id UUID REFERENCES shops(id),
    date DATE NOT NULL,
    total_amount DECIMAL(10,2),
    status VARCHAR(50) DEFAULT 'pending',
    created_by UUID REFERENCES users(id),
    approved_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create sales table
CREATE TABLE IF NOT EXISTS sales (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    shop_id UUID REFERENCES shops(id),
    customer_name VARCHAR(255),
    customer_phone VARCHAR(20),
    total DECIMAL(10,2),
    payment_method VARCHAR(50),
    status VARCHAR(50) DEFAULT 'completed',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create vendors table
CREATE TABLE IF NOT EXISTS vendors (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    name VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    mobile VARCHAR(20),
    email VARCHAR(255),
    address TEXT,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create expenses table
CREATE TABLE IF NOT EXISTS expenses (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    vendor_id INTEGER REFERENCES vendors(id),
    amount DECIMAL(10,2) NOT NULL,
    category VARCHAR(100),
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    created_by UUID REFERENCES users(id),
    approved_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create money_collections table
CREATE TABLE IF NOT EXISTS money_collections (
    id SERIAL PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    shop_id UUID REFERENCES shops(id),
    amount DECIMAL(10,2) NOT NULL,
    collected_by VARCHAR(255),
    collected_from UUID REFERENCES users(id),
    status VARCHAR(50) DEFAULT 'pending',
    approval_deadline TIMESTAMP,
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Insert test tenant
INSERT INTO tenants (id, name, code, status, subscription_plan)
VALUES ('11111111-1111-1111-1111-111111111111', 'Test Company', 'TEST001', 'active', 'premium')
ON CONFLICT DO NOTHING;

-- Insert test shop
INSERT INTO shops (id, tenant_id, name, address, phone, status)
VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Main Store', '123 Main St', '+1234567890', 'active')
ON CONFLICT DO NOTHING;

-- Insert test admin user (password: admin123)
INSERT INTO users (tenant_id, shop_id, username, password, email, mobile, role, status)
VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'admin', '\$2a\$10\$9Xz3zPfmS.Zv1JzR5yYFPOGxKjH5kR0G1nG9mNvL2JwKx3zV6OZLC', 'admin@test.com', '+1234567890', 'admin', 'active'),
    (NULL, NULL, 'superadmin', '\$2a\$10\$9Xz3zPfmS.Zv1JzR5yYFPOGxKjH5kR0G1nG9mNvL2JwKx3zV6OZLC', 'super@liquorpro.com', '+918630668488', 'saas_admin', 'active')
ON CONFLICT (username) DO NOTHING;

-- Insert test categories
INSERT INTO categories (tenant_id, name, description)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'Beer', 'Beer products'),
    ('11111111-1111-1111-1111-111111111111', 'Wine', 'Wine products'),
    ('11111111-1111-1111-1111-111111111111', 'Spirits', 'Spirit products')
ON CONFLICT DO NOTHING;

-- Insert test products
INSERT INTO products (tenant_id, name, category_id, brand, price, cost)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'Budweiser', 1, 'Budweiser', 12.99, 8.99),
    ('11111111-1111-1111-1111-111111111111', 'Corona', 1, 'Corona', 14.99, 10.99),
    ('11111111-1111-1111-1111-111111111111', 'Red Wine', 2, 'Generic', 25.99, 18.99)
ON CONFLICT DO NOTHING;

-- Insert initial stock
INSERT INTO stocks (tenant_id, shop_id, product_id, quantity)
VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 1, 100),
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 2, 75),
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 3, 50)
ON CONFLICT DO NOTHING;

-- Insert test vendor
INSERT INTO vendors (tenant_id, name, contact_person, mobile)
VALUES ('11111111-1111-1111-1111-111111111111', 'Test Supplier', 'John Doe', '+9876543210')
ON CONFLICT DO NOTHING;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO liquorpro;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO liquorpro;

EOF

echo "Database initialized successfully!"
echo ""
echo "Test Credentials:"
echo "Username: admin"
echo "Password: admin123"
echo ""
echo "Super Admin:"
echo "Username: superadmin"
echo "Password: admin123"