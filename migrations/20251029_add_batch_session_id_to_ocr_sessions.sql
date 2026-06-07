-- Add batch_session_id column to ocr_sessions table
-- This allows linking individual OCR sessions to batch OCR sessions

-- Add the column
ALTER TABLE ocr_sessions
ADD COLUMN IF NOT EXISTS batch_session_id UUID;

-- Add foreign key constraint
ALTER TABLE ocr_sessions
ADD CONSTRAINT fk_ocr_sessions_batch_session
FOREIGN KEY (batch_session_id)
REFERENCES batch_ocr_sessions(id)
ON DELETE CASCADE;

-- Add index for efficient querying
CREATE INDEX IF NOT EXISTS idx_ocr_sessions_batch_session_id
ON ocr_sessions(batch_session_id);

-- Add comment
COMMENT ON COLUMN ocr_sessions.batch_session_id IS 'Links individual OCR session to a batch OCR session for multi-image processing';
