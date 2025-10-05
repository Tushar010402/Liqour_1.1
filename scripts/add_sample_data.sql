-- Add sample data for testing user experience
-- This script creates sample shops and sales data for the Demo Tenant

-- Get the Demo Tenant ID and create shops
WITH tenant_info AS (
    SELECT id as tenant_id FROM tenants WHERE name = 'Demo Tenant' LIMIT 1
),
shop_data AS (
    INSERT INTO shops (id, tenant_id, name, address, phone, created_at, updated_at)
    SELECT 
        gen_random_uuid(),
        tenant_info.tenant_id,
        shop_name,
        shop_address,
        shop_phone,
        NOW(),
        NOW()
    FROM tenant_info
    CROSS JOIN (VALUES
        ('Main Store', '123 Main Street, Mumbai, MH 400001', '+919876543210'),
        ('Downtown Branch', '456 Park Avenue, Mumbai, MH 400002', '+919876543211'),
        ('Mall Outlet', '789 Shopping Center, Mumbai, MH 400003', '+919876543212')
    ) AS shops(shop_name, shop_address, shop_phone)
    RETURNING id as shop_id
)
-- Create sample daily sales records
INSERT INTO daily_sales_records (
    id, tenant_id, shop_id, record_date, total_sales_amount, 
    total_transactions, total_customers, created_at, updated_at
)
SELECT 
    gen_random_uuid(),
    tenant_info.tenant_id,
    shop_data.shop_id,
    CURRENT_DATE - INTERVAL '1 day' * i,
    15000.0 + (RANDOM() * 10000), -- Random amount between 15k-25k
    25 + FLOOR(RANDOM() * 25)::int, -- Random transactions 25-50
    20 + FLOOR(RANDOM() * 20)::int, -- Random customers 20-40
    NOW(),
    NOW()
FROM tenant_info
CROSS JOIN shop_data
CROSS JOIN generate_series(0, 29) AS i; -- Last 30 days

-- Display summary of inserted data
SELECT 
    'Sample data insertion completed successfully!' as message,
    (SELECT COUNT(*) FROM shops WHERE tenant_id = (SELECT id FROM tenants WHERE name = 'Demo Tenant')) as shops_created,
    (SELECT COUNT(*) FROM daily_sales_records WHERE tenant_id = (SELECT id FROM tenants WHERE name = 'Demo Tenant')) as daily_sales_records;