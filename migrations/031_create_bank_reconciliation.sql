-- Migration 031: Create Bank Reconciliation tables
-- Purpose: Support bank statement import and reconciliation

-- Bank Reconciliation table
CREATE TABLE IF NOT EXISTS bank_reconciliations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    bank_account_id UUID NOT NULL REFERENCES bank_accounts(id),

    -- Reconciliation period
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    -- Balances
    statement_opening_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
    statement_closing_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
    book_opening_balance DECIMAL(15,2) NOT NULL DEFAULT 0,
    book_closing_balance DECIMAL(15,2) NOT NULL DEFAULT 0,

    -- Reconciliation status
    status VARCHAR(20) DEFAULT 'draft', -- draft, in_progress, completed, approved
    difference DECIMAL(15,2) DEFAULT 0,
    is_balanced BOOLEAN DEFAULT false,

    -- Approval workflow
    reconciled_by_id UUID REFERENCES users(id),
    reconciled_at TIMESTAMP WITH TIME ZONE,
    approved_by_id UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,

    -- Audit
    created_by_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Bank Statement Entry table
CREATE TABLE IF NOT EXISTS bank_statement_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    bank_account_id UUID NOT NULL REFERENCES bank_accounts(id),
    reconciliation_id UUID REFERENCES bank_reconciliations(id),

    -- Statement details
    transaction_date DATE NOT NULL,
    value_date DATE,
    description TEXT,
    reference_number VARCHAR(100),
    transaction_type VARCHAR(10), -- credit, debit
    amount DECIMAL(15,2) NOT NULL,
    running_balance DECIMAL(15,2),

    -- Matching status
    is_matched BOOLEAN DEFAULT false,
    matched_transaction_id UUID REFERENCES bank_transactions(id),
    matched_deposit_id UUID REFERENCES cash_deposits(id),

    -- Import metadata
    imported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    source_file VARCHAR(255),
    row_number INT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_bank_reconciliations_tenant ON bank_reconciliations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_reconciliations_account ON bank_reconciliations(bank_account_id);
CREATE INDEX IF NOT EXISTS idx_bank_reconciliations_status ON bank_reconciliations(status);
CREATE INDEX IF NOT EXISTS idx_bank_reconciliations_period ON bank_reconciliations(period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_bank_statement_entries_tenant ON bank_statement_entries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_statement_entries_account ON bank_statement_entries(bank_account_id);
CREATE INDEX IF NOT EXISTS idx_bank_statement_entries_reconciliation ON bank_statement_entries(reconciliation_id);
CREATE INDEX IF NOT EXISTS idx_bank_statement_entries_date ON bank_statement_entries(transaction_date);
CREATE INDEX IF NOT EXISTS idx_bank_statement_entries_matched ON bank_statement_entries(is_matched);

-- Comments
COMMENT ON TABLE bank_reconciliations IS 'Bank statement reconciliation records';
COMMENT ON TABLE bank_statement_entries IS 'Imported bank statement entries for reconciliation';
