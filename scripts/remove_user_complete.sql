-- Complete User Removal Script
-- Removes user with phone 8126816664 and all related data

DO $$
DECLARE
    user_id_to_remove UUID;
    tenant_id_to_check UUID;
BEGIN
    -- Get the user ID
    SELECT id INTO user_id_to_remove
    FROM users
    WHERE phone = '+918126816664' OR phone = '8126816664';

    IF user_id_to_remove IS NULL THEN
        RAISE NOTICE 'User not found with phone 8126816664';
        RETURN;
    END IF;

    RAISE NOTICE 'Found user ID: %', user_id_to_remove;

    -- Get tenant ID associated with this user (if any)
    SELECT tenant_id INTO tenant_id_to_check
    FROM users
    WHERE id = user_id_to_remove;

    -- Begin cleanup
    RAISE NOTICE 'Starting cleanup for user...';

    -- Disable foreign key checks temporarily
    SET session_replication_role = 'replica';

    -- Remove from daily_sales records (created_by, approved_by)
    UPDATE daily_sales SET created_by = NULL WHERE created_by = user_id_to_remove;
    UPDATE daily_sales SET approved_by = NULL WHERE approved_by = user_id_to_remove;
    UPDATE daily_sales SET salesman_id = NULL WHERE salesman_id = user_id_to_remove;

    -- Remove from money_collection
    UPDATE money_collection SET collected_by = NULL WHERE collected_by = user_id_to_remove;
    UPDATE money_collection SET approved_by = NULL WHERE approved_by = user_id_to_remove;

    -- Remove from vendors
    UPDATE vendors SET created_by = NULL WHERE created_by = user_id_to_remove;

    -- Remove from vendor_invoices
    UPDATE vendor_invoices SET created_by = NULL WHERE created_by = user_id_to_remove;

    -- Remove from shops
    UPDATE shops SET created_by = NULL WHERE created_by = user_id_to_remove;
    UPDATE shops SET manager_id = NULL WHERE manager_id = user_id_to_remove;

    -- Remove from products
    UPDATE products SET created_by = NULL WHERE created_by = user_id_to_remove;

    -- Remove from expenses
    UPDATE expenses SET created_by = NULL WHERE created_by = user_id_to_remove;
    UPDATE expenses SET approved_by = NULL WHERE approved_by = user_id_to_remove;

    -- Remove from inventory_adjustments
    DELETE FROM inventory_adjustments WHERE adjusted_by = user_id_to_remove;

    -- Remove from ocr_sessions
    DELETE FROM ocr_sessions WHERE created_by = user_id_to_remove;

    -- Remove from audit_logs
    DELETE FROM audit_logs WHERE user_id = user_id_to_remove;

    -- Remove from sessions
    DELETE FROM sessions WHERE user_id = user_id_to_remove;

    -- Remove from tenant_users (if exists)
    DELETE FROM tenant_users WHERE user_id = user_id_to_remove;

    -- Remove from user_permissions (if exists)
    DELETE FROM user_permissions WHERE user_id = user_id_to_remove;

    -- Remove from user_activities (if exists)
    DELETE FROM user_activities WHERE user_id = user_id_to_remove;

    -- Finally, remove the user
    DELETE FROM users WHERE id = user_id_to_remove;

    -- Re-enable foreign key checks
    SET session_replication_role = 'origin';

    RAISE NOTICE 'User removed successfully';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error during user removal: %', SQLERRM;
        SET session_replication_role = 'origin';
        RAISE;
END $$;

-- Verification queries
SELECT 'User Check:' as check_type,
       COUNT(*) as count
FROM users
WHERE phone = '+918126816664' OR phone = '8126816664';

SELECT 'Sessions Check:' as check_type,
       COUNT(*) as count
FROM sessions
WHERE user_id IN (
    SELECT id FROM users WHERE phone = '+918126816664' OR phone = '8126816664'
);