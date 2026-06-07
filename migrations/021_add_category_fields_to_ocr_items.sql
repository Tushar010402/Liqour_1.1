-- Add category and subcategory detection fields to OCR extracted items table
-- This enables smart stock organization and better brand matching

ALTER TABLE ocr_extracted_items
ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES brand_categories(id),
ADD COLUMN IF NOT EXISTS subcategory_id UUID REFERENCES brand_subcategories(id),
ADD COLUMN IF NOT EXISTS detected_category VARCHAR(50),
ADD COLUMN IF NOT EXISTS detected_subcategory VARCHAR(50);

-- Add indexes for better performance on category-based queries
CREATE INDEX IF NOT EXISTS idx_ocr_extracted_items_category_id ON ocr_extracted_items(category_id);
CREATE INDEX IF NOT EXISTS idx_ocr_extracted_items_subcategory_id ON ocr_extracted_items(subcategory_id);
CREATE INDEX IF NOT EXISTS idx_ocr_extracted_items_detected_category ON ocr_extracted_items(detected_category);

-- Add comments for documentation
COMMENT ON COLUMN ocr_extracted_items.category_id IS 'Mapped SaaS category ID (Whiskey, Vodka, Rum, Beer, Gin)';
COMMENT ON COLUMN ocr_extracted_items.subcategory_id IS 'Mapped SaaS subcategory ID (Premium, Normal, etc.)';
COMMENT ON COLUMN ocr_extracted_items.detected_category IS 'Category name detected by Gemini AI (raw string)';
COMMENT ON COLUMN ocr_extracted_items.detected_subcategory IS 'Subcategory detected by Gemini AI (raw string)';
