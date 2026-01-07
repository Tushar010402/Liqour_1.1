-- Migration 034: Fix Cash Management System
-- Date: 2025-11-26
-- Purpose: Add requested_from_user_id, create cash_holdings & cash_transactions tables
-- This migration implements UPI-like cash request workflow where any user can request cash from any other user

BEGIN;

-- ============================================================================
-- 1. Add requested_from_user_id to money_collections
-- ============================================================================
ALTER TABLE money_collections
ADD COLUMN IF NOT EXISTS requested_from_user_id UUID REFERENCES users(id);

-- Migrate existing data: set requested_from_user_id = executive_id for backward compatibility
UPDATE money_collections
SET requested_from_user_id = executive_id
WHERE requested_from_user_id IS NULL;

-- Add index for filtering by target user (received requests)
CREATE INDEX IF NOT EXISTS idx_money_collections_requested_from
ON money_collections(requested_from_user_id);

-- Add composite index for "Received Requests" query
CREATE INDEX IF NOT EXISTS idx_money_collections_received
ON money_collections(requested_from_user_id, status, tenant_id)
WHERE deleted_at IS NULL;

-- Add composite index for "Sent Requests" query
CREATE INDEX IF NOT EXISTS idx_money_collections_sent
ON money_collections(created_by, status, tenant_id)
WHERE deleted_at IS NULL;

-- ============================================================================
-- 2. Create cash_holdings table (Ledger-style balance tracking)
-- ============================================================================
CREATE TABLE IF NOT EXISTS cash_holdings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    shop_id UUID REFERENCES shops(id),
    current_balance DECIMAL(15, 2) NOT NULL DEFAULT 0,
    last_transaction_id UUID,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_cash_holdings_user_tenant UNIQUE(user_id, tenant_id)
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_cash_holdings_tenant ON cash_holdings(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_holdings_user ON cash_holdings(user_id);
CREATE INDEX IF NOT EXISTS idx_cash_holdings_balance ON cash_holdings(current_balance DESC);

-- ============================================================================
-- 3. Create cash_transactions table (Audit Trail)
-- ============================================================================
CREATE TABLE IF NOT EXISTS cash_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    transaction_type VARCHAR(50) NOT NULL, -- collection_sent, collection_received, sale, expense, adjustment
    amount DECIMAL(15, 2) NOT NULL,
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('credit', 'debit')),
    previous_balance DECIMAL(15, 2) NOT NULL,
    new_balance DECIMAL(15, 2) NOT NULL,
    reference_type VARCHAR(50), -- money_collection, sale, expense, manual
    reference_id UUID,
    counterparty_user_id UUID REFERENCES users(id),
    description TEXT NOT NULL,
    notes TEXT,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for audit trail queries
CREATE INDEX IF NOT EXISTS idx_cash_transactions_user ON cash_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_cash_transactions_tenant ON cash_transactions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_transactions_created ON cash_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cash_transactions_reference ON cash_transactions(reference_type, reference_id);

-- ============================================================================
-- 4. Initialize cash_holdings from existing data
-- ============================================================================
-- Calculate initial balances from daily_sales_records minus approved money_collections
INSERT INTO cash_holdings (id, tenant_id, user_id, current_balance, last_updated_at, created_at, updated_at)
SELECT
    gen_random_uuid(),
    u.tenant_id,
    u.id as user_id,
    COALESCE(
        (SELECT COALESCE(SUM(dsr.total_cash_amount), 0)
         FROM daily_sales_records dsr
         WHERE (dsr.salesman_id = u.id OR dsr.created_by_id = u.id)
           AND dsr.tenant_id = u.tenant_id
           AND dsr.deleted_at IS NULL)
        -
        (SELECT COALESCE(SUM(mc.amount), 0)
         FROM money_collections mc
         WHERE mc.executive_id = u.id
           AND mc.tenant_id = u.tenant_id
           AND mc.status = 'approved'
           AND mc.deleted_at IS NULL),
        0
    ) as current_balance,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM users u
WHERE u.deleted_at IS NULL
  AND u.is_active = true
  AND u.tenant_id IS NOT NULL
  AND u.role IN ('salesman', 'executive', 'assistant_manager', 'manager', 'admin', 'owner')
ON CONFLICT (user_id, tenant_id) DO UPDATE
SET current_balance = EXCLUDED.current_balance,
    last_updated_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP;

COMMIT;
