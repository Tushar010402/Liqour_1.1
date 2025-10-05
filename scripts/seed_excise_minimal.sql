-- Minimal Excise Test Data - Production Ready
-- Matches actual database schema constraints

-- 1. Tenant
INSERT INTO tenants (id, name, domain, is_active)
VALUES ('11111111-1111-1111-1111-111111111111'::uuid, 'UP Test Shop', 'uptest.liquorpro.com', true)
ON CONFLICT (id) DO NOTHING;

-- 2. User (without created_by field)
INSERT INTO users (id, tenant_id, username, email, password_hash, first_name, last_name, role, is_active)
VALUES (
    '22222222-2222-2222-2222-222222222222'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'shopowner',
    'shop.owner@upexcise.test',
    '$2a$10$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW',
    'Ramesh',
    'Kumar',
    'owner',
    true
) ON CONFLICT (email) DO NOTHING;

-- 3. Shops (shop_type must be lowercase: 'composite', 'imfl', etc.)
INSERT INTO shops (id, tenant_id, name, license_number, address, phone, excise_district, shop_type, can_sell_country_liquor, can_sell_imfl, can_sell_beer, can_sell_wine, is_active)
VALUES
(
    '33333333-3333-3333-3333-333333333333'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Shop - Lucknow',
    'UP-COMP-2025-001',
    'MG Road, Lucknow, UP',
    '+919876543210',
    'Lucknow',
    'composite',
    true, true, true, true, true
),
(
    '44444444-4444-4444-4444-444444444444'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Shop - Varanasi',
    'UP-IMFL-2025-002',
    'Godowlia, Varanasi, UP',
    '+919876543211',
    'Varanasi',
    'imfl',
    false, true, true, true, true
) ON CONFLICT (id) DO NOTHING;

-- 4. Excise Licenses
INSERT INTO excise_licenses (
    id, tenant_id, shop_id, license_number, license_type,
    issued_date, expiry_date, monthly_fee, is_active
)
VALUES
(
    '55555555-5555-5555-5555-555555555555'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid,
    'UP-COMP-2025-001',
    'COMPOSITE',
    '2025-04-01', '2026-03-31', 50000.00, true
),
(
    '66666666-6666-6666-6666-666666666666'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '44444444-4444-4444-4444-444444444444'::uuid,
    'UP-IMFL-2025-002',
    'FL-2A',
    '2025-04-01', '2026-03-31', 50000.00, true
) ON CONFLICT (id) DO NOTHING;

-- Link shops to licenses
UPDATE shops SET excise_license_id = '55555555-5555-5555-5555-555555555555' WHERE id = '33333333-3333-3333-3333-333333333333';
UPDATE shops SET excise_license_id = '66666666-6666-6666-6666-666666666666' WHERE id = '44444444-4444-4444-4444-444444444444';

-- 5. CL-2 Godown Vendor (without created_by since it has FK constraint)
-- First create a system user if needed or use existing user
DO $$
DECLARE
    system_user_id UUID;
BEGIN
    -- Get existing user ID
    SELECT id INTO system_user_id FROM users WHERE email = 'shop.owner@upexcise.test' LIMIT 1;

    IF system_user_id IS NOT NULL THEN
        INSERT INTO vendors (
            id, tenant_id, name, contact_person, email, phone,
            address, city, state, gst_number,
            vendor_type, cl2_license_number, is_cl2_godown,
            excise_district, is_active, created_by
        )
        VALUES (
            '77777777-7777-7777-7777-777777777777'::uuid,
            '11111111-1111-1111-1111-111111111111'::uuid,
            'UP State Depot - Lucknow',
            'Depot Manager',
            'depot.lucknow@upexcise.gov.in',
            '+910522123456',
            'Excise Dept, Gomti Nagar',
            'Lucknow',
            'Uttar Pradesh',
            '09AAACU1234A1Z5',
            'cl2_godown',
            'UP-CL2-LKO-001',
            true,
            'Lucknow',
            true,
            system_user_id
        ) ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

-- 6. Categories, Brands, Products
INSERT INTO categories (id, tenant_id, name, is_active)
VALUES
('88888888-8888-8888-8888-888888888888'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'IMFL', true),
('99999999-9999-9999-9999-999999999999'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Country Liquor', true),
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Beer', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO brands (id, tenant_id, name, is_active)
VALUES
('b1111111-1111-1111-1111-111111111111'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Royal Challenge', true),
('b2222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'UP CL', true),
('b3333333-3333-3333-3333-333333333333'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Kingfisher', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO products (
    id, tenant_id, category_id, brand_id, name, sku, barcode, size, alcohol_content,
    cost_price, selling_price, mrp, security_code_required, bottle_type, excise_category, is_active
)
VALUES
(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '88888888-8888-8888-8888-888888888888'::uuid,
    'b1111111-1111-1111-1111-111111111111'::uuid,
    'Royal Challenge 750ml', 'RC-750', '8901234567890', '750ml', 42.8,
    800, 1200, 1300, true, 'glass', 'imfl', true
),
(
    'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '99999999-9999-9999-9999-999999999999'::uuid,
    'b2222222-2222-2222-2222-222222222222'::uuid,
    'UP CL 375ml', 'CL-375', '8901234567891', '375ml', 25.0,
    50, 80, 90, true, 'pet', 'country_liquor', true
),
(
    'dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'b3333333-3333-3333-3333-333333333333'::uuid,
    'Kingfisher 650ml', 'KF-650', '8901234567892', '650ml', 5.0,
    100, 150, 160, false, 'glass', 'beer', true
) ON CONFLICT (id) DO NOTHING;

-- 7. Security Codes
INSERT INTO bottle_security_codes (
    id, tenant_id, security_code, product_id,
    status, received_date, warehouse_source, batch_number, verified
)
VALUES
('20202020-2020-2020-2020-202020202020'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'UP2025ABC001234', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'in_stock', CURRENT_DATE - 5, 'CL2-LKO-001', 'BATCH-001', true),
('30303030-3030-3030-3030-303030303030'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'UP2025ABC001235', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'in_stock', CURRENT_DATE - 5, 'CL2-LKO-001', 'BATCH-001', true),
('40404040-4040-4040-4040-404040404040'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'UP2025CL000567', 'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 'in_stock', CURRENT_DATE - 5, 'CL2-LKO-001', 'BATCH-002', true)
ON CONFLICT (id) DO NOTHING;

-- Verification
DO $$
DECLARE
    counts TEXT;
BEGIN
    SELECT
        'Tenants: ' || COUNT(*) || ', ' ||
        'Users: ' || (SELECT COUNT(*) FROM users WHERE tenant_id = '11111111-1111-1111-1111-111111111111') || ', ' ||
        'Shops: ' || (SELECT COUNT(*) FROM shops WHERE tenant_id = '11111111-1111-1111-1111-111111111111') || ', ' ||
        'Licenses: ' || (SELECT COUNT(*) FROM excise_licenses WHERE tenant_id = '11111111-1111-1111-1111-111111111111') || ', ' ||
        'Products: ' || (SELECT COUNT(*) FROM products WHERE tenant_id = '11111111-1111-1111-1111-111111111111') || ', ' ||
        'Security Codes: ' || (SELECT COUNT(*) FROM bottle_security_codes WHERE tenant_id = '11111111-1111-1111-1111-111111111111')
    INTO counts FROM tenants WHERE id = '11111111-1111-1111-1111-111111111111';

    RAISE NOTICE '';
    RAISE NOTICE '✅ EXCISE SEED DATA LOADED!';
    RAISE NOTICE '%', counts;
    RAISE NOTICE '';
    RAISE NOTICE '🔑 Login: shop.owner@upexcise.test / test123';
    RAISE NOTICE '🆔 Tenant: 11111111-1111-1111-1111-111111111111';
    RAISE NOTICE '';
END $$;
