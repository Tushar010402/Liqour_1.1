-- Migration: Extend Finance Module for UP Excise Compliance
-- Date: 2025-01-15
-- Description: Add UP Excise-specific fields to existing finance tables

-- ============================================================
-- 1. EXTEND VENDORS TABLE (for CL-2 Godown tracking)
-- ============================================================

ALTER TABLE vendors
ADD COLUMN IF NOT EXISTS vendor_type VARCHAR(50) DEFAULT 'general',
ADD COLUMN IF NOT EXISTS cl2_license_number VARCHAR(50),
ADD COLUMN IF NOT EXISTS excise_district VARCHAR(100),
ADD COLUMN IF NOT EXISTS is_cl2_godown BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS warehouse_capacity INTEGER,
ADD COLUMN IF NOT EXISTS godown_address TEXT;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_vendors_cl2 ON vendors(is_cl2_godown) WHERE is_cl2_godown = true;
CREATE INDEX IF NOT EXISTS idx_vendors_license ON vendors(cl2_license_number) WHERE cl2_license_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vendors_type ON vendors(vendor_type);

-- Add unique constraint for CL-2 license numbers
ALTER TABLE vendors
ADD CONSTRAINT unique_cl2_license UNIQUE (cl2_license_number);

-- Add check constraint for vendor type
ALTER TABLE vendors
ADD CONSTRAINT check_vendor_type
CHECK (vendor_type IN ('general', 'cl2_godown', 'imfl_supplier', 'beer_supplier', 'wine_supplier'));

COMMENT ON COLUMN vendors.vendor_type IS 'Type of vendor: general, cl2_godown, imfl_supplier, etc.';
COMMENT ON COLUMN vendors.cl2_license_number IS 'CL-2 Godown license number from UP Excise Department';
COMMENT ON COLUMN vendors.excise_district IS 'Excise district where godown is registered';
COMMENT ON COLUMN vendors.is_cl2_godown IS 'True if this vendor is a CL-2 licensed godown/warehouse';

-- ============================================================
-- 2. EXTEND VENDOR_TRANSACTIONS TABLE (for Consideration Fees)
-- ============================================================

ALTER TABLE vendor_transactions
ADD COLUMN IF NOT EXISTS is_consideration_fee BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS security_codes JSONB,
ADD COLUMN IF NOT EXISTS stock_lift_id UUID,
ADD COLUMN IF NOT EXISTS excise_payment_proof TEXT,
ADD COLUMN IF NOT EXISTS bottles_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS fee_per_bottle DECIMAL(10,2);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_vendor_txn_consideration ON vendor_transactions(is_consideration_fee) WHERE is_consideration_fee = true;
CREATE INDEX IF NOT EXISTS idx_vendor_txn_stock_lift ON vendor_transactions(stock_lift_id) WHERE stock_lift_id IS NOT NULL;

-- Add check constraint for consideration fee
ALTER TABLE vendor_transactions
ADD CONSTRAINT check_consideration_fee
CHECK (
    (is_consideration_fee = false) OR
    (is_consideration_fee = true AND bottles_count > 0 AND fee_per_bottle > 0)
);

COMMENT ON COLUMN vendor_transactions.is_consideration_fee IS 'True if this transaction is a consideration fee payment to excise';
COMMENT ON COLUMN vendor_transactions.security_codes IS 'JSONB array of bottle security codes associated with this payment';
COMMENT ON COLUMN vendor_transactions.stock_lift_id IS 'Reference to stock lift transaction';
COMMENT ON COLUMN vendor_transactions.excise_payment_proof IS 'URL or file path to e-payment proof document';
COMMENT ON COLUMN vendor_transactions.bottles_count IS 'Number of bottles for which consideration fee is paid';
COMMENT ON COLUMN vendor_transactions.fee_per_bottle IS 'Consideration fee amount per bottle';

-- ============================================================
-- 3. EXTEND EXPENSES TABLE (for License Fee tracking)
-- ============================================================

ALTER TABLE expenses
ADD COLUMN IF NOT EXISTS excise_license_id UUID,
ADD COLUMN IF NOT EXISTS is_license_fee BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS license_fee_month DATE,
ADD COLUMN IF NOT EXISTS license_fee_year INTEGER;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_expenses_license ON expenses(excise_license_id) WHERE excise_license_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_license_fee ON expenses(is_license_fee) WHERE is_license_fee = true;
CREATE INDEX IF NOT EXISTS idx_expenses_fee_month ON expenses(license_fee_month) WHERE license_fee_month IS NOT NULL;

-- Add check constraint for license fee
ALTER TABLE expenses
ADD CONSTRAINT check_license_fee
CHECK (
    (is_license_fee = false) OR
    (is_license_fee = true AND excise_license_id IS NOT NULL AND license_fee_month IS NOT NULL)
);

COMMENT ON COLUMN expenses.excise_license_id IS 'Foreign key to excise_licenses table';
COMMENT ON COLUMN expenses.is_license_fee IS 'True if this expense is a monthly license fee payment';
COMMENT ON COLUMN expenses.license_fee_month IS 'Month for which license fee is being paid (YYYY-MM-01 format)';
COMMENT ON COLUMN expenses.license_fee_year IS 'Year of license fee payment for quick filtering';

-- ============================================================
-- 4. EXTEND CASH_DEPOSITS TABLE (for Daily Report linkage)
-- ============================================================

ALTER TABLE cash_deposits
ADD COLUMN IF NOT EXISTS excise_report_id UUID,
ADD COLUMN IF NOT EXISTS is_daily_sales_deposit BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS sales_date DATE;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_cash_deposits_report ON cash_deposits(excise_report_id) WHERE excise_report_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cash_deposits_daily ON cash_deposits(is_daily_sales_deposit) WHERE is_daily_sales_deposit = true;
CREATE INDEX IF NOT EXISTS idx_cash_deposits_sales_date ON cash_deposits(sales_date) WHERE sales_date IS NOT NULL;

COMMENT ON COLUMN cash_deposits.excise_report_id IS 'Foreign key to excise_daily_reports table';
COMMENT ON COLUMN cash_deposits.is_daily_sales_deposit IS 'True if this is a daily sales deposit linked to excise report';
COMMENT ON COLUMN cash_deposits.sales_date IS 'Date of sales for which this deposit is made';

-- ============================================================
-- 5. EXTEND MONEY_COLLECTIONS TABLE (for Daily Report linkage)
-- ============================================================

ALTER TABLE money_collections
ADD COLUMN IF NOT EXISTS excise_report_id UUID,
ADD COLUMN IF NOT EXISTS included_in_excise_report BOOLEAN DEFAULT false;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_money_collections_report ON money_collections(excise_report_id) WHERE excise_report_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_money_collections_excise ON money_collections(included_in_excise_report) WHERE included_in_excise_report = true;

COMMENT ON COLUMN money_collections.excise_report_id IS 'Foreign key to excise_daily_reports table';
COMMENT ON COLUMN money_collections.included_in_excise_report IS 'True if this collection is included in daily excise report';

-- ============================================================
-- 6. EXTEND PRODUCTS TABLE (for Security Code requirements)
-- ============================================================

ALTER TABLE products
ADD COLUMN IF NOT EXISTS security_code_required BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS bottle_type VARCHAR(20),
ADD COLUMN IF NOT EXISTS excise_category VARCHAR(50);

-- Create index
CREATE INDEX IF NOT EXISTS idx_products_excise_category ON products(excise_category) WHERE excise_category IS NOT NULL;

-- Add check constraint for bottle type
ALTER TABLE products
ADD CONSTRAINT check_bottle_type
CHECK (bottle_type IS NULL OR bottle_type IN ('tetra', 'pet', 'glass', 'can'));

-- Add check constraint for excise category
ALTER TABLE products
ADD CONSTRAINT check_excise_category
CHECK (excise_category IS NULL OR excise_category IN ('country_liquor', 'imfl', 'beer', 'wine', 'low_alcohol'));

COMMENT ON COLUMN products.security_code_required IS 'True if product requires security code validation (mandatory for excise)';
COMMENT ON COLUMN products.bottle_type IS 'Type of bottle: tetra (mandatory for country liquor), pet, glass, can';
COMMENT ON COLUMN products.excise_category IS 'Excise category: country_liquor, imfl, beer, wine, low_alcohol';

-- ============================================================
-- 7. EXTEND SHOPS TABLE (for License linkage)
-- ============================================================

ALTER TABLE shops
ADD COLUMN IF NOT EXISTS excise_license_id UUID,
ADD COLUMN IF NOT EXISTS shop_type VARCHAR(20),
ADD COLUMN IF NOT EXISTS area_sqft INTEGER,
ADD COLUMN IF NOT EXISTS excise_district VARCHAR(100),
ADD COLUMN IF NOT EXISTS can_sell_country_liquor BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS can_sell_imfl BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS can_sell_beer BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS can_sell_wine BOOLEAN DEFAULT false;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_shops_license ON shops(excise_license_id) WHERE excise_license_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shops_type ON shops(shop_type) WHERE shop_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shops_district ON shops(excise_district) WHERE excise_district IS NOT NULL;

-- Add check constraint for shop type
ALTER TABLE shops
ADD CONSTRAINT check_shop_type
CHECK (shop_type IS NULL OR shop_type IN ('country_liquor', 'imfl', 'composite', 'model', 'beer_only'));

COMMENT ON COLUMN shops.excise_license_id IS 'Foreign key to excise_licenses table (one license per shop)';
COMMENT ON COLUMN shops.shop_type IS 'Type of shop: country_liquor, imfl, composite, model, beer_only';
COMMENT ON COLUMN shops.area_sqft IS 'Shop area in square feet (minimum 400 for composite shops)';
COMMENT ON COLUMN shops.excise_district IS 'Excise district where shop is registered';
COMMENT ON COLUMN shops.can_sell_country_liquor IS 'True if shop has license to sell country liquor';
COMMENT ON COLUMN shops.can_sell_imfl IS 'True if shop has license to sell IMFL';
COMMENT ON COLUMN shops.can_sell_beer IS 'True if shop has license to sell beer';
COMMENT ON COLUMN shops.can_sell_wine IS 'True if shop has license to sell wine';

-- ============================================================
-- 8. EXTEND STOCK_PURCHASES TABLE (for Security Codes)
-- ============================================================

ALTER TABLE stock_purchases
ADD COLUMN IF NOT EXISTS security_codes_json JSONB,
ADD COLUMN IF NOT EXISTS consideration_fee_paid DECIMAL(12,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS consideration_fee_transaction_id UUID,
ADD COLUMN IF NOT EXISTS cl2_godown_id UUID;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_stock_purchases_godown ON stock_purchases(cl2_godown_id) WHERE cl2_godown_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stock_purchases_consideration ON stock_purchases(consideration_fee_transaction_id) WHERE consideration_fee_transaction_id IS NOT NULL;

COMMENT ON COLUMN stock_purchases.security_codes_json IS 'JSONB array of bottle security codes received in this purchase';
COMMENT ON COLUMN stock_purchases.consideration_fee_paid IS 'Total consideration fee paid for this purchase';
COMMENT ON COLUMN stock_purchases.consideration_fee_transaction_id IS 'Reference to vendor_transaction for consideration fee';
COMMENT ON COLUMN stock_purchases.cl2_godown_id IS 'Reference to CL-2 godown vendor from which stock was lifted';

-- ============================================================
-- DATA MIGRATION (Set defaults for existing records)
-- ============================================================

-- Set default vendor_type for existing vendors
UPDATE vendors
SET vendor_type = 'general',
    is_cl2_godown = false
WHERE vendor_type IS NULL;

-- Set default values for existing products
UPDATE products
SET security_code_required = true,
    excise_category = CASE
        WHEN name ILIKE '%beer%' THEN 'beer'
        WHEN name ILIKE '%wine%' THEN 'wine'
        WHEN name ILIKE '%whisky%' OR name ILIKE '%rum%' OR name ILIKE '%vodka%' THEN 'imfl'
        ELSE 'country_liquor'
    END
WHERE excise_category IS NULL;

-- Set default shop permissions (assuming IMFL shops)
UPDATE shops
SET can_sell_imfl = true,
    can_sell_beer = true
WHERE can_sell_imfl IS NULL;

-- ============================================================
-- GRANTS (Ensure proper permissions)
-- ============================================================

-- Grant permissions to application user (adjust username as needed)
-- GRANT SELECT, INSERT, UPDATE ON vendors TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON vendor_transactions TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON expenses TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON cash_deposits TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON money_collections TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON products TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON shops TO liquorpro_app;
-- GRANT SELECT, INSERT, UPDATE ON stock_purchases TO liquorpro_app;

-- ============================================================
-- VERIFICATION QUERIES
-- ============================================================

-- Verify vendor extensions
-- SELECT COUNT(*) as total_vendors,
--        SUM(CASE WHEN is_cl2_godown THEN 1 ELSE 0 END) as cl2_godowns
-- FROM vendors;

-- Verify product extensions
-- SELECT excise_category, COUNT(*)
-- FROM products
-- WHERE excise_category IS NOT NULL
-- GROUP BY excise_category;

-- Verify shop extensions
-- SELECT shop_type, COUNT(*)
-- FROM shops
-- WHERE shop_type IS NOT NULL
-- GROUP BY shop_type;

-- ============================================================
-- ROLLBACK SCRIPT (uncomment to rollback changes)
-- ============================================================

/*
-- Rollback vendors
ALTER TABLE vendors
DROP COLUMN IF EXISTS vendor_type,
DROP COLUMN IF EXISTS cl2_license_number,
DROP COLUMN IF EXISTS excise_district,
DROP COLUMN IF EXISTS is_cl2_godown,
DROP COLUMN IF EXISTS warehouse_capacity,
DROP COLUMN IF EXISTS godown_address;

-- Rollback vendor_transactions
ALTER TABLE vendor_transactions
DROP COLUMN IF EXISTS is_consideration_fee,
DROP COLUMN IF EXISTS security_codes,
DROP COLUMN IF EXISTS stock_lift_id,
DROP COLUMN IF EXISTS excise_payment_proof,
DROP COLUMN IF EXISTS bottles_count,
DROP COLUMN IF EXISTS fee_per_bottle;

-- Rollback expenses
ALTER TABLE expenses
DROP COLUMN IF EXISTS excise_license_id,
DROP COLUMN IF EXISTS is_license_fee,
DROP COLUMN IF EXISTS license_fee_month,
DROP COLUMN IF EXISTS license_fee_year;

-- Rollback cash_deposits
ALTER TABLE cash_deposits
DROP COLUMN IF EXISTS excise_report_id,
DROP COLUMN IF EXISTS is_daily_sales_deposit,
DROP COLUMN IF EXISTS sales_date;

-- Rollback money_collections
ALTER TABLE money_collections
DROP COLUMN IF EXISTS excise_report_id,
DROP COLUMN IF EXISTS included_in_excise_report;

-- Rollback products
ALTER TABLE products
DROP COLUMN IF EXISTS security_code_required,
DROP COLUMN IF EXISTS bottle_type,
DROP COLUMN IF EXISTS excise_category;

-- Rollback shops
ALTER TABLE shops
DROP COLUMN IF EXISTS excise_license_id,
DROP COLUMN IF EXISTS shop_type,
DROP COLUMN IF EXISTS area_sqft,
DROP COLUMN IF EXISTS excise_district,
DROP COLUMN IF EXISTS can_sell_country_liquor,
DROP COLUMN IF EXISTS can_sell_imfl,
DROP COLUMN IF EXISTS can_sell_beer,
DROP COLUMN IF EXISTS can_sell_wine;

-- Rollback stock_purchases
ALTER TABLE stock_purchases
DROP COLUMN IF EXISTS security_codes_json,
DROP COLUMN IF EXISTS consideration_fee_paid,
DROP COLUMN IF EXISTS consideration_fee_transaction_id,
DROP COLUMN IF EXISTS cl2_godown_id;
*/

-- ============================================================
-- END OF MIGRATION
-- ============================================================

-- Log migration completion
DO $$
BEGIN
    RAISE NOTICE 'Migration 001_extend_finance_for_excise.sql completed successfully';
    RAISE NOTICE 'Extended tables: vendors, vendor_transactions, expenses, cash_deposits, money_collections, products, shops, stock_purchases';
END $$;
