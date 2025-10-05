-- Clean up all existing product catalog data
DELETE FROM product_templates;
DELETE FROM subcategories;
DELETE FROM brands WHERE tenant_id != '373e965a-6dec-44d6-a2ab-0400449fc71d';
DELETE FROM categories WHERE tenant_id != '373e965a-6dec-44d6-a2ab-0400449fc71d';

-- Reset sequences if needed
SELECT setval('product_templates_id_seq', 1, false);
SELECT setval('subcategories_id_seq', 1, false);

-- Verify cleanup
SELECT COUNT(*) as remaining_templates FROM product_templates;
SELECT COUNT(*) as remaining_categories FROM categories;
SELECT COUNT(*) as remaining_brands FROM brands;
SELECT COUNT(*) as remaining_subcategories FROM subcategories;