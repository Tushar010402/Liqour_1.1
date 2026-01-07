-- Migration: 051_sales_submission_alarm.sql
-- Description: Add daily sales submission alarm definition
-- Date: 2025-12-18

-- Add new alarm definition for daily sales submission check
INSERT INTO alarm_definitions (
    id,
    code,
    name,
    description,
    category,
    trigger_type,
    default_priority,
    threshold_schema,
    check_service,
    check_method,
    default_channels,
    default_cooldown_minutes,
    is_active,
    is_system,
    created_at,
    updated_at
) VALUES (
    gen_random_uuid(),
    'daily_sales_not_submitted',
    'Daily Sales Not Submitted',
    'Alert when user has not submitted daily sales by the configured deadline. Configurable per role with different deadlines for salesmen (1 PM) and managers (2 PM).',
    'business',
    'scheduled',
    'high',
    '{
        "deadline_time": "13:00",
        "role_deadlines": {
            "salesman": "13:00",
            "manager": "14:00",
            "admin": "14:00"
        },
        "check_roles": ["salesman", "manager"],
        "notify_roles": ["admin", "owner"],
        "grace_period_minutes": 30
    }',
    'finance',
    'CheckDailySalesSubmission',
    '["push", "in_app"]',
    60,
    true,
    true,
    NOW(),
    NOW()
) ON CONFLICT (code) DO NOTHING;

-- Create index on daily_sales_records for efficient submission checks
CREATE INDEX IF NOT EXISTS idx_daily_sales_records_salesman_date
ON daily_sales_records (salesman_id, record_date);

-- Create index on users for role-based queries
CREATE INDEX IF NOT EXISTS idx_users_tenant_role_active
ON users (tenant_id, role, is_active);

COMMENT ON INDEX idx_daily_sales_records_salesman_date IS 'Optimize queries for checking if a salesman has submitted daily sales for a specific date';
COMMENT ON INDEX idx_users_tenant_role_active IS 'Optimize queries for finding active users by role within a tenant';
