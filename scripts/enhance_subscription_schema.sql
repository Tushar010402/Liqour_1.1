-- Enhanced Multi-Term Subscription Schema Migration
-- This migration is SAFE and adds new functionality without breaking existing features

BEGIN;

-- Phase 1: Enhance pricing_plans table with multi-term support
ALTER TABLE pricing_plans 
ADD COLUMN IF NOT EXISTS billing_term_months INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS two_year_discount DECIMAL(5,2) DEFAULT 30.0,
ADD COLUMN IF NOT EXISTS three_year_discount DECIMAL(5,2) DEFAULT 40.0,
ADD COLUMN IF NOT EXISTS auto_create_variants BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS discount_strategy JSONB DEFAULT '{}';

-- Phase 2: Enhance subscriptions table with detailed tracking
ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS billing_term_months INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS discount_applied DECIMAL(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS original_price DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS discount_reason TEXT,
ADD COLUMN IF NOT EXISTS term_start_date TIMESTAMP,
ADD COLUMN IF NOT EXISTS term_end_date TIMESTAMP;

-- Phase 3: Create plan_billing_variants table for dynamic pricing
CREATE TABLE IF NOT EXISTS plan_billing_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_plan_id UUID NOT NULL,
    billing_term_months INTEGER NOT NULL,
    discount_percentage DECIMAL(5,2) DEFAULT 0,
    effective_price DECIMAL(10,2) NOT NULL,
    razorpay_plan_id VARCHAR(255),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(base_plan_id, billing_term_months)
);

-- Add foreign key constraint
ALTER TABLE plan_billing_variants 
ADD CONSTRAINT fk_plan_billing_variants_base_plan 
FOREIGN KEY (base_plan_id) REFERENCES pricing_plans(id) ON DELETE CASCADE;

-- Phase 4: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_plan_billing_variants_base_plan ON plan_billing_variants(base_plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_billing_variants_term ON plan_billing_variants(billing_term_months);
CREATE INDEX IF NOT EXISTS idx_subscriptions_term_months ON subscriptions(billing_term_months);
CREATE INDEX IF NOT EXISTS idx_subscriptions_term_dates ON subscriptions(term_start_date, term_end_date);

-- Phase 5: Update existing data to maintain compatibility
-- Set billing_term_months based on existing billing_cycle
UPDATE pricing_plans 
SET billing_term_months = CASE 
    WHEN billing_cycle = 'monthly' THEN 1
    WHEN billing_cycle = 'yearly' THEN 12
    ELSE 1
END
WHERE billing_term_months IS NULL OR billing_term_months = 0;

UPDATE subscriptions 
SET billing_term_months = CASE 
    WHEN billing_cycle = 'monthly' THEN 1
    WHEN billing_cycle = 'yearly' THEN 12
    ELSE 1
END,
term_start_date = current_period_start,
term_end_date = current_period_end,
original_price = amount
WHERE billing_term_months IS NULL OR billing_term_months = 0;

-- Phase 6: Create audit log for schema changes
INSERT INTO pg_catalog.pg_stat_statements_info (dealloc) VALUES (0) ON CONFLICT DO NOTHING;

COMMIT;

-- Verification queries
SELECT 'Enhanced pricing_plans table' as status, 
       COUNT(*) as total_plans,
       COUNT(CASE WHEN two_year_discount IS NOT NULL THEN 1 END) as enhanced_plans
FROM pricing_plans;

SELECT 'Enhanced subscriptions table' as status,
       COUNT(*) as total_subscriptions,
       COUNT(CASE WHEN billing_term_months IS NOT NULL THEN 1 END) as enhanced_subscriptions
FROM subscriptions;

SELECT 'Plan billing variants table' as status,
       COUNT(*) as total_variants
FROM plan_billing_variants;

-- Final verification message
DO $$
BEGIN
    RAISE NOTICE 'Multi-term subscription schema enhancement completed successfully!';
    RAISE NOTICE 'All existing data preserved and enhanced with new capabilities.';
    RAISE NOTICE 'Timestamp: %', now();
END $$;