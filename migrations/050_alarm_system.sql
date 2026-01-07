-- Create Alarm System Tables
-- Date: 2025-12-16
-- Description: Comprehensive alarm system for configurable business, scheduled, and system alerts

BEGIN;

-- ========================================
-- alarm_definitions: System alarm type definitions (seeded)
-- ========================================
CREATE TABLE IF NOT EXISTS alarm_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identification
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT,

    -- Classification
    category VARCHAR(50) NOT NULL CHECK (category IN ('business', 'scheduled', 'system')),
    trigger_type VARCHAR(20) NOT NULL CHECK (trigger_type IN ('scheduled', 'event', 'both')),
    default_priority VARCHAR(20) NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('low', 'normal', 'high', 'critical')),

    -- Configuration schema (defines what thresholds can be configured)
    threshold_schema JSONB DEFAULT '{}',

    -- Service responsible for checking this alarm
    check_service VARCHAR(100),
    check_method VARCHAR(100),

    -- Default settings
    default_channels JSONB DEFAULT '["push"]',
    default_cooldown_minutes INT DEFAULT 60,
    supports_shop_scope BOOLEAN DEFAULT true,

    -- Status
    is_active BOOLEAN DEFAULT true,
    is_system BOOLEAN DEFAULT true,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for alarm_definitions
CREATE INDEX IF NOT EXISTS idx_alarm_definitions_code ON alarm_definitions(code);
CREATE INDEX IF NOT EXISTS idx_alarm_definitions_category ON alarm_definitions(category);
CREATE INDEX IF NOT EXISTS idx_alarm_definitions_active ON alarm_definitions(is_active) WHERE is_active = true;

-- ========================================
-- alarm_configurations: Tenant-specific alarm configurations
-- ========================================
CREATE TABLE IF NOT EXISTS alarm_configurations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,

    -- Reference to definition
    alarm_definition_id UUID NOT NULL REFERENCES alarm_definitions(id) ON DELETE CASCADE,
    alarm_code VARCHAR(50) NOT NULL,

    -- Configuration
    is_enabled BOOLEAN DEFAULT true,
    priority VARCHAR(20) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),

    -- Thresholds (specific to alarm type)
    thresholds JSONB DEFAULT '{}',

    -- Schedule configuration
    schedule_type VARCHAR(20) CHECK (schedule_type IN ('cron', 'preset', 'event_only')),
    cron_expression VARCHAR(50),
    preset_schedule VARCHAR(50),
    timezone VARCHAR(50) DEFAULT 'Asia/Kolkata',

    -- Notification channels
    channels JSONB DEFAULT '["push"]',

    -- Recipients configuration
    recipients JSONB DEFAULT '{}',
    -- Format: {"roles": ["owner", "manager"], "user_ids": ["uuid1", "uuid2"], "notify_creator": true}

    -- Rate limiting
    cooldown_minutes INT DEFAULT 60,
    max_alerts_per_day INT DEFAULT 100,

    -- Quiet hours (bypass for critical)
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    bypass_quiet_for_critical BOOLEAN DEFAULT true,

    -- Custom message templates
    custom_title_template TEXT,
    custom_message_template TEXT,

    -- Audit
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT uq_alarm_config_tenant_shop_code UNIQUE(tenant_id, shop_id, alarm_code)
);

-- Indexes for alarm_configurations
CREATE INDEX IF NOT EXISTS idx_alarm_configs_tenant ON alarm_configurations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alarm_configs_shop ON alarm_configurations(shop_id);
CREATE INDEX IF NOT EXISTS idx_alarm_configs_code ON alarm_configurations(alarm_code);
CREATE INDEX IF NOT EXISTS idx_alarm_configs_enabled ON alarm_configurations(is_enabled) WHERE is_enabled = true;
CREATE INDEX IF NOT EXISTS idx_alarm_configs_tenant_enabled ON alarm_configurations(tenant_id, is_enabled) WHERE is_enabled = true;

-- ========================================
-- alarm_instances: Generated alarm records
-- ========================================
CREATE TABLE IF NOT EXISTS alarm_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE SET NULL,

    -- Reference
    alarm_config_id UUID REFERENCES alarm_configurations(id) ON DELETE SET NULL,
    alarm_code VARCHAR(50) NOT NULL,

    -- Alert content
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    priority VARCHAR(20) NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),

    -- Status workflow
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'acknowledged', 'resolved', 'expired', 'snoozed')),

    -- Context data
    trigger_data JSONB DEFAULT '{}',
    related_entity_type VARCHAR(50),
    related_entity_id UUID,

    -- Timing
    triggered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    acknowledged_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by UUID REFERENCES users(id),
    resolution_notes TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    snoozed_until TIMESTAMP WITH TIME ZONE,

    -- Delivery tracking
    notification_id UUID REFERENCES notifications(id),
    channels_sent JSONB DEFAULT '[]',
    delivery_status JSONB DEFAULT '{}',

    -- Escalation
    escalation_level INT DEFAULT 0,
    escalated_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for alarm_instances
CREATE INDEX IF NOT EXISTS idx_alarm_instances_tenant ON alarm_instances(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alarm_instances_shop ON alarm_instances(shop_id);
CREATE INDEX IF NOT EXISTS idx_alarm_instances_code ON alarm_instances(alarm_code);
CREATE INDEX IF NOT EXISTS idx_alarm_instances_status ON alarm_instances(status);
CREATE INDEX IF NOT EXISTS idx_alarm_instances_active ON alarm_instances(tenant_id, status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_alarm_instances_triggered ON alarm_instances(triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_alarm_instances_entity ON alarm_instances(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_alarm_instances_config_entity ON alarm_instances(alarm_config_id, related_entity_id);

-- Unique constraint for cooldown checking (one active alarm per config+entity per day)
-- Note: Using date_trunc is STABLE not IMMUTABLE for timestamptz, so we use a compound index
-- The application layer will handle cooldown checking using a query instead
CREATE INDEX IF NOT EXISTS idx_alarm_instances_cooldown
ON alarm_instances(alarm_config_id, related_entity_id, triggered_at)
WHERE status IN ('active', 'acknowledged');

-- ========================================
-- alarm_schedule_runs: Track scheduled check executions
-- ========================================
CREATE TABLE IF NOT EXISTS alarm_schedule_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alarm_config_id UUID NOT NULL REFERENCES alarm_configurations(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Run details
    scheduled_for TIMESTAMP WITH TIME ZONE NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Status
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped')),

    -- Results
    items_checked INT DEFAULT 0,
    alarms_triggered INT DEFAULT 0,
    error_message TEXT,
    run_metadata JSONB DEFAULT '{}',

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for alarm_schedule_runs
CREATE INDEX IF NOT EXISTS idx_alarm_runs_config ON alarm_schedule_runs(alarm_config_id);
CREATE INDEX IF NOT EXISTS idx_alarm_runs_tenant ON alarm_schedule_runs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alarm_runs_scheduled ON alarm_schedule_runs(scheduled_for);
CREATE INDEX IF NOT EXISTS idx_alarm_runs_status ON alarm_schedule_runs(status) WHERE status = 'pending';

-- ========================================
-- alarm_recipients: Pre-computed recipients for each alarm config
-- ========================================
CREATE TABLE IF NOT EXISTS alarm_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alarm_config_id UUID NOT NULL REFERENCES alarm_configurations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Recipient details (denormalized for performance)
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Delivery preferences
    channels JSONB DEFAULT '["push"]',

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_alarm_recipient UNIQUE(alarm_config_id, user_id)
);

-- Index for alarm_recipients
CREATE INDEX IF NOT EXISTS idx_alarm_recipients_config ON alarm_recipients(alarm_config_id);
CREATE INDEX IF NOT EXISTS idx_alarm_recipients_user ON alarm_recipients(user_id);

-- ========================================
-- Update triggers
-- ========================================
CREATE OR REPLACE FUNCTION update_alarm_tables_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_alarm_definitions_updated_at ON alarm_definitions;
CREATE TRIGGER trg_alarm_definitions_updated_at
    BEFORE UPDATE ON alarm_definitions
    FOR EACH ROW EXECUTE FUNCTION update_alarm_tables_updated_at();

DROP TRIGGER IF EXISTS trg_alarm_configurations_updated_at ON alarm_configurations;
CREATE TRIGGER trg_alarm_configurations_updated_at
    BEFORE UPDATE ON alarm_configurations
    FOR EACH ROW EXECUTE FUNCTION update_alarm_tables_updated_at();

DROP TRIGGER IF EXISTS trg_alarm_instances_updated_at ON alarm_instances;
CREATE TRIGGER trg_alarm_instances_updated_at
    BEFORE UPDATE ON alarm_instances
    FOR EACH ROW EXECUTE FUNCTION update_alarm_tables_updated_at();

DROP TRIGGER IF EXISTS trg_alarm_schedule_runs_updated_at ON alarm_schedule_runs;
CREATE TRIGGER trg_alarm_schedule_runs_updated_at
    BEFORE UPDATE ON alarm_schedule_runs
    FOR EACH ROW EXECUTE FUNCTION update_alarm_tables_updated_at();

COMMIT;

-- ========================================
-- Seed alarm definitions
-- ========================================
INSERT INTO alarm_definitions (code, name, description, category, trigger_type, default_priority, threshold_schema, check_service, check_method, default_channels, default_cooldown_minutes, supports_shop_scope)
VALUES
    -- Business Alerts
    ('low_stock', 'Low Stock Alert', 'Triggered when product stock falls below threshold', 'business', 'both', 'high',
     '{"min_quantity": {"type": "number", "label": "Minimum Quantity", "default": 10}, "products": {"type": "array", "label": "Specific Products (optional)"}}',
     'AlarmCheckerService', 'CheckLowStock', '["push", "email"]', 60, true),

    ('cash_shortage', 'Cash Shortage Alert', 'Triggered when cash variance exceeds threshold', 'business', 'event', 'critical',
     '{"max_variance_percent": {"type": "number", "label": "Max Variance %", "default": 5}, "max_variance_amount": {"type": "number", "label": "Max Variance Amount", "default": 500}}',
     'AlarmCheckerService', 'CheckCashShortage', '["push", "email"]', 30, true),

    ('collection_overdue', 'Collection Overdue Alert', 'Triggered when credit collection is overdue', 'business', 'both', 'high',
     '{"days_overdue": {"type": "number", "label": "Days Overdue", "default": 7}, "min_amount": {"type": "number", "label": "Min Amount", "default": 1000}}',
     'AlarmCheckerService', 'CheckCollectionOverdue', '["push", "email"]', 1440, true),

    ('high_discount_usage', 'High Discount Usage Alert', 'Triggered when discount usage exceeds threshold', 'business', 'scheduled', 'high',
     '{"max_discount_percent": {"type": "number", "label": "Max Total Discount %", "default": 15}, "check_period_hours": {"type": "number", "label": "Check Period (hours)", "default": 24}}',
     'AlarmCheckerService', 'CheckHighDiscountUsage', '["push"]', 1440, true),

    ('sales_anomaly', 'Sales Anomaly Alert', 'Triggered when sales deviate significantly from expected', 'business', 'scheduled', 'normal',
     '{"deviation_threshold_percent": {"type": "number", "label": "Deviation Threshold %", "default": 30}}',
     'AlarmCheckerService', 'CheckSalesAnomaly', '["push"]', 1440, true),

    -- Scheduled Reports
    ('daily_sales_summary', 'Daily Sales Summary', 'Daily summary of sales performance', 'scheduled', 'scheduled', 'normal',
     '{"include_comparison": {"type": "boolean", "label": "Include Previous Day Comparison", "default": true}}',
     'AlarmCheckerService', 'GenerateDailySummary', '["push", "email"]', 1440, true),

    ('weekly_report', 'Weekly Business Report', 'Weekly summary of business performance', 'scheduled', 'scheduled', 'normal',
     '{"include_charts": {"type": "boolean", "label": "Include Charts", "default": true}}',
     'AlarmCheckerService', 'GenerateWeeklyReport', '["email"]', 10080, true),

    ('audit_reminder', 'Audit Reminder', 'Reminder for upcoming or overdue audits', 'scheduled', 'scheduled', 'high',
     '{"days_before": {"type": "number", "label": "Days Before Due", "default": 1}}',
     'AlarmCheckerService', 'CheckAuditReminder', '["push"]', 1440, true),

    ('end_of_day_report', 'End of Day Report', 'Daily closing summary report', 'scheduled', 'scheduled', 'normal',
     '{"include_inventory": {"type": "boolean", "label": "Include Inventory Summary", "default": true}, "include_cash": {"type": "boolean", "label": "Include Cash Summary", "default": true}}',
     'AlarmCheckerService', 'GenerateEODReport', '["push", "email"]', 1440, true),

    -- System Alerts
    ('usage_limit_approaching', 'Usage Limit Approaching', 'Triggered when usage approaches subscription limit', 'system', 'scheduled', 'high',
     '{"threshold_percent": {"type": "number", "label": "Threshold %", "default": 80}}',
     'AlarmCheckerService', 'CheckUsageLimits', '["push", "email"]', 1440, false),

    ('subscription_expiry', 'Subscription Expiry Warning', 'Triggered before subscription expires', 'system', 'scheduled', 'critical',
     '{"days_before": {"type": "number", "label": "Days Before Expiry", "default": 7}}',
     'AlarmCheckerService', 'CheckSubscriptionExpiry', '["push", "email"]', 1440, false),

    ('system_maintenance', 'System Maintenance Notice', 'Notification about scheduled maintenance', 'system', 'event', 'normal',
     '{}',
     NULL, NULL, '["push", "email"]', 60, false)

ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    trigger_type = EXCLUDED.trigger_type,
    default_priority = EXCLUDED.default_priority,
    threshold_schema = EXCLUDED.threshold_schema,
    check_service = EXCLUDED.check_service,
    check_method = EXCLUDED.check_method,
    default_channels = EXCLUDED.default_channels,
    default_cooldown_minutes = EXCLUDED.default_cooldown_minutes,
    supports_shop_scope = EXCLUDED.supports_shop_scope,
    updated_at = CURRENT_TIMESTAMP;

-- ========================================
-- Verification
-- ========================================
SELECT '=== ALARM SYSTEM TABLES CREATED ===' as info;

SELECT
    'Tables Created' as check_type,
    COUNT(*) as count
FROM information_schema.tables
WHERE table_name IN ('alarm_definitions', 'alarm_configurations', 'alarm_instances', 'alarm_schedule_runs', 'alarm_recipients');

SELECT
    'Alarm Definitions Seeded' as check_type,
    COUNT(*) as count
FROM alarm_definitions;

SELECT code, name, category, trigger_type, default_priority
FROM alarm_definitions
ORDER BY category, code;
