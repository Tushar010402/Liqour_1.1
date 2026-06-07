-- Add display_name column to saas_brands for user-friendly brand names
-- name = technical/backend identifier (for AI matching, OCR, SKU generation)
-- display_name = user-facing name shown in UI (fallback to name if empty)

ALTER TABLE saas_brands ADD COLUMN IF NOT EXISTS display_name TEXT;

-- Backfill from description where it's meaningful (not empty, not same as name)
UPDATE saas_brands SET display_name = description
  WHERE description IS NOT NULL
    AND description != ''
    AND description != name
    AND display_name IS NULL;

-- Index for search performance
CREATE INDEX IF NOT EXISTS idx_saas_brands_display_name ON saas_brands(display_name) WHERE display_name IS NOT NULL;
