-- Create missing money_collections table for LiquorPro Finance system

CREATE TABLE IF NOT EXISTS money_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id),
    executive_id UUID NOT NULL,
    assistant_manager_id UUID NOT NULL,
    shop_id UUID NOT NULL REFERENCES shops(id),
    
    collection_date TIMESTAMP NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    collection_type VARCHAR(50) NOT NULL, -- daily_sales, credit_recovery, other
    description TEXT,
    notes TEXT,
    
    -- 15-minute approval deadline fields
    collected_at TIMESTAMP NOT NULL,
    submitted_at TIMESTAMP NOT NULL,
    deadline_at TIMESTAMP NOT NULL, -- submitted_at + 15 minutes
    approval_deadline TIMESTAMP NOT NULL, -- submitted_at + 15 minutes
    
    -- Approval tracking
    approved_at TIMESTAMP,
    approved_by UUID,
    rejected_at TIMESTAMP,
    rejected_by UUID,
    rejection_reason TEXT,
    
    -- Status tracking
    status VARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected, expired
    
    -- Standard fields
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_money_collection_deadline ON money_collections(approval_deadline);
CREATE INDEX IF NOT EXISTS idx_money_collection_status ON money_collections(status);
CREATE INDEX IF NOT EXISTS idx_money_collection_tenant ON money_collections(tenant_id);
CREATE INDEX IF NOT EXISTS idx_money_collection_shop ON money_collections(shop_id);
CREATE INDEX IF NOT EXISTS idx_money_collection_executive ON money_collections(executive_id);
CREATE INDEX IF NOT EXISTS idx_money_collection_assistant_manager ON money_collections(assistant_manager_id);

-- Success message
SELECT 'Money collections table created successfully!' as status;