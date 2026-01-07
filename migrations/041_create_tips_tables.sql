-- Create Tips Management Tables
-- Date: 2025-12-01
-- Description: Hybrid tips system - individual tips, pooled tips, distributions, and payouts

BEGIN;

-- ========================================
-- 1. tip_pools: Daily pooled tips collection
-- ========================================
CREATE TABLE IF NOT EXISTS tip_pools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Pool Identification
    pool_date DATE NOT NULL,
    shift VARCHAR(20), -- morning, evening, night, full_day (NULL = all shifts)

    -- Amount
    total_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',

    -- Distribution Configuration
    distribution_method VARCHAR(30) NOT NULL DEFAULT 'equal',
    -- 'equal' - Split equally among all staff
    -- 'hours_worked' - Proportional to hours worked
    -- 'sales_proportional' - Proportional to sales made
    -- 'custom' - Custom weights set manually

    -- Participating Staff (for reference)
    participating_staff_ids UUID[], -- Array of user IDs
    participating_staff_count INTEGER DEFAULT 0,

    -- Status Workflow
    status VARCHAR(20) DEFAULT 'pending',
    -- 'pending' - Created but not distributed
    -- 'distributed' - Amounts calculated and assigned
    -- 'paid' - All staff have been paid
    -- 'cancelled' - Pool cancelled

    -- Notes
    notes TEXT,

    -- Distribution Tracking
    distributed_at TIMESTAMP WITH TIME ZONE,
    distributed_by UUID REFERENCES users(id),

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT uq_tip_pool UNIQUE(shop_id, pool_date, shift)
);

-- Indexes for tip_pools
CREATE INDEX IF NOT EXISTS idx_tip_pools_tenant ON tip_pools(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tip_pools_shop ON tip_pools(shop_id);
CREATE INDEX IF NOT EXISTS idx_tip_pools_date ON tip_pools(pool_date DESC);
CREATE INDEX IF NOT EXISTS idx_tip_pools_status ON tip_pools(status);
CREATE INDEX IF NOT EXISTS idx_tip_pools_shop_date ON tip_pools(shop_id, pool_date DESC);

-- ========================================
-- 2. tip_transactions: Individual and pooled tip records
-- ========================================
CREATE TABLE IF NOT EXISTS tip_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,

    -- Sale Reference (for individual tips)
    sale_id UUID REFERENCES sales(id) ON DELETE SET NULL,
    daily_sales_record_id UUID REFERENCES daily_sales_records(id) ON DELETE SET NULL,

    -- Recipient
    salesman_id UUID NOT NULL REFERENCES users(id),

    -- Tip Type
    tip_type VARCHAR(20) NOT NULL, -- 'individual', 'pooled'

    -- Amount
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',

    -- Payment Method (for individual tips)
    payment_method VARCHAR(20), -- cash, card, upi

    -- Pool Reference (for pooled tips)
    tip_pool_id UUID REFERENCES tip_pools(id) ON DELETE SET NULL,

    -- Payout Tracking
    payout_status VARCHAR(20) DEFAULT 'pending',
    -- 'pending' - Tip recorded but not paid
    -- 'scheduled' - Included in a payout batch
    -- 'paid' - Paid to staff
    -- 'cancelled' - Cancelled

    payout_date DATE,
    payout_reference VARCHAR(100), -- Transaction reference for payment
    payout_batch_id UUID, -- Will reference tip_payout_batches

    -- Recording Details
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    recorded_by UUID NOT NULL REFERENCES users(id),

    -- Notes
    notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for tip_transactions
CREATE INDEX IF NOT EXISTS idx_tip_transactions_tenant ON tip_transactions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tip_transactions_shop ON tip_transactions(shop_id);
CREATE INDEX IF NOT EXISTS idx_tip_transactions_salesman ON tip_transactions(salesman_id);
CREATE INDEX IF NOT EXISTS idx_tip_transactions_type ON tip_transactions(tip_type);
CREATE INDEX IF NOT EXISTS idx_tip_transactions_sale ON tip_transactions(sale_id) WHERE sale_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tip_transactions_pool ON tip_transactions(tip_pool_id) WHERE tip_pool_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tip_transactions_payout_status ON tip_transactions(payout_status);
CREATE INDEX IF NOT EXISTS idx_tip_transactions_recorded_at ON tip_transactions(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_tip_transactions_salesman_pending ON tip_transactions(salesman_id, payout_status) WHERE payout_status = 'pending';

-- ========================================
-- 3. tip_distributions: How pooled tips are distributed
-- ========================================
CREATE TABLE IF NOT EXISTS tip_distributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tip_pool_id UUID NOT NULL REFERENCES tip_pools(id) ON DELETE CASCADE,
    salesman_id UUID NOT NULL REFERENCES users(id),

    -- Distribution Factors
    hours_worked DECIMAL(5,2), -- Hours worked on that day
    sales_amount DECIMAL(12,2), -- Sales made by this salesman
    custom_weight DECIMAL(5,2) DEFAULT 1.0, -- Manual weight multiplier

    -- Calculated Distribution
    distribution_percentage DECIMAL(5,2) NOT NULL, -- Percentage of pool
    amount DECIMAL(10,2) NOT NULL, -- Actual amount

    -- Payout Tracking
    payout_status VARCHAR(20) DEFAULT 'pending',
    payout_date DATE,
    payout_reference VARCHAR(100),
    payout_batch_id UUID, -- Will reference tip_payout_batches

    -- Notes
    notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_tip_distribution UNIQUE(tip_pool_id, salesman_id)
);

-- Indexes for tip_distributions
CREATE INDEX IF NOT EXISTS idx_tip_distributions_pool ON tip_distributions(tip_pool_id);
CREATE INDEX IF NOT EXISTS idx_tip_distributions_salesman ON tip_distributions(salesman_id);
CREATE INDEX IF NOT EXISTS idx_tip_distributions_payout_status ON tip_distributions(payout_status);

-- ========================================
-- 4. tip_payout_batches: Batch payouts to staff
-- ========================================
CREATE TABLE IF NOT EXISTS tip_payout_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE SET NULL, -- NULL for tenant-wide payout

    -- Batch Identification
    batch_number VARCHAR(50) NOT NULL, -- e.g., 'TIP-2025-12-001'

    -- Period Covered
    payout_period_start DATE NOT NULL,
    payout_period_end DATE NOT NULL,

    -- Totals
    total_amount DECIMAL(12,2) NOT NULL,
    total_individual_tips DECIMAL(12,2) DEFAULT 0,
    total_pooled_tips DECIMAL(12,2) DEFAULT 0,
    staff_count INTEGER NOT NULL,
    transactions_count INTEGER DEFAULT 0,

    -- Status
    status VARCHAR(20) DEFAULT 'pending',
    -- 'pending' - Created but not processed
    -- 'processing' - Being processed
    -- 'completed' - All payments done
    -- 'partial' - Some payments failed
    -- 'failed' - Processing failed

    -- Payment Details
    payment_method VARCHAR(30), -- bank_transfer, cash, check, upi
    payment_reference VARCHAR(200),
    payment_notes TEXT,

    -- Processing
    processed_by UUID REFERENCES users(id),
    processed_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Approval (if required)
    requires_approval BOOLEAN DEFAULT FALSE,
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,

    -- Error Tracking
    failed_payments_count INTEGER DEFAULT 0,
    error_details JSONB, -- [{salesman_id, error, amount}]

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_tip_payout_batch UNIQUE(batch_number)
);

-- Indexes for tip_payout_batches
CREATE INDEX IF NOT EXISTS idx_tip_payout_batches_tenant ON tip_payout_batches(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tip_payout_batches_shop ON tip_payout_batches(shop_id);
CREATE INDEX IF NOT EXISTS idx_tip_payout_batches_status ON tip_payout_batches(status);
CREATE INDEX IF NOT EXISTS idx_tip_payout_batches_period ON tip_payout_batches(payout_period_start, payout_period_end);
CREATE INDEX IF NOT EXISTS idx_tip_payout_batches_created ON tip_payout_batches(created_at DESC);

-- ========================================
-- 5. Add foreign key for payout_batch_id after table creation
-- ========================================
ALTER TABLE tip_transactions
    ADD CONSTRAINT fk_tip_transactions_payout_batch
    FOREIGN KEY (payout_batch_id)
    REFERENCES tip_payout_batches(id)
    ON DELETE SET NULL;

ALTER TABLE tip_distributions
    ADD CONSTRAINT fk_tip_distributions_payout_batch
    FOREIGN KEY (payout_batch_id)
    REFERENCES tip_payout_batches(id)
    ON DELETE SET NULL;

-- ========================================
-- 6. tip_reports_cache: Pre-computed tip reports for performance
-- ========================================
CREATE TABLE IF NOT EXISTS tip_reports_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,

    -- Report Period
    report_type VARCHAR(20) NOT NULL, -- daily, weekly, monthly
    report_date DATE NOT NULL, -- Start date of period

    -- Salesman Breakdown (JSONB for flexibility)
    salesman_data JSONB NOT NULL,
    /* Structure:
    [
        {
            "salesman_id": "uuid",
            "salesman_name": "string",
            "individual_tips": 1500.00,
            "pooled_tips": 500.00,
            "total_tips": 2000.00,
            "sales_amount": 50000.00,
            "tip_to_sales_ratio": 4.00,
            "transactions_count": 25
        }
    ]
    */

    -- Totals
    total_individual_tips DECIMAL(12,2) DEFAULT 0,
    total_pooled_tips DECIMAL(12,2) DEFAULT 0,
    total_tips DECIMAL(12,2) DEFAULT 0,
    total_sales DECIMAL(15,2) DEFAULT 0,
    avg_tip_per_transaction DECIMAL(10,2) DEFAULT 0,
    tip_to_sales_ratio DECIMAL(8,4) DEFAULT 0,

    -- Computation
    computed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_tip_reports_cache UNIQUE(tenant_id, shop_id, report_type, report_date)
);

-- Indexes for tip_reports_cache
CREATE INDEX IF NOT EXISTS idx_tip_reports_cache_tenant ON tip_reports_cache(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tip_reports_cache_shop ON tip_reports_cache(shop_id);
CREATE INDEX IF NOT EXISTS idx_tip_reports_cache_type ON tip_reports_cache(report_type);
CREATE INDEX IF NOT EXISTS idx_tip_reports_cache_date ON tip_reports_cache(report_date DESC);

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== TIPS MANAGEMENT TABLES CREATED ===' as info;

SELECT
    'tip_pools' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'tip_pools') as column_count;

SELECT
    'tip_transactions' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'tip_transactions') as column_count;

SELECT
    'tip_distributions' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'tip_distributions') as column_count;

SELECT
    'tip_payout_batches' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'tip_payout_batches') as column_count;

SELECT
    'tip_reports_cache' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'tip_reports_cache') as column_count;
