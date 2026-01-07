-- Create Notification Devices Table
-- Date: 2025-12-16
-- Description: Store FCM tokens for push notifications per device

BEGIN;

-- ========================================
-- notification_devices: Store FCM tokens per device
-- ========================================
CREATE TABLE IF NOT EXISTS notification_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- FCM Token
    fcm_token TEXT NOT NULL,

    -- Device Information
    device_id TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    device_name TEXT,
    app_version TEXT,

    -- Status
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT uq_notification_device_user_device UNIQUE(user_id, device_id),
    CONSTRAINT uq_notification_device_fcm_token UNIQUE(fcm_token)
);

-- Indexes for notification_devices
CREATE INDEX IF NOT EXISTS idx_notification_devices_user ON notification_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_devices_tenant ON notification_devices(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notification_devices_token ON notification_devices(fcm_token);
CREATE INDEX IF NOT EXISTS idx_notification_devices_active ON notification_devices(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_notification_devices_user_active ON notification_devices(user_id, is_active) WHERE is_active = true;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_notification_devices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for auto-updating updated_at
DROP TRIGGER IF EXISTS trg_notification_devices_updated_at ON notification_devices;
CREATE TRIGGER trg_notification_devices_updated_at
    BEFORE UPDATE ON notification_devices
    FOR EACH ROW
    EXECUTE FUNCTION update_notification_devices_updated_at();

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== NOTIFICATION DEVICES TABLE CREATED ===' as info;

SELECT
    'notification_devices' as table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'notification_devices') as column_count;

-- Show indexes
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'notification_devices'
ORDER BY indexname;
