-- Create Notification System Tables
-- Date: 2025-12-01
-- Description: Multi-channel notifications - In-app, Push, Email, SMS, WhatsApp

BEGIN;

-- ========================================
-- 1. notification_preferences: User notification preferences
-- ========================================
CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Channel Preferences
    channels JSONB DEFAULT '{
        "in_app": true,
        "push": true,
        "email": true,
        "sms": false,
        "whatsapp": false
    }',

    -- Alert Type Preferences (which alerts to receive)
    alert_types JSONB DEFAULT '{
        "cash_shortage": true,
        "inventory_shrinkage": true,
        "suspicious_activity": true,
        "audit_reminder": true,
        "collection_overdue": true,
        "low_stock": true,
        "budget_exceeded": true
    }',

    -- Severity Filter (minimum severity to receive)
    minimum_severity VARCHAR(20) DEFAULT 'info', -- info, warning, critical

    -- Quiet Hours
    quiet_hours_enabled BOOLEAN DEFAULT FALSE,
    quiet_hours_start TIME DEFAULT '22:00',
    quiet_hours_end TIME DEFAULT '07:00',
    quiet_hours_exceptions JSONB DEFAULT '["critical"]', -- Severities that bypass quiet hours

    -- Frequency Controls
    digest_mode BOOLEAN DEFAULT FALSE, -- Send digest instead of individual notifications
    digest_frequency VARCHAR(20) DEFAULT 'daily', -- hourly, daily, weekly
    max_notifications_per_hour INTEGER DEFAULT 10,

    -- Device Tokens (for push notifications)
    push_tokens JSONB DEFAULT '[]',
    /* Array of:
    {
        "token": "string",
        "device_id": "string",
        "device_type": "ios/android/web",
        "added_at": "timestamp",
        "last_used": "timestamp"
    }
    */

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_notification_preferences UNIQUE(user_id)
);

-- Indexes for notification_preferences
CREATE INDEX IF NOT EXISTS idx_notification_prefs_tenant ON notification_preferences(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notification_prefs_user ON notification_preferences(user_id);

-- ========================================
-- 2. whatsapp_subscriptions: WhatsApp Business API integration
-- ========================================
CREATE TABLE IF NOT EXISTS whatsapp_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Phone Number
    phone_number VARCHAR(20) NOT NULL, -- With country code, e.g., +919876543210
    formatted_number VARCHAR(20), -- Formatted for display

    -- Verification
    is_verified BOOLEAN DEFAULT FALSE,
    verification_code VARCHAR(10),
    verification_sent_at TIMESTAMP WITH TIME ZONE,
    verification_attempts INTEGER DEFAULT 0,
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    deactivated_at TIMESTAMP WITH TIME ZONE,
    deactivation_reason TEXT,

    -- Opt-in/Opt-out
    opt_in_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    opt_out_at TIMESTAMP WITH TIME ZONE,
    consent_text TEXT, -- Record of what user agreed to

    -- Rate Limiting
    messages_sent_today INTEGER DEFAULT 0,
    last_message_at TIMESTAMP WITH TIME ZONE,
    daily_limit INTEGER DEFAULT 50,

    -- WhatsApp Specific
    whatsapp_user_id VARCHAR(100), -- WhatsApp's internal user ID if available
    last_interaction_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_whatsapp_user UNIQUE(user_id),
    CONSTRAINT uq_whatsapp_phone_tenant UNIQUE(tenant_id, phone_number)
);

-- Indexes for whatsapp_subscriptions
CREATE INDEX IF NOT EXISTS idx_whatsapp_tenant ON whatsapp_subscriptions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_user ON whatsapp_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_phone ON whatsapp_subscriptions(phone_number);
CREATE INDEX IF NOT EXISTS idx_whatsapp_verified ON whatsapp_subscriptions(is_verified, is_active);

-- ========================================
-- 3. notifications: Central notification storage
-- ========================================
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Notification Type
    notification_type VARCHAR(50) NOT NULL,
    -- 'alert', 'reminder', 'info', 'action_required', 'system'
    category VARCHAR(50), -- finance, inventory, sales, audit, system

    -- Severity
    severity VARCHAR(20) DEFAULT 'info', -- info, warning, critical

    -- Content
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    short_message VARCHAR(160), -- For SMS (160 char limit)

    -- Rich Content (for in-app/push)
    icon VARCHAR(50), -- Icon name or emoji
    image_url TEXT,
    action_url TEXT, -- Deep link
    action_label VARCHAR(100),
    action_data JSONB, -- Additional data for action handling

    -- Reference
    reference_type VARCHAR(50), -- alert, investigation, audit_session, etc.
    reference_id UUID,

    -- Status
    status VARCHAR(20) DEFAULT 'unread', -- unread, read, archived, deleted

    -- Timestamps
    read_at TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE,

    -- Expiry
    expires_at TIMESTAMP WITH TIME ZONE,
    is_persistent BOOLEAN DEFAULT FALSE,

    -- Grouping (for notification stacking)
    group_key VARCHAR(100), -- Notifications with same key can be grouped
    group_count INTEGER DEFAULT 1,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for notifications
CREATE INDEX IF NOT EXISTS idx_notifications_tenant ON notifications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(notification_type);
CREATE INDEX IF NOT EXISTS idx_notifications_severity ON notifications(severity);
CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications(status);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, status) WHERE status = 'unread';
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_expires ON notifications(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_reference ON notifications(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_notifications_group ON notifications(group_key) WHERE group_key IS NOT NULL;

-- ========================================
-- 4. notification_deliveries: Track delivery across channels
-- ========================================
CREATE TABLE IF NOT EXISTS notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Channel
    channel VARCHAR(20) NOT NULL, -- in_app, push, email, sms, whatsapp

    -- Status
    status VARCHAR(20) DEFAULT 'pending',
    -- 'pending', 'queued', 'sent', 'delivered', 'read', 'failed', 'bounced'

    -- Timestamps
    queued_at TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,

    -- Delivery Details
    provider VARCHAR(50), -- firebase, sendgrid, twilio, whatsapp_business
    provider_message_id VARCHAR(200),
    provider_response JSONB,

    -- Error Tracking
    error_code VARCHAR(50),
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    next_retry_at TIMESTAMP WITH TIME ZONE,

    -- Channel-specific data
    delivery_data JSONB,
    /* Examples:
    - Push: {"token": "...", "platform": "ios"}
    - Email: {"to": "email@...", "subject": "..."}
    - SMS: {"to": "+91...", "message_id": "..."}
    - WhatsApp: {"to": "+91...", "template": "alert_template"}
    */

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for notification_deliveries
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_notification ON notification_deliveries(notification_id);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user ON notification_deliveries(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_channel ON notification_deliveries(channel);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status ON notification_deliveries(status);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_pending ON notification_deliveries(status) WHERE status IN ('pending', 'queued');
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_retry ON notification_deliveries(next_retry_at) WHERE status = 'failed' AND retry_count < max_retries;
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_provider ON notification_deliveries(provider, provider_message_id);

-- ========================================
-- 5. notification_templates: Reusable notification templates
-- ========================================
CREATE TABLE IF NOT EXISTS notification_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE, -- NULL for system templates

    -- Template Identification
    template_key VARCHAR(100) NOT NULL, -- e.g., 'cash_shortage_alert'
    name VARCHAR(255) NOT NULL,
    description TEXT,

    -- Template Type
    notification_type VARCHAR(50) NOT NULL,
    category VARCHAR(50),
    default_severity VARCHAR(20) DEFAULT 'info',

    -- Content Templates (with placeholders like {{amount}}, {{shop_name}})
    title_template VARCHAR(255) NOT NULL,
    message_template TEXT NOT NULL,
    short_message_template VARCHAR(160), -- For SMS

    -- Channel-specific templates
    push_template JSONB, -- {title, body, icon, action}
    email_template JSONB, -- {subject, html_body, text_body}
    sms_template TEXT,
    whatsapp_template JSONB, -- {template_name, parameters}

    -- Default Action
    default_action_url TEXT,
    default_action_label VARCHAR(100),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    is_system BOOLEAN DEFAULT FALSE, -- System templates can't be deleted

    -- Audit
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_notification_template UNIQUE(tenant_id, template_key)
);

-- Indexes for notification_templates
CREATE INDEX IF NOT EXISTS idx_notification_templates_tenant ON notification_templates(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notification_templates_key ON notification_templates(template_key);
CREATE INDEX IF NOT EXISTS idx_notification_templates_type ON notification_templates(notification_type);
CREATE INDEX IF NOT EXISTS idx_notification_templates_active ON notification_templates(is_active) WHERE is_active = TRUE;

-- ========================================
-- 6. notification_digests: Batched notification digests
-- ========================================
CREATE TABLE IF NOT EXISTS notification_digests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Digest Period
    digest_type VARCHAR(20) NOT NULL, -- hourly, daily, weekly
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Summary
    notification_ids UUID[] NOT NULL,
    notification_count INTEGER NOT NULL,

    -- Breakdown by type
    summary_by_type JSONB,
    /* {
        "cash_shortage": 2,
        "inventory_shrinkage": 1,
        "audit_reminder": 3
    } */

    -- Breakdown by severity
    summary_by_severity JSONB,
    /* {
        "critical": 1,
        "warning": 3,
        "info": 2
    } */

    -- Status
    status VARCHAR(20) DEFAULT 'pending', -- pending, sent, failed

    -- Delivery
    sent_at TIMESTAMP WITH TIME ZONE,
    channels_sent TEXT[],

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for notification_digests
CREATE INDEX IF NOT EXISTS idx_notification_digests_tenant ON notification_digests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notification_digests_user ON notification_digests(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_digests_period ON notification_digests(period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_notification_digests_status ON notification_digests(status);

-- ========================================
-- 7. notification_rate_limits: Rate limiting per user/channel
-- ========================================
CREATE TABLE IF NOT EXISTS notification_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel VARCHAR(20) NOT NULL,

    -- Current Period
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Counts
    notifications_sent INTEGER DEFAULT 0,
    rate_limit INTEGER NOT NULL, -- Max per period

    -- Status
    is_limited BOOLEAN DEFAULT FALSE, -- True if rate limit exceeded

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_rate_limit UNIQUE(user_id, channel, period_start)
);

-- Indexes for notification_rate_limits
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_channel ON notification_rate_limits(user_id, channel);
CREATE INDEX IF NOT EXISTS idx_rate_limits_period ON notification_rate_limits(period_end);
CREATE INDEX IF NOT EXISTS idx_rate_limits_limited ON notification_rate_limits(is_limited) WHERE is_limited = TRUE;

COMMIT;

-- ========================================
-- Seed System Notification Templates
-- ========================================
BEGIN;

INSERT INTO notification_templates (
    template_key, name, description, notification_type, category, default_severity,
    title_template, message_template, short_message_template,
    push_template, email_template, sms_template, whatsapp_template,
    is_active, is_system
) VALUES
-- Cash Shortage Alert
(
    'cash_shortage_alert',
    'Cash Shortage Alert',
    'Alert when cash count shows shortage',
    'alert',
    'finance',
    'warning',
    'Cash Shortage: {{amount}}',
    'A cash shortage of {{amount}} has been detected at {{shop_name}} on {{date}}. Expected: {{expected}}, Actual: {{actual}}.',
    'Cash shortage of {{amount}} at {{shop_name}}',
    '{"title": "Cash Shortage Alert", "body": "{{amount}} shortage at {{shop_name}}", "icon": "cash_alert"}',
    '{"subject": "Cash Shortage Alert - {{shop_name}}", "text_body": "A cash shortage has been detected."}',
    'Cash shortage of {{amount}} detected at {{shop_name}}. Please investigate.',
    '{"template_name": "cash_shortage_alert", "parameters": ["amount", "shop_name", "date"]}',
    true,
    true
),
-- Inventory Shrinkage Alert
(
    'inventory_shrinkage_alert',
    'Inventory Shrinkage Alert',
    'Alert when inventory shrinkage exceeds threshold',
    'alert',
    'inventory',
    'warning',
    'Inventory Shrinkage: {{product_name}}',
    'Inventory shrinkage detected for {{product_name}} at {{shop_name}}. System: {{system_qty}}, Physical: {{physical_qty}}, Variance: {{variance_qty}} units ({{variance_value}}).',
    'Shrinkage: {{product_name}} - {{variance_qty}} units',
    '{"title": "Inventory Shrinkage", "body": "{{product_name}} variance: {{variance_qty}} units", "icon": "inventory_alert"}',
    '{"subject": "Inventory Shrinkage Alert - {{product_name}}", "text_body": "Inventory shrinkage detected."}',
    'Inventory shrinkage: {{product_name}} - {{variance_qty}} units at {{shop_name}}',
    '{"template_name": "inventory_shrinkage_alert", "parameters": ["product_name", "variance_qty", "shop_name"]}',
    true,
    true
),
-- Suspicious Activity Alert
(
    'suspicious_activity_alert',
    'Suspicious Activity Alert',
    'Alert for detected suspicious patterns',
    'alert',
    'security',
    'critical',
    'Suspicious Activity Detected',
    'Suspicious activity detected: {{activity_type}} by {{user_name}} at {{shop_name}}. {{description}}',
    'Suspicious: {{activity_type}} by {{user_name}}',
    '{"title": "Suspicious Activity", "body": "{{activity_type}} detected", "icon": "security_alert"}',
    '{"subject": "Suspicious Activity Alert", "text_body": "Suspicious activity requires investigation."}',
    'ALERT: Suspicious {{activity_type}} detected at {{shop_name}}. Investigate immediately.',
    '{"template_name": "suspicious_activity_alert", "parameters": ["activity_type", "user_name", "shop_name"]}',
    true,
    true
),
-- Audit Reminder
(
    'audit_reminder',
    'Audit Reminder',
    'Reminder for upcoming audit',
    'reminder',
    'audit',
    'info',
    'Audit Reminder: {{audit_type}}',
    'Reminder: {{audit_type}} audit is scheduled for {{shop_name}} at {{scheduled_time}}. Please ensure you are available.',
    'Audit reminder: {{audit_type}} at {{scheduled_time}}',
    '{"title": "Audit Reminder", "body": "{{audit_type}} at {{scheduled_time}}", "icon": "audit"}',
    '{"subject": "Audit Reminder - {{shop_name}}", "text_body": "Your scheduled audit is coming up."}',
    'Reminder: {{audit_type}} audit at {{shop_name}} scheduled for {{scheduled_time}}',
    '{"template_name": "audit_reminder", "parameters": ["audit_type", "shop_name", "scheduled_time"]}',
    true,
    true
),
-- Collection Overdue
(
    'collection_overdue',
    'Collection Overdue Alert',
    'Alert when money collection is past deadline',
    'alert',
    'finance',
    'critical',
    'Collection Overdue: {{amount}}',
    'Money collection of {{amount}} from {{collector_name}} is overdue by {{minutes}} minutes. Please follow up immediately.',
    'OVERDUE: {{amount}} collection - {{minutes}} min late',
    '{"title": "Collection Overdue", "body": "{{amount}} - {{minutes}} min overdue", "icon": "overdue_alert"}',
    '{"subject": "URGENT: Collection Overdue", "text_body": "A money collection is overdue."}',
    'URGENT: {{amount}} collection from {{collector_name}} overdue by {{minutes}} min',
    '{"template_name": "collection_overdue", "parameters": ["amount", "collector_name", "minutes"]}',
    true,
    true
),
-- Low Stock Alert
(
    'low_stock_alert',
    'Low Stock Alert',
    'Alert when stock falls below minimum level',
    'alert',
    'inventory',
    'warning',
    'Low Stock: {{product_name}}',
    '{{product_name}} stock is low at {{shop_name}}. Current: {{current_qty}}, Minimum: {{min_qty}}. Please reorder.',
    'Low stock: {{product_name}} - {{current_qty}} left',
    '{"title": "Low Stock Alert", "body": "{{product_name}} - {{current_qty}} remaining", "icon": "low_stock"}',
    '{"subject": "Low Stock Alert - {{product_name}}", "text_body": "Stock is running low."}',
    'Low stock alert: {{product_name}} at {{shop_name}} - {{current_qty}} remaining',
    '{"template_name": "low_stock_alert", "parameters": ["product_name", "shop_name", "current_qty"]}',
    true,
    true
)
ON CONFLICT (tenant_id, template_key) DO NOTHING;

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== NOTIFICATION SYSTEM TABLES CREATED ===' as info;

SELECT
    'notification_preferences' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notification_preferences') as column_count;

SELECT
    'whatsapp_subscriptions' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'whatsapp_subscriptions') as column_count;

SELECT
    'notifications' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notifications') as column_count;

SELECT
    'notification_deliveries' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notification_deliveries') as column_count;

SELECT
    'notification_templates' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notification_templates') as column_count;

SELECT
    'notification_digests' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notification_digests') as column_count;

SELECT
    'notification_rate_limits' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notification_rate_limits') as column_count;

-- Show system templates
SELECT 'System Notification Templates:' as info;
SELECT template_key, name, notification_type, default_severity
FROM notification_templates
WHERE is_system = TRUE
ORDER BY template_key;
