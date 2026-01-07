-- Migration 030: Create Executive Finance table
-- Purpose: Track cash handovers from salesmen to executives AND expense claim approvals

CREATE TABLE IF NOT EXISTS executive_finances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    shop_id UUID NOT NULL REFERENCES shops(id),

    -- Transaction type
    transaction_type VARCHAR(20) NOT NULL, -- 'cash_handover' or 'expense_claim'

    -- Parties involved
    from_user_id UUID NOT NULL REFERENCES users(id), -- salesman
    to_user_id UUID NOT NULL REFERENCES users(id),   -- executive

    -- Amount details
    amount DECIMAL(15,2) NOT NULL,
    description TEXT,
    notes TEXT,

    -- For expense claims
    expense_category_id UUID REFERENCES expense_categories(id),
    receipt_url TEXT,

    -- Approval workflow
    status VARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected
    submitted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES users(id),
    rejection_reason TEXT,

    -- Audit
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_executive_finances_tenant ON executive_finances(tenant_id);
CREATE INDEX IF NOT EXISTS idx_executive_finances_shop ON executive_finances(shop_id);
CREATE INDEX IF NOT EXISTS idx_executive_finances_status ON executive_finances(status);
CREATE INDEX IF NOT EXISTS idx_executive_finances_from_user ON executive_finances(from_user_id);
CREATE INDEX IF NOT EXISTS idx_executive_finances_to_user ON executive_finances(to_user_id);
CREATE INDEX IF NOT EXISTS idx_executive_finances_type ON executive_finances(transaction_type);
CREATE INDEX IF NOT EXISTS idx_executive_finances_created ON executive_finances(created_at DESC);

-- Add comment for documentation
COMMENT ON TABLE executive_finances IS 'Tracks cash handovers from salesmen to executives and expense claim approvals';
