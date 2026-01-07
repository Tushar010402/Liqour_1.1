-- Migration: Add category and subcategory fields to ocr_items table
-- Purpose: Store inferred category/subcategory during OCR extraction for display in review UI
-- Author: Claude Code
-- Date: 2025-11-13

-- Add category fields to ocr_items table
ALTER TABLE ocr_items
ADD COLUMN IF NOT EXISTS inferred_category_id UUID REFERENCES categories(id),
ADD COLUMN IF NOT EXISTS inferred_subcategory_id UUID REFERENCES subcategories(id),
ADD COLUMN IF NOT EXISTS inferred_category_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS inferred_subcategory_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS category_confidence DECIMAL(5,2) DEFAULT 0.00;

-- Add indexes for category lookups
CREATE INDEX IF NOT EXISTS idx_ocr_items_inferred_category
ON ocr_items(inferred_category_id);

CREATE INDEX IF NOT EXISTS idx_ocr_items_inferred_subcategory
ON ocr_items(inferred_subcategory_id);

-- Add comment
COMMENT ON COLUMN ocr_items.inferred_category_id IS 'Auto-inferred category based on brand name patterns (e.g., Whiskey, Rum, Vodka)';
COMMENT ON COLUMN ocr_items.inferred_subcategory_id IS 'Auto-inferred subcategory based on price range (e.g., Premium, Normal, Basic)';
COMMENT ON COLUMN ocr_items.inferred_category_name IS 'Category name stored for display without JOIN';
COMMENT ON COLUMN ocr_items.inferred_subcategory_name IS 'Subcategory name stored for display without JOIN';
COMMENT ON COLUMN ocr_items.category_confidence IS 'Confidence score (0-100) for category inference';
