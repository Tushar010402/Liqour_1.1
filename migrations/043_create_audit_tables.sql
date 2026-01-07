-- Create Physical Audit Tables
-- Date: 2025-12-01
-- Description: Audit schedules, sessions, cash audits, inventory audits, variances

BEGIN;

-- ========================================
-- 1. audit_schedules: Configurable audit schedules
-- ========================================
CREATE TABLE IF NOT EXISTS audit_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE, -- NULL = all shops in tenant

    -- Schedule Identification
    name VARCHAR(255) NOT NULL,
    description TEXT,

    -- Schedule Type
    schedule_type VARCHAR(50) NOT NULL,
    -- 'daily_closing' - End of day cash + quick stock check
    -- 'weekly' - Weekly complete inventory
    -- 'monthly_cycle' - Monthly rotating category audit
    -- 'spot_check' - Random unannounced (triggered manually)

    -- Timing Configuration
    cron_expression VARCHAR(100), -- e.g., '0 20 * * *' for 8 PM daily (NULL for spot checks)
    time_window_start TIME, -- Start of allowed audit window
    time_window_end TIME, -- End of allowed audit window
    completion_deadline_minutes INTEGER DEFAULT 60, -- Must complete within X minutes

    -- Audit Scope
    audit_type VARCHAR(50) NOT NULL, -- 'cash', 'inventory', 'both'

    -- Inventory Scope (for inventory audits)
    category_ids UUID[], -- NULL = all categories
    brand_ids UUID[], -- Filter by brands
    high_value_threshold DECIMAL(15,2), -- Include items above this price
    include_high_value_only BOOLEAN DEFAULT FALSE,
    sample_percentage INTEGER, -- For cycle counts, % of items to count

    -- Notifications
    notify_before_minutes INTEGER DEFAULT 30, -- Notify X minutes before
    escalate_after_minutes INTEGER DEFAULT 60, -- Escalate if not started
    notification_recipients UUID[], -- User IDs to notify

    -- Assignment
    default_assignee_ids UUID[], -- Default people to assign
    require_blind_count BOOLEAN DEFAULT FALSE, -- Cash: counter can't see expected

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    last_triggered_at TIMESTAMP WITH TIME ZONE,
    next_trigger_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_by_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for audit_schedules
CREATE INDEX IF NOT EXISTS idx_audit_schedules_tenant ON audit_schedules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_schedules_shop ON audit_schedules(shop_id);
CREATE INDEX IF NOT EXISTS idx_audit_schedules_type ON audit_schedules(schedule_type);
CREATE INDEX IF NOT EXISTS idx_audit_schedules_active ON audit_schedules(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_audit_schedules_next_trigger ON audit_schedules(next_trigger_at) WHERE is_active = TRUE AND next_trigger_at IS NOT NULL;

-- ========================================
-- 2. audit_sessions: Each audit instance
-- ========================================
CREATE TABLE IF NOT EXISTS audit_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    schedule_id UUID REFERENCES audit_schedules(id) ON DELETE SET NULL, -- NULL for ad-hoc/spot

    -- Session Identification
    session_number VARCHAR(50) NOT NULL, -- e.g., 'AUD-2025-12-001'

    -- Type & Trigger
    audit_type VARCHAR(50) NOT NULL, -- 'cash', 'inventory', 'both'
    trigger_type VARCHAR(50) NOT NULL, -- 'scheduled', 'spot_check', 'ad_hoc', 'automated'
    audit_date DATE NOT NULL,

    -- Timing
    scheduled_at TIMESTAMP WITH TIME ZONE,
    deadline_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    paused_at TIMESTAMP WITH TIME ZONE,
    resumed_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Status Workflow
    status VARCHAR(50) DEFAULT 'scheduled',
    -- 'scheduled', 'in_progress', 'paused', 'pending_review',
    -- 'approved', 'rejected', 'expired', 'cancelled'

    -- Multi-Counter Support (for inventory)
    assigned_counters JSONB,
    /* Array of:
    {
        "user_id": "uuid",
        "user_name": "string",
        "section": "whiskey",
        "category_id": "uuid",
        "status": "completed",
        "started_at": "timestamp",
        "completed_at": "timestamp"
    }
    */
    sections_total INTEGER DEFAULT 0,
    sections_completed INTEGER DEFAULT 0,

    -- Summary (calculated after completion)
    total_cash_variance DECIMAL(15,2) DEFAULT 0,
    total_inventory_variance DECIMAL(15,2) DEFAULT 0,
    total_variance_value DECIMAL(15,2) DEFAULT 0,
    variance_count INTEGER DEFAULT 0,
    items_counted INTEGER DEFAULT 0,
    items_with_variance INTEGER DEFAULT 0,

    -- Review Workflow
    reviewed_by_id UUID REFERENCES users(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,

    -- Approval
    approved_by_id UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,

    -- Notes
    notes TEXT,
    issues_found TEXT,

    -- Audit
    created_by_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT uq_audit_session_number UNIQUE(session_number)
);

-- Indexes for audit_sessions
CREATE INDEX IF NOT EXISTS idx_audit_sessions_tenant ON audit_sessions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_shop ON audit_sessions(shop_id);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_schedule ON audit_sessions(schedule_id);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_date ON audit_sessions(audit_date DESC);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_type ON audit_sessions(audit_type);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_status ON audit_sessions(status);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_created_by ON audit_sessions(created_by_id);
CREATE INDEX IF NOT EXISTS idx_audit_sessions_pending ON audit_sessions(status) WHERE status IN ('scheduled', 'in_progress', 'pending_review');
CREATE INDEX IF NOT EXISTS idx_audit_sessions_shop_date ON audit_sessions(shop_id, audit_date DESC);

-- ========================================
-- 3. cash_audits: Denomination-wise cash counting
-- ========================================
CREATE TABLE IF NOT EXISTS cash_audits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    audit_session_id UUID NOT NULL REFERENCES audit_sessions(id) ON DELETE CASCADE,

    -- Expected Amounts (from system)
    expected_total DECIMAL(15,2) NOT NULL,
    expected_breakdown JSONB,
    /* {
        "opening_balance": 5000,
        "cash_sales": 45000,
        "deposits_made": 20000,
        "petty_cash_used": 500,
        "collections_received": 10000
    } */

    -- Actual Count
    actual_total DECIMAL(15,2) NOT NULL,
    blind_count BOOLEAN DEFAULT FALSE, -- Counter didn't see expected amount

    -- Denomination Recording (Indian Currency)
    denominations JSONB NOT NULL,
    /* {
        "notes": {
            "2000": {"count": 5, "total": 10000},
            "500": {"count": 20, "total": 10000},
            "200": {"count": 10, "total": 2000},
            "100": {"count": 30, "total": 3000},
            "50": {"count": 20, "total": 1000},
            "20": {"count": 25, "total": 500},
            "10": {"count": 30, "total": 300}
        },
        "coins": {
            "10": {"count": 10, "total": 100},
            "5": {"count": 20, "total": 100},
            "2": {"count": 25, "total": 50},
            "1": {"count": 50, "total": 50}
        }
    } */

    -- Variance
    variance_amount DECIMAL(15,2) NOT NULL, -- actual - expected
    variance_percentage DECIMAL(5,2) NOT NULL,
    variance_type VARCHAR(20), -- 'shortage', 'overage', 'balanced'

    -- Explanation & Evidence
    variance_explanation TEXT,
    photo_evidence_urls TEXT[],

    -- Approval Tracking
    requires_approval BOOLEAN DEFAULT FALSE,
    approval_threshold_exceeded BOOLEAN DEFAULT FALSE,
    variance_threshold DECIMAL(15,2), -- Threshold that was exceeded

    -- Counter Info
    counted_by_id UUID NOT NULL REFERENCES users(id),
    counted_at TIMESTAMP WITH TIME ZONE NOT NULL,
    count_duration_minutes INTEGER, -- How long counting took

    -- Verification (second count if required)
    verified_by_id UUID REFERENCES users(id),
    verified_at TIMESTAMP WITH TIME ZONE,
    verification_amount DECIMAL(15,2),
    verification_matches BOOLEAN,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for cash_audits
CREATE INDEX IF NOT EXISTS idx_cash_audits_tenant ON cash_audits(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_audits_session ON cash_audits(audit_session_id);
CREATE INDEX IF NOT EXISTS idx_cash_audits_counted_by ON cash_audits(counted_by_id);
CREATE INDEX IF NOT EXISTS idx_cash_audits_variance_type ON cash_audits(variance_type);
CREATE INDEX IF NOT EXISTS idx_cash_audits_counted_at ON cash_audits(counted_at DESC);

-- ========================================
-- 4. inventory_audits: Inventory count sessions (sections)
-- ========================================
CREATE TABLE IF NOT EXISTS inventory_audits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    audit_session_id UUID NOT NULL REFERENCES audit_sessions(id) ON DELETE CASCADE,

    -- Section Assignment
    section_name VARCHAR(100), -- 'whiskey', 'beer', 'wine', 'all'
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    brand_id UUID REFERENCES brands(id) ON DELETE SET NULL,

    -- Assignment
    assigned_to_id UUID NOT NULL REFERENCES users(id),

    -- Status
    status VARCHAR(50) DEFAULT 'pending',
    -- 'pending', 'in_progress', 'completed', 'reviewed'

    -- Progress
    total_items INTEGER DEFAULT 0,
    counted_items INTEGER DEFAULT 0,
    skipped_items INTEGER DEFAULT 0,
    progress_percentage DECIMAL(5,2) DEFAULT 0,

    -- Summary
    total_system_value DECIMAL(15,2) DEFAULT 0,
    total_physical_value DECIMAL(15,2) DEFAULT 0,
    total_variance_value DECIMAL(15,2) DEFAULT 0,
    variance_items_count INTEGER DEFAULT 0,

    -- Timing
    started_at TIMESTAMP WITH TIME ZONE,
    paused_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    count_duration_minutes INTEGER,

    -- Notes
    notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for inventory_audits
CREATE INDEX IF NOT EXISTS idx_inventory_audits_tenant ON inventory_audits(tenant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_audits_session ON inventory_audits(audit_session_id);
CREATE INDEX IF NOT EXISTS idx_inventory_audits_assigned ON inventory_audits(assigned_to_id);
CREATE INDEX IF NOT EXISTS idx_inventory_audits_category ON inventory_audits(category_id);
CREATE INDEX IF NOT EXISTS idx_inventory_audits_status ON inventory_audits(status);

-- ========================================
-- 5. inventory_audit_items: Individual item counts
-- ========================================
CREATE TABLE IF NOT EXISTS inventory_audit_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    inventory_audit_id UUID NOT NULL REFERENCES inventory_audits(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,

    -- Product Info (denormalized for reports)
    product_name VARCHAR(255),
    product_sku VARCHAR(100),
    product_barcode VARCHAR(100),
    category_name VARCHAR(255),
    brand_name VARCHAR(255),

    -- Quantities
    system_quantity INTEGER NOT NULL,
    physical_quantity INTEGER, -- NULL until counted
    variance_quantity INTEGER, -- system - physical

    -- Values
    unit_cost DECIMAL(15,2) NOT NULL,
    unit_price DECIMAL(15,2),
    variance_value DECIMAL(15,2), -- variance_quantity * unit_cost

    -- Count Details
    count_method VARCHAR(50), -- 'barcode_scan', 'manual', 'voice'
    barcode_scanned VARCHAR(100),
    scan_count INTEGER DEFAULT 0, -- Number of scans for this item

    -- Evidence (for discrepancies)
    variance_explanation TEXT,
    photo_evidence_urls TEXT[],

    -- Status
    is_counted BOOLEAN DEFAULT FALSE,
    is_skipped BOOLEAN DEFAULT FALSE,
    skip_reason TEXT,

    -- Timestamps
    counted_at TIMESTAMP WITH TIME ZONE,
    counted_by_id UUID REFERENCES users(id),

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for inventory_audit_items
CREATE INDEX IF NOT EXISTS idx_inv_audit_items_tenant ON inventory_audit_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_inv_audit_items_audit ON inventory_audit_items(inventory_audit_id);
CREATE INDEX IF NOT EXISTS idx_inv_audit_items_product ON inventory_audit_items(product_id);
CREATE INDEX IF NOT EXISTS idx_inv_audit_items_counted ON inventory_audit_items(is_counted);
CREATE INDEX IF NOT EXISTS idx_inv_audit_items_barcode ON inventory_audit_items(product_barcode);
CREATE INDEX IF NOT EXISTS idx_inv_audit_items_variance ON inventory_audit_items(variance_quantity) WHERE variance_quantity IS NOT NULL AND variance_quantity != 0;

-- ========================================
-- 6. audit_variances: Variance tracking and resolution
-- ========================================
CREATE TABLE IF NOT EXISTS audit_variances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    audit_session_id UUID NOT NULL REFERENCES audit_sessions(id) ON DELETE CASCADE,

    -- Variance Type & Reference
    variance_type VARCHAR(50) NOT NULL, -- 'cash', 'inventory'
    reference_id UUID NOT NULL, -- cash_audit_id or inventory_audit_item_id
    product_id UUID REFERENCES products(id) ON DELETE SET NULL, -- NULL for cash variances

    -- Variance Details
    expected_value DECIMAL(15,2) NOT NULL,
    actual_value DECIMAL(15,2) NOT NULL,
    variance_amount DECIMAL(15,2) NOT NULL,
    variance_percentage DECIMAL(5,2) NOT NULL,

    -- Classification
    severity VARCHAR(50) NOT NULL, -- 'minor', 'moderate', 'major', 'critical'
    within_tolerance BOOLEAN DEFAULT FALSE,
    tolerance_threshold DECIMAL(5,2), -- The threshold that was checked

    -- Pattern Detection
    is_recurring BOOLEAN DEFAULT FALSE,
    similar_variance_count INTEGER DEFAULT 0,
    pattern_flags JSONB,
    /* {
        "consecutive_days": 3,
        "same_product": true,
        "same_user": true,
        "same_amount_range": true
    } */

    -- Investigation Link
    investigation_id UUID REFERENCES investigations(id) ON DELETE SET NULL,
    suspicious_activity_id UUID REFERENCES suspicious_activities(id) ON DELETE SET NULL,

    -- Status & Resolution
    status VARCHAR(50) DEFAULT 'open',
    -- 'open', 'investigating', 'explained', 'resolved', 'written_off'

    assigned_to_id UUID REFERENCES users(id),
    resolution_type VARCHAR(50),
    -- 'counting_error', 'system_error', 'theft', 'damage', 'spoilage',
    -- 'receiving_error', 'unknown', 'written_off'
    resolution_notes TEXT,

    -- Financial Resolution
    write_off_amount DECIMAL(15,2) DEFAULT 0,
    recovery_amount DECIMAL(15,2) DEFAULT 0,

    -- Resolution Tracking
    resolved_by_id UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Approval (for write-offs)
    approved_by_id UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for audit_variances
CREATE INDEX IF NOT EXISTS idx_audit_variances_tenant ON audit_variances(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_variances_session ON audit_variances(audit_session_id);
CREATE INDEX IF NOT EXISTS idx_audit_variances_type ON audit_variances(variance_type);
CREATE INDEX IF NOT EXISTS idx_audit_variances_product ON audit_variances(product_id);
CREATE INDEX IF NOT EXISTS idx_audit_variances_severity ON audit_variances(severity);
CREATE INDEX IF NOT EXISTS idx_audit_variances_status ON audit_variances(status);
CREATE INDEX IF NOT EXISTS idx_audit_variances_investigation ON audit_variances(investigation_id);
CREATE INDEX IF NOT EXISTS idx_audit_variances_open ON audit_variances(status) WHERE status IN ('open', 'investigating');
CREATE INDEX IF NOT EXISTS idx_audit_variances_recurring ON audit_variances(is_recurring) WHERE is_recurring = TRUE;

-- ========================================
-- 7. audit_resolutions: Resolution records for audit variances
-- ========================================
CREATE TABLE IF NOT EXISTS audit_resolutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    variance_id UUID NOT NULL REFERENCES audit_variances(id) ON DELETE CASCADE,

    -- Resolution Details
    resolution_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,

    -- Financial Impact
    original_variance DECIMAL(15,2) NOT NULL,
    amount_written_off DECIMAL(15,2) DEFAULT 0,
    amount_recovered DECIMAL(15,2) DEFAULT 0,
    amount_adjusted DECIMAL(15,2) DEFAULT 0,

    -- Accountability
    responsible_user_id UUID REFERENCES users(id),
    responsibility_type VARCHAR(50), -- 'direct', 'oversight', 'system'
    action_taken TEXT,
    disciplinary_action TEXT,

    -- Supporting Documents
    supporting_documents JSONB, -- Array of {filename, path, type}

    -- Approval
    approved_by_id UUID NOT NULL REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Audit
    created_by_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for audit_resolutions
CREATE INDEX IF NOT EXISTS idx_audit_resolutions_tenant ON audit_resolutions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_resolutions_variance ON audit_resolutions(variance_id);
CREATE INDEX IF NOT EXISTS idx_audit_resolutions_responsible ON audit_resolutions(responsible_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_resolutions_type ON audit_resolutions(resolution_type);

-- ========================================
-- 8. audit_notifications: Audit-specific notifications
-- ========================================
CREATE TABLE IF NOT EXISTS audit_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Reference
    audit_session_id UUID REFERENCES audit_sessions(id) ON DELETE CASCADE,
    schedule_id UUID REFERENCES audit_schedules(id) ON DELETE SET NULL,

    -- Notification Details
    notification_type VARCHAR(50) NOT NULL,
    -- 'upcoming', 'started', 'reminder', 'overdue', 'completed',
    -- 'variance_alert', 'approval_required', 'escalation'

    recipient_id UUID NOT NULL REFERENCES users(id),

    -- Content
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    action_url TEXT,
    priority VARCHAR(20) DEFAULT 'normal', -- low, normal, high, urgent

    -- Delivery
    channels TEXT[] DEFAULT ARRAY['in_app'], -- in_app, push, email, sms, whatsapp
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,

    -- Status
    status VARCHAR(50) DEFAULT 'pending',
    -- 'pending', 'sent', 'delivered', 'read', 'failed'
    error_message TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for audit_notifications
CREATE INDEX IF NOT EXISTS idx_audit_notifications_tenant ON audit_notifications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_notifications_session ON audit_notifications(audit_session_id);
CREATE INDEX IF NOT EXISTS idx_audit_notifications_recipient ON audit_notifications(recipient_id);
CREATE INDEX IF NOT EXISTS idx_audit_notifications_type ON audit_notifications(notification_type);
CREATE INDEX IF NOT EXISTS idx_audit_notifications_status ON audit_notifications(status);
CREATE INDEX IF NOT EXISTS idx_audit_notifications_unread ON audit_notifications(recipient_id, status) WHERE status NOT IN ('read', 'failed');

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== PHYSICAL AUDIT TABLES CREATED ===' as info;

SELECT
    'audit_schedules' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'audit_schedules') as column_count;

SELECT
    'audit_sessions' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'audit_sessions') as column_count;

SELECT
    'cash_audits' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'cash_audits') as column_count;

SELECT
    'inventory_audits' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'inventory_audits') as column_count;

SELECT
    'inventory_audit_items' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'inventory_audit_items') as column_count;

SELECT
    'audit_variances' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'audit_variances') as column_count;

SELECT
    'audit_resolutions' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'audit_resolutions') as column_count;

SELECT
    'audit_notifications' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'audit_notifications') as column_count;
