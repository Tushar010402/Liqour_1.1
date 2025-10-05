-- Create tenant admin user script
-- This script creates a tenant and an admin user for phone number 8126816664

-- First, create a tenant if it doesn't exist
INSERT INTO tenants (id, name, status, created_at, updated_at)
VALUES (
    gen_random_uuid(),
    'Demo Tenant',
    'active',
    NOW(),
    NOW()
) ON CONFLICT (name) DO NOTHING;

-- Get the tenant ID
WITH tenant_info AS (
    SELECT id as tenant_id FROM tenants WHERE name = 'Demo Tenant' LIMIT 1
)
-- Create the tenant admin user
INSERT INTO users (
    id, 
    username, 
    email, 
    first_name, 
    last_name, 
    phone, 
    password_hash, 
    role, 
    is_active, 
    is_superuser, 
    tenant_id, 
    created_at, 
    updated_at
)
SELECT 
    gen_random_uuid(),
    'tenant_admin_8126816664',
    'admin@demo-tenant.com',
    'Tenant',
    'Admin',
    '+918126816664',
    '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewYhpGhAJbQKg8FW', -- Password: TenantAdmin@2024
    'admin',
    true,
    false,
    tenant_info.tenant_id,
    NOW(),
    NOW()
FROM tenant_info
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE phone = '+918126816664' OR email = 'admin@demo-tenant.com'
);

-- Verify the user was created
SELECT 
    u.username,
    u.email,
    u.phone,
    u.role,
    u.is_active,
    t.name as tenant_name
FROM users u
LEFT JOIN tenants t ON u.tenant_id = t.id
WHERE u.phone = '+918126816664';