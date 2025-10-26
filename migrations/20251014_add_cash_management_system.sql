-- ══════════════════════════════════════════════════════════════════════════════
-- Hierarchical Cash Management System - Database Migration
-- Created: 2025-10-14
-- Purpose: Enable complete cash accountability with denomination tracking
-- ══════════════════════════════════════════════════════════════════════════════

-- Enable UUID extension for uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 1. CashHolding Table - Real-time Cash Balance Tracking
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS cash_holdings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    current_balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    last_updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Ensure one cash holding per user per shop
    CONSTRAINT uq_cash_holding_user_shop UNIQUE(tenant_id, user_id, shop_id)
);

CREATE INDEX idx_cash_holdings_user ON cash_holdings(user_id);
CREATE INDEX idx_cash_holdings_shop ON cash_holdings(shop_id);
CREATE INDEX idx_cash_holdings_tenant ON cash_holdings(tenant_id);

COMMENT ON TABLE cash_holdings IS 'Real-time cash balance for each user at each shop';
COMMENT ON COLUMN cash_holdings.current_balance IS 'Current cash amount in hand';
COMMENT ON COLUMN cash_holdings.last_updated_at IS 'Last transaction timestamp';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 2. CashCollection Table - Hierarchical Cash Collections
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS cash_collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    amount DECIMAL(12,2) NOT NULL,
    collection_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'approved',
    approved_at TIMESTAMP,
    approved_by_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_by_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_cash_collection_amount CHECK (amount > 0),
    CONSTRAINT chk_cash_collection_status CHECK (status IN ('pending', 'approved', 'rejected'))
);

CREATE INDEX idx_cash_collections_from_user ON cash_collections(from_user_id);
CREATE INDEX idx_cash_collections_to_user ON cash_collections(to_user_id);
CREATE INDEX idx_cash_collections_shop ON cash_collections(shop_id);
CREATE INDEX idx_cash_collections_date ON cash_collections(collection_date DESC);
CREATE INDEX idx_cash_collections_status ON cash_collections(status);
CREATE INDEX idx_cash_collections_tenant ON cash_collections(tenant_id);

COMMENT ON TABLE cash_collections IS 'Cash collections between users in organizational hierarchy';
COMMENT ON COLUMN cash_collections.from_user_id IS 'User giving cash (subordinate)';
COMMENT ON COLUMN cash_collections.to_user_id IS 'User receiving cash (superior)';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 3. CashSubmission Table - Bank Deposits with Denomination Breakdown
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS cash_submissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    total_amount DECIMAL(12,2) NOT NULL,

    -- Denomination breakdown
    notes_500 INTEGER NOT NULL DEFAULT 0,
    notes_200 INTEGER NOT NULL DEFAULT 0,
    notes_100 INTEGER NOT NULL DEFAULT 0,
    notes_50 INTEGER NOT NULL DEFAULT 0,
    notes_20 INTEGER NOT NULL DEFAULT 0,
    notes_10 INTEGER NOT NULL DEFAULT 0,

    -- Bank deposit details
    bank_account_id UUID REFERENCES bank_accounts(id) ON DELETE SET NULL,
    bank_slip_number VARCHAR(100),
    deposit_date TIMESTAMP NOT NULL,
    receipt_photo_url TEXT NOT NULL,
    notes TEXT,

    -- Approval workflow
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    approved_at TIMESTAMP,
    approved_by_id UUID REFERENCES users(id) ON DELETE SET NULL,
    rejection_reason TEXT,

    created_by_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_cash_submission_amount CHECK (total_amount > 0),
    CONSTRAINT chk_cash_submission_status CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT chk_cash_submission_denominations CHECK (
        (notes_500 * 500 + notes_200 * 200 + notes_100 * 100 +
         notes_50 * 50 + notes_20 * 20 + notes_10 * 10) = total_amount
    )
);

CREATE INDEX idx_cash_submissions_user ON cash_submissions(user_id);
CREATE INDEX idx_cash_submissions_shop ON cash_submissions(shop_id);
CREATE INDEX idx_cash_submissions_date ON cash_submissions(deposit_date DESC);
CREATE INDEX idx_cash_submissions_status ON cash_submissions(status);
CREATE INDEX idx_cash_submissions_tenant ON cash_submissions(tenant_id);

COMMENT ON TABLE cash_submissions IS 'Cash submissions to bank with denomination tracking and photo evidence';
COMMENT ON COLUMN cash_submissions.notes_500 IS 'Count of ₹500 notes';
COMMENT ON COLUMN cash_submissions.notes_200 IS 'Count of ₹200 notes';
COMMENT ON COLUMN cash_submissions.notes_100 IS 'Count of ₹100 notes';
COMMENT ON COLUMN cash_submissions.notes_50 IS 'Count of ₹50 notes';
COMMENT ON COLUMN cash_submissions.notes_20 IS 'Count of ₹20 notes';
COMMENT ON COLUMN cash_submissions.notes_10 IS 'Count of ₹10 notes';
COMMENT ON CONSTRAINT chk_cash_submission_denominations ON cash_submissions IS 'Ensures denomination total matches declared amount';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 4. CashTransaction Table - Complete Audit Trail
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS cash_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    transaction_type VARCHAR(50) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    previous_balance DECIMAL(12,2) NOT NULL,
    new_balance DECIMAL(12,2) NOT NULL,
    related_entity_type VARCHAR(50),
    related_entity_id UUID,
    description TEXT NOT NULL,
    transaction_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_cash_transaction_type CHECK (
        transaction_type IN ('sale', 'collection_received', 'collection_given', 'submission', 'adjustment')
    )
);

CREATE INDEX idx_cash_transactions_user ON cash_transactions(user_id);
CREATE INDEX idx_cash_transactions_shop ON cash_transactions(shop_id);
CREATE INDEX idx_cash_transactions_date ON cash_transactions(transaction_date DESC);
CREATE INDEX idx_cash_transactions_type ON cash_transactions(transaction_type);
CREATE INDEX idx_cash_transactions_tenant ON cash_transactions(tenant_id);
CREATE INDEX idx_cash_transactions_related ON cash_transactions(related_entity_type, related_entity_id);

COMMENT ON TABLE cash_transactions IS 'Complete audit trail for all cash movements';
COMMENT ON COLUMN cash_transactions.transaction_type IS 'Type: sale, collection_received, collection_given, submission, adjustment';
COMMENT ON COLUMN cash_transactions.previous_balance IS 'Balance before transaction';
COMMENT ON COLUMN cash_transactions.new_balance IS 'Balance after transaction';
COMMENT ON COLUMN cash_transactions.related_entity_type IS 'Type of related record (sale, collection, submission)';
COMMENT ON COLUMN cash_transactions.related_entity_id IS 'ID of related record';

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Helper Functions
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Function to update last_updated_at on cash_holdings
CREATE OR REPLACE FUNCTION update_cash_holding_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_cash_holding_timestamp
    BEFORE UPDATE ON cash_holdings
    FOR EACH ROW
    EXECUTE FUNCTION update_cash_holding_timestamp();

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Sample Data for Testing
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Note: Sample data should be added via application logic, not migration
-- This ensures proper tenant isolation and business logic validation

-- ══════════════════════════════════════════════════════════════════════════════
-- Migration Complete
-- ══════════════════════════════════════════════════════════════════════════════

COMMENT ON SCHEMA public IS 'Cash Management System migration applied successfully - 2025-10-14';
