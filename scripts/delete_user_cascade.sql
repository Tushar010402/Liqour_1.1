-- Complete cascade deletion for user and tenant
-- This will remove user with phone 8126816664 and all associated data

BEGIN;

-- User and tenant IDs
\set user_id '36cf23d8-266d-4132-9244-cd666d8821c3'
\set tenant_id '46d08e6f-4519-45df-bea8-49361d066972'

-- Start with the most dependent tables first
DELETE FROM stock_histories WHERE tenant_id = :'tenant_id';
DELETE FROM stocks WHERE tenant_id = :'tenant_id';
DELETE FROM daily_sales_items WHERE tenant_id = :'tenant_id';
DELETE FROM daily_sales_records WHERE tenant_id = :'tenant_id';
DELETE FROM daily_sale_summaries WHERE tenant_id = :'tenant_id';
DELETE FROM ocr_extracted_items WHERE tenant_id = :'tenant_id';
DELETE FROM ocr_items WHERE tenant_id = :'tenant_id';
DELETE FROM batch_ocr_sessions WHERE tenant_id = :'tenant_id';
DELETE FROM ocr_sessions WHERE tenant_id = :'tenant_id';
DELETE FROM ocr_learning_feedback WHERE tenant_id = :'tenant_id';
DELETE FROM cash_transactions WHERE tenant_id = :'tenant_id';
DELETE FROM cash_holdings WHERE tenant_id = :'tenant_id';
DELETE FROM cash_collections WHERE tenant_id = :'tenant_id';
DELETE FROM cash_requests WHERE tenant_id = :'tenant_id';
DELETE FROM bank_transactions WHERE tenant_id = :'tenant_id';
DELETE FROM bank_accounts WHERE tenant_id = :'tenant_id';
DELETE FROM expenses WHERE tenant_id = :'tenant_id';
DELETE FROM invoices WHERE tenant_id = :'tenant_id';
DELETE FROM vendor_invoice_items WHERE tenant_id = :'tenant_id';
DELETE FROM vendor_invoices WHERE tenant_id = :'tenant_id';
DELETE FROM vendor_bank_accounts WHERE tenant_id = :'tenant_id';
DELETE FROM vendors WHERE tenant_id = :'tenant_id';
DELETE FROM products WHERE tenant_id = :'tenant_id';
DELETE FROM shops WHERE tenant_id = :'tenant_id';

-- Delete the user
DELETE FROM users WHERE id = :'user_id';

COMMIT;

-- Verify deletion
SELECT 'Verification Results:' as info;
SELECT 'User count with phone 8126816664: ' || COUNT(*) as check_result
FROM users WHERE phone LIKE '%8126816664%';
SELECT 'Shops count for tenant: ' || COUNT(*) as check_result
FROM shops WHERE tenant_id = '46d08e6f-4519-45df-bea8-49361d066972';
SELECT 'Products count for tenant: ' || COUNT(*) as check_result
FROM products WHERE tenant_id = '46d08e6f-4519-45df-bea8-49361d066972';