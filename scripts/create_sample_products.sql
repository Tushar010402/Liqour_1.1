-- Create Sample Products for Testing
-- Tenant: 712fd4a7-8879-4ad9-98c1-f054d1881669 (Dr Dangs Lab)

-- Get IDs we'll need
DO $$
DECLARE
    v_tenant_id UUID := '712fd4a7-8879-4ad9-98c1-f054d1881669';
    v_shop_id UUID;
    v_whiskey_cat_id UUID := '13529f42-ad1e-4766-9335-08b05e690093';
    v_beer_cat_id UUID := '221d134b-80e0-438b-8758-62acd18f1412';
    v_kingfisher_brand_id UUID := 'f186a763-f823-47a8-82b9-8804265c7645';
    v_chivas_brand_id UUID := '47ecc969-f5ee-437b-9994-47f3edd9ae97';
BEGIN
    -- Get shop ID for this tenant
    SELECT id INTO v_shop_id FROM shops WHERE tenant_id = v_tenant_id LIMIT 1;

    IF v_shop_id IS NULL THEN
        RAISE NOTICE 'No shop found for tenant, creating one...';
        INSERT INTO shops (tenant_id, name, address, phone, email, is_active, is_primary)
        VALUES (v_tenant_id, 'Main Store', 'New Delhi', '+919999992020', 'draja@gmail.com', true, true)
        RETURNING id INTO v_shop_id;
    END IF;

    -- Insert sample products
    INSERT INTO products (
        tenant_id, shop_id, template_id,
        name, sku, barcode,
        category_id, brand_id,
        size, alcohol_content, description,
        cost_price, selling_price,
        is_active
    ) VALUES
    -- Whiskey products
    (v_tenant_id, v_shop_id, 1, 'Chivas Regal 12 Years', 'CR12-750', 'CR12750ML',
     v_whiskey_cat_id, v_chivas_brand_id,
     '750ml', 40.0, 'Premium blended Scotch whisky aged 12 years',
     1800.00, 2200.00, true),

    (v_tenant_id, v_shop_id, 2, 'Chivas Regal 18 Years', 'CR18-750', 'CR18750ML',
     v_whiskey_cat_id, v_chivas_brand_id,
     '750ml', 40.0, 'Premium blended Scotch whisky aged 18 years',
     4500.00, 5500.00, true),

    -- Beer products
    (v_tenant_id, v_shop_id, 3, 'Kingfisher Premium', 'KF-PREM-650', 'KFPREM650',
     v_beer_cat_id, v_kingfisher_brand_id,
     '650ml', 5.0, 'Premium lager beer',
     120.00, 150.00, true),

    (v_tenant_id, v_shop_id, 4, 'Kingfisher Strong', 'KF-STR-500', 'KFSTR500',
     v_beer_cat_id, v_kingfisher_brand_id,
     '500ml', 8.0, 'Strong premium beer',
     100.00, 130.00, true),

    (v_tenant_id, v_shop_id, 5, 'Kingfisher Ultra', 'KF-ULTRA-330', 'KFULTRA330',
     v_beer_cat_id, v_kingfisher_brand_id,
     '330ml', 4.8, 'Light and crisp beer',
     110.00, 140.00, true);

    RAISE NOTICE 'Created 5 sample products successfully!';

END $$;

-- Verify products created
SELECT
    p.id,
    p.name,
    c.name as category,
    b.name as brand,
    p.size,
    p.cost_price,
    p.selling_price
FROM products p
JOIN categories c ON p.category_id = c.id
JOIN brands b ON p.brand_id = b.id
WHERE p.tenant_id = '712fd4a7-8879-4ad9-98c1-f054d1881669'
ORDER BY p.created_at DESC;
