-- Migration: Add progress tracking fields to OCR tables
-- Purpose: Enable real-time progress updates for batch OCR processing
-- Date: 2025-11-05
-- Version: v1.0.27

-- ===========================================================================
-- 1. Add progress tracking fields to batch_ocr_sessions
-- ===========================================================================

ALTER TABLE batch_ocr_sessions
ADD COLUMN IF NOT EXISTS current_stage VARCHAR(50) DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS progress_percentage INT DEFAULT 0;

-- Create index for efficient querying by stage
CREATE INDEX IF NOT EXISTS idx_batch_ocr_sessions_current_stage
ON batch_ocr_sessions(current_stage);

-- Add check constraint for valid progress percentage (drop first if exists)
DO $$
BEGIN
    ALTER TABLE batch_ocr_sessions DROP CONSTRAINT IF EXISTS valid_progress_percentage;
    ALTER TABLE batch_ocr_sessions ADD CONSTRAINT valid_progress_percentage
    CHECK (progress_percentage >= 0 AND progress_percentage <= 100);
END $$;

-- Add check constraint for valid stage values (drop first if exists)
DO $$
BEGIN
    ALTER TABLE batch_ocr_sessions DROP CONSTRAINT IF EXISTS valid_current_stage;
    ALTER TABLE batch_ocr_sessions ADD CONSTRAINT valid_current_stage
    CHECK (current_stage IN ('pending', 'vision_api', 'gemini_extraction', 'item_matching', 'completed', 'failed'));
END $$;

-- ===========================================================================
-- 2. Add progress tracking fields to ocr_sessions (individual sessions)
-- ===========================================================================

ALTER TABLE ocr_sessions
ADD COLUMN IF NOT EXISTS current_stage VARCHAR(50) DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS progress_percentage INT DEFAULT 0;

-- Create index for efficient querying by stage
CREATE INDEX IF NOT EXISTS idx_ocr_sessions_current_stage
ON ocr_sessions(current_stage);

-- Add check constraint for valid progress percentage (drop first if exists)
DO $$
BEGIN
    ALTER TABLE ocr_sessions DROP CONSTRAINT IF EXISTS valid_progress_percentage_ocr;
    ALTER TABLE ocr_sessions ADD CONSTRAINT valid_progress_percentage_ocr
    CHECK (progress_percentage >= 0 AND progress_percentage <= 100);
END $$;

-- Add check constraint for valid stage values (drop first if exists)
DO $$
BEGIN
    ALTER TABLE ocr_sessions DROP CONSTRAINT IF EXISTS valid_current_stage_ocr;
    ALTER TABLE ocr_sessions ADD CONSTRAINT valid_current_stage_ocr
    CHECK (current_stage IN ('pending', 'vision_api', 'gemini_extraction', 'item_matching', 'completed', 'failed'));
END $$;

-- ===========================================================================
-- 3. Update existing records to have consistent progress values
-- ===========================================================================

-- Set progress for pending sessions
UPDATE batch_ocr_sessions
SET current_stage = 'pending', progress_percentage = 0
WHERE status = 'pending' AND current_stage IS NULL;

-- Set progress for completed sessions
UPDATE batch_ocr_sessions
SET current_stage = 'completed', progress_percentage = 100
WHERE status IN ('completed', 'partial') AND current_stage IS NULL;

-- Set progress for failed sessions
UPDATE batch_ocr_sessions
SET current_stage = 'failed', progress_percentage = 0
WHERE status = 'failed' AND current_stage IS NULL;

-- Set progress for processing sessions (set to vision_api stage as default)
UPDATE batch_ocr_sessions
SET current_stage = 'vision_api', progress_percentage = 30
WHERE status = 'processing' AND current_stage IS NULL;

-- Do the same for individual OCR sessions
UPDATE ocr_sessions
SET current_stage = 'pending', progress_percentage = 0
WHERE status = 'pending' AND current_stage IS NULL;

UPDATE ocr_sessions
SET current_stage = 'completed', progress_percentage = 100
WHERE status = 'completed' AND current_stage IS NULL;

UPDATE ocr_sessions
SET current_stage = 'failed', progress_percentage = 0
WHERE status = 'failed' AND current_stage IS NULL;

UPDATE ocr_sessions
SET current_stage = 'vision_api', progress_percentage = 30
WHERE status = 'processing' AND current_stage IS NULL;

-- ===========================================================================
-- 4. Add comments for documentation
-- ===========================================================================

COMMENT ON COLUMN batch_ocr_sessions.current_stage IS
'Current processing stage: pending, vision_api, gemini_extraction, item_matching, completed, failed';

COMMENT ON COLUMN batch_ocr_sessions.progress_percentage IS
'Progress percentage (0-100): pending=0%, vision_api=30%, gemini_extraction=60%, item_matching=90%, completed=100%';

COMMENT ON COLUMN ocr_sessions.current_stage IS
'Current processing stage: pending, vision_api, gemini_extraction, item_matching, completed, failed';

COMMENT ON COLUMN ocr_sessions.progress_percentage IS
'Progress percentage (0-100): pending=0%, vision_api=30%, gemini_extraction=60%, item_matching=90%, completed=100%';

-- ===========================================================================
-- Migration complete
-- ===========================================================================
