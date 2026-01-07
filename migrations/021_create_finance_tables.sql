-- Create Finance Tables: expense_categories and money_collections
-- Date: 2025-11-21

BEGIN;

-- ========================================
-- 1. Create expense_categories table
-- ========================================
CREATE TABLE IF NOT EXISTS expense_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for expense_categories
CREATE INDEX IF NOT EXISTS idx_expense_categories_tenant_id ON expense_categories(tenant_id);
CREATE INDEX IF NOT EXISTS idx_expense_categories_name ON expense_categories(name);
CREATE INDEX IF NOT EXISTS idx_expense_categories_is_active ON expense_categories(is_active);
CREATE UNIQUE INDEX IF NOT EXISTS idx_expense_categories_tenant_name ON expense_categories(tenant_id, name) WHERE deleted_at IS NULL;

-- ========================================
-- 2. Create money_collections table
-- ========================================
CREATE TABLE IF NOT EXISTS money_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    executive_id UUID NOT NULL REFERENCES users(id),
    assistant_manager_id UUID REFERENCES users(id),
    shop_id UUID NOT NULL REFERENCES shops(id),

    -- Collection details
    collection_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(15, 2) NOT NULL,
    collection_type VARCHAR(50) NOT NULL DEFAULT 'daily_sales',
    description TEXT,
    notes TEXT,

    -- 15-minute approval deadline tracking
    collected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deadline_at TIMESTAMP WITH TIME ZONE NOT NULL,
    approval_deadline TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Status and approval
    status VARCHAR(20) DEFAULT 'pending',
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES users(id),
    rejection_reason TEXT,

    -- Audit fields
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for money_collections
CREATE INDEX IF NOT EXISTS idx_money_collections_tenant_id ON money_collections(tenant_id);
CREATE INDEX IF NOT EXISTS idx_money_collections_executive_id ON money_collections(executive_id);
CREATE INDEX IF NOT EXISTS idx_money_collections_shop_id ON money_collections(shop_id);
CREATE INDEX IF NOT EXISTS idx_money_collections_status ON money_collections(status);
CREATE INDEX IF NOT EXISTS idx_money_collections_deadline_at ON money_collections(deadline_at);
CREATE INDEX IF NOT EXISTS idx_money_collections_collected_at ON money_collections(collected_at);
CREATE INDEX IF NOT EXISTS idx_money_collections_created_at ON money_collections(created_at);

-- ========================================
-- 3. Seed default expense categories
-- ========================================
-- Insert default categories for each tenant
INSERT INTO expense_categories (tenant_id, name, description, is_active, created_by)
SELECT
    t.id as tenant_id,
    cat.name,
    cat.description,
    true,
    (SELECT id FROM users WHERE tenant_id = t.id AND role = 'admin' LIMIT 1)
FROM tenants t
CROSS JOIN (VALUES
    ('Utilities', 'Electricity, water, internet, and other utility bills'),
    ('Rent', 'Shop rent and lease payments'),
    ('Salaries', 'Employee wages and salaries'),
    ('Transportation', 'Delivery and transportation expenses'),
    ('Maintenance', 'Repairs and maintenance of equipment'),
    ('Supplies', 'Office and shop supplies'),
    ('Marketing', 'Advertising and promotional expenses'),
    ('Taxes', 'Government taxes and duties'),
    ('Insurance', 'Business insurance premiums'),
    ('Miscellaneous', 'Other general expenses')
) AS cat(name, description)
WHERE EXISTS (SELECT 1 FROM users WHERE tenant_id = t.id AND role = 'admin')
ON CONFLICT DO NOTHING;

COMMIT;

-- ========================================
-- Verification
-- ========================================
SELECT '=== FINANCE TABLES CREATED ===' as info;

SELECT
    'expense_categories' as table_name,
    COUNT(*) as row_count
FROM expense_categories;

SELECT
    'money_collections' as table_name,
    COUNT(*) as row_count
FROM money_collections;

-- Show expense categories by tenant
SELECT 'Expense Categories by Tenant:' as info;
SELECT
    t.name as tenant_name,
    COUNT(ec.id) as category_count
FROM tenants t
LEFT JOIN expense_categories ec ON t.id = ec.tenant_id
GROUP BY t.id, t.name
ORDER BY t.name;
