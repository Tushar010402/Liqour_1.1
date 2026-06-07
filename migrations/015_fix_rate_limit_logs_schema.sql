-- Migration: Fix rate_limit_logs table schema
-- Description: Add missing columns to rate_limit_logs table and rename request_count to attempt_count
-- Date: 2025-10-27

BEGIN;

-- Add missing columns to rate_limit_logs table
ALTER TABLE rate_limit_logs
ADD COLUMN IF NOT EXISTS request_ip VARCHAR(255) DEFAULT '',
ADD COLUMN IF NOT EXISTS user_agent TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS tenant_id UUID,
ADD COLUMN IF NOT EXISTS request_path VARCHAR(255) DEFAULT '',
ADD COLUMN IF NOT EXISTS request_method VARCHAR(10) DEFAULT '',
ADD COLUMN IF NOT EXISTS response_code INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS user_id UUID;

-- Rename request_count to attempt_count
ALTER TABLE rate_limit_logs
RENAME COLUMN request_count TO attempt_count;

-- Add foreign key constraints for tenant_id and user_id
ALTER TABLE rate_limit_logs
ADD CONSTRAINT fk_rate_limit_logs_tenant
FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL;

ALTER TABLE rate_limit_logs
ADD CONSTRAINT fk_rate_limit_logs_user
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Add index for tenant_id if not exists
CREATE INDEX IF NOT EXISTS idx_rate_limit_logs_tenant_id ON rate_limit_logs(tenant_id);

-- Add index for user_id if not exists
CREATE INDEX IF NOT EXISTS idx_rate_limit_logs_user_id ON rate_limit_logs(user_id);

COMMIT;
