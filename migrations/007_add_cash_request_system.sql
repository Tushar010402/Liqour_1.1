-- Migration 007: Add Cash Request System
-- Date: 2025-01-16
-- Purpose: Add cash request feature for users to request cash from others with approval workflow

-- Create cash_requests table
CREATE TABLE IF NOT EXISTS cash_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,

    -- Request participants
    requester_id UUID NOT NULL,           -- Who is requesting cash
    requested_from_id UUID NOT NULL,      -- Who is being asked for cash
    shop_id UUID NOT NULL,

    -- Request details
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    reason TEXT,
    request_date TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Approval workflow (10-minute deadline like collections)
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    expires_at TIMESTAMP,                  -- 10-minute approval deadline
    approved_at TIMESTAMP,
    approved_by_id UUID,                   -- Who approved (usually requested_from_id)
    rejected_at TIMESTAMP,
    reject_reason TEXT,

    -- Audit timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by_id UUID NOT NULL,

    -- Foreign keys
    CONSTRAINT fk_cash_requests_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_cash_requests_requester FOREIGN KEY (requester_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_cash_requests_requested_from FOREIGN KEY (requested_from_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_cash_requests_shop FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
    CONSTRAINT fk_cash_requests_approved_by FOREIGN KEY (approved_by_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_cash_requests_created_by FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Prevent self-requests
    CONSTRAINT chk_no_self_request CHECK (requester_id != requested_from_id)
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_cash_requests_tenant ON cash_requests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_requests_requester ON cash_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_cash_requests_requested_from ON cash_requests(requested_from_id);
CREATE INDEX IF NOT EXISTS idx_cash_requests_shop ON cash_requests(shop_id);
CREATE INDEX IF NOT EXISTS idx_cash_requests_status ON cash_requests(status);
CREATE INDEX IF NOT EXISTS idx_cash_requests_expires_at ON cash_requests(expires_at);
CREATE INDEX IF NOT EXISTS idx_cash_requests_status_expires ON cash_requests(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_cash_requests_requested_from_status ON cash_requests(requested_from_id, status);
CREATE INDEX IF NOT EXISTS idx_cash_requests_requester_status ON cash_requests(requester_id, status);

-- Add comments for documentation
COMMENT ON TABLE cash_requests IS 'Cash request system - users can request cash advances from other users with approval workflow';
COMMENT ON COLUMN cash_requests.requester_id IS 'User requesting cash (who will receive the cash)';
COMMENT ON COLUMN cash_requests.requested_from_id IS 'User being asked to provide cash (who will give the cash)';
COMMENT ON COLUMN cash_requests.reason IS 'Reason for requesting cash (e.g., salary advance, expense reimbursement)';
COMMENT ON COLUMN cash_requests.expires_at IS '10-minute deadline for approval of pending request';
COMMENT ON COLUMN cash_requests.status IS 'pending - awaiting approval, approved - cash transferred, rejected - request denied, expired - deadline passed';

-- Verify migration
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_name = 'cash_requests'
        AND table_schema = 'public'
    ) THEN
        RAISE EXCEPTION 'Migration failed: cash_requests table not created';
    END IF;

    RAISE NOTICE 'Migration 007 completed successfully - Cash Request System added';
END $$;
