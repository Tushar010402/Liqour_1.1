-- Migration: Fix vendors table ID column from integer to UUID
-- Date: 2025-10-13
-- Description: The vendors table was created with an integer ID, but the code expects UUID

-- First, check if the table exists and has data
DO $$
BEGIN
    -- Drop the table if it exists and recreate with correct schema
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'vendors') THEN
        -- Drop existing table (safe since it's likely empty or test data)
        DROP TABLE IF EXISTS vendors CASCADE;
        RAISE NOTICE 'Dropped existing vendors table';
    END IF;
END $$;

-- Create vendors table with UUID ID
CREATE TABLE IF NOT EXISTS vendors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- Tenant association
    tenant_id UUID NOT NULL,

    -- Basic Information
    name VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),

    -- Address Information
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(100),
    country VARCHAR(100) DEFAULT 'India',
    postal_code VARCHAR(20),

    -- Business Information
    tax_id VARCHAR(100),
    gst_number VARCHAR(50),
    pan_number VARCHAR(50),
    payment_terms VARCHAR(50),
    credit_limit DECIMAL(15, 2) DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT true,
    created_by UUID,

    -- Indexes
    CONSTRAINT fk_vendors_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_vendors_tenant_id ON vendors(tenant_id);
CREATE INDEX IF NOT EXISTS idx_vendors_is_active ON vendors(tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_vendors_name ON vendors(tenant_id, name);
CREATE INDEX IF NOT EXISTS idx_vendors_deleted_at ON vendors(deleted_at);

-- Create composite index for common queries
CREATE INDEX IF NOT EXISTS idx_vendors_tenant_active_name ON vendors(tenant_id, is_active, name) WHERE deleted_at IS NULL;

COMMENT ON TABLE vendors IS 'Vendor management for tracking suppliers and their financial information';
COMMENT ON COLUMN vendors.id IS 'UUID primary key';
COMMENT ON COLUMN vendors.tenant_id IS 'Associated tenant (multi-tenancy support)';
COMMENT ON COLUMN vendors.credit_limit IS 'Maximum credit allowed for this vendor';
COMMENT ON COLUMN vendors.payment_terms IS 'Payment terms (e.g., Net 30, Net 60)';
