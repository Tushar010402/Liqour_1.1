-- Migration: Create Tenant Bank Account Management System
-- Description: Creates tables for managing tenant bank accounts, transactions, and reconciliation
-- Date: 2025-10-26

-- ============================================================================
-- Table: tenant_bank_accounts
-- Purpose: Store bank account details for each tenant with OD limit tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS tenant_bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,

    -- Bank Account Details
    bank_name VARCHAR(255) NOT NULL,
    account_number VARCHAR(50) NOT NULL,
    account_holder_name VARCHAR(255) NOT NULL,
    ifsc_code VARCHAR(20),
    branch_name VARCHAR(255),
    branch_address TEXT,

    -- Account Type and Status
    account_type VARCHAR(20) NOT NULL DEFAULT 'current' CHECK (account_type IN ('current', 'savings', 'od', 'cash_credit')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_default BOOLEAN NOT NULL DEFAULT false,

    -- Balance Tracking
    current_balance DECIMAL(15, 2) NOT NULL DEFAULT 0.00,

    -- Overdraft (OD) Management
    od_limit DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    used_od_amount DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    available_od DECIMAL(15, 2) GENERATED ALWAYS AS (od_limit - used_od_amount) STORED,

    -- Available Balance (includes OD)
    total_available_balance DECIMAL(15, 2) GENERATED ALWAYS AS (current_balance + (od_limit - used_od_amount)) STORED,

    -- Interest Rates (for OD accounts)
    od_interest_rate DECIMAL(5, 2) DEFAULT 0.00,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,

    -- Constraints
    CONSTRAINT fk_tenant_bank_accounts_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT unique_tenant_account_number UNIQUE (tenant_id, account_number),
    CONSTRAINT check_current_balance CHECK (current_balance >= -od_limit),
    CONSTRAINT check_od_amounts CHECK (used_od_amount >= 0 AND used_od_amount <= od_limit)
);

-- Indexes for performance
CREATE INDEX idx_tenant_bank_accounts_tenant_id ON tenant_bank_accounts(tenant_id);
CREATE INDEX idx_tenant_bank_accounts_active ON tenant_bank_accounts(tenant_id, is_active);
CREATE INDEX idx_tenant_bank_accounts_default ON tenant_bank_accounts(tenant_id, is_default);

-- ============================================================================
-- Table: bank_transactions
-- Purpose: Record all bank transactions for audit trail and reconciliation
-- ============================================================================

CREATE TABLE IF NOT EXISTS bank_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    bank_account_id UUID NOT NULL,

    -- Transaction Details
    transaction_type VARCHAR(50) NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal', 'od_usage', 'od_repayment', 'interest_charge', 'bank_charges', 'adjustment')),
    amount DECIMAL(15, 2) NOT NULL,

    -- Balance Snapshots
    balance_before DECIMAL(15, 2) NOT NULL,
    balance_after DECIMAL(15, 2) NOT NULL,
    od_used_before DECIMAL(15, 2) DEFAULT 0.00,
    od_used_after DECIMAL(15, 2) DEFAULT 0.00,

    -- Transaction References
    reference_type VARCHAR(50), -- 'cash_submission', 'manual_entry', 'bank_statement', etc.
    reference_id UUID, -- Links to cash_submissions.id, etc.
    bank_reference_number VARCHAR(100), -- Bank slip number, transaction ID

    -- Transaction Metadata
    transaction_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description TEXT,
    notes TEXT,

    -- Reconciliation
    is_reconciled BOOLEAN NOT NULL DEFAULT false,
    reconciliation_id UUID,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,

    -- Constraints
    CONSTRAINT fk_bank_transactions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_bank_transactions_account FOREIGN KEY (bank_account_id) REFERENCES tenant_bank_accounts(id) ON DELETE CASCADE,
    CONSTRAINT check_transaction_amount CHECK (amount != 0)
);

-- Indexes for performance
CREATE INDEX idx_bank_transactions_tenant ON bank_transactions(tenant_id);
CREATE INDEX idx_bank_transactions_account ON bank_transactions(bank_account_id);
CREATE INDEX idx_bank_transactions_date ON bank_transactions(transaction_date DESC);
CREATE INDEX idx_bank_transactions_reference ON bank_transactions(reference_type, reference_id);
CREATE INDEX idx_bank_transactions_reconciliation ON bank_transactions(is_reconciled);

-- ============================================================================
-- Table: bank_reconciliations
-- Purpose: Track reconciliation between system records and bank statements
-- ============================================================================

CREATE TABLE IF NOT EXISTS bank_reconciliations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    bank_account_id UUID NOT NULL,

    -- Reconciliation Period
    reconciliation_date DATE NOT NULL,
    statement_start_date DATE NOT NULL,
    statement_end_date DATE NOT NULL,

    -- Balances
    system_balance DECIMAL(15, 2) NOT NULL,
    bank_statement_balance DECIMAL(15, 2) NOT NULL,
    difference DECIMAL(15, 2) GENERATED ALWAYS AS (bank_statement_balance - system_balance) STORED,

    -- Status
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'discrepancy')),

    -- Reconciliation Details
    total_deposits DECIMAL(15, 2) DEFAULT 0.00,
    total_withdrawals DECIMAL(15, 2) DEFAULT 0.00,
    unreconciled_deposits DECIMAL(15, 2) DEFAULT 0.00,
    unreconciled_withdrawals DECIMAL(15, 2) DEFAULT 0.00,

    -- Notes and Resolution
    notes TEXT,
    resolution_notes TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_by UUID,
    completed_by UUID,

    -- Constraints
    CONSTRAINT fk_bank_reconciliations_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_bank_reconciliations_account FOREIGN KEY (bank_account_id) REFERENCES tenant_bank_accounts(id) ON DELETE CASCADE,
    CONSTRAINT unique_reconciliation_period UNIQUE (bank_account_id, reconciliation_date)
);

-- Indexes for performance
CREATE INDEX idx_bank_reconciliations_tenant ON bank_reconciliations(tenant_id);
CREATE INDEX idx_bank_reconciliations_account ON bank_reconciliations(bank_account_id);
CREATE INDEX idx_bank_reconciliations_date ON bank_reconciliations(reconciliation_date DESC);
CREATE INDEX idx_bank_reconciliations_status ON bank_reconciliations(status);

-- ============================================================================
-- Foreign Key: Link cash_submissions to bank accounts
-- ============================================================================

-- Check if cash_submissions table has bank_account_id column
-- If not, add it
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'cash_submissions'
        AND column_name = 'bank_account_id'
    ) THEN
        ALTER TABLE cash_submissions
        ADD COLUMN bank_account_id UUID REFERENCES tenant_bank_accounts(id) ON DELETE SET NULL;

        CREATE INDEX idx_cash_submissions_bank_account ON cash_submissions(bank_account_id);
    END IF;
END $$;

-- ============================================================================
-- Function: Update bank account balance
-- Purpose: Automatically update balance when transactions are inserted
-- ============================================================================

CREATE OR REPLACE FUNCTION update_bank_account_balance()
RETURNS TRIGGER AS $$
BEGIN
    -- Update current balance based on transaction type
    IF NEW.transaction_type IN ('deposit', 'od_repayment') THEN
        UPDATE tenant_bank_accounts
        SET current_balance = current_balance + NEW.amount,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.bank_account_id;
    ELSIF NEW.transaction_type IN ('withdrawal', 'bank_charges', 'interest_charge') THEN
        UPDATE tenant_bank_accounts
        SET current_balance = current_balance - NEW.amount,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.bank_account_id;
    ELSIF NEW.transaction_type = 'od_usage' THEN
        UPDATE tenant_bank_accounts
        SET used_od_amount = used_od_amount + NEW.amount,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.bank_account_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_update_bank_balance ON bank_transactions;
CREATE TRIGGER trigger_update_bank_balance
    AFTER INSERT ON bank_transactions
    FOR EACH ROW
    EXECUTE FUNCTION update_bank_account_balance();

-- ============================================================================
-- Function: Enforce single default bank account per tenant
-- ============================================================================

CREATE OR REPLACE FUNCTION enforce_single_default_bank_account()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        -- Set all other accounts for this tenant to non-default
        UPDATE tenant_bank_accounts
        SET is_default = false
        WHERE tenant_id = NEW.tenant_id
        AND id != NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_enforce_default_account ON tenant_bank_accounts;
CREATE TRIGGER trigger_enforce_default_account
    BEFORE INSERT OR UPDATE ON tenant_bank_accounts
    FOR EACH ROW
    EXECUTE FUNCTION enforce_single_default_bank_account();

-- ============================================================================
-- Comments for documentation
-- ============================================================================

COMMENT ON TABLE tenant_bank_accounts IS 'Stores bank account information for tenants with OD limit tracking';
COMMENT ON TABLE bank_transactions IS 'Records all bank transactions for audit trail and reconciliation';
COMMENT ON TABLE bank_reconciliations IS 'Tracks reconciliation between system and bank statements';

COMMENT ON COLUMN tenant_bank_accounts.od_limit IS 'Maximum overdraft limit sanctioned by bank';
COMMENT ON COLUMN tenant_bank_accounts.used_od_amount IS 'Currently used overdraft amount';
COMMENT ON COLUMN tenant_bank_accounts.available_od IS 'Available overdraft = od_limit - used_od_amount (computed)';
COMMENT ON COLUMN tenant_bank_accounts.total_available_balance IS 'Total available = current_balance + available_od (computed)';

-- ============================================================================
-- Grant permissions (adjust as per your security model)
-- ============================================================================

-- Grant access to application role if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'liquorpro') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_bank_accounts TO liquorpro;
        GRANT SELECT, INSERT, UPDATE, DELETE ON bank_transactions TO liquorpro;
        GRANT SELECT, INSERT, UPDATE, DELETE ON bank_reconciliations TO liquorpro;
    END IF;
END $$;
