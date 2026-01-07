-- Migration: 054_daily_sales_drafts.sql
-- Description: Create daily_sales_drafts table for backend draft persistence
-- Date: 2025-12-25

-- ============================================================================
-- DAILY SALES DRAFTS TABLE
-- ============================================================================
-- Stores draft daily sales entries per user per shop per date
-- Replaces Hive local storage for cross-device consistency
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_sales_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    shop_id UUID NOT NULL,
    record_date DATE NOT NULL,

    -- Draft Data (JSONB for flexibility)
    -- Contains: salesman_id, totals, items[], expenses[], location, images, notes
    draft_data JSONB NOT NULL DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_auto_save_at TIMESTAMP WITH TIME ZONE,

    -- Metadata for debugging/analytics
    device_id VARCHAR(255),
    app_version VARCHAR(50),

    -- Unique constraint: One draft per user per shop per date
    CONSTRAINT unique_user_shop_date_draft
        UNIQUE (tenant_id, user_id, shop_id, record_date)
);

-- Comment on table
COMMENT ON TABLE daily_sales_drafts IS 'Stores draft daily sales entries per user per shop per date for backend persistence';

-- Comment on columns
COMMENT ON COLUMN daily_sales_drafts.draft_data IS 'JSONB containing draft data: salesman_id, totals, items[], expenses[], location, images, notes';
COMMENT ON COLUMN daily_sales_drafts.last_auto_save_at IS 'Timestamp of last auto-save from client';
COMMENT ON COLUMN daily_sales_drafts.device_id IS 'Client device identifier for debugging';
COMMENT ON COLUMN daily_sales_drafts.app_version IS 'Client app version for debugging';

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Primary lookup index: user's draft for specific shop and date
CREATE INDEX IF NOT EXISTS idx_drafts_user_shop_date
    ON daily_sales_drafts(tenant_id, user_id, shop_id, record_date);

-- Index for listing all drafts for a user (multi-shop scenarios)
CREATE INDEX IF NOT EXISTS idx_drafts_user
    ON daily_sales_drafts(tenant_id, user_id, updated_at DESC);

-- Index for cleanup jobs (old drafts)
CREATE INDEX IF NOT EXISTS idx_drafts_cleanup
    ON daily_sales_drafts(updated_at);

-- Index for shop-based queries
CREATE INDEX IF NOT EXISTS idx_drafts_shop
    ON daily_sales_drafts(tenant_id, shop_id);

-- ============================================================================
-- TRIGGER: Auto-update updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_daily_sales_drafts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_daily_sales_drafts_updated_at ON daily_sales_drafts;

CREATE TRIGGER trigger_daily_sales_drafts_updated_at
    BEFORE UPDATE ON daily_sales_drafts
    FOR EACH ROW
    EXECUTE FUNCTION update_daily_sales_drafts_updated_at();

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant permissions (adjust based on your database user)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON daily_sales_drafts TO liquorpro_app;
