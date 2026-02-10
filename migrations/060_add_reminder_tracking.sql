-- Migration 060: Add reminder tracking columns to prevent duplicate notifications
-- This fixes repeated FCM push notifications for overdue/pending items

-- Add reminder tracking to sales table
ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS last_reminder_level INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_reminder_sent_at TIMESTAMPTZ;

-- Add reminder tracking to daily_sales_records table
ALTER TABLE daily_sales_records
    ADD COLUMN IF NOT EXISTS last_reminder_level INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_reminder_sent_at TIMESTAMPTZ;

-- Index for efficient querying of pending sales that need reminders
CREATE INDEX IF NOT EXISTS idx_sales_pending_reminder
    ON sales (status, created_at, last_reminder_level)
    WHERE status = 'pending' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_daily_sales_pending_reminder
    ON daily_sales_records (status, created_at, last_reminder_level)
    WHERE status = 'pending' AND deleted_at IS NULL;

-- Add reminder dedup tracking table for the ReminderSchedulerService
-- This tracks which reminders have been sent to prevent re-sending within a time window
CREATE TABLE IF NOT EXISTS reminder_sent_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    reminder_type VARCHAR(100) NOT NULL,  -- e.g., 'credit_overdue', 'cash_collection', 'daily_sales'
    reminder_date DATE NOT NULL,          -- the date this reminder was sent
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_reminder_per_user_per_day UNIQUE (tenant_id, user_id, reminder_type, reminder_date)
);

CREATE INDEX IF NOT EXISTS idx_reminder_sent_log_lookup
    ON reminder_sent_log (tenant_id, user_id, reminder_type, reminder_date);
