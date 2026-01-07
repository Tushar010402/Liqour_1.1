-- Migration: Fix Money Collections for Assistant Manager
-- Date: 2025-11-25
-- Description: Add rejection fields, tenant_settings table, and soft delete index

-- Add proper rejection fields to money_collections
ALTER TABLE money_collections ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE money_collections ADD COLUMN IF NOT EXISTS rejected_by_id UUID REFERENCES users(id);
ALTER TABLE money_collections ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Remove duplicate ApprovalDeadline (use DeadlineAt only)
-- Note: Check if column exists first to avoid error
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'money_collections'
               AND column_name = 'approval_deadline') THEN
        ALTER TABLE money_collections DROP COLUMN approval_deadline;
    END IF;
END $$;

-- Create tenant_settings table for configurable deadline
CREATE TABLE IF NOT EXISTS tenant_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) UNIQUE,
    money_collection_deadline_minutes INT DEFAULT 15,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tenant_settings_tenant ON tenant_settings(tenant_id);

-- Insert default settings for existing tenants
INSERT INTO tenant_settings (tenant_id, money_collection_deadline_minutes)
SELECT id, 15 FROM tenants
ON CONFLICT (tenant_id) DO NOTHING;

-- Add soft delete index for performance
CREATE INDEX IF NOT EXISTS idx_money_collections_deleted ON money_collections(deleted_at) WHERE deleted_at IS NULL;

-- Add index for status queries
CREATE INDEX IF NOT EXISTS idx_money_collections_status ON money_collections(status);

-- Add index for tenant + status queries
CREATE INDEX IF NOT EXISTS idx_money_collections_tenant_status ON money_collections(tenant_id, status);
