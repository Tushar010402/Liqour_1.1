-- Migration: Create UP Excise-Specific Tables
-- Date: 2025-01-15
-- Description: Create new tables for UP Excise compliance (licenses, reports, security codes)

-- ============================================================
-- 1. EXCISE LICENSES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS excise_licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    shop_id UUID NOT NULL,

    -- License details
    license_number VARCHAR(50) UNIQUE NOT NULL,
    license_type VARCHAR(20) NOT NULL,

    -- Validity
    issued_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT true,

    -- Financial
    monthly_fee DECIMAL(10,2) NOT NULL,
    bank_account_id UUID,

    -- Additional details
    restrictions JSONB,
    license_conditions TEXT,
    issuing_authority VARCHAR(200),
    license_category VARCHAR(50),

    -- Audit fields
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by UUID,
    updated_by UUID,

    -- Foreign keys
    CONSTRAINT fk_excise_license_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_excise_license_shop FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
    CONSTRAINT fk_excise_license_bank FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL,
    CONSTRAINT fk_excise_license_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_excise_license_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,

    -- Unique constraint
    CONSTRAINT unique_shop_license UNIQUE (shop_id),

    -- Check constraints
    CONSTRAINT check_license_type CHECK (license_type IN ('FL-2A', 'FL-17', 'CL-2', 'COMPOSITE', 'IMFL', 'COUNTRY_LIQUOR', 'BEER_ONLY', 'MODEL')),
    CONSTRAINT check_dates CHECK (expiry_date > issued_date),
    CONSTRAINT check_monthly_fee CHECK (monthly_fee >= 0)
);

-- Indexes
CREATE INDEX idx_excise_licenses_tenant ON excise_licenses(tenant_id);
CREATE INDEX idx_excise_licenses_shop ON excise_licenses(shop_id);
CREATE INDEX idx_excise_licenses_number ON excise_licenses(license_number);
CREATE INDEX idx_excise_licenses_type ON excise_licenses(license_type);
CREATE INDEX idx_excise_licenses_active ON excise_licenses(is_active) WHERE is_active = true;
CREATE INDEX idx_excise_licenses_expiry ON excise_licenses(expiry_date) WHERE is_active = true;

-- Comments
COMMENT ON TABLE excise_licenses IS 'Excise licenses for shops (FL-2A, CL-2, Composite, etc.)';
COMMENT ON COLUMN excise_licenses.license_number IS 'Unique excise license number from UP Excise Department';
COMMENT ON COLUMN excise_licenses.license_type IS 'Type of license: FL-2A (wholesale), CL-2 (wholesale), COMPOSITE (retail), etc.';
COMMENT ON COLUMN excise_licenses.monthly_fee IS 'Monthly license fee amount to be paid';
COMMENT ON COLUMN excise_licenses.restrictions IS 'JSONB field for license-specific restrictions (e.g., max 2 shops per licensee)';

-- ============================================================
-- 2. EXCISE DAILY REPORTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS excise_daily_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    shop_id UUID NOT NULL,
    license_id UUID NOT NULL,
    report_date DATE NOT NULL,

    -- Stock breakdown (JSONB for flexibility)
    opening_stock JSONB NOT NULL DEFAULT '{}',
    stock_lifted JSONB NOT NULL DEFAULT '{}',
    sales JSONB NOT NULL DEFAULT '{}',
    returns JSONB NOT NULL DEFAULT '{}',
    closing_stock JSONB NOT NULL DEFAULT '{}',

    -- Financial linkages (to existing finance tables)
    money_collection_id UUID,
    cash_deposit_id UUID,
    consideration_fee_paid DECIMAL(12,2) DEFAULT 0,

    -- Portal upload status
    uploaded_to_portal BOOLEAN DEFAULT false,
    upload_timestamp TIMESTAMP,
    upload_attempts INTEGER DEFAULT 0,
    sms_confirmation VARCHAR(100),
    portal_response JSONB,
    portal_status VARCHAR(20) DEFAULT 'pending',

    -- Report metadata
    report_status VARCHAR(20) DEFAULT 'draft',
    generated_automatically BOOLEAN DEFAULT false,

    -- Audit fields
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by UUID,
    uploaded_by UUID,

    -- Foreign keys
    CONSTRAINT fk_daily_report_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_daily_report_shop FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
    CONSTRAINT fk_daily_report_license FOREIGN KEY (license_id) REFERENCES excise_licenses(id) ON DELETE CASCADE,
    CONSTRAINT fk_daily_report_money_collection FOREIGN KEY (money_collection_id) REFERENCES money_collections(id) ON DELETE SET NULL,
    CONSTRAINT fk_daily_report_cash_deposit FOREIGN KEY (cash_deposit_id) REFERENCES cash_deposits(id) ON DELETE SET NULL,
    CONSTRAINT fk_daily_report_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_daily_report_uploaded_by FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE SET NULL,

    -- Unique constraint (one report per shop per day)
    CONSTRAINT unique_shop_report_date UNIQUE (shop_id, report_date),

    -- Check constraints
    CONSTRAINT check_report_status CHECK (report_status IN ('draft', 'submitted', 'uploaded', 'failed')),
    CONSTRAINT check_portal_status CHECK (portal_status IN ('pending', 'uploading', 'success', 'failed', 'retry')),
    CONSTRAINT check_consideration_fee CHECK (consideration_fee_paid >= 0)
);

-- Indexes
CREATE INDEX idx_daily_reports_tenant ON excise_daily_reports(tenant_id);
CREATE INDEX idx_daily_reports_shop ON excise_daily_reports(shop_id);
CREATE INDEX idx_daily_reports_license ON excise_daily_reports(license_id);
CREATE INDEX idx_daily_reports_date ON excise_daily_reports(report_date DESC);
CREATE INDEX idx_daily_reports_uploaded ON excise_daily_reports(uploaded_to_portal, report_date DESC);
CREATE INDEX idx_daily_reports_status ON excise_daily_reports(report_status, portal_status);
CREATE INDEX idx_daily_reports_pending ON excise_daily_reports(shop_id, uploaded_to_portal) WHERE uploaded_to_portal = false;

-- Comments
COMMENT ON TABLE excise_daily_reports IS 'Daily excise reports for UP Excise portal submission';
COMMENT ON COLUMN excise_daily_reports.opening_stock IS 'Opening stock breakdown by product/category (JSONB)';
COMMENT ON COLUMN excise_daily_reports.stock_lifted IS 'Stock lifted today from CL-2 godowns (JSONB)';
COMMENT ON COLUMN excise_daily_reports.sales IS 'Sales made today (JSONB)';
COMMENT ON COLUMN excise_daily_reports.closing_stock IS 'Closing stock = opening + lifted - sales + returns (JSONB)';
COMMENT ON COLUMN excise_daily_reports.sms_confirmation IS 'SMS confirmation code received from UP Excise portal';
COMMENT ON COLUMN excise_daily_reports.portal_response IS 'Full response from UP Excise portal (JSONB)';

-- ============================================================
-- 3. BOTTLE SECURITY CODES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS bottle_security_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    security_code VARCHAR(50) UNIQUE NOT NULL,

    -- Product linkage
    product_id UUID NOT NULL,
    product_name VARCHAR(200),

    -- Transaction linkages
    vendor_transaction_id UUID,
    stock_purchase_id UUID,
    sale_id UUID,

    -- Status tracking
    status VARCHAR(20) DEFAULT 'in_stock',
    received_date DATE,
    sold_date DATE,

    -- Source tracking
    warehouse_source VARCHAR(100),
    cl2_godown_id UUID,
    batch_number VARCHAR(50),

    -- Additional metadata
    verified BOOLEAN DEFAULT false,
    verification_date TIMESTAMP,

    -- Multi-tenancy
    tenant_id UUID NOT NULL,
    shop_id UUID,

    -- Audit fields
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by UUID,

    -- Foreign keys
    CONSTRAINT fk_security_code_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_security_code_shop FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE SET NULL,
    CONSTRAINT fk_security_code_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    CONSTRAINT fk_security_code_vendor_txn FOREIGN KEY (vendor_transaction_id) REFERENCES vendor_transactions(id) ON DELETE SET NULL,
    CONSTRAINT fk_security_code_purchase FOREIGN KEY (stock_purchase_id) REFERENCES stock_purchases(id) ON DELETE SET NULL,
    CONSTRAINT fk_security_code_sale FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL,
    CONSTRAINT fk_security_code_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,

    -- Check constraints
    CONSTRAINT check_security_code_status CHECK (status IN ('in_stock', 'sold', 'damaged', 'missing', 'returned')),
    CONSTRAINT check_security_code_format CHECK (length(security_code) >= 6)
);

-- Indexes
CREATE INDEX idx_security_codes_code ON bottle_security_codes(security_code);
CREATE INDEX idx_security_codes_product ON bottle_security_codes(product_id);
CREATE INDEX idx_security_codes_status ON bottle_security_codes(status);
CREATE INDEX idx_security_codes_tenant ON bottle_security_codes(tenant_id);
CREATE INDEX idx_security_codes_shop ON bottle_security_codes(shop_id);
CREATE INDEX idx_security_codes_dates ON bottle_security_codes(received_date, sold_date);
CREATE INDEX idx_security_codes_purchase ON bottle_security_codes(stock_purchase_id) WHERE stock_purchase_id IS NOT NULL;
CREATE INDEX idx_security_codes_sale ON bottle_security_codes(sale_id) WHERE sale_id IS NOT NULL;
CREATE INDEX idx_security_codes_in_stock ON bottle_security_codes(tenant_id, status) WHERE status = 'in_stock';

-- Comments
COMMENT ON TABLE bottle_security_codes IS 'Security codes for individual bottles (mandatory for UP Excise compliance)';
COMMENT ON COLUMN bottle_security_codes.security_code IS 'Unique security code printed on bottle (proof of excise duty payment)';
COMMENT ON COLUMN bottle_security_codes.status IS 'Current status: in_stock, sold, damaged, missing, returned';
COMMENT ON COLUMN bottle_security_codes.warehouse_source IS 'Name of CL-2 godown/warehouse from which bottle was received';

-- ============================================================
-- 4. EXCISE COMPLIANCE LOGS TABLE (Audit Trail)
-- ============================================================

CREATE TABLE IF NOT EXISTS excise_compliance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    shop_id UUID,
    license_id UUID,

    -- Log details
    log_type VARCHAR(50) NOT NULL,
    log_level VARCHAR(20) DEFAULT 'info',
    message TEXT NOT NULL,
    details JSONB,

    -- Related entities
    related_entity_type VARCHAR(50),
    related_entity_id UUID,

    -- Timestamp
    logged_at TIMESTAMP DEFAULT NOW(),
    logged_by UUID,

    -- Foreign keys
    CONSTRAINT fk_compliance_log_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_compliance_log_shop FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE SET NULL,
    CONSTRAINT fk_compliance_log_license FOREIGN KEY (license_id) REFERENCES excise_licenses(id) ON DELETE SET NULL,
    CONSTRAINT fk_compliance_log_user FOREIGN KEY (logged_by) REFERENCES users(id) ON DELETE SET NULL,

    -- Check constraints
    CONSTRAINT check_log_type CHECK (log_type IN ('license_created', 'license_renewed', 'license_expired', 'fee_paid', 'report_generated', 'report_uploaded', 'upload_failed', 'security_code_added', 'security_code_verified', 'consideration_fee_paid', 'compliance_warning', 'compliance_violation')),
    CONSTRAINT check_log_level CHECK (log_level IN ('debug', 'info', 'warning', 'error', 'critical'))
);

-- Indexes
CREATE INDEX idx_compliance_logs_tenant ON excise_compliance_logs(tenant_id);
CREATE INDEX idx_compliance_logs_shop ON excise_compliance_logs(shop_id);
CREATE INDEX idx_compliance_logs_license ON excise_compliance_logs(license_id);
CREATE INDEX idx_compliance_logs_type ON excise_compliance_logs(log_type);
CREATE INDEX idx_compliance_logs_level ON excise_compliance_logs(log_level);
CREATE INDEX idx_compliance_logs_time ON excise_compliance_logs(logged_at DESC);
CREATE INDEX idx_compliance_logs_entity ON excise_compliance_logs(related_entity_type, related_entity_id);

-- Comments
COMMENT ON TABLE excise_compliance_logs IS 'Audit trail for all excise compliance activities';
COMMENT ON COLUMN excise_compliance_logs.log_type IS 'Type of compliance event';
COMMENT ON COLUMN excise_compliance_logs.log_level IS 'Severity: debug, info, warning, error, critical';

-- ============================================================
-- 5. UPDATE FOREIGN KEY CONSTRAINTS ON EXTENDED TABLES
-- ============================================================

-- Add foreign key from expenses to excise_licenses
ALTER TABLE expenses
DROP CONSTRAINT IF EXISTS fk_expenses_excise_license,
ADD CONSTRAINT fk_expenses_excise_license
    FOREIGN KEY (excise_license_id)
    REFERENCES excise_licenses(id)
    ON DELETE SET NULL;

-- Add foreign key from cash_deposits to excise_daily_reports
ALTER TABLE cash_deposits
DROP CONSTRAINT IF EXISTS fk_cash_deposits_excise_report,
ADD CONSTRAINT fk_cash_deposits_excise_report
    FOREIGN KEY (excise_report_id)
    REFERENCES excise_daily_reports(id)
    ON DELETE SET NULL;

-- Add foreign key from money_collections to excise_daily_reports
ALTER TABLE money_collections
DROP CONSTRAINT IF EXISTS fk_money_collections_excise_report,
ADD CONSTRAINT fk_money_collections_excise_report
    FOREIGN KEY (excise_report_id)
    REFERENCES excise_daily_reports(id)
    ON DELETE SET NULL;

-- Add foreign key from shops to excise_licenses
ALTER TABLE shops
DROP CONSTRAINT IF EXISTS fk_shops_excise_license,
ADD CONSTRAINT fk_shops_excise_license
    FOREIGN KEY (excise_license_id)
    REFERENCES excise_licenses(id)
    ON DELETE SET NULL;

-- ============================================================
-- 6. CREATE HELPER VIEWS
-- ============================================================

-- View: Active licenses with shop details
CREATE OR REPLACE VIEW vw_active_licenses AS
SELECT
    l.id,
    l.tenant_id,
    l.shop_id,
    s.name as shop_name,
    s.address as shop_address,
    l.license_number,
    l.license_type,
    l.issued_date,
    l.expiry_date,
    l.monthly_fee,
    l.is_active,
    EXTRACT(DAY FROM (l.expiry_date - CURRENT_DATE)) as days_until_expiry,
    CASE
        WHEN l.expiry_date < CURRENT_DATE THEN 'expired'
        WHEN l.expiry_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'expiring_soon'
        ELSE 'active'
    END as license_status
FROM excise_licenses l
JOIN shops s ON l.shop_id = s.id
WHERE l.is_active = true;

-- View: Daily reports pending upload
CREATE OR REPLACE VIEW vw_pending_excise_reports AS
SELECT
    r.id,
    r.tenant_id,
    r.shop_id,
    s.name as shop_name,
    r.report_date,
    r.created_at,
    r.upload_attempts,
    EXTRACT(HOUR FROM (NOW() - r.created_at)) as hours_since_creation
FROM excise_daily_reports r
JOIN shops s ON r.shop_id = s.id
WHERE r.uploaded_to_portal = false
  AND r.report_status != 'draft'
ORDER BY r.report_date DESC;

-- View: Security codes summary by shop
CREATE OR REPLACE VIEW vw_security_codes_summary AS
SELECT
    shop_id,
    s.name as shop_name,
    COUNT(*) as total_codes,
    COUNT(*) FILTER (WHERE status = 'in_stock') as in_stock,
    COUNT(*) FILTER (WHERE status = 'sold') as sold,
    COUNT(*) FILTER (WHERE status = 'damaged') as damaged,
    COUNT(*) FILTER (WHERE status = 'missing') as missing
FROM bottle_security_codes bsc
JOIN shops s ON bsc.shop_id = s.id
GROUP BY shop_id, s.name;

-- ============================================================
-- 7. CREATE HELPER FUNCTIONS
-- ============================================================

-- Function: Calculate days until license expiry
CREATE OR REPLACE FUNCTION get_license_expiry_days(license_id UUID)
RETURNS INTEGER AS $$
DECLARE
    expiry_date DATE;
BEGIN
    SELECT expiry_date INTO expiry_date
    FROM excise_licenses
    WHERE id = license_id;

    RETURN EXTRACT(DAY FROM (expiry_date - CURRENT_DATE))::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- Function: Check if daily report exists for date
CREATE OR REPLACE FUNCTION has_daily_report(p_shop_id UUID, p_report_date DATE)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM excise_daily_reports
        WHERE shop_id = p_shop_id
          AND report_date = p_report_date
    );
END;
$$ LANGUAGE plpgsql;

-- Function: Get pending license fees
CREATE OR REPLACE FUNCTION get_pending_license_fees(p_license_id UUID)
RETURNS TABLE (
    month DATE,
    amount DECIMAL,
    days_overdue INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH months AS (
        SELECT
            date_trunc('month', d)::DATE as month,
            (SELECT monthly_fee FROM excise_licenses WHERE id = p_license_id) as fee
        FROM generate_series(
            (SELECT issued_date FROM excise_licenses WHERE id = p_license_id),
            CURRENT_DATE,
            '1 month'::interval
        ) d
    )
    SELECT
        m.month,
        m.fee,
        EXTRACT(DAY FROM (CURRENT_DATE - (m.month + INTERVAL '1 month')))::INTEGER as days_overdue
    FROM months m
    WHERE NOT EXISTS (
        SELECT 1
        FROM expenses e
        WHERE e.excise_license_id = p_license_id
          AND e.is_license_fee = true
          AND e.license_fee_month = m.month
          AND e.status = 'paid'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 8. TRIGGERS
-- ============================================================

-- Trigger: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_excise_licenses_updated_at
    BEFORE UPDATE ON excise_licenses
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_excise_daily_reports_updated_at
    BEFORE UPDATE ON excise_daily_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_bottle_security_codes_updated_at
    BEFORE UPDATE ON bottle_security_codes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger: Log license fee payment
CREATE OR REPLACE FUNCTION log_license_fee_payment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_license_fee = true AND NEW.status = 'paid' THEN
        INSERT INTO excise_compliance_logs (
            tenant_id,
            shop_id,
            license_id,
            log_type,
            log_level,
            message,
            details,
            logged_by
        ) VALUES (
            NEW.tenant_id,
            NEW.shop_id,
            NEW.excise_license_id,
            'fee_paid',
            'info',
            'License fee paid for ' || TO_CHAR(NEW.license_fee_month, 'Mon YYYY'),
            jsonb_build_object(
                'expense_id', NEW.id,
                'amount', NEW.amount,
                'payment_method', NEW.payment_method,
                'receipt_no', NEW.receipt_no
            ),
            NEW.created_by_id
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_log_license_fee
    AFTER INSERT OR UPDATE ON expenses
    FOR EACH ROW
    EXECUTE FUNCTION log_license_fee_payment();

-- ============================================================
-- 9. SEED DATA (Optional - for testing)
-- ============================================================

-- Insert sample expense categories for excise
INSERT INTO expense_categories (id, tenant_id, name, description, is_active, created_by)
SELECT
    gen_random_uuid(),
    t.id,
    'License Fees',
    'Monthly excise license fees',
    true,
    (SELECT id FROM users WHERE tenant_id = t.id LIMIT 1)
FROM tenants t
WHERE NOT EXISTS (
    SELECT 1 FROM expense_categories
    WHERE tenant_id = t.id AND name = 'License Fees'
);

-- ============================================================
-- VERIFICATION QUERIES
-- ============================================================

-- Verify tables created
-- SELECT table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('excise_licenses', 'excise_daily_reports', 'bottle_security_codes', 'excise_compliance_logs')
-- ORDER BY table_name;

-- Verify views created
-- SELECT table_name
-- FROM information_schema.views
-- WHERE table_schema = 'public'
--   AND table_name LIKE 'vw_%'
-- ORDER BY table_name;

-- Verify functions created
-- SELECT routine_name
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_type = 'FUNCTION'
--   AND routine_name IN ('get_license_expiry_days', 'has_daily_report', 'get_pending_license_fees')
-- ORDER BY routine_name;

-- ============================================================
-- GRANTS (Ensure proper permissions)
-- ============================================================

-- Grant permissions to application user (adjust username as needed)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON excise_licenses TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON excise_daily_reports TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON bottle_security_codes TO liquorpro_app;
-- GRANT SELECT, INSERT ON excise_compliance_logs TO liquorpro_app;
-- GRANT SELECT ON vw_active_licenses TO liquorpro_app;
-- GRANT SELECT ON vw_pending_excise_reports TO liquorpro_app;
-- GRANT SELECT ON vw_security_codes_summary TO liquorpro_app;

-- ============================================================
-- ROLLBACK SCRIPT (uncomment to rollback changes)
-- ============================================================

/*
DROP TRIGGER IF EXISTS trigger_log_license_fee ON expenses;
DROP TRIGGER IF EXISTS trigger_bottle_security_codes_updated_at ON bottle_security_codes;
DROP TRIGGER IF EXISTS trigger_excise_daily_reports_updated_at ON excise_daily_reports;
DROP TRIGGER IF EXISTS trigger_excise_licenses_updated_at ON excise_licenses;

DROP FUNCTION IF EXISTS log_license_fee_payment();
DROP FUNCTION IF EXISTS update_updated_at_column();
DROP FUNCTION IF EXISTS get_pending_license_fees(UUID);
DROP FUNCTION IF EXISTS has_daily_report(UUID, DATE);
DROP FUNCTION IF EXISTS get_license_expiry_days(UUID);

DROP VIEW IF EXISTS vw_security_codes_summary;
DROP VIEW IF EXISTS vw_pending_excise_reports;
DROP VIEW IF EXISTS vw_active_licenses;

DROP TABLE IF EXISTS excise_compliance_logs CASCADE;
DROP TABLE IF EXISTS bottle_security_codes CASCADE;
DROP TABLE IF EXISTS excise_daily_reports CASCADE;
DROP TABLE IF EXISTS excise_licenses CASCADE;
*/

-- ============================================================
-- END OF MIGRATION
-- ============================================================

-- Log migration completion
DO $$
BEGIN
    RAISE NOTICE 'Migration 002_create_excise_tables.sql completed successfully';
    RAISE NOTICE 'Created tables: excise_licenses, excise_daily_reports, bottle_security_codes, excise_compliance_logs';
    RAISE NOTICE 'Created views: vw_active_licenses, vw_pending_excise_reports, vw_security_codes_summary';
    RAISE NOTICE 'Created functions: get_license_expiry_days, has_daily_report, get_pending_license_fees';
END $$;
