-- Create Theft Detection Tables
-- Date: 2025-12-01
-- Description: Cash variances, suspicious activities, investigations, alerts, detection metrics

BEGIN;

-- ========================================
-- 1. investigations: Formal investigation tracking (create first due to FK dependencies)
-- ========================================
CREATE TABLE IF NOT EXISTS investigations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE SET NULL, -- NULL for cross-shop investigations

    -- Case Identification
    case_number VARCHAR(50) NOT NULL, -- e.g., 'INV-2025-00001'
    title VARCHAR(255) NOT NULL,
    description TEXT,

    -- Investigation Type
    investigation_type VARCHAR(50) NOT NULL,
    -- 'cash_shortage', 'inventory_shrinkage', 'discount_abuse', 'void_abuse',
    -- 'return_fraud', 'theft', 'policy_violation', 'other'

    -- Subjects Under Investigation
    subject_user_ids JSONB, -- Array of user UUIDs
    subject_names TEXT, -- Comma-separated names for quick reference

    -- Financial Impact
    estimated_loss DECIMAL(12,2),
    confirmed_loss DECIMAL(12,2),
    recovered_amount DECIMAL(12,2) DEFAULT 0,

    -- Timeline
    incident_start_date DATE,
    incident_end_date DATE,
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,

    -- Status Workflow
    status VARCHAR(30) DEFAULT 'open',
    -- 'open', 'in_progress', 'pending_review', 'pending_approval',
    -- 'closed_confirmed', 'closed_unfounded', 'closed_inconclusive'

    priority VARCHAR(20) DEFAULT 'medium', -- low, medium, high, critical

    -- Assignment
    lead_investigator_id UUID REFERENCES users(id),
    assigned_to JSONB, -- Array of {user_id, assigned_at, role}

    -- Evidence
    evidence_files JSONB, -- Array of {filename, path, type, uploaded_at, uploaded_by}
    evidence_summary TEXT,

    -- Findings & Resolution
    findings TEXT,
    root_cause TEXT,
    recommendations TEXT,
    actions_taken TEXT,
    preventive_measures TEXT,

    -- Approval Workflow
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT uq_investigation_case_number UNIQUE(case_number)
);

-- Indexes for investigations
CREATE INDEX IF NOT EXISTS idx_investigations_tenant ON investigations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_investigations_shop ON investigations(shop_id);
CREATE INDEX IF NOT EXISTS idx_investigations_type ON investigations(investigation_type);
CREATE INDEX IF NOT EXISTS idx_investigations_status ON investigations(status);
CREATE INDEX IF NOT EXISTS idx_investigations_priority ON investigations(priority);
CREATE INDEX IF NOT EXISTS idx_investigations_lead ON investigations(lead_investigator_id);
CREATE INDEX IF NOT EXISTS idx_investigations_opened ON investigations(opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_investigations_open_status ON investigations(status) WHERE status NOT IN ('closed_confirmed', 'closed_unfounded', 'closed_inconclusive');

-- ========================================
-- 2. investigation_notes: Notes and updates on investigations
-- ========================================
CREATE TABLE IF NOT EXISTS investigation_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    investigation_id UUID NOT NULL REFERENCES investigations(id) ON DELETE CASCADE,

    -- Note Details
    note_type VARCHAR(30) DEFAULT 'general',
    -- 'general', 'status_change', 'evidence_added', 'interview', 'finding', 'action_taken'
    content TEXT NOT NULL,

    -- Attachments
    attachments JSONB, -- Array of {filename, path, type}

    -- Visibility
    is_internal BOOLEAN DEFAULT TRUE, -- Internal notes not visible to subjects
    is_pinned BOOLEAN DEFAULT FALSE,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for investigation_notes
CREATE INDEX IF NOT EXISTS idx_investigation_notes_investigation ON investigation_notes(investigation_id);
CREATE INDEX IF NOT EXISTS idx_investigation_notes_type ON investigation_notes(note_type);
CREATE INDEX IF NOT EXISTS idx_investigation_notes_created ON investigation_notes(created_at DESC);

-- ========================================
-- 3. cash_variances: Cash shortage/overage tracking
-- ========================================
CREATE TABLE IF NOT EXISTS cash_variances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Date/Shift
    variance_date DATE NOT NULL,
    shift VARCHAR(20), -- morning, evening, night, NULL = full day

    -- Expected vs Actual
    expected_cash DECIMAL(12,2) NOT NULL,
    actual_cash DECIMAL(12,2) NOT NULL,
    variance_amount DECIMAL(12,2) NOT NULL, -- actual - expected (negative = shortage)
    variance_percentage DECIMAL(5,2),

    -- Breakdown (for analysis)
    opening_balance DECIMAL(12,2),
    cash_sales DECIMAL(12,2),
    card_sales DECIMAL(12,2),
    upi_sales DECIMAL(12,2),
    credit_sales DECIMAL(12,2),
    deposits_made DECIMAL(12,2),
    petty_cash_used DECIMAL(12,2),
    cash_in_drawer DECIMAL(12,2),
    cash_with_staff JSONB, -- [{user_id, name, amount}]

    -- Classification
    variance_type VARCHAR(30), -- 'shortage', 'overage', 'balanced'
    severity VARCHAR(20) DEFAULT 'info', -- info, low, medium, high, critical

    -- Attribution
    responsible_staff JSONB, -- Array of {user_id, name, role, shift_portion, status}
    primary_responsible_id UUID REFERENCES users(id),

    -- Investigation Link
    investigation_id UUID REFERENCES investigations(id) ON DELETE SET NULL,

    -- Status & Resolution
    status VARCHAR(30) DEFAULT 'pending',
    -- 'pending', 'investigating', 'explained', 'unresolved', 'theft_confirmed', 'recovered'

    explanation TEXT,
    resolution_notes TEXT,
    recovery_amount DECIMAL(12,2) DEFAULT 0,

    -- Review
    calculated_by UUID REFERENCES users(id),
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_cash_variance UNIQUE(shop_id, variance_date, shift)
);

-- Indexes for cash_variances
CREATE INDEX IF NOT EXISTS idx_cash_variances_tenant ON cash_variances(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_variances_shop ON cash_variances(shop_id);
CREATE INDEX IF NOT EXISTS idx_cash_variances_date ON cash_variances(variance_date DESC);
CREATE INDEX IF NOT EXISTS idx_cash_variances_type ON cash_variances(variance_type);
CREATE INDEX IF NOT EXISTS idx_cash_variances_severity ON cash_variances(severity);
CREATE INDEX IF NOT EXISTS idx_cash_variances_status ON cash_variances(status);
CREATE INDEX IF NOT EXISTS idx_cash_variances_responsible ON cash_variances(primary_responsible_id);
CREATE INDEX IF NOT EXISTS idx_cash_variances_investigation ON cash_variances(investigation_id);
CREATE INDEX IF NOT EXISTS idx_cash_variances_unresolved ON cash_variances(status) WHERE status NOT IN ('explained', 'recovered');

-- ========================================
-- 4. suspicious_activities: Detected anomalies and patterns
-- ========================================
CREATE TABLE IF NOT EXISTS suspicious_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Detection Type
    detection_type VARCHAR(50) NOT NULL,
    -- 'excessive_discount', 'void_pattern', 'price_override', 'return_abuse',
    -- 'cash_shortage_pattern', 'inventory_shrinkage', 'time_anomaly',
    -- 'transaction_pattern', 'refund_pattern', 'same_customer_discount',
    -- 'split_transaction', 'after_hours_activity', 'bulk_void'

    -- Who
    user_id UUID REFERENCES users(id),
    user_name VARCHAR(255),
    user_role VARCHAR(50),

    -- What
    activity_description TEXT NOT NULL,
    summary TEXT, -- Brief summary for list views

    -- Related Data
    related_transactions JSONB, -- Array of transaction IDs
    related_products JSONB, -- Array of product IDs
    related_customers JSONB, -- Array of customer info

    -- Metrics
    total_impact DECIMAL(12,2), -- Financial impact
    occurrence_count INTEGER DEFAULT 1,
    period_days INTEGER, -- Over what period

    -- Statistical Scores
    frequency_score DECIMAL(5,2), -- How often vs normal
    deviation_score DECIMAL(5,2), -- Standard deviations from mean (Z-score)
    confidence_score DECIMAL(5,2), -- Detection confidence 0-100%

    -- Detection Details
    detection_rule VARCHAR(100), -- Name of rule that triggered
    detection_parameters JSONB, -- Parameters used for detection
    benchmark_value DECIMAL(15,2), -- What was expected/normal
    actual_value DECIMAL(15,2), -- What was observed

    -- Time Context
    activity_start_date TIMESTAMP WITH TIME ZONE,
    activity_end_date TIMESTAMP WITH TIME ZONE,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Classification
    severity VARCHAR(20) NOT NULL, -- low, medium, high, critical
    risk_level INTEGER DEFAULT 0, -- 0-100 composite score
    category VARCHAR(50), -- finance, inventory, operations

    -- Status Workflow
    status VARCHAR(30) DEFAULT 'new',
    -- 'new', 'acknowledged', 'investigating', 'false_positive', 'confirmed', 'resolved'

    -- Investigation Link
    investigation_id UUID REFERENCES investigations(id) ON DELETE SET NULL,

    -- Acknowledgment
    acknowledged_by UUID REFERENCES users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    acknowledgment_notes TEXT,

    -- Resolution
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_type VARCHAR(50), -- 'false_positive', 'warning_issued', 'training', 'disciplinary', 'termination'
    resolution_notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for suspicious_activities
CREATE INDEX IF NOT EXISTS idx_suspicious_tenant ON suspicious_activities(tenant_id);
CREATE INDEX IF NOT EXISTS idx_suspicious_shop ON suspicious_activities(shop_id);
CREATE INDEX IF NOT EXISTS idx_suspicious_user ON suspicious_activities(user_id);
CREATE INDEX IF NOT EXISTS idx_suspicious_type ON suspicious_activities(detection_type);
CREATE INDEX IF NOT EXISTS idx_suspicious_severity ON suspicious_activities(severity);
CREATE INDEX IF NOT EXISTS idx_suspicious_status ON suspicious_activities(status);
CREATE INDEX IF NOT EXISTS idx_suspicious_risk ON suspicious_activities(risk_level DESC);
CREATE INDEX IF NOT EXISTS idx_suspicious_detected ON suspicious_activities(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_suspicious_investigation ON suspicious_activities(investigation_id);
CREATE INDEX IF NOT EXISTS idx_suspicious_unresolved ON suspicious_activities(status) WHERE status NOT IN ('false_positive', 'resolved');
CREATE INDEX IF NOT EXISTS idx_suspicious_user_pattern ON suspicious_activities(user_id, detection_type);

-- ========================================
-- 5. alert_configurations: Configurable detection thresholds
-- ========================================
CREATE TABLE IF NOT EXISTS alert_configurations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE, -- NULL for tenant-wide config

    -- Alert Type
    alert_type VARCHAR(50) NOT NULL,
    -- 'cash_shortage', 'inventory_shrinkage', 'excessive_discount', 'void_abuse',
    -- 'return_abuse', 'low_stock', 'overdue_collection', 'budget_exceeded'

    name VARCHAR(255),
    description TEXT,

    -- Status
    is_enabled BOOLEAN DEFAULT TRUE,

    -- Thresholds (JSONB for flexibility)
    thresholds JSONB NOT NULL,
    /* Example:
    {
        "amount": 500,           // Absolute amount threshold
        "percentage": 2,         // Percentage threshold
        "count": 5,              // Count threshold
        "period_days": 7         // Period for counting
    }
    */

    -- Severity Rules
    severity_rules JSONB,
    /* Example:
    {
        "info": {"min": 0, "max": 100},
        "low": {"min": 100, "max": 500},
        "medium": {"min": 500, "max": 2000},
        "high": {"min": 2000, "max": 5000},
        "critical": {"min": 5000}
    }
    */

    -- Notification Settings
    notification_channels JSONB DEFAULT '["in_app"]',
    -- ["in_app", "push", "email", "sms", "whatsapp"]

    notification_recipients JSONB,
    /* Example:
    {
        "roles": ["manager", "admin", "owner"],
        "user_ids": ["uuid1", "uuid2"],
        "severity_overrides": {
            "critical": {"channels": ["sms", "whatsapp"], "roles": ["owner"]}
        }
    }
    */

    -- Escalation
    escalation_enabled BOOLEAN DEFAULT FALSE,
    escalation_rules JSONB,
    /* Example:
    {
        "level_1": {"delay_hours": 24, "notify_roles": ["manager"]},
        "level_2": {"delay_hours": 48, "notify_roles": ["admin"]},
        "level_3": {"delay_hours": 72, "notify_roles": ["owner"]}
    }
    */

    -- Schedule
    check_frequency VARCHAR(30) DEFAULT 'daily', -- real_time, hourly, daily, weekly
    check_schedule JSONB, -- Cron-like schedule for specific timing

    -- Quiet Hours (don't send notifications)
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    respect_quiet_hours BOOLEAN DEFAULT TRUE,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_alert_config UNIQUE(tenant_id, shop_id, alert_type)
);

-- Indexes for alert_configurations
CREATE INDEX IF NOT EXISTS idx_alert_config_tenant ON alert_configurations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alert_config_shop ON alert_configurations(shop_id);
CREATE INDEX IF NOT EXISTS idx_alert_config_type ON alert_configurations(alert_type);
CREATE INDEX IF NOT EXISTS idx_alert_config_enabled ON alert_configurations(is_enabled) WHERE is_enabled = TRUE;

-- ========================================
-- 6. detection_alerts: Generated alerts from detection system
-- ========================================
CREATE TABLE IF NOT EXISTS detection_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Alert Type & Config Reference
    alert_type VARCHAR(50) NOT NULL,
    alert_config_id UUID REFERENCES alert_configurations(id) ON DELETE SET NULL,

    -- Severity
    severity VARCHAR(20) NOT NULL, -- info, warning, critical

    -- Content
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    details JSONB, -- Additional structured data

    -- Reference
    reference_type VARCHAR(50), -- cash_variance, suspicious_activity, shrinkage_record, etc.
    reference_id UUID,

    -- Status
    status VARCHAR(30) DEFAULT 'pending',
    -- 'pending', 'sent', 'acknowledged', 'resolved', 'escalated', 'expired'

    -- Escalation
    escalation_level INTEGER DEFAULT 0,
    escalated_at TIMESTAMP WITH TIME ZONE,
    next_escalation_at TIMESTAMP WITH TIME ZONE,

    -- Acknowledgment
    acknowledged_by UUID REFERENCES users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    acknowledgment_notes TEXT,

    -- Resolution
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,

    -- Notifications Sent
    notifications_sent JSONB,
    /* Array of:
    {
        "channel": "push",
        "recipient_id": "uuid",
        "sent_at": "timestamp",
        "status": "delivered",
        "error": null
    }
    */

    -- Timing
    triggered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for detection_alerts
CREATE INDEX IF NOT EXISTS idx_detection_alerts_tenant ON detection_alerts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_detection_alerts_shop ON detection_alerts(shop_id);
CREATE INDEX IF NOT EXISTS idx_detection_alerts_type ON detection_alerts(alert_type);
CREATE INDEX IF NOT EXISTS idx_detection_alerts_severity ON detection_alerts(severity);
CREATE INDEX IF NOT EXISTS idx_detection_alerts_status ON detection_alerts(status);
CREATE INDEX IF NOT EXISTS idx_detection_alerts_triggered ON detection_alerts(triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_detection_alerts_pending ON detection_alerts(status) WHERE status IN ('pending', 'sent');
CREATE INDEX IF NOT EXISTS idx_detection_alerts_escalation ON detection_alerts(next_escalation_at) WHERE status = 'sent' AND next_escalation_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_detection_alerts_expires ON detection_alerts(expires_at) WHERE expires_at IS NOT NULL AND status IN ('pending', 'sent');

-- ========================================
-- 7. detection_metrics: Statistical data for ML readiness
-- ========================================
CREATE TABLE IF NOT EXISTS detection_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Metric Identification
    metric_type VARCHAR(50) NOT NULL,
    -- 'daily_cash_variance', 'daily_discount_rate', 'daily_void_count',
    -- 'daily_shrinkage_rate', 'daily_sales_amount', etc.

    metric_date DATE NOT NULL,

    -- Statistical Data
    mean_value DECIMAL(12,4),
    std_deviation DECIMAL(12,4),
    min_value DECIMAL(12,4),
    max_value DECIMAL(12,4),
    median_value DECIMAL(12,4),
    sample_count INTEGER,

    -- Moving Averages
    moving_avg_7d DECIMAL(12,4),
    moving_avg_30d DECIMAL(12,4),
    moving_avg_90d DECIMAL(12,4),

    -- Trend
    trend_direction VARCHAR(20), -- increasing, decreasing, stable
    trend_strength DECIMAL(5,4), -- Correlation coefficient

    -- Additional Context
    metadata JSONB, -- Any additional data needed for analysis

    -- Audit
    computed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_detection_metrics UNIQUE(shop_id, metric_type, metric_date)
);

-- Indexes for detection_metrics
CREATE INDEX IF NOT EXISTS idx_detection_metrics_tenant ON detection_metrics(tenant_id);
CREATE INDEX IF NOT EXISTS idx_detection_metrics_shop ON detection_metrics(shop_id);
CREATE INDEX IF NOT EXISTS idx_detection_metrics_type ON detection_metrics(metric_type);
CREATE INDEX IF NOT EXISTS idx_detection_metrics_date ON detection_metrics(metric_date DESC);
CREATE INDEX IF NOT EXISTS idx_detection_metrics_shop_type ON detection_metrics(shop_id, metric_type, metric_date DESC);

-- ========================================
-- 8. Add investigation_id FK to shrinkage_records (from 040 migration)
-- ========================================
ALTER TABLE shrinkage_records
    ADD CONSTRAINT fk_shrinkage_investigation
    FOREIGN KEY (investigation_id)
    REFERENCES investigations(id)
    ON DELETE SET NULL;

COMMIT;

-- ========================================
-- Seed Default Alert Configurations
-- ========================================
BEGIN;

-- Insert default alert configurations for each tenant
INSERT INTO alert_configurations (tenant_id, alert_type, name, description, is_enabled, thresholds, severity_rules, notification_channels, check_frequency, created_by)
SELECT
    t.id as tenant_id,
    config.alert_type,
    config.name,
    config.description,
    true,
    config.thresholds::jsonb,
    config.severity_rules::jsonb,
    '["in_app", "push"]'::jsonb,
    config.check_frequency,
    (SELECT id FROM users WHERE tenant_id = t.id AND role = 'admin' LIMIT 1)
FROM tenants t
CROSS JOIN (VALUES
    ('cash_shortage', 'Cash Shortage Alert', 'Alerts when actual cash is less than expected', '{"percentage": 1, "amount": 500}', '{"info": {"max": 100}, "low": {"min": 100, "max": 500}, "medium": {"min": 500, "max": 2000}, "high": {"min": 2000, "max": 5000}, "critical": {"min": 5000}}', 'daily'),
    ('inventory_shrinkage', 'Inventory Shrinkage Alert', 'Alerts when inventory shrinkage exceeds threshold', '{"percentage": 3, "value": 5000}', '{"low": {"max": 2}, "medium": {"min": 2, "max": 5}, "high": {"min": 5, "max": 10}, "critical": {"min": 10}}', 'daily'),
    ('excessive_discount', 'Excessive Discount Alert', 'Alerts when discount patterns are unusual', '{"percentage": 15, "count": 10, "period_days": 7}', '{"low": {"max": 15}, "medium": {"min": 15, "max": 25}, "high": {"min": 25}}', 'weekly'),
    ('void_abuse', 'Void Transaction Alert', 'Alerts when void patterns are unusual', '{"count": 5, "period_days": 1}', '{"low": {"max": 5}, "medium": {"min": 5, "max": 10}, "high": {"min": 10}}', 'daily'),
    ('overdue_collection', 'Overdue Collection Alert', 'Alerts for money collections past deadline', '{"minutes_overdue": 30}', '{"warning": {"max": 30}, "critical": {"min": 30}}', 'real_time')
) AS config(alert_type, name, description, thresholds, severity_rules, check_frequency)
WHERE EXISTS (SELECT 1 FROM users WHERE tenant_id = t.id AND role = 'admin')
ON CONFLICT (tenant_id, shop_id, alert_type) DO NOTHING;

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== THEFT DETECTION TABLES CREATED ===' as info;

SELECT
    'investigations' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'investigations') as column_count;

SELECT
    'investigation_notes' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'investigation_notes') as column_count;

SELECT
    'cash_variances' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'cash_variances') as column_count;

SELECT
    'suspicious_activities' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'suspicious_activities') as column_count;

SELECT
    'alert_configurations' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'alert_configurations') as column_count;

SELECT
    'detection_alerts' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'detection_alerts') as column_count;

SELECT
    'detection_metrics' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'detection_metrics') as column_count;

-- Show default alert configurations
SELECT 'Default Alert Configurations:' as info;
SELECT
    t.name as tenant_name,
    COUNT(ac.id) as config_count
FROM tenants t
LEFT JOIN alert_configurations ac ON t.id = ac.tenant_id
GROUP BY t.id, t.name
ORDER BY t.name;
