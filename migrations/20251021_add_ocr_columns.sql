-- Migration: Add missing columns to ocr_sessions
-- Date: 2025-10-21
-- Purpose: Add extracted_data and import_id columns for bulk import integration

-- Add extracted_data column if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_name = 'ocr_sessions' AND column_name = 'extracted_data') THEN
        ALTER TABLE ocr_sessions ADD COLUMN extracted_data JSONB;
        COMMENT ON COLUMN ocr_sessions.extracted_data IS 'JSON array of extracted products from the invoice';
    END IF;
END $$;

-- Add import_id column if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_name = 'ocr_sessions' AND column_name = 'import_id') THEN
        ALTER TABLE ocr_sessions ADD COLUMN import_id UUID REFERENCES import_history(id) ON DELETE SET NULL;
        COMMENT ON COLUMN ocr_sessions.import_id IS 'Reference to import_history if session was confirmed for import';
    END IF;
END $$;

-- Add index on import_id if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE tablename = 'ocr_sessions' AND indexname = 'idx_ocr_sessions_import_id') THEN
        CREATE INDEX idx_ocr_sessions_import_id ON ocr_sessions(import_id);
    END IF;
END $$;

-- Make shop_id nullable (it was NOT NULL before)
ALTER TABLE ocr_sessions ALTER COLUMN shop_id DROP NOT NULL;

-- Verification
SELECT
    'OCR sessions table updated successfully' as message,
    count(*) as total_sessions,
    count(extracted_data) as sessions_with_data,
    count(import_id) as sessions_imported
FROM ocr_sessions;
