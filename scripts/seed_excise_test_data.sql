-- Seed Data for UP Excise Compliance Testing
-- This script creates test data for testing excise features with authentication

-- =====================================================
-- 1. CREATE TEST TENANT
-- =====================================================
INSERT INTO tenants (id, name, domain, is_active, created_at, updated_at)
VALUES (
    '11111111-1111-1111-1111-111111111111'::uuid,
    'UP Test Liquor Shop',
    'up-test-shop.liquorpro.com',
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 2. CREATE TEST USER (Shop Owner)
-- =====================================================
INSERT INTO users (id, tenant_id, username, email, password_hash, first_name, last_name, role, is_active, created_at, updated_at)
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
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 3. CREATE TEST SHOPS
-- =====================================================
INSERT INTO shops (id, tenant_id, name, license_number, address, phone, excise_district, shop_type, can_sell_country_liquor, can_sell_imfl, can_sell_beer, can_sell_wine, is_active, created_at, updated_at)
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
    true,
    NOW(),
    NOW()
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
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 4. CREATE EXCISE LICENSES
-- =====================================================
INSERT INTO excise_licenses (
    id, tenant_id, shop_id, license_number, license_type,
    issue_date, expiry_date, monthly_fee, security_deposit,
    is_active, created_at, updated_at
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
    500000.00,
    true,
    NOW(),
    NOW()
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
    500000.00,
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 5. CREATE CL-2 GODOWN VENDOR
-- =====================================================
INSERT INTO vendors (
    id, tenant_id, name, contact_person, email, phone,
    address, city, state, gstin,
    vendor_type, cl2_license_number, is_cl2_godown,
    is_active, created_at, updated_at
)
VALUES (
    '77777777-7777-7777-7777-777777777777'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Uttar Pradesh State Depot - Lucknow',
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
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 6. CREATE PRODUCT CATEGORIES
-- =====================================================
INSERT INTO categories (id, tenant_id, name, description, is_active, created_at, updated_at)
VALUES
(
    '88888888-8888-8888-8888-888888888888'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'IMFL - Whisky',
    'Indian Made Foreign Liquor - Whisky Category',
    true,
    NOW(),
    NOW()
),
(
    '99999999-9999-9999-9999-999999999999'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Country Liquor',
    'Country Liquor Category',
    true,
    NOW(),
    NOW()
),
(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Beer',
    'Beer Category',
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 7. CREATE SAMPLE PRODUCTS
-- =====================================================
INSERT INTO products (
    id, tenant_id, category_id, name, description,
    sku, barcode, unit_of_measure,
    cost_price, selling_price, mrp, tax_rate,
    reorder_level, reorder_quantity,
    requires_security_code,
    is_active, created_at, updated_at
)
VALUES
(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '88888888-8888-8888-8888-888888888888'::uuid,
    'Royal Challenge Whisky 750ml',
    'Premium IMFL Whisky',
    'RC-WHISKY-750',
    '8901234567890',
    'bottle',
    800.00,
    1200.00,
    1300.00,
    18.00,
    50,
    100,
    true,
    true,
    NOW(),
    NOW()
),
(
    'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '99999999-9999-9999-9999-999999999999'::uuid,
    'UP Country Liquor 375ml',
    'Standard Country Liquor',
    'CL-STD-375',
    '8901234567891',
    'bottle',
    50.00,
    80.00,
    90.00,
    18.00,
    100,
    200,
    true,
    true,
    NOW(),
    NOW()
),
(
    'dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'Kingfisher Beer 650ml',
    'Premium Beer',
    'KF-BEER-650',
    '8901234567892',
    'bottle',
    100.00,
    150.00,
    160.00,
    18.00,
    100,
    150,
    false,
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 8. CREATE SAMPLE PURCHASE FROM CL-2 GODOWN
-- =====================================================
INSERT INTO stock_purchases (
    id, tenant_id, shop_id, vendor_id,
    purchase_date, total_amount, paid_amount, payment_status,
    notes, excise_lifted_from_godown, excise_godown_challan_number,
    created_at, updated_at
)
VALUES (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid,
    '77777777-7777-7777-7777-777777777777'::uuid,
    CURRENT_DATE - INTERVAL '5 days',
    95000.00,
    95000.00,
    'paid',
    'Stock lifted from CL-2 godown',
    true,
    'CL2-LKO-20251001-001',
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 9. CREATE CONSIDERATION FEE TRANSACTION
-- =====================================================
INSERT INTO vendor_transactions (
    id, tenant_id, vendor_id, transaction_date,
    transaction_type, amount, payment_method,
    reference_number, description,
    is_consideration_fee, fee_per_bottle,
    created_at, updated_at
)
VALUES (
    'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '77777777-7777-7777-7777-777777777777'::uuid,
    CURRENT_DATE - INTERVAL '5 days',
    'payment',
    5000.00,
    'bank_transfer',
    'CONS-FEE-OCT-001',
    'Consideration fee for 100 bottles @ ₹50/bottle',
    true,
    50.00,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 10. CREATE LICENSE FEE EXPENSE
-- =====================================================
INSERT INTO expenses (
    id, tenant_id, shop_id, expense_date,
    category, amount, payment_method,
    description, is_license_fee, license_id,
    created_at, updated_at
)
VALUES (
    '10101010-1010-1010-1010-101010101010'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid,
    DATE_TRUNC('month', CURRENT_DATE),
    'license_fee',
    50000.00,
    'bank_transfer',
    'Monthly license fee for October 2025',
    true,
    '55555555-5555-5555-5555-555555555555'::uuid,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 11. CREATE SAMPLE SECURITY CODES
-- =====================================================
INSERT INTO bottle_security_codes (
    id, tenant_id, security_code, product_id,
    status, received_date, warehouse_source,
    batch_number, verified, created_at, updated_at
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
    true,
    NOW(),
    NOW()
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
    true,
    NOW(),
    NOW()
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
    true,
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check created data
DO $$
DECLARE
    tenant_count INT;
    shop_count INT;
    license_count INT;
    product_count INT;
    security_code_count INT;
BEGIN
    SELECT COUNT(*) INTO tenant_count FROM tenants WHERE id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO shop_count FROM shops WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO license_count FROM excise_licenses WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO product_count FROM products WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
    SELECT COUNT(*) INTO security_code_count FROM bottle_security_codes WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

    RAISE NOTICE '✅ Seed Data Created Successfully!';
    RAISE NOTICE '   Tenants: %', tenant_count;
    RAISE NOTICE '   Shops: %', shop_count;
    RAISE NOTICE '   Licenses: %', license_count;
    RAISE NOTICE '   Products: %', product_count;
    RAISE NOTICE '   Security Codes: %', security_code_count;
    RAISE NOTICE '';
    RAISE NOTICE '📋 Test Credentials:';
    RAISE NOTICE '   Email: shop.owner@upexcise.test';
    RAISE NOTICE '   Password: test123';
    RAISE NOTICE '   Tenant ID: 11111111-1111-1111-1111-111111111111';
END $$;
