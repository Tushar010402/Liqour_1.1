-- Create Finance Matrix Tables
-- Date: 2025-12-01
-- Description: Pre-computed metrics, credit aging, expense budgets, shrinkage records, finance alerts

BEGIN;

-- ========================================
-- 1. finance_metrics_daily: Pre-computed daily metrics for fast dashboard
-- ========================================
CREATE TABLE IF NOT EXISTS finance_metrics_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,  -- NULL for tenant-wide aggregates
    metric_date DATE NOT NULL,

    -- Sales Metrics
    total_sales DECIMAL(15,2) DEFAULT 0,
    cash_sales DECIMAL(15,2) DEFAULT 0,
    card_sales DECIMAL(15,2) DEFAULT 0,
    upi_sales DECIMAL(15,2) DEFAULT 0,
    credit_sales DECIMAL(15,2) DEFAULT 0,
    sales_count INTEGER DEFAULT 0,
    items_sold INTEGER DEFAULT 0,
    avg_transaction_value DECIMAL(15,2) DEFAULT 0,

    -- Comparison to Previous Period
    prev_period_sales DECIMAL(15,2) DEFAULT 0,
    sales_growth_amount DECIMAL(15,2) DEFAULT 0,
    sales_growth_percent DECIMAL(8,4) DEFAULT 0,

    -- Cash Flow Metrics
    cash_inflow DECIMAL(15,2) DEFAULT 0,
    cash_outflow DECIMAL(15,2) DEFAULT 0,
    net_cash_flow DECIMAL(15,2) DEFAULT 0,

    -- Expense Metrics
    total_expenses DECIMAL(15,2) DEFAULT 0,

    -- Inventory Metrics (snapshot at end of day)
    inventory_value DECIMAL(15,2) DEFAULT 0,
    inventory_items_count INTEGER DEFAULT 0,

    -- Returns & Discounts
    total_returns DECIMAL(15,2) DEFAULT 0,
    returns_count INTEGER DEFAULT 0,
    total_discounts DECIMAL(15,2) DEFAULT 0,
    discounts_count INTEGER DEFAULT 0,

    -- Computation Tracking
    computed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    computation_duration_ms INTEGER,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_finance_metrics_daily UNIQUE(tenant_id, shop_id, metric_date)
);

-- Indexes for finance_metrics_daily
CREATE INDEX IF NOT EXISTS idx_finance_metrics_daily_tenant_date ON finance_metrics_daily(tenant_id, metric_date DESC);
CREATE INDEX IF NOT EXISTS idx_finance_metrics_daily_shop_date ON finance_metrics_daily(shop_id, metric_date DESC) WHERE shop_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_finance_metrics_daily_computed ON finance_metrics_daily(computed_at);

-- ========================================
-- 2. credit_sales_aging: Track receivables with aging buckets
-- ========================================
CREATE TABLE IF NOT EXISTS credit_sales_aging (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Customer Info
    customer_name VARCHAR(255),
    customer_phone VARCHAR(20),
    customer_address TEXT,

    -- Sale Reference
    daily_sales_record_id UUID REFERENCES daily_sales_records(id) ON DELETE SET NULL,
    sale_id UUID REFERENCES sales(id) ON DELETE SET NULL,

    -- Amount Details
    original_amount DECIMAL(15,2) NOT NULL,
    paid_amount DECIMAL(15,2) DEFAULT 0,
    outstanding_amount DECIMAL(15,2) NOT NULL,

    -- Dates
    credit_date DATE NOT NULL,
    due_date DATE,
    last_payment_date DATE,
    last_reminder_date DATE,

    -- Aging (calculated on read, but can be stored for reports)
    days_outstanding INTEGER DEFAULT 0,
    aging_bucket VARCHAR(20) DEFAULT '0-30', -- '0-30', '31-60', '61-90', '90+'

    -- Status
    status VARCHAR(20) DEFAULT 'outstanding', -- outstanding, partial, paid, written_off, disputed
    priority VARCHAR(20) DEFAULT 'normal', -- low, normal, high, critical

    -- Notes & Follow-up
    notes TEXT,
    last_follow_up_notes TEXT,
    next_follow_up_date DATE,

    -- Write-off tracking
    written_off_amount DECIMAL(15,2) DEFAULT 0,
    written_off_at TIMESTAMP WITH TIME ZONE,
    written_off_by UUID REFERENCES users(id),
    write_off_reason TEXT,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for credit_sales_aging
CREATE INDEX IF NOT EXISTS idx_credit_aging_tenant ON credit_sales_aging(tenant_id);
CREATE INDEX IF NOT EXISTS idx_credit_aging_shop ON credit_sales_aging(shop_id);
CREATE INDEX IF NOT EXISTS idx_credit_aging_status ON credit_sales_aging(status) WHERE status != 'paid';
CREATE INDEX IF NOT EXISTS idx_credit_aging_bucket ON credit_sales_aging(aging_bucket);
CREATE INDEX IF NOT EXISTS idx_credit_aging_due_date ON credit_sales_aging(due_date) WHERE status = 'outstanding';
CREATE INDEX IF NOT EXISTS idx_credit_aging_customer_phone ON credit_sales_aging(customer_phone);
CREATE INDEX IF NOT EXISTS idx_credit_aging_outstanding ON credit_sales_aging(outstanding_amount DESC) WHERE status = 'outstanding';

-- ========================================
-- 3. expense_budgets: Budget vs Actual tracking
-- ========================================
CREATE TABLE IF NOT EXISTS expense_budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE, -- NULL for tenant-wide budget
    expense_category_id UUID REFERENCES expense_categories(id) ON DELETE CASCADE,

    -- Budget Period
    budget_year INTEGER NOT NULL,
    budget_month INTEGER NOT NULL, -- 0 for annual budget, 1-12 for monthly

    -- Budget Amounts
    budgeted_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    actual_amount DECIMAL(15,2) DEFAULT 0,
    variance_amount DECIMAL(15,2) DEFAULT 0,
    variance_percent DECIMAL(8,4) DEFAULT 0,

    -- Alert Thresholds
    warning_threshold_percent DECIMAL(5,2) DEFAULT 80.00, -- Alert at 80% utilization
    critical_threshold_percent DECIMAL(5,2) DEFAULT 100.00, -- Alert at 100%

    -- Status
    status VARCHAR(20) DEFAULT 'active', -- active, closed, exceeded, cancelled

    -- Notes
    notes TEXT,
    adjustment_reason TEXT,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_expense_budget UNIQUE(tenant_id, shop_id, expense_category_id, budget_year, budget_month)
);

-- Indexes for expense_budgets
CREATE INDEX IF NOT EXISTS idx_expense_budgets_tenant ON expense_budgets(tenant_id);
CREATE INDEX IF NOT EXISTS idx_expense_budgets_period ON expense_budgets(budget_year, budget_month);
CREATE INDEX IF NOT EXISTS idx_expense_budgets_status ON expense_budgets(status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_expense_budgets_category ON expense_budgets(expense_category_id);

-- ========================================
-- 4. shrinkage_records: Track inventory shrinkage
-- ========================================
CREATE TABLE IF NOT EXISTS shrinkage_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    stock_verification_id UUID REFERENCES stock_verifications(id) ON DELETE SET NULL,

    -- Verification Details
    verification_date DATE NOT NULL,

    -- Quantity Comparison
    system_quantity INTEGER NOT NULL,
    physical_quantity INTEGER NOT NULL,
    variance_quantity INTEGER NOT NULL, -- system - physical (negative = shortage)

    -- Value Calculation
    unit_cost DECIMAL(10,2) NOT NULL,
    unit_price DECIMAL(10,2),
    variance_value DECIMAL(15,2) NOT NULL, -- variance_quantity * unit_cost
    retail_loss DECIMAL(15,2), -- variance_quantity * unit_price

    -- Shrinkage Rate
    shrinkage_rate DECIMAL(8,4), -- (variance / system) * 100

    -- Classification
    shrinkage_type VARCHAR(30) DEFAULT 'unknown', -- theft, damage, spoilage, counting_error, receiving_error, unknown
    severity VARCHAR(20) DEFAULT 'low', -- low, medium, high, critical
    risk_score INTEGER DEFAULT 0, -- 0-100 composite score

    -- Analysis
    probable_causes JSONB, -- Array of {cause: string, probability: number}
    similar_pattern_count INTEGER DEFAULT 0,
    is_recurring BOOLEAN DEFAULT FALSE,

    -- Investigation Reference
    investigation_id UUID, -- Will reference investigations table

    -- Resolution
    status VARCHAR(20) DEFAULT 'pending', -- pending, investigating, resolved, written_off
    reason TEXT,
    resolution_notes TEXT,
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Approval
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for shrinkage_records
CREATE INDEX IF NOT EXISTS idx_shrinkage_tenant ON shrinkage_records(tenant_id);
CREATE INDEX IF NOT EXISTS idx_shrinkage_shop ON shrinkage_records(shop_id);
CREATE INDEX IF NOT EXISTS idx_shrinkage_product ON shrinkage_records(product_id);
CREATE INDEX IF NOT EXISTS idx_shrinkage_verification ON shrinkage_records(stock_verification_id);
CREATE INDEX IF NOT EXISTS idx_shrinkage_date ON shrinkage_records(verification_date DESC);
CREATE INDEX IF NOT EXISTS idx_shrinkage_type ON shrinkage_records(shrinkage_type);
CREATE INDEX IF NOT EXISTS idx_shrinkage_severity ON shrinkage_records(severity);
CREATE INDEX IF NOT EXISTS idx_shrinkage_status ON shrinkage_records(status) WHERE status != 'resolved';
CREATE INDEX IF NOT EXISTS idx_shrinkage_risk_score ON shrinkage_records(risk_score DESC);

-- ========================================
-- 5. finance_alerts: Proactive alerts for managers
-- ========================================
CREATE TABLE IF NOT EXISTS finance_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE, -- Target user for the alert

    -- Alert Details
    alert_type VARCHAR(50) NOT NULL, -- cash_shortage, low_stock, overdue_collection, high_expense, anomaly, shrinkage, etc.
    severity VARCHAR(20) NOT NULL, -- info, warning, critical
    category VARCHAR(50), -- finance, inventory, sales, audit

    -- Content
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    action_url TEXT, -- Deep link to related resource
    action_label VARCHAR(100), -- e.g., "View Details", "Investigate"

    -- Related Entity
    related_type VARCHAR(50), -- cash_holding, stock, credit_sale, expense, shrinkage, etc.
    related_id UUID,

    -- Metrics (for display)
    metric_value DECIMAL(15,2),
    metric_threshold DECIMAL(15,2),
    metric_unit VARCHAR(20), -- %, Rs, units

    -- Status
    status VARCHAR(20) DEFAULT 'unread', -- unread, read, acknowledged, resolved, dismissed
    read_at TIMESTAMP WITH TIME ZONE,
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    acknowledged_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by UUID REFERENCES users(id),
    resolution_notes TEXT,

    -- Auto-dismiss
    expires_at TIMESTAMP WITH TIME ZONE,
    is_persistent BOOLEAN DEFAULT FALSE, -- If true, doesn't auto-dismiss

    -- Notification tracking
    notifications_sent JSONB, -- [{channel: 'push', sent_at: timestamp, status: 'delivered'}]

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for finance_alerts
CREATE INDEX IF NOT EXISTS idx_finance_alerts_tenant ON finance_alerts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_finance_alerts_user ON finance_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_finance_alerts_shop ON finance_alerts(shop_id);
CREATE INDEX IF NOT EXISTS idx_finance_alerts_type ON finance_alerts(alert_type);
CREATE INDEX IF NOT EXISTS idx_finance_alerts_severity ON finance_alerts(severity);
CREATE INDEX IF NOT EXISTS idx_finance_alerts_status ON finance_alerts(status) WHERE status NOT IN ('resolved', 'dismissed');
CREATE INDEX IF NOT EXISTS idx_finance_alerts_user_unread ON finance_alerts(user_id, status) WHERE status = 'unread';
CREATE INDEX IF NOT EXISTS idx_finance_alerts_created ON finance_alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_finance_alerts_expires ON finance_alerts(expires_at) WHERE expires_at IS NOT NULL AND status = 'unread';

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== FINANCE MATRIX TABLES CREATED ===' as info;

SELECT
    'finance_metrics_daily' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'finance_metrics_daily') as column_count;

SELECT
    'credit_sales_aging' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'credit_sales_aging') as column_count;

SELECT
    'expense_budgets' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'expense_budgets') as column_count;

SELECT
    'shrinkage_records' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'shrinkage_records') as column_count;

SELECT
    'finance_alerts' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'finance_alerts') as column_count;
