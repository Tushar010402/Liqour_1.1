-- Migration: Fix cash_requests table column names
-- Date: 2025-10-28
-- Description: Rename columns to match Go models

-- ============================================
-- Rename columns to match the Go model expectations
-- ============================================

-- 1. Rename from_user_id to requester_id
ALTER TABLE cash_requests
RENAME COLUMN from_user_id TO requester_id;

-- 2. Rename to_user_id to requested_from_id
ALTER TABLE cash_requests
RENAME COLUMN to_user_id TO requested_from_id;

-- 3. Update the index names to match
ALTER INDEX idx_cash_requests_from_user
RENAME TO idx_cash_requests_requester;

ALTER INDEX idx_cash_requests_to_user
RENAME TO idx_cash_requests_requested_from;

-- 4. Update the foreign key constraint names (optional but keeps naming consistent)
ALTER TABLE cash_requests
DROP CONSTRAINT IF EXISTS cash_requests_from_user_id_fkey;

ALTER TABLE cash_requests
DROP CONSTRAINT IF EXISTS cash_requests_to_user_id_fkey;

ALTER TABLE cash_requests
ADD CONSTRAINT cash_requests_requester_id_fkey
FOREIGN KEY (requester_id) REFERENCES users(id);

ALTER TABLE cash_requests
ADD CONSTRAINT cash_requests_requested_from_id_fkey
FOREIGN KEY (requested_from_id) REFERENCES users(id);

-- ============================================
-- Verify changes
-- ============================================
-- This will show the updated table structure
-- \d cash_requests