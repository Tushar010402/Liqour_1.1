-- Migration 031a: Create Cash Deposits table
-- Purpose: Track cash deposits from shops to bank accounts

CREATE TABLE IF NOT EXISTS cash_deposits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    bank_account_id UUID NOT NULL REFERENCES bank_accounts(id),
    shop_id UUID NOT NULL REFERENCES shops(id),

    -- Deposit details
    amount DECIMAL(15,2) NOT NULL,
    deposit_date DATE NOT NULL,
    slip_number VARCHAR(50),
    notes TEXT,

    -- Status and approval
    status VARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by_id UUID REFERENCES users(id),
    rejection_reason TEXT,

    -- Audit
    created_by_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cash_deposits_tenant ON cash_deposits(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_deposits_bank_account ON cash_deposits(bank_account_id);
CREATE INDEX IF NOT EXISTS idx_cash_deposits_shop ON cash_deposits(shop_id);
CREATE INDEX IF NOT EXISTS idx_cash_deposits_date ON cash_deposits(deposit_date);
CREATE INDEX IF NOT EXISTS idx_cash_deposits_status ON cash_deposits(status);

-- Comment
COMMENT ON TABLE cash_deposits IS 'Cash deposit records from shops to bank accounts';
