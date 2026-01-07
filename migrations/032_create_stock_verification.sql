-- Migration 032: Create Stock Verification tables
-- Purpose: Track physical stock counts and discrepancies with full audit trail

-- Stock Verification table (header)
CREATE TABLE IF NOT EXISTS stock_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    money_collection_id UUID REFERENCES money_collections(id),
    shop_id UUID NOT NULL REFERENCES shops(id),

    -- Verification details
    verification_date DATE NOT NULL,
    total_stock_value DECIMAL(15,2) NOT NULL DEFAULT 0,
    discrepancy_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,

    -- Status and approval
    status VARCHAR(20) DEFAULT 'pending', -- pending, in_progress, completed, approved, rejected
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by_id UUID REFERENCES users(id),
    rejection_reason TEXT,

    -- Audit
    created_by_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Stock Verification Items table (line items)
CREATE TABLE IF NOT EXISTS stock_verification_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    stock_verification_id UUID NOT NULL REFERENCES stock_verifications(id),
    product_id UUID NOT NULL REFERENCES products(id),

    -- Quantity comparison
    system_quantity INT NOT NULL DEFAULT 0,
    physical_quantity INT NOT NULL DEFAULT 0,
    discrepancy_quantity INT NOT NULL DEFAULT 0,

    -- Value comparison
    unit_value DECIMAL(15,2) NOT NULL DEFAULT 0,
    discrepancy_value DECIMAL(15,2) NOT NULL DEFAULT 0,

    -- Explanation
    reason TEXT,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Audit trail for stock changes
CREATE TABLE IF NOT EXISTS stock_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    stock_verification_id UUID REFERENCES stock_verifications(id),
    product_id UUID NOT NULL REFERENCES products(id),
    shop_id UUID NOT NULL REFERENCES shops(id),

    -- Change details
    action VARCHAR(50) NOT NULL, -- adjustment, verification, write_off, transfer
    previous_quantity INT NOT NULL,
    new_quantity INT NOT NULL,
    quantity_change INT NOT NULL,
    reason TEXT NOT NULL,

    -- Financial impact
    unit_value DECIMAL(15,2),
    total_value_change DECIMAL(15,2),

    -- Audit
    performed_by_id UUID NOT NULL REFERENCES users(id),
    performed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    approved_by_id UUID REFERENCES users(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    ip_address VARCHAR(45),
    user_agent TEXT
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_stock_verifications_tenant ON stock_verifications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_verifications_shop ON stock_verifications(shop_id);
CREATE INDEX IF NOT EXISTS idx_stock_verifications_date ON stock_verifications(verification_date);
CREATE INDEX IF NOT EXISTS idx_stock_verifications_status ON stock_verifications(status);

CREATE INDEX IF NOT EXISTS idx_stock_verification_items_tenant ON stock_verification_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_verification_items_verification ON stock_verification_items(stock_verification_id);
CREATE INDEX IF NOT EXISTS idx_stock_verification_items_product ON stock_verification_items(product_id);

CREATE INDEX IF NOT EXISTS idx_stock_audit_logs_tenant ON stock_audit_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_audit_logs_shop ON stock_audit_logs(shop_id);
CREATE INDEX IF NOT EXISTS idx_stock_audit_logs_product ON stock_audit_logs(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_audit_logs_date ON stock_audit_logs(performed_at);
CREATE INDEX IF NOT EXISTS idx_stock_audit_logs_verification ON stock_audit_logs(stock_verification_id);

-- Comments
COMMENT ON TABLE stock_verifications IS 'Stock count verification records with approval workflow';
COMMENT ON TABLE stock_verification_items IS 'Individual product items in a stock verification';
COMMENT ON TABLE stock_audit_logs IS 'Complete audit trail of all stock changes';
