-- Migration: 055_app_logging_tables.sql
-- Description: Industrial-grade app logging system for Flutter app
-- Created: 2026-01-05
-- Author: Claude AI

-- ============================================================================
-- APP LOG SESSIONS TABLE
-- Tracks user sessions for grouping logs and analytics
-- ============================================================================
CREATE TABLE IF NOT EXISTS app_log_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    user_id UUID,
    device_id TEXT NOT NULL,
    device_model TEXT,
    os_version TEXT,
    app_version TEXT,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    log_count INT DEFAULT 0,
    error_count INT DEFAULT 0,
    warning_count INT DEFAULT 0,
    is_synced BOOLEAN DEFAULT FALSE,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for sessions
CREATE INDEX IF NOT EXISTS idx_app_log_sessions_tenant ON app_log_sessions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_app_log_sessions_user ON app_log_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_app_log_sessions_device ON app_log_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_app_log_sessions_started ON app_log_sessions(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_log_sessions_tenant_started ON app_log_sessions(tenant_id, started_at DESC);

-- ============================================================================
-- APP LOG ENTRIES TABLE
-- Individual log entries from the Flutter app
-- ============================================================================
CREATE TABLE IF NOT EXISTS app_log_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES app_log_sessions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL,
    client_log_id TEXT, -- ID from Flutter app for deduplication
    timestamp TIMESTAMPTZ NOT NULL,
    level TEXT NOT NULL, -- debug, info, warning, error, success
    tag TEXT NOT NULL,   -- API, Navigation, Error, UserAction, etc.
    message TEXT NOT NULL,
    stack_trace TEXT,
    metadata JSONB,
    screen_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_level CHECK (level IN ('debug', 'info', 'warning', 'error', 'success'))
);

-- Indexes for log entries
CREATE INDEX IF NOT EXISTS idx_app_log_entries_session ON app_log_entries(session_id);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_tenant ON app_log_entries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_timestamp ON app_log_entries(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_tenant_timestamp ON app_log_entries(tenant_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_level ON app_log_entries(level);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_tag ON app_log_entries(tag);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_level_timestamp ON app_log_entries(level, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_app_log_entries_client_log ON app_log_entries(client_log_id);

-- GIN index for JSONB metadata search
CREATE INDEX IF NOT EXISTS idx_app_log_entries_metadata ON app_log_entries USING GIN (metadata);

-- ============================================================================
-- APP NETWORK REQUESTS TABLE
-- Detailed API call logs for debugging and performance monitoring
-- ============================================================================
CREATE TABLE IF NOT EXISTS app_network_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    log_entry_id UUID REFERENCES app_log_entries(id) ON DELETE CASCADE,
    session_id UUID REFERENCES app_log_sessions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL,
    request_id TEXT, -- Correlation ID from app
    method TEXT NOT NULL, -- GET, POST, PUT, DELETE, etc.
    url TEXT NOT NULL,
    path TEXT, -- Just the path portion
    status_code INT,
    duration_ms INT,
    request_size INT,
    response_size INT,
    request_headers JSONB,
    response_headers JSONB,
    error_message TEXT,
    is_success BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for network requests
CREATE INDEX IF NOT EXISTS idx_app_network_requests_session ON app_network_requests(session_id);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_tenant ON app_network_requests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_log_entry ON app_network_requests(log_entry_id);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_created ON app_network_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_status ON app_network_requests(status_code);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_path ON app_network_requests(path);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_duration ON app_network_requests(duration_ms DESC);
CREATE INDEX IF NOT EXISTS idx_app_network_requests_errors ON app_network_requests(tenant_id, is_success) WHERE is_success = FALSE;

-- ============================================================================
-- APP LOG BATCHES TABLE
-- Track received log batches for deduplication and audit
-- ============================================================================
CREATE TABLE IF NOT EXISTS app_log_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id TEXT NOT NULL UNIQUE, -- ID from Flutter app
    session_id UUID REFERENCES app_log_sessions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL,
    log_count INT NOT NULL,
    received_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    status TEXT DEFAULT 'received', -- received, processed, failed
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for batches
CREATE INDEX IF NOT EXISTS idx_app_log_batches_batch ON app_log_batches(batch_id);
CREATE INDEX IF NOT EXISTS idx_app_log_batches_session ON app_log_batches(session_id);
CREATE INDEX IF NOT EXISTS idx_app_log_batches_tenant ON app_log_batches(tenant_id);
CREATE INDEX IF NOT EXISTS idx_app_log_batches_received ON app_log_batches(received_at DESC);

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================
COMMENT ON TABLE app_log_sessions IS 'User app sessions for grouping logs and analytics';
COMMENT ON TABLE app_log_entries IS 'Individual log entries from the Flutter app';
COMMENT ON TABLE app_network_requests IS 'Detailed API call logs for debugging';
COMMENT ON TABLE app_log_batches IS 'Log batch tracking for deduplication';

COMMENT ON COLUMN app_log_entries.level IS 'Log level: debug, info, warning, error, success';
COMMENT ON COLUMN app_log_entries.tag IS 'Log category: API, Navigation, Error, UserAction, etc.';
COMMENT ON COLUMN app_log_entries.client_log_id IS 'ID from Flutter app for deduplication';
COMMENT ON COLUMN app_network_requests.request_id IS 'Correlation ID to trace requests';

-- ============================================================================
-- DATA RETENTION: Function to cleanup old logs
-- ============================================================================
CREATE OR REPLACE FUNCTION cleanup_old_app_logs(retention_days INT DEFAULT 30)
RETURNS TABLE (
    deleted_sessions BIGINT,
    deleted_entries BIGINT,
    deleted_requests BIGINT,
    deleted_batches BIGINT
) AS $$
DECLARE
    cutoff_date TIMESTAMPTZ;
    v_deleted_entries BIGINT;
    v_deleted_requests BIGINT;
    v_deleted_batches BIGINT;
    v_deleted_sessions BIGINT;
BEGIN
    cutoff_date := NOW() - (retention_days || ' days')::INTERVAL;

    -- Delete network requests first (child table)
    DELETE FROM app_network_requests
    WHERE created_at < cutoff_date;
    GET DIAGNOSTICS v_deleted_requests = ROW_COUNT;

    -- Delete log entries (child table)
    DELETE FROM app_log_entries
    WHERE created_at < cutoff_date;
    GET DIAGNOSTICS v_deleted_entries = ROW_COUNT;

    -- Delete batches
    DELETE FROM app_log_batches
    WHERE created_at < cutoff_date;
    GET DIAGNOSTICS v_deleted_batches = ROW_COUNT;

    -- Delete sessions that have no logs and are old
    DELETE FROM app_log_sessions
    WHERE started_at < cutoff_date
    AND NOT EXISTS (
        SELECT 1 FROM app_log_entries e WHERE e.session_id = app_log_sessions.id
    );
    GET DIAGNOSTICS v_deleted_sessions = ROW_COUNT;

    RETURN QUERY SELECT v_deleted_sessions, v_deleted_entries, v_deleted_requests, v_deleted_batches;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_app_logs IS 'Cleanup logs older than retention_days (default 30)';

-- ============================================================================
-- VIEW: Log statistics per tenant per day
-- ============================================================================
CREATE OR REPLACE VIEW app_log_daily_stats AS
SELECT
    tenant_id,
    DATE(timestamp) as log_date,
    COUNT(*) as total_logs,
    COUNT(*) FILTER (WHERE level = 'error') as error_count,
    COUNT(*) FILTER (WHERE level = 'warning') as warning_count,
    COUNT(*) FILTER (WHERE level = 'info') as info_count,
    COUNT(*) FILTER (WHERE level = 'debug') as debug_count,
    COUNT(*) FILTER (WHERE level = 'success') as success_count,
    COUNT(DISTINCT session_id) as unique_sessions,
    COUNT(DISTINCT tag) as unique_tags,
    jsonb_object_agg(tag, tag_count) as logs_by_tag
FROM (
    SELECT
        tenant_id,
        timestamp,
        level,
        session_id,
        tag,
        COUNT(*) OVER (PARTITION BY tenant_id, DATE(timestamp), tag) as tag_count
    FROM app_log_entries
) sub
GROUP BY tenant_id, DATE(timestamp);

COMMENT ON VIEW app_log_daily_stats IS 'Daily log statistics per tenant';

-- ============================================================================
-- GRANT PERMISSIONS (if needed)
-- ============================================================================
-- GRANT SELECT, INSERT, UPDATE, DELETE ON app_log_sessions TO liquorpro_prod;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON app_log_entries TO liquorpro_prod;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON app_network_requests TO liquorpro_prod;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON app_log_batches TO liquorpro_prod;
