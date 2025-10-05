-- Create SaaS Service Database Tables
-- This script creates all necessary tables for the subscription management system

BEGIN;

-- 1. Create pricing_plans table with enhanced multi-term support
CREATE TABLE IF NOT EXISTS pricing_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    billing_cycle VARCHAR(50) NOT NULL DEFAULT 'monthly',
    billing_term_months INTEGER DEFAULT 1,
    trial_days INTEGER DEFAULT 60,
    max_locations INTEGER DEFAULT 1,
    max_users INTEGER DEFAULT 10,
    max_products INTEGER DEFAULT 1000,
    features JSONB DEFAULT '[]',
    ai_features JSONB DEFAULT '[]',
    popular BOOLEAN DEFAULT false,
    enterprise BOOLEAN DEFAULT false,
    active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    razorpay_plan_id VARCHAR(255),
    yearly_discount DECIMAL(5,2) DEFAULT 20.0,
    two_year_discount DECIMAL(5,2) DEFAULT 30.0,
    three_year_discount DECIMAL(5,2) DEFAULT 40.0,
    auto_create_variants BOOLEAN DEFAULT true,
    discount_strategy JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 2. Create subscriptions table with detailed tracking
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    plan_id UUID NOT NULL REFERENCES pricing_plans(id),
    status VARCHAR(50) NOT NULL DEFAULT 'trial',
    current_period_start TIMESTAMP,
    current_period_end TIMESTAMP,
    trial_start TIMESTAMP,
    trial_end TIMESTAMP,
    cancelled_at TIMESTAMP,
    ended_at TIMESTAMP,
    razorpay_customer_id VARCHAR(255),
    razorpay_subscription_id VARCHAR(255),
    auto_renew BOOLEAN DEFAULT true,
    billing_cycle VARCHAR(50) NOT NULL DEFAULT 'monthly',
    billing_term_months INTEGER DEFAULT 1,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    next_billing_date TIMESTAMP,
    discount_applied DECIMAL(5,2) DEFAULT 0,
    original_price DECIMAL(10,2),
    discount_reason TEXT,
    term_start_date TIMESTAMP,
    term_end_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 3. Create plan_billing_variants table for dynamic pricing
CREATE TABLE IF NOT EXISTS plan_billing_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_plan_id UUID NOT NULL REFERENCES pricing_plans(id) ON DELETE CASCADE,
    billing_term_months INTEGER NOT NULL,
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    effective_price DECIMAL(10,2) NOT NULL,
    razorpay_plan_id VARCHAR(255),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(base_plan_id, billing_term_months)
);

-- 4. Create payments table
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    invoice_id UUID,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    status VARCHAR(50) NOT NULL,
    payment_method VARCHAR(100),
    razorpay_payment_id VARCHAR(255),
    razorpay_order_id VARCHAR(255),
    razorpay_signature VARCHAR(255),
    failure_reason TEXT,
    processed_at TIMESTAMP,
    refunded_at TIMESTAMP,
    refund_amount DECIMAL(10,2) DEFAULT 0,
    refund_reason TEXT,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 5. Create invoices table
CREATE TABLE IF NOT EXISTS invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    invoice_number VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'draft',
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    tax DECIMAL(10,2) DEFAULT 0,
    discount DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    period_start TIMESTAMP,
    period_end TIMESTAMP,
    due_date TIMESTAMP,
    paid_at TIMESTAMP,
    voided_at TIMESTAMP,
    billing_name VARCHAR(255),
    billing_email VARCHAR(255),
    billing_address TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 6. Create usage_records table
CREATE TABLE IF NOT EXISTS usage_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    record_date DATE NOT NULL,
    locations INTEGER DEFAULT 0,
    users INTEGER DEFAULT 0,
    products INTEGER DEFAULT 0,
    sales INTEGER DEFAULT 0,
    api_requests INTEGER DEFAULT 0,
    storage_used BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 7. Create webhook_events table
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider VARCHAR(50) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_id VARCHAR(255) UNIQUE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    payload TEXT,
    processed_at TIMESTAMP,
    error_message TEXT,
    retries INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 8. Create admin_users table
CREATE TABLE IF NOT EXISTS admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'admin',
    active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- 9. Create audit_logs table
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES admin_users(id),
    tenant_id UUID REFERENCES tenants(id),
    action VARCHAR(100) NOT NULL,
    resource VARCHAR(100) NOT NULL,
    resource_id VARCHAR(255),
    old_values TEXT,
    new_values TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_pricing_plans_active ON pricing_plans(active) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_pricing_plans_billing_cycle ON pricing_plans(billing_cycle);
CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant ON subscriptions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_plan ON subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_billing_dates ON subscriptions(current_period_start, current_period_end);
CREATE INDEX IF NOT EXISTS idx_plan_billing_variants_base_plan ON plan_billing_variants(base_plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_billing_variants_term ON plan_billing_variants(billing_term_months);
CREATE INDEX IF NOT EXISTS idx_payments_subscription ON payments(subscription_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_invoices_subscription ON invoices(subscription_id);
CREATE INDEX IF NOT EXISTS idx_usage_records_subscription ON usage_records(subscription_id);
CREATE INDEX IF NOT EXISTS idx_usage_records_date ON usage_records(record_date);
CREATE INDEX IF NOT EXISTS idx_webhook_events_status ON webhook_events(status);
CREATE INDEX IF NOT EXISTS idx_audit_logs_admin_user ON audit_logs(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON audit_logs(resource, resource_id);

COMMIT;

-- Insert default pricing plans with multi-term support
INSERT INTO pricing_plans (
    name, display_name, description, price, currency, billing_cycle, billing_term_months,
    trial_days, max_locations, max_users, max_products, features, ai_features, 
    popular, enterprise, active, sort_order, yearly_discount, two_year_discount, three_year_discount
) VALUES 
(
    'smart_starter',
    'Smart Starter',
    'Perfect for small businesses getting started with AI-powered liquor inventory management',
    49.0,
    'INR',
    'monthly',
    1,
    60,
    3,
    10,
    500,
    '["inventory_management", "sales_tracking", "basic_reports", "mobile_app", "email_support"]',
    '["inventory_optimization", "sales_forecasting"]',
    false,
    false,
    true,
    1,
    20.0,
    30.0,
    40.0
),
(
    'pro_intelligence',
    'Pro Intelligence',
    'Advanced features for growing businesses with AI-powered insights and analytics',
    149.0,
    'INR',
    'monthly',
    1,
    60,
    -1,
    50,
    -1,
    '["everything_in_starter", "advanced_analytics", "api_access", "custom_reports", "priority_support", "multi_location"]',
    '["advanced_forecasting", "demand_planning", "price_optimization", "customer_insights"]',
    true,
    false,
    true,
    2,
    25.0,
    35.0,
    45.0
),
(
    'enterprise_ai',
    'Enterprise AI',
    'Complete enterprise solution with advanced AI capabilities and dedicated support',
    299.0,
    'INR',
    'monthly',
    1,
    30,
    -1,
    -1,
    -1,
    '["everything_in_pro", "white_label", "dedicated_support", "custom_integrations", "sla_guarantee", "advanced_security"]',
    '["predictive_analytics", "market_intelligence", "supply_chain_optimization", "custom_ai_models"]',
    false,
    true,
    true,
    3,
    30.0,
    40.0,
    50.0
) ON CONFLICT (name) DO NOTHING;

-- Create billing variants for each plan
DO $$
DECLARE
    plan_record RECORD;
    monthly_price DECIMAL(10,2);
    yearly_price DECIMAL(10,2);
    two_year_price DECIMAL(10,2);
    three_year_price DECIMAL(10,2);
BEGIN
    FOR plan_record IN SELECT * FROM pricing_plans WHERE active = true LOOP
        monthly_price := plan_record.price;
        yearly_price := monthly_price * 12 * (1 - plan_record.yearly_discount/100);
        two_year_price := monthly_price * 24 * (1 - plan_record.two_year_discount/100);
        three_year_price := monthly_price * 36 * (1 - plan_record.three_year_discount/100);
        
        -- Insert billing variants
        INSERT INTO plan_billing_variants (base_plan_id, billing_term_months, discount_percentage, effective_price) VALUES
        (plan_record.id, 1, 0, monthly_price),
        (plan_record.id, 12, plan_record.yearly_discount, yearly_price),
        (plan_record.id, 24, plan_record.two_year_discount, two_year_price),
        (plan_record.id, 36, plan_record.three_year_discount, three_year_price)
        ON CONFLICT (base_plan_id, billing_term_months) DO NOTHING;
    END LOOP;
END $$;

-- Verification and success message
SELECT 'SaaS Tables Created Successfully!' as status;
SELECT 'Total Plans:', COUNT(*) FROM pricing_plans;
SELECT 'Total Billing Variants:', COUNT(*) FROM plan_billing_variants;