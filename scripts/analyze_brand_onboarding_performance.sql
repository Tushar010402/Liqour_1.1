-- Brand Onboarding Performance Analysis
-- File: scripts/analyze_brand_onboarding_performance.sql
-- Purpose: Analyze database performance for brand onboarding queries

-- ========================================
-- 1. Index Usage Analysis
-- ========================================

-- Check if new indexes are being used
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE tablename = 'products'
  AND indexname LIKE '%saas%'
ORDER BY idx_scan DESC;

-- Expected output should show:
-- idx_products_saas_variant - used for lookups
-- idx_products_tenant_saas_variant_unique - used for duplicate prevention

-- ========================================
-- 2. Query Performance Stats
-- ========================================

-- Most time-consuming queries on products table
SELECT
    substring(query, 1, 100) as query_snippet,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time,
    stddev_exec_time
FROM pg_stat_statements
WHERE query LIKE '%products%'
  AND query LIKE '%saas_variant_id%'
ORDER BY total_exec_time DESC
LIMIT 10;

-- Note: Requires pg_stat_statements extension
-- Enable with: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ========================================
-- 3. Table Bloat Analysis
-- ========================================

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) -
                   pg_relation_size(schemaname||'.'||tablename)) as indexes_size,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows,
    round((n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0)) * 100, 2) as dead_row_percent
FROM pg_stat_user_tables
WHERE tablename = 'products';

-- If dead_row_percent > 10%, consider running VACUUM ANALYZE

-- ========================================
-- 4. Duplicate Check Performance
-- ========================================

-- Test duplicate detection query performance
EXPLAIN ANALYZE
SELECT id
FROM products
WHERE tenant_id = '373e965a-6dec-44d6-a2ab-0400449fc71d'
  AND saas_variant_id = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';

-- Expected: Index Scan using idx_products_tenant_saas_variant_unique
-- Execution time should be < 1ms

-- ========================================
-- 5. Onboarding Query Patterns
-- ========================================

-- Products onboarded per tenant
SELECT
    tenant_id,
    COUNT(*) as onboarded_products,
    COUNT(DISTINCT saas_brand_id) as unique_brands,
    COUNT(DISTINCT category_id) as categories_used,
    MIN(created_at) as first_onboarding,
    MAX(created_at) as last_onboarding
FROM products
WHERE saas_variant_id IS NOT NULL
GROUP BY tenant_id
ORDER BY onboarded_products DESC
LIMIT 20;

-- ========================================
-- 6. Index Efficiency Check
-- ========================================

-- Check for sequential scans (should be minimal for indexed queries)
SELECT
    schemaname,
    tablename,
    seq_scan as sequential_scans,
    seq_tup_read as seq_rows_read,
    idx_scan as index_scans,
    idx_tup_fetch as idx_rows_fetched,
    CASE
        WHEN seq_scan > 0 AND idx_scan > 0 THEN
            round((idx_scan::numeric / (seq_scan + idx_scan)) * 100, 2)
        ELSE 0
    END as index_usage_percent
FROM pg_stat_user_tables
WHERE tablename = 'products';

-- index_usage_percent should be > 95% for optimal performance

-- ========================================
-- 7. Lock Contention Analysis
-- ========================================

-- Check for lock waits on products table
SELECT
    locktype,
    relation::regclass as table_name,
    mode,
    granted,
    COUNT(*) as lock_count
FROM pg_locks
WHERE relation = 'products'::regclass
GROUP BY locktype, relation, mode, granted
ORDER BY lock_count DESC;

-- ========================================
-- 8. Duplicate Prevention Effectiveness
-- ========================================

-- Find any actual duplicates (should be 0)
SELECT
    tenant_id,
    saas_variant_id,
    COUNT(*) as duplicate_count,
    array_agg(id) as product_ids
FROM products
WHERE saas_variant_id IS NOT NULL
GROUP BY tenant_id, saas_variant_id
HAVING COUNT(*) > 1;

-- Expected: 0 rows (duplicate prevention working)

-- ========================================
-- 9. Category Creation Patterns
-- ========================================

-- Categories created through onboarding
SELECT
    c.name as category_name,
    COUNT(DISTINCT p.tenant_id) as tenant_count,
    COUNT(p.id) as product_count,
    MIN(p.created_at) as first_used,
    MAX(p.created_at) as last_used
FROM categories c
JOIN products p ON c.id = p.category_id
WHERE p.saas_variant_id IS NOT NULL
GROUP BY c.id, c.name
ORDER BY product_count DESC
LIMIT 20;

-- ========================================
-- 10. Performance Recommendations
-- ========================================

-- Missing indexes check (should show none for saas_* columns)
SELECT
    schemaname,
    tablename,
    attname as column_name,
    n_distinct,
    correlation
FROM pg_stats
WHERE tablename = 'products'
  AND attname IN ('saas_brand_id', 'saas_variant_id', 'tenant_id')
ORDER BY correlation;

-- High correlation (close to 1 or -1) means index is efficient

-- ========================================
-- 11. Cache Hit Ratio
-- ========================================

SELECT
    'products' as table_name,
    heap_blks_read as disk_reads,
    heap_blks_hit as cache_hits,
    round(
        (heap_blks_hit::numeric / NULLIF(heap_blks_hit + heap_blks_read, 0)) * 100,
        2
    ) as cache_hit_ratio
FROM pg_statio_user_tables
WHERE relname = 'products';

-- cache_hit_ratio should be > 99% for good performance

-- ========================================
-- 12. Vacuum and Analyze Status
-- ========================================

SELECT
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    n_mod_since_analyze as rows_modified_since_analyze
FROM pg_stat_user_tables
WHERE tablename = 'products';

-- If n_mod_since_analyze is high, run: ANALYZE products;

-- ========================================
-- MAINTENANCE RECOMMENDATIONS
-- ========================================

/*
Based on analysis results:

1. If dead_row_percent > 10%:
   VACUUM ANALYZE products;

2. If index_usage_percent < 95%:
   Review query patterns and add missing indexes

3. If cache_hit_ratio < 99%:
   Consider increasing shared_buffers in postgresql.conf

4. If duplicates found:
   CRITICAL: Investigate unique constraint bypass

5. Regular maintenance (weekly):
   ANALYZE products;
   REINDEX INDEX CONCURRENTLY idx_products_tenant_saas_variant_unique;
*/

-- ========================================
-- MONITORING QUERIES (Run periodically)
-- ========================================

-- Daily check: Onboarding volume
SELECT
    DATE(created_at) as date,
    COUNT(*) as products_onboarded,
    COUNT(DISTINCT tenant_id) as active_tenants,
    COUNT(DISTINCT saas_brand_id) as unique_brands
FROM products
WHERE saas_variant_id IS NOT NULL
  AND created_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Hourly check: Recent onboardings
SELECT
    date_trunc('hour', created_at) as hour,
    COUNT(*) as onboardings,
    AVG(cost_price) as avg_cost,
    AVG(selling_price) as avg_selling_price
FROM products
WHERE saas_variant_id IS NOT NULL
  AND created_at >= NOW() - INTERVAL '24 hours'
GROUP BY date_trunc('hour', created_at)
ORDER BY hour DESC;
