-- Ensure SaaS Admin User exists in database for audit logs and admin operations

-- Create the default system admin user if it doesn't exist
INSERT INTO admin_users (
    id,
    name,
    email,
    mobile,
    role,
    password_hash,
    is_active,
    created_at,
    updated_at
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'System Admin',
    'admin@liquorpro.com',
    '+918630668488',
    'super_admin',
    '$2a$10$YourHashedPasswordHere', -- This is a placeholder
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO UPDATE SET
    updated_at = NOW(),
    is_active = true;

-- Also ensure the actual SaaS admin exists
INSERT INTO admin_users (
    id,
    name,
    email,
    mobile,
    role,
    password_hash,
    is_active,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),
    'SaaS Admin',
    'saas@liquorpro.com',
    '+918630668488',
    'saas_admin',
    '$2a$10$YourHashedPasswordHere',
    true,
    NOW(),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM admin_users WHERE mobile = '+918630668488'
);

-- Grant necessary permissions (if permissions table exists)
-- This is a placeholder for your permission system