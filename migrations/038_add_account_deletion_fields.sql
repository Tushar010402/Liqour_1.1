-- Migration: 038_add_account_deletion_fields.sql
-- Purpose: Add account deletion grace period fields for App Store Guideline 5.1.1(v) compliance
-- Date: 2025-11-30

-- Add deletion tracking columns to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_scheduled_for TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_reason TEXT;

-- Create index for efficient querying of accounts scheduled for deletion
-- Partial index only includes users with pending deletion
CREATE INDEX IF NOT EXISTS idx_users_deletion_scheduled
    ON users(deletion_scheduled_for)
    WHERE deletion_scheduled_for IS NOT NULL AND deleted_at IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN users.deletion_requested_at IS 'Timestamp when user requested account deletion';
COMMENT ON COLUMN users.deletion_scheduled_for IS 'Timestamp when account will be permanently deleted (30 days after request)';
COMMENT ON COLUMN users.deletion_reason IS 'Optional reason provided by user for account deletion';
