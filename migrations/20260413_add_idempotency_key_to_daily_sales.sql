-- Add idempotency key to daily_sales_records to prevent duplicate submissions
-- from network retries or double-taps

ALTER TABLE daily_sales_records
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(255);

-- Partial unique index: only enforce uniqueness on non-null, non-deleted rows
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sales_idempotency_key
    ON daily_sales_records (idempotency_key)
    WHERE idempotency_key IS NOT NULL AND deleted_at IS NULL;
