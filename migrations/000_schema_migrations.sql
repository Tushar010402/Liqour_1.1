-- Migration Tracking System
-- This table tracks which migrations have been applied to prevent duplicate runs
-- Date: 2025-10-27

CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    version VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(500) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    checksum VARCHAR(64),
    execution_time_ms INTEGER,
    success BOOLEAN DEFAULT true,
    error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_schema_migrations_version ON schema_migrations(version);
CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied_at ON schema_migrations(applied_at DESC);
CREATE INDEX IF NOT EXISTS idx_schema_migrations_success ON schema_migrations(success);

COMMENT ON TABLE schema_migrations IS 'Tracks database migrations to ensure idempotent deployments';
COMMENT ON COLUMN schema_migrations.version IS 'Migration version number (e.g., 001, 002, 20251021)';
COMMENT ON COLUMN schema_migrations.name IS 'Human-readable migration name';
COMMENT ON COLUMN schema_migrations.checksum IS 'MD5 hash of migration file to detect changes';
COMMENT ON COLUMN schema_migrations.execution_time_ms IS 'Time taken to execute migration in milliseconds';

-- Insert initial record to mark migration system setup
INSERT INTO schema_migrations (version, name, execution_time_ms)
VALUES ('000', 'schema_migrations_table', 0)
ON CONFLICT (version) DO NOTHING;
