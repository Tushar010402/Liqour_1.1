-- Migration: 036_create_user_sessions_table.sql
-- Description: Create user_sessions table for device tracking and session management
-- Date: 2024-11-30

-- Create user_sessions table
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,

    -- User reference
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Token management
    token VARCHAR(500),
    token_hash VARCHAR(255),
    refresh_token VARCHAR(500),

    -- Device identification
    device_id VARCHAR(255),
    device_name VARCHAR(255),
    device_type VARCHAR(50),

    -- Device environment
    os_name VARCHAR(100),
    os_version VARCHAR(50),
    app_version VARCHAR(50),

    -- Network/Location info
    ip_address VARCHAR(45),
    user_agent TEXT,
    login_location VARCHAR(255),

    -- Session timing
    last_active_at TIMESTAMP,
    expires_at TIMESTAMP,

    -- Session state
    is_active BOOLEAN DEFAULT true,
    is_current BOOLEAN DEFAULT false
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_active ON user_sessions(user_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_sessions_device ON user_sessions(device_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON user_sessions(token_hash) WHERE deleted_at IS NULL AND is_active = true;
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_active ON user_sessions(user_id, last_active_at DESC) WHERE deleted_at IS NULL AND is_active = true;

-- Add comments
COMMENT ON TABLE user_sessions IS 'Stores user device sessions for 2-device login limit management';
COMMENT ON COLUMN user_sessions.device_id IS 'Unique device identifier from client';
COMMENT ON COLUMN user_sessions.device_name IS 'Human readable device name (e.g., Samsung Galaxy S23)';
COMMENT ON COLUMN user_sessions.device_type IS 'Device type: mobile, web, tablet';
COMMENT ON COLUMN user_sessions.os_name IS 'Operating system name: Android, iOS, Web';
COMMENT ON COLUMN user_sessions.os_version IS 'Operating system version';
COMMENT ON COLUMN user_sessions.app_version IS 'Application version';
COMMENT ON COLUMN user_sessions.last_active_at IS 'Last activity timestamp for session';
COMMENT ON COLUMN user_sessions.login_location IS 'Approximate login location from IP';
COMMENT ON COLUMN user_sessions.is_current IS 'True for the most recently used session';
COMMENT ON COLUMN user_sessions.token_hash IS 'SHA256 hash of the JWT token for validation';

-- Log migration
DO $$
BEGIN
    RAISE NOTICE 'Migration 036: user_sessions table created successfully';
END $$;
