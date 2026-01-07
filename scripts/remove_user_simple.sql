-- Simple User Removal Script
-- Removes user with phone 8126816664

BEGIN;

-- Store user ID for reference
CREATE TEMP TABLE user_to_remove AS
SELECT id, username, email, phone, tenant_id
FROM users
WHERE phone = '+918126816664' OR phone = '8126816664';

-- Display user info before removal
SELECT 'Removing User:' as action, * FROM user_to_remove;

-- Get the user ID
DO $$
DECLARE
    uid UUID;
    tid UUID;
BEGIN
    SELECT id, tenant_id INTO uid, tid FROM user_to_remove LIMIT 1;

    IF uid IS NOT NULL THEN
        -- Disable foreign key checks
        SET session_replication_role = 'replica';

        -- Remove from audit_logs
        DELETE FROM audit_logs WHERE user_id = uid;

        -- Remove from daily_sales_records (if created_by or approved_by columns exist)
        UPDATE daily_sales_records SET created_by = NULL WHERE created_by = uid;
        UPDATE daily_sales_records SET approved_by = NULL WHERE approved_by = uid;
        UPDATE daily_sales_records SET salesman_id = NULL WHERE salesman_id = uid;

        -- Remove from ocr_sessions
        DELETE FROM ocr_sessions WHERE created_by = uid;
        DELETE FROM batch_ocr_sessions WHERE created_by = uid;

        -- Remove from cash_collections
        UPDATE cash_collections SET collected_by = NULL WHERE collected_by = uid;

        -- Remove from expenses
        UPDATE expenses SET created_by = NULL WHERE created_by = uid;
        UPDATE expenses SET approved_by = NULL WHERE approved_by = uid;

        -- Remove from shops
        UPDATE shops SET created_by = NULL WHERE created_by = uid;
        UPDATE shops SET manager_id = NULL WHERE manager_id = uid;

        -- Remove from products
        UPDATE products SET created_by = NULL WHERE created_by = uid;

        -- Remove from vendors
        UPDATE vendors SET created_by = NULL WHERE created_by = uid;

        -- Remove from invoices
        UPDATE invoices SET created_by = NULL WHERE created_by = uid;

        -- Remove from tenant_users if exists
        DELETE FROM tenant_users WHERE user_id = uid;

        -- Remove from admin_users if exists
        DELETE FROM admin_users WHERE user_id = uid;

        -- Finally remove the user
        DELETE FROM users WHERE id = uid;

        -- Re-enable foreign key checks
        SET session_replication_role = 'origin';

        RAISE NOTICE 'User % removed successfully', uid;
    ELSE
        RAISE NOTICE 'User not found';
    END IF;
END $$;

-- Cleanup temp table
DROP TABLE user_to_remove;

COMMIT;

-- Verification
SELECT 'Users with phone 8126816664:' as check,
       COUNT(*) as remaining_count
FROM users
WHERE phone = '+918126816664' OR phone = '8126816664';