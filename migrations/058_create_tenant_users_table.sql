-- Migration: 058_create_tenant_users_table.sql
-- Description: Creates tenant_users table for SaaS usage tracking
-- Date: 2026-02-04

-- Create tenant_users table if not exists
CREATE TABLE IF NOT EXISTS tenant_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    email VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant_id ON tenant_users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_deleted_at ON tenant_users(deleted_at);
CREATE INDEX IF NOT EXISTS idx_tenant_users_is_active ON tenant_users(is_active);

-- Populate from existing users table (only if empty)
INSERT INTO tenant_users (id, tenant_id, email, is_active, created_at, updated_at)
SELECT id, tenant_id, email, is_active, created_at, updated_at
FROM users
WHERE tenant_id IS NOT NULL
  AND deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM tenant_users LIMIT 1)
ON CONFLICT (id) DO NOTHING;

-- Add comment to table
COMMENT ON TABLE tenant_users IS 'Tracks users per tenant for SaaS usage tracking and billing';
