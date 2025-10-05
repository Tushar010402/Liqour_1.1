-- Seed Data for UP Excise Compliance Testing - FIXED VERSION
-- This script creates minimal test data that matches actual schema

-- =====================================================
-- 1. CREATE TEST TENANT
-- =====================================================
INSERT INTO tenants (id, name, domain, is_active)
VALUES (
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Test Liquor Shop',
    'up-test-shop.liquorpro.com',
    true
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 2. CREATE TEST USER (Shop Owner)
-- =====================================================
INSERT INTO users (id, tenant_id, username, email, password_hash, first_name, last_name, role, is_active, created_by)
VALUES (
    '22222222-2222-2222-2222-222222222222'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'shopowner',
    'shop.owner@upexcise.test',
    '$2a$10$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', -- password: test123
    'Ramesh',
    'Kumar',
    'owner',
    true,
    '22222222-2222-2222-2222-222222222222'::uuid
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 3. CREATE TEST SHOPS
-- =====================================================
INSERT INTO shops (id, tenant_id, name, license_number, address, phone, excise_district, shop_type, can_sell_country_liquor, can_sell_imfl, can_sell_beer, can_sell_wine, is_active)
VALUES
(
    '33333333-3333-3333-3333-333333333333'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Liquor Shop - Lucknow',
    'UP-COMPOSITE-2025-0001',
    'MG Road, Hazratganj, Lucknow, UP - 226001',
    '+91-9876543210',
    'Lucknow',
    'COMPOSITE',
    true,
    true,
    true,
    true,
    true
),
(
    '44444444-4444-4444-4444-444444444444'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Liquor Shop - Varanasi',
    'UP-FL2A-2025-0002',
    'Godowlia Chowk, Varanasi, UP - 221001',
    '+91-9876543211',
    'Varanasi',
    'FL-2A',
    false,
    true,
    true,
    true,
    true
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 4. CREATE EXCISE LICENSES
-- =====================================================
INSERT INTO excise_licenses (
    id, tenant_id, shop_id, license_number, license_type,
    issued_date, expiry_date, monthly_fee,
    is_active, issuing_authority, license_category
)
VALUES
(
    '55555555-5555-5555-5555-555555555555'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid,
    'UP-COMPOSITE-2025-0001',
    'COMPOSITE',
    '2025-04-01'::date,
    '2026-03-31'::date,
    50000.00,
    true,
    'UP Excise Department - Lucknow',
    'Retail'
),
(
    '66666666-6666-6666-6666-666666666666'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '44444444-4444-4444-4444-444444444444'::uuid,
    'UP-FL2A-2025-0002',
    'FL-2A',
    '2025-04-01'::date,
    '2026-03-31'::date,
    50000.00,
    true,
    'UP Excise Department - Varanasi',
    'Retail'
) ON CONFLICT (id) DO NOTHING;

-- Link shops to licenses
UPDATE shops SET excise_license_id = '55555555-5555-5555-5555-555555555555'::uuid WHERE id = '33333333-3333-3333-3333-333333333333'::uuid;
UPDATE shops SET excise_license_id = '66666666-6666-6666-6666-666666666666'::uuid WHERE id = '44444444-4444-4444-4444-444444444444'::uuid;

-- =====================================================
-- 5. CREATE CL-2 GODOWN VENDOR
-- =====================================================
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
    '+91-0522-1234567',
    'Excise Department, Gomti Nagar',
    'Lucknow',
    'Uttar Pradesh',
    '09AAACU1234A1Z5',
    'cl2_godown',
    'UP-CL2-LKO-001',
    true,
    'Lucknow',
    true,
    '22222222-2222-2222-2222-222222222222'::uuid
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 6. CREATE PRODUCT CATEGORIES
-- =====================================================
INSERT INTO categories (id, tenant_id, name, description, is_active)
VALUES
(
    '88888888-8888-8888-8888-888888888888'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'IMFL - Whisky',
    'Indian Made Foreign Liquor - Whisky Category',
    true
),
(
    '99999999-9999-9999-9999-999999999999'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Country Liquor',
    'Country Liquor Category',
    true
),
(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Beer',
    'Beer Category',
    true
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 7. CREATE BRANDS
-- =====================================================
INSERT INTO brands (id, tenant_id, name, is_active)
VALUES
(
    'b1111111-1111-1111-1111-111111111111'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Royal Challenge',
    true
),
(
    'b2222222-2222-2222-2222-222222222222'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Country Liquor',
    true
),
(
    'b3333333-3333-3333-3333-333333333333'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Kingfisher',
    true
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 8. CREATE SAMPLE PRODUCTS
-- =====================================================
INSERT INTO products (
    id, tenant_id, category_id, brand_id, name, description,
    sku, barcode, size, alcohol_content,
    cost_price, selling_price, mrp,
    security_code_required, bottle_type, excise_category,
    is_active
)
VALUES
(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '88888888-8888-8888-8888-888888888888'::uuid,
    'b1111111-1111-1111-1111-111111111111'::uuid,
    'Royal Challenge Whisky 750ml',
    'Premium IMFL Whisky',
    'RC-WHISKY-750',
    '8901234567890',
    '750ml',
    42.8,
    800.00,
    1200.00,
    1300.00,
    true,
    'glass',
    'imfl',
    true
),
(
    'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '99999999-9999-9999-9999-999999999999'::uuid,
    'b2222222-2222-2222-2222-222222222222'::uuid,
    'UP Country Liquor 375ml',
    'Standard Country Liquor',
    'CL-STD-375',
    '8901234567891',
    '375ml',
    25.0,
    50.00,
    80.00,
    90.00,
    true,
    'pet',
    'country_liquor',
    true
),
(
    'dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'b3333333-3333-3333-3333-333333333333'::uuid,
    'Kingfisher Beer 650ml',
    'Premium Beer',
    'KF-BEER-650',
    '8901234567892',
    '650ml',
    5.0,
    100.00,
    150.00,
    160.00,
    false,
    'glass',
    'beer',
    true
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 9. CREATE SAMPLE SECURITY CODES
-- =====================================================
INSERT INTO bottle_security_codes (
    id, tenant_id, security_code, product_id,
    status, received_date, warehouse_source,
    batch_number, verified
)
VALUES
(
    '20202020-2020-2020-2020-202020202020'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP2025ABC001234',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    'in_stock',
    CURRENT_DATE - INTERVAL '5 days',
    'CL2-LKO-001',
    'BATCH-OCT-2025-001',
    true
),
(
    '30303030-3030-3030-3030-303030303030'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP2025ABC001235',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    'in_stock',
    CURRENT_DATE - INTERVAL '5 days',
    'CL2-LKO-001',
    'BATCH-OCT-2025-001',
    true
),
(
    '40404040-4040-4040-4040-404040404040'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP2025CL000567',
    'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
    'in_stock',
    CURRENT_DATE - INTERVAL '5 days',
    'CL2-LKO-001',
    'BATCH-OCT-2025-002',
    true
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check created data
DO $$
DECLARE
    tenant_count INT;
    user_count INT;
    shop_count INT;
    license_count INT;
    vendor_count INT;
    category_count INT;
    brand_count INT;
    product_count INT;
    security_code_count INT;
BEGIN
    SELECT COUNT(*) INTO tenant_count FROM tenants WHERE id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO user_count FROM users WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO shop_count FROM shops WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO license_count FROM excise_licenses WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO vendor_count FROM vendors WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO category_count FROM categories WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO brand_count FROM brands WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO product_count FROM products WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO security_code_count FROM bottle_security_codes WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

    RAISE NOTICE '';
    RAISE NOTICE '✅ ============================================';
    RAISE NOTICE '✅ EXCISE SEED DATA CREATED SUCCESSFULLY!';
    RAISE NOTICE '✅ ============================================';
    RAISE NOTICE '';
    RAISE NOTICE '📊 DATA SUMMARY:';
    RAISE NOTICE '   ├─ Tenants: %', tenant_count;
    RAISE NOTICE '   ├─ Users: %', user_count;
    RAISE NOTICE '   ├─ Shops: %', shop_count;
    RAISE NOTICE '   ├─ Excise Licenses: %', license_count;
    RAISE NOTICE '   ├─ CL-2 Godown Vendors: %', vendor_count;
    RAISE NOTICE '   ├─ Categories: %', category_count;
    RAISE NOTICE '   ├─ Brands: %', brand_count;
    RAISE NOTICE '   ├─ Products: %', product_count;
    RAISE NOTICE '   └─ Security Codes: %', security_code_count;
    RAISE NOTICE '';
    RAISE NOTICE '🔑 TEST CREDENTIALS:';
    RAISE NOTICE '   Email: shop.owner@upexcise.test';
    RAISE NOTICE '   Password: test123';
    RAISE NOTICE '   Username: shopowner';
    RAISE NOTICE '';
    RAISE NOTICE '🆔 TEST IDS:';
    RAISE NOTICE '   Tenant ID: 11111111-1111-1111-1111-111111111111';
    RAISE NOTICE '   User ID: 22222222-2222-2222-2222-222222222222';
    RAISE NOTICE '   Shop 1 ID: 33333333-3333-3333-3333-333333333333';
    RAISE NOTICE '   Shop 2 ID: 44444444-4444-4444-4444-444444444444';
    RAISE NOTICE '   License 1 ID: 55555555-5555-5555-5555-555555555555';
    RAISE NOTICE '   License 2 ID: 66666666-6666-6666-6666-666666666666';
    RAISE NOTICE '';
    RAISE NOTICE '📝 NEXT STEPS:';
    RAISE NOTICE '   1. Login to get JWT token';
    RAISE NOTICE '   2. Test excise endpoints with authentication';
    RAISE NOTICE '   3. Auto-generate daily reports';
    RAISE NOTICE '   4. Test compliance dashboard';
    RAISE NOTICE '';
END $$;
