-- Create Finance Matrix Views and Materialized Views
-- Date: 2025-12-01
-- Description: Pre-computed views for analytics and reporting

BEGIN;

-- ========================================
-- 1. v_salesman_performance: Salesman performance metrics
-- ========================================
CREATE OR REPLACE VIEW v_salesman_performance AS
SELECT
    dsr.tenant_id,
    dsr.shop_id,
    s.name AS shop_name,
    dsr.salesman_id,
    u.name AS salesman_name,
    DATE_TRUNC('month', dsr.record_date) AS month,
    DATE_TRUNC('week', dsr.record_date) AS week,
    COUNT(*) AS sales_count,
    SUM(dsr.total_sales_amount) AS total_sales,
    SUM(dsr.total_cash_amount) AS cash_collected,
    SUM(dsr.total_card_amount) AS card_collected,
    SUM(dsr.total_upi_amount) AS upi_collected,
    SUM(dsr.total_credit_amount) AS credit_given,
    AVG(dsr.total_sales_amount) AS avg_sale_value,
    SUM(COALESCE(
        (SELECT SUM(dsi.quantity) FROM daily_sales_items dsi WHERE dsi.daily_sales_record_id = dsr.id),
        0
    )) AS items_sold
FROM daily_sales_records dsr
JOIN shops s ON dsr.shop_id = s.id
LEFT JOIN users u ON dsr.salesman_id = u.id
WHERE dsr.status = 'approved'
  AND dsr.deleted_at IS NULL
GROUP BY
    dsr.tenant_id,
    dsr.shop_id,
    s.name,
    dsr.salesman_id,
    u.name,
    DATE_TRUNC('month', dsr.record_date),
    DATE_TRUNC('week', dsr.record_date);

-- ========================================
-- 2. v_stock_turnover: Stock turnover analysis
-- ========================================
CREATE OR REPLACE VIEW v_stock_turnover AS
SELECT
    st.tenant_id,
    st.shop_id,
    st.product_id,
    p.name AS product_name,
    p.sku AS product_sku,
    b.name AS brand_name,
    c.name AS category_name,
    st.quantity AS current_stock,
    st.average_cost,
    st.quantity * st.average_cost AS stock_value,
    st.minimum_level,
    st.maximum_level,
    COALESCE(sales.total_sold_30d, 0) AS units_sold_30d,
    COALESCE(sales.total_sold_7d, 0) AS units_sold_7d,
    CASE
        WHEN st.quantity > 0 AND COALESCE(sales.total_sold_30d, 0) > 0
        THEN ROUND(st.quantity::DECIMAL / (COALESCE(sales.total_sold_30d, 0) / 30.0), 1)
        ELSE NULL
    END AS days_of_stock,
    CASE
        WHEN COALESCE(sales.total_sold_30d, 0) = 0 THEN 'dead_stock'
        WHEN st.quantity / NULLIF(sales.total_sold_30d / 30.0, 0) > 90 THEN 'slow_moving'
        WHEN st.quantity / NULLIF(sales.total_sold_30d / 30.0, 0) < 15 THEN 'fast_moving'
        ELSE 'normal'
    END AS stock_velocity,
    st.quantity <= st.minimum_level AS is_low_stock,
    st.updated_at AS last_updated
FROM stocks st
JOIN products p ON st.product_id = p.id
LEFT JOIN brands b ON p.brand_id = b.id
LEFT JOIN categories c ON p.category_id = c.id
LEFT JOIN LATERAL (
    SELECT
        SUM(CASE WHEN dsr.record_date >= CURRENT_DATE - INTERVAL '30 days' THEN dsi.quantity ELSE 0 END) AS total_sold_30d,
        SUM(CASE WHEN dsr.record_date >= CURRENT_DATE - INTERVAL '7 days' THEN dsi.quantity ELSE 0 END) AS total_sold_7d
    FROM daily_sales_items dsi
    JOIN daily_sales_records dsr ON dsi.daily_sales_record_id = dsr.id
    WHERE dsi.product_id = st.product_id
      AND dsr.shop_id = st.shop_id
      AND dsr.status = 'approved'
      AND dsr.record_date >= CURRENT_DATE - INTERVAL '30 days'
) sales ON true
WHERE st.deleted_at IS NULL;

-- ========================================
-- 3. v_daily_sales_summary: Daily sales summary by shop
-- ========================================
CREATE OR REPLACE VIEW v_daily_sales_summary AS
SELECT
    dsr.tenant_id,
    dsr.shop_id,
    s.name AS shop_name,
    dsr.record_date,
    COUNT(*) AS transactions_count,
    SUM(dsr.total_sales_amount) AS total_sales,
    SUM(dsr.total_cash_amount) AS cash_sales,
    SUM(dsr.total_card_amount) AS card_sales,
    SUM(dsr.total_upi_amount) AS upi_sales,
    SUM(dsr.total_credit_amount) AS credit_sales,
    AVG(dsr.total_sales_amount) AS avg_transaction_value,
    SUM(
        (SELECT COUNT(*) FROM daily_sales_items dsi WHERE dsi.daily_sales_record_id = dsr.id)
    ) AS total_items_sold,
    COUNT(DISTINCT dsr.salesman_id) AS salesmen_count
FROM daily_sales_records dsr
JOIN shops s ON dsr.shop_id = s.id
WHERE dsr.status = 'approved'
  AND dsr.deleted_at IS NULL
GROUP BY
    dsr.tenant_id,
    dsr.shop_id,
    s.name,
    dsr.record_date;

-- ========================================
-- 4. v_cash_holding_summary: Cash holding by user and role
-- ========================================
CREATE OR REPLACE VIEW v_cash_holding_summary AS
SELECT
    ch.tenant_id,
    ch.user_id,
    u.name AS user_name,
    u.role AS user_role,
    ch.shop_id,
    s.name AS shop_name,
    ch.current_balance,
    ch.last_transaction_at,
    COALESCE(pending.pending_collections, 0) AS pending_collections,
    COALESCE(pending.pending_amount, 0) AS pending_collection_amount
FROM cash_holdings ch
JOIN users u ON ch.user_id = u.id
LEFT JOIN shops s ON ch.shop_id = s.id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS pending_collections,
        SUM(amount) AS pending_amount
    FROM money_collections mc
    WHERE mc.executive_id = ch.user_id
      AND mc.status = 'pending'
      AND mc.deleted_at IS NULL
) pending ON true
WHERE ch.deleted_at IS NULL;

-- ========================================
-- 5. v_expense_summary: Expense summary by category and period
-- ========================================
CREATE OR REPLACE VIEW v_expense_summary AS
SELECT
    e.tenant_id,
    e.shop_id,
    s.name AS shop_name,
    e.category_id,
    ec.name AS category_name,
    DATE_TRUNC('month', e.expense_date) AS month,
    COUNT(*) AS expense_count,
    SUM(e.amount) AS total_amount,
    AVG(e.amount) AS avg_amount,
    MIN(e.amount) AS min_amount,
    MAX(e.amount) AS max_amount
FROM expenses e
JOIN shops s ON e.shop_id = s.id
LEFT JOIN expense_categories ec ON e.category_id = ec.id
WHERE e.deleted_at IS NULL
GROUP BY
    e.tenant_id,
    e.shop_id,
    s.name,
    e.category_id,
    ec.name,
    DATE_TRUNC('month', e.expense_date);

-- ========================================
-- 6. v_credit_aging_summary: Credit aging summary
-- ========================================
CREATE OR REPLACE VIEW v_credit_aging_summary AS
SELECT
    tenant_id,
    shop_id,
    CASE
        WHEN days_outstanding <= 30 THEN '0-30'
        WHEN days_outstanding <= 60 THEN '31-60'
        WHEN days_outstanding <= 90 THEN '61-90'
        ELSE '90+'
    END AS aging_bucket,
    COUNT(*) AS customer_count,
    SUM(outstanding_amount) AS total_outstanding,
    AVG(outstanding_amount) AS avg_outstanding,
    AVG(days_outstanding) AS avg_days_outstanding
FROM credit_sales_aging
WHERE status = 'outstanding'
  AND deleted_at IS NULL
GROUP BY
    tenant_id,
    shop_id,
    CASE
        WHEN days_outstanding <= 30 THEN '0-30'
        WHEN days_outstanding <= 60 THEN '31-60'
        WHEN days_outstanding <= 90 THEN '61-90'
        ELSE '90+'
    END;

-- ========================================
-- 7. v_shrinkage_summary: Shrinkage summary by product/category
-- ========================================
CREATE OR REPLACE VIEW v_shrinkage_summary AS
SELECT
    sr.tenant_id,
    sr.shop_id,
    s.name AS shop_name,
    sr.product_id,
    p.name AS product_name,
    c.name AS category_name,
    DATE_TRUNC('month', sr.verification_date) AS month,
    COUNT(*) AS variance_count,
    SUM(sr.variance_quantity) AS total_variance_qty,
    SUM(sr.variance_value) AS total_variance_value,
    AVG(sr.shrinkage_rate) AS avg_shrinkage_rate,
    MAX(sr.risk_score) AS max_risk_score
FROM shrinkage_records sr
JOIN shops s ON sr.shop_id = s.id
JOIN products p ON sr.product_id = p.id
LEFT JOIN categories c ON p.category_id = c.id
GROUP BY
    sr.tenant_id,
    sr.shop_id,
    s.name,
    sr.product_id,
    p.name,
    c.name,
    DATE_TRUNC('month', sr.verification_date);

-- ========================================
-- 8. v_tips_summary: Tips summary by salesman and period
-- ========================================
CREATE OR REPLACE VIEW v_tips_summary AS
SELECT
    tt.tenant_id,
    tt.shop_id,
    s.name AS shop_name,
    tt.salesman_id,
    u.name AS salesman_name,
    DATE_TRUNC('month', tt.recorded_at) AS month,
    DATE_TRUNC('week', tt.recorded_at) AS week,
    tt.tip_type,
    COUNT(*) AS tip_count,
    SUM(tt.amount) AS total_tips,
    AVG(tt.amount) AS avg_tip,
    SUM(CASE WHEN tt.payout_status = 'pending' THEN tt.amount ELSE 0 END) AS pending_payout,
    SUM(CASE WHEN tt.payout_status = 'paid' THEN tt.amount ELSE 0 END) AS paid_amount
FROM tip_transactions tt
JOIN shops s ON tt.shop_id = s.id
LEFT JOIN users u ON tt.salesman_id = u.id
WHERE tt.deleted_at IS NULL
GROUP BY
    tt.tenant_id,
    tt.shop_id,
    s.name,
    tt.salesman_id,
    u.name,
    DATE_TRUNC('month', tt.recorded_at),
    DATE_TRUNC('week', tt.recorded_at),
    tt.tip_type;

-- ========================================
-- 9. v_audit_completion_summary: Audit completion rates
-- ========================================
CREATE OR REPLACE VIEW v_audit_completion_summary AS
SELECT
    tenant_id,
    shop_id,
    DATE_TRUNC('month', audit_date) AS month,
    audit_type,
    trigger_type,
    COUNT(*) AS total_audits,
    SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) AS completed_audits,
    SUM(CASE WHEN status = 'expired' THEN 1 ELSE 0 END) AS expired_audits,
    SUM(CASE WHEN status = 'rejected' THEN 1 ELSE 0 END) AS rejected_audits,
    SUM(CASE WHEN status IN ('scheduled', 'in_progress', 'pending_review') THEN 1 ELSE 0 END) AS pending_audits,
    ROUND(
        SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END)::DECIMAL /
        NULLIF(COUNT(*), 0) * 100,
        2
    ) AS completion_rate,
    AVG(total_variance_value) AS avg_variance_value,
    AVG(variance_count) AS avg_variance_count
FROM audit_sessions
WHERE deleted_at IS NULL
GROUP BY
    tenant_id,
    shop_id,
    DATE_TRUNC('month', audit_date),
    audit_type,
    trigger_type;

-- ========================================
-- 10. v_suspicious_activity_summary: Suspicious activity summary
-- ========================================
CREATE OR REPLACE VIEW v_suspicious_activity_summary AS
SELECT
    sa.tenant_id,
    sa.shop_id,
    s.name AS shop_name,
    sa.user_id,
    u.name AS user_name,
    u.role AS user_role,
    sa.detection_type,
    DATE_TRUNC('month', sa.detected_at) AS month,
    COUNT(*) AS incident_count,
    SUM(COALESCE(sa.total_impact, 0)) AS total_impact,
    AVG(sa.confidence_score) AS avg_confidence,
    MAX(sa.risk_level) AS max_risk_level,
    SUM(CASE WHEN sa.status = 'confirmed' THEN 1 ELSE 0 END) AS confirmed_count,
    SUM(CASE WHEN sa.status = 'false_positive' THEN 1 ELSE 0 END) AS false_positive_count
FROM suspicious_activities sa
JOIN shops s ON sa.shop_id = s.id
LEFT JOIN users u ON sa.user_id = u.id
GROUP BY
    sa.tenant_id,
    sa.shop_id,
    s.name,
    sa.user_id,
    u.name,
    u.role,
    sa.detection_type,
    DATE_TRUNC('month', sa.detected_at);

COMMIT;

-- ========================================
-- Create Additional Performance Indexes
-- ========================================
BEGIN;

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_daily_sales_tenant_shop_date
    ON daily_sales_records(tenant_id, shop_id, record_date DESC)
    WHERE status = 'approved' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_daily_sales_items_product_date
    ON daily_sales_items(product_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_expenses_tenant_shop_date
    ON expenses(tenant_id, shop_id, expense_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_stocks_tenant_shop_product
    ON stocks(tenant_id, shop_id, product_id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cash_holdings_tenant_user
    ON cash_holdings(tenant_id, user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_money_collections_tenant_status_date
    ON money_collections(tenant_id, status, created_at DESC)
    WHERE deleted_at IS NULL;

-- GIN indexes for JSONB columns
CREATE INDEX IF NOT EXISTS idx_cash_variances_staff_gin
    ON cash_variances USING GIN (responsible_staff);

CREATE INDEX IF NOT EXISTS idx_suspicious_transactions_gin
    ON suspicious_activities USING GIN (related_transactions);

CREATE INDEX IF NOT EXISTS idx_audit_sessions_counters_gin
    ON audit_sessions USING GIN (assigned_counters);

-- Partial indexes for active records
CREATE INDEX IF NOT EXISTS idx_active_tip_pools
    ON tip_pools(shop_id, pool_date)
    WHERE status IN ('pending', 'distributed') AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_open_investigations
    ON investigations(tenant_id, status, priority)
    WHERE status NOT LIKE 'closed%' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_unresolved_variances
    ON audit_variances(tenant_id, status, severity)
    WHERE status IN ('open', 'investigating');

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== FINANCE MATRIX VIEWS CREATED ===' as info;

SELECT
    schemaname,
    viewname
FROM pg_views
WHERE viewname LIKE 'v_%'
  AND schemaname = 'public'
ORDER BY viewname;
