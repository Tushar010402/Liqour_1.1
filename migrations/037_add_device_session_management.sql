-- Migration: 037_add_device_session_management.sql
-- Description: Add device tracking and session management for 2-device login limit
-- Date: 2024-11-30

-- Add device tracking columns to user_sessions table
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS device_id VARCHAR(255);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS device_name VARCHAR(255);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS device_type VARCHAR(50);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS os_name VARCHAR(100);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS os_version VARCHAR(50);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS app_version VARCHAR(50);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMP;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS login_location VARCHAR(255);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS is_current BOOLEAN DEFAULT false;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS refresh_token VARCHAR(500);
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS token_hash VARCHAR(255);

-- Add comments for clarity
COMMENT ON COLUMN user_sessions.device_id IS 'Unique device identifier from client';
COMMENT ON COLUMN user_sessions.device_name IS 'Human readable device name (e.g., Samsung Galaxy S23)';
COMMENT ON COLUMN user_sessions.device_type IS 'Device type: mobile, web, tablet';
COMMENT ON COLUMN user_sessions.os_name IS 'Operating system name: Android, iOS, Web';
COMMENT ON COLUMN user_sessions.os_version IS 'Operating system version';
COMMENT ON COLUMN user_sessions.app_version IS 'Application version';
COMMENT ON COLUMN user_sessions.last_active_at IS 'Last activity timestamp for session';
COMMENT ON COLUMN user_sessions.login_location IS 'Approximate login location from IP';
COMMENT ON COLUMN user_sessions.is_current IS 'True for the most recently used session';
COMMENT ON COLUMN user_sessions.refresh_token IS 'Hashed refresh token for this session';
COMMENT ON COLUMN user_sessions.token_hash IS 'SHA256 hash of the JWT token for validation';

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_active
ON user_sessions(user_id, is_active)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_sessions_device
ON user_sessions(device_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash
ON user_sessions(token_hash)
WHERE deleted_at IS NULL AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_user_sessions_last_active
ON user_sessions(user_id, last_active_at DESC)
WHERE deleted_at IS NULL AND is_active = true;

-- Deactivate any existing orphaned sessions (cleanup)
UPDATE user_sessions
SET is_active = false,
    deleted_at = NOW()
WHERE expires_at IS NOT NULL
  AND expires_at < NOW()
  AND deleted_at IS NULL;

-- Log migration
DO $$
BEGIN
    RAISE NOTICE 'Migration 037: Device session management columns added successfully';
END $$;
