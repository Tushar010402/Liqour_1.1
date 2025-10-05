-- Fix shops table by adding missing columns for LiquorPro

-- Add missing columns to shops table
ALTER TABLE shops ADD COLUMN IF NOT EXISTS license_number VARCHAR(255);
ALTER TABLE shops ADD COLUMN IF NOT EXISTS license_file VARCHAR(500);
ALTER TABLE shops ADD COLUMN IF NOT EXISTS latitude DECIMAL(10,8);
ALTER TABLE shops ADD COLUMN IF NOT EXISTS longitude DECIMAL(11,8);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_shops_license_number ON shops(license_number);
CREATE INDEX IF NOT EXISTS idx_shops_location ON shops(latitude, longitude);

-- Success message
SELECT 'Shops table fixed successfully!' as status;