-- Enhanced Subscription and Billing System Schema
-- Implements industrial-grade subscription management with comprehensive billing automation

-- Plan Extended Data Table (stores comprehensive plan information)
CREATE TABLE IF NOT EXISTS plan_extended_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES pricing_plans(id) ON DELETE CASCADE,
    data JSONB NOT NULL, -- Stores limits, features, pricing structure
    version INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE NULL
);

CREATE INDEX idx_plan_extended_data_plan_id ON plan_extended_data(plan_id);
CREATE INDEX idx_plan_extended_data_version ON plan_extended_data(plan_id, version DESC);

-- Billing Cycle Jobs Table (for autonomous billing processing)
CREATE TABLE IF NOT EXISTS billing_cycle_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(50) NOT NULL, -- renewal, trial_ending, grace_period, suspension
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    scheduled_for TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(20) DEFAULT 'pending', -- pending, processing, completed, failed
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    last_error TEXT,
    processing_started_at TIMESTAMP WITH TIME ZONE NULL,
    processing_completed_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_billing_jobs_scheduled ON billing_cycle_jobs(scheduled_for, status);
CREATE INDEX idx_billing_jobs_subscription ON billing_cycle_jobs(subscription_id);
CREATE INDEX idx_billing_jobs_type_status ON billing_cycle_jobs(type, status);

-- Payment Attempts Table (tracks payment retry attempts)
CREATE TABLE IF NOT EXISTS payment_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL, -- pending, processing, succeeded, failed
    failure_reason TEXT,
    payment_method_info JSONB, -- Store payment method details
    gateway_transaction_id VARCHAR(255),
    gateway_response JSONB, -- Store gateway response
    attempted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    next_retry_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_payment_attempts_payment ON payment_attempts(payment_id);
CREATE INDEX idx_payment_attempts_retry ON payment_attempts(next_retry_at, status);
CREATE INDEX idx_payment_attempts_status ON payment_attempts(status, attempted_at);

-- Billing Events Table (audit trail for billing operations)
CREATE TABLE IF NOT EXISTS billing_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(50) NOT NULL, -- invoice_created, payment_succeeded, subscription_renewed, etc.
    tenant_id UUID NULL REFERENCES tenants(id),
    subscription_id UUID NULL REFERENCES subscriptions(id),
    invoice_id UUID NULL REFERENCES invoices(id),
    payment_id UUID NULL REFERENCES payments(id),
    data JSONB NOT NULL, -- Event-specific data
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'processed', -- pending, processed, failed
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_billing_events_type ON billing_events(type, processed_at);
CREATE INDEX idx_billing_events_tenant ON billing_events(tenant_id, processed_at);
CREATE INDEX idx_billing_events_subscription ON billing_events(subscription_id, processed_at);

-- Scheduled Plan Changes Table (for managing plan upgrades/downgrades)
CREATE TABLE IF NOT EXISTS scheduled_plan_changes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    current_plan_id UUID NOT NULL REFERENCES pricing_plans(id),
    new_plan_id UUID NOT NULL REFERENCES pricing_plans(id),
    change_type VARCHAR(20) NOT NULL, -- upgrade, downgrade, change
    effective_date TIMESTAMP WITH TIME ZONE NOT NULL,
    proration_method VARCHAR(20) DEFAULT 'immediate', -- immediate, next_cycle, custom
    proration_amount DECIMAL(10,2) DEFAULT 0.00,
    status VARCHAR(20) DEFAULT 'scheduled', -- scheduled, processing, completed, cancelled
    requested_by UUID NULL, -- Admin user who requested the change
    reason TEXT,
    processed_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_scheduled_changes_subscription ON scheduled_plan_changes(subscription_id);
CREATE INDEX idx_scheduled_changes_effective ON scheduled_plan_changes(effective_date, status);

-- Subscription Addons Table (for additional features/services)
CREATE TABLE IF NOT EXISTS subscription_addons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    addon_name VARCHAR(100) NOT NULL,
    addon_type VARCHAR(50) NOT NULL, -- feature, limit_increase, service
    price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',
    billing_cycle VARCHAR(20) DEFAULT 'monthly',
    quantity INTEGER DEFAULT 1,
    status VARCHAR(20) DEFAULT 'active', -- active, suspended, cancelled
    activated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    cancelled_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_subscription_addons_subscription ON subscription_addons(subscription_id);
CREATE INDEX idx_subscription_addons_status ON subscription_addons(status);

-- Dunning Management Table (tracks payment recovery efforts)
CREATE TABLE IF NOT EXISTS dunning_sequences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    sequence_type VARCHAR(30) DEFAULT 'standard', -- standard, vip, enterprise
    current_step INTEGER DEFAULT 1,
    max_steps INTEGER DEFAULT 4,
    step_schedule JSONB NOT NULL, -- Array of step configurations
    status VARCHAR(20) DEFAULT 'active', -- active, paused, completed, cancelled
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE NULL,
    next_action_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_dunning_sequences_subscription ON dunning_sequences(subscription_id);
CREATE INDEX idx_dunning_sequences_next_action ON dunning_sequences(next_action_at, status);

-- Dunning Actions Table (tracks individual dunning actions)
CREATE TABLE IF NOT EXISTS dunning_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sequence_id UUID NOT NULL REFERENCES dunning_sequences(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL,
    action_type VARCHAR(30) NOT NULL, -- email, sms, phone_call, service_suspension
    status VARCHAR(20) DEFAULT 'pending', -- pending, sent, delivered, failed
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    executed_at TIMESTAMP WITH TIME ZONE NULL,
    response_data JSONB, -- Store response from email/SMS service
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_dunning_actions_sequence ON dunning_actions(sequence_id);
CREATE INDEX idx_dunning_actions_scheduled ON dunning_actions(scheduled_at, status);

-- Subscription Metrics Table (for analytics and reporting)
CREATE TABLE IF NOT EXISTS subscription_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    metric_date DATE NOT NULL,
    mrr DECIMAL(10,2) DEFAULT 0.00, -- Monthly Recurring Revenue
    arr DECIMAL(10,2) DEFAULT 0.00, -- Annual Recurring Revenue
    ltv DECIMAL(10,2) DEFAULT 0.00, -- Customer Lifetime Value
    churn_score DECIMAL(5,2) DEFAULT 0.00, -- Churn prediction score (0-100)
    health_score DECIMAL(5,2) DEFAULT 100.00, -- Subscription health (0-100)
    usage_score DECIMAL(5,2) DEFAULT 0.00, -- Usage adoption score (0-100)
    payment_health VARCHAR(20) DEFAULT 'healthy', -- healthy, at_risk, failed
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(subscription_id, metric_date)
);

CREATE INDEX idx_subscription_metrics_tenant_date ON subscription_metrics(tenant_id, metric_date);
CREATE INDEX idx_subscription_metrics_subscription_date ON subscription_metrics(subscription_id, metric_date);
CREATE INDEX idx_subscription_metrics_health ON subscription_metrics(health_score, metric_date);

-- Webhook Delivery Attempts Table (tracks webhook delivery)
CREATE TABLE IF NOT EXISTS webhook_delivery_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_event_id UUID NOT NULL REFERENCES webhook_events(id) ON DELETE CASCADE,
    endpoint_url VARCHAR(500) NOT NULL,
    attempt_number INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL, -- pending, delivered, failed, retrying
    http_status_code INTEGER,
    response_body TEXT,
    response_headers JSONB,
    error_message TEXT,
    attempted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    next_retry_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_webhook_attempts_event ON webhook_delivery_attempts(webhook_event_id);
CREATE INDEX idx_webhook_attempts_retry ON webhook_delivery_attempts(next_retry_at, status);

-- Enhanced Usage Records with detailed tracking
ALTER TABLE usage_records ADD COLUMN IF NOT EXISTS detailed_usage JSONB;
ALTER TABLE usage_records ADD COLUMN IF NOT EXISTS overage_charges JSONB;
ALTER TABLE usage_records ADD COLUMN IF NOT EXISTS billing_period_start DATE;
ALTER TABLE usage_records ADD COLUMN IF NOT EXISTS billing_period_end DATE;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_usage_records_billing_period ON usage_records(tenant_id, billing_period_start, billing_period_end);
CREATE INDEX IF NOT EXISTS idx_usage_records_date ON usage_records(record_date);

-- Subscription Feature Flags Table (for feature toggles)
CREATE TABLE IF NOT EXISTS subscription_feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    feature_name VARCHAR(100) NOT NULL,
    enabled BOOLEAN DEFAULT true,
    configuration JSONB, -- Feature-specific configuration
    enabled_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    disabled_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(subscription_id, feature_name)
);

CREATE INDEX idx_subscription_features_subscription ON subscription_feature_flags(subscription_id);
CREATE INDEX idx_subscription_features_enabled ON subscription_feature_flags(enabled, feature_name);

-- Plan Usage Quotas Table (for granular limit tracking)
CREATE TABLE IF NOT EXISTS plan_usage_quotas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    quota_type VARCHAR(50) NOT NULL, -- users, shops, products, api_requests, storage
    quota_limit INTEGER NOT NULL, -- -1 for unlimited
    current_usage INTEGER DEFAULT 0,
    reset_period VARCHAR(20) DEFAULT 'monthly', -- daily, weekly, monthly, yearly
    last_reset_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    next_reset_at TIMESTAMP WITH TIME ZONE NOT NULL,
    overage_allowed BOOLEAN DEFAULT false,
    overage_rate DECIMAL(10,4) DEFAULT 0.0000, -- Cost per unit over limit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(subscription_id, quota_type)
);

CREATE INDEX idx_usage_quotas_subscription ON plan_usage_quotas(subscription_id);
CREATE INDEX idx_usage_quotas_reset ON plan_usage_quotas(next_reset_at);
CREATE INDEX idx_usage_quotas_overage ON plan_usage_quotas(overage_allowed, current_usage);

-- Billing Configurations Table (system-wide billing settings)
CREATE TABLE IF NOT EXISTS billing_configurations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    configuration_key VARCHAR(100) NOT NULL UNIQUE,
    configuration_value JSONB NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default billing configurations
INSERT INTO billing_configurations (configuration_key, configuration_value, description) VALUES
('grace_period_days', '7', 'Days of grace period after failed payment'),
('dunning_email_schedule', '[1, 3, 5, 7]', 'Days to send dunning emails'),
('trial_ending_notifications', '[7, 3, 1]', 'Days before trial end to send notifications'),
('auto_retry_failed_payments', 'true', 'Automatically retry failed payments'),
('max_payment_retries', '3', 'Maximum number of payment retry attempts'),
('retry_interval_hours', '[24, 72, 168]', 'Hours between payment retry attempts'),
('auto_suspend_on_failure', 'true', 'Automatically suspend on payment failure'),
('invoice_terms_days', '7', 'Payment terms for invoices in days'),
('proration_enabled', 'true', 'Enable proration for plan changes'),
('webhook_retry_count', '3', 'Number of webhook delivery retries')
ON CONFLICT (configuration_key) DO NOTHING;

-- Revenue Recognition Table (for financial reporting)
CREATE TABLE IF NOT EXISTS revenue_recognition (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id),
    invoice_id UUID NOT NULL REFERENCES invoices(id),
    recognition_date DATE NOT NULL,
    recognized_amount DECIMAL(10,2) NOT NULL,
    recognition_type VARCHAR(30) NOT NULL, -- subscription, setup, usage, addon
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_revenue_recognition_date ON revenue_recognition(recognition_date);
CREATE INDEX idx_revenue_recognition_subscription ON revenue_recognition(subscription_id, recognition_date);
CREATE INDEX idx_revenue_recognition_type ON revenue_recognition(recognition_type, recognition_date);

-- Customer Success Metrics Table
CREATE TABLE IF NOT EXISTS customer_success_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    metric_date DATE NOT NULL,
    login_frequency DECIMAL(5,2) DEFAULT 0.00, -- Logins per week
    feature_adoption_score DECIMAL(5,2) DEFAULT 0.00, -- 0-100
    support_ticket_count INTEGER DEFAULT 0,
    nps_score INTEGER NULL, -- Net Promoter Score
    churn_risk_score DECIMAL(5,2) DEFAULT 0.00, -- 0-100
    engagement_score DECIMAL(5,2) DEFAULT 0.00, -- 0-100
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(tenant_id, metric_date)
);

CREATE INDEX idx_customer_success_tenant_date ON customer_success_metrics(tenant_id, metric_date);
CREATE INDEX idx_customer_success_churn_risk ON customer_success_metrics(churn_risk_score DESC, metric_date);

-- Update existing subscriptions table with additional fields
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS grace_period_end TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS suspension_reason VARCHAR(255) NULL;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS last_payment_attempt TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS failed_payment_count INTEGER DEFAULT 0;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS subscription_source VARCHAR(50) DEFAULT 'direct'; -- direct, referral, campaign
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS referral_code VARCHAR(50) NULL;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_subscriptions_grace_period ON subscriptions(grace_period_end) WHERE grace_period_end IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_status_period ON subscriptions(status, current_period_end);
CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant_status ON subscriptions(tenant_id, status);

-- Update existing invoices table
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_terms_days INTEGER DEFAULT 7;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS late_fee DECIMAL(10,2) DEFAULT 0.00;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS collection_status VARCHAR(30) DEFAULT 'current'; -- current, overdue, in_collection, written_off
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS dunning_level INTEGER DEFAULT 0;

-- Add invoice aging indexes
CREATE INDEX IF NOT EXISTS idx_invoices_collection_status ON invoices(collection_status, due_date);
CREATE INDEX IF NOT EXISTS idx_invoices_overdue ON invoices(due_date, status) WHERE status IN ('open', 'overdue');

-- Create triggers for automatic updates
CREATE OR REPLACE FUNCTION update_subscription_metrics()
RETURNS TRIGGER AS $$
BEGIN
    -- Update last modification timestamp
    NEW.updated_at = NOW();
    
    -- Track payment failures
    IF NEW.status = 'past_due' AND OLD.status != 'past_due' THEN
        NEW.failed_payment_count = COALESCE(NEW.failed_payment_count, 0) + 1;
        NEW.last_payment_attempt = NOW();
    END IF;
    
    -- Reset failure count on successful payment
    IF NEW.status = 'active' AND OLD.status = 'past_due' THEN
        NEW.failed_payment_count = 0;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER subscription_metrics_trigger
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION update_subscription_metrics();

-- Create function for automatic quota reset
CREATE OR REPLACE FUNCTION reset_usage_quotas()
RETURNS void AS $$
BEGIN
    UPDATE plan_usage_quotas 
    SET current_usage = 0,
        last_reset_at = NOW(),
        next_reset_at = CASE 
            WHEN reset_period = 'daily' THEN NOW() + INTERVAL '1 day'
            WHEN reset_period = 'weekly' THEN NOW() + INTERVAL '1 week'
            WHEN reset_period = 'monthly' THEN NOW() + INTERVAL '1 month'
            WHEN reset_period = 'yearly' THEN NOW() + INTERVAL '1 year'
            ELSE NOW() + INTERVAL '1 month'
        END
    WHERE next_reset_at <= NOW();
END;
$$ LANGUAGE plpgsql;

-- Comments for documentation
COMMENT ON TABLE plan_extended_data IS 'Stores comprehensive plan configuration including limits, features, and pricing structure in JSONB format';
COMMENT ON TABLE billing_cycle_jobs IS 'Manages autonomous billing operations like renewals, notifications, and suspensions';
COMMENT ON TABLE payment_attempts IS 'Tracks payment retry attempts with detailed failure information';
COMMENT ON TABLE billing_events IS 'Audit trail for all billing-related events in the system';
COMMENT ON TABLE subscription_metrics IS 'Stores calculated metrics for subscription analytics and health monitoring';
COMMENT ON TABLE dunning_sequences IS 'Manages automated payment recovery sequences for failed payments';
COMMENT ON TABLE webhook_delivery_attempts IS 'Tracks webhook delivery attempts with retry logic';
COMMENT ON TABLE revenue_recognition IS 'Handles revenue recognition for financial reporting compliance';
COMMENT ON TABLE customer_success_metrics IS 'Tracks customer engagement and success indicators';

-- Create views for common queries
CREATE OR REPLACE VIEW subscription_health_dashboard AS
SELECT 
    s.id as subscription_id,
    s.tenant_id,
    s.status,
    s.current_period_end,
    s.failed_payment_count,
    p.name as plan_name,
    p.price as plan_price,
    sm.health_score,
    sm.churn_score,
    sm.payment_health,
    CASE 
        WHEN s.current_period_end < NOW() THEN 'expired'
        WHEN s.current_period_end < NOW() + INTERVAL '7 days' THEN 'expiring_soon'
        WHEN s.failed_payment_count > 0 THEN 'payment_issues'
        ELSE 'healthy'
    END as overall_status
FROM subscriptions s
JOIN pricing_plans p ON s.plan_id = p.id
LEFT JOIN subscription_metrics sm ON s.id = sm.subscription_id 
    AND sm.metric_date = CURRENT_DATE;

COMMENT ON VIEW subscription_health_dashboard IS 'Provides a comprehensive view of subscription health for monitoring and alerts';

-- Grant permissions (adjust as needed for your user roles)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO saas_admin;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO saas_admin;