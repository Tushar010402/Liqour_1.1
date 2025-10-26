-- Add stock tracking fields to OCR extracted items table
ALTER TABLE ocr_extracted_items
ADD COLUMN IF NOT EXISTS rate_per_unit DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS opening_stock INTEGER,
ADD COLUMN IF NOT EXISTS closing_stock INTEGER,
ADD COLUMN IF NOT EXISTS row_number INTEGER;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_ocr_extracted_items_row_number ON ocr_extracted_items(session_id, row_number);

-- Add comments for documentation
COMMENT ON COLUMN ocr_extracted_items.rate_per_unit IS 'Rate per unit/bottle extracted from the receipt';
COMMENT ON COLUMN ocr_extracted_items.opening_stock IS 'Opening stock quantity extracted from stock report';
COMMENT ON COLUMN ocr_extracted_items.closing_stock IS 'Closing stock quantity extracted from stock report';
COMMENT ON COLUMN ocr_extracted_items.row_number IS 'Row number in the original document for maintaining order';