-- Migration 059: Add performance indexes for 100K-user scale
-- These indexes eliminate full table scans on the most common query patterns

-- Sales table: filtered by tenant + shop + date (most common query pattern)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_tenant_shop_date
    ON sales (tenant_id, shop_id, sale_date DESC);

-- Sales table: pending/uncollected sales lookup
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_tenant_status
    ON sales (tenant_id, status) WHERE status IN ('pending', 'approved');

-- Sales table: due amount filtering (uncollected sales)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_tenant_due
    ON sales (tenant_id, status, due_amount) WHERE due_amount > 0;

-- Sale items: FK lookup by sale_id
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sale_items_sale_id
    ON sale_items (sale_id);

-- Sale items: product lookup within tenant
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sale_items_tenant_product
    ON sale_items (tenant_id, product_id);

-- Products: category count queries (N+1 elimination)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_tenant_category
    ON products (tenant_id, category_id);

-- Products: brand count queries (N+1 elimination)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_tenant_brand
    ON products (tenant_id, brand_id);

-- Daily sales records: date range queries (replaces DATE() function usage)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_daily_sales_records_tenant_shop_date
    ON daily_sales_records (tenant_id, shop_id, record_date);

-- Stock purchases: vendor aggregate queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stock_purchases_tenant_vendor
    ON stock_purchases (tenant_id, vendor_id);

-- Vendor transactions: vendor balance calculations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_vendor_transactions_tenant_vendor
    ON vendor_transactions (tenant_id, vendor_id);

-- Stocks: product stock lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stocks_tenant_product_shop
    ON stocks (tenant_id, product_id, shop_id);

-- Sale returns: tenant + status filtering
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sale_returns_tenant_status
    ON sale_returns (tenant_id, status);

-- Sale payments: sale lookup
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sale_payments_sale_id
    ON sale_payments (sale_id);

-- Sales: "my sales" by creator
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_tenant_created_by
    ON sales (tenant_id, created_by_id);

-- Sales: sales by salesman
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_tenant_salesman
    ON sales (tenant_id, salesman_id);
