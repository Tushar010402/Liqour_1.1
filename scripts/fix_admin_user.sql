-- Ensure SaaS Admin User exists in database for audit logs and admin operations

-- Create the default system admin user if it doesn't exist
INSERT INTO admin_users (
    id,
    name,
    email,
    mobile,
    role,
    active,
    created_at,
    updated_at
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'System Admin',
    'admin@liquorpro.com',
    '+919999999999',
    'super_admin',
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO UPDATE SET
    updated_at = NOW(),
    active = true;

-- Also ensure the actual SaaS admin exists
INSERT INTO admin_users (
    id,
    name,
    email,
    mobile,
    role,
    active,
    first_name,
    last_name,
    created_at,
    updated_at
) VALUES (
    '00000000-0000-0000-0000-000000000002',
    'SaaS Admin',
    'saas@liquorpro.com',
    '+918630668488',
    'saas_admin',
    true,
    'SaaS',
    'Administrator',
    NOW(),
    NOW()
) ON CONFLICT (mobile) DO UPDATE SET
    role = 'saas_admin',
    active = true,
    updated_at = NOW();